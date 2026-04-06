#!/usr/bin/env python3
"""run_regression.py — Full bus_matrix verification regression suite.

Runs directed sims (Icarus, GHDL, xsim, ModelSim), formal, UVM, and lint
in order, collects results, writes verification/work/regression_results.log.

Usage:
    source IP/interface/bus_matrix/setup.sh
    python3 $CLAUDE_BUS_MATRIX_PATH/verification/tools/run_regression.py
    python3 $CLAUDE_BUS_MATRIX_PATH/verification/tools/run_regression.py --skip-modelsim --skip-uvm --skip-formal
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path


def read_result_log(path):
    """Read the first line of a results.log and return PASS/FAIL/SKIP/NO_RUN.

    Applies Guard 1 (downgrade stale PASS if content contains FAIL) and
    Guard 2 (treat SKIP as neutral).
    """
    if not os.path.isfile(path):
        return "NO_RUN"
    with open(path) as fh:
        lines = [l.strip() for l in fh.readlines() if l.strip()]
    if not lines:
        return "NO_RUN"

    valid_statuses = ("PASS", "FAIL", "SKIP")
    overall = lines[0] if lines[0] in valid_statuses else "NO_RUN"

    # Guard 1: downgrade stale PASS to FAIL if body contains FAIL
    if overall == "PASS" and any("FAIL" in l for l in lines[1:]):
        overall = "FAIL"

    return overall


def parse_per_test_results(sim_log_path, proto):
    """Parse sim output log for per-test PASS/FAIL lines.

    Looks for lines matching 'test_name: PASS' or 'test_name: FAIL'.
    Returns list of (test_name, status) tuples.
    """
    if not os.path.isfile(sim_log_path):
        return []

    seen = {}
    with open(sim_log_path) as fh:
        for line in fh:
            m = re.match(r"^(test_\w+):\s+(PASS|FAIL)", line.strip())
            if m:
                name, status = m.group(1), m.group(2)
                # Keep worst status if duplicated (FAIL > PASS)
                if name not in seen or status == "FAIL":
                    seen[name] = status
    return list(seen.items())


def tool_installed(name):
    """Check if a tool is on PATH."""
    try:
        subprocess.run(
            [name, "--version"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        return True
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def run_script(cmd, cwd=None, timeout=300):
    """Run a Python script via subprocess, return (returncode, stdout+stderr)."""
    print(f"  CMD: {' '.join(cmd)}")
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
        )
        return result.returncode, result.stdout
    except subprocess.TimeoutExpired:
        return 1, "TIMEOUT"


def main():
    # Guard: require CLAUDE_BUS_MATRIX_PATH
    ip_path = os.environ.get("CLAUDE_BUS_MATRIX_PATH")
    if not ip_path:
        print("ERROR: CLAUDE_BUS_MATRIX_PATH is not set.")
        print("       Please run:  source IP/interface/bus_matrix/setup.sh")
        sys.exit(1)

    ip_path = str(Path(ip_path).resolve())

    parser = argparse.ArgumentParser(
        description="Run the full bus_matrix verification regression suite"
    )
    parser.add_argument("--skip-sim", action="store_true",
                        help="Skip all directed simulation steps")
    parser.add_argument("--skip-uvm", action="store_true",
                        help="Skip UVM testbench step")
    parser.add_argument("--skip-formal", action="store_true",
                        help="Skip formal verification step")
    parser.add_argument("--skip-lint", action="store_true",
                        help="Skip lint step")
    parser.add_argument("--skip-modelsim", action="store_true",
                        help="Skip ModelSim-specific simulation step")
    parser.add_argument("--skip-xsim", action="store_true",
                        help="Skip Vivado xsim-specific simulation step")
    args = parser.parse_args()

    tools_dir = os.path.join(ip_path, "verification", "tools")
    work_dir = os.path.join(ip_path, "verification", "work")
    os.makedirs(work_dir, exist_ok=True)

    sim_script = os.path.join(tools_dir, "sim_bus_matrix.py")
    lint_script = os.path.join(tools_dir, "lint_bus_matrix.py")
    formal_script = os.path.join(tools_dir, "formal_bus_matrix.py")

    protos = ["ahb", "axi", "wb"]
    entries = []  # List of (label, status)

    # -----------------------------------------------------------------------
    # 1. Icarus SV directed tests
    # -----------------------------------------------------------------------
    if not args.skip_sim:
        print("\n=== Icarus SV Directed Tests ===")
        if tool_installed("iverilog"):
            rc, out = run_script(
                [sys.executable, sim_script, "--sim", "icarus", "--proto", "all", "--lang", "sv"]
            )
            for proto in protos:
                run_dir = os.path.join(work_dir, "icarus", f"{proto}_sv")
                # Try to get per-test results from sim log
                sim_log = os.path.join(run_dir, "sim.log")
                per_test = parse_per_test_results(sim_log, proto)
                if per_test:
                    for test_name, status in per_test:
                        entries.append((f"sim/icarus/{proto}_sv/{test_name}", status))
                else:
                    # Fall back to results.log overall status
                    result_log = os.path.join(run_dir, "results.log")
                    status = read_result_log(result_log)
                    entries.append((f"sim/icarus/{proto}_sv", status))
        else:
            for proto in protos:
                entries.append((f"sim/icarus/{proto}_sv", "SKIP"))

    # -----------------------------------------------------------------------
    # 2. GHDL VHDL directed tests
    # -----------------------------------------------------------------------
    if not args.skip_sim:
        print("\n=== GHDL VHDL Directed Tests ===")
        if tool_installed("ghdl"):
            rc, out = run_script(
                [sys.executable, sim_script, "--sim", "ghdl", "--proto", "all", "--lang", "vhdl"]
            )
            for proto in protos:
                run_dir = os.path.join(work_dir, "ghdl", f"{proto}_vhdl")
                sim_log = os.path.join(run_dir, "ghdl.log")
                per_test = parse_per_test_results(sim_log, proto)
                if per_test:
                    for test_name, status in per_test:
                        entries.append((f"sim/ghdl/{proto}_vhdl/{test_name}", status))
                else:
                    result_log = os.path.join(run_dir, "results.log")
                    status = read_result_log(result_log)
                    entries.append((f"sim/ghdl/{proto}_vhdl", status))
        else:
            for proto in protos:
                entries.append((f"sim/ghdl/{proto}_vhdl", "SKIP"))

    # -----------------------------------------------------------------------
    # 3. ModelSim SV directed tests
    # -----------------------------------------------------------------------
    if not args.skip_sim and not args.skip_modelsim:
        print("\n=== ModelSim Directed Tests ===")
        if tool_installed("vsim"):
            rc, out = run_script(
                [sys.executable, sim_script, "--sim", "modelsim", "--proto", "all", "--lang", "sv"]
            )
            for proto in protos:
                run_dir = os.path.join(work_dir, "modelsim", f"{proto}_sv")
                result_log = os.path.join(run_dir, "results.log")
                status = read_result_log(result_log)
                entries.append((f"sim/modelsim/{proto}_sv", status))

            rc, out = run_script(
                [sys.executable, sim_script, "--sim", "modelsim", "--proto", "all", "--lang", "vhdl"]
            )
            for proto in protos:
                run_dir = os.path.join(work_dir, "modelsim", f"{proto}_vhdl")
                result_log = os.path.join(run_dir, "results.log")
                status = read_result_log(result_log)
                entries.append((f"sim/modelsim/{proto}_vhdl", status))
        else:
            for proto in protos:
                entries.append((f"sim/modelsim/{proto}_sv", "SKIP"))
                entries.append((f"sim/modelsim/{proto}_vhdl", "SKIP"))

    # -----------------------------------------------------------------------
    # 4. xsim SV directed tests
    # -----------------------------------------------------------------------
    if not args.skip_sim and not args.skip_xsim:
        print("\n=== Vivado xsim SV Directed Tests ===")
        if tool_installed("xvlog"):
            rc, out = run_script(
                [sys.executable, sim_script, "--sim", "xsim", "--proto", "all", "--lang", "sv"],
                timeout=600,
            )
            for proto in protos:
                run_dir = os.path.join(work_dir, "xsim", f"{proto}_sv")
                sim_log = os.path.join(run_dir, "xsim.log")
                per_test = parse_per_test_results(sim_log, proto)
                if per_test:
                    for test_name, status in per_test:
                        entries.append((f"sim/xsim/{proto}_sv/{test_name}", status))
                else:
                    result_log = os.path.join(run_dir, "results.log")
                    status = read_result_log(result_log)
                    entries.append((f"sim/xsim/{proto}_sv", status))
        else:
            for proto in protos:
                entries.append((f"sim/xsim/{proto}_sv", "SKIP"))

    # -----------------------------------------------------------------------
    # 5. xsim VHDL directed tests (skip — xsim VHDL not currently supported)
    # -----------------------------------------------------------------------
    if not args.skip_sim and not args.skip_xsim:
        # xsim+vhdl: sim_bus_matrix.py will skip these (not implemented)
        # Register as SKIP so they appear in the table
        for proto in protos:
            entries.append((f"sim/xsim/{proto}_vhdl", "SKIP"))

    # -----------------------------------------------------------------------
    # 6. UVM tests (separate script, NOT a flag on sim)
    # -----------------------------------------------------------------------
    if not args.skip_uvm:
        print("\n=== UVM Tests ===")
        uvm_work = os.path.join(work_dir, "xsim", "uvm")
        uvm_result = os.path.join(uvm_work, "results.log")
        # Check if UVM script exists
        uvm_script = os.path.join(tools_dir, "uvm_bus_matrix.py")
        if os.path.isfile(uvm_script) and tool_installed("xvlog"):
            rc, out = run_script(
                [sys.executable, uvm_script, "--test", "bus_matrix_base_test"],
                timeout=600,
            )
            status = read_result_log(uvm_result)
            entries.append(("uvm/xsim/bus_matrix_base_test", status))
        elif os.path.isfile(uvm_result):
            # UVM was run previously — collect its result
            status = read_result_log(uvm_result)
            entries.append(("uvm/xsim/bus_matrix_base_test", status))
        else:
            entries.append(("uvm/xsim/bus_matrix_base_test", "SKIP"))

    # -----------------------------------------------------------------------
    # 7. Formal verification
    # -----------------------------------------------------------------------
    if not args.skip_formal:
        print("\n=== Formal Verification ===")
        if os.path.isfile(formal_script) and tool_installed("sby"):
            rc, out = run_script(
                [sys.executable, formal_script]
            )
            formal_result = os.path.join(ip_path, "verification", "formal", "results.log")
            # Parse formal results per-sby-file
            if os.path.isfile(formal_result):
                with open(formal_result) as fh:
                    for line in fh:
                        m = re.match(r"\[(\S+)\]\s+(PASS|FAIL|SKIP)", line.strip())
                        if m:
                            entries.append((f"formal/{m.group(1)}", m.group(2)))
                # If no per-file entries found, use overall
                if not any(label.startswith("formal/") for label, _ in entries):
                    status = read_result_log(formal_result)
                    entries.append(("formal", status))
            else:
                entries.append(("formal", "NO_RUN"))
        else:
            entries.append(("formal", "SKIP"))

    # -----------------------------------------------------------------------
    # 8. Lint results
    # -----------------------------------------------------------------------
    if not args.skip_lint:
        print("\n=== Lint ===")
        lint_result = os.path.join(ip_path, "verification", "lint", "lint_results.log")
        if os.path.isfile(lint_script):
            rc, out = run_script(
                [sys.executable, lint_script]
            )
            status = read_result_log(lint_result)
            entries.append(("lint", status))
        elif os.path.isfile(lint_result):
            status = read_result_log(lint_result)
            entries.append(("lint", status))
        else:
            entries.append(("lint", "NO_RUN"))

    # -----------------------------------------------------------------------
    # Results summary
    # -----------------------------------------------------------------------
    results_log = os.path.join(work_dir, "regression_results.log")

    n_pass = sum(1 for _, s in entries if s == "PASS")
    n_skip = sum(1 for _, s in entries if s in ("SKIP", "MISSING"))
    n_total = len(entries)
    n_fail = n_total - n_pass - n_skip

    overall = "PASSED" if n_fail == 0 else "FAILED"

    # Build report
    lines = []
    lines.append("=" * 60)
    lines.append("bus_matrix Regression Results")
    lines.append("=" * 60)

    max_label = max((len(label) for label, _ in entries), default=40)
    for label, status in entries:
        lines.append(f"  {label:<{max_label}}  {status}")

    lines.append("-" * 60)
    lines.append(f"  Total: {n_total}  Pass: {n_pass}  Fail: {n_fail}  Skip: {n_skip}")
    lines.append("=" * 60)
    lines.append(f"REGRESSION {overall}")

    report = "\n".join(lines)
    print(f"\n{report}")

    # Write results log
    with open(results_log, "w") as fh:
        fh.write(report + "\n")
    print(f"\nResults: {results_log}")

    sys.exit(0 if n_fail == 0 else 1)


if __name__ == "__main__":
    main()
