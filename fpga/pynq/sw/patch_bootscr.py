#!/usr/bin/env python3
"""Add a kernel argument to PYNQ's boot.scr without u-boot-tools.

  sudo python3 patch_bootscr.py /boot/boot.scr            # adds mem=256M
  sudo python3 patch_bootscr.py /boot/boot.scr --arg mem=256M
  sudo python3 patch_bootscr.py /boot/boot.scr --dry-run  # show, change nothing

Why this exists: the board that needs the edit has no route to an apt mirror,
and neither did the build host.  A U-Boot legacy image is 64 bytes of header
(magic, CRCs, type) and, for TYPE=script, an 8-byte size table before the
text -- small enough to implement here rather than to depend on mkimage for.

The safety argument, since this rewrites the file the board boots from:
BEFORE anything is modified, both CRCs of the EXISTING boot.scr are verified
against this script's own computation.  If they match, our CRC convention is
U-Boot's -- proven against the very file U-Boot already accepts -- so the
rewritten header will verify too.  If they do not match, nothing is touched.
A .orig backup is written either way, and the edit is idempotent.
"""

import argparse
import os
import struct
import sys
import time
import zlib

MAGIC = 0x27051956
HDR = struct.Struct(">7I4B32s")     # ih_magic..ih_comp + ih_name; 64 bytes
IH_TYPE_SCRIPT = 6


def crc32(b: bytes) -> int:
    return zlib.crc32(b) & 0xFFFFFFFF


def parse(blob: bytes):
    if len(blob) < HDR.size + 8:
        sys.exit("error: file too small to be a boot.scr")
    (magic, hcrc, mtime, size, load, ep, dcrc,
     ih_os, arch, typ, comp, name) = HDR.unpack_from(blob, 0)
    if magic != MAGIC:
        sys.exit(f"error: bad uImage magic 0x{magic:08x}")
    if typ != IH_TYPE_SCRIPT:
        sys.exit(f"error: ih_type={typ}, not a script image")
    data = blob[HDR.size:HDR.size + size]
    if len(data) != size:
        sys.exit("error: truncated payload")

    # The two proofs that our arithmetic is U-Boot's arithmetic.
    if crc32(data) != dcrc:
        sys.exit("error: payload CRC mismatch -- refusing to touch this file")
    zeroed = HDR.pack(magic, 0, mtime, size, load, ep, dcrc,
                      ih_os, arch, typ, comp, name)
    if crc32(zeroed) != hcrc:
        sys.exit("error: header CRC mismatch -- refusing to touch this file")

    script_size, term = struct.unpack_from(">II", data, 0)
    if term != 0 or script_size != size - 8:
        sys.exit("error: unexpected script size table")
    return (mtime, load, ep, ih_os, arch, typ, comp, name), data[8:]


def build(meta, script: bytes) -> bytes:
    mtime, load, ep, ih_os, arch, typ, comp, name = meta
    data = struct.pack(">II", len(script), 0) + script
    dcrc = crc32(data)
    zeroed = HDR.pack(MAGIC, 0, mtime, len(data), load, ep, dcrc,
                      ih_os, arch, typ, comp, name)
    return HDR.pack(MAGIC, crc32(zeroed), mtime, len(data), load, ep, dcrc,
                    ih_os, arch, typ, comp, name) + data


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("bootscr")
    ap.add_argument("--arg", default="mem=256M")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    blob = open(args.bootscr, "rb").read()
    meta, script = parse(blob)
    print(f"# parsed OK: {len(script)} bytes of script, both CRCs verified")

    lines = script.decode("utf-8", "surrogateescape").splitlines(keepends=True)
    hits = [i for i, l in enumerate(lines)
            if "setenv bootargs" in l and not l.lstrip().startswith("#")]
    if not hits:
        sys.exit("error: no 'setenv bootargs' line found")
    changed = 0
    for i in hits:
        if args.arg in lines[i]:
            print(f"# line {i + 1} already has {args.arg}; leaving it")
            continue
        # Inside the closing quote if there is one, else at end of line.
        body = lines[i].rstrip("\n")
        if body.rstrip().endswith(("'", '"')):
            stripped = body.rstrip()
            q = stripped[-1]
            body = stripped[:-1] + " " + args.arg + q
        else:
            body = body + " " + args.arg
        print(f"# line {i + 1}:\n#   - {lines[i].rstrip()}\n#   + {body}")
        lines[i] = body + "\n"
        changed += 1

    if not changed:
        print("# nothing to do")
        return 0
    if args.dry_run:
        print("# dry run: not writing")
        return 0

    out = build(meta, "".join(lines).encode("utf-8", "surrogateescape"))
    meta2, script2 = parse(out)          # round-trip our own output
    assert args.arg.encode() in script2

    backup = args.bootscr + ".orig"
    if not os.path.exists(backup):
        open(backup, "wb").write(blob)
        print(f"# backup: {backup}")
    tmp = args.bootscr + ".new"
    open(tmp, "wb").write(out)
    os.replace(tmp, args.bootscr)
    print(f"# wrote {args.bootscr} ({len(out)} bytes); power-cycle and check "
          f"/proc/cmdline")
    return 0


if __name__ == "__main__":
    sys.exit(main())
