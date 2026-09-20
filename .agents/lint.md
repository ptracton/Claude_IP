# Step 8 — `lint` Sub-Agent

## Trigger

Step 3 complete. Runs in parallel with Steps 4–7.

## Prerequisites

- `design/rtl/verilog/` and `design/rtl/vhdl/` populated with parse-clean sources.
- `verification/lint/` directory exists.
- `verification/tools/lint_IP_NAME.py` skeleton exists from Step 1.
- `IP_COMMON_PATH` is set (sourced from `setup.sh`).
- `${IP_COMMON_PATH}/verification/tools/ip_tool_base.py` exists (provides base class).

**Standard hosts** (not csun.edu):
- `verilator` 5.0+ and `vhdl_ls` (or `vunit`) are on `$PATH`.

**On *.csun.edu** (Verilator and GHDL are NOT installed):
- `verification/lint/spyglass/` directory exists with one static `.prj` file
  per SV top-level variant.
- `spyglass_vc` is on `$PATH` (Synopsys SpyGlass, via VC Static compat layer).
- There is no VHDL lint on csun.edu — see the SpyGlass subsection below.

## Machine-Specific Environment: *.csun.edu

When running on `*.csun.edu`, Verilator and GHDL are **not installed** — do
not attempt to invoke them there (mirrors how `synthesis.md`/`run_vendor_synth.py`
skip Vivado/Quartus/Yosys on csun.edu in favor of Design Compiler).
`lint_IP_NAME.py` must detect this environment the same way `run_vendor_synth.py`
does:

```python
import socket
ON_CSUN = socket.getfqdn().endswith(".csun.edu")
```

When `ON_CSUN` is `True`:
- SV lint runs via SpyGlass (`spyglass_vc`) instead of Verilator.
- VHDL lint is **skipped**, not attempted and not silently marked PASS as a
  false positive — log it explicitly as `SKIPPED` with the reason (see
  SpyGlass subsection) and do not count it as a failure. GHDL isn't
  installed on csun.edu, and the installed SpyGlass has no supported way to
  select VHDL-2008 semantics, which this repo's VHDL RTL requires.

## Common Components

Import `ip_tool_base.py` from `${IP_COMMON_PATH}/verification/tools/ip_tool_base.py`.
Do not duplicate the env-var guard, results-log writer, or subprocess runner. Include
`${IP_COMMON_PATH}/rtl/verilog/` in the verilator include path so common primitives are
resolved without extra configuration in each IP.

## Responsibilities

1. Configure `verilator --lint-only` for all SV RTL sources (standard hosts):
   - Write flags to `verification/lint/verilator.flags` (include paths, defines, top module).
   - Target all files in `design/rtl/verilog/`.
2. Configure VHDL linting for all VHDL RTL sources (standard hosts):
   - Write configuration to `verification/lint/vhdl_lint.toml`.
   - Target all files in `design/rtl/vhdl/`.
3. Zero un-waived warnings or errors are acceptable in RTL source files.
   Testbench files under `verification/` may carry documented waivers.
   A properly justified, pragma'd RTL waiver is acceptable when a tool flags
   a real but low-risk finding (e.g. a documented style deviation) — "zero
   un-waived" is the bar, not "zero waivers ever." See `waivers.md` for the
   required format.
4. For any warning that must be waived, add an entry to `verification/lint/waivers.md`:
   - File path, line number, tool + warning code, one-line justification.
   - Corresponding suppression pragma must appear in the source file at that line.
5. Complete `verification/tools/lint_IP_NAME.py`:
   - Accepts `--lang {sv,vhdl,all}`.
   - Sources `setup.sh` environment at startup.
   - Detects `ON_CSUN`; runs Verilator/VHDL linter on standard hosts, SpyGlass
     SV-only on csun.edu (see subsection below).
   - Writes `verification/lint/lint_results.log` containing `PASS` or `FAIL`.
   - Exits non-zero on any un-waived warning or error. A `SKIPPED` language
     (VHDL on csun.edu) does not count as a failure.
6. Coordinate with the `regression` sub-agent (Step 7): `lint_IP_NAME.py` exit code
   must be propagated correctly by `regression_IP_NAME.py`.

### SpyGlass (csun.edu only, SV lint)

