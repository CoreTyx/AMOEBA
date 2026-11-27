#!/usr/bin/env python3
"""Timing-check violations in a full_tb timing run, summarised without IP.

    timing_report.py sim.log [--annotation "<line>"]... [--annotation-fail "<why>"]

Fails (exit 1) on any VCS timing-check violation in sim.log, or when run.sh
reports that the SDF annotation was not complete (--annotation-fail: the
verdict of hvl/pin/sdf_msgs.sh on compile.log, which accepts only the SDF
messages it can check line by line).

The summary is safe to paste anywhere: counts per check kind ($setuphold,
$recrem, $width, ...), per bench phase (from the PHASE START lines' times) and
per scan register group (the RTL-derived instance name with its bit index and
flop suffix removed).  It never prints a cell type, model file, pin name or
SDF/limit value; the full messages stay in sim.log.

This is a log check, not a certificate of annotation coverage.
"""
import argparse
import re
import sys
from collections import Counter
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("sim_log", type=Path)
ap.add_argument("--annotation", action="append", default=[],
                help="a line describing the (passed) annotation check")
ap.add_argument("--annotation-fail", default="")
a = ap.parse_args()

problems = []
if a.annotation_fail:
    problems.append(f"SDF annotation: {a.annotation_fail}")
if not a.sim_log.is_file() or a.sim_log.stat().st_size == 0:
    problems.append(f"{a.sim_log.name}: missing or empty")
    text = ""
else:
    text = a.sim_log.read_text(errors="replace")

# VCS: '"<model file>", <line>: Timing violation in <instance>' then the check
# '$setuphold( <ref event>, <data event>, <limits> );' on the next line(s).
viol_re = re.compile(r"Timing violation in\s+(\S+)")
check_re = re.compile(r"\$(setuphold|setup|hold|recrem|recovery|removal|width|period|skew|nochange|fullskew|timeskew)\b")
time_re = re.compile(r"^\s*\[(\d+)\]|\btime\s*[=:]?\s*(\d+)", re.I)
phase_re = re.compile(r"^\[(\d+)\] PHASE START: (.+?) \(errors")

lines = text.splitlines()
phases = []            # (time, name)
for line in lines:
    m = phase_re.match(line)
    if m:
        phases.append((int(m.group(1)), m.group(2)))


def phase_at(t):
    name = "before phase A"
    for pt, pn in phases:
        if pt <= t:
            name = pn
        else:
            break
    return name


def group_of(inst):
    leaf = inst.rstrip(" ").split(".")[-1].lstrip("\\").strip()
    leaf = re.sub(r"(_reg)?(_\d+_)+$", "", leaf)
    leaf = re.sub(r"_reg$", "", leaf)
    leaf = re.sub(r"^(chip/)?soc_core_", "", leaf)
    return leaf or "?"


kinds, by_phase, by_group = Counter(), Counter(), Counter()
first_time = None
last_time = 0
n = 0
for i, line in enumerate(lines):
    m = viol_re.search(line)
    if not m:
        # Some VCS versions print the check on the same line as the time only.
        continue
    n += 1
    kind = "?"
    for nxt in lines[i:i + 3]:
        c = check_re.search(nxt)
        if c:
            kind = "$" + c.group(1)
            break
    # The simulation time: VCS prints it in the check's event list as 'ev:<t>'
    t = None
    for nxt in lines[i:i + 3]:
        ts = re.findall(r":\s*(\d+)\s*(?:ps|ns|fs)?\s*[,)]", nxt)
        if ts:
            t = max(int(x) for x in ts)
            break
    kinds[kind] += 1
    by_group[group_of(m.group(1))] += 1
    if t is not None:
        by_phase[phase_at(t)] += 1
        first_time = t if first_time is None else min(first_time, t)
        last_time = max(last_time, t)
    else:
        by_phase["(time not read)"] += 1

print(f"TIMING VIOLATIONS: {n}")
if n:
    print("  by check: " + ", ".join(f"{k} x{v}" for k, v in kinds.most_common()))
    print("  by phase: " + ", ".join(f"{k} x{v}" for k, v in by_phase.most_common()))
    print("  by register (top 15): " + ", ".join(f"{k} x{v}" for k, v in by_group.most_common(15)))
    problems.append(f"{n} timing-check violation(s) in {a.sim_log.name} (full messages there)")
for line in a.annotation:
    print(f"ANNOTATION: {line}")
for p in problems:
    print(f"PROBLEM: {p}")
print(f"TIMING LOG CHECK: {'FAIL' if problems else 'PASS'}")
print("Review VCS annotation coverage in compile.log; this check does not prove full annotation.")
sys.exit(1 if problems else 0)
