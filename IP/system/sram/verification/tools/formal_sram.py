#!/usr/bin/env python3
"""formal_sram.py — Formal-verification runner (VC Formal; SymbiYosys on standard hosts) for the sram IP.

SKELETON (Step 1). The full implementation is ported from the timer's
formal_timer.py in Step 5 (formal). Until then this script only checks its
environment, accepts the final command line, records FAIL in
verification/formal/vcf/results.log and exits 1, so a regression can never mistake it for a pass.

Usage (final):
  python3 formal_sram.py --proto all --lang all
  python3 formal_sram.py --clean
"""

import argparse
import datetime
import os
import sys

STEP = 5


def main() -> int:
    # Guard: require CLAUDE_SRAM_PATH
    sram_path = os.environ.get("CLAUDE_SRAM_PATH")
    if not sram_path:
        print("ERROR: CLAUDE_SRAM_PATH is not set.")
        print("       Please run:  source IP/system/sram/setup.sh")
        sys.exit(1)

    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--proto", choices=["apb", "ahb", "axi4l", "wb", "all"], default="all")
    parser.add_argument("--lang", choices=["sv", "vhdl", "all"], default="all")
    parser.add_argument("--max-time", default="30M")
    parser.add_argument("--clean", action="store_true")
    args = parser.parse_args()
    if getattr(args, "clean", False):
        import shutil
        shutil.rmtree(os.path.join(sram_path, "verification", "formal", "work"), ignore_errors=True)
        print("Removed verification/formal/work")
        return 0

    result = os.path.join(sram_path, "verification/formal/vcf/results.log")
    os.makedirs(os.path.dirname(result), exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    with open(result, "w") as fh:
        fh.write(f"FAIL: not implemented yet (Step {STEP}, formal) — {stamp}\n")
    print(f"FAIL: formal_sram.py is a Step 1 skeleton; implemented in Step {STEP} (formal).")
    return 1


if __name__ == "__main__":
    sys.exit(main())
