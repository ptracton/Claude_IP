#!/usr/bin/env python3
"""uvm_mutants.py — Prove the sram UVM tests can fail (Step 6, .agents/uvm.md).

Each mutant is one textual edit of a copy of design/rtl/verilog (the real RTL
is never touched). uvm_sram.py runs the tests named for it on that copy
(VCS, SV, GENERIC by default); the mutant is "killed" when the run fails.

Usage:
  source IP/system/sram/setup.sh
  python3 $CLAUDE_SRAM_PATH/verification/tools/uvm_mutants.py [--mutant <name>|all]
      [--proto apb|ahb|axi4l|wb] [--sim vcs|xcelium] [--jobs N]

Results: verification/work/uvm/mutants/results.log (first line PASS when every
mutant was killed), one work directory per mutant beside it.
"""

import argparse
import concurrent.futures
import datetime
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sim_sram as ss  # noqa: E402

# name: (file, original text, mutated text, cfg, tests, what it breaks)
MUTANTS = {
    "oor_ok": ("sram_port.sv",
               "assign req_err = oor || dom_err_i[dom]",
               "assign req_err = dom_err_i[dom]",
               "base", "smoke", "no bus error past the last word"),
    "addr_alias": ("sram_port.sv",
                   "assign idx = mem_addr_i[OffW +: IdxW];",
                   "assign idx = mem_addr_i[OffW +: IdxW] & ~(IdxW'(1) << (IdxW - 1));",
                   "base", "smoke", "top word-address bit dropped (upper half aliases)"),
    "lane0_we": ("sram_port.sv",
                 "arr_lane_we_o = NLANES'(mem_be_i);",
                 "arr_lane_we_o = NLANES'(mem_be_i) | NLANES'(1);",
                 "base", "random", "byte lane 0 written on every write"),
    "irq_wr_err": ("sram_port.sv",
                   "err_irq_q    <= (x_valid && rsp_err) ||",
                   "err_irq_q    <= (x_valid && rsp_err && !x_we) ||",
                   "base", "smoke", "no err_irq for a failed write"),
    "ds_ok": ("sram_core.sv",
              "assign dom_err[d]      = PWR_GATE && "
              "(pwr_mode_req_i[2*d +: 2] == sram_pkg::PWR_DS ||",
              "assign dom_err[d]      = PWR_GATE && (1'b0 ||",
              "base", "power", "deep sleep accepts bus accesses"),
    "ecc_no_uncorr": ("sram_port.sv",
                      "assign rsp_err  = x_err || (checked && dec_double);",
                      "assign rsp_err  = x_err;",
                      "full", "ecc", "uncorrectable ECC error answers OKAY"),
    "ecc_no_corr_irq": ("sram_port.sv",
                        "ecc_corr_q   <= ECC_EN && checked && dec_single;",
                        "ecc_corr_q   <= 1'b0;",
                        "full", "ecc", "no ecc_corr pulse"),
    "bist_no_fail": ("sram_bist.sv",
                     "          fail_d = 1'b1;\n        end\n        if (elem_write) begin",
                     "          fail_d = 1'b0;\n        end\n        if (elem_write) begin",
                     "full", "bist", "BIST never reports a failure"),
    "b_read_only": ("sram_core.sv",
                    ".READ_ONLY     (TECH == sram_pkg::TECH_SKY130),",
                    ".READ_ONLY     (1'b1),",
                    "dp", "dp", "port B rejects writes on every technology"),
}


def run_mutant(name: str, args, sram_path: str, base: str) -> tuple:
    f, old, new, cfg, tests, what = MUTANTS[name]
    wd = os.path.join(base, name)
    rtl = os.path.join(wd, "rtl")
    if os.path.isdir(rtl):
        shutil.rmtree(rtl)
    shutil.copytree(os.path.join(sram_path, "design", "rtl", "verilog"), rtl)
    path = os.path.join(rtl, f)
    text = open(path).read()
    if text.count(old) != 1:
        return name, "ERROR", f"original text found {text.count(old)} times in {f}"
    with open(path, "w") as fh:
        fh.write(text.replace(old, new))
    cmd = [sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                        "uvm_sram.py"),
           "--sim", args.sim, "--proto", args.proto, "--lang", "sv", "--tech", "generic",
           "--cfg", cfg, "--test", tests, "--rtl-dir", rtl, "--work", os.path.join(wd, "work")]
    out, rc = ss._run(cmd, wd, 7200)
    with open(os.path.join(wd, "run.log"), "w") as fh:
        fh.write(" ".join(cmd) + "\n\n" + out)
    if "build FAILED" in out:
        return name, "ERROR", "mutant does not compile (see run.log)"
    killed = rc != 0
    first = next((l.strip() for l in out.splitlines() if l.strip().startswith("FAIL ")), "")
    return name, "KILLED" if killed else "SURVIVED", f"{cfg}/{tests}: {what}. {first[:150]}"


def main() -> int:
    sram_path = ss.get_sram_path()
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mutant", choices=list(MUTANTS) + ["all"], default="all")
    ap.add_argument("--proto", choices=ss.SUPPORTED_PROTOS, default="apb")
    ap.add_argument("--sim", choices=["vcs", "xcelium"], default="vcs")
    ap.add_argument("--jobs", type=int, default=1, help="mutants in parallel (max 3)")
    args = ap.parse_args()
    base = os.path.join(sram_path, "verification", "work", "uvm", "mutants")
    os.makedirs(base, exist_ok=True)
    names = list(MUTANTS) if args.mutant == "all" else [args.mutant]
    with concurrent.futures.ThreadPoolExecutor(max(1, min(args.jobs, 3))) as ex:
        res = list(ex.map(lambda n: run_mutant(n, args, sram_path, base), names))
    ok = all(r[1] == "KILLED" for r in res)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    with open(os.path.join(base, "results.log"), "w") as fh:
        fh.write(("PASS" if ok else "FAIL") + "\n")
        fh.write(f"uvm_mutants.py {stamp} ({args.sim}, {args.proto}, SV, GENERIC)\n")
        for n, st, msg in res:
            fh.write(f"{n:16} {st:9} {msg}\n")
    for n, st, msg in res:
        print(f"  {n:16} {st:9} {msg}")
    print(f"{'PASS' if ok else 'FAIL'}: {sum(r[1] == 'KILLED' for r in res)}/{len(res)} "
          f"mutants killed -> {base}/results.log")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
