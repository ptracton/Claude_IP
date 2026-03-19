#!/usr/bin/env bash
# setup.sh — Environment setup for timer
# Usage: source timer/setup.sh

# ---------------------------------------------------------------------------
# Self-locate: set CLAUDE_TIMER_PATH to the directory containing this file
# ---------------------------------------------------------------------------
export CLAUDE_TIMER_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Common components path  (IP/common/ — shared across all IP projects)
# timer lives at IP/system/timer/ so IP/common/ is two levels up
# ---------------------------------------------------------------------------
export IP_COMMON_PATH="$(cd "${CLAUDE_TIMER_PATH}/../.." && pwd)/common"

# ---------------------------------------------------------------------------
# Project identity
# ---------------------------------------------------------------------------
export TIMER_NAME="timer"

# ---------------------------------------------------------------------------
# Convenience paths derived from CLAUDE_TIMER_PATH
# ---------------------------------------------------------------------------
export TIMER_DESIGN_PATH="${CLAUDE_TIMER_PATH}/design"
export TIMER_VERIFICATION_PATH="${CLAUDE_TIMER_PATH}/verification"
export TIMER_FIRMWARE_PATH="${CLAUDE_TIMER_PATH}/firmware"
export TIMER_SYNTHESIS_PATH="${CLAUDE_TIMER_PATH}/synthesis"
export TIMER_DOC_PATH="${CLAUDE_TIMER_PATH}/doc"

# ---------------------------------------------------------------------------
# External tool paths (set as variables only — PATH updated at the END of
# this file, after all sourced scripts, so nothing can overwrite our entries)
# ---------------------------------------------------------------------------
export OSS_CAD_SUITE_PATH="/opt/oss-cad-suite"
export XPACK_RISCV_PATH="/opt/xpack-riscv-none-elf-gcc-15.2.0-1"
export QUARTUS_PATH="/opt/intelFPGA_lite/23.1std/quartus/bin"
export MODELSIM_PATH="/opt/intelFPGA_pro/21.1/modelsim_ase/bin"

# ---------------------------------------------------------------------------
# Vivado 2023.2  (sources its own settings64.sh which modifies PATH)
# ---------------------------------------------------------------------------
if [ -f "/opt/Xilinx/Vivado/2023.2/settings64.sh" ]; then
    source "/opt/Xilinx/Vivado/2023.2/settings64.sh"
else
    echo "WARNING: Vivado not found at /opt/Xilinx/Vivado/2023.2/settings64.sh"
fi

# ---------------------------------------------------------------------------
# Python virtual environment  (activation script modifies PATH)
# ---------------------------------------------------------------------------
CLAUDE_IP_VENV="$(cd "${CLAUDE_TIMER_PATH}/../../.." && pwd)/virtualenv/CLAUDE_IP/bin/activate"
if [ -f "${CLAUDE_IP_VENV}" ]; then
    source "${CLAUDE_IP_VENV}"
else
    echo "WARNING: Python venv not found at ${CLAUDE_IP_VENV}"
    echo "         Run: python3 -m venv $(cd "${CLAUDE_TIMER_PATH}/../../.." && pwd)/virtualenv/CLAUDE_IP"
fi
unset CLAUDE_IP_VENV

# ---------------------------------------------------------------------------
# PATH — updated last so these entries are never overwritten by sourced scripts
# ---------------------------------------------------------------------------
export PATH="${XPACK_RISCV_PATH}/bin:${OSS_CAD_SUITE_PATH}/bin:${QUARTUS_PATH}:${MODELSIM_PATH}:${PATH}"

echo "timer environment ready. CLAUDE_TIMER_PATH=${CLAUDE_TIMER_PATH}"
