#!/usr/bin/env python3
"""sim_bus_matrix.py — Simulation runner for bus_matrix IP.

Supports Icarus Verilog (SV), GHDL (VHDL), Vivado xsim (SV), ModelSim,
Synopsys VCS MX (SV+VHDL), and Cadence Xcelium (SV+VHDL).

On *.csun.edu only VCS and Xcelium are available; Icarus, GHDL, ModelSim,
and xsim are rejected with a clear error on that host.

Writes verification/work/<sim>/<proto>_<lang>/results.log with PASS or FAIL.
"""

import argparse
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Host detection
# ---------------------------------------------------------------------------
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

# Simulators that are not available on csun.edu
_CSUN_BLOCKED = {"icarus", "ghdl", "modelsim", "xsim"}


def run_cmd(cmd, cwd=None, logfile=None, timeout=None):
    """Run a shell command, tee output to logfile, return (returncode, stdout+stderr)."""
    print(f"  CMD: {' '.join(cmd)}")
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
        )
    except FileNotFoundError:
        output = f"ERROR: {cmd[0]} not found on PATH\n"
        if logfile:
            with open(logfile, "a") as fh:
                fh.write(output)
        return 127, output
    except subprocess.TimeoutExpired:
        output = f"ERROR: {cmd[0]} timed out after {timeout}s\n"
        if logfile:
            with open(logfile, "a") as fh:
                fh.write(output)
        return 124, output
    output = result.stdout
    if logfile:
        with open(logfile, "a") as fh:
            fh.write(output)
    return result.returncode, output


def check_pass(output, proto):
    """Return True if the output contains the expected PASS banner."""
    pass_token = f"PASS tb_bus_matrix_{proto}"
    fail_token  = "FAIL"
    fatal_token = "FATAL_ERROR"
    if pass_token in output:
        # Ensure no FAIL or FATAL_ERROR appears before the PASS
        pass_pos  = output.find(pass_token)
        fail_pos  = output.find(fail_token)
        fatal_pos = output.find(fatal_token)
        if fail_pos != -1 and fail_pos < pass_pos:
            return False
        if fatal_pos != -1 and fatal_pos < pass_pos:
            return False
        return True
    return False


def run_icarus_sv(ip_path, common_path, proto, run_dir):
    """Run Icarus Verilog SV simulation for the given protocol."""
    rtl_dir   = os.path.join(ip_path, "design", "rtl", "verilog")
    tb_dir    = os.path.join(ip_path, "verification", "testbench")
    tests_dir = os.path.join(ip_path, "verification", "tests")
    tasks_dir = os.path.join(common_path, "verification", "tasks")
    ctests_dir = os.path.join(common_path, "verification", "tests")

    out_bin = os.path.join(run_dir, f"tb_bus_matrix_{proto}.vvp")
    log_file = os.path.join(run_dir, "compile.log")

    # Collect RTL sources in dependency order
    rtl_srcs = [
        os.path.join(rtl_dir, "bus_matrix_decoder.sv"),
        os.path.join(rtl_dir, "bus_matrix_arb.sv"),
        os.path.join(rtl_dir, "bus_matrix_core.sv"),
    ]

    # Protocol-specific interface source
    if proto == "ahb":
        rtl_srcs.append(os.path.join(rtl_dir, "bus_matrix_ahb.sv"))
        bfm_srcs = [
            os.path.join(tb_dir, "bus_matrix_ahb_master.sv"),
            os.path.join(tb_dir, "bus_matrix_ahb_slave.sv"),
        ]
        tb_src = os.path.join(tb_dir, "tb_bus_matrix_ahb.sv")
    elif proto == "axi":
        rtl_srcs.append(os.path.join(rtl_dir, "bus_matrix_axi.sv"))
        bfm_srcs = [
            os.path.join(tb_dir, "bus_matrix_axi_master.sv"),
            os.path.join(tb_dir, "bus_matrix_axi_slave.sv"),
        ]
        tb_src = os.path.join(tb_dir, "tb_bus_matrix_axi.sv")
    else:  # wb
        rtl_srcs.append(os.path.join(rtl_dir, "bus_matrix_wb.sv"))
        bfm_srcs = [
            os.path.join(tb_dir, "bus_matrix_wb_master.sv"),
            os.path.join(tb_dir, "bus_matrix_wb_slave.sv"),
        ]
        tb_src = os.path.join(tb_dir, "tb_bus_matrix_wb.sv")

    compile_cmd = [
        "iverilog",
        "-g2012",
        f"-I{tasks_dir}",
        f"-I{ctests_dir}",
        f"-I{tests_dir}",
        f"-I{tb_dir}",
        "-o", out_bin,
    ]

    compile_cmd.extend(rtl_srcs + bfm_srcs + [tb_src])

    # Clear log
    open(log_file, "w").close()
    rc, out = run_cmd(compile_cmd, cwd=run_dir, logfile=log_file)
    if rc != 0:
        return False, f"Compile FAILED:\n{out}"

    # Run simulation
    sim_log = os.path.join(run_dir, "sim.log")
    open(sim_log, "w").close()
    rc, out = run_cmd(["vvp", out_bin], cwd=run_dir, logfile=sim_log)
    return check_pass(out, proto), out


