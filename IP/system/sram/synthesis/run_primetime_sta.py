#!/usr/bin/env python3
"""run_primetime_sta.py — PrimeTime STA for the sram IP (csun.edu only).

Static timing analysis of Design Compiler's gate-level netlists (all 24 per
PDK: base / opts / dp x 4 buses x SV / VHDL, see run_vendor_synth.py) at:
  - SAED90, SAED32, SAED14 — the single worst-case corner each EDK ships, with
    the same standard-cell and SRAM macro .db synth.tcl compiled against;
  - SKY130 — three standard-cell corners (ss_100C_1v60, tt_025C_1v80,
    ff_n40C_1v95), all against the one SKY130 netlist set (synthesized at
    ss_100C_1v60). The OpenRAM macros ship only TT 1.8 V 25 C, so every SKY130
    corner uses TT macro timing (user decision 2026-11-24): SS / FF results are
    approximate on any path that starts or ends at a macro pin.

Delays use the library wire-load model DC chose for each netlist (read from
DC's <variant>_timing.rpt, because synth.tcl picks it after writing the .sdc).
Setup and hold are both reported; with ideal clocks (no clock tree yet) hold
mostly checks clock-to-output against the macros' hold requirements.

PASS for a target: every netlist analysed, setup and hold met. SAED90 is an
accepted setup failure at 100 MHz (user decision 2026-11-25,
synthesis/known_issues.md); its report says FAIL with a pointer.

Usage:
    python3 synthesis/run_primetime_sta.py                 # all 6 targets
    python3 synthesis/run_primetime_sta.py --saed90        # one SAED target (--saed32, --saed14)
    python3 synthesis/run_primetime_sta.py --sky130        # SKY130, all 3 corners
    python3 synthesis/run_primetime_sta.py --ss            # one SKY130 corner (--tt, --ff)
    python3 synthesis/run_primetime_sta.py --jobs 2        # pt_shell runs in parallel (max 3)
    python3 synthesis/run_primetime_sta.py --report        # only rewrite the summaries
    python3 synthesis/run_primetime_sta.py --clean

Requirements: source IP/system/sram/setup.sh; pt_shell on PATH; DC netlists
(python3 synthesis/run_vendor_synth.py --dc).

Outputs:
    synthesis/primetime/pt_<target>_run.log
    synthesis/primetime/reports/<target>/<variant>_{timing,hold,constraint,qor,check}.rpt
    synthesis/primetime/report_sta_<target>.txt     (per-netlist WNS / TNS, setup and hold)
"""

import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_vendor_synth as rvs  # noqa: E402  (PDK paths, variants, DC report parsing)

build_sky130_libs = rvs.build_sky130_libs
build_saed32_sram_libs = rvs.build_saed32_sram_libs

PT_BIN = "pt_shell"
PT_TIMEOUT = 3600
MAX_JOBS = 3          # csun.edu: at most ~3 heavy EDA jobs at once

SAED_TARGETS = {
    "saed90": {
        "label": "SAED90 (90nm)",
        "desc": "saed90nm_max + SRAM*_max macros (the EDK's single corner)",
        "stdlib": f"{rvs.SAED90_PDK}/Digital_Standard_cell_Library/synopsys/models/saed90nm_max.db",
    },
    "saed32": {
        "label": "SAED32 (32nm)",
        "desc": "SS 0.95 V 125 C (worst case) + patched saed32sramlp SS macros",
        "stdlib": f"{rvs.SAED32_EDK}/lib/stdcell_rvt/db_nldm/saed32rvt_ss0p95v125c.db",
    },
    "saed14": {
        "label": "SAED14 (14nm)",
        "desc": "SS 0.72 V 125 C (worst case) + saed14sram SS macros",
        "stdlib": f"{rvs.SAED14_EDK}/SAED14nm_EDK_STD_RVT/liberty/nldm/base/saed14rvt_base_ss0p72v125c.db",
    },
}
SKY130_TARGETS = {
    "ss_100C_1v60": "worst case (synthesis corner)",
    "tt_025C_1v80": "typical",
    "ff_n40C_1v95": "best case",
}
ALL_TARGETS = list(SAED_TARGETS) + list(SKY130_TARGETS)

