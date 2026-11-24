#!/usr/bin/env bash
# run_regression.sh — Convenience wrapper for regression_sram.py (same options).
# Usage:  source IP/system/sram/setup.sh && bash verification/regression/run_regression.sh [--collect]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${SCRIPT_DIR}/../tools"

if [[ -z "${CLAUDE_SRAM_PATH:-}" ]]; then
  echo "ERROR: CLAUDE_SRAM_PATH is not set.  Run: source IP/system/sram/setup.sh"
  exit 1
fi

exec python3 "${TOOLS_DIR}/regression_sram.py" "$@"
