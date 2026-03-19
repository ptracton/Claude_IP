#!/usr/bin/env python3
"""lint_timer.py — Lint runner for the timer IP block.

Runs Verilator (SystemVerilog) and/or GHDL (VHDL-2008) lint checks on all
RTL source files under design/rtl/.

Results are written to:
    ${CLAUDE_TIMER_PATH}/verification/lint/lint_results.log

Exit codes:
    0  — all checks passed (zero un-waived warnings/errors)
    1  — one or more warnings or errors found, or environment error

Usage:
    python3 lint_timer.py [--lang {sv,vhdl,all}]

Prerequisites:
    source IP/system/timer/setup.sh   (sets CLAUDE_TIMER_PATH)
"""

import argparse
import os
import subprocess
import sys
from datetime import datetime
from typing import List, Tuple

# ---------------------------------------------------------------------------
# Locate and import ip_tool_base from ${IP_COMMON_PATH}/verification/tools/
# ---------------------------------------------------------------------------
_TIMER_PATH = os.environ.get("CLAUDE_TIMER_PATH", "")
if _TIMER_PATH:
    _COMMON_PATH = os.environ.get(
        "IP_COMMON_PATH",
        os.path.join(_TIMER_PATH, "..", "..", "common"),
    )
    _BASE_DIR = os.path.join(_COMMON_PATH, "verification", "tools")
    if _BASE_DIR not in sys.path:
        sys.path.insert(0, os.path.normpath(_BASE_DIR))

try:
    from ip_tool_base import (
        require_env,
        run_command,
        write_results_log,
        get_verilator_version,
        get_ghdl_version,
    )
except ImportError:
    # Fallback minimal implementations so the script fails gracefully when
    # ip_tool_base is not yet available (e.g., during first bootstrap).
    def require_env(var_name):  # type: ignore[misc]
        value = os.environ.get(var_name, "")
        if not value:
            print(f"ERROR: {var_name} is not set.")
            print("       Please run:  source timer/setup.sh")
            sys.exit(1)
        return value

    def run_command(cmd, cwd=None, capture=True):  # type: ignore[misc]
        if capture:
            r = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True)
            return r.returncode, r.stdout, r.stderr
        r = subprocess.run(cmd, cwd=cwd)
        return r.returncode, "", ""

    def write_results_log(log_path, passed, details=None):  # type: ignore[misc]
        os.makedirs(os.path.dirname(log_path), exist_ok=True)
        result_str = "PASS" if passed else "FAIL"
        timestamp = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
        lines = [result_str, f"Generated: {timestamp}"]
        if details:
            lines.extend(details)
        with open(log_path, "w") as fh:
            fh.write("\n".join(lines) + "\n")

    def get_verilator_version(binary="verilator"):  # type: ignore[misc]
        try:
            r = subprocess.run([binary, "--version"], capture_output=True, text=True)
            if r.returncode == 0:
                return r.stdout.splitlines()[0].strip()
        except FileNotFoundError:
            pass
        return "unknown"

    def get_ghdl_version(binary="ghdl"):  # type: ignore[misc]
        try:
            r = subprocess.run([binary, "--version"], capture_output=True, text=True)
            output = r.stdout or r.stderr
            if output:
                return output.splitlines()[0].strip()
        except FileNotFoundError:
            pass
        return "unknown"


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SUPPORTED_LANGS = ["sv", "vhdl", "all"]

VERILATOR_BIN = "/opt/oss-cad-suite/bin/verilator"
GHDL_BIN      = "/opt/oss-cad-suite/bin/ghdl"

# Common RTL files (always included, in dependency order)
SV_COMMON_FILES = [
    "design/rtl/verilog/timer_reg_pkg.sv",
    "design/rtl/verilog/timer_regfile.sv",
    "design/rtl/verilog/timer_core.sv",
]

