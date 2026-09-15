#!/usr/bin/env python3
"""Can a non-secure PL master reach the DDR carve-out?

    sudo python3 probe_tz.py

ahblite_axi_bridge is built with C_M_AXI_NON_SECURE=1, so every read it issues
on HP0 carries ARPROT[1]=1.  Zynq-7000 gates non-secure DDR access per 64 MB
segment through SLCR.TZ_DDR_RAM: a zero bit means that segment answers secure
masters only, and a non-secure access to it returns DECERR.

That failure has a very specific shape, and it is the one on the bench: the PS
itself reads and writes the carve-out perfectly (the Cortex-A9 runs secure, and
load+verify passes), while the PL gets an error back after a handful of cycles
-- long enough to have crossed into the PS, far short of the bridge's timeout.

Read-only.  Writing SLCR needs an unlock and is not something to do casually
from a diagnostic.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from amoeba.mmio import Mmio                            # noqa: E402
from amoeba import regs as R                            # noqa: E402

SLCR_BASE = 0xF800_0000
TZ_DDR_RAM = 0x430
SLCR_LOCKSTA = 0x00C
DDR_SEG = 64 << 20          # one TZ_DDR_RAM bit per 64 MiB


def main() -> int:
    with Mmio(SLCR_BASE, 0x1000) as slcr:
        tz = slcr.read(TZ_DDR_RAM)
        lock = slcr.read(SLCR_LOCKSTA)

    print(f"# SLCR.TZ_DDR_RAM = 0x{tz:08x}   (LOCKSTA={lock})")
    print("#   one bit per 64 MiB segment; 1 = non-secure masters allowed")

    base, size = R.DDR_CARVEOUT_BASE, R.DDR_CARVEOUT_SIZE
    first, last = base // DDR_SEG, (base + size - 1) // DDR_SEG
    print(f"# carve-out 0x{base:08x}..0x{base + size - 1:08x} "
          f"= segments {first}..{last}")

    blocked = [i for i in range(first, last + 1) if not (tz >> i) & 1]
    for i in range(first, last + 1):
        ok = (tz >> i) & 1
        print(f"#   seg {i:2d}  0x{i * DDR_SEG:08x}  "
              f"{'non-secure OK' if ok else 'SECURE ONLY  <-- blocks the PL'}")

    print()
    if blocked:
        print(f"VERDICT: segments {blocked} refuse non-secure masters.")
        print("  The bridge issues non-secure reads (C_M_AXI_NON_SECURE=1), so")
        print("  HP0 answers DECERR -- which is exactly the error-after-a-few-")
        print("  cycles seen on the AHB.  Two ways out:")
        print("    - rebuild the bridge with C_M_AXI_NON_SECURE=0, or")
        print("    - open these segments in TZ_DDR_RAM at boot (u-boot/FSBL).")
    else:
        print("VERDICT: every carve-out segment already allows non-secure")
        print("  access, so TrustZone is NOT what is rejecting the reads.")
        print("  Look at the protocol converter and the AXI address instead.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
