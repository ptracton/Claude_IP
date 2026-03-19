#!/usr/bin/env bash
# run_formal.sh — Run or clean SymbiYosys formal verification for all timer protocols.
#
# Usage:
#   ./run_formal.sh          # run all formal checks
#   ./run_formal.sh --clean  # remove all sby run directories and artifacts
#
# Results are printed to stdout and the script exits non-zero on any failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SBY=/opt/oss-cad-suite/bin/sby

# ---------------------------------------------------------------------------
# Clean mode
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--clean" ]]; then
  echo "Cleaning formal verification artifacts..."
  for proto in apb ahb axi4l wb; do
    rm -rf "${SCRIPT_DIR}/timer_${proto}"
  done
  rm -rf "${SCRIPT_DIR}/work"
  echo "Formal clean complete."
  exit 0
fi

# ---------------------------------------------------------------------------
# Run mode
# ---------------------------------------------------------------------------
pass_count=0
fail_count=0
results=()

for proto in apb ahb axi4l wb; do
  sby_file="${SCRIPT_DIR}/timer_${proto}.sby"
  echo "[formal] Running timer_${proto} ..."
  if "${SBY}" -f "${sby_file}" -d "${SCRIPT_DIR}/work/timer_${proto}"; then
    echo "[formal] timer_${proto}: PASS"
    results+=("timer_${proto}: PASS")
    ((pass_count++)) || true
  else
    echo "[formal] timer_${proto}: FAIL"
    results+=("timer_${proto}: FAIL")
    ((fail_count++)) || true
  fi
done

echo ""
echo "============================================"
echo "Formal Verification Results"
echo "============================================"
for r in "${results[@]}"; do
  echo "  $r"
done
echo "============================================"
echo "PASS: ${pass_count}  FAIL: ${fail_count}"
if [[ ${fail_count} -eq 0 ]]; then
  echo "All formal checks PASSED."
  exit 0
else
  echo "One or more formal checks FAILED."
  exit 1
fi
