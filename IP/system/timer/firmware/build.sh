#!/usr/bin/env bash
# build.sh — Cross-compile the timer firmware driver for all supported targets.
#
# Targets:
#   ARM Cortex-M33  (arm-none-eabi-gcc)
#   RISC-V 32-bit   (riscv64-unknown-elf-gcc with rv32imac_zicsr/ilp32)
#
# Usage:
#   bash firmware/build.sh                   # build all targets
#   bash firmware/build.sh arm               # ARM Cortex-M33 only
#   bash firmware/build.sh riscv             # RISC-V only
#   bash firmware/build.sh clean             # remove all build and lib output
#   bash firmware/build.sh clean arm         # remove ARM build/lib output only
#   bash firmware/build.sh clean riscv       # remove RISC-V build/lib output only
#
# Output:
#   firmware/lib/arm-cortex-m33/libtimer.a
#   firmware/lib/riscv32/libtimer.a
#
# Prerequisites:
#   - CLAUDE_TIMER_PATH must be set (run: source timer/setup.sh)
#   - IP_COMMON_PATH must be set to the common firmware include root
#   - arm-none-eabi-gcc must be on PATH for ARM builds
#   - riscv-none-elf-gcc must be on PATH for RISC-V builds

set -e

# ---------------------------------------------------------------------------
# Environment checks
# ---------------------------------------------------------------------------
if [ -z "${CLAUDE_TIMER_PATH}" ]; then
    echo "ERROR: CLAUDE_TIMER_PATH is not set."
    echo "       Please run:  source timer/setup.sh"
    exit 1
fi

FIRMWARE_DIR="${CLAUDE_TIMER_PATH}/firmware"

# Parse arguments: optional leading "clean" keyword, optional arch filter
CLEAN=0
if [[ "${1}" == "clean" ]]; then
    CLEAN=1
    shift
fi
FILTER="${1:-all}"

# ---------------------------------------------------------------------------
# Helper: clean one architecture
#   $1 = human label    (e.g. "ARM Cortex-M33")
#   $2 = build_tag      (e.g. "arm-cortex-m33")
# ---------------------------------------------------------------------------
clean_target() {
    local label="$1"
    local build_tag="$2"

    echo ""
    echo "=== Cleaning ${label} ==="
    rm -rf "${FIRMWARE_DIR}/build/${build_tag}"
    rm -rf "${FIRMWARE_DIR}/lib/${build_tag}"
    echo "=== ${label} clean complete ==="
}

# ---------------------------------------------------------------------------
# Helper: build one architecture
#   $1 = human label  (e.g. "ARM Cortex-M33")
#   $2 = toolchain file relative to firmware dir  (e.g. cmake/arm-cortex-m33.cmake)
#   $3 = build subdirectory name  (e.g. arm-cortex-m33)
#   $4 = required compiler binary name  (checked with command -v)
# ---------------------------------------------------------------------------
build_target() {
    local label="$1"
    local toolchain="$2"
    local build_tag="$3"
    local compiler="$4"

    if ! command -v "${compiler}" >/dev/null 2>&1; then
        echo "WARNING: ${compiler} not found — skipping ${label} build."
        return 0
    fi

    local build_dir="${FIRMWARE_DIR}/build/${build_tag}"
    mkdir -p "${build_dir}"

    echo ""
    echo "=== Configuring ${label} ==="
    cmake -S "${FIRMWARE_DIR}" \
          -B "${build_dir}" \
          -DCMAKE_TOOLCHAIN_FILE="${FIRMWARE_DIR}/${toolchain}" \
          -DCMAKE_BUILD_TYPE=Release \
          --fresh

    echo "=== Building ${label} ==="
    cmake --build "${build_dir}" --parallel

    echo "=== ${label} complete — library: firmware/lib/${build_tag}/libtimer.a ==="
}

# ---------------------------------------------------------------------------
# Clean or build selected targets
# ---------------------------------------------------------------------------
if [[ "${CLEAN}" == "1" ]]; then
    if [[ "${FILTER}" == "all" || "${FILTER}" == "arm" ]]; then
        clean_target "ARM Cortex-M33" "arm-cortex-m33"
    fi
    if [[ "${FILTER}" == "all" || "${FILTER}" == "riscv" ]]; then
        clean_target "RISC-V 32-bit" "riscv32"
    fi
    echo ""
    echo "Timer firmware clean complete."
else
    if [[ "${FILTER}" == "all" || "${FILTER}" == "arm" ]]; then
        build_target \
            "ARM Cortex-M33" \
            "cmake/arm-cortex-m33.cmake" \
            "arm-cortex-m33" \
            "arm-none-eabi-gcc"
    fi
    if [[ "${FILTER}" == "all" || "${FILTER}" == "riscv" ]]; then
        build_target \
            "RISC-V 32-bit (rv32imac_zicsr)" \
            "cmake/riscv32.cmake" \
            "riscv32" \
            "riscv-none-elf-gcc"
    fi
    echo ""
    echo "Timer firmware build complete."
    echo "Libraries:"
    find "${FIRMWARE_DIR}/lib" -name "libtimer.a" 2>/dev/null | sort | sed 's/^/  /'
fi
