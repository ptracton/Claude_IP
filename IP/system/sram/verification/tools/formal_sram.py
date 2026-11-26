#!/usr/bin/env python3
"""formal_sram.py — Formal verification runner (Synopsys VC Formal) for the sram IP.

Every job is proven on the SystemVerilog and on the VHDL-2008 RTL with the
same SVA checkers, bound into the design (verification/formal/vcf/). Jobs
(all TECH_GENERIC, small sizes; see verification/formal/vcf/README.md):

  core_base       sram_core  W16 D16, byte enables, power gating, RL1
  core_be0_err    sram_core  BYTE_EN 0, partial write = error, no power gating, RL2
  core_be0_full   sram_core  BYTE_EN 0, partial write = full word
  core_ecc        sram_core  ECC only (byte enables -> read-modify-write), RL1
  core_opts       sram_core  ECC, BANK_PG x2, BIST, RL2
  dp_sync         sram_core  dual port, one clock, A16/B8, ECC, BANK_PG x2
  dp_sync_wide_b  sram_core  dual port, one clock, A16/B32, ECC (16-bit codewords: RMW)
  dp_async        sram_core  dual port, separate clocks (clk_b random), BANK_PG x2
  top_apb / top_ahb / top_axi4l / top_wb
                  sram_<proto> W32 D8, bus checker on the bus port
  ecc             sram_fv_ecc_top: SECDED encode / flip / decode, K = 8..64

Results:
    ${CLAUDE_SRAM_PATH}/verification/formal/vcf/results.log
Run directories (vcf.log, report_fv.txt, results.log, traces/):
    ${CLAUDE_SRAM_PATH}/verification/work/vcf/<job>_<lang>/

VC Formal runs on csun.edu only (no SymbiYosys flow: the checkers bind into
VHDL designs and read internal signals, which needs VC Formal).

Usage:
    python3 formal_sram.py                         # every job, both languages
    python3 formal_sram.py --job core_base --lang sv
    python3 formal_sram.py --job top_ahb --trace   # FSDB per failure
    python3 formal_sram.py --jobs 2                # parallel jobs (max 3)
    python3 formal_sram.py --clean
"""

import argparse
import os
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PROTOCOLS = ["apb", "ahb", "axi4l", "wb"]

# Compile order (dependencies first), as in sim_sram.py
SRAM_RTL = [
    "sram_pkg", "sram_ecc_enc", "sram_ecc_dec",
    "sram_macro_generic", "sram_macro_saed90", "sram_macro_saed32", "sram_macro_saed14",
    "sram_macro_sky130", "sram_macro_xilinx", "sram_macro_altera",
    "sram_macro_dp_generic", "sram_macro_dp_saed90", "sram_macro_dp_saed32",
    "sram_macro_dp_saed14", "sram_macro_dp_sky130", "sram_macro_dp_xilinx",
    "sram_macro_dp_altera",
    "sram_macro", "sram_macro_dp", "sram_array", "sram_pwr_ctrl", "sram_clr", "sram_bist",
    "sram_port", "sram_cdc", "sram_core",
]
COMMON_RTL = ["claude_sync", "claude_pulse_sync"]

VCF_DIR = "verification/formal/vcf"
WAIVERS = f"{VCF_DIR}/sram_fv_waivers.txt"
CHECKERS = ["sram_core_fv.sv", "sram_array_fv.sv", "sram_pwr_fv.sv", "sram_leaf_fv.sv",
            "sram_port_fv.sv"]

# TECH_GENERIC power timing (sram_pkg::pwr_enter_cycles / pwr_wake_cycles)
GENERIC_TIMING = {"ENTER_CYC": 2, "WAKE_LS": 2, "WAKE_DS": 4, "WAKE_SD": 8}

# Defaults of every core parameter the jobs may change
BASE = {
    "ADDR_W": 8, "WIDTH": 16, "DEPTH": 16, "BYTE_EN": 1, "PARTIAL_WR_ERR": 1,
    "READ_LATENCY": 1, "PWR_GATE": 1, "ECC_EN": 0, "BANK_PG": 0, "NUM_BANKS": 1,
    "BIST_EN": 0, "DUAL_PORT": 0, "WIDTH_B": None, "BYTE_EN_B": None,
    "PARTIAL_WR_ERR_B": None, "READ_LATENCY_B": None, "COMMON_CLK": 1,
}