def run_ghdl_vhdl(ip_path, common_path, proto, run_dir):
    """Run GHDL VHDL simulation for the given protocol."""
    rtl_vhdl_dir = os.path.join(ip_path, "design", "rtl", "vhdl")
    tb_dir       = os.path.join(ip_path, "verification", "testbench")
    common_rtl_vhdl = os.path.join(common_path, "design", "rtl", "vhdl")
    common_tests_vhdl = os.path.join(common_path, "verification", "tests")

    log_file = os.path.join(run_dir, "ghdl.log")
    open(log_file, "w").close()

    # VHDL source files in compile order
    vhdl_srcs = []

    # Common ip_test_pkg
    pkg_file = os.path.join(common_tests_vhdl, "ip_test_pkg.vhd")
    if os.path.isfile(pkg_file):
        vhdl_srcs.append(pkg_file)

    # RTL VHDL sources (no interface or regfile needed — config via generics)
    rtl_order = [
        "bus_matrix_decoder.vhd",
        "bus_matrix_arb.vhd",
        "bus_matrix_core.vhd",
        f"bus_matrix_{proto}.vhd",
    ]

    for fn in rtl_order:
        fp = os.path.join(rtl_vhdl_dir, fn)
        if os.path.isfile(fp):
            vhdl_srcs.append(fp)

    tb_file = os.path.join(tb_dir, f"tb_bus_matrix_{proto}.vhd")
    if os.path.isfile(tb_file):
        vhdl_srcs.append(tb_file)
    else:
        return False, f"VHDL testbench not found: {tb_file}"

    # Analyze all sources
    all_out = ""
    for src in vhdl_srcs:
        rc, out = run_cmd(
            ["ghdl", "-a", "--std=08", "-frelaxed", src],
            cwd=run_dir,
            logfile=log_file,
        )
        all_out += out
        if rc != 0:
            return False, f"GHDL analyze FAILED for {src}:\n{out}"

    # Elaborate
    tb_name = f"tb_bus_matrix_{proto}"
    rc, out = run_cmd(
        ["ghdl", "-e", "--std=08", "-frelaxed", tb_name],
        cwd=run_dir,
        logfile=log_file,
    )
    all_out += out
    if rc != 0:
        return False, f"GHDL elaborate FAILED:\n{out}"

    # Run
    rc, out = run_cmd(
        ["ghdl", "-r", "--std=08", "-frelaxed", tb_name, "--stop-time=1ms"],
        cwd=run_dir,
        logfile=log_file,
    )
    all_out += out
    return check_pass(all_out, proto), all_out


def run_modelsim(ip_path, common_path, proto, lang, run_dir):
    """Run ModelSim simulation using .do files."""
    import shutil
    vsim = shutil.which("vsim")
    if not vsim:
        return True, "Skipped: vsim not found on PATH"

    modelsim_dir = os.path.join(ip_path, "verification", "modelsim")

    if lang == "sv":
        do_file = os.path.join(modelsim_dir, f"sim_bus_matrix_{proto}.do")
    else:
        # VHDL .do files — check if they exist
        do_file = os.path.join(modelsim_dir, f"sim_bus_matrix_{proto}_vhdl.do")

    if not os.path.isfile(do_file):
        return True, f"Skipped: {do_file} not found"

    log_file = os.path.join(run_dir, "modelsim.log")
    open(log_file, "w").close()
    rc, out = run_cmd(
        ["vsim", "-batch", "-do", do_file],
        cwd=modelsim_dir,
        logfile=log_file,
    )
    return check_pass(out, proto), out


