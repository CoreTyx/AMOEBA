#!/usr/bin/env python3
"""Fuzzing front end for the pin bench -- STUB until a generator is chosen.

The bench side is done: hvl/pin/fuzz/fuzz.cmd runs one case and dumps its
signature.  What a generator must provide, whichever one is plugged in
(Cascade, riscv-dv, AAPG, ...):

  gen   --seed N --out DIR   DIR/case.elf: RV64IMAC + Zicsr/Zifencei, M/S/U,
                             Sv39 allowed; no F/D, no Zicbo*.  Entry at
                             0x8000_0000, memory 0x8000_0000-0x8FFF_FFFF.  On
                             completion it stores its signature (registers and
                             any checked memory) at SIG_BASE, writes tohost =
                             (code << 1) | 1, then executes fence.i -- the D$ is
                             write-back and only fence.i makes the stores
                             visible on the link.
  ref   DIR                  DIR/reference.hex in the bench's dump_mem format
                             ("<addr> <64-bit word>" per line), from Spike.
  check DIR RUN              compare RUN/signature.hex with DIR/reference.hex.

Each case then runs twice through hvl/pin/pin.sh: on the RTL (DUT=rtl) and on
the netlist (DUT=gate), and bin/pin_trace_cmp.py requires their pin traces to
match.  A case therefore fails on any of: a timeout, a nonzero exit code, a
signature that disagrees with Spike, or a netlist that differs from its RTL
at the pins.
"""
import sys

SIG_BASE = 0x80F0_0000
SIG_BYTES = 4096


def check(ref_path, run_dir):
    """The one part that does not depend on the generator."""
    def load(p):
        with open(p) as f:
            return {int(a, 16): int(w, 16) for a, w in (ln.split() for ln in f if ln.strip())}
    ref, got = load(ref_path), load(f"{run_dir}/signature.hex")
    bad = [a for a in sorted(ref) if got.get(a) != ref[a]]
    for a in bad[:8]:
        print(f"signature {a:#x}: got {got.get(a, 0):#018x}, expected {ref[a]:#018x}")
    print(f"{'MATCH' if not bad else 'MISMATCH'}: {len(ref) - len(bad)}/{len(ref)} words")
    return 1 if bad else 0


def main(argv):
    if len(argv) == 3 and argv[0] == "check":
        return check(f"{argv[1]}/reference.hex", argv[2])
    if argv and argv[0] in ("gen", "ref"):
        print(f"pin_fuzz.py {argv[0]}: no generator selected yet -- see the docstring")
        return 2
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
