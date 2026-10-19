#!/usr/bin/env python3
"""sim_sram.py — Directed-simulation runner for the sram IP.

Runs the system testbench (verification/testbench/tb_sram_<proto>.sv: the
SRAMs behind IP/interface/bus_matrix) on one or more technologies. Follows
the timer's sim_timer.py conventions.

Implemented (Step 4):
    proto                lang  simulators
    ahb, apb, axi4l, wb  sv    vcs, xcelium (csun.edu)
Every other protocol / language / simulator combination is reported as FAIL
with "not implemented yet", so a regression never mistakes it for a pass.

Technology (--tech): generic, saed90, saed32, saed14, sky130, or all. PDK runs
compile the vendor SRAM macro models through
IP/common/verification/tools/pdk_sram_models.py. GENERIC also runs the
backdoor tests (IP/common/verification/dpi/claude_backdoor.c).

Results:
    ${CLAUDE_SRAM_PATH}/verification/work/<sim>/<proto>_<lang>_<tech>/{compile,sim,results}.log
    ${CLAUDE_SRAM_PATH}/verification/work/results.log   (one line per run, overall status first)

Usage:
    python3 sim_sram.py                                   # vcs, ahb, sv, generic
    python3 sim_sram.py --sim all --proto all --tech all --jobs 8   # everything, 8 at a time
    python3 sim_sram.py --sim xcelium --tech sky130 --test ecc
    python3 sim_sram.py --waves                           # VCS: vcdplus.vpd, Xcelium: waves.shm
    python3 sim_sram.py --proto all --tech all --coverage --jobs 8   # VCS coverage, merged
Tests (--test): all, reset, params, access, burst, pipeline, contention, ecc,
power, clear, bist, dp, resetbusy.

Gate-level (--postsyn) and power (--power) simulation arrive with synthesis
(Step 10); the options are accepted and reported as not implemented.
"""

import argparse
import concurrent.futures
import datetime
import os
import socket
import subprocess
import sys


# ---------------------------------------------------------------------------
# Host detection (same as sim_timer.py)
# ---------------------------------------------------------------------------
def _hostname_fqdn() -> str:
    """Host FQDN: `hostname -f` first (reverse DNS is unreliable on csun.edu)."""
    try:
        out = subprocess.run(["hostname", "-f"], capture_output=True, text=True, timeout=5)
        fqdn = out.stdout.strip()
        if fqdn:
            return fqdn
    except (OSError, subprocess.TimeoutExpired):
        pass
    return socket.getfqdn()


