#!/usr/bin/env python3
"""fi_arm_lst.py -- the FI_ARM prologue, patched into a built memory image
(hvl/pin/fi_always.sh).

    fi_arm_lst.py <in.lst> <out.lst> <fi_control>

FI_CONTROL resets to 0, so a test runs with injection only if something
arms it first.  This replaces the image's first 8 bytes (at the reset
vector) with a jump to a stub in the tohost window, past the tohost line,
that writes FI_CONTROL, runs the 8 displaced bytes and jumps back.  The
image is otherwise untouched, so any test runs armed without a rebuild.
The jump and the stub use t0 and t1, which the core does not reset.
The displaced instructions must not depend on their address.
"""
import sys

RESET_VECTOR = 0x8000_0000
STUB = 0x8080_0100
FI_CONTROL = 0x1007_000B
T0, T1 = 5, 6


def read_lst(path):
    """{byte address of an 8-byte word: its value}"""
    words, addr = {}, None
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        if line.startswith("@"):
            addr = int(line[1:], 16) * 8
        else:
            words[addr] = int(line, 16)
            addr += 8
    return words


def write_lst(path, words):
    with open(path, "w") as f:
        expect = None
        for addr in sorted(words):
            if addr != expect:
                f.write(f"@{addr // 8:08x}\n")
            f.write(f"{words[addr]:016x}\n")
            expect = addr + 8


def u_type(op, rd, imm20):
    return (imm20 & 0xFFFFF) << 12 | rd << 7 | op


def i_type(op, funct3, rd, rs1, imm12):
    return (imm12 & 0xFFF) << 20 | rs1 << 15 | funct3 << 12 | rd << 7 | op


def s_type(funct3, rs1, rs2, imm12):
    return (imm12 >> 5 & 0x7F) << 25 | rs2 << 20 | rs1 << 15 | funct3 << 12 | (imm12 & 0x1F) << 7 | 0x23


def hi_lo(offset):
    lo = offset & 0xFFF
    lo = lo - 0x1000 if lo & 0x800 else lo
    return (offset - lo) >> 12, lo


def far_jump(pc, target):
    """auipc t0 / jalr x0: 8 bytes from pc to target."""
    hi, lo = hi_lo(target - pc)
    return [u_type(0x17, T0, hi), i_type(0x67, 0, 0, T0, lo)]


def address_independent(code):
    """The 8 bytes split into whole instructions none of which reads the pc."""
    i = 0
    while i < len(code):
        half = int.from_bytes(code[i:i + 2], "little")
        if half & 3 == 3:
            if i + 4 > len(code):
                return False
            word = int.from_bytes(code[i:i + 4], "little")
            if word & 0x7F in (0x17, 0x6F, 0x67, 0x63):   # auipc, jal, jalr, branch
                return False
            i += 4
        else:
            quadrant, funct3 = half & 3, half >> 13
            if quadrant == 1 and funct3 in (1, 5, 6, 7):   # c.jal, c.j, c.beqz, c.bnez
                return False
            if quadrant == 2 and funct3 == 4 and (half >> 2) & 0x1F == 0 and (half >> 7) & 0x1F:
                return False                                # c.jr, c.jalr
            i += 2
    return True


def main():
    src, dst, arm = sys.argv[1], sys.argv[2], int(sys.argv[3], 0)
    words = read_lst(src)
    if RESET_VECTOR not in words:
        sys.exit(f"{src}: nothing at the reset vector {RESET_VECTOR:#x}")
    if any(STUB <= a < STUB + 64 for a in words):
        sys.exit(f"{src}: the image already uses the stub's place {STUB:#x}")
    displaced = words[RESET_VECTOR].to_bytes(8, "little")
    if not address_independent(displaced):
        sys.exit(f"{src}: the first 8 bytes ({displaced.hex()}) depend on their address")

    hi, lo = hi_lo(FI_CONTROL)
    stub = [
        u_type(0x37, T0, hi),                    # lui   t0, FI_CONTROL
        i_type(0x13, 0, T1, 0, arm),             # li    t1, arm
        s_type(0, T0, T1, lo),                   # sb    t1, FI_CONTROL(t0)
        0x0FF0000F,                              # fence iorw, iorw
    ]
    code = b"".join(w.to_bytes(4, "little") for w in stub) + displaced
    back = STUB + len(code)
    code += b"".join(w.to_bytes(4, "little") for w in far_jump(back, RESET_VECTOR + 8))
    code += bytes(-len(code) % 8)
    for i in range(0, len(code), 8):
        words[STUB + i] = int.from_bytes(code[i:i + 8], "little")
    jump = far_jump(RESET_VECTOR, STUB)
    words[RESET_VECTOR] = jump[0] | jump[1] << 32
    write_lst(dst, words)


if __name__ == "__main__":
    main()
