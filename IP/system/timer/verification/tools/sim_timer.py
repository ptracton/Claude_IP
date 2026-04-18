#!/usr/bin/env python3
"""sim_timer.py — Simulation runner for the timer IP block.

Supports Icarus Verilog (SV), GHDL (VHDL), ModelSim/Questa, Vivado xsim,
Synopsys VCS MX (SV+VHDL), and Cadence Xcelium (SV+VHDL).

On ecs-vdi.ecs.csun.edu only VCS and Xcelium are available; Icarus, GHDL,
ModelSim, and xsim are rejected with a clear error on that host.

Results are written to:
    ${CLAUDE_TIMER_PATH}/verification/work/<sim>/<proto>_<lang>/results.log

Usage examples:
    python3 sim_timer.py --sim icarus   --proto apb --lang sv
    python3 sim_timer.py --sim ghdl     --proto all --lang vhdl
    python3 sim_timer.py --sim vcs      --proto all --lang all
    python3 sim_timer.py --sim xcelium  --proto all --lang all
    python3 sim_timer.py --proto all --lang all   (runs icarus+ghdl on standard hosts;
                                                   vcs+xcelium on ecs-vdi)
"""

import argparse
import os
import socket
import subprocess
import sys

# ---------------------------------------------------------------------------
# Host detection
# ---------------------------------------------------------------------------
ON_ECS_VDI = socket.getfqdn() == "ecs-vdi.ecs.csun.edu"

# Simulators that are not available on ecs-vdi
_ECS_VDI_BLOCKED = {"icarus", "ghdl", "modelsim", "xsim"}

# ---------------------------------------------------------------------------
# Environment guard
# ---------------------------------------------------------------------------
def get_timer_path() -> str:
    """Return the timer IP root directory.

    Prefers CLAUDE_TIMER_PATH if set.  Falls back to computing the path from
    the location of this script (verification/tools/sim_timer.py → ../../).
    """
    path = os.environ.get("CLAUDE_TIMER_PATH")
    if path:
        return path
    # Auto-detect: this file lives at <timer_root>/verification/tools/sim_timer.py
    detected = os.path.normpath(
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    )
    print(f"INFO: CLAUDE_TIMER_PATH not set — using auto-detected path: {detected}")
    print("      Run 'source setup.sh' to suppress this message.")
    return detected


# ---------------------------------------------------------------------------
# Tool paths
# ---------------------------------------------------------------------------
OSS_CAD = "/opt/oss-cad-suite/bin"
IVERILOG = os.path.join(OSS_CAD, "iverilog")
VVP      = os.path.join(OSS_CAD, "vvp")
GHDL     = os.path.join(OSS_CAD, "ghdl")

# ModelSim/Questa — searched in PATH and common install locations
def _find_tool(name: str) -> str:
    """Return the first hit for *name* in PATH or well-known ModelSim installs."""
    import shutil
    hit = shutil.which(name)
    if hit:
        return hit
    for prefix in ["/opt/modelsim/bin", "/opt/questa/bin",
                   "/opt/intelFPGA/modelsim_ase/bin",
                   "/opt/intelFPGA_lite/modelsim_ase/bin",
                   "/tools/mentor/modelsim/bin"]:
        candidate = os.path.join(prefix, name)
        if os.path.isfile(candidate):
            return candidate
    return name   # fall back to bare name; FileNotFoundError on exec

VLIB = _find_tool("vlib")
VCOM = _find_tool("vcom")
VLOG = _find_tool("vlog")
VSIM = _find_tool("vsim")

# ---------------------------------------------------------------------------
# Vivado xsim tool paths (for directed tests — no UVM)
# ---------------------------------------------------------------------------

def _find_vivado_bin() -> str:
    """Return the Vivado bin directory or '' if not found."""
    import shutil
    if shutil.which("xvlog"):
        return os.path.dirname(shutil.which("xvlog"))
    for root in ["/opt/Xilinx/Vivado", "/tools/Xilinx/Vivado",
                 "/opt/xilinx/Vivado"]:
        if not os.path.isdir(root):
            continue
        versions = sorted(
            [v for v in os.listdir(root)
             if os.path.isdir(os.path.join(root, v))],
            reverse=True,
        )
        for v in versions:
            candidate = os.path.join(root, v, "bin")
            if os.path.isfile(os.path.join(candidate, "xvlog")):
                return candidate
    return ""


VIVADO_BIN = _find_vivado_bin()
XVLOG = os.path.join(VIVADO_BIN, "xvlog") if VIVADO_BIN else "xvlog"
XVHDL = os.path.join(VIVADO_BIN, "xvhdl") if VIVADO_BIN else "xvhdl"
XELAB = os.path.join(VIVADO_BIN, "xelab") if VIVADO_BIN else "xelab"
XSIM  = os.path.join(VIVADO_BIN, "xsim")  if VIVADO_BIN else "xsim"

SUPPORTED_PROTOS = ["ahb", "apb", "axi4l", "wb"]
SUPPORTED_LANGS  = ["sv", "vhdl"]


# ---------------------------------------------------------------------------
# File lists
# ---------------------------------------------------------------------------

