#!/usr/bin/env python3
"""fw_sram.py — Firmware build and test runner for the sram IP (Step 9).

Steps (each one row or more in the results file):
  host    Host unit tests (firmware/test/): host gcc, C99, -Wall -Wextra -Werror
          -pedantic, -DSRAM_FW_HOST_TEST (memory accesses go to a fault-injecting
          model), with -fsanitize=address,undefined when the compiler supports
          it. One row per check printed by test_sram.
  compile The library sources and the example compiled by host gcc without
          SRAM_FW_HOST_TEST (the real volatile accessors), compile only: catches
          C99 / warning problems where no cross compiler is installed.
  cross   firmware/build.sh for ARM Cortex-M33 (arm-none-eabi-gcc) and RISC-V 32
          (riscv-none-elf-gcc), as the timer. A target whose compiler is not on
          PATH is SKIP (not a failure; csun.edu has none at the moment). Library
          sizes (text/data/bss) from <prefix>-size go into the results file.
  mutants Each entry of MUTANTS (one deliberate bug in src/) is built into
          test_sram, which must then fail (KILLED = PASS row; SURVIVED = FAIL).

Usage:
  source IP/system/sram/setup.sh
  python3 $CLAUDE_SRAM_PATH/verification/tools/fw_sram.py [--skip-host]
      [--skip-compile] [--skip-cross] [--skip-mutants] [--mutant <name>|all]
      [--list-mutants]

Results: verification/firmware/fw_results.log — first line PASS / FAIL, then one
"PASS|FAIL|SKIP <step>/<check>  <note>" row per check, then the size table.
Exit status 0 only when no row is FAIL. Build products: firmware/build/,
firmware/lib/ (removed by cleanup.sh).
"""

import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(_HERE, "..", "..", "..", "..", "common",
                                                 "verification", "tools")))
from ip_tool_base import ON_CSUN  # noqa: E402

CFLAGS = ["-std=c99", "-Wall", "-Wextra", "-Werror", "-pedantic", "-O2", "-g"]
SAN = ["-fsanitize=address,undefined", "-fno-sanitize-recover=all", "-fno-omit-frame-pointer"]
CROSS = [("arm", "arm-cortex-m33", "arm-none-eabi"), ("riscv", "riscv32", "riscv-none-elf")]
TIMEOUT = 600


def run(cmd: list, cwd: str = None, env: dict = None) -> tuple:
    try:
        p = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True,
                           timeout=TIMEOUT)
        return p.returncode, p.stdout + p.stderr
    except FileNotFoundError as exc:
        return 127, str(exc)
    except subprocess.TimeoutExpired:
        return 124, f"timed out after {TIMEOUT} s"


def tail(text: str, n: int = 3) -> str:
    lines = [ln.strip() for ln in text.strip().splitlines() if ln.strip()]
    return " | ".join(lines[-n:])[:200]


def sanitizers_ok(cc: str, bdir: str) -> bool:
    """True when cc can build and run a sanitized program on this host."""
    src = os.path.join(bdir, "san_probe.c")
    exe = os.path.join(bdir, "san_probe")
    with open(src, "w") as fh:
        fh.write("int main(void) { return 0; }\n")
    rc, _ = run([cc] + SAN + [src, "-o", exe])
    return rc == 0 and run([exe])[0] == 0


