#!/usr/bin/env python3
"""sim_sram.py — Directed-simulation runner for the sram IP.

Runs the system testbench (verification/testbench/tb_sram_<proto>.sv: the
SRAMs behind IP/interface/bus_matrix) on one or more technologies. Follows
the timer's sim_timer.py conventions.

Implemented (Step 4):
    proto                lang       simulators
    ahb, apb, axi4l, wb  sv, vhdl   vcs, xcelium (csun.edu)
--lang vhdl runs the same SV bench (BFMs, tests, reference models) around the
VHDL top-levels and the VHDL bus_matrix (+define+VHDL_DUT, mixed language).
Every other protocol / language / simulator combination is reported as FAIL
with "not implemented yet", so a regression never mistakes it for a pass.

Technology (--tech): generic, saed90, saed32, saed14, sky130, or all. PDK runs
compile the vendor SRAM macro models through
IP/common/verification/tools/pdk_sram_models.py. GENERIC also runs the
backdoor tests (IP/common/verification/dpi/claude_backdoor.c).

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
VHDL coverage also runs the SV twin of each run: VCS filters constants out of
VHDL line/condition coverage but not toggle, so the SV twin's Unreachable bits
are excluded from the VHDL toggle (see "VHDL toggle constants" below).
Tests (--test): all, reset, params, access, burst, pipeline, contention, ecc,
power, clear, bist, dp, resetbusy.

Gate-level (--postsyn) and power (--power) simulation arrive with synthesis
(Step 10); the options are accepted and reported as not implemented.
"""

import argparse
import concurrent.futures
import datetime
import os
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
_CSUN_BLOCKED = {"icarus", "ghdl", "modelsim", "xsim"}


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
SUPPORTED_TESTS = ["all", "reset", "params", "access", "burst", "pipeline", "contention",
                   "ecc", "power", "clear", "bist", "dp", "resetbusy"]

# sram_pkg::TECH_* values
TECH_NUM = {"generic": 0, "saed90": 3, "saed32": 4, "saed14": 5, "sky130": 6}

# (proto, lang) pairs that have a testbench, and the simulators that run them
IMPLEMENTED = {(p, lang): {"vcs", "xcelium"} for p in ("ahb", "apb", "axi4l", "wb")
               for lang in ("sv", "vhdl")}

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


def macro_models(tech: str, sram_path: str, work_dir: str) -> list:
    """Vendor SRAM macro models for a PDK (none for GENERIC)."""
    if tech == "generic":
        return []
    sys.path.insert(0, os.path.join(get_common_path(sram_path), "verification", "tools"))
    import pdk_sram_models  # noqa: E402
    return pdk_sram_models.model_files(tech, work_dir)


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
    parser.add_argument("--sim", choices=["icarus", "ghdl", "modelsim", "xsim", "vcs",
                                          "xcelium", "all"], default=None,
                        help="simulator (default: vcs on csun.edu); 'all' = vcs + xcelium "
                             "on csun.edu")
    parser.add_argument("--proto", choices=SUPPORTED_PROTOS + ["all"], default="ahb")
    parser.add_argument("--lang", choices=SUPPORTED_LANGS + ["all"], default="sv")
    parser.add_argument("--tech", choices=SUPPORTED_TECHS + ["all"], default="generic")
    parser.add_argument("--test", choices=SUPPORTED_TESTS, default="all")
    parser.add_argument("--waves", action="store_true", help="dump waveforms")
    parser.add_argument("--coverage", action="store_true",
                        help="VCS code coverage (line, cond, fsm, tgl, branch) of the sram RTL "
                             "(vendor macro models excluded); merged report in "
                             "verification/work/coverage/ (summary.txt, dashboard.html)")
    parser.add_argument("--jobs", type=int, default=1,
                        help="runs in parallel (each run has its own work directory)")
    parser.add_argument("--postsyn", action="store_true", help="gate-level (Step 10)")
    parser.add_argument("--power", action="store_true", help="PrimePower (Step 10/12)")
    parser.add_argument("--pdk", default="all", help="PDK for --postsyn / --power")
    args = parser.parse_args()

    if args.postsyn or args.power:
        print("FAIL: --postsyn / --power are not implemented yet (synthesis is Step 10).")
        return 1

    sim = args.sim or ("vcs" if ON_CSUN else "icarus")
    if ON_CSUN and sim in _CSUN_BLOCKED:
        print(f"ERROR: --sim {sim} is not available on *.csun.edu; use vcs or xcelium.")
        return 1
    sims = (["vcs", "xcelium"] if ON_CSUN else ["icarus", "ghdl", "modelsim", "xsim"]) \
        if sim == "all" else [sim]
    protos = SUPPORTED_PROTOS if args.proto == "all" else [args.proto]
    langs = SUPPORTED_LANGS if args.lang == "all" else [args.lang]
    techs = SUPPORTED_TECHS if args.tech == "all" else [args.tech]

    work_base = os.path.join(sram_path, "verification", "work")
    os.makedirs(work_base, exist_ok=True)
    runs = []      # (label, runner, args) in report order
    summary = {}
    for s in sims:
        for p in protos:
            for lang in langs:
                if s == "icarus" and lang != "sv" or s == "ghdl" and lang != "vhdl":
                    continue
                for t in techs:
                    label = f"{s}/{p}_{lang}/{t}"
                    if s not in IMPLEMENTED.get((p, lang), set()):
                        summary[label] = ("FAIL", "not implemented yet")
                        runs.append((label, None, None))
                        continue
                    work_dir = os.path.join(work_base, s, f"{p}_{lang}_{t}")
                    runner = run_vcs if s == "vcs" else run_xcelium
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
    with concurrent.futures.ThreadPoolExecutor(max(1, args.jobs)) as ex:
        futs = {ex.submit(r, *a): label for label, r, a in runs if r is not None}
        for f in concurrent.futures.as_completed(futs):
            ok, summ = f.result()
            summary[futs[f]] = ("PASS" if ok else "FAIL", summ)
    summary = [(label,) + summary[label] for label, _, _ in runs]

    if args.coverage:
        merge_coverage(work_base, [a[6] for _, r, a in runs if r is run_vcs])

    all_pass = all(st == "PASS" for _, st, _ in summary) and bool(summary)
    green, red, reset = "\033[32m", "\033[31m", "\033[0m"
    print("\n" + "=" * 78)
    print(f"sram simulation results (--test {args.test})")
    print("=" * 78)
    for label, st, summ in summary:
        print(f"  {label:<28} {green if st == 'PASS' else red}{st}{reset}  {summ}")
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