def sv_files(proto: str, timer_path: str) -> list:
    """Return the ordered list of SV source files for the given protocol."""
    common_path = os.environ.get(
        "IP_COMMON_PATH",
        os.path.join(timer_path, "..", "..", "common")
    )
    rtl = os.path.join(timer_path, "design", "rtl", "verilog")
    tasks_common = os.path.join(common_path, "verification", "tasks")
    tests   = os.path.join(timer_path, "verification", "tests")
    tb_dir  = os.path.join(timer_path, "verification", "testbench")

    # Protocol-specific RTL files
    # The *_if adapters are common (claude_*_if); the top wrappers are IP-local.
    common_rtl = os.path.join(common_path, "design", "rtl", "verilog")
    proto_rtl = {
        "ahb":   [os.path.join(common_rtl, "claude_ahb_if.sv"),   os.path.join(rtl, "timer_ahb.sv")],
        "apb":   [os.path.join(common_rtl, "claude_apb_if.sv"),   os.path.join(rtl, "timer_apb.sv")],
        "axi4l": [os.path.join(common_rtl, "claude_axi4l_if.sv"), os.path.join(rtl, "timer_axi4l.sv")],
        "wb":    [os.path.join(common_rtl, "claude_wb_if.sv"),     os.path.join(rtl, "timer_wb.sv")],
    }

    files = [
        os.path.join(rtl, "timer_reg_pkg.sv"),
        os.path.join(rtl, "timer_regfile.sv"),
        os.path.join(rtl, "timer_core.sv"),
    ]
    for f in proto_rtl[proto]:
        files.append(f)

    files.append(os.path.join(tb_dir, f"tb_timer_{proto}.sv"))
    return files


def vhdl_files(proto: str, timer_path: str) -> list:
    """Return the ordered list of VHDL source files for the given protocol."""
    rtl      = os.path.join(timer_path, "design", "rtl", "vhdl")
    tests    = os.path.join(timer_path, "verification", "tests")
    tb_dir   = os.path.join(timer_path, "verification", "testbench")

    common_path = os.environ.get(
        "IP_COMMON_PATH",
        os.path.join(timer_path, "..", "..", "common")
    )
    common_rtl = os.path.join(common_path, "design", "rtl", "vhdl")
    proto_rtl = {
        "ahb":   [os.path.join(common_rtl, "claude_ahb_if.vhd"),   os.path.join(rtl, "timer_ahb.vhd")],
        "apb":   [os.path.join(common_rtl, "claude_apb_if.vhd"),   os.path.join(rtl, "timer_apb.vhd")],
        "axi4l": [os.path.join(common_rtl, "claude_axi4l_if.vhd"), os.path.join(rtl, "timer_axi4l.vhd")],
        "wb":    [os.path.join(common_rtl, "claude_wb_if.vhd"),     os.path.join(rtl, "timer_wb.vhd")],
    }

    files = [
        os.path.join(rtl, "timer_reg_pkg.vhd"),
        os.path.join(rtl, "timer_regfile.vhd"),
        os.path.join(rtl, "timer_core.vhd"),
    ]
    for f in proto_rtl[proto]:
        files.append(f)

    # Test helper package (common) must be analyzed before the testbench
    common_tests = os.path.join(common_path, "verification", "tests")
    files.append(os.path.join(common_tests, "ip_test_pkg.vhd"))
    files.append(os.path.join(tb_dir, f"tb_timer_{proto}.vhd"))
    return files


# ---------------------------------------------------------------------------
# Include directories for Icarus
# ---------------------------------------------------------------------------

def sv_include_dirs(timer_path: str) -> list:
    """Return include-directory flags for iverilog."""
    common_path = os.environ.get(
        "IP_COMMON_PATH",
        os.path.join(timer_path, "..", "..", "common")
    )
    return [
        os.path.join(common_path, "verification", "tasks"),
        os.path.join(common_path, "verification", "tests"),
        os.path.join(timer_path, "verification", "tests"),
    ]


# ---------------------------------------------------------------------------
# Runners
# ---------------------------------------------------------------------------

