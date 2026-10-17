#!/usr/bin/python3
"""Random-program fuzzer for the AMOEBA core.

Generates random, self-terminating RISC-V assembly programs, runs each one on a
Verilator build of the testbench and sorts the runs by how they ended.  The
oracle is whatever the simulator binary was built with: Spike co-simulation and
the RVFI checker (build/), the RVFI checker alone (build_no_spike/), or the
same with fault injection enabled (build_ecc_inject/).

Usually driven from sim/Makefile:

    make -C sim fuzz_no_spike FUZZ_N=200 FUZZ_SEED=1 FUZZ_JOBS=4
    make -C sim fuzz          FUZZ_N=200          # needs spike with --log-commits
    make -C sim fuzz_ecc_inject FUZZ_N=200

Every program is a function of its seed alone (given the same options), and a
failing program is saved as a standalone .s under sim/fuzz/failures/<kind>/, so
it replays through the ordinary flow:

    make -C sim run_verilator_top_tb_no_spike PROG=fuzz/failures/<kind>/seed_<n>.s

To shrink a failing program to the lines that matter:

    python3 bin/fuzz.py --sim sim/verilator/build_no_spike/Vtop_tb \\
        --minimize sim/fuzz/failures/<kind>/seed_<n>.s

Program shape
  * x27 is the data base pointer, x29 the loop counter and x30 the trap
    handler's scratch register.  The random body never writes them, which is
    what keeps memory accesses in bounds, loops finite and traps recoverable.
  * Branches and jumps only go forward; loops count x29 down from a small
    constant and do not nest.  Every program therefore reaches the tohost write.
  * Loads and stores are aligned and land in a .data scratch area made of more
    regions than the D-cache has ways, each one way-size apart, so re-pointing
    x27 forces set conflicts and evictions.
"""

import argparse
import concurrent.futures
import os
import random
import re
import shutil
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(SCRIPT_DIR)

BASE, LOOP, TRAP = 27, 29, 30
RESERVED = {BASE, LOOP, TRAP}
DEST_REGS = [r for r in range(1, 32) if r not in RESERVED]
RVC_REGS = list(range(8, 16))       # the registers most compressed forms need

# Scratch layout.  hdl config: DCACHE_NUMWAYS = 4, DCACHE_WAYSIZEINBYTES = 1024.
REGION_BYTES = 1024
NUM_REGIONS = 8

# Funct7 = 1111111 on the OP opcode is reserved in every extension, so this is
# an illegal instruction on the core and on Spike alike.
ILLEGAL_WORD = 0xFE000033

RAND_INSTR_INSERT_FREQ = 0x7C1      # hdl/core/privileged/csrm.sv

INTERESTING = [
    0, 1, 2, -1, -2,
    0x7FFFFFFFFFFFFFFF, -0x8000000000000000, -0x7FFFFFFFFFFFFFFF,
    0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, -0x80000000, 0x100000000,
    0x5555555555555555, -0x5555555555555556, 0xFF, 0xFFFF, 63, 64, 31, 32,
]

OP_RR = ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and",
         "addw", "subw", "sllw", "srlw", "sraw"]
OP_RI = ["addi", "slti", "sltiu", "xori", "ori", "andi", "addiw"]
OP_SH64 = ["slli", "srli", "srai"]
OP_SH32 = ["slliw", "srliw", "sraiw"]
OP_MULDIV = ["mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu",
             "mulw", "divw", "divuw", "remw", "remuw"]
OP_LOAD = [("lb", 1), ("lbu", 1), ("lh", 2), ("lhu", 2), ("lw", 4), ("lwu", 4), ("ld", 8)]
OP_STORE = [("sb", 1), ("sh", 2), ("sw", 4), ("sd", 8)]
OP_AMO = ["amoswap", "amoadd", "amoxor", "amoand", "amoor",
          "amomin", "amomax", "amominu", "amomaxu"]
