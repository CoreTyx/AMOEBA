#!/usr/bin/python3

# The one RISC-V cross toolchain every piece of test code is built with.
#
# Baremetal, ISA-level, ECC and FreeRTOS tests and the Linux boot image all take
# their compiler from the prefix this prints, so there is a single toolchain to
# reason about and a single one to patch.  It is kernel.org's nolibc
# riscv64-linux build: a Linux-targeting compiler is the only kind that can link
# the kernel's VDSO, and with -ffreestanding -nostdlib it builds the bare-metal
# tests just as well.  It ships no C library, so test code cannot lean on newlib.
#
#   python3 bin/toolchain.py     print the tool prefix, fetching it on first use
#
# Set CROSS_COMPILE to build with something else -- a locally patched toolchain,
# or any host that is not x86-64 Linux.  It is passed through untouched.

import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

# Pinned by checksum so a regression can never be an upstream tarball quietly
# changing underneath us.
VERSION = "13.2.0"
SHA256  = "07c58f4551e636cbe8ba16707909e94ac262f45dc8fe28034011842bdc0c7417"
TARBALL = f"x86_64-gcc-{VERSION}-nolibc-riscv64-linux.tar.xz"
URL     = f"https://mirrors.edge.kernel.org/pub/tools/crosstool/files/bin/x86_64/{VERSION}/{TARBALL}"

ROOT    = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "toolchain")
INSTALL = os.path.join(ROOT, f"gcc-{VERSION}-nolibc")
PREFIX  = os.path.join(INSTALL, "riscv64-linux", "bin", "riscv64-linux-")

def fetch():
    os.makedirs(ROOT, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix=".fetch-", dir=ROOT)
    try:
        tarball = os.path.join(tmp, TARBALL)
        print(f"[INFO]  Fetching RISC-V toolchain gcc-{VERSION}-nolibc into {ROOT}", file=sys.stderr)
        if subprocess.run(["curl", "-fsSL", "-o", tarball, URL]).returncode != 0:
            sys.exit(f"[ERROR] Could not download {URL}")
        with open(tarball, "rb") as f:
            digest = hashlib.sha256(f.read()).hexdigest()
        if digest != SHA256:
            sys.exit(f"[ERROR] {TARBALL} has sha256 {digest}, expected {SHA256}")
        if subprocess.run(["tar", "-C", tmp, "-xf", tarball]).returncode != 0:
            sys.exit(f"[ERROR] Could not unpack {TARBALL}")
        # Renamed into place last, so an interrupted or concurrent fetch never
        # leaves a half-unpacked toolchain where the builds look for it.
        try:
            os.rename(os.path.join(tmp, os.path.basename(INSTALL)), INSTALL)
        except OSError:
            if not os.path.isfile(PREFIX + "gcc"):
                raise
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

def prefix():
    override = os.environ.get("CROSS_COMPILE")
    if override:
        return override
    if not os.path.isfile(PREFIX + "gcc"):
        fetch()
    return PREFIX

if __name__ == "__main__":
    print(prefix())