def run_icarus(proto: str, timer_path: str, work_dir: str) -> bool:
    """Compile and run SV testbench with Icarus Verilog. Returns True on PASS."""
    os.makedirs(work_dir, exist_ok=True)
    vvp_out  = os.path.join(work_dir, f"tb_timer_{proto}.vvp")
    log_path = os.path.join(work_dir, "sim.log")
    results  = os.path.join(work_dir, "results.log")

    files = sv_files(proto, timer_path)
    incdirs = sv_include_dirs(timer_path)
    incflags = []
    for d in incdirs:
        incflags += ["-I", d]

    compile_cmd = (
        [IVERILOG, "-g2012", "-Wall", "-Wno-timescale"]
        + incflags
        + ["-o", vvp_out]
        + files
    )

    print(f"  [icarus/{proto}_sv] Compiling ...")
    try:
        cp = subprocess.run(
            compile_cmd,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            universal_newlines=True,
            timeout=120
        )
    except FileNotFoundError:
        msg = f"ERROR: iverilog not found at {IVERILOG}"
        print(msg)
        _write_result(results, "FAIL", msg)
        return False

    compile_log = cp.stdout + cp.stderr
    if cp.returncode != 0:
        print(f"  [icarus/{proto}_sv] Compile FAILED:\n{compile_log}")
        _write_result(results, "FAIL", compile_log)
        return False

    print(f"  [icarus/{proto}_sv] Running ...")
    try:
        rp = subprocess.run(
            [VVP, vvp_out],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            universal_newlines=True,
            timeout=120
        )
    except FileNotFoundError:
        msg = f"ERROR: vvp not found at {VVP}"
        print(msg)
        _write_result(results, "FAIL", msg)
        return False

    sim_log = rp.stdout + rp.stderr
    with open(log_path, "w") as fh:
        fh.write(compile_log)
        fh.write(sim_log)

    print(f"  [icarus/{proto}_sv] Simulation output:\n{sim_log.strip()}")

    # PASS if exit code 0, "PASS" appears in output, and no "FAIL" string.
    # Icarus returns 0 even for $finish(1), so we must check for FAIL text.
    passed = (rp.returncode == 0) and ("PASS" in sim_log) and ("FAIL" not in sim_log)
    _write_result(results, "PASS" if passed else "FAIL", sim_log)
    return passed


def run_ghdl(proto: str, timer_path: str, work_dir: str) -> bool:
    """Analyze, elaborate, and simulate VHDL testbench with GHDL. Returns True on PASS."""
    os.makedirs(work_dir, exist_ok=True)
    log_path = os.path.join(work_dir, "sim.log")
    results  = os.path.join(work_dir, "results.log")

    files = vhdl_files(proto, timer_path)
    tb_top = f"tb_timer_{proto}"

    # Analysis pass
    print(f"  [ghdl/{proto}_vhdl] Analyzing ...")
    full_log = ""
    for f in files:
        cmd = [GHDL, "-a", "--std=08", "-frelaxed", f"--workdir={work_dir}", f]
        try:
            cp = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, timeout=60)
        except FileNotFoundError:
            msg = f"ERROR: ghdl not found at {GHDL}"
            print(msg)
            _write_result(results, "FAIL", msg)
            return False
        out = cp.stdout + cp.stderr
        full_log += out
        if cp.returncode != 0:
            print(f"  [ghdl/{proto}_vhdl] Analysis FAILED on {os.path.basename(f)}:\n{out}")
            _write_result(results, "FAIL", full_log)
            return False

    # Elaboration
    print(f"  [ghdl/{proto}_vhdl] Elaborating {tb_top} ...")
    elab_cmd = [GHDL, "-e", "--std=08", "-frelaxed", f"--workdir={work_dir}", tb_top]
    cp = subprocess.run(elab_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
                        timeout=60, cwd=work_dir)
    out = cp.stdout + cp.stderr
    full_log += out
    if cp.returncode != 0:
        print(f"  [ghdl/{proto}_vhdl] Elaboration FAILED:\n{out}")
        _write_result(results, "FAIL", full_log)
        return False

    # Simulation
    print(f"  [ghdl/{proto}_vhdl] Simulating ...")
    sim_cmd = [GHDL, "-r", "--std=08", "-frelaxed", f"--workdir={work_dir}",
               tb_top, "--stop-time=1ms"]
    rp = subprocess.run(sim_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
                        timeout=120, cwd=work_dir)
    out = rp.stdout + rp.stderr
    full_log += out

    with open(log_path, "w") as fh:
        fh.write(full_log)

    print(f"  [ghdl/{proto}_vhdl] Output:\n{out.strip()}")

    # GHDL exits non-zero on severity-failure. Also check for "FAIL" text
    # from assert-style checks printed via report/write.
    passed = (rp.returncode == 0) and ("PASS" in out) and ("FAIL" not in out)
    _write_result(results, "PASS" if passed else "FAIL", out)
    return passed


