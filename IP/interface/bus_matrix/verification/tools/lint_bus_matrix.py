#!/usr/bin/env python3
"""lint_bus_matrix.py — Lint runner for bus_matrix IP.

Runs Verilator --lint-only on all SV RTL sources and GHDL -s (syntax check)
on all VHDL RTL sources. Writes verification/lint/lint_results.log.
"""

import argparse
import os
import sys
from pathlib import Path

# Import common base
common_path = os.environ.get("IP_COMMON_PATH", "")
if common_path:
    sys.path.insert(0, os.path.join(common_path, "verification", "tools"))
from ip_tool_base import require_env, run_command, write_results_log, get_verilator_version


def lint_sv(ip_path):
    """Run Verilator --lint-only on all SV RTL sources."""
    rtl_dir = os.path.join(ip_path, "design", "rtl", "verilog")
    common_srcs = [
        os.path.join(rtl_dir, "bus_matrix_decoder.sv"),
        os.path.join(rtl_dir, "bus_matrix_arb.sv"),
        os.path.join(rtl_dir, "bus_matrix_core.sv"),
    ]

    tops = {
        "ahb": os.path.join(rtl_dir, "bus_matrix_ahb.sv"),
        "axi": os.path.join(rtl_dir, "bus_matrix_axi.sv"),
        "wb":  os.path.join(rtl_dir, "bus_matrix_wb.sv"),
    }

    all_pass = True
    details = []

    for proto, top_file in tops.items():
        top_mod = f"bus_matrix_{proto}"
        cmd = [
            "verilator", "--lint-only", "-Wall",
            "--top-module", top_mod,
            f"-I{rtl_dir}",
        ] + common_srcs + [top_file]

        print(f"  [SV] verilator --lint-only {top_mod} ...")
        rc, stdout, stderr = run_command(cmd)
        output = (stdout + stderr).strip()
        if rc != 0:
            print(f"  [SV] {top_mod}: FAIL")
            if output:
                print(output)
            details.append(f"SV {top_mod}: FAIL")
            all_pass = False
        else:
            print(f"  [SV] {top_mod}: PASS")
            details.append(f"SV {top_mod}: PASS")

    return all_pass, details


def lint_vhdl(ip_path):
    """Run GHDL -s (syntax check) on all VHDL RTL sources."""
    rtl_dir = os.path.join(ip_path, "design", "rtl", "vhdl")

    vhdl_files = [
        "bus_matrix_decoder.vhd",
        "bus_matrix_arb.vhd",
        "bus_matrix_core.vhd",
        "bus_matrix_ahb.vhd",
        "bus_matrix_axi.vhd",
        "bus_matrix_wb.vhd",
    ]

    all_pass = True
    details = []

    for fn in vhdl_files:
        fp = os.path.join(rtl_dir, fn)
        if not os.path.isfile(fp):
            print(f"  [VHDL] {fn}: NOT FOUND")
            details.append(f"VHDL {fn}: NOT FOUND")
            all_pass = False
            continue

        cmd = ["ghdl", "-s", "--std=08", "-frelaxed", fp]
        print(f"  [VHDL] ghdl -s {fn} ...")
        rc, stdout, stderr = run_command(cmd)
        output = (stdout + stderr).strip()
        if rc != 0:
            print(f"  [VHDL] {fn}: FAIL")
            if output:
                print(output)
            details.append(f"VHDL {fn}: FAIL")
            all_pass = False
        else:
            print(f"  [VHDL] {fn}: PASS")
            details.append(f"VHDL {fn}: PASS")

    return all_pass, details


def main():
    ip_path = require_env("CLAUDE_BUS_MATRIX_PATH")
    ip_path = str(Path(ip_path).resolve())

    parser = argparse.ArgumentParser(description="Lint bus_matrix RTL sources")
    parser.add_argument(
        "--lang",
        choices=["sv", "vhdl", "all"],
        default="all",
        help="HDL language to lint (default: all)",
    )
    args = parser.parse_args()

    results_log = os.path.join(ip_path, "verification", "lint", "lint_results.log")
    overall_pass = True
    all_details = []

    ver = get_verilator_version()
    all_details.append(f"Verilator: {ver}")

    if args.lang in ("sv", "all"):
        print("\n=== SV Lint (Verilator) ===")
        passed, details = lint_sv(ip_path)
        overall_pass = overall_pass and passed
        all_details.extend(details)

    if args.lang in ("vhdl", "all"):
        print("\n=== VHDL Lint (GHDL syntax check) ===")
        passed, details = lint_vhdl(ip_path)
        overall_pass = overall_pass and passed
        all_details.extend(details)

    write_results_log(results_log, overall_pass, all_details)

    print("\n" + "=" * 50)
    if overall_pass:
        print("LINT PASSED")
    else:
        print("LINT FAILED")
    print("=" * 50)
    print(f"Results: {results_log}")

    sys.exit(0 if overall_pass else 1)


if __name__ == "__main__":
    main()
