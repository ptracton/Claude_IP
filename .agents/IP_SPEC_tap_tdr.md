# JTAG TAP and test data register port (`tdr_*` / `tap_*`) — approved 2026-11-27

Spec version: **1.0** (see "Change log" at the end).

Location: `.agents/IP_SPEC_tap_tdr.md` (all interface specs live in `.agents/`; the RTL
headers of components built from it point here).

Status: specification only, Phase 0.1 of `.agents/IP_PLAN.md` (§3.6, §3.9, §9). Nothing
here is implemented yet.

Requirements (user 2026-11-27):

1. **The TAP and its test logic MUST conform to IEEE Std 1149.1-2013.** Where this spec and
   the standard disagree, the standard wins and this spec is fixed.
2. **It must be easy to extend with special operations**, without editing the TAP.

A SoC has **one** TAP. Everything reached over JTAG (RISC-V debug transport, jtag2bus and
its DMA mode, MBIST, ILA, test control, and new special operations) is a **front end** that
owns one or more instructions and their test data registers (TDRs), and plugs into the TAP
through one standard **TDR port**.

```
 TCK TMS TDI TRST*                                          TDO (3-state)
   │   │   │   │       ┌──────────────────────────────┐        ▲
   └───┴───┴───┴──────►│ jtag_tap (1149.1)            │────────┘
                       │ TAP controller, IR, BYPASS,  │
                       │ IDCODE, decode from YAML     │
                       └──┬──────┬──────┬──────┬──────┘
             TDR port 0   │  1   │  2   │  3   │ ...                (TCK domain)
                    ┌─────▼┐ ┌───▼──┐ ┌─▼────┐ ┌▼──────────┐
                    │ BSR  │ │ DTM  │ │jtag2 │ │ jtag_ops  │◄── special operations:
                    │      │ │      │ │ bus  │ │ dispatcher│    one op handler each
                    └──────┘ └──┬───┘ └──┬───┘ └──┬────────┘
                                │ CDC    │ CDC    │ CDC       (front end's job)
                             riscv_dm  mem_*   op_* handlers (system clock)
```

---

## 1149.1 conformance

### What `jtag_tap` implements (the standard's mandatory items)

| 1149.1 item | Implementation |
|---|---|
| TAP pins TCK, TMS, TDI, TDO, optional TRST* | `tck_i`, `tms_i`, `tdi_i`, `tdo_o` + `tdo_oe_o`, `trst_n_i` (`HAS_TRST`, default 1) |
| TMS / TDI / TRST* undriven = logic 1 | pull-ups in the pad ring; the SoC generator adds them and the BSDL states them |
| TDO 3-state | `tdo_oe_o` high **only** in Shift-IR and Shift-DR; TDO changes on the **falling** edge of TCK |
| TMS / TDI sampled on the rising edge of TCK | yes, everywhere |
| 16-state TAP controller | exactly the standard's state diagram, on the rising edge of TCK |
| Asynchronous reset to Test-Logic-Reset by TRST*, and at power-up | `trst_n_i` resets the controller asynchronously; the SoC ties it to (TRST* pin AND power-on reset), so the TAP is in Test-Logic-Reset after power-up even with no TRST* pin. **Documented exception to D8** (synchronous resets) and lint / DFT waiver class `DFT1` |
| Five TCK with TMS = 1 reach Test-Logic-Reset from any state | yes (formal proof) |
| Test logic inactive in Test-Logic-Reset | system logic runs normally; IR holds IDCODE (or BYPASS if no IDCODE) |
| Instruction register ≥ 2 bits, capture pattern `...01` | `IR_W` (default 5); captures `01` in bits [1:0], status in the upper bits |
| IR shift stage + update stage | shift on the rising edge in Shift-IR; the update stage (holding the current instruction) loads on the **falling** edge of TCK in Update-IR, and is reset in Test-Logic-Reset |
| BYPASS register, opcode all ones | 1 bit, captures 0; all-ones opcode; every unused opcode also selects BYPASS |
| Mandatory instructions BYPASS, SAMPLE, PRELOAD, EXTEST | yes, with SAMPLE and PRELOAD as **separate** opcodes (-2013) |
| Boundary-scan register on every system pin | `boundary_scan` (Phase 2), generated from the pad list; **required** for a conforming SoC |
| Optional instructions used | IDCODE (device identification register), CLAMP, HIGHZ |
| BSDL | generated per SoC (`write_bsdl` from the generator and / or DFT Compiler BSD), declaring every instruction; design-specific instructions are declared `PRIVATE` unless the SoC documents them |