ON_CSUN = _hostname_fqdn().endswith(".csun.edu")
_CSUN_BLOCKED = {"icarus", "ghdl", "modelsim", "xsim"}


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
def get_sram_path() -> str:
    """sram IP root: CLAUDE_SRAM_PATH, else derived from this file's location."""
    path = os.environ.get("CLAUDE_SRAM_PATH")
    if path:
        return path
    detected = os.path.normpath(
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    print(f"INFO: CLAUDE_SRAM_PATH not set — using auto-detected path: {detected}")
    print("      Run 'source setup.sh' to suppress this message.")
    return detected


def get_common_path(sram_path: str) -> str:
    return os.environ.get("IP_COMMON_PATH") or os.path.normpath(
        os.path.join(sram_path, "..", "..", "common"))


SUPPORTED_PROTOS = ["ahb", "apb", "axi4l", "wb"]
SUPPORTED_LANGS = ["sv", "vhdl"]
SUPPORTED_TECHS = ["generic", "saed90", "saed32", "saed14", "sky130"]
SUPPORTED_TESTS = ["all", "reset", "params", "access", "burst", "pipeline", "contention",
                   "ecc", "power", "clear", "bist", "dp", "resetbusy"]

# sram_pkg::TECH_* values
TECH_NUM = {"generic": 0, "saed90": 3, "saed32": 4, "saed14": 5, "sky130": 6}

# (proto, lang) pairs that have a testbench, and the simulators that run them
IMPLEMENTED = {(p, "sv"): {"vcs", "xcelium"} for p in ("ahb", "apb", "axi4l", "wb")}

# Compile order of the sram RTL (dependencies first)
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


def sv_files(proto: str, sram_path: str) -> list:
    """Ordered SV sources of the <proto> system testbench (RTL, model, bench)."""
    common = get_common_path(sram_path)
    crtl = os.path.join(common, "design", "rtl", "verilog")
    rtl = os.path.join(sram_path, "design", "rtl", "verilog")
    bm = os.path.normpath(os.path.join(sram_path, "..", "..", "interface", "bus_matrix",
                                       "design", "rtl", "verilog"))
    tb = os.path.join(sram_path, "verification", "testbench")
    files = [os.path.join(crtl, f) for f in
             ("claude_sync.sv", "claude_pulse_sync.sv", f"claude_{proto}_mem_if.sv")]
    files += [os.path.join(rtl, f"{m}.sv") for m in SRAM_RTL]
    files += [os.path.join(rtl, f"sram_{proto}.sv"), os.path.join(rtl, f"sram_{proto}_dp.sv")]
    files += [os.path.join(bm, f"{m}.sv") for m in
              ("bus_matrix_pkg", "bus_matrix_decoder", "bus_matrix_arb", "bus_matrix_core",
               f"bus_matrix_{proto}_tgt", f"bus_matrix_{proto}_ini", f"bus_matrix_{proto}")]
    files += [os.path.join(sram_path, "design", "behavioral", "sram_model.sv"),
              os.path.join(tb, "sram_tb_pkg.sv"),
              os.path.join(tb, f"sram_tb_{proto}_master.sv"),
              os.path.join(tb, f"tb_sram_{proto}.sv")]
    return files


def dpi_files(sram_path: str) -> list:
    return [os.path.join(get_common_path(sram_path), "verification", "dpi", "claude_backdoor.c")]


def tech_defines(tech: str) -> list:
    """Defines as NAME[=VALUE] strings."""
    d = [f"TECH={TECH_NUM[tech]}"]
    if tech == "generic":
        d.append("TECH_GENERIC")
    return d


def macro_models(tech: str, sram_path: str, work_dir: str) -> list:
    """Vendor SRAM macro models for a PDK (none for GENERIC)."""
    if tech == "generic":
        return []
    sys.path.insert(0, os.path.join(get_common_path(sram_path), "verification", "tools"))
    import pdk_sram_models  # noqa: E402
    return pdk_sram_models.model_files(tech, work_dir)


# ---------------------------------------------------------------------------
# Result helpers
# ---------------------------------------------------------------------------
def _write_result(path: str, status: str, detail: str) -> None:
    with open(path, "w") as fh:
        fh.write(f"{status}\n")
        fh.write(detail)
    print(f"  -> {path} : {status}")


def _run(cmd: list, cwd: str, timeout: int) -> tuple:
    """Run a command; returns (output, returncode). Tool missing / timeout -> rc 127 / 124."""
    try:
        p = subprocess.run(cmd, cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, universal_newlines=True, timeout=timeout)
        return p.stdout, p.returncode
    except FileNotFoundError:
        return f"ERROR: {cmd[0]} not found in PATH\n", 127
    except subprocess.TimeoutExpired:
        return f"ERROR: {cmd[0]} timed out after {timeout} s\n", 124


def _passed(sim_log: str, tb_top: str) -> bool:
    """PASS marker printed and no FAIL / reference-model ERROR before it."""
    pos = sim_log.find(f"PASS {tb_top}")
    if pos < 0:
        return False
    head = sim_log[:pos]
    return "FAIL" not in head and "ERROR [sram_model]" not in head


def _summary_line(sim_log: str, tb_top: str) -> str:
    for line in sim_log.splitlines():
        if line.startswith(f"PASS {tb_top}") or line.startswith(f"FAIL {tb_top}"):
            return line.strip()
    return ""


# ---------------------------------------------------------------------------
# Runners
# ---------------------------------------------------------------------------
COV_METRICS = "line+cond+fsm+tgl+branch"


def cov_hier(proto: str, work_dir: str) -> str:
    """-cm_hier file: the sram top-levels and everything below them, except the
    vendor SRAM macro models (not our code)."""
    path = os.path.join(work_dir, "cov_hier.cfg")
    with open(path, "w") as fh:
        fh.write(f"+moduletree sram_{proto}\n+moduletree sram_{proto}_dp\n")
        for m in ("SRAM*", "sky130_sram_*", "sram_1rw1r_*", "sram_2rw_*"):
            fh.write(f"-moduletree {m}\n")
    return path


def run_vcs(proto: str, lang: str, tech: str, test: str, waves: bool,
            sram_path: str, work_dir: str, coverage: bool = False) -> tuple:
    """Compile and simulate with VCS. Returns (passed, summary)."""
    os.makedirs(work_dir, exist_ok=True)
    results = os.path.join(work_dir, "results.log")
    tb_top = f"tb_sram_{proto}"
    tests = os.path.join(sram_path, "verification", "tests")
    tbdir = os.path.join(sram_path, "verification", "testbench")
    simv = os.path.join(work_dir, "simv")
    cmd = (["vcs", "-full64", "-sverilog", "-timescale=1ns/1ps",
            # r+w: VPI backdoor (claude_backdoor.c); f: force; pp: waveforms
            "-debug_access+pp+f+r+w", f"+incdir+{tests}+{tbdir}", "-o", simv]
           + [f"+define+{d}" for d in tech_defines(tech)]
           + macro_models(tech, sram_path, work_dir)
           + sv_files(proto, sram_path) + dpi_files(sram_path)
           + ["-top", tb_top])
    cov = []
    if coverage:
        cov = ["-cm", COV_METRICS, "-cm_dir", os.path.join(work_dir, "cov.vdb")]
        # -cm_noconst / -cm_seqnoconst: leave out logic that is constant by
        # construction (tie-offs and parameter-disabled features, also through
        # flops), e.g. the ECC pins of an instance with ECC_EN = 0.
        cmd += cov + ["-cm_hier", cov_hier(proto, work_dir), "-cm_noconst", "-cm_seqnoconst"]
    tag = f"[vcs/{proto}_{lang}/{tech}]"
    print(f"  {tag} Compiling ...")
    out, rc = _run(cmd, work_dir, 900)
    with open(os.path.join(work_dir, "compile.log"), "w") as fh:
        fh.write(" ".join(cmd) + "\n\n" + out)
    if rc != 0:
        print(f"  {tag} Compile FAILED (see {work_dir}/compile.log)")
        _write_result(results, "FAIL", out)
        return False, "compile failed"
    print(f"  {tag} Simulating (+test={test}) ...")
    plus = [f"+test={test}"] + (["+waves"] if waves else [])
    sim_out, rc = _run([simv] + plus + cov, work_dir, 3600)
    with open(os.path.join(work_dir, "sim.log"), "w") as fh:
        fh.write(sim_out)
    ok = _passed(sim_out, tb_top)
    summ = _summary_line(sim_out, tb_top) or f"no PASS line (rc {rc})"
    print(f"  {tag} {summ}")
    _write_result(results, "PASS" if ok else "FAIL", sim_out)
    return ok, summ


def run_xcelium(proto: str, lang: str, tech: str, test: str, waves: bool,
                sram_path: str, work_dir: str, coverage: bool = False) -> tuple:
    """Compile, elaborate and simulate with Xcelium (xrun). Returns (passed, summary)."""
    os.makedirs(work_dir, exist_ok=True)
    results = os.path.join(work_dir, "results.log")
    tb_top = f"tb_sram_{proto}"
    tests = os.path.join(sram_path, "verification", "tests")
    tbdir = os.path.join(sram_path, "verification", "testbench")
    log = os.path.join(work_dir, "sim.log")
    defs = []
    for d in tech_defines(tech):
        defs += ["-define", d]
    cmd = (["xrun", "-64", "-sv", "-timescale", "1ns/1ps",
            # +rw: VPI backdoor (claude_backdoor.c) and force
            "-access", "+rwc", "-incdir", tests, "-incdir", tbdir, "-work", "work", "-log", log]
           + defs + macro_models(tech, sram_path, work_dir)
           + sv_files(proto, sram_path) + dpi_files(sram_path)
           + ["-top", tb_top, f"+test={test}"])
    if waves:
        # Probe everything into waves.shm
        tcl = os.path.join(work_dir, "waves.tcl")
        with open(tcl, "w") as fh:
            fh.write("database -open waves -shm -default\nprobe -create -all -depth all\nrun\nexit\n")
        cmd += ["-input", tcl]
    tag = f"[xcelium/{proto}_{lang}/{tech}]"
    print(f"  {tag} Running xrun (+test={test}) ...")
    out, rc = _run(cmd, work_dir, 3600)
    with open(os.path.join(work_dir, "compile.log"), "w") as fh:
        fh.write(" ".join(cmd) + "\n\n" + out)
    sim_out = open(log).read() if os.path.exists(log) else out
    ok = _passed(sim_out, tb_top) and "*E," not in sim_out
    summ = _summary_line(sim_out, tb_top) or f"no PASS line (rc {rc}, see {log})"
    print(f"  {tag} {summ}")
    _write_result(results, "PASS" if ok else "FAIL", sim_out)
    return ok, summ


def _parse_modlist(path: str) -> tuple:
    """(total line, {module: (score, line, cond, tgl, fsm, branch)}) from urg modlist.txt;
    the first row of a module is its merged (all parameter sets) result."""
    import re
    num = r"([0-9.]+|--)"
    row = re.compile(r"^\s*" + r"\s+".join([num] * 6) + r"\s+([a-z_0-9]+)\s*$")
    mods, total = {}, ""
    with open(path) as fh:
        lines = fh.read().splitlines()
    for i, line in enumerate(lines):
        if line.startswith("Total Module Definition Coverage Summary"):
            total = lines[i + 2].strip()
        m = row.match(line)
        if m and m.group(7) not in mods and not m.group(7).startswith("tb_"):
            mods[m.group(7)] = m.groups()[:6]
    return total, mods


def per_run_coverage(work_base: str, run_dirs: list, rpt: str) -> None:
    """One urg report per run (one bus x technology): coverage/per_run.txt lists
    each run's total and its weakest module, and per_run_modules.txt every
    module of every run."""
    def one(d):
        d = os.path.abspath(d)
        out = os.path.join(d, "cov_report")
        _run(["urg", "-full64", "-dir", os.path.join(d, "cov.vdb"), "-format", "text",
              "-report", out], d, 1800)
        return d, _parse_modlist(os.path.join(out, "modlist.txt")) \
            if os.path.exists(os.path.join(out, "modlist.txt")) else ("", {})
    with concurrent.futures.ThreadPoolExecutor(8) as ex:
        res = sorted(ex.map(one, run_dirs))
    hdr = f"{'run':28}{'SCORE':>7}{'LINE':>7}{'COND':>7}{'TOGGLE':>7}{'FSM':>7}{'BRANCH':>7}"
    with open(os.path.join(rpt, "per_run.txt"), "w") as fh, \
         open(os.path.join(rpt, "per_run_modules.txt"), "w") as fm:
        fh.write("sram code coverage per run (bus x technology), and the weakest module\n")
        fh.write(hdr + "  weakest module (score)\n")
        for d, (total, mods) in res:
            label = "/".join(d.split(os.sep)[-2:])
            worst = min(mods.items(), key=lambda kv: float(kv[1][0])) if mods else ("-", ("0",))
            fh.write(f"{label:28}" + "".join(f"{v:>7}" for v in total.split())
                     + f"  {worst[0]} ({worst[1][0]})\n")
            fm.write(f"== {label}\n")
            for name, v in sorted(mods.items(), key=lambda kv: float(kv[1][0])):
                fm.write(f"  {name:26}" + "".join(f"{x:>7}" for x in v) + "\n")
    print(f"  [coverage] per-run reports -> {rpt}/per_run.txt")


def merge_coverage(work_base: str, work_dirs: list) -> None:
    """Merge every run's cov.vdb with urg; reports in work/coverage/.

    The runs are different designs (one top per protocol, one macro leaf per
    technology), so a plain urg merge keeps only the first design's
    instances. "-flex_merge modules" (an LCA feature, hence -lca) merges code
    coverage by module definition across the different hierarchies.
    Writes coverage/summary.txt (one line per module definition, all runs
    merged) and coverage/per_run.txt (each bus x technology on its own).
    """
    vdbs = [os.path.join(d, "cov.vdb") for d in work_dirs
            if os.path.isdir(os.path.join(d, "cov.vdb"))]
    if not vdbs:
        print("  [coverage] no VCS coverage databases (coverage is collected with VCS only)")
        return
    rpt = os.path.join(work_base, "coverage")
    cmd = (["urg", "-full64", "-lca", "-flex_merge", "modules", "-format", "both",
            # The .vdb suffix keeps the database inside work/: without it urg
            # writes <work_base>.vdb next to the work directory.
            "-report", rpt, "-dbname", os.path.join(work_base, "coverage_merged.vdb")]
           + sum((["-dir", v] for v in vdbs), []))
    out, rc = _run(cmd, work_base, 1800)
    with open(os.path.join(work_base, "coverage_urg.log"), "w") as fh:
        fh.write(" ".join(cmd) + "\n\n" + out)
    if rc != 0:
        print(f"  [coverage] urg FAILED (rc {rc}), see {work_base}/coverage_urg.log")
        return
    total, mods = _parse_modlist(os.path.join(rpt, "modlist.txt"))
    with open(os.path.join(rpt, "summary.txt"), "w") as fh:
        fh.write(f"sram code coverage, {len(vdbs)} VCS runs merged by module definition\n")
        fh.write(f"{'':26}{'SCORE':>7}{'LINE':>7}{'COND':>7}{'TOGGLE':>7}{'FSM':>7}{'BRANCH':>7}\n")
        fh.write(f"{'TOTAL':26}" + "".join(f"{v:>7}" for v in total.split()) + "\n")
        for name, v in sorted(mods.items(), key=lambda kv: float(kv[1][0])):
            fh.write(f"{name:26}" + "".join(f"{x:>7}" for x in v) + "\n")
    per_run_coverage(work_base, [os.path.dirname(v) for v in vdbs], rpt)
    print(f"  [coverage] merged {len(vdbs)} runs -> {rpt}/summary.txt (HTML: dashboard.html)")
    print(f"  [coverage] total SCORE LINE COND TOGGLE FSM BRANCH: {total}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    sram_path = get_sram_path()
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sim", choices=["icarus", "ghdl", "modelsim", "xsim", "vcs",
                                          "xcelium", "all"], default=None,
                        help="simulator (default: vcs on csun.edu); 'all' = vcs + xcelium "
                             "on csun.edu")
    parser.add_argument("--proto", choices=SUPPORTED_PROTOS + ["all"], default="ahb")
    parser.add_argument("--lang", choices=SUPPORTED_LANGS + ["all"], default="sv")
    parser.add_argument("--tech", choices=SUPPORTED_TECHS + ["all"], default="generic")
    parser.add_argument("--test", choices=SUPPORTED_TESTS, default="all")
    parser.add_argument("--waves", action="store_true", help="dump waveforms")
    parser.add_argument("--coverage", action="store_true",
                        help="VCS code coverage (line, cond, fsm, tgl, branch) of the sram RTL "
                             "(vendor macro models excluded); merged report in "
                             "verification/work/coverage/ (summary.txt, dashboard.html)")
    parser.add_argument("--jobs", type=int, default=1,
                        help="runs in parallel (each run has its own work directory)")
    parser.add_argument("--postsyn", action="store_true", help="gate-level (Step 10)")
    parser.add_argument("--power", action="store_true", help="PrimePower (Step 10/12)")
    parser.add_argument("--pdk", default="all", help="PDK for --postsyn / --power")
    args = parser.parse_args()

    if args.postsyn or args.power:
        print("FAIL: --postsyn / --power are not implemented yet (synthesis is Step 10).")
        return 1

    sim = args.sim or ("vcs" if ON_CSUN else "icarus")
    if ON_CSUN and sim in _CSUN_BLOCKED:
        print(f"ERROR: --sim {sim} is not available on *.csun.edu; use vcs or xcelium.")
        return 1
    sims = (["vcs", "xcelium"] if ON_CSUN else ["icarus", "ghdl", "modelsim", "xsim"]) \
        if sim == "all" else [sim]
    protos = SUPPORTED_PROTOS if args.proto == "all" else [args.proto]
    langs = SUPPORTED_LANGS if args.lang == "all" else [args.lang]
    techs = SUPPORTED_TECHS if args.tech == "all" else [args.tech]

    work_base = os.path.join(sram_path, "verification", "work")
    os.makedirs(work_base, exist_ok=True)
    runs = []      # (label, runner, args) in report order
    summary = {}
    for s in sims:
        for p in protos:
            for lang in langs:
                if s == "icarus" and lang != "sv" or s == "ghdl" and lang != "vhdl":
                    continue
                for t in techs:
                    label = f"{s}/{p}_{lang}/{t}"
                    if s not in IMPLEMENTED.get((p, lang), set()):
                        summary[label] = ("FAIL", "not implemented yet")
                        runs.append((label, None, None))
                        continue
                    work_dir = os.path.join(work_base, s, f"{p}_{lang}_{t}")
                    runner = run_vcs if s == "vcs" else run_xcelium
                    runs.append((label, runner,
                                 (p, lang, t, args.test, args.waves, sram_path, work_dir,
                                  args.coverage and s == "vcs")))
    with concurrent.futures.ThreadPoolExecutor(max(1, args.jobs)) as ex:
        futs = {ex.submit(r, *a): label for label, r, a in runs if r is not None}
        for f in concurrent.futures.as_completed(futs):
            ok, summ = f.result()
            summary[futs[f]] = ("PASS" if ok else "FAIL", summ)
    summary = [(label,) + summary[label] for label, _, _ in runs]

    if args.coverage:
        merge_coverage(work_base, [a[6] for _, r, a in runs if r is run_vcs])

    all_pass = all(st == "PASS" for _, st, _ in summary) and bool(summary)
    green, red, reset = "\033[32m", "\033[31m", "\033[0m"
    print("\n" + "=" * 78)
    print(f"sram simulation results (--test {args.test})")
    print("=" * 78)
    for label, st, summ in summary:
        print(f"  {label:<28} {green if st == 'PASS' else red}{st}{reset}  {summ}")
    print("=" * 78)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    with open(os.path.join(work_base, "results.log"), "w") as fh:
        fh.write(f"{'PASS' if all_pass else 'FAIL'}  sim_sram.py --test {args.test}  {stamp}\n")
        for label, st, summ in summary:
            fh.write(f"{st:<5} {label:<28} {summ}\n")
    print(f"All simulations {green}PASSED{reset}." if all_pass
          else f"One or more simulations {red}FAILED{reset}.")
    return 0 if all_pass else 1


if __name__ == "__main__":
    sys.exit(main())
