# Step 11 — `cleanup` Sub-Agent

## Trigger

All prior steps complete and `verification/tools/regression_IP_NAME.py` exits 0.

## Prerequisites

- `verification/regression/report.md` shows all tests and lint checks as `PASS`.
- `synthesis/vivado/report.txt` and `synthesis/quartus/report.txt` confirm timing closure
  at 100 MHz.
- No un-resolved items in `synthesis/known_issues.md`.

## Responsibilities

1. Run `cleanup.sh` (created in Step 1) to remove all build and simulation artifacts:
   - `verification/work/` contents.
   - `firmware/build/`, `firmware/obj/`, `firmware/lib/`.
   - Synthesis intermediate files in `synthesis/*/`.
   - Vivado journal and log files (`.jou`, `.log`, `.pb`).
   - Quartus `db/` and `incremental_db/` directories.
2. Update `.gitignore` (at the `IP_NAME/` root) to exclude:
   - All tool-generated scratch files and build artifacts.
   - Waveform databases (`.vcd`, `.fst`, `.wdb`).
   - Simulator working directories.
   - `firmware/build/`, `firmware/obj/`, `firmware/lib/`.
   - `synthesis/*/` intermediate files.
   - Source files and final report files must **never** be excluded.
3. Verify `cleanup.sh` removes all build artifacts without touching:
   - Any source file under `design/`, `verification/testbench/`, `verification/tests/`,
     `verification/tasks/`, `firmware/src/`, `firmware/include/`, `firmware/examples/`.
   - Any report file under `verification/regression/`, `synthesis/`, `doc/`.
4. Run a final full regression from a clean state:
   - `bash cleanup.sh && python3 verification/tools/regression_IP_NAME.py`
   - Confirm `verification/regression/report.md` regenerates and shows all `PASS`.
5. Update `doc/spec.md` with final content:
   - Complete register map (linked to `doc/IP_NAME_regs.html`).
   - Resource utilization numbers from synthesis reports.
   - Simulator and synthesis tool versions used (from `setup.sh` or tool `--version`).
   - Known limitations updated from `synthesis/known_issues.md`.
   - Planned improvements (if any).
6. Create the release tag:
   ```
   git tag -a v1.0.0 -m "Initial verified release of IP_NAME"
   ```

## Outputs

| Artifact | Description |
|----------|-------------|
| Updated `.gitignore` | Excludes all tool scratch and build artifacts |
| Updated `doc/spec.md` | Final specification with register map, utilization, tool versions |
| Git tag `v1.0.0` | Marks the verified, clean initial release |

## Quality Gate

- `bash cleanup.sh && python3 verification/tools/regression_IP_NAME.py` exits 0.
- `git status` shows no untracked tool-generated files after a full run + cleanup.
- `doc/spec.md` contains actual utilization numbers (no "TBD" remaining in final fields).
- Git tag `v1.0.0` exists and points to a clean HEAD.