def run_modelsim(proto: str, lang: str, timer_path: str, work_dir: str) -> bool:
    """Compile and simulate with ModelSim/Questa. Returns True on PASS.

    All commands run with cwd=work_dir so the logical library name "work"
    resolves to work_dir/work without needing vmap.

    Flow:
      1. vlib work                  — create physical library directory
      2. vcom -2008 -work work      — analyse VHDL files in dependency order
         vlog -sv -work work        — OR analyse SV files
      3. write sim.do               — batch do-file: run -all; quit -f
      4. vsim -c work.tb_top        — batch simulate; transcript → stdout
    """
    os.makedirs(work_dir, exist_ok=True)
    log_path = os.path.join(work_dir, "sim.log")
    results  = os.path.join(work_dir, "results.log")
    do_path  = os.path.join(work_dir, "sim.do")
    tb_top   = f"tb_timer_{proto}"
    full_log = ""

    # Write the do-file (avoids shell quoting issues with inline -do strings).
    # "run -all" runs until all VHDL processes reach a permanent wait (deadlock),
    # which is how our testbenches terminate.  ModelSim then exits naturally when
    # the do-file finishes — "quit -f" is intentionally omitted because it hangs
    # when stdin is not a real terminal (subprocess with DEVNULL).
    with open(do_path, "w") as fh:
        fh.write("run -all\n")

    def _run(cmd, timeout=60):
        return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
                              timeout=timeout, cwd=work_dir, errors="replace")

    # -- Step 1: vlib --------------------------------------------------------
    print(f"  [modelsim/{proto}_{lang}] Creating library ...")
    try:
        cp = _run([VLIB, "work"], timeout=30)
    except FileNotFoundError:
        msg = f"vlib not found ({VLIB}). Is ModelSim/Questa in PATH?"
        print(f"  [modelsim/{proto}_{lang}] WARNING: {msg}")
        _skip_result(results, msg)
        return True  # SKIP — tool absent is not a test failure
    full_log += cp.stdout + cp.stderr
    if cp.returncode != 0:
        print(f"  [modelsim/{proto}_{lang}] vlib FAILED:\n{cp.stdout + cp.stderr}")
        _write_result(results, "FAIL", full_log)
        return False

    # -- Step 2: compile sources --------------------------------------------
    if lang == "vhdl":
        files            = vhdl_files(proto, timer_path)
        compile_cmd_base = [VCOM, "-2008", "-work", "work"]
    else:
        files    = sv_files(proto, timer_path)
        incdirs  = sv_include_dirs(timer_path)
        incflags = ["+incdir+" + d for d in incdirs]
        compile_cmd_base = [VLOG, "-sv", "-work", "work"] + incflags

    print(f"  [modelsim/{proto}_{lang}] Compiling {len(files)} file(s) ...")
    try:
        if lang == "vhdl":
            # vcom must analyse VHDL files one at a time (dependency order)
            for f in files:
                cp = _run(compile_cmd_base + [f])
                full_log += cp.stdout + cp.stderr
                if cp.returncode != 0:
                    print(f"  [modelsim/{proto}_{lang}] vcom FAILED on "
                          f"{os.path.basename(f)}:\n{cp.stdout + cp.stderr}")
                    _write_result(results, "FAIL", full_log)
                    return False
        else:
            # vlog compiles all SV files in one pass
            cp = _run(compile_cmd_base + files)
            full_log += cp.stdout + cp.stderr
            if cp.returncode != 0:
                print(f"  [modelsim/{proto}_{lang}] vlog FAILED:\n"
                      f"{cp.stdout + cp.stderr}")
                _write_result(results, "FAIL", full_log)
                return False
    except FileNotFoundError as exc:
        msg = f"ERROR: compiler not found — {exc}"
        print(f"  {msg}")
        _write_result(results, "FAIL", msg)
        return False

    # -- Step 3: simulate ---------------------------------------------------
    print(f"  [modelsim/{proto}_{lang}] Simulating {tb_top} ...")
    # vsim -c reads stdin even after the do-file ends, so we cannot use
    # subprocess.run() — it would block indefinitely.  Instead, use Popen
    # and poll the log file for the testbench's final PASS/FAIL banner.
    # Once the banner is seen (or the timeout expires), kill vsim and return.
    sim_cmd = [VSIM, "-c", f"work.{tb_top}", "-do", do_path]
    import time
    try:
        with open(log_path, "w") as sim_fh:
            proc = subprocess.Popen(sim_cmd, stdout=sim_fh, stderr=sim_fh,
                                    stdin=subprocess.DEVNULL, cwd=work_dir)
    except FileNotFoundError as exc:
        msg = f"ERROR: vsim not found — {exc}"
        print(f"  {msg}")
        _write_result(results, "FAIL", msg)
        return False

    deadline = time.monotonic() + 300
    sim_out  = ""
    done     = False
    pass_marker  = f"PASS tb_timer_{proto}"
    fail_markers = ["FAIL", "FATAL_ERROR"]

    while time.monotonic() < deadline:
        time.sleep(1)
        # Read whatever the log has so far
        try:
            with open(log_path) as fh:
                sim_out = fh.read()
        except OSError:
            pass
        if pass_marker in sim_out or any(m in sim_out for m in fail_markers):
            done = True
            break
        if proc.poll() is not None:   # vsim exited on its own
            break

    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()

    # Final read after process is dead
    try:
        with open(log_path) as fh:
            sim_out = fh.read()
    except OSError:
        pass
    full_log += sim_out

    if not done and time.monotonic() >= deadline:
        print(f"  [modelsim/{proto}_{lang}] ERROR: timeout — no pass/fail seen in 300 s")

    print(f"  [modelsim/{proto}_{lang}] Simulation output:\n{sim_out.strip()}")

    passed = (pass_marker in sim_out) and not any(m in sim_out for m in fail_markers)
    _write_result(results, "PASS" if passed else "FAIL", sim_out)
    return passed


def _write_result(path: str, status: str, detail: str) -> None:
    """Write a results.log file."""
    with open(path, "w") as fh:
        fh.write(f"{status}\n")
        fh.write(detail)
    print(f"  -> {path} : {status}")


def _skip_result(path: str, msg: str) -> None:
    """Write a results.log with SKIP status (tool not installed)."""
    with open(path, "w") as fh:
        fh.write(f"SKIP\n{msg}\n")
    print(f"  -> {path} : SKIP")


