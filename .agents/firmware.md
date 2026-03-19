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
  - RISC-V 32-bit:  `riscv-none-elf-gcc` (xPack, at `/opt/xpack-riscv-none-elf-gcc-*/bin`)

## Cross-Compilation Requirement (mandatory)

**RULE — Firmware is NEVER built with the host (x86-64) GCC.** The driver targets embedded
bare-metal SoC platforms. All compilation and syntax-checking must use cross-compilers.

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
6. Write CMake toolchain files:
   - `firmware/cmake/arm-cortex-m33.cmake` — sets `CMAKE_C_COMPILER arm-none-eabi-gcc`,
     `CMAKE_C_FLAGS_INIT "-mcpu=cortex-m33 -mthumb -mfloat-abi=soft"`,
     `CMAKE_SYSTEM_NAME Generic`.
   - `firmware/cmake/riscv32.cmake` — sets `CMAKE_C_COMPILER riscv-none-elf-gcc`,
     `CMAKE_C_FLAGS_INIT "-march=rv32imac_zicsr -mabi=ilp32"`,
     `CMAKE_SYSTEM_NAME Generic`.
   - Both toolchain files set `CMAKE_FIND_ROOT_PATH_MODE_*` to prevent host library
     contamination, and `--specs=nano.specs --specs=nosys.specs` in linker flags.
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
| `firmware/cmake/arm-cortex-m33.cmake` | CMake toolchain file for ARM Cortex-M33 |
| `firmware/cmake/riscv32.cmake` | CMake toolchain file for RISC-V 32-bit (xPack) |
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
