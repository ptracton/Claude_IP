#!/usr/bin/env python3
"""ip_tool_base.py — Shared base class for all Claude_IP tool scripts.

Provides:
  - Environment-variable guard helper
  - Subprocess runner with captured output and return code
  - Results-log writer (PASS / FAIL)
  - Version string helpers for Verilator and GHDL

All IP-specific tool scripts (lint_<IP>.py, sim_<IP>.py, …) should import
this module from ${IP_COMMON_PATH}/verification/tools/ip_tool_base.py.
"""

import os
import subprocess
import sys
from datetime import datetime
from typing import List, Optional, Tuple


# ---------------------------------------------------------------------------
# Environment guard
# ---------------------------------------------------------------------------

def require_env(var_name: str) -> str:
    """Return the value of environment variable *var_name* or abort.

    If the variable is not set or is empty this function prints a clear error
    message and calls ``sys.exit(1)``.  It never returns an empty string.

    Args:
        var_name: Name of the required environment variable.

    Returns:
        The non-empty string value of the variable.
    """
    value = os.environ.get(var_name, "")
    if not value:
        print(f"ERROR: {var_name} is not set.")
        print(f"       Please source the appropriate setup.sh before running this script.")
        sys.exit(1)
    return value


# ---------------------------------------------------------------------------
# Subprocess runner
# ---------------------------------------------------------------------------

def run_command(
    cmd: List[str],
    cwd: Optional[str] = None,
    capture: bool = True,
) -> Tuple[int, str, str]:
    """Run *cmd* as a subprocess and return (returncode, stdout, stderr).

    Args:
        cmd:     Command and arguments as a list of strings.
        cwd:     Working directory for the subprocess (default: current dir).
        capture: If True, capture stdout/stderr; if False, let them pass
                 through to the terminal and return empty strings.

    Returns:
        A three-tuple ``(returncode, stdout, stderr)``.
        *stdout* and *stderr* are decoded UTF-8 strings (empty when
        *capture* is False).
    """
    if capture:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return result.returncode, result.stdout, result.stderr
    else:
        result = subprocess.run(cmd, cwd=cwd)
        return result.returncode, "", ""


# ---------------------------------------------------------------------------
# Results-log writer
# ---------------------------------------------------------------------------

def write_results_log(
    log_path: str,
    passed: bool,
    details: Optional[List[str]] = None,
) -> None:
    """Write *log_path* with a PASS or FAIL result line and optional details.

    The log file is always overwritten.  The first line is either ``PASS`` or
    ``FAIL``.  Subsequent lines contain *details* (if provided) and a
    timestamp.

    Args:
        log_path: Absolute path of the results log file.
        passed:   True → write "PASS"; False → write "FAIL".
        details:  Optional list of additional lines to append.
    """
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    result_str = "PASS" if passed else "FAIL"
    timestamp = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    lines = [result_str, f"Generated: {timestamp}"]
    if details:
        lines.extend(details)
    with open(log_path, "w") as fh:
        fh.write("\n".join(lines) + "\n")


# ---------------------------------------------------------------------------
# Tool-version helpers
# ---------------------------------------------------------------------------

def get_verilator_version(verilator_bin: str = "verilator") -> str:
    """Return the Verilator version string, or 'unknown' on failure."""
    try:
        rc, stdout, stderr = run_command([verilator_bin, "--version"])
        if rc == 0 and stdout.strip():
            return stdout.splitlines()[0].strip()
        return "unknown"
    except FileNotFoundError:
        return "not found"


def get_ghdl_version(ghdl_bin: str = "ghdl") -> str:
    """Return the GHDL version string, or 'unknown' on failure."""
    try:
        rc, stdout, stderr = run_command([ghdl_bin, "--version"])
        output = stdout or stderr
        if output.strip():
            return output.splitlines()[0].strip()
        return "unknown"
    except FileNotFoundError:
        return "not found"