def step_host(fw: str, cc: str) -> list:
    bdir = os.path.join(fw, "build", "host")
    os.makedirs(bdir, exist_ok=True)
    san = SAN if sanitizers_ok(cc, bdir) else []
    exe = os.path.join(bdir, "test_sram")
    srcs = [os.path.join(fw, "src", f) for f in ("sram_memtest.c", "sram_sideband.c")] + \
           [os.path.join(fw, "test", f) for f in ("sram_test_mem.c", "test_sram.c")]
    inc = ["-I" + os.path.join(fw, d) for d in ("include", "src", "test")]
    rc, out = run([cc] + CFLAGS + san + ["-DSRAM_FW_HOST_TEST"] + inc + srcs + ["-o", exe])
    tag = "sanitizers on" if san else "no sanitizers"
    if rc != 0:
        return [("FAIL", "host/build", f"{tag}: {tail(out)}")]
    rows = [("PASS", "host/build", tag)]
    rc, out = run([exe])
    checks = []
    for ln in out.splitlines():
        m = re.match(r"^(PASS|FAIL) (\S+)(?::\s*(.*))?$", ln)
        if m:
            checks.append((m.group(1), f"host/{m.group(2)}", m.group(3) or ""))
    if not checks:
        checks.append(("FAIL", "host/run", f"no check rows, exit {rc}: {tail(out)}"))
    elif rc != 0 and all(st == "PASS" for st, _, _ in checks):
        checks.append(("FAIL", "host/run", f"exit status {rc}: {tail(out)}"))
    elif not re.search(r"^RESULT: ", out, re.M):
        checks.append(("FAIL", "host/run", f"no RESULT line (crash?): {tail(out)}"))
    return rows + checks


# Mutants of the firmware sources: (name, file in src/, original text, mutated text).
# Each one must make test_sram fail (KILLED); a survivor means a missing check.
MUTANTS = [
    ("march_m3_up", "sram_memtest.c",
     "(march_rw(base, words, 0, bg, ~bg, fail) != SRAM_OK) ||   /* M3 down */",
     "(march_rw(base, words, 1, bg, ~bg, fail) != SRAM_OK) ||   /* M3 down */"),
    ("march_no_m5", "sram_memtest.c",
     "if (check_word(base, i, bg, fail) != SRAM_OK) {",
     "if (0) {"),
    ("march_no_m1_read", "sram_memtest.c",
     "if (check_word(base, i, rd, fail) != SRAM_OK) {",
     "if ((rd != wr) && (rd == bg_never)) {"),
    ("walking_no_zero", "sram_memtest.c",
     "if (check_word(base, i, ~one, fail) != SRAM_OK) {",
     "if (0) {"),
    ("walking_31_bits", "sram_memtest.c", "for (b = 0u; b < 32u; b++) {",
     "for (b = 0u; b < 31u; b++) {"),
    ("addr_bus_no_phase1", "sram_memtest.c",
     "        if (check_word(base, o, SRAM_PAT, fail) != SRAM_OK) {\n            return",
     "        if (0) {\n            return"),
    ("addr_bus_no_phase2", "sram_memtest.c",
     "if ((o != t) && (check_word(base, o, SRAM_PAT, fail) != SRAM_OK)) {",
     "if (0) {"),
    ("addr_in_no_complement", "sram_memtest.c", "for (inv = 0u; inv < 2u; inv++) {",
     "for (inv = 0u; inv < 1u; inv++) {"),
    ("lanes_no_upper_half", "sram_memtest.c", "SRAM_WR16(a + 2u, 0x5678u);",
     "SRAM_WR32(a, 0x56781234u);"),
    ("lanes_first_word_only", "sram_memtest.c", "if ((size > 4u) && (lanes_word(",
     "if ((size > 0x7FFFFFFFu) && (lanes_word("),
    ("report_no_addr", "sram_memtest.c", "fail->addr     = addr;", "fail->addr     = 0u;"),
    ("args_no_align", "sram_memtest.c", "return ((base & 3u) == 0u) && ",
     "return (base == base) && "),
    ("all_skips_checker", "sram_memtest.c",
     "rc = sram_test_march_c(base, size, SRAM_CHECKER, fail);", "rc = SRAM_OK;"),
    ("ack_any_mode", "sram_sideband.c",
     "if ((h->get_pwr_ack(h->ctx, domain) & 3u) == mode) {",
     "if ((h->get_pwr_ack(h->ctx, domain) & 3u) == mode || n == 0u) {"),
    ("timeout_off_by_one", "sram_sideband.c",
     "for (n = 0u; n < dev->timeout; n++) {\n        if ((h->get_pwr_ack",
     "for (n = 0u; n <= dev->timeout; n++) {\n        if ((h->get_pwr_ack"),
    ("set_all_serial", "sram_sideband.c",
     "        dev->hooks->set_pwr_req(dev->hooks->ctx, d, mode);\n    }",
     "        dev->hooks->set_pwr_req(dev->hooks->ctx, d, mode);\n"
     "        (void)wait_ack(dev, d, mode);\n    }"),
    ("clear_no_state_check", "sram_sideband.c",
     "if ((m != SRAM_PWR_RUN) && (m != SRAM_PWR_LS)) {", "if (m > SRAM_PWR_SD) {"),
    ("clear_no_wait", "sram_sideband.c",
     "dev->hooks->pulse_clr(dev->hooks->ctx);\n    return sram_wait_idle(dev);",
     "dev->hooks->pulse_clr(dev->hooks->ctx);\n    return SRAM_OK;"),
    ("bist_ignores_fail", "sram_sideband.c",
     "if ((h->get_status(h->ctx) & SRAM_STATUS_BIST_FAIL) != 0u) {", "if (0) {"),
    ("ecc_accepts_3", "sram_sideband.c", "((bits != 1u) && (bits != 2u))", "(bits > 3u)"),
    ("range_no_x4", "sram_sideband.c", "if ((slice & 3u) != 0u) {", "if (0) {"),
    ("init_no_status_hook", "sram_sideband.c", "(hooks->get_status == 0) || ", ""),
]


