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
All VHDL testbenches must `use work.IP_NAME_test_pkg.all` and call `test_start()`,
`test_done()`, and `check_eq()` from the shared test package (see item 2a below).

#### 2a. Write `verification/tests/IP_NAME_test_pkg.vhd`

A shared VHDL package that provides verbose, formatted test output functions usable by
all four VHDL testbenches:

```vhdl
package IP_NAME_test_pkg is
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

**Compilation order**: `IP_NAME_test_pkg.vhd` **must be analyzed before any testbench**
that uses it. Place it first in the `vhdl_files()` list in `sim_IP_NAME.py`, before the
testbench `.vhd` file.

**Check patterns for masked STATUS bits**: use `check_eq(rdata and x"00000001", x"00000001",
"STATUS.INTR set")` rather than inline `if rdata(0) /= '1' then report...`. This ensures
`check_eq` counts the check and prints the formatted output.

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
pass_marker = f"PASS tb_IP_NAME_{proto}"
fail_marker = "FAIL"
done = False
while time.monotonic() < deadline:
    time.sleep(1)
    with open(log_path) as fh:
        sim_out = fh.read()
    if pass_marker in sim_out or fail_marker in sim_out:
        done = True; break
    if proc.poll() is not None:
        break
proc.terminate(); proc.wait(timeout=10)
```

**ModelSim do-file**: write only `run -all\n` — do NOT include `quit -f`. With
`stdin=subprocess.DEVNULL`, `quit -f` triggers a crash ("Unexpected EOF on RPC channel")
because vsim's internal IPC tries to read from the closed stdin pipe. Omitting it is safe:
`run -all` returns naturally when the simulation reaches a VHDL `wait;` deadlock.

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

## Quality Gate

- All eight `results.log` files (4 protocols × 2 languages) contain `PASS`.
- `sim_IP_NAME.py --proto all --lang all` exits non-zero when a deliberate assertion
  failure is injected into any testbench.
- No testbench or task code resides in `design/rtl/`.
- No compile-time DUT-selection defines in any testbench — DUT is named explicitly.
