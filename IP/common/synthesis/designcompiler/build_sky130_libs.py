#!/usr/bin/env python3
"""build_sky130_libs.py — Compile the SkyWater sky130 ASCII .lib corners to .db.

Shared across all IP modules so the sky130 Design Compiler library only needs
compiling once, in one place, instead of every IP/*/synthesis/ maintaining
its own copy. Any IP's run_vendor_synth.py can:

    sys.path.insert(0, str(Path(IP_COMMON_PATH) / "synthesis" / "designcompiler"))
    import build_sky130_libs
    db_paths = build_sky130_libs.ensure_sky130_dbs()

dc_shell on this host cannot read ASCII .lib directly as a target_library
("File is not a DB file", DB-1) — each corner must be compiled once with
Library Compiler (lc_shell). The compiled .db files are cached in
sky130_lib/ next to this script (mtime-checked against the source .lib) so
repeat runs, across any IP, reuse them instead of recompiling.

Usage:
    python3 build_sky130_libs.py            # compile (or reuse) all corners
    python3 build_sky130_libs.py --force    # recompile even if cache is fresh
"""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional

# SkyWater 130nm open-source PDK, installed per-user via volare (not under
# /opt/ECE_Lib like the SAED PDKs — those are shared installs; this one is
# each CSUN user's own scratch install).
SKY130_PDK = ("/tmp/pet43490/PDK/volare/sky130/versions/"
              "0fe599b2afb6708d281543108caf8310912f54af/sky130A")

# All three sky130_fd_sc_hd corners are compiled so per-corner STA/analysis
# has them available; synthesis itself only targets the typical corner
# (SKY130_SYNTH_CORNER) — matching how the SAED PDKs synthesize to a single
# corner's .db.
SKY130_CORNERS = {
    "ss_100C_1v60": "libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__ss_100C_1v60.lib",  # worst-case (slow)
    "tt_025C_1v80": "libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib",  # typical
    "ff_n40C_1v95": "libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__ff_n40C_1v95.lib",  # best-case (fast)
}
SKY130_SYNTH_CORNER = "tt_025C_1v80"

CACHE_DIR = Path(__file__).resolve().parent / "sky130_lib"


def ensure_sky130_dbs(pdk_path: str = SKY130_PDK, cache_dir: Path = CACHE_DIR,
                       force: bool = False) -> Optional[dict]:
    """Compile every sky130 corner's ASCII .lib to .db via lc_shell, caching each.

    Returns {corner: db_path} for every corner in SKY130_CORNERS, or None on failure.
    """
    cache_dir.mkdir(parents=True, exist_ok=True)

    db_paths = {}
    to_compile = {}
    for corner, rel_lib in SKY130_CORNERS.items():
        ascii_lib = Path(pdk_path) / rel_lib
        if not ascii_lib.is_file():
            print(f"  ERROR: sky130 {corner} library not found at {ascii_lib}")
            return None
        db_path = cache_dir / f"{ascii_lib.stem}.db"
        if not force and db_path.exists() and db_path.stat().st_mtime >= ascii_lib.stat().st_mtime:
            db_paths[corner] = str(db_path)
        else:
            to_compile[corner] = (ascii_lib, db_path)

    if to_compile:
        lc_shell = shutil.which("lc_shell")
        if not lc_shell:
            print("  ERROR: lc_shell not found on PATH — needed to compile sky130's ASCII .lib to .db")
            return None

        compile_tcl = cache_dir / "compile_lib.tcl"
        lines = []
        for corner, (ascii_lib, db_path) in to_compile.items():
            lines.append(f'read_lib "{ascii_lib}"')
            lines.append(f'write_lib {ascii_lib.stem} -output "{db_path}"')
        lines.append("quit")
        compile_tcl.write_text("\n".join(lines) + "\n")

        print(f"  Compiling sky130 corners ({', '.join(to_compile)}) -> .db (lc_shell)")
        try:
            result = subprocess.run(
                [lc_shell, "-f", str(compile_tcl)],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                timeout=600,
                cwd=str(cache_dir),
            )
        except subprocess.TimeoutExpired:
            print("  ERROR: lc_shell timed out after 600 s compiling sky130 libs")
            return None

        (cache_dir / "lc_run.log").write_text(result.stdout)

        for corner, (ascii_lib, db_path) in to_compile.items():
            if not db_path.exists():
                print(f"  ERROR: lc_shell failed to compile sky130 {corner} lib (exit {result.returncode})")
                print(f"         See {cache_dir / 'lc_run.log'} for details")
                return None
            db_paths[corner] = str(db_path)

    return db_paths


def main() -> None:
    parser = argparse.ArgumentParser(description="Compile sky130 ASCII .lib corners to .db (shared cache)")
    parser.add_argument("--pdk", default=SKY130_PDK, help="Path to the sky130A PDK root")
    parser.add_argument("--cache-dir", default=str(CACHE_DIR), help="Where to write/read compiled .db files")
    parser.add_argument("--force", action="store_true", help="Recompile even if the cache looks up to date")
    args = parser.parse_args()

    db_paths = ensure_sky130_dbs(args.pdk, Path(args.cache_dir), args.force)
    if not db_paths:
        sys.exit(1)

    for corner, path in db_paths.items():
        marker = "  (synthesis corner)" if corner == SKY130_SYNTH_CORNER else ""
        print(f"  {corner:<15} {path}{marker}")
    sys.exit(0)


if __name__ == "__main__":
    main()
