#!/usr/bin/env python3
"""run_vendor_synth.py — Run vendor synthesis for the bus_matrix IP.

Automatically detects the host environment and runs appropriate tools:
  - On standard hosts: Vivado and Quartus (Yosys: synthesis/yosys/run_synth.py)
  - On *.csun.edu: Design Compiler with the SAED90/32/14 and SKY130 PDKs

Every protocol variant (APB4, AHB-Lite, AXI4-Lite, Wishbone) is synthesized
with its default parameters (bus_matrix_pkg), in SV and, for Design
Compiler, also in VHDL.

STA (PrimeTime, csun.edu only) is a separate step — see
synthesis/run_primetime_sta.py — run after synthesizing whichever PDK(s)
you want STA on.

Usage:
    python3 synthesis/run_vendor_synth.py              # run appropriate tools for host
    python3 synthesis/run_vendor_synth.py --vivado     # Vivado only (standard hosts)
    python3 synthesis/run_vendor_synth.py --quartus    # Quartus only (standard hosts)
    python3 synthesis/run_vendor_synth.py --dc         # Design Compiler all PDKs (csun.edu)
    python3 synthesis/run_vendor_synth.py --dc90       # Design Compiler 90nm only (csun.edu)
    python3 synthesis/run_vendor_synth.py --dc32       # Design Compiler 32nm only (csun.edu)
    python3 synthesis/run_vendor_synth.py --dc14       # Design Compiler 14nm only (csun.edu)
    python3 synthesis/run_vendor_synth.py --dcsky130   # Design Compiler SKY130 only (csun.edu)
    python3 synthesis/run_vendor_synth.py --clean      # clean all tool outputs

Requirements:
    - CLAUDE_BUS_MATRIX_PATH set (source IP/interface/bus_matrix/setup.sh)
    - On standard hosts: vivado, quartus_sh on PATH
    - On csun.edu: dc_shell on PATH (lc_shell also required for sky130 —
      compiles its ASCII .lib to .db on first use; result is cached in
      IP/common/synthesis/designcompiler/sky130_lib/)

Outputs:
    synthesis/vivado/report.txt                      — Vivado summary (standard hosts only)
    synthesis/quartus/report.txt                     — Quartus summary (standard hosts only)
    synthesis/designcompiler/report_<pdk>.txt        — DC per-variant summary (csun.edu only)
    synthesis/designcompiler/dc_<pdk>_run.log        — DC full log (csun.edu only)
    synthesis/designcompiler/reports/<pdk>/          — DC per-variant area/timing reports
    synthesis/designcompiler/netlists/<pdk>/         — DC netlists + SDF + SDC
"""

import argparse
import glob
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

SAED90_PDK = "/opt/ECE_Lib/SAED90nm_EDK_10072017/SAED90_EDK/SAED_EDK90nm"
SAED32_EDK = "/opt/ECE_Lib/SAED32_EDK"
SAED14_EDK = "/opt/ECE_Lib/SAED14nm_EDK_03_2025"

# ---------------------------------------------------------------------------
# sky130 PDK tooling lives in IP/common/synthesis/designcompiler — shared
# across every IP module so the sky130 .lib -> .db compile (via lc_shell)
# happens once and every IP's synthesis run reuses the same cached .db files,
# instead of each IP/*/synthesis/ recompiling its own copy.
# ---------------------------------------------------------------------------
_IP_COMMON_PATH = os.environ.get("IP_COMMON_PATH") or str(
    Path(__file__).resolve().parent.parent.parent.parent / "common"
)
sys.path.insert(0, str(Path(_IP_COMMON_PATH) / "synthesis" / "designcompiler"))
import build_sky130_libs  # noqa: E402

SKY130_PDK = build_sky130_libs.SKY130_PDK

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
    "sky130": {
        "label":   "SKY130 (130nm, SkyWater open-source PDK)",
        "env_var": "SKY130_PDK",
        "path":    SKY130_PDK,
    },
}


PROTOS = ["apb", "ahb", "axi4l", "wb"]
LANG_SUFFIX = {"sv": "", "vhdl": "_vhdl"}


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


def find_tool(name: str) -> Optional[str]:
    """Return the full path of a tool on PATH, or None."""
    return shutil.which(name)


# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------

# Note: sky130_lib/ is NOT listed here — it's the shared cross-IP .db cache
# under IP/common/synthesis/designcompiler/, not a per-IP artifact.
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
    "designcompiler/dc_sky130_run.log",
    "designcompiler/command.log",
    "designcompiler/default.svf",
]
DESIGNCOMPILER_CLEAN_GLOBS = ["*.v", "*.sdf", "*.pvk", "*.pvl", "*.syn", "*.mr"]
# ALIB cache dirs (compile_ultra's abstract-library cache, e.g. "alib-52" —
# the numeric suffix isn't stable, hence the glob).
DESIGNCOMPILER_CLEAN_DIR_GLOBS = ["alib-*"]


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
    for pattern in DESIGNCOMPILER_CLEAN_DIR_GLOBS:
        for p in dc_dir.glob(pattern):
            shutil.rmtree(p)
            print(f"  removed {p.relative_to(synth_dir.parent)}/")
    print("=== Design Compiler clean complete ===")


