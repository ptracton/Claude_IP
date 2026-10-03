#!/usr/bin/env python3
"""claude_vcf.py — Reusable Synopsys VC Formal (FPV) driver for Claude IP.

Every Claude IP exposes the same four bus top-levels (APB4, AHB-Lite,
AXI4-Lite, Wishbone B4) built on the common claude_<proto>_if bridges, in
both SystemVerilog and VHDL-2008. This module holds everything about a VC
Formal run that is not specific to one IP:

  - BUS_PROTOCOLS: clock/reset/bridge/checker names per bus protocol
  - VcfJob:        one (top-level, language) proof job
  - run_job():     runs vcf in batch mode with the generic
                   ${IP_COMMON_PATH}/verification/formal/vcf/claude_vcf_fpv.tcl
  - parse_report() / judge(): turn "report_fv -list" into PASS/FAIL,
                   honouring an IP's waiver file

An IP-specific runner (e.g. verification/tools/formal_timer.py) only lists
its RTL files, its checker files, and its waiver file.

Pass criteria for a job:
  - every assertion is proven and non-vacuous
  - every cover property is covered
  - unless the property name matches a waiver pattern (fnmatch glob)
Constraints (assumptions) that are vacuous are reported but never fail a
job: a master rule such as "hold signals during a wait state" is vacuous
against a zero-wait-state slave, and that is expected.
"""

import fnmatch
import os
import re
import shutil
import subprocess
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

VCF_BIN = "vcf"

# Per-protocol facts shared by every IP (names match IP/common/design/rtl).
BUS_PROTOCOLS: Dict[str, Dict[str, str]] = {
    "apb":   {"clock": "PCLK",  "reset": "PRESETn", "sense": "low",
              "bridge": "claude_apb_if",   "checker": "claude_apb_fv"},
    "ahb":   {"clock": "HCLK",  "reset": "HRESETn", "sense": "low",
              "bridge": "claude_ahb_if",   "checker": "claude_ahb_fv"},
    "axi4l": {"clock": "ACLK",  "reset": "ARESETn", "sense": "low",
              "bridge": "claude_axi4l_if", "checker": "claude_axi4l_fv"},
    "wb":    {"clock": "CLK_I", "reset": "RST_I",   "sense": "high",
              "bridge": "claude_wb_if",    "checker": "claude_wb_fv"},
}

LANGS = ["sv", "vhdl"]


@dataclass
class VcfJob:
    """One VC Formal FPV job: a single top-level in a single language."""
    name: str                 # e.g. "timer_apb_sv"
    top: str                  # top-level module/entity
    lang: str                 # "sv" or "vhdl"
    proto: str                # key of BUS_PROTOCOLS
    rtl_files: List[str]      # compile order
    sva_files: List[str]      # checkers + bind module file
    bind_module: str          # bind-only module name
    incdirs: List[str] = field(default_factory=list)
    max_time: str = "30M"


@dataclass
class PropResult:
    kind: str                 # "assert", "cover", "constraint"
    name: str
    status: str               # proven, falsified, covered, uncoverable, ...
    vacuity: str = ""         # non_vacuous, vacuous, "" (n/a)
    depth: Optional[int] = None


@dataclass
class JobResult:
    job: VcfJob
    ran: bool                           # tool completed and wrote a report
    props: List[PropResult] = field(default_factory=list)
    failures: List[Tuple[PropResult, str]] = field(default_factory=list)
    waived: List[Tuple[PropResult, str]] = field(default_factory=list)
    log_path: str = ""
    report_path: str = ""
    message: str = ""

    @property
    def passed(self) -> bool:
        return self.ran and not self.failures

    def count(self, kind: str, status: str) -> int:
        return sum(1 for p in self.props if p.kind == kind and p.status == status)


def common_path() -> str:
    """Return IP_COMMON_PATH (this file lives in <common>/verification/tools)."""
    env = os.environ.get("IP_COMMON_PATH")
    if env:
        return env
    return os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))


