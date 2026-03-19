# Step 6 — `uvm` Sub-Agent

## Trigger

Step 5 complete (formal verification passing) and all directed tests passing; Vivado is
available (`xvlog`/`xelab`/`xsim` in `$PATH` after sourcing `setup.sh`).

## Prerequisites

- All eight directed-test results logs contain `PASS`
  (`verification/work/icarus/<proto>_sv/results.log` ×4 and
  `verification/work/ghdl/<proto>_vhdl/results.log` ×4).
- `verification/work/formal/<proto>/results.log` contains `PASS` for all protocols.
- `verification/testbench/`, `verification/tests/`, `verification/tasks/` exist and
  are populated from Step 4.
- `CLAUDE_<IP_NAME>_PATH` is set (sourced from `setup.sh`).
- Vivado 2023.1 or later is on `$PATH` (sourced from `setup.sh`).

## SV Interface Exception

**UVM ONLY**: `Claude_IP.md` bans SV `interface` constructs in directed-test BFMs because
Icarus Verilog does not support them. UVM runs exclusively on Vivado xsim, which **does**
support SV interfaces. UVM `virtual interface` is the standard UVM connection mechanism
and **is permitted** inside `verification/tasks/uvm/`. No SV `interface` may appear in
`verification/testbench/`, `verification/tests/`, or `verification/tasks/` outside
the `uvm/` subdirectory.

## Coding Standards

**RULE — Read the SystemVerilog style guide in full before writing a single line of UVM code.**

- `.agents/VerilogCodingStyle.md` — lowRISC Comportable style for SystemVerilog

**RULE — This document is immutable. Do not edit, summarize, or override it.**
Every rule applies to every `.sv` file produced by this step. If a style-guide rule and any
other instruction conflict, the style guide wins for all matters of code formatting and
structure.

**RULE — No silent deviations.** Any line that cannot comply must carry an inline comment
explaining why. Deviations without a comment are a quality-gate failure.

## Responsibilities

### 1. Create `verification/tasks/uvm/` structure

UVM sources live in `verification/tasks/uvm/` — **not** `verification/testbench/uvm/`.

The UVM testbench targets the APB4 bus variant of the IP (the most representative for
register-level UVM testing). One package bundles all UVM classes.

Required files (substitute `IP_NAME` throughout):

| File | Contents |
|------|----------|
| `IP_NAME_apb_if.sv` | **SV interface** — bundles all APB4 signals + IP outputs |
| `IP_NAME_uvm_pkg.sv` | Package that `` `include ``s all UVM class files in order |
| `tb_IP_NAME_uvm.sv` | Testbench top — clock/reset, DUT instantiation, VIF config_db set |
| `IP_NAME_seq_item.sv` | UVM sequence item (addr, data, strb, write, rdata) |
| `IP_NAME_sequencer.sv` | `uvm_sequencer` alias |
| `IP_NAME_apb_driver.sv` | APB4 driver — see **Driver Timing** section below |
| `IP_NAME_apb_monitor.sv` | APB4 monitor — observes ACCESS phase |
| `IP_NAME_env.sv` | UVM env — instantiates agent, scoreboard |
| `IP_NAME_scoreboard.sv` | Shadow register model — see **Scoreboard** section below |
| `IP_NAME_base_seq.sv` | Base + concrete sequences (reg-RW, IRQ) |
| `IP_NAME_base_test.sv` | Base test class + concrete test (`IP_NAME_base_test`) |

### 2. Naming conflicts between RTL and UVM

**CRITICAL**: If the RTL defines `module IP_NAME_apb_if` (the APB bus-interface bridge
module) AND the UVM defines `interface IP_NAME_apb_if` (the BFM signal bundle), SystemVerilog
allows a module and an interface to share a name **only when they live in different work
libraries**.

Compile RTL into `rtl_lib` and UVM sources into the default `work` library. xelab resolves
the DUT's `IP_NAME_apb_if` instantiation to the MODULE in `rtl_lib`; the testbench resolves
its `IP_NAME_apb_if` to the INTERFACE in `work`.

### 3. Driver timing for registered reads

**CRITICAL — do not get this wrong.** The regfile read path is **registered**:
```
rd_data <= reg[rd_addr]   // always_ff, updated one cycle after rd_en
```
The APB interface asserts `rd_en` during the **SETUP phase** (PSEL=1, PENABLE=0) so that
`rd_data` is valid at the ACCESS phase. From the driver's perspective:

```
T1 posedge: drive PSEL=1, PENABLE=0, PADDR     (SETUP phase, NBAs applied at end of T1)
T2 posedge: drive PENABLE=1                     (ACCESS phase, NBAs applied at end of T2)
            → DUT's rd_en fires at T2 posedge Active
            → rd_data NBA update fires at end of T2
            → PRDATA at T2 Active is STALE (pre-T2 value)
