#!/usr/bin/env python3
"""run_vendor_synth.py — Run Vivado and/or Quartus synthesis for bus_matrix.

Invokes each per-variant TCL script, captures output, parses reports,
and writes human-readable summaries.

Usage:
    source IP/interface/bus_matrix/setup.sh
    python3 $CLAUDE_BUS_MATRIX_PATH/synthesis/run_vendor_synth.py
    python3 $CLAUDE_BUS_MATRIX_PATH/synthesis/run_vendor_synth.py --vivado
    python3 $CLAUDE_BUS_MATRIX_PATH/synthesis/run_vendor_synth.py --quartus
    python3 $CLAUDE_BUS_MATRIX_PATH/synthesis/run_vendor_synth.py --clean
"""

import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


PROTOS = ["ahb", "axi", "wb"]


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
        return 1, "TIMEOUT after {timeout}s"
    except FileNotFoundError:
        return 1, f"Tool not found: {cmd[0]}"

    if logfile:
        with open(logfile, "w") as fh:
            fh.write(result.stdout)
    return result.returncode, result.stdout


def parse_vivado_utilization(rpt_path):
    """Parse Vivado utilization report for Slice LUTs and Slice Registers."""
    luts = "N/A"
    ffs = "N/A"
    bram = "0"
    dsp = "0"
    if not os.path.isfile(rpt_path):
        return luts, ffs, bram, dsp

    with open(rpt_path) as fh:
        content = fh.read()

    # Match "| Slice LUTs* | NNN |" style table rows (asterisk may be present)
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
    """Parse Vivado timing summary for WNS."""
    wns = "N/A"
    if not os.path.isfile(rpt_path):
        return wns

    with open(rpt_path) as fh:
        content = fh.read()

    # Match the per-clock PCLK row: "PCLK   7.639   0.000  ..."
    m = re.search(r"^PCLK\s+([-\d.]+)", content, re.MULTILINE)
    if m:
        wns = m.group(1)

    return wns


def parse_quartus_map_report(rpt_path):
    """Parse Quartus map report for Total registers."""
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

    # Write report
    report_path = os.path.join(synth_dir, "report.txt")
    with open(report_path, "w") as fh:
        fh.write("Vivado Synthesis Report — bus_matrix (Zynq-7010 xc7z010clg400-1)\n")
        fh.write("=" * 70 + "\n\n")
        fh.write(f"{'Variant':<10} {'LUTs':<8} {'FFs':<8} {'BRAM':<6} {'DSP':<6} {'WNS':<10} {'Result'}\n")
        fh.write("-" * 60 + "\n")
        for r in results:
            fh.write(f"{r['variant']:<10} {r['luts']:<8} {r['ffs']:<8} {r['bram']:<6} {r['dsp']:<6} {r['wns']:<10} {r['status']}\n")

    return all_pass, results


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

        # Find the map report
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

    # Write report
    report_path = os.path.join(synth_dir, "report.txt")
    with open(report_path, "w") as fh:
        fh.write("Quartus Synthesis Report — bus_matrix (Cyclone V SE 5CSEMA4U23C6)\n")
        fh.write("=" * 60 + "\n\n")
        fh.write(f"{'Variant':<10} {'Registers':<12} {'Result'}\n")
        fh.write("-" * 35 + "\n")
        for r in results:
            fh.write(f"{r['variant']:<10} {r['registers']:<12} {r['status']}\n")

    return all_pass, results


def clean(ip_path):
    """Remove synthesis work directories."""
    for subdir in ["vivado/work", "quartus/work", "yosys/work"]:
        d = os.path.join(ip_path, "synthesis", subdir)
        if os.path.isdir(d):
            shutil.rmtree(d)
            print(f"  Removed {d}")
    # Remove Vivado journal/log files from CWD
    for pattern in ["vivado*.log", "vivado*.jou", ".Xil"]:
        for f in glob.glob(os.path.join(ip_path, pattern)):
            if os.path.isfile(f):
                os.remove(f)
            elif os.path.isdir(f):
                shutil.rmtree(f)


def main():
    ip_path = os.environ.get("CLAUDE_BUS_MATRIX_PATH")
    if not ip_path:
        print("ERROR: CLAUDE_BUS_MATRIX_PATH is not set.")
        print("       Please run:  source IP/interface/bus_matrix/setup.sh")
        sys.exit(1)

    ip_path = str(Path(ip_path).resolve())

    parser = argparse.ArgumentParser(description="Run vendor synthesis for bus_matrix")
    parser.add_argument("--vivado", action="store_true", help="Run Vivado only")
    parser.add_argument("--quartus", action="store_true", help="Run Quartus only")
    parser.add_argument("--clean", action="store_true", help="Remove work directories")
    args = parser.parse_args()

    if args.clean:
        clean(ip_path)
        print("Clean complete.")
        sys.exit(0)

    # Default: run both if neither flag given
    run_vivado_flag = args.vivado or (not args.vivado and not args.quartus)
    run_quartus_flag = args.quartus or (not args.vivado and not args.quartus)

    overall = True

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
    if overall:
        print("VENDOR SYNTHESIS PASSED")
    else:
        print("VENDOR SYNTHESIS FAILED")
    print("=" * 50)

    sys.exit(0 if overall else 1)


if __name__ == "__main__":
    main()
