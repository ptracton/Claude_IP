# SoC description (`<soc>.soc.yaml`) and generator outputs — approved 2026-11-27

Spec version: **1.0**. Location: `.agents/IP_SPEC_soc_yaml.md` (all interface specs live in `.agents/`).

Status: specification only, Phase 0.1 of `.agents/IP_PLAN.md` (§4, §13, roadmap Phase 2
"SoC generator v1"). Nothing here is implemented yet.

One YAML file describes one SoC. The generator (`SoC/tools/gen_soc.py`) reads it plus every
used IP's `<ip>.ip.yaml` (`IP_SPEC_ip_meta.md`), validates it, and writes the RTL tops,
constraints, power intent, firmware headers, devicetree, debug files, models and
documentation, so none of these can drift apart. Every "set in the SoC YAML" in the other
specs refers to a section of this file.

---

## File layout

`SoC/<soc>/<soc>.soc.yaml`, generated outputs in `SoC/<soc>/generated/` (never edited by
hand, reproducible).

```yaml
schema_version: 1
soc:      {name: soc0, description: "Bus bring-up, no CPU", target: {fpga: zybo_z7_10}}   # or {asic: saed32}
clocks:   ...
resets:   ...
power:    ...
bus:      ...
instances: ...
irq:      ...
events:   ...
streams:  ...
ctl:      ...
dma:      ...
jtag:     ...
pads:     ...
dft:      ...
security: ...
software: ...
```

## Sections

| Section | Contents | Used by spec |
|---|---|---|
| `clocks` | domains: `name`, source (`pin`, `pll`, `divider` of another domain, `tick`), frequency, `gateable` / `always_on`, the power manager's gating control | sideband (gating, ticks), reset |
| `resets` | reset domains (normally one per clock domain), the `system` set, release order and delays, source enables | reset |
| `power` | power domains: switchable or always-on, members (instances), retention, power-manager instance, Q-channel connections, wake sources | sideband (Q-channel), ctl_stream (ring nodes in always-on), event (wake) |
| `bus` | fabric instances (`bus_matrix_<proto>`, bridges, fences), masters (with their `mem_prot` limits) and slaves, address windows | mem_bus_initiator, sideband (fences) |
| `instances` | `name`, `ip`, `version` (must match the `ip.yaml`), `params`, `base` (or `auto`), `clock`, `reset`, `power` domain, overrides such as `ctl_sec_req` (can only be raised) | ip_meta |
| `irq` | PLIC size and priority bits; per instance: source numbers (`auto` or explicit), per-hart targets; CLINT | sideband (interrupts) |
| `events` | event router size, level inputs (tapped IRQ / DMA lines), static wires, default routes, crossing cells | event |
| `streams` | chains (block list with params, `out: {fmt: auto / name, max_w, round, sat, lossless}`), stream switches, taps, `stimulus` for the precision report | stream, fx (chain precision) |
| `ctl` | topologies: rings (ordered node list), point-to-point links, controllers with `ctl_prot`; DEST IDs (`auto` or explicit) | ctl_stream |
| `dma` | channels, back-door connections to comms IP, channel protection limits | ctl_stream, sideband |
| `jtag` | `tap_impl`, `idcode`, `conformance`, `instructions` (Way 2), `ops` (Way 1, shared with cmd2bus) | tap_tdr, cmd2bus |
| `pads` | pad list: name, direction, owning instance port, pull, drive, boundary-scan cell type, test-mode function (scan in / out) | tap_tdr (boundary scan), DFT |
| `dft` | scan pins, compression, ATPG targets (stuck-at / transition coverage) | §3.9 |
| `security` | lifecycle states, firewall regions, which instances are secure-only, debug lock behavior | ctl_stream (security), cmd2bus, tap_tdr |
| `software` | memory regions for the linker script, boot device, RTOS selection, devicetree options | outputs below |

Defaults follow the plan: address map of §13.6 (`base: auto` places APB peripherals in
4 KiB slots from `0x4000_0000`, DSP blocks from `0x5000_0000`, security blocks from
`0x7000_0000`), IRQ numbers in instance order, DEST IDs in ring order from 1.

## Validation (the generator stops with a message naming the line)

- **Address map:** no overlaps; windows aligned to their size (4 KiB minimum); every master can
  reach the slaves it needs; secure regions only behind a firewall.
