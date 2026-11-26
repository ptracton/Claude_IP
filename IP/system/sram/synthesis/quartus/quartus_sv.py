#!/usr/bin/env python3
"""quartus_sv.py — SystemVerilog sources for Quartus Prime Lite (Standard) 23.1.

Quartus Lite / Standard parses SystemVerilog-2005 only (VERILOG_INPUT_VERSION
SYSTEMVERILOG_2009 is a Pro-edition value), and its parser rejects three
constructs the sram SV RTL uses (accepted by VCS, Xcelium, Verilator, xsim,
Design Compiler, SpyGlass, VC Formal and Vivado):

  1. generate constructs outside an explicit generate ... endgenerate region
     (IEEE 1364-2005 / 1800-2005 made the keywords optional)
         -> each outermost labelled generate construct (`for` / `if` with
            `begin : g_*`, including its else chain) is wrapped in
            generate / endgenerate;
  2. genvar declared in the loop header, `for (genvar i = ...)`
         -> `genvar i;` declared once per module, `for (i = ...)`;
  3. localparam in the parameter port list `#(..., localparam X = ...)`
         -> `parameter X = ...` (nothing can override a header localparam, and
            every instantiation names its parameters, so the value is the same).

The rewrite is purely syntactic. It relies on the RTL coding style
(.agents/VerilogCodingStyle.md): every generate block is labelled `g_*`,
procedural blocks are labelled `p_*` or unlabelled. The repository RTL is not
changed: run_vendor_synth.py --quartus writes the copies into
synthesis/quartus/work/<variant>/src/ and gives those to Quartus.
"""

import os
import re
import sys

_TOKEN = re.compile(r"[A-Za-z_][A-Za-z0-9_$]*|\S")


def strip_comments(text: str) -> str:
    """Comments (and string contents) blanked with spaces: same offsets, same lines."""
    def blank(m):
        return re.sub(r"[^\n]", " ", m.group(0))
    return re.sub(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\\n])*"', blank, text, flags=re.S)


def _tokens(code: str, start: int, end: int) -> list:
    return [(m.group(0), m.start()) for m in _TOKEN.finditer(code, start, end)]


def _match_paren(toks: list, i: int) -> int:
    """Index of the ')' matching the '(' at toks[i]."""
    depth = 0
    for j in range(i, len(toks)):
        if toks[j][0] == "(":
            depth += 1
        elif toks[j][0] == ")":
            depth -= 1
            if depth == 0:
                return j
    raise ValueError("unbalanced parentheses")


def _match_end(toks: list, i: int) -> int:
    """Index of the `end` matching the `begin` at toks[i]."""
    depth = 0
    for j in range(i, len(toks)):
        if toks[j][0] == "begin":
            depth += 1
        elif toks[j][0] == "end":
            depth -= 1
            if depth == 0:
                return j
    raise ValueError("unbalanced begin / end")


def _construct_end(toks: list, i: int) -> int:
    """toks[i] is `for` / `if` of a generate construct: index of its last token
    (the final `end`, after any else / else-if chain)."""
    j = _match_paren(toks, i + 1) + 1
    if toks[j][0] != "begin":
        raise ValueError(f"generate construct without begin at offset {toks[i][1]}")
    j = _match_end(toks, j)
    while j + 1 < len(toks) and toks[j + 1][0] == "else":
        k = j + 2
        if toks[k][0] == "if":
            k = _match_paren(toks, k + 1) + 1
        if toks[k][0] != "begin":
            raise ValueError(f"else without begin at offset {toks[k][1]}")
        j = _match_end(toks, k)
    return j


def _is_generate_begin(toks: list, j: int) -> bool:
    """toks[j] is `begin` with a `: g_*` label."""
    return (toks[j][0] == "begin" and j + 2 < len(toks) and toks[j + 1][0] == ":"
            and toks[j + 2][0].startswith("g_"))


def _module(text: str) -> str:
    code = strip_comments(text)
    # (3) header localparams -> parameters (header = up to the end of the port list)
    hdr = re.search(r"\)\s*;", code).end()
    text = re.sub(r"\blocalparam\b", "parameter", text[:hdr]) + text[hdr:]
    code = strip_comments(text)
    hdr = re.search(r"\)\s*;", code).end()
    # (2) genvars declared in loop headers
    names = []
    for m in re.finditer(r"\bfor\s*\(\s*genvar\s+(\w+)", code):
        if m.group(1) not in names:
            names.append(m.group(1))
    # (1) outermost generate constructs: `for` / `if` (...) begin : g_*
    toks = _tokens(code, hdr, len(code))
    edits = []                       # (offset, insert text) in increasing order
    i = 0
    while i < len(toks):
        if toks[i][0] in ("for", "if") and (i == 0 or toks[i - 1][0] != "else") \
                and i + 1 < len(toks) and toks[i + 1][0] == "(":
            j = _match_paren(toks, i + 1) + 1
            if j < len(toks) and _is_generate_begin(toks, j):
                last = _construct_end(toks, i)
                edits.append((toks[i][1], "generate "))
                edits.append((toks[last][1] + len("end"), " endgenerate"))
                i = last + 1
                continue
        i += 1
    out = text
    for off, ins in reversed(edits):
        out = out[:off] + ins + out[off:]
    out = re.sub(r"\bfor(\s*)\(\s*genvar\s+(\w+)", r"for\1(\2", out)
    if names:
        out = out[:hdr] + "\n  genvar " + ", ".join(names) + ";  // quartus_sv.py" + out[hdr:]
    return out


def transform(text: str) -> str:
    """Quartus-Lite form of one SV source file (packages are returned unchanged)."""
    code = strip_comments(text)
    pieces, pos = [], 0
    for m in re.finditer(r"\bmodule\b.*?\bendmodule\b", code, re.S):
        pieces.append(text[pos:m.start()])
        pieces.append(_module(text[m.start():m.end()]))
        pos = m.end()
    pieces.append(text[pos:])
    return "".join(pieces)


def write_sources(files: list, dst_dir: str) -> list:
    """Write the Quartus form of each file into dst_dir; returns the new paths."""
    os.makedirs(dst_dir, exist_ok=True)
    out = []
    for f in files:
        with open(f) as fh:
            text = fh.read()
        dst = os.path.join(dst_dir, os.path.basename(f))
        with open(dst, "w") as fh:
            fh.write(f"// Generated by synthesis/quartus/quartus_sv.py from {f}\n" + transform(text))
        out.append(dst)
    return out


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("usage: quartus_sv.py <dst_dir> <file.sv> ...")
        sys.exit(1)
    for p in write_sources(sys.argv[2:], sys.argv[1]):
        print(p)
