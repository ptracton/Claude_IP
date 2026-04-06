#!/usr/bin/env python3
"""formal_bus_matrix.py — Run formal verification tasks on the bus_matrix RTL.

Uses SymbiYosys (sby) with .sby configurations in verification/formal/.
Writes verification/formal/results.log with PASS/FAIL/SKIP per task.

Usage:
    source IP/interface/bus_matrix/setup.sh
    python3 $CLAUDE_BUS_MATRIX_PATH/verification/tools/formal_bus_matrix.py
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path


def run_cmd(cmd, cwd=None, timeout=300):
    """Run a command, return (rc, stdout+stderr)."""
    print(f"  CMD: {' '.join(cmd)}")
    try:
        result = subprocess.run(
            cmd, cwd=cwd,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=timeout,
        )
        return result.returncode, result.stdout
    except subprocess.TimeoutExpired:
        return 1, "TIMEOUT"
    except FileNotFoundError:
        return 1, f"Tool not found: {cmd[0]}"


def main():
    ip_path = os.environ.get("CLAUDE_BUS_MATRIX_PATH")
    if not ip_path:
        print("ERROR: CLAUDE_BUS_MATRIX_PATH is not set.")
        print("       Please run:  source IP/interface/bus_matrix/setup.sh")
        sys.exit(1)

    ip_path = str(Path(ip_path).resolve())
    formal_dir = os.path.join(ip_path, "verification", "formal")
    work_dir = os.path.join(formal_dir, "work")
    os.makedirs(work_dir, exist_ok=True)
    result_log = os.path.join(formal_dir, "results.log")

    # Check if sby is available
    sby_bin = shutil.which("sby")
    if not sby_bin:
        print("  SKIP: sby (SymbiYosys) not found on PATH")
        with open(result_log, "w") as fh:
            fh.write("SKIP\n")
            fh.write("# sby not found on PATH\n")
        print(f"Formal results written to {result_log}")
        sys.exit(0)

    # Discover .sby files (exclude work directory)
    sby_files = sorted(
        f for f in Path(formal_dir).glob("*.sby")
        if "work" not in f.parts
    )

    if not sby_files:
        print("  SKIP: no .sby files found")
        with open(result_log, "w") as fh:
            fh.write("SKIP\n")
            fh.write("# no .sby files found\n")
        sys.exit(0)

    overall_pass = True
    entries = []

    for sby_path in sby_files:
        name = sby_path.stem
        task_work = os.path.join(work_dir, name)

        print(f"\n  Running sby on {name}...")
        rc, out = run_cmd(
            [sby_bin, "-f", "-d", task_work, str(sby_path)],
            cwd=formal_dir,
        )

        if rc == 0:
            entries.append(f"[{name}] PASS")
            print(f"  [{name}] PASS")
        else:
            entries.append(f"[{name}] FAIL")
            overall_pass = False
            print(f"  [{name}] FAIL")
            # Print last few lines of output for debugging
            for line in out.strip().splitlines()[-5:]:
                print(f"    {line}")

    status = "PASS" if overall_pass else "FAIL"
    with open(result_log, "w") as fh:
        fh.write(f"{status}\n")
        fh.write(f"# formal verification results\n")
        for entry in entries:
            fh.write(f"{entry}\n")

    print(f"\nFormal results written to {result_log}")
    sys.exit(0 if overall_pass else 1)


if __name__ == "__main__":
    main()
