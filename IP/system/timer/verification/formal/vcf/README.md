# Timer — VC Formal verification

Formal property verification of the timer with **Synopsys VC Formal**
(FPV). It covers all four bus top-levels (`timer_apb`, `timer_ahb`,
`timer_axi4l`, `timer_wb`) in **both SystemVerilog and VHDL-2008**: eight
proof jobs, all using the same SVA checkers.

The bus-protocol checkers, the register read-back checker, the Tcl run
script and the Python driver are shared IP components. They are documented
in [`$IP_COMMON_PATH/verification/formal/README.md`](../../../../../common/verification/formal/README.md).
This directory holds only what is specific to the timer.

## Running

```bash
source IP/system/timer/setup.sh
python3 $CLAUDE_TIMER_PATH/verification/tools/formal_timer.py --tool vcf                # all 8 jobs
python3 $CLAUDE_TIMER_PATH/verification/tools/formal_timer.py --tool vcf --proto ahb --lang vhdl
python3 $CLAUDE_TIMER_PATH/verification/tools/formal_timer.py --tool vcf --trace        # FSDB per failure
```

With `--tool auto` (the default), VC Formal is used when `vcf` is on `PATH`
(csun.edu), and SymbiYosys otherwise. `run_regression.py` makes the same
choice and collects each job's result as `formal/vcf/<top>_<lang>`.

| Output | Location |
|--------|----------|
| Summary (PASS/FAIL, per-job counts, failures, waivers) | `verification/formal/vcf/results.log` |
| Per-job run directory (`vcf.log`, `report_fv.txt`, `results.log`, `traces/`) | `verification/work/vcf/<top>_<lang>/` |

Each job takes about one minute. The default time budget is 30 minutes per
job (`--max-time`).

## Files

| File | Bound to | Contents |
|------|----------|----------|
| `timer_<proto>_fv.sv` | `timer_<proto>` | common `claude_<proto>_fv` + `timer_regmap_fv` + "no error response" check |
| `timer_<proto>_fv_bind.sv` | — | bind-only module: binds the three checkers below into the top-level |
| `timer_block_binds.svh` | — | binds shared by all four tops (`timer_core`, `timer_regfile`) |
| `timer_regmap_fv.sv` | (via wrapper) | protocol-neutral register map (one `claude_reg_fv` per address) |
| `timer_core_fv.sv` | `timer_core` | counter, prescaler, IRQ and trigger properties |
| `timer_regfile_fv.sv` | `timer_regfile` | CTRL, STATUS, LOAD, COUNT and CAPTURE hardware behaviour |
| `timer_fv_waivers.txt` | — | waived results with justifications |

The checkers use only the ports of the block they are bound to, so the SV
and VHDL builds get identical checks.

## What is proven

**Bus protocol** (per top-level, from the common checkers). The design meets
every slave rule of its protocol, with the solver acting as an unconstrained
but legal master. See the common README for the full rule list. In addition,
each timer top-level never signals an error (`p_no_slverr`, `p_no_error`,
`p_bresp_okay`/`p_rresp_okay`, `p_no_err`).

**Register map** (`timer_regmap_fv`, identical on every protocol):

| Address | Checks |
|---------|--------|
| 0x00 CTRL | bits 13:0 except RESTART[12] read back what was written (strobe-aware); bits 31:15 read 0; reads 0 after reset |
| 0x04 STATUS | bits 31:3 read 0 |
| 0x08 LOAD | all bits read back what was written; reads 0 after reset |
| 0x14–0x3C | unmapped: always read 0 |

**Register file** (`timer_regfile_fv`):
- CTRL fields follow byte-strobed writes and otherwise hold.
- RESTART is exactly a one-cycle pulse per write that sets it.
- LOAD follows writes and otherwise holds.
- STATUS.INTR: hardware set has priority over W1C, the bit is sticky and W1C,
  and it never rises spuriously.
- STATUS reads return INTR, ACTIVE (one cycle late) and OVF (set/W1C shadow).
- COUNT reads return `hw_count_val`.
- CAPTURE latches `hw_count_val` the cycle after SNAPSHOT.
- `rd_data` changes only on a read.

**Core** (`timer_core_fv`):
- IRQ equation, level and pulse modes.
- EN=0 stops the counter and freezes COUNT within one cycle.
- Enable loads COUNT from LOAD (LOAD=0 acts as 1).
- While running, COUNT only holds or decrements by one.
- At underflow, repeat mode reloads and keeps running; one-shot mode stops.
- INTR and TRIGGER outputs are one-cycle pulses.
- TRIGGER is gated by TRIG_EN and coincides with the INTR set pulse.
- OVF is set only on an underflow while INTR is still pending.

**Coverage.** Every register is read, written and checked through each bus.
Other covers show that each behaviour is reachable: underflow in repeat
mode, one-shot completion, level and pulse IRQ, trigger, overflow, restart,
prescaled counting, W1C, snapshot, back-to-back and pipelined bus transfers,
AXI back-pressure, and write-before-address.

## Waivers

| Property | Result | Why |
|----------|--------|-----|
| `timer_apb.u_fv.u_bus.c_slverr` | uncoverable | `claude_apb_if` ties PSLVERR=0 |
| `timer_ahb.u_fv.u_bus.g_s_error_two_cycle.*` | vacuous | `claude_ahb_if` ties HRESP=OKAY, so there is no ERROR response to check |
| `timer_wb.u_fv.u_bus.c_err` | uncoverable | `claude_wb_if` ties ERR_O=0 |

## Bugs found by this flow

Found when the VC Formal flow was first brought up and fixed in the RTL:

1. **VHDL `timer_core`: RESTART bypassed EN=0** (`timer_core.vhd`). The
   RESTART branch was not guarded by `ctrl_en`, as the SV version is. A write
   of RESTART together with EN=0 therefore reloaded the counter, and
   `hw_active` stayed high after the timer was disabled. Found by
   `p_active_off` / `p_count_frozen` on the VHDL top only.
2. **RESTART/SNAPSHOT pulse stretched to two cycles** (`timer_regfile.sv` /
   `.vhd`). A CTRL write whose byte-1 strobe was low, issued right after a
   RESTART or SNAPSHOT write, kept the self-clearing bit set for another
   cycle. `apply_strb` preserved the current value of the bit. Only AHB can
   issue CTRL writes on consecutive cycles, so only the AHB runs failed
   (`p_restart_clear`). Now a write can only set these bits.
3. **AHB bridge returned read data one transfer late** (common
   `claude_ahb_if.sv` / `.vhd`). `rd_en` was issued in the data phase and
   the register file's read data is registered, yet HREADY was always high.
   Every AHB read therefore returned the previous read's data. The
   directed-test BFM hid this because it samples HRDATA two cycles after the
   data phase. The bridge now inserts one wait state per read: HREADY goes
   low while `rd_en` is issued. Writes stay zero-wait.