# Accepted failures (user decisions); the report still says FAIL.
STA_KNOWN_FAILURES = {
    "saed90": "100 MHz setup not met on SAED90 (user decision 2026-11-25), see synthesis/known_issues.md",
}

_RESULT_RE = re.compile(r"^STA_RESULT\s+(\S+)\s+(\S+)\s+(\S+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\d+)\s*$", re.M)
_WLM_RE = re.compile(r"Des/Clust/Port\s+Wire Load Model\s+Library\s*\n\s*-+\s*\n\s*(\S+)\s+(\S+)\s+(\S+)")


def is_sky130(target: str) -> bool:
    return target in SKY130_TARGETS


def netlist_pdk(target: str) -> str:
    return "sky130" if is_sky130(target) else target


def all_variants() -> list:
    return [(c, rvs.variant_name(p, c, lang)) for c in rvs.CFGS for lang in ("sv", "vhdl")
            for p in rvs.PROTOS]


# ---------------------------------------------------------------------------
# Libraries (the same files synth.tcl links)
# ---------------------------------------------------------------------------

def target_libs(target: str) -> Optional[tuple]:
    """(standard-cell .db, [macro .db]) for a target, or None."""
    if target == "saed90":
        macros = sorted(glob.glob(f"{rvs.SAED90_PDK}/Memories/synopsys/models/SRAM*_max.db"))
        return SAED_TARGETS[target]["stdlib"], macros
    if target == "saed32":
        db = build_saed32_sram_libs.ensure_saed32_sram_db("ss0p95v125c_i0p95v")
        return (SAED_TARGETS[target]["stdlib"], [db]) if db else None
    if target == "saed14":
        return (SAED_TARGETS[target]["stdlib"],
                [f"{rvs.SAED14_EDK}/SAED14nm_EDK_SRAM/liberty/nldm/saed14sram_ss0p72v125c.db"])
    dbs = build_sky130_libs.ensure_sky130_dbs(build_sky130_libs.SKY130_PDK)
    sram = build_sky130_libs.ensure_sky130_sram_dbs(build_sky130_libs.SKY130_PDK)
    if not dbs or not sram or target not in dbs:
        return None
    return dbs[target], list(sram)


def dc_wire_load(pdk: str, variant: str) -> str:
    """Wire-load model DC used for a netlist ("-" if the report has none)."""
    rpt = rvs.get_ip_path() / "synthesis" / "designcompiler" / "reports" / pdk / f"{variant}_timing.rpt"
    if rpt.exists():
        m = _WLM_RE.search(rpt.read_text())
        if m:
            return m.group(2)
    return "-"


# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

def run_sta(synth_dir: Path, target: str) -> bool:
    # A previous run's log would make the summary report stale results.
    (synth_dir / "primetime" / f"pt_{target}_run.log").unlink(missing_ok=True)
    pt_shell = shutil.which(PT_BIN)
    if not pt_shell:
        print(f"  ERROR: {PT_BIN} not found on PATH")
        return False
    pdk = netlist_pdk(target)
    net_dir = synth_dir / "designcompiler" / "netlists" / pdk
    if not any(net_dir.glob("*.v")):
        print(f"  ERROR: no {pdk} netlists at {net_dir}; run synthesis/run_vendor_synth.py --dc first")
        return False
    libs = target_libs(target)
    if not libs or not all(os.path.isfile(x) for x in [libs[0]] + libs[1]):
        print(f"  ERROR: libraries not available for target '{target}': {libs}")
        return False
    stdlib, macros = libs
    variants = [(v, dc_wire_load(pdk, v)) for _, v in all_variants()]
    pt_dir = synth_dir / "primetime"
    rpt_dir = pt_dir / "reports" / target
    if rpt_dir.exists():
        shutil.rmtree(rpt_dir)       # stale reports would hide a failed variant
    rpt_dir.mkdir(parents=True)
    log = pt_dir / f"pt_{target}_run.log"
    env = {**os.environ,
           "PT_TARGET": target, "PT_STDLIB": stdlib, "PT_MACROS": " ".join(macros),
           "PT_NET_DIR": str(net_dir), "PT_RPT_DIR": str(rpt_dir),
           "PT_VARIANTS": " ".join(f"{v}:{w}" for v, w in variants)}
    start = datetime.now()
    print(f"  [{start:%H:%M:%S}] start {target} ({len(variants)} netlists, {len(macros)} macro .db) -> {log.name}",
          flush=True)
    # Each target in its own work directory: parallel pt_shell runs must not
    # share pt_shell_command.log / .rce.
    work = pt_dir / "work" / target
    work.mkdir(parents=True, exist_ok=True)
    try:
        with open(log, "w") as fh:
            rc = subprocess.run([pt_shell, "-f", str(pt_dir / "sta.tcl")], stdout=fh,
                                stderr=subprocess.STDOUT, cwd=str(work), env=env,
                                timeout=PT_TIMEOUT).returncode
    except subprocess.TimeoutExpired:
        print(f"  ERROR: PrimeTime {target} timed out after {PT_TIMEOUT} s")
        return False
    mins = (datetime.now() - start).total_seconds() / 60
    print(f"  [{datetime.now():%H:%M:%S}] done {target} ({mins:.1f} min, exit {rc})", flush=True)
    return rc == 0


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

