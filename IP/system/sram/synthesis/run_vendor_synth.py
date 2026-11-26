#!/usr/bin/env python3
"""run_vendor_synth.py — Run vendor synthesis for the sram IP.

Automatically detects the host environment and runs appropriate tools:
  - On standard hosts: Vivado, Quartus and Yosys
  - On *.csun.edu: Design Compiler with the SAED90/32/14 and SKY130 PDKs and
    each PDK's SRAM macro libraries

Configurations (plan §4 and Step 10 decisions, 2026-11-24), each on all four
buses (APB4, AHB-Lite, AXI4-Lite, Wishbone) in SV and in VHDL-2008:
  base  sram_<proto>     WIDTH 32, DEPTH 1024, BYTE_EN, PWR_GATE (RTL defaults)
  opts  sram_<proto>     base + ECC_EN, BANK_PG (2 banks), BIST_EN, READ_LATENCY 2
  dp    sram_<proto>_dp  opts + port B 8 bits wide on its own clock
                         (WIDTH_B 8, COMMON_CLK 0; SAED14: COMMON_CLK 1)
Design Compiler: 24 netlists per PDK, one dc_shell per PDK x configuration
(synthesis/designcompiler/synth.tcl), up to --jobs at a time.

STA (PrimeTime, csun.edu only) is a separate step — see
synthesis/run_primetime_sta.py.

Usage:
    python3 synthesis/run_vendor_synth.py              # run appropriate tools for host
    python3 synthesis/run_vendor_synth.py --vivado     # Vivado only (standard hosts)
    python3 synthesis/run_vendor_synth.py --quartus    # Quartus only (standard hosts)
    python3 synthesis/run_vendor_synth.py --yosys      # Yosys only (standard hosts)
    python3 synthesis/run_vendor_synth.py --dc         # Design Compiler all PDKs (csun.edu)
    python3 synthesis/run_vendor_synth.py --dc90 / --dc32 / --dc14 / --dcsky130
    python3 synthesis/run_vendor_synth.py --dc --cfg base   # one configuration
    python3 synthesis/run_vendor_synth.py --dc --jobs 2     # parallel dc_shell runs (default 3)
    python3 synthesis/run_vendor_synth.py --vivado --jobs 3 # parallel Vivado runs (also Quartus / Yosys)
    python3 synthesis/run_vendor_synth.py --quartus --cfg dp --proto apb --lang vhdl   # one netlist
    python3 synthesis/run_vendor_synth.py --report     # rewrite report_<pdk>.txt from existing reports
    python3 synthesis/run_vendor_synth.py --clean      # clean all tool outputs

Requirements:
    - CLAUDE_SRAM_PATH and IP_COMMON_PATH set (source IP/system/sram/setup.sh)
    - On csun.edu: dc_shell on PATH; lc_shell for sky130 (compiles the
      standard-cell and OpenRAM macro ASCII .lib to .db on first use; cached
      in IP/common/synthesis/designcompiler/sky130_lib/)

Outputs:
    synthesis/designcompiler/report_<pdk>.txt            — DC summary, one row per netlist
    synthesis/designcompiler/dc_<pdk>_<cfg>_run.log      — DC full log
    synthesis/designcompiler/reports/<pdk>/              — area, timing, QoR, reference, constraint
    synthesis/designcompiler/netlists/<pdk>/             — netlists + SDF + SDC
    synthesis/vivado/report.txt, synthesis/quartus/report.txt,
    synthesis/yosys/report.txt                           — FPGA / Yosys summaries
    synthesis/{vivado,quartus,yosys}/work/               — logs, reports, netlists per variant

Standard-host flows (24 netlists per tool: base / opts / dp x 4 buses x SV / VHDL):
    Vivado   xc7z010clg400-1, OOC, 100 MHz, TECH = XILINX (XPM): PASS = BRAM used, WNS >= 0
    Quartus  5CSEMA4U23C6, Analysis & Synthesis, TECH = ALTERA (altsyncram): PASS = block
             memory bits > 0. SV is read from SystemVerilog-2005 copies made by
             synthesis/quartus/quartus_sv.py (Quartus Lite rejects implicit generate
             regions, genvar in for headers and header localparams; the RTL is not changed).
    Yosys    generic cells, TECH = GENERIC: PASS = the array is inferred as memories.
             SV through the yosys-slang plugin, VHDL through the ghdl plugin (-frelaxed for
             the documented shared-variable dual-clock RAM).
"""

import argparse
import os
import re
import shutil
import socket
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path
from typing import Optional


def _hostname_fqdn() -> str:
    """Host FQDN (`hostname -f`, as setup.sh; getfqdn() can return the short name)."""
    try:
        out = subprocess.run(["hostname", "-f"], capture_output=True, text=True, timeout=5)
        if out.stdout.strip():
            return out.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        pass
    return socket.getfqdn()


