#!/usr/bin/env python3
"""sim_sram.py — Directed-simulation runner for the sram IP.

Runs the system testbench (verification/testbench/tb_sram_<proto>.sv: the
SRAMs behind IP/interface/bus_matrix) on one or more technologies. Follows
the timer's sim_timer.py conventions.

Implemented (Step 4):
    proto                lang       simulators
    ahb, apb, axi4l, wb  sv, vhdl   vcs, xcelium (csun.edu)
    ahb, apb, axi4l, wb  sv         verilator (standard hosts; GENERIC unless
                                    the PDK models are installed)
    ahb, apb, axi4l, wb  sv, vhdl   xsim (standard hosts, Vivado): GENERIC and the
                                    FPGA leaves, XILINX (XPM) and ALTERA (altera_mf)
--lang vhdl runs the same SV bench (BFMs, tests, reference models) around the
VHDL top-levels and the VHDL bus_matrix (+define+VHDL_DUT, mixed language).
Every other protocol / language / simulator combination is reported as FAIL
with "not implemented yet", so a regression never mistakes it for a pass.

Technology (--tech): generic, saed90, saed32, saed14, sky130, xilinx, altera,
or all (vcs / xcelium / verilator: generic and the four PDKs; xsim: generic,
xilinx, altera). PDK runs compile the vendor SRAM macro models through
IP/common/verification/tools/pdk_sram_models.py. GENERIC also runs the
backdoor tests (IP/common/verification/dpi/claude_backdoor.c).

xsim (Vivado simulator, standard hosts): the same SV bench, with the VHDL tops
for --lang vhdl (mixed language). xsim has no VPI / VHPI and cannot write a
VHDL object from SV, so the backdoor bit flips (TB_NO_BACKDOOR) and, with a
VHDL DUT, the read-path stuck-bit faults (BF_OK = 0) report SKIPPED; the
reference models check every response as on the other simulators. XILINX
elaborates xpm_memory_* from Vivado's precompiled xpm library; ALTERA compiles
Quartus' altera_mf model (Verilog for an SV DUT, VHDL for a VHDL DUT) from
$QUARTUS_PATH/../eda/sim_lib. XILINX with a VHDL DUT is SKIP: the XPM model
forces its read data, and xsim does not support a force on a port connected
to VHDL (XSIM 43-4289); Vivado synthesis covers that leaf
(synthesis/run_vendor_synth.py --vivado).

Results:
    ${CLAUDE_SRAM_PATH}/verification/work/<sim>/<proto>_<lang>_<tech>/{compile,sim,results}.log
    ${CLAUDE_SRAM_PATH}/verification/work/results.log   (one line per run, overall status first)

Usage:
    python3 sim_sram.py                                   # vcs, ahb, sv, generic
    python3 sim_sram.py --sim all --proto all --tech all --jobs 8   # everything, 8 at a time
    python3 sim_sram.py --sim xcelium --tech sky130 --test ecc
    python3 sim_sram.py --waves                           # VCS: vcdplus.vpd, Xcelium: waves.shm
    python3 sim_sram.py --proto all --tech all --coverage --jobs 8   # VCS coverage, merged
    python3 sim_sram.py --lang all --proto all --tech all --sim all --coverage --jobs 10
                                                          # everything (80 runs)
    python3 sim_sram.py --sim xsim --lang all --proto all --tech all --jobs 4
                                                          # standard host: 24 xsim runs
VHDL coverage also runs the SV twin of each run: VCS filters constants out of
VHDL line/condition coverage but not toggle, so the SV twin's Unreachable bits
are excluded from the VHDL toggle (see "VHDL toggle constants" below).
Tests (--test): all, reset, params, access, burst, pipeline, contention, ecc,
power, clear, bist, dp, resetbusy.

Gate-level (--postsyn, Step 10): the three DC netlists of each bus (base,
opts, dp; synthesis/run_vendor_synth.py) with SDF, the vendor SRAM macro
models and the standard-cell models, in tb_sram_<proto> with
+define+SRAM_POSTSYN (testbench/sram_tb_postsyn_body.svh). --lang picks the
netlists synthesized from SV or from VHDL. VCS, csun.edu only:
    python3 sim_sram.py --postsyn --proto all --lang all --pdk all --jobs 3
    -> verification/work/postsyn/<proto>_<lang>_<pdk>/, postsyn/results.log
SAED90 runs are reported as KNOWN (accepted timing failure); --no-sdf runs
the same netlists with zero-delay gates (a timing failure passes there).

Power (--power, Step 12): the same gate-level runs with +saif (one backward
SAIF per netlist), then PrimePower per netlist at the typical corner:
    python3 sim_sram.py --power --proto all --pdk all --jobs 3
    -> verification/work/power/<proto>_<lang>_<pdk>/power/<netlist>/, power/results.log
SAED90 is SKIP; a negative macro share (SAED32-LP liberty) is reported as invalid.
"""

import argparse
import concurrent.futures
import datetime
import os
import shutil
import socket
import subprocess
import sys


# ---------------------------------------------------------------------------
# Host detection (same as sim_timer.py)
# ---------------------------------------------------------------------------
def _hostname_fqdn() -> str:
    """Host FQDN: `hostname -f` first (reverse DNS is unreliable on csun.edu)."""
    try:
        out = subprocess.run(["hostname", "-f"], capture_output=True, text=True, timeout=5)
        fqdn = out.stdout.strip()
        if fqdn:
            return fqdn
    except (OSError, subprocess.TimeoutExpired):
        pass
    return socket.getfqdn()


