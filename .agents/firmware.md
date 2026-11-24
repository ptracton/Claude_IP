# Step 9 — `firmware` Sub-Agent

## Trigger

Step 2 complete (`firmware/include/IP_NAME_regs.h` exists). Runs in parallel with Steps 3–8.

## Prerequisites

- `firmware/include/IP_NAME_regs.h` exists and passes cross-compiler syntax check.
- `firmware/include/`, `firmware/src/`, `firmware/examples/`, `firmware/cmake/` directories exist.
- `IP_COMMON_PATH` is set (sourced from `setup.sh`).
- `cmake` 3.20+ is on `$PATH`.
- Cross-compilers are on `$PATH` (added by `setup.sh` at the **end** of the file):
  - ARM Cortex-M33: `arm-none-eabi-gcc`
    (standard hosts: system-installed via apt/brew; `*.csun.edu`: xPack at
    `/tmp/pet43490/CrossCompilers/arm-gnu-toolchain-*-x86_64-arm-none-eabi/bin`)
  - RISC-V 32-bit:  `riscv-none-elf-gcc`
    (xPack; standard hosts: `/opt/xpack-riscv-none-elf-gcc-*/bin`; `*.csun.edu`:
    `/tmp/pet43490/CrossCompilers/xpack-riscv-none-elf-gcc-*/bin`)
  - **2026-11-23: `/tmp/pet43490/CrossCompilers` no longer exists on csun.edu** (removed by the
    10-day `/tmp` cleanup). Cross builds there SKIP until the toolchains are reinstalled —
    preferably outside `/tmp`, then fix the `CROSS_COMPILERS_PATH` block in every `setup.sh`.
    Reinstalling downloads from Arm / xPack: ask the user first.

## Cross-Compilation Requirement (mandatory)

**RULE — Firmware libraries are NEVER built with the host (x86-64) GCC.** The driver targets
embedded bare-metal SoC platforms. Every shipped artifact (`libIP_NAME.a`, example binary) and
the syntax check must use the cross-compilers.

**Exception — host unit tests (user decision 2026-11-23, sram Step 9).** A host-gcc test program
under `firmware/test/` may compile the driver sources together with a model of the hardware
(fault-injecting memory, fake side band, fake register file) and run on the build host. Its
binaries stay in `firmware/build/host*/` and are never shipped. It is how firmware is verified on
hosts with no cross compiler (csun.edu at the moment).

Supported targets:

| Target         | Compiler           | Flags                               | Library output                        |
|----------------|--------------------|-------------------------------------|---------------------------------------|
| ARM Cortex-M33 | `arm-none-eabi-gcc` | `-mcpu=cortex-m33 -mthumb -mfloat-abi=soft` | `firmware/lib/arm-cortex-m33/libIP_NAME.a` |
| RISC-V 32-bit  | `riscv-none-elf-gcc` (xPack) | `-march=rv32imac_zicsr -mabi=ilp32` | `firmware/lib/riscv32/libIP_NAME.a` |

## Common Components

**Check `${IP_COMMON_PATH}/firmware/` before writing any new firmware infrastructure.**

- `${IP_COMMON_PATH}/firmware/include/platform.h` — the canonical platform MMIO stub.
  The IP-specific `firmware/include/platform.h` must be a symlink or a copy of this
  file; do not write a new one from scratch.
- `${IP_COMMON_PATH}/firmware/cmake/` — shared CMake modules. Do not duplicate CMake logic.

## Responsibilities

1. Write the public API header `firmware/include/IP_NAME.h`:
   - Declares all public driver functions and types.
   - Does **not** expose driver internals.
   - Includes `IP_NAME_regs.h` for register definitions.
2. Write `firmware/include/platform.h`:
   - Defines `MMIO_READ32(addr)` and `MMIO_WRITE32(addr, val)` macros backed by
     `volatile uint32_t *` casts.
   - This is the only file a user replaces when porting to a new target.
3. Write the driver implementation `firmware/src/IP_NAME.c`:
   - Uses **only** `firmware/include/IP_NAME_regs.h` for register definitions.
   - No hardcoded addresses or magic numbers.
   - Pure C99 — no compiler extensions, no OS or RTOS dependencies.
