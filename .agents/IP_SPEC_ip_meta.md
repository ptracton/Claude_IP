# IP metadata (`<ip>.ip.yaml`) — approved 2026-11-27

Spec version: **1.0**. Location: `.agents/IP_SPEC_ip_meta.md` (all interface specs live in `.agents/`; the RTL
headers of components built from it point here).

Status: specification only, Phase 0.1 of `.agents/IP_PLAN.md` (§4 SoC assembly). Nothing
here is implemented yet.

The SoC generator (`IP_SPEC_soc_yaml.md`) must know, for every IP, its parameters, ports,
clock / reset / power domains, planes, registers, interrupts, events, streams, golden model
and verification status, without reading its RTL by hand. Each IP therefore ships one
machine-readable file, **`IP/<category>/<ip>/<ip>.ip.yaml`**, partly generated and partly
written, and checked against the RTL on every regression.

---

## Rules

1. **One file per IP**, at the IP's root, schema version in the file (`meta_version: 1`).
2. **Generated parts are never edited by hand:** ports (parsed from the SV and VHDL tops by
   `IP/common/tools/ip_meta.py`), registers (from the `.rdl`), resources (from the synthesis
   reports), status (from the step results). The written parts are the descriptions that only
   the designer knows (planes, domains, parameter ranges, model hooks).
3. **Consistency check** (`ip_meta.py --check`, run by the regression): the SV and VHDL tops
   have identical ports and parameters; every port belongs to exactly one declared plane or
   group; every parameter range matches the RTL's elaboration checks; every `spec_versions`
   entry names an existing spec version.
4. **IP-XACT** (IEEE 1685-2022) export is a later script (`ip_meta.py --ipxact`); the YAML is the
   source.

## Schema (version 1)

```yaml
meta_version: 1
name: fir                      # IP name (directory name)
category: DSP                  # IP/<category>/
version: 1.0.0                 # IP version, same as STD_VERSION
description: "Fixed-point FIR filter, 1-1024 taps, polyphase decimate / interpolate"
spec_versions:                 # interface specs this version implements
  stream: "1.1"
  sideband: "1.1"
  ctl_stream: "1.1"
  fx: "1.0"
languages: [sv, vhdl]
tops:                          # one per bus protocol
  apb:   {sv: fir_apb,   vhdl: fir_apb}
  ahb:   {sv: fir_ahb,   vhdl: fir_ahb}
  axi4l: {sv: fir_axi4l, vhdl: fir_axi4l}
  wb:    {sv: fir_wb,    vhdl: fir_wb}

parameters:                    # written: ranges and meaning; checked against the RTL
  - {name: TAPS,     type: int, default: 63, range: [1, 1024], doc: "number of taps"}
  - {name: S_W,      type: int, default: 16, range: [2, 32]}
  - {name: S_FRAC_W, type: int, default: 15}
  - {name: ROUND,    type: enum, default: FX_CONVERGENT, values: fx_round}
  - {name: CTL_PORT, type: int, default: 1, range: [0, 1]}

clocks:
  - {name: clk, domain: bus, gateable: true, branches: [mac, coef]}   # claude_clk_gate branches
resets:
  - {name: rst_n, domain: bus}
ticks: []                      # tick_<name>_i inputs (IP_SPEC_sideband.md)
power:
  pwr_gate: false              # PWR_GATE support
  domains: []                  # internal power domains, if any
  clamps: {}                   # output -> isolation value (generated from the spec table when pwr_gate)

planes:
  control: {protocols: [apb, ahb, axi4l, wb], window: 4096, std_block: 0xFC0, err_bridges: true}
  memory_master: null          # or {adapter: mst_if, addr_w: 32}
  streams:
    - {port: s_data, role: sink,   format: {from_params: S_}}
    - {port: m_data, role: source, format: {from_params: M_}, out_fmt: "fir_model:out_fmt"}
  bus_mode: {block: 0xF80}
  ctl_port: {param: CTL_PORT, sec_req_default: 0, sync_boundary: "start of frame"}
  events:
    outputs: [{name: evt_frame_o, index: 0, doc: "frame done", max_rate: 1}]
    inputs:  [{name: evt_swap_i,  index: 0, action: "COEF_SWAP", policy: PEND}]
  irq: {width: 1, causes: from_rdl}
  dma: null
  dft: {ports: [test_mode_i, scan_en_i], waivers: [DFT0]}

registers: {rdl: design/systemrdl/fir.rdl}            # generated register list below
math:
  model: verification/model/fir_model.py             # golden model module
  out_fmt: "fir_model:out_fmt"                        # lossless format hook (IP_SPEC_fx.md)
  recursive_points: []                                # IP_SPEC_fx.md R1
  cmsis_compatible: {ROUND: FX_TRUNC, SAT: FX_SAT}    # R10, if any
firmware:
  headers: [firmware/include/fir.h, firmware/include/fir_regs.h]

# ---- generated sections (ip_meta.py) ----
ports:        []   # every top port: name, dir, width expression, plane / group
register_map: []   # name, offset, access, fields (with fx_fmt / flt_fmt)
resources:    {}   # per PDK / FPGA: area, cells, LUT / FF / DSP / BRAM, fmax
status:            # per step: result, date, host; signed_off: {host: csun.edu, date: ...}
  steps: {}
```

## Uses

- **SoC generator:** instantiation (tops, parameters, ports by plane), address-map windows,
  clock / reset / power-domain wiring, IRQ and event numbering, stream format checks and
  `fmt: auto` (through `out_fmt`), control-stream DEST assignment and security, UPF assembly.
- **Docs:** the IP catalog page and the SoC documentation tables are generated from it.
- **Checks:** a SoC that uses a parameter value outside its range, an unsupported spec version,
  or an IP whose status is not signed off for the target host is reported before generation.

## Verification

- `ip_meta.py --check` passes for every IP in the regression; deliberate mismatches (a port added
  only in VHDL, a parameter range wider than the RTL check, an unknown spec version) are caught.
- The generated sections are reproducible (running twice gives identical files).

## Change log

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-11-27 | approved |