# job name -> (top-level, parameter overrides)
JOBS = {
    "core_base":      ("sram_core", {}),
    "core_be0_err":   ("sram_core", {"DEPTH": 8, "BYTE_EN": 0, "PARTIAL_WR_ERR": 1,
                                     "PWR_GATE": 0, "READ_LATENCY": 2}),
    "core_be0_full":  ("sram_core", {"DEPTH": 8, "BYTE_EN": 0, "PARTIAL_WR_ERR": 0}),
    "core_ecc":       ("sram_core", {"DEPTH": 8, "ECC_EN": 1}),
    "core_opts":      ("sram_core", {"DEPTH": 8, "ECC_EN": 1, "BANK_PG": 1, "NUM_BANKS": 2,
                                     "BIST_EN": 1, "READ_LATENCY": 2}),
    "dp_sync":        ("sram_core", {"DEPTH": 8, "DUAL_PORT": 1, "WIDTH_B": 8, "ECC_EN": 1,
                                     "BANK_PG": 1, "NUM_BANKS": 2, "READ_LATENCY_B": 2}),
    # A16/B32: 16-bit codewords, so byte writes on either port need a
    # read-modify-write (dp_sync's 8-bit codewords never do).
    "dp_sync_wide_b": ("sram_core", {"WIDTH": 16, "DEPTH": 8, "DUAL_PORT": 1, "WIDTH_B": 32,
                                     "ECC_EN": 1}),
    "dp_async":       ("sram_core", {"DEPTH": 8, "DUAL_PORT": 1, "WIDTH_B": 16,
                                     "COMMON_CLK": 0, "BANK_PG": 1, "NUM_BANKS": 2}),
    **{f"top_{p}": (f"sram_{p}", {"WIDTH": 32, "DEPTH": 8}) for p in PROTOCOLS},
    "ecc":            ("sram_fv_ecc_top", {}),
}

DEFAULT_MAX_TIME = "30M"


def job_params(name):
    """Full parameter set of a job (port-B parameters default to port A's)."""
    p = dict(BASE)
    p.update(JOBS[name][1])
    for b, a in (("WIDTH_B", "WIDTH"), ("BYTE_EN_B", "BYTE_EN"),
                 ("PARTIAL_WR_ERR_B", "PARTIAL_WR_ERR"), ("READ_LATENCY_B", "READ_LATENCY")):
        if p[b] is None:
            p[b] = p[a]
    return p


def max_wait(p):
    """Response bound (cycles) for a configuration.

    A request may wait for an engine that is already running (the checkers'
    environment rule stops new engine requests while it waits): BIST is about
    11 cycles per word, plus waking every domain (shutdown: wake + clear),
    the clear engine one cycle per word, a power-mode exit and the latency.
    """
    d = p["DEPTH"]
    return 16 * d + 40 if p["BIST_EN"] else 4 * d + 40


def ecc_check_bits(k):
    """sram_pkg::ecc_check_bits: Hamming bits plus the overall parity bit."""
    r = 0
    while (1 << r) < k + r + 1:
        r += 1
    return r + 1


