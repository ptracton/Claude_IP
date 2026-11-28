# Lint waivers — master adapters (`claude_<proto>_mst_if`)

Format as in a regular IP (`.agents/lint.md`): file, line, tool + code, justification, and the
matching suppression.

**None.** Verilator `-Wall`, GHDL analysis / synthesis, Yosys and the Vivado / Quartus
synthesis runs are clean without waivers.

Notes (not waivers):

- `claude_axi4l_mst_if.sv`: `BRESP[0]` / `RRESP[0]` are consumed by `unused_resp`, matched by
  Verilator's default `*unused*` pattern; they only distinguish SLVERR from DECERR, which
  `mem_*` does not carry (spec).
- SpyGlass (csun.edu) has not been run yet.