def run_xsim_sv(ip_path, common_path, proto, run_dir):
    """Run Vivado xsim SV simulation for the given protocol."""
    rtl_dir   = os.path.join(ip_path, "design", "rtl", "verilog")
    tb_dir    = os.path.join(ip_path, "verification", "testbench")
    tests_dir = os.path.join(ip_path, "verification", "tests")
    tasks_dir = os.path.join(common_path, "verification", "tasks")
    ctests_dir = os.path.join(common_path, "verification", "tests")

    top_mod = f"tb_bus_matrix_{proto}"

    # RTL sources in dependency order
    rtl_srcs = [
        os.path.join(rtl_dir, "bus_matrix_decoder.sv"),
        os.path.join(rtl_dir, "bus_matrix_arb.sv"),
        os.path.join(rtl_dir, "bus_matrix_core.sv"),
        os.path.join(rtl_dir, f"bus_matrix_{proto}.sv"),
    ]

    # BFM sources
    bfm_srcs = [
        os.path.join(tb_dir, f"bus_matrix_{proto}_master.sv"),
        os.path.join(tb_dir, f"bus_matrix_{proto}_slave.sv"),
    ]

    tb_src = os.path.join(tb_dir, f"{top_mod}.sv")
    all_srcs = rtl_srcs + bfm_srcs + [tb_src]

    log_file = os.path.join(run_dir, "xvlog.log")
    open(log_file, "w").close()

    # Step 1: xvlog — compile all SV sources
    xvlog_cmd = [
        "xvlog", "--sv",
        "--include", tasks_dir,
        "--include", ctests_dir,
        "--include", tests_dir,
        "--include", tb_dir,
    ] + all_srcs

    rc, out = run_cmd(xvlog_cmd, cwd=run_dir, logfile=log_file)
    if rc != 0:
        return False, f"xvlog FAILED:\n{out}"

    # Step 2: xelab — elaborate
    elab_log = os.path.join(run_dir, "xelab.log")
    open(elab_log, "w").close()
    elab_cmd = [
        "xelab", top_mod,
        "-s", f"{top_mod}_sim",
        "--timescale", "1ns/1ps",
        "--debug", "off",
    ]

    rc, out = run_cmd(elab_cmd, cwd=run_dir, logfile=elab_log)
    if rc != 0:
        return False, f"xelab FAILED:\n{out}"

    # Step 3: xsim — run simulation
    sim_log = os.path.join(run_dir, "xsim.log")
    open(sim_log, "w").close()

    # Write a tcl command file to run all and quit
    tcl_file = os.path.join(run_dir, "run.tcl")
    with open(tcl_file, "w") as fh:
        fh.write("run all\nquit\n")

    sim_cmd = [
        "xsim", f"{top_mod}_sim",
        "--tclbatch", tcl_file,
    ]

    rc, out = run_cmd(sim_cmd, cwd=run_dir, logfile=sim_log)
    return check_pass(out, proto), out


def _vhdl_srcs(ip_path, common_path, proto):
    """Return the ordered list of VHDL source files for the given protocol."""
    rtl_vhdl_dir = os.path.join(ip_path, "design", "rtl", "vhdl")
    tb_dir = os.path.join(ip_path, "verification", "testbench")
    common_tests_vhdl = os.path.join(common_path, "verification", "tests")

    srcs = []
    pkg_file = os.path.join(common_tests_vhdl, "ip_test_pkg.vhd")
    if os.path.isfile(pkg_file):
        srcs.append(pkg_file)

    rtl_order = [
        "bus_matrix_decoder.vhd",
        "bus_matrix_arb.vhd",
        "bus_matrix_core.vhd",
        f"bus_matrix_{proto}.vhd",
    ]
    for fn in rtl_order:
        fp = os.path.join(rtl_vhdl_dir, fn)
        if os.path.isfile(fp):
            srcs.append(fp)

    return srcs, os.path.join(tb_dir, f"tb_bus_matrix_{proto}.vhd")