- **IRQ / events / DEST IDs / JTAG opcodes / op codes:** unique; within the configured sizes.
- **Domains:** every instance port is on a declared clock / reset / power domain; ticks only
  within one domain; every crossing has a crossing cell; ring nodes and fences of a switchable
  power domain sit in an always-on parent.
- **Streams:** formats match on every link (or are resolved by `fmt: auto`); `lossless: true`
  links are wide enough; feedback quantization points not `FX_WRAP`; `BFP` widths match.
- **Parameters:** inside the ranges of each `ip.yaml`; spec versions supported; the IP's status is
  signed off for the target (warning on FPGA, error for an ASIC tape-out target).
- **Security:** `ctl_sec_req` never lowered; controllers' `ctl_prot` within the master limits.
- **JTAG:** with `tap_impl: CLAUDE` and `conformance: true`, every system pin has a boundary-scan
  cell.

## Generated outputs (`SoC/<soc>/generated/`)

| Output | Contents |
|---|---|
| `<soc>_top.sv`, `<soc>_top.vhd` | the SoC top in both languages, identical ports |
| `<soc>.sdc` | clocks, generated clocks (dividers, gated branches), CDC false paths / max delays, IP boundary budgets, test-mode case analysis |
| `<soc>.upf` | power domains, switches, isolation (from every IP's clamp table), retention, always-on parents of ring nodes and fences |
| `soc.h` | base addresses, IRQ numbers, event numbers, DEST IDs, stream link formats, clock frequencies (C99) |
| **`soc.dts`** | **devicetree** for Zephyr and other RTOS: CPU nodes, memory, CLINT (`sifive,clint0`), PLIC (`sifive,plic-1.0.0`), every instance as `compatible = "claude,<ip>"` with `reg`, `interrupts`, `clocks`, and Claude properties (`claude,dest-id`, `claude,events`); matching Zephyr binding YAML files for each IP type |
| `<soc>.ld` | linker script memory regions |
| `<soc>.rdl` | SystemRDL address map of address maps (one regfile per instance) → HTML documentation |
| `<soc>.bsdl` | BSDL (conforming builds) |
| `openocd.cfg`, `jtag_ops.tcl` | OpenOCD configuration, TDR / OPS procedures, cmd2bus Tcl |
| `chain_model.py`, `chain_report.md` / `.csv` | chain golden model and precision report (`IP_SPEC_fx.md`) |
| `soc_test_cfg.py` | the configuration the SoC-level Python tests and BFMs load |
| `<soc>.md` | address map, IRQ table, event table, stream chains, power and reset domains |

## Example (SoC-0, bus bring-up, no CPU)

```yaml
schema_version: 1
soc: {name: soc0, description: "Bus bring-up", target: {fpga: zybo_z7_10}}
clocks:
  - {name: sys, source: {pin: clk125}, freq_mhz: 125, always_on: true}
  - {name: tck, source: {pin: tck},    freq_mhz: 10}
resets:
  domains: [{name: sys, clock: sys}, {name: tck, clock: tck, kind: tap}]
  system: [sys]
bus:
  fabric: {ip: bus_matrix, proto: ahb}
  masters: [{name: jtag2bus0, mem_prot_max: 0b001}, {name: uart2bus0}]
instances:
  - {name: jtag0,     ip: jtag_tap,  params: {TAP_IMPL: XILINX_BSCAN}, clock: tck}
  - {name: jtag2bus0, ip: jtag2bus,  clock: sys}
  - {name: uart2bus0, ip: uart2bus,  clock: sys}
  - {name: sram0,     ip: sram,      base: 0x1000_0000, params: {DEPTH: 8192}, clock: sys}
  - {name: gpio0,     ip: gpio,      base: auto, clock: sys}
  - {name: timer0,    ip: timer,     base: auto, clock: sys}
jtag: {tap_impl: XILINX_BSCAN, conformance: false, ops: []}
software: {devicetree: true}
```

## Verification

- Schema validation of every example and reference SoC; deliberate errors of every validation
  rule are caught with the right message.
- Reproducibility: two runs give byte-identical outputs.
- Generated tops compile in SV and VHDL (and mixed); `soc.dts` compiles with `dtc` and Zephyr's
  binding checker; `soc.h` passes the cross-compile checks; the generated `.sdc` / `.upf` load in
  DC / PrimeTime / VC LP on csun.edu.
- SoC-0 built from the example runs on the Zybo-Z7 with the cmd2bus host library.

## Change log

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-11-27 | approved |
