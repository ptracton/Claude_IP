#!/bin/bash
# Remove all generated synthesis outputs, leaving only source files.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Design Compiler outputs
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
    "$DC_DIR"/default.svf \
    "$DC_DIR"/report.txt

# Yosys outputs
rm -rf "$SCRIPT_DIR/yosys/work"

# Python cache
rm -rf "$SCRIPT_DIR/__pycache__"

echo "Synthesis outputs cleaned."
