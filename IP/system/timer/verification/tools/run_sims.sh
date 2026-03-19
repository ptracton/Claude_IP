#!/usr/bin/env bash
# run_sims.sh — Run all 8 timer IP simulation combinations directly.
#
# Usage:  source IP/system/timer/setup.sh && bash run_sims.sh
#
# Runs Icarus Verilog for all 4 SV testbenches and GHDL for all 4 VHDL
# testbenches.  Results are written to:
#   verification/work/icarus/<proto>_sv/results.log
#   verification/work/ghdl/<proto>_vhdl/results.log

set -e

if [ -z "${CLAUDE_TIMER_PATH}" ]; then
  echo "ERROR: CLAUDE_TIMER_PATH is not set. Run: source setup.sh"
  exit 1
fi

IVERILOG="/opt/oss-cad-suite/bin/iverilog"
VVP="/opt/oss-cad-suite/bin/vvp"
GHDL="/opt/oss-cad-suite/bin/ghdl"

RTL="${CLAUDE_TIMER_PATH}/design/rtl/verilog"
VHDL_RTL="${CLAUDE_TIMER_PATH}/design/rtl/vhdl"
IP_COMMON="${IP_COMMON_PATH:-${CLAUDE_TIMER_PATH}/../../common}"
TASKS="${IP_COMMON}/verification/tasks"
COMMON_TESTS="${IP_COMMON}/verification/tests"
TESTS="${CLAUDE_TIMER_PATH}/verification/tests"
TB="${CLAUDE_TIMER_PATH}/verification/testbench"
WORK="${CLAUDE_TIMER_PATH}/verification/work"

ALL_PASS=1

run_icarus() {
  local proto="$1"
  local work_dir="${WORK}/icarus/${proto}_sv"
  mkdir -p "${work_dir}"
  local vvp_out="${work_dir}/tb_timer_${proto}.vvp"
  local log="${work_dir}/sim.log"
  local result="${work_dir}/results.log"

  echo "--- Icarus ${proto} SV ---"

  # Protocol-specific RTL files (claude_*_if comes from common/)
  local COMMON_RTL="${IP_COMMON}/design/rtl/verilog"
  local if_files=""
  case "${proto}" in
    ahb)   if_files="${COMMON_RTL}/claude_ahb_if.sv ${RTL}/timer_ahb.sv" ;;
    apb)   if_files="${COMMON_RTL}/claude_apb_if.sv ${RTL}/timer_apb.sv" ;;
    axi4l) if_files="${COMMON_RTL}/claude_axi4l_if.sv ${RTL}/timer_axi4l.sv" ;;
    wb)    if_files="${COMMON_RTL}/claude_wb_if.sv ${RTL}/timer_wb.sv" ;;
  esac

  if "${IVERILOG}" -g2012 -Wall -Wno-timescale \
       -I "${TASKS}" -I "${TESTS}" -I "${COMMON_TESTS}" \
       "${RTL}/timer_reg_pkg.sv" \
       "${RTL}/timer_regfile.sv" \
       "${RTL}/timer_core.sv" \
       ${if_files} \
       "${TB}/tb_timer_${proto}.sv" \
       -o "${vvp_out}" > "${log}" 2>&1; then
    "${VVP}" "${vvp_out}" >> "${log}" 2>&1
    local rc=$?
    if [ ${rc} -eq 0 ] \
         && grep -q "PASS tb_timer_${proto}" "${log}" \
         && ! grep -q "FAIL" "${log}"; then
      echo "PASS" > "${result}"
      echo "  PASS: ${result}"
    else
      echo "FAIL" > "${result}"
      cat "${log}" >> "${result}"
      echo "  FAIL: see ${result}"
      ALL_PASS=0
    fi
  else
    echo "FAIL" > "${result}"
    cat "${log}" >> "${result}"
    echo "  COMPILE FAIL: see ${result}"
    ALL_PASS=0
  fi
}