def leaf_geometry(p):
    """Geometry of one single-port generic leaf (sram_macro_generic), for the
    sram_leaf_fv bind: stored width, lanes and words per bank (sram_pkg)."""
    width, ecc = p["WIDTH"], p["ECC_EN"]
    cw = min(width, p["WIDTH_B"]) if p["DUAL_PORT"] else width
    if ecc:
        lanes, mw = width // cw, (width // cw) * (cw + ecc_check_bits(cw))
    else:
        lanes, mw = (width // 8 if p["BYTE_EN"] else 1), width
    leaf_ecc = 1 if ecc and not p["DUAL_PORT"] else 0
    # a_word_ok (sram_leaf_fv): one leaf, one power domain, no BIST.
    leaf_clr = 1 if leaf_ecc and p["NUM_BANKS"] == 1 and not p["BIST_EN"] else 0
    return {"LEAF_W": mw, "LEAF_NLANES": lanes, "LEAF_D": p["DEPTH"] // p["NUM_BANKS"],
            "LEAF_ECC": leaf_ecc, "LEAF_CLR": leaf_clr}


def write_cfg(path, name, p):
    """Write the sram_fv_cfg.svh `defines the bound checkers read."""
    top = JOBS[name][0]
    is_top = top != "sram_core"
    async_b = p["DUAL_PORT"] and not p["COMMON_CLK"]
    npd = p["NUM_BANKS"] if p["BANK_PG"] else 1
    vals = {
        "ADDR_W": p["ADDR_W"], "WIDTH": p["WIDTH"], "DEPTH": p["DEPTH"],
        "BYTE_EN": p["BYTE_EN"], "PARTIAL_WR_ERR": p["PARTIAL_WR_ERR"],
        "PWR_GATE": p["PWR_GATE"], "ECC_EN": p["ECC_EN"], "NPD": npd,
        "NUM_BANKS": p["NUM_BANKS"], "BIST_EN": p["BIST_EN"], "DUAL_PORT": p["DUAL_PORT"],
        "WIDTH_B": p["WIDTH_B"], "BYTE_EN_B": p["BYTE_EN_B"],
        "PARTIAL_WR_ERR_B": p["PARTIAL_WR_ERR_B"], "COMMON_CLK": p["COMMON_CLK"],
        "MAX_WAIT": max_wait(p), "BUS_WAIT": max_wait(p) + 8,
        "CHECK_BOUNDS": 0 if async_b else 1, "ENV_IS_RTL": 1 if is_top else 0,
        **GENERIC_TIMING,
        **leaf_geometry(p),
    }
    lines = [f"// sram_fv_cfg.svh — GENERATED by verification/tools/formal_sram.py for job",
             f"// {name}. Do not edit.", "", "`ifndef SRAM_FV_CFG_SVH", "`define SRAM_FV_CFG_SVH"]
    lines += [f"`define SRAM_FV_{k} {v}" for k, v in vals.items()]
    if not p["DUAL_PORT"]:             # sram_macro_generic exists (see the binds)
        lines.append("`define SRAM_FV_LEAF_BIND")
    if vals["LEAF_CLR"]:               # the leaf bind reads sram_clr's state
        lines.append("`define SRAM_FV_LEAF_CLR_BIND")
    lines += ["`endif", ""]
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "sram_fv_cfg.svh"), "w") as fh:
        fh.write("\n".join(lines))


def elab_opts(name, lang, p, cfg_dir):
    """VCS elaborate options that set the job's configuration on its top-level.

    VHDL uses a generics file with /<TOP>/<NAME> paths: "-gv NAME=V" would set
    the generic in every VHDL instance that has one of that name (e.g. port B's
    sram_port WIDTH), see .agents/Claude_IP.md "VHDL DUTs"."""
    top = JOBS[name][0]
    if top == "sram_fv_ecc_top":
        return ""
    keys = ["ADDR_W", "WIDTH", "DEPTH", "BYTE_EN", "PARTIAL_WR_ERR", "READ_LATENCY",
            "PWR_GATE", "ECC_EN", "BANK_PG", "NUM_BANKS", "BIST_EN"]
    if top == "sram_core":
        # Every port-B parameter is set explicitly (VCS can take a dependent
        # generic's default from the other generic's default, see
        # .agents/Claude_IP.md "VHDL DUTs").
        keys += ["DUAL_PORT", "WIDTH_B", "BYTE_EN_B", "PARTIAL_WR_ERR_B", "READ_LATENCY_B",
                 "COMMON_CLK"]
    if lang == "vhdl":
        os.makedirs(cfg_dir, exist_ok=True)
        gfile = os.path.join(cfg_dir, "generics.txt")
        with open(gfile, "w") as fh:
            fh.writelines(f"assign {p[k]} /{top.upper()}/{k}\n" for k in keys)
        return f"-gfile {gfile}"
    return " ".join(f"-pvalue+{top}.{k}={p[k]}" for k in keys)


