# Verification of the memory-bus master adapters (`claude_<proto>_mst_if`)

The master adapters (`IP/common/design/rtl/{verilog,vhdl}/claude_<proto>_mst_if.*`) take
requests on the Claude memory bus and issue them as APB4 / AHB-Lite / AXI4-Lite /
Wishbone B4 master transfers. Specification:
[`.agents/IP_SPEC_mem_bus_initiator.md`](../../../../.agents/IP_SPEC_mem_bus_initiator.md)
(rules 6–9, `mem_prot`, timing) on top of
[`.agents/IP_SPEC_mem_bus.md`](../../../../.agents/IP_SPEC_mem_bus.md) (rules 1–5). They are
shared, so they are verified here once.

Status: **`claude_apb_mst_if`, `claude_ahb_mst_if` and `claude_axi4l_mst_if` done** (SV
and VHDL, simulation and lint on the standard host); Wishbone follows. Formal (VC Formal) and the VCS / Xcelium
runs are csun.edu work, still to do.

```
mst_if/
├── tb/
│   ├── tb_claude_<proto>_mst_if.sv   SV loopback testbench per protocol (bus monitor inside)
│   ├── mst_if_tests.sv               SV protocol-neutral BFM, reference memory, tests
│   ├── tb_claude_<proto>_mst_if.vhd  pure-VHDL twin of each testbench (GHDL)
│   └── mst_if_stim.vhd               VHDL protocol-neutral initiator, reference memory, tests
├── lint/                             verilator.flags, vhdl_lint.toml, waivers.md (as for a regular IP)
├── results.log                       last run of verify_mst_if.py
└── work/                             tool output (git-ignored)
```

The master adapters have the same RTL, lint and synthesis requirements as regular IP (user,
2026-11-27): both languages simulate on Icarus / GHDL (pure-language benches), xsim and
ModelSim (every SV / VHDL pairing), and VCS / Xcelium on csun.edu; lint with Verilator and
GHDL (SpyGlass on csun.edu); synthesis with Yosys, Vivado and Quartus (Design Compiler and
PrimeTime on csun.edu).

The memory behind the slave adapter is `IP/common/verification/models/claude_mem_model.sv`
(behavioral `mem_*` SRAM: size, base, random grant / response delays, error range,
backdoor), written for these tests and the planned bus_matrix system test, and its VHDL twin
`claude_mem_model.vhd` (same timing and the same xorshift32 random generator) for the
pure-VHDL benches.

## Loopback

```
initiator BFM ─ mem_* ─► claude_<proto>_mst_if (DUT) ─ bus ─► claude_<proto>_mem_if ─ mem_* ─► claude_mem_model
```

The slave adapter is the signed-off one. The DUT and the slave adapter can each be SV or
VHDL, so every language pairing runs (`sv-sv`, `sv-vhdl`, `vhdl-sv`, `vhdl-vhdl`, master
first; mixed pairs need a mixed-language simulator).

## Running

```bash
source IP/system/timer/setup.sh        # any IP's setup.sh sets IP_COMMON_PATH
cd $IP_COMMON_PATH/verification/tools
python3 verify_mst_if.py --sim local --lint --fpga   # every tool on a standard host
python3 verify_mst_if.py --sim xsim --pair vhdl-sv --width 32
python3 verify_mst_if.py --sim vcs              # csun.edu
python3 verify_mst_if.py --clean
```

Each simulation runs at `DATA_W` 32, 16 and 8 (`--width`); AXI4-Lite at 32 and 64 (the
only widths AXI4-Lite allows). AHB-Lite also runs both parameter sets
`HAS_HWSTRB = 1, HAS_HNONSEC = 1` and `HAS_HWSTRB = 0, HAS_HNONSEC = 0`.

`--sim local` runs Icarus (sv-sv), GHDL (vhdl-vhdl, the pure-VHDL benches), xsim and
ModelSim (every pair). Icarus needed one change in the signed-off `claude_ahb_mem_if.sv` and
`claude_axi4l_mem_if.sv` (a `?:` of enum values rewritten as `if` / `else`, user-approved
2026-11-27); those two files are due for re-verification on csun.edu (checklist, retrofit
track).

