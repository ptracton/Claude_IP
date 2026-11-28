#!/usr/bin/env python3
"""verify_mst_if.py — Verify the shared claude_<proto>_mst_if master adapters.

The adapters live in IP/common/design/rtl/{verilog,vhdl}/claude_<proto>_mst_if.*
(spec: .agents/IP_SPEC_mem_bus_initiator.md). Each loopback testbench
IP/common/verification/mst_if/tb/tb_claude_<proto>_mst_if.sv connects

  initiator BFM -> claude_<proto>_mst_if (DUT) -> bus -> claude_<proto>_mem_if
  -> claude_mem_model

and checks both sides of the DUT. The DUT and the slave adapter can each be the SV
or the VHDL version ("pairs": sv-sv, sv-vhdl, vhdl-sv, vhdl-vhdl, master first).

  --sim icarus    sv-sv only (Icarus has no VHDL)
  --sim ghdl      vhdl-vhdl only, with the pure-VHDL benches tb_claude_<proto>_mst_if.vhd
  --sim xsim      every pair (mixed-language), Vivado xsim
  --sim modelsim  every pair (mixed-language), ModelSim (Intel FPGA edition)
  --sim vcs       every pair (csun.edu)
  --sim xcelium   every pair (csun.edu)
  --sim local     icarus + ghdl + xsim + modelsim (standard hosts)
  --sim all       every simulator found in PATH
  --width W,...   DATA_W values (default 32,16,8)
  --lint          Verilator -Wall on the SV adapter and GHDL analysis + synthesis
                  check of the VHDL adapter (standard hosts), Yosys synthesis of
                  the SV adapter and of the VHDL adapter (GHDL plugin); SpyGlass on
                  csun.edu when spyglass_vc is in PATH. Also checks that out-of-range
                  parameters stop elaboration in both languages.

  --fpga          out-of-context synthesis of every adapter, SV and VHDL, in Vivado
                  (xc7z010, Zybo-Z7) and Quartus (5CSEMA4U23C6, DE0-Nano-SoC), when
                  vivado / quartus_map are in PATH

Formal (VC Formal, csun.edu) is not set up yet for the master adapters: the run
reports it as SKIPPED.

Requires IP_COMMON_PATH (source any IP's setup.sh). Results: one line per run on
the console and in IP/common/verification/mst_if/results.log. Work files go to
IP/common/verification/mst_if/work/ (removed by --clean).

Examples:
  python3 verify_mst_if.py --sim local --lint
  python3 verify_mst_if.py --sim xsim --pair vhdl-sv --width 32
  python3 verify_mst_if.py --sim vcs --proto apb
"""

import argparse
import datetime
import os
import shutil
import subprocess
import sys

# Protocols whose master adapter exists (the others are added as they are built).
PROTOS = ["apb", "ahb", "axi4l"]
PAIRS = ["sv-sv", "sv-vhdl", "vhdl-sv", "vhdl-vhdl"]
WIDTHS = [32, 16, 8]
# Default widths per protocol (AXI4-Lite allows only 32 and 64).
WIDTHS_BY_PROTO = {"axi4l": [32, 64]}
# Extra testbench parameter sets per protocol (each runs at every width).
VARIANTS = {
    "apb": [{}],
    "ahb": [{"HAS_HWSTRB": 1, "HAS_HNONSEC": 1}, {"HAS_HWSTRB": 0, "HAS_HNONSEC": 0}],
    "axi4l": [{}],
}
# Protocols Icarus cannot simulate (none since the 2026-11-27 slave-adapter fix).
ICARUS_NO = {}
SIM_TIMEOUT_S = 900


def guard_env() -> str:
    common = os.environ.get("IP_COMMON_PATH")
    if not common:
        print("ERROR: IP_COMMON_PATH is not set.")
        print("       Please run:  source <IP>/setup.sh  (any Claude IP)")
        sys.exit(1)
    return common


