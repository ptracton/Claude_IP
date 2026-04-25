#!/usr/bin/env bash
# cleanup.sh — Remove all build and simulation artifacts for bus_matrix
# Usage: bash IP/interface/bus_matrix/cleanup.sh

if [ -z "${CLAUDE_BUS_MATRIX_PATH}" ]; then
    echo "ERROR: CLAUDE_BUS_MATRIX_PATH is not set."
    echo "       Please run:  source IP/interface/bus_matrix/setup.sh"
    exit 1
fi

set -e

echo "Cleaning bus_matrix build and simulation artifacts..."

rm -rf "${CLAUDE_BUS_MATRIX_PATH}/verification/work"/*

if [ -f "${CLAUDE_BUS_MATRIX_PATH}/synthesis/run_vendor_synth.py" ]; then
    python3 "${CLAUDE_BUS_MATRIX_PATH}/synthesis/run_vendor_synth.py" --clean 2>/dev/null || true
fi
bash "${CLAUDE_BUS_MATRIX_PATH}/synthesis/clean.sh" 2>/dev/null || true

rm -f  "${CLAUDE_BUS_MATRIX_PATH}/verification/formal/results.log"
rm -rf "${CLAUDE_BUS_MATRIX_PATH}/verification/formal/work"
rm -f  "${CLAUDE_BUS_MATRIX_PATH}/verification/lint/lint_results.log"

echo "Clean complete."
