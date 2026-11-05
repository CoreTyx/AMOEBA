#!/usr/bin/env python3
"""Cascade fuzzing on the pin bench (docs/postsynth_fuzz_plan.md).

    pin_fuzz.py gen N [--seed S] [--out DIR] [--jobs J]
    pin_fuzz.py run [DIR] [--sim verilator|vcs] [--dut rtl|rtl_sva|gate] [--prune] [-- +plusargs...]

gen  writes fz_<seed>_<i>.lst / .cmd / .txt (descriptor) into DIR (default
     sim/pin/fuzz).  Run hvl/pin/fuzz/get_cascade.sh once first.
run  runs every image in DIR through hvl/pin/pin.sh, one at a time, and
     prints one PASS/FAIL line each plus a total.  --prune deletes a passing
     program's image and run directory (about 3 MB), keeping its descriptor
     (.txt): `gen` with the same --seed regenerates it exactly.  Images are independent
     files, so several `run`s on different directories can go in parallel.

Cascade is used as published, with four replacements made from here (no fork):
  - the final block: Cascade's stops with a store to a "stop address" below
    0x8000_0000 and dumps registers; on this chip nothing below 0x8000_0000 is
    both off-chip and 64-bit-storable, and EXT_MEM stores sit in the D$.  Ours
    writes tohost = 1 and runs fence.i, like every other test's exit.
  - design profiling: Cascade runs a program on the design's own simulator to
    learn which medeleg bits stick.  The RTL fixes the core's answer
    (csrm.sv: MEDELEG_MASK, 0xB3FE with C), intersected with the bits the
    installed Spike keeps (measured: Cascade assumes 0xB3FF; Spike 1.1.0 keeps
    0xB309).  A wrong value could only make programs fail, never hide a bug.
  - counters: this core has no Zicntr/Zihpm; the initial block's mcycle and
    minstret resets become mscratch writes, and random CSR ops skip them.
  - generation seed: Cascade's gen_many_elfs always seeds 0; ours takes --seed.
A Cascade program detects a bug by not terminating, so the bench's
run_until_tohost timeout is the check.
"""
import os
import random
import subprocess
import sys

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CASCADE = os.path.join(R, "third_party", "cascade", "fuzzer")
DESIGN = "forte"
TOHOST = 0x8080_0000
MEDELEG_MASK = 0xB3FE   # hdl/core/privileged/csrm.sv, ZCA_SUPPORTED


def spike_medeleg_mask(tmp):
    """The medeleg bits the installed Spike keeps (write all ones, read back).
    Cascade pre-simulates on Spike, so a bit the core keeps and Spike drops
    makes the program disagree with the core -- seen as 146/5000 false
    failures with Spike 1.1.0 (mask 0xB309) against Cascade's assumed 0xB3FF."""
    os.makedirs(tmp, exist_ok=True)
    src, elf, cmd = (os.path.join(tmp, f) for f in ("medeleg.S", "medeleg.elf", "medeleg.cmd"))
    with open(src, "w") as f:
        f.write(".globl _start\n_start:\n li t0, -1\n csrw medeleg, t0\n csrr t1, medeleg\n1: j 1b\n")
    subprocess.run(["riscv64-unknown-elf-gcc", "-march=rv64imac_zicsr", "-mabi=lp64", "-nostdlib",
                    "-Wl,-N", "-Ttext=0x80000000", "-o", elf, src], check=True, capture_output=True)
    with open(cmd, "w") as f:
        f.write("until pc 0 0x8000000a\nreg 0 t1\nq\n")    # li is compressed: csrr ends at +0xa
    out = subprocess.run(["spike", "-d", f"--debug-cmd={cmd}", "--isa=rv64imac_zicsr_zifencei",
                          "--pc=0x80000000", "-m0x80000000:0x10000000", elf],
                         capture_output=True, text=True, timeout=60)
    vals = [l.strip() for l in (out.stdout + out.stderr).splitlines() if l.strip().startswith("0x")]
    if not vals:
        sys.exit(f"pin_fuzz.py: could not read Spike's medeleg mask:\n{out.stdout}{out.stderr}")
    return int(vals[-1], 16)


