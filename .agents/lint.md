# Step 8 — `lint` Sub-Agent

## Trigger

Step 3 complete. Runs in parallel with Steps 4–7.

## Prerequisites

- `design/rtl/verilog/` and `design/rtl/vhdl/` populated with parse-clean sources.
- `verification/lint/` directory exists.
- `verification/tools/lint_IP_NAME.py` skeleton exists from Step 1.
- `IP_COMMON_PATH` is set (sourced from `setup.sh`).
- `${IP_COMMON_PATH}/verification/tools/ip_tool_base.py` exists (provides base class).
- `verilator` 5.0+ and `vhdl_ls` (or `vunit`) are on `$PATH`.

## Common Components

Import `ip_tool_base.py` from `${IP_COMMON_PATH}/verification/tools/ip_tool_base.py`.
Do not duplicate the env-var guard, results-log writer, or subprocess runner. Include
`${IP_COMMON_PATH}/rtl/verilog/` in the verilator include path so common primitives are
resolved without extra configuration in each IP.

## Responsibilities

1. Configure `verilator --lint-only` for all SV RTL sources:
   - Write flags to `verification/lint/verilator.flags` (include paths, defines, top module).
   - Target all files in `design/rtl/verilog/`.
2. Configure VHDL linting for all VHDL RTL sources:
   - Write configuration to `verification/lint/vhdl_lint.toml`.
   - Target all files in `design/rtl/vhdl/`.
3. Zero un-waived warnings or errors are acceptable in RTL source files.
   Testbench files under `verification/` may carry documented waivers.
4. For any warning that must be waived, add an entry to `verification/lint/waivers.md`:
   - File path, line number, warning code, one-line justification.
   - Corresponding suppression pragma must appear in the source file at that line.
5. Complete `verification/tools/lint_IP_NAME.py`:
   - Accepts `--lang {sv,vhdl,all}`.
   - Sources `setup.sh` environment at startup.
   - Runs verilator and/or VHDL linter based on `--lang`.
   - Writes `verification/lint/lint_results.log` containing `PASS` or `FAIL`.
   - Exits non-zero on any un-waived warning or error.
6. Coordinate with the `regression` sub-agent (Step 6): `lint_IP_NAME.py` exit code
   must be propagated correctly by `regression_IP_NAME.py`.

## Outputs

| Artifact | Description |
|----------|-------------|
| `verification/lint/verilator.flags` | Verilator lint flags and include paths |
| `verification/lint/vhdl_lint.toml` | VHDL linter configuration |
| `verification/lint/waivers.md` | Approved waivers with justifications |
| `verification/lint/lint_results.log` | `PASS` or `FAIL` |
| `verification/tools/lint_IP_NAME.py` | Completed lint runner |

## Quality Gate

- `lint_IP_NAME.py` exits 0 on clean RTL sources.
- `lint_IP_NAME.py` exits non-zero when a deliberate lint error is injected.
- `verification/lint/waivers.md` has zero entries for files under `design/rtl/`.
- `verification/lint/lint_results.log` contains `PASS`.