ON_CSUN = _hostname_fqdn().endswith(".csun.edu")

SAED90_PDK = "/opt/ECE_Lib/SAED90nm_EDK_10072017/SAED90_EDK/SAED_EDK90nm"
SAED32_EDK = "/opt/ECE_Lib/SAED32_EDK"
SAED14_EDK = "/opt/ECE_Lib/SAED14nm_EDK_03_2025"

_IP_COMMON_PATH = os.environ.get("IP_COMMON_PATH") or str(
    Path(__file__).resolve().parent.parent.parent.parent / "common")
sys.path.insert(0, str(Path(_IP_COMMON_PATH) / "synthesis" / "designcompiler"))
import build_sky130_libs  # noqa: E402
import build_saed32_sram_libs  # noqa: E402

PDK_CONFIGS = {
    "saed90": {"label": "SAED90 (90nm)", "env_var": "SAED90_PDK", "path": SAED90_PDK,
               "macros": "SRAM<w>x<d>_1rw / SRAM<w>x<d> (_max .db per macro)"},
    "saed32": {"label": "SAED32 (32nm)", "env_var": "SAED32_EDK", "path": SAED32_EDK,
               "macros": "saed32sramlp_ss0p95v125c_i0p95v + SD/LS/DS pins (patched copy, SRAMLP1RW / SRAMLP2RW)"},
    "saed14": {"label": "SAED14 (14nm)", "env_var": "SAED14_EDK", "path": SAED14_EDK,
               "macros": "saed14sram_ss0p72v125c (SRAM1RW / SRAM2RW)"},
    "sky130": {"label": "SKY130 (130nm, SkyWater open-source PDK)", "env_var": "SKY130_PDK",
               "path": build_sky130_libs.SKY130_PDK,
               "macros": "OpenRAM sky130_sram_*_1rw1r_* at TT 1.8 V 25 C (only corner shipped)"},
}
PDKS = list(PDK_CONFIGS)
CFGS = ["base", "opts", "dp"]
PROTOS = ["apb", "ahb", "axi4l", "wb"]
CFG_TEXT = {
    "base": "WIDTH 32, DEPTH 1024, BYTE_EN, PWR_GATE",
    "opts": "base + ECC_EN, BANK_PG (2 banks), BIST_EN, READ_LATENCY 2",
    "dp":   "opts + WIDTH_B 8, COMMON_CLK 0 (SAED14: 1)",
}
# SRAM macro instance lines in a netlist ("SRAM8x1024_1rw u_prim ( ...")
MACRO_RE = re.compile(r"^(SRAM\w+|sky130_sram_\w+)\s+\S+\s*\(")
DC_TIMEOUT = 4 * 3600
# Per-variant reports written by synth.tcl (<variant>_<kind>.rpt)
DC_REPORTS = ("area", "timing", "qor", "ref", "constraint")


def variant_name(proto: str, cfg: str, lang: str) -> str:
    """Netlist / report base name (= top module of the netlist), as synth.tcl."""
    top = f"sram_{proto}_dp" if cfg == "dp" else f"sram_{proto}"
    return top + ("_opts" if cfg == "opts" else "") + ("_vhdl" if lang == "vhdl" else "")


# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------

def clean_design_compiler(synth_dir: Path) -> None:
    print("=== Cleaning Design Compiler outputs ===")
    dc_dir = synth_dir / "designcompiler"
    for d in ("work", "reports", "netlists"):
        if (dc_dir / d).exists():
            shutil.rmtree(dc_dir / d)
            print(f"  removed designcompiler/{d}/")
    for p in dc_dir.glob("dc_*_run.log"):
        p.unlink()
        print(f"  removed designcompiler/{p.name}")


def clean_fpga(synth_dir: Path) -> None:
    print("=== Cleaning Vivado / Quartus / Yosys outputs ===")
    for rel in ("vivado/work", "quartus/work", "yosys/work"):
        if (synth_dir / rel).exists():
            shutil.rmtree(synth_dir / rel)
            print(f"  removed {rel}/")


# ---------------------------------------------------------------------------
# Design Compiler
# ---------------------------------------------------------------------------

def dc_env(pdk: str) -> Optional[dict]:
    cfg = PDK_CONFIGS[pdk]
    if not cfg["path"] or not os.path.isdir(cfg["path"]):
        print(f"  ERROR: {cfg['label']} PDK not found at '{cfg['path']}'")
        return None
    env = {"PDK_TARGET": pdk, cfg["env_var"]: cfg["path"], "IP_COMMON_PATH": _IP_COMMON_PATH,
           "CLAUDE_SRAM_PATH": str(get_ip_path())}
    if pdk == "saed32":
        db = build_saed32_sram_libs.ensure_saed32_sram_db("ss0p95v125c_i0p95v")
        if not db:
            return None
        env["SAED32_SRAM_DB"] = db
    if pdk == "sky130":
        dbs = build_sky130_libs.ensure_sky130_dbs(cfg["path"])
        sram = build_sky130_libs.ensure_sky130_sram_dbs(cfg["path"])
        if not dbs or not sram:
            return None
        env["SKY130_STDLIB_DB"] = dbs[build_sky130_libs.SKY130_SYNTH_CORNER]
        env["SKY130_SRAM_DBS"] = " ".join(sram)
    return env


