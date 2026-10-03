#!/usr/bin/env python3
"""formal_timer.py — Formal verification runner for the timer IP block.

Two formal tools are supported:

  sby  SymbiYosys (open source). SV only, flat wrappers in
       verification/formal/*.sby. Results:
           ${CLAUDE_TIMER_PATH}/verification/formal/results.log
  vcf  Synopsys VC Formal (FPV). All four bus top-levels in BOTH SystemVerilog
       and VHDL-2008, checked with the same SVA checkers bound into the design
       (common bus checkers from ${IP_COMMON_PATH}/verification/formal/ plus
       the timer checkers in verification/formal/vcf/). Results:
           ${CLAUDE_TIMER_PATH}/verification/formal/vcf/results.log
       Run directories: ${CLAUDE_TIMER_PATH}/verification/work/vcf/<top>_<lang>/

--tool auto (default) picks vcf when it is on PATH (e.g. *.csun.edu) and sby
otherwise.

Usage:
    python3 verification/tools/formal_timer.py
    python3 verification/tools/formal_timer.py --tool sby --depth 30
    python3 verification/tools/formal_timer.py --tool vcf --proto apb --lang vhdl
    python3 verification/tools/formal_timer.py --tool vcf --trace   # FSDB per failure
    python3 verification/tools/formal_timer.py --clean
"""

import argparse
import os
import shutil
import subprocess
import sys
from datetime import datetime

PROTOCOLS = ["apb", "ahb", "axi4l", "wb"]
SBY_PATH = "/opt/oss-cad-suite/bin/sby"

# ---------------------------------------------------------------------------
# VC Formal job description (the reusable machinery lives in
# ${IP_COMMON_PATH}/verification/tools/claude_vcf.py)
# ---------------------------------------------------------------------------
SV_RTL = [
    "design/rtl/verilog/timer_reg_pkg.sv",
    "design/rtl/verilog/timer_regfile.sv",
    "design/rtl/verilog/timer_core.sv",
]
VHDL_RTL = [
    "design/rtl/vhdl/timer_reg_pkg.vhd",
    "design/rtl/vhdl/timer_regfile.vhd",
    "design/rtl/vhdl/timer_core.vhd",
]
VCF_CHECKERS = [
    "verification/formal/vcf/timer_regmap_fv.sv",
    "verification/formal/vcf/timer_core_fv.sv",
    "verification/formal/vcf/timer_regfile_fv.sv",
]
VCF_WAIVERS = "verification/formal/vcf/timer_fv_waivers.txt"


def import_claude_vcf(timer_path):
    """Import claude_vcf from ${IP_COMMON_PATH}/verification/tools."""
    common = os.environ.get(
        "IP_COMMON_PATH", os.path.join(timer_path, "..", "..", "common"))
    sys.path.insert(0, os.path.normpath(os.path.join(common, "verification", "tools")))
    import claude_vcf  # noqa: E402  (path set up above)
    return claude_vcf


def vcf_jobs(cv, timer_path, protos, langs, max_time):
    """Build one claude_vcf.VcfJob per (protocol, language)."""
    def ip(rel):
        return os.path.join(timer_path, rel)

    jobs = []
    for proto in protos:
        top = f"timer_{proto}"
        for lang in langs:
            if lang == "vhdl":
                rtl = ([ip(f) for f in VHDL_RTL] + [cv.common_bridge_file(proto, "vhdl")] +
                       [ip(f"design/rtl/vhdl/{top}.vhd")])
            else:
                rtl = ([cv.common_bridge_file(proto, "sv")] + [ip(f) for f in SV_RTL] +
                       [ip(f"design/rtl/verilog/{top}.sv")])
            sva = (cv.common_checker_files(proto) + [ip(f) for f in VCF_CHECKERS] +
                   [ip(f"verification/formal/vcf/{top}_fv.sv"),
                    ip(f"verification/formal/vcf/{top}_fv_bind.sv")])
            jobs.append(cv.VcfJob(
                name=f"{top}_{lang}", top=top, lang=lang, proto=proto,
                rtl_files=rtl, sva_files=sva, bind_module=f"{top}_fv_bind",
                incdirs=[ip("verification/formal/vcf")], max_time=max_time,
            ))
    return jobs


