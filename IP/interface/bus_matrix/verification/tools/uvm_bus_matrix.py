#!/usr/bin/env python3
"""uvm_bus_matrix.py — Standalone UVM runner for bus_matrix (Vivado xsim or VCS).

xsim (standard hosts): xvlog (compile RTL + UVM), xelab (elaborate), xsim
(simulate); Popen + polling for xsim to avoid hangs.
VCS (csun.edu): one `vcs -ntb_opts uvm-1.2` compile, then simv per test.
--sim auto (the default) picks xsim when xvlog is on PATH, else VCS.

The DUT is bus_matrix_axi4l with its default (bus_matrix_pkg) configuration;
the slaves are the shared claude_axi4l_if bridge + bus_matrix_tb_mem.

Usage:
    source IP/interface/bus_matrix/setup.sh
    python3 $CLAUDE_BUS_MATRIX_PATH/verification/tools/uvm_bus_matrix.py
    python3 $CLAUDE_BUS_MATRIX_PATH/verification/tools/uvm_bus_matrix.py --test bus_matrix_rw_test
    python3 $CLAUDE_BUS_MATRIX_PATH/verification/tools/uvm_bus_matrix.py --test all --sim vcs
"""

import argparse
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

TESTS = ["bus_matrix_base_test", "bus_matrix_rw_test", "bus_matrix_contention_test",
         "bus_matrix_map_test", "bus_matrix_decerr_test"]


def rtl_files(ip_path):
    """RTL of the AXI4-Lite variant, package first."""
    rtl = os.path.join(ip_path, "design", "rtl", "verilog")
    return [os.path.join(rtl, f) for f in [
        "bus_matrix_pkg.sv", "bus_matrix_decoder.sv", "bus_matrix_arb.sv",
        "bus_matrix_core.sv", "bus_matrix_axi4l_tgt.sv", "bus_matrix_axi4l_ini.sv",
        "bus_matrix_axi4l.sv",
    ]]


def tb_model_files(ip_path):
    """Slave models shared with the directed testbench."""
    common = os.environ.get("IP_COMMON_PATH",
                            os.path.join(ip_path, "..", "..", "common"))
    return [
        os.path.join(common, "design", "rtl", "verilog", "claude_axi4l_if.sv"),
        os.path.join(ip_path, "verification", "testbench", "bus_matrix_tb_mem.sv"),
        os.path.join(ip_path, "verification", "testbench", "bus_matrix_tb_axi4l_slave.sv"),
    ]


def uvm_incdirs(uvm_dir):
    return [uvm_dir] + [os.path.join(uvm_dir, d)
                        for d in ("agents/axi_master", "sequences", "env", "tests")]


def find_vivado_root():
    """Find Vivado installation root from xvlog on PATH."""
    xvlog = shutil.which("xvlog")
    if xvlog:
        # xvlog is at <vivado_root>/bin/xvlog
        return str(Path(xvlog).resolve().parent.parent)
    # Scan common locations
    for base in ["/opt/Xilinx/Vivado", "/tools/Xilinx/Vivado"]:
        if os.path.isdir(base):
            versions = sorted(os.listdir(base), reverse=True)
            for v in versions:
                candidate = os.path.join(base, v, "bin", "xvlog")
                if os.path.isfile(candidate):
                    return os.path.join(base, v)
    return None


