#!/usr/bin/env python3
"""uvm_sram.py — UVM runner of the sram IP (Step 6): VCS and Xcelium, csun.edu.

One DUT per build (verification/tasks/uvm/tb_sram_uvm.sv), chosen by
protocol x language x technology x configuration; every test and seed runs
from that one build.

  configurations  base  32 x 1024, defaults
                  full  32 x 1024, ECC + BANK_PG (2 banks) + BIST, READ_LATENCY 2
                  dp    dual port A 32 / B 8, separate clocks (SAED14: one clock)
  tests           smoke random power clear stress (every configuration),
                  ecc bist (full), dp (dp); "all" = those that apply

Usage:
  source IP/system/sram/setup.sh
  python3 $CLAUDE_SRAM_PATH/verification/tools/uvm_sram.py \\
      [--sim vcs|xcelium|all] [--proto ahb|apb|axi4l|wb|all] [--lang sv|vhdl|all] \\
      [--tech generic|saed90|saed32|saed14|sky130|all] [--cfg base|full|dp|all] \\
      [--test <name>|all] [--seed N] [--seeds K] [--scale S] [--coverage] [--waves] \\
      [--jobs N] [--verbosity UVM_LOW]

Results:
  verification/work/uvm/<sim>/<proto>_<lang>_<tech>_<cfg>/   build, <test>_s<seed>.log
  verification/work/uvm/results.log      first line PASS / FAIL, then one row per test run
  verification/work/uvm/coverage/        (--coverage, VCS) code + functional coverage:
                                         per_build.txt, functional.txt, per-config merges

A run passes when its log has "TEST PASSED" (sram_base_test counts UVM
errors and fatals, which include the scoreboard's and sram_model's checks).
"""

import argparse
import concurrent.futures
import datetime
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sim_sram as ss  # noqa: E402  (file lists, PDK models, coverage helpers)

SIMS = ["vcs", "xcelium"]
CFGS = ["base", "full", "dp"]
TESTS = ["smoke", "random", "power", "clear", "ecc", "bist", "dp", "stress"]
ONLY_IN = {"ecc": {"full"}, "bist": {"full"}, "dp": {"dp"}}
TB_TOP = "tb_sram_uvm"


def applies(test: str, cfg: str) -> bool:
    return cfg in ONLY_IN.get(test, set(CFGS))


