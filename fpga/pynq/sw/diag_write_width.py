#!/usr/bin/env python3
"""Does one Python register write reach the PL as one AXI write?

Writes UART_TX_PUSH (an idle span of 1 bit: harmless, the chip is held in
reset) once with a raw struct.pack_into store and once with a 32-bit ctypes
store (what Mmio.write uses), and reports what the PL saw: entries queued
(UART_N_TX) and writes narrower than a word (PARTIAL_WRITES), which fbu_top
ignores for registers with a side effect.  Right: pack_into 0 queued and 2
partial on this Linux; ctypes 1 queued, 0 partial.  Needs the forte bitstream
loaded (run_cmd.py does that)."""

import ctypes
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from forte import regs as R  # noqa: E402
from amoeba.mmio import Mmio  # noqa: E402

ctl = Mmio(R.CTL_BASE, R.CTL_SPAN)
assert ctl.read(R.REG_ID) == R.FBU_ID, "forte bitstream not loaded"
ctl.write(R.REG_PIN_CTRL, 0)
entry = R.pack(R.REG_UART_TX_PUSH, kind=R.UART_TX_IDLE, data=1)
where = ctl._delta + R.REG_UART_TX_PUSH


def seen_by_pl(store):
    queued = ctl.read(R.REG_UART_N_TX)
    partial = ctl.read(R.REG_PARTIAL_WRITES)
    store()
    return ctl.read(R.REG_UART_N_TX) - queued, ctl.read(R.REG_PARTIAL_WRITES) - partial


def pack_into_store():
    struct.pack_into("<I", ctl._map, where, entry)


def ctypes_store():
    ctypes.c_uint32.from_buffer(ctl._map, where).value = entry


for name, store in (("struct.pack_into", pack_into_store), ("ctypes c_uint32 ", ctypes_store)):
    queued, partial = seen_by_pl(store)
    print(f"{name}: {queued} entries queued, {partial} partial writes")
