#!/usr/bin/env bash
# run_regression.sh — Convenience wrapper for run_regression.py.
# Usage:  source timer/setup.sh && bash verification/regression/run_regression.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${SCRIPT_DIR}/../tools"

if [[ -z "${CLAUDE_TIMER_PATH:-}" ]]; then
  echo "ERROR: CLAUDE_TIMER_PATH is not set.  Run: source timer/setup.sh"
  exit 1
fi

exec python3 "${TOOLS_DIR}/run_regression.py" "$@"
