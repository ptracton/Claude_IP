---
name: VC Formal on csun.edu — bound SVA checkers verify SV and VHDL tops
description: How the Synopsys VC Formal (FPV) flow is invoked, what works for mixed-language bind, how to debug counterexamples, and what it found on the timer
type: reference
---

VC Formal (`vcf`, `/opt/synopsys/vc_formal/Y-2026.03-SP1/bin`) is the formal
tool on csun.edu, where SymbiYosys is not installed. It was first wired up for
`IP/system/timer`. See [formal.md](formal.md) Section 6 for the spec any new
IP should follow, and `IP/common/verification/formal/README.md` for the
reusable library.

**Invocation that works:** `vcf -f claude_vcf_fpv.tcl -batch`, with the run
described by `FV_*` environment variables (normally set by
`IP/common/verification/tools/claude_vcf.py`). The key compile lines:
- VHDL RTL: `analyze -format vhdl -vcs "-vhdl08 <files>"`. VHDL-2008 works
  here, unlike the SpyGlass compat layer ([reference_spyglass_lint](reference_spyglass_lint.md)).
- SVA checkers: `analyze -format sverilog -vcs "-sverilog +incdir+... <files>"`
- `elaborate <top> -sva -vcs "-lca -sva_bind_enable <bind_module>"`. The
  binds must sit inside a bind-only module whose name is passed to
  `-sva_bind_enable`. This form is required for a VHDL top and also works for
  an SV top.
- Reset: `create_clock`, `create_reset -sense low|high`,
  `sim_run -stable`, `sim_save_reset`. Proofs start from reset and the
  reset input is held inactive, so no `$initstate` assumptions are needed.
- `check_fv -block`, then `report_fv -list > file`. Pass/fail comes from
  parsing that report, not from the exit code, which is 0 even with
  falsified assertions.

**Mixed-language bind works, but checkers must use ports only.** SV checkers
bind into VHDL entities (`timer_core`, `timer_regfile`, `timer_<proto>`)
with named port connections. VHDL port names match case-insensitively.
Hierarchical references into VHDL are not supported (`hdl_xmr` is also
unsupported in VHDL), so keep every property on the bound block's ports.
Report names for VHDL instances come back upper-cased
(`TIMER_APB.U_FV.u_bus...`), so waiver globs are matched case-insensitively.
When the bound checker contains generate blocks, the VHDL hierarchy also gets
an extra level (`BUS_MATRIX_APB.U_FV.u_fv.g_slv[0]...` vs SV
`bus_matrix_apb.u_fv.g_slv[0]...`): write waiver globs as `<top>.u_fv*.<rest>`
so one line matches both languages.

**VHDL generics are not visible to an SV bind.** A checker bound into a VHDL
entity sees its generics as 0 (e.g. `NUM_MASTERS`), so pass the configuration
as literals: generate a `<ip>_fv_cfg.svh` from the RTL package before each
run (bus_matrix: `formal_bus_matrix.py` writes `bus_matrix_fv_cfg.svh` from
`bus_matrix_pkg.sv`).

**`claude_vcf.VcfJob` clock/reset overrides.** Jobs default to the timer's
per-protocol clock/reset names (`PCLK`/`PRESETn`, ...). An IP with one
`clk`/`rst_n` on every variant passes them per job (see
`formal_bus_matrix.py`).

**Debugging:** `fvtrace -property <name> -file x.fsdb` writes a
counterexample, and `get_props -usage assert -status falsified` lists the
failures. `/opt/synopsys/vc_formal/Y-2026.03-SP1/verdi/bin/fsdb2vcd x.fsdb -o x.vcd`
converts one to VCD for reading without a GUI. `formal_timer.py --trace`
does all of this per failure.

**Two checker traps hit during bring-up:**
- An APB master assumption was missing ("ACCESS only after SETUP"), so the
  solver jumped straight to ACCESS. Always rule out an under-constrained
  master before blaming RTL.
- On pipelined AHB, a read request and the completion of the *previous* read
  happen in the same cycle. `claude_reg_fv` tracks the open read instead of
  treating a same-cycle request and completion as one transaction.

**Timer results (2026-09-26):** all 8 jobs (4 protocols × SV/VHDL) PASS in
about 1 minute each. The flow found three real RTL bugs, all fixed (details
in `IP/system/timer/verification/formal/vcf/README.md`):
- VHDL `timer_core` RESTART not gated by EN (SV was already correct).
- CTRL RESTART/SNAPSHOT pulse stretched to two cycles by a back-to-back,
  byte-masked CTRL write. Only reachable over AHB.
- The common `claude_ahb_if` returned HRDATA one transfer late. The user
  chose the fix: one read wait state (HREADY low while `rd_en` is issued).
  Directed-test BFM timing was unaffected.

After the fixes, VCS and Xcelium directed tests (8/8 each) and SpyGlass SV
lint all still pass.

**Pitfalls found on the sram (2026-11-15):**
- **VHDL generics: use `-gfile`, not `-gv`.** `elaborate -vcs "-gv WIDTH=16"` sets WIDTH in
  *every* VHDL instance with that generic (vcf.log: `assign 16 /TOP/SUB/U_X/WIDTH`). Write a file
  of `assign <v> /<TOP>/<NAME>` lines and pass `-gfile <file>` (sram `formal_sram.py elab_opts`).
- **Undriven "symbolic" nets are X-injected.** A free variable held by `$stable(x)` on one clock
  can change between that clock's edges when another clock is random (`create_random_clock`):
  properties on the second clock then see other values (false CEX, and the trace dump does not
  show it — the `.fsdb.xml` lists it under "X-Injected-Signals"). Use a self-holding register
  without reset: `always_ff @(posedge clk) sym <= sym;` (free initial value, constant after).
- **`initial` blocks are not a start state.** After `sim_run`/`sim_save_reset`, registers without
  a reset are free. A checker register needs a real reset; a bind can reach an ancestor's reset by
  upward reference (`.rst_n(sram_core.rst_n)`), which also works for VHDL-instantiated leaves (verified 2026-11-15: lemma proven 8/8 in core_ecc_vhdl and core_opts_vhdl).
  VCS rejects `initial` + `always_ff` on one variable (ICPD) and a declaration initializer on an
  `always_ff` variable (ICPD_INIT).
- **Helper lemmas need `set_fml_var fml_enable_assume_proof true`** to be used by the other
  properties (`claude_vcf.VcfJob(assume_proven=True)`, env `FV_ASSUME_PROVEN`). Docs warn it can
  also slow a run.
- **Do not edit `claude_vcf_fpv.tcl` while a vcf run is in progress:** vcf reads the script as it
  executes and resumed at a shifted offset after a 3 h proof ("missing close-brace"; the report
  was already written).
- **Waivers can be job-scoped:** `<job glob>:<property glob> <result> # why` (matched with and
  without the `_sv`/`_vhdl` suffix).
- **Reading traces without Verdi:** `$VC_FORMAL/verdi/bin/fsdbreport t.fsdb -of h -s /top/sig ...
  -o out.txt` (values shown at an edge are the post-edge values).
- **A bind with no target:** SV elaboration ignores it; with a VHDL design it is `Error-[SVABIND] Bind target not found`. Guard binds to optional modules with a generated `define.
- **`report_fv -list` row format:** `inconclusive(depth=22)` has no space before the depth. claude_vcf.py `_ROW_RE` now accepts it (fixed 2026-11-15); before, inconclusive waivers never matched and depths were lost.
