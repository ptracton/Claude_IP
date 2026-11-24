#!/usr/bin/env python3
"""regression_sram.py — Regression runner and report for the sram IP (Step 7).

Runs every sub-runner of the IP, then collects their result files into one
report. Ported from the timer's regression_timer.py (report.md layout) and the
bus_matrix run_regression.py (host split, per-test counting, stale-run guard).

    step      csun.edu (VCS / Xcelium / VC Formal / SpyGlass)          standard host
    sim       sim_sram.py  --sim all --proto all --lang all --tech all  sim_sram.py --sim verilator
              --coverage   (80 runs x 12 tests, code coverage)          --proto all --tech generic
    uvm       uvm_sram.py  all x all x all x all x all --coverage       -
              (240 builds, 1440 runs, functional + code coverage)
    mutants   uvm_mutants.py --mutant all (every mutant must be killed) -
    formal    formal_sram.py --job all --lang all                       -
    lint      lint_sram.py --lang all                                   lint_sram.py --lang all
    firmware  fw_sram.py (host unit tests, mutants, cross build)       fw_sram.py

Collected entries (each PASS / FAIL; an expected result that is missing is FAIL):
    sim/<sim>/<proto>_<lang>_<tech>/<test>   one per directed test (12 per run)
    uvm/<sim>/<build>/<test>/s<seed>         one per UVM test run
    mutant/<name>                            KILLED = PASS
    formal/<job>                             one per VC Formal job
    lint                                     first line of lint_results.log
    fw/<step>/<check>                        one per PASS / FAIL row of
                                             verification/firmware/fw_results.log
                                             (SKIP rows, e.g. a missing cross
                                             compiler, are not counted)
    coverage/...                             targets: every module >= 90 in every
                                             directed run and UVM build, UVM
                                             functional coverage 100 per config

Usage:
  source IP/system/sram/setup.sh
  python3 $CLAUDE_SRAM_PATH/verification/tools/regression_sram.py
      [--collect] [--skip-sim] [--skip-uvm] [--skip-mutants] [--skip-formal]
      [--skip-lint] [--skip-firmware] [--jobs N]

  --collect   run nothing; report on the result files already in work/ (each
              source is listed with its timestamp so stale results are visible)
  --skip-X    neither run nor collect step X (reported as SKIP)
  --jobs N    parallel jobs for sim / uvm / formal (default 3, the csun.edu
              limit: 8 CPUs / 15 GB; formal is capped at 3 by formal_sram.py)

A full csun.edu run takes about 4-5 hours (sim ~70 min, UVM ~60 min, formal
and mutants the rest); run it detached (setsid / nohup).

Results:
  verification/regression/report.md          overall result, step and coverage
                                             summary, every entry
  verification/work/regression_results.log   the console table
Exit status 0 only when every collected entry passes.
"""

import argparse
import os
import re
import subprocess
import sys
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "..", "..", "..", "common", "verification", "tools"))
from ip_tool_base import ON_CSUN  # noqa: E402

PROTOS = ["ahb", "apb", "axi4l", "wb"]
LANGS = ["sv", "vhdl"]
TECHS = ["generic", "saed90", "saed32", "saed14", "sky130"]
DIRECTED_TESTS = ["test_reset", "test_params", "test_access", "test_burst", "test_pipeline",
                  "test_contention", "test_ecc", "test_power", "test_clear", "test_bist",
                  "test_dp", "test_reset_busy"]
UVM_BUILDS = 240            # 4 protos x 2 langs x 5 techs x 3 cfgs x 2 sims
UVM_RUNS = 1440
CODE_TARGET = 90.0          # every module, every run / build
FUNC_TARGET = 100.0         # UVM covergroups merged per configuration

STEP_TIMEOUT = 8 * 3600
STEPS = ["sim", "uvm", "mutants", "formal", "lint", "firmware"]


# ---------------------------------------------------------------------------
# Running
# ---------------------------------------------------------------------------

def run_step(label: str, cmd: list) -> int:
    """Run one sub-runner with its output streaming to the console."""
    print(f"\n{'=' * 70}\n  {label}\n  {' '.join(cmd)}\n{'=' * 70}", flush=True)
    try:
        return subprocess.run(cmd, timeout=STEP_TIMEOUT).returncode
    except FileNotFoundError as exc:
        print(f"ERROR: {exc}")
        return 127
    except subprocess.TimeoutExpired:
        print(f"ERROR: {label} timed out after {STEP_TIMEOUT} s")
        return 124


