#!/usr/bin/env python3
"""run_vendor_synth.py — Run Vivado and Quartus synthesis for the Timer IP.

Usage:
    python3 synthesis/run_vendor_synth.py            # run both tools
    python3 synthesis/run_vendor_synth.py --vivado   # Vivado only
    python3 synthesis/run_vendor_synth.py --quartus  # Quartus only
    python3 synthesis/run_vendor_synth.py --clean            # clean all tool outputs
    python3 synthesis/run_vendor_synth.py --clean --vivado   # clean Vivado outputs only
    python3 synthesis/run_vendor_synth.py --clean --quartus  # clean Quartus outputs only

Requirements:
    - CLAUDE_TIMER_PATH set (source timer/setup.sh)
    - vivado on PATH (Vivado 2023.2)
    - quartus_sh on PATH (Quartus Prime)

Outputs:
    synthesis/vivado/utilization.rpt       — Vivado LUT/FF utilization
    synthesis/vivado/timing_summary.rpt    — Vivado timing summary
    synthesis/vivado/vivado_run.log        — raw Vivado output
    synthesis/vivado/report.txt            — human-readable summary
    synthesis/quartus/work/                — Quartus project files and map report
    synthesis/quartus/quartus_run.log      — raw Quartus output
    synthesis/quartus/report.txt           — human-readable summary
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path


# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------

VIVADO_CLEAN = [
    "vivado/utilization.rpt",
    "vivado/timing_summary.rpt",
    "vivado/vivado_run.log",
    "vivado/timer_apb_ooc.xdc",
    "vivado/report.txt",
]
VIVADO_CLEAN_DIRS = []   # Vivado in-memory — no project directory written

QUARTUS_CLEAN_DIRS = [
    "quartus/work",
    "quartus/db",
    "quartus/incremental_db",
]
QUARTUS_CLEAN = [
    "quartus/quartus_run.log",
    "quartus/timer_apb.sdc",
    "quartus/report.txt",
]


def clean_vivado(synth_dir: Path) -> None:
    print("=== Cleaning Vivado outputs ===")
    for rel in VIVADO_CLEAN:
        p = synth_dir / rel
        if p.exists():
            p.unlink()
            print(f"  removed {p.relative_to(synth_dir.parent)}")
    for rel in VIVADO_CLEAN_DIRS:
        p = synth_dir / rel
        if p.exists():
            shutil.rmtree(p)
            print(f"  removed {p.relative_to(synth_dir.parent)}/")
    print("=== Vivado clean complete ===")


def clean_quartus(synth_dir: Path) -> None:
    print("=== Cleaning Quartus outputs ===")
    for rel in QUARTUS_CLEAN:
        p = synth_dir / rel
        if p.exists():
            p.unlink()
            print(f"  removed {p.relative_to(synth_dir.parent)}")
    for rel in QUARTUS_CLEAN_DIRS:
        p = synth_dir / rel
        if p.exists():
            shutil.rmtree(p)
            print(f"  removed {p.relative_to(synth_dir.parent)}/")
    print("=== Quartus clean complete ===")


# ---------------------------------------------------------------------------
# Tool discovery
# ---------------------------------------------------------------------------

def find_tool(name: str) -> str | None:
    """Return the full path of a tool on PATH, or None."""
    return shutil.which(name)


# ---------------------------------------------------------------------------
# Vivado
# ---------------------------------------------------------------------------

def run_vivado(synth_dir: Path) -> bool:
    vivado = find_tool("vivado")
    if not vivado:
        print("  ERROR: vivado not found on PATH — is setup.sh sourced?")
        return False

    tcl = synth_dir / "vivado" / "synth.tcl"
    log = synth_dir / "vivado" / "vivado_run.log"

    print(f"  Tool    : {vivado}")
    print(f"  Script  : {tcl}")
    print(f"  Log     : {log}")

    cmd = [
        vivado, "-mode", "batch",
        "-source", str(tcl),
        "-nojournal", "-nolog",
    ]

    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=600,
            cwd=str(synth_dir / "vivado"),
        )
    except subprocess.TimeoutExpired:
        print("  ERROR: Vivado timed out after 600 s")
        return False

    log.write_text(result.stdout)

    if result.returncode != 0:
        print(f"  ERROR: Vivado exited with code {result.returncode}")
        print(f"         See {log} for details")
        # Print last 20 lines to help diagnose
        for line in result.stdout.splitlines()[-20:]:
            print(f"    {line}")
        return False

    return True


def parse_vivado_utilization(rpt_path: Path) -> dict:
    """Extract LUT and FF counts from a Vivado utilization report."""
    data = {"luts": "?", "ffs": "?", "bram": "0", "dsp": "0"}
    if not rpt_path.exists():
        return data

    text = rpt_path.read_text()

    # Match table rows like: | Slice LUTs*   |  152 |  0  | ...
    lut_m = re.search(r'\|\s*(?:Slice|CLB)\s+LUTs\*?\s*\|\s*(\d+)', text)
    ff_m  = re.search(r'\|\s*(?:Slice|CLB)\s+Registers\s*\|\s*(\d+)', text)
    br_m  = re.search(r'\|\s*Block RAM Tile\s*\|\s*(\d+)', text)
    ds_m  = re.search(r'\|\s*DSPs\s*\|\s*(\d+)', text)

    if lut_m: data["luts"] = lut_m.group(1)
    if ff_m:  data["ffs"]  = ff_m.group(1)
    if br_m:  data["bram"] = br_m.group(1)
    if ds_m:  data["dsp"]  = ds_m.group(1)

    return data


def parse_vivado_timing(rpt_path: Path) -> dict:
    """Extract WNS and clock period from a Vivado timing summary report."""
    data = {"wns": "?", "period": "10.000", "met": "?"}
    if not rpt_path.exists():
        return data

    text = rpt_path.read_text()

    # The per-clock table has a row like: "PCLK   6.162   0.000  ..."
    # Match clock name then the first numeric field (WNS)
    wns_m = re.search(r'PCLK\s+([-\d.]+)', text)
    if wns_m:
        wns = wns_m.group(1)
        data["wns"] = wns
        try:
            data["met"] = "MET" if float(wns) >= 0 else "VIOLATED"
        except ValueError:
            pass

    return data


def write_vivado_report(synth_dir: Path, util: dict, timing: dict) -> None:
    rpt_path = synth_dir / "vivado" / "report.txt"
    now = datetime.now().strftime("%Y-%m-%d")
    lines = [
        "=" * 72,
        "Vivado OOC Synthesis Report — timer_apb",
        f"Target device : xc7z010clg400-1 (Zynq-7010, CLG400, speed grade -1)",
        f"Board         : Zybo-Z7-10 (Digilent)",
        f"Tool version  : Vivado 2023.2",
        f"Clock target  : 100 MHz (10.000 ns period)",
        f"Run date      : {now}",
        "=" * 72,
        "",
        "STATUS: PASS — synthesis completed successfully.",
        "",
        "-" * 72,
        "Resource Utilization",
        "-" * 72,
        f"  Slice LUTs   : {util['luts']}",
        f"  Slice FFs    : {util['ffs']}",
        f"  Block RAMs   : {util['bram']}",
        f"  DSPs         : {util['dsp']}",
        "",
        "-" * 72,
        "Timing Summary (OOC — synthesis estimate)",
        "-" * 72,
        f"  Clock period : {timing['period']} ns  (100 MHz target)",
        f"  WNS          : {timing['wns']} ns",
        f"  Timing       : {timing['met']}",
        "",
        "Full reports:",
        "  synthesis/vivado/utilization.rpt",
        "  synthesis/vivado/timing_summary.rpt",
        "=" * 72,
    ]
    rpt_path.write_text("\n".join(lines) + "\n")
    print(f"  Report  : {rpt_path}")


# ---------------------------------------------------------------------------
# Quartus
# ---------------------------------------------------------------------------

def run_quartus(synth_dir: Path) -> bool:
    quartus_sh = find_tool("quartus_sh")
    if not quartus_sh:
        print("  ERROR: quartus_sh not found on PATH — is setup.sh sourced?")
        return False

    tcl = synth_dir / "quartus" / "synth.tcl"
    log = synth_dir / "quartus" / "quartus_run.log"

    print(f"  Tool    : {quartus_sh}")
    print(f"  Script  : {tcl}")
    print(f"  Log     : {log}")

    cmd = [quartus_sh, "-t", str(tcl)]

    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=600,
            cwd=str(synth_dir / "quartus"),
        )
    except subprocess.TimeoutExpired:
        print("  ERROR: Quartus timed out after 600 s")
        return False

    log.write_text(result.stdout)

    if result.returncode != 0:
        print(f"  ERROR: Quartus exited with code {result.returncode}")
        print(f"         See {log} for details")
        for line in result.stdout.splitlines()[-20:]:
            print(f"    {line}")
        return False

    return True


def find_quartus_map_rpt(synth_dir: Path) -> Path | None:
    """Find the map report generated by Quartus Analysis & Synthesis."""
    # Quartus writes to the work directory (not output_files/) when run via Tcl
    for p in (synth_dir / "quartus" / "work").rglob("*.map.rpt"):
        return p
    return None


def parse_quartus_utilization(rpt_path: Path) -> dict:
    """Extract ALM and register counts from a Quartus map report.

    ALMs are N/A from synthesis-only (Fitter not run); registers are available.
    """
    data = {"alms": "N/A (Fitter not run)", "regs": "?", "m10k": "0", "dsp": "0"}
    if not rpt_path or not rpt_path.exists():
        return data

    text = rpt_path.read_text()

    # ALMs: Cyclone V reports "Logic utilization (in ALMs) ; N/A" pre-fit
    # Try to find a numeric value; fall back to N/A label
    alm_m = re.search(r'Logic utilization \(in ALMs\)\s*;\s*([\d,]+)', text)
    reg_m = re.search(r'Total registers\s*;\s*([\d,]+)', text)
    m10_m = re.search(r'Total block memory bits\s*;\s*([\d,]+)', text)
    dsp_m = re.search(r'Total DSP Blocks\s*;\s*([\d,]+)', text)

    if alm_m:  data["alms"] = alm_m.group(1).replace(",", "")
    if reg_m:  data["regs"] = reg_m.group(1).replace(",", "")
    if m10_m:  data["m10k"] = m10_m.group(1).replace(",", "")
    if dsp_m:  data["dsp"]  = dsp_m.group(1).replace(",", "")

    return data


def write_quartus_report(synth_dir: Path, util: dict, map_rpt: Path | None) -> None:
    rpt_path = synth_dir / "quartus" / "report.txt"
    now = datetime.now().strftime("%Y-%m-%d")
    rpt_ref = str(map_rpt) if map_rpt else "synthesis/quartus/work/timer_apb/output_files/timer_apb.map.rpt"
    lines = [
        "=" * 72,
        "Quartus Prime Synthesis Report — timer_apb",
        f"Target device : 5CSEMA4U23C6 (Cyclone V SE A4 — DE0-Nano-SoC)",
        f"Tool version  : Quartus Prime (quartus_sh)",
        f"Clock target  : 100 MHz (10.000 ns period)",
        f"Run date      : {now}",
        "=" * 72,
        "",
        "STATUS: PASS — Analysis & Synthesis completed successfully.",
        "",
        "-" * 72,
        "Resource Utilization",
        "-" * 72,
        f"  ALMs (Adaptive Logic Modules) : {util['alms']}",
        f"  Registers                     : {util['regs']}",
        f"  M10K memory bits              : {util['m10k']}",
        f"  DSP Blocks                    : {util['dsp']}",
        "",
        "Note: Full place-and-route timing requires running the Fitter.",
        "      Re-run with execute_flow -compile for post-route timing.",
        "",
        "Full report:",
        f"  {rpt_ref}",
        "=" * 72,
    ]
    rpt_path.write_text("\n".join(lines) + "\n")
    print(f"  Report  : {rpt_path}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def get_synth_dir() -> Path:
    env = os.environ.get("CLAUDE_TIMER_PATH")
    if env:
        return Path(env) / "synthesis"
    return Path(__file__).resolve().parent


def main() -> None:
    parser = argparse.ArgumentParser(description="Run Vivado and/or Quartus synthesis for timer IP")
    parser.add_argument("--vivado",  action="store_true", help="Vivado only (synthesis or clean)")
    parser.add_argument("--quartus", action="store_true", help="Quartus only (synthesis or clean)")
    parser.add_argument("--clean",   action="store_true", help="Remove outputs instead of running synthesis")
    args = parser.parse_args()

    synth_dir = get_synth_dir()
    print(f"Timer IP — Vendor Synthesis")
    print(f"  Synth dir : {synth_dir}")
    print()

    run_all = not args.vivado and not args.quartus
    do_vivado  = run_all or args.vivado
    do_quartus = run_all or args.quartus

    # --- Clean mode ---
    if args.clean:
        if do_vivado:
            clean_vivado(synth_dir)
        if do_quartus:
            clean_quartus(synth_dir)
        sys.exit(0)

    results = {}

    # --- Vivado ---
    if do_vivado:
        print("=== Vivado (Zynq-7010 xc7z010clg400-1) ===")
        ok = run_vivado(synth_dir)
        results["vivado"] = ok
        if ok:
            util   = parse_vivado_utilization(synth_dir / "vivado" / "utilization.rpt")
            timing = parse_vivado_timing(synth_dir / "vivado" / "timing_summary.rpt")
            write_vivado_report(synth_dir, util, timing)
            print(f"  LUTs={util['luts']}  FFs={util['ffs']}  WNS={timing['wns']} ns  {timing['met']}")
        print()

    # --- Quartus ---
    if do_quartus:
        print("=== Quartus (Cyclone V SE 5CSEMA4U23C6) ===")
        ok = run_quartus(synth_dir)
        results["quartus"] = ok
        if ok:
            map_rpt = find_quartus_map_rpt(synth_dir)
            util    = parse_quartus_utilization(map_rpt)
            write_quartus_report(synth_dir, util, map_rpt)
            print(f"  ALMs={util['alms']}  Regs={util['regs']}")
        print()

    # --- Summary ---
    print("=" * 40)
    all_pass = all(results.values())
    for tool, ok in results.items():
        status = "PASS" if ok else "FAIL"
        print(f"  {tool:<10} : {status}")
    print("=" * 40)
    sys.exit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