### What every test data register follows (TDR rules)

All TDRs, including the user / private ones of the front ends, follow the standard's TDR
behavior. `claude_tdr` (below) implements it once so front ends never re-do it.

1. **Capture**: the shift stage loads its capture value on the **rising** edge of TCK in
   Capture-DR, only when its instruction is selected.
2. **Shift**: on each rising edge of TCK in Shift-DR the shift stage moves one bit toward
   TDO; TDI enters at the most significant bit; bit 0 is the serial output (LSB first).
3. **Update**: a TDR with a parallel output has an update stage that loads from the shift
   stage on the **falling** edge of TCK in Update-DR. The parallel output never changes
   during Capture or Shift, and does not change when the TDR is not selected.
4. **Serial output** to the TAP comes straight from shift-stage bit 0 (a flop). The TAP
   muxes by instruction and drives TDO from its falling-edge output flop.
5. **Any number of shifted bits is legal from the host**; the front end uses the update
   stage contents and never hangs.
6. **Reset**: TDR update stages are reset in Test-Logic-Reset (or by TRST*), never by a
   system reset, so a debugger keeps its connection across `ndmreset` and watchdog resets.
7. **No TDR or front end may disturb the system pins** except through the boundary-scan
   register under EXTEST / CLAMP / HIGHZ, as the standard requires.

### Conformance scope

- The SoC is conforming with `TAP_IMPL = CLAUDE` **and** a boundary-scan register on all
  system pins. The SoC generator refuses `TAP_IMPL = CLAUDE` without `boundary_scan` unless
  the SoC YAML sets `jtag.conformance: false` (for example an FPGA build using user pins,
  whose pins cannot be boundary-scanned); such a build is labelled non-conforming in its
  BSDL-free docs.
- With `TAP_IMPL = XILINX_BSCAN` / `INTEL_VJTAG` (see "FPGA"), conformance is provided by the
  FPGA's own TAP; our front ends sit behind its USER instructions.

---

## The TDR port

### Naming

- **TDR = test data register**, the IEEE 1149.1 term for any register that the current
  instruction connects between TDI and TDO: BYPASS, the device identification register
  (IDCODE), the boundary-scan register, and every design-specific register (TEST_CTRL,
  DTMCS, DMI, OPS, ...). The port carries the signals any TDR needs, so all of them,
  standard or not, attach the same way.