4. Driver API must include at minimum:
   - `IP_NAME_init(uintptr_t base_addr)` — initialize peripheral to known state.
   - `IP_NAME_write_reg(uintptr_t base, uint32_t offset, uint32_t value)` — raw write.
   - `IP_NAME_read_reg(uintptr_t base, uint32_t offset)` — raw read.
   - Higher-level functions for each distinct hardware capability.
5. All public functions carry Doxygen-style comment blocks (`@brief`, `@param`, `@return`).
6. CMake toolchain files — **use shared files from common, do not create per-IP copies**:
   - Toolchain files already exist at `${IP_COMMON_PATH}/firmware/cmake/`:
     - `arm-cortex-m33.cmake` — ARM Cortex-M33 (`arm-none-eabi-gcc`, `-mcpu=cortex-m33 -mthumb -mfloat-abi=soft`)
     - `riscv32.cmake` — RISC-V 32-bit (`riscv-none-elf-gcc`, `-march=rv32imac_zicsr -mabi=ilp32`)
   - Both files set `CMAKE_SYSTEM_NAME Generic`, all `CMAKE_FIND_ROOT_PATH_MODE_*` to
     prevent host library contamination, and `--specs=nano.specs --specs=nosys.specs`.
   - Pass them to `build.sh` via `${IP_COMMON}/firmware/cmake/<file>.cmake` — do NOT
     place copies in `firmware/cmake/`. The IP-specific `firmware/cmake/` directory is
     not needed and must not be created.
   - In `firmware/build.sh`, resolve the common path as:
     `IP_COMMON="${IP_COMMON_PATH:-${CLAUDE_IP_NAME_PATH}/../../common}"`
   - Pass the full absolute path to cmake: `-DCMAKE_TOOLCHAIN_FILE="${IP_COMMON}/firmware/cmake/arm-cortex-m33.cmake"`
7. Write `firmware/CMakeLists.txt`:
   - Requires a toolchain file via `-DCMAKE_TOOLCHAIN_FILE` — **reject builds without
     a recognised cross-compiler** with `message(FATAL_ERROR ...)`.
   - Detects the architecture tag from `CMAKE_C_COMPILER` (`arm-none-eabi` → `arm-cortex-m33`,
     `riscv` → `riscv32`).
   - Outputs `libIP_NAME.a` to `firmware/lib/<arch>/`.
   - Example executable (`TIMER_BUILD_EXAMPLE`) defaults **OFF** — linking a bare-metal
     executable without a startup file generates spurious newlib syscall warnings.
8. Write `firmware/build.sh`:
   - Accepts optional positional arguments: `arm`, `riscv`, or nothing (builds both).
   - Accepts a leading `clean` argument: `bash build.sh clean`, `bash build.sh clean arm`,
     `bash build.sh clean riscv` — removes `build/<arch>/` and `lib/<arch>/`.
   - Skips a target gracefully (with `WARNING:` message) if the cross-compiler is not on PATH.
   - Uses `--fresh` flag on `cmake` to guarantee a clean configure.
   - Reports library paths at the end.
9. Write `firmware/examples/IP_NAME_example.c`:
   - Self-contained example demonstrating every public API function.
   - Compiles cleanly against `libIP_NAME.a`.
10. Update `README.md` — **Firmware** section:
    - **Build Targets**: table of cross-compilation targets, toolchains, flags, output paths.
    - **Code Size**: run `riscv-none-elf-size` / `arm-none-eabi-size` and report `.text`,
      `.data`, `.bss` bytes per target.
    - **API Summary**: table of every public function with signature and `@brief` description.

## Outputs