def step_commands(tools: str, jobs: int) -> dict:
    py = sys.executable
    t = lambda name: os.path.join(tools, name)  # noqa: E731
    if ON_CSUN:
        return {
            "sim": [py, t("sim_sram.py"), "--sim", "all", "--proto", "all", "--lang", "all",
                    "--tech", "all", "--coverage", "--jobs", str(jobs)],
            "uvm": [py, t("uvm_sram.py"), "--sim", "all", "--proto", "all", "--lang", "all",
                    "--tech", "all", "--cfg", "all", "--coverage", "--jobs", str(jobs)],
            "mutants": [py, t("uvm_mutants.py"), "--mutant", "all", "--jobs", str(jobs)],
            "formal": [py, t("formal_sram.py"), "--job", "all", "--lang", "all",
                       "--jobs", str(min(jobs, 3))],
            "lint": [py, t("lint_sram.py"), "--lang", "all"],
            "firmware": [py, t("fw_sram.py")],
        }
    return {
        "sim": [py, t("sim_sram.py"), "--sim", "verilator", "--proto", "all", "--lang", "sv",
                "--tech", "generic", "--jobs", str(jobs)],
        "lint": [py, t("lint_sram.py"), "--lang", "all"],
        "firmware": [py, t("fw_sram.py")],
    }


# ---------------------------------------------------------------------------
# Collecting
# ---------------------------------------------------------------------------

def stamp(path: str) -> str:
    if not os.path.exists(path):
        return "missing"
    return datetime.fromtimestamp(os.path.getmtime(path)).strftime("%Y-%m-%d %H:%M")


def first_line(path: str) -> str:
    try:
        with open(path) as fh:
            return fh.readline().strip()
    except OSError:
        return ""


def collect_sim(work: str) -> list:
    """One entry per directed test of every expected run. A run directory that
    is missing, or a test without its 'test_x: PASS' line, is FAIL."""
    sims = ["vcs", "xcelium"] if ON_CSUN else ["verilator"]
    langs = LANGS if ON_CSUN else ["sv"]
    techs = TECHS if ON_CSUN else ["generic"]
    out = []
    for s in sims:
        for p in PROTOS:
            for lang in langs:
                for tech in techs:
                    run = f"{p}_{lang}_{tech}"
                    log = os.path.join(work, s, run, "results.log")
                    status = {}
                    overall = ""
                    if os.path.isfile(log):
                        with open(log, errors="replace") as fh:
                            lines = fh.read().splitlines()
                        overall = lines[0].strip() if lines else ""
                        for ln in lines:
                            m = re.match(r"^(test_\w+): (PASS|FAIL)\b", ln)
                            if m:
                                # a test listed twice keeps a FAIL
                                if status.get(m.group(1)) != "FAIL":
                                    status[m.group(1)] = m.group(2)
                    for test in DIRECTED_TESTS:
                        st = status.get(test, "FAIL")
                        if overall != "PASS":
                            st = "FAIL"
                        note = "" if os.path.isfile(log) else "no results.log"
                        out.append((f"sim/{s}/{run}/{test}", st, note))
    return out


def collect_uvm(work: str) -> list:
    """One entry per row of work/uvm/results.log; fewer rows than the full
    matrix is a FAIL entry of its own."""
    log = os.path.join(work, "uvm", "results.log")
    out = []
    if not os.path.isfile(log):
        return [("uvm/results.log", "FAIL", "missing")]
    with open(log, errors="replace") as fh:
        lines = fh.read().splitlines()
    rows = 0
    for ln in lines[2:]:
        m = re.match(r"^(\S+)\s+(\S+)\s+s(\d+)\s+(PASS|FAIL)\b\s*(.*)$", ln)
        if not m:
            continue
        rows += 1
        note = "" if m.group(4) == "PASS" else m.group(5)[:120]
        out.append((f"uvm/{m.group(1)}/{m.group(2)}/s{m.group(3)}", m.group(4), note))
    if rows < UVM_RUNS:
        out.append(("uvm/matrix", "FAIL", f"{rows} of {UVM_RUNS} runs in results.log "
                    "(partial run: re-run the full matrix)"))
    return out