OP_BRANCH = ["beq", "bne", "blt", "bge", "bltu", "bgeu"]
OP_CSR_R = ["csrrw", "csrrs", "csrrc"]
OP_CSR_I = ["csrrwi", "csrrsi", "csrrci"]

# Relative frequency of each kind of body item.  "trap" and "rand_insert" are
# overridden from the command line.
WEIGHTS = {
    "alu_rr": 20, "alu_ri": 16, "shift": 8, "muldiv": 10, "li": 8, "upper": 3,
    "load": 12, "store": 12, "rebase": 4, "amo": 3, "branch": 8, "jump": 3,
    "loop": 2, "csr": 2, "fence": 1, "rvc": 2, "trap": 0, "rand_insert": 0,
}

BODY_BEGIN = "# fuzz:body-begin"
BODY_END = "# fuzz:body-end"


class Generator:
    def __init__(self, seed, length, weights):
        self.rng = random.Random(seed)
        self.length = length
        self.weights = weights
        self.label_count = 0
        self.budget = 0

    def reg(self):
        return self.rng.choice(RVC_REGS) if self.rng.random() < 0.4 else self.rng.randrange(32)

    def dest(self):
        if self.rng.random() < 0.05:
            return 0
        pool = [r for r in RVC_REGS if r in DEST_REGS] if self.rng.random() < 0.4 else DEST_REGS
        return self.rng.choice(pool)

    def value(self):
        r = self.rng.random()
        if r < 0.5:
            return self.rng.choice(INTERESTING)
        if r < 0.7:
            return 1 << self.rng.randrange(64)
        if r < 0.8:
            return self.rng.randrange(-2048, 2048)
        return self.rng.getrandbits(64) - (1 << 63)

    def imm12(self):
        if self.rng.random() < 0.4:
            return self.rng.choice([0, 1, -1, 7, 63, 2047, -2048, 0x7FF, -0x400])
        return self.rng.randrange(-2048, 2048)

    def label(self):
        self.label_count += 1
        return f".Lf{self.label_count}"

    def item(self, in_loop, depth):
        kinds = [k for k, w in self.weights.items() if w > 0
                 and not (k == "loop" and (in_loop or depth > 0))
                 and not (k in ("branch", "jump") and depth >= 2)]
        kind = self.rng.choices(kinds, [self.weights[k] for k in kinds])[0]
        return getattr(self, "gen_" + kind)(in_loop, depth)

    def block(self, count, in_loop, depth):
        lines = []
        for _ in range(count):
            if self.budget <= 0:
                break
            self.budget -= 1
            lines += self.item(in_loop, depth)
        return lines

    # ── straight-line items ──────────────────────────────────────────────────
    def gen_alu_rr(self, *_):
        return [f"    {self.rng.choice(OP_RR)} x{self.dest()}, x{self.reg()}, x{self.reg()}"]

    def gen_alu_ri(self, *_):
        return [f"    {self.rng.choice(OP_RI)} x{self.dest()}, x{self.reg()}, {self.imm12()}"]

    def gen_shift(self, *_):
        if self.rng.random() < 0.7:
            amount = self.rng.choice([0, 1, 31, 32, 63, self.rng.randrange(64)])
            return [f"    {self.rng.choice(OP_SH64)} x{self.dest()}, x{self.reg()}, {amount}"]
        amount = self.rng.choice([0, 1, 31, self.rng.randrange(32)])
        return [f"    {self.rng.choice(OP_SH32)} x{self.dest()}, x{self.reg()}, {amount}"]

    def gen_muldiv(self, *_):
        return [f"    {self.rng.choice(OP_MULDIV)} x{self.dest()}, x{self.reg()}, x{self.reg()}"]

    def gen_li(self, *_):
        return [f"    li x{self.dest()}, {self.value()}"]

    def gen_upper(self, *_):
        op = self.rng.choice(["lui", "auipc"])
        return [f"    {op} x{self.dest()}, {self.rng.randrange(1 << 20)}"]

    def offset(self, size):
        return self.rng.randrange(REGION_BYTES // size) * size

    def gen_load(self, *_):
        op, size = self.rng.choice(OP_LOAD)
        return [f"    {op} x{self.dest()}, {self.offset(size)}(x{BASE})"]

    def gen_store(self, *_):
        op, size = self.rng.choice(OP_STORE)
        return [f"    {op} x{self.reg()}, {self.offset(size)}(x{BASE})"]

    def gen_rebase(self, *_):
        return [f"    la x{BASE}, scratch + {self.rng.randrange(NUM_REGIONS) * REGION_BYTES}"]

    def gen_amo(self, *_):
        op = self.rng.choice(OP_AMO) + self.rng.choice([".w", ".d"])
        return [f"    {op} x{self.dest()}, x{self.reg()}, (x{BASE})"]

    def gen_csr(self, *_):
        if self.rng.random() < 0.5:
            return [f"    {self.rng.choice(OP_CSR_R)} x{self.dest()}, mscratch, x{self.reg()}"]
        return [f"    {self.rng.choice(OP_CSR_I)} x{self.dest()}, mscratch, {self.rng.randrange(32)}"]

    def gen_fence(self, *_):
        return ["    fence.i"]

    def gen_rvc(self, *_):
        return ["    .option " + self.rng.choice(["rvc", "norvc"])]

    def gen_trap(self, *_):
        # Both are exactly four bytes, which is what the handler steps over.
        if self.rng.random() < 0.5:
            return ["    ecall"]
        return [f"    .4byte 0x{ILLEGAL_WORD:08x}"]

    def gen_rand_insert(self, *_):
        period = self.rng.choice([0, 1, 2, 3, 5, 8, 17, self.rng.randrange(1, 64)])
        rd = self.rng.choice([r for r in DEST_REGS if r != 0])
        return [f"    li x{rd}, {period}", f"    csrw 0x{RAND_INSTR_INSERT_FREQ:x}, x{rd}"]

    # ── control flow ─────────────────────────────────────────────────────────
    def gen_branch(self, in_loop, depth):
        target = self.label()
        lines = [f"    {self.rng.choice(OP_BRANCH)} x{self.reg()}, x{self.reg()}, {target}"]
        lines += self.block(self.rng.randrange(1, 6), in_loop, depth + 1)
        return lines + [f"{target}:"]

    def gen_jump(self, in_loop, depth):
        target = self.label()
        if self.rng.random() < 0.5:
            lines = [f"    jal x{self.dest()}, {target}"]
        else:
            addr = self.rng.choice([r for r in DEST_REGS if r != 0])
            lines = [f"    la x{addr}, {target}", f"    jalr x{self.dest()}, 0(x{addr})"]
        # Skipped over: only ever fetched speculatively.
        lines += self.block(self.rng.randrange(1, 4), in_loop, depth + 1)
        return lines + [f"{target}:"]

    def gen_loop(self, _in_loop, depth):
        top = self.label()
        lines = [f"    li x{LOOP}, {self.rng.randrange(1, 5)}", f"{top}:"]
        lines += self.block(self.rng.randrange(2, 9), True, depth + 1)
        return lines + [f"    addi x{LOOP}, x{LOOP}, -1", f"    bnez x{LOOP}, {top}"]

    # ── whole program ────────────────────────────────────────────────────────
    def program(self, header):
        out = [f"# {line}" for line in header]
        out += [
            "    .option norvc",
            '    .section .init, "ax"',
            "    .globl _start",
            "_start:",
            f"    la x{TRAP}, trap_handler",
            f"    csrw mtvec, x{TRAP}",
            "    csrwi mie, 0",
        ]
        for r in range(1, 32):
            if r not in RESERVED:
                out.append(f"    li x{r}, {self.value()}")
        out += [f"    li x{LOOP}, 0", f"    li x{TRAP}, 0", f"    la x{BASE}, scratch", BODY_BEGIN]
        self.budget = self.length
        while self.budget > 0:
            out += self.block(self.budget, False, 0)
        out += [
            BODY_END,
            "    .option norvc",
            f"    li x{LOOP}, 1",
            f"    la x{TRAP}, tohost",
            f"    sd x{LOOP}, 0(x{TRAP})",
            "    slti x0, x0, -256",
            "1:  j 1b",
            "",
            # mtvec[1:0] is the mode field, so the handler must be 4-aligned.  gas
            # treats .balign 4 as already satisfied under norvc, even when earlier
            # compressed code left the address at 2 mod 4, so align under rvc.
            "    .option rvc",
            "    .balign 4",
            "    .option norvc",
            "trap_handler:",
            f"    csrr x{TRAP}, mepc",
            f"    addi x{TRAP}, x{TRAP}, 4",
            f"    csrw mepc, x{TRAP}",
            "    mret",
            "",
            '    .section .data, "aw"',
            "    .balign 16",
            "scratch:",
        ]
        for _ in range(NUM_REGIONS * REGION_BYTES // 8):
            out.append(f"    .dword 0x{self.rng.getrandbits(64):016x}")
        return "\n".join(out) + "\n"


# ── build and run ────────────────────────────────────────────────────────────
def find_tool(name):
    for prefix in ["riscv64-unknown-elf-", "riscv64-elf-"]:
        if shutil.which(prefix + name):
            return prefix + name
    sys.exit(f"fuzz: no RISC-V {name} found in PATH")


def get_option(key):
    result = subprocess.run([sys.executable, os.path.join(SCRIPT_DIR, "get_options.py"), key],
                            stdout=subprocess.PIPE, check=True)
    return result.stdout.decode().strip()


class Runner:
    def __init__(self, sim, timeout_cycles, wall_timeout):
        self.sim = os.path.abspath(sim)
        if not os.access(self.sim, os.X_OK):
            sys.exit(f"fuzz: simulator {self.sim} not found -- build it first")
        self.timeout_cycles = timeout_cycles
        self.wall_timeout = wall_timeout
        self.gcc = find_tool("gcc")
        self.objcopy = find_tool("objcopy")
        self.arch = get_option("arch")
        self.abi = get_option("abi")
        self.clock = get_option("clock")
        self.bmem_x = get_option("bmem_x")
        linker_script = os.path.join(SCRIPT_DIR, "link.ld")
        with open(linker_script) as f:
            self.load_addr = int(re.search(r"_text_start\s*=\s*(0x[0-9a-fA-F]+)", f.read()).group(1), 16)
        self.linker_script = linker_script

    def build(self, source, run_dir):
        """Assemble source into run_dir.  Returns (memory list, elf) or None."""
        elf = os.path.join(run_dir, "prog.elf")
        binary = os.path.join(run_dir, "prog.bin")
        memlst = os.path.join(run_dir, "memory_8.lst")
        cmd = [self.gcc, "-mcmodel=medany", "-ffreestanding", "-nostartfiles", "-nostdlib",
               "-static", "-Wl,--no-relax", f"-march={self.arch}", f"-mabi={self.abi}",
               "-T", self.linker_script, source, "-o", elf]
        with open(os.path.join(run_dir, "compile.log"), "w") as log:
            if subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT).returncode != 0:
                return None
            if subprocess.run([self.objcopy, "-O", "binary", elf, binary],
                              stdout=log, stderr=subprocess.STDOUT).returncode != 0:
                return None
        with open(binary, "rb") as f:
            image = f.read()
        image += bytes(-len(image) % 8)
        # Same format bin/generate_memory_file.py -8 writes: one 64-bit word per
        # line, addressed by word index.
        with open(memlst, "w") as f:
            f.write(f"@{self.load_addr >> 3:08x}\n")
            for i in range(0, len(image), 8):
                f.write(image[i:i + 8][::-1].hex() + "\n")
        return memlst, elf

    def run(self, source, run_dir):
        """Build and simulate source.  Returns (kind, log path); kind is "pass" on success."""
        # monitor.sv writes ./time.txt and ../spike/commit.log relative to the
        # working directory, so each run gets its own pair of directories.
        cwd = os.path.join(run_dir, "verilator")
        os.makedirs(cwd, exist_ok=True)
        os.makedirs(os.path.join(run_dir, "spike"), exist_ok=True)
        built = self.build(source, run_dir)
        if built is None:
            return "asm_error", os.path.join(run_dir, "compile.log")
        memlst, elf = built
        log_path = os.path.join(run_dir, "simulation.log")
        cmd = [self.sim, f"+TIMEOUT_ECE411={self.timeout_cycles}",
               f"+CLOCK_PERIOD_PS_ECE411={self.clock}", f"+BRAM_0_ON_X_ECE411={self.bmem_x}",
               f"+MEMLST_ECE411={memlst}", f"+ELF_ECE411={elf}"]
        with open(log_path, "w") as log:
            try:
                rc = subprocess.run(cmd, cwd=cwd, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=self.wall_timeout).returncode
            except subprocess.TimeoutExpired:
                return "wall_timeout", log_path
        return classify(rc, log_path), log_path


# Checked in the order the lines appear in the log, so the first thing that went
# wrong names the failure.
FAILURE_PATTERNS = [
    ("spike_mismatch", "Spike Monitor Error"),
    ("spike_exit", "Spike exited with error"),
    ("rvfi_checker", "RVFI Monitor Error"),
    ("rvfi_x", "RVFI Interface Error"),
    ("memory_error", "Memory Error"),
    ("timeout", "Timed out"),
    ("tohost_fail", "test FAILED"),
]


def classify(rc, log_path):
    passed = False
    with open(log_path, errors="replace") as f:
        for line in f:
            for kind, pattern in FAILURE_PATTERNS:
                if pattern in line:
                    return kind
            passed = passed or "test PASSED" in line
    if rc < 0:
        return f"signal_{-rc}"
    if rc != 0:
        return "sim_error"
    return "pass" if passed else "no_verdict"


def signature(kind, log_path):
    """What minimize() must preserve: the failure kind plus, when the RVFI checker
    reported one, its message and the instruction it was looking at.  Matching on
    the kind alone lets a shrinking program drift onto a different bug."""
    if kind in ("pass", "asm_error"):
        return (kind,)
    detail = []
    with open(log_path, errors="replace") as f:
        for line in f:
            for key in ("Error message:", "rvfi_insn ="):
                if line.startswith(key) and not any(d.startswith(key) for d in detail):
                    detail.append(line.strip())
    return (kind, *detail)


def fuzz_one(runner, args, weights, seed):
    run_dir = os.path.join(args.out, "work", f"seed_{seed}")
    shutil.rmtree(run_dir, ignore_errors=True)
    os.makedirs(run_dir)
    source = os.path.join(run_dir, f"seed_{seed}.s")
    header = [
        f"Generated by bin/fuzz.py --seed {seed} --count 1 --length {args.length}"
        + (f" --trap-weight {args.trap_weight}" if args.trap_weight else "")
        + (" --rand-insert" if args.rand_insert else ""),
        "x27 = data base, x29 = loop counter, x30 = trap scratch; the body never writes them.",
    ]
    with open(source, "w") as f:
        f.write(Generator(seed, args.length, weights).program(header))
    kind, log_path = runner.run(source, run_dir)
    if kind != "pass":
        dest = os.path.join(args.out, "failures", kind)
        os.makedirs(dest, exist_ok=True)
        shutil.copy(source, dest)
        shutil.copy(log_path, os.path.join(dest, f"seed_{seed}.log"))
    if kind == "pass" or not args.keep:
        shutil.rmtree(run_dir, ignore_errors=True)
    return seed, kind


def minimize(runner, args):
    """Delta-debug the body of a failing program down to the lines that matter."""
    with open(args.minimize) as f:
        lines = f.read().splitlines()
    try:
        begin, end = lines.index(BODY_BEGIN), lines.index(BODY_END)
    except ValueError:
        sys.exit(f"fuzz: {args.minimize} has no {BODY_BEGIN} / {BODY_END} markers")
    head, body, tail = lines[:begin + 1], lines[begin + 1:end], lines[end:]
    work = os.path.join(args.out, "work", "minimize")
    trial = os.path.join(work, "trial.s")

    def outcome(candidate):
        shutil.rmtree(work, ignore_errors=True)
        os.makedirs(work)
        with open(trial, "w") as f:
            f.write("\n".join(head + candidate + tail) + "\n")
        return signature(*runner.run(trial, work))

    target = outcome(body)
    if target[0] == "pass":
        sys.exit("fuzz: the program passes on this simulator; nothing to minimize")
    print(f"fuzz: minimizing for {' / '.join(target)}, {len(body)} body lines")
    # A candidate that no longer assembles (a branch lost its label) or that
    # fails some other way simply does not match, and its lines are kept.  The
    # instruction encoding is part of the match, so lines whose removal would
    # only move or re-encode the failing instruction are kept as well.
    chunk = max(len(body) // 2, 1)
    while True:
        i = 0
        while i < len(body):
            candidate = body[:i] + body[i + chunk:]
            if outcome(candidate) == target:
                body = candidate
                print(f"fuzz:   {len(body)} lines left")
            else:
                i += chunk
        if chunk == 1:
            break
        chunk = max(chunk // 2, 1)
    out_path = re.sub(r"\.s$", "", args.minimize) + ".min.s"
    with open(out_path, "w") as f:
        f.write("\n".join(head + body + tail) + "\n")
    shutil.rmtree(work, ignore_errors=True)
    print(f"fuzz: wrote {out_path} ({len(body)} body lines, still {target[0]})")


def main():
    p = argparse.ArgumentParser(description="Random-program fuzzer for the AMOEBA core.")
    p.add_argument("--sim", required=True, help="Verilator testbench binary (Vtop_tb) to run")
    p.add_argument("--out", default=os.path.join(REPO_DIR, "sim", "fuzz"), help="output directory")
    p.add_argument("--seed", type=int, default=1, help="seed of the first program")
    p.add_argument("--count", type=int, default=100, help="number of programs")
    p.add_argument("--length", type=int, default=200, help="body items per program")
    p.add_argument("--jobs", type=int, default=1, help="simulations to run at once")
    p.add_argument("--timeout", type=int, default=200000, help="simulation timeout in cycles")
    p.add_argument("--wall-timeout", type=int, default=600, help="per-run limit in seconds")
    p.add_argument("--trap-weight", type=int, default=0,
                   help="relative frequency of ecall / illegal instructions (0 = none)")
    p.add_argument("--rand-insert", action="store_true",
                   help="write random periods to the dummy-insertion CSR (0x7c1); "
                        "under co-simulation this needs a Spike that knows the CSR")
    p.add_argument("--keep", action="store_true", help="keep work directories of failing runs")
    p.add_argument("--minimize", metavar="FILE.s", help="shrink a failing program instead of fuzzing")
    args = p.parse_args()
    args.out = os.path.abspath(args.out)

    runner = Runner(args.sim, args.timeout, args.wall_timeout)
    if args.minimize:
        minimize(runner, args)
        return

    weights = dict(WEIGHTS, trap=args.trap_weight, rand_insert=2 if args.rand_insert else 0)
    counts = {}
    seeds = range(args.seed, args.seed + args.count)
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for done, (seed, kind) in enumerate(pool.map(lambda s: fuzz_one(runner, args, weights, s), seeds), 1):
            counts[kind] = counts.get(kind, 0) + 1
            if kind != "pass":
                print(f"fuzz: seed {seed}: {kind}", flush=True)
            if done % 10 == 0 or done == args.count:
                print(f"fuzz: {done}/{args.count} run, {counts.get('pass', 0)} passed", flush=True)

    print("fuzz: summary")
    for kind in sorted(counts):
        print(f"fuzz:   {kind:16s} {counts[kind]}")
    failed = args.count - counts.get("pass", 0)
    if failed:
        print(f"fuzz: failing programs and logs are in {os.path.join(args.out, 'failures')}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
