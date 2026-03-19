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

**RULE — No SystemVerilog `interface` constructs.** Icarus Verilog does not support SV
`interface` / `modport` / `virtual interface`. All testbench and BFM connections must use
explicit individual signals. Using `interface` is a quality-gate failure.

## Responsibilities

Because each bus protocol is a **separate top-level entity** (`IP_NAME_ahb`,
`IP_NAME_apb`, `IP_NAME_axi4l`, `IP_NAME_wb`), there is one dedicated testbench per
top-level in both SystemVerilog and VHDL. There are no compile-time defines to select
a protocol — each testbench file explicitly names its DUT.

### 1. Write SV testbenches — one per top-level

Create one file per bus protocol under `verification/testbench/`:

| File | DUT instantiated |
|------|-----------------|
| `tb_IP_NAME_ahb.sv` | `IP_NAME_ahb` |
| `tb_IP_NAME_apb.sv` | `IP_NAME_apb` |
| `tb_IP_NAME_axi4l.sv` | `IP_NAME_axi4l` |
| `tb_IP_NAME_wb.sv` | `IP_NAME_wb` |

Each SV testbench:
- Instantiates **only** its named DUT (no DUT-selection defines).
- Drives clock and reset.
- Includes the BFM task library for its protocol from `verification/tasks/` or
  `${IP_COMMON_PATH}/verification/tasks/`.
- Calls the shared test tasks from `verification/tests/`.
- Calls `$finish(1)` on any assertion failure.

### 2. Write VHDL testbenches — one per top-level

Create one file per bus protocol under `verification/testbench/`:

| File | DUT instantiated |
|------|-----------------|
| `tb_IP_NAME_ahb.vhd` | `IP_NAME_ahb` |
| `tb_IP_NAME_apb.vhd` | `IP_NAME_apb` |
| `tb_IP_NAME_axi4l.vhd` | `IP_NAME_axi4l` |
| `tb_IP_NAME_wb.vhd` | `IP_NAME_wb` |

Each VHDL testbench instantiates its named VHDL DUT and drives all tests.
All VHDL testbenches must `use work.ip_test_pkg.all` and call `test_start()`,
`test_done()`, and `check_eq()` from the shared test package (see item 2a below).

**RULE — Add `use std.env.all;` and end the stimulus process with `stop;` (not `wait;`).**
See `.agents/VHDL2008CodingStyle.md` §Testbench Simulation Termination for the full rule.
Without `stop;`, Vivado xsim runs forever after tests complete, then crashes with
`FATAL_ERROR` when the process runner kills it. GHDL and ModelSim are also more
robust when `stop;` is used.

#### 2a. VHDL test package — use common `ip_test_pkg`

**Do NOT create a per-IP test package.** A generic VHDL-2008 test package already exists
at `${IP_COMMON_PATH}/verification/tests/ip_test_pkg.vhd`. All four VHDL testbenches must
use it directly:

```vhdl
use work.ip_test_pkg.all;
```

The package provides `test_start`, `test_done`, and `check_eq` with the same signatures as
the old per-IP package. There is also a matching SV include file at
`${IP_COMMON_PATH}/verification/tests/ip_test_pkg.sv` — SV testbenches use
`` `include "ip_test_pkg.sv" `` (resolved via the `-I` include path set in the runner).

The package interface:

```vhdl
package ip_test_pkg is
  shared variable chk_num : integer := 0;  -- GHDL needs -frelaxed for this
  procedure test_start(name : string);
  procedure test_done(name : string);
  procedure check_eq(
    actual   : std_ulogic_vector(31 downto 0);
    expected : std_ulogic_vector(31 downto 0);
    msg      : string
  );