def run_dc_job(synth_dir: Path, dc_shell: str, pdk: str, cfg: str, env: dict,
               protos: list, langs: list) -> bool:
    dc_dir = synth_dir / "designcompiler"
    work = dc_dir / "work" / f"{pdk}_{cfg}"
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    log = dc_dir / f"dc_{pdk}_{cfg}_run.log"
    # Stale reports and netlists of this job's variants would hide a failed
    # run. Exact names only: a glob on "sram_apb_*" would also match the
    # opts / dp variants another job (thread) is writing at the same time.
    for proto in protos:
        for lang in langs:
            v = variant_name(proto, cfg, lang)
            for kind in DC_REPORTS:
                (dc_dir / "reports" / pdk / f"{v}_{kind}.rpt").unlink(missing_ok=True)
            for ext in ("v", "sdf", "sdc"):
                (dc_dir / "netlists" / pdk / f"{v}.{ext}").unlink(missing_ok=True)
    job_env = {**os.environ, **env, "SRAM_CFG": cfg, "SRAM_OUT_DIR": str(dc_dir),
               "SRAM_PROTOS": " ".join(protos), "SRAM_LANGS": " ".join(langs)}
    start = datetime.now()
    print(f"  [{start:%H:%M:%S}] start {pdk} {cfg} -> {log.name}", flush=True)
    try:
        with open(log, "w") as fh:
            rc = subprocess.run([dc_shell, "-f", str(dc_dir / "synth.tcl")], cwd=str(work),
                                stdout=fh, stderr=subprocess.STDOUT, env=job_env,
                                timeout=DC_TIMEOUT).returncode
    except subprocess.TimeoutExpired:
        print(f"  ERROR: {pdk} {cfg} timed out after {DC_TIMEOUT} s")
        return False
    mins = (datetime.now() - start).total_seconds() / 60
    text = log.read_text(errors="replace")
    ok = rc == 0 and "Synthesis complete" in text
    print(f"  [{datetime.now():%H:%M:%S}] {'done' if ok else 'FAIL'} {pdk} {cfg} "
          f"({mins:.1f} min, exit {rc})", flush=True)
    if not ok:
        for line in [l for l in text.splitlines() if l.startswith("Error")][:10]:
            print(f"    {line}")
    return ok


_AREA_RE  = re.compile(r"Total cell area:\s*([\d.]+)")
_MAREA_RE = re.compile(r"Macro/Black Box area:\s*([\d.]+)")
_CELLS_RE = re.compile(r"Number of cells:\s*(\d+)")
_SEQ_RE   = re.compile(r"Number of sequential cells:\s*(\d+)")
_SLACK_RE = re.compile(r"slack \((MET|VIOLATED)[^)]*\)\s+([-\d.]+)")


def parse_dc_variant(rpt_dir: Path, variant: str) -> dict:
    """Cells, FFs, area, macro count/area and worst slack of one netlist."""
    d = {"cells": "?", "ffs": "?", "area": "?", "marea": "?", "macros": "?", "wns": "?",
         "met": "MISSING"}
    area = rpt_dir / f"{variant}_area.rpt"
    if area.exists():
        text = area.read_text()
        for key, rx in (("cells", _CELLS_RE), ("ffs", _SEQ_RE), ("area", _AREA_RE),
                        ("marea", _MAREA_RE)):
            m = rx.search(text)
            if m:
                d[key] = m.group(1)
    netlist = rpt_dir.parent.parent / "netlists" / rpt_dir.name / f"{variant}.v"
    if netlist.exists():
        # SRAM macro instances in the written netlist (exact, whole hierarchy)
        d["macros"] = str(sum(1 for line in netlist.read_text().splitlines()
                              if MACRO_RE.match(line.strip())))
    timing = rpt_dir / f"{variant}_timing.rpt"
    if timing.exists():
        slacks = [(m.group(1), float(m.group(2))) for m in _SLACK_RE.finditer(timing.read_text())]
        if slacks:
            worst = min(slacks, key=lambda s: s[1])
            d["wns"], d["met"] = f"{worst[1]:+.2f}", worst[0]
    return d


# PDKs whose timing failure is accepted (user decision); the report still says
# FAIL and points at the explanation.
DC_KNOWN_FAILURES = {
    "saed90": "100 MHz not met on SAED90 (user decision 2026-11-25), see synthesis/known_issues.md",
}


