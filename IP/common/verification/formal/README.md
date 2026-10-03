# Common formal verification library

Reusable pieces for formally verifying any Claude IP block with **Synopsys VC
Formal** (FPV app). They cover all four bus protocols and work on both
**SystemVerilog and VHDL-2008** RTL. Checkers are written in SVA and *bound*
into the design, so the same checker files serve both languages.

An IP adds only its own register map and functional properties. Everything
about the bus protocols, register read-back and running the tool lives here.

| File | Purpose |
|------|---------|
| `claude_fv_defines.svh` | `CLAUDE_FV_MASTER` / `CLAUDE_FV_SLAVE` macros (assume vs. assert by role) |
| `claude_apb_fv.sv` | APB4 protocol checker + transaction observer |
| `claude_ahb_fv.sv` | AHB-Lite protocol checker + transaction observer |
| `claude_axi4l_fv.sv` | AXI4-Lite protocol checker + transaction observer |
| `claude_wb_fv.sv` | Wishbone B4 (classic) protocol checker + transaction observer |
| `claude_reg_fv.sv` | Protocol-neutral register read-back checker (one instance per address) |
| `vcf/claude_vcf_fpv.tcl` | Generic VC Formal run script (configured by environment variables) |
| `../tools/claude_vcf.py` | Python driver: builds jobs, runs `vcf`, parses reports, applies waivers |

The older SymbiYosys flow (flat per-IP wrappers, SV only) is separate and is
described in `.agents/formal.md`.

## How the pieces fit

```
                        bound into  <ip>_<proto>  (SV module or VHDL entity)
  ┌──────────────────────────────────────────────────────────────────────┐
  │ <ip>_<proto>_fv                                                      │
  │   claude_<proto>_fv ──obs_*──►  <ip>_regmap_fv                        │
  │   (assume master rules,          └─ claude_reg_fv  × each register   │
  │    assert slave rules)                                               │
  └──────────────────────────────────────────────────────────────────────┘
  bound into <ip>_core / <ip>_regfile: IP-specific functional checkers
```

1. **Protocol checker** (`claude_<proto>_fv`). All of its ports are inputs, so
   it can be bound to any slave port that uses the matching `claude_<proto>_if`
   pin set. With `MASTER_IS_ENV=1` (the default) the master-side rules are
   **assumed**: the solver acts as a legal bus master. The slave-side rules
   are **asserted** against the design. Setting `MASTER_IS_ENV=0` swaps the
   two roles, so the same file can check a bus master.
2. **Transaction observer.** Each protocol checker also turns bus activity
   into one protocol-neutral transaction stream:

   | Signal | Meaning |
   |--------|---------|
   | `obs_wr_vld` | one-cycle pulse: a write has completed on the bus |
   | `obs_wr_addr/data/strb` | its word address (`addr[ADDR_W+1:2]`), data, byte strobes |
   | `obs_wr_busy` | a write is in progress but not yet complete |
   | `obs_rd_req` | one-cycle pulse: a read has been requested (e.g. APB SETUP, AHB address phase, AXI AR handshake) |
   | `obs_rd_vld` | one-cycle pulse: read data is valid on the bus |
   | `obs_rd_addr/data` | the completing read's word address and data |

3. **Register checker** (`claude_reg_fv`). It consumes the observer stream,
   so every register-map property is written **once per IP** and runs
   unchanged on all four protocols. For one word address it checks:
   - `a_rw_readback`: bits in `RW_MASK` read back what software last wrote,
     with byte strobes applied.
   - `a_rsvd_zero`: bits in `ZERO_MASK` always read 0. Use `'1` for
     unmapped addresses.
   - `a_reset_value`: before any write, bits in `RESET_MASK` read `RESET_VAL`.

   Reads that overlap write activity are skipped rather than guessed at.
   `c_checked` proves that the comparison is still reachable.
   Hardware-owned, self-clearing and W1C bits must be left out of
   `RW_MASK` / `RESET_MASK` and checked by the IP's own properties.

### Protocol rules

