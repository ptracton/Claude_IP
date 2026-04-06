#!/usr/bin/env bash
# sim_bus_matrix_ahb.sh — Vivado xsim directed test for bus_matrix_ahb.
#
# Usage:
#   cd IP/interface/bus_matrix
#   source setup.sh
#   bash verification/xsim/sim_bus_matrix_ahb.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BM_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

DESIGN_DIR="${BM_ROOT}/design/rtl/verilog"
TB_DIR="${BM_ROOT}/verification/testbench"
TESTS_DIR="${BM_ROOT}/verification/tests"
COMMON_TESTS="${IP_COMMON_PATH}/verification/tests"
WORK_DIR="${BM_ROOT}/verification/work/xsim/ahb"
TOP="tb_bus_matrix_ahb"

mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

echo "=== xvlog: Compile ==="
xvlog --sv --work work \
    --include "${DESIGN_DIR}" \
    --include "${TB_DIR}" \
    --include "${TESTS_DIR}" \
    --include "${COMMON_TESTS}" \
    "${DESIGN_DIR}/bus_matrix_arb.sv" \
    "${DESIGN_DIR}/bus_matrix_decoder.sv" \
    "${DESIGN_DIR}/bus_matrix_core.sv" \
    "${DESIGN_DIR}/bus_matrix_ahb.sv" \
    "${TB_DIR}/bus_matrix_ahb_master.sv" \
    "${TB_DIR}/bus_matrix_ahb_slave.sv" \
    "${TB_DIR}/${TOP}.sv"

echo "=== xelab: Elaborate ==="
xelab -debug typical --snapshot "${TOP}_snap" --relax "work.${TOP}"

echo "=== xsim: Simulate ==="
xsim "${TOP}_snap" --runall --log xsim.log

echo "=== Done ==="
grep -q "PASS" xsim.log && echo "PASS" || echo "FAIL"