def import_claude_vcf(ip_path):
    """Import claude_vcf from ${IP_COMMON_PATH}/verification/tools."""
    common = os.environ.get("IP_COMMON_PATH",
                            os.path.join(ip_path, "..", "..", "common"))
    sys.path.insert(0, os.path.normpath(os.path.join(common, "verification", "tools")))
    import claude_vcf  # noqa: E402  (path set up above)
    return claude_vcf


def build_job(cv, ip_path, name, lang, max_time):
    """One claude_vcf.VcfJob for (job, language)."""
    def ip(rel):
        return os.path.join(ip_path, rel)

    common = os.environ.get("IP_COMMON_PATH",
                            os.path.normpath(os.path.join(ip_path, "..", "..", "common")))
    top, _ = JOBS[name]
    p = job_params(name)
    ext, rdir = ("vhd", "vhdl") if lang == "vhdl" else ("sv", "verilog")
    rtl = [os.path.join(common, "design", "rtl", rdir, f"{m}.{ext}") for m in COMMON_RTL]
    rtl += [ip(f"design/rtl/{rdir}/{m}.{ext}") for m in SRAM_RTL]
    vcf = ip(VCF_DIR)
    cfg_dir = ip(f"verification/work/vcf/cfg/{name}_{lang}")

    if top == "sram_fv_ecc_top":
        sva = [os.path.join(vcf, "sram_fv_ecc_top.sv")]
        bind = "sram_fv_ecc_bind"
        proto = "apb"
        clock, reset, sense = "clk", "rst_n", "low"
        extra_clocks, extra_resets = [], []
    else:
        sva = [os.path.join(common, "verification", "formal", "claude_mem_fv.sv")]
        sva += [os.path.join(vcf, c) for c in CHECKERS]
        if top == "sram_core":
            sva.append(os.path.join(vcf, "sram_fv_core_bind.sv"))
            bind = "sram_fv_core_bind"
            proto = "apb"  # only supplies defaults that clock/reset override
            clock, reset, sense = "clk", "rst_n", "low"
            # Port B clock: the same clock (one-clock dual port; unused on a
            # single-port core), or a random clock (separate clocks).
            async_b = p["DUAL_PORT"] and not p["COMMON_CLK"]
            extra_clocks = [("clk_b", 70 if async_b else 100, bool(async_b))]
            extra_resets = [("rst_b_n", "low")]
        else:
            proto = top.replace("sram_", "")
            mem_if = os.path.join(common, "design", "rtl", rdir, f"claude_{proto}_mem_if.{ext}")
            rtl = rtl[:len(COMMON_RTL)] + [mem_if] + rtl[len(COMMON_RTL):]
            rtl.append(ip(f"design/rtl/{rdir}/{top}.{ext}"))
            sva += [cv.common_checker_files(proto)[0],
                    os.path.join(vcf, "sram_bus_fv.sv"),
                    os.path.join(vcf, f"sram_{proto}_fv_bind.sv")]
            bind = f"sram_{proto}_fv_bind"
            clock = reset = sense = None   # the protocol's standard pins
            extra_clocks, extra_resets = [], []
        write_cfg(cfg_dir, name, p)

    return cv.VcfJob(
        name=f"{name}_{lang}", top=top, lang=lang, proto=proto,
        rtl_files=rtl, sva_files=sva, bind_module=bind,
        incdirs=[cfg_dir, vcf], max_time=max_time,
        clock=clock, reset=reset, reset_sense=sense,
        elab_opts=elab_opts(name, lang, p, cfg_dir),
        extra_clocks=extra_clocks, extra_resets=extra_resets,
        # ECC jobs: the sram_leaf_fv lemma (valid stored codewords) is only
        # useful to the end-to-end data checks once it is assumed.
        assume_proven=bool(p.get("ECC_EN")),
    )