def parse_results(synth_dir: Path, target: str) -> dict:
    log = synth_dir / "primetime" / f"pt_{target}_run.log"
    res = {}
    if log.exists():
        for m in _RESULT_RE.finditer(log.read_text()):
            res[m.group(1)] = {"swns": float(m.group(2)), "stns": float(m.group(3)),
                               "snvp": int(m.group(4)), "hwns": float(m.group(5)),
                               "htns": float(m.group(6)), "hnvp": int(m.group(7))}
    return res


def write_report(synth_dir: Path, target: str) -> bool:
    res = parse_results(synth_dir, target)
    pdk = netlist_pdk(target)
    dc_rpt = synth_dir / "designcompiler" / "reports" / pdk
    rows = all_variants()
    ok = lambda r: r is not None and r["snvp"] == 0 and r["hnvp"] == 0  # noqa: E731
    n_ok = sum(ok(res.get(v)) for _, v in rows)
    all_ok = n_ok == len(rows)
    if is_sky130(target):
        tline = f"SKY130 (130nm) — standard cells {target} ({SKY130_TARGETS[target]})"
        mline = "OpenRAM sky130_sram_* at TT 1.8 V 25 C at every corner (only corner shipped)"
    else:
        tline = f"{SAED_TARGETS[target]['label']} — {SAED_TARGETS[target]['desc']}"
        mline = rvs.PDK_CONFIGS[pdk]["macros"]
    lines = [
        "=" * 104,
        "PrimeTime STA Report — sram IP",
        f"Target        : {tline}",
        f"SRAM macros   : {mline}",
        "Constraints   : DC's .sdc per netlist (100 MHz, 3.0 ns I/O delay; dp port B on clk_b);",
        "                ideal clocks; DC's wire-load model per netlist (no parasitics)",
        "Tool version  : PrimeTime (pt_shell)",
        f"Run date      : {datetime.now():%Y-%m-%d}",
        "=" * 104,
        "",
        f"STATUS: {'PASS' if all_ok else 'FAIL'} — {n_ok}/{len(rows)} netlists meet setup and hold.",
    ]
    if not all_ok and target in STA_KNOWN_FAILURES:
        lines.append(f"        Accepted known failure: {STA_KNOWN_FAILURES[target]}")
    if is_sky130(target) and target != "ss_100C_1v60":
        lines.append("        Approximate: macro timing is TT at this corner (synthesis/known_issues.md).")
    lines.append("")
    hdr = (f"  {'Netlist':<22} {'WLM':>8} {'DC WNS':>8} {'Setup WNS':>10} {'TNS':>10} {'NVP':>5} "
           f"{'Hold WNS':>9} {'TNS':>9} {'NVP':>5}  Result")
    for c in rvs.CFGS:
        lines += [f"Configuration {c}: {rvs.CFG_TEXT[c]}", hdr, "  " + "-" * 100]
        for cc, v in rows:
            if cc != c:
                continue
            r = res.get(v)
            dcw = rvs.parse_dc_variant(dc_rpt, v)["wns"] if target in (pdk, "ss_100C_1v60") else "-"
            wlm = dc_wire_load(pdk, v)
            if r is None:
                lines.append(f"  {v:<22} {wlm:>8} {dcw:>8} {'—':>10} {'':>10} {'':>5} {'':>9} {'':>9} {'':>5}  MISSING")
                continue
            lines.append(f"  {v:<22} {wlm:>8} {dcw:>8} {r['swns']:>+10.3f} {r['stns']:>10.3f} {r['snvp']:>5} "
                         f"{r['hwns']:>+9.3f} {r['htns']:>9.3f} {r['hnvp']:>5}  "
                         f"{'MET' if ok(r) else 'VIOLATED'}")
        lines.append("")
    lines += [
        "WNS / TNS in ns; NVP = violating endpoints. DC WNS = Design Compiler's worst slack for the",
        "same netlist (synthesis corner only), for correlation.",
        "",
        f"Per-netlist reports : synthesis/primetime/reports/{target}/",
        f"Full log            : synthesis/primetime/pt_{target}_run.log",
        "=" * 104,
    ]
    path = synth_dir / "primetime" / f"report_sta_{target}.txt"
    path.write_text("\n".join(lines) + "\n")
    print(f"  Report  : {path}  ({'PASS' if all_ok else 'FAIL'}, {n_ok}/{len(rows)})")
    return all_ok


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def clean(synth_dir: Path) -> None:
    pt = synth_dir / "primetime"
    for d in ("reports", "work"):
        if (pt / d).exists():
            shutil.rmtree(pt / d)
    for p in pt.glob("pt_*_run.log"):
        p.unlink()
    print("=== PrimeTime clean complete (report_sta_*.txt kept) ===")


