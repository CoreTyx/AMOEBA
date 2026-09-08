"""Register map for the AMOEBA PL design.

These constants have NO compile-time link to the hardware.  The offsets come
from ``localparam logic [7:0] R_*`` in ``rtl/amoeba_ctl.sv`` and the base
addresses from ``amoeba_assign`` calls in ``tcl/bd_pynq.tcl``; nothing but
diligence keeps them in step, and a silent mismatch reads as a dead board.

``check_regs.py`` parses both sources and asserts they agree.  Run it whenever
the RTL changes.
"""

# ---- base addresses, from tcl/bd_pynq.tcl -----------------------------------
CTL_BASE = 0x43C0_0000
CTL_SIZE = 0x1000
MEM_BASE = 0x4400_0000          # image window; size comes from CAPS.mem_kb
DMA_BASE = 0x4040_0000
DMA_SIZE = 0x1_0000

# The DDR carve-out, from opt(ddr_carveout)/opt(ddr_size) in tcl/bd_pynq.tcl.
# In an AXI build this is the core's memory: the bridge subtracts EXT_MEM_BASE
# from the core's address and adds this, so core 0x8000_0000 is PS 0x1000_0000.
# It is also the trace DMA's target.
#
# The PS must be kept out of this range.  Nothing in the PL enforces it -- the
# clamp in bd_pynq.tcl stops the CORE from reaching PS memory, not the other
# way round -- so if Linux on the A9 is left free to allocate here, the kernel
# and the soft core will quietly share pages.  Pass a matching `mem=` bootarg
# or reserved-memory node in the PS devicetree on the SD card.
DDR_CARVEOUT_BASE = 0x1000_0000
DDR_CARVEOUT_SIZE = 0x1000_0000         # 256 MiB

# ---- the core's own view of memory, from pkg/config_baremetal_linux.vh ------
# EXT_MEM_BASE is 0x80000000 in every configuration in this project.  The PS
# needs it to turn a program's load address into an offset in the image window.
EXT_MEM_BASE = 0x8000_0000

# ---- control registers, offsets from CTL_BASE -------------------------------
R_ID = 0x00
R_VERSION = 0x04
R_CAPS = 0x08
R_CTRL = 0x0C
R_STATUS = 0x10
R_UART_DATA = 0x14
R_UART_LEVEL = 0x18
R_CYCLES_LO = 0x20
R_CYCLES_HI = 0x24
R_RETIRED_LO = 0x28
R_RETIRED_HI = 0x2C
R_TRAPS = 0x30
R_TOHOST_LO = 0x34
R_TOHOST_HI = 0x38
R_TRACE_MODE = 0x40
R_TRIG_START_LO = 0x44
R_TRIG_START_HI = 0x48
R_TRIG_COUNT = 0x4C
R_TRIG_PC_LO = 0x50
R_TRIG_PC_HI = 0x54
R_TRACE_STAT = 0x58

# ---- external AHB probe, from rtl/amoeba_bus_probe.sv -----------------------
# The only window onto the bus between the core and its memory.  Everything
# else in this map describes the core; when the core stalls on a bus that
# never answers, these are what tell the two apart.
R_BUS_STATE = 0x60
R_BUS_XACT = 0x64
R_BUS_BEAT = 0x68
R_BUS_ERR = 0x6C
R_BUS_STALL = 0x70
R_BUS_ADDR = 0x74
R_BUS_XADDR = 0x78
R_BUS_WAIT = 0x7C
R_BUS_ERRWAIT = 0x80
R_BUS_ERRXACT = 0x84
R_BUS_PRESTATE = 0x88
R_BUS_CAPSEL = 0x8C
R_BUS_CAPDAT = 0x90
R_BUS_CAPSTAT = 0x94
R_BUS_RSTXACT = 0x98
R_BUS_CAPRDAT = 0x9C

CAP_VALID = 1 << 31          # amoeba_bus_probe stamps this on every written entry
CAP_CORE_RESET = 1 << 30     # was the core held on THAT cycle -- see decode_cap

CAP_DEPTH = 64

ID_MAGIC = 0x414D_4F42          # "AMOB"

# ---- CTRL bits --------------------------------------------------------------
CTRL_CORE_RESET = 1 << 0
CTRL_MON_CLEAR = 1 << 1
CTRL_TRACE_CLEAR = 1 << 2