class Paths:
    def __init__(self, common: str):
        self.common = common
        self.rtl_sv = os.path.join(common, "design", "rtl", "verilog")
        self.rtl_vhdl = os.path.join(common, "design", "rtl", "vhdl")
        self.models = os.path.join(common, "verification", "models")
        self.mst_if = os.path.join(common, "verification", "mst_if")
        self.tb = os.path.join(self.mst_if, "tb")
        self.work = os.path.join(self.mst_if, "work")
        self.results = os.path.join(self.mst_if, "results.log")

    def rtl(self, name: str, lang: str) -> str:
        if lang == "vhdl":
            return os.path.join(self.rtl_vhdl, f"{name}.vhd")
        return os.path.join(self.rtl_sv, f"{name}.sv")

    def tb_sources(self, proto: str):
        return [os.path.join(self.models, "claude_mem_model.sv"),
                os.path.join(self.tb, f"tb_claude_{proto}_mst_if.sv")]


def run(cmd, cwd, log_path, timeout=SIM_TIMEOUT_S, env=None):
    """Run cmd in cwd, append its output to log_path. Returns (rc, output)."""
    try:
        p = subprocess.run(cmd, cwd=cwd, stdin=subprocess.DEVNULL, env=env,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           universal_newlines=True, timeout=timeout)
        out, rc = p.stdout, p.returncode
    except FileNotFoundError:
        out, rc = f"ERROR: {cmd[0]} not found in PATH\n", 127
    except subprocess.TimeoutExpired:
        out, rc = f"ERROR: {cmd[0]} timed out after {timeout}s\n", 124
    with open(log_path, "a") as fh:
        fh.write("$ " + " ".join(cmd) + "\n" + out + "\n")
    return rc, out


def judge_sim(log_path: str, top: str):
    """PASS only if the testbench printed its PASS line and nothing failed."""
    with open(log_path, errors="replace") as fh:
        text = fh.read()
    if f"PASS {top}" not in text:
        fail = [l for l in text.splitlines()
                if "FAIL" in l or "ERROR" in l or "Error-" in l or "*E," in l]
        return False, (fail[0].strip() if fail else "no PASS line in log")
    if "ERROR [claude_mem_model]" in text:
        return False, "memory-bus violation reported by claude_mem_model"
    return True, ""


def fresh_dir(path: str) -> str:
    if os.path.isdir(path):
        shutil.rmtree(path)
    os.makedirs(path)
    return path


# ---------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------

def sources_by_lang(paths: Paths, proto: str, pair: str):
    """(sv_files, vhdl_files) for the DUT and the slave adapter of a pair."""
    mst_lang, slv_lang = pair.split("-")
    sv, vhdl = [], []
    for name, lang in ((f"claude_{proto}_mst_if", mst_lang), (f"claude_{proto}_mem_if", slv_lang)):
        (vhdl if lang == "vhdl" else sv).append(paths.rtl(name, lang))
    return sv, vhdl


def gparams(width, variant):
    p = {"DATA_W": width}
    p.update(variant)
    return p


def run_icarus(paths, proto, pair, width, variant, wdir):
    top = f"tb_claude_{proto}_mst_if"
    log = os.path.join(wdir, "sim.log")
    sv, vhdl = sources_by_lang(paths, proto, pair)
    if vhdl:
        return None, "Icarus has no VHDL"
    if proto in ICARUS_NO:
        return "skip", ICARUS_NO[proto]
    vvp = os.path.join(wdir, "sim.vvp")
    gp = [f"-P{top}.{k}={v}" for k, v in gparams(width, variant).items()]
    rc, _ = run(["iverilog", "-g2012", "-I", paths.tb] + gp + ["-o", vvp]
                + sv + paths.tb_sources(proto), wdir, log)
    if rc != 0:
        return False, "iverilog compile failed"
    run(["vvp", "-n", vvp], wdir, log)
    return judge_sim(log, top)


