#!/usr/bin/env python3
"""uvm_sram.py — UVM runner (VCS on csun.edu, Vivado xsim elsewhere) for the sram IP.

SKELETON (Step 1). The full implementation is ported from the timer's
uvm_timer.py in Step 6 (uvm). Until then this script only checks its
environment, accepts the final command line, records FAIL in
verification/work/uvm/results.log and exits 1, so a regression can never mistake it for a pass.

Usage (final):
  python3 uvm_sram.py --proto all --test sram_random_test
"""

import argparse
import datetime
import os
import sys

STEP = 6


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
    parser.add_argument("--test", default="all")
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()

    result = os.path.join(sram_path, "verification/work/uvm/results.log")
    os.makedirs(os.path.dirname(result), exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    with open(result, "w") as fh:
        fh.write(f"FAIL: not implemented yet (Step {STEP}, uvm) — {stamp}\n")
    print(f"FAIL: uvm_sram.py is a Step 1 skeleton; implemented in Step {STEP} (uvm).")
    return 1


if __name__ == "__main__":
    sys.exit(main())