end package;
```

`check_eq` must:
- Increment `chk_num`
- Print a formatted line: `[N] <msg> | exp=<hex> | got=<hex> | PASS/FAIL`
- Call `report "FAIL: <msg>" severity failure` on mismatch

**GHDL shared variable constraint**: VHDL-2008 strict mode requires shared variables to
use a protected type. `chk_num : integer` is not protected. Compile GHDL with `-frelaxed`
to downgrade this to a warning. **Add `-frelaxed` to every GHDL command** (analyze,
elaborate, simulate) in `sim_IP_NAME.py`.

**Compilation order**: `ip_test_pkg.vhd` **must be analyzed before any testbench** that
uses it. In `sim_IP_NAME.py`, build a `COMMON_TESTS` path:
```python
common_tests = os.path.join(common_path, "verification", "tests")
```
and place `os.path.join(common_tests, "ip_test_pkg.vhd")` first in the VHDL file list.
For Icarus, add `common_tests` to the `-I` include dir list so SV testbenches find
`ip_test_pkg.sv`.

**Check patterns for masked STATUS bits**: use `check_eq(rdata and x"00000001", x"00000001",
"STATUS.INTR set")` rather than inline `if rdata(0) /= '1' then report...`. This ensures
`check_eq` counts the check and prints the formatted output.

**Read-only register test pattern**: Never hardcode the expected value of a hardware-updated
register (COUNT, CAPTURE, STATUS.ACTIVE) after the timer has been running. The counter value
at any given point depends on timing, safe_load_val behavior, and protocol latency. Instead,
use a **read-before/write/read-after** pattern:

```vhdl
-- Read COUNT before write attempt (save baseline)
-- ... drive bus read to 0x00C, capture rdata into saved_count ...
saved_count := HRDATA;  -- or PRDATA, RDATA, DAT_O depending on protocol

-- Attempt write to COUNT (should be ignored — it is read-only)
-- ... drive bus write of 0xFFFFFFFF to 0x00C ...

-- Read COUNT again — must equal saved value (write was ignored)
-- ... drive bus read to 0x00C, capture rdata ...
check_eq(rdata_v, saved_count, "COUNT read-only");
```

Declare `variable saved_count : std_ulogic_vector(31 downto 0);` in the process variable
declarations alongside `rdata_v` and `timeout`. This pattern is protocol-agnostic and
works regardless of what value the hardware counter currently holds.

### 3. Write reusable BFM task libraries

**First** check `${IP_COMMON_PATH}/verification/tasks/` for existing BFMs. If a
common BFM exists for the protocol, include it; do not re-implement it. If it does
not exist, write it there so future IPs benefit.

For any protocol not yet in common, create in `verification/tasks/`:
- `tasks_ahb.sv`, `tasks_apb.sv`, `tasks_axi4l.sv`, `tasks_wb.sv`

Each task library provides: `write_reg`, `read_reg`, `assert_eq`, `apply_reset`,
`burst_write`, `burst_read`.

### 4. Write directed test files

Create in `verification/tests/` — these are protocol-agnostic test tasks called by
all four testbenches through the appropriate BFM interface:

- `test_reset.sv` — verify all registers reach reset state.
- `test_rw.sv` — single register write then read-back for every register.
- `test_back2back.sv` — back-to-back transactions without idle cycles.
- `test_strobe.sv` — byte-enable / write-strobe combinations.
- `test_IP_NAME_ops.sv` — IP-specific functional operations.

### 5. Complete `verification/tools/sim_IP_NAME.py`

- Accepts `--proto {ahb,apb,axi4l,wb,all}` and `--lang {sv,vhdl,all}`.
- Accepts `--sim {icarus,ghdl,modelsim,all}`.
- Builds the correct file list for the selected simulator, DUT top-level, and language.
- No compile-time defines for protocol — the testbench file selects the DUT.
- Captures simulator stdout/stderr.
- Writes `verification/work/<sim>/<proto>_<lang>/results.log` with `PASS` or `FAIL`.
- Exits non-zero if any result is `FAIL`.

**GHDL flags**: add `-frelaxed` to the analyze, elaborate, and simulate commands.
`IP_NAME_test_pkg.vhd` must appear first in the VHDL file list.

**ModelSim (`vsim -c`) hangs with `subprocess.run()`**: ModelSim reads stdin
indefinitely even after the simulation completes when stdin is not a real terminal.
Do NOT use `subprocess.run()` for vsim. Use `subprocess.Popen` with
`stdin=subprocess.DEVNULL`, write stdout/stderr to a log file, and poll:

```python
proc = subprocess.Popen(
    vsim_cmd, stdout=log_fh, stderr=log_fh,
    stdin=subprocess.DEVNULL, cwd=work_dir
)
deadline = time.monotonic() + 300
pass_marker  = f"PASS tb_IP_NAME_{proto}"
fail_markers = ["FAIL", "FATAL_ERROR"]   # FATAL_ERROR not caught by "FAIL"
done = False
while time.monotonic() < deadline:
    time.sleep(1)
    with open(log_path) as fh:
        sim_out = fh.read()
    if pass_marker in sim_out or any(m in sim_out for m in fail_markers):
        done = True; break
    if proc.poll() is not None:
        break