| Protocol | Master rules (assumed) | Slave rules (asserted) |
|----------|------------------------|------------------------|
| APB4 | PENABLE⇒PSEL; SETUP→ACCESS; ACCESS only after SETUP; signals stable SETUP→ACCESS and in wait states; PENABLE low after a completed transfer; PSTRB=0 on reads | PREADY within `MAX_WAIT` |
| AHB-Lite | IDLE/NONSEQ only (`SINGLE_ONLY`); address/control held while HREADY low; write data held in a stalled data phase | data phase ends within `MAX_WAIT`; HREADY high and HRESP OKAY outside data phases; two-cycle ERROR response |
| AXI4-Lite | VALID held and payload stable until READY (AW, W, AR); at most one outstanding write and read | B/R held until READY; B only after AW and W handshakes; R only after AR; responses and READYs within `MAX_WAIT` |
| Wishbone B4 | STB⇒CYC; request held until ACK/ERR | ACK/ERR only for an active request; never both; termination within `MAX_WAIT` |

The one-outstanding-transaction (AXI) and single-transfer (AHB) assumptions
match what the `claude_axi4l_if` / `claude_ahb_if` bridges support. Relax
them (`SINGLE_ONLY=0`, or remove `m_single_*`) when checking a slave that
supports more.

## Adding VC Formal to a new IP

Use `IP/system/timer/verification/formal/vcf/` as the worked example.

1. **Register map**: write `verification/formal/vcf/<ip>_regmap_fv.sv`. It
   takes the `obs_*` ports and has one `claude_reg_fv` instance per register,
   plus a generate loop over unmapped addresses with `ZERO_MASK('1)`.
2. **Functional checkers**: write `<ip>_core_fv.sv`, `<ip>_regfile_fv.sv`, and
   so on. Use **only the ports** of the block they are bound to, so they work
   unchanged on SV modules and VHDL entities. Hierarchical references into
   VHDL are not supported.
3. **Per-protocol wrapper**: `<ip>_<proto>_fv.sv` instantiates
   `claude_<proto>_fv` and `<ip>_regmap_fv`, plus any top-level port
   properties.
4. **Bind module**: `<ip>_<proto>_fv_bind.sv` is a bind-only module holding
   `bind <ip>_<proto> <ip>_<proto>_fv ...` and binds for the sub-blocks.
   VC Formal needs the binds inside a module to apply them to a VHDL top;
   the runner passes that module name to `-sva_bind_enable`.
5. **Waivers**: `<ip>_fv_waivers.txt`, one line per waiver:
   `<property glob> <result> # justification`. Globs are case-insensitive,
   because VC Formal upper-cases VHDL instance names. Typical entries are
   covers of responses a bridge ties off (for example `c_slverr uncoverable`).
6. **Runner**: in `verification/tools/formal_<ip>.py`, import
   `claude_vcf`, build one `VcfJob` per (protocol, language), and call
   `claude_vcf.run_job()`. The helpers `common_bridge_file()` and
   `common_checker_files()` supply the common files.

## Running VC Formal directly

`claude_vcf.run_job()` is the normal entry point. To run by hand, set the
`FV_*` variables documented at the top of `vcf/claude_vcf_fpv.tcl`, then:

```
vcf -f $IP_COMMON_PATH/verification/formal/vcf/claude_vcf_fpv.tcl -batch
```

The script compiles the RTL (VHDL with `-vhdl08`) and the checkers, then
elaborates with the bind module. It applies the reset through a reset
simulation (`sim_run -stable; sim_save_reset`), so every proof starts from
the reset state, and then runs `check_fv`. Results are written with
`report_fv -list`. If `FV_TRACE_DIR` is set, it also writes one FSDB
counterexample per falsified assertion; open these in Verdi, or convert them
with `fsdb2vcd`.

## Pass criteria

A job passes only when **every assertion is proven and non-vacuous and every
cover is covered**, apart from waived results. Assumptions (the master
rules) may be vacuous without failing the job. For example, "hold signals
during a wait state" is vacuous against a zero-wait slave. Inconclusive
results fail the job; raise the time budget (`--max-time`) instead.