def run_cmd(cmd, cwd=None, logfile=None, timeout=300):
    """Run a command, return (rc, stdout+stderr)."""
    print(f"  CMD: {' '.join(cmd)}")
    try:
        result = subprocess.run(
            cmd, cwd=cwd,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return 1, f"TIMEOUT after {timeout}s"
    except FileNotFoundError:
        return 1, f"Tool not found: {cmd[0]}"

    if logfile:
        with open(logfile, "w") as fh:
            fh.write(result.stdout)
    return result.returncode, result.stdout


def main():
    ip_path = os.environ.get("CLAUDE_BUS_MATRIX_PATH")
    if not ip_path:
        print("ERROR: CLAUDE_BUS_MATRIX_PATH is not set.")
        print("       Please run:  source IP/interface/bus_matrix/setup.sh")
        sys.exit(1)
    ip_path = str(Path(ip_path).resolve())

    parser = argparse.ArgumentParser(description="Run UVM tests for bus_matrix (xsim or VCS)")
    parser.add_argument("--test", default="bus_matrix_base_test",
                        help="UVM test name, or 'all' (default: bus_matrix_base_test)")
    parser.add_argument("--verbosity", default="UVM_MEDIUM",
                        help="UVM verbosity (default: UVM_MEDIUM)")
    parser.add_argument("--sim", choices=["auto", "xsim", "vcs"], default="auto",
                        help="simulator (default: xsim if xvlog is on PATH, else vcs)")
    args = parser.parse_args()
    tests = TESTS if args.test == "all" else [args.test]

    sim = args.sim
    if sim == "auto":
        sim = "xsim" if shutil.which("xvlog") or find_vivado_root() else "vcs"
    if sim == "vcs":
        sys.exit(run_vcs(ip_path, tests, args.verbosity))
    if len(tests) > 1:
        print("ERROR: --test all is supported with --sim vcs only; run xsim tests one at a time.")
        sys.exit(1)
    args.test = tests[0]

    vivado_root = find_vivado_root()
    if not vivado_root:
        print("ERROR: Vivado not found. Ensure xvlog is on PATH.")
        sys.exit(1)

    uvm_lib_dir = os.path.join(vivado_root, "data", "xsim", "system_verilog", "uvm")
    uvm_inc_dir = os.path.join(vivado_root, "data", "xsim", "system_verilog", "uvm_include")

    XVLOG = shutil.which("xvlog") or os.path.join(vivado_root, "bin", "xvlog")
    XELAB = shutil.which("xelab") or os.path.join(vivado_root, "bin", "xelab")
    XSIM = shutil.which("xsim") or os.path.join(vivado_root, "bin", "xsim")

    # Paths
    rtl_dir = os.path.join(ip_path, "design", "rtl", "verilog")
    uvm_dir = os.path.join(ip_path, "verification", "uvm")
    tb_dir = os.path.join(ip_path, "verification", "testbench")
    work_dir = os.path.join(ip_path, "verification", "work", "xsim", "uvm")
    os.makedirs(work_dir, exist_ok=True)

    rtl_lib_dir = os.path.join(work_dir, "rtl_lib")
    work_lib_dir = os.path.join(work_dir, "work")

    # UVM source files — slave models, interface, package, testbench
    uvm_files = tb_model_files(ip_path) + [
        os.path.join(uvm_dir, "bus_matrix_axi_if.sv"),
        os.path.join(uvm_dir, "bus_matrix_uvm_pkg.sv"),
        os.path.join(uvm_dir, "tb_bus_matrix_uvm.sv"),
    ]

    print(f"\n=== UVM Test: {args.test} ===")
    print(f"  Vivado root: {vivado_root}")

    # -----------------------------------------------------------------------
    # Step 1a: Compile RTL into rtl_lib
    # -----------------------------------------------------------------------
    print("\n--- Step 1a: Compile RTL ---")
    xvlog_rtl_cmd = [
        XVLOG, "--sv",
        "--work", f"rtl_lib={rtl_lib_dir}",
        "--log", os.path.join(work_dir, "xvlog_rtl.log"),
    ] + rtl_files(ip_path)

    rc, out = run_cmd(xvlog_rtl_cmd, cwd=work_dir)
    if rc != 0:
        print(f"  xvlog RTL FAILED (rc={rc})")
        print(out[-500:] if len(out) > 500 else out)
        write_result(work_dir, False, out)
        sys.exit(1)
    print("  RTL compile: OK")

    # -----------------------------------------------------------------------
    # Step 1b: Compile UVM sources into work
    # -----------------------------------------------------------------------
    print("\n--- Step 1b: Compile UVM ---")
    xvlog_uvm_cmd = [
        XVLOG, "--sv",
        "-L", f"uvm={uvm_lib_dir}",
        "-i", uvm_inc_dir,
    ] + [x for d in uvm_incdirs(uvm_dir) for x in ("-i", d)] + [
        "--work", f"work={work_lib_dir}",
        "-L", f"rtl_lib={rtl_lib_dir}",
        "--log", os.path.join(work_dir, "xvlog_uvm.log"),
    ] + uvm_files

    rc, out = run_cmd(xvlog_uvm_cmd, cwd=work_dir)
    if rc != 0:
        print(f"  xvlog UVM FAILED (rc={rc})")
        print(out[-500:] if len(out) > 500 else out)
        write_result(work_dir, False, out)
        sys.exit(1)
    print("  UVM compile: OK")

    # -----------------------------------------------------------------------
    # Step 2: Elaborate
    # -----------------------------------------------------------------------
    print("\n--- Step 2: Elaborate ---")
    snapshot = "tb_uvm_sim"
    xelab_cmd = [
        XELAB,
        "--debug", "typical",
        "--snapshot", snapshot,
        "--timescale", "1ns/1ps",
        "--log", os.path.join(work_dir, "xelab.log"),
        "-L", f"uvm={uvm_lib_dir}",
        "-L", f"work={work_lib_dir}",
        "-L", f"rtl_lib={rtl_lib_dir}",
        f"work.tb_bus_matrix_uvm",
    ]

    rc, out = run_cmd(xelab_cmd, cwd=work_dir, timeout=300)
    if rc != 0:
        print(f"  xelab FAILED (rc={rc})")
        print(out[-500:] if len(out) > 500 else out)
        write_result(work_dir, False, out)
        sys.exit(1)
    print("  Elaborate: OK")

    # -----------------------------------------------------------------------
    # Step 3: Simulate (Popen + polling — xsim hangs with subprocess.run)
    # -----------------------------------------------------------------------
    print(f"\n--- Step 3: Simulate ({args.test}) ---")
    sim_log_path = os.path.join(work_dir, "xsim.log")

    xsim_cmd = [
        XSIM, snapshot,
        "--runall",
        "--log", sim_log_path,
        "--testplusarg", f"UVM_TESTNAME={args.test}",
        "--testplusarg", f"UVM_VERBOSITY={args.verbosity}",
    ]

    print(f"  CMD: {' '.join(xsim_cmd)}")
    with open(os.path.join(work_dir, "xsim_stdout.log"), "w") as sim_log_fh:
        proc = subprocess.Popen(
            xsim_cmd,
            stdout=sim_log_fh, stderr=sim_log_fh,
            stdin=subprocess.DEVNULL, cwd=work_dir,
        )

    deadline = time.monotonic() + 300
    done = False
    sim_out = ""
    while time.monotonic() < deadline:
        time.sleep(1)
        if os.path.isfile(sim_log_path):
            with open(sim_log_path, errors="replace") as fh:
                sim_out = fh.read()
            if "TEST PASSED" in sim_out or "TEST FAILED" in sim_out:
                done = True
                break
        if proc.poll() is not None:
            break

    # Give xsim a moment to flush, then terminate
    try:
        proc.wait(timeout=15)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()

    # Read final log
    if os.path.isfile(sim_log_path):
        with open(sim_log_path, errors="replace") as fh:
            sim_out = fh.read()

    passed = ("TEST PASSED" in sim_out) and ("TEST FAILED" not in sim_out)

    if passed:
        print(f"  Simulate: PASS")
    else:
        print(f"  Simulate: FAIL")
        # Print last lines of sim log for debug
        lines = sim_out.strip().split("\n")
        for line in lines[-20:]:
            print(f"    {line}")

    write_result(work_dir, passed, sim_out)

    print(f"\n{'='*50}")
    print(f"UVM {'PASSED' if passed else 'FAILED'}: {args.test}")
    print(f"{'='*50}")
    print(f"Results: {os.path.join(work_dir, 'results.log')}")

    sys.exit(0 if passed else 1)


def run_vcs(ip_path, tests, verbosity):
    """Compile once with VCS (built-in UVM 1.2) and run each test. Returns exit code."""
    uvm_dir = os.path.join(ip_path, "verification", "uvm")
    work_dir = os.path.join(ip_path, "verification", "work", "vcs", "uvm")
    os.makedirs(work_dir, exist_ok=True)

    files = rtl_files(ip_path) + tb_model_files(ip_path) + [
        os.path.join(uvm_dir, "bus_matrix_axi_if.sv"),
        os.path.join(uvm_dir, "bus_matrix_uvm_pkg.sv"),
        os.path.join(uvm_dir, "tb_bus_matrix_uvm.sv"),
    ]
    print("\n=== UVM (VCS) ===")
    rc, out = run_cmd(["vcs", "-full64", "-sverilog", "-ntb_opts", "uvm-1.2",
                       "-timescale=1ns/1ps",
                       "+incdir+" + "+".join(uvm_incdirs(uvm_dir))] + files +
                      ["-o", "simv_uvm"],
                      cwd=work_dir, logfile=os.path.join(work_dir, "compile.log"))
    if rc != 0:
        print(f"  vcs compile FAILED (rc={rc})")
        print(out[-1500:])
        write_result(work_dir, False, out)
        return 1

    all_out, all_pass = [], True
    for test in tests:
        rc, out = run_cmd([os.path.join(work_dir, "simv_uvm"),
                           f"+UVM_TESTNAME={test}", f"+UVM_VERBOSITY={verbosity}"],
                          cwd=work_dir, logfile=os.path.join(work_dir, f"{test}.log"))
        passed = rc == 0 and "TEST PASSED" in out and "TEST FAILED" not in out
        all_pass &= passed
        print(f"  {test}: {'PASS' if passed else 'FAIL'}")
        all_out.append(f"{test}: {'PASS' if passed else 'FAIL'}")
        all_out.append(out)

    write_result(work_dir, all_pass, "\n".join(all_out))
    print(f"\nUVM {'PASSED' if all_pass else 'FAILED'} — results: "
          f"{os.path.join(work_dir, 'results.log')}")
    return 0 if all_pass else 1


def write_result(work_dir, passed, sim_out):
    """Write results.log: first line PASS/FAIL, rest is sim output."""
    result_path = os.path.join(work_dir, "results.log")
    with open(result_path, "w") as fh:
        fh.write("PASS\n" if passed else "FAIL\n")
        fh.write(sim_out)


if __name__ == "__main__":
    main()
