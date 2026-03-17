# Step 4 — `directed_tests` Sub-Agent

## Trigger

Step 3 complete (`design/rtl/verilog/` and `design/rtl/vhdl/` populated and parse-clean).

## Prerequisites

- All RTL and bus adapter sources in `design/rtl/verilog/` and `design/rtl/vhdl/` are
  parse-clean.
- `verification/testbench/`, `verification/tests/`, `verification/tasks/`,
  `verification/work/` directories exist.
- `verification/tools/sim_IP_NAME.py` skeleton exists from Step 1.
- `IP_COMMON_PATH` is set (sourced from `setup.sh`).

## Common Components

**Check `${IP_COMMON_PATH}/verification/tasks/` before writing any new BFM task library.**

- Protocol BFM task libraries for AHB-Lite, APB4, AXI4-Lite, and Wishbone B4 live in
  `${IP_COMMON_PATH}/verification/tasks/` (`ahb_bfm.sv`, `apb_bfm.sv`, etc.).
  Include them directly in the testbench rather than re-implementing bus-driving logic.
- If a common BFM does not yet exist for a required protocol, write it in
  `${IP_COMMON_PATH}/verification/tasks/` so all future IPs can reuse it.
- IP-specific test stimulus and assertions belong in `verification/tests/`; generic
  protocol mechanics belong in `${IP_COMMON_PATH}/verification/tasks/`.
- All references to common tasks must use `IP_COMMON_PATH`, never a hardcoded path.

**Check `${IP_COMMON_PATH}/verification/tools/` for the Python base class.**

- `${IP_COMMON_PATH}/verification/tools/ip_tool_base.py` provides the env-var guard,
  results-log writer, and subprocess runner used by all tool scripts. Import it rather
  than duplicating that logic in `sim_IP_NAME.py`.

## Coding Standards

**RULE — Read both style guides in full before writing a single line of testbench code.**

- `.agents/VerilogCodingStyle.md` — lowRISC Comportable style for SystemVerilog
- `.agents/VHDL2008CodingStyle.md` — IEEE 1076-2008 VHDL style

**RULE — These documents are immutable. Do not edit, summarize, or override them.**
Every rule applies to every `.sv` and `.vhd` file produced by this step. If a style-guide
rule and any other instruction conflict, the style guide wins for all matters of code
formatting and structure.

**RULE — No silent deviations.** Any line that cannot comply must carry an inline comment
explaining why. Deviations without a comment are a quality-gate failure.

## Responsibilities

1. Write the top-level simulation testbench `verification/testbench/testbench.sv`:
   - Instantiates the DUT (one bus protocol at a time, selected by a compile-time define).
   - Drives clock and reset.
   - Calls tasks from `verification/tasks/` to run each test.
   - Calls `$finish(1)` on any assertion failure.
2. Write VHDL testbench equivalents in `verification/testbench/` for each bus protocol:
   - `tb_IP_NAME_<proto>.vhd` — instantiates VHDL DUT and drives all tests.
3. Write reusable bus-functional model (BFM) tasks in `verification/tasks/`:
   - `tasks_<proto>.sv` — SV task library: `write_reg`, `read_reg`, `assert_eq`,
     `apply_reset`, `burst_write`, `burst_read`.
4. Write individual directed test files in `verification/tests/`:
   - `test_reset.sv` — verify all registers reach reset state.
   - `test_rw.sv` — single register write then read-back for every register.
   - `test_back2back.sv` — back-to-back transactions without idle cycles.
   - `test_strobe.sv` — byte-enable / write-strobe combinations.
   - `test_IP_NAME_ops.sv` — IP-specific functional operations.
5. Complete `verification/tools/sim_IP_NAME.py`:
   - Builds the correct file list for the selected simulator and language.
   - Passes compile-time defines for protocol selection.
   - Captures simulator stdout/stderr.
   - Writes `verification/work/<sim>/results.log` with `PASS` or `FAIL`.
   - Exits non-zero on `FAIL`.
6. Run Icarus Verilog and GHDL locally; both must produce `PASS` before marking complete.

## Outputs

| Artifact | Description |
|----------|-------------|
| `verification/testbench/testbench.sv` | Top-level SV testbench |
| `verification/testbench/tb_IP_NAME_<proto>.vhd` | VHDL testbench per bus protocol |
| `verification/tasks/tasks_<proto>.sv` | Reusable SV BFM task library |
| `verification/tests/test_*.sv` | Directed SV test files |
| `verification/tools/sim_IP_NAME.py` | Completed simulation runner |
| `verification/work/<sim>/results.log` | `PASS` / `FAIL` per simulator |

## Quality Gate

- `verification/work/icarus/results.log` contains `PASS`.
- `verification/work/ghdl/results.log` contains `PASS`.
- `sim_IP_NAME.py` exits non-zero when a deliberate assertion failure is injected.
- No testbench or task code resides in `design/rtl/`.
