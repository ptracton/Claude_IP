#!/usr/bin/env python3
"""run_regression.py — Full regression harness for the Timer IP.

Runs simulation (Icarus SV + GHDL VHDL + Vivado xsim UVM),
formal verification (SymbiYosys), and collects lint results;
prints a consolidated pass/fail table.

Usage:
    python3 run_regression.py [--skip-sim] [--skip-uvm] [--skip-formal] [--skip-lint]

Results written to:
    ${CLAUDE_TIMER_PATH}/verification/work/regression_results.log
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path


def get_timer_path() -> str:
    path = os.environ.get("CLAUDE_TIMER_PATH")
    if not path:
        print("ERROR: CLAUDE_TIMER_PATH is not set.  Run: source timer/setup.sh")
        sys.exit(1)
    return path


def run_step(label: str, cmd: list, cwd: str = None) -> bool:
    """Run a subprocess step, returning True on success."""
    print(f"\n{'='*60}")
    print(f"  Running: {label}")
    print(f"{'='*60}")
    try:
        result = subprocess.run(cmd, cwd=cwd, timeout=600)
        return result.returncode == 0
    except FileNotFoundError as exc:
        print(f"ERROR: {exc}")
        return False
    except subprocess.TimeoutExpired:
        print(f"ERROR: {label} timed out after 600 s")
        return False


def read_result_log(path: str) -> str:
    """Read first line of a results.log; return 'PASS', 'FAIL', or 'MISSING'."""
    try:
        with open(path) as fh:
            return fh.readline().strip()
    except FileNotFoundError:
        return "MISSING"


KNOWN_TESTS = ["test_reset", "test_rw", "test_back2back", "test_strobe", "test_timer_ops"]


def parse_per_test_results(log_path: str) -> list:
    """Return list of (label, status) per test from a results.log.

    SV logs have per-test lines ``test_name: PASS/FAIL``.
    VHDL logs only have an overall first-line PASS/FAIL — all known tests
    inherit that status so they are counted individually.
    """
    if not os.path.isfile(log_path):
        return []

    with open(log_path) as fh:
        lines = [l.strip() for l in fh]

    per_test = {}
    for line in lines:
        for test in KNOWN_TESTS:
            if line == f"{test}: PASS":
                per_test[test] = "PASS"
            elif line == f"{test}: FAIL":
                per_test[test] = "FAIL"

    # Fall back to overall status if no per-test lines found (e.g. VHDL/GHDL)
    if not per_test and lines:
        overall = lines[0] if lines[0] in ("PASS", "FAIL") else "MISSING"
        per_test = {t: overall for t in KNOWN_TESTS}

    return list(per_test.items())


def collect_results(timer_path: str) -> list:
    """Walk work/ and collect (label, status) pairs, counting individual tests."""
    work = Path(timer_path) / "verification" / "work"
    entries = []

    # Simulation results: work/<sim>/<proto>_<lang>/results.log
    # Skip xsim/uvm — collected separately as a single UVM entry below.
    for sim_dir in sorted(work.iterdir()):
        if sim_dir.name in ("formal", "regression_results.log"):
            continue
        if not sim_dir.is_dir():
            continue
        for run_dir in sorted(sim_dir.iterdir()):
            if not run_dir.is_dir():
                continue
            if sim_dir.name == "xsim" and run_dir.name == "uvm":
                continue
            rlog = str(run_dir / "results.log")
            for test, status in parse_per_test_results(rlog):
                label = f"sim/{sim_dir.name}/{run_dir.name}/{test}"
                entries.append((label, status))

    # Formal results: work/formal/<proto>/results.log  (one per protocol)
    formal_work = work / "formal"
    if formal_work.exists():
        for proto_dir in sorted(formal_work.iterdir()):
            if not proto_dir.is_dir():
                continue
            rlog = proto_dir / "results.log"
            status = read_result_log(str(rlog))
            entries.append((f"formal/{proto_dir.name}", status))

    # UVM results: work/xsim/uvm/results.log — single entry per test run
    uvm_work = work / "xsim" / "uvm"
    if uvm_work.exists():
        rlog = uvm_work / "results.log"
        status = read_result_log(str(rlog))
        entries.append(("uvm/xsim/timer_base_test", status))

    return entries


def main():
    timer_path = get_timer_path()
    tools_dir = os.path.join(timer_path, "verification", "tools")

    parser = argparse.ArgumentParser(description="Timer IP regression harness.")
    parser.add_argument("--skip-sim",    action="store_true")
    parser.add_argument("--skip-uvm",    action="store_true",
                        help="Skip Vivado xsim UVM simulation")
    parser.add_argument("--skip-formal", action="store_true")
    parser.add_argument("--skip-lint",   action="store_true")
    args = parser.parse_args()

    # ------------------------------------------------------------------ #
    # 1. Simulation
    # ------------------------------------------------------------------ #
    if not args.skip_sim:
        run_step(
            "Icarus SV simulation (all protocols)",
            [sys.executable,
             os.path.join(tools_dir, "sim_timer.py"),
             "--sim", "icarus", "--proto", "all", "--lang", "sv"],
        )
        run_step(
            "GHDL VHDL simulation (all protocols)",
            [sys.executable,
             os.path.join(tools_dir, "sim_timer.py"),
             "--sim", "ghdl", "--proto", "all", "--lang", "vhdl"],
        )

    # ------------------------------------------------------------------ #
    # 1b. UVM simulation (Vivado xsim)
    # ------------------------------------------------------------------ #
    if not args.skip_uvm:
        run_step(
            "UVM simulation — timer_base_test (Vivado xsim)",
            [sys.executable,
             os.path.join(tools_dir, "uvm_timer.py"),
             "--test", "timer_base_test"],
        )

    # ------------------------------------------------------------------ #
    # 2. Formal verification
    # ------------------------------------------------------------------ #
    if not args.skip_formal:
        run_step(
            "SymbiYosys formal verification (all protocols)",
            [sys.executable,
             os.path.join(tools_dir, "run_formal.py"),
             "--proto", "all"],
        )

    # ------------------------------------------------------------------ #
    # 3. Collect all results
    # ------------------------------------------------------------------ #
    results = collect_results(timer_path)

    # Lint
    if not args.skip_lint:
        lint_log = os.path.join(timer_path, "verification", "lint", "lint_results.log")
        lint_status = read_result_log(lint_log)
        results.append(("lint", lint_status))

    # ------------------------------------------------------------------ #
    # 4. Summarise
    # ------------------------------------------------------------------ #
    total = len(results)
    n_pass = sum(1 for _, s in results if s == "PASS")
    n_fail = total - n_pass

    sep = "=" * 60
    lines = []
    lines.append(sep)
    lines.append("Timer IP Regression Results")
    lines.append(sep)
    for label, status in results:
        lines.append(f"  {label:<40} {status}")
    lines.append("-" * 60)
    lines.append(f"  Total: {total}  Pass: {n_pass}  Fail: {n_fail}")
    lines.append(sep)
    lines.append("REGRESSION PASSED" if n_fail == 0 else "REGRESSION FAILED")

    report = "\n".join(lines)
    print("\n" + report)

    # Write report file
    out_path = os.path.join(timer_path, "verification", "work", "regression_results.log")
    with open(out_path, "w") as fh:
        fh.write(report + "\n")
    print(f"\nReport written to: {out_path}")

    sys.exit(0 if n_fail == 0 else 1)


if __name__ == "__main__":
    main()
