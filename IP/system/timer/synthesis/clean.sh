#!/bin/bash
# Remove all generated synthesis outputs, leaving only source files.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Design Compiler outputs
# Note: sky130_lib/ is deliberately NOT removed here — it's the shared
# cross-IP .db cache under IP/common/synthesis/designcompiler/, not a
# per-IP artifact. Clean it directly if you really need to force a rebuild.
DC_DIR="$SCRIPT_DIR/designcompiler"
rm -rf \
    "$DC_DIR"/cksum_dir \
    "$DC_DIR"/reports \
    "$DC_DIR"/netlists \
    "$DC_DIR"/*.v \
    "$DC_DIR"/*.sdf \
    "$DC_DIR"/*.pvk \
    "$DC_DIR"/*.pvl \
    "$DC_DIR"/*.syn \
    "$DC_DIR"/*.mr \
    "$DC_DIR"/ARCH \
    "$DC_DIR"/ENTI \
    "$DC_DIR"/PACK \
    "$DC_DIR"/command.log \
    "$DC_DIR"/dc_saed90_run.log \
    "$DC_DIR"/dc_saed32_run.log \
    "$DC_DIR"/dc_saed14_run.log \
    "$DC_DIR"/dc_sky130_run.log \
    "$DC_DIR"/default.svf \
    "$DC_DIR"/report.txt

# PrimeTime STA outputs (csun.edu only; see run_primetime_sta.py)
# Note: report_sta_<target>.txt is NOT removed — it's the committed final
# per-target summary, like report_sky130.txt above.
rm -rf "$SCRIPT_DIR/primetime/reports" "$SCRIPT_DIR/primetime/.rce"
rm -f "$SCRIPT_DIR"/primetime/pt_*_run.log "$SCRIPT_DIR/primetime/pt_shell_command.log"

# Yosys outputs
rm -rf "$SCRIPT_DIR/yosys/work"

# Python cache
rm -rf "$SCRIPT_DIR/__pycache__"

echo "Synthesis outputs cleaned."