# ---- STATUS bits ------------------------------------------------------------
ST_CORE_RESET = 1 << 0
ST_UART_VALID = 1 << 1
ST_UART_OVERFLOW = 1 << 2
ST_TOHOST_VALID = 1 << 3
ST_TRACE_OVERFLOW = 1 << 4
ST_TRACE_STALLING = 1 << 5

# ---- UART_DATA --------------------------------------------------------------
UART_VALID = 1 << 8
UART_BYTE = 0xFF

# ---- trace modes, from rtl/amoeba_trace.sv ----------------------------------
TRACE_OFF = 0
TRACE_ALL = 1
TRACE_WINDOW = 2
TRACE_PC_TRIG = 3


# ---- BUS_STATE bit fields ---------------------------------------------------
BUS_HSEL = 1 << 2
BUS_HTRANS = 0x3 << 3
BUS_HWRITE = 1 << 5
BUS_HBURST = 0x7 << 6
BUS_HSIZE = 0x7 << 9
BUS_HREADY = 1 << 12
BUS_HRESP = 1 << 13
BUS_SEEN_FIRST = 1 << 14
BUS_CORE_RESET = 1 << 15

HTRANS_NAMES = {0: "IDLE", 1: "BUSY", 2: "NONSEQ", 3: "SEQ"}


def decode_bus_state(v: int) -> str:
    """Render BUS_STATE as the sentence you would otherwise have to assemble
    by hand from a hex word at three in the morning."""
    htrans = (v >> 3) & 0x3
    return (
        f"HSEL={1 if v & BUS_HSEL else 0} "
        f"HTRANS={HTRANS_NAMES[htrans]} "
        f"HWRITE={1 if v & BUS_HWRITE else 0} "
        f"HBURST={(v >> 6) & 0x7} "
        f"HSIZE={(v >> 9) & 0x7} "
        f"HREADY={1 if v & BUS_HREADY else 0} "
        f"HRESP={1 if v & BUS_HRESP else 0} "
        f"core_reset={1 if v & BUS_CORE_RESET else 0}"
    )


def decode_cap(v: int) -> str:
    """One captured AHB cycle, as laid out by amoeba_bus_probe's cap_word."""
    if not (v & CAP_VALID):
        return "<never written>"
    return (
        f"HSEL={(v >> 9) & 1} "
        f"HTRANS={HTRANS_NAMES[(v >> 6) & 0x3]:6s} "
        f"HWRITE={(v >> 8) & 1} "
        f"HSIZE={(v >> 3) & 0x7} "
        f"HBURST={v & 0x7} "
        f"HREADY={(v >> 10) & 1} "
        f"HRESP={(v >> 11) & 1} "
        f"addr=...{(v >> 12) & 0xFFF:03x} "
        f"rst={(v >> 30) & 1}"
    )


def caps_mem_kb(caps: int) -> int:
    """Image memory size in KiB, CAPS[31:16].

    MEANINGFUL ONLY IN A BRAM BUILD.  The field carries the MEM_KB parameter
    verbatim, and an AXI build passes it through unchanged even though the
    memory is then the DDR carve-out -- 256 MiB, which does not fit in 16 bits
    of KiB anyway.  Ask Amoeba.mem_bytes instead of reading this directly.
    """
    return (caps >> 16) & 0xFFFF


def caps_has_trace(caps: int) -> bool:
    """CAPS[8]."""
    return bool(caps & (1 << 8))


def caps_is_bram(caps: int) -> bool:
    """CAPS[0]: 1 = block RAM backend, 0 = AXI/DDR."""
    return bool(caps & 1)


def tohost_addr(mem_kb: int, is_bram: bool) -> int:
    """The address the bus monitor is watching for HTIF writes.

    Must match TOHOST_ADDR in rtl/amoeba_pynq_top.sv and the PROVIDE(tohost)
    in the program's linker script.  In a BRAM build the memory is small and
    amoeba_mem_bram truncates rather than faulting, so an address above the
    array aliases back into it -- the usual 0x80800000 against a 128 KiB array
    lands on offset 0, the reset vector.  Hence the top page of real memory.
    """
    if is_bram:
        return EXT_MEM_BASE + mem_kb * 1024 - 4096
    return 0x8080_0000
