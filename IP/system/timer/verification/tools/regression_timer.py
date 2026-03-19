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
        overall = lines[0] if lines[0] in ("PASS", "FAIL") else "NO_RUN"
        test_results = {test: overall for test in KNOWN_TESTS}

    return test_results


def collect_sim_per_test_rows(timer_path: str) -> list:
    """Return a list of dicts with keys: test, protocol, sv_result, vhdl_result.

    Each row combines the SV (Icarus) and VHDL (GHDL) result for the same
    test + protocol pair so both languages appear on one line.
    """
    work_base = os.path.join(timer_path, "verification", "work")
    rows = []
    for proto in SUPPORTED_PROTOS:
        sv_log   = os.path.join(work_base, "icarus", f"{proto}_sv",   "results.log")
        vhdl_log = os.path.join(work_base, "ghdl",   f"{proto}_vhdl", "results.log")
        sv_tests   = parse_per_test_results(sv_log)
        vhdl_tests = parse_per_test_results(vhdl_log)
        for test in KNOWN_TESTS:
            rows.append({
                "test":        test,
                "protocol":    proto,
                "sv_result":   sv_tests.get(test,   "NO_RUN"),
                "vhdl_result": vhdl_tests.get(test, "NO_RUN"),
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

    sv_pass   = sum(1 for r in per_test_rows if r["sv_result"]   == "PASS")
    sv_fail   = sum(1 for r in per_test_rows if r["sv_result"]   == "FAIL")
    vhdl_pass = sum(1 for r in per_test_rows if r["vhdl_result"] == "PASS")
    vhdl_fail = sum(1 for r in per_test_rows if r["vhdl_result"] == "FAIL")
    total_pass = sv_pass + vhdl_pass
    total_fail = sv_fail + vhdl_fail
    total_run  = total_pass + total_fail

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
                 f" (SV: {sv_pass}/{sv_pass + sv_fail},"
                 f" VHDL: {vhdl_pass}/{vhdl_pass + vhdl_fail})\n\n")

        # Per-test simulation table — SV and VHDL side by side
        fh.write("## Per-Test Results\n\n")
        fh.write("| Test                     | Protocol | SV (Icarus) | VHDL (GHDL) |\n")
        fh.write("|--------------------------|----------|-------------|-------------|\n")
        for row in per_test_rows:
            fh.write(
                f"| {row['test']:<24} | {row['protocol']:<8} "
                f"| {row['sv_result']:<11} | {row['vhdl_result']:<11} |\n"
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
          f" (SV: {sv_pass}/{sv_pass + sv_fail},"
          f" VHDL: {vhdl_pass}/{vhdl_pass + vhdl_fail})")
    print(f"[regression_timer] Overall result: {overall}")

    sys.exit(0 if overall_pass else 1)


if __name__ == "__main__":
    main()