def collect_mutants(work: str) -> list:
    log = os.path.join(work, "uvm", "mutants", "results.log")
    if not os.path.isfile(log):
        return [("mutant/results.log", "FAIL", "missing")]
    out = []
    with open(log, errors="replace") as fh:
        for ln in fh.read().splitlines()[2:]:
            m = re.match(r"^(\w+)\s+(KILLED|SURVIVED|\S+)\s+(.*)$", ln)
            if m:
                ok = m.group(2) == "KILLED"
                out.append((f"mutant/{m.group(1)}", "PASS" if ok else "FAIL",
                            "" if ok else m.group(3)[:120]))
    if not out:
        out.append(("mutant/results.log", "FAIL", "no mutant rows"))
    return out


def collect_formal(ip: str) -> list:
    log = os.path.join(ip, "verification", "formal", "vcf", "results.log")
    if not os.path.isfile(log):
        return [("formal/results.log", "FAIL", "missing")]
    out = []
    with open(log, errors="replace") as fh:
        for ln in fh.read().splitlines():
            m = re.match(r"^(PASS|FAIL): (\S+)\s+(.*)$", ln)
            if m:
                out.append((f"formal/{m.group(2)}", m.group(1),
                            "" if m.group(1) == "PASS" else m.group(3)[:120]))
    if not out:
        out.append(("formal/results.log", "FAIL", "no job rows"))
    return out


def collect_lint(ip: str) -> list:
    log = os.path.join(ip, "verification", "lint", "lint_results.log")
    line = first_line(log)
    st = "PASS" if line == "PASS" or line.startswith("PASS") else "FAIL"
    return [("lint", st, "" if st == "PASS" else (line[:120] or "missing"))]


def collect_firmware(ip: str) -> list:
    log = os.path.join(ip, "verification", "firmware", "fw_results.log")
    if not os.path.isfile(log):
        return [("fw/fw_results.log", "FAIL", "missing")]
    out = []
    with open(log, errors="replace") as fh:
        for ln in fh.read().splitlines():
            m = re.match(r"^(PASS|FAIL) (\S+)(?:\s+(.*))?$", ln)
            if m:
                out.append((f"fw/{m.group(2)}", m.group(1),
                            "" if m.group(1) == "PASS" else (m.group(3) or "")[:120]))
    if not out:
        out.append(("fw/fw_results.log", "FAIL", "no check rows"))
    return out


def _weakest(line: str):
    m = re.search(r"^(\S+)\s.*\s(\S.*?) \(([\d.]+)\)\s*$", line)
    return (m.group(1), m.group(2), float(m.group(3))) if m else None