SpyGlass's classic project-file interface (`spyglass_vc -project X.prj -goal
lint/lint_rtl -batch -app lint`) is what's available on csun.edu — not the
native `spyglass`/`sg_shell` binaries also present under
`/opt/synopsys/vc_static/*/SG_COMPAT/`, which have their own independent
parser with no VHDL-2008 support at all and are not worth using here either.

- One static `.prj` file per SV top-level variant under
  `verification/lint/spyglass/<top>.prj`, using **relative** `read_file`
  paths (no `search_path` equivalent exists for SpyGlass's `read_file`) —
  `spyglass_vc` must be invoked with `verification/lint/spyglass/` as `cwd`
  for these to resolve. Mirrors the per-variant static-script convention
  already used for `synthesis/yosys/*.ys`.
- Goal: `lint/lint_rtl`. Project options: `set_option enableSV yes`,
  `set_option top <variant>`.
- **`spyglass_vc`'s own exit code is not a reliable pass/fail signal** — do
  not gate on it. Parse
  `vcst_rtdb/spyglass/<top>/<top>/lint/lint_rtl/spyglass_reports/moresimple.rpt`
  instead, which lists every violation with its Rule/Severity/Message.
- Filter out translator/environment noise before deciding pass/fail — these
  appear on *every* run regardless of design content and are not RTL
  findings: `COM_OPT009`/`COM_OPT010` (`search_path`/`link_library` not set —
  expected, since full paths are given directly and no gate library is
  used) and any `PrjToTclSummary` row whose message contains "Skipped
  option" (the classic-SpyGlass-compat translator always reports skipping
  `template_info`, `overloadrules`, and `template`, unconditionally).
- To waive a genuine finding at a specific line, use SpyGlass's own inline
  pragma (verified working):
  ```systemverilog
  //spyglass disable_block <RuleName>
  ... code ...
  //spyglass enable_block <RuleName>
  ```
  Record it in `waivers.md` exactly like a Verilator/GHDL waiver.
- **VHDL has no SpyGlass path here.** The underlying VCS-based analyzer used
  by `spyglass_vc` *can* parse VHDL-2008 (`analyze -format vhdl -vcs
  {-vhdl08} {files}` works when called directly), but the classic
  `.prj`/`read_file -type vhdl` project-file interface has no supported way
  to pass that flag through (confirmed by testing `set_option vhdl2008`,
  `enableVHDL2008`, `read_file -type vhdl2008`, `-vhdl_opts`, and the
  separate native `spyglass`/`sg_shell` binaries — none work; see
  `.agents/reference_spyglass_lint.md` for the full investigation). Do not
  attempt to force this via undocumented internal-file patching in
  production scripts — it's fragile across tool versions. Log VHDL as
  `SKIPPED` on csun.edu instead.
7. Update `README.md` — replace the `[TBD]` placeholder in **Lint Results** with:
   - Overall result (`PASS` / `FAIL` / `SKIPPED`) for each language:

     ```markdown
     | Language | Tool       | Warnings | Waivers | Result  |
     |----------|------------|----------|---------|---------|
     | SV       | Verilator  | 0        | 0       | PASS    |
     | VHDL     | vhdl_ls    | 0        | 0       | PASS    |
     ```

     On csun.edu, use `SpyGlass` as the SV tool and mark VHDL `SKIPPED` with
     a one-line reason instead of a fabricated Warnings/Waivers row.
   - If waivers exist, list them with their justifications (testbench
     waivers are unrestricted; RTL waivers must meet the bar in item 3 above).
   - Tool versions and the date results were generated.

## Outputs

**On standard hosts:**

| Artifact | Description |
|----------|-------------|
| `verification/lint/verilator.flags` | Verilator lint flags and include paths |
| `verification/lint/vhdl_lint.toml` | VHDL linter configuration |
| `verification/lint/waivers.md` | Approved waivers with justifications |
| `verification/lint/lint_results.log` | `PASS` or `FAIL` |
| `verification/tools/lint_IP_NAME.py` | Completed lint runner (host-aware; SpyGlass on csun.edu) |

**On *.csun.edu:**

| Artifact | Description |
|----------|-------------|
| `verification/lint/spyglass/<top>.prj` | One static SpyGlass project file per SV top-level variant |
| `verification/lint/waivers.md` | Approved waivers, including any `//spyglass disable_block` entries |
| `verification/lint/lint_results.log` | `PASS` or `FAIL` (VHDL logged `SKIPPED`, not counted as failure) |
| `verification/tools/lint_IP_NAME.py` | Completed lint runner (host-aware; SpyGlass on csun.edu) |

## Quality Gate

**Standard hosts:**
- `lint_IP_NAME.py` exits 0 on clean RTL sources.
- `lint_IP_NAME.py` exits non-zero when a deliberate lint error is injected.
- `verification/lint/lint_results.log` contains `PASS`.

**On *.csun.edu:**
- `lint_IP_NAME.py` exits 0 for SV via SpyGlass, with VHDL logged `SKIPPED`
  (not a failure).
- Pass/fail comes from `moresimple.rpt`, filtered for known translator
  noise — not from `spyglass_vc`'s own exit code (unreliable).

**All hosts:**
- Every RTL waiver in `verification/lint/waivers.md` has a corresponding
  suppression pragma at that exact line in the source, a one-line
  justification, and the tool + warning code that triggered it.
