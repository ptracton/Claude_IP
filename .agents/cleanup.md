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
   - Synthesis intermediate files in `synthesis/*/` via two calls:
     - `python3 synthesis/run_vendor_synth.py --clean` — Vivado, Quartus outputs.
     - `bash synthesis/clean.sh` — Design Compiler outputs (`reports/`, `netlists/`,
       `ARCH/`, `ENTI/`, `PACK/`, `dc_saed90_run.log`, `dc_saed32_run.log`, etc.).
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
5. Finalize `README.md`:
   - Confirm every `[TBD]` placeholder has been replaced by its owning sub-agent.
     Run `grep -n "\[TBD\]" README.md` — must return zero results.
   - Verify the Overview section accurately describes the completed IP.
   - Confirm all result tables show actual numbers and dates, not placeholders.
   - Check every internal link (e.g., `doc/IP_NAME_regs.html`, `doc/uvm_arch.md`) resolves.
6. Update `doc/spec.md` with final content:
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
| Finalized `README.md` | No `[TBD]` remaining; all sections populated with real results |
| Updated `.gitignore` | Excludes all tool scratch and build artifacts |
| Updated `doc/spec.md` | Final specification with register map, utilization, tool versions |
| Git tag `v1.0.0` | Marks the verified, clean initial release |

## Quality Gate

- `bash cleanup.sh && python3 verification/tools/regression_IP_NAME.py` exits 0.
- `git status` shows no untracked tool-generated files after a full run + cleanup.
- `grep -n "\[TBD\]" README.md` returns zero results.
- All result tables in `README.md` contain real numbers and dates.
- `doc/spec.md` contains actual utilization numbers (no "TBD" remaining in final fields).
- Git tag `v1.0.0` exists and points to a clean HEAD.