def common_formal_dir() -> str:
    return os.path.join(common_path(), "verification", "formal")


def common_bridge_file(proto: str, lang: str) -> str:
    """Path to the common bus bridge RTL for *proto* in *lang*."""
    bridge = BUS_PROTOCOLS[proto]["bridge"]
    if lang == "vhdl":
        return os.path.join(common_path(), "design", "rtl", "vhdl", f"{bridge}.vhd")
    return os.path.join(common_path(), "design", "rtl", "verilog", f"{bridge}.sv")


def common_checker_files(proto: str) -> List[str]:
    """Common SVA files every job for *proto* needs (bus checker + reg checker)."""
    d = common_formal_dir()
    return [
        os.path.join(d, f"{BUS_PROTOCOLS[proto]['checker']}.sv"),
        os.path.join(d, "claude_reg_fv.sv"),
    ]


def find_vcf() -> Optional[str]:
    return shutil.which(VCF_BIN)


def vcf_version(vcf: str) -> str:
    """Best-effort tool version string (from the VC_STATIC/VCF install path)."""
    m = re.search(r"/(vc_formal|vc_static)/([^/]+)/", os.path.realpath(vcf))
    return f"VC Formal {m.group(2)}" if m else "VC Formal (version unknown)"


# ---------------------------------------------------------------------------
# Waivers
# ---------------------------------------------------------------------------

def load_waivers(path: Optional[str]) -> List[Tuple[str, str]]:
    """Read a waiver file: one "<glob> <status> # justification" per line.

    <status> is the result being waived (e.g. uncoverable, vacuous).
    Globs match property names case-insensitively, so one entry covers the
    SV and VHDL runs of the same top-level.
    Returns [(pattern_with_status, justification)].
    """
    waivers: List[Tuple[str, str]] = []
    if not path or not os.path.isfile(path):
        return waivers
    with open(path) as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            body, _, why = line.partition("#")
            parts = body.split()
            if len(parts) != 2:
                raise ValueError(f"{path}: malformed waiver line: {raw.rstrip()}")
            if not why.strip():
                raise ValueError(f"{path}: waiver without justification: {raw.rstrip()}")
            waivers.append((f"{parts[0]} {parts[1]}", why.strip()))
    return waivers


def _waiver_for(prop: PropResult, outcome: str,
                waivers: List[Tuple[str, str]]) -> Optional[str]:
    for pat, why in waivers:
        glob, status = pat.split(" ", 1)
        # Case-insensitive: VC Formal upper-cases VHDL instance names, and
        # VHDL identifiers are case-insensitive anyway.
        if status == outcome and fnmatch.fnmatchcase(prop.name.lower(), glob.lower()):
            return why
    return None


# ---------------------------------------------------------------------------
# Report parsing / judging
# ---------------------------------------------------------------------------

_SECTION_RE = re.compile(r"^\s*>\s*(Assertion|Cover|Constraint)\s*$")
_ROW_RE = re.compile(
    r"^\s*\[\s*\d+\]\s+(?P<status>\S+)"
    r"(?:\s+\(depth=(?P<depth>\d+)\))?"
    r"(?:\s+\((?P<vac>[a-z_]+)\))?"
    r"\s+-\s+(?P<name>\S+)"
)


def parse_report(report_path: str) -> List[PropResult]:
    """Parse the "List Results" section of `report_fv -list`."""
    props: List[PropResult] = []
    kind = None
    in_list = False
    with open(report_path) as fh:
        for line in fh:
            if "List Results" in line:
                in_list = True
                continue
            if not in_list:
                continue
            m = _SECTION_RE.match(line)
            if m:
                kind = {"Assertion": "assert", "Cover": "cover",
                        "Constraint": "constraint"}[m.group(1)]
                continue
            m = _ROW_RE.match(line)
            if m and kind:
                props.append(PropResult(
                    kind=kind, name=m.group("name"), status=m.group("status"),
                    vacuity=m.group("vac") or "",
                    depth=int(m.group("depth")) if m.group("depth") else None,
                ))
    return props