proc.terminate()
try:
    proc.wait(timeout=10)
except subprocess.TimeoutExpired:
    proc.kill(); proc.wait()
```

**Fail-marker rule**: always check for both `"FAIL"` and `"FATAL_ERROR"`.
`"FATAL_ERROR"` does not contain the substring `"FAIL"`, so a single `fail_marker = "FAIL"`
will silently miss simulator kernel crashes.

**Position-based PASS/FAIL determination**: A `FATAL_ERROR` that appears *after* the
PASS banner in the log is caused by our process termination (simulator kernel orphaned),
not a real test failure. Evaluate pass/fail based on position:

```python
pass_pos = sim_out.find(pass_marker)
if pass_pos >= 0:
    pre_pass = sim_out[:pass_pos]
    passed = not any(m in pre_pass for m in fail_markers)
else:
    passed = False
```

**ModelSim do-file**: write only `run -all\n` — do NOT include `quit -f`. With
`stdin=subprocess.DEVNULL`, `quit -f` triggers a crash ("Unexpected EOF on RPC channel")
because vsim's internal IPC tries to read from the closed stdin pipe. Omitting it is safe:
`run -all` returns naturally when the simulation reaches `std.env.stop`.

### ModelSim GUI .do files (for interactive waveform viewing)

In addition to the batch-mode runner in `sim_IP_NAME.py`, provide GUI `.do` files so the
user can open ModelSim and see waveforms without running the Python script.

**RULE — Split every testbench into two `.do` files.** Place both under
`verification/modelsim/`:

| File | Purpose |
|------|---------|
| `tb_IP_NAME_<proto>.do` | Compile RTL + TB, call `vsim`, source the wave file, `run -all` |
| `tb_IP_NAME_<proto>_wave.do` | `add wave` commands only — loadable independently from the GUI |

The main `.do` must source the wave file with:
```tcl
do [file join [file dirname [info script]] tb_IP_NAME_<proto>_wave.do]
```

**Wave file format** — match the format ModelSim saves when you use File > Save Format:

```tcl
onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Clock & Reset}
add wave -noupdate -radix binary    /tb_IP_NAME_<proto>/clk
add wave -noupdate -radix binary    /tb_IP_NAME_<proto>/rst_n
add wave -noupdate -divider {<Protocol> Bus}
add wave -noupdate -radix hexadecimal /tb_IP_NAME_<proto>/<BUS_SIG>
...
add wave -noupdate -divider {DUT: regfile}
add wave -noupdate -radix hexadecimal /tb_IP_NAME_<proto>/u_dut/u_regfile/clk
add wave -noupdate -radix hexadecimal /tb_IP_NAME_<proto>/u_dut/u_regfile/rst_n
add wave -noupdate -radix hexadecimal /tb_IP_NAME_<proto>/u_dut/u_regfile/wr_en
add wave -noupdate -radix hexadecimal /tb_IP_NAME_<proto>/u_dut/u_regfile/wr_addr
add wave -noupdate -radix hexadecimal /tb_IP_NAME_<proto>/u_dut/u_regfile/wr_data
add wave -noupdate -radix hexadecimal /tb_IP_NAME_<proto>/u_dut/u_regfile/wr_strb
add wave -noupdate -radix hexadecimal /tb_IP_NAME_<proto>/u_dut/u_regfile/rd_en
add wave -noupdate -radix hexadecimal /tb_IP_NAME_<proto>/u_dut/u_regfile/rd_addr
add wave -noupdate -radix hexadecimal /tb_IP_NAME_<proto>/u_dut/u_regfile/rd_data
add wave -noupdate -radix hexadecimal /tb_IP_NAME_<proto>/u_dut/u_regfile/hw_count_val
...  (all regfile ports and internal _q registers)
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 217
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {0 ps} {624750 ps}
```

Key rules:
- Use `-noupdate` on every `add wave` command.
- Use `{Braces}` for divider names with spaces.
- Show all regfile **ports** (not just internal register names) plus the internal `_q` storage signals.
- End with `TreeUpdate`, `WaveRestoreCursors`, and `WaveRestoreZoom` as ModelSim expects.

**Path setup** in the main `.do` — use env var with fallback to script location:
```tcl
if {[info exists env(CLAUDE_IP_NAME_PATH)]} {
    set TIMER $env(CLAUDE_IP_NAME_PATH)
} else {
    set TIMER [file normalize [file dirname [info script]]/../..]
}
```

### Vivado GUI simulation projects (for interactive waveform viewing)

**RULE — Always create Vivado simulation projects for every bus interface.** This is
mandatory, not optional. Place all files under `verification/vivado/`:

| File | Purpose |
|------|---------|
| `create_project_<proto>.tcl` | Creates the Vivado project; run once to generate the `.xpr` |
| `wave_<proto>.tcl` | Adds waveform groups; sourced automatically at simulation start |

Projects target **`xc7z010clg400-1`** (Zynq-7010) — the same part used for synthesis.
Generated project files go under `verification/vivado/work/<proto>/` (gitignored).

#### `create_project_<proto>.tcl` structure

```tcl
# create_project_<proto>.tcl — Vivado project for IP_NAME <PROTO> simulation
# Usage:
#   vivado -mode tcl -source create_project_<proto>.tcl
#   or: source create_project_<proto>.tcl  (from the Vivado Tcl console)

