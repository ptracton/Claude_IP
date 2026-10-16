#!/usr/bin/env python3
"""lint_sram.py — Lint runner (Verilator/VHDL lint; SpyGlass on csun.edu) for the sram IP.

SKELETON (Step 1). The full implementation is ported from the timer's
lint_timer.py in Step 8 (lint). Until then this script only checks its
environment, accepts the final command line, records FAIL in
verification/lint/lint_results.log and exits 1, so a regression can never mistake it for a pass.

Usage (final):
  python3 lint_sram.py --lang all
"""

import argparse
import datetime
import os
import sys

STEP = 8


def main() -> int:
    # Guard: require CLAUDE_SRAM_PATH
    sram_path = os.environ.get("CLAUDE_SRAM_PATH")
    if not sram_path:
        print("ERROR: CLAUDE_SRAM_PATH is not set.")
        print("       Please run:  source IP/system/sram/setup.sh")
        sys.exit(1)

    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--lang", choices=["sv", "vhdl", "all"], default="all")
    args = parser.parse_args()

    result = os.path.join(sram_path, "verification/lint/lint_results.log")
    os.makedirs(os.path.dirname(result), exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    with open(result, "w") as fh:
        fh.write(f"FAIL: not implemented yet (Step {STEP}, lint) — {stamp}\n")
    print(f"FAIL: lint_sram.py is a Step 1 skeleton; implemented in Step {STEP} (lint).")
    return 1


if __name__ == "__main__":
    sys.exit(main())