def write_dc_report(synth_dir: Path, pdk: str) -> bool:
    """Write report_<pdk>.txt (24 rows). True if every netlist exists, meets
    timing and contains SRAM macros."""
    cfg = PDK_CONFIGS[pdk]
    rpt_dir = synth_dir / "designcompiler" / "reports" / pdk
    rows = []
    for c in CFGS:
        for lang in ("sv", "vhdl"):
            for proto in PROTOS:
                v = variant_name(proto, c, lang)
                rows.append((c, v, parse_dc_variant(rpt_dir, v)))
    ok_row = lambda r: r["met"] == "MET" and r["macros"] not in ("?", "0")  # noqa: E731
    all_ok = all(ok_row(r) for _, _, r in rows)
    lines = [
        "=" * 96,
        "Design Compiler Synthesis Report — sram IP",
        f"Target PDK    : {cfg['label']}",
        f"SRAM macros   : {cfg['macros']}",
        "Constraints   : 100 MHz bus clock(s); 3.0 ns input and output delay on every port;",
        "                dp: port B pins on clk_b, asynchronous to clk_a (SAED14: one clock)",
        "                compiled with a 0.2 ns setup margin (clock uncertainty, not in the .sdc):",
        "                WNS below includes it; synthesis/primetime/report_sta_*.txt has the real slack",
        "Tool version  : Design Compiler (dc_shell)",
        f"Run date      : {datetime.now():%Y-%m-%d}",
        "=" * 96,
        "",
        f"STATUS: {'PASS' if all_ok else 'FAIL'} — "
        f"{sum(ok_row(r) for _, _, r in rows)}/{len(rows)} netlists meet timing with SRAM macros.",
    ]
    if not all_ok and pdk in DC_KNOWN_FAILURES:
        lines.append(f"        Accepted known failure: {DC_KNOWN_FAILURES[pdk]}")
    lines += [
        "",
    ]
    for c in CFGS:
        lines += [f"Configuration {c}: {CFG_TEXT[c]}",
                  f"  {'Netlist':<24} {'Cells':>7} {'FFs':>6} {'Macros':>6} {'Macro area':>12} "
                  f"{'Total area':>12} {'WNS (ns)':>9}  Timing",
                  "  " + "-" * 92]
        for cc, v, r in rows:
            if cc == c:
                lines.append(f"  {v:<24} {r['cells']:>7} {r['ffs']:>6} {r['macros']:>6} "
                             f"{r['marea']:>12} {r['area']:>12} {r['wns']:>9}  {r['met']}")
        lines.append("")
    lines += [
        "Area is in the library's units (um^2 for SAED32/14 and SKY130). Total area includes the macros.",
        "Macros = SRAM macro instances counted in the netlist; 0 would mean the array was not mapped to macros.",
        "WNS is the worst slack among the 10 paths in each <netlist>_timing.rpt.",
        "",
        f"Per-netlist reports : synthesis/designcompiler/reports/{pdk}/",
        f"Netlists, SDF, SDC  : synthesis/designcompiler/netlists/{pdk}/",
        f"Full logs           : synthesis/designcompiler/dc_{pdk}_<cfg>_run.log",
        "=" * 96,
    ]
    path = synth_dir / "designcompiler" / f"report_{pdk}.txt"
    path.write_text("\n".join(lines) + "\n")
    print(f"  Report  : {path}  ({'PASS' if all_ok else 'FAIL'})")
    return all_ok


def run_design_compiler(synth_dir: Path, pdks: list, cfgs: list, jobs: int,
                        protos: list, langs: list) -> dict:
    dc_shell = shutil.which("dc_shell")
    if not dc_shell:
        print("  ERROR: dc_shell not found on PATH")
        return {f"dc_{p}": False for p in pdks}
    envs = {p: dc_env(p) for p in pdks}
    work = [(p, c) for p in pdks for c in cfgs if envs[p]]
    print(f"  {len(work)} dc_shell runs, {jobs} at a time")
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        futs = {(p, c): pool.submit(run_dc_job, synth_dir, dc_shell, p, c, envs[p], protos, langs)
                for p, c in work}
        done = {}
        for k, f in futs.items():
            try:
                done[k] = f.result()
            except Exception as e:  # noqa: BLE001 — one job's crash must not lose the others
                print(f"  ERROR: {k[0]} {k[1]} job raised {type(e).__name__}: {e}")
                done[k] = False
    results = {}
    for p in pdks:
        ran = envs[p] is not None and all(done.get((p, c), False) for c in cfgs)
        results[f"dc_{p}"] = write_dc_report(synth_dir, p) and ran
    return results


# ---------------------------------------------------------------------------
# Vivado / Quartus / Yosys (standard hosts): same 24 variants, one tool run each
# ---------------------------------------------------------------------------