def run_vcs(ip_path, common_path, proto, lang, run_dir):
    """Compile and simulate with Synopsys VCS MX. Returns (passed, output).

    SV flow  (2 steps): vcs -full64 -sverilog ... <sv-files> -o simv ; ./simv
    VHDL flow (3 steps): vhdlan -full64 -vhdl08 <vhd-files> ;
                          vcs -full64 <tb_top> -o simv (elaborate) ; ./simv
    """
    rtl_dir = os.path.join(ip_path, "design", "rtl", "verilog")
    tb_dir  = os.path.join(ip_path, "verification", "testbench")
    tests_dir = os.path.join(ip_path, "verification", "tests")
    tasks_dir = os.path.join(common_path, "verification", "tasks")
    ctests_dir = os.path.join(common_path, "verification", "tests")

    tb_top = f"tb_bus_matrix_{proto}"
    simv = os.path.join(run_dir, f"simv_{proto}_{lang}")

    if lang == "sv":
        rtl_srcs = [
            os.path.join(rtl_dir, "bus_matrix_decoder.sv"),
            os.path.join(rtl_dir, "bus_matrix_arb.sv"),
            os.path.join(rtl_dir, "bus_matrix_core.sv"),
            os.path.join(rtl_dir, f"bus_matrix_{proto}.sv"),
        ]
        bfm_srcs = [
            os.path.join(tb_dir, f"bus_matrix_{proto}_master.sv"),
            os.path.join(tb_dir, f"bus_matrix_{proto}_slave.sv"),
        ]
        tb_src = os.path.join(tb_dir, f"{tb_top}.sv")

        incdirs = [tasks_dir, ctests_dir, tests_dir, tb_dir]
        incflag = "+incdir+" + "+".join(incdirs)

        log_file = os.path.join(run_dir, "compile.log")
        open(log_file, "w").close()
        compile_cmd = (
            ["vcs", "-full64", "-sverilog", "-timescale=1ns/1ps", "-debug_acc+all", incflag]
            + rtl_srcs + bfm_srcs + [tb_src]
            + ["-o", simv]
        )
        rc, out = run_cmd(compile_cmd, cwd=run_dir, logfile=log_file, timeout=180)
        if rc != 0:
            return False, f"vcs compile FAILED:\n{out}"
    else:  # vhdl
        vhdl_srcs, tb_file = _vhdl_srcs(ip_path, common_path, proto)
        if not os.path.isfile(tb_file):
            return False, f"VHDL testbench not found: {tb_file}"
        vhdl_srcs = vhdl_srcs + [tb_file]

        log_file = os.path.join(run_dir, "vhdlan.log")
        open(log_file, "w").close()
        vhdlan_cmd = ["vhdlan", "-full64", "-vhdl08"] + vhdl_srcs
        rc, out = run_cmd(vhdlan_cmd, cwd=run_dir, logfile=log_file, timeout=180)
        if rc != 0:
            return False, f"vhdlan FAILED:\n{out}"

        elab_log = os.path.join(run_dir, "elab.log")
        open(elab_log, "w").close()
        elab_cmd = ["vcs", "-full64", "-debug_acc+all", tb_top, "-o", simv]
        rc, out = run_cmd(elab_cmd, cwd=run_dir, logfile=elab_log, timeout=180)
        if rc != 0:
            return False, f"vcs elaborate FAILED:\n{out}"

    sim_log = os.path.join(run_dir, "sim.log")
    open(sim_log, "w").close()
    rc, out = run_cmd([simv], cwd=run_dir, logfile=sim_log, timeout=120)
    return check_pass(out, proto), out