def run_ghdl(paths, proto, pair, width, variant, wdir):
    top = f"tb_claude_{proto}_mst_if"
    log = os.path.join(wdir, "sim.log")
    if pair != "vhdl-vhdl":
        return None, "GHDL runs only the pure-VHDL pair"
    files = [paths.rtl(f"claude_{proto}_mst_if", "vhdl"), paths.rtl(f"claude_{proto}_mem_if", "vhdl"),
             os.path.join(paths.models, "claude_mem_model.vhd"),
             os.path.join(paths.tb, "mst_if_stim.vhd"), os.path.join(paths.tb, f"{top}.vhd")]
    for f in files:
        rc, _ = run(["ghdl", "-a", "--std=08", f"--workdir={wdir}", f], wdir, log)
        if rc != 0:
            return False, f"ghdl -a failed on {os.path.basename(f)}"
    rc, _ = run(["ghdl", "-e", "--std=08", f"--workdir={wdir}", top], wdir, log)
    if rc != 0:
        return False, "ghdl -e failed"
    gp = [f"-g{k}={v}" for k, v in gparams(width, variant).items()]
    run(["ghdl", "-r", "--std=08", f"--workdir={wdir}", top] + gp, wdir, log)
    return judge_sim(log, top)


def run_xsim(paths, proto, pair, width, variant, wdir):
    top = f"tb_claude_{proto}_mst_if"
    log = os.path.join(wdir, "sim.log")
    sv, vhdl = sources_by_lang(paths, proto, pair)
    if vhdl:
        rc, _ = run(["xvhdl", "-2008"] + vhdl, wdir, log)
        if rc != 0:
            return False, "xvhdl failed"
    rc, _ = run(["xvlog", "-sv", "-i", paths.tb] + sv + paths.tb_sources(proto), wdir, log)
    if rc != 0:
        return False, "xvlog failed"
    # --O0: the default xelab optimizer runs for many minutes on these benches.
    # -timescale: the shared RTL has no `timescale (as for VCS / Xcelium).
    gp = []
    for k, v in gparams(width, variant).items():
        gp += ["-generic_top", f"{k}={v}"]
    rc, _ = run(["xelab", "-debug", "off", "--O0", "-timescale", "1ns/1ps"] + gp
                + [top, "-s", "snap"], wdir, log)
    if rc != 0:
        return False, "xelab failed"
    run(["xsim", "snap", "-R"], wdir, log)
    return judge_sim(log, top)


def run_modelsim(paths, proto, pair, width, variant, wdir):
    top = f"tb_claude_{proto}_mst_if"
    log = os.path.join(wdir, "sim.log")
    sv, vhdl = sources_by_lang(paths, proto, pair)
    rc, _ = run(["vlib", "work"], wdir, log)
    if vhdl:
        rc, _ = run(["vcom", "-2008", "-quiet"] + vhdl, wdir, log)
        if rc != 0:
            return False, "vcom failed"
    rc, _ = run(["vlog", "-sv", "-quiet", "-timescale", "1ns/1ps", "+incdir+" + paths.tb]
                + sv + paths.tb_sources(proto), wdir, log)
    if rc != 0:
        return False, "vlog failed"
    gp = [f"-G{k}={v}" for k, v in gparams(width, variant).items()]
    run(["vsim", "-c", "-quiet", "-t", "1ps"] + gp + ["-do", "run -all; quit -f", top], wdir, log)
    return judge_sim(log, top)


def run_vcs(paths, proto, pair, width, variant, wdir):
    top = f"tb_claude_{proto}_mst_if"
    log = os.path.join(wdir, "sim.log")
    sv, vhdl = sources_by_lang(paths, proto, pair)
    simv = os.path.join(wdir, "simv")
    with open(os.path.join(wdir, "synopsys_sim.setup"), "w") as fh:
        fh.write("WORK > DEFAULT\nDEFAULT : ./work_lib\n")
    os.makedirs(os.path.join(wdir, "work_lib"), exist_ok=True)
    if vhdl:
        rc, _ = run(["vhdlan", "-full64", "-vhdl08"] + vhdl, wdir, log)
        if rc != 0:
            return False, "vhdlan failed"
    rc, _ = run(["vlogan", "-full64", "-sverilog", "-timescale=1ns/1ps", "+incdir+" + paths.tb]
                + sv + paths.tb_sources(proto), wdir, log)
    if rc != 0:
        return False, "vlogan failed"
    gp = [f"-pvalue+{top}.{k}={v}" for k, v in gparams(width, variant).items()]
    rc, _ = run(["vcs", "-full64", "-timescale=1ns/1ps"] + gp + [top, "-o", simv], wdir, log)
    if rc != 0:
        return False, "vcs elaboration failed"
    run([simv], wdir, log)
    return judge_sim(log, top)


