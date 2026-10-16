#!/usr/bin/env python3
"""regression_sram.py — Regression runner (sim + formal + lint + UVM -> report.md) for the sram IP.

SKELETON (Step 1). The full implementation is ported from the timer's
regression_timer.py in Step 7 (regression). Until then this script only checks its
environment, accepts the final command line, records FAIL in
verification/regression/report.md and exits 1, so a regression can never mistake it for a pass.

Usage (final):
  python3 regression_sram.py
"""

import argparse
import datetime
import os
import sys

STEP = 7


def main() -> int:
    # Guard: require CLAUDE_SRAM_PATH
    sram_path = os.environ.get("CLAUDE_SRAM_PATH")
    if not sram_path:
        print("ERROR: CLAUDE_SRAM_PATH is not set.")
        print("       Please run:  source IP/system/sram/setup.sh")
        sys.exit(1)

    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--quick", action="store_true")
    args = parser.parse_args()

    result = os.path.join(sram_path, "verification/regression/report.md")
    os.makedirs(os.path.dirname(result), exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    with open(result, "w") as fh:
        fh.write(f"FAIL: not implemented yet (Step {STEP}, regression) — {stamp}\n")
    print(f"FAIL: regression_sram.py is a Step 1 skeleton; implemented in Step {STEP} (regression).")
    return 1


if __name__ == "__main__":
    sys.exit(main())
