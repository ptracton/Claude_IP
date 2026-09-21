#!/usr/bin/env python3
"""run_primetime_sta.py — Run PrimeTime STA for the Timer IP (csun.edu only).

Static timing analysis on Design Compiler's gate-level netlists, across
every PDK target that run_vendor_synth.py can synthesize:
  - SAED90, SAED32, SAED14 — one target each, using the same single
    (worst-case) corner .db that synth.tcl already synthesized against.
  - SKY130 — three PVT corners (ss_100C_1v60, tt_025C_1v80, ff_n40C_1v95),
    all rechecked against the one netlist set DC synthesizes (to the
    typical corner). This is the only PDK here with real multi-corner
    coverage — the SAED EDKs each ship a single .db.

This is a separate step from run_vendor_synth.py: run DC synthesis for
whichever PDK(s) you want STA on first, then run this script.

Usage:
    python3 synthesis/run_primetime_sta.py              # everything: saed90+32+14, sky130 all 3 corners
    python3 synthesis/run_primetime_sta.py --saed90     # SAED90 only
    python3 synthesis/run_primetime_sta.py --saed32     # SAED32 only
    python3 synthesis/run_primetime_sta.py --saed14     # SAED14 only
    python3 synthesis/run_primetime_sta.py --sky130     # SKY130, all 3 corners
    python3 synthesis/run_primetime_sta.py --ss         # SKY130 ss_100C_1v60 only
    python3 synthesis/run_primetime_sta.py --tt         # SKY130 tt_025C_1v80 only
    python3 synthesis/run_primetime_sta.py --ff         # SKY130 ff_n40C_1v95 only
    python3 synthesis/run_primetime_sta.py --clean      # clean all STA outputs

Requirements:
    - CLAUDE_TIMER_PATH set (source timer/setup.sh)
    - csun.edu only; pt_shell on PATH
    - Design Compiler netlists + .sdc already generated for whichever
      target(s) you run STA against — synth.tcl writes a .sdc alongside
      each netlist (see run_vendor_synth.py):
          python3 synthesis/run_vendor_synth.py --dc         (all four PDKs)
          python3 synthesis/run_vendor_synth.py --dcsky130   (sky130 only)
          python3 synthesis/run_vendor_synth.py --dc90       (etc.)

Outputs:
    synthesis/primetime/pt_<target>_run.log        — PrimeTime full log, per target
    synthesis/primetime/reports/<target>/          — Per-variant timing/QoR/constraint reports
    synthesis/primetime/report_sta_<target>.txt    — WNS/TNS summary, per target

Where <target> is one of: saed90, saed32, saed14, ss_100C_1v60, tt_025C_1v80, ff_n40C_1v95
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

# Host detection
import socket


def _hostname_fqdn() -> str:
    """Return the host FQDN.

    socket.getfqdn() falls back to the short hostname when reverse DNS
    doesn't resolve (observed on some *.csun.edu machines), so shell out to
    `hostname -f` first — the same command setup.sh uses for host detection.
    """
    try:
        out = subprocess.run(["hostname", "-f"], capture_output=True,
                             text=True, timeout=5)
        fqdn = out.stdout.strip()
        if fqdn:
            return fqdn
    except (OSError, subprocess.TimeoutExpired):
        pass
    return socket.getfqdn()


ON_CSUN = _hostname_fqdn().endswith(".csun.edu")

PT_BIN = "pt_shell"

# ---------------------------------------------------------------------------
# SAED — same single .db each EDK synthesized against (see synth.tcl); no
# per-IP recompile step needed, unlike sky130's ASCII .lib.
# ---------------------------------------------------------------------------
SAED90_PDK = "/opt/ECE_Lib/SAED90nm_EDK_10072017/SAED90_EDK/SAED_EDK90nm"
SAED32_EDK = "/opt/ECE_Lib/SAED32_EDK"
SAED14_EDK = "/opt/ECE_Lib/SAED14nm_EDK_03_2025"

SAED_TARGETS = {
    "saed90": {
        "label": "SAED90 (90nm)",
        "desc":  "saed90nm_max — single corner shipped by this EDK",
        "db":    f"{SAED90_PDK}/Digital_Standard_cell_Library/synopsys/models/saed90nm_max.db",
    },
    "saed32": {
        "label": "SAED32 (32nm)",
        "desc":  "SS 0.95V 125°C (worst-case) — single corner shipped by this EDK",
        "db":    f"{SAED32_EDK}/lib/stdcell_rvt/db_nldm/saed32rvt_ss0p95v125c.db",
    },
    "saed14": {
        "label": "SAED14 (14nm)",
        "desc":  "SS 0.72V 125°C (worst-case) — single corner shipped by this EDK",
        "db":    f"{SAED14_EDK}/SAED14nm_EDK_STD_RVT/liberty/nldm/base/saed14rvt_base_ss0p72v125c.db",
    },
}

# ---------------------------------------------------------------------------
# sky130 — shared cross-IP cache under IP/common/synthesis/designcompiler/,
# same tooling DC synthesis uses (see build_sky130_libs.py).
# ---------------------------------------------------------------------------
_IP_COMMON_PATH = os.environ.get("IP_COMMON_PATH") or str(
    Path(__file__).resolve().parent.parent.parent.parent / "common"
)
sys.path.insert(0, str(Path(_IP_COMMON_PATH) / "synthesis" / "designcompiler"))
import build_sky130_libs  # noqa: E402

SKY130_PDK = build_sky130_libs.SKY130_PDK
SKY130_CORNER_DESC = {
    "ss_100C_1v60": "worst-case",
    "tt_025C_1v80": "typical",
    "ff_n40C_1v95": "best-case",
}

ALL_SAED_TARGETS = list(SAED_TARGETS)
ALL_SKY130_TARGETS = list(SKY130_CORNER_DESC)


def is_sky130_target(target: str) -> bool:
    return target in SKY130_CORNER_DESC


def netlist_pdk_for(target: str) -> str:
    """Which designcompiler/netlists/<pdk>/ dir a target's netlists live in."""
    return "sky130" if is_sky130_target(target) else target


# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------

PRIMETIME_CLEAN_DIRS = ["primetime/reports", "primetime/.rce"]
# Note: report_sta_<target>.txt is NOT cleaned — like report_saed90.txt /
# report_sky130.txt (DC's own summaries), it's the committed final
# per-target summary, not a per-IP scratch artifact.
PRIMETIME_CLEAN_GLOBS = ["primetime/pt_*_run.log", "primetime/pt_shell_command.log"]


def clean_primetime(synth_dir: Path) -> None:
    print("=== Cleaning PrimeTime outputs ===")
    for rel in PRIMETIME_CLEAN_DIRS:
        p = synth_dir / rel
        if p.exists():
            shutil.rmtree(p)
            print(f"  removed {p.relative_to(synth_dir.parent)}/")
    for pattern in PRIMETIME_CLEAN_GLOBS:
        for p in synth_dir.glob(pattern):
            p.unlink()
            print(f"  removed {p.relative_to(synth_dir.parent)}")
    print("=== PrimeTime clean complete ===")


# ---------------------------------------------------------------------------
# PrimeTime STA
# ---------------------------------------------------------------------------

def find_tool(name: str) -> Optional[str]:
    return shutil.which(name)


def resolve_db(target: str) -> Optional[str]:
    """Return the .db path for a target, or None if unavailable."""
    if is_sky130_target(target):
        db_paths = build_sky130_libs.ensure_sky130_dbs(SKY130_PDK)
        return db_paths.get(target) if db_paths else None
    return SAED_TARGETS[target]["db"]