def run_xcelium(paths, proto, pair, width, variant, wdir):
    top = f"tb_claude_{proto}_mst_if"
    log = os.path.join(wdir, "sim.log")
    sv, vhdl = sources_by_lang(paths, proto, pair)
    cmd = ["xrun", "-64", "-timescale", "1ns/1ps", "-sv", "-incdir", paths.tb]
    for k, v in gparams(width, variant).items():
        cmd += ["-defparam", f"{top}.{k}={v}"]
    if vhdl:
        cmd += ["-v200x", "-inc_v200x_pkg"] + vhdl
    cmd += sv + paths.tb_sources(proto) + ["-top", top]
    rc, _ = run(cmd, wdir, log)
    ok, why = judge_sim(log, top)
    if ok and rc != 0:
        return False, f"xrun exit code {rc}"
    return ok, why


SIMS = {"icarus": ("iverilog", run_icarus), "ghdl": ("ghdl", run_ghdl), "xsim": ("xvlog", run_xsim),
        "modelsim": ("vsim", run_modelsim),
        "vcs": ("vcs", run_vcs), "xcelium": ("xrun", run_xcelium)}


def sim_flow(paths, sims, protos, pairs, widths):
    results = []
    for sim in sims:
        tool, runner = SIMS[sim]
        if not shutil.which(tool):
            line = f"SKIPPED: sim {sim}  ({tool} not in PATH)"
            print("  " + line)
            results.append((None, line))
            continue
        for proto in protos:
            skipped = set()
            for pair in pairs:
                for variant in VARIANTS[proto]:
                    vtag = "".join(f"_{k.lower()}{v}" for k, v in variant.items())
                    for width in (widths or WIDTHS_BY_PROTO.get(proto, WIDTHS)):
                        name = f"{sim}/{proto}/{pair}/w{width}{vtag}"
                        wdir = fresh_dir(os.path.join(paths.work, "sim", sim, proto, pair,
                                                      f"w{width}{vtag}"))
                        ok, why = runner(paths, proto, pair, width, variant, wdir)
                        if ok is None:
                            continue
                        if ok == "skip":
                            if (sim, proto) not in skipped:
                                line = f"SKIPPED: sim {sim}/{proto}  ({why})"
                                print("  " + line, flush=True)
                                results.append((None, line))
                                skipped.add((sim, proto))
                            continue
                        line = f"{'PASS' if ok else 'FAIL'}: sim {name}" + ("" if ok else f"  ({why})")
                        print("  " + line, flush=True)
                        results.append((ok, line))
    return results


# ---------------------------------------------------------------------------
# Lint
# ---------------------------------------------------------------------------

# Out-of-range parameter values that must stop elaboration (sideband spec rule 6).
BAD_PARAMS = {"apb": [("DATA_W", 12), ("DATA_W", 64), ("ADDR_W", 33)],
              "ahb": [("DATA_W", 24), ("DATA_W", 2048), ("ADDR_W", 65), ("HAS_HWSTRB", 2)],
              "axi4l": [("DATA_W", 16), ("DATA_W", 128), ("ADDR_W", 65)]}


def verilator_flags(paths):
    """Flags from mst_if/lint/verilator.flags ('#' comments and blank lines ignored)."""
    flags = []
    with open(os.path.join(paths.mst_if, "lint", "verilator.flags")) as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#"):
                flags += line.split()
    return flags


