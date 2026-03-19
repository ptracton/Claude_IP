#!/usr/bin/env python3
"""run_formal.py — Run SymbiYosys formal verification for the timer IP.

Usage:
    python3 run_formal.py [--proto apb|ahb|axi4l|wb|all]

The script resolves the formal directory relative to its own location
(../formal from tools/), so CLAUDE_TIMER_PATH is not required.
Results are written to:
    <timer_root>/verification/work/formal/<proto>/results.log
"""

import argparse
import os
import subprocess
import sys

SBY = "/opt/oss-cad-suite/bin/sby"
SUPPORTED_PROTOS = ["ahb", "apb", "axi4l", "wb"]


def get_timer_path() -> str:
    """Return the timer IP root directory.

    Preference order:
      1. CLAUDE_TIMER_PATH environment variable (explicit override)
      2. Derived from this script's location: ../../ relative to tools/
    """
    env_path = os.environ.get("CLAUDE_TIMER_PATH")
    if env_path:
        return env_path
    # Derive from script location: tools/ -> verification/ -> timer root
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.normpath(os.path.join(script_dir, "..", ".."))


def run_formal(proto: str, timer_path: str) -> bool:
    """Run SymbiYosys for one protocol variant. Returns True on PASS."""
    formal_dir = os.path.join(timer_path, "verification", "formal")
    work_dir   = os.path.join(timer_path, "verification", "work", "formal", proto)
    sby_file   = os.path.join(formal_dir, f"timer_{proto}.sby")
    results    = os.path.join(work_dir, "results.log")

    os.makedirs(work_dir, exist_ok=True)

    if not os.path.isfile(sby_file):
        msg = f"ERROR: .sby file not found: {sby_file}"
        print(f"  [formal/{proto}] {msg}")
        _write_result(results, "FAIL", msg)
        return False

    print(f"  [formal/{proto}] Running SymbiYosys ...")
    try:
        cp = subprocess.run(
            [SBY, "-f", sby_file, "-d", os.path.join(formal_dir, "work", f"timer_{proto}")],
            capture_output=True,
            text=True,
            timeout=300,
            cwd=formal_dir,
        )
    except FileNotFoundError:
        msg = f"ERROR: sby not found at {SBY}"
        print(f"  [formal/{proto}] {msg}")
        _write_result(results, "FAIL", msg)
        return False
    except subprocess.TimeoutExpired:
        msg = "ERROR: sby timed out after 300 s"
        print(f"  [formal/{proto}] {msg}")
        _write_result(results, "FAIL", msg)
        return False

    out = cp.stdout + cp.stderr
    print(f"  [formal/{proto}] Output:\n{out.strip()}")

    passed = cp.returncode == 0
    _write_result(results, "PASS" if passed else "FAIL", out)
    return passed


def _write_result(path: str, status: str, detail: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(f"{status}\n{detail}")
    print(f"  -> {path} : {status}")


def main() -> None:
    timer_path = get_timer_path()

    parser = argparse.ArgumentParser(
        description="Run SymbiYosys formal verification for the timer IP."
    )
    parser.add_argument(
        "--proto",
        choices=SUPPORTED_PROTOS + ["all"],
        default="all",
        help="Protocol variant to verify (default: all)",
    )
    args = parser.parse_args()

    protos = SUPPORTED_PROTOS if args.proto == "all" else [args.proto]
    all_pass = True
    summary = []

    print(f"Timer IP root : {timer_path}")
    print(f"Protocols     : {', '.join(protos)}")
    print()

    for proto in protos:
        ok = run_formal(proto, timer_path)
        summary.append((proto, "PASS" if ok else "FAIL"))
        if not ok:
            all_pass = False

    print()
    print("=" * 50)
    print("Formal Verification Summary")
    print("=" * 50)
    for p, s in summary:
        print(f"  formal/{p:<10} {s}")
    print("=" * 50)

    sys.exit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