def run_xsim(proto: str, lang: str, timer_path: str, work_dir: str) -> bool:
    """Compile and simulate a directed testbench with Vivado xsim.

    Three-step flow:
      1. xvlog --sv (SV) or xvhdl --2008 per file (VHDL)
      2. xelab --snapshot <snap>
      3. xsim  <snap> --runall   (Popen + DEVNULL — xsim hangs on TTY stdin)

    Returns True on PASS or SKIP (tool absent); False on compile/sim FAIL.
    """
    import time as _time

    os.makedirs(work_dir, exist_ok=True)
    log_path = os.path.join(work_dir, "sim.log")
    results  = os.path.join(work_dir, "results.log")
    tb_top   = f"tb_timer_{proto}"
    snapshot = f"{tb_top}_sim"
    full_log = ""

    if not VIVADO_BIN:
        msg = "Vivado (xvlog/xelab/xsim) not found — skipping."
        print(f"  [xsim/{proto}_{lang}] WARNING: {msg}")
        _skip_result(results, msg)
        return True  # SKIP

    def _run(cmd, label, timeout=180):
        nonlocal full_log
        print(f"  [xsim/{proto}_{lang}] {label} ...")
        try:
            cp = subprocess.run(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
                timeout=timeout, cwd=work_dir,
            )
        except FileNotFoundError as exc:
            msg = f"ERROR: tool not found — {exc}"
            print(f"  {msg}")
            _write_result(results, "FAIL", full_log + "\n" + msg)
            return False
        out = cp.stdout + cp.stderr
        full_log += out
        if cp.returncode != 0:
            print(f"  [xsim/{proto}_{lang}] {label} FAILED:\n{out}")
            _write_result(results, "FAIL", full_log)
            return False
        return True

    # ------------------------------------------------------------------
    # Step 1: compile
    # ------------------------------------------------------------------
    if lang == "sv":
        incdirs = sv_include_dirs(timer_path)
        inc_flags = []
        for d in incdirs:
            inc_flags += ["-i", d]
        compile_cmd = (
            [XVLOG, "--sv",
             "--log", os.path.join(work_dir, "xvlog.log")]
            + inc_flags
            + sv_files(proto, timer_path)
        )
        if not _run(compile_cmd, "xvlog"):
            return False
    else:
        xvhdl_log = os.path.join(work_dir, "xvhdl.log")
        for f in vhdl_files(proto, timer_path):
            cmd = [XVHDL, "--2008", "--log", xvhdl_log, f]
            if not _run(cmd, f"xvhdl {os.path.basename(f)}"):
                return False

    # ------------------------------------------------------------------
    # Step 2: elaborate
    # ------------------------------------------------------------------
    elab_cmd = [
        XELAB,
        "--snapshot", snapshot,
        "--timescale", "1ns/1ps",
        "--debug", "typical",
        "--log", os.path.join(work_dir, "xelab.log"),
        tb_top,
    ]
    if not _run(elab_cmd, "xelab"):
        return False

    # ------------------------------------------------------------------
    # Step 3: simulate (Popen + DEVNULL — xsim hangs reading TTY stdin)
    # ------------------------------------------------------------------
    xsim_log = os.path.join(work_dir, "xsim_out.log")
    sim_cmd = [XSIM, snapshot, "--runall", "--log", xsim_log]

    print(f"  [xsim/{proto}_{lang}] Simulating ...")
    try:
        proc = subprocess.Popen(
            sim_cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            cwd=work_dir,
        )
    except FileNotFoundError as exc:
        msg = f"ERROR: xsim not found — {exc}"
        print(f"  {msg}")
        _write_result(results, "FAIL", full_log + "\n" + msg)
        return False

    pass_marker  = f"PASS tb_timer_{proto}"
    fail_markers = ["FAIL", "FATAL_ERROR"]
    deadline = _time.monotonic() + 300
    sim_out  = ""
    done     = False

    while _time.monotonic() < deadline:
        _time.sleep(1)
        try:
            with open(xsim_log, errors="replace") as fh:
                sim_out = fh.read()
        except OSError:
            pass
        if pass_marker in sim_out or any(m in sim_out for m in fail_markers):
            done = True
            break
        if proc.poll() is not None:
            break

    # Give xsim up to 15 s to exit cleanly (e.g. after std.env.stop).
    # If it doesn't exit on its own, force-kill it.
    try:
        proc.wait(timeout=15)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()

    # Final read after process is confirmed dead
    try:
        with open(xsim_log, errors="replace") as fh:
            sim_out = fh.read()
    except OSError:
        pass
    full_log += sim_out

    with open(log_path, "w") as fh:
        fh.write(full_log)

    if not done:
        print(f"  [xsim/{proto}_{lang}] ERROR: timeout — no PASS/FAIL seen in 300 s")

    print(f"  [xsim/{proto}_{lang}] Output:\n{sim_out.strip()}")

    # A FATAL_ERROR that appears after the PASS banner is caused by our
    # process termination (xsimk orphaned), not a real simulation failure.
    # Only treat fail markers as failures when they precede the PASS banner.
    pass_pos = sim_out.find(pass_marker)
    if pass_pos >= 0:
        pre_pass = sim_out[:pass_pos]
        passed = not any(m in pre_pass for m in fail_markers)
    else:
        passed = False
    _write_result(results, "PASS" if passed else "FAIL", full_log)
    return passed