# (top_module_name, extra_sv_files) for each bus variant
# claude_*_if files come from common/; paths are expanded at runtime via common_path.
SV_VARIANTS: List[Tuple[str, List[str]]] = [
    ("timer_apb",    ["common:claude_apb_if.sv",   "design/rtl/verilog/timer_apb.sv"]),
    ("timer_ahb",    ["common:claude_ahb_if.sv",   "design/rtl/verilog/timer_ahb.sv"]),
    ("timer_axi4l",  ["common:claude_axi4l_if.sv", "design/rtl/verilog/timer_axi4l.sv"]),
    ("timer_wb",     ["common:claude_wb_if.sv",    "design/rtl/verilog/timer_wb.sv"]),
]

# VHDL files in compilation order (packages before consumers)
# claude_*_if files come from common/; paths are expanded at runtime via common_path.
VHDL_FILES = [
    "design/rtl/vhdl/timer_reg_pkg.vhd",
    "design/rtl/vhdl/timer_regfile.vhd",
    "design/rtl/vhdl/timer_core.vhd",
    "common:claude_apb_if.vhd",
    "design/rtl/vhdl/timer_apb.vhd",
    "common:claude_ahb_if.vhd",
    "design/rtl/vhdl/timer_ahb.vhd",
    "common:claude_axi4l_if.vhd",
    "design/rtl/vhdl/timer_axi4l.vhd",
    "common:claude_wb_if.vhd",
    "design/rtl/vhdl/timer_wb.vhd",
]


# ---------------------------------------------------------------------------
# SV lint via Verilator
# ---------------------------------------------------------------------------

def run_sv_lint(timer_path: str, common_path: str) -> Tuple[bool, List[str]]:
    """Run Verilator --lint-only on all four SV top-level variants.

    Returns:
        (passed, detail_lines)
    """
    passed = True
    details: List[str] = []
    common_rtl_sv = os.path.join(common_path, "design", "rtl", "verilog")

    def resolve_sv(f: str) -> str:
        """Expand 'common:<name>' to an absolute path in common/design/rtl/verilog/."""
        if f.startswith("common:"):
            return os.path.join(common_rtl_sv, f[len("common:"):])
        return os.path.join(timer_path, f)

    verilator_ver = get_verilator_version(VERILATOR_BIN)
    details.append(f"[SV] Verilator version: {verilator_ver}")

    for top_module, extra_files in SV_VARIANTS:
        src_files = [resolve_sv(f) for f in SV_COMMON_FILES + extra_files]
        cmd = [
            VERILATOR_BIN,
            "--lint-only",
            "-Wall",
            "-Wno-DECLFILENAME",
            f"-I{common_rtl_sv}",
            f"--top-module", top_module,
        ] + src_files

        details.append(f"[SV] Linting {top_module} ...")
        rc, stdout, stderr = run_command(cmd, cwd=timer_path)
        output = (stdout + stderr).strip()

        if rc != 0 or output:
            # Verilator writes warnings/errors to stderr; non-zero exit = error.
            # Presence of output lines starting with '%Warning' or '%Error'
            # also indicates a problem.
            has_issues = (rc != 0) or any(
                line.lstrip().startswith(("%Warning", "%Error"))
                for line in output.splitlines()
            )
            if has_issues:
                passed = False
                details.append(f"[SV] FAIL — {top_module}")
                for line in output.splitlines():
                    details.append(f"       {line}")
            else:
                # Informational output only (e.g., version banner)
                details.append(f"[SV] PASS — {top_module}")
        else:
            details.append(f"[SV] PASS — {top_module}")

    return passed, details


# ---------------------------------------------------------------------------
# VHDL lint via GHDL -a
# ---------------------------------------------------------------------------

