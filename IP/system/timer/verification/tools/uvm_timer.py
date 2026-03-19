#!/usr/bin/env python3
"""uvm_timer.py — UVM simulation runner for the timer APB IP.

Uses Vivado xsim (xvlog / xelab / xsim) which ships a built-in UVM 1.2
library.  No external UVM installation is required.

The UVM testbench targets the APB4 variant of the timer IP.

Name-collision note
-------------------
The RTL defines *module* timer_apb_if (APB-to-regfile bridge).
The UVM directory defines *interface* timer_apb_if (BFM bundle).
SystemVerilog allows a module and an interface to share a name only when
they live in **different work libraries**.  We therefore compile into two
libraries:

    rtl_lib  — RTL sources (reg pkg, regfile, core, timer_apb_if MODULE,
                             timer_apb wrapper)
    work     — UVM interface (timer_apb_if INTERFACE), UVM pkg, testbench

xelab searches rtl_lib first via "-L rtl_lib" so timer_apb.sv can
resolve its `timer_apb_if` instantiation to the MODULE.  The testbench
instantiates `timer_apb_if` using the INTERFACE found in `work`.

Usage
-----
    python3 uvm_timer.py [--test <test_name>] [--verbosity <UVM_NONE|...|UVM_HIGH>]

    python3 uvm_timer.py --test timer_base_test
    python3 uvm_timer.py --test timer_base_test --verbosity UVM_LOW

Results are written to:
    ${CLAUDE_TIMER_PATH}/verification/work/xsim/uvm/results.log
"""

import argparse
import os
import subprocess
import sys

# ---------------------------------------------------------------------------
# Environment guard
# ---------------------------------------------------------------------------

def get_timer_path() -> str:
    path = os.environ.get("CLAUDE_TIMER_PATH")
    if not path:
        print("ERROR: CLAUDE_TIMER_PATH is not set.")
        print("       Please run:  source timer/setup.sh")
        sys.exit(1)
    return path


# ---------------------------------------------------------------------------
# Tool paths — Vivado xsim
# ---------------------------------------------------------------------------

def _find_vivado_bin() -> str:
    """Return the Vivado bin directory, checking common install paths."""
    import shutil
    # If xvlog is already in PATH (e.g. settings64.sh was sourced) use it.
    if shutil.which("xvlog"):
        return os.path.dirname(shutil.which("xvlog"))
    # Common Vivado installation prefixes (newest first)
    for root in ["/opt/Xilinx/Vivado", "/tools/Xilinx/Vivado",
                 "/opt/xilinx/Vivado"]:
        if not os.path.isdir(root):
            continue
        # Pick the highest version directory
        versions = sorted(
            [v for v in os.listdir(root) if os.path.isdir(os.path.join(root, v))],
            reverse=True
        )
        for v in versions:
            candidate = os.path.join(root, v, "bin")
            if os.path.isfile(os.path.join(candidate, "xvlog")):
                return candidate
    return ""   # not found


VIVADO_BIN = _find_vivado_bin()
XVLOG = os.path.join(VIVADO_BIN, "xvlog") if VIVADO_BIN else "xvlog"
XELAB = os.path.join(VIVADO_BIN, "xelab") if VIVADO_BIN else "xelab"
XSIM  = os.path.join(VIVADO_BIN, "xsim")  if VIVADO_BIN else "xsim"

# Pre-compiled xsim UVM library and macros include directory.
# These paths are relative to the Vivado installation root.
def _vivado_root() -> str:
    """Return the Vivado installation root directory."""
    if VIVADO_BIN:
        return os.path.dirname(VIVADO_BIN)   # bin/../
    return ""

_vroot = _vivado_root()
UVM_LIB_DIR   = os.path.join(_vroot, "data", "xsim", "system_verilog", "uvm") \
                 if _vroot else ""
UVM_MACROS_INC = os.path.join(_vroot, "data", "xsim", "system_verilog",
                               "uvm_include") if _vroot else ""


# ---------------------------------------------------------------------------
# File lists
# ---------------------------------------------------------------------------