def run_vcf_flow(timer_path, args):
    """Run VC Formal for the selected protocols/languages. Returns exit code."""
    cv = import_claude_vcf(timer_path)
    vcf = cv.find_vcf()
    if not vcf:
        print("ERROR: vcf (Synopsys VC Formal) not found on PATH.")
        return 1

    protos = PROTOCOLS if args.proto == "all" else [args.proto]
    langs = cv.LANGS if args.lang == "all" else [args.lang]
    waivers = cv.load_waivers(os.path.join(timer_path, VCF_WAIVERS))
    work = os.path.join(timer_path, "verification", "work", "vcf")
    results_log = os.path.join(timer_path, "verification", "formal", "vcf", "results.log")

    print(f"[vcf] {cv.vcf_version(vcf)}")
    results = []
    for job in vcf_jobs(cv, timer_path, protos, langs, args.max_time):
        print(f"[vcf] Running {job.name} ...", flush=True)
        r = cv.run_job(job, os.path.join(work, job.name), waivers,
                       traces=args.trace, vcf=vcf)
        results.append(r)
        print(f"[vcf] {cv.summary_line(r)}")
        for p, why in r.failures:
            print(f"        {why:<24} {p.name}")
        # Per-run result, same shape as the other verification results logs.
        with open(os.path.join(work, job.name, "results.log"), "w") as fh:
            fh.write(("PASS" if r.passed else "FAIL") + "\n")

    overall = "PASS" if results and all(r.passed for r in results) else "FAIL"
    lines = [overall, f"Generated: {datetime.now().isoformat(timespec='seconds')}",
             f"Tool: {cv.vcf_version(vcf)}", ""]
    for r in results:
        lines.append(cv.summary_line(r))
        lines += [f"    FAIL   {why:<24} {p.name}" for p, why in r.failures]
        lines += [f"    WAIVED {p.name}  ({why})" for p, why in r.waived]
        lines.append(f"    report: {os.path.relpath(r.report_path, timer_path)}")
    with open(results_log, "w") as fh:
        fh.write("\n".join(lines) + "\n")

    print()
    print("============================================")
    print("VC Formal Results")
    print("============================================")
    for r in results:
        print(" ", cv.summary_line(r))
    print("============================================")
    print(f"Overall: {overall}")
    print(f"Results written to: {results_log}")
    return 0 if overall == "PASS" else 1


def find_sby():
    """Return path to sby, checking SBY_PATH then PATH."""
    if os.path.isfile(SBY_PATH) and os.access(SBY_PATH, os.X_OK):
        return SBY_PATH
    found = shutil.which("sby")
    if found:
        return found
    return None


def run_protocol(sby, formal_dir, proto, depth, work_dir):
    """Run sby for one protocol. Returns (proto, passed, log_lines)."""
    sby_file = os.path.join(formal_dir, f"timer_{proto}.sby")
    out_dir = os.path.join(work_dir, f"timer_{proto}")

    cmd = [sby, "-f", sby_file, "-d", out_dir]
    print(f"[formal] Running timer_{proto} ...")

    result = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        cwd=formal_dir,
    )

    passed = result.returncode == 0
    status = "PASS" if passed else "FAIL"
    print(f"[formal] timer_{proto}: {status}")

    log_lines = [f"  timer_{proto}: {status}\n"]
    log_lines += [f"    {line}\n" for line in result.stdout.splitlines()
                  if "DONE" in line or "failed assertion" in line or "Status:" in line]
    return proto, passed, log_lines