ON_CSUN = _hostname_fqdn().endswith(".csun.edu")
_CSUN_BLOCKED = {"verilator", "icarus", "ghdl", "modelsim", "xsim"}


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
def get_sram_path() -> str:
    """sram IP root: CLAUDE_SRAM_PATH, else derived from this file's location."""
    path = os.environ.get("CLAUDE_SRAM_PATH")
    if path:
        return path
    detected = os.path.normpath(
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    print(f"INFO: CLAUDE_SRAM_PATH not set — using auto-detected path: {detected}")
    print("      Run 'source setup.sh' to suppress this message.")
    return detected


def get_common_path(sram_path: str) -> str:
    return os.environ.get("IP_COMMON_PATH") or os.path.normpath(
        os.path.join(sram_path, "..", "..", "common"))


SUPPORTED_PROTOS = ["ahb", "apb", "axi4l", "wb"]
SUPPORTED_LANGS = ["sv", "vhdl"]
SUPPORTED_TECHS = ["generic", "saed90", "saed32", "saed14", "sky130"]
FPGA_TECHS = ["xilinx", "altera"]           # vendor RAM leaves: xsim only
XSIM_TECHS = ["generic"] + FPGA_TECHS
SUPPORTED_TESTS = ["all", "reset", "params", "access", "burst", "pipeline", "contention",
                   "ecc", "power", "clear", "bist", "dp", "resetbusy"]

# sram_pkg::TECH_* values
TECH_NUM = {"generic": 0, "xilinx": 1, "altera": 2, "saed90": 3, "saed32": 4, "saed14": 5,
            "sky130": 6}

# (proto, lang) pairs that have a testbench, and the simulators that run them
IMPLEMENTED = {(p, lang): {"vcs", "xcelium", "xsim"} | ({"verilator"} if lang == "sv" else set())
               for p in ("ahb", "apb", "axi4l", "wb") for lang in ("sv", "vhdl")}

# (simulator, language, technology) combinations that cannot run, with the reason
# (reported as SKIP, not counted as a failure).
UNSUPPORTED = {
    ("xsim", "vhdl", "xilinx"): "xsim cannot force the XPM read data across the "
                                "SV/VHDL boundary (XSIM 43-4289); see synthesis --vivado",
}

# Compile order of the sram RTL (dependencies first)
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


def sv_files(proto: str, sram_path: str) -> list:
    """Ordered SV sources of the <proto> system testbench (RTL, model, bench)."""
    common = get_common_path(sram_path)
    crtl = os.path.join(common, "design", "rtl", "verilog")
    rtl = os.path.join(sram_path, "design", "rtl", "verilog")
    bm = os.path.normpath(os.path.join(sram_path, "..", "..", "interface", "bus_matrix",
                                       "design", "rtl", "verilog"))
    tb = os.path.join(sram_path, "verification", "testbench")
    files = [os.path.join(crtl, f) for f in
             ("claude_sync.sv", "claude_pulse_sync.sv", f"claude_{proto}_mem_if.sv")]
    files += [os.path.join(rtl, f"{m}.sv") for m in SRAM_RTL]
    files += [os.path.join(rtl, f"sram_{proto}.sv"), os.path.join(rtl, f"sram_{proto}_dp.sv")]
    files += [os.path.join(bm, f"{m}.sv") for m in
              ("bus_matrix_pkg", "bus_matrix_decoder", "bus_matrix_arb", "bus_matrix_core",
               f"bus_matrix_{proto}_tgt", f"bus_matrix_{proto}_ini", f"bus_matrix_{proto}")]
    files += [os.path.join(sram_path, "design", "behavioral", "sram_model.sv"),
              os.path.join(tb, "sram_tb_pkg.sv"),
              os.path.join(tb, f"sram_tb_{proto}_master.sv"),
              os.path.join(tb, f"tb_sram_{proto}.sv")]
    return files


def vhdl_files(proto: str, sram_path: str) -> list:
    """Ordered VHDL-2008 sources of the DUT for --lang vhdl: the sram tops and
    the bus_matrix (the bench, BFMs and reference models stay SystemVerilog)."""
    common = get_common_path(sram_path)
    crtl = os.path.join(common, "design", "rtl", "vhdl")
    rtl = os.path.join(sram_path, "design", "rtl", "vhdl")
    bm = os.path.normpath(os.path.join(sram_path, "..", "..", "interface", "bus_matrix",
                                       "design", "rtl", "vhdl"))
    files = [os.path.join(crtl, f) for f in
             ("claude_sync.vhd", "claude_pulse_sync.vhd", f"claude_{proto}_mem_if.vhd")]
    files += [os.path.join(rtl, f"{m}.vhd") for m in SRAM_RTL]
    files += [os.path.join(rtl, f"sram_{proto}.vhd"), os.path.join(rtl, f"sram_{proto}_dp.vhd")]
    files += [os.path.join(bm, f"{m}.vhd") for m in
              ("bus_matrix_pkg", "bus_matrix_decoder", "bus_matrix_arb", "bus_matrix_core",
               f"bus_matrix_{proto}_tgt", f"bus_matrix_{proto}_ini", f"bus_matrix_{proto}")]
    return files


def bench_files(proto: str, sram_path: str) -> list:
    """SV bench sources around a VHDL DUT: reference model, package, BFM, top."""
    tb = os.path.join(sram_path, "verification", "testbench")
    return [os.path.join(sram_path, "design", "behavioral", "sram_model.sv"),
            os.path.join(tb, "sram_tb_pkg.sv"),
            os.path.join(tb, f"sram_tb_{proto}_master.sv"),
            os.path.join(tb, f"tb_sram_{proto}.sv")]


def dpi_files(sram_path: str) -> list:
    return [os.path.join(get_common_path(sram_path), "verification", "dpi", "claude_backdoor.c")]


def tech_defines(tech: str, lang: str = "sv") -> list:
    """Defines as NAME[=VALUE] strings."""
    d = [f"TECH={TECH_NUM[tech]}"]
    if lang == "vhdl":
        d.append("VHDL_DUT")
    if tech == "generic":
        d.append("TECH_GENERIC")
    return d


def macro_models(tech: str, sram_path: str, work_dir: str, gate_level: bool = False) -> list:
    """Vendor SRAM macro models for a PDK (none for GENERIC). gate_level:
    post-synthesis runs (SKY130 read delay from the liberty, see
    pdk_sram_models.SKY130_GL_DELAY)."""
    if tech == "generic":
        return []
    sys.path.insert(0, os.path.join(get_common_path(sram_path), "verification", "tools"))
    import pdk_sram_models  # noqa: E402
    return pdk_sram_models.model_files(tech, work_dir, gate_level=gate_level)


# ---------------------------------------------------------------------------
# Result helpers
# ---------------------------------------------------------------------------
def _write_result(path: str, status: str, detail: str) -> None:
    with open(path, "w") as fh:
        fh.write(f"{status}\n")
        fh.write(detail)
    print(f"  -> {path} : {status}")


def _run(cmd: list, cwd: str, timeout: int) -> tuple:
    """Run a command; returns (output, returncode). Tool missing / timeout -> rc 127 / 124."""
    try:
        p = subprocess.run(cmd, cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, universal_newlines=True, timeout=timeout)
        return p.stdout, p.returncode
    except FileNotFoundError:
        return f"ERROR: {cmd[0]} not found in PATH\n", 127
    except subprocess.TimeoutExpired:
        return f"ERROR: {cmd[0]} timed out after {timeout} s\n", 124


def _passed(sim_log: str, tb_top: str) -> bool:
    """PASS marker printed and no FAIL / reference-model ERROR before it."""
    pos = sim_log.find(f"PASS {tb_top}")
    if pos < 0:
        return False
    head = sim_log[:pos]
    return "FAIL" not in head and "ERROR [sram_model]" not in head


def _summary_line(sim_log: str, tb_top: str) -> str:
    for line in sim_log.splitlines():
        if line.startswith(f"PASS {tb_top}") or line.startswith(f"FAIL {tb_top}"):
            return line.strip()
    return ""


# ---------------------------------------------------------------------------
# Runners
# ---------------------------------------------------------------------------
COV_METRICS = "line+cond+fsm+tgl+branch"


def cov_hier(proto: str, work_dir: str, lang: str = "sv") -> str:
    """-cm_hier file: the sram top-levels and everything below them, except the
    vendor SRAM macro models (not our code). VHDL entity names are given in
    upper case (VCS stores VHDL names in upper case)."""
    path = os.path.join(work_dir, "cov_hier.cfg")
    tops = [f"sram_{proto}", f"sram_{proto}_dp"]
    if lang == "vhdl":
        tops = [t.upper() for t in tops]
    with open(path, "w") as fh:
        fh.write("".join(f"+moduletree {t}\n" for t in tops))
        if lang == "vhdl":
            # +moduletree does not reach below a VHDL instance that sits in an SV
            # generate block (the directly attached SRAMs): name those trees.
            fh.write("".join(f"+tree tb_sram_{proto}.g_direct[{i}].u_s\n" for i in (0, 1)))
        # SAED models are SRAM<digit>... / SRAMLP...: a bare "SRAM*" would also
        # match the upper-case VHDL tops (SRAM_AHB...).
        vendor = ("SRAM1*", "SRAM2*", "SRAM3*", "SRAM6*", "SRAM8*", "SRAMLP*",
                  "sky130_sram_*", "sram_1rw1r_*", "sram_2rw_*")
        for m in vendor:
            fh.write(f"-moduletree {m}\n")
        if lang == "vhdl":
            # an explicit +tree overrides -moduletree: drop the models by module
            fh.write("".join(f"-module {m}\n" for m in vendor))
    return path


def run_vcs(proto: str, lang: str, tech: str, test: str, waves: bool,
            sram_path: str, work_dir: str, coverage: bool = False) -> tuple:
    """Compile and simulate with VCS. Returns (passed, summary)."""
    os.makedirs(work_dir, exist_ok=True)
    results = os.path.join(work_dir, "results.log")
    tb_top = f"tb_sram_{proto}"
    tests = os.path.join(sram_path, "verification", "tests")
    tbdir = os.path.join(sram_path, "verification", "testbench")
    simv = os.path.join(work_dir, "simv")
    incs = [f"+incdir+{tests}+{tbdir}"]
    defs = [f"+define+{d}" for d in tech_defines(tech, lang)]
    # r+w: VPI backdoor (claude_backdoor.c); f: force; pp: waveforms
    debug = ["-debug_access+pp+f+r+w"]
    cov = []
    cov_elab = []
    if coverage:
        cov = ["-cm", COV_METRICS, "-cm_dir", os.path.join(work_dir, "cov.vdb")]
        # -cm_noconst / -cm_seqnoconst: leave out logic that is constant by
        # construction (tie-offs and parameter-disabled features, also through
        # flops), e.g. the ECC pins of an instance with ECC_EN = 0.
        cov_elab = cov + ["-cm_hier", cov_hier(proto, work_dir, lang), "-cm_noconst",
                          "-cm_seqnoconst"]
    if lang == "sv":
        steps = [["vcs", "-full64", "-sverilog", "-timescale=1ns/1ps", "-o", simv]
                 + debug + incs + defs + macro_models(tech, sram_path, work_dir)
                 + sv_files(proto, sram_path) + dpi_files(sram_path)
                 + ["-top", tb_top] + cov_elab]
    else:
        # Mixed language (VCS-MX): vendor Verilog models (vlogan), the VHDL DUT
        # (vhdlan -vhdl08), the SV bench (vlogan), then elaborate the SV top.
        with open(os.path.join(work_dir, "synopsys_sim.setup"), "w") as fh:
            fh.write("WORK > DEFAULT\nDEFAULT : ./work_lib\n")
        os.makedirs(os.path.join(work_dir, "work_lib"), exist_ok=True)
        models = macro_models(tech, sram_path, work_dir)
        steps = ([["vlogan", "-full64", "-timescale=1ns/1ps"] + models] if models else []) + [
            ["vhdlan", "-full64", "-vhdl08"] + vhdl_files(proto, sram_path),
            ["vlogan", "-full64", "-sverilog", "-timescale=1ns/1ps"] + incs + defs
            + bench_files(proto, sram_path),
            ["vcs", "-full64", "-timescale=1ns/1ps", "-o", simv] + debug
            # VHPI entry points of the backdoor helper (VHDL storage)
            + ["-CFLAGS", "-DCLAUDE_BD_VHPI -DCLAUDE_BD_VHPI_ROOTS"]
            + dpi_files(sram_path) + [tb_top] + cov_elab
            # +moduletree of VHDL entities needs this switch (an LCA feature)
            + (["-lca", "-cm_hier_enable_moduletree_vhdl"] if coverage else [])]
    tag = f"[vcs/{proto}_{lang}/{tech}]"
    print(f"  {tag} Compiling ...")
    log_txt = ""
    rc = 0
    for cmd in steps:
        out, rc = _run(cmd, work_dir, 900)
        log_txt += " ".join(cmd) + "\n\n" + out + "\n"
        if rc != 0:
            break
    with open(os.path.join(work_dir, "compile.log"), "w") as fh:
        fh.write(log_txt)
    if rc != 0:
        print(f"  {tag} Compile FAILED (see {work_dir}/compile.log)")
        _write_result(results, "FAIL", log_txt)
        return False, "compile failed"
    print(f"  {tag} Simulating (+test={test}) ...")
    plus = [f"+test={test}"] + (["+waves"] if waves else [])
    sim_out, rc = _run([simv] + plus + cov, work_dir, 3600)
    with open(os.path.join(work_dir, "sim.log"), "w") as fh:
        fh.write(sim_out)
    ok = _passed(sim_out, tb_top)
    summ = _summary_line(sim_out, tb_top) or f"no PASS line (rc {rc})"
    print(f"  {tag} {summ}")
    _write_result(results, "PASS" if ok else "FAIL", sim_out)
    return ok, summ


# ---------------------------------------------------------------------------
# Gate level (--postsyn, Step 10): DC netlists + SDF, VCS
# ---------------------------------------------------------------------------
_SAED90_PDK = "/opt/ECE_Lib/SAED90nm_EDK_10072017/SAED90_EDK/SAED_EDK90nm"
_SAED32_EDK = "/opt/ECE_Lib/SAED32_EDK"
_SAED14_EDK = "/opt/ECE_Lib/SAED14nm_EDK_03_2025"

# Standard-cell simulation models (as sim_timer.py). SAED14's cells wrap
# "_func" UDPs that live in companion *_udp.v files. SKY130: primitives.v
# is compiled from a copy with `default_nettype wire (its non-ANSI UDP ports
# fail under `default_nettype none), and sky130_fd_sc_hd.v is a -v library
# (one unused cell references an undeclared VPWR).
POSTSYN_CELLS = {
    "saed90": {"cells": [f"{_SAED90_PDK}/Digital_Standard_cell_Library/verilog/saed90nm.v"]},
    "saed32": {"cells": [f"{_SAED32_EDK}/lib/stdcell_rvt/verilog/saed32nm.v"]},
    "saed14": {"cells": [f"{_SAED14_EDK}/SAED14nm_EDK_STD_RVT/verilog/{d}/saed14rvt_{d}{s}.v"
                         for d in ("base", "cg", "dlvl", "iso") for s in ("", "_udp")]},
    "sky130": {"cells": [], "nettype_wire": ["primitives.v"], "v_libs": ["sky130_fd_sc_hd.v"]},
}
POSTSYN_PDKS = list(POSTSYN_CELLS)

# SAED90 does not meet 100 MHz (user decision 2026-11-25, synthesis/
# known_issues.md): with +notimingcheck its violating paths show up as wrong
# data, not as timing-check messages. Its runs are reported, not counted.
POSTSYN_KNOWN_FAILURES = {"saed90"}

# Netlists of one gate-level run: (bench instance, configuration suffix).
POSTSYN_NETLISTS = [("u_base", ""), ("u_opts", "_opts"), ("u_dp", "_dp")]


def _sky130_verilog() -> str:
    pdk = os.environ.get("CLAUDE_SKY130_PDK_PATH", "")
    return os.path.join(pdk, "libs.ref", "sky130_fd_sc_hd", "verilog")


def postsyn_netlist_copy(src: str, top: str, tag: str, dst: str) -> None:
    """Copy a DC netlist with every sub-module renamed <name>__<tag>.

    One bench compiles three netlists, and DC names sub-designs after their
    parameters, so the same name (e.g. sram_clr_00000400_00000002_1) can be
    defined by two netlists with different logic. The top keeps its name;
    library cells are not defined in the netlist and are untouched."""
    import re
    with open(src) as fh:
        text = fh.read()
    names = set(re.findall(r"^module\s+(\w+)", text, re.M)) - {top}
    if names:
        rx = re.compile(r"\b(" + "|".join(sorted(map(re.escape, names), key=len, reverse=True)) + r")\b")
        text = rx.sub(lambda m: f"{m.group(1)}__{tag}", text)
    with open(dst, "w") as fh:
        fh.write(text)


def run_vcs_postsyn(proto: str, lang: str, pdk: str, waves: bool, sram_path: str,
                    work_dir: str, sdf: bool = True, saif: bool = False) -> tuple:
    """Gate-level simulation of the three DC netlists of (proto, RTL language,
    PDK) in tb_sram_<proto> (+define+SRAM_POSTSYN, sram_tb_postsyn_body.svh),
    with DC's SDF on each, the vendor SRAM macro models and the standard-cell
    models. +notimingcheck: function is checked; timing is PrimeTime's job
    (synthesis/run_primetime_sta.py). Returns (passed, summary)."""
    os.makedirs(work_dir, exist_ok=True)
    results = os.path.join(work_dir, "results.log")
    tb_top = f"tb_sram_{proto}"
    tag = f"[postsyn/{proto}_{lang}/{pdk}]"
    net_dir = os.path.join(sram_path, "synthesis", "designcompiler", "netlists", pdk)
    lsuf = "_vhdl" if lang == "vhdl" else ""
    nets, sdfs, defs = [], [], []
    for inst, csuf in POSTSYN_NETLISTS:
        top = f"sram_{proto}{'_dp' if csuf == '_dp' else ''}{'_opts' if csuf == '_opts' else ''}{lsuf}"
        src = os.path.join(net_dir, f"{top}.v")
        if not os.path.isfile(src):
            msg = f"netlist not found: {src} (run synthesis/run_vendor_synth.py --dc first)"
            print(f"  {tag} {msg}")
            _write_result(results, "FAIL", msg)
            return False, "netlist missing"
        dst = os.path.join(work_dir, f"{top}.v")
        postsyn_netlist_copy(src, top, inst[2:], dst)
        nets.append(dst)
        sdf_file = os.path.join(net_dir, f"{top}.sdf")
        if sdf and os.path.isfile(sdf_file):
            sdfs += ["-sdf", f"typ:{tb_top}.{inst}:{sdf_file}"]
        defs.append(f"+define+PS_{inst[2:].upper()}={top}")
    cfg = POSTSYN_CELLS[pdk]
    # Corrected copies where a vendor cell model disagrees with its liberty
    # (SAED90 SSR flip-flops, IP/common/verification/tools/pdk_cell_models.py)
    sys.path.insert(0, os.path.join(get_common_path(sram_path), "verification", "tools"))
    import pdk_cell_models  # noqa: E402
    cells = pdk_cell_models.cell_files(pdk, work_dir) or list(cfg["cells"])
    for name in cfg.get("nettype_wire", []):
        src = os.path.join(_sky130_verilog(), name)
        dst = os.path.join(work_dir, "nettype_wire_" + name)
        with open(src) as fh:
            text = fh.read()
        with open(dst, "w") as fh:
            fh.write(text.replace("`default_nettype none", "`default_nettype wire"))
        cells.append(dst)
    v_libs = []
    for name in cfg.get("v_libs", []):
        v_libs += ["-v", os.path.join(_sky130_verilog(), name)]
    missing = [f for f in cells + v_libs[1::2] if not os.path.isfile(f)]
    if missing:
        msg = "cell models not found:\n" + "\n".join(missing)
        print(f"  {tag} {msg}")
        _write_result(results, "FAIL", msg)
        return False, "cell models missing"
    tbdir = os.path.join(sram_path, "verification", "testbench")
    bench = [os.path.join(tbdir, f) for f in
             ("sram_tb_pkg.sv", f"sram_tb_{proto}_master.sv", f"tb_sram_{proto}.sv")]
    simv = os.path.join(work_dir, "simv")
    cmd = (["vcs", "-full64", "-sverilog", "-timescale=1ns/1ps", "-o", simv,
            "-debug_access+pp", "+notimingcheck", "+neg_tchk", "+vcs+initreg+random",
            f"+incdir+{tbdir}", f"+define+TECH={TECH_NUM[pdk]}", "+define+SRAM_POSTSYN"]
           # --no-sdf: zero-delay gates (the cell models' own specify / #
           # delays too), so only function is left
           + ([] if sdf else ["+delay_mode_zero"])
           + defs + sdfs + macro_models(pdk, sram_path, work_dir, gate_level=True) + cells + nets + bench
           + v_libs + ["-top", tb_top])
    print(f"  {tag} Compiling (3 netlists, SDF {len(sdfs) // 2}) ...")
    out, rc = _run(cmd, work_dir, 1800)
    with open(os.path.join(work_dir, "compile.log"), "w") as fh:
        fh.write(" ".join(cmd) + "\n\n" + out)
    if rc != 0:
        print(f"  {tag} Compile FAILED (see {work_dir}/compile.log)")
        _write_result(results, "FAIL", out)
        return False, "compile failed"
    print(f"  {tag} Simulating ...")
    # +vcs+initreg+0: every gate-level flop starts at 0 (no X before reset)
    for inst, _ in POSTSYN_NETLISTS:     # stale activity must not reach --power
        f = os.path.join(work_dir, f"saif_{inst[2:]}.saif")
        if os.path.exists(f):
            os.remove(f)
    sim_out, rc = _run([simv, "+vcs+initreg+0"] + (["+waves"] if waves else [])
                       + (["+saif"] if saif else []), work_dir, 7200)
    with open(os.path.join(work_dir, "sim.log"), "w") as fh:
        fh.write(sim_out)
    ok = _passed(sim_out, tb_top)
    summ = _summary_line(sim_out, tb_top) or f"no PASS line (rc {rc})"
    print(f"  {tag} {summ}")
    _write_result(results, "PASS" if ok else "FAIL", sim_out)
    return ok, summ


def run_postsyn(args, sram_path: str) -> int:
    """--postsyn: every (proto, lang, pdk) selected, VCS, --jobs in parallel."""
    if not ON_CSUN:
        print("ERROR: --postsyn needs VCS and the PDKs (csun.edu only).")
        return 1
    protos = SUPPORTED_PROTOS if args.proto == "all" else [args.proto]
    langs = SUPPORTED_LANGS if args.lang == "all" else [args.lang]
    pdks = POSTSYN_PDKS if args.pdk == "all" else [args.pdk]
    bad = [p for p in pdks if p not in POSTSYN_PDKS]
    if bad:
        print(f"ERROR: --pdk must be one of {POSTSYN_PDKS} or all (got {bad})")
        return 1
    work_base = os.path.join(sram_path, "verification", "work")
    sub = "postsyn_nosdf" if args.no_sdf else "postsyn"
    runs = [(f"{sub}/{p}_{lang}/{k}", (p, lang, k, args.waves, sram_path,
                                        os.path.join(work_base, sub, f"{p}_{lang}_{k}"),
                                        not args.no_sdf))
            for k in pdks for p in protos for lang in langs]
    summary = {}
    with concurrent.futures.ThreadPoolExecutor(max(1, min(args.jobs, 3))) as ex:
        futs = {ex.submit(run_vcs_postsyn, *a): label for label, a in runs}
        for f in concurrent.futures.as_completed(futs):
            try:
                ok, summ = f.result()
            except Exception as e:  # a crashed run is a FAIL, not a lost summary
                ok, summ = False, f"runner error {type(e).__name__}: {e}"
            summary[futs[f]] = ("PASS" if ok else "FAIL", summ)
    rows = []
    for label, a in runs:
        st, summ = summary[label]
        if st == "FAIL" and a[2] in POSTSYN_KNOWN_FAILURES and not args.no_sdf:
            st = "KNOWN"
        rows.append((label, st, summ))
    all_pass = all(st in ("PASS", "KNOWN") for _, st, _ in rows) and bool(rows)
    green, red, yellow, reset = "\033[32m", "\033[31m", "\033[33m", "\033[0m"
    col = {"PASS": green, "FAIL": red, "KNOWN": yellow}
    print("\n" + "=" * 78)
    print("sram post-synthesis (gate-level) simulation results")
    print("=" * 78)
    for label, st, summ in rows:
        print(f"  {label:<26} {col[st]}{st:<5}{reset}  {summ}")
    if any(st == "KNOWN" for _, st, _ in rows):
        print("  KNOWN = accepted failure (SAED90 misses 100 MHz, synthesis/known_issues.md)")
    print("=" * 78)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    with open(os.path.join(work_base, sub, "results.log"), "w") as fh:
        fh.write(f"{'PASS' if all_pass else 'FAIL'}  sim_sram.py --postsyn"
                 f"{' --no-sdf' if args.no_sdf else ''}  {stamp}\n")
        for label, st, summ in rows:
            fh.write(f"{st:<5} {label:<26} {summ}\n")
    print(f"All post-synthesis simulations {green}PASSED{reset}." if all_pass
          else f"One or more post-synthesis simulations {red}FAILED{reset}.")
    return 0 if all_pass else 1


# ---------------------------------------------------------------------------
# Power (--power, Step 12): PrimePower on the gate-level activity
# ---------------------------------------------------------------------------
POWER_PDKS = ["saed90", "saed32", "saed14", "sky130"]  # SAED90 rows: SKIP (POSTSYN_KNOWN_FAILURES)


def power_libs(pdk: str, sram_path: str) -> list:
    """Typical-corner standard-cell and SRAM macro .db files (the netlists are
    synthesized at the worst corner; power is reported at typical, as the
    timer and bus_matrix do)."""
    import glob
    import re
    sys.path.insert(0, os.path.join(get_common_path(sram_path), "synthesis", "designcompiler"))
    import build_sky130_libs  # noqa: E402
    import build_saed32_sram_libs  # noqa: E402
    if pdk == "saed90":
        std = [f"{_SAED90_PDK}/Digital_Standard_cell_Library/synopsys/models/saed90nm_typ.db"]
        mdir = f"{_SAED90_PDK}/Memories/synopsys/models"
        return std + sorted(f for f in glob.glob(f"{mdir}/SRAM*_typ.db")
                            if re.search(r"/SRAM\d+x\d+(_1rw)?_typ\.db$", f))
    if pdk == "saed32":
        db = build_saed32_sram_libs.ensure_saed32_sram_db("tt1p05v25c_i1p05v")
        return [f"{_SAED32_EDK}/lib/stdcell_rvt/db_nldm/saed32rvt_tt1p05v25c.db"] + ([db] if db else [])
    if pdk == "saed14":
        base = f"{_SAED14_EDK}/SAED14nm_EDK_STD_RVT/liberty/nldm"
        return [f"{base}/base/saed14rvt_base_tt0p8v25c.db", f"{base}/cg/saed14rvt_cg_tt0p8v25c.db",
                f"{base}/dlvl/saed14rvt_dlvl_tt0p8v25c_i0p8v.db", f"{base}/iso/saed14rvt_iso_tt0p8v25c.db",
                f"{_SAED14_EDK}/SAED14nm_EDK_SRAM/liberty/nldm/saed14sram_tt0p8v25c.db"]
    dbs = build_sky130_libs.ensure_sky130_dbs(build_sky130_libs.SKY130_PDK) or {}
    sram = build_sky130_libs.ensure_sky130_sram_dbs(build_sky130_libs.SKY130_PDK) or []
    return ([dbs["tt_025C_1v80"]] if "tt_025C_1v80" in dbs else []) + list(sram)


def _power_numbers(rpt: str) -> dict:
    """Total / internal / switching / leakage (mW) from report_power."""
    import re
    d = {}
    if not os.path.isfile(rpt):
        return d
    text = open(rpt).read()
    for label, key in (("Cell Internal Power", "internal"), ("Net Switching Power", "switching"),
                       ("Cell Leakage Power", "leakage"), ("Total Power", "total")):
        m = re.search(rf"{label}\s*=\s*([\d.eE+-]+)", text)
        if m:
            d[key] = float(m.group(1))
    # Power groups: "<group>  internal switching leakage total (pct)"
    grp = {}
    for m in re.finditer(r"^(clock_network|register|combinational|sequential|memory)\s+"
                         r"([-\d.eE+]+)\s+([-\d.eE+]+)\s+([-\d.eE+]+)\s+([-\d.eE+]+)", text, re.M):
        grp[m.group(1)] = float(m.group(5))
    if grp:
        d["logic"] = sum(v for k, v in grp.items() if k != "memory")
        d["memory"] = grp.get("memory", 0.0)
    return d


def _annotation_pct(rpt: str) -> float:
    """Percentage of nets annotated from the SAIF (report_switching_activity)."""
    import re
    if not os.path.isfile(rpt):
        return -1.0
    for line in open(rpt):
        m = re.match(r"\s*Nets\s+\d+\(\s*([\d.]+)%\)", line)
        if m:
            return float(m.group(1))
    return -1.0


def run_power_one(proto: str, lang: str, pdk: str, inst: str, csuf: str, sram_path: str,
                  work_dir: str) -> tuple:
    """PrimePower for one netlist instance of a gate-level run. Returns
    (passed, numbers dict, detail)."""
    tb_top = f"tb_sram_{proto}"
    lsuf = "_vhdl" if lang == "vhdl" else ""
    top = f"sram_{proto}{'_dp' if csuf == '_dp' else ''}{'_opts' if csuf == '_opts' else ''}{lsuf}"
    net_dir = os.path.join(sram_path, "synthesis", "designcompiler", "netlists", pdk)
    pdir = os.path.join(work_dir, "power", inst[2:])
    os.makedirs(pdir, exist_ok=True)
    saif = os.path.join(work_dir, f"saif_{inst[2:]}.saif")
    netlist = os.path.join(net_dir, f"{top}.v")
    sdc = os.path.join(net_dir, f"{top}.sdc")
    libs = power_libs(pdk, sram_path)
    missing = [f for f in [saif, netlist, sdc] + libs if not os.path.isfile(f)] + ([] if libs else ["libs"])
    if missing:
        return False, {}, "missing: " + ", ".join(missing)
    rpts = {k: os.path.join(pdir, f"power_{k}.rpt")
            for k in ("annotation", "overall", "hierarchy", "top_cells", "top_nets")}
    for r in rpts.values():
        if os.path.exists(r):
            os.remove(r)
    # DC's .sdc names the synthesis-corner library on its wire-load line; drop
    # it and apply DC's per-netlist model by name from the typical library
    # (as run_primetime_sta.py does: the model is chosen after write_sdc).
    sdc_pw = os.path.join(pdir, f"{top}_power.sdc")
    with open(sdc) as fi, open(sdc_pw, "w") as fo:
        for line in fi:
            if not line.startswith("set_wire_load_model"):
                fo.write(line)
    sys.path.insert(0, os.path.join(sram_path, "synthesis"))
    import run_primetime_sta  # noqa: E402
    wlm = run_primetime_sta.dc_wire_load(pdk, top)
    wlm_cmds = ["set_wire_load_mode top", f"set_wire_load_model -name {wlm}"] if wlm != "-" else []
    tcl = os.path.join(pdir, "run_power.tcl")
    with open(tcl, "w") as fh:
        fh.write("\n".join([
            f"# PrimePower — GENERATED by sim_sram.py --power ({proto} {lang} {pdk} {inst[2:]})",
            "set_app_var power_enable_analysis true",
            "set_app_var power_analysis_mode averaged",
            f"set_app_var link_path [list * {' '.join(libs)}]",
            f"read_verilog {netlist}",
            f"current_design {top}",
            "link_design",
            f"read_sdc {sdc_pw}",
            *wlm_cmds,
            f"read_saif {saif} -strip_path {tb_top}/{inst}",
            "update_power",
            f"redirect {rpts['annotation']} {{ report_switching_activity -list_not_annotated }}",
            f"redirect {rpts['overall']} {{ report_power -nosplit -unit mW }}",
            f"redirect {rpts['hierarchy']} {{ report_power -nosplit -unit mW -hierarchy -levels 3 }}",
            f"redirect {rpts['top_cells']} {{ report_power -nosplit -unit mW -cell_power -leaf "
            "-nworst 10 -sort_by total_power }",
            f"redirect {rpts['top_nets']} {{ report_power -nosplit -unit mW -net_power -leaf "
            "-nworst 10 -sort_by net_switching_power }",
            "exit", ""]))
    out, rc = _run(["pt_shell", "-f", tcl], pdir, 1800)
    with open(os.path.join(pdir, "pt_shell.log"), "w") as fh:
        fh.write(out)
    # pt_shell exits 0 even when the script aborts: judge by the log and the
    # reports. PT-063 (Library Compiler path unset) is printed at every start.
    errors = [ln for ln in out.splitlines() if ln.startswith("Error:") and "(PT-063)" not in ln]
    nums = _power_numbers(rpts["overall"])
    nums["annot"] = _annotation_pct(rpts["annotation"])
    empty = [k for k, r in rpts.items() if k != "annotation"
             and (not os.path.isfile(r) or os.path.getsize(r) == 0)]
    ok = rc == 0 and not errors and not empty and "total" in nums
    detail = "; ".join(errors[:2]) if errors else ("empty reports: " + ", ".join(empty) if empty else "")
    if ok and nums["annot"] < 99.0:
        ok, detail = False, f"SAIF annotation {nums['annot']:.1f} % < 99 %"
    if ok and nums.get("memory", 0.0) < 0.0:
        # The vendor macro liberty's input-pin internal power is negative
        # (SAED32-LP); the macro share is not a usable estimate.
        nums["memory_invalid"] = True
        detail = "macro power negative (vendor liberty input-pin internal_power), not counted"
    return ok, nums, detail


def run_power(args, sram_path: str) -> int:
    """--power: gate-level runs with +saif, then PrimePower per netlist."""
    if not ON_CSUN:
        print("ERROR: --power needs VCS, PrimePower and the PDKs (csun.edu only).")
        return 1
    protos = SUPPORTED_PROTOS if args.proto == "all" else [args.proto]
    langs = SUPPORTED_LANGS if args.lang == "all" else [args.lang]
    pdks = POWER_PDKS if args.pdk == "all" else [args.pdk]
    work_base = os.path.join(sram_path, "verification", "work")
    runs = [(p, lang, k) for k in pdks for p in protos for lang in langs]
    rows = []

    def one(run):
        p, lang, k = run
        label = f"power/{p}_{lang}/{k}"
        if k in POSTSYN_KNOWN_FAILURES:
            return [(label, "-", "SKIP", {}, "gate-level activity not valid (accepted timing failure)")]
        wd = os.path.join(work_base, "power", f"{p}_{lang}_{k}")
        ok, summ = run_vcs_postsyn(p, lang, k, False, sram_path, wd, sdf=True, saif=True)
        if not ok:
            return [(label, "-", "FAIL", {}, f"gate-level run failed: {summ}")]
        out = []
        for inst, csuf in POSTSYN_NETLISTS:
            pok, nums, det = run_power_one(p, lang, k, inst, csuf, sram_path, wd)
            out.append((label, inst[2:], "PASS" if pok else "FAIL", nums, det))
        return out

    with concurrent.futures.ThreadPoolExecutor(max(1, min(args.jobs, 3))) as ex:
        for res in ex.map(one, runs):
            rows += res
    all_pass = all(st in ("PASS", "SKIP") for _, _, st, _, _ in rows) and bool(rows)
    lines = [f"{'PASS' if all_pass else 'FAIL'}  sim_sram.py --power  "
             f"{datetime.datetime.now().strftime('%Y-%m-%d %H:%M')}",
             f"{'run':<24} {'netlist':<5} {'status':<5} {'logic':>9} {'macros':>9} {'total':>9} "
             f"{'switching':>9} {'leakage':>9} {'SAIF %':>7}  (mW, typical corner)"]
    for label, inst, st, n, det in rows:
        if n.get("total") is not None:
            inv = n.get("memory_invalid")
            mac = "invalid" if inv else f"{n.get('memory', 0):.4f}"
            tot = "n/a" if inv else f"{n['total']:.4f}"
            lines.append(f"{label:<24} {inst:<5} {st:<5} {n.get('logic', 0):>9.4f} {mac:>9} {tot:>9} "
                         f"{n.get('switching', 0):>9.4f} {n.get('leakage', 0):>9.4f} "
                         f"{n.get('annot', -1):>7.1f}  {det}")
        else:
            lines.append(f"{label:<24} {inst:<5} {st:<5} {det}")
    os.makedirs(os.path.join(work_base, "power"), exist_ok=True)
    with open(os.path.join(work_base, "power", "results.log"), "w") as fh:
        fh.write("\n".join(lines) + "\n")
    print("\n" + "=" * 100)
    print("\n".join(lines))
    print("=" * 100)
    return 0 if all_pass else 1


def run_xcelium(proto: str, lang: str, tech: str, test: str, waves: bool,
                sram_path: str, work_dir: str, coverage: bool = False) -> tuple:
    """Compile, elaborate and simulate with Xcelium (xrun). Returns (passed, summary)."""
    os.makedirs(work_dir, exist_ok=True)
    results = os.path.join(work_dir, "results.log")
    tb_top = f"tb_sram_{proto}"
    tests = os.path.join(sram_path, "verification", "tests")
    tbdir = os.path.join(sram_path, "verification", "testbench")
    log = os.path.join(work_dir, "sim.log")
    defs = []
    for d in tech_defines(tech, lang):
        defs += ["-define", d]
    if lang == "sv":
        src = sv_files(proto, sram_path)
    else:
        # Mixed language: the VHDL-2008 DUT and the SV bench in one xrun.
        # -namemap_mixgen: VHDL generic maps bind Verilog parameters by name
        # (by default xmelab binds them by position, so the PDK wrappers'
        # "VERBOSE => 0" would set a SKY130 model's first parameter,
        # NUM_WMASKS).
        src = ["-v200x", "-inc_v200x_pkg", "-namemap_mixgen"] + vhdl_files(proto, sram_path) \
            + bench_files(proto, sram_path) + ["-ccargs", "-DCLAUDE_BD_VHPI"]
    cmd = (["xrun", "-64", "-sv", "-timescale", "1ns/1ps",
            # +rw: VPI backdoor (claude_backdoor.c) and force
            "-access", "+rwc", "-incdir", tests, "-incdir", tbdir, "-work", "work", "-log", log]
           + defs + macro_models(tech, sram_path, work_dir)
           + src + dpi_files(sram_path)
           + ["-top", tb_top, f"+test={test}"])
    if waves:
        # Probe everything into waves.shm
        tcl = os.path.join(work_dir, "waves.tcl")
        with open(tcl, "w") as fh:
            fh.write("database -open waves -shm -default\nprobe -create -all -depth all\nrun\nexit\n")
        cmd += ["-input", tcl]
    tag = f"[xcelium/{proto}_{lang}/{tech}]"
    print(f"  {tag} Running xrun (+test={test}) ...")
    out, rc = _run(cmd, work_dir, 3600)
    with open(os.path.join(work_dir, "compile.log"), "w") as fh:
        fh.write(" ".join(cmd) + "\n\n" + out)
    sim_out = open(log).read() if os.path.exists(log) else out
    ok = _passed(sim_out, tb_top) and "*E," not in sim_out
    summ = _summary_line(sim_out, tb_top) or f"no PASS line (rc {rc}, see {log})"
    print(f"  {tag} {summ}")
    _write_result(results, "PASS" if ok else "FAIL", sim_out)
    return ok, summ


# Verilator memory budget. The whole build (verilator_bin plus the parallel
# g++ jobs) and the simulation run inside one systemd user scope with
# MemoryMax, so an oversize build fails on its own instead of the kernel
# OOM killer taking down other processes. Peak with these settings: see
# README "Simulation Results". Override with SRAM_VERILATOR_MEM (e.g. 12G).
VERILATOR_MEM_MAX = os.environ.get("SRAM_VERILATOR_MEM", "8G")
VERILATOR_BUILD_JOBS = 4      # g++ jobs per build (each ~0.5-1 GB on this bench)
# Per-protocol override. The AXI4-Lite bench becomes 191 MB of C++ in 64 files (the largest
# 40 MB), and one g++ on such a file takes up to ~3.7 GB, so two at once can reach the 8 GB
# cap: it was OOM-killed with 4 jobs (2 of 3 builds) and with 2 jobs (2026-11-25). One
# compile at a time bounds the peak at about half the cap, at the cost of build time.
VERILATOR_BUILD_JOBS_PROTO = {"axi4l": 1}


def _mem_capped(cmd: list) -> list:
    """Prefix cmd with a systemd-run scope limited to VERILATOR_MEM_MAX (no swap).
    Falls back to the bare command where systemd user scopes are unavailable."""
    if not shutil.which("systemd-run"):
        return cmd
    probe = subprocess.run(["systemd-run", "--user", "--scope", "-q", "true"],
                           capture_output=True)
    if probe.returncode != 0:
        return cmd
    return (["systemd-run", "--user", "--scope", "-q",
             "-p", f"MemoryMax={VERILATOR_MEM_MAX}", "-p", "MemorySwapMax=0"] + cmd)


def run_verilator(proto: str, lang: str, tech: str, test: str, waves: bool,
                  sram_path: str, work_dir: str, coverage: bool = False) -> tuple:
    """Build (verilator --binary --timing) and run the SV bench. Returns (passed, summary).

    SV only: Verilator has no VHDL. --vpi plus the public leaf arrays of
    verification/testbench/sram_tb.vlt give the backdoor its VPI access. The
    bench skews its procedural drives by 1 ns on Verilator (sram_tb_drv.svh).
    One build per protocol / technology; --test only changes the run."""
    os.makedirs(work_dir, exist_ok=True)
    results = os.path.join(work_dir, "results.log")
    tb_top = f"tb_sram_{proto}"
    tests = os.path.join(sram_path, "verification", "tests")
    tbdir = os.path.join(sram_path, "verification", "testbench")
    obj = os.path.join(work_dir, "obj")
    defs = [f"+define+{d}" for d in tech_defines(tech, lang)]
    jobs = str(VERILATOR_BUILD_JOBS)          # -j: Verilator's own threads (and the default)
    build_jobs = str(VERILATOR_BUILD_JOBS_PROTO.get(proto, VERILATOR_BUILD_JOBS))  # g++ jobs
    cmd = (["verilator", "--binary", "--timing", "-j", jobs, "--build-jobs", build_jobs,
            "--top-module", tb_top,
            "--timescale", "1ns/1ps", "--vpi", "-Mdir", obj,
            # lint is lint_sram.py's job (Step 8); keep the build to errors
            "-Wno-fatal", "-Wno-lint", "-Wno-style",
            f"+incdir+{tests}", f"+incdir+{tbdir}"]
           + (["--trace-fst"] if waves else []) + defs
           + [os.path.join(tbdir, "sram_tb.vlt")]
           + macro_models(tech, sram_path, work_dir)
           + sv_files(proto, sram_path) + dpi_files(sram_path))
    tag = f"[verilator/{proto}_{lang}/{tech}]"
    print(f"  {tag} Building ...")
    out, rc = _run(_mem_capped(cmd), work_dir, 3600)
    with open(os.path.join(work_dir, "compile.log"), "w") as fh:
        fh.write(" ".join(cmd) + "\n\n" + out)
    if rc != 0:
        print(f"  {tag} Build FAILED (see {work_dir}/compile.log"
              + (f"; memory cap {VERILATOR_MEM_MAX}"
                 if rc in (-9, 137) or "] Terminated" in out or "] Killed" in out else "")
              + ")")
        _write_result(results, "FAIL", out)
        return False, "build failed"
    print(f"  {tag} Simulating (+test={test}) ...")
    plus = [f"+test={test}"] + (["+waves"] if waves else [])
    sim_out, rc = _run(_mem_capped([os.path.join(obj, f"V{tb_top}")] + plus), work_dir, 3600)
    with open(os.path.join(work_dir, "sim.log"), "w") as fh:
        fh.write(sim_out)
    ok = _passed(sim_out, tb_top) and rc == 0
    summ = _summary_line(sim_out, tb_top) or f"no PASS line (rc {rc})"
    print(f"  {tag} {summ}")
    _write_result(results, "PASS" if ok else "FAIL", sim_out)
    return ok, summ


def quartus_sim_lib() -> str:
    """Quartus simulation models (altera_mf.v / .vhd): $QUARTUS_PATH/../eda/sim_lib."""
    qp = os.environ.get("QUARTUS_PATH", "/opt/intelFPGA_lite/23.1std/quartus/bin")
    return os.path.normpath(os.path.join(qp, "..", "eda", "sim_lib"))


def run_xsim(proto: str, lang: str, tech: str, test: str, waves: bool,
             sram_path: str, work_dir: str, coverage: bool = False) -> tuple:
    """Compile (xvlog / xvhdl), elaborate (xelab) and run (xsim) the SV bench with
    the Vivado simulator. Returns (passed, summary).

    --lang vhdl: the VHDL tops under the SV bench (mixed language). TB_NO_BACKDOOR:
    xsim has no VPI / VHPI. XILINX: -L xpm (Vivado's precompiled XPM). ALTERA: the
    Quartus altera_mf model, Verilog into work (SV DUT) or VHDL into library
    altera_mf (VHDL DUT: xsim does not apply Verilog port defaults to a VHDL
    component, and the single-port leaf leaves altsyncram's unused ports out)."""
    os.makedirs(work_dir, exist_ok=True)
    results = os.path.join(work_dir, "results.log")
    tb_top = f"tb_sram_{proto}"
    tests = os.path.join(sram_path, "verification", "tests")
    tbdir = os.path.join(sram_path, "verification", "testbench")
    defs = []
    for d in tech_defines(tech, lang) + ["TB_NO_BACKDOOR"]:
        defs += ["-d", d]
    incs = ["-i", tests, "-i", tbdir]
    steps = []
    libs = []
    if tech == "xilinx":
        libs = ["-L", "xpm"]
    elif tech == "altera":
        sim_lib = quartus_sim_lib()
        if lang == "sv":
            steps.append(["xvlog", os.path.join(sim_lib, "altera_mf.v")])
        else:
            steps.append(["xvhdl", "-work", "altera_mf",
                          os.path.join(sim_lib, "altera_mf_components.vhd"),
                          os.path.join(sim_lib, "altera_mf.vhd")])
            libs = ["-L", "altera_mf"]
    if lang == "sv":
        steps.append(["xvlog", "-sv"] + defs + incs + sv_files(proto, sram_path))
    else:
        steps.append(["xvhdl", "-2008"] + vhdl_files(proto, sram_path))
        steps.append(["xvlog", "-sv"] + defs + incs + bench_files(proto, sram_path))
    steps.append(["xelab", "-timescale", "1ns/1ps"] + libs
                 + (["-debug", "typical"] if waves else []) + [tb_top, "-s", "snap"])
    tag = f"[xsim/{proto}_{lang}/{tech}]"
    print(f"  {tag} Compiling ...")
    log_txt = ""
    rc = 0
    for cmd in steps:
        out, rc = _run(cmd, work_dir, 1800)
        log_txt += " ".join(cmd) + "\n\n" + out + "\n"
        if rc != 0 or "ERROR:" in out:
            rc = rc or 1
            break
    with open(os.path.join(work_dir, "compile.log"), "w") as fh:
        fh.write(log_txt)
    if rc != 0:
        print(f"  {tag} Compile FAILED (see {work_dir}/compile.log)")
        _write_result(results, "FAIL", log_txt)
        return False, "compile failed"
    print(f"  {tag} Simulating (+test={test}) ...")
    cmd = ["xsim", "snap", "-testplusarg", f"test={test}"]
    if waves:
        tcl = os.path.join(work_dir, "waves.tcl")
        with open(tcl, "w") as fh:
            fh.write("open_vcd waves.vcd\nlog_vcd -level 0 [get_objects -r /*]\n"
                     "run all\nclose_vcd\nexit\n")
        cmd += ["-tclbatch", tcl]
    else:
        cmd += ["-R"]
    sim_out, rc = _run(cmd, work_dir, 3600)
    with open(os.path.join(work_dir, "sim.log"), "w") as fh:
        fh.write(sim_out)
    ok = _passed(sim_out, tb_top) and "FATAL_ERROR" not in sim_out
    summ = _summary_line(sim_out, tb_top) or f"no PASS line (rc {rc})"
    print(f"  {tag} {summ}")
    _write_result(results, "PASS" if ok else "FAIL", sim_out)
    return ok, summ


# ---------------------------------------------------------------------------
# VHDL toggle constants
#
# VCS filters constant (structurally unreachable) code out of line, condition
# and toggle coverage in Verilog, but in VHDL only out of line and condition:
# a VHDL signal tied off by a generic (port B of a single port, the ECC pins
# with ECC_EN = 0, ...) counts as an untoggled bit. The SV twin of every VHDL
# unit is compiled with the same parameters, and its constant analysis
# (-cm_noconst -cm_seqnoconst) marks those bits Unreachable. vhdl_toggle_el()
# carries that result over: a VHDL bit that did not toggle is excluded when
# the SV twin of the same unit, with the same generic values, has it
# Unreachable (same signal name, same bit, same direction). Every exclusion is
# listed in vhdl_const_excl.txt next to the exclusion file.
# ---------------------------------------------------------------------------
def _cov_params(text: str) -> dict:
    """Parameter / generic list of a urg section header -> {NAME: value}."""
    import re
    out = {}
    for m in re.finditer(r'([A-Za-z_][A-Za-z_0-9]*)\s*=\s*("[^"]*"|[^,]*)', text):
        out[m.group(1).upper()] = m.group(2).strip().strip('"')
    return out


def _toggle_sections(modinfo: str) -> list:
    """Toggle sections of a urg text modinfo.txt: one dict per module and
    parameter set with module, params, instances and rows
    (name, bits or None, toggle, 1->0, 0->1)."""
    import re
    head = re.compile(r"^Toggle Coverage for Module : (\S+)(?: RTL)?(?: \( (?:generic|parameter) "
                      r"(.*) \))?\s*$")
    row = re.compile(r"^(\S+?)(?:\[(\d+)(?::(\d+))?\])?\s+(Yes|No|Unreachable|Excluded)\s+"
                     r"(Yes|No|Unreachable|Excluded)\s+(Yes|No|Unreachable|Excluded)\b")
    secs, cur, state = [], None, ""
    with open(modinfo) as fh:
        for line in fh:
            line = line.rstrip("\n")
            m = head.match(line)
            if m:
                name = m.group(1).split(".")[-1].lower()
                cur = {"module": name, "params": _cov_params(m.group(2) or ""),
                       "instances": [], "rows": [], "vhdl": "." in m.group(1),
                       "pct": None, "tot": 0, "cov": 0}
                secs.append(cur)
                state = "head"
                continue
            if cur is None:
                continue
            if line.startswith(("Line Coverage for Module", "Cond Coverage for Module",
                                "FSM Coverage for Module", "Branch Coverage for Module",
                                "Assert Coverage for Module")):
                cur, state = None, ""
                continue
            if state == "head" and line.startswith("Toggle Coverage for Module self-instances"):
                state = "inst"
            elif state == "inst":
                if line.startswith("-"):
                    state = "body"
                elif line.strip():
                    cur["instances"].append(line.strip())
            elif state == "body":
                f = line.split()
                if cur["pct"] is None and len(f) == 2 and f[0][0].isdigit():
                    cur["pct"] = float(f[1])          # SCORE TOGGLE (exclusions applied)
                elif line.startswith("Total Bits ") and len(f) == 5:
                    cur["tot"], cur["cov"] = int(f[2]), int(f[3])
                r = row.match(line)
                if r:
                    hi = r.group(2)
                    lo = r.group(3) if r.group(3) is not None else hi
                    bits = None if hi is None else range(int(lo), int(hi) + 1)
                    cur["rows"].append((r.group(1), bits, r.group(4), r.group(5), r.group(6)))
    return secs


# VHDL objects VCS covers that have no SV counterpart in the report: memory
# arrays (SV memories are toggle-covered only with -cm_tgl mda, which the SV
# runs do not use). Their untoggled bits are excluded like the constants.
VHDL_TOGGLE_UNMEASURED = {"sram_macro_generic": ("MEM",)}


def _norm_sig(name: str) -> str:
    """Signal name for SV <-> VHDL matching: lower case, array index in []."""
    import re
    return re.sub(r"\((\d+)\)", r"[\1]", name).lower()


def vhdl_toggle_el(vhdl_dir: str, sv_dir: str) -> str:
    """Write <vhdl_dir>/vhdl_const.el (urg exclusion file) and
    vhdl_const_excl.txt from the two runs' text reports; returns the .el path
    ("" when either report is missing)."""
    rep = {}
    for tag, d in (("vhdl", vhdl_dir), ("sv", sv_dir)):
        out = os.path.join(d, "cov_report_raw")
        _run(["urg", "-full64", "-dir", os.path.join(d, "cov.vdb"), "-format", "text",
              "-report", out], d, 1800)
        rep[tag] = os.path.join(out, "modinfo.txt")
        if not os.path.exists(rep[tag]):
            return ""
    sv = _toggle_sections(rep["sv"])
    # urg merges parameter sets with the same toggle shape into one section,
    # whose header shows one of them: an instance is matched to the SV section
    # holding the same instance path first, by parameter values otherwise.
    sv_by_inst = {}
    for t in sv:
        for i in t["instances"]:
            sv_by_inst[_norm_sig(i)] = t

    def unreachable(twins):
        """(signal, bit) -> directions Unreachable in every twin."""
        unr = None
        for t in twins:
            u = {}
            for name, bits, tog, t10, t01 in t["rows"]:
                dirs = {d for d, v in (("1to0", t10), ("0to1", t01)) if v == "Unreachable"}
                if dirs:
                    for b in (bits if bits is not None else [None]):
                        u[(_norm_sig(name), b)] = dirs
            unr = u if unr is None else {k: v & u[k] for k, v in unr.items() if k in u}
        return unr or {}

    el_lines, audit = [], []
    for sec in _toggle_sections(rep["vhdl"]):
        gen = {k: v.strip("'") for k, v in sec["params"].items() if k != "INIT_FILE"}
        by_param = [t for t in sv if t["module"] == sec["module"] and
                    all(t["params"].get(k, v) == v for k, v in gen.items())]
        for inst in sec["instances"]:
            t = sv_by_inst.get(_norm_sig(inst))
            twins = [t] if t is not None and t["module"] == sec["module"] else by_param
            if not twins:
                continue
            unr = unreachable(twins)
            skip = VHDL_TOGGLE_UNMEASURED.get(sec["module"], ())
            excl = []
            for name, bits, tog, t10, t01 in sec["rows"]:
                if tog == "Yes":
                    continue
                miss = {d for d, v in (("1to0", t10), ("0to1", t01)) if v == "No"}
                if name.split("(")[0] in skip:
                    if miss:
                        kind = "" if len(miss) == 2 else f"{next(iter(miss))} "
                        rng = "" if bits is None else (f" [{bits[-1]}:{bits[0]}]" if len(bits) > 1
                                                       else f" [{bits[0]}]")
                        excl.append(f"Toggle {kind}{name}{rng}")
                    continue
                groups = {}   # direction set -> bits
                for b in (bits if bits is not None else [None]):
                    dirs = frozenset(miss & unr.get((_norm_sig(name), b), set()))
                    if dirs:
                        groups.setdefault(dirs, []).append(b)
                for dirs, bl in groups.items():
                    kind = "" if len(dirs) == 2 else f"{next(iter(dirs))} "
                    if bl == [None]:
                        excl.append(f"Toggle {kind}{name}")
                        continue
                    # consecutive runs of bits -> [hi:lo]
                    bl.sort()
                    start = prev = bl[0]
                    for b in bl[1:] + [None]:
                        if b is not None and b == prev + 1:
                            prev = b
                            continue
                        rng = f"[{prev}:{start}]" if prev != start else f"[{start}]"
                        excl.append(f"Toggle {kind}{name} {rng}")
                        if b is not None:
                            start = prev = b
            if excl:
                el_lines.append(f"INSTANCE: {inst}")
                el_lines += excl
                audit += [f"{inst}  {e[len('Toggle '):]}" for e in excl]
    el = os.path.join(vhdl_dir, "vhdl_const.el")
    with open(el, "w") as fh:
        fh.write("// VHDL toggle bits that are constant by construction: Unreachable in the\n"
                 f"// SV twin's constant analysis ({sv_dir}). Written by sim_sram.py.\n")
        fh.write("\n".join(el_lines) + "\n")
    with open(os.path.join(vhdl_dir, "vhdl_const_excl.txt"), "w") as fh:
        fh.write(f"{len(audit)} VHDL toggle exclusions (instance, signal [bits]): Unreachable "
                 f"in {sv_dir}, or untoggled bits of a VHDL memory array "
                 f"({VHDL_TOGGLE_UNMEASURED})\n")
        fh.write("\n".join(audit) + "\n")
    return el


def _el_args(run_dir: str) -> list:
    el = os.path.join(run_dir, "vhdl_const.el")
    return ["-elfile", el, "-excl_bypass_checks"] if os.path.exists(el) else []


def _vhdl_toggle_fix(modinfo: str, total: str, mods: dict) -> tuple:
    """Apply the VHDL toggle exclusions (vhdl_const.el) to the module list.

    urg applies INSTANCE exclusions to each parameter set's toggle score but not
    to the module-definition list. Each VHDL module's toggle is recomputed from
    its parameter sets: covered / (covered / score), i.e. the toggle targets
    left after the exclusions; SCORE is the mean of the available metrics, as
    in urg. The run total is recomputed the same way over every parameter set.
    """
    secs = _toggle_sections(modinfo)
    if not any(s_["vhdl"] for s_ in secs):
        return total, mods
    acc = {}
    for sec in secs:
        name = sec["module"] + (" (vhdl)" if sec["vhdl"] else "")
        eff = sec["cov"] / (sec["pct"] / 100.0) if sec["pct"] else sec["tot"]
        c, e = acc.get(name, (0.0, 0.0))
        acc[name] = (c + sec["cov"], e + eff)

    def rescore(vals, tgl):
        v = list(vals)
        v[3] = f"{tgl:.2f}"
        nums = [float(x) for x in v[1:] if x != "--"]
        v[0] = f"{sum(nums) / len(nums):.2f}"
        return tuple(v)
    for name, (c, e) in acc.items():
        if name.endswith("(vhdl)") and name in mods and e > 0 and mods[name][3] != "--":
            mods[name] = rescore(mods[name], 100.0 * c / e)
    tc = sum(c for c, _ in acc.values())
    te = sum(e for _, e in acc.values())
    if total and te > 0:
        total = "  ".join(rescore(["0"] + total.split()[1:], 100.0 * tc / te))
    return total, mods


def _parse_modlist(path: str) -> tuple:
    """(total line, {module: (score, line, cond, tgl, fsm, branch)}) from urg modlist.txt;
    the first row of a module is its merged (all parameter sets) result. VHDL
    toggle exclusions are applied from modinfo.txt (_vhdl_toggle_fix)."""
    import re
    num = r"([0-9.]+|--)"
    # SV: "sram_core"; VHDL: "DEFAULT.SRAM_CORE RTL" (reported as "sram_core (vhdl)")
    row = re.compile(r"^\s*" + r"\s+".join([num] * 6)
                     + r"\s+(?:([A-Za-z_0-9]+)\.)?([A-Za-z_0-9]+)( [A-Za-z_0-9]+)?\s*$")
    mods, total = {}, ""
    with open(path) as fh:
        lines = fh.read().splitlines()
    for i, line in enumerate(lines):
        if line.startswith("Total Module Definition Coverage Summary"):
            total = lines[i + 2].strip()
        m = row.match(line)
        if not m:
            continue
        name = m.group(8).lower() + (" (vhdl)" if m.group(7) else "")
        if name not in mods and not name.startswith("tb_"):
            mods[name] = m.groups()[:6]
    modinfo = os.path.join(os.path.dirname(path), "modinfo.txt")
    if os.path.exists(modinfo):
        total, mods = _vhdl_toggle_fix(modinfo, total, mods)
    return total, mods


def per_run_coverage(work_base: str, run_dirs: list, rpt: str) -> list:
    """One urg report per run (one bus x technology): coverage/per_run.txt lists
    each run's total and its weakest module, and per_run_modules.txt every
    module of every run."""
    def one(d):
        d = os.path.abspath(d)
        out = os.path.join(d, "cov_report")
        _run(["urg", "-full64", "-dir", os.path.join(d, "cov.vdb"), "-format", "text",
              "-report", out] + _el_args(d), d, 1800)
        return d, _parse_modlist(os.path.join(out, "modlist.txt")) \
            if os.path.exists(os.path.join(out, "modlist.txt")) else ("", {})
    with concurrent.futures.ThreadPoolExecutor(8) as ex:
        res = sorted(ex.map(one, run_dirs))
    hdr = f"{'run':28}{'SCORE':>7}{'LINE':>7}{'COND':>7}{'TOGGLE':>7}{'FSM':>7}{'BRANCH':>7}"
    with open(os.path.join(rpt, "per_run.txt"), "w") as fh, \
         open(os.path.join(rpt, "per_run_modules.txt"), "w") as fm:
        fh.write("sram code coverage per run (bus x technology), and the weakest module\n")
        fh.write(hdr + "  weakest module (score)\n")
        for d, (total, mods) in res:
            label = "/".join(d.split(os.sep)[-2:])
            worst = min(mods.items(), key=lambda kv: float(kv[1][0])) if mods else ("-", ("0",))
            fh.write(f"{label:28}" + "".join(f"{v:>7}" for v in total.split())
                     + f"  {worst[0]} ({worst[1][0]})\n")
            fm.write(f"== {label}\n")
            for name, v in sorted(mods.items(), key=lambda kv: float(kv[1][0])):
                fm.write(f"  {name:26}" + "".join(f"{x:>7}" for x in v) + "\n")
    print(f"  [coverage] per-run reports -> {rpt}/per_run.txt")
    return res


def _urg_merge(work_base: str, vdbs: list, rpt: str, tag: str) -> tuple:
    """urg merge by module definition of vdbs into rpt; returns (total, mods) or None."""
    cmd = (["urg", "-full64", "-lca", "-flex_merge", "modules", "-format", "both",
            # The .vdb suffix keeps the database inside work/: without it urg
            # writes <work_base>.vdb next to the work directory.
            "-report", rpt, "-dbname", os.path.join(work_base, f"coverage_merged{tag}.vdb")]
           + sum((["-dir", v] for v in vdbs), []))
    out, rc = _run(cmd, work_base, 1800)
    log = os.path.join(work_base, f"coverage_urg{tag}.log")
    with open(log, "w") as fh:
        fh.write(" ".join(cmd) + "\n\n" + out)
    if rc != 0 or not os.path.exists(os.path.join(rpt, "modlist.txt")):
        print(f"  [coverage] urg merge FAILED or empty (rc {rc}), see {log}")
        return None
    return _parse_modlist(os.path.join(rpt, "modlist.txt"))


def _write_summary(path: str, title: str, total: str, mods: dict) -> None:
    with open(path, "w") as fh:
        fh.write(title + "\n")
        fh.write(f"{'':30}{'SCORE':>7}{'LINE':>7}{'COND':>7}{'TOGGLE':>7}{'FSM':>7}{'BRANCH':>7}\n")
        fh.write(f"{'TOTAL':30}" + "".join(f"{v:>7}" for v in total.split()) + "\n")
        for name, v in sorted(mods.items(), key=lambda kv: float(kv[1][0])):
            fh.write(f"{name:30}" + "".join(f"{x:>7}" for x in v) + "\n")


def merge_coverage(work_base: str, work_dirs: list) -> None:
    """Merge the runs' cov.vdb with urg; reports in work/coverage/.

    The runs are different designs (one top per protocol, one macro leaf per
    technology), so a plain urg merge keeps only the first design's
    instances. "-flex_merge modules" (an LCA feature, hence -lca) merges code
    coverage by module definition across the different hierarchies.

    SV and VHDL runs are merged separately:
      coverage/summary.txt        SV runs (urg, exact)
      coverage/vhdl/summary.txt   VHDL runs: line / cond / FSM / branch from the
                                  urg merge; toggle = the best single run after
                                  its constant exclusions (a lower bound of the
                                  union: the merge cannot apply per-instance
                                  exclusions, its instances are the first run's)
      coverage/per_run.txt        each bus x language x technology on its own
    """
    vdbs = [os.path.join(d, "cov.vdb") for d in work_dirs
            if os.path.isdir(os.path.join(d, "cov.vdb"))]
    if not vdbs:
        print("  [coverage] no VCS coverage databases (coverage is collected with VCS only)")
        return

    def is_vhdl(v):
        return os.path.basename(os.path.dirname(v)).split("_")[1:2] == ["vhdl"]
    # VHDL runs: toggle exclusions from the SV twin (same protocol and technology)
    for v in vdbs:
        d = os.path.dirname(v)
        if not is_vhdl(v):
            continue
        twin = d.replace("_vhdl_", "_sv_")
        if os.path.isdir(os.path.join(twin, "cov.vdb")) and vhdl_toggle_el(d, twin):
            print(f"  [coverage] {os.path.basename(d)}: VHDL toggle constants from "
                  f"{os.path.basename(twin)} -> {d}/vhdl_const_excl.txt")
        else:
            print(f"  [coverage] {os.path.basename(d)}: no SV twin coverage ({twin}); VHDL "
                  "toggle constants are not excluded")
    rpt = os.path.join(work_base, "coverage")
    # urg replaces its report directory: SV merge first, then the VHDL merge
    # (coverage/vhdl/), then the per-run reports.
    sv = [v for v in vdbs if not is_vhdl(v)]
    vh = [v for v in vdbs if is_vhdl(v)]
    if sv:
        r = _urg_merge(work_base, sv, rpt, "")
        if r:
            _write_summary(os.path.join(rpt, "summary.txt"),
                           f"sram code coverage, {len(sv)} SV runs (VCS) merged by module "
                           "definition", *r)
            print(f"  [coverage] merged {len(sv)} SV runs -> {rpt}/summary.txt "
                  "(HTML: dashboard.html)")
            print(f"  [coverage] SV total SCORE LINE COND TOGGLE FSM BRANCH: {r[0]}")
    os.makedirs(rpt, exist_ok=True)
    runs = per_run_coverage(work_base, [os.path.dirname(v) for v in vdbs], rpt)
    if vh:
        vrpt = os.path.join(rpt, "vhdl")
        r = _urg_merge(work_base, vh, vrpt, "_vhdl")
        if r:
            total, mods = r
            best, best_total = {}, 0.0
            for d, (t, m) in runs:
                if "_vhdl_" not in os.path.basename(d):
                    continue
                if t and t.split()[3] != "--":
                    best_total = max(best_total, float(t.split()[3]))
                for name, x in m.items():
                    if x[3] != "--":
                        best[name] = max(best.get(name, 0.0), float(x[3]))

            def rescore(x, tgl):
                x = list(x)
                x[3] = f"{tgl:.2f}"
                nums = [float(y) for y in x[1:] if y != "--"]
                x[0] = f"{sum(nums) / len(nums):.2f}"
                return tuple(x)
            mods = {n: (rescore(x, best[n]) if n in best and x[3] != "--" else x)
                    for n, x in mods.items()}
            total = "  ".join(rescore(["0"] + total.split()[1:], best_total))
            _write_summary(os.path.join(vrpt, "summary.txt"),
                           f"sram code coverage, {len(vh)} VHDL runs (VCS) merged by module "
                           "definition; TOGGLE = best single run after its constant "
                           "exclusions (lower bound of the union)", total, mods)
            print(f"  [coverage] merged {len(vh)} VHDL runs -> {vrpt}/summary.txt")
            print(f"  [coverage] VHDL total SCORE LINE COND TOGGLE FSM BRANCH: {total}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    sram_path = get_sram_path()
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sim", choices=["verilator", "icarus", "ghdl", "modelsim", "xsim",
                                          "vcs", "xcelium", "all"], default=None,
                        help="simulator (default: vcs on csun.edu, verilator elsewhere); "
                             "'all' = vcs + xcelium on csun.edu, verilator + xsim elsewhere")
    parser.add_argument("--proto", choices=SUPPORTED_PROTOS + ["all"], default="ahb")
    parser.add_argument("--lang", choices=SUPPORTED_LANGS + ["all"], default="sv")
    parser.add_argument("--tech", choices=SUPPORTED_TECHS + FPGA_TECHS + ["all"],
                        default="generic",
                        help="all: generic + PDKs (vcs, xcelium; verilator on csun.edu), "
                             "generic (verilator on a standard host), generic + xilinx + "
                             "altera (xsim)")
    parser.add_argument("--test", choices=SUPPORTED_TESTS, default="all")
    parser.add_argument("--waves", action="store_true", help="dump waveforms")
    parser.add_argument("--coverage", action="store_true",
                        help="VCS code coverage (line, cond, fsm, tgl, branch) of the sram RTL "
                             "(vendor macro models excluded); merged report in "
                             "verification/work/coverage/ (summary.txt, dashboard.html)")
    parser.add_argument("--jobs", type=int, default=1,
                        help="runs in parallel (each run has its own work directory)")
    parser.add_argument("--postsyn", action="store_true",
                        help="gate-level: DC netlists + SDF of --proto / --lang (RTL language "
                             "synthesized) / --pdk, VCS (Step 10)")
    parser.add_argument("--no-sdf", action="store_true",
                        help="--postsyn without SDF, +delay_mode_zero (zero-delay gates): tells a timing failure "
                             "from a functional one; results in work/postsyn_nosdf/")
    parser.add_argument("--power", action="store_true",
                        help="PrimePower (Step 12): gate-level runs with SAIF, then report_power per "
                             "netlist (base / opts / dp) at the typical corner; SAED90 skipped")
    parser.add_argument("--pdk", default="all", help="PDK for --postsyn / --power")
    args = parser.parse_args()

    if args.power:
        return run_power(args, sram_path)
    if args.postsyn:
        return run_postsyn(args, sram_path)

    sim = args.sim or ("vcs" if ON_CSUN else "verilator")
    if ON_CSUN and sim in _CSUN_BLOCKED:
        print(f"ERROR: --sim {sim} is not available on *.csun.edu; use vcs or xcelium.")
        return 1
    sims = (["vcs", "xcelium"] if ON_CSUN else ["verilator", "xsim"]) if sim == "all" else [sim]
    protos = SUPPORTED_PROTOS if args.proto == "all" else [args.proto]
    langs = SUPPORTED_LANGS if args.lang == "all" else [args.lang]

    def techs_of(s: str) -> list:
        if args.tech != "all":
            return [args.tech]
        if s == "xsim":
            return XSIM_TECHS
        # Standard hosts have no PDK macro models: Verilator runs GENERIC (a PDK
        # can still be asked for by name where its models are installed).
        return SUPPORTED_TECHS if ON_CSUN else ["generic"]

    work_base = os.path.join(sram_path, "verification", "work")
    os.makedirs(work_base, exist_ok=True)
    runs = []      # (label, runner, args) in report order
    summary = {}
    for s in sims:
        for p in protos:
            for lang in langs:
                if s in ("icarus", "verilator") and lang != "sv" or s == "ghdl" and lang != "vhdl":
                    continue
                for t in techs_of(s):
                    label = f"{s}/{p}_{lang}/{t}"
                    if (s, lang, t) in UNSUPPORTED:
                        summary[label] = ("SKIP", UNSUPPORTED[(s, lang, t)])
                        runs.append((label, None, None))
                        continue
                    if (s not in IMPLEMENTED.get((p, lang), set())
                            or (t in FPGA_TECHS) != (s == "xsim") and t != "generic"):
                        summary[label] = ("FAIL", "not implemented yet")
                        runs.append((label, None, None))
                        continue
                    work_dir = os.path.join(work_base, s, f"{p}_{lang}_{t}")
                    runner = {"vcs": run_vcs, "xcelium": run_xcelium,
                              "verilator": run_verilator, "xsim": run_xsim}[s]
                    runs.append((label, runner,
                                 (p, lang, t, args.test, args.waves, sram_path, work_dir,
                                  args.coverage and s == "vcs")))
    if args.coverage:
        # A VHDL coverage run needs its SV twin (same protocol and technology):
        # the SV constant analysis supplies the VHDL toggle exclusions.
        labels = {label for label, _, _ in runs}
        for label, r, a in list(runs):
            if r is run_vcs and a[1] == "vhdl" and f"vcs/{a[0]}_sv/{a[2]}" not in labels:
                p, t = a[0], a[2]
                runs.append((f"vcs/{p}_sv/{t}", run_vcs,
                             (p, "sv", t, args.test, args.waves, sram_path,
                              os.path.join(work_base, "vcs", f"{p}_sv_{t}"), True)))
                print(f"  [coverage] adding vcs/{p}_sv/{t}: SV twin of the VHDL run "
                      "(toggle constant analysis)")
    workers = max(1, args.jobs)
    if any(r is run_verilator for _, r, _ in runs) and workers > 1:
        # Each Verilator run has its own VERILATOR_MEM_MAX scope; running
        # them in parallel would multiply the budget, so they go one at a time
        # (in their own queue: other simulators keep --jobs).
        print(f"  [verilator] one run at a time (memory budget {VERILATOR_MEM_MAX} "
              f"per run; each build already uses {VERILATOR_BUILD_JOBS} compile jobs)")
    with concurrent.futures.ThreadPoolExecutor(1) as ex_v, \
            concurrent.futures.ThreadPoolExecutor(workers) as ex:
        futs = {(ex_v if r is run_verilator else ex).submit(r, *a): label
                for label, r, a in runs if r is not None}
        for f in concurrent.futures.as_completed(futs):
            ok, summ = f.result()
            summary[futs[f]] = ("PASS" if ok else "FAIL", summ)
    summary = [(label,) + summary[label] for label, _, _ in runs]

    if args.coverage:
        merge_coverage(work_base, [a[6] for _, r, a in runs if r is run_vcs])

    all_pass = (all(st in ("PASS", "SKIP") for _, st, _ in summary)
                and any(st == "PASS" for _, st, _ in summary))
    green, red, reset = "\033[32m", "\033[31m", "\033[0m"
    print("\n" + "=" * 78)
    print(f"sram simulation results (--test {args.test})")
    print("=" * 78)
    for label, st, summ in summary:
        print(f"  {label:<28} {red if st == 'FAIL' else green}{st}{reset}  {summ}")
    print("=" * 78)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    with open(os.path.join(work_base, "results.log"), "w") as fh:
        fh.write(f"{'PASS' if all_pass else 'FAIL'}  sim_sram.py --test {args.test}  {stamp}\n")
        for label, st, summ in summary:
            fh.write(f"{st:<5} {label:<28} {summ}\n")
    print(f"All simulations {green}PASSED{reset}." if all_pass
          else f"One or more simulations {red}FAILED{reset}.")
    return 0 if all_pass else 1


if __name__ == "__main__":
    sys.exit(main())