def step_mutants(fw: str, cc: str, only: str) -> list:
    """Build test_sram against each mutated source; every mutant must be killed."""
    rows = []
    for name, fname, old, new in MUTANTS:
        if only not in ("all", name):
            continue
        mdir = os.path.join(fw, "build", "mutants", name)
        os.makedirs(mdir, exist_ok=True)
        srcs = []
        for f in ("sram_memtest.c", "sram_sideband.c"):
            with open(os.path.join(fw, "src", f)) as fh:
                text = fh.read()
            if f == fname:
                if text.count(old) != 1:
                    rows.append(("FAIL", f"mutant/{name}",
                                 f"original text found {text.count(old)} times in {f}"))
                    break
                text = text.replace(old, new)
                if name == "march_no_m1_read":   # keep it compiling: read but never check
                    text = text.replace("static int march_rw(",
                                        "static const uint32_t bg_never = 0x13572468u;\n"
                                        "static int march_rw(", 1)
            dst = os.path.join(mdir, f)
            with open(dst, "w") as fh:
                fh.write(text)
            srcs.append(dst)
        else:
            exe = os.path.join(mdir, "test_sram")
            inc = ["-I" + os.path.join(fw, d) for d in ("include", "src", "test")]
            tests = [os.path.join(fw, "test", f) for f in ("sram_test_mem.c", "test_sram.c")]
            rc, out = run([cc, "-std=c99", "-O2", "-w", "-DSRAM_FW_HOST_TEST"] + inc +
                          srcs + tests + ["-o", exe])
            if rc != 0:
                rows.append(("FAIL", f"mutant/{name}", f"does not compile: {tail(out)}"))
                continue
            rc, out = run([exe])
            killers = [ln.split()[1] for ln in out.splitlines() if ln.startswith("FAIL ")]
            if rc != 0:
                rows.append(("PASS", f"mutant/{name}",
                             f"KILLED by {len(killers)} check(s), e.g. "
                             f"{killers[0].rstrip(':') if killers else 'exit ' + str(rc)}"))
            else:
                rows.append(("FAIL", f"mutant/{name}", "SURVIVED (no check failed)"))
    return rows


def step_compile(fw: str, cc: str) -> list:
    bdir = os.path.join(fw, "build", "host_compile")
    os.makedirs(bdir, exist_ok=True)
    rows = []
    inc = ["-I" + os.path.join(fw, d) for d in ("include", "src")]
    for rel in ("src/sram_memtest.c", "src/sram_sideband.c", "examples/sram_example.c"):
        obj = os.path.join(bdir, os.path.basename(rel).replace(".c", ".o"))
        rc, out = run([cc] + CFLAGS + inc + ["-c", os.path.join(fw, rel), "-o", obj])
        rows.append(("PASS" if rc == 0 else "FAIL", f"compile/{os.path.basename(rel)}",
                     "" if rc == 0 else tail(out)))
    return rows