set script_dir [file normalize [file dirname [info script]]]

if {[info exists ::env(CLAUDE_IP_NAME_PATH)]} {
    set ip_dir $::env(CLAUDE_IP_NAME_PATH)
} else {
    set ip_dir [file normalize "${script_dir}/../.."]
}
if {[info exists ::env(IP_COMMON_PATH)]} {
    set common_dir $::env(IP_COMMON_PATH)
} else {
    set common_dir [file normalize "${ip_dir}/../../common"]
}

set rtl_dir   "${ip_dir}/design/rtl/verilog"
set tasks_dir "${common_dir}/verification/tasks"
set tests_dir "${ip_dir}/verification/tests"
set tb_dir    "${ip_dir}/verification/testbench"
set work_dir  "${ip_dir}/verification/vivado/work/<proto>"
set wave_tcl  "${script_dir}/wave_<proto>.tcl"

create_project tb_IP_NAME_<proto> "${work_dir}" -part xc7z010clg400-1 -force
set_property simulator_language Mixed [current_project]
set_property target_language Verilog  [current_project]

add_files -norecurse [list \
    "${rtl_dir}/IP_NAME_reg_pkg.sv" \
    "${rtl_dir}/IP_NAME_regfile.sv" \
    "${rtl_dir}/IP_NAME_core.sv"    \
    "${rtl_dir}/IP_NAME_<proto>_if.sv" \
    "${rtl_dir}/IP_NAME_<proto>.sv" \
]
foreach f [get_files -of_objects [get_filesets sources_1] -filter {FILE_EXT == ".sv"}] {
    set_property file_type SystemVerilog $f
}

add_files -norecurse -sim_only "${tb_dir}/tb_IP_NAME_<proto>.sv"
set_property file_type SystemVerilog [get_files tb_IP_NAME_<proto>.sv]

set_property top              tb_IP_NAME_<proto> [get_filesets sim_1]
set_property top_lib          xil_defaultlib     [get_filesets sim_1]
set_property include_dirs     [list "${tasks_dir}" "${tests_dir}"] \
                              [get_filesets sim_1]
