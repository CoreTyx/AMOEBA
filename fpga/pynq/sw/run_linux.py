#!/usr/bin/env python3
"""Boot the testcode/linux image on the soft core and stream the console.

  sudo python3 run_linux.py --bitstream ../amoeba.bit --dir ../linux --timeout 600

Expects --dir to hold boot_shim.bin and fw_payload.bin from
`make -C testcode/linux CONFIG=baremetal_linux TIMEBASE_HZ=25000000`
(TIMEBASE_HZ MUST be the real FCLK0: MTIME ticks off HCLK, and a kernel whose
declared timebase is 4x the true rate runs every sleep and timeout 4x slow --
functionally "working" and useless.  The FreeRTOS soak mode exists because of
exactly this class of bug.)

Differences from run_freertos.py, each load-bearing:

- TWO blobs, not one: the shim at the reset vector and fw_payload (OpenSBI +
  embedded DT + kernel + initramfs) at +2 MB, per testcode/linux/README.md.
- tohost is IGNORED.  The AXI bus monitor watches 0x8080_0000, and that
  address is INSIDE fw_payload's span -- the kernel writes it as ordinary
  memory, so tohost_valid latching means nothing here.  The run ends on
  timeout, a pass pattern, or a fail pattern, never on tohost.
- Milestones from testcode/linux/README.md are stamped with wall time and PL
  cycles as they fly by, so a stall names the phase it stalled in.
"""

import argparse
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from amoeba import Amoeba, AmoebaError, regs as R  # noqa: E402

SHIM_ADDR    = 0x8000_0000
PAYLOAD_ADDR = 0x8020_0000

MILESTONES = [
    ("M0 firmware",   re.compile(rb"OpenSBI v1\.")),
    ("M1 kernel",     re.compile(rb"Linux version 6\.6")),
    ("M2 console",    re.compile(rb"printk: bootconsole")),
    ("M3 mmu",        re.compile(rb"Initmem setup node 0")),
    ("M4 init done",  re.compile(rb"Freeing unused kernel image")),
    ("M5 userspace",  re.compile(rb"AMOEBA_LINUX_BOOT_OK")),
]
FAIL = re.compile(rb"Kernel panic|Unable to handle kernel|Oops:|SBI panic")


def _load_blob(dev, path, addr, verify):
    blob = open(path, "rb").read()
    off = addr - R.EXT_MEM_BASE
    t0 = time.monotonic()
    dev.mem.write_bytes(off, blob)
    if verify:
        back = dev.mem.read_bytes(off, len(blob))
        if back != blob:
            bad = next(i for i in range(len(blob)) if back[i] != blob[i])
            raise AmoebaError(f"{os.path.basename(path)}: verify failed at "
                              f"0x{addr + bad:08x}")
    print(f"# {os.path.basename(path)}: {len(blob)} bytes at 0x{addr:08x} "
          f"({time.monotonic() - t0:.1f} s{', verified' if verify else ''})")
    return len(blob)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True,
                    help="directory holding boot_shim.bin and fw_payload.bin")
    ap.add_argument("--bitstream")
    ap.add_argument("--fclk", type=float, default=25.0)
    ap.add_argument("--timeout", type=float, default=600.0)
    ap.add_argument("--no-verify", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    shim = os.path.join(args.dir, "boot_shim.bin")
    payload = os.path.join(args.dir, "fw_payload.bin")
    for p in (shim, payload):
        if not os.path.exists(p):
            print(f"error: {p} not found", file=sys.stderr)
            return 2

    dev = Amoeba(bitstream=args.bitstream,
                 fclk_mhz=args.fclk if args.fclk > 0 else None)
    try:
        print(f"# {dev.describe()}")
        if dev.is_bram:
            print("error: the Linux image needs the AXI/DDR backend",
                  file=sys.stderr)
            return 2
        got = dev.check_fclk(args.fclk)
        print(f"# fabric clock verified: {got / 1e6:.3f} MHz")
        if abs(got - 25e6) > 25e4:
            print("# WARNING: image was built TIMEBASE_HZ=25000000; the "
                  "kernel's clock will be wrong", file=sys.stderr)

        dev.halt()
        end = _load_blob(dev, shim, SHIM_ADDR, not args.no_verify)
        _load_blob(dev, payload, PAYLOAD_ADDR, not args.no_verify)
        dev.clear_monitors()
        dev.start()
        print(f"# core released; streaming console for up to "
              f"{args.timeout:.0f} s (tohost is ignored on purpose: "
              f"0x80800000 lies inside the image)")

        t0 = time.monotonic()
        c0 = dev.cycles
        tail = b""
        hit = set()
        rc = 1
        try:
            for chunk in dev.stream_console(args.timeout, until_tohost=False,
                                            poll=0.001):
                if not args.quiet:
                    sys.stdout.buffer.write(chunk)
                    sys.stdout.flush()
                tail = (tail + chunk)[-4096:]
                for name, pat in MILESTONES:
                    if name not in hit and pat.search(tail):
                        hit.add(name)
                        print(f"\n# --- {name} at {time.monotonic() - t0:7.2f} s, "
                              f"{dev.cycles - c0} cycles ---", file=sys.stderr)
                if "M5 userspace" in hit:
                    rc = 0
                    break
                if FAIL.search(tail):
                    print("\n# FAIL pattern seen", file=sys.stderr)
                    rc = 3
                    break
        except KeyboardInterrupt:
            print("\n# interrupted", file=sys.stderr)

        wall = time.monotonic() - t0
        print(f"# ran {wall:.1f} s, {dev.cycles - c0} cycles, "
              f"{dev.retired} retired, {dev.traps} traps", file=sys.stderr)
        if dev.uart_overflow:
            print("# WARNING: console FIFO overflowed -- log has gaps",
                  file=sys.stderr)
        missed = [n for n, _ in MILESTONES if n not in hit]
        if missed:
            print(f"# milestones not reached: {', '.join(missed)}",
                  file=sys.stderr)
        return rc
    finally:
        dev.close()


if __name__ == "__main__":
    sys.exit(main())
