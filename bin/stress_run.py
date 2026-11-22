#!/usr/bin/env python3
"""
stress_run.py -- run one stress-suite matrix entry (one test, one build, one
DUT, a list of seeds) through sim/Makefile and judge it.

    python3 bin/stress_run.py --path testcode/stress/mmu/st_tlb_thrash.c \
        --build no_spike --dut legacy --seeds "1 2" --timeout 40000000 [--expect fail]

Per seed:
  * builds the program with CFLAGS_EXTRA="-DSEED=<s> -DST_SCALE=<n> [-DCOSIM]
    [-DST_DUMMY_INSERT=<k>]" (bin/generate_memory_file.py honours CFLAGS_EXTRA)
  * lints the disassembly: the chip has no FPU, so no F/D instruction may appear
    in a stress program even though it is compiled -march=rv64gc
  * runs the matching make target (strict exit is on by default)
  * expect=pass: make must succeed and the log must say "test PASSED";
    expect=fail (harness self-checks): the run must FAIL
Writes sim/stress_results/<id>.json and appends a line to $GITHUB_STEP_SUMMARY.
Exit status 0 only if every seed met its expectation.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIM = os.path.join(REPO, "sim")
MAKE = os.environ.get("MAKE", "make")

TARGET = {"spike": "run_verilator_top_tb", "no_spike": "run_verilator_top_tb_no_spike", "ecc": "run_ecc_inject"}
# objdump line: "  addr:<tab>encoding<tab>mnemonic ..."
INSN_RE = re.compile(r"^\s*[0-9a-f]+:\s+([0-9a-f]{4}|[0-9a-f]{8})\s")
FP_OPCODES = {0x07, 0x27, 0x43, 0x47, 0x4B, 0x4F, 0x53}   # LOAD-FP STORE-FP FMADD..FNMADD OP-FP


def is_fp_encoding(hexword):
    """By ENCODING, not mnemonic: objdump spells CSR accesses to fflags/frm/
    fcsr as frflags/frrm/frcsr, which are SYSTEM (0x73) instructions."""
    w = int(hexword, 16)
    if len(hexword) == 8:
        return (w & 0x7F) in FP_OPCODES
    q, f3 = w & 3, (w >> 13) & 7
    return (q in (0, 2)) and f3 in (1, 5)      # c.fld / c.fsd / c.fldsp / c.fsdsp (RV64)


SECTION_RE = re.compile(r"^Disassembly of section (\S+):")


def fp_lint(dis_path):
    """F/D instructions in the program's CODE.  The .dis is `objdump -D`, which
    also 'disassembles' data sections, so only .init/.text* are inspected."""
    bad = []
    if not os.path.isfile(dis_path):
        return bad
    code = False
    with open(dis_path, errors="replace") as f:
        for line in f:
            s = SECTION_RE.match(line)
            if s:
                code = s.group(1) == ".init" or s.group(1).startswith(".text")
                continue
            if not code:
                continue
            m = INSN_RE.match(line)
            if m and is_fp_encoding(m.group(1)):
                bad.append(line.strip())
    return bad


def run_seed(a, seed):
    name = os.path.splitext(os.path.basename(a.path))[0]
    run_name = f"{name}_{a.dut}_{a.build}{'_' + a.variant if a.variant else ''}_s{seed}"
    cflags = f"-DSEED={seed} -DST_SCALE={a.scale}"
    if a.build == "spike":
        cflags += " -DCOSIM"
    if a.variant == "dummy":
        cflags += f" -DST_DUMMY_INSERT={4 + seed % 13}"
    link_args = ""
    if a.link_args == "rand":
        link_args = f"+LINK_GAPS=1 +LINK_SEED={seed}"
    elif a.link_args:
        link_args = a.link_args
    cmd = [MAKE, "-s", "-C", SIM, TARGET[a.build], f"PROG={os.path.join(REPO, a.path)}",
           f"PROG_NAME={run_name}", f"TIMEOUT={a.timeout}", f"DUT={a.dut}", f"CFLAGS_EXTRA={cflags}"]
    if link_args:
        cmd.append(f"LINK_ARGS={link_args}")
    t0 = time.time()
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    dt = time.time() - t0
    log = p.stdout
    logdir = os.path.join(SIM, "verilator", run_name)
    os.makedirs(logdir, exist_ok=True)
    with open(os.path.join(logdir, "make.log"), "w") as f:
        f.write(" ".join(cmd) + "\n" + log)
    stem = os.path.splitext(os.path.basename(a.path))[0]
    fp = fp_lint(os.path.join(SIM, "bin", stem + ".dis"))
    passed = p.returncode == 0 and "test PASSED" in log
    st_line = next((l for l in log.splitlines() if "[ST] pass=" in l), "")
    fails = [l for l in log.splitlines() if "  FAIL [" in l][:10]
    # A must-fail self-check only counts if the SIMULATOR delivered the FAIL
    # verdict -- a compile error or a make failure before simulation would
    # otherwise look like the harness catching the bad program.
    sim_verdict = any(m in log for m in ("test FAILED", "TB Error: Timed out",
                                          "halted without a tohost exit"))
    if a.expect == "fail":
        ok = (not passed) and sim_verdict
    else:
        ok = passed and not fp
    return dict(seed=seed, ok=ok, passed=passed, rc=p.returncode, secs=round(dt, 1), fp_insns=fp[:5],
                summary=st_line.strip(), fails=fails, run=run_name,
                tail=log.splitlines()[-25:] if not ok else [])


def gh_error(title, lines):
    """A GitHub ::error annotation: readable through the public API, unlike job
    logs, so a failure's details are visible without signing in."""
    if not os.environ.get("GITHUB_ACTIONS"):
        return
    keep = [l for l in lines if l and "Heartbeat" not in l][-40:]
    msg = "\n".join(keep)[-6000:]
    enc = msg.replace("%", "%25").replace("\r", "").replace("\n", "%0A")
    print(f"::error title={title.replace(',', ' ').replace(':', ' ')}::{enc}", flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--path", required=True)
    ap.add_argument("--build", default="no_spike", choices=sorted(TARGET))
    ap.add_argument("--dut", default="legacy")
    ap.add_argument("--seeds", default="1")
    ap.add_argument("--timeout", type=int, default=10000000)
    ap.add_argument("--expect", default="pass", choices=["pass", "fail"])
    ap.add_argument("--scale", type=int, default=1)
    ap.add_argument("--link-args", default="")
    ap.add_argument("--variant", default="")
    ap.add_argument("--xfail", default="")
    ap.add_argument("--id", default="")
    a = ap.parse_args()

    results = []
    for s in a.seeds.split():
        r = run_seed(a, int(s))
        results.append(r)
        tag = "OK  " if r["ok"] else "FAIL"
        print(f"[{tag}] {a.path} build={a.build} dut={a.dut} variant={a.variant or '-'} seed={s} "
              f"({r['secs']}s) {r['summary']}", flush=True)
        if r["fp_insns"]:
            print("  F/D instructions in a program for an FPU-less chip:\n    " + "\n    ".join(r["fp_insns"]))
        for l in r["fails"]:
            print("  " + l)
        if not r["ok"]:
            print("  --- last lines of the run ---\n  " + "\n  ".join(r["tail"]))
            gh_error(f"{os.path.basename(a.path)} {a.dut}/{a.build} {a.variant or ''} seed {s}",
                     [r["summary"]] + r["fails"] + r["fp_insns"] + ["--- tail ---"] + r["tail"])

    ok = all(r["ok"] for r in results)
    xfail = bool(a.xfail) and not ok
    out = dict(id=a.id or os.path.basename(a.path), path=a.path, build=a.build, dut=a.dut,
               variant=a.variant, expect=a.expect, ok=ok, xfail=a.xfail if xfail else "", results=results)
    os.makedirs(os.path.join(SIM, "stress_results"), exist_ok=True)
    with open(os.path.join(SIM, "stress_results", (a.id or "result") + ".json"), "w") as f:
        json.dump(out, f, indent=1)
    summ = os.environ.get("GITHUB_STEP_SUMMARY")
    if summ:
        with open(summ, "a") as f:
            status = "PASS" if ok else ("XFAIL " + a.xfail if xfail else "FAIL")
            f.write(f"| `{a.path}` | {a.build} | {a.dut} | {a.variant or '-'} | {a.seeds} | **{status}** |\n")
    if xfail:
        print(f"known failure ({a.xfail}): not failing the job")
        return 0
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
