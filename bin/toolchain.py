#!/usr/bin/python3

# The one RISC-V cross toolchain every piece of test code is built with.
#
# Baremetal, ISA-level, ECC and FreeRTOS tests and the Linux boot image all take
# their compiler from the prefix this prints, so there is a single compiler to
# reason about.  It is a riscv64 Linux-targeting
# gcc already installed on the host: a Linux-targeting compiler is the only kind
# that can link the kernel's VDSO, and with -ffreestanding -nostdlib it builds the
# bare-metal tests just as well.  Test code must not lean on its C library.
#
#   python3 bin/toolchain.py           print the tool prefix
#   python3 bin/toolchain.py --libdir  print a directory the compiler needs on
#                                      LD_LIBRARY_PATH, or nothing
#   python3 bin/toolchain.py --make    both, space-separated (bin/toolchain.mk)
#
# The compiler is the first of PREFIXES found on PATH, and must be gcc
# REQUIRED_VERSION.  On EWS, ece411.sh puts one on PATH; CI installs Ubuntu's
# gcc-14 cross compiler (.github/scripts/install_riscv_gcc.sh).
#
# Set CROSS_COMPILE to build with something else -- a rebuilt or patched gcc, say.
# It is used as given (resolved to an absolute path); a different version is only
# warned about.

import os
import shutil
import subprocess
import sys

REQUIRED_VERSION = "14.2.0"
PREFIXES = ["riscv64-unknown-linux-gnu-", "riscv64-linux-gnu-", "riscv64-linux-"]

def die(msg):
    sys.exit(f"[ERROR] toolchain.py: {msg}")

def warn(msg):
    print(f"[WARN]  toolchain.py: {msg}", file=sys.stderr)

def resolve(prefix):
    """Absolute prefix for a prefix that is a path or a bare name on PATH."""
    gcc = shutil.which(prefix + "gcc")
    if gcc is None:
        return None
    return os.path.join(os.path.dirname(os.path.abspath(gcc)), os.path.basename(prefix))

def env_with(libdir):
    env = dict(os.environ)
    if libdir:
        env["LD_LIBRARY_PATH"] = libdir + os.pathsep + env.get("LD_LIBRARY_PATH", "")
    return env

def compiles(prefix, libdir):
    """True if gcc runs cc1: --version alone does not load it."""
    r = subprocess.run([prefix + "gcc", "-x", "c", "-c", "-", "-o", os.devnull],
                       input=b"", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       env=env_with(libdir))
    return r.returncode == 0, r.stderr.decode(errors="replace").strip()

def check(prefix):
    """The extra library directory prefix needs, or "" if none."""
    ok, err = compiles(prefix, "")
    if ok:
        return ""
    # The EWS install's cc1 was linked against libmpfr.so.4, which RHEL 9 does
    # not ship; the install carries a copy in compat/ but does not put it on
    # LD_LIBRARY_PATH.
    compat = os.path.normpath(os.path.join(os.path.dirname(prefix), "..", "compat"))
    if os.path.isdir(compat) and compiles(prefix, compat)[0]:
        return compat
    die(f"{prefix}gcc does not run:\n{err}")

def version(prefix, libdir):
    r = subprocess.run([prefix + "gcc", "-dumpfullversion"], stdout=subprocess.PIPE,
                       env=env_with(libdir))
    return r.stdout.decode().strip()

def find():
    override = os.environ.get("CROSS_COMPILE")
    if override:
        prefix = resolve(override)
        if prefix is None:
            die(f"CROSS_COMPILE={override}: no {override}gcc")
        libdir = check(prefix)
        found = version(prefix, libdir)
        if found != REQUIRED_VERSION:
            warn(f"CROSS_COMPILE={override} is gcc {found}, not {REQUIRED_VERSION}")
        return prefix, libdir
    for candidate in PREFIXES:
        prefix = resolve(candidate)
        if prefix is None:
            continue
        libdir = check(prefix)
        found = version(prefix, libdir)
        if found != REQUIRED_VERSION:
            die(f"{prefix}gcc is gcc {found}; every tier builds with gcc "
                f"{REQUIRED_VERSION}.  Set CROSS_COMPILE to use it anyway.")
        return prefix, libdir
    die(f"no riscv64 Linux gcc {REQUIRED_VERSION} found (looked for "
        f"{', '.join(p + 'gcc' for p in PREFIXES)} on PATH).  Put one's bin "
        f"directory on PATH or set CROSS_COMPILE.")

if __name__ == "__main__":
    prefix, libdir = find()
    if sys.argv[1:] == ["--libdir"]:
        print(libdir)
    elif sys.argv[1:] == ["--make"]:
        print(prefix, libdir)
    else:
        print(prefix)
