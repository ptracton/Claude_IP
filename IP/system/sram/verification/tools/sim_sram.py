#!/usr/bin/env python3
"""sim_sram.py — Directed-simulation runner for the sram IP.

SKELETON (Step 1). The full implementation is ported from the timer's
sim_timer.py in Step 4 (directed_tests). Until then this script only checks its
environment, accepts the final command line, records FAIL in
verification/work/results.log and exits 1, so a regression can never mistake it for a pass.

Usage (final):
  python3 sim_sram.py --sim vcs --proto ahb --lang sv --tech generic
  python3 sim_sram.py --postsyn --pdk saed32 --proto apb
  python3 sim_sram.py --power --pdk sky130
"""

import argparse
import datetime
import os
import sys

STEP = 4


def main() -> int:
    # Guard: require CLAUDE_SRAM_PATH
    sram_path = os.environ.get("CLAUDE_SRAM_PATH")
    if not sram_path:
        print("ERROR: CLAUDE_SRAM_PATH is not set.")
        print("       Please run:  source IP/system/sram/setup.sh")
        sys.exit(1)

    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sim", choices=["icarus", "ghdl", "modelsim", "xsim", "vcs", "xcelium", "all"])
    parser.add_argument("--proto", choices=["apb", "ahb", "axi4l", "wb", "all"], default="all")
    parser.add_argument("--lang", choices=["sv", "vhdl", "all"], default="all")
    parser.add_argument("--tech", default="generic",
                        help="generic | xilinx | altera | saed90 | saed32 | saed14 | sky130")
    parser.add_argument("--test", default="all")
    parser.add_argument("--postsyn", action="store_true", help="gate-level simulation")
    parser.add_argument("--power", action="store_true", help="PrimePower (implies --postsyn)")
    parser.add_argument("--pdk", default="all")
    args = parser.parse_args()

    result = os.path.join(sram_path, "verification/work/results.log")
    os.makedirs(os.path.dirname(result), exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    with open(result, "w") as fh:
        fh.write(f"FAIL: not implemented yet (Step {STEP}, directed_tests) — {stamp}\n")
    print(f"FAIL: sim_sram.py is a Step 1 skeleton; implemented in Step {STEP} (directed_tests).")
    return 1


if __name__ == "__main__":
    sys.exit(main())
