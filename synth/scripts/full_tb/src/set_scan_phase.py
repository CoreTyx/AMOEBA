#!/usr/bin/env python3
"""Update phase flags for instance paths matching a quoted glob."""

import argparse
import fnmatch
from pathlib import Path
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("glob", help="Instance-path glob, e.g. '*ieu_c_Rd*'")
    parser.add_argument("value", choices=("0", "1"), help="New phase flag")
    parser.add_argument("--file", type=Path, default=Path("scan_phase.txt"),
                        help="File to edit (default: scan_phase.txt)")
    args = parser.parse_args()

    # Preserve line endings, spacing, comments, and nonmatching lines.
    with args.file.open("r", encoding="utf-8", newline="") as source:
        lines = source.readlines()
    entry = re.compile(r"^[ \t]*(\S+)[ \t]+([01])(?=[ \t\r\n]|$)")
    matched = changed = 0
    for index, line in enumerate(lines):
        match = entry.match(line)
        if not match or match[1].startswith("#"):
            continue
        if fnmatch.fnmatchcase(match[1], args.glob):
            matched += 1
            if match[2] != args.value:
                start, end = match.span(2)
                lines[index] = line[:start] + args.value + line[end:]
                changed += 1

    if changed:
        with args.file.open("w", encoding="utf-8", newline="") as destination:
            destination.writelines(lines)
    print(f"{args.file}: matched {matched} entries, changed {changed} to {args.value}")


if __name__ == "__main__":
    main()