set_property -name {xsim.simulate.runtime}    -value {1ms}         -objects [get_filesets sim_1]
set_property -name {xsim.simulate.custom_tcl} -value "${wave_tcl}" -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Project created: ${work_dir}/tb_IP_NAME_<proto>.xpr"
```

#### `wave_<proto>.tcl` structure

```tcl
# wave_<proto>.tcl — Vivado xsim wave configuration for IP_NAME <PROTO> testbench
# Sourced automatically via xsim.simulate.custom_tcl.
# Can also be sourced manually from the Vivado Tcl console.

add_wave_divider "Clock & Reset"
add_wave /tb_IP_NAME_<proto>/clk
add_wave /tb_IP_NAME_<proto>/rst_n          ;# use RST_I for Wishbone

add_wave_divider "<Protocol> Bus"
add_wave /tb_IP_NAME_<proto>/<BUS_SIG>
add_wave -radix hex /tb_IP_NAME_<proto>/<BUS_DATA_SIG>
# ... all bus signals

add_wave_divider "IP Outputs"
add_wave /tb_IP_NAME_<proto>/irq
add_wave /tb_IP_NAME_<proto>/trigger_out

add_wave_divider "DUT: regfile ports"
add_wave /tb_IP_NAME_<proto>/u_dut/u_regfile/clk
add_wave /tb_IP_NAME_<proto>/u_dut/u_regfile/rst_n
add_wave /tb_IP_NAME_<proto>/u_dut/u_regfile/wr_en
add_wave -radix hex /tb_IP_NAME_<proto>/u_dut/u_regfile/wr_addr
add_wave -radix hex /tb_IP_NAME_<proto>/u_dut/u_regfile/wr_data
add_wave -radix hex /tb_IP_NAME_<proto>/u_dut/u_regfile/wr_strb
add_wave /tb_IP_NAME_<proto>/u_dut/u_regfile/rd_en
add_wave -radix hex /tb_IP_NAME_<proto>/u_dut/u_regfile/rd_addr
add_wave -radix hex /tb_IP_NAME_<proto>/u_dut/u_regfile/rd_data
# ... all hw_* and ctrl_* output ports

add_wave_divider "DUT: regfile storage"
add_wave -radix hex /tb_IP_NAME_<proto>/u_dut/u_regfile/ctrl_q
add_wave -radix hex /tb_IP_NAME_<proto>/u_dut/u_regfile/status_q
add_wave -radix hex /tb_IP_NAME_<proto>/u_dut/u_regfile/load_q
add_wave -radix hex /tb_IP_NAME_<proto>/u_dut/u_regfile/count_q
# ... any additional _q registers

