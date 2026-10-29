#!/usr/bin/env python3
"""Does one Python register write reach the PL as one AXI write?

Writes UART_TX_PUSH (an idle span of 1 bit: harmless, the chip is held in
reset) once with each store method and reads UART_N_TX, which counts entries
the PL received.  1 per write is right; 2 means the store was split into two
halfword writes, each of which the PL acted on.  Needs the forte bitstream
loaded (run_cmd.py does that)."""

import ctypes
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from forte import regs as R  # noqa: E402
from amoeba.mmio import Mmio  # noqa: E402

ctl = Mmio(R.CTL_BASE, R.CTL_SPAN)
assert ctl.read(R.REG_ID) == R.FBU_ID, "forte bitstream not loaded"
ctl.write(R.REG_PIN_CTRL, 0)
entry = R.pack(R.REG_UART_TX_PUSH, kind=R.UART_TX_IDLE, data=1)


def count_after(store):
    before = ctl.read(R.REG_UART_N_TX)
    store()
    return ctl.read(R.REG_UART_N_TX) - before


word = ctypes.c_uint32.from_buffer(ctl._map, ctl._delta + R.REG_UART_TX_PUSH)


def ctypes_store():
    word.value = entry


print(f"struct.pack_into (Mmio.write): {count_after(lambda: ctl.write(R.REG_UART_TX_PUSH, entry))} PL writes")
print(f"ctypes c_uint32 store:         {count_after(ctypes_store)} PL writes")