def lint_flow(paths, protos):
    results = []
    wroot = fresh_dir(os.path.join(paths.work, "lint"))
    for proto in protos:
        top = f"claude_{proto}_mst_if"
        sv, vhd = paths.rtl(top, "sv"), paths.rtl(top, "vhdl")
        log = os.path.join(wroot, f"{top}.log")

        if shutil.which("verilator"):
            rc, out = run(["verilator"] + verilator_flags(paths) + [sv], wroot, log)
            ok = rc == 0 and "%Warning" not in out and "%Error" not in out
            results.append((ok, f"{'PASS' if ok else 'FAIL'}: lint verilator {top}"))
        else:
            results.append((None, f"SKIPPED: lint verilator {top}  (not in PATH)"))

        if shutil.which("ghdl"):
            gw = fresh_dir(os.path.join(wroot, "ghdl"))
            rc1, _ = run(["ghdl", "-a", "--std=08", f"--workdir={gw}", vhd], wroot, log)
            rc2, out = run(["ghdl", "--synth", "--std=08", f"--workdir={gw}", top], wroot, log)
            ok = rc1 == 0 and rc2 == 0 and "warning" not in out.lower()
            results.append((ok, f"{'PASS' if ok else 'FAIL'}: lint ghdl {top}"))
        else:
            results.append((None, f"SKIPPED: lint ghdl {top}  (not in PATH)"))

        # Parameter checks must stop elaboration in both languages.
        for pname, value in BAD_PARAMS.get(proto, []):
            caught = []
            if shutil.which("verilator"):
                rc, _ = run(["verilator", "--lint-only", f"-G{pname}={value}", sv], wroot, log)
                caught.append(rc != 0)
            if shutil.which("ghdl"):
                gw = os.path.join(wroot, "ghdl")
                rc, _ = run(["ghdl", "--synth", "--std=08", f"--workdir={gw}",
                             f"-g{pname}={value}", top], wroot, log)
                caught.append(rc != 0)
            ok = bool(caught) and all(caught)
            results.append((ok, f"{'PASS' if ok else 'FAIL'}: param-check {top} {pname}={value}"))

        # Yosys synthesis: SV directly, VHDL through the GHDL plugin.
        if shutil.which("yosys"):
            rc, out = run(["yosys", "-q", "-p", f"read_verilog -sv {sv}; synth -top {top}"],
                          wroot, log)
            results.append((rc == 0, f"{'PASS' if rc == 0 else 'FAIL'}: synth yosys {top} (sv)"))
            rc, out = run(["yosys", "-m", "ghdl", "-q", "-p",
                           f"ghdl --std=08 {vhd} -e {top}; synth -top {top}"], wroot, log)
            results.append((rc == 0, f"{'PASS' if rc == 0 else 'FAIL'}: synth yosys+ghdl {top} (vhdl)"))
        else:
            results.append((None, f"SKIPPED: synth yosys {top}  (not in PATH)"))

        if shutil.which("spyglass_vc"):
            results.append((None, f"SKIPPED: lint spyglass {top}  (SpyGlass project not set up yet)"))
    for ok, line in results:
        print("  " + line)
    return results


# ---------------------------------------------------------------------------
# FPGA synthesis (smoke test: the adapters build in both vendors' tools)
# ---------------------------------------------------------------------------