# Compile order (dependencies first), as synth.tcl / sim_sram.py / lint_sram.py
SRAM_UNITS = [
    "sram_pkg", "sram_ecc_enc", "sram_ecc_dec",
    "sram_macro_generic", "sram_macro_saed90", "sram_macro_saed32", "sram_macro_saed14",
    "sram_macro_sky130", "sram_macro_xilinx", "sram_macro_altera",
    "sram_macro_dp_generic", "sram_macro_dp_saed90", "sram_macro_dp_saed32",
    "sram_macro_dp_saed14", "sram_macro_dp_sky130", "sram_macro_dp_xilinx",
    "sram_macro_dp_altera",
    "sram_macro", "sram_macro_dp", "sram_array", "sram_pwr_ctrl", "sram_clr", "sram_bist",
    "sram_port", "sram_cdc", "sram_core",
]
CLK_PORT = {"apb": "PCLK", "ahb": "HCLK", "axi4l": "ACLK", "wb": "CLK_I"}
OPTS = {"ECC_EN": 1, "BANK_PG": 1, "NUM_BANKS": 2, "BIST_EN": 1, "READ_LATENCY": 2}
TECH_NUM = {"generic": 0, "xilinx": 1, "altera": 2}
YOSYS = "/opt/oss-cad-suite/bin/yosys"
FPGA_TIMEOUT = 1800


def rtl_files(lang: str, proto: str, top: str) -> list:
    ext = "sv" if lang == "sv" else "vhd"
    sub = "verilog" if lang == "sv" else "vhdl"
    crtl = Path(_IP_COMMON_PATH) / "design" / "rtl" / sub
    rtl = get_ip_path() / "design" / "rtl" / sub
    files = [crtl / f"claude_sync.{ext}", crtl / f"claude_pulse_sync.{ext}",
             crtl / f"claude_{proto}_mem_if.{ext}"]
    files += [rtl / f"{u}.{ext}" for u in SRAM_UNITS]
    files.append(rtl / f"{top}.{ext}")
    return [str(f) for f in files]


def fpga_variants(tech: str, sel: Optional[dict] = None) -> list:
    """(name, top, lang, proto, cfg, generics dict, clk_a, clk_b); sel limits the
    configurations / buses / languages ({"cfg": [...], "proto": [...], "lang": [...]})."""
    sel = sel or {}
    out = []
    for cfg in sel.get("cfg") or CFGS:
        for lang in sel.get("lang") or ("sv", "vhdl"):
            for proto in sel.get("proto") or PROTOS:
                gen = {"TECH": TECH_NUM[tech]}
                if cfg in ("opts", "dp"):
                    gen.update(OPTS)
                clk_a, clk_b = CLK_PORT[proto], ""
                if cfg == "dp":
                    gen.update({"WIDTH_B": 8, "COMMON_CLK": 0})
                    clk_a, clk_b = f"A_{CLK_PORT[proto]}", f"B_{CLK_PORT[proto]}"
                top = f"sram_{proto}_dp" if cfg == "dp" else f"sram_{proto}"
                out.append((variant_name(proto, cfg, lang), top, lang, proto, cfg, gen,
                            clk_a, clk_b))
    return out


def fpga_env(work: Path, v: tuple) -> dict:
    name, top, lang, proto, _cfg, gen, clk_a, clk_b = v
    return {**os.environ, "SRAM_NAME": name, "SRAM_TOP": top, "SRAM_LANG": lang,
            "SRAM_FILES": " ".join(rtl_files(lang, proto, top)),
            "SRAM_GENERICS": " ".join(f"{k}={x}" for k, x in gen.items()),
            "SRAM_CLK_A": clk_a, "SRAM_CLK_B": clk_b, "SRAM_OUT_DIR": str(work)}


def run_tool(cmd: list, cwd: Path, env: dict, log: Path) -> int:
    try:
        with open(log, "w") as fh:
            return subprocess.run(cmd, cwd=str(cwd), env=env, stdout=fh,
                                  stderr=subprocess.STDOUT, timeout=FPGA_TIMEOUT).returncode
    except subprocess.TimeoutExpired:
        return 124
    except FileNotFoundError:
        return 127


