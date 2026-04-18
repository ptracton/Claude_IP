#!/usr/bin/env python3
"""run_regression.py — Full regression harness for Claude IP cores.

Runs simulation (various simulators), formal verification (SymbiYosys),
UVM tests, and collects lint results; prints a consolidated pass/fail table.

Usage:
    python3 run_regression.py [--skip-sim] [--skip-uvm] [--skip-formal] [--skip-lint]

Results written to:
    ${CLAUDE_<IP_NAME>_PATH}/verification/work/regression_results.log
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

# Import from common tools
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "common", "verification", "tools"))
from ip_tool_base import require_env, run_command, ON_ECS_VDI


def get_ip_path(ip_name: str) -> str:
    """Return the IP root directory."""
    env_var = f"CLAUDE_{ip_name.upper()}_PATH"
    path = os.environ.get(env_var)
    if not path:
        print(f"ERROR: {env_var} is not set.  Run: source {ip_name}/setup.sh")
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


# This would need to be customized per IP
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
        overall = lines[0] if lines[0] in ("PASS", "FAIL", "SKIP") else "MISSING"
        # Guard: if any line contains "FAIL", downgrade a claimed PASS to FAIL.
        # Catches results.log files written with a weak PASS check.
        if overall == "PASS" and any("FAIL" in l for l in lines[1:]):
            overall = "FAIL"
        per_test = {t: overall for t in KNOWN_TESTS}

    return list(per_test.items())


def collect_results(ip_path: str, ip_name: str) -> list:
    """Walk work/ and collect (label, status) pairs, counting individual tests."""
    work = Path(ip_path) / "verification" / "work"
    entries = []

    # Determine which simulators to collect based on host
    if ON_ECS_VDI:
        expected_sims = {"vcs", "xcelium"}
    else:
        expected_sims = {"icarus", "ghdl", "modelsim", "xsim"}

    # Simulation results: work/<sim>/<proto>_<lang>/results.log
    # Skip xsim/uvm — collected separately as a single UVM entry below.
    for sim_dir in sorted(work.iterdir()):
        if sim_dir.name in ("formal", "regression_results.log"):
            continue
        if not sim_dir.is_dir():
            continue
        if sim_dir.name not in expected_sims:
            continue  # Skip simulators not expected on this host
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

    # UVM results: work/xsim/uvm/results.log — single entry per test run (only on standard hosts)
    if not ON_ECS_VDI:
        uvm_work = work / "xsim" / "uvm"
        if uvm_work.exists():
            rlog = uvm_work / "results.log"
            status = read_result_log(str(rlog))
            entries.append((f"uvm/xsim/{ip_name}_base_test", status))

    return entries


def main():
    # IP name should be passed as argument or detected
    parser = argparse.ArgumentParser(description="Claude IP regression harness.")
    parser.add_argument("ip_name", help="IP name (e.g., timer, bus_matrix)")
    parser.add_argument("--skip-sim",    action="store_true")
    parser.add_argument("--skip-uvm",    action="store_true",
                        help="Skip Vivado xsim UVM simulation")
    parser.add_argument("--skip-formal", action="store_true")
    parser.add_argument("--skip-lint",   action="store_true")
    parser.add_argument("--skip-modelsim", action="store_true",
                        help="Skip ModelSim SV+VHDL simulation")
    parser.add_argument("--skip-xsim",     action="store_true",
                        help="Skip Vivado xsim SV+VHDL directed simulation")
    args = parser.parse_args()

    ip_name = args.ip_name
    ip_path = get_ip_path(ip_name)
    tools_dir = os.path.join(ip_path, "verification", "tools")

    # ------------------------------------------------------------------ #
    # 1. Simulation
    # ------------------------------------------------------------------ #
    if not args.skip_sim:
        if ON_ECS_VDI:
            # On ecs-vdi, only VCS and Xcelium are available
            run_step(
                f"VCS SV simulation (all protocols) - {ip_name}",
                [sys.executable,
                 os.path.join(tools_dir, f"sim_{ip_name}.py"),
                 "--sim", "vcs", "--proto", "all", "--lang", "sv"],
            )
            run_step(
                f"VCS VHDL simulation (all protocols) - {ip_name}",
                [sys.executable,
                 os.path.join(tools_dir, f"sim_{ip_name}.py"),
                 "--sim", "vcs", "--proto", "all", "--lang", "vhdl"],
            )
            run_step(
                f"Xcelium SV simulation (all protocols) - {ip_name}",
                [sys.executable,
                 os.path.join(tools_dir, f"sim_{ip_name}.py"),
                 "--sim", "xcelium", "--proto", "all", "--lang", "sv"],
            )
            run_step(
                f"Xcelium VHDL simulation (all protocols) - {ip_name}",
                [sys.executable,
                 os.path.join(tools_dir, f"sim_{ip_name}.py"),
                 "--sim", "xcelium", "--proto", "all", "--lang", "vhdl"],
            )
        else:
            # On standard hosts
            run_step(
                f"Icarus SV simulation (all protocols) - {ip_name}",
                [sys.executable,
                 os.path.join(tools_dir, f"sim_{ip_name}.py"),
                 "--sim", "icarus", "--proto", "all", "--lang", "sv"],
            )
            run_step(
                f"GHDL VHDL simulation (all protocols) - {ip_name}",
                [sys.executable,
                 os.path.join(tools_dir, f"sim_{ip_name}.py"),
                 "--sim", "ghdl", "--proto", "all", "--lang", "vhdl"],
            )

    # ------------------------------------------------------------------ #
    # 1b. ModelSim directed simulation (SV + VHDL) - only on standard hosts
    # ------------------------------------------------------------------ #
    if not args.skip_modelsim and not ON_ECS_VDI:
        run_step(
            f"ModelSim SV simulation (all protocols) - {ip_name}",
            [sys.executable,
             os.path.join(tools_dir, f"sim_{ip_name}.py"),
             "--sim", "modelsim", "--proto", "all", "--lang", "sv"],
        )
        run_step(
            f"ModelSim VHDL simulation (all protocols) - {ip_name}",
            [sys.executable,
             os.path.join(tools_dir, f"sim_{ip_name}.py"),
             "--sim", "modelsim", "--proto", "all", "--lang", "vhdl"],
        )

    # ------------------------------------------------------------------ #
    # 1c. Vivado xsim directed simulation (SV + VHDL) - only on standard hosts
    # ------------------------------------------------------------------ #
    if not args.skip_xsim and not ON_ECS_VDI:
        run_step(
            f"Vivado xsim SV simulation (all protocols) - {ip_name}",
            [sys.executable,
             os.path.join(tools_dir, f"sim_{ip_name}.py"),
             "--sim", "xsim", "--proto", "all", "--lang", "sv"],
        )
        run_step(
            f"Vivado xsim VHDL simulation (all protocols) - {ip_name}",
            [sys.executable,
             os.path.join(tools_dir, f"sim_{ip_name}.py"),
             "--sim", "xsim", "--proto", "all", "--lang", "vhdl"],
        )

    # ------------------------------------------------------------------ #
    # 1d. UVM simulation (Vivado xsim) - only on standard hosts
    # ------------------------------------------------------------------ #
    if not args.skip_uvm and not ON_ECS_VDI:
        run_step(
            f"UVM simulation — {ip_name}_base_test (Vivado xsim)",
            [sys.executable,
             os.path.join(tools_dir, f"uvm_{ip_name}.py"),
             "--test", f"{ip_name}_base_test"],
        )

    # ------------------------------------------------------------------ #
    # 2. Formal verification
    # ------------------------------------------------------------------ #
    if not args.skip_formal:
        run_step(
            f"SymbiYosys formal verification (all protocols) - {ip_name}",
            [sys.executable,
             os.path.join(tools_dir, "run_formal.py"),
             "--proto", "all"],
        )

    # ------------------------------------------------------------------ #
    # 3. Collect all results
    # ------------------------------------------------------------------ #
    results = collect_results(ip_path, ip_name)

    # Lint
    if not args.skip_lint:
        lint_log = os.path.join(ip_path, "verification", "lint", "lint_results.log")
        lint_status = read_result_log(lint_log)
        results.append(("lint", lint_status))

    # ------------------------------------------------------------------ #
    # 4. Summarise
    # ------------------------------------------------------------------ #
    total = len(results)
    n_pass = sum(1 for _, s in results if s == "PASS")
    n_skip = sum(1 for _, s in results if s in ("SKIP", "MISSING"))
    n_fail = total - n_pass - n_skip

    sep = "=" * 60
    lines = []
    lines.append(sep)
    lines.append(f"{ip_name.upper()} Regression Results")
    lines.append(sep)
    for label, status in results:
        lines.append(f"  {label:<40} {status}")
    lines.append("-" * 60)
    lines.append(f"  Total: {total}  Pass: {n_pass}  Fail: {n_fail}  Skip: {n_skip}")
    lines.append(sep)
    lines.append("REGRESSION PASSED" if n_fail == 0 else "REGRESSION FAILED")

    report = "\n".join(lines)
    print("\n" + report)

    # Write report file
    out_path = os.path.join(ip_path, "verification", "work", "regression_results.log")
    with open(out_path, "w") as fh:
        fh.write(report + "\n")
    print(f"\nReport written to: {out_path}")

    sys.exit(0 if n_fail == 0 else 1)


if __name__ == "__main__":
    main()