# Verification of the memory-bus adapters (`claude_<proto>_mem_if`)

The adapters (`IP/common/design/rtl/{verilog,vhdl}/claude_<proto>_mem_if.*`)
connect an APB4, AHB-Lite, AXI4-Lite or Wishbone B4 slave port to the Claude
memory bus. The bus itself is specified in
[`IP/common/design/rtl/mem_bus.md`](../../design/rtl/mem_bus.md). Because the
adapters are shared, they are verified here, once, independently of any IP
that uses them.

```
mem_if/
├── tb/                          simulation (SV testbenches; VHDL DUT via mixed-language)
│   ├── tb_claude_<proto>_mem_if.sv   one testbench per protocol
│   ├── mem_if_tests.sv          protocol-neutral tests (`include'd by every testbench)
│   ├── claude_mem_tb_target.sv  memory model: random stalls, error region, protocol checks
│   └── claude_mem_if_elab.sv    all adapters at DATA_W 8/16/64 + AHB lane self-check
├── formal/                      VC Formal harnesses, bound into each adapter
│   ├── claude_<proto>_mem_if_fv.sv       bus checker + memory-bus checker + end-to-end checker
│   ├── claude_<proto>_mem_if_fv_bind.sv  bind-only module (works for SV and VHDL tops)
│   └── claude_mem_if_fv_waivers.txt      waivers (none)
├── results.log                  last run of verify_mem_if.py
└── work/                        tool output (git-ignored)
```

## Running

```bash
source IP/system/timer/setup.sh        # any IP's setup.sh sets IP_COMMON_PATH
cd $IP_COMMON_PATH/verification/tools
python3 verify_mem_if.py --sim all --formal          # everything (csun.edu)
python3 verify_mem_if.py --sim vcs --proto ahb --lang vhdl
python3 verify_mem_if.py --formal --proto axi4l --max-time 2H --traces
python3 verify_mem_if.py --clean
```

Simulators: VCS and Xcelium (both languages through one SV testbench).
Formal: VC Formal, using the shared `claude_vcf.py` driver. These are the
csun.edu tools. Icarus/GHDL/SymbiYosys runs are not set up here: the SRAM IP
exercises the adapters through its own per-language testbenches.

## What the simulation checks

Each testbench runs the shared tests twice: once against a memory that grants
at once and answers in the next cycle, and once with random grant delays
(0–3) and response delays (0–4 extra cycles).

| Test | Checks |
|---|---|
| `test_basic_rw` | words at both ends and the middle of the storage |
| `test_strobe` | partial writes merge (strobes 0001, 0100, 1010, 0000) |
| `test_sweep` | 64 consecutive words |
| `test_raw` | read directly after a write to the same word |
| `test_error` | error region gives the bus error response on writes and reads; the write is dropped; the next transfer is OKAY |
| `test_ahb_sized` (AHB) | byte and halfword transfers: byte enables from HSIZE/HADDR, ANDed with HWSTRB |
| `test_ahb_burst` (AHB) | pipelined INCR4 bursts with SEQ beats, with and without a BUSY cycle; a burst into the error region |
| `test_axi_concurrent` (AXI4-Lite) | a write and a read issued in the same cycle both complete correctly |
| `check_accounting` | memory requests == bus transfers; no memory-bus protocol violation seen by the model; the slow half really stalled |

The memory model drives `mem_rdata`/`mem_err` to X outside the response
cycle, so an adapter that samples them at the wrong time shows up as X.

## What formal proves

For each adapter, in SV and in VHDL, with the solver acting as any legal bus
master and any legal memory (grant and response each within 2 cycles):

- the adapter obeys its bus protocol as a slave (`claude_<proto>_fv`;
  AHB with bursts, BUSY and every legal HSIZE allowed);
- it obeys the memory-bus initiator rules (`claude_mem_fv`): request held
  until granted, one request at a time;
- every bus transfer becomes exactly one memory request carrying the same
  kind, address, byte enables and write data, and the bus response carries
  the memory's read data and error flag (`claude_mem_xfer_fv`; AXI checks
  writes and reads separately because B and R can complete together).

All assertions must be proven and non-vacuous and all covers covered.