def cascade_env(tmp):
    """Point Cascade at our design entry and a scratch directory, then import it."""
    if not os.path.isdir(CASCADE):
        sys.exit("pin_fuzz.py: no Cascade checkout -- run hvl/pin/fuzz/get_cascade.sh")
    os.environ.update({
        "CASCADE_ENV_SOURCED": "yes",
        "CASCADE_DESIGN_PROCESSING_ROOT": os.path.join(R, "hvl", "pin", "fuzz", "cascade"),
        "CASCADE_DATADIR": tmp,
        "CASCADE_PATH_TO_FIGURES": os.path.join(tmp, "figures"),
        "CASCADE_META_ROOT": os.path.dirname(CASCADE),
    })
    sys.path.insert(0, CASCADE)

    import cascade.basicblock as bb
    import common.profiledesign as prof
    from params.fuzzparams import RDEP_MASK_REGISTER_ID
    from rv.asmutil import li_into_reg
    from cascade.cfinstructionclasses import (ImmRdInstruction, RegImmInstruction,
                                              IntStoreInstruction, SpecialInstruction, JALInstruction)

    def finalblock(fuzzerstate, design_name):
        # x30 (RDEP) holds tohost's address, x1 the exit value 1.  lui sign-
        # extends bit 31, so clear the upper half with slli/srli.
        a = RDEP_MASK_REGISTER_ID
        lui, addi = li_into_reg(TOHOST, do_check_bounds=False)   # its bound guards the sign extension, which slli/srli clear
        return [
            ImmRdInstruction("lui", a, lui, True),
            RegImmInstruction("addi", a, a, addi, True),
            RegImmInstruction("slli", a, a, 32, True),
            RegImmInstruction("srli", a, a, 32, True),
            RegImmInstruction("addi", 1, 0, 1, True),
            IntStoreInstruction("sd", a, 1, 0, -1, True),
            SpecialInstruction("fence.i"),       # write the D$ back: tohost reaches the link
            JALInstruction("jal", 0, 0),
        ]

    bb.finalblock = finalblock
    spike_mask = spike_medeleg_mask(tmp)
    prof.PROFILED_MEDELEG_MASK = MEDELEG_MASK & spike_mask
    print(f"medeleg: core {MEDELEG_MASK:#06x} & spike {spike_mask:#06x} = {prof.PROFILED_MEDELEG_MASK:#06x}")

    # No Zicntr/Zihpm on this core (pkg/config.vh): mcycle, minstret, mhpm*
    # are illegal here but real in Spike, so a program touching them diverges
    # from its own pre-simulation and looks like a hang.  The initial block's
    # counter resets become mscratch writes (same size, same place), and the
    # random M-mode CSR ops never pick a counter.
    import random as _random
    import cascade.initialblock as ib
    import cascade.randomize.pickrandomcsrop as pr
    from rv.csrids import CSR_IDS
    _csrreg = ib.CSRRegInstruction
    def csrreg(instr, rd, rs1, csr, *a, **k):
        return _csrreg(instr, rd, rs1, CSR_IDS.MSCRATCH if csr in (CSR_IDS.MCYCLE, CSR_IDS.MINSTRET) else csr, *a, **k)
    ib.CSRRegInstruction = csrreg

    class NoCounters:
        absent = {"MINSTRET", "MHPMCOUNTER3", "MHPMEVENT31"}
        def __getattr__(self, name):
            return getattr(_random, name)
        def choice(self, seq):
            return _random.choice([x for x in seq if getattr(x, "name", None) not in self.absent] or seq)
    pr.random = NoCounters()
    from cascade.fuzzfromdescriptor import gen_new_test_instance, gen_fuzzerstate_elf_expectedvals
    from common.spike import calibrate_spikespeed
    return gen_new_test_instance, gen_fuzzerstate_elf_expectedvals, calibrate_spikespeed


def _worker(args):
    desc, elf_out = args
    _, gen_elf = _worker.fns
    fuzzerstate, elfpath, *_ = gen_elf(*desc[:2], desc[2], desc[3], desc[4], False)
    os.replace(elfpath, elf_out)
    return sum(len(b) for b in fuzzerstate.instr_objs_seq) + len(fuzzerstate.final_bb)