def write_fpga_report(path: Path, title: str, cols: list, rows: list,
                      notes: Optional[list] = None) -> bool:
    ok = all(r[-1] == "PASS" for r in rows)
    w = [max(len(str(c)), *(len(str(r[i])) for r in rows)) for i, c in enumerate(cols)]
    lines = ["=" * 78, title, f"Run date : {datetime.now():%Y-%m-%d}", "=" * 78, "",
             f"STATUS: {'PASS' if ok else 'FAIL'} — {sum(r[-1] == 'PASS' for r in rows)}"
             f"/{len(rows)} variants", "",
             "  ".join(str(c).ljust(w[i]) for i, c in enumerate(cols)),
             "  ".join("-" * x for x in w)]
    lines += ["  ".join(str(c).ljust(w[i]) for i, c in enumerate(r)) for r in rows]
    lines += ["", "Configurations: " + "; ".join(f"{c} = {t}" for c, t in CFG_TEXT.items()),
              "(dp on FPGA: COMMON_CLK 0 on every variant.)"] + (notes or []) + ["=" * 78]
    path.write_text("\n".join(lines) + "\n")
    print(f"  Report  : {path}  ({'PASS' if ok else 'FAIL'})")
    return ok


def run_parallel(fn, variants: list, jobs: int) -> list:
    """fn(variant) -> row for every variant, up to jobs at a time, rows in variant order."""
    with ThreadPoolExecutor(max(1, jobs)) as ex:
        return list(ex.map(fn, variants))


def run_vivado(synth_dir: Path, sel: Optional[dict] = None, jobs: int = 1) -> bool:
    print("=== Vivado (Zynq-7010 xc7z010clg400-1, TECH = XILINX) ===")
    if not shutil.which("vivado"):
        print("  ERROR: vivado not found on PATH — is setup.sh sourced?")
        return False
    work = synth_dir / "vivado" / "work"
    work.mkdir(parents=True, exist_ok=True)

    def one(v):
        name = v[0]
        rc = run_tool(["vivado", "-mode", "batch", "-nojournal", "-nolog", "-source",
                       str(synth_dir / "vivado" / "synth.tcl")], work, fpga_env(work, v),
                      work / f"{name}_vivado.log")
        util = work / f"{name}_utilization.rpt"
        text = util.read_text() if util.exists() else ""
        get = lambda rx: (re.search(rx, text).group(1) if re.search(rx, text) else "?")  # noqa: E731
        luts = get(r"\|\s*Slice LUTs\*?\s*\|\s*(\d+)")
        ffs = get(r"\|\s*Slice Registers\s*\|\s*(\d+)")
        bram = get(r"\|\s*Block RAM Tile\s*\|\s*([\d.]+)")
        tim = work / f"{name}_timing_summary.rpt"
        m = re.search(r"WNS\(ns\).*\n\s*-+.*\n\s*([-\d.]+)", tim.read_text()) if tim.exists() else None
        wns = m.group(1) if m else "?"
        ok = rc == 0 and bram not in ("?", "0") and wns != "?" and float(wns) >= 0
        row = (name, luts, ffs, bram, wns, "PASS" if ok else "FAIL")
        print(f"  [Vivado] {name}: {row[-1]} (rc {rc}, BRAM {bram}, WNS {wns})", flush=True)
        return row

    rows = run_parallel(one, fpga_variants("xilinx", sel), jobs)
    return write_fpga_report(synth_dir / "vivado" / "report.txt",
                             "Vivado Synthesis Report — sram IP (xc7z010clg400-1, 100 MHz, TECH = XILINX)",
                             ["Netlist", "LUTs", "FFs", "BRAM tiles", "WNS (ns)", "Result"], rows)


def run_quartus(synth_dir: Path, sel: Optional[dict] = None, jobs: int = 1) -> bool:
    print("=== Quartus (Cyclone V SE 5CSEMA4U23C6, TECH = ALTERA) ===")
    if not shutil.which("quartus_sh"):
        print("  ERROR: quartus_sh not found on PATH — is setup.sh sourced?")
        return False
    work = synth_dir / "quartus" / "work"
    work.mkdir(parents=True, exist_ok=True)

    sys.path.insert(0, str(synth_dir / "quartus"))
    import quartus_sv  # noqa: E402  (SV-2005 form of the SV RTL for Quartus Lite)

    def one(v):
        name = v[0]
        env = fpga_env(work, v)
        if v[2] == "sv":
            env["SRAM_FILES"] = " ".join(quartus_sv.write_sources(
                env["SRAM_FILES"].split(), str(work / f"{name}_src")))
        rc = run_tool(["quartus_sh", "-t", str(synth_dir / "quartus" / "synth.tcl")], work,
                      env, work / f"{name}_quartus.log")
        rpts = list((work / name).glob("*.map.summary")) + list((work / name).glob("*.map.rpt"))
        text = "\n".join(r.read_text(errors="replace") for r in rpts)
        get = lambda rx: (re.search(rx, text).group(1).replace(",", "")  # noqa: E731
                          if re.search(rx, text) else "?")
        # Analysis & Synthesis only: the summary's ALM count is N/A before the
        # Fitter, so the map report's estimate is used.
        alms = get(r"Estimate of Logic utilization \(ALMs needed\)\s*;\s*([\d,]+)")
        regs = get(r"Total registers\s*[;:]\s*([\d,]+)")
        bits = get(r"Total block memory bits\s*[;:]\s*([\d,]+)")
        ok = rc == 0 and bits not in ("?", "0")
        row = (name, alms, regs, bits, "PASS" if ok else "FAIL")
        print(f"  [Quartus] {name}: {row[-1]} (rc {rc}, block memory bits {bits})", flush=True)
        return row

    rows = run_parallel(one, fpga_variants("altera", sel), jobs)
    return write_fpga_report(synth_dir / "quartus" / "report.txt",
                             "Quartus Synthesis Report — sram IP (5CSEMA4U23C6, TECH = ALTERA)",
                             ["Netlist", "ALMs (est.)", "Registers", "Block mem bits", "Result"], rows,
                             ["SV netlists are synthesized from the SystemVerilog-2005 copies "
                              "written by synthesis/quartus/quartus_sv.py",
                              "(work/<netlist>_src/; Quartus Lite needs explicit generate regions, "
                              "no genvar in for headers, no header localparams)."])


