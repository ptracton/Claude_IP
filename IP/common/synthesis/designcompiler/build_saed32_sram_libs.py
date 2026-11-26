#!/usr/bin/env python3
"""build_saed32_sram_libs.py — Patched SAED32 low-power SRAM libraries (.db).

The SAED32 EDK's low-power SRAM liberty (lib/sram_lp/db_nldm/
saed32sramlp_<corner>.lib / .db) omits the macros' power-control pins, while
the vendor LEF (lib/sram_lp/lef/saed32sram.lef) and Verilog model
(lib/sram_lp/verilog/saed32sram.v) have them:

    SRAMLP1RW<d>x<w> : SD, LS, DS
    SRAMLP2RW<d>x<w> : SD, LS1, LS2, DS1, DS2

Design Compiler then cannot link any design that drives them (LINK-1 "Can't
find inout port 'SD'"). This module writes a copy of each requested corner's
.lib with those pins added to every SRAMLP cell as plain inputs (direction
input, the capacitance of the cell's chip-select pin CSB / CSB1, no timing or
power arcs) and compiles it to .db with lc_shell. The vendor files are never
edited. STA sees the added pins as unconstrained inputs: their timing is not
characterized in the EDK (see IP/system/sram/synthesis/known_issues.md).

Compiled .db files are cached in saed32_lib/ next to this script (mtime-checked
against the vendor .lib), shared by every IP, as sky130_lib/ is.

Usage:
    python3 build_saed32_sram_libs.py                    # default corners
    python3 build_saed32_sram_libs.py --corner tt1p05v25c_i1p05v --force

    sys.path.insert(0, str(Path(IP_COMMON_PATH) / "synthesis" / "designcompiler"))
    import build_saed32_sram_libs
    db = build_saed32_sram_libs.ensure_saed32_sram_db("ss0p95v125c_i0p95v")
"""

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional

SAED32_EDK = "/opt/ECE_Lib/SAED32_EDK"
VENDOR_DIR = Path(SAED32_EDK) / "lib" / "sram_lp" / "db_nldm"
CACHE_DIR = Path(__file__).resolve().parent / "saed32_lib"

# Synthesis corner (worst case, matches saed32rvt_ss0p95v125c) and the
# typical corner used by STA / power.
DEFAULT_CORNERS = ["ss0p95v125c_i0p95v", "tt1p05v25c_i1p05v"]

ADDED_PINS = {
    "SRAMLP1RW": (["SD", "LS", "DS"], "CSB"),
    "SRAMLP2RW": (["SD", "LS1", "LS2", "DS1", "DS2"], "CSB1"),
}

_CELL_RE = re.compile(r"^(\s*)cell\s*\(\s*\"?(SRAMLP[12]RW\w+?)\"?\s*\)\s*\{")
_LIB_RE = re.compile(r"^\s*library\s*\(\s*\"?([\w.]+)\"?\s*\)")


def _block_end(lines: list, start: int) -> int:
    """Index of the line that closes the brace block opened on line start."""
    depth = 0
    for i in range(start, len(lines)):
        depth += lines[i].count("{") - lines[i].count("}")
        if depth == 0:
            return i
    raise ValueError(f"unbalanced braces from line {start + 1}")


def patch_lib(text: str) -> tuple:
    """Return (patched text, library name, number of cells patched)."""
    lines = text.splitlines(keepends=True)
    lib_name = next((m.group(1) for m in map(_LIB_RE.match, lines) if m), None)
    if lib_name is None:
        raise ValueError("no library() statement")
    out, i, n = [], 0, 0
    while i < len(lines):
        m = _CELL_RE.match(lines[i])
        if not m:
            out.append(lines[i])
            i += 1
            continue
        end = _block_end(lines, i)
        cell = lines[i:end + 1]
        pins, ref = ADDED_PINS[m.group(2)[:9]]
        body = "".join(cell)
        ref_m = re.search(rf"pin\s*\(\s*\"?{ref}\"?\s*\)\s*\{{(.*?)capacitance\s*:\s*([\d.eE+-]+)",
                          body, re.S)
        if not ref_m:
            raise ValueError(f"{m.group(2)}: no capacitance on pin {ref}")
        cap = ref_m.group(2)
        present = [p for p in pins if re.search(rf"pin\s*\(\s*\"?{p}\"?\s*\)", body)]
        missing = [p for p in pins if p not in present]
        ind = m.group(1) + "\t"
        added = []
        for p in missing:
            added += [f"{ind}pin({p}) {{\n",
                      f"{ind}\t/* added by build_saed32_sram_libs.py: present in the vendor\n",
                      f"{ind}\t   LEF and Verilog model, missing from the vendor liberty */\n",
                      f"{ind}\trelated_power_pin : VDD;\n",
                      f"{ind}\trelated_ground_pin : VSS;\n",
                      f"{ind}\tdirection : input;\n",
                      f"{ind}\tcapacitance : {cap};\n",
                      f"{ind}}}\n"]
        cell = fix_output_buses(cell)
        # insert just before the cell's closing brace
        out += cell[:-1] + added + [cell[-1]]
        n += 1 if missing else 0
        i = end + 1
    return "".join(out), lib_name, n


