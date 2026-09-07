#!/usr/bin/env bash
# setup.sh — Environment setup for bus_matrix
# Usage: source IP/interface/bus_matrix/setup.sh

# ---------------------------------------------------------------------------
# Guard: must be sourced, not executed
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: setup.sh must be sourced, not executed directly."
    echo "       Use:  source setup.sh   or   . setup.sh"
    exit 1
fi

# ---------------------------------------------------------------------------
# Self-locate: set CLAUDE_BUS_MATRIX_PATH to the directory containing this file
# ---------------------------------------------------------------------------
export CLAUDE_BUS_MATRIX_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Common components path  (IP/common/ — shared across all IP projects)
# bus_matrix lives at IP/interface/bus_matrix/ so IP/common/ is two levels up
# ---------------------------------------------------------------------------
export IP_COMMON_PATH="$(cd "${CLAUDE_BUS_MATRIX_PATH}/../.." && pwd)/common"

# ---------------------------------------------------------------------------
# Project identity
# ---------------------------------------------------------------------------
export IP_NAME="bus_matrix"

# ---------------------------------------------------------------------------
# Convenience paths derived from CLAUDE_BUS_MATRIX_PATH
# ---------------------------------------------------------------------------
export BUS_MATRIX_DESIGN_PATH="${CLAUDE_BUS_MATRIX_PATH}/design"
export BUS_MATRIX_VERIFICATION_PATH="${CLAUDE_BUS_MATRIX_PATH}/verification"
export BUS_MATRIX_SYNTHESIS_PATH="${CLAUDE_BUS_MATRIX_PATH}/synthesis"
export BUS_MATRIX_DOC_PATH="${CLAUDE_BUS_MATRIX_PATH}/doc"

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
    CLAUDE_IP_VENV="$(cd "${CLAUDE_BUS_MATRIX_PATH}/../../.." && pwd)/virtualenv/CLAUDE_IP/bin/activate"
    if [ -f "${CLAUDE_IP_VENV}" ]; then
        source "${CLAUDE_IP_VENV}"
    else
        echo "WARNING: Python venv not found at ${CLAUDE_IP_VENV}"
        echo "         Run: python3 -m venv $(cd "${CLAUDE_BUS_MATRIX_PATH}/../../.." && pwd)/virtualenv/CLAUDE_IP"
    fi
    unset CLAUDE_IP_VENV
fi

# ---------------------------------------------------------------------------
# PATH — updated last so these entries are never overwritten by sourced scripts
# On csun.edu: VCS and Xcelium are already on the system PATH; OSS CAD Suite,
#             Quartus, and ModelSim are not installed on that host, but the
#             cross-compiler toolchains are (from CROSS_COMPILERS_PATH above).
# ---------------------------------------------------------------------------
if [ "${_ON_CSUN}" -eq 0 ]; then
    export PATH="${XPACK_RISCV_PATH}/bin:${OSS_CAD_SUITE_PATH}/bin:${QUARTUS_PATH}:${MODELSIM_PATH}:${PATH}"
else
    export PATH="${XPACK_RISCV_PATH}/bin:${ARM_TOOLCHAIN_PATH}/bin:${PATH}"
fi

unset _HOSTNAME _ON_CSUN

echo "bus_matrix environment ready. CLAUDE_BUS_MATRIX_PATH=${CLAUDE_BUS_MATRIX_PATH}"
