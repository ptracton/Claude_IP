#!/usr/bin/env python3
"""verify_mem_if.py — Verify the shared claude_<proto>_mem_if memory-bus adapters.

The adapters live in IP/common/design/rtl/{verilog,vhdl}/claude_<proto>_mem_if.*
(see IP/common/design/rtl/mem_bus.md). This script runs, for each protocol
(apb, ahb, axi4l, wb) and each language (sv, vhdl):

  --sim vcs|xcelium|all   directed testbench IP/common/verification/mem_if/tb/
                          tb_claude_<proto>_mem_if.sv. The testbench is SV;
                          the VHDL adapter runs through mixed-language
                          simulation. Also runs claude_mem_if_elab (all four
                          adapters at DATA_W 8/16/64).
  --formal                VC Formal: bus checker + memory-bus checker +
                          end-to-end transfer checker bound into the adapter
                          (IP/common/verification/mem_if/formal/).
  --lint                  SpyGlass lint/lint_rtl on each SV adapter (same
                          goal and report filtering as the timer's lint step).

Requires IP_COMMON_PATH (source any IP's setup.sh). VCS, Xcelium and VC Formal
are csun.edu tools.

Results: one line per run on the console and in
IP/common/verification/mem_if/results.log. Work files go to
IP/common/verification/mem_if/work/ (removed by --clean).

Examples:
  python3 verify_mem_if.py --sim all --formal
  python3 verify_mem_if.py --sim vcs --proto ahb --lang vhdl
  python3 verify_mem_if.py --formal --proto axi4l --max-time 2H
"""

import argparse
import datetime
import os
import re
import shutil
import subprocess
import sys

PROTOS = ["apb", "ahb", "axi4l", "wb"]
LANGS = ["sv", "vhdl"]
SIM_TIMEOUT_S = 600


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
        self.tasks = os.path.join(common, "verification", "tasks")
        self.tests = os.path.join(common, "verification", "tests")
        self.formal = os.path.join(common, "verification", "formal")
        self.mem_if = os.path.join(common, "verification", "mem_if")
        self.tb = os.path.join(self.mem_if, "tb")
        self.mem_if_formal = os.path.join(self.mem_if, "formal")
        self.work = os.path.join(self.mem_if, "work")
        self.results = os.path.join(self.mem_if, "results.log")

    def adapter(self, proto: str, lang: str) -> str:
        if lang == "vhdl":
            return os.path.join(self.rtl_vhdl, f"claude_{proto}_mem_if.vhd")
        return os.path.join(self.rtl_sv, f"claude_{proto}_mem_if.sv")

    def incdirs(self):
        return [self.tasks, self.tests, self.tb]


