#!/usr/bin/env python3
"""regression_timer.py — Regression runner and reporter for the timer IP block.

Invokes sim_timer.py, formal_timer.py, and lint_timer.py in sequence.
A consolidated report is written to:
    ${CLAUDE_TIMER_PATH}/verification/regression/report.md
Exits non-zero if any sub-runner fails.
"""

import os
import subprocess
import sys
from datetime import datetime


# ---------------------------------------------------------------------------
# Known tests — update this list when new tests are added
# ---------------------------------------------------------------------------
KNOWN_TESTS = [
    "test_reset",
    "test_rw",
    "test_back2back",
    "test_strobe",
    "test_timer_ops",
]

SUPPORTED_PROTOS = ["apb", "ahb", "axi4l", "wb"]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def run_step(label, cmd):
    """Run a sub-command, return (passed: bool, log: str)."""
    print(f"\n[regression_timer] Running: {label}")
    print(f"  Command: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    passed = result.returncode == 0
    log = result.stdout + result.stderr
    status = "PASS" if passed else "FAIL"
    print(f"  Result: {status}")
    return passed, log


def parse_per_test_results(results_log_path: str) -> dict:
    """Parse a results.log file and return {test_name: 'PASS'|'FAIL'}.

    Handles two formats:
    - Per-test (SV/Icarus): lines of the form ``test_name: PASS`` or
      ``test_name: FAIL`` — each test gets its own status.
    - Overall-only (VHDL/GHDL): first line is ``PASS`` or ``FAIL`` with no
      per-test breakdown — all known tests inherit the overall status.
    """
    if not os.path.isfile(results_log_path):
        return {}

    with open(results_log_path) as fh:
        lines = [l.strip() for l in fh]

    # Try to collect per-test lines first
    test_results = {}
    for line in lines:
        for test in KNOWN_TESTS:
            if line == f"{test}: PASS":
                test_results[test] = "PASS"
            elif line == f"{test}: FAIL":
                test_results[test] = "FAIL"

    # Fall back: no per-test lines found — use overall first-line status
    if not test_results and lines:
        overall = lines[0] if lines[0] in ("PASS", "FAIL", "SKIP") else "NO_RUN"
        # Guard: if any line contains "FAIL", downgrade a claimed PASS to FAIL.
        if overall == "PASS" and any("FAIL" in l for l in lines[1:]):
            overall = "FAIL"
        test_results = {test: overall for test in KNOWN_TESTS}

    return test_results


def collect_sim_per_test_rows(timer_path: str) -> list:
    """Return a list of dicts: {test, protocol, sim, lang, result}.

    Covers all six sim/lang combos:
      icarus/sv, ghdl/vhdl, modelsim/sv, modelsim/vhdl, xsim/sv, xsim/vhdl
    """
    work_base = os.path.join(timer_path, "verification", "work")
    sim_langs = [
        ("icarus",   "sv"),
        ("ghdl",     "vhdl"),
        ("modelsim", "sv"),
        ("modelsim", "vhdl"),
        ("xsim",     "sv"),
        ("xsim",     "vhdl"),
    ]
    rows = []
    for proto in SUPPORTED_PROTOS:
        for sim, lang in sim_langs:
            log = os.path.join(work_base, sim, f"{proto}_{lang}", "results.log")
            test_results = parse_per_test_results(log)
            for test in KNOWN_TESTS:
                rows.append({
                    "test":     test,
                    "protocol": proto,
                    "sim":      sim,
                    "lang":     lang,
                    "result":   test_results.get(test, "NO_RUN"),
                })
    return rows


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    # Guard: require CLAUDE_TIMER_PATH
    timer_path = os.environ.get("CLAUDE_TIMER_PATH")
    if not timer_path:
        print("ERROR: CLAUDE_TIMER_PATH is not set.")
        print("       Please run:  source timer/setup.sh")
        sys.exit(1)

    tools_dir = os.path.join(timer_path, "verification", "tools")
    regression_dir = os.path.join(timer_path, "verification", "regression")
    os.makedirs(regression_dir, exist_ok=True)
    report_path = os.path.join(regression_dir, "report.md")

    timestamp = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
    step_results = {}

    # ------------------------------------------------------------------
    # Run sim (SV via Icarus)
    # ------------------------------------------------------------------
    passed, log = run_step(
        "Simulation (icarus/sv)",
        [sys.executable, os.path.join(tools_dir, "sim_timer.py"),
         "--sim", "icarus", "--proto", "all", "--lang", "sv"],
    )
    step_results["Simulation (icarus/sv)"] = ("PASS" if passed else "FAIL", log)

    # ------------------------------------------------------------------
    # Run sim (VHDL via GHDL)
    # ------------------------------------------------------------------
    passed_vhdl, log_vhdl = run_step(
        "Simulation (ghdl/vhdl)",
        [sys.executable, os.path.join(tools_dir, "sim_timer.py"),
         "--sim", "ghdl", "--proto", "all", "--lang", "vhdl"],
    )
    step_results["Simulation (ghdl/vhdl)"] = ("PASS" if passed_vhdl else "FAIL", log_vhdl)

    # ------------------------------------------------------------------
    # Run sim (ModelSim SV)
    # ------------------------------------------------------------------
    passed_msim_sv, log_msim_sv = run_step(
        "Simulation (modelsim/sv)",
        [sys.executable, os.path.join(tools_dir, "sim_timer.py"),
         "--sim", "modelsim", "--proto", "all", "--lang", "sv"],
    )
    step_results["Simulation (modelsim/sv)"] = (
        "PASS" if passed_msim_sv else "FAIL", log_msim_sv)

    # ------------------------------------------------------------------
    # Run sim (ModelSim VHDL)
    # ------------------------------------------------------------------
    passed_msim_vhdl, log_msim_vhdl = run_step(
        "Simulation (modelsim/vhdl)",
        [sys.executable, os.path.join(tools_dir, "sim_timer.py"),
         "--sim", "modelsim", "--proto", "all", "--lang", "vhdl"],
    )
    step_results["Simulation (modelsim/vhdl)"] = (
        "PASS" if passed_msim_vhdl else "FAIL", log_msim_vhdl)

    # ------------------------------------------------------------------
    # Run sim (Vivado xsim SV)
    # ------------------------------------------------------------------
    passed_xsim_sv, log_xsim_sv = run_step(
        "Simulation (xsim/sv)",
        [sys.executable, os.path.join(tools_dir, "sim_timer.py"),
         "--sim", "xsim", "--proto", "all", "--lang", "sv"],
    )
    step_results["Simulation (xsim/sv)"] = (
        "PASS" if passed_xsim_sv else "FAIL", log_xsim_sv)

    # ------------------------------------------------------------------
    # Run sim (Vivado xsim VHDL)
    # ------------------------------------------------------------------
    passed_xsim_vhdl, log_xsim_vhdl = run_step(
        "Simulation (xsim/vhdl)",
        [sys.executable, os.path.join(tools_dir, "sim_timer.py"),
         "--sim", "xsim", "--proto", "all", "--lang", "vhdl"],
    )
    step_results["Simulation (xsim/vhdl)"] = (
        "PASS" if passed_xsim_vhdl else "FAIL", log_xsim_vhdl)

    # ------------------------------------------------------------------
    # Run formal
    # ------------------------------------------------------------------
    passed_formal, log_formal = run_step(
        "Formal verification",
        [sys.executable, os.path.join(tools_dir, "formal_timer.py")],
    )
    step_results["Formal verification"] = ("PASS" if passed_formal else "FAIL", log_formal)

    # ------------------------------------------------------------------
    # Run lint
    # ------------------------------------------------------------------
    passed_lint, log_lint = run_step(
        "Lint (all languages)",
        [sys.executable, os.path.join(tools_dir, "lint_timer.py"), "--lang", "all"],
    )
    step_results["Lint (all languages)"] = ("PASS" if passed_lint else "FAIL", log_lint)

    # ------------------------------------------------------------------
    # Collect per-test simulation rows from results.log files
    # ------------------------------------------------------------------
    per_test_rows = collect_sim_per_test_rows(timer_path)

    # ------------------------------------------------------------------
    # Determine overall result and test counts
    # ------------------------------------------------------------------
    overall_pass = all(status == "PASS" for status, _ in step_results.values())

    total_pass = sum(1 for r in per_test_rows if r["result"] == "PASS")
    total_fail = sum(1 for r in per_test_rows if r["result"] == "FAIL")
    total_skip = sum(1 for r in per_test_rows if r["result"] in ("SKIP", "NO_RUN"))
    total_run  = total_pass + total_fail + total_skip

    if total_fail > 0:
        overall_pass = False
    overall = "PASS" if overall_pass else "FAIL"

    # ------------------------------------------------------------------
    # Write report
    # ------------------------------------------------------------------
    with open(report_path, "w") as fh:
        fh.write("# Timer Regression Report\n\n")
        fh.write(f"**Generated:** {timestamp}\n\n")
        fh.write(f"**Overall Result:** {overall}\n\n")
        fh.write(f"**Tests:** {total_pass}/{total_run} passed"
                 f" ({total_fail} fail, {total_skip} skip/no-run)\n\n")

        fh.write("## Per-Test Results\n\n")
        fh.write("| Test                     | Protocol | Simulator | Language | Result  |\n")
        fh.write("|--------------------------|----------|-----------|----------|---------|\n")
        for row in per_test_rows:
            fh.write(
                f"| {row['test']:<24} | {row['protocol']:<8} "
                f"| {row['sim']:<9} | {row['lang']:<8} | {row['result']:<7} |\n"
            )

        fh.write("\n## Step Summary\n\n")
        fh.write("| Step | Result |\n")
        fh.write("|------|--------|\n")
        for step, (status, _) in step_results.items():
            fh.write(f"| {step} | {status} |\n")

        fh.write("\n## Detail Logs\n\n")
        for step, (status, log) in step_results.items():
            fh.write(f"### {step} — {status}\n\n")
            fh.write("```\n")
            fh.write(log or "(no output)\n")
            fh.write("```\n\n")

    print(f"\n[regression_timer] Report written to: {report_path}")
    print(f"[regression_timer] Tests: {total_pass}/{total_run} passed"
          f" ({total_fail} fail, {total_skip} skip/no-run)")
    print(f"[regression_timer] Overall result: {overall}")

    sys.exit(0 if overall_pass else 1)


if __name__ == "__main__":
    main()