def run_xcelium(ip_path, common_path, proto, lang, run_dir):
    """Compile, elaborate, and simulate with Cadence Xcelium. Returns (passed, output).

    SV flow  (1 step): xrun -64 -access +rwc -timescale 1ns/1ps -sv +incdir+... <files> -top <tb_top>
    VHDL flow (3 steps): xmvhdl -V200X <vhd-files> ; xmelab <tb_top> ; xmsim <tb_top>

    VHDL has no PLI hook like SV's $shm_open/$shm_probe, so the SHM waveform
    database is opened via an inline xmsim command script instead (dumped to
    waves.shm/ in the sim work directory).
    """
    rtl_dir = os.path.join(ip_path, "design", "rtl", "verilog")
    tb_dir  = os.path.join(ip_path, "verification", "testbench")
    tests_dir = os.path.join(ip_path, "verification", "tests")
    tasks_dir = os.path.join(common_path, "verification", "tasks")
    ctests_dir = os.path.join(common_path, "verification", "tests")

    tb_top = f"tb_bus_matrix_{proto}"

    if lang == "sv":
        rtl_srcs = [
            os.path.join(rtl_dir, "bus_matrix_decoder.sv"),
            os.path.join(rtl_dir, "bus_matrix_arb.sv"),
            os.path.join(rtl_dir, "bus_matrix_core.sv"),
            os.path.join(rtl_dir, f"bus_matrix_{proto}.sv"),
        ]
        bfm_srcs = [
            os.path.join(tb_dir, f"bus_matrix_{proto}_master.sv"),
            os.path.join(tb_dir, f"bus_matrix_{proto}_slave.sv"),
        ]
        tb_src = os.path.join(tb_dir, f"{tb_top}.sv")

        incdirs = [tasks_dir, ctests_dir, tests_dir, tb_dir]
        incflag = "+incdir+" + "+".join(incdirs)

        log_file = os.path.join(run_dir, "sim.log")
        open(log_file, "w").close()
        xrun_cmd = (
            ["xrun", "-64", "-access", "+rwc", "-timescale", "1ns/1ps",
             "-work", "work", "-sv", incflag]
            + rtl_srcs + bfm_srcs + [tb_src]
            + ["-top", tb_top]
        )
        rc, out = run_cmd(xrun_cmd, cwd=run_dir, logfile=log_file, timeout=180)
        if rc != 0:
            return False, f"xrun FAILED:\n{out}"
        return check_pass(out, proto), out

    else:  # vhdl
        vhdl_srcs, tb_file = _vhdl_srcs(ip_path, common_path, proto)
        if not os.path.isfile(tb_file):
            return False, f"VHDL testbench not found: {tb_file}"
        vhdl_srcs = vhdl_srcs + [tb_file]

        # Step 1: xmvhdl — VHDL-2008 analysis (-WORK must be uppercase)
        log_file = os.path.join(run_dir, "xmvhdl.log")
        open(log_file, "w").close()
        vhdl_cmd = ["xmvhdl", "-64", "-WORK", "work", "-V200X", "-INC_V200X_PKG"] + vhdl_srcs
        rc, out = run_cmd(vhdl_cmd, cwd=run_dir, logfile=log_file, timeout=180)
        if rc != 0:
            return False, f"xmvhdl FAILED:\n{out}"

        # Step 2: xmelab — elaborate
        elab_log = os.path.join(run_dir, "elab.log")
        open(elab_log, "w").close()
        elab_cmd = ["xmelab", "-64", "-access", "+rwc", tb_top]
        rc, out = run_cmd(elab_cmd, cwd=run_dir, logfile=elab_log, timeout=180)
        if rc != 0:
            return False, f"xmelab FAILED:\n{out}"

        # Step 3: xmsim — simulate, dumping waves.shm/ via an inline command script
        sim_log = os.path.join(run_dir, "sim.log")
        open(sim_log, "w").close()
        shm_cmd = ("@database -open waves -shm -default; "
                   "probe -database waves -create / -all -depth all; "
                   "run; exit")
        sim_cmd = ["xmsim", "-64", "-input", shm_cmd, tb_top]
        rc, out = run_cmd(sim_cmd, cwd=run_dir, logfile=sim_log, timeout=120)
        return check_pass(out, proto), out


