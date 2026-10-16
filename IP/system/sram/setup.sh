#!/usr/bin/env bash
# setup.sh — Environment setup for sram
# Usage: source IP/system/sram/setup.sh

# ---------------------------------------------------------------------------
# Guard: must be sourced, not executed
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: setup.sh must be sourced, not executed directly."
    echo "       Use:  source setup.sh   or   . setup.sh"
    exit 1
fi

# ---------------------------------------------------------------------------
# Self-locate: set CLAUDE_SRAM_PATH to the directory containing this file
# ---------------------------------------------------------------------------
export CLAUDE_SRAM_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Common components path  (IP/common/ — shared across all IP projects)
# sram lives at IP/system/sram/ so IP/common/ is two levels up
# ---------------------------------------------------------------------------
export IP_COMMON_PATH="$(cd "${CLAUDE_SRAM_PATH}/../.." && pwd)/common"

# ---------------------------------------------------------------------------
# Project identity
# ---------------------------------------------------------------------------
export SRAM_NAME="sram"

# ---------------------------------------------------------------------------
# Convenience paths derived from CLAUDE_SRAM_PATH
# ---------------------------------------------------------------------------
export SRAM_DESIGN_PATH="${CLAUDE_SRAM_PATH}/design"
export SRAM_VERIFICATION_PATH="${CLAUDE_SRAM_PATH}/verification"
export SRAM_FIRMWARE_PATH="${CLAUDE_SRAM_PATH}/firmware"
export SRAM_SYNTHESIS_PATH="${CLAUDE_SRAM_PATH}/synthesis"
export SRAM_DOC_PATH="${CLAUDE_SRAM_PATH}/doc"

# ---------------------------------------------------------------------------
# Host detection
# ---------------------------------------------------------------------------
_HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
if [[ "${_HOSTNAME}" == *.csun.edu ]]; then
    _ON_CSUN=1
else
    _ON_CSUN=0
fi

# ---------------------------------------------------------------------------
# External tool paths (set as variables only — PATH updated at the END of
# this file, after all sourced scripts, so nothing can overwrite our entries)
# ---------------------------------------------------------------------------
export OSS_CAD_SUITE_PATH="/opt/oss-cad-suite"
export QUARTUS_PATH="/opt/intelFPGA_lite/23.1std/quartus/bin"
export MODELSIM_PATH="/opt/intelFPGA_pro/21.1/modelsim_ase/bin"

# Cross-compiler toolchains (arm-none-eabi-gcc, riscv-none-elf-gcc).
# On csun.edu both live under /tmp/pet43490/CrossCompilers instead of the
# standard-host locations (xpack at /opt; ARM toolchain expected
# system-installed via apt/brew and already on PATH there).
if [ "${_ON_CSUN}" -eq 1 ]; then
    export CROSS_COMPILERS_PATH="/tmp/pet43490/CrossCompilers"
    export XPACK_RISCV_PATH="${CROSS_COMPILERS_PATH}/xpack-riscv-none-elf-gcc-15.2.0-1"
    export ARM_TOOLCHAIN_PATH="${CROSS_COMPILERS_PATH}/arm-gnu-toolchain-15.3.rel1-x86_64-arm-none-eabi"
else
    export XPACK_RISCV_PATH="/opt/xpack-riscv-none-elf-gcc-15.2.0-1"
fi

# SkyWater sky130 PDK root (stable sky130A symlink) for Design Compiler,
# PrimeTime, post-synthesis simulation and power. Read by
# IP/common/synthesis/designcompiler/build_sky130_libs.py. The sram IP also
# uses its OpenRAM macros (libs.ref/sky130_sram_macros). Kept out of /tmp
# (the host's /tmp cleanup wiped it twice). Pre-set it to override.
if [ "${_ON_CSUN}" -eq 1 ]; then
    export CLAUDE_SKY130_PDK_PATH="${CLAUDE_SKY130_PDK_PATH:-/home/users6/pet43490/PDK/sky130A}"
fi

# ---------------------------------------------------------------------------
# Vivado 2023.2  (sources its own settings64.sh which modifies PATH)
# Not available on csun.edu.
# ---------------------------------------------------------------------------
if [ "${_ON_CSUN}" -eq 0 ]; then
    if [ -f "/opt/Xilinx/Vivado/2023.2/settings64.sh" ]; then
        source "/opt/Xilinx/Vivado/2023.2/settings64.sh"
    else
        echo "WARNING: Vivado not found at /opt/Xilinx/Vivado/2023.2/settings64.sh"
    fi
fi

# ---------------------------------------------------------------------------
# Python virtual environment  (activation script modifies PATH)
# Not activated on csun.edu — use system Python there.
# ---------------------------------------------------------------------------
if [ "${_ON_CSUN}" -eq 0 ]; then
    CLAUDE_IP_VENV="$(cd "${CLAUDE_SRAM_PATH}/../../.." && pwd)/virtualenv/CLAUDE_IP/bin/activate"
    if [ -f "${CLAUDE_IP_VENV}" ]; then
        source "${CLAUDE_IP_VENV}"
    else
        echo "WARNING: Python venv not found at ${CLAUDE_IP_VENV}"
        echo "         Run: python3 -m venv $(cd "${CLAUDE_SRAM_PATH}/../../.." && pwd)/virtualenv/CLAUDE_IP"
    fi
    unset CLAUDE_IP_VENV
fi

# ---------------------------------------------------------------------------
# PATH — updated last so these entries are never overwritten by sourced scripts
# On csun.edu: VCS and Xcelium are already on the system PATH; OSS CAD Suite,
#             Quartus, and ModelSim are not installed on that host, but the
#             cross-compiler toolchains are (from CROSS_COMPILERS_PATH above).
# _path_prepend skips directories already on PATH, so sourcing this file
# more than once does not grow PATH.
# ---------------------------------------------------------------------------
_path_prepend() {
    local dir
    for dir in "$@"; do
        case ":${PATH}:" in
            *":${dir}:"*) ;;
            *) PATH="${dir}:${PATH}" ;;
        esac
    done
}

# Listed last-first: the first argument ends up last in front of PATH.
if [ "${_ON_CSUN}" -eq 0 ]; then
    _path_prepend "${MODELSIM_PATH}" "${QUARTUS_PATH}" "${OSS_CAD_SUITE_PATH}/bin" \
                  "${XPACK_RISCV_PATH}/bin"
else
    _path_prepend "${ARM_TOOLCHAIN_PATH}/bin" "${XPACK_RISCV_PATH}/bin"
fi
export PATH

unset -f _path_prepend
unset _HOSTNAME _ON_CSUN

echo "sram environment ready. CLAUDE_SRAM_PATH=${CLAUDE_SRAM_PATH}"