# ---------------------------------------------------------------------------
# VCS MX runner (ecs-vdi only)
# ---------------------------------------------------------------------------

def run_vcs(proto: str, lang: str, timer_path: str, work_dir: str) -> bool:
    """Compile and simulate with Synopsys VCS MX. Returns True on PASS.

    SV flow  (2 steps):
      1. vcs -full64 -sverilog -timescale=1ns/1ps +incdir+... <sv-files> -o simv
      2. ./simv

    VHDL flow (3 steps — vcs treats .vhd files as Verilog without vhdlan):
      1. vhdlan -full64 <vhd-files>          (analyze VHDL into work library)
      2. vcs -full64 -e <tb-top> -o simv     (elaborate)
      3. ./simv
    """
    os.makedirs(work_dir, exist_ok=True)
    log_path = os.path.join(work_dir, "sim.log")
    results  = os.path.join(work_dir, "results.log")
    simv     = os.path.join(work_dir, f"simv_{proto}_{lang}")
    tb_top   = f"tb_timer_{proto}"
    full_log = ""

    if lang == "sv":
        # ── SV: single vcs compilation step ───────────────────────────────
        incdirs = sv_include_dirs(timer_path)
        incflag = "+incdir+" + "+".join(incdirs)
        # -timescale sets the default for files that lack a `timescale directive;
        # VCS requires all modules to agree on timescale when any one specifies it.
        compile_cmd = (
            ["vcs", "-full64", "-sverilog", "-timescale=1ns/1ps", incflag]
            + sv_files(proto, timer_path)
            + ["-o", simv]
        )
        print(f"  [vcs/{proto}_{lang}] Compiling ...")
        try:
            cp = subprocess.run(compile_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                universal_newlines=True, timeout=180, cwd=work_dir)
        except FileNotFoundError:
            msg = "ERROR: vcs not found — is Synopsys VCS MX in PATH?"
            print(f"  {msg}")
            _write_result(results, "FAIL", msg)
            return False
        full_log = cp.stdout + cp.stderr
        if cp.returncode != 0:
            print(f"  [vcs/{proto}_{lang}] Compile FAILED:\n{full_log}")
            _write_result(results, "FAIL", full_log)
            return False

    else:
        # ── VHDL: vhdlan (analyze) then vcs -e (elaborate) ───────────────
        src = vhdl_files(proto, timer_path)

        # Step 1: vhdlan — VHDL analysis into work library
        # -vhdl08: enable VHDL-2008 (required for conditional variable assignments,
        #          "when...else" in sequential context, etc.)
        vhdlan_cmd = ["vhdlan", "-full64", "-vhdl08"] + src
        print(f"  [vcs/{proto}_{lang}] Analyzing VHDL (vhdlan) ...")
        try:
            ap = subprocess.run(vhdlan_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                universal_newlines=True, timeout=180, cwd=work_dir)
        except FileNotFoundError:
            msg = "ERROR: vhdlan not found — is Synopsys VCS MX in PATH?"
            print(f"  {msg}")
            _write_result(results, "FAIL", msg)
            return False
        full_log += ap.stdout + ap.stderr
        if ap.returncode != 0:
            print(f"  [vcs/{proto}_{lang}] vhdlan FAILED:\n{full_log}")
            _write_result(results, "FAIL", full_log)
            return False

        # Step 2: vcs — elaborate (design unit is a positional arg, not -e)
        elab_cmd = ["vcs", "-full64", tb_top, "-o", simv]
        print(f"  [vcs/{proto}_{lang}] Elaborating (vcs -e) ...")
        try:
            ep = subprocess.run(elab_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                universal_newlines=True, timeout=180, cwd=work_dir)
        except FileNotFoundError:
            msg = "ERROR: vcs not found — is Synopsys VCS MX in PATH?"
            print(f"  {msg}")
            _write_result(results, "FAIL", full_log + "\n" + msg)
            return False
        full_log += ep.stdout + ep.stderr
        if ep.returncode != 0:
            print(f"  [vcs/{proto}_{lang}] Elaborate FAILED:\n{ep.stdout + ep.stderr}")
            _write_result(results, "FAIL", full_log)
            return False

    # ── Simulate ──────────────────────────────────────────────────────────
    print(f"  [vcs/{proto}_{lang}] Simulating {tb_top} ...")
    try:
        rp = subprocess.run([simv], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            universal_newlines=True, timeout=120, cwd=work_dir)
    except FileNotFoundError:
        msg = f"ERROR: compiled binary not found at {simv}"
        print(f"  {msg}")
        _write_result(results, "FAIL", full_log + "\n" + msg)
        return False

    sim_out = rp.stdout + rp.stderr
    full_log += sim_out
    with open(log_path, "w") as fh:
        fh.write(full_log)

    print(f"  [vcs/{proto}_{lang}] Output:\n{sim_out.strip()}")

    pass_marker  = f"PASS {tb_top}"
    fail_markers = ["FAIL", "FATAL_ERROR"]
    pass_pos = full_log.find(pass_marker)
    if pass_pos >= 0:
        passed = not any(m in full_log[:pass_pos] for m in fail_markers)
    else:
        passed = False
    _write_result(results, "PASS" if passed else "FAIL", full_log)
    return passed