def run(cmd, cwd, log_path, timeout=SIM_TIMEOUT_S):
    """Run cmd in cwd, append its output to log_path. Returns (rc, output)."""
    try:
        p = subprocess.run(cmd, cwd=cwd, stdin=subprocess.DEVNULL,
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
        fail = [l for l in text.splitlines() if "FAIL" in l or "Error-" in l or "*E," in l]
        return False, (fail[0].strip() if fail else "no PASS line in log")
    if "ERROR [claude_mem_tb_target]" in text:
        return False, "memory-bus protocol violation reported by the model"
    return True, ""


# ---------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------

def sim_sources(paths: Paths, top: str):
    if top == "claude_mem_if_elab":
        return [os.path.join(paths.tb, "claude_mem_if_elab.sv")]
    return [os.path.join(paths.tb, "claude_mem_tb_target.sv"),
            os.path.join(paths.tb, f"{top}.sv")]


def vhdl_adapters(paths: Paths, top: str, proto: str):
    if top == "claude_mem_if_elab":
        return [paths.adapter(p, "vhdl") for p in PROTOS]
    return [paths.adapter(proto, "vhdl")]


def sv_adapters(paths: Paths, top: str, proto: str):
    if top == "claude_mem_if_elab":
        return [paths.adapter(p, "sv") for p in PROTOS]
    return [paths.adapter(proto, "sv")]


def run_vcs(paths: Paths, top: str, proto: str, lang: str, wdir: str):
    log = os.path.join(wdir, "sim.log")
    inc = ["+incdir+" + d for d in paths.incdirs()]
    simv = os.path.join(wdir, "simv")
    if lang == "sv":
        rc, _ = run(["vcs", "-full64", "-sverilog", "-timescale=1ns/1ps", "-debug_acc+all"]
                    + inc + sv_adapters(paths, top, proto) + sim_sources(paths, top)
                    + ["-top", top, "-o", simv], wdir, log)
        if rc != 0:
            return False, "vcs compile failed"
    else:
        with open(os.path.join(wdir, "synopsys_sim.setup"), "w") as fh:
            fh.write("WORK > DEFAULT\nDEFAULT : ./work_lib\n")
        os.makedirs(os.path.join(wdir, "work_lib"), exist_ok=True)
        rc, _ = run(["vhdlan", "-full64", "-vhdl08"] + vhdl_adapters(paths, top, proto),
                    wdir, log)
        if rc != 0:
            return False, "vhdlan failed"
        rc, _ = run(["vlogan", "-full64", "-sverilog", "-timescale=1ns/1ps"] + inc
                    + sim_sources(paths, top), wdir, log)
        if rc != 0:
            return False, "vlogan failed"
        rc, _ = run(["vcs", "-full64", "-debug_acc+all", "-timescale=1ns/1ps", top,
                     "-o", simv], wdir, log)
        if rc != 0:
            return False, "vcs elaboration failed"
    rc, _ = run([simv], wdir, log)
    return judge_sim(log, top)


def run_xcelium(paths: Paths, top: str, proto: str, lang: str, wdir: str):
    log = os.path.join(wdir, "sim.log")
    inc = ["+incdir+" + d for d in paths.incdirs()]
    cmd = ["xrun", "-64", "-access", "+rwc", "-timescale", "1ns/1ps", "-sv"]
    if lang == "vhdl":
        # -v200x: VHDL-2008 for the .vhd files; -inc_v200x_pkg: 2008 additions
        cmd += ["-v200x", "-inc_v200x_pkg"] + vhdl_adapters(paths, top, proto)
    else:
        cmd += sv_adapters(paths, top, proto)
    cmd += inc + sim_sources(paths, top) + ["-top", top]
    rc, _ = run(cmd, wdir, log)
    ok, why = judge_sim(log, top)
    if ok and rc != 0:
        return False, f"xrun exit code {rc}"
    return ok, why


def sim_flow(paths: Paths, sims, protos, langs):
    results = []
    tops = [(f"tb_claude_{p}_mem_if", p) for p in protos] + [("claude_mem_if_elab", "all")]
    for sim in sims:
        for top, proto in tops:
            for lang in langs:
                name = f"{sim}/{top}_{lang}"
                wdir = os.path.join(paths.work, "sim", sim, f"{top}_{lang}")
                if os.path.isdir(wdir):
                    shutil.rmtree(wdir)
                os.makedirs(wdir)
                print(f"  [{name}] running ...", flush=True)
                runner = run_vcs if sim == "vcs" else run_xcelium
                ok, why = runner(paths, top, proto, lang, wdir)
                line = f"{'PASS' if ok else 'FAIL'}: sim {name}" + ("" if ok else f"  ({why})")
                print("  " + line, flush=True)
                results.append((ok, line))
    return results


# ---------------------------------------------------------------------------
# Formal (VC Formal)
# ---------------------------------------------------------------------------

def formal_flow(paths: Paths, protos, langs, max_time, traces):
    sys.path.insert(0, os.path.join(paths.common, "verification", "tools"))
    import claude_vcf as cv  # noqa: E402

    vcf = cv.find_vcf()
    if not vcf:
        line = "FAIL: formal  (vcf not found in PATH — VC Formal is a csun.edu tool)"
        print("  " + line)
        return [(False, line)]
    print(f"  Tool: {cv.vcf_version(vcf)}")
    waivers = cv.load_waivers(os.path.join(paths.mem_if_formal, "claude_mem_if_fv_waivers.txt"))
    results = []
    for proto in protos:
        top = f"claude_{proto}_mem_if"
        for lang in langs:
            job = cv.VcfJob(
                name=f"{top}_{lang}", top=top, lang=lang, proto=proto,
                rtl_files=[paths.adapter(proto, lang)],
                sva_files=[os.path.join(paths.formal, f"claude_{proto}_fv.sv"),
                           os.path.join(paths.formal, "claude_mem_fv.sv"),
                           os.path.join(paths.formal, "claude_mem_xfer_fv.sv"),
                           os.path.join(paths.mem_if_formal, f"{top}_fv.sv"),
                           os.path.join(paths.mem_if_formal, f"{top}_fv_bind.sv")],
                bind_module=f"{top}_fv_bind",
                incdirs=[paths.mem_if_formal],
                max_time=max_time,
            )
            run_dir = os.path.join(paths.work, "formal", job.name)
            print(f"  [formal/{job.name}] running (budget {max_time}) ...", flush=True)
            r = cv.run_job(job, run_dir, waivers, traces=traces, vcf=vcf)
            line = cv.summary_line(r).replace(": ", ": formal ", 1)
            print("  " + line, flush=True)
            for p, why in r.failures:
                print(f"      FAILING {p.kind} {p.name}: {why}")
            for p, why in r.waived:
                print(f"      waived  {p.kind} {p.name}: {why}")
            results.append((r.passed, line))
    return results


# ---------------------------------------------------------------------------
# Lint (SpyGlass, SV only; csun.edu has no working VHDL-2008 lint)
# ---------------------------------------------------------------------------

SPYGLASS_GOAL = "lint/lint_rtl"
# Same filtering as IP/system/timer/verification/tools/lint_timer.py.
SPYGLASS_BENIGN_RULES = {"COM_OPT009", "COM_OPT010"}
SPYGLASS_ROW_RE = re.compile(
    r'^\[\d+\]\s+(\S+)\s+\S+\s+(fatal|error|warning|info)\s+\S+\s+\S+\s+\S+\s+(.*)$',
    re.IGNORECASE,
)


def lint_flow(paths: Paths, protos):
    if not shutil.which("spyglass_vc"):
        line = "FAIL: lint  (spyglass_vc not found in PATH — SpyGlass is a csun.edu tool)"
        print("  " + line)
        return [(False, line)]
    results = []
    for proto in protos:
        top = f"claude_{proto}_mem_if"
        wdir = os.path.join(paths.work, "lint", top)
        if os.path.isdir(wdir):
            shutil.rmtree(wdir)
        os.makedirs(wdir)
        with open(os.path.join(wdir, f"{top}.prj"), "w") as fh:
            fh.write("set_option projectwdir .\nset_option enableSV yes\n"
                     f"set_option top {top}\n"
                     f"read_file -type verilog {{ {paths.adapter(proto, 'sv')} }}\n")
        print(f"  [lint/{top}] running ...", flush=True)
        log = os.path.join(wdir, "spyglass.log")
        run(["spyglass_vc", "-project", f"{top}.prj", "-goal", SPYGLASS_GOAL,
             "-batch", "-app", "lint"], wdir, log)
        rpt = os.path.join(wdir, "vcst_rtdb", "spyglass", top, top, "lint", "lint_rtl",
                           "spyglass_reports", "moresimple.rpt")
        if not os.path.isfile(rpt):
            line = f"FAIL: lint {top}  (no SpyGlass report; see {log})"
            print("  " + line)
            results.append((False, line))
            continue
        real = []
        with open(rpt) as fh:
            for raw in fh:
                m = SPYGLASS_ROW_RE.match(raw.rstrip("\n"))
                if not m:
                    continue
                rule, sev, msg = m.group(1), m.group(2).lower(), m.group(3).strip()
                if rule in SPYGLASS_BENIGN_RULES or (rule == "PrjToTclSummary"
                                                      and "Skipped option" in msg):
                    continue
                real.append(f"{sev:<8} {rule:<24} {msg}")
        ok = not real
        line = f"{'PASS' if ok else 'FAIL'}: lint {top}  ({len(real)} finding(s))"
        print("  " + line)
        for r in real:
            print("      " + r)
        results.append((ok, line))
    return results


# ---------------------------------------------------------------------------

def main() -> int:
    common = guard_env()
    paths = Paths(common)

    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sim", choices=["vcs", "xcelium", "all", "none"], default="none")
    ap.add_argument("--formal", action="store_true", help="run VC Formal")
    ap.add_argument("--lint", action="store_true", help="run SpyGlass lint (SV)")
    ap.add_argument("--proto", choices=PROTOS + ["all"], default="all")
    ap.add_argument("--lang", choices=LANGS + ["all"], default="all")
    ap.add_argument("--max-time", default="30M", help="VC Formal budget per job")
    ap.add_argument("--traces", action="store_true", help="write FSDB counterexamples")
    ap.add_argument("--clean", action="store_true", help="remove the work directory and exit")
    args = ap.parse_args()

    if args.clean:
        shutil.rmtree(paths.work, ignore_errors=True)
        print(f"Removed {paths.work}")
        return 0
    if args.sim == "none" and not args.formal and not args.lint:
        ap.error("nothing to do: give --sim, --formal and/or --lint")

    protos = PROTOS if args.proto == "all" else [args.proto]
    langs = LANGS if args.lang == "all" else [args.lang]
    sims = [] if args.sim == "none" else (["vcs", "xcelium"] if args.sim == "all" else [args.sim])

    results = []
    if args.lint:
        print("=== Lint ===")
        results += lint_flow(paths, protos)
    if sims:
        print("=== Simulation ===")
        results += sim_flow(paths, sims, protos, langs)
    if args.formal:
        print("=== Formal ===")
        results += formal_flow(paths, protos, langs, args.max_time, args.traces)

    n_pass = sum(1 for ok, _ in results if ok)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    with open(paths.results, "w") as fh:
        fh.write(f"# verify_mem_if.py {' '.join(sys.argv[1:])}  ({stamp})\n")
        for _, line in results:
            fh.write(line + "\n")
        fh.write(f"# {n_pass}/{len(results)} PASS\n")
    print(f"\n{n_pass}/{len(results)} PASS  (summary in {paths.results})")
    return 0 if n_pass == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