def rtl_files(timer_path: str) -> list:
    """RTL sources compiled into the 'rtl_lib' work library."""
    rtl = os.path.join(timer_path, "design", "rtl", "verilog")
    common_rtl = os.path.join(
        os.environ.get("IP_COMMON_PATH", os.path.join(timer_path, "..", "..", "common")),
        "design", "rtl", "verilog"
    )
    return [
        os.path.join(rtl, "timer_reg_pkg.sv"),
        os.path.join(rtl, "timer_regfile.sv"),
        os.path.join(rtl, "timer_core.sv"),
        os.path.join(common_rtl, "claude_apb_if.sv"),  # MODULE  (not the UVM interface)
        os.path.join(rtl, "timer_apb.sv"),
    ]


def uvm_files(timer_path: str) -> list:
    """UVM sources compiled into the default 'work' library."""
    uvm = os.path.join(timer_path, "verification", "tasks", "uvm")
    return [
        os.path.join(uvm, "timer_apb_if.sv"),   # INTERFACE (not the RTL module)
        os.path.join(uvm, "timer_uvm_pkg.sv"),
        os.path.join(uvm, "tb_timer_uvm.sv"),
    ]


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

def run_uvm(test_name: str, verbosity: str,
            timer_path: str, work_dir: str) -> bool:
    """Compile, elaborate, and simulate the UVM testbench with xsim.

    Returns True on PASS.

    Three-step Vivado xsim flow:
        1. xvlog --sv --uvm_version 1.2  (RTL → rtl_lib; UVM → work)
        2. xelab --uvm_version 1.2 tb_timer_uvm -s tb_uvm_sim
        3. xsim  tb_uvm_sim -runall
    """
    os.makedirs(work_dir, exist_ok=True)
    log_path    = os.path.join(work_dir, "sim.log")
    results     = os.path.join(work_dir, "results.log")
    rtl_lib_dir = os.path.join(work_dir, "rtl_lib")
    work_lib    = os.path.join(work_dir, "work")
    snapshot    = "tb_uvm_sim"
    full_log    = ""

    def _run(cmd, label, timeout=120):
        nonlocal full_log
        print(f"  [uvm/{label}] Running: {' '.join(os.path.basename(a) for a in cmd[:3])} ...")
        try:
            cp = subprocess.run(
                cmd, capture_output=True, text=True,
                timeout=timeout, cwd=work_dir
            )
        except FileNotFoundError as exc:
            msg = f"ERROR: tool not found — {exc}. Is Vivado in PATH?"
            print(f"  {msg}")
            _write_result(results, "FAIL", msg)
            return False, ""
        out = cp.stdout + cp.stderr
        full_log += out
        if cp.returncode != 0:
            print(f"  [uvm/{label}] FAILED (rc={cp.returncode}):\n{out}")
            _write_result(results, "FAIL", full_log)
            return False, out
        return True, out

    # Common xvlog flags for both RTL and UVM passes.
    # -i UVM_MACROS_INC makes `include "uvm_macros.svh"` resolve.
    # -L uvm links the pre-compiled Vivado UVM 1.2 library.
    common_xvlog = [
        XVLOG, "--sv", "--uvm_version", "1.2",
        "-L", f"uvm={UVM_LIB_DIR}",
    ]
    if UVM_MACROS_INC and os.path.isdir(UVM_MACROS_INC):
        common_xvlog += ["-i", UVM_MACROS_INC]

    # ------------------------------------------------------------------
    # Step 1a: compile RTL into rtl_lib
    # ------------------------------------------------------------------
    rtl_cmd = common_xvlog + [
        "--work", f"rtl_lib={rtl_lib_dir}",
        "--log",  os.path.join(work_dir, "xvlog_rtl.log"),
    ] + rtl_files(timer_path)

    ok, _ = _run(rtl_cmd, "xvlog_rtl")
    if not ok:
        return False

    # ------------------------------------------------------------------
    # Step 1b: compile UVM sources into work (default library)
    # ------------------------------------------------------------------
    uvm_cmd = common_xvlog + [
        "--work", f"work={work_lib}",
        "--log",  os.path.join(work_dir, "xvlog_uvm.log"),
        # rtl_lib must be on the search path so tb can resolve timer_apb
        "-L", f"rtl_lib={rtl_lib_dir}",
    ] + uvm_files(timer_path)

    ok, _ = _run(uvm_cmd, "xvlog_uvm")
    if not ok:
        return False

    # ------------------------------------------------------------------
    # Step 2: elaborate
    # ------------------------------------------------------------------
    elab_cmd = [
        XELAB, "--uvm_version", "1.2",
        "--debug", "typical",
        "--snapshot", snapshot,
        "--timescale", "1ns/1ps",
        "--log", os.path.join(work_dir, "xelab.log"),
        "-L", f"uvm={UVM_LIB_DIR}",
        "-L", f"work={work_lib}",
        "-L", f"rtl_lib={rtl_lib_dir}",
        "work.tb_timer_uvm",
    ]

    ok, _ = _run(elab_cmd, "xelab", timeout=180)
    if not ok:
        return False

    # ------------------------------------------------------------------
    # Step 3: simulate
    # ------------------------------------------------------------------
    print(f"  [uvm/xsim] Simulating {test_name} ...")
    sim_cmd = [
        XSIM, snapshot,
        "--runall",
        "--log", log_path,
        "--testplusarg", f"UVM_TESTNAME={test_name}",
        "--testplusarg", f"UVM_VERBOSITY={verbosity}",
    ]

    import time
    try:
        with open(log_path, "w") as sim_fh:
            proc = subprocess.Popen(
                sim_cmd, stdout=sim_fh, stderr=sim_fh,
                stdin=subprocess.DEVNULL, cwd=work_dir
            )
    except FileNotFoundError as exc:
        msg = f"ERROR: xsim not found — {exc}"
        print(f"  {msg}")
        _write_result(results, "FAIL", msg)
        return False

    deadline  = time.monotonic() + 300
    sim_out   = ""
    done      = False
    pass_mark = "TEST PASSED"
    fail_mark = "TEST FAILED"

    while time.monotonic() < deadline:
        time.sleep(1)
        try:
            with open(log_path, errors="replace") as fh:
                sim_out = fh.read()
        except OSError:
            pass
        if pass_mark in sim_out or fail_mark in sim_out or "UVM_FATAL" in sim_out:
            done = True
            break
        if proc.poll() is not None:
            break

    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()

    try:
        with open(log_path, errors="replace") as fh:
            sim_out = fh.read()
    except OSError:
        pass
    full_log += sim_out

    if not done:
        print(f"  [uvm/xsim] ERROR: timeout — no PASS/FAIL seen in 300 s")

    print(f"  [uvm/xsim] Output:\n{sim_out.strip()}")

    # The UVM report summary always prints "UVM_ERROR :    N" and
    # "UVM_FATAL :    N" lines, so substring checks for those strings
    # fire even on a clean run.  Rely solely on the PASS/FAIL markers
    # emitted by timer_base_test.sv which already accounts for all errors.
    passed = (pass_mark in sim_out) and (fail_mark not in sim_out)

    with open(results, "w") as fh:
        fh.write("PASS\n" if passed else "FAIL\n")
        fh.write(sim_out)

    status = "PASS" if passed else "FAIL"
    print(f"  -> {results} : {status}")
    return passed


# ---------------------------------------------------------------------------
# Result helper
# ---------------------------------------------------------------------------

def _write_result(path: str, status: str, detail: str) -> None:
    with open(path, "w") as fh:
        fh.write(f"{status}\n")
        fh.write(detail)
    print(f"  -> {path} : {status}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    timer_path = get_timer_path()

    parser = argparse.ArgumentParser(
        description="Run UVM simulation for the timer IP using Vivado xsim."
    )
    parser.add_argument(
        "--test",
        default="timer_base_test",
        help="UVM test name passed as +UVM_TESTNAME (default: %(default)s)",
    )
    parser.add_argument(
        "--verbosity",
        default="UVM_LOW",
        choices=["UVM_NONE", "UVM_LOW", "UVM_MEDIUM", "UVM_HIGH", "UVM_FULL", "UVM_DEBUG"],
        help="UVM verbosity level (default: %(default)s)",
    )
    args = parser.parse_args()

    work_dir = os.path.join(timer_path, "verification", "work", "xsim", "uvm")

    ok = run_uvm(args.test, args.verbosity, timer_path, work_dir)

    print("\n" + "=" * 60)
    print(f"UVM Result: {'PASS' if ok else 'FAIL'}  (test={args.test})")
    print("=" * 60)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