- **`tdr_*`** are the `jtag_tap` ports that drive the TDRs ("signals to / from the test
  data registers"), outputs except the serial returns `tdr_tdo_i`.
- **`tap_*`** are the same signals seen from a front end ("signals coming from the TAP"),
  inputs except the front end's serial output `tap_tdo_o`.
- The second part follows the standard's names: `tck`, `tdi`, `tdo`, `capture` / `shift` /
  `update` for the Capture-DR / Shift-DR / Update-DR states, `rti` for Run-Test/Idle, `tlr`
  for Test-Logic-Reset, and `sel` for "the current instruction selects this register".
- (An earlier draft used `udr_*`, for "user data register"; it was renamed because the port
  is not only for user registers.)

### TAP side (`jtag_tap`, `N_TDR` front-end instructions)

| Port | Dir | Width | Meaning |
|---|---|---|---|
| `tdr_tck_o` | out | 1 | TCK, buffered (front-end clock, both edges used by `claude_tdr`) |
| `tdr_tlr_o` | out | 1 | TAP in Test-Logic-Reset (or TRST* low): reset of TCK-domain logic |
| `tdr_sel_o` | out | `N_TDR` | bit *k*: the current instruction (IR update stage) selects TDR *k* |
| `tdr_capture_o` | out | 1 | TAP in Capture-DR |
| `tdr_shift_o` | out | 1 | TAP in Shift-DR |
| `tdr_update_o` | out | 1 | TAP in Update-DR |
| `tdr_rti_o` | out | 1 | TAP in Run-Test/Idle |
| `tdr_tdi_o` | out | 1 | TDI |
| `tdr_tdo_i` | in | `N_TDR` | bit *k*: serial output of TDR *k* |

`capture`, `shift`, `update`, `rti` are not qualified by `sel`; each front end combines them
with its own `sel` (inside `claude_tdr`). The set matches the Xilinx `BSCANE2` primitive
(`CAPTURE`, `SHIFT`, `UPDATE`, `RUNTEST`, `RESET`, `SEL`, `TDI`, `TDO`, `TCK`), so the same
front ends run behind it.

### Front-end side

`tap_tck_i`, `tap_tlr_i`, `tap_sel_i`, `tap_capture_i`, `tap_shift_i`, `tap_update_i`,
`tap_rti_i`, `tap_tdi_i` (in) and `tap_tdo_o` (out). A front end with two TDRs (the DTM:
DTMCS and DMI) has suffixed `sel` / `tdo` pairs (`tap_sel_dmi_i`, `tap_tdo_dmi_o`). Plain
ports in SV and VHDL.

---

## Extending: adding special operations (user 2026-11-27)

There are two ways, and the first is the normal one.

### Way 1: a new operation code on `jtag_ops` (no new instruction, no TAP change)

`jtag_ops` is a standard front end owning one private instruction (`OPS`, default `0x0E`)
with a command TDR. It dispatches **operation codes** to small handler blocks in the system
clock. Adding a special operation = writing a handler and adding one YAML line.

**OPS TDR** (shifted LSB first; length `OPS_LEN` = 2 + 8 + 32 + 32 = 74 by default):

| Bits | Shift in (host → SoC) | Capture (SoC → host) |
|---|---|---|
| [1:0] | `CMD`: 0 = NOP / poll, 1 = RUN, 2 = CLEAR (clear sticky error), 3 = reserved | `STATUS`: 0 = OK, 2 = error, 3 = busy (RISC-V DMI `op` encoding) |
| [9:2] | `OPCODE` (256 codes) | opcode of the last operation |
| [41:10] | `ARG0` | `RESULT0` |
| [73:42] | `ARG1` | `RESULT1` / error code |

Behavior:

1. On Update with `CMD` = RUN, the dispatcher sends `{OPCODE, ARG0, ARG1}` across to the
   system clock (`claude_handshake_sync`) and starts the matching handler.
2. The next Capture returns `busy` until the handler finishes, then `OK` or `error` with the
   results. An Update with RUN while busy is ignored and sets a sticky busy error (cleared
   by CLEAR), as in RISC-V `dmireset`.
3. An opcode with no handler returns `error` with error code "unknown opcode", at once.
4. Opcode `0x00` is reserved: `RESULT0` = number of handlers, `RESULT1` = `jtag_ops`
   version, so a host can discover what is there. Opcode `0x01` with `ARG0` = *n* returns
   the 32-bit ID of handler *n* (from the YAML), so host scripts find operations by name.
5. A handler never needs TCK; TCK may stop mid-operation and the result waits.
6. Long data (more than 64 bits per operation) uses repeated operations or Way 2.

**Handler port** (one per handler, system clock, plain ports):

| Port | Dir (handler) | Meaning |
|---|---|---|
| `op_start_i` | in | one-cycle pulse: start, with the fields below valid |
| `op_code_i[7:0]`, `op_arg0_i[31:0]`, `op_arg1_i[31:0]` | in | the operation |
| `op_done_o` | out | one-cycle pulse: finished (any number of cycles after start; may be the same cycle) |
| `op_err_o`, `op_res0_o[31:0]`, `op_res1_o[31:0]` | out | results, valid with `op_done_o` |

A handler may serve a range of opcodes. Typical handlers: reset-controller requests (hold /
release a domain), clock-select override, read the lifecycle state, start MBIST on a bank
and return pass / fail, trigger the ILA, read a fuse word, set an SoC strap, a sticky "boot
from JTAG" flag for the boot ROM.

**SoC YAML** (the generator builds the dispatcher's decode, the documentation, a C / Python
opcode table and the OpenOCD Tcl procedures):

```yaml
jtag:
  ops:
    - {name: rst_hold,  opcode: 0x10, handler: u_rstctl.jtag_op,  doc: "hold domain ARG0 in reset"}
    - {name: mbist_run, opcode: 0x20, handler: u_mbist.jtag_op,   doc: "run MBIST on bank ARG0"}
```

### Way 2: a new instruction with its own TDR (no TAP RTL change)

For operations that need TCK-rate data or a long DR (ILA readout, jtag2bus DMA, a new debug
transport). Build the front end from `claude_tdr`, then add one YAML entry:

```yaml
jtag:
  instructions:
    - {name: ILA, opcode: 0x0C, tdr_len: 64, front_end: u_ila, bsdl: PRIVATE}
```

The generator passes the opcode table to `jtag_tap` as parameters (`N_TDR`,
`TDR_OPCODES` packed vector), connects TDR port *k*, adds the instruction and register to
the BSDL (`INSTRUCTION_OPCODE`, `REGISTER_ACCESS`), and checks that opcodes are unique, not
all ones, and do not collide with the standard ones. **`jtag_tap` RTL never changes.**

### `claude_tdr`: the building block (Phase 0.2 component)

One parameterized cell that implements the TDR rules above, used by every front end:

| Parameter | Meaning |
|---|---|
| `LEN` | TDR length |
| `HAS_UPDATE` | 1 = parallel update stage (falling-edge, reset in Test-Logic-Reset) |
| `SYS_XFER` | 1 = carry each Update to a system clock with `claude_handshake_sync`, report `busy` in the next capture, return results (the Way 1 pattern, reusable for Way 2 front ends) |

Ports: the front-end TDR port, `capture_val_i[LEN-1:0]`, `update_q_o[LEN-1:0]`,
`update_pulse_o` (TCK domain), and with `SYS_XFER` a system-side request / done / result
port with the same shape as the handler port. Writing a new front end is then "instantiate
`claude_tdr`, add the operation logic".

---

## Default instruction map

`IR_W` = 5. All values are SoC YAML parameters; these are the generator defaults.

| IR | Instruction | TDR | Owner | BSDL |
|---|---|---|---|---|
| `0x00` | EXTEST | boundary-scan register | `boundary_scan` | public |
| `0x01` | IDCODE | 32-bit device identification register | `jtag_tap` | public |
| `0x02` | SAMPLE | boundary-scan register | `boundary_scan` | public |
| `0x03` | PRELOAD | boundary-scan register | `boundary_scan` | public |
| `0x04` | CLAMP | BYPASS | `jtag_tap` + `boundary_scan` | public |
| `0x05` | HIGHZ | BYPASS | `jtag_tap` + `boundary_scan` | public |
| `0x08` | TEST_CTRL | test-control register | `jtag_tap` | private |
| `0x09` | MBIST | MBIST TDR | `mbist_ctrl` | private |
| `0x0A` | BUS | jtag2bus command TDR (with DMA burst mode, D5) | `jtag2bus` | private |
| `0x0C` | ILA | ILA TDR | `ila` | private |
| `0x0E` | OPS | special-operations TDR | `jtag_ops` | private |
| `0x10` | DTMCS | RISC-V DTM control / status | `riscv_dtm` | private |
| `0x11` | DMI | RISC-V DMI | `riscv_dtm` | private |
| others below `0x1F` | free | — | new Way 2 front ends | per YAML |
| `0x1F` | BYPASS | BYPASS | `jtag_tap` | public |

IDCODE, DTMCS / DMI and BYPASS use the values OpenOCD and the RISC-V debug spec expect.
IDCODE: 32 bits, bit 0 = 1, version / part number / JEDEC manufacturer from the SoC YAML.

---

## Test control and debug lock (inside `jtag_tap`)

- **TEST_CTRL** (private, §3.9): a TDR with an update stage; bits `test_mode` (source of
  every IP's `test_mode_i`), `scan_comp`, `mbist_en`. Kept across instruction changes, reset
  only in Test-Logic-Reset, so leaving test mode is "reset the TAP".
- **Debug lock** (`dbg_lock_i` from the lifecycle controller, §11): when high, the private
  instructions select BYPASS (their `tdr_sel_o` bits are held 0) except the authentication
  ones named in the lifecycle spec, and TEST_CTRL cannot be set (D7 rule 7). The public
  1149.1 instructions always work, as conformance requires.

---

## FPGA

The FPGA's JTAG pins belong to the FPGA's own (conforming) TAP. Parameter `TAP_IMPL`
replaces `jtag_tap` by a thin adapter with the same TAP-side TDR port:

| `TAP_IMPL` | TDR port driven by | Notes |
|---|---|---|
| `CLAUDE` (default, ASIC) | `jtag_tap` on dedicated pins | conforming with `boundary_scan` |
| `XILINX_BSCAN` | one `BSCANE2` per instruction (`USER1`–`USER4`) | at most 4 front ends: OPS, BUS, and the DTM (OpenOCD `use_bscan_tunnel`) fit; Way 1 operations need no extra USER slot |
| `INTEL_VJTAG` | `sld_virtual_jtag`, virtual IR selects the TDR | Quartus System Console, OpenOCD |
| `CLAUDE` on user pins | `jtag_tap` on PMOD / header pins | `jtag.conformance: false` (no boundary scan) |

Front ends are identical in every case. Way 1 is what makes the 4-slot `BSCANE2` limit a
non-issue: special operations share the one OPS instruction.

---

## DFT

- The TAP controller, IR, TEST_CTRL and the TDO flop are **excluded from scan** (DC
  `set_scan_element false`): they control test mode. Waiver class `DFT1`, which also covers
  the asynchronous TRST* / power-on reset of the TAP and its falling-edge flops.
- Front-end TCK-domain flops (shift and update stages, both edges) are scanned on TCK as a
  primary clock; DFT Compiler orders mixed-edge flops and inserts lock-up latches.
- No TDR output drives a clock or an asynchronous reset in a system domain (DFT rules 1
  and 2); for example `ndmreset` and the `rst_hold` operation are synchronous requests to the
  reset controller.

---

## What every front end documents

1. Its instructions (Way 2) or opcodes (Way 1), with defaults.
2. Each TDR's length, field layout, capture value, and what Update does.
3. For system-side work: status / busy, the busy error, latency in TCK and system cycles.
4. The highest TCK frequency it supports relative to the system clock it crosses to.

---

## Verification

- **JTAG host BFM** (SV task set, VHDL procedures, UVM agent `claude_jtag_agent`, Python
  helpers generating the same sequences as OpenOCD scripts): TRST* and TMS resets,
  `irscan`, `drscan` of any length, Pause-DR / Pause-IR, Run-Test/Idle, TCK stopped for
  random periods, random TCK / system clock ratios.
- **1149.1 conformance suite** (simulation, on `jtag_tap` + `boundary_scan` + every TDR):
  one test per mandatory rule in the conformance table above: TDO 3-state and falling-edge
  timing, capture `01`, IDCODE after reset, BYPASS for every unused opcode, update stages
  only on the falling edge in Update-DR / Update-IR, parallel outputs stable during shift,
  Test-Logic-Reset by five TMS = 1 and by TRST* asynchronously, power-up into
  Test-Logic-Reset, SAMPLE / PRELOAD / EXTEST / CLAMP / HIGHZ on the boundary register.
- **Formal** (`jtag_tap`): the 16-state controller equals the standard's diagram; five
  TMS = 1 from any state reach Test-Logic-Reset; at most one `tdr_sel_o` bit; debug lock.
  **`claude_tdr_fv`** (every front end and `claude_tdr`): capture / shift only when
  selected, update stage changes only on the falling edge in Update-DR, `busy` always
  resolves while the system clock runs.
- **BSDL**: the generated BSDL passes a BSDL syntax / semantic check, and on csun.edu DFT
  Compiler BSD (`check_bsd`) confirms 1149.1 compliance of the synthesized netlist (license
  permitting; otherwise the simulation suite is the gate and the run is marked SKIPPED).
- **`jtag_ops`**: discovery opcodes, unknown opcode error, busy / CLEAR, a handler that takes
  0, 1 and many cycles, TCK stopped mid-operation, system in reset (status `error`).
- **FPGA adapters** in simulation (Vivado `BSCANE2` unisim, Intel `sld_virtual_jtag` model),
  then OpenOCD on both boards: `scan_chain`, `irscan` / `drscan` of every TDR, OPS
  operations from Tcl, and GDB through the DTM once the DM exists (Phase 3).

---

## Change log

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-11-27 | approved |
