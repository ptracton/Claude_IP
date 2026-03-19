#!/usr/bin/env python3
"""run_synth.py — Run Yosys synthesis for the Timer IP and generate a report.

Usage:
    cd $CLAUDE_TIMER_PATH/synthesis/yosys
    python3 run_synth.py

Or from anywhere (requires CLAUDE_TIMER_PATH env var):
    python3 $CLAUDE_TIMER_PATH/synthesis/yosys/run_synth.py

Outputs:
    synthesis/yosys/work/yosys_raw_<proto>.log   — raw Yosys output per variant
    synthesis/yosys/work/synthesis_report.log    — parsed cell-count summary
"""

import os
import re
import subprocess
import sys
from pathlib import Path


YOSYS  = "/opt/oss-cad-suite/bin/yosys"
PROTOS = ["apb", "ahb", "axi4l", "wb"]


def get_synth_dir() -> Path:
    """Return the synthesis/yosys directory regardless of working directory."""
    env_path = os.environ.get("CLAUDE_TIMER_PATH")
    if env_path:
        return Path(env_path) / "synthesis" / "yosys"
    # Fall back to the directory containing this script
    return Path(__file__).resolve().parent


def parse_stat(output: str) -> dict:
    """Parse 'yosys stat' output and return per-module cell counts.

    Returns a dict keyed by module name, each value a dict of {cell: count}.
    """
    results: dict = {}
    current: str | None = None
    for line in output.splitlines():
        # Module header: "=== timer_apb ==="
        m = re.match(r'\s*===\s+(\S+)\s+===', line)
        if m:
            current = m.group(1)
            results[current] = {}
            continue
        if current is None:
            continue
        # Cell line: "      42   $_DFF_P_"  (count first, then cell name)
        m = re.match(r'\s+(\d+)\s+(\$[\w]+)\s*$', line)
        if m:
            count, cell = int(m.group(1)), m.group(2)
            results[current][cell] = results[current].get(cell, 0) + count
    return results


def summarise(stats: dict, proto: str) -> list:
    """Return a list of formatted report lines for one protocol variant."""
    top = f"timer_{proto}"
    lines = [f"  Protocol : {proto.upper():<8}  Top module : {top}"]

    if top in stats:
        data = stats[top]
    else:
        # Flattened designs may appear under a different key; try fuzzy match
        candidates = [k for k in stats if proto in k.lower()]
        data = stats.get(candidates[0], {}) if candidates else {}

    if not data:
        lines.append("    (no cell data found — check yosys_raw log)")
        return lines

    total = sum(data.values())
    lines.append(f"    {'Cell type':<32} {'Count':>6}")
    lines.append(f"    {'-' * 32}  {'-' * 6}")
    for cell, cnt in sorted(data.items()):
        lines.append(f"    {cell:<32} {cnt:>6}")
    lines.append(f"    {'--- Total cells ---':<32} {total:>6}")
    return lines


def run_one(synth_dir: Path, work_dir: Path, proto: str) -> tuple[bool, str]:
    """Invoke Yosys for a single protocol variant.

    Returns (success, combined_output).
    """
    ys_script = synth_dir / f"synth_timer_{proto}.ys"
    if not ys_script.exists():
        return False, f"ERROR: script not found: {ys_script}"

    try:
        cp = subprocess.run(
            [YOSYS, str(ys_script)],
            capture_output=True,
            text=True,
            timeout=300,
            cwd=str(synth_dir),
        )
    except FileNotFoundError:
        return False, f"ERROR: yosys not found at {YOSYS}"
    except subprocess.TimeoutExpired:
        return False, "ERROR: Yosys timed out"

    output = cp.stdout + cp.stderr

    # Save per-protocol raw log
    raw_log = work_dir / f"yosys_raw_{proto}.log"
    raw_log.write_text(output)

    if cp.returncode != 0:
        return False, output

    return True, output


def main() -> None:
    synth_dir = get_synth_dir()
    work_dir  = synth_dir / "work"
    work_dir.mkdir(exist_ok=True)

    report_path = work_dir / "synthesis_report.log"

    print(f"Yosys synthesis — Timer IP")
    print(f"  Synth dir : {synth_dir}")
    print(f"  Work dir  : {work_dir}")
    print(f"  Yosys     : {YOSYS}")
    print()

    all_stats: dict = {}
    failed:    list = []

    for proto in PROTOS:
        print(f"  [{proto.upper():<6}] synthesising timer_{proto} ...", end=" ", flush=True)
        ok, output = run_one(synth_dir, work_dir, proto)
        if ok:
            print("OK")
            stats = parse_stat(output)
            all_stats.update(stats)
        else:
            print("FAILED")
            failed.append(proto)
            print(output[-1000:])

    sep   = "=" * 62
    lines = [
        sep,
        "Timer IP  —  Yosys Generic Synthesis Report",
        sep,
        "",
    ]

    for proto in PROTOS:
        lines.extend(summarise(all_stats, proto))
        lines.append("")

    lines.append(sep)

    if failed:
        lines.append(f"FAIL  (failed variants: {', '.join(failed)})")
        exit_code = 1
    else:
        lines.append("PASS")
        exit_code = 0

    report = "\n".join(lines)
    print("\n" + report)

    report_path.write_text(report + "\n")
    print(f"\nReport written to: {report_path}")

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