def main():
    ip_path = os.environ.get("CLAUDE_BUS_MATRIX_PATH")
    if not ip_path:
        print("ERROR: CLAUDE_BUS_MATRIX_PATH is not set.")
        print("       Please run:  source IP/interface/bus_matrix/setup.sh")
        sys.exit(1)

    ip_path = str(Path(ip_path).resolve())
    common_path = os.environ.get(
        "IP_COMMON_PATH",
        str(Path(ip_path).parent.parent / "common"),
    )
    common_path = str(Path(common_path).resolve())

    parser = argparse.ArgumentParser(description="Run bus_matrix simulations")
    parser.add_argument(
        "--proto",
        choices=["ahb", "axi", "wb", "all"],
        default="all",
        help="Bus protocol variant to simulate (default: all)",
    )
    parser.add_argument(
        "--lang",
        choices=["sv", "vhdl", "all"],
        default="all",
        help="HDL language to simulate (default: all)",
    )
    parser.add_argument(
        "--sim",
        choices=["icarus", "ghdl", "xsim", "modelsim", "vcs", "xcelium", "all"],
        default=None,
        help="Simulator to use. On *.csun.edu only vcs and xcelium are "
             "available. 'all' selects icarus+ghdl+xsim+modelsim on standard "
             "hosts and vcs+xcelium on csun.edu. (default: icarus on "
             "standard hosts, vcs on csun.edu)",
    )
    parser.add_argument(
        "--test",
        default=None,
        help="Name of a specific test (informational only; all tests run by default)",
    )
    args = parser.parse_args()

    sim_arg = args.sim
    if sim_arg is None:
        sim_arg = "vcs" if ON_CSUN else "icarus"

    if ON_CSUN and sim_arg in _CSUN_BLOCKED:
        print(f"ERROR: --sim {sim_arg} is not available on *.csun.edu.")
        print("       Use --sim vcs or --sim xcelium on this host.")
        sys.exit(1)

    protos = ["ahb", "axi", "wb"] if args.proto == "all" else [args.proto]
    langs  = ["sv", "vhdl"]       if args.lang  == "all" else [args.lang]
    if sim_arg == "all":
        sims = ["vcs", "xcelium"] if ON_CSUN else ["icarus", "ghdl", "xsim", "modelsim"]
    else:
        sims = [sim_arg]

    work_base = os.path.join(ip_path, "verification", "work")
    overall_pass = True

    for sim in sims:
        for proto in protos:
            for lang in langs:
                run_dir = os.path.join(work_base, sim, f"{proto}_{lang}")
                os.makedirs(run_dir, exist_ok=True)
                result_log = os.path.join(run_dir, "results.log")

                print(f"\n[{sim}/{proto}_{lang}] Running...")
                t0 = time.time()

                passed = False
                detail = ""

                if sim == "icarus" and lang == "sv":
                    passed, detail = run_icarus_sv(ip_path, common_path, proto, run_dir)
                elif sim == "ghdl" and lang == "vhdl":
                    passed, detail = run_ghdl_vhdl(ip_path, common_path, proto, run_dir)
                elif sim == "xsim" and lang == "sv":
                    passed, detail = run_xsim_sv(ip_path, common_path, proto, run_dir)
                elif sim == "modelsim":
                    passed, detail = run_modelsim(ip_path, common_path, proto, lang, run_dir)
                elif sim == "vcs":
                    passed, detail = run_vcs(ip_path, common_path, proto, lang, run_dir)
                elif sim == "xcelium":
                    passed, detail = run_xcelium(ip_path, common_path, proto, lang, run_dir)
                else:
                    # Unsupported combination (e.g. icarus+vhdl, ghdl+sv, xsim+vhdl)
                    detail = f"Skipped: {sim} does not support {lang}"
                    passed = True  # skip counts as pass (not a failure)

                elapsed = time.time() - t0
                if detail.startswith("Skipped:"):
                    status = "SKIP"
                else:
                    status = "PASS" if passed else "FAIL"

                with open(result_log, "w") as fh:
                    fh.write(f"{status}\n")
                    fh.write(f"# sim={sim} proto={proto} lang={lang}\n")
                    fh.write(f"# elapsed={elapsed:.1f}s\n")
                    if detail:
                        fh.write(f"# {detail[:200]}\n")

                print(f"[{sim}/{proto}_{lang}] {status}  ({elapsed:.1f}s)")
                print(f"  result: {result_log}")

                if not passed:
                    overall_pass = False

    print("\n" + "=" * 60)
    if overall_pass:
        print("ALL SIMULATIONS PASSED")
    else:
        print("ONE OR MORE SIMULATIONS FAILED")
    print("=" * 60)

    sys.exit(0 if overall_pass else 1)


if __name__ == "__main__":
    main()