_BUS_RE = re.compile(r"^\s*bus\s*\(\s*\"?(O[12]?)\"?\s*\)\s*\{")
_MINCAP_RE = re.compile(r"^\s*min_capacitance\s*:\s*([\d.eE+-]+)\s*;")
_MAXCAP_RE = re.compile(r"^\s*max_capacitance\s*:\s*([\d.eE+-]+)\s*;")
_IPWR_RE = re.compile(r"^(\s*)internal_power\s*\(\s*\)\s*\{")


def fix_output_buses(cell: list) -> list:
    """Repair the two vendor defects that current lc_shell rejects (the shipped
    .db was compiled by an older Library Compiler), on the read-data buses
    O / O1 / O2 only:
      - min_capacitance (0.1) greater than max_capacitance (0.025), LBDB-596:
        the min_capacitance line is dropped (a design-rule limit, no timing);
      - internal_power() without related_pin: related to the port's clock
        (O: CE, O1: CE1, O2: CE2), the pin every read-data change follows."""
    out, i = [], 0
    while i < len(cell):
        m = _BUS_RE.match(cell[i])
        if not m:
            out.append(cell[i])
            i += 1
            continue
        end = _block_end(cell, i)
        bus = cell[i:end + 1]
        clk = {"O": "CE", "O1": "CE1", "O2": "CE2"}[m.group(1)]
        maxcap = next((float(x.group(1)) for x in map(_MAXCAP_RE.match, bus) if x), None)
        j = 0
        while j < len(bus):
            ln = bus[j]
            mc = _MINCAP_RE.match(ln)
            if mc and maxcap is not None and float(mc.group(1)) > maxcap:
                out.append(f"{ln[:len(ln) - len(ln.lstrip())]}/* min_capacitance "
                           f"{mc.group(1)} > max_capacitance {maxcap} dropped "
                           f"(build_saed32_sram_libs.py) */\n")
                j += 1
                continue
            mi = _IPWR_RE.match(ln)
            if mi:
                grp_end = j + _block_end(bus[j:], 0)
                if not any("related_pin" in x for x in bus[j:grp_end + 1]):
                    out.append(ln)
                    out.append(f"{mi.group(1)}\trelated_pin : \"{clk}\"; "
                               f"/* added by build_saed32_sram_libs.py */\n")
                    j += 1
                    continue
            out.append(ln)
            j += 1
        i = end + 1
    return out


def ensure_saed32_sram_db(corner: str, cache_dir: Path = CACHE_DIR,
                          force: bool = False) -> Optional[str]:
    """Patched .db for one corner (built and cached on first use), or None."""
    src = VENDOR_DIR / f"saed32sramlp_{corner}.lib"
    if not src.is_file():
        print(f"  ERROR: SAED32 SRAM library not found: {src}")
        return None
    cache_dir.mkdir(parents=True, exist_ok=True)
    db = cache_dir / f"saed32sramlp_{corner}_pins.db"
    if not force and db.exists() and db.stat().st_mtime >= src.stat().st_mtime:
        return str(db)

    try:
        text, lib_name, n = patch_lib(src.read_text())
    except ValueError as e:
        print(f"  ERROR: patching {src.name}: {e}")
        return None
    lib = cache_dir / f"saed32sramlp_{corner}_pins.lib"
    lib.write_text(text)
    lc_shell = shutil.which("lc_shell")
    if not lc_shell:
        print("  ERROR: lc_shell not found on PATH — needed to compile the patched SAED32 SRAM .lib")
        return None
    tcl = cache_dir / f"compile_{corner}.tcl"
    tcl.write_text(f'read_lib "{lib}"\nwrite_lib {lib_name} -output "{db}"\nquit\n')
    print(f"  Compiling patched SAED32 SRAM library {corner} ({n} cells) -> .db (lc_shell)")
    try:
        res = subprocess.run([lc_shell, "-f", str(tcl)], stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, universal_newlines=True,
                             timeout=900, cwd=str(cache_dir))
    except subprocess.TimeoutExpired:
        print("  ERROR: lc_shell timed out compiling the SAED32 SRAM library")
        return None
    log = cache_dir / f"lc_{corner}.log"
    log.write_text(res.stdout)
    if not db.exists():
        print(f"  ERROR: lc_shell did not write {db.name} (exit {res.returncode}); see {log}")
        return None
    return str(db)


def main() -> None:
    ap = argparse.ArgumentParser(description="Patched SAED32 low-power SRAM .db (shared cache)")
    ap.add_argument("--corner", action="append", help=f"corner(s) (default {DEFAULT_CORNERS})")
    ap.add_argument("--force", action="store_true", help="rebuild even if the cache is fresh")
    args = ap.parse_args()
    ok = True
    for c in args.corner or DEFAULT_CORNERS:
        db = ensure_saed32_sram_db(c, force=args.force)
        print(f"  {c:<22} {db or 'FAILED'}")
        ok = ok and db is not None
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