def run_vcf_flow(ip_path, args):
    """Run the selected jobs. Returns the exit code."""
    cv = import_claude_vcf(ip_path)
    vcf = cv.find_vcf()
    if not vcf:
        print("ERROR: vcf (Synopsys VC Formal) not found on PATH (csun.edu only).")
        return 1

    names = list(JOBS) if args.job == "all" else [args.job]
    langs = cv.LANGS if args.lang == "all" else [args.lang]
    waivers = cv.load_waivers(os.path.join(ip_path, WAIVERS))
    work = os.path.join(ip_path, "verification", "work", "vcf")
    results_log = os.path.join(ip_path, VCF_DIR, "results.log")
    jobs = [build_job(cv, ip_path, n, lang, args.max_time) for n in names for lang in langs]

    print(f"[vcf] {cv.vcf_version(vcf)}")
    print(f"[vcf] {len(jobs)} job(s), {args.jobs} at a time")

    def run(job):
        print(f"[vcf] Running {job.name} ...", flush=True)
        r = cv.run_job(job, os.path.join(work, job.name), waivers, traces=args.trace, vcf=vcf)
        print(f"[vcf] {cv.summary_line(r)}", flush=True)
        for prop, why in r.failures:
            print(f"        {why:<24} {prop.name}", flush=True)
        with open(os.path.join(work, job.name, "results.log"), "w") as fh:
            fh.write(("PASS" if r.passed else "FAIL") + "\n")
        return r

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(run, jobs))

    overall = "PASS" if results and all(r.passed for r in results) else "FAIL"
    lines = [overall, f"Generated: {datetime.now().isoformat(timespec='seconds')}",
             f"Tool: {cv.vcf_version(vcf)}", ""]
    for r in results:
        lines.append(cv.summary_line(r))
        lines += [f"    FAIL   {why:<24} {prop.name}" for prop, why in r.failures]
        # Depth for waived inconclusive (bounded) results: the bound reached.
        lines += [f"    WAIVED {prop.name}"
                  + (f" depth={prop.depth}" if prop.depth is not None else "")
                  + f"  ({why})" for prop, why in r.waived]
        lines.append(f"    report: {os.path.relpath(r.report_path, ip_path)}")
    os.makedirs(os.path.dirname(results_log), exist_ok=True)
    with open(results_log, "w") as fh:
        fh.write("\n".join(lines) + "\n")

    print()
    print("============================================")
    print("VC Formal Results")
    print("============================================")
    for r in results:
        print(" ", cv.summary_line(r))
    print("============================================")
    print(f"Overall: {overall}")
    print(f"Results written to: {results_log}")
    return 0 if overall == "PASS" else 1


def do_clean(ip_path):
    """Remove VC Formal run directories and the results log."""
    for d in [os.path.join(ip_path, "verification", "work", "vcf")]:
        if os.path.isdir(d):
            shutil.rmtree(d)
            print(f"  removed {d}")
    log = os.path.join(ip_path, VCF_DIR, "results.log")
    if os.path.isfile(log):
        os.remove(log)
        print(f"  removed {log}")
    print("Formal clean complete.")


def main():
    ip_path = os.environ.get("CLAUDE_SRAM_PATH")
    if not ip_path:
        print("ERROR: CLAUDE_SRAM_PATH is not set.")
        print("       Please run:  source IP/system/sram/setup.sh")
        sys.exit(1)

    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--job", choices=list(JOBS) + ["all"], default="all",
                        help="formal job (default: all)")
    parser.add_argument("--lang", choices=["sv", "vhdl", "all"], default="all",
                        help="RTL language (default: all)")
    parser.add_argument("--max-time", default=DEFAULT_MAX_TIME,
                        help=f"time budget per job (default {DEFAULT_MAX_TIME})")
    parser.add_argument("--jobs", type=int, default=2, choices=[1, 2, 3],
                        help="jobs run in parallel (default 2; csun.edu: at most 3)")
    parser.add_argument("--trace", action="store_true",
                        help="write an FSDB counterexample per failing assertion")
    parser.add_argument("--clean", action="store_true", help="remove formal outputs")
    args = parser.parse_args()

    if args.clean:
        do_clean(ip_path)
        return 0
    return run_vcf_flow(ip_path, args)


if __name__ == "__main__":
    sys.exit(main())
