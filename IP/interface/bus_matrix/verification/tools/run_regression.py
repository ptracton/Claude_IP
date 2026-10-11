#!/usr/bin/env python3
"""run_regression.py — Full regression harness for the bus_matrix IP.

Runs directed simulation (VCS + Xcelium on csun.edu; Icarus, GHDL, ModelSim
and Vivado xsim elsewhere), UVM (VCS on csun.edu, Vivado xsim elsewhere), formal
verification (VC Formal where `vcf` is on PATH, e.g. csun.edu; SymbiYosys
otherwise), and collects lint results; prints a consolidated pass/fail table.
Ported from IP/system/timer/verification/tools/run_regression.py.

Usage:
    python3 run_regression.py [--skip-sim] [--skip-uvm] [--skip-formal] [--skip-lint]
                              [--skip-modelsim] [--skip-xsim]

Results written to:
    ${CLAUDE_BUS_MATRIX_PATH}/verification/work/regression_results.log
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

# Host detection
import socket


def _hostname_fqdn() -> str:
    """Return the host FQDN.

    socket.getfqdn() falls back to the short hostname when reverse DNS
    doesn't resolve (observed on some *.csun.edu machines), so shell out to
    `hostname -f` first — the same command setup.sh uses for host detection.
    """
    try:
        out = subprocess.run(["hostname", "-f"], capture_output=True,
                             text=True, timeout=5)
        fqdn = out.stdout.strip()
        if fqdn:
            return fqdn
    except (OSError, subprocess.TimeoutExpired):
        pass
    return socket.getfqdn()


ON_CSUN = _hostname_fqdn().endswith(".csun.edu")

PROTOS = ["ahb", "apb", "axi4l", "wb"]
LANGS = ["sv", "vhdl"]
KNOWN_TESTS = ["test_reset", "test_route", "test_strobe", "test_decode_err",
               "test_contention", "test_arb"]

STEP_TIMEOUT = 600
# Formal runs sequentially: 8 jobs at up to 30 minutes plus the two AXI4-Lite
# jobs at up to 3 hours each (formal_bus_matrix.py budgets).
FORMAL_TIMEOUT = 10 * 3600


def get_ip_path() -> str:
    path = os.environ.get("CLAUDE_BUS_MATRIX_PATH")
    if not path:
        print("ERROR: CLAUDE_BUS_MATRIX_PATH is not set.  "
              "Run: source IP/interface/bus_matrix/setup.sh")
        sys.exit(1)
    return path


def run_step(label: str, cmd: list, cwd: str = None,
             timeout: int = STEP_TIMEOUT) -> bool:
    """Run a subprocess step, returning True on success."""
    print(f"\n{'='*60}")
    print(f"  Running: {label}")
    print(f"{'='*60}")
    try:
        result = subprocess.run(cmd, cwd=cwd, timeout=timeout)
        return result.returncode == 0
    except FileNotFoundError as exc:
        print(f"ERROR: {exc}")
        return False
    except subprocess.TimeoutExpired:
        print(f"ERROR: {label} timed out after {timeout} s")
        return False


def read_result_log(path: str) -> str:
    """Read first line of a results.log; return 'PASS', 'FAIL', or 'MISSING'."""
    try:
        with open(path) as fh:
            return fh.readline().strip()
    except FileNotFoundError:
        return "MISSING"


def parse_per_test_results(log_path: str) -> list:
    """Return list of (label, status) per test from a results.log.

    Both the SV and VHDL testbenches print ``test_name: PASS/FAIL (N checks)``
    lines. If none are found the overall first-line status is used for every
    known test, so a run that died early is still counted per test.
    """
    if not os.path.isfile(log_path):
        return []

    with open(log_path) as fh:
        lines = [l.strip() for l in fh]

    per_test = {}
    for line in lines:
        for test in KNOWN_TESTS:
            if line.startswith(f"{test}: PASS"):
                per_test.setdefault(test, "PASS")
            elif line.startswith(f"{test}: FAIL"):
                per_test[test] = "FAIL"

    overall = lines[0] if lines and lines[0] in ("PASS", "FAIL", "SKIP") else "MISSING"
    # Guard: if any line contains "FAIL", downgrade a claimed PASS to FAIL.
    if overall == "PASS" and any("FAIL" in l for l in lines[1:]):
        overall = "FAIL"

    if not per_test:
        per_test = {t: overall for t in KNOWN_TESTS}
    else:
        # A test that never reported (run aborted) inherits the overall status,
        # or FAIL if the overall claims PASS without it.
        for t in KNOWN_TESTS:
            if t not in per_test:
                per_test[t] = "FAIL" if overall == "PASS" else overall

    return [(t, per_test[t]) for t in KNOWN_TESTS]


def collect_results(ip_path: str) -> list:
    """Walk work/ and collect (label, status) pairs, counting individual tests."""
    work = Path(ip_path) / "verification" / "work"
    entries = []

    # Determine which simulators to collect based on host
    if ON_CSUN:
        expected_sims = ["vcs", "xcelium"]
    else:
        expected_sims = ["icarus", "ghdl", "modelsim", "xsim"]

    # Simulation results: work/<sim>/<proto>_<lang>/results.log. Only the
    # current protocol/language runs are collected, so stale run directories
    # (e.g. the pre-rename axi_*) never count.
    for sim in expected_sims:
        sim_dir = work / sim
        if not sim_dir.is_dir():
            continue
        for proto in PROTOS:
            for lang in LANGS:
                run_dir = sim_dir / f"{proto}_{lang}"
                if not run_dir.is_dir():
                    continue
                rlog = str(run_dir / "results.log")
                for test, status in parse_per_test_results(rlog):
                    entries.append((f"sim/{sim}/{run_dir.name}/{test}", status))

    # SymbiYosys results: work/formal/<job>/results.log
    formal_work = work / "formal"
    if formal_work.exists():
        for job_dir in sorted(formal_work.iterdir()):
            if not job_dir.is_dir():
                continue
            status = read_result_log(str(job_dir / "results.log"))
            entries.append((f"formal/{job_dir.name}", status))

    # VC Formal results: work/vcf/<top>_<lang>/results.log  (one per job)
    vcf_work = work / "vcf"
    if vcf_work.exists():
        for job_dir in sorted(vcf_work.iterdir()):
            if not job_dir.is_dir():
                continue
            status = read_result_log(str(job_dir / "results.log"))
            entries.append((f"formal/vcf/{job_dir.name}", status))

    # UVM results: work/<sim>/uvm/results.log — xsim (one test) on standard
    # hosts, VCS (all tests) on csun.edu
    if ON_CSUN:
        uvm_log = work / "vcs" / "uvm" / "results.log"
        if uvm_log.exists():
            entries.append(("uvm/vcs/all_tests", read_result_log(str(uvm_log))))
    else:
        uvm_work = work / "xsim" / "uvm"
        if uvm_work.exists():
            status = read_result_log(str(uvm_work / "results.log"))
            entries.append(("uvm/xsim/bus_matrix_base_test", status))

    return entries


def main():
    ip_path = get_ip_path()
    tools_dir = os.path.join(ip_path, "verification", "tools")
    sim_script = os.path.join(tools_dir, "sim_bus_matrix.py")

    parser = argparse.ArgumentParser(description="bus_matrix IP regression harness.")
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

    # ------------------------------------------------------------------ #
    # 1. Simulation
    # ------------------------------------------------------------------ #
    if not args.skip_sim:
        if ON_CSUN:
            sims = [("VCS", "vcs"), ("Xcelium", "xcelium")]
        else:
            sims = [("Icarus", "icarus")]
            if not args.skip_modelsim:
                sims.append(("ModelSim", "modelsim"))
            if not args.skip_xsim:
                sims.append(("Vivado xsim", "xsim"))
        for name, sim in sims:
            run_step(f"{name} SV simulation (all protocols)",
                     [sys.executable, sim_script,
                      "--sim", sim, "--proto", "all", "--lang", "sv"])
            if sim == "icarus":
                # Icarus has no VHDL; GHDL covers it on standard hosts
                run_step("GHDL VHDL simulation (all protocols)",
                         [sys.executable, sim_script,
                          "--sim", "ghdl", "--proto", "all", "--lang", "vhdl"])
            else:
                run_step(f"{name} VHDL simulation (all protocols)",
                         [sys.executable, sim_script,
                          "--sim", sim, "--proto", "all", "--lang", "vhdl"])

    # ------------------------------------------------------------------ #
    # 1b. UVM simulation — Vivado xsim on standard hosts, VCS on csun.edu
    # ------------------------------------------------------------------ #
    if not args.skip_uvm:
        if ON_CSUN:
            run_step(
                "UVM simulation — all tests (VCS)",
                [sys.executable,
                 os.path.join(tools_dir, "uvm_bus_matrix.py"),
                 "--sim", "vcs", "--test", "all"],
            )
        else:
            run_step(
                "UVM simulation — bus_matrix_base_test (Vivado xsim)",
                [sys.executable,
                 os.path.join(tools_dir, "uvm_bus_matrix.py"),
                 "--sim", "xsim", "--test", "bus_matrix_base_test"],
            )

    # ------------------------------------------------------------------ #
    # 2. Formal verification
    # ------------------------------------------------------------------ #
    if not args.skip_formal:
        tool = "vcf" if shutil.which("vcf") else "sby"
        run_step(
            f"Formal verification ({tool}, all protocols)",
            [sys.executable,
             os.path.join(tools_dir, "formal_bus_matrix.py"),
             "--tool", tool, "--proto", "all"],
            timeout=FORMAL_TIMEOUT,
        )

    # ------------------------------------------------------------------ #
    # 3. Collect all results
    # ------------------------------------------------------------------ #
    results = collect_results(ip_path)

    # Lint
    if not args.skip_lint:
        lint_log = os.path.join(ip_path, "verification", "lint", "lint_results.log")
        results.append(("lint", read_result_log(lint_log)))

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
    lines.append("bus_matrix IP Regression Results")
    lines.append(sep)
    for label, status in results:
        lines.append(f"  {label:<44} {status}")
    lines.append("-" * 60)
    lines.append(f"  Total: {total}  Pass: {n_pass}  Fail: {n_fail}  Skip: {n_skip}")
    lines.append(sep)
    lines.append("REGRESSION PASSED" if n_fail == 0 else "REGRESSION FAILED")

    report = "\n".join(lines)
    print("\n" + report)

    out_path = os.path.join(ip_path, "verification", "work", "regression_results.log")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as fh:
        fh.write(report + "\n")
    print(f"\nReport written to: {out_path}")

    sys.exit(0 if n_fail == 0 else 1)


if __name__ == "__main__":
    main()
