#!/usr/bin/env python3
"""
patch_bootarg.py -- select which userland program a Linux boot image runs,
without rebuilding OpenSBI, the device tree or the kernel.

testcode/linux/Makefile puts a fixed-width slot on the kernel command line:

    amoeba_prog=________________        (16 underscores)

The kernel passes unknown key=value parameters to /init as environment
variables, and /init (testcode/linux/initramfs/init.c) runs only the program
named there, after stripping trailing underscores.  This script rewrites the
slot inside a finished .lst image (the format of bin/linux_image_to_lst.py:
`@<word index>` lines, then one 64-bit little-endian word per line, most
significant byte first).  The bootargs keep exactly the same length, so the
FDT's layout -- and therefore everything OpenSBI and the kernel parse from
it -- is unchanged apart from those bytes.  FDTs carry no checksum.

    patch_bootarg.py boot.lst boot_pfault.lst pfault
    patch_bootarg.py boot.lst boot_all.lst ""        # all programs (no-op copy)
"""
import sys

SLOT = b"amoeba_prog="
WIDTH = 16


def read_lst(path):
    segs, cur = [], None
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("@"):
                cur = [int(line[1:], 16), []]
                segs.append(cur)
            else:
                cur[1].append(int(line, 16))
    return segs


def write_lst(path, segs):
    with open(path, "w") as f:
        for start, words in segs:
            f.write(f"@{start:08x}\n")
            for w in words:
                f.write(f"{w:016x}\n")


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    src, dst, name = sys.argv[1], sys.argv[2], sys.argv[3]
    if len(name) > WIDTH or any(c in name for c in " =\"'"):
        sys.exit(f"error: program name '{name}' must be at most {WIDTH} plain characters")
    value = (name.encode() + b"_" * WIDTH)[:WIDTH]
    segs = read_lst(src)
    hits = 0
    for seg in segs:
        blob = bytearray(b"".join(w.to_bytes(8, "little") for w in seg[1]))
        pos = blob.find(SLOT + b"_" * WIDTH)
        while pos >= 0:
            blob[pos + len(SLOT):pos + len(SLOT) + WIDTH] = value
            hits += 1
            pos = blob.find(SLOT + b"_" * WIDTH, pos + 1)
        if hits:
            seg[1] = [int.from_bytes(blob[i:i + 8], "little") for i in range(0, len(blob), 8)]
    if hits == 0:
        sys.exit("error: no `amoeba_prog=________________` slot in the image -- "
                 "was it built from a testcode/linux/Makefile with PROG_SLOT?")
    write_lst(dst, segs)
    print(f"{dst}: amoeba_prog={value.decode()} ({hits} occurrence{'s' if hits != 1 else ''})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