**Back-pressure.** The signed-off slave adapters are ready whenever a master has only one
transfer outstanding, which would leave the master's "hold until ready" rules untested.
The AHB testbench therefore holds the bus-wide HREADY low at random outside the master's
own data phase (as another slave stretching its data phase would), and the AXI4-Lite
testbench has a channel throttle that delays AWREADY / WREADY / ARREADY at random (legal on
both sides: a VALID passed to the slave stays until its handshake). Both run in the second
(random-delay) pass.

## What is checked

On the DUT's `mem_*` side (it is the target): `mem_gnt` low in reset; one response per
accepted request, never in the handshake cycle, never without a request outstanding.
On the bus side (APB4 monitor in the testbench): every APB4 master rule (PENABLE only with
PSEL, SETUP always followed by ACCESS with the same payload, wait states hold everything,
PENABLE low after a completed ACCESS, PSTRB zero on reads, bus idle in reset), and an
**end-to-end check**: each accepted request appears exactly once on the bus with the same
direction, address, PPROT, strobes and write data.

On the AXI4-Lite side the monitor checks: AW / W / AR VALID and payload held until READY,
AWVALID and WVALID raised together, one transaction outstanding and never a read and a
write at once, BREADY / RREADY only while a response is expected, every VALID / READY low in
reset; end to end: AWADDR / ARADDR, AWPROT / ARPROT, WDATA and WSTRB.

On the AHB-Lite side the monitor checks: the address phase held unchanged while HREADY is
low, HTRANS only IDLE / NONSEQ and no new transfer
during a data phase, HBURST SINGLE, HMASTLOCK 0, HSIZE no wider than the bus and HADDR
aligned to it, HWDATA / HWSTRB held through data-phase wait states, HTRANS IDLE in reset;
end to end: HADDR / HSIZE (the request's address and size for aligned patterns, the
word-aligned address at full size for sparse writes), HWRITE, HPROT
(`{0, 0, prot[0], ~prot[2]}`), HNONSEC, HWSTRB and HWDATA.

| Test | Checks |
|---|---|
| `test_latency` | zero-wait memory: APB response in cycle 3, one transfer per 4 cycles (spec table); AHB 4 and 5, because the signed-off AHB slave adapter adds one wait state per beat; AXI4-Lite 5 and 6, because the signed-off slave adapter registers its slots and responses |
| `test_basic_rw` | full words at both ends and the middle, back to back |
| `test_sizes_lanes` | every naturally aligned size on every lane (rules 6, 7), read back exactly those lanes |
| `test_sparse_strobes` | every write-strobe pattern (rule 8), read back as a whole word; AHB with `HAS_HWSTRB = 0`: every non-aligned pattern is answered with `mem_err` and **no** bus access, and memory is unchanged |
| `test_prot` | all eight `mem_prot` values reach PPROT |
| `test_error` | error region: PSLVERR reaches `mem_err`, the write is dropped, the next transfer is OKAY |
| `test_reset_mid_transfer` | reset during ACCESS: bus idle and `mem_gnt` low during reset, traffic resumes |
| `test_random` | 500 constrained-random transfers (sizes, lanes, sparse strobes, 5 % errors, random PPROT) against the reference memory |

The tests run twice: zero-wait memory with no idle cycles, then random grant (0–3) and
response (0–4) delays in the memory and random idle cycles (0–3) in the initiator.

The testbench was checked against deliberately broken adapters, and each run reports FAIL:
APB (PSTRB not zeroed on reads, `mem_gnt` held high during a transfer, a corrupted PADDR
bit) AHB (HSIZE always full width, HTRANS left at NONSEQ, the rule-8 check removed, the address
phase not held while HREADY is low) and AXI4-Lite (WVALID or ARVALID dropped before READY,
a wrong ARPROT, the error taken from RRESP[0]).

## Lint and synthesis

- `--lint`: Verilator with `lint/verilator.flags` (`-Wall`, any warning fails) on each SV
  adapter, GHDL analysis and `--synth` on each VHDL adapter (`lint/vhdl_lint.toml`), Yosys
  synthesis of both (VHDL through the GHDL plugin), and a check that out-of-range parameters
  stop elaboration in both languages. No waivers (`lint/waivers.md`).
- `--fpga`: out-of-context synthesis of every adapter, SV and VHDL, in Vivado (xc7z010,
  Zybo-Z7) and Quartus Lite (5CSEMA4U23C6, DE0-Nano-SoC).
- Still to set up on csun.edu: SpyGlass lint, Design Compiler + PrimeTime, VC Formal.