def safe_jobs(requested: int) -> int:
    """Cap parallel builds: about 3 heavy EDA jobs on csun (8 CPUs, 15 GB), and
    no more than MemAvailable / 2 GB."""
    jobs = max(1, min(requested, 3))
    try:
        with open("/proc/meminfo") as fh:
            for line in fh:
                if line.startswith("MemAvailable:"):
                    gb = int(line.split()[1]) / (1024 * 1024)
                    jobs = max(1, min(jobs, int(gb // 2)))
    except OSError:
        pass
    if jobs != requested:
        print(f"  --jobs {requested} -> {jobs} (host limit / free memory)")
    return jobs


# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------
def uvm_dir(sram_path: str) -> str:
    return os.path.join(sram_path, "verification", "tasks", "uvm")


def uvm_incdirs(sram_path: str) -> list:
    u = uvm_dir(sram_path)
    return [u] + [os.path.join(u, d) for d in ("agents/bus", "agents/sb", "env", "sequences",
                                               "tests")]


def bench_files(sram_path: str) -> list:
    """SV bench: reference model, interfaces, UVM package, top."""
    u = uvm_dir(sram_path)
    return [os.path.join(sram_path, "design", "behavioral", "sram_model.sv"),
            os.path.join(u, "sram_bus_if.sv"), os.path.join(u, "sram_sb_if.sv"),
            os.path.join(u, "sram_uvm_pkg.sv"), os.path.join(u, "tb_sram_uvm.sv")]


def rtl_sv(proto: str, sram_path: str, rtl_dir: str = "") -> list:
    """SV RTL; rtl_dir replaces design/rtl/verilog (uvm_mutants.py)."""
    common = ss.get_common_path(sram_path)
    crtl = os.path.join(common, "design", "rtl", "verilog")
    rtl = rtl_dir or os.path.join(sram_path, "design", "rtl", "verilog")
    return ([os.path.join(crtl, f) for f in
             ("claude_sync.sv", "claude_pulse_sync.sv", f"claude_{proto}_mem_if.sv")]
            + [os.path.join(rtl, f"{m}.sv") for m in ss.SRAM_RTL]
            + [os.path.join(rtl, f"sram_{proto}.sv"), os.path.join(rtl, f"sram_{proto}_dp.sv")])


def rtl_vhdl(proto: str, sram_path: str) -> list:
    common = ss.get_common_path(sram_path)
    crtl = os.path.join(common, "design", "rtl", "vhdl")
    rtl = os.path.join(sram_path, "design", "rtl", "vhdl")
    return ([os.path.join(crtl, f) for f in
             ("claude_sync.vhd", "claude_pulse_sync.vhd", f"claude_{proto}_mem_if.vhd")]
            + [os.path.join(rtl, f"{m}.vhd") for m in ss.SRAM_RTL]
            + [os.path.join(rtl, f"sram_{proto}.vhd"),
               os.path.join(rtl, f"sram_{proto}_dp.vhd")])


def defines(proto: str, lang: str, tech: str, cfg: str) -> list:
    d = [f"TECH={ss.TECH_NUM[tech]}", f"SRAM_PROTO_{proto.upper()}", f"SRAM_CFG_{cfg.upper()}"]
    if lang == "vhdl":
        d.append("VHDL_DUT")
    return d


def cov_hier(proto: str, work_dir: str, lang: str) -> str:
    """-cm_hier: the sram top and everything below, without the vendor macro
    models (as sim_sram.cov_hier, for the UVM top)."""
    path = os.path.join(work_dir, "cov_hier.cfg")
    tops = [f"sram_{proto}", f"sram_{proto}_dp"]
    if lang == "vhdl":
        tops = [t.upper() for t in tops]
    vendor = ("SRAM1*", "SRAM2*", "SRAM3*", "SRAM6*", "SRAM8*", "SRAMLP*",
              "sky130_sram_*", "sram_1rw1r_*", "sram_2rw_*")
    with open(path, "w") as fh:
        fh.write("".join(f"+moduletree {t}\n" for t in tops))
        fh.write("".join(f"-moduletree {m}\n" for m in vendor))
    return path


# ---------------------------------------------------------------------------
# Build and run
# ---------------------------------------------------------------------------
def build_vcs(b: dict) -> tuple:
    """Compile one build with VCS (-ntb_opts uvm-1.2). Returns (ok, log text)."""
    wd, sp = b["dir"], b["sram"]
    simv = os.path.join(wd, "simv")
    incs = ["+incdir+" + "+".join(uvm_incdirs(sp))]
    defs = [f"+define+{d}" for d in defines(b["proto"], b["lang"], b["tech"], b["cfg"])]
    debug = ["-debug_access+pp+f+r"]
    cov = []
    if b["coverage"]:
        cov = ["-cm", ss.COV_METRICS, "-cm_dir", os.path.join(wd, "cov.vdb"),
               "-cm_hier", cov_hier(b["proto"], wd, b["lang"]), "-cm_noconst",
               "-cm_seqnoconst"]
    uvm = ["-ntb_opts", "uvm-1.2"]
    models = ss.macro_models(b["tech"], sp, wd)
    if b["lang"] == "sv":
        steps = [["vcs", "-full64", "-sverilog", "-timescale=1ns/1ps", "-o", simv] + uvm
                 + debug + incs + defs + models + rtl_sv(b["proto"], sp, b["rtl_dir"])
                 + bench_files(sp)
                 + ["-top", TB_TOP] + cov]
    else:
        with open(os.path.join(wd, "synopsys_sim.setup"), "w") as fh:
            fh.write("WORK > DEFAULT\nDEFAULT : ./work_lib\n")
        os.makedirs(os.path.join(wd, "work_lib"), exist_ok=True)
        steps = ([["vlogan", "-full64", "-sverilog"] + uvm]
                 + ([["vlogan", "-full64", "-timescale=1ns/1ps"] + models] if models else [])
                 + [["vhdlan", "-full64", "-vhdl08"] + rtl_vhdl(b["proto"], sp),
                    ["vlogan", "-full64", "-sverilog", "-timescale=1ns/1ps"] + uvm + incs
                    + defs + bench_files(sp),
                    ["vcs", "-full64", "-timescale=1ns/1ps", "-o", simv] + uvm + debug
                    + [TB_TOP] + cov
                    + (["-lca", "-cm_hier_enable_moduletree_vhdl"] if b["coverage"] else [])])
    log = ""
    for cmd in steps:
        out, rc = ss._run(cmd, wd, 1800)
        log += " ".join(cmd) + "\n\n" + out + "\n"
        if rc != 0:
            return False, log
    return True, log


def build_xcelium(b: dict) -> tuple:
    """Compile and elaborate one build with xrun -elaborate (UVM 1.2)."""
    wd, sp = b["dir"], b["sram"]
    defs = []
    for d in defines(b["proto"], b["lang"], b["tech"], b["cfg"]):
        defs += ["-define", d]
    incs = sum((["-incdir", i] for i in uvm_incdirs(sp)), [])
    if b["lang"] == "sv":
        src = rtl_sv(b["proto"], sp, b["rtl_dir"]) + bench_files(sp)
    else:
        # -namemap_mixgen: VHDL generic maps bind Verilog parameters by name (Step 4)
        src = (["-v200x", "-inc_v200x_pkg", "-namemap_mixgen"] + rtl_vhdl(b["proto"], sp)
               + bench_files(sp))
    cmd = (["xrun", "-64", "-elaborate", "-sv", "-uvm", "-uvmhome", "CDNS-1.2", "-timescale",
            "1ns/1ps", "-access", "+rwc", "-xmlibdirname", os.path.join(wd, "xcelium.d"),
            "-log", os.path.join(wd, "xrun_elab.log")] + defs + incs
           + ss.macro_models(b["tech"], sp, wd) + src + ["-top", TB_TOP])
    out, rc = ss._run(cmd, wd, 1800)
    log = " ".join(cmd) + "\n\n" + out
    if os.path.exists(os.path.join(wd, "xrun_elab.log")):
        log += open(os.path.join(wd, "xrun_elab.log"), errors="replace").read()
    return rc == 0 and "*E," not in out, log


def run_one(b: dict, test: str, seed: int) -> tuple:
    """Run one test / seed of a build. Returns (passed, log path, summary line)."""
    wd = b["dir"]
    name = f"{test}_s{seed}"
    log = os.path.join(wd, f"{name}.log")
    plus = [f"+UVM_TESTNAME=sram_{test}_test", f"+UVM_VERBOSITY={b['verbosity']}",
            f"+SCALE={b['scale']}"]
    if b["waves"]:
        plus.append("+waves")
    if b["sim"] == "vcs":
        cmd = [os.path.join(wd, "simv"), f"+ntb_random_seed={seed}"] + plus
        if b["coverage"]:
            cmd += ["-cm", ss.COV_METRICS, "-cm_dir", os.path.join(wd, "cov.vdb"),
                    "-cm_name", name]
    else:
        cmd = ["xrun", "-64", "-R", "-xmlibdirname", os.path.join(wd, "xcelium.d"),
               "-svseed", str(seed), "-log", log] + plus
    out, rc = ss._run(cmd, wd, 7200)
    if b["sim"] == "vcs" or not os.path.exists(log):
        with open(log, "w") as fh:
            fh.write(" ".join(cmd) + "\n\n" + out)
    text = open(log, errors="replace").read()
    ok = "TEST PASSED" in text and "TEST FAILED" not in text
    summ, fcov = "", ""
    for line in text.splitlines():
        if "[SB]" in line and "beats A=" in line:
            summ = line.split("[SB]", 1)[1].strip()
        if "[COV]" in line and "functional coverage" in line:
            cov = line.split("functional coverage (this test)", 1)[1]
            fcov = "  | functional " + cov.split(":")[0].strip()
    summ += fcov
    if not ok:
        errs = [l for l in text.splitlines() if "UVM_ERROR" in l or "UVM_FATAL" in l
                or "*E," in l or "Error-" in l]
        errs = [l for l in errs if not re.search(r"UVM_(ERROR|FATAL)\s*:\s*\d+", l)]
        summ = (errs[0].strip()[:160] if errs else f"no TEST PASSED (rc {rc})")
    return ok, log, summ


def do_build(b: dict) -> list:
    """Build, then run every scheduled test / seed. Returns result rows."""
    tag = f"[{b['sim']}/{b['proto']}_{b['lang']}/{b['tech']}/{b['cfg']}]"
    os.makedirs(b["dir"], exist_ok=True)
    if b["coverage"] and os.path.isdir(os.path.join(b["dir"], "cov.vdb")):
        shutil.rmtree(os.path.join(b["dir"], "cov.vdb"))
    print(f"  {tag} building ...", flush=True)
    ok, log = (build_vcs if b["sim"] == "vcs" else build_xcelium)(b)
    with open(os.path.join(b["dir"], "compile.log"), "w") as fh:
        fh.write(log)
    if not ok:
        print(f"  {tag} build FAILED (see {b['dir']}/compile.log)", flush=True)
        return [(b, t, s, False, os.path.join(b["dir"], "compile.log"), "build failed")
                for t, s in b["runs"]]
    rows = []
    for t, s in b["runs"]:
        ok, log, summ = run_one(b, t, s)
        print(f"  {tag} {t} seed {s}: {'PASS' if ok else 'FAIL'}  {summ}", flush=True)
        rows.append((b, t, s, ok, log, summ))
    return rows


# ---------------------------------------------------------------------------
# Coverage (VCS)
# ---------------------------------------------------------------------------
def _groups_score(report_dir: str) -> str:
    """Functional (covergroup) score from a urg text report: the instance score
    ("INST SCORE" of groups.txt). The covergroups are per instance and give
    the coverpoints of absent features weight 0 per instance, which only the
    instance score honours (the type score counts every coverpoint)."""
    grp = os.path.join(report_dir, "groups.txt")
    if not os.path.exists(grp):
        return "--"
    lines = open(grp, errors="replace").read().splitlines()
    for i, line in enumerate(lines):
        if line.startswith("Total Groups Coverage Summary"):
            vals = lines[i + 2].split()
            if len(vals) >= 2:
                return vals[1]
    return "--"


def coverage_reports(builds: list, work_base: str) -> None:
    rpt = os.path.join(work_base, "coverage")
    os.makedirs(rpt, exist_ok=True)
    vcs = [b for b in builds if b["sim"] == "vcs" and
           os.path.isdir(os.path.join(b["dir"], "cov.vdb"))]
    if not vcs:
        print("  [coverage] no VCS coverage databases")
        return

    def one(b):
        out = os.path.join(b["dir"], "cov_report")
        ss._run(["urg", "-full64", "-dir", os.path.join(b["dir"], "cov.vdb"), "-format",
                 "text", "-report", out], b["dir"], 1800)
        ml = os.path.join(out, "modlist.txt")
        total, mods = ss._parse_modlist(ml) if os.path.exists(ml) else ("", {})
        return b, total, mods, _groups_score(out)

    with concurrent.futures.ThreadPoolExecutor(3) as ex:
        res = list(ex.map(one, vcs))
    hdr = f"{'build':34}{'SCORE':>7}{'LINE':>7}{'COND':>7}{'TOGGLE':>7}{'FSM':>7}{'BRANCH':>7}"
    with open(os.path.join(rpt, "per_build.txt"), "w") as fh:
        fh.write("sram UVM coverage per build (code: sram top and below; GROUP: functional)\n")
        fh.write(hdr + f"{'GROUP':>8}  weakest module (score)\n")
        for b, total, mods, grp in sorted(res, key=lambda r: r[0]["label"]):
            worst = min(mods.items(), key=lambda kv: float(kv[1][0])) if mods else ("-", ("0",))
            fh.write(f"{b['label']:34}" + "".join(f"{v:>7}" for v in total.split())
                     + f"{grp:>8}  {worst[0]} ({worst[1][0]})\n")
    # Functional coverage merged per configuration (same covergroups, different
    # builds): one urg merge per cfg.
    with open(os.path.join(rpt, "functional.txt"), "w") as fh:
        fh.write("sram UVM functional coverage, merged per configuration (target 100 %)\n")
        for cfg in CFGS:
            vdbs = [os.path.join(b["dir"], "cov.vdb") for b in vcs if b["cfg"] == cfg]
            if not vdbs:
                continue
            out = os.path.join(rpt, cfg)
            r = ss._urg_merge(work_base, vdbs, out, f"_uvm_{cfg}")
            grp = _groups_score(out)
            fh.write(f"{cfg:6} builds {len(vdbs):3}  GROUP {grp:>7}"
                     + (f"  code {r[0]}" if r else "") + "\n")
    print(f"  [coverage] {rpt}/per_build.txt, {rpt}/functional.txt")


# ---------------------------------------------------------------------------
def main() -> int:
    sram_path = ss.get_sram_path()
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sim", choices=SIMS + ["all"], default="vcs")
    ap.add_argument("--proto", choices=ss.SUPPORTED_PROTOS + ["all"], default="apb")
    ap.add_argument("--lang", choices=ss.SUPPORTED_LANGS + ["all"], default="sv")
    ap.add_argument("--tech", choices=ss.SUPPORTED_TECHS + ["all"], default="generic")
    ap.add_argument("--cfg", choices=CFGS + ["all"], default="base")
    ap.add_argument("--test", choices=TESTS + ["all"], default="all")
    ap.add_argument("--seed", type=int, default=1, help="first seed")
    ap.add_argument("--seeds", type=int, default=1, help="seeds per test")
    ap.add_argument("--scale", type=int, default=1, help="multiply the transfer counts")
    ap.add_argument("--coverage", action="store_true", help="VCS code + functional coverage")
    ap.add_argument("--waves", action="store_true")
    ap.add_argument("--jobs", type=int, default=1, help="parallel builds (capped at 3)")
    ap.add_argument("--verbosity", default="UVM_LOW")
    ap.add_argument("--rtl-dir", default="",
                    help="SV RTL directory instead of design/rtl/verilog (--lang sv; mutants)")
    ap.add_argument("--work", default="", help="work directory (default verification/work/uvm)")
    args = ap.parse_args()
    if args.rtl_dir and args.lang != "sv":
        print("ERROR: --rtl-dir replaces the SV RTL only (use --lang sv)")
        return 1

    pick = lambda v, allv: allv if v == "all" else [v]  # noqa: E731
    work_base = os.path.abspath(args.work) if args.work else \
        os.path.join(sram_path, "verification", "work", "uvm")
    builds = []
    for sim in pick(args.sim, SIMS):
        for proto in pick(args.proto, ss.SUPPORTED_PROTOS):
            for lang in pick(args.lang, ss.SUPPORTED_LANGS):
                for tech in pick(args.tech, ss.SUPPORTED_TECHS):
                    for cfg in pick(args.cfg, CFGS):
                        tests = [t for t in pick(args.test, TESTS) if applies(t, cfg)]
                        if not tests:
                            continue
                        label = f"{proto}_{lang}_{tech}_{cfg}"
                        builds.append({
                            "sim": sim, "proto": proto, "lang": lang, "tech": tech, "cfg": cfg,
                            "label": f"{sim}/{label}", "sram": sram_path,
                            "dir": os.path.join(work_base, sim, label),
                            "runs": [(t, args.seed + k) for t in tests
                                     for k in range(args.seeds)],
                            "coverage": args.coverage and sim == "vcs", "waves": args.waves,
                            "scale": args.scale, "verbosity": args.verbosity,
                            "rtl_dir": os.path.abspath(args.rtl_dir) if args.rtl_dir else ""})
    if not builds:
        print("nothing to run (test does not apply to the configuration)")
        return 1
    if args.coverage and args.sim != "vcs":
        print("  note: functional / code coverage is collected on VCS only (no IMC on csun)")
    jobs = safe_jobs(args.jobs)
    print(f"uvm_sram.py: {len(builds)} builds, "
          f"{sum(len(b['runs']) for b in builds)} test runs, --jobs {jobs}")
    rows = []
    with concurrent.futures.ThreadPoolExecutor(jobs) as ex:
        for r in ex.map(do_build, builds):
            rows += r
    if args.coverage:
        coverage_reports(builds, work_base)

    npass = sum(1 for r in rows if r[3])
    status = "PASS" if npass == len(rows) else "FAIL"
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    os.makedirs(work_base, exist_ok=True)
    with open(os.path.join(work_base, "results.log"), "w") as fh:
        fh.write(f"{status}\n")
        fh.write(f"uvm_sram.py {stamp}: {npass}/{len(rows)} test runs passed\n")
        for b, t, s, ok, log, summ in sorted(rows, key=lambda r: (r[0]["label"], r[1], r[2])):
            fh.write(f"{b['label']:34} {t:7} s{s:<4} {'PASS' if ok else 'FAIL'}  {summ}\n")
    print("=" * 78)
    for b, t, s, ok, log, summ in sorted(rows, key=lambda r: (r[0]["label"], r[1], r[2])):
        if not ok:
            print(f"  FAIL {b['label']} {t} s{s}: {summ}\n       {log}")
    print(f"{status}: {npass}/{len(rows)} test runs passed -> {work_base}/results.log")
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