add_wave_divider "DUT: core internals"
add_wave /tb_IP_NAME_<proto>/u_dut/u_core/ctrl_en
# ... key internal state signals (counters, flags, pulses)
```

Key rules for wave files:
- Use `add_wave_divider "Name"` (plain string, no braces).
- Use `add_wave -radix hex` for multi-bit data/address signals.
- Cover all regfile **ports** and internal `_q` storage signals.
- Cover key core internals: counter values, prescaler, `tick`, interrupt/trigger pulses.
- For Wishbone, replace `rst_n` with `RST_I` at the TB level (the regfile port is still `rst_n`).

#### How to use (for README)

Always add an **Interactive Simulation (GUI)** section to the IP `README.md` documenting:

1. Create project (once): `vivado -mode tcl -source verification/vivado/create_project_apb.tcl`
2. Open: `File > Open Project > verification/vivado/work/apb/tb_IP_NAME_apb.xpr`
3. Run: `Flow > Run Simulation > Run Behavioral Simulation`
4. Re-run after changes: **Restart** then **Run All** in xsim toolbar
5. Reload waves: `source /path/to/verification/vivado/wave_apb.tcl`

### 6. Run and verify

Run Icarus Verilog (SV) and GHDL (VHDL) for all four protocols. All eight combinations
must produce `PASS` before marking this step complete:

```
verification/work/icarus/ahb_sv/results.log    → PASS
verification/work/icarus/apb_sv/results.log    → PASS
verification/work/icarus/axi4l_sv/results.log  → PASS
verification/work/icarus/wb_sv/results.log     → PASS
verification/work/ghdl/ahb_vhdl/results.log    → PASS
verification/work/ghdl/apb_vhdl/results.log    → PASS
verification/work/ghdl/axi4l_vhdl/results.log  → PASS
verification/work/ghdl/wb_vhdl/results.log     → PASS
```

### 7. Update `README.md`

Replace the `[TBD]` placeholder in **Simulation Results** with a table of every
test × protocol × simulator × language combination and its result.
Include the simulator versions and the date the results were generated.
7. Update `README.md` — replace the `[TBD]` placeholder in **Simulation Results** with a
   table of every test run, the simulators used, the language tested, and the result:

   ```markdown
   | Test              | Simulator | Language | Result |
   |-------------------|-----------|----------|--------|
   | test_reset        | icarus    | SV       | PASS   |
   | test_reset        | ghdl      | VHDL     | PASS   |
   | test_rw           | icarus    | SV       | PASS   |
   | test_back2back    | icarus    | SV       | PASS   |
   | test_strobe       | icarus    | SV       | PASS   |
   | test_IP_NAME_ops  | icarus    | SV       | PASS   |
   ```

   Include the simulator version and the date the results were generated.

## Outputs

| Artifact | Description |
|----------|-------------|
| `verification/testbench/tb_IP_NAME_ahb.sv` | AHB-Lite SV testbench |
| `verification/testbench/tb_IP_NAME_apb.sv` | APB4 SV testbench |
| `verification/testbench/tb_IP_NAME_axi4l.sv` | AXI4-Lite SV testbench |
| `verification/testbench/tb_IP_NAME_wb.sv` | Wishbone B4 SV testbench |
| `verification/testbench/tb_IP_NAME_ahb.vhd` | AHB-Lite VHDL testbench |
| `verification/testbench/tb_IP_NAME_apb.vhd` | APB4 VHDL testbench |
| `verification/testbench/tb_IP_NAME_axi4l.vhd` | AXI4-Lite VHDL testbench |
| `verification/testbench/tb_IP_NAME_wb.vhd` | Wishbone B4 VHDL testbench |
| `verification/tasks/tasks_<proto>.sv` | Reusable SV BFM task library (if not in common) |
| `verification/tests/test_*.sv` | Directed SV test files |
| `verification/tools/sim_IP_NAME.py` | Completed simulation runner |
| `verification/work/<sim>/<proto>_<lang>/results.log` | `PASS` / `FAIL` per combination |
| `verification/modelsim/tb_IP_NAME_<proto>.do` | ModelSim GUI compile+sim script (4 files) |
| `verification/modelsim/tb_IP_NAME_<proto>_wave.do` | ModelSim waveform config (4 files) |
| `verification/vivado/create_project_<proto>.tcl` | Vivado project creation script (4 files) |
| `verification/vivado/wave_<proto>.tcl` | Vivado xsim waveform config (4 files) |

## Quality Gate

- All eight `results.log` files (4 protocols × 2 languages) contain `PASS`.
- `sim_IP_NAME.py --proto all --lang all` exits non-zero when a deliberate assertion
  failure is injected into any testbench.
- No testbench or task code resides in `design/rtl/`.
- No compile-time DUT-selection defines in any testbench — DUT is named explicitly.
- All four `verification/modelsim/tb_IP_NAME_<proto>.do` files exist and reference their
  corresponding `_wave.do` files.
- All four `verification/vivado/create_project_<proto>.tcl` files exist, target
  `xc7z010clg400-1`, set `xsim.simulate.custom_tcl` to the corresponding `wave_<proto>.tcl`,
  and include the correct RTL + TB sources with `include_dirs` for tasks and tests.
- All four `verification/vivado/wave_<proto>.tcl` files exist and cover Clock/Reset,
  bus signals, IP outputs, regfile ports, regfile storage, and core internals.
- `README.md` contains an **Interactive Simulation (GUI)** section documenting both
  ModelSim and Vivado usage.
