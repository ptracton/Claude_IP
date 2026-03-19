#!/usr/bin/env python3
"""formal_timer.py — Formal verification runner for the timer IP block.

Invokes SymbiYosys for each bus-protocol variant and collects results.
Results are written to:
    ${CLAUDE_TIMER_PATH}/verification/formal/results.log

Usage:
    python3 verification/tools/formal_timer.py
    python3 verification/tools/formal_timer.py --depth 30
    python3 verification/tools/formal_timer.py --clean
"""

import argparse
import os
import shutil
import subprocess
import sys

PROTOCOLS = ["apb", "ahb", "axi4l", "wb"]
SBY_PATH = "/opt/oss-cad-suite/bin/sby"


def find_sby():
    """Return path to sby, checking SBY_PATH then PATH."""
    if os.path.isfile(SBY_PATH) and os.access(SBY_PATH, os.X_OK):
        return SBY_PATH
    found = shutil.which("sby")
    if found:
        return found
    return None


def run_protocol(sby, formal_dir, proto, depth, work_dir):
    """Run sby for one protocol. Returns (proto, passed, log_lines)."""
    sby_file = os.path.join(formal_dir, f"timer_{proto}.sby")
    out_dir = os.path.join(work_dir, f"timer_{proto}")

    cmd = [sby, "-f", sby_file, "-d", out_dir]
    print(f"[formal] Running timer_{proto} ...")

    result = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        cwd=formal_dir,
    )

    passed = result.returncode == 0
    status = "PASS" if passed else "FAIL"
    print(f"[formal] timer_{proto}: {status}")

    log_lines = [f"  timer_{proto}: {status}\n"]
    log_lines += [f"    {line}\n" for line in result.stdout.splitlines()
                  if "DONE" in line or "failed assertion" in line or "Status:" in line]
    return proto, passed, log_lines


def do_clean(formal_dir):
    """Remove sby run directories."""
    print("Cleaning formal verification artifacts...")
    for proto in PROTOCOLS:
        for d in [
            os.path.join(formal_dir, f"timer_{proto}"),
            os.path.join(formal_dir, "work", f"timer_{proto}"),
        ]:
            if os.path.isdir(d):
                shutil.rmtree(d)
                print(f"  removed {d}")
    work = os.path.join(formal_dir, "work")
    if os.path.isdir(work):
        shutil.rmtree(work)
        print(f"  removed {work}")
    print("Formal clean complete.")


def main():
    timer_path = os.environ.get("CLAUDE_TIMER_PATH")
    if not timer_path:
        print("ERROR: CLAUDE_TIMER_PATH is not set.")
        print("       Please run:  source timer/setup.sh")
        sys.exit(1)

    parser = argparse.ArgumentParser(
        description="Run formal verification checks on the timer IP block."
    )
    parser.add_argument(
        "--depth",
        type=int,
        default=20,
        help="BMC depth in clock cycles (default: %(default)s)",
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Remove sby run directories and exit",
    )
    args = parser.parse_args()

    formal_dir = os.path.join(timer_path, "verification", "formal")
    results_log = os.path.join(formal_dir, "results.log")

    if args.clean:
        do_clean(formal_dir)
        sys.exit(0)

    sby = find_sby()
    if not sby:
        print("ERROR: sby not found. Install oss-cad-suite or add sby to PATH.")
        sys.exit(1)

    work_dir = os.path.join(formal_dir, "work")
    os.makedirs(work_dir, exist_ok=True)

    pass_count = 0
    fail_count = 0
    all_log_lines = []

    for proto in PROTOCOLS:
        proto, passed, log_lines = run_protocol(sby, formal_dir, proto, args.depth, work_dir)
        all_log_lines += log_lines
        if passed:
            pass_count += 1
        else:
            fail_count += 1

    overall = "PASS" if fail_count == 0 else "FAIL"

    print()
    print("============================================")
    print("Formal Verification Results")
    print("============================================")
    for line in all_log_lines:
        if line.strip().startswith("timer_"):
            print(" ", line.strip())
    print(f"PASS: {pass_count}  FAIL: {fail_count}")
    print("============================================")

    with open(results_log, "w") as fh:
        fh.write(f"{overall}\n")
        for line in all_log_lines:
            fh.write(line)
        fh.write(f"PASS: {pass_count}  FAIL: {fail_count}\n")

    print(f"Results written to: {results_log}")

    if fail_count == 0:
        print("All formal checks PASSED.")
        sys.exit(0)
    else:
        print("One or more formal checks FAILED.")
        sys.exit(1)


if __name__ == "__main__":
    main()