def do_clean(formal_dir):
    """Remove sby and VC Formal run directories."""
    print("Cleaning formal verification artifacts...")
    vcf_work = os.path.join(formal_dir, "..", "work", "vcf")
    if os.path.isdir(vcf_work):
        shutil.rmtree(vcf_work)
        print(f"  removed {os.path.normpath(vcf_work)}")
    for proto in PROTOCOLS:
        for d in [
            os.path.join(formal_dir, f"timer_{proto}"),
            os.path.join(formal_dir, "work", f"timer_{proto}"),
        ]:
            if os.path.isdir(d):
                shutil.rmtree(d)
                print(f"  removed {d}")
    work = os.path.join(formal_dir, "work")
    if os.path.isdir(work):
        shutil.rmtree(work)
        print(f"  removed {work}")
    print("Formal clean complete.")


def main():
    timer_path = os.environ.get("CLAUDE_TIMER_PATH")
    if not timer_path:
        print("ERROR: CLAUDE_TIMER_PATH is not set.")
        print("       Please run:  source timer/setup.sh")
        sys.exit(1)

    parser = argparse.ArgumentParser(
        description="Run formal verification checks on the timer IP block."
    )
    parser.add_argument(
        "--depth",
        type=int,
        default=20,
        help="BMC depth in clock cycles (default: %(default)s)",
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Remove sby and VC Formal run directories and exit",
    )
    parser.add_argument(
        "--tool",
        choices=["auto", "sby", "vcf"],
        default="auto",
        help="formal tool: vcf if on PATH, else sby (default: %(default)s)",
    )
    parser.add_argument("--proto", choices=PROTOCOLS + ["all"], default="all",
                        help="bus top-level (vcf only, default: %(default)s)")
    parser.add_argument("--lang", choices=["sv", "vhdl", "all"], default="all",
                        help="RTL language (vcf only, default: %(default)s)")
    parser.add_argument("--max-time", default="30M",
                        help="VC Formal time budget per job (default: %(default)s)")
    parser.add_argument("--trace", action="store_true",
                        help="VC Formal: save an FSDB counterexample per failure")
    args = parser.parse_args()

    formal_dir = os.path.join(timer_path, "verification", "formal")
    results_log = os.path.join(formal_dir, "results.log")

    if args.clean:
        do_clean(formal_dir)
        sys.exit(0)

    tool = args.tool
    if tool == "auto":
        tool = "vcf" if shutil.which("vcf") else "sby"
    if tool == "vcf":
        sys.exit(run_vcf_flow(timer_path, args))

    sby = find_sby()
    if not sby:
        print("ERROR: sby not found. Install oss-cad-suite or add sby to PATH.")
        sys.exit(1)

    work_dir = os.path.join(formal_dir, "work")
    os.makedirs(work_dir, exist_ok=True)

    pass_count = 0
    fail_count = 0
    all_log_lines = []

    for proto in PROTOCOLS:
        proto, passed, log_lines = run_protocol(sby, formal_dir, proto, args.depth, work_dir)
        all_log_lines += log_lines
        if passed:
            pass_count += 1
        else:
            fail_count += 1

    overall = "PASS" if fail_count == 0 else "FAIL"

    print()
    print("============================================")
    print("Formal Verification Results")
    print("============================================")
    for line in all_log_lines:
        if line.strip().startswith("timer_"):
            print(" ", line.strip())
    print(f"PASS: {pass_count}  FAIL: {fail_count}")
    print("============================================")

    with open(results_log, "w") as fh:
        fh.write(f"{overall}\n")
        for line in all_log_lines:
            fh.write(line)
        fh.write(f"PASS: {pass_count}  FAIL: {fail_count}\n")

    print(f"Results written to: {results_log}")

    if fail_count == 0:
        print("All formal checks PASSED.")
        sys.exit(0)
    else:
        print("One or more formal checks FAILED.")
        sys.exit(1)


if __name__ == "__main__":
    main()