def run_yosys(synth_dir: Path, sel: Optional[dict] = None, jobs: int = 1) -> bool:
    """Generic Yosys synthesis (TECH = GENERIC): logic mapped, the array kept
    as one $mem cell per bank (memory -nomap) so the report shows it was
    inferred as a memory, not as flip-flops. SV through the yosys-slang plugin
    (the built-in Verilog frontend lacks SV constructs the RTL uses, e.g. ++
    in sram_pkg's constant functions), VHDL through the ghdl plugin; both ship
    with the OSS CAD Suite."""
    print("=== Yosys (generic, TECH = GENERIC) ===")
    if not os.access(YOSYS, os.X_OK):
        print(f"  ERROR: yosys not found at {YOSYS}")
        return False
    work = synth_dir / "yosys" / "work"
    work.mkdir(parents=True, exist_ok=True)

    def one(v):
        name, top, lang, proto, cfg, gen, _a, _b = v
        files = " ".join(rtl_files(lang, proto, top))
        if lang == "sv":
            gens = " ".join(f"-G {k}={x}" for k, x in gen.items())
            read = ["plugin -i slang", f"read_slang --top {top} {gens} {files}",
                    f"hierarchy -check -top {top}"]
        else:
            gens = " ".join(f"-g{k}={x}" for k, x in gen.items())
            # -frelaxed: the dual-clock RAM template is a plain shared variable
            # (documented deviation, verification/lint/waivers.md W5)
            read = ["plugin -i ghdl", f"ghdl --std=08 -frelaxed {gens} {files} -e {top}",
                    f"hierarchy -check -top {top}"]
        # VHDL dual port: the ghdl plugin gives the dual-clock RAM read ports
        # that Yosys' memory_collect rejects (kernel/mem.cc assert port.clk ==
        # wport.clk; Yosys 0.60). Its memories stay as unmerged $memrd / $memwr
        # (still memories: counted from stat's "memories" line), no memory pass,
        # and the netlist is written as RTLIL (write_verilog asserts the same way).
        unmerged = lang == "vhdl" and cfg == "dp"
        mem_pass = [] if unmerged else ["memory -nomap"]
        out = (f"write_rtlil {work / (name + '_synth.il')}" if unmerged
               else f"write_verilog -noattr {work / (name + '_synth.v')}")
        ys = work / f"{name}.ys"
        ys.write_text("\n".join(read + [
            "proc", "flatten", "opt -full"] + mem_pass + ["opt -full",
            "techmap", "opt -fast", "abc", "opt_clean", "stat", out]) + "\n")
        log = work / f"{name}_yosys.log"
        rc = run_tool([YOSYS, "-q", "-l", str(log.with_suffix('.stat')), str(ys)], work,
                      dict(os.environ), log)
        stat = log.with_suffix(".stat")
        text = stat.read_text(errors="replace") if stat.exists() else ""
        mems = sum(int(m.group(1)) for m in re.finditer(r"^\s+(\d+)\s+\$mem(?:_v2)?\s*$", text, re.M))
        mems += sum(int(m.group(1)) for m in re.finditer(r"^\s+(\d+)\s+memories\s*$", text, re.M))
        cells = re.findall(r"Number of cells:\s+(\d+)|^\s+(\d+)\s+cells\s*$", text, re.M)
        cells = [a or b for a, b in cells]
        ffs = sum(int(m.group(1)) for m in re.finditer(r"^\s+(\d+)\s+\$_S?DFF\w*\s*$", text, re.M))
        ok = rc == 0 and mems > 0
        row = (name, cells[-1] if cells else "?", ffs, mems, "PASS" if ok else "FAIL")
        print(f"  [Yosys] {name}: {row[-1]} (rc {rc}, $mem {mems})", flush=True)
        return row

    rows = run_parallel(one, fpga_variants("generic", sel), jobs)
    return write_fpga_report(synth_dir / "yosys" / "report.txt",
                             "Yosys Synthesis Report — sram IP (generic cells, TECH = GENERIC)",
                             ["Netlist", "Cells", "FFs", "Memories", "Result"], rows,
                             ["Memories = $mem cells, plus unmerged memories ($memrd / $memwr) "
                              "for the VHDL dual-port",
                              "netlists: Yosys 0.60 memory_collect / write_verilog assert on the "
                              "ghdl plugin's dual-clock RAM",
                              "(kernel/mem.cc port.clk == wport.clk), so those skip the memory "
                              "pass and are written as RTLIL (.il)."])


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def get_ip_path() -> Path:
    env = os.environ.get("CLAUDE_SRAM_PATH")
    return Path(env).resolve() if env else Path(__file__).resolve().parent.parent


