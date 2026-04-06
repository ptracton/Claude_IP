#!/usr/bin/env bash
# run_regression.sh — Full regression for bus_matrix IP.
#
# Runs all simulation suites (Icarus SV, GHDL VHDL, optionally xsim) and
# reports results. Must be run from the bus_matrix root directory (where
# setup.sh lives), or sourced from there.
#
# Usage:
#   cd IP/interface/bus_matrix
#   source setup.sh
#   bash verification/regression/run_regression.sh [--verbose] [--xsim]

set -euo pipefail

# ---- Resolve script location -----------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BM_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

DESIGN_DIR="${BM_ROOT}/design/rtl/verilog"
TB_DIR="${BM_ROOT}/verification/testbench"
TESTS_DIR="${BM_ROOT}/verification/tests"
WORK_DIR="${BM_ROOT}/verification/work/regression"

# Common IP shared RTL and test/task files
COMMON_TESTS="${IP_COMMON_PATH}/verification/tests"

VERBOSE=0
RUN_XSIM=0
for arg in "$@"; do
  [[ "$arg" == "--verbose" ]] && VERBOSE=1
  [[ "$arg" == "--xsim" ]] && RUN_XSIM=1
done

mkdir -p "${WORK_DIR}"

# ---- Colour helpers --------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}  PASS${NC}  $1"; }
fail() { echo -e "${RED}   FAIL${NC}  $1"; }
info() { echo -e "${YELLOW}  INFO${NC}  $1"; }

# ---- Result tracking -------------------------------------------------------
TOTAL=0; PASSED=0; FAILED=0
declare -a FAILURES=()

run_sim() {
  local name="$1"; shift
  local log="${WORK_DIR}/${name}.log"
  TOTAL=$((TOTAL + 1))
  if [[ $VERBOSE -eq 1 ]]; then
    "$@" 2>&1 | tee "${log}"
  else
    "$@" > "${log}" 2>&1
  fi
  local rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]] || grep -q "FAIL\|ERROR\|error:" "${log}" 2>/dev/null; then
    fail "${name}"
    FAILURES+=("${name}")
    FAILED=$((FAILED + 1))
  else
    pass "${name}"
    PASSED=$((PASSED + 1))
  fi
}

# ============================================================================
# Icarus Verilog — SystemVerilog testbenches
# ============================================================================
echo ""
info "=== Icarus Verilog (SystemVerilog) ==="

for PROTO in ahb axi wb; do
  TB="tb_bus_matrix_${PROTO}"
  case "${PROTO}" in
    ahb)
      DUT="${DESIGN_DIR}/bus_matrix_ahb.sv"
      BFMS="${TB_DIR}/bus_matrix_ahb_master.sv ${TB_DIR}/bus_matrix_ahb_slave.sv"
      ;;
    axi)
      DUT="${DESIGN_DIR}/bus_matrix_axi.sv"
      BFMS="${TB_DIR}/bus_matrix_axi_master.sv ${TB_DIR}/bus_matrix_axi_slave.sv"
      ;;
    wb)
      DUT="${DESIGN_DIR}/bus_matrix_wb.sv"
      BFMS="${TB_DIR}/bus_matrix_wb_master.sv ${TB_DIR}/bus_matrix_wb_slave.sv"
      ;;
  esac

  VVP="${WORK_DIR}/${TB}_sv.vvp"
  # Compile
  run_sim "icarus_compile_${PROTO}_sv" \
    iverilog -g2012 -Wall \
      -I"${DESIGN_DIR}" -I"${TB_DIR}" -I"${TESTS_DIR}" \
      -I"${COMMON_TESTS}" \
      -o "${VVP}" \
      "${DESIGN_DIR}/bus_matrix_arb.sv" \
      "${DESIGN_DIR}/bus_matrix_decoder.sv" \
      "${DESIGN_DIR}/bus_matrix_core.sv" \
      ${DUT} \
      ${BFMS} \
      "${TB_DIR}/${TB}.sv"
  # Simulate (only if compile passed)
  if [[ -f "${VVP}" ]]; then
    run_sim "icarus_sim_${PROTO}_sv" vvp "${VVP}"
  fi
done

# ============================================================================
# GHDL — VHDL testbenches
# ============================================================================
echo ""
info "=== GHDL (VHDL) ==="

VHDL_RTL_DIR="${BM_ROOT}/design/rtl/vhdl"

for PROTO in ahb axi wb; do
  TB="tb_bus_matrix_${PROTO}"
  GHDL_WORK="${WORK_DIR}/ghdl_${PROTO}"
  mkdir -p "${GHDL_WORK}"

  run_sim "ghdl_compile_${PROTO}_vhd" bash -c "
    cd '${GHDL_WORK}' && \
    ghdl -a --std=08 -frelaxed --workdir='${GHDL_WORK}' \
      '${VHDL_RTL_DIR}/bus_matrix_decoder.vhd' \
      '${VHDL_RTL_DIR}/bus_matrix_arb.vhd' \
      '${VHDL_RTL_DIR}/bus_matrix_core.vhd' \
      '${VHDL_RTL_DIR}/bus_matrix_${PROTO}.vhd' \
      '${TB_DIR}/${TB}.vhd'
  "
  run_sim "ghdl_elab_${PROTO}_vhd" bash -c "
    cd '${GHDL_WORK}' && \
    ghdl -e --std=08 -frelaxed --workdir='${GHDL_WORK}' '${TB}'
  "
  if [[ -f "${GHDL_WORK}/${TB}" ]]; then
    run_sim "ghdl_sim_${PROTO}_vhd" bash -c "
      cd '${GHDL_WORK}' && ./'${TB}' --wave='${TB}.ghw' 2>&1
    "
  fi
done

# ============================================================================
# Vivado xsim (optional, requires --xsim flag)
# ============================================================================
if [[ $RUN_XSIM -eq 1 ]]; then
  echo ""
  info "=== Vivado xsim ==="

  for PROTO in ahb axi wb; do
    XSIM_SCRIPT="${BM_ROOT}/verification/xsim/sim_bus_matrix_${PROTO}.sh"
    if [[ -f "${XSIM_SCRIPT}" ]]; then
      run_sim "xsim_${PROTO}" bash "${XSIM_SCRIPT}"
    else
      info "Skipping xsim_${PROTO}: script not found"
    fi
  done
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "=================================================================="
echo " Regression Summary"
echo "=================================================================="
echo -e " Total:  ${TOTAL}"
echo -e " Passed: ${GREEN}${PASSED}${NC}"
echo -e " Failed: ${RED}${FAILED}${NC}"
if [[ ${#FAILURES[@]} -gt 0 ]]; then
  echo ""
  echo " Failed tests:"
  for f in "${FAILURES[@]}"; do
    echo -e "   ${RED}*${NC} ${f}  (log: ${WORK_DIR}/${f}.log)"
  done
fi
echo "=================================================================="

if [[ ${FAILED} -eq 0 ]]; then
  echo -e "${GREEN}ALL SIMULATIONS PASSED${NC}"
  exit 0
else
  echo -e "${RED}REGRESSION FAILED${NC}"
  exit 1
fi