def collect_coverage(work: str, do_sim: bool, do_uvm: bool) -> tuple:
    """Coverage targets as entries, plus summary lines for the report."""
    out, summary = [], []
    if do_sim and ON_CSUN:
        path = os.path.join(work, "coverage", "per_run.txt")
        rows = []
        if os.path.isfile(path):
            with open(path) as fh:
                for ln in fh:
                    w = _weakest(ln.rstrip())
                    if w and w[0].startswith(("vcs/", "xcelium/")):
                        rows.append(w)
        exp = len(PROTOS) * len(LANGS) * len(TECHS)
        if len(rows) < exp:
            out.append(("coverage/directed", "FAIL", f"{len(rows)} of {exp} runs in per_run.txt"))
        for run, mod, score in rows:
            ok = score >= CODE_TARGET
            out.append((f"coverage/directed/{run}", "PASS" if ok else "FAIL",
                        "" if ok else f"{mod} {score:.2f} < {CODE_TARGET:.0f}"))
        if rows:
            run, mod, score = min(rows, key=lambda r: r[2])
            summary.append(f"Directed code coverage: weakest module of any run {mod} "
                           f"{score:.2f} ({run}; target {CODE_TARGET:.0f}) — {stamp(path)}")
    if do_uvm and ON_CSUN:
        path = os.path.join(work, "uvm", "coverage", "per_build.txt")
        rows = []
        if os.path.isfile(path):
            with open(path) as fh:
                for ln in fh:
                    w = _weakest(ln.rstrip())
                    if w and w[0].startswith("vcs/"):
                        rows.append(w)
        exp = UVM_BUILDS // 2       # code coverage on VCS only
        if len(rows) < exp:
            out.append(("coverage/uvm", "FAIL", f"{len(rows)} of {exp} builds in per_build.txt"))
        for run, mod, score in rows:
            ok = score >= CODE_TARGET
            out.append((f"coverage/uvm/{run}", "PASS" if ok else "FAIL",
                        "" if ok else f"{mod} {score:.2f} < {CODE_TARGET:.0f}"))
        if rows:
            run, mod, score = min(rows, key=lambda r: r[2])
            summary.append(f"UVM code coverage: weakest module of any build {mod} {score:.2f} "
                           f"({run}; target {CODE_TARGET:.0f}) — {stamp(path)}")
        path = os.path.join(work, "uvm", "coverage", "functional.txt")
        cfgs = {}
        if os.path.isfile(path):
            with open(path) as fh:
                for ln in fh:
                    m = re.match(r"^(base|full|dp)\s+builds\s+\d+\s+GROUP\s+([\d.]+)", ln)
                    if m:
                        cfgs[m.group(1)] = float(m.group(2))
        for cfg in ["base", "full", "dp"]:
            if cfg not in cfgs:
                out.append((f"coverage/functional/{cfg}", "FAIL", "missing"))
                continue
            ok = cfgs[cfg] >= FUNC_TARGET
            out.append((f"coverage/functional/{cfg}", "PASS" if ok else "FAIL",
                        "" if ok else f"{cfgs[cfg]:.2f} < {FUNC_TARGET:.0f}"))
        if cfgs:
            summary.append("UVM functional coverage merged per config: " +
                           ", ".join(f"{c} {v:.2f}" for c, v in cfgs.items()) +
                           f" (target {FUNC_TARGET:.0f}) — {stamp(path)}")
    return out, summary


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    ip = os.environ.get("CLAUDE_SRAM_PATH")
    if not ip:
        print("ERROR: CLAUDE_SRAM_PATH is not set.")
        print("       Please run:  source IP/system/sram/setup.sh")
        return 1

    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--collect", action="store_true",
                    help="run nothing; report on the existing result files")
    for s in STEPS:
        ap.add_argument(f"--skip-{s}", action="store_true", help=f"skip the {s} step")
    ap.add_argument("--jobs", type=int, default=3, help="parallel jobs (default 3)")
    args = ap.parse_args()

    tools = os.path.join(ip, "verification", "tools")
    work = os.path.join(ip, "verification", "work")
    cmds = step_commands(tools, args.jobs)
    # Steps that apply on this host and were not skipped
    active = [s for s in STEPS if s in cmds and not getattr(args, f"skip_{s.replace('-', '_')}")]
    start = datetime.now()

    exit_codes = {}
    if not args.collect:
        labels = {"sim": "Directed simulation", "uvm": "UVM matrix", "mutants": "UVM mutants",
                  "formal": "Formal (VC Formal)", "lint": "Lint", "firmware": "Firmware"}
        for s in active:
            exit_codes[s] = run_step(labels[s], cmds[s])

    collectors = {
        "sim": lambda: collect_sim(work),
        "uvm": lambda: collect_uvm(work),
        "mutants": lambda: collect_mutants(work),
        "formal": lambda: collect_formal(ip),
        "lint": lambda: collect_lint(ip),
        "firmware": lambda: collect_firmware(ip),
    }
    sources = {
        "sim": os.path.join(work, "results.log"),
        "uvm": os.path.join(work, "uvm", "results.log"),
        "mutants": os.path.join(work, "uvm", "mutants", "results.log"),
        "formal": os.path.join(ip, "verification", "formal", "vcf", "results.log"),
        "lint": os.path.join(ip, "verification", "lint", "lint_results.log"),
        "firmware": os.path.join(ip, "verification", "firmware", "fw_results.log"),
    }
    entries = {s: collectors[s]() for s in active}
    # A sub-runner that failed without leaving a failing entry still fails
    for s, rc in exit_codes.items():
        if rc != 0 and all(st == "PASS" for _, st, _ in entries[s]):
            entries[s].append((f"{s}/runner", "FAIL", f"exit status {rc}"))
    cov, cov_summary = collect_coverage(work, "sim" in active, "uvm" in active)
    if cov:
        entries["coverage"] = cov

    allrows = [r for s in entries for r in entries[s]]
    n_pass = sum(1 for _, st, _ in allrows if st == "PASS")
    n_fail = len(allrows) - n_pass
    overall = "PASS" if n_fail == 0 and allrows else "FAIL"
    skipped = [s for s in STEPS if s not in active]
    when = datetime.now().strftime("%Y-%m-%d %H:%M")
    host = "csun.edu" if ON_CSUN else "standard host"

    # ---- console table ----------------------------------------------------
    sep = "=" * 70
    con = [sep, f"sram IP regression — {when} ({host}{', collect only' if args.collect else ''})",
           sep]
    for s in entries:
        rows = entries[s]
        p = sum(1 for _, st, _ in rows if st == "PASS")
        con.append(f"  {s:<10} {p:>5}/{len(rows):<5} {'PASS' if p == len(rows) else 'FAIL'}"
                   + (f"   ({sources[s]}: {stamp(sources[s])})" if s in sources else ""))
    for s in skipped:
        con.append(f"  {s:<10} {'':>11} SKIP" + ("" if s in cmds else "  (not on this host)"))
    fails = [r for r in allrows if r[1] != "PASS"]
    if fails:
        con.append("-" * 70)
        for name, st, note in fails[:60]:
            con.append(f"  {st}  {name}  {note}")
        if len(fails) > 60:
            con.append(f"  ... {len(fails) - 60} more (see report.md)")
    con.append("-" * 70)
    con.append(f"  Total: {len(allrows)}  Pass: {n_pass}  Fail: {n_fail}  "
               f"Skip: {len(skipped)} step(s)")
    con.append(sep)
    con.append("REGRESSION PASSED" if overall == "PASS" else "REGRESSION FAILED")
    text = "\n".join(con)
    print("\n" + text)
    os.makedirs(work, exist_ok=True)
    with open(os.path.join(work, "regression_results.log"), "w") as fh:
        fh.write(text + "\n")

    # ---- report.md --------------------------------------------------------
    rdir = os.path.join(ip, "verification", "regression")
    os.makedirs(rdir, exist_ok=True)
    report = os.path.join(rdir, "report.md")
    with open(report, "w") as fh:
        fh.write(f"{overall}\n\n# sram Regression Report\n\n")
        fh.write(f"**Generated:** {when} on {host}"
                 f"{' (collect only: no step was run)' if args.collect else ''}, "
                 f"{int((datetime.now() - start).total_seconds() // 60)} min\n\n")
        fh.write(f"**Overall Result:** {overall} — {n_pass}/{len(allrows)} entries pass\n\n")
        fh.write("## Steps\n\n| Step | Entries | Pass | Result | Source (timestamp) |\n"
                 "|---|---|---|---|---|\n")
        for s in entries:
            rows = entries[s]
            p = sum(1 for _, st, _ in rows if st == "PASS")
            src = (f"`{os.path.relpath(sources[s], ip)}` ({stamp(sources[s])})"
                   if s in sources else "per_run / per_build / functional")
            fh.write(f"| {s} | {len(rows)} | {p} | {'PASS' if p == len(rows) else 'FAIL'} "
                     f"| {src} |\n")
        for s in skipped:
            why = "skipped" if s in cmds else "not run on this host"
            fh.write(f"| {s} | - | - | SKIP | {why} |\n")
        if cov_summary:
            fh.write("\n## Coverage\n\n" + "".join(f"- {ln}\n" for ln in cov_summary))
        if fails:
            fh.write("\n## Failures\n\n| Entry | Result | Note |\n|---|---|---|\n")
            for name, st, note in fails:
                fh.write(f"| {name} | {st} | {note.replace('|', '/')} |\n")
        fh.write("\n## All Entries\n")
        for s in entries:
            fh.write(f"\n### {s}\n\n| Entry | Result |\n|---|---|\n")
            for name, st, _ in entries[s]:
                fh.write(f"| {name} | {st} |\n")
    print(f"\nReport: {report}")
    return 0 if overall == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