def clean_fpga(synth_dir: Path) -> None:
    """Remove Vivado/Quartus/Yosys work directories (summaries are kept)."""
    print("=== Cleaning Vivado / Quartus / Yosys outputs ===")
    for rel in ["vivado/work", "vivado/.Xil", "quartus/work", "quartus/db",
                "quartus/incremental_db", "yosys/work"]:
        p = synth_dir / rel
        if p.exists():
            shutil.rmtree(p)
            print(f"  removed {p.relative_to(synth_dir.parent)}/")
    for pattern in ["vivado/*.jou", "vivado/*.log"]:
        for p in synth_dir.glob(pattern):
            p.unlink()
            print(f"  removed {p.relative_to(synth_dir.parent)}")
    print("=== Vivado / Quartus / Yosys clean complete ===")


# sky130 ships only ASCII .lib (no pre-compiled .db, unlike the SAED PDKs).
# dc_shell on this host can't read ASCII .lib directly as target_library
# ("File is not a DB file", DB-1), so it needs compiling once via Library
# Compiler (lc_shell). That compile — and its resulting .db cache — is
# shared across all IP modules; see IP/common/synthesis/designcompiler/
# build_sky130_libs.py.
def run_design_compiler(synth_dir: Path, pdk_target: str) -> bool:
    """Run Design Compiler synthesis for the given PDK target (saed90, saed32, saed14, sky130)."""
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

    if pdk_target == "sky130":
        db_paths = build_sky130_libs.ensure_sky130_dbs(cfg["path"])
        if not db_paths:
            return False
        extra_env["SKY130_STDLIB_DB"] = db_paths[build_sky130_libs.SKY130_SYNTH_CORNER]

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


_AREA_RE   = re.compile(r"Total cell area:\s*([\d.]+)")
_CELLS_RE  = re.compile(r"Number of cells:\s*(\d+)")
_SEQ_RE    = re.compile(r"Number of sequential cells:\s*(\d+)")
_SLACK_RE  = re.compile(r"slack \((MET|VIOLATED)[^)]*\)\s+([-\d.]+)")


def parse_dc_variant(rpt_dir: Path, variant: str) -> dict:
    """Cells, flip-flops, area and worst slack of one variant's DC reports."""
    data = {"cells": "?", "ffs": "?", "area": "?", "wns": "?", "met": "?"}
    area_rpt = rpt_dir / f"{variant}_area.rpt"
    if area_rpt.exists():
        text = area_rpt.read_text()
        for key, rx in (("cells", _CELLS_RE), ("ffs", _SEQ_RE), ("area", _AREA_RE)):
            m = rx.search(text)
            if m:
                data[key] = m.group(1)
    timing_rpt = rpt_dir / f"{variant}_timing.rpt"
    if timing_rpt.exists():
        slacks = [(m.group(1), float(m.group(2)))
                  for m in _SLACK_RE.finditer(timing_rpt.read_text())]
        if slacks:
            worst = min(slacks, key=lambda s: s[1])
            data["wns"] = f"{worst[1]:+.2f}"
            data["met"] = worst[0]
    return data


def write_dc_report(synth_dir: Path, pdk_target: str) -> bool:
    """Write report_<pdk>.txt (one row per variant). Returns True if all met."""
    cfg = PDK_CONFIGS[pdk_target]
    rpt_dir = synth_dir / "designcompiler" / "reports" / pdk_target
    rpt_path = synth_dir / "designcompiler" / f"report_{pdk_target}.txt"
    now = datetime.now().strftime("%Y-%m-%d")
    rows = []
    for lang in ("sv", "vhdl"):
        for proto in PROTOS:
            variant = f"bus_matrix_{proto}{LANG_SUFFIX[lang]}"
            rows.append((variant, parse_dc_variant(rpt_dir, variant)))
    all_met = all(r["met"] == "MET" for _, r in rows)
    lines = [
        "=" * 78,
        "Design Compiler Synthesis Report — bus_matrix IP",
        f"Target PDK    : {cfg['label']}",
        "Configuration : 2 masters, 4 slaves, round robin (bus_matrix_pkg defaults)",
        "Constraints   : 100 MHz clk; 3.0 ns input and output delay on every port",
        "Tool version  : Design Compiler (dc_shell)",
        f"Run date      : {now}",
        "=" * 78,
        "",
        f"STATUS: {'PASS' if all_met else 'TIMING VIOLATED'} — synthesis completed.",
        "",
        f"{'Variant':<24} {'Cells':>7} {'FFs':>5} {'Area':>12} {'WNS (ns)':>9}  Timing",
        "-" * 78,
    ]
    for variant, r in rows:
        lines.append(f"{variant:<24} {r['cells']:>7} {r['ffs']:>5} {r['area']:>12} "
                     f"{r['wns']:>9}  {r['met']}")
    lines += [
        "",
        "Area is in the library's units (um^2 for SAED32/14 and SKY130).",
        "WNS is the worst slack among the 10 paths in each <variant>_timing.rpt.",
        "",
        "Per-variant area and timing reports:",
        f"  synthesis/designcompiler/reports/{pdk_target}/",
        "Netlists, SDF and SDC:",
        f"  synthesis/designcompiler/netlists/{pdk_target}/",
        "Full log:",
        f"  synthesis/designcompiler/dc_{pdk_target}_run.log",
        "=" * 78,
    ]
    rpt_path.write_text("\n".join(lines) + "\n")
    print(f"  Report  : {rpt_path}")
    return all_met


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

    # First value of the row under the Design Timing Summary "WNS(ns)" header
    m = re.search(r"WNS\(ns\).*\n\s*-+.*\n\s*([-\d.]+)", content)
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
# Main
# ---------------------------------------------------------------------------

