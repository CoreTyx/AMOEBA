#!/usr/bin/env python3
"""Is the core executing?  Ask memory, not the retire counter.

The retire counter says 0 while the bus capture shows a taken branch and a
gp-relative address computed correctly -- one of the two is lying, and this
settles it without touching the RTL.

_start ends in a loop that zeroes .bss:

    8000002e: sd zero,0(t0)      t0 = _bss_start, stepping by 8 to _bss_end

So poison .bss from the PS after the load, let the core run, and read it back.
Bytes that came back zero are bytes the CORE wrote -- the PS never writes a
zero there in this script, and load() ran before the poison.  The count of
them is how far the loop got before it stopped, which is the thing the bus
capture cannot show (64 entries covers 64 cycles).

Poll order matters: retired is read WITHOUT halting, because amoeba_retire's
tap_rst includes core_reset and a halt would zero the number being measured.
"""

import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from amoeba import Amoeba, AmoebaError, image as _image, regs as R  # noqa: E402

POISON = 0xA5


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True)
    ap.add_argument("--bitstream")
    ap.add_argument("--fclk", type=float, default=25.0)
    ap.add_argument("--seconds", type=float, default=3.0)
    ap.add_argument("--poll", type=float, default=0.25)
    args = ap.parse_args()

    img = _image.load(args.image)
    try:
        bss_start = img.symbols["_bss_start"]
        bss_end = img.symbols["_bss_end"]
    except KeyError:
        print("error: image has no _bss_start/_bss_end", file=sys.stderr)
        return 2

    dev = Amoeba(bitstream=args.bitstream,
                 fclk_mhz=args.fclk if args.fclk > 0 else None)
    try:
        print(f"# {dev.describe()}")
        if dev.is_bram:
            print("error: this probe is for the AXI/DDR backend", file=sys.stderr)
            return 2

        off = bss_start - R.EXT_MEM_BASE
        n = bss_end - bss_start
        print(f"# .bss 0x{bss_start:08x}..0x{bss_end:08x} "
              f"({n} bytes) poisoned with 0x{POISON:02x}")

        def _poison(d):
            # After clear_monitors(), before start(): the last moment the PS
            # owns this memory alone.
            #
            # write_bytes, not fill: fill() on the DDR mapping is a memcpy of
            # a single repeated byte and only accepts 0x00 or 0xff.  0xa5 is
            # worth the chunked loop -- it cannot be confused with erased
            # memory, with a zero the core wrote, or with a half-written word.
            chunk = 1 << 16
            pat = bytes([POISON])
            done = 0
            while done < n:
                k = min(chunk, n - done)
                d.mem.write_bytes(off + done, pat * k)
                done += k
            back = d.mem.read_bytes(off, 64)
            if back != pat * 64:
                raise AmoebaError("poison did not stick -- the PS view of the "
                                  "carve-out is not what we think it is")
            tail = d.mem.read_bytes(off + n - 64, 64)
            if tail != pat * 64:
                raise AmoebaError("poison did not reach the end of .bss")

        dev.run(img, verify=True, on_armed=_poison)

        # ---- watch it live.  No halt anywhere in this loop. ----------------
        print(f"# {'t':>6} {'cycles':>12} {'retired':>10} {'traps':>6} "
              f"{'xact':>6} {'beat':>6} {'err':>5}  zeroed")
        t0 = time.monotonic()
        deadline = t0 + args.seconds
        while True:
            now = time.monotonic()
            cyc = dev.cycles
            ret = dev.retired
            zeroed = _leading_zeros(dev.mem.read_bytes(off, min(n, 4096)))
            print(f"# {now - t0:6.2f} {cyc:12d} {ret:10d} {dev.traps:6d} "
                  f"{dev.ctl.read(R.R_BUS_XACT):6d} "
                  f"{dev.ctl.read(R.R_BUS_BEAT):6d} "
                  f"{dev.ctl.read(R.R_BUS_ERR):5d}  {zeroed}")
            if now >= deadline:
                break
            time.sleep(args.poll)

        # ---- the verdict --------------------------------------------------
        blob = dev.mem.read_bytes(off, n)
        z = _leading_zeros(blob)
        untouched = blob.count(POISON)
        print(f"#\n# .bss after the run: {z} leading zero bytes, "
              f"{untouched} of {n} still poisoned")
        if z == 0:
            print("# VERDICT: the core never wrote a single .bss word.  It is "
                  "NOT executing\n"
                  "#          the bss loop, and retired=0 is honest.")
        elif z >= n:
            print("# VERDICT: .bss fully zeroed -- _start COMPLETED and "
                  "jal main was taken.\n"
                  "#          retired=0 is a broken counter.")
        else:
            print(f"# VERDICT: the core zeroed {z} bytes and STOPPED at "
                  f"0x{bss_start + z:08x}.\n"
                  f"#          It is executing, so retired=0 is a broken "
                  f"counter; the wedge\n"
                  f"#          is at that address, {z // 64} cache lines in.")
        return 0
    finally:
        dev.close()


def _leading_zeros(b: bytes) -> int:
    i = 0
    while i < len(b) and b[i] == 0:
        i += 1
    return i


if __name__ == "__main__":
    sys.exit(main())
