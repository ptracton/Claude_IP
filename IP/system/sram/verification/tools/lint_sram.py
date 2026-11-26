#!/usr/bin/env python3
"""lint_sram.py — Lint runner for the sram IP (Step 8).

Host-aware, following lint_bus_matrix.py / lint_timer.py (.agents/lint.md):
  - csun.edu:      SpyGlass (spyglass_vc, goal lint/lint_rtl) on the SV RTL; VHDL is
                   SKIPPED (no VHDL-2008 path in SpyGlass, no GHDL; see
                   .agents/reference_spyglass_lint.md) and does not count as a failure.
  - standard host: Verilator --lint-only -Wall (SV) and GHDL -a --std=08 (VHDL).

CDC (csun.edu): SpyGlass cdc/cdc_verify_struct on the four dual-port tops with separate
clocks (*_dp_cdc), clocks and synchronous resets in a generated SGDC per project; only
warnings / errors count (crossings and constraint checks are reported as info).

What is linted (user decision 2026-11-23): every top-level with every option on,
since a reduced configuration only adds findings for the logic it switches off.
  all eight SV tops on GENERIC   ECC_EN, BANK_PG (2 banks), BIST_EN, READ_LATENCY 2;
                                 dual port: WIDTH_B 8, separate clocks (COMMON_CLK 0)
  sram_apb / sram_apb_dp on each PDK and FPGA technology, same options (SAED14 dual
                                 port: COMMON_CLK 1, its SRAM2RW has one write clock),
                                 so every macro leaf is elaborated; the vendor cells
                                 (SRAM*, sky130_sram_*, xpm_memory_*, altsyncram) are
                                 black boxes (port-only stubs: FPGA in verification/lint/
                                 stubs/, PDK generated from the wrappers into
                                 verification/work/lint_stubs/).
One SpyGlass project per configuration, each in its own directory
verification/lint/spyglass/<cfg>/ (written by this script) so parallel runs do not
share a vcst_rtdb. Pass/fail comes from each project's moresimple.rpt (the
spyglass_vc exit status is unreliable), minus translator noise (COM_OPT009/010,
PrjToTclSummary "Skipped option", "Please refer ..." pointer rows) and the black-box
notices of the vendor-cell stubs (InfoAnalyzeBBox, SM_BB_USER, UNMATCHED_BBNAME).

Usage:
  source IP/system/sram/setup.sh
  python3 $CLAUDE_SRAM_PATH/verification/tools/lint_sram.py [--lang sv|vhdl|all]
      [--cfg <name>|all] [--jobs N] [--list]

Results: verification/lint/lint_results.log (first line PASS / FAIL), one block per
configuration with its findings. Exit status 0 only when every configuration is clean.
Waivers: verification/lint/waivers.md (each one an RTL pragma).
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(_HERE, "..", "..", "..", "..", "common",
                                                 "verification", "tools")))
from ip_tool_base import ON_CSUN, get_ghdl_version, get_verilator_version  # noqa: E402

PROTOS = ["ahb", "apb", "axi4l", "wb"]
TECH_NUM = {"generic": 0, "xilinx": 1, "altera": 2, "saed90": 3, "saed32": 4, "saed14": 5,
            "sky130": 6}

# Compile order (dependencies first), as sim_sram.py
SRAM_RTL = [
    "sram_pkg", "sram_ecc_enc", "sram_ecc_dec",
    "sram_macro_generic", "sram_macro_saed90", "sram_macro_saed32", "sram_macro_saed14",
    "sram_macro_sky130", "sram_macro_xilinx", "sram_macro_altera",
    "sram_macro_dp_generic", "sram_macro_dp_saed90", "sram_macro_dp_saed32",
    "sram_macro_dp_saed14", "sram_macro_dp_sky130", "sram_macro_dp_xilinx",
    "sram_macro_dp_altera",
    "sram_macro", "sram_macro_dp", "sram_array", "sram_pwr_ctrl", "sram_clr", "sram_bist",
    "sram_port", "sram_cdc", "sram_core",
]

OPTS = {"ECC_EN": 1, "BANK_PG": 1, "NUM_BANKS": 2, "BIST_EN": 1, "READ_LATENCY": 2}
DP_OPTS = {"WIDTH_B": 8, "COMMON_CLK": 0}

SPYGLASS_BIN = "spyglass_vc"
SPYGLASS_GOAL = "lint/lint_rtl"
CDC_GOAL = "cdc/cdc_verify_struct"
# Clock / reset ports of the dual-port tops (all resets synchronous; WB active-high)
CDC_PINS = {"ahb": ("HCLK", "HRESETn", 0), "apb": ("PCLK", "PRESETn", 0),
            "axi4l": ("ACLK", "ARESETn", 0), "wb": ("CLK_I", "RST_I", 1)}
VERILATOR_BIN = "/opt/oss-cad-suite/bin/verilator"
GHDL_BIN = "/opt/oss-cad-suite/bin/ghdl"
RUN_TIMEOUT = 1800


def configs() -> list:
    """(name, top, proto, tech, params)."""
    out = []
    for p in PROTOS:
        out.append((f"{p}_generic", f"sram_{p}", p, "generic", dict(OPTS)))
        out.append((f"{p}_dp_generic", f"sram_{p}_dp", p, "generic", {**OPTS, **DP_OPTS}))
    for t in ["saed90", "saed32", "saed14", "sky130", "xilinx", "altera"]:
        out.append((f"apb_{t}", "sram_apb", "apb", t, {**OPTS, "TECH": TECH_NUM[t]}))
        dp = {**OPTS, **DP_OPTS, "TECH": TECH_NUM[t]}
        if t == "saed14":
            dp["COMMON_CLK"] = 1
        out.append((f"apb_dp_{t}", "sram_apb_dp", "apb", t, dp))
    # SpyGlass CDC (csun.edu): the dual-port tops with separate clocks, GENERIC
    # (the PDK cells are black boxes, so the core's crossings are the same).
    for p in PROTOS:
        out.append((f"{p}_dp_cdc", f"sram_{p}_dp", p, "generic", {**OPTS, **DP_OPTS}))
    return out


def is_cdc(name: str) -> bool:
    return name.endswith("_cdc")


def common_path(ip: str) -> str:
    return os.environ.get("IP_COMMON_PATH", os.path.normpath(os.path.join(ip, "..", "..",
                                                                          "common")))


def sv_files(ip: str, proto: str, top: str) -> list:
    crtl = os.path.join(common_path(ip), "design", "rtl", "verilog")
    rtl = os.path.join(ip, "design", "rtl", "verilog")
    files = [os.path.join(crtl, f) for f in
             ("claude_sync.sv", "claude_pulse_sync.sv", f"claude_{proto}_mem_if.sv")]
    files += [os.path.join(rtl, f"{m}.sv") for m in SRAM_RTL]
    files.append(os.path.join(rtl, f"{top}.sv"))
    return files


def stub_files(ip: str, tech: str) -> list:
    """Black-box declarations of the vendor cells: hand-written for the FPGA
    primitives (verification/lint/stubs/), generated from the wrappers for the
    PDK macros (verification/work/lint_stubs/, see gen_pdk_stubs)."""
    if tech == "generic":
        return []
    if tech in ("xilinx", "altera"):
        return [os.path.join(ip, "verification", "lint", "stubs", f"stubs_{tech}.sv")]
    return [gen_pdk_stubs(ip, tech)]


_INST_RE = re.compile(r"PrimW == (\d+) && PrimD == (\d+)\)\s*begin\s*:\s*\w+\s*"
                      r"(\w+)\s*(?:#\((.*?)\))?\s*u_prim\s*\((.*?)\);", re.S)


def gen_pdk_stubs(ip: str, tech: str) -> str:
    """Port-only stubs of the PDK SRAM cells a wrapper instantiates, built from
    our own RTL only (no vendor file content): the cell names and port names
    from the instantiations in sram_macro[_dp]_<tech>.sv, the widths from the
    `PrimW == w && PrimD == d` branch around each one (address ports
    clog2(d), data ports w, sky130 wmask w/8, the rest 1 bit), outputs
    O / O1 / O2 / dout0 / dout1. Written to verification/work/lint_stubs/."""
    rtl = os.path.join(ip, "design", "rtl", "verilog")
    cells = {}
    for f in (f"sram_macro_{tech}.sv", f"sram_macro_dp_{tech}.sv"):
        with open(os.path.join(rtl, f)) as fh:
            text = re.sub(r"//[^\n]*", "", fh.read())
        for m in _INST_RE.finditer(text):
            w, d, mod, prm, conns = int(m.group(1)), int(m.group(2)), m.group(3), m.group(4), m.group(5)
            ports = re.findall(r"\.(\w+)\s*\(", conns)
            params = re.findall(r"\.(\w+)\s*\(", prm or "")
            cells[mod] = (w, d, ports, params)
    out_dir = os.path.join(ip, "verification", "work", "lint_stubs")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"stubs_{tech}.sv")
    lines = [f"// Generated by lint_sram.py: port-only black boxes of the {tech.upper()} SRAM cells",
             "// (from the wrapper instantiations; lint only, not a model).", ""]
    for mod, (w, d, ports, params) in sorted(cells.items()):
        aw = max(1, (d - 1).bit_length())
        hdr = f"module {mod}"
        if params:
            hdr += " #(" + ", ".join(f"parameter {p} = 0" for p in params) + ")"
        decl = []
        for p in ports:
            if re.fullmatch(r"A\d?|addr\d", p):
                rng = f"[{aw - 1}:0] "
            elif re.fullmatch(r"I\d?|O\d?|din\d|dout\d", p):
                rng = f"[{w - 1}:0] "
            elif re.fullmatch(r"wmask\d", p):
                rng = f"[{max(1, w // 8) - 1}:0] "
            else:
                rng = ""
            dirn = "output" if re.fullmatch(r"O\d?|dout\d", p) else "input "
            decl.append(f"  {dirn} wire {rng}{p}")
        lines += [hdr + " (", ",\n".join(decl), ");", "endmodule", ""]
    with open(path, "w") as fh:
        fh.write("\n".join(lines))
    return path


def vhdl_files(ip: str) -> list:
    crtl = os.path.join(common_path(ip), "design", "rtl", "vhdl")
    rtl = os.path.join(ip, "design", "rtl", "vhdl")
    files = [os.path.join(crtl, f) for f in ("claude_sync.vhd", "claude_pulse_sync.vhd")]
    files += [os.path.join(crtl, f"claude_{p}_mem_if.vhd") for p in PROTOS]
    files += [os.path.join(rtl, f"{m}.vhd") for m in SRAM_RTL]
    files += [os.path.join(rtl, f"sram_{p}{s}.vhd") for p in PROTOS for s in ("", "_dp")]
    return files


def safe_jobs(req: int) -> int:
    """At most 3 heavy jobs (csun.edu: 8 CPUs / 15 GB; ~1.8 GB per SpyGlass run)."""
    n = max(1, min(req, 3))
    try:
        with open("/proc/meminfo") as fh:
            for ln in fh:
                if ln.startswith("MemAvailable:"):
                    gb = int(ln.split()[1]) / 1e6
                    n = max(1, min(n, int(gb // 2.5)))
    except OSError:
        pass
    return n


# ---------------------------------------------------------------------------
# SpyGlass
# ---------------------------------------------------------------------------
_ROW_RE = re.compile(r"^\[\w+\]\s+(\S+)\s+\S+\s+(fatal|error|warning|info)\s+(\S+)\s+(\S+)"
                     r"\s+\S+\s+(.*)$", re.IGNORECASE)
_BENIGN_RULES = {"COM_OPT009", "COM_OPT010"}
# Black-box bookkeeping of the vendor-cell stubs (`set_option stop`): which
# stubs were used (InfoAnalyzeBBox, SM_BB_USER) or not (UNMATCHED_BBNAME).
_STUB_RULES = {"InfoAnalyzeBBox", "SM_BB_USER", "UNMATCHED_BBNAME"}
# CDC info rows reviewed 2026-11-23 (lint/waivers.md "CDC report filter"): recognised
# synchronized crossings, constraint / clock / reset bookkeeping. Any other CDC info
# rule counts as a finding until it has been reviewed and added here.
_CDC_INFO_RULES = {"Ac_sync02", "Setup_port01", "Reset_info01", "Clock_info03b",
                   "Propagate_Clocks", "Clock_info01", "Reset_check12"}


def write_prj(ip: str, cfg: tuple) -> str:
    name, top, proto, tech, params = cfg
    d = os.path.join(ip, "verification", "lint", "spyglass", name)
    os.makedirs(d, exist_ok=True)
    files = [os.path.relpath(f, d) for f in stub_files(ip, tech) + sv_files(ip, proto, top)]
    prm = " ".join(f"{top}.{k}={v}" for k, v in params.items())
    prj = os.path.join(d, f"{name}.prj")
    goal, app = (CDC_GOAL, "cdc") if is_cdc(name) else (SPYGLASS_GOAL, "lint")
    if is_cdc(name):
        clk, rst, pol = CDC_PINS[proto]
        with open(os.path.join(d, f"{name}.sgdc"), "w") as fh:
            fh.write(f"# Clocks and resets of {top} for SpyGlass CDC (written by lint_sram.py).\n"
                     "# Ports A and B on separate, unrelated clocks (COMMON_CLK = 0); both\n"
                     "# resets synchronous (the IP has no asynchronous reset).\n"
                     f"current_design {top}\n"
                     f"clock -name A_{clk} -domain dom_a -period 10\n"
                     f"clock -name B_{clk} -domain dom_b -period 13.7\n"
                     f"reset -name A_{rst} -value {pol} -sync\n"
                     f"reset -name B_{rst} -value {pol} -sync\n")
    with open(prj, "w") as fh:
        fh.write(f"# SpyGlass {app} project {name}: {top}, TECH {tech.upper()}, all options.\n"
                 "# Written by verification/tools/lint_sram.py (do not edit); run from this\n"
                 f"# directory: spyglass_vc -project {name}.prj -goal {goal} "
                 f"-batch -app {app}\n\n")
        fh.write("set_option projectwdir .\nset_option enableSV yes\n")
        fh.write(f"set_option top {top}\n")
        fh.write(f"set_option param {{{prm}}}\n")
        if tech != "generic":
            fh.write("# vendor cells: port-only stubs, not linted\n")
            fh.write(f"set_option stop {{{' '.join(stub_modules(ip, tech))}}}\n")
        fh.write("read_file -type verilog { \\\n")
        for f in files:
            fh.write(f"  {f} \\\n")
        fh.write("}\n")
        if is_cdc(name):
            fh.write(f"read_file -type sgdc {name}.sgdc\n")
    return d


def stub_modules(ip: str, tech: str) -> list:
    mods = []
    for f in stub_files(ip, tech):
        with open(f) as fh:
            mods += re.findall(r"^\s*module\s+(\w+)", fh.read(), re.M)
    return mods


def parse_moresimple(path: str, cdc: bool = False) -> tuple:
    """(real, benign) rows. CDC runs report every synchronized crossing and
    constraint check as info; only the reviewed info rules (_CDC_INFO_RULES)
    are dropped, any other CDC row counts."""
    real, benign = [], []
    with open(path, errors="replace") as fh:
        for ln in fh:
            m = _ROW_RE.match(ln.rstrip("\n"))
            if not m:
                continue
            rule, sev, fpath, line, msg = (m.group(1), m.group(2).lower(), m.group(3),
                                           m.group(4), m.group(5).strip())
            row = f"{sev:<8} {rule:<16} {os.path.basename(fpath)}:{line}  {msg}"
            if (rule in _BENIGN_RULES or (rule in _STUB_RULES and stub_row(msg, fpath))
                    or (rule == "PrjToTclSummary" and "Skipped option" in msg)
                    or msg.startswith("Please refer") or "/lint/stubs/" in fpath
                    or (cdc and sev == "info" and rule in _CDC_INFO_RULES)
                    # CDC: SpyGlass counts only asynchronous resets as "Resets";
                    # the IP's resets are synchronous (declared -sync in the SGDC).
                    or (cdc and rule == "Setup_clockreset01" and "'Resets'" in msg)):
                benign.append(row)
            else:
                real.append(row)
    return real, benign


def stub_row(msg: str, fpath: str) -> bool:
    """A black-box notice about a vendor-cell stub, not about the sram RTL."""
    return ("stubs" in fpath or "blackbox" in msg or "Stop applied" in msg)


def run_spyglass(ip: str, cfg: tuple) -> tuple:
    name, top = cfg[0], cfg[1]
    d = write_prj(ip, cfg)
    for junk in ("vcst_rtdb", "vcst_rtdb.bak"):
        shutil.rmtree(os.path.join(d, junk), ignore_errors=True)
    goal, app = (CDC_GOAL, "cdc") if is_cdc(name) else (SPYGLASS_GOAL, "lint")
    cmd = [SPYGLASS_BIN, "-project", f"{name}.prj", "-goal", goal, "-batch", "-app", app]
    try:
        r = subprocess.run(cmd, cwd=d, capture_output=True, text=True, timeout=RUN_TIMEOUT)
        out = r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        return name, False, [f"timeout after {RUN_TIMEOUT} s"], 0
    with open(os.path.join(d, "spyglass.out"), "w") as fh:
        fh.write(out)
    rpt = os.path.join(d, "vcst_rtdb", "spyglass", name, top, *goal.split("/"),
                       "spyglass_reports", "moresimple.rpt")
    if not os.path.isfile(rpt):
        tail = out.strip().splitlines()[-15:]
        return name, False, [f"no moresimple.rpt (rc={r.returncode})"] + tail, 0
    real, benign = parse_moresimple(rpt, is_cdc(name))
    return name, not real, real, len(benign)


def lint_spyglass(ip: str, cfgs: list, jobs: int) -> tuple:
    det = [f"[SV] SpyGlass: {shutil.which(SPYGLASS_BIN) or SPYGLASS_BIN}, goals {SPYGLASS_GOAL} "
           f"(*_cdc: {CDC_GOAL})"]
    ok_all = True
    with ThreadPoolExecutor(max_workers=safe_jobs(jobs)) as ex:
        futs = {c[0]: ex.submit(run_spyglass, ip, c) for c in cfgs}
        for c in cfgs:
            name, ok, real, nben = futs[c[0]].result()
            ok_all &= ok
            st = "PASS" if ok else "FAIL"
            det.append(f"[SV] {st} {name:<16} {c[1]:<14} TECH {c[3]:<8} "
                       f"{len(real)} finding(s), {nben} benign filtered")
            det += [f"       {r}" for r in real]
            print("\n".join(det[-1 - len(real):]), flush=True)
    return ok_all, det


# ---------------------------------------------------------------------------
# Standard host: Verilator / GHDL
# ---------------------------------------------------------------------------
def lint_verilator(ip: str, cfgs: list) -> tuple:
    det = [f"[SV] Verilator: {get_verilator_version(VERILATOR_BIN)}"]
    ok_all = True
    crtl = os.path.join(common_path(ip), "design", "rtl", "verilog")
    flags = os.path.join(ip, "verification", "lint", "verilator.flags")
    vlt = os.path.join(ip, "verification", "lint", "verilator_waivers.vlt")
    for name, top, proto, tech, params in cfgs:
        if is_cdc(name):
            det.append(f"[SV] SKIPPED {name} (SpyGlass CDC: csun.edu only)")
            continue
        cmd = [VERILATOR_BIN, "--lint-only", "-f", flags, vlt, f"-I{crtl}", "--top-module", top]
        cmd += [f"-G{k}={v}" for k, v in params.items()]
        cmd += stub_files(ip, tech) + sv_files(ip, proto, top)
        r = subprocess.run(cmd, cwd=ip, capture_output=True, text=True)
        out = [ln for ln in (r.stdout + r.stderr).splitlines()
               if ln.lstrip().startswith(("%Warning", "%Error"))]
        ok = r.returncode == 0 and not out
        ok_all &= ok
        det.append(f"[SV] {'PASS' if ok else 'FAIL'} {name:<16} {top:<14} TECH {tech}")
        det += [f"       {ln}" for ln in out]
    return ok_all, det


# GHDL waivers (waivers.md "VHDL (GHDL, standard hosts)"): (file, message regex, class).
# Only the matching diagnostic line is dropped; anything else in the file still fails.
_GHDL_WAIVERS = [
    # W5: the dual-clock true dual-port RAM template is a plain shared variable
    # (VHDL-93 style; Vivado / Quartus infer block RAM from it, a protected type
    # would not). Analysed with -frelaxed, which turns the 2008 error into this warning.
    ("sram_macro_dp_generic.vhd", r"type of a shared variable must be a protected type", "W5"),
    # W7: byte_size_of(w, nlanes) parameters shadow the generics W / NLANES of the
    # same name (the function is called with exactly those generics).
    ("sram_macro_altera.vhd", r'declaration of "(w|nlanes)" hides generic', "W7"),
    ("sram_macro_dp_altera.vhd", r'declaration of "(w|nlanes)" hides generic', "W7"),
]
_GHDL_DIAG = re.compile(r"^(?P<file>[^:\s]+\.vhdl?):\d+:\d+:(?P<kind>warning|error|note):\s*(?P<msg>.*)$")


def ghdl_findings(fname: str, out: str) -> tuple:
    """(findings, waived count) of one GHDL analysis: diagnostics minus the waivers."""
    real, waived = [], 0
    for ln in out.splitlines():
        m = _GHDL_DIAG.match(ln.strip())
        if not m:
            if re.search(r"ghdl:error", ln):
                real.append(ln.strip())
            continue
        if m.group("kind") == "note" and "-frelaxed" in m.group("msg"):
            continue
        if any(os.path.basename(m.group("file")) == wf and re.search(rx, m.group("msg"))
               for wf, rx, _ in _GHDL_WAIVERS):
            waived += 1
            continue
        real.append(ln.strip())
    return real, waived


def lint_ghdl(ip: str) -> tuple:
    det = [f"[VHDL] GHDL: {get_ghdl_version(GHDL_BIN)}"]
    work = os.path.join(ip, "verification", "work", "ghdl_lint")
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    ok_all = True
    for f in vhdl_files(ip):
        name = os.path.basename(f)
        relaxed = ["-frelaxed"] if any(w[0] == name for w in _GHDL_WAIVERS[:1]) else []
        r = subprocess.run([GHDL_BIN, "-a", "--std=08", *relaxed, f"--workdir={work}", f],
                           cwd=ip, capture_output=True, text=True)
        real, waived = ghdl_findings(name, r.stdout + r.stderr)
        ok = r.returncode == 0 and not real
        ok_all &= ok
        det.append(f"[VHDL] {'PASS' if ok else 'FAIL'} {name}"
                   + (f"  ({waived} waived)" if waived else ""))
        det += [f"       {ln}" for ln in real]
    return ok_all, det


# ---------------------------------------------------------------------------
def main() -> int:
    ip = os.environ.get("CLAUDE_SRAM_PATH")
    if not ip:
        print("ERROR: CLAUDE_SRAM_PATH is not set.")
        print("       Please run:  source IP/system/sram/setup.sh")
        return 1
    all_cfgs = configs()
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lang", choices=["sv", "vhdl", "all"], default="all")
    ap.add_argument("--cfg", choices=[c[0] for c in all_cfgs] + ["all"], default="all")
    ap.add_argument("--jobs", type=int, default=3, help="parallel SpyGlass runs (max 3)")
    ap.add_argument("--list", action="store_true", help="list the configurations")
    args = ap.parse_args()
    if args.list:
        for name, top, _, tech, params in all_cfgs:
            print(f"{name:<16} {top:<14} {tech:<8} " +
                  " ".join(f"{k}={v}" for k, v in params.items()))
        return 0
    cfgs = all_cfgs if args.cfg == "all" else [c for c in all_cfgs if c[0] == args.cfg]

    stamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    host = "csun.edu" if ON_CSUN else "standard host"
    det = [f"lint_sram.py {stamp} ({host}), --lang {args.lang}, --cfg {args.cfg}"]
    ok = True
    if args.lang in ("sv", "all"):
        o, d = lint_spyglass(ip, cfgs, args.jobs) if ON_CSUN else lint_verilator(ip, cfgs)
        ok &= o
        det += d
    if args.lang in ("vhdl", "all"):
        if ON_CSUN:
            det += ["[VHDL] SKIPPED — no VHDL lint on csun.edu: GHDL is not installed and",
                    "[VHDL] SpyGlass has no VHDL-2008 path (.agents/reference_spyglass_lint.md)."]
        else:
            o, d = lint_ghdl(ip)
            ok &= o
            det += d
    log = os.path.join(ip, "verification", "lint", "lint_results.log")
    os.makedirs(os.path.dirname(log), exist_ok=True)
    with open(log, "w") as fh:
        fh.write(("PASS" if ok else "FAIL") + "\n" + "\n".join(det) + "\n")
    print("\n".join(ln for ln in det if not ln.startswith(("[SV] PASS", "[SV] FAIL", "       "))))
    print(f"\nResult: {'PASS' if ok else 'FAIL'} -> {log}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