def main() -> None:
    ap = argparse.ArgumentParser(description="PrimeTime STA for the sram IP (csun.edu only)")
    for t in SAED_TARGETS:
        ap.add_argument(f"--{t}", action="store_true", help=f"{t} only")
    ap.add_argument("--sky130", action="store_true", help="SKY130, all 3 corners")
    ap.add_argument("--ss", action="store_true", help="SKY130 ss_100C_1v60 only")
    ap.add_argument("--tt", action="store_true", help="SKY130 tt_025C_1v80 only")
    ap.add_argument("--ff", action="store_true", help="SKY130 ff_n40C_1v95 only")
    ap.add_argument("--jobs", type=int, default=3, help=f"pt_shell runs in parallel (max {MAX_JOBS})")
    ap.add_argument("--report", action="store_true", help="only rewrite report_sta_<target>.txt")
    ap.add_argument("--clean", action="store_true", help="remove PrimeTime outputs")
    args = ap.parse_args()
    synth_dir = rvs.get_ip_path() / "synthesis"

    if args.clean:
        clean(synth_dir)
        sys.exit(0)
    if not rvs.ON_CSUN:
        print("ERROR: PrimeTime STA is only available on csun.edu.")
        sys.exit(1)

    picked = [t for t in SAED_TARGETS if getattr(args, t)]
    picked += [t for t, flag in (("ss_100C_1v60", args.ss), ("tt_025C_1v80", args.tt),
                                 ("ff_n40C_1v95", args.ff)) if flag or args.sky130]
    targets = [t for t in ALL_TARGETS if t in picked] or ALL_TARGETS
    jobs = max(1, min(args.jobs, MAX_JOBS))

    print("sram IP — PrimeTime STA")
    print(f"  Targets : {' '.join(targets)}  (--jobs {jobs})")
    ran = {t: True for t in targets}
    if not args.report:
        # Build shared library caches once, before the threads start.
        for t in targets:
            target_libs(t)
        with ThreadPoolExecutor(max_workers=jobs) as ex:
            futs = {t: ex.submit(run_sta, synth_dir, t) for t in targets}
            for t, f in futs.items():
                try:
                    ran[t] = f.result()
                except Exception as e:  # a crashed job is a FAIL, not a lost summary
                    print(f"  ERROR: {t} job raised {type(e).__name__}: {e}")
                    ran[t] = False
    results = {t: write_report(synth_dir, t) and ran[t] for t in targets}

    print("=" * 40)
    for t, ok in results.items():
        note = " (accepted known failure)" if not ok and t in STA_KNOWN_FAILURES else ""
        print(f"  pt_{t:<18} : {'PASS' if ok else 'FAIL'}{note}")
    print("=" * 40)
    sys.exit(0 if all(results.values()) else 1)


if __name__ == "__main__":
    main()
