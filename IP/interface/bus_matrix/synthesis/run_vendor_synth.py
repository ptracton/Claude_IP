#!/usr/bin/env python3
"""run_vendor_synth.py — Run synthesis for bus_matrix IP.

Standard hosts (not ecs-vdi): Vivado + Quartus + Yosys.
ecs-vdi.ecs.csun.edu: Design Compiler with SAED90/SAED32/SAED14 PDKs.

Usage:
    source IP/interface/bus_matrix/setup.sh
    cd $CLAUDE_BUS_MATRIX_PATH

    # Standard hosts
    python3 synthesis/run_vendor_synth.py              # Vivado + Quartus
    python3 synthesis/run_vendor_synth.py --vivado
    python3 synthesis/run_vendor_synth.py --quartus
    python3 synthesis/run_vendor_synth.py --clean

    # ecs-vdi
    python3 synthesis/run_vendor_synth.py              # all three PDKs
    python3 synthesis/run_vendor_synth.py --dc         # all three PDKs
    python3 synthesis/run_vendor_synth.py --dc90
    python3 synthesis/run_vendor_synth.py --dc32
    python3 synthesis/run_vendor_synth.py --dc14
"""

import argparse
import glob
import os
import re
import shutil
import socket
import subprocess
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Host detection
# ---------------------------------------------------------------------------

ON_ECS_VDI = socket.getfqdn() == "ecs-vdi.ecs.csun.edu"

PROTOS = ["ahb", "axi", "wb"]

# ---------------------------------------------------------------------------
# PDK configuration (ecs-vdi only)
# ---------------------------------------------------------------------------

SAED90_PDK = "/opt/ECE_Lib/SAED90nm_EDK_10072017/SAED90_EDK/SAED_EDK90nm"
SAED32_EDK = "/opt/ECE_Lib/SAED32_EDK"
SAED14_EDK = "/opt/ECE_Lib/SAED14nm_EDK_03_2025"

PDK_CONFIGS = {
    "saed90": {"label": "SAED90 (90nm)", "env_var": "SAED90_PDK", "path": SAED90_PDK},
    "saed32": {"label": "SAED32 (32nm)", "env_var": "SAED32_EDK", "path": SAED32_EDK},
    "saed14": {"label": "SAED14 (14nm)", "env_var": "SAED14_EDK", "path": SAED14_EDK},
}

# ---------------------------------------------------------------------------
# Files cleaned by --clean (Design Compiler artefacts inside designcompiler/)
# ---------------------------------------------------------------------------

DESIGNCOMPILER_CLEAN_DIRS = [
    "cksum_dir", "reports", "netlists", "ARCH", "ENTI", "PACK",
]

DESIGNCOMPILER_CLEAN_FILES = [
    "command.log", "default.svf",
    "dc_saed90_run.log", "dc_saed32_run.log", "dc_saed14_run.log",
    "report_saed90.txt", "report_saed32.txt", "report_saed14.txt",
]

