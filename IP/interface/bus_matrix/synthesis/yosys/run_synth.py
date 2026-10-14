#!/usr/bin/env python3
"""run_synth.py — Run Yosys synthesis for all bus_matrix variants (SV + VHDL).

Usage (from IP/interface/bus_matrix/):
    python3 synthesis/yosys/run_synth.py
    python3 synthesis/yosys/run_synth.py --sv-only
    python3 synthesis/yosys/run_synth.py --vhdl-only
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path


PROTOS = ["apb", "ahb", "axi4l", "wb"]

SCRIPT_DIR = Path(__file__).parent
IP_DIR = SCRIPT_DIR.parent.parent


def run_yosys(script_path, work_dir):
    """Invoke Yosys on a .ys script. Return (rc, stdout)."""
    result = subprocess.run(
        ["yosys", str(script_path)],
        cwd=str(IP_DIR),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return result.returncode, result.stdout


def parse_stat(output):
    """Extract total cells and flip-flop count from the last yosys stat block.

    Cell lines are "<count>   $<cell>". $scopeinfo is debug info, not logic,
    so it is not counted. Every cell type containing "DFF" is a flip-flop.
    """
    blocks = output.split("Printing statistics.")
    if len(blocks) < 2:
        return "N/A", "N/A"
    cells = {}
    for m in re.finditer(r"^\s+(\d+)\s+(\$\w+)\s*$", blocks[-1], re.M):
        cells[m.group(2)] = cells.get(m.group(2), 0) + int(m.group(1))
    cells.pop("$scopeinfo", None)
    if not cells:
        return "N/A", "N/A"
    dffs = sum(n for c, n in cells.items() if "DFF" in c.upper())
    return str(sum(cells.values())), str(dffs)


def main():
    parser = argparse.ArgumentParser(description="Yosys synthesis runner for bus_matrix")
    parser.add_argument("--sv-only",   action="store_true", help="SV variants only")
    parser.add_argument("--vhdl-only", action="store_true", help="VHDL variants only")
    args = parser.parse_args()

    run_sv   = not args.vhdl_only
    run_vhdl = not args.sv_only

    work_dir = SCRIPT_DIR / "work"
    work_dir.mkdir(exist_ok=True)

    results = []
    all_pass = True

    variants = []
    if run_sv:
        variants += [(f"bus_matrix_{p}", f"synth_bus_matrix_{p}.ys", "SV") for p in PROTOS]
    if run_vhdl:
        variants += [(f"bus_matrix_{p}", f"synth_bus_matrix_{p}_vhdl.ys", "VHDL") for p in PROTOS]

    for top, script_name, lang in variants:
        script_path = SCRIPT_DIR / script_name
        print(f"  [Yosys] {top} ({lang})...")
        rc, out = run_yosys(script_path, work_dir)
        (work_dir / f"yosys_raw_{script_path.stem}.log").write_text(out)
        cells, dffs = parse_stat(out)
        status = "PASS" if rc == 0 else "FAIL"
        if rc != 0:
            all_pass = False
        print(f"    {status}  cells={cells}  DFFs={dffs}")
        results.append((top, lang, cells, dffs, status))

    log_path = work_dir / "synthesis_report.log"
    with open(log_path, "w") as fh:
        fh.write("Yosys Synthesis Report — bus_matrix\n")
        fh.write("=" * 55 + "\n\n")
        fh.write(f"{'Variant':<22} {'Lang':<6} {'Cells':<8} {'DFFs':<8} Result\n")
        fh.write("-" * 55 + "\n")
        for top, lang, cells, dffs, status in results:
            fh.write(f"{top:<22} {lang:<6} {cells:<8} {dffs:<8} {status}\n")

    print(f"\nReport written to {log_path}")
    sys.exit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