def lib_size(prefix: str, lib: str) -> str:
    rc, out = run([prefix + "-size", "-t", lib])
    if rc != 0:
        return "size failed"
    for ln in out.splitlines():
        f = ln.split()
        if len(f) >= 3 and "TOTALS" in ln:
            return f"text {f[0]} B, data {f[1]} B, bss {f[2]} B"
    return "size: no TOTALS row"


def step_cross(fw: str) -> tuple:
    rows, sizes = [], []
    for arg, tag, prefix in CROSS:
        cc = prefix + "-gcc"
        if shutil.which(cc) is None:
            rows.append(("SKIP", f"cross/{tag}", f"{cc} not on PATH"))
            continue
        rc, out = run(["bash", os.path.join(fw, "build.sh"), arg])
        lib = os.path.join(fw, "lib", tag, "libsram.a")
        ok = rc == 0 and os.path.isfile(lib)
        rows.append(("PASS" if ok else "FAIL", f"cross/{tag}",
                     "" if ok else f"exit {rc}: {tail(out)}"))
        if ok:
            sizes.append(f"{tag:<16} {lib_size(prefix, lib)}  ({cc} "
                         f"{run([cc, '-dumpversion'])[1].strip()})")
    return rows, sizes


def main() -> int:
    ip = os.environ.get("CLAUDE_SRAM_PATH")
    if not ip:
        print("ERROR: CLAUDE_SRAM_PATH is not set.")
        print("       Please run:  source IP/system/sram/setup.sh")
        return 1
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--skip-host", action="store_true", help="skip the host unit tests")
    ap.add_argument("--skip-compile", action="store_true", help="skip the host compile check")
    ap.add_argument("--skip-cross", action="store_true", help="skip the cross builds")
    ap.add_argument("--skip-mutants", action="store_true", help="skip the mutation check")
    ap.add_argument("--mutant", default="all", help="run one mutant by name (default all)")
    ap.add_argument("--list-mutants", action="store_true", help="list the mutants and exit")
    args = ap.parse_args()
    if args.list_mutants:
        for name, fname, _, _ in MUTANTS:
            print(f"{name:<24} {fname}")
        return 0

    fw = os.path.join(ip, "firmware")
    cc = shutil.which("gcc") or "gcc"
    rows, sizes = [], []
    if not args.skip_host:
        rows += step_host(fw, cc)
    if not args.skip_mutants:
        rows += step_mutants(fw, cc, args.mutant)
    if not args.skip_compile:
        rows += step_compile(fw, cc)
    if not args.skip_cross:
        r, sizes = step_cross(fw)
        rows += r

    n_fail = sum(1 for st, _, _ in rows if st == "FAIL")
    n_pass = sum(1 for st, _, _ in rows if st == "PASS")
    overall = "PASS" if n_fail == 0 and n_pass > 0 else "FAIL"
    host = "csun.edu" if ON_CSUN else "standard host"
    gccv = run([cc, "-dumpfullversion"])[1].strip()
    hdr = [overall,
           f"fw_sram.py {datetime.now().strftime('%Y-%m-%d %H:%M')} ({host}), host gcc {gccv}",
           f"Pass {n_pass}  Fail {n_fail}  Skip {len(rows) - n_pass - n_fail}"]
    body = [f"{st} {name}" + (f"  {note}" if note else "") for st, name, note in rows]
    body += ["", "Library sizes (firmware/lib/<arch>/libsram.a, -O2 Release):"]
    body += ["  " + s for s in sizes] if sizes else ["  none (no cross compiler on PATH)"]

    out_dir = os.path.join(ip, "verification", "firmware")
    os.makedirs(out_dir, exist_ok=True)
    log = os.path.join(out_dir, "fw_results.log")
    with open(log, "w") as fh:
        fh.write("\n".join(hdr + body) + "\n")

    for ln in hdr[1:] + [b for b in body if not b.startswith("PASS host/")]:
        print(ln)
    print(f"\nResult: {overall} -> {log}")
    return 0 if overall == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
