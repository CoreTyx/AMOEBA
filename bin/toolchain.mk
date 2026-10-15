# The RISC-V cross toolchain, for every Makefile that builds test code.
#
#   include <repo>/bin/toolchain.mk
#
# Sets CROSS_COMPILE to the absolute tool prefix bin/toolchain.py picks (or to
# the CROSS_COMPILE given, resolved), and exports LD_LIBRARY_PATH when that
# compiler needs a library directory of its own to run.

TOOLCHAIN_PY := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))toolchain.py

# Evaluated once: toolchain.py runs the compiler to check it.
TOOLCHAIN := $(shell CROSS_COMPILE='$(CROSS_COMPILE)' python3 $(TOOLCHAIN_PY) --make)
ifeq ($(strip $(TOOLCHAIN)),)
$(error no RISC-V toolchain: see the bin/toolchain.py error above)
endif
override CROSS_COMPILE := $(word 1,$(TOOLCHAIN))
TOOLCHAIN_LIBDIR       := $(word 2,$(TOOLCHAIN))
ifneq ($(TOOLCHAIN_LIBDIR),)
export LD_LIBRARY_PATH := $(TOOLCHAIN_LIBDIR):$(LD_LIBRARY_PATH)
endif
