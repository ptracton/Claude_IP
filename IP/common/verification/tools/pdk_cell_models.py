#!/usr/bin/env python3
"""pdk_cell_models.py — Standard-cell simulation models with vendor bugs fixed.

Gate-level simulation compiles the PDK's standard-cell Verilog models with a
Design Compiler netlist. DC maps logic onto a cell by its liberty function,
so a model that disagrees with the liberty simulates a netlist differently
from what DC built. This module writes corrected copies of such models into a
work directory; the vendor files are never modified (as pdk_sram_models.py
does for the SRAM macros).

Fixes:
  SAED90 (Digital_Standard_cell_Library/verilog/saed90nm.v)
    DFFSSRX1/X2 (synchronous set / reset flip-flops): the liberty's
    next_state is (RSTB*D)+(!SETB) — set wins — but the model computes
    (!SETB + D) * RSTB — reset wins. They differ when SETB and RSTB are both
    low, which DC uses (found 2026-11-25: sram_axi4l_dp_vhdl on SAED90, the
    port-A AXI interface's sel_write_q, simulated wrongly even with zero
    delay). SDFFSSRX1/X2 (scan versions): liberty (SI*SE)+(RSTB*D*SE')+
    (!SETB), model SE ? SI : (!SETB + D) * RSTB — also wrong when SE is high
    with SETB low. The copies compute the liberty function.
  SAED32, SAED14, SKY130: used as shipped.

Usage:
  from pdk_cell_models import cell_files
  files = cell_files("saed90", work_dir)            # list of .v paths to compile

  python3 pdk_cell_models.py <pdk> <work_dir>       # prints the file list
"""

import os
import re
import sys
from typing import List

SAED90_CELLS = ("/opt/ECE_Lib/SAED90nm_EDK_10072017/SAED90_EDK/SAED_EDK90nm/"
                "Digital_Standard_cell_Library/verilog/saed90nm.v")

SAED90_SSR = ("DFFSSRX1", "DFFSSRX2")
SAED90_SSSR = ("SDFFSSRX1", "SDFFSSRX2")

_NOTE = "    // [pdk_cell_models.py] next state as the liberty: (RSTB*D)+(!SETB), set wins\n"
_NOTE_S = ("    // [pdk_cell_models.py] next state as the liberty: "
           "(SI*SE)+(RSTB*D*SE')+(!SETB), set wins\n")


def _module_span(text: str, name: str) -> tuple:
    m = re.search(rf"^module\s+{name}\s*\(", text, re.M)
    if not m:
        raise ValueError(f"SAED90 cell model: module {name} not found (model changed?)")
    end = text.find("endmodule", m.start())
    return m.start(), end


def fix_saed90(text: str) -> str:
    """Make the SSR flip-flops' next state match the liberty."""
    for name in SAED90_SSR + SAED90_SSSR:
        a, b = _module_span(text, name)
        body = text[a:b]
        old = re.search(r"^\s*or\s*\(\s*DS\s*,\s*S\s*,\s*D\s*\)\s*;\s*\n"
                        r"\s*and\s*\(\s*D1\s*,\s*DS\s*,\s*RSTB\s*\)\s*;\s*\n", body, re.M)
        if not old:
            raise ValueError(f"SAED90 cell model {name}: next-state gates not found (model changed?)")
        if name in SAED90_SSR:
            new = (_NOTE + "    wire DR;\n    and (DR, D, RSTB);\n    or  (D1, DR, S);\n")
            body = body[:old.start()] + new + body[old.end():]
        else:
            mux = re.search(r"^\s*saed90_mux\s*\(\s*D2\s*,\s*D1\s*,\s*SI\s*,\s*SE\s*\)\s*;\s*\n",
                            body, re.M)
            if not mux:
                raise ValueError(f"SAED90 cell model {name}: scan mux not found (model changed?)")
            # remove the mux first (it follows the gates), then the gates
            body = body[:mux.start()] + body[mux.end():]
            new = (_NOTE_S + "    wire DR, DM;\n    and (DR, D, RSTB);\n"
                   "    saed90_mux (DM, DR, SI, SE);\n    or  (D2, DM, S);\n"
                   "    assign D1 = DR;\n")
            body = body[:old.start()] + new + body[old.end():]
        text = text[:a] + body + text[b:]
    return text


def cell_files(pdk: str, work_dir: str) -> List[str]:
    """Corrected copies of the standard-cell models of *pdk* that need one
    (others: an empty list; the caller compiles the vendor files)."""
    if pdk != "saed90":
        return []
    os.makedirs(work_dir, exist_ok=True)
    dst = os.path.join(work_dir, "saed90nm_fixed.v")
    with open(SAED90_CELLS) as fh:
        fixed = fix_saed90(fh.read())
    with open(dst, "w") as fh:
        fh.write(fixed)
    return [dst]


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    print(" ".join(cell_files(sys.argv[1], sys.argv[2])))
