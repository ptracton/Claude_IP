#!/usr/bin/env python3
"""run_vendor_synth.py — Run vendor synthesis for the Timer IP.

Automatically detects the host environment and runs appropriate tools:
  - On standard hosts: Vivado, Quartus, and Yosys
  - On ecs-vdi.ecs.csun.edu: Design Compiler with both 90nm and 32nm PDKs

Usage:
    python3 synthesis/run_vendor_synth.py            # run appropriate tools for host
    python3 synthesis/run_vendor_synth.py --vivado   # Vivado only (standard hosts)
    python3 synthesis/run_vendor_synth.py --quartus  # Quartus only (standard hosts)
    python3 synthesis/run_vendor_synth.py --dc       # Design Compiler all PDKs (ecs-vdi)
    python3 synthesis/run_vendor_synth.py --dc90     # Design Compiler 90nm only (ecs-vdi)
    python3 synthesis/run_vendor_synth.py --dc32     # Design Compiler 32nm only (ecs-vdi)
    python3 synthesis/run_vendor_synth.py --dc14     # Design Compiler 14nm only (ecs-vdi)
    python3 synthesis/run_vendor_synth.py --clean    # clean all tool outputs

Requirements:
    - CLAUDE_TIMER_PATH set (source timer/setup.sh)
    - On standard hosts: vivado, quartus_sh on PATH
    - On ecs-vdi: dc_shell on PATH
        90nm PDK at /opt/ECE_Lib/SAED90nm_EDK_10072017/SAED90_EDK/SAED_EDK90nm
        32nm PDK at /opt/ECE_Lib/SAED32_EDK
        14nm PDK at /opt/ECE_Lib/SAED14nm_EDK_03_2025

Outputs:
    synthesis/vivado/report.txt                      — Vivado summary (standard hosts only)
    synthesis/quartus/report.txt                     — Quartus summary (standard hosts only)
    synthesis/yosys/work/synthesis_report.log        — Yosys summary (standard hosts only)
    synthesis/designcompiler/dc_saed90_run.log       — DC 90nm full log (ecs-vdi only)
    synthesis/designcompiler/dc_saed32_run.log       — DC 32nm full log (ecs-vdi only)
    synthesis/designcompiler/dc_saed14_run.log       — DC 14nm full log (ecs-vdi only)
    synthesis/designcompiler/reports/saed90/         — DC 90nm per-variant reports
    synthesis/designcompiler/reports/saed32/         — DC 32nm per-variant reports
    synthesis/designcompiler/reports/saed14/         — DC 14nm per-variant reports
    synthesis/designcompiler/netlists/saed90/        — DC 90nm netlists + SDF
    synthesis/designcompiler/netlists/saed32/        — DC 32nm netlists + SDF
    synthesis/designcompiler/netlists/saed14/        — DC 14nm netlists + SDF
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

# Host detection
import socket
ON_ECS_VDI = socket.getfqdn() == "ecs-vdi.ecs.csun.edu"

SAED90_PDK = "/opt/ECE_Lib/SAED90nm_EDK_10072017/SAED90_EDK/SAED_EDK90nm"
SAED32_EDK = "/opt/ECE_Lib/SAED32_EDK"
SAED14_EDK = "/opt/ECE_Lib/SAED14nm_EDK_03_2025"

PDK_CONFIGS = {
    "saed90": {
        "label":   "SAED90 (90nm)",
        "env_var": "SAED90_PDK",
        "path":    SAED90_PDK,
    },
    "saed32": {
        "label":   "SAED32 (32nm)",
        "env_var": "SAED32_EDK",
        "path":    SAED32_EDK,
    },
    "saed14": {
        "label":   "SAED14 (14nm)",
        "env_var": "SAED14_EDK",
        "path":    SAED14_EDK,
    },
}


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

# DC clean is handled by clean.sh; mirror the key paths here for --clean
DESIGNCOMPILER_CLEAN_DIRS = [
    "designcompiler/cksum_dir",
    "designcompiler/reports",
    "designcompiler/netlists",
    "designcompiler/ARCH",
    "designcompiler/ENTI",
    "designcompiler/PACK",
]
DESIGNCOMPILER_CLEAN = [
    "designcompiler/dc_saed90_run.log",
    "designcompiler/dc_saed32_run.log",
    "designcompiler/dc_saed14_run.log",
    "designcompiler/command.log",
    "designcompiler/default.svf",
    "designcompiler/report.txt",
]
DESIGNCOMPILER_CLEAN_GLOBS = ["*.v", "*.sdf", "*.pvk", "*.pvl", "*.syn", "*.mr"]


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


def clean_design_compiler(synth_dir: Path) -> None:
    print("=== Cleaning Design Compiler outputs ===")
    dc_dir = synth_dir / "designcompiler"
    for rel in DESIGNCOMPILER_CLEAN_DIRS:
        p = synth_dir / rel
        if p.exists():
            shutil.rmtree(p)
            print(f"  removed {p.relative_to(synth_dir.parent)}/")
    for rel in DESIGNCOMPILER_CLEAN:
        p = synth_dir / rel
        if p.exists():
            p.unlink()
            print(f"  removed {p.relative_to(synth_dir.parent)}")
    for pattern in DESIGNCOMPILER_CLEAN_GLOBS:
        for p in dc_dir.glob(pattern):
            p.unlink()
            print(f"  removed {p.relative_to(synth_dir.parent)}")
    print("=== Design Compiler clean complete ===")


# ---------------------------------------------------------------------------
# Tool discovery
# ---------------------------------------------------------------------------

def find_tool(name: str) -> Optional[str]:
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
            universal_newlines=True,
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
            universal_newlines=True,
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


def find_quartus_map_rpt(synth_dir: Path) -> Optional[Path]:
    """Find the map report generated by Quartus Analysis & Synthesis."""
    for p in (synth_dir / "quartus" / "work").rglob("*.map.rpt"):
        return p
    return None


def parse_quartus_utilization(rpt_path: Path) -> dict:
    """Extract ALM and register counts from a Quartus map report."""
    data = {"alms": "N/A (Fitter not run)", "regs": "?", "m10k": "0", "dsp": "0"}
    if not rpt_path or not rpt_path.exists():
        return data

    text = rpt_path.read_text()

    alm_m = re.search(r'Logic utilization \(in ALMs\)\s*;\s*([\d,]+)', text)
    reg_m = re.search(r'Total registers\s*;\s*([\d,]+)', text)
    m10_m = re.search(r'Total block memory bits\s*;\s*([\d,]+)', text)
    dsp_m = re.search(r'Total DSP Blocks\s*;\s*([\d,]+)', text)

    if alm_m:  data["alms"] = alm_m.group(1).replace(",", "")
    if reg_m:  data["regs"] = reg_m.group(1).replace(",", "")
    if m10_m:  data["m10k"] = m10_m.group(1).replace(",", "")
    if dsp_m:  data["dsp"]  = dsp_m.group(1).replace(",", "")

    return data


def write_quartus_report(synth_dir: Path, util: dict, map_rpt: Optional[Path]) -> None:
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
# Design Compiler
# ---------------------------------------------------------------------------

def run_design_compiler(synth_dir: Path, pdk_target: str) -> bool:
    """Run Design Compiler synthesis for the given PDK target (saed90 or saed32)."""
    cfg = PDK_CONFIGS[pdk_target]

    dc_shell = find_tool("dc_shell")
    if not dc_shell:
        print("  ERROR: dc_shell not found on PATH")
        return False

    if not os.path.isdir(cfg["path"]):
        print(f"  ERROR: {cfg['label']} PDK not found at {cfg['path']}")
        return False

    tcl = synth_dir / "designcompiler" / "synth.tcl"
    log = synth_dir / "designcompiler" / f"dc_{pdk_target}_run.log"

    print(f"  Tool    : {dc_shell}")
    print(f"  PDK     : {cfg['path']}")
    print(f"  Script  : {tcl}")
    print(f"  Log     : {log}")

    (synth_dir / "designcompiler").mkdir(exist_ok=True)

    cmd = [dc_shell, "-f", str(tcl)]
    extra_env = {
        "PDK_TARGET":       pdk_target,
        cfg["env_var"]:     cfg["path"],
    }

    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            timeout=1200,
            cwd=str(synth_dir / "designcompiler"),
            env={**os.environ, **extra_env},
        )
    except subprocess.TimeoutExpired:
        print(f"  ERROR: Design Compiler ({pdk_target}) timed out after 1200 s")
        return False

    log.write_text(result.stdout)

    if result.returncode != 0:
        print(f"  ERROR: Design Compiler ({pdk_target}) exited with code {result.returncode}")
        print(f"         See {log} for details")
        for line in result.stdout.splitlines()[-20:]:
            print(f"    {line}")
        return False

    return True


def parse_dc_area(log_path: Path) -> dict:
    """Extract cell and FF counts from Design Compiler report_area output."""
    data = {"cells": "?", "ffs": "?"}
    if not log_path.exists():
        return data

    text = log_path.read_text()

    cells_m = re.search(r'Number of cells\s*:\s*(\d+)', text)
    seq_m   = re.search(r'Number of sequential cells\s*:\s*(\d+)', text)

    if cells_m: data["cells"] = cells_m.group(1)
    if seq_m:   data["ffs"]   = seq_m.group(1)

    return data


def write_dc_report(synth_dir: Path, pdk_target: str, util: dict) -> None:
    cfg = PDK_CONFIGS[pdk_target]
    rpt_path = synth_dir / "designcompiler" / f"report_{pdk_target}.txt"
    now = datetime.now().strftime("%Y-%m-%d")
    lines = [
        "=" * 72,
        f"Design Compiler Synthesis Report — timer IP",
        f"Target PDK    : {cfg['label']}",
        f"Tool version  : Design Compiler (dc_shell)",
        f"Run date      : {now}",
        "=" * 72,
        "",
        "STATUS: PASS — synthesis completed successfully.",
        "",
        "-" * 72,
        "Synthesis Results",
        "-" * 72,
        f"  Total cells  : {util['cells']}",
        f"  Flip-flops   : {util['ffs']}",
        "",
        "Per-variant area and timing reports:",
        f"  synthesis/designcompiler/reports/{pdk_target}/",
        "",
        "Netlists and SDF:",
        f"  synthesis/designcompiler/netlists/{pdk_target}/",
        "",
        "Full log:",
        f"  synthesis/designcompiler/dc_{pdk_target}_run.log",
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
    parser = argparse.ArgumentParser(description="Run synthesis for timer IP (host-aware)")
    parser.add_argument("--vivado",  action="store_true", help="Vivado only (standard hosts)")
    parser.add_argument("--quartus", action="store_true", help="Quartus only (standard hosts)")
    parser.add_argument("--dc",      action="store_true", help="Design Compiler all PDKs (ecs-vdi)")
    parser.add_argument("--dc90",    action="store_true", help="Design Compiler 90nm only (ecs-vdi)")
    parser.add_argument("--dc32",    action="store_true", help="Design Compiler 32nm only (ecs-vdi)")
    parser.add_argument("--dc14",    action="store_true", help="Design Compiler 14nm only (ecs-vdi)")
    parser.add_argument("--clean",   action="store_true", help="Remove outputs instead of running synthesis")
    args = parser.parse_args()

    synth_dir = get_synth_dir()
    print(f"Timer IP — Vendor Synthesis")
    print(f"  Host      : {'ecs-vdi.ecs.csun.edu' if ON_ECS_VDI else 'standard host'}")
    print(f"  Synth dir : {synth_dir}")
    print()

    dc_flags_requested = args.dc or args.dc90 or args.dc32 or args.dc14

    if ON_ECS_VDI:
        if args.vivado or args.quartus:
            print("ERROR: Vivado and Quartus not available on ecs-vdi.")
            sys.exit(1)
        # Default on ecs-vdi: run all three PDKs
        run_vivado_flag  = False
        run_quartus_flag = False
        run_dc90 = not dc_flags_requested or args.dc or args.dc90
        run_dc32 = not dc_flags_requested or args.dc or args.dc32
        run_dc14 = not dc_flags_requested or args.dc or args.dc14
    else:
        if dc_flags_requested:
            print("ERROR: Design Compiler only available on ecs-vdi.")
            sys.exit(1)
        run_all          = not args.vivado and not args.quartus
        run_vivado_flag  = run_all or args.vivado
        run_quartus_flag = run_all or args.quartus
        run_dc90 = False
        run_dc32 = False
        run_dc14 = False

    # --- Clean mode ---
    if args.clean:
        if run_vivado_flag:
            clean_vivado(synth_dir)
        if run_quartus_flag:
            clean_quartus(synth_dir)
        if run_dc90 or run_dc32:
            clean_design_compiler(synth_dir)
        sys.exit(0)

    results = {}

    # --- Design Compiler ---
    if run_dc90:
        print(f"=== Design Compiler — SAED90 (90nm) ===")
        ok = run_design_compiler(synth_dir, "saed90")
        results["dc_saed90"] = ok
        if ok:
            util = parse_dc_area(synth_dir / "designcompiler" / "dc_saed90_run.log")
            write_dc_report(synth_dir, "saed90", util)
            print(f"  Cells={util['cells']}  FFs={util['ffs']}")
        print()

    if run_dc32:
        print(f"=== Design Compiler — SAED32 (32nm) ===")
        ok = run_design_compiler(synth_dir, "saed32")
        results["dc_saed32"] = ok
        if ok:
            util = parse_dc_area(synth_dir / "designcompiler" / "dc_saed32_run.log")
            write_dc_report(synth_dir, "saed32", util)
            print(f"  Cells={util['cells']}  FFs={util['ffs']}")
        print()

    if run_dc14:
        print(f"=== Design Compiler — SAED14 (14nm) ===")
        ok = run_design_compiler(synth_dir, "saed14")
        results["dc_saed14"] = ok
        if ok:
            util = parse_dc_area(synth_dir / "designcompiler" / "dc_saed14_run.log")
            write_dc_report(synth_dir, "saed14", util)
            print(f"  Cells={util['cells']}  FFs={util['ffs']}")
        print()

    # --- Vivado ---
    if run_vivado_flag:
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
    if run_quartus_flag:
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
        print(f"  {tool:<20} : {status}")
    print("=" * 40)
    sys.exit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
