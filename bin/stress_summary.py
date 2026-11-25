#!/usr/bin/env python3
"""stress_summary.py <dir> -- render the per-job result JSONs of a stress run
(written by bin/stress_run.py and bin/riscv_tests.py) as one Markdown table
for $GITHUB_STEP_SUMMARY."""
import glob
import json
import os
import sys


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "results"
    rows = []
    for p in sorted(glob.glob(os.path.join(d, "**", "*.json"), recursive=True)):
        try:
            r = json.load(open(p))
        except (OSError, ValueError):
            continue
        res = r.get("results", [])
        if "seed" in (res[0] if res else {}):
            n_ok = sum(1 for x in res if x.get("ok"))
            what = f"seeds {n_ok}/{len(res)}"
        else:
            n_ok = sum(1 for x in res if x.get("ok"))
            what = f"tests {n_ok}/{len(res)}"
        status = "PASS" if r.get("ok") else ("XFAIL " + r["xfail"] if r.get("xfail") else "FAIL")
        rows.append((status != "PASS", r.get("id", os.path.basename(p)), r.get("build", ""), r.get("dut", ""),
                     r.get("variant", "") or "-", what, status))
    total, failed = len(rows), sum(1 for r in rows if r[6] == "FAIL")
    print(f"## Stress suite: {total - failed}/{total} jobs passed\n")
    print("| job | build | DUT | variant | result | status |")
    print("|---|---|---|---|---|---|")
    for r in sorted(rows, key=lambda r: (not r[0], r[1])):
        print(f"| `{r[1]}` | {r[2]} | {r[3]} | {r[4]} | {r[5]} | **{r[6]}** |")
    return 0


if __name__ == "__main__":
    sys.exit(main())