def get_ip_path() -> Path:
    env = os.environ.get("CLAUDE_BUS_MATRIX_PATH")
    if env:
        return Path(env).resolve()
    return Path(__file__).resolve().parent.parent


def main() -> None:
    parser = argparse.ArgumentParser(description="Run synthesis for the bus_matrix IP (host-aware)")
    parser.add_argument("--vivado",  action="store_true", help="Vivado only (standard hosts)")
    parser.add_argument("--quartus", action="store_true", help="Quartus only (standard hosts)")
    parser.add_argument("--dc",      action="store_true", help="Design Compiler all PDKs (csun.edu)")
    parser.add_argument("--dc90",    action="store_true", help="Design Compiler 90nm only (csun.edu)")
    parser.add_argument("--dc32",    action="store_true", help="Design Compiler 32nm only (csun.edu)")
    parser.add_argument("--dc14",    action="store_true", help="Design Compiler 14nm only (csun.edu)")
    parser.add_argument("--dcsky130", action="store_true", help="Design Compiler SKY130 only (csun.edu)")
    parser.add_argument("--clean",   action="store_true", help="Remove outputs instead of running synthesis")
    args = parser.parse_args()

    ip_path = get_ip_path()
    synth_dir = ip_path / "synthesis"
    print("bus_matrix IP — Vendor Synthesis")
    print(f"  Host      : {_hostname_fqdn()}{' (csun.edu)' if ON_CSUN else ' (standard host)'}")
    print(f"  Synth dir : {synth_dir}")
    print()

    # --- Clean mode (host-agnostic: removes whatever is present) ---
    if args.clean:
        clean_fpga(synth_dir)
        clean_design_compiler(synth_dir)
        sys.exit(0)

    dc_flags_requested = args.dc or args.dc90 or args.dc32 or args.dc14 or args.dcsky130

    if ON_CSUN:
        if args.vivado or args.quartus:
            print("ERROR: Vivado and Quartus not available on csun.edu.")
            sys.exit(1)
        run_vivado_flag  = False
        run_quartus_flag = False
        dc_pdks = [p for p, flag in [("saed90", args.dc90), ("saed32", args.dc32),
                                     ("saed14", args.dc14), ("sky130", args.dcsky130)]
                   if not dc_flags_requested or args.dc or flag]
    else:
        if dc_flags_requested:
            print("ERROR: Design Compiler only available on csun.edu.")
            sys.exit(1)
        run_all          = not args.vivado and not args.quartus
        run_vivado_flag  = run_all or args.vivado
        run_quartus_flag = run_all or args.quartus
        dc_pdks = []

    results = {}

    # --- Design Compiler ---
    for pdk in dc_pdks:
        print(f"=== Design Compiler — {PDK_CONFIGS[pdk]['label']} ===")
        ok = run_design_compiler(synth_dir, pdk)
        if ok:
            met = write_dc_report(synth_dir, pdk)
            print(f"  Timing  : {'MET' if met else 'VIOLATED (see report)'}")
        results[f"dc_{pdk}"] = ok
        print()

    # --- Vivado ---
    if run_vivado_flag:
        print("=== Vivado (Zynq-7010 xc7z010clg400-1) ===")
        if find_tool("vivado"):
            ok, _ = run_vivado(str(ip_path))
            results["vivado"] = ok
        else:
            print("  ERROR: vivado not found on PATH — is setup.sh sourced?")
            results["vivado"] = False
        print()

    # --- Quartus ---
    if run_quartus_flag:
        print("=== Quartus (Cyclone V SE 5CSEMA4U23C6) ===")
        if find_tool("quartus_sh"):
            ok, _ = run_quartus(str(ip_path))
            results["quartus"] = ok
        else:
            print("  ERROR: quartus_sh not found on PATH — is setup.sh sourced?")
            results["quartus"] = False
        print()

    # --- Summary ---
    print("=" * 40)
    all_pass = all(results.values())
    for tool, ok in results.items():
        print(f"  {tool:<20} : {'PASS' if ok else 'FAIL'}")
    print("=" * 40)
    sys.exit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
