#!/usr/bin/env python3
"""
riscv_tests.py -- build and run the official riscv-tests (third_party/riscv-tests)
on the AMOEBA testbench, for the ISA the chip actually implements.

    riscv_tests.py shards                         # JSON matrix of shards
    riscv_tests.py build  [--dummy N]             # ELFs into sim/riscv_tests/
    riscv_tests.py run --shard rv64ui-p [--build no_spike|spike] [--dut legacy|forte]
                       [--link-args rand] [--dummy N]

Suites: rv64ui/um/ua/uc in the physical (-p) and virtual-memory (-v) envs, and
rv64si/rv64mi in -p.  Built -march=rv64imac_zicsr_zifencei: the riscv-tests env
would otherwise execute FP CSR writes the chip does not have.

Glue, applied to a COPY of the env (the submodule is never modified):
  * env/p write_tohost: two 32-bit stores become one 64-bit store + fence.i,
    the exit protocol the testbench and the pin bench expect
  * env/v do_tohost: + fence.i, because the v env writes tohost from a
    supervisor virtual address the testbench's store snoop cannot see; the
    write-back then reaches the bus, where the testbench sees it physically
  * EXTRA_INIT: with --dummy N, AMOEBA's random dummy-instruction insertion
    (CSR 0x7c1) runs under every -p test -- results must not change
  * the tohost address comes from each ELF and is passed to the testbench as
    +TOHOST_ADDR_ECE411 (riscv-tests link .tohost after .text.init)
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RT = os.path.join(REPO, "third_party", "riscv-tests")
OUT = os.path.join(REPO, "sim", "riscv_tests")
SIM = os.path.join(REPO, "sim")
EXCLUDE = os.path.join(REPO, "testcode", "riscv_tests", "exclude.txt")
STUBS = os.path.join(REPO, "testcode", "riscv_tests", "stub_include")
GCC = os.environ.get("RISCV_GCC", "riscv64-unknown-elf-gcc")
NM = os.environ.get("RISCV_NM", "riscv64-unknown-elf-nm")
MAKE = os.environ.get("MAKE", "make")
MARCH = "-march=rv64imac_zicsr_zifencei -mabi=lp64"
OPTS = "-static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles"
SUITES = [("rv64ui", "pv"), ("rv64um", "pv"), ("rv64ua", "pv"), ("rv64uc", "pv"), ("rv64si", "p"), ("rv64mi", "p")]
TARGET = {"spike": "run_verilator_top_tb", "no_spike": "run_verilator_top_tb_no_spike"}


def excluded():
    ex = {}
    if os.path.isfile(EXCLUDE):
        for line in open(EXCLUDE):
            line = line.split("#", 1)[0].strip()
            if line:
                name, _, why = line.partition(" ")
                ex[name] = why.strip()
    return ex


def sc_tests(suite):
    txt = open(os.path.join(RT, "isa", suite, "Makefrag")).read().replace("\\\n", " ")
    m = re.search(rf"^{suite}_sc_tests\s*=\s*(.*)$", txt, re.M)
    return m.group(1).split() if m else []


def shards():
    out = []
    for suite, envs in SUITES:
        for e in envs:
            out.append(dict(shard=f"{suite}-{e}"))
    return out


def prepare_env(dummy):
    """Copy env/ and apply the glue described in the module docstring."""
    dst = os.path.join(OUT, f"env{'_d' + str(dummy) if dummy else ''}")
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    shutil.copytree(os.path.join(RT, "env"), dst)
    p = os.path.join(dst, "p", "riscv_test.h")
    s = open(p).read()
    old = ("        sw TESTNUM, tohost, t5;                                         \\\n"
           "        sw zero, tohost + 4, t5;                                        \\\n")
    if old not in s:
        sys.exit("riscv_tests.py: env/p write_tohost changed upstream -- update the glue")
    s = s.replace(old, "        sd TESTNUM, tohost, t5;                                         \\\n"
                       "        fence.i;                                                        \\\n")
    if dummy:
        s = s.replace("#define EXTRA_INIT\n", f"#define EXTRA_INIT csrwi 0x7c1, {int(dummy)};\n", 1)
    open(p, "w").write(s)
    v = os.path.join(dst, "v", "vm.c")
    s = open(v).read()
    if "  tohost = tohost_value;\n" not in s:
        sys.exit("riscv_tests.py: env/v do_tohost changed upstream -- update the glue")
    s = s.replace("  tohost = tohost_value;\n", "  tohost = tohost_value;\n  asm volatile (\"fence.i\" ::: \"memory\");\n")
    open(v, "w").write(s)
    return dst


def build_one(name, suite, env, envdir, outdir):
    src = os.path.join(RT, "isa", suite, name.split("-", 2)[2] + ".S")
    elf = os.path.join(outdir, name + ".elf")
    inc = f"-I{os.path.join(RT, 'isa', 'macros', 'scalar')}"
    if env == "p":
        cmd = f"{GCC} {MARCH} {OPTS} -I{envdir}/p {inc} -T{envdir}/p/link.ld {src} -o {elf}"
    else:
        ent = hashlib.md5(elf.encode()).hexdigest()[:7]
        # env/v/vm.c carries FP instructions behind a run-time misa check
        # (never taken on this FPU-less chip), so the assembler needs F/D here.
        cmd = (f"{GCC} -march=rv64gc_zicsr_zifencei -mabi=lp64 {OPTS} -DENTROPY=0x{ent} -std=gnu99 -O2 -I{STUBS} -I{envdir}/v {inc} "
               f"-T{envdir}/v/link.ld {envdir}/v/entry.S {envdir}/v/vm.c {envdir}/v/string.c {src} -o {elf}")
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if r.returncode:
        sys.stderr.write(r.stdout + r.stderr)
        sys.exit(f"riscv_tests.py: build of {name} failed")
    nm = subprocess.run([NM, elf], capture_output=True, text=True).stdout
    m = re.search(r"^([0-9a-f]+) \w tohost$", nm, re.M)
    if not m:
        sys.exit(f"riscv_tests.py: {name} has no tohost symbol")
    return elf, int(m.group(1), 16)


def tests_in(shard):
    suite, env = shard.rsplit("-", 1)
    return suite, env, [f"{suite}-{env}-{t}" for t in sc_tests(suite)]


def cmd_build(a, only=None):
    os.makedirs(OUT, exist_ok=True)
    envdir = prepare_env(a.dummy)
    outdir = os.path.join(OUT, f"elf{'_d' + str(a.dummy) if a.dummy else ''}")
    os.makedirs(outdir, exist_ok=True)
    manifest = {}
    for s in shards():
        if only and s["shard"] != only:
            continue
        suite, env, names = tests_in(s["shard"])
        for n in names:
            manifest[n] = build_one(n, suite, env, envdir, outdir)
    print(f"built {len(manifest)} tests into {os.path.relpath(outdir, REPO)}")
    return manifest


def cmd_run(a):
    ex = excluded()
    manifest = cmd_build(a, only=a.shard)
    results, bad = [], 0
    for name, (elf, tohost) in sorted(manifest.items()):
        if name in ex:
            print(f"[SKIP] {name}: {ex[name]}")
            continue
        plus = f"+TOHOST_ADDR_ECE411={tohost:x}"
        link = f"+LINK_GAPS=1 +LINK_SEED={int(hashlib.md5(name.encode()).hexdigest()[:4], 16)}" if a.link_args == "rand" else ""
        run_name = f"rt_{name}_{a.dut}_{a.build}{'_d' if a.dummy else ''}"
        cmd = [MAKE, "-s", "-C", SIM, TARGET[a.build], f"PROG={elf}", f"PROG_NAME={run_name}",
               f"TIMEOUT={a.timeout}", f"DUT={a.dut}", f"PLUSARGS={plus}"]
        if link:
            cmd.append(f"LINK_ARGS={link}")
        t0 = time.time()
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
        ok = p.returncode == 0 and "test PASSED" in p.stdout
        logdir = os.path.join(SIM, "verilator", run_name)
        os.makedirs(logdir, exist_ok=True)
        open(os.path.join(logdir, "make.log"), "w").write(" ".join(cmd) + "\n" + p.stdout)
        print(f"[{'OK  ' if ok else 'FAIL'}] {name} ({time.time() - t0:.1f}s)", flush=True)
        if not ok:
            bad += 1
            print("    " + "\n    ".join(p.stdout.splitlines()[-15:]))
        results.append(dict(test=name, ok=ok))
    os.makedirs(os.path.join(SIM, "stress_results"), exist_ok=True)
    tag = f"rt-{a.shard}-{a.dut}-{a.build}{'-d' if a.dummy else ''}"
    json.dump(dict(id=tag, ok=bad == 0, results=results),
              open(os.path.join(SIM, "stress_results", tag + ".json"), "w"), indent=1)
    summ = os.environ.get("GITHUB_STEP_SUMMARY")
    if summ:
        with open(summ, "a") as f:
            f.write(f"| riscv-tests `{a.shard}` | {a.build} | {a.dut} | {'dummy' if a.dummy else '-'} | "
                    f"{len(results) - bad}/{len(results)} | **{'PASS' if bad == 0 else 'FAIL'}** |\n")
    print(f"{a.shard}: {len(results) - bad}/{len(results)} passed")
    return 0 if bad == 0 else 1


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd")
    sub.add_parser("shards")
    b = sub.add_parser("build")
    b.add_argument("--dummy", type=int, default=0)
    r = sub.add_parser("run")
    r.add_argument("--shard", required=True)
    r.add_argument("--build", default="no_spike", choices=sorted(TARGET))
    r.add_argument("--dut", default="legacy")
    r.add_argument("--link-args", default="")
    r.add_argument("--dummy", type=int, default=0)
    r.add_argument("--timeout", type=int, default=3000000)
    a = ap.parse_args()
    if not a.cmd:
        ap.error("a command is required: shards | build | run")
    if a.cmd == "shards":
        print(json.dumps({"include": shards()}, separators=(",", ":")))
        return 0
    if a.cmd == "build":
        cmd_build(a)
        return 0
    return cmd_run(a)


if __name__ == "__main__":
    sys.exit(main())
