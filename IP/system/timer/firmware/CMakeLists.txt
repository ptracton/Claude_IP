cmake_minimum_required(VERSION 3.20)

# ---------------------------------------------------------------------------
# Toolchain must be set before project() via -DCMAKE_TOOLCHAIN_FILE.
# Supported toolchain files (in cmake/):
#   cmake/arm-cortex-m33.cmake
#   cmake/riscv32.cmake
# ---------------------------------------------------------------------------
project(timer_firmware C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

# ---------------------------------------------------------------------------
# Derive a short architecture tag from the toolchain for output naming.
# Falls back to the processor name reported by CMake.
# ---------------------------------------------------------------------------
if(CMAKE_C_COMPILER MATCHES "arm-none-eabi")
    set(TIMER_ARCH_TAG "arm-cortex-m33")
elseif(CMAKE_C_COMPILER MATCHES "riscv")
    set(TIMER_ARCH_TAG "riscv32")
else()
    message(FATAL_ERROR
        "No recognised cross-compiler configured.\n"
        "Run cmake with a supported toolchain file:\n"
        "  -DCMAKE_TOOLCHAIN_FILE=cmake/arm-cortex-m33.cmake\n"
        "  -DCMAKE_TOOLCHAIN_FILE=cmake/riscv32.cmake\n"
    )
endif()

message(STATUS "Timer firmware target architecture: ${TIMER_ARCH_TAG}")

# ---------------------------------------------------------------------------
# Include paths
#   1. IP-specific headers (timer.h, timer_regs.h)
#   2. Common firmware headers (platform.h) via IP_COMMON_PATH env var
# ---------------------------------------------------------------------------
include_directories(
    include
    $ENV{IP_COMMON_PATH}/firmware/include
)

# ---------------------------------------------------------------------------
# Compiler warning flags (applied to all targets)
# ---------------------------------------------------------------------------
set(TIMER_WARN_FLAGS -Wall -Wextra -Werror)

# ---------------------------------------------------------------------------
# Static library: libtimer.a
# Output goes to firmware/lib/<arch>/libtimer.a
# ---------------------------------------------------------------------------
add_library(timer STATIC src/timer.c)

target_include_directories(timer PUBLIC
    include
    $ENV{IP_COMMON_PATH}/firmware/include
)

target_compile_options(timer PRIVATE ${TIMER_WARN_FLAGS})

set_target_properties(timer PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/lib/${TIMER_ARCH_TAG}"
)

# ---------------------------------------------------------------------------
# Example executable
# Disabled by default for cross-compilation: linking a bare-metal executable
# without a target-specific startup file and linker script produces spurious
# newlib syscall warnings and is not a meaningful build artifact.
# Enable explicitly with -DTIMER_BUILD_EXAMPLE=ON only when a linker script
# and startup file are provided for the target board.
# ---------------------------------------------------------------------------
option(TIMER_BUILD_EXAMPLE "Build the timer_example bare-metal binary" OFF)

if(TIMER_BUILD_EXAMPLE)
    add_executable(timer_example examples/timer_example.c)

    target_include_directories(timer_example PRIVATE
        include
        $ENV{IP_COMMON_PATH}/firmware/include
    )

    target_link_libraries(timer_example PRIVATE timer)

    target_compile_options(timer_example PRIVATE ${TIMER_WARN_FLAGS})

    set_target_properties(timer_example PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/lib/${TIMER_ARCH_TAG}"
        OUTPUT_NAME "timer_example-${TIMER_ARCH_TAG}"
    )
endif()