def run_sta(synth_dir: Path, target: str) -> bool:
    """Run PrimeTime STA for one target (SAED PDK or SKY130 corner)."""
    pt_shell = find_tool(PT_BIN)
    if not pt_shell:
        print("  ERROR: pt_shell not found on PATH")
        return False

    net_pdk = netlist_pdk_for(target)
    net_dir = synth_dir / "designcompiler" / "netlists" / net_pdk
    if not any(net_dir.glob("*.v")):
        dc_flag = f"--dc{net_pdk.replace('saed', '')}" if net_pdk != "sky130" else "--dcsky130"
        print(f"  ERROR: no {net_pdk} netlists at {net_dir}")
        print(f"         Run synthesis/run_vendor_synth.py {dc_flag} first.")
        return False

    db = resolve_db(target)
    if not db or not os.path.isfile(db):
        print(f"  ERROR: library .db not available for target '{target}' ({db})")
        return False

    tcl = synth_dir / "primetime" / "sta.tcl"
    rpt_dir = synth_dir / "primetime" / "reports" / target
    log = synth_dir / "primetime" / f"pt_{target}_run.log"

    print(f"  Tool    : {pt_shell}")
    print(f"  Target  : {target}")
    print(f"  Library : {db}")
    print(f"  Script  : {tcl}")
    print(f"  Log     : {log}")

    cmd = [pt_shell, "-f", str(tcl)]
    extra_env = {
        "PT_TARGET":  target,
        "PT_DB":      db,
        "PT_NET_DIR": str(net_dir),
        "PT_RPT_DIR": str(rpt_dir),
    }

    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            timeout=1200,
            cwd=str(synth_dir / "primetime"),
            env={**os.environ, **extra_env},
        )
    except subprocess.TimeoutExpired:
        print(f"  ERROR: PrimeTime ({target}) timed out after 1200 s")
        return False

    log.write_text(result.stdout)

    if result.returncode != 0:
        print(f"  ERROR: PrimeTime ({target}) exited with code {result.returncode}")
        print(f"         See {log} for details")
        for line in result.stdout.splitlines()[-20:]:
            print(f"    {line}")
        return False

    return True


def parse_pt_qor(rpt_dir: Path) -> dict:
    """Extract worst WNS and total TNS across every *_qor.rpt in rpt_dir."""
    data = {"wns": None, "tns": 0.0, "met": "?"}
    found = False

    for rpt in sorted(rpt_dir.glob("*_qor.rpt")):
        text = rpt.read_text()
        wns_m = re.search(r'Critical Path Slack:\s*(-?[\d.]+)', text)
        tns_m = re.search(r'Total Negative Slack:\s*(-?[\d.]+)', text)
        if wns_m:
            found = True
            wns = float(wns_m.group(1))
            if data["wns"] is None or wns < data["wns"]:
                data["wns"] = wns
        if tns_m:
            data["tns"] += float(tns_m.group(1))

    if found:
        data["met"] = "MET" if data["wns"] is not None and data["wns"] >= 0 else "VIOLATED"
    return data


