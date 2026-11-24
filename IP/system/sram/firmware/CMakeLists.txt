cmake_minimum_required(VERSION 3.20)

# ---------------------------------------------------------------------------
# sram firmware: memory tests + side-band helpers (no register driver; D2).
# Toolchain must be set before project() via -DCMAKE_TOOLCHAIN_FILE.
# Supported toolchain files (in ${IP_COMMON_PATH}/firmware/cmake/):
#   arm-cortex-m33.cmake
#   riscv32.cmake
# Host unit tests (firmware/test/) are built by verification/tools/fw_sram.py,
# not here.
# ---------------------------------------------------------------------------
project(sram_firmware C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

# ---------------------------------------------------------------------------
# Derive a short architecture tag from the toolchain for output naming.
# ---------------------------------------------------------------------------
if(CMAKE_C_COMPILER MATCHES "arm-none-eabi")
    set(SRAM_ARCH_TAG "arm-cortex-m33")
elseif(CMAKE_C_COMPILER MATCHES "riscv")
    set(SRAM_ARCH_TAG "riscv32")
else()
    message(FATAL_ERROR
        "No recognised cross-compiler configured.\n"
        "Run cmake with a supported toolchain file:\n"
        "  -DCMAKE_TOOLCHAIN_FILE=<IP_COMMON_PATH>/firmware/cmake/arm-cortex-m33.cmake\n"
        "  -DCMAKE_TOOLCHAIN_FILE=<IP_COMMON_PATH>/firmware/cmake/riscv32.cmake\n"
    )
endif()

message(STATUS "sram firmware target architecture: ${SRAM_ARCH_TAG}")

# ---------------------------------------------------------------------------
# Compiler warning flags (applied to all targets)
# ---------------------------------------------------------------------------
set(SRAM_WARN_FLAGS -Wall -Wextra -Werror -pedantic)

# ---------------------------------------------------------------------------
# Static library: libsram.a -> firmware/lib/<arch>/libsram.a
# The sources need only include/ (sram.h) and src/ (sram_access.h); nothing
# from IP/common (memory accesses are 8/16/32-bit, see sram_access.h).
# ---------------------------------------------------------------------------
add_library(sram STATIC
    src/sram_memtest.c
    src/sram_sideband.c
)

target_include_directories(sram PUBLIC include PRIVATE src)

target_compile_options(sram PRIVATE ${SRAM_WARN_FLAGS})

set_target_properties(sram PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/lib/${SRAM_ARCH_TAG}"
)

# ---------------------------------------------------------------------------
# Example executable
# Disabled by default for cross-compilation: linking a bare-metal executable
# without a target-specific startup file and linker script is not a
# meaningful build artifact. Enable with -DSRAM_BUILD_EXAMPLE=ON when a
# linker script and startup file are provided for the target board.
# ---------------------------------------------------------------------------
option(SRAM_BUILD_EXAMPLE "Build the sram_example bare-metal binary" OFF)

if(SRAM_BUILD_EXAMPLE)
    add_executable(sram_example examples/sram_example.c)
    target_link_libraries(sram_example PRIVATE sram)
    target_compile_options(sram_example PRIVATE ${SRAM_WARN_FLAGS})
    set_target_properties(sram_example PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/lib/${SRAM_ARCH_TAG}"
        OUTPUT_NAME "sram_example-${SRAM_ARCH_TAG}"
    )
endif()