DESIGNCOMPILER_CLEAN_GLOBS = [
    "*.v", "*.sdf", "*.pvk", "*.pvl", "*.syn", "*.mr",
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def run_cmd(cmd, cwd=None, logfile=None, timeout=600):
    """Run a command, optionally save output to logfile, return (rc, output)."""
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
    except subprocess.TimeoutExpired:
        return 1, f"TIMEOUT after {timeout}s"
    except FileNotFoundError:
        return 1, f"Tool not found: {cmd[0]}"

    if logfile:
        with open(logfile, "w") as fh:
            fh.write(result.stdout)
    return result.returncode, result.stdout


# ---------------------------------------------------------------------------
# Design Compiler (ecs-vdi only)
# ---------------------------------------------------------------------------

def run_design_compiler(synth_dir, pdk_target):
    """Run dc_shell for a single PDK target. Return (rc, output)."""
    cfg = PDK_CONFIGS[pdk_target]
    dc_dir = os.path.join(synth_dir, "designcompiler")
    tcl_file = os.path.join(dc_dir, "synth.tcl")
    log_file = os.path.join(dc_dir, f"dc_{pdk_target}_run.log")

    env = os.environ.copy()
    env["PDK_TARGET"] = pdk_target
    env[cfg["env_var"]] = cfg["path"]

    print(f"  CMD: dc_shell -f {tcl_file}  [PDK_TARGET={pdk_target}]")
    try:
        result = subprocess.run(
            ["dc_shell", "-f", tcl_file],
            cwd=dc_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=1200,
            env=env,
        )
    except subprocess.TimeoutExpired:
        return 1, "TIMEOUT after 1200s"
    except FileNotFoundError:
        return 1, "Tool not found: dc_shell"

    with open(log_file, "w") as fh:
        fh.write(result.stdout)
    return result.returncode, result.stdout


def write_dc_report(synth_dir, pdk_target, rc):
    """Write a human-readable DC summary report."""
    cfg = PDK_CONFIGS[pdk_target]
    dc_dir = os.path.join(synth_dir, "designcompiler")
    report_path = os.path.join(dc_dir, f"report_{pdk_target}.txt")

    variants = [f"bus_matrix_{p}" for p in PROTOS]
    status = "PASS" if rc == 0 else "FAIL"

    with open(report_path, "w") as fh:
        fh.write(f"Design Compiler Synthesis Report — bus_matrix ({cfg['label']})\n")
        fh.write("=" * 65 + "\n\n")
        fh.write(f"Overall status : {status}\n")
        fh.write(f"Log            : designcompiler/dc_{pdk_target}_run.log\n\n")
        fh.write(f"Area reports   : designcompiler/reports/{pdk_target}/<variant>_area.rpt\n")
        fh.write(f"Timing reports : designcompiler/reports/{pdk_target}/<variant>_timing.rpt\n")
        fh.write(f"Netlists       : designcompiler/netlists/{pdk_target}/<variant>.v\n\n")
        fh.write(f"{'Variant':<22} {'Lang':<6} {'Result'}\n")
        fh.write("-" * 40 + "\n")
        for v in variants:
            fh.write(f"{v:<22} {'SV':<6} {status}\n")
            fh.write(f"{v}_vhdl        {'VHDL':<6} {status}\n")


def clean_design_compiler(synth_dir):
    """Remove all DC-generated outputs."""
    dc_dir = os.path.join(synth_dir, "designcompiler")
    if not os.path.isdir(dc_dir):
        return
    for d in DESIGNCOMPILER_CLEAN_DIRS:
        p = os.path.join(dc_dir, d)
        if os.path.isdir(p):
            shutil.rmtree(p)
            print(f"  Removed {p}")
    for f in DESIGNCOMPILER_CLEAN_FILES:
        p = os.path.join(dc_dir, f)
        if os.path.isfile(p):
            os.remove(p)
            print(f"  Removed {p}")
    for pattern in DESIGNCOMPILER_CLEAN_GLOBS:
        for p in glob.glob(os.path.join(dc_dir, pattern)):
            if os.path.isfile(p):
                os.remove(p)
                print(f"  Removed {p}")


# ---------------------------------------------------------------------------
# Vivado
# ---------------------------------------------------------------------------

def parse_vivado_utilization(rpt_path):
    luts = "N/A"
    ffs = "N/A"
    bram = "0"
    dsp = "0"
    if not os.path.isfile(rpt_path):
        return luts, ffs, bram, dsp

    with open(rpt_path) as fh:
        content = fh.read()

    m = re.search(r"\|\s*Slice LUTs\*?\s*\|\s*(\d+)\s*\|", content)
    if m:
        luts = m.group(1)

    m = re.search(r"\|\s*Slice Registers\s*\|\s*(\d+)\s*\|", content)
    if m:
        ffs = m.group(1)

    m = re.search(r"\|\s*Block RAM Tile\s*\|\s*([\d.]+)\s*\|", content)
    if m:
        bram = m.group(1)

    m = re.search(r"\|\s*DSPs\s*\|\s*(\d+)\s*\|", content)
    if m:
        dsp = m.group(1)

    return luts, ffs, bram, dsp


def parse_vivado_timing(rpt_path):
    wns = "N/A"
    if not os.path.isfile(rpt_path):
        return wns

    with open(rpt_path) as fh:
        content = fh.read()

    m = re.search(r"^CLK\s+([-\d.]+)", content, re.MULTILINE)
    if m:
        wns = m.group(1)

    return wns


def run_vivado(ip_path):
    """Run Vivado synthesis for all protocol variants."""
    synth_dir = os.path.join(ip_path, "synthesis", "vivado")
    work_dir = os.path.join(synth_dir, "work")
    os.makedirs(work_dir, exist_ok=True)

    all_pass = True
    results = []

    for proto in PROTOS:
        top = f"bus_matrix_{proto}"
        tcl_file = os.path.join(synth_dir, f"synth_{top}.tcl")
        log_file = os.path.join(work_dir, f"{top}_vivado.log")

        print(f"\n  [Vivado] Synthesizing {top}...")
        rc, out = run_cmd(
            ["vivado", "-mode", "batch", "-source", tcl_file],
            cwd=ip_path,
            logfile=log_file,
            timeout=600,
        )

        util_rpt = os.path.join(work_dir, f"{top}_utilization.rpt")
        timing_rpt = os.path.join(work_dir, f"{top}_timing_summary.rpt")
        luts, ffs, bram, dsp = parse_vivado_utilization(util_rpt)
        wns = parse_vivado_timing(timing_rpt)

        status = "PASS" if rc == 0 else "FAIL"
        if rc != 0:
            all_pass = False
            print(f"  [Vivado] {top}: FAIL (rc={rc})")
        else:
            print(f"  [Vivado] {top}: PASS  LUTs={luts} FFs={ffs} WNS={wns}ns")

        results.append({
            "variant": proto.upper(),
            "top": top,
            "luts": luts,
            "ffs": ffs,
            "bram": bram,
            "dsp": dsp,
            "wns": wns,
            "status": status,
        })

    report_path = os.path.join(synth_dir, "report.txt")
    with open(report_path, "w") as fh:
        fh.write("Vivado Synthesis Report — bus_matrix (Zynq-7010 xc7z010clg400-1)\n")
        fh.write("=" * 70 + "\n\n")
        fh.write(f"{'Variant':<10} {'LUTs':<8} {'FFs':<8} {'BRAM':<6} {'DSP':<6} {'WNS':<10} {'Result'}\n")
        fh.write("-" * 60 + "\n")
        for r in results:
            fh.write(f"{r['variant']:<10} {r['luts']:<8} {r['ffs']:<8} {r['bram']:<6} {r['dsp']:<6} {r['wns']:<10} {r['status']}\n")

    return all_pass, results


# ---------------------------------------------------------------------------
# Quartus
# ---------------------------------------------------------------------------

def parse_quartus_map_report(rpt_path):
    regs = "N/A"
    if not os.path.isfile(rpt_path):
        return regs

    with open(rpt_path) as fh:
        for line in fh:
            m = re.search(r"Total registers\s*[;:]\s*(\d+)", line)
            if m:
                regs = m.group(1)
                break

    return regs


def run_quartus(ip_path):
    """Run Quartus synthesis for all protocol variants."""
    synth_dir = os.path.join(ip_path, "synthesis", "quartus")
    work_dir = os.path.join(synth_dir, "work")
    os.makedirs(work_dir, exist_ok=True)

    all_pass = True
    results = []

    for proto in PROTOS:
        top = f"bus_matrix_{proto}"
        tcl_file = os.path.join(synth_dir, f"synth_{top}.tcl")
        log_file = os.path.join(work_dir, f"{top}_quartus.log")

        print(f"\n  [Quartus] Synthesizing {top}...")
        rc, out = run_cmd(
            ["quartus_sh", "-t", tcl_file],
            cwd=ip_path,
            logfile=log_file,
            timeout=600,
        )

        map_rpts = glob.glob(os.path.join(work_dir, top, "*.map.rpt"))
        regs = "N/A"
        if map_rpts:
            regs = parse_quartus_map_report(map_rpts[0])

        status = "PASS" if rc == 0 else "FAIL"
        if rc != 0:
            all_pass = False
            print(f"  [Quartus] {top}: FAIL (rc={rc})")
        else:
            print(f"  [Quartus] {top}: PASS  Registers={regs}")

        results.append({
            "variant": proto.upper(),
            "top": top,
            "registers": regs,
            "status": status,
        })

    report_path = os.path.join(synth_dir, "report.txt")
    with open(report_path, "w") as fh:
        fh.write("Quartus Synthesis Report — bus_matrix (Cyclone V SE 5CSEMA4U23C6)\n")
        fh.write("=" * 60 + "\n\n")
        fh.write(f"{'Variant':<10} {'Registers':<12} {'Result'}\n")
        fh.write("-" * 35 + "\n")
        for r in results:
            fh.write(f"{r['variant']:<10} {r['registers']:<12} {r['status']}\n")

    return all_pass, results


# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------

def clean(ip_path):
    """Remove synthesis work directories and DC artefacts."""
    synth_dir = os.path.join(ip_path, "synthesis")

    # Standard tool work dirs
    for subdir in ["vivado/work", "quartus/work", "yosys/work"]:
        d = os.path.join(synth_dir, subdir)
        if os.path.isdir(d):
            shutil.rmtree(d)
            print(f"  Removed {d}")

    # Vivado journal/log files
    for pattern in ["vivado*.log", "vivado*.jou", ".Xil"]:
        for f in glob.glob(os.path.join(ip_path, pattern)):
            if os.path.isfile(f):
                os.remove(f)
            elif os.path.isdir(f):
                shutil.rmtree(f)

    # DC artefacts
    clean_design_compiler(synth_dir)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ip_path = os.environ.get("CLAUDE_BUS_MATRIX_PATH")
    if not ip_path:
        print("ERROR: CLAUDE_BUS_MATRIX_PATH is not set.")
        print("       Please run:  source IP/interface/bus_matrix/setup.sh")
        sys.exit(1)

    ip_path = str(Path(ip_path).resolve())
    synth_dir = os.path.join(ip_path, "synthesis")

    parser = argparse.ArgumentParser(description="Run vendor synthesis for bus_matrix")

    if ON_ECS_VDI:
        parser.add_argument("--dc",   action="store_true", help="Run DC with all PDKs (default)")
        parser.add_argument("--dc90", action="store_true", help="Run DC with SAED90 only")
        parser.add_argument("--dc32", action="store_true", help="Run DC with SAED32 only")
        parser.add_argument("--dc14", action="store_true", help="Run DC with SAED14 only")
    else:
        parser.add_argument("--vivado",  action="store_true", help="Run Vivado only")
        parser.add_argument("--quartus", action="store_true", help="Run Quartus only")

    parser.add_argument("--clean", action="store_true", help="Remove work directories")
    args = parser.parse_args()

    if args.clean:
        clean(ip_path)
        print("Clean complete.")
        sys.exit(0)

    overall = True

    if ON_ECS_VDI:
        run_dc90 = args.dc or args.dc90 or not (args.dc90 or args.dc32 or args.dc14)
        run_dc32 = args.dc or args.dc32 or not (args.dc90 or args.dc32 or args.dc14)
        run_dc14 = args.dc or args.dc14 or not (args.dc90 or args.dc32 or args.dc14)

        if not shutil.which("dc_shell"):
            print("ERROR: dc_shell not found on PATH")
            sys.exit(1)

        for pdk, flag in [("saed90", run_dc90), ("saed32", run_dc32), ("saed14", run_dc14)]:
            if not flag:
                continue
            cfg = PDK_CONFIGS[pdk]
            print(f"\n=== Design Compiler Synthesis ({cfg['label']}) ===")
            rc, _ = run_design_compiler(synth_dir, pdk)
            write_dc_report(synth_dir, pdk, rc)
            if rc != 0:
                overall = False
                print(f"  [DC] {cfg['label']}: FAIL (rc={rc})")
            else:
                print(f"  [DC] {cfg['label']}: PASS")

    else:
        run_vivado_flag  = getattr(args, "vivado",  False) or not (getattr(args, "vivado",  False) or getattr(args, "quartus", False))
        run_quartus_flag = getattr(args, "quartus", False) or not (getattr(args, "vivado",  False) or getattr(args, "quartus", False))

        if run_vivado_flag:
            print("\n=== Vivado Synthesis (Zynq-7010) ===")
            if shutil.which("vivado"):
                passed, _ = run_vivado(ip_path)
                overall = overall and passed
            else:
                print("  SKIP: vivado not found on PATH")

        if run_quartus_flag:
            print("\n=== Quartus Synthesis (Cyclone V SE) ===")
            if shutil.which("quartus_sh"):
                passed, _ = run_quartus(ip_path)
                overall = overall and passed
            else:
                print("  SKIP: quartus_sh not found on PATH")

    print("\n" + "=" * 50)
    print("VENDOR SYNTHESIS PASSED" if overall else "VENDOR SYNTHESIS FAILED")
    print("=" * 50)

    sys.exit(0 if overall else 1)


if __name__ == "__main__":
    main()