run_ghdl() {
  local proto="$1"
  local work_dir="${WORK}/ghdl/${proto}_vhdl"
  mkdir -p "${work_dir}"
  local log="${work_dir}/sim.log"
  local result="${work_dir}/results.log"

  echo "--- GHDL ${proto} VHDL ---"

  # Protocol-specific VHDL files (claude_*_if comes from common/)
  local COMMON_VHDL="${IP_COMMON}/design/rtl/vhdl"
  local if_files=""
  case "${proto}" in
    ahb)   if_files="${COMMON_VHDL}/claude_ahb_if.vhd ${VHDL_RTL}/timer_ahb.vhd" ;;
    apb)   if_files="${COMMON_VHDL}/claude_apb_if.vhd ${VHDL_RTL}/timer_apb.vhd" ;;
    axi4l) if_files="${COMMON_VHDL}/claude_axi4l_if.vhd ${VHDL_RTL}/timer_axi4l.vhd" ;;
    wb)    if_files="${COMMON_VHDL}/claude_wb_if.vhd ${VHDL_RTL}/timer_wb.vhd" ;;
  esac

  local ok=1
  > "${log}"

  # Analyze all files in dependency order
  for f in \
    "${VHDL_RTL}/timer_reg_pkg.vhd" \
    "${VHDL_RTL}/timer_regfile.vhd" \
    "${VHDL_RTL}/timer_core.vhd" \
    ${if_files} \
    "${COMMON_TESTS}/ip_test_pkg.vhd" \
    "${TB}/tb_timer_${proto}.vhd"
  do
    if ! "${GHDL}" -a --std=08 -frelaxed "--workdir=${work_dir}" "${f}" >> "${log}" 2>&1; then
      echo "  Analysis failed on ${f}"
      ok=0
      break
    fi
  done

  if [ ${ok} -eq 1 ]; then
    if ! "${GHDL}" -e --std=08 -frelaxed "--workdir=${work_dir}" "tb_timer_${proto}" >> "${log}" 2>&1; then
      echo "  Elaboration failed"
      ok=0
    fi
  fi

  if [ ${ok} -eq 1 ]; then
    "${GHDL}" -r --std=08 -frelaxed "--workdir=${work_dir}" "tb_timer_${proto}" \
      --stop-time=1ms >> "${log}" 2>&1
    local rc=$?
    if [ ${rc} -eq 0 ] \
         && grep -q "PASS tb_timer_${proto}" "${log}" \
         && ! grep -q "FAIL" "${log}"; then
      echo "PASS" > "${result}"
      echo "  PASS: ${result}"
    else
      echo "FAIL" > "${result}"
      cat "${log}" >> "${result}"
      echo "  FAIL: see ${result}"
      ALL_PASS=0
    fi
  else
    echo "FAIL" > "${result}"
    cat "${log}" >> "${result}"
    ALL_PASS=0
  fi
}

# Run all 4 Icarus simulations
for proto in ahb apb axi4l wb; do
  run_icarus "${proto}"
done

# Run all 4 GHDL simulations
for proto in ahb apb axi4l wb; do
  run_ghdl "${proto}"
done

echo ""
echo "========================================"
echo "Simulation Summary"
echo "========================================"
for proto in ahb apb axi4l wb; do
  result="${WORK}/icarus/${proto}_sv/results.log"
  status=$(head -1 "${result}" 2>/dev/null || echo "MISSING")
  printf "  icarus/%-10s %s\n" "${proto}_sv" "${status}"
done
for proto in ahb apb axi4l wb; do
  result="${WORK}/ghdl/${proto}_vhdl/results.log"
  status=$(head -1 "${result}" 2>/dev/null || echo "MISSING")
  printf "  ghdl/%-12s %s\n" "${proto}_vhdl" "${status}"
done
echo "========================================"

if [ ${ALL_PASS} -eq 1 ]; then
  echo "All simulations PASSED."
  exit 0
else
  echo "One or more simulations FAILED."
  exit 1
fi