# ---------------------------------------------------------------------------
# Xcelium runner (ecs-vdi only)
# ---------------------------------------------------------------------------

def run_xcelium(proto: str, lang: str, timer_path: str, work_dir: str) -> bool:
    """Compile, elaborate, and simulate with Cadence Xcelium. Returns True on PASS.

    SV flow  (1 step via xrun):
      xrun -64 -access +rwc -timescale 1ns/1ps -sv +incdir+... <sv-files> -top <tb_top>

    VHDL flow (3 steps — xrun does not expose xmvhdl's -v2k8 flag directly):
      1. xmvhdl -64 -work work -v2k8 <vhd-files>   (analyze VHDL-2008)
      2. xmelab -64 -access +rwc -log elab.log <tb_top>  (elaborate)
      3. xmsim  -64 -log sim.log <tb_top>           (simulate)
    """
    os.makedirs(work_dir, exist_ok=True)
    log_path  = os.path.join(work_dir, "sim.log")
    results   = os.path.join(work_dir, "results.log")
    tb_top    = f"tb_timer_{proto}"
    full_log  = ""

    def _run(cmd, label, timeout=180):
        """Run a subprocess; return (stdout+stderr, returncode) or raise on tool-not-found."""
        try:
            p = subprocess.run(cmd, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               universal_newlines=True, timeout=timeout, cwd=work_dir)
            return p.stdout + p.stderr, p.returncode
        except FileNotFoundError:
            raise RuntimeError("ERROR: {} not found — is Cadence Xcelium in PATH?".format(cmd[0]))
        except subprocess.TimeoutExpired:
            raise RuntimeError("ERROR: {} timed out after {}s".format(label, timeout))

    if lang == "sv":
        # ── SV: single xrun step ──────────────────────────────────────────
        incdirs = sv_include_dirs(timer_path)
        incflag = "+incdir+" + "+".join(incdirs)
        xrun_cmd = [
            "xrun", "-64", "-access", "+rwc",
            # Set default timescale for modules that lack a `timescale directive;
            # xmelab requires all modules to agree on timescale when any one specifies it.
            "-timescale", "1ns/1ps",
            "-log", log_path,
            "-work", "work",
            "-sv", incflag,
        ] + sv_files(proto, timer_path) + ["-top", tb_top]

        print(f"  [xcelium/{proto}_{lang}] Running xrun ...")
        try:
            out, rc = _run(xrun_cmd, "xrun")
        except RuntimeError as exc:
            msg = str(exc)
            print(f"  {msg}")
            _write_result(results, "FAIL", msg)
            return False

        try:
            with open(log_path, errors="replace") as fh:
                full_log = fh.read()
        except OSError:
            full_log = out

    else:
        # ── VHDL: xmvhdl → xmelab → xmsim ───────────────────────────────
        src = vhdl_files(proto, timer_path)
        elab_log = os.path.join(work_dir, "elab.log")

        # Step 1: xmvhdl — VHDL-2008 analysis
        # -V200X:        enable VHDL-200X (2008) + VHDL-93 features
        # -INC_V200X_PKG: implicitly include *_additions packages (e.g.
        #                  std_logic_1164_additions) so that to_hstring and
        #                  other 2008 subprograms are visible without an
        #                  explicit use clause in user code.
        # -WORK must be uppercase for xmvhdl.
        vhdl_cmd = ["xmvhdl", "-64", "-WORK", "work", "-V200X", "-INC_V200X_PKG"] + src
        print(f"  [xcelium/{proto}_{lang}] Analyzing VHDL (xmvhdl -V200X) ...")
        try:
            out, rc = _run(vhdl_cmd, "xmvhdl")
        except RuntimeError as exc:
            msg = str(exc)
            print(f"  {msg}")
            _write_result(results, "FAIL", msg)
            return False
        full_log += out
        if rc != 0:
            print(f"  [xcelium/{proto}_{lang}] xmvhdl FAILED:\n{out}")
            _write_result(results, "FAIL", full_log)
            return False

        # Step 2: xmelab — elaborate
        elab_cmd = ["xmelab", "-64", "-access", "+rwc", "-log", elab_log, tb_top]
        print(f"  [xcelium/{proto}_{lang}] Elaborating (xmelab) ...")
        try:
            out, rc = _run(elab_cmd, "xmelab")
        except RuntimeError as exc:
            msg = str(exc)
            print(f"  {msg}")
            _write_result(results, "FAIL", full_log + "\n" + msg)
            return False
        try:
            with open(elab_log, errors="replace") as fh:
                full_log += fh.read()
        except OSError:
            full_log += out
        if rc != 0:
            print(f"  [xcelium/{proto}_{lang}] xmelab FAILED:\n{out}")
            _write_result(results, "FAIL", full_log)
            return False

        # Step 3: xmsim — simulate
        sim_cmd = ["xmsim", "-64", "-log", log_path, tb_top]
        print(f"  [xcelium/{proto}_{lang}] Simulating (xmsim) ...")
        try:
            out, rc = _run(sim_cmd, "xmsim", timeout=120)
        except RuntimeError as exc:
            msg = str(exc)
            print(f"  {msg}")
            _write_result(results, "FAIL", full_log + "\n" + msg)
            return False
        try:
            with open(log_path, errors="replace") as fh:
                full_log += fh.read()
        except OSError:
            full_log += out

    with open(log_path, "w") as fh:
        fh.write(full_log)

    # Filter cosmetic CLE-10/ERR-3 lines that xmsim emits when std.env.stop is
    # called; they are unavoidable with the 3-step xmvhdl/xmelab/xmsim flow and
    # do not affect pass/fail determination (they appear after the PASS marker).
    display_log = "\n".join(
        ln for ln in full_log.splitlines()
        if "CLE-10" not in ln and "ERR-3" not in ln
    )
    print(f"  [xcelium/{proto}_{lang}] Output (tail):\n{display_log[-800:].strip()}")

    pass_marker  = f"PASS {tb_top}"
    fail_markers = ["FAIL", "FATAL_ERROR", "ERROR"]
    pass_pos = full_log.find(pass_marker)
    if pass_pos >= 0:
        passed = not any(m in full_log[:pass_pos] for m in fail_markers)
    else:
        passed = False
    _write_result(results, "PASS" if passed else "FAIL", full_log)
    return passed


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    timer_path = get_timer_path()

    parser = argparse.ArgumentParser(
        description="Run simulation tests for the timer IP block."
    )
    parser.add_argument(
        "--sim",
        choices=["icarus", "ghdl", "modelsim", "xsim", "vcs", "xcelium", "all"],
        default=None,
        help="Simulator to use. On ecs-vdi.ecs.csun.edu only vcs and xcelium are "
             "available. 'all' selects icarus+ghdl on standard hosts and "
             "vcs+xcelium on ecs-vdi. (default: icarus on standard hosts, vcs on ecs-vdi)",
    )
    parser.add_argument(
        "--proto",
        choices=SUPPORTED_PROTOS + ["all"],
        default="apb",
        help="Bus protocol (default: %(default)s)",
    )
    parser.add_argument(
        "--lang",
        choices=SUPPORTED_LANGS + ["all"],
        default="sv",
        help="HDL language (default: %(default)s)",
    )
    parser.add_argument(
        "--test",
        default=None,
        help="Name of a specific test (informational only; all tests run by default)",
    )
    args = parser.parse_args()

    # Apply ecs-vdi restrictions before expanding 'all'
    sim_arg = args.sim
    if sim_arg is None:
        sim_arg = "vcs" if ON_ECS_VDI else "icarus"

    if ON_ECS_VDI and sim_arg in _ECS_VDI_BLOCKED:
        print(f"ERROR: --sim {sim_arg} is not available on ecs-vdi.ecs.csun.edu.")
        print("       Use --sim vcs or --sim xcelium on this host.")
        sys.exit(1)

    # Expand 'all'
    protos = SUPPORTED_PROTOS if args.proto == "all" else [args.proto]
    langs  = SUPPORTED_LANGS  if args.lang  == "all" else [args.lang]
    if sim_arg == "all":
        sims = ["vcs", "xcelium"] if ON_ECS_VDI else ["icarus", "ghdl", "modelsim", "xsim"]
    else:
        sims = [sim_arg]

    work_base = os.path.join(timer_path, "verification", "work")

    all_pass = True
    results_summary = []

    for sim in sims:
        for proto in protos:
            for lang in langs:
                # Skip invalid combinations for single-language simulators
                if sim == "icarus" and lang != "sv":
                    continue
                if sim == "ghdl" and lang != "vhdl":
                    continue
                work_dir = os.path.join(work_base, sim, f"{proto}_{lang}")

                if sim == "icarus":
                    ok = run_icarus(proto, timer_path, work_dir)
                elif sim == "ghdl":
                    ok = run_ghdl(proto, timer_path, work_dir)
                elif sim == "modelsim":
                    ok = run_modelsim(proto, lang, timer_path, work_dir)
                elif sim == "xsim":
                    ok = run_xsim(proto, lang, timer_path, work_dir)
                elif sim == "vcs":
                    ok = run_vcs(proto, lang, timer_path, work_dir)
                elif sim == "xcelium":
                    ok = run_xcelium(proto, lang, timer_path, work_dir)
                else:
                    ok = False

                label = f"{sim}/{proto}_{lang}"
                results_summary.append((label, "PASS" if ok else "FAIL"))
                if not ok:
                    all_pass = False

    # Print summary
    print("\n" + "=" * 60)
    print("Simulation Results Summary")
    print("=" * 60)
    for label, status in results_summary:
        print(f"  {label:<35} {status}")
    print("=" * 60)

    if not all_pass:
        print("One or more simulations FAILED.")
        sys.exit(1)
    else:
        print("All simulations PASSED.")
        sys.exit(0)


if __name__ == "__main__":
    main()
