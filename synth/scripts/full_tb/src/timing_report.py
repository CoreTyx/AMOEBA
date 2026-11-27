#!/usr/bin/env python3
"""Make VCS timing violations and SDF annotation diagnostics fail the run.

This is a log check, not a certificate of annotation coverage. Review the VCS
annotation summary against the supplied models/netlist before qualification.
"""
import re
import sys
from pathlib import Path


def main():
    violation = re.compile(
        r"timing\s+violation|\$(?:setuphold|setup|hold|recovery|removal|recrem|width|period|nochange)\s*\(",
        re.IGNORECASE,
    )
    annotation = re.compile(
        r"(?:warning|error|fatal)-\[SDF[^\]]*\]|"
        r"(?:SDF|back.?annotation).*\b(?:warnings?|errors?|failed|failure)\b|"
        r"\b(?:warnings?|errors?|failed|failure)\b.*(?:SDF|back.?annotation)",
        re.IGNORECASE,
    )
    problems = [] if sys.argv[1:] else ["No logs supplied"]
    for name in sys.argv[1:]:
        path = Path(name)
        if not path.is_file() or path.stat().st_size == 0:
            problems.append(f"{name}: missing/empty log")
            continue
        for number, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
            # Some versions print summary counters, including zero errors.
            diagnostic = re.sub(r"\b0\s+(?:warnings?|errors?)\b", "", line, flags=re.I)
            if violation.search(line) or annotation.search(diagnostic):
                problems.append(f"{name}:{number}: {line.strip()}")
    for line in problems:
        print(line)
    print(f"TIMING LOG CHECK: {'FAIL' if problems else 'PASS'} ({len(problems)} diagnostic lines)")
    print("Review VCS annotation coverage in compile.log/sim.log; this check does not prove full annotation.")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