def judge(result: JobResult, waivers: List[Tuple[str, str]]) -> None:
    """Fill result.failures / result.waived from result.props."""
    for p in result.props:
        outcome = None
        if p.kind == "assert":
            if p.status != "proven":
                outcome = p.status          # falsified / inconclusive / not_run
            elif p.vacuity == "vacuous":
                outcome = "vacuous"
        elif p.kind == "cover":
            if p.status != "covered":
                outcome = p.status          # uncoverable / inconclusive
        if outcome is None:
            continue
        why = _waiver_for(p, outcome, waivers)
        if why:
            result.waived.append((p, f"{outcome}: {why}"))
        else:
            detail = outcome + (f" (depth={p.depth})" if p.depth is not None else "")
            result.failures.append((p, detail))


# ---------------------------------------------------------------------------
# Running
# ---------------------------------------------------------------------------

def run_job(job: VcfJob, run_dir: str, waivers: List[Tuple[str, str]],
            traces: bool = False, vcf: str = VCF_BIN) -> JobResult:
    """Run one job in *run_dir* (created/cleaned) and judge the results."""
    if os.path.isdir(run_dir):
        shutil.rmtree(run_dir)
    os.makedirs(run_dir)

    proto = BUS_PROTOCOLS[job.proto]
    report = os.path.join(run_dir, "report_fv.txt")
    log = os.path.join(run_dir, "vcf.log")
    env = dict(os.environ)
    env.update({
        "FV_TOP": job.top,
        "FV_LANG": job.lang,
        "FV_RTL_FILES": " ".join(job.rtl_files),
        "FV_SVA_FILES": " ".join(job.sva_files),
        "FV_INCDIRS": " ".join(job.incdirs + [common_formal_dir()]),
        "FV_BIND": job.bind_module,
        "FV_CLOCK": proto["clock"],
        "FV_RESET": proto["reset"],
        "FV_RESET_SENSE": proto["sense"],
        "FV_MAX_TIME": job.max_time,
        "FV_REPORT": report,
        "FV_TRACE_DIR": os.path.join(run_dir, "traces") if traces else "",
    })
    tcl = os.path.join(common_formal_dir(), "vcf", "claude_vcf_fpv.tcl")

    with open(log, "w") as fh:
        rc = subprocess.run([vcf, "-f", tcl, "-batch"], cwd=run_dir, env=env,
                            stdout=fh, stderr=subprocess.STDOUT).returncode

    result = JobResult(job=job, ran=False, log_path=log, report_path=report)
    with open(log, errors="replace") as fh:
        log_text = fh.read()
    if "CLAUDE_VCF_DONE" not in log_text or not os.path.isfile(report):
        errs = [l for l in log_text.splitlines()
                if re.search(r"\bError-|\bERROR\b|CLAUDE_VCF_ERROR", l)]
        result.message = (f"vcf did not complete (rc={rc})" +
                          (": " + errs[0].strip() if errs else ""))
        return result

    result.ran = True
    result.props = parse_report(report)
    if not any(p.kind == "assert" for p in result.props):
        result.ran = False
        result.message = "report contains no assertions (checkers not bound?)"
        return result
    judge(result, waivers)
    return result


def summary_line(r: JobResult) -> str:
    if not r.ran:
        return f"FAIL: {r.job.name}  ({r.message})"
    a_tot = sum(1 for p in r.props if p.kind == "assert")
    c_tot = sum(1 for p in r.props if p.kind == "cover")
    status = "PASS" if r.passed else "FAIL"
    return (f"{status}: {r.job.name}  asserts {r.count('assert', 'proven')}/{a_tot} proven, "
            f"covers {r.count('cover', 'covered')}/{c_tot} covered, "
            f"{len(r.waived)} waived, {len(r.failures)} failing")
