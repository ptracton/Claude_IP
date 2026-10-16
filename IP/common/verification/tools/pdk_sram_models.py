#!/usr/bin/env python3
"""pdk_sram_models.py — Simulation models of PDK SRAM macros, with vendor bugs fixed.

Some vendor SRAM simulation models do not compile, or do not behave like the
macro, so this module writes corrected copies into a work directory. The
vendor files are never modified. Used by every IP that simulates SRAM macros
(RTL with real macros, and gate-level netlists).

Fixes:
  SAED14 (SAED14nm_EDK_SRAM/verilog/saed14sram.v)
    Outside POWER_AWARE_MODE, every SRAM1RW* model assigns O_ud (SRAM2RW*:
    O1_ud, O2_ud) without declaring it and never drives the output, so reads
    return Z. The fix declares the register and drives the output from it:
    the read is registered on the clock (CE->O arc in the liberty) and, for
    SRAM1RW*, O is 0 after any non-read cycle, as in the model's own code.
  SKY130 OpenRAM (libs.ref/sky130_sram_macros/verilog/*.v)
    The memory array `mem` is used in an always block before it is
    declared, which VCS rejects (Error-[IND]). The fix moves the
    declaration above the first use.
  SAED90, SAED32 low-power: used as shipped (no fixes needed).

Usage:
  from pdk_sram_models import model_files
  files = model_files("saed14", work_dir)          # list of .v paths to compile

  python3 pdk_sram_models.py <pdk> <work_dir>      # prints the file list
"""

import os
import re
import sys
from typing import List

SAED90_MEM = "/opt/ECE_Lib/SAED90nm_EDK_10072017/SAED90_EDK/SAED_EDK90nm/Memories/verilog"
SAED32_SRAM_LP = "/opt/ECE_Lib/SAED32_EDK/lib/sram_lp/verilog/saed32sram.v"
SAED14_SRAM = "/opt/ECE_Lib/SAED14nm_EDK_03_2025/SAED14nm_EDK_SRAM/verilog/saed14sram.v"
SKY130_SRAM_MACROS = ["sky130_sram_1kbyte_1rw1r_32x256_8",
                      "sky130_sram_2kbyte_1rw1r_32x512_8",
                      "sky130_sram_1kbyte_1rw1r_8x1024_8"]


def _sky130_pdk() -> str:
    pdk = os.environ.get("CLAUDE_SKY130_PDK_PATH", "")
    if not pdk:
        raise RuntimeError("CLAUDE_SKY130_PDK_PATH is not set (source the IP's setup.sh)")
    return pdk


def fix_saed14(text: str) -> str:
    """Declare every undeclared <out>_ud register and drive <out> from it.

    Applies to the non-POWER_AWARE branch of each SRAM1RW* (O_ud -> O) and
    SRAM2RW* (O1_ud -> O1, O2_ud -> O2) model.
    """
    parts = re.split(r"(?=^module )", text, flags=re.M)
    fixed_any = False
    for i, mod in enumerate(parts):
        if not mod.startswith("module "):
            continue
        m = re.search(r"`else\s*\n(.*?)`endif", mod, re.S)
        if not m:
            continue
        names = sorted(set(re.findall(r"\b(\w+)_ud\s*<=", m.group(1))))
        decls = []
        for name in names:
            if re.search(rf"^\s*reg\s+\[\d+:0\]\s+{name}_ud\b", m.group(1), re.M):
                continue  # already declared in this branch
            msb = None
            # "output [N:0] O" or a list such as "output [7:0]O1,O2".
            for w, names_txt in re.findall(r"output\s*\[(\d+):0\]\s*([\w\s,]+)", mod):
                if name in [n.strip() for n in names_txt.split(",")]:
                    msb = w
            if msb is None:
                raise ValueError(f"saed14sram.v: cannot find the width of output {name}")
            decls.append(f"reg   [{msb}:0] {name}_ud ;\nassign {name} = {name}_ud;\n")
        if decls:
            note = "// [pdk_sram_models.py] *_ud declared and outputs driven (vendor model bug)\n"
            ins = m.start(1)
            parts[i] = mod[:ins] + note + "".join(decls) + mod[ins:]
            fixed_any = True
    if not fixed_any:
        raise ValueError("saed14sram.v: fix pattern not found (model changed?)")
    return "".join(parts)


def fix_sky130(text: str) -> str:
    """Move the `mem` declaration above its first use."""
    m = re.search(r"^\s*reg\s+\[DATA_WIDTH-1:0\]\s+mem\s*\[0:RAM_DEPTH-1\];\s*$", text, re.M)
    if not m:
        raise ValueError("sky130 SRAM model: mem declaration not found (model changed?)")
    decl = m.group(0).strip()
    text = text[:m.start()] + text[m.end():]
    anchor = re.search(r"^\s*reg\s+\[DATA_WIDTH-1:0\]\s+dout0;\s*$", text, re.M)
    if not anchor:
        raise ValueError("sky130 SRAM model: dout0 declaration not found (model changed?)")
    note = "  // [pdk_sram_models.py] mem declared before use (vendor model bug)\n"
    return text[:anchor.end()] + "\n" + note + "  " + decl + text[anchor.end():]


def model_files(pdk: str, work_dir: str) -> List[str]:
    """Verilog files to compile for the SRAM macros of *pdk*."""
    os.makedirs(work_dir, exist_ok=True)
    if pdk == "saed90":
        return sorted(os.path.join(SAED90_MEM, f) for f in os.listdir(SAED90_MEM)
                      if re.fullmatch(r"SRAM\d+x\d+(_1rw)?\.v", f))
    if pdk == "saed32":
        return [SAED32_SRAM_LP]
    if pdk == "saed14":
        dst = os.path.join(work_dir, "saed14sram_fixed.v")
        with open(SAED14_SRAM) as fh:
            fixed = fix_saed14(fh.read())
        with open(dst, "w") as fh:
            fh.write(fixed)
        return [dst]
    if pdk == "sky130":
        src_dir = os.path.join(_sky130_pdk(), "libs.ref", "sky130_sram_macros", "verilog")
        files = []
        for name in SKY130_SRAM_MACROS:
            with open(os.path.join(src_dir, f"{name}.v")) as fh:
                fixed = fix_sky130(fh.read())
            dst = os.path.join(work_dir, f"{name}_fixed.v")
            with open(dst, "w") as fh:
                fh.write(fixed)
            files.append(dst)
        return files
    raise ValueError(f"unknown PDK '{pdk}' (saed90, saed32, saed14, sky130)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    print(" ".join(model_files(sys.argv[1], sys.argv[2])))