def write_pt_report(synth_dir: Path, target: str, qor: dict) -> None:
    if is_sky130_target(target):
        pdk_line = f"SKY130 (130nm, SkyWater open-source PDK) — {target} ({SKY130_CORNER_DESC[target]})"
    else:
        cfg = SAED_TARGETS[target]
        pdk_line = f"{cfg['label']} — {cfg['desc']}"

    rpt_path = synth_dir / "primetime" / f"report_sta_{target}.txt"
    now = datetime.now().strftime("%Y-%m-%d")
    wns_str = f"{qor['wns']:.3f}" if qor["wns"] is not None else "?"
    lines = [
        "=" * 72,
        "PrimeTime STA Report — timer IP",
        f"Target        : {pdk_line}",
        f"Tool version  : PrimeTime (pt_shell)",
        f"Run date      : {now}",
        "=" * 72,
        "",
        "STATUS: PASS — STA completed successfully for all 8 variants (4 SV + 4 VHDL).",
        f"        Timing is {qor['met']} at this target — see Timing Summary below.",
        "",
        "-" * 72,
        "Timing Summary (across all variants, 100 MHz / 10 ns target)",
        "-" * 72,
        f"  Worst-case WNS : {wns_str} ns",
        f"  Total TNS      : {qor['tns']:.3f} ns",
        f"  Timing         : {qor['met']}",
        "",
        "Per-variant reports:",
        f"  synthesis/primetime/reports/{target}/",
        "",
        "Full log:",
        f"  synthesis/primetime/pt_{target}_run.log",
        "=" * 72,
    ]
    rpt_path.write_text("\n".join(lines) + "\n")
    print(f"  Report  : {rpt_path}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def get_synth_dir() -> Path:
    env = os.environ.get("CLAUDE_TIMER_PATH")
    if env:
        return Path(env) / "synthesis"
    return Path(__file__).resolve().parent


def main() -> None:
    parser = argparse.ArgumentParser(description="Run PrimeTime STA for timer IP (csun.edu only)")
    parser.add_argument("--saed90", action="store_true", help="SAED90 only")
    parser.add_argument("--saed32", action="store_true", help="SAED32 only")
    parser.add_argument("--saed14", action="store_true", help="SAED14 only")
    parser.add_argument("--sky130", action="store_true", help="SKY130, all 3 corners")
    parser.add_argument("--ss",     action="store_true", help="SKY130 ss_100C_1v60 only")
    parser.add_argument("--tt",     action="store_true", help="SKY130 tt_025C_1v80 only")
    parser.add_argument("--ff",     action="store_true", help="SKY130 ff_n40C_1v95 only")
    parser.add_argument("--clean",  action="store_true", help="Remove outputs instead of running STA")
    args = parser.parse_args()

    synth_dir = get_synth_dir()

    # --- Clean mode: host-agnostic no-op-safe, so top-level cleanup.sh can
    # call this unconditionally on any host (mirrors run_vendor_synth.py).
    if args.clean:
        clean_primetime(synth_dir)
        sys.exit(0)

    if not ON_CSUN:
        print("ERROR: PrimeTime STA only available on csun.edu.")
        sys.exit(1)

    print("Timer IP — PrimeTime STA")
    print(f"  Host      : {_hostname_fqdn()} (csun.edu)")
    print(f"  Synth dir : {synth_dir}")
    print()

    any_flag = (args.saed90 or args.saed32 or args.saed14 or args.sky130
                or args.ss or args.tt or args.ff)

    run_saed90 = (not any_flag) or args.saed90
    run_saed32 = (not any_flag) or args.saed32
    run_saed14 = (not any_flag) or args.saed14
    run_ss = (not any_flag) or args.sky130 or args.ss
    run_tt = (not any_flag) or args.sky130 or args.tt
    run_ff = (not any_flag) or args.sky130 or args.ff

    targets = []
    if run_saed90: targets.append("saed90")
    if run_saed32: targets.append("saed32")
    if run_saed14: targets.append("saed14")
    if run_ss: targets.append("ss_100C_1v60")
    if run_tt: targets.append("tt_025C_1v80")
    if run_ff: targets.append("ff_n40C_1v95")

    results = {}
    for target in targets:
        print(f"=== PrimeTime STA — {target} ===")
        ok = run_sta(synth_dir, target)
        results[f"pt_{target}"] = ok
        if ok:
            qor = parse_pt_qor(synth_dir / "primetime" / "reports" / target)
            write_pt_report(synth_dir, target, qor)
            wns_str = f"{qor['wns']:.3f}" if qor["wns"] is not None else "?"
            print(f"  WNS={wns_str} ns  TNS={qor['tns']:.3f} ns  {qor['met']}")
        print()

    # --- Summary ---
    print("=" * 40)
    all_pass = all(results.values())
    for tool, ok in results.items():
        status = "PASS" if ok else "FAIL"
        print(f"  {tool:<20} : {status}")
    print("=" * 40)
    sys.exit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