T3 posedge: DUT sees PSEL=1, PENABLE=1 (from T2 NBA)
            → PRDATA = rd_data = reg[addr]  ← CORRECT here
            drive PSEL=0, PENABLE=0         (return to idle)
```

**Capture `item.rdata = vif.PRDATA` at T3 (the idle clock), NOT at T2.**

Capturing at T2's Active region reads stale data because the `always_ff` NBA for `rd_data`
has not yet propagated. This produces a consistent "one-behind" error where read-back of
register N returns the value from register N-1's transaction.

Correct driver structure:
```systemverilog
// SETUP phase
@(posedge vif.PCLK);
vif.PSEL <= 1; vif.PENABLE <= 0; vif.PADDR <= item.addr; ...

// ACCESS phase
@(posedge vif.PCLK);
vif.PENABLE <= 1;
while (!vif.PREADY) @(posedge vif.PCLK);

// Idle / capture — DUT sees PSEL=1, PENABLE=1 here; PRDATA is valid
@(posedge vif.PCLK);
vif.PSEL <= 0; vif.PENABLE <= 0; ...
if (!item.write) item.rdata = vif.PRDATA;   // ← correct capture point
```

### 4. Scoreboard shadow model for hardware-driven bits

Status bits set by hardware (e.g., `STATUS.INTR` set by `hw_intr_set` pulse from the core)
are **not visible** to the scoreboard's write handler. When a STATUS read returns a bit as
`1` but the shadow says `0`, it means hardware set it — this is valid behavior, not a FAIL.

**Rule**: In `handle_read` for W1C status registers, if `actual[bit] == 1` but
`shadow[bit] == 0`, **update the shadow to 1** (log an INFO about hardware set) and
**PASS** the comparison. Only FAIL if `actual[bit] == 1` when the shadow says `0` **after**
a confirmed W1C write cleared it AND the hardware cannot have re-set it (e.g., timer
disabled).

For simpler implementations: skip the INTR bit comparison on reads during polling; only
assert INTR=0 after a W1C write.

### 5. Create `verification/tools/uvm_IP_NAME.py`

A **separate, standalone runner** — do not add a `--uvm-test` flag to `sim_IP_NAME.py`.

The runner uses a three-step Vivado xsim flow:

#### Step 1a — compile RTL into `rtl_lib`
```
xvlog --sv --uvm_version 1.2
      -L uvm=<VIVADO>/data/xsim/system_verilog/uvm
      -i <VIVADO>/data/xsim/system_verilog/uvm_include
      --work rtl_lib=<work_dir>/rtl_lib
      --log xvlog_rtl.log
      <all RTL .sv files>
```

#### Step 1b — compile UVM sources into `work`
```
xvlog --sv --uvm_version 1.2
      -L uvm=<VIVADO>/data/xsim/system_verilog/uvm
      -i <VIVADO>/data/xsim/system_verilog/uvm_include
      --work work=<work_dir>/work
      -L rtl_lib=<work_dir>/rtl_lib
      --log xvlog_uvm.log
      <all UVM .sv files in verification/tasks/uvm/>
```

#### Step 2 — elaborate
```
xelab --uvm_version 1.2
      --debug typical
      --snapshot tb_uvm_sim
      --timescale 1ns/1ps          # ← REQUIRED if any RTL lacks `timescale
      --log xelab.log
      -L uvm=<VIVADO>/data/xsim/system_verilog/uvm
      -L work=<work_dir>/work
      -L rtl_lib=<work_dir>/rtl_lib
      work.tb_IP_NAME_uvm
```

**`--timescale 1ns/1ps` is mandatory** when the RTL modules do not carry `` `timescale ``
directives. Without it, xelab 43-4100 fails: *"Module X has a timescale but at least one
module in design doesn't have timescale."*

#### Step 3 — simulate (Popen + polling)

`xsim` with `--runall` hangs indefinitely when its stdin is not a real terminal (it keeps
reading even after the simulation completes). **Never use `subprocess.run()` for xsim.**

Use `subprocess.Popen` with `stdin=subprocess.DEVNULL`, writing stdout/stderr to a log
file, and poll the log for PASS/FAIL markers:

```python
proc = subprocess.Popen(
    [XSIM, snapshot, "--runall", "--log", log_path,
     "--testplusarg", f"UVM_TESTNAME={test_name}",
     "--testplusarg", f"UVM_VERBOSITY={verbosity}"],
    stdout=sim_log_fh, stderr=sim_log_fh,
    stdin=subprocess.DEVNULL, cwd=work_dir
)
deadline = time.monotonic() + 300
done = False
while time.monotonic() < deadline:
    time.sleep(1)
    with open(log_path, errors="replace") as fh:   # ← errors="replace" for non-UTF-8
        sim_out = fh.read()
    if "TEST PASSED" in sim_out or "TEST FAILED" in sim_out:
        done = True; break
    if proc.poll() is not None:
        break
proc.terminate(); proc.wait(timeout=10)
```

#### PASS detection

```python
passed = ("TEST PASSED" in sim_out) and ("TEST FAILED" not in sim_out)
```