def run_vhdl_lint(timer_path: str) -> Tuple[bool, List[str]]:
    """Run GHDL -a --std=08 on all VHDL RTL files in dependency order.

    A temporary workdir is used so that GHDL's library database does not
    pollute the source tree.

    Returns:
        (passed, detail_lines)
    """
    passed = True
    details: List[str] = []

    ghdl_ver = get_ghdl_version(GHDL_BIN)
    details.append(f"[VHDL] GHDL version: {ghdl_ver}")

    # Use a scratch workdir inside verification/work/ so artefacts are gitignored
    workdir = os.path.join(timer_path, "verification", "work", "ghdl_lint")
    os.makedirs(workdir, exist_ok=True)

    common_rtl_vhd = os.path.join(
        os.environ.get("IP_COMMON_PATH", os.path.join(timer_path, "..", "..", "common")),
        "design", "rtl", "vhdl"
    )

    def resolve_vhd(f: str) -> str:
        if f.startswith("common:"):
            return os.path.join(common_rtl_vhd, f[len("common:"):])
        return os.path.join(timer_path, f)

    for vhd_file in VHDL_FILES:
        abs_path = resolve_vhd(vhd_file)
        cmd = [GHDL_BIN, "-a", "--std=08", f"--workdir={workdir}", abs_path]

        details.append(f"[VHDL] Analysing {vhd_file} ...")
        rc, stdout, stderr = run_command(cmd, cwd=timer_path)
        output = (stdout + stderr).strip()

        if rc != 0:
            passed = False
            details.append(f"[VHDL] FAIL — {vhd_file}")
            for line in output.splitlines():
                details.append(f"       {line}")
        else:
            if output:
                # Warnings: GHDL emits them to stderr but exits 0
                has_warnings = any(
                    "warning" in line.lower() or "error" in line.lower()
                    for line in output.splitlines()
                )
                if has_warnings:
                    passed = False
                    details.append(f"[VHDL] FAIL (warnings) — {vhd_file}")
                    for line in output.splitlines():
                        details.append(f"       {line}")
                else:
                    details.append(f"[VHDL] PASS — {vhd_file}")
            else:
                details.append(f"[VHDL] PASS — {vhd_file}")

    return passed, details


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def main() -> None:
    # Guard: require CLAUDE_TIMER_PATH
    timer_path = require_env("CLAUDE_TIMER_PATH")
    common_path = os.environ.get(
        "IP_COMMON_PATH",
        os.path.normpath(os.path.join(timer_path, "..", "..", "common")),
    )

    parser = argparse.ArgumentParser(
        description="Run lint checks on the timer IP block RTL sources.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--lang",
        choices=SUPPORTED_LANGS,
        default="all",
        help="HDL language(s) to lint (default: %(default)s)",
    )
    args = parser.parse_args()

    lint_dir = os.path.join(timer_path, "verification", "lint")
    os.makedirs(lint_dir, exist_ok=True)
    results_log = os.path.join(lint_dir, "lint_results.log")

    timestamp = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    print(f"lint_timer.py — timer IP lint runner")
    print(f"  CLAUDE_TIMER_PATH = {timer_path}")
    print(f"  IP_COMMON_PATH    = {common_path}")
    print(f"  --lang            = {args.lang}")
    print(f"  timestamp         = {timestamp}")
    print()

    all_passed = True
    all_details: List[str] = [f"lint_timer.py run: {timestamp}", f"--lang={args.lang}"]

    if args.lang in ("sv", "all"):
        sv_passed, sv_details = run_sv_lint(timer_path, common_path)
        all_details.extend(sv_details)
        if not sv_passed:
            all_passed = False
            print("[SV]  FAIL — see details below")
        else:
            print("[SV]  PASS")
        for line in sv_details:
            print(f"  {line}")
        print()

    if args.lang in ("vhdl", "all"):
        vhdl_passed, vhdl_details = run_vhdl_lint(timer_path)
        all_details.extend(vhdl_details)
        if not vhdl_passed:
            all_passed = False
            print("[VHDL] FAIL — see details below")
        else:
            print("[VHDL] PASS")
        for line in vhdl_details:
            print(f"  {line}")
        print()

    # Write results log
    write_results_log(results_log, all_passed, all_details)
    result_str = "PASS" if all_passed else "FAIL"
    print(f"Result: {result_str}")
    print(f"Results log: {results_log}")

    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    main()