def main() -> None:
    ap = argparse.ArgumentParser(description="Run synthesis for the sram IP (host-aware)")
    ap.add_argument("--vivado", action="store_true", help="Vivado only (standard hosts)")
    ap.add_argument("--quartus", action="store_true", help="Quartus only (standard hosts)")
    ap.add_argument("--yosys", action="store_true", help="Yosys only (standard hosts)")
    ap.add_argument("--dc", action="store_true", help="Design Compiler all PDKs (csun.edu)")
    ap.add_argument("--dc90", action="store_true", help="Design Compiler SAED90 only")
    ap.add_argument("--dc32", action="store_true", help="Design Compiler SAED32 only")
    ap.add_argument("--dc14", action="store_true", help="Design Compiler SAED14 only")
    ap.add_argument("--dcsky130", action="store_true", help="Design Compiler SKY130 only")
    ap.add_argument("--cfg", choices=CFGS, action="append",
                    help="configuration(s) to synthesize (default all)")
    ap.add_argument("--proto", choices=PROTOS, action="append",
                    help="bus(es) to synthesize (default all; debugging)")
    ap.add_argument("--lang", choices=["sv", "vhdl"], action="append",
                    help="language(s) to synthesize (default both; debugging)")
    ap.add_argument("--jobs", type=int, default=3,
                    help="parallel tool runs (default 3: csun has 8 CPUs / 15 GB; also Vivado / "
                         "Quartus / Yosys on a standard host)")
    ap.add_argument("--report", action="store_true",
                    help="only rewrite report_<pdk>.txt from the existing reports")
    ap.add_argument("--clean", action="store_true", help="remove outputs")
    args = ap.parse_args()

    synth_dir = get_ip_path() / "synthesis"
    print("sram IP — Vendor Synthesis")
    print(f"  Host      : {_hostname_fqdn()}{' (csun.edu)' if ON_CSUN else ' (standard host)'}")
    print(f"  Synth dir : {synth_dir}\n")

    if args.clean:
        clean_fpga(synth_dir)
        clean_design_compiler(synth_dir)
        sys.exit(0)

    pick = [("saed90", args.dc90), ("saed32", args.dc32), ("saed14", args.dc14),
            ("sky130", args.dcsky130)]
    dc_any = args.dc or any(f for _, f in pick)
    fpga_any = args.vivado or args.quartus or args.yosys
    if ON_CSUN:
        if fpga_any:
            print("ERROR: Vivado, Quartus and Yosys are not available on csun.edu.")
            sys.exit(1)
        dc_pdks = [p for p, f in pick if args.dc or f or not dc_any]
    else:
        if dc_any:
            print("ERROR: Design Compiler is only available on csun.edu.")
            sys.exit(1)
        dc_pdks = []

    results = {}
    if args.report:
        for p in dc_pdks:
            results[f"dc_{p}"] = write_dc_report(synth_dir, p)
    elif dc_pdks:
        print("=== Design Compiler ===")
        results.update(run_design_compiler(synth_dir, dc_pdks, args.cfg or CFGS,
                                           max(1, args.jobs), args.proto or PROTOS,
                                           args.lang or ["sv", "vhdl"]))
    if not ON_CSUN:
        run_all = not fpga_any
        sel = {"cfg": args.cfg, "proto": args.proto, "lang": args.lang}
        jobs = max(1, args.jobs)
        if run_all or args.vivado:
            results["vivado"] = run_vivado(synth_dir, sel, jobs)
        if run_all or args.quartus:
            results["quartus"] = run_quartus(synth_dir, sel, jobs)
        if run_all or args.yosys:
            results["yosys"] = run_yosys(synth_dir, sel, jobs)

    print("=" * 40)
    for tool, ok in results.items():
        print(f"  {tool:<20} : {'PASS' if ok else 'FAIL'}")
    print("=" * 40)
    sys.exit(0 if results and all(results.values()) else 1)


if __name__ == "__main__":
    main()