| Artifact | Description |
|----------|-------------|
| `firmware/include/IP_NAME.h` | Public API header |
| `firmware/include/platform.h` | Platform MMIO stub (user replaces for target) |
| `firmware/src/IP_NAME.c` | Driver implementation (C99) |
| *(toolchain files live in `${IP_COMMON_PATH}/firmware/cmake/`)* | Shared; do not create per-IP copies |
| `firmware/CMakeLists.txt` | CMake build definition (cross-compile only) |
| `firmware/build.sh` | Build script with `arm`/`riscv`/`clean` options |
| `firmware/examples/IP_NAME_example.c` | Usage example |
| `firmware/lib/arm-cortex-m33/libIP_NAME.a` | ARM Cortex-M33 static library |
| `firmware/lib/riscv32/libIP_NAME.a` | RISC-V 32-bit static library |

## Quality Gate

- `arm-none-eabi-gcc -fsyntax-only -std=c99 firmware/include/IP_NAME.h` passes.
- `riscv-none-elf-gcc -fsyntax-only -std=c99 firmware/include/IP_NAME.h` passes.
- `bash firmware/build.sh arm` builds `firmware/lib/arm-cortex-m33/libIP_NAME.a` without warnings.
- `bash firmware/build.sh riscv` builds `firmware/lib/riscv32/libIP_NAME.a` without warnings.
- `bash firmware/build.sh clean` removes both `build/` subdirectories and `lib/` subdirectories.
- No `#include` of anything outside `firmware/include/` and generated headers in driver sources.
- **No host GCC output** — any `.a` file compiled with `x86-64-linux-gnu-gcc` or plain `gcc`
  is a quality gate failure.

## Register-less IPs (memory-like, e.g. sram)

An IP without a register block (no RDL, no `IP_NAME_regs.h`; sram decision D2) has no register
driver. Step 9 then ships, following `IP/system/sram/firmware/`:

- **Memory tests** on a base address and size: address bus, walking 1s/0s, address-in-address,
  March C- (background as an argument; run 0 and 0x55555555), byte lanes, and a `*_test_all`
  selector. First failure reported as `{addr, expected, actual}`.
- **Side-band helpers** through integrator **hooks**: a struct of callbacks (`set_pwr_req`,
  `get_pwr_ack`, `pulse_clr`, `get_status`, ...) plus `ctx`. The helpers only sequence (request,
  poll with a timeout, refuse illegal states); they never assume an address map. Required hooks
  are checked in `*_init`; optional ones may be NULL -> `*_ERR_NOHOOK`.
- Read the RTL for the sequencing rules before writing them (sram: the clear engine skips
  DS/SD domains; `ecc_inj_i` re-arms every cycle it is high, so its hook is a pulse; `busy_o`
  covers a pending clear/BIST from the next cycle, so "done" = busy low).
- Memory accesses need 8/16/32-bit accessors; `platform.h` has only `MMIO_*32`, so such an IP
  uses its own `src/<ip>_access.h` (overridable macros) instead of copying `platform.h`. Do not
  widen the common `platform.h` for one IP.
- The example shows one *assumed* wiring of the side band (e.g. a system-control register),
  clearly marked as an example.

## Runner and verification (from sram Step 9)

`verification/tools/fw_<ip>.py` (build it in Step 9; never report results from scratch scripts):

| Step | What |
|---|---|
| host | host gcc `-std=c99 -Wall -Wextra -Werror -pedantic` build of `firmware/test/` + sources, run, one row per check; ASan/UBSan when the host can link them (csun gcc 11.5 cannot) |
| mutants | a list of (file, original, mutated) edits to `src/`; the host test must fail for each (KILLED). A survivor means a missing fault or check; an equivalent mutant is replaced, not ignored |
| compile | sources + example compiled with the real accessors (no test model), compile only |
| cross | `firmware/build.sh arm` / `riscv`; SKIP (not FAIL) when the compiler is missing; record `<prefix>-size -t` totals for the README Code Size table |

Results go to `verification/firmware/fw_results.log` (first line PASS/FAIL, then
`PASS|FAIL|SKIP <step>/<check>` rows), and the regression runner collects them as step
`firmware`. Lesson from sram: the first mutation run left 9/22 mutants alive — a fault model
needs, per test step, a fault that only that step can see (pattern-sensitive bits for walking
0s, decoder multi-access for each address-bus phase, falling-edge coupling for March C- M5,
last-word and halfword lane faults), and "blind" checks that show what each test cannot see.
