# Step 9 — `firmware` Sub-Agent

## Trigger

Step 2 complete (`firmware/include/IP_NAME_regs.h` exists). Runs in parallel with Steps 3–8.

## Prerequisites

- `firmware/include/IP_NAME_regs.h` exists and passes `gcc -fsyntax-only`.
- `firmware/include/`, `firmware/src/`, `firmware/examples/`, `firmware/cmake/` directories exist.
- `IP_COMMON_PATH` is set (sourced from `setup.sh`).
- `gcc` 11.0+ and `cmake` 3.20+ are on `$PATH`.

## Common Components

**Check `${IP_COMMON_PATH}/firmware/` before writing any new firmware infrastructure.**

- `${IP_COMMON_PATH}/firmware/include/platform.h` — the canonical platform MMIO stub.
  The IP-specific `firmware/include/platform.h` must be a symlink or a copy of this
  file; do not write a new one from scratch. Users replace only the common version when
  porting to a new target.
- `${IP_COMMON_PATH}/firmware/cmake/` — shared CMake modules. The IP's `firmware/cmake/`
  directory includes these modules; do not duplicate CMake logic.
- If new shared firmware utilities (e.g., common error codes, ring-buffer helpers) are
  developed, place them in `${IP_COMMON_PATH}/firmware/` rather than in the IP-specific
  `firmware/src/` so every IP can benefit.

## Responsibilities

1. Write the public API header `firmware/include/IP_NAME.h`:
   - Declares all public driver functions and types.
   - Does **not** expose driver internals.
   - Includes `IP_NAME_regs.h` for register definitions.
2. Write `firmware/include/platform.h`:
   - Isolates platform-specific memory-mapped I/O in a single stub file.
   - Defines `MMIO_READ32(addr)` and `MMIO_WRITE32(addr, val)` macros backed by
     `volatile uint32_t *` casts.
   - This is the only file a user needs to replace when porting to a new target.
3. Write the driver implementation `firmware/src/IP_NAME.c`:
   - Uses **only** `firmware/include/IP_NAME_regs.h` for register definitions.
   - No hardcoded addresses or magic numbers.
4. Driver API must include at minimum:
   - `IP_NAME_init(uintptr_t base_addr)` — initialize peripheral, apply reset defaults.
   - `IP_NAME_write_reg(uintptr_t base, uint32_t offset, uint32_t value)` — raw write.
   - `IP_NAME_read_reg(uintptr_t base, uint32_t offset, uint32_t *value)` — raw read.
   - Higher-level functions for each distinct hardware capability.
5. All public functions carry Doxygen-style comment blocks: `@brief`, `@param`, `@return`,
   `@note` where applicable.
6. Driver is pure C99 — no compiler extensions, no OS or RTOS dependencies.
7. Write `firmware/build.sh`:
   - Runs `cmake` out-of-source into `firmware/build/`.
   - Builds static library `firmware/lib/libIP_NAME.a`.
   - Must be callable without arguments after `setup.sh` is sourced.
8. Write `firmware/cmake/IP_NAME.cmake` — CMake targets for the library and examples.
9. Write `firmware/examples/main.c`:
   - Self-contained example demonstrating every public API function.
   - Compiles cleanly against `libIP_NAME.a`.

## Outputs

| Artifact | Description |
|----------|-------------|
| `firmware/include/IP_NAME.h` | Public API header |
| `firmware/include/platform.h` | Platform MMIO stub (user replaces for target) |
| `firmware/src/IP_NAME.c` | Driver implementation |
| `firmware/build.sh` | CMake + make build script |
| `firmware/cmake/IP_NAME.cmake` | CMake build targets |
| `firmware/examples/main.c` | Usage example |

## Quality Gate

- `gcc -std=c99 -Wall -Wextra -Werror -fsyntax-only firmware/include/IP_NAME.h` passes.
- `firmware/build.sh` builds `firmware/lib/libIP_NAME.a` without warnings.
- `cleanup.sh` removes `firmware/build/`, `firmware/obj/`, `firmware/lib/` cleanly.
- No `#include` of anything outside `firmware/include/` and generated headers in driver sources.