**Do NOT check** `"UVM_ERROR" not in sim_out` or `"UVM_FATAL" not in sim_out`. The UVM
report summary always prints these strings (e.g., `UVM_ERROR :    0`) even on a clean run.
The `TEST PASSED` / `TEST FAILED` markers emitted by the test class already account for all
error counts.

#### Results file

Write `verification/work/xsim/uvm/results.log`:
- First line: `PASS` or `FAIL`
- Remaining lines: full simulator output

#### Log encoding

xsim may write non-UTF-8 bytes to the log. Always open with `errors="replace"`:
```python
with open(log_path, errors="replace") as fh:
    sim_out = fh.read()
```

#### Vivado path discovery

Search in order:
1. Check if `xvlog` is already in `$PATH` (from `settings64.sh` being sourced).
2. Scan common install roots (`/opt/Xilinx/Vivado`, `/tools/Xilinx/Vivado`) for the
   highest version number that contains `bin/xvlog`.

Derive UVM library paths from the Vivado root:
```python
UVM_LIB_DIR   = <vivado_root>/data/xsim/system_verilog/uvm
UVM_MACROS_INC = <vivado_root>/data/xsim/system_verilog/uvm_include
```

### 6. Testbench clock/reset (`tb_IP_NAME_uvm.sv`)

Use `` `timescale 1ns/1ps `` at the top of the testbench. Provide clock (10 ns period)
and active-low reset (8-cycle de-assertion). Set the VIF in `uvm_config_db` before
`run_test()`:

```systemverilog
`timescale 1ns/1ps
// ...
initial begin
    uvm_config_db #(virtual IP_NAME_apb_if)::set(null, "*", "IP_NAME_apb_vif", u_if);
    run_test();
end
```

### 7. Update `verification/tools/run_regression.py`

Add `--skip-uvm` flag and a dedicated UVM step:

```python
if not args.skip_uvm:
    run_step(
        "UVM simulation — IP_NAME_base_test (Vivado xsim)",
        [sys.executable,
         os.path.join(tools_dir, "uvm_IP_NAME.py"),
         "--test", "IP_NAME_base_test"],
    )
```

In `collect_results()`, **exclude** `work/xsim/uvm/` from the generic per-test sim loop
(it would be misinterpreted as 5 per-test entries). Collect it as one entry:

```python
# In the sim loop:
if sim_dir.name == "xsim" and run_dir.name == "uvm":
    continue   # collected separately below

# After the sim loop:
uvm_work = work / "xsim" / "uvm"
if uvm_work.exists():
    status = read_result_log(str(uvm_work / "results.log"))
    entries.append(("uvm/xsim/IP_NAME_base_test", status))
```

### 8. Document UVM structure in the IP README

Replace the `[TBD]` placeholder in **UVM Verification Results** with:

```markdown
| Test                  | Bus    | Simulator    | Result |
|-----------------------|--------|--------------|--------|
| IP_NAME_base_test     | APB4   | Vivado xsim  | PASS   |
```

Include Vivado version and date.

## Outputs

| Artifact | Description |
|----------|-------------|
| `verification/tasks/uvm/IP_NAME_apb_if.sv` | SV interface (BFM signal bundle) |
| `verification/tasks/uvm/IP_NAME_uvm_pkg.sv` | UVM package (includes all classes) |
| `verification/tasks/uvm/tb_IP_NAME_uvm.sv` | Testbench top |
| `verification/tasks/uvm/IP_NAME_seq_item.sv` | Sequence item |
| `verification/tasks/uvm/IP_NAME_sequencer.sv` | Sequencer |
| `verification/tasks/uvm/IP_NAME_apb_driver.sv` | APB4 driver |
| `verification/tasks/uvm/IP_NAME_apb_monitor.sv` | APB4 monitor |
| `verification/tasks/uvm/IP_NAME_env.sv` | UVM environment |
| `verification/tasks/uvm/IP_NAME_scoreboard.sv` | Shadow register scoreboard |
| `verification/tasks/uvm/IP_NAME_base_seq.sv` | Base + concrete sequences |
| `verification/tasks/uvm/IP_NAME_base_test.sv` | Base + concrete test classes |
| `verification/tools/uvm_IP_NAME.py` | Standalone Vivado xsim UVM runner |
| `verification/work/xsim/uvm/results.log` | `PASS` / `FAIL` + full sim output |

## Quality Gate

- `uvm_IP_NAME.py --test IP_NAME_base_test` exits 0 and `results.log` first line is `PASS`.
- Scoreboard reports `PASS=N FAIL=0` in the sim output.
- No `UVM_ERROR` or `UVM_FATAL` appears in the simulation output.
- `run_regression.py` includes `uvm/xsim/IP_NAME_base_test PASS` in its summary table.
- `--skip-uvm` flag skips the UVM step cleanly (for environments without Vivado).
- The UVM runner does not hang — Popen + polling is used for xsim.