def fpga_flow(paths, protos):
    results = []
    for proto in protos:
        top = f"claude_{proto}_mst_if"
        for lang in ("sv", "vhdl"):
            src = paths.rtl(top, lang)
            if shutil.which("vivado"):
                w = fresh_dir(os.path.join(paths.work, "fpga", "vivado", f"{top}_{lang}"))
                rd = f"read_verilog -sv {src}" if lang == "sv" else f"read_vhdl -vhdl2008 {src}"
                with open(os.path.join(w, "synth.tcl"), "w") as fh:
                    fh.write(f"{rd}\nsynth_design -top {top} -part xc7z010clg400-1 "
                             "-mode out_of_context\nreport_utilization -file util.rpt\n")
                log = os.path.join(w, "vivado.log")
                run(["vivado", "-mode", "batch", "-nojournal", "-nolog", "-source", "synth.tcl"],
                    w, log)
                with open(log, errors="replace") as fh:
                    ok = "synth_design completed successfully" in fh.read()
                results.append((ok, f"{'PASS' if ok else 'FAIL'}: synth vivado {top} ({lang})"))
            else:
                results.append((None, f"SKIPPED: synth vivado {top} ({lang})  (not in PATH)"))
            if shutil.which("quartus_map"):
                w = fresh_dir(os.path.join(paths.work, "fpga", "quartus", f"{top}_{lang}"))
                kind = ("SYSTEMVERILOG_FILE " + src) if lang == "sv" else \
                       ("VHDL_FILE " + src + " -hdl_version VHDL_2008")
                with open(os.path.join(w, "m.qsf"), "w") as fh:
                    fh.write('set_global_assignment -name FAMILY "Cyclone V"\n'
                             "set_global_assignment -name DEVICE 5CSEMA4U23C6\n"
                             f"set_global_assignment -name TOP_LEVEL_ENTITY {top}\n"
                             f"set_global_assignment -name {kind}\n")
                rc, _ = run(["quartus_map", "m"], w, os.path.join(w, "quartus.log"))
                results.append((rc == 0, f"{'PASS' if rc == 0 else 'FAIL'}: synth quartus {top} ({lang})"))
            else:
                results.append((None, f"SKIPPED: synth quartus {top} ({lang})  (not in PATH)"))
    for ok, line in results:
        print("  " + line, flush=True)
    return results


# ---------------------------------------------------------------------------

def main() -> int:
    common = guard_env()
    paths = Paths(common)

    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sim", choices=list(SIMS) + ["local", "all", "none"], default="none")
    ap.add_argument("--lint", action="store_true")
    ap.add_argument("--formal", action="store_true", help="VC Formal (not set up yet)")
    ap.add_argument("--fpga", action="store_true", help="Vivado + Quartus synthesis smoke test")
    ap.add_argument("--proto", choices=PROTOS + ["all"], default="all")
    ap.add_argument("--pair", choices=PAIRS + ["all"], default="all")
    ap.add_argument("--width", default=None,
                    help="comma-separated DATA_W values (default: 32,16,8; AXI4-Lite 32,64)")
    ap.add_argument("--clean", action="store_true", help="remove the work directory and exit")
    args = ap.parse_args()

    if args.clean:
        shutil.rmtree(paths.work, ignore_errors=True)
        print(f"Removed {paths.work}")
        return 0
    if args.sim == "none" and not args.lint and not args.formal and not args.fpga:
        ap.error("nothing to do: give --sim, --lint, --fpga and/or --formal")

    protos = PROTOS if args.proto == "all" else [args.proto]
    pairs = PAIRS if args.pair == "all" else [args.pair]
    widths = [int(w) for w in args.width.split(",")] if args.width else None
    if args.sim == "local":
        sims = ["icarus", "ghdl", "xsim", "modelsim"]
    elif args.sim == "all":
        sims = list(SIMS)
    elif args.sim == "none":
        sims = []
    else:
        sims = [args.sim]

    results = []
    if args.lint:
        print("=== Lint ===")
        results += lint_flow(paths, protos)
    if args.fpga:
        print("=== FPGA synthesis ===")
        results += fpga_flow(paths, protos)
    if sims:
        print("=== Simulation ===")
        results += sim_flow(paths, sims, protos, pairs, widths)
    if args.formal:
        line = "SKIPPED: formal  (master-adapter harness not written yet; csun.edu VC Formal)"
        print("=== Formal ===\n  " + line)
        results.append((None, line))

    ran = [(ok, l) for ok, l in results if ok is not None]
    n_pass = sum(1 for ok, _ in ran if ok)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    os.makedirs(paths.mst_if, exist_ok=True)
    with open(paths.results, "w") as fh:
        fh.write(f"# verify_mst_if.py {' '.join(sys.argv[1:])}  ({stamp})\n")
        for _, line in results:
            fh.write(line + "\n")
        fh.write(f"# {n_pass}/{len(ran)} PASS ({len(results) - len(ran)} skipped)\n")
    print(f"\n{n_pass}/{len(ran)} PASS, {len(results) - len(ran)} skipped "
          f"(summary in {paths.results})")
    return 0 if ran and n_pass == len(ran) else 1


if __name__ == "__main__":
    sys.exit(main())