def gen(n, seed, out, jobs):
    import multiprocessing as mp
    os.makedirs(out, exist_ok=True)
    tmp = os.path.join(out, "tmp")
    new_instance, gen_elf, calibrate = cascade_env(tmp)
    calibrate()
    random.seed(seed)
    descs = [new_instance(DESIGN, seed * 100003 + i, True) for i in range(n)]
    # (memsize, design_name, randseed, nmax_bbs, authorize_privileges)
    names = [f"fz_{seed}_{i}" for i in range(n)]
    _worker.fns = (new_instance, gen_elf)
    with mp.Pool(jobs) as pool:
        ninstrs = pool.map(_worker, [(d, os.path.join(out, nm + ".elf")) for d, nm in zip(descs, names)])

    for nm, d, ni in zip(names, descs, ninstrs):
        to_lst(os.path.join(out, nm + ".elf"), os.path.join(out, nm + ".lst"))
        timeout = max(200_000, 400 * ni)     # cycles; a miss costs ~50, most instructions far less
        with open(os.path.join(out, nm + ".cmd"), "w") as f:
            f.write(f"# Cascade program {nm}: {ni} instructions; descriptor in {nm}.txt\n"
                    "mem_policy zero\nload_lst $MEM\nreset 16\n"
                    f"run_until_tohost {timeout}\nexpect_tohost 0\nfinish\n")
        with open(os.path.join(out, nm + ".txt"), "w") as f:
            f.write(repr(d) + "\n")
        print(f"{nm}: {ni} instructions")


def to_lst(elf, lst):
    """Cascade's ELF is one segment at the boot address: objcopy it to binary
    and write the bench's .lst (an @word-index line, then 64-bit words).
    Not bin/generate_memory_file.py: it rejects section sizes that are not a
    multiple of 8, and it writes a shared sim/bin/memory_8.lst."""
    bin_path = elf[:-4] + ".bin"
    subprocess.run(["riscv64-unknown-elf-objcopy", "-O", "binary", elf, bin_path], check=True)
    data = open(bin_path, "rb").read()
    data += bytes(-len(data) % 8)
    with open(lst, "w") as f:
        f.write(f"@{0x8000_0000 // 8:08x}\n")
        for i in range(0, len(data), 8):
            f.write(f"{int.from_bytes(data[i:i + 8], 'little'):016x}\n")
    os.remove(bin_path)


def run(d, sim, dut, extra, prune=False):
    images = sorted(f[:-4] for f in os.listdir(d) if f.startswith("fz_") and f.endswith(".lst"))
    passed = 0
    for nm in images:
        r = subprocess.run([os.path.join(R, "hvl", "pin", "pin.sh"), "run",
                            os.path.join(d, nm + ".lst"), os.path.join(d, nm + ".cmd"), "+UART_QUIET", *extra],
                           env={**os.environ, "SIM": sim, "DUT": dut}, capture_output=True, text=True)
        verdict = next((l for l in r.stdout.splitlines() if l.startswith("PIN_TB_RESULT:")), "PIN_TB_RESULT: FAIL no verdict")
        ok = "PASS" in verdict
        passed += ok
        print(f"{'PASS' if ok else 'FAIL'} {nm}  {'' if ok else verdict}", flush=True)
        if ok and prune:
            import shutil
            for ext in (".lst", ".elf", ".cmd"):
                if os.path.exists(os.path.join(d, nm + ext)):
                    os.remove(os.path.join(d, nm + ext))
            shutil.rmtree(os.path.join(R, "sim", "pin", "runs", f"{sim}_{dut}", nm), ignore_errors=True)
    print(f"fuzz: {passed}/{len(images)} passed ({sim}/{dut})")
    return 0 if passed == len(images) else 1


def main(argv):
    def opt(name, default):
        if name in argv:
            i = argv.index(name); v = argv[i + 1]; del argv[i:i + 2]; return v
        return default
    extra = argv[argv.index("--") + 1:] if "--" in argv else []
    argv = argv[:argv.index("--")] if "--" in argv else argv
    if argv[:1] == ["gen"] and len(argv) >= 2:
        venv = os.path.join(R, "third_party", "cascade", ".venv", "bin", "python")
        if os.path.exists(venv) and os.path.realpath(sys.prefix) != os.path.realpath(os.path.dirname(os.path.dirname(venv))):
            os.execv(venv, [venv, os.path.abspath(__file__), *sys.argv[1:]])   # Cascade's dependencies
        seed, out, jobs = int(opt("--seed", 1)), opt("--out", os.path.join(R, "sim", "pin", "fuzz")), int(opt("--jobs", 4))
        gen(int(argv[1]), seed, out, jobs)
        return 0
    if argv[:1] == ["run"]:
        sim, dut = opt("--sim", "verilator"), opt("--dut", "rtl")
        prune = "--prune" in argv
        argv = [a for a in argv if a != "--prune"]
        return run(argv[1] if len(argv) > 1 else os.path.join(R, "sim", "pin", "fuzz"), sim, dut, extra, prune)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
