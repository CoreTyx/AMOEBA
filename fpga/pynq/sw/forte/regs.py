"""fbu_top's register map.  The source of truth is fpga/bringup/rtl/fbu_pkg.sv;
check_regs_forte.py fails when the two disagree.  Fields are packed by name
through `pack`, never by hand-built shifts."""

CTL_BASE = 0x43C0_0000
CTL_SPAN = 0x1000
MEM_BASE = 0x4400_0000
MEM_SPAN = 0x10_0000
# MEM_AXI builds: EXT_MEM (0x8000_0000..0x8FFF_FFFF) is this carve-out of PS
# DDR, which the PS kernel leaves alone (mem=256M).  CAPS bit 4 says which.
DDR_CARVEOUT = 0x1000_0000
DDR_SPAN = 0x1000_0000
CAPS_MEM_AXI = 1 << 4

FBU_ID = 0x4642_5530
FBU_VERSION = 0x0001_0000

REG_ID = 0x000
REG_VERSION = 0x004
REG_CAPS = 0x008
REG_SCRATCH = 0x00C
REG_SOFT_RESET = 0x010
REG_PARTIAL_WRITES = 0x014

REG_PIN_CTRL = 0x100
REG_PIN_IN = 0x104
REG_RST_PULSE = 0x108
REG_RST_COUNT = 0x10C
REG_BOOTGATE = 0x120
REG_BOOTGATE_STAT = 0x124
REG_BOOTGATE_HDR = 0x128
REG_BOOTGATE_PASSES = 0x12C
REG_LINK_CYC_LO = 0x170
REG_LINK_CYC_HI = 0x174
REG_CYC_TOTAL_LO = 0x178
REG_CYC_TOTAL_HI = 0x17C

REG_FI_CTRL = 0x150
REG_FI_ARG0 = 0x154
REG_FI_ARG1 = 0x158
REG_FI_SEED = 0x15C
REG_FI_HIGH_CYC_LO = 0x160
REG_FI_HIGH_CYC_HI = 0x164
REG_FI_EDGES = 0x168
REG_FI_LATENCY = 0x16C
REG_FI_PHASE_OFS = 0x180
REG_FI_PHASE_NOW = 0x184
REG_FI_EVENTS = 0x188
REG_FI_PHASE_MASK = 0x1C0

REG_LINK_CFG = 0x200
REG_LINK_WDOG = 0x204
REG_PRNG_INIT_LO = 0x208
REG_PRNG_INIT_HI = 0x20C
REG_PRNG_LOAD = 0x210
REG_MEM_BASE = 0x214
REG_MEM_LIMIT = 0x218
REG_RESET_VEC = 0x21C
REG_LINK_ERR = 0x220
REG_LINK_ERR_COUNT = 0x224
REG_FIRST_ERR = 0x228
REG_FIRST_ERR_CYC_LO = 0x22C
REG_FIRST_ERR_CYC_HI = 0x230
REG_LINK_RD = 0x234
REG_LINK_WR = 0x238

REG_MEM_STAT = 0x240
REG_MEM_ERR_ADDR = 0x244
REG_MEM_READS = 0x248
REG_MEM_WRITES = 0x24C
REG_MEM_DROPPED = 0x250
REG_MEM_LAT_MAX = 0x254
REG_MEM_LAT_SUM_LO = 0x258
REG_MEM_LAT_SUM_HI = 0x25C

REG_TOHOST_ADDR = 0x280
REG_TOHOST_STAT = 0x284
REG_TOHOST_VAL_LO = 0x288
REG_TOHOST_VAL_HI = 0x28C
REG_TOHOST_CYC_LO = 0x290
REG_TOHOST_CYC_HI = 0x294

REG_TRACE_CTRL = 0x300
REG_TRACE_LEVEL = 0x304
REG_TRACE_WRITTEN = 0x308
REG_TRACE_DROPPED = 0x30C
REG_TRACE_POP = 0x310
REG_TRACE_STAT = 0x314
REG_TRACE_CLEAR = 0x318
REG_TRACE_HEAD = 0x340

REG_UART_RX_BIT = 0x400
REG_UART_TX_PERIOD = 0x404
REG_UART_TX_GAP = 0x408
REG_UART_RX_DATA = 0x40C
REG_UART_RX_POP = 0x410
REG_UART_TX_PUSH = 0x414
REG_UART_STAT = 0x418
REG_UART_RX_LEVEL = 0x41C
REG_UART_TX_LEVEL = 0x420
REG_UART_N_RX = 0x424
REG_UART_N_TX = 0x428
REG_UART_N_FERR = 0x42C
REG_UART_MATCH_LEN = 0x430
REG_UART_MATCH_CTRL = 0x434
REG_UART_CLEAR = 0x438
REG_UART_MATCH0 = 0x440
REG_UART_MATCH1 = 0x460

REG_SCAN_CTRL = 0x600
REG_SCAN_LEN = 0x604
REG_SCAN_ADDR = 0x608
REG_SCAN_PATTERN = 0x60C
REG_SCAN_CAPTURE = 0x610
SCAN_DEPTH = 1024

REG_STAT_LAST = 0x500
REG_STAT_MIN = 0x504
REG_STAT_MAX = 0x508
REG_STAT_EDGES = 0x50C
REG_STAT_CLASS = 0x510
REG_STAT_GLITCH = 0x514
REG_CLKOUT_EDGES = 0x518
REG_CLKOUT_WINDOW = 0x51C
STATUS_CLASSES = ["none", "stalled", "active", "quiet"]

REG_TRIG = 0x580

# (lsb, width) of each field, by register
FIELDS = {
    REG_PIN_CTRL: {"release": (0, 1), "fault_inject": (1, 1), "test_mode": (2, 1),
                   "scan_en": (3, 1), "irq": (4, 2), "rx_force_en": (6, 1), "rx_force_val": (7, 1)},
    REG_BOOTGATE: {"enable": (0, 1), "selftest": (1, 1), "retries": (4, 4), "timeout": (16, 16)},
    REG_LINK_CFG: {"det": (0, 1), "gap_pct": (1, 7), "rd_lat": (16, 16)},
    REG_LINK_WDOG: {"wdog": (0, 16), "mutate": (16, 2)},
    REG_TRACE_CTRL: {"enable": (0, 1), "stop_on_error": (1, 1)},
    REG_UART_TX_PUSH: {"data": (0, 8), "kind": (8, 2)},
    REG_UART_MATCH_LEN: {"len0": (0, 8), "len1": (8, 8)},
    REG_FI_CTRL: {"mode": (0, 4), "start_on_release": (4, 1), "start": (8, 1), "stop": (9, 1),
                  "clear_counts": (10, 1), "running": (16, 1)},
    REG_TRIG: {"source": (0, 4), "action": (4, 4), "repeat": (8, 1), "line": (9, 1),
               "arm": (10, 1), "disarm": (11, 1), "armed": (12, 1), "length": (16, 16)},
}

FI_STATIC, FI_SQUARE, FI_RANDOM, FI_PULSE, FI_BURST, FI_PHASE, FI_SINGLE = range(7)
FI_GROUPS = ["alu0", "alu1", "cmp", "mul", "div", "rf", "pipe", "icache", "dcache"]
# chip fault-counter phase of each injection site (fbu_fi_gen.sv)
FI_SITE_PHASES = {
    "alu0": [0x1FE, 0x1EE, 0x1DE], "alu1": [0x1BE, 0x1AE, 0x19E], "cmp": [0x1CE, 0x18E],
    "mul": [0x17E], "div": [0x15E], "rf": [0x1FF], "pipe": [0x1FF], "icache": [0x13E], "dcache": [0x11E],
}

TRIG_SRC_CYCLE, TRIG_SRC_MATCH0, TRIG_SRC_MATCH1, TRIG_SRC_STATE, TRIG_SRC_RANDOM, TRIG_SRC_ERROR = range(1, 7)
TRIG_RESET, TRIG_IRQ_SET, TRIG_IRQ_CLEAR, TRIG_IRQ_PULSE, TRIG_FAULT = range(1, 6)
LINK_STATES = ["idle", "header", "write_data", "read_turnaround", "read_latency", "read_data", "read_release"]

UART_TX_BYTE, UART_TX_BAD_STOP, UART_TX_BREAK, UART_TX_IDLE = range(4)

LINK_ERRORS = {
    1: "LE_REQ_DIR0", 2: "LE_CONTENTION", 3: "LE_IO_MISMATCH", 4: "LE_WATCHDOG",
    5: "LE_GUARD", 6: "LE_HDR_REQ_DROP", 7: "LE_HDR_WR_CHG", 8: "LE_ADDR_RANGE",
    9: "LE_ADDR_ALIGN", 10: "LE_FIRST_XACT", 11: "LE_WD_REQ", 12: "LE_WD_DIR",
    13: "LE_WD_WR", 14: "LE_RTA_REQ", 15: "LE_RLAT_DIR", 16: "LE_RD_DIR",
    17: "LE_RD_REQ", 18: "LE_REL_DIR", 21: "LE_LAT_OVERRUN", 22: "LE_REQ_OVERFLOW",
    23: "LE_MEM_ERR",
}

# fbu_mem_bram port B: window w at w << 18; registers at 0xC0000
MEM_WINDOWS = [(0x8000_0000, 128 * 1024), (0x8080_0000, 4 * 1024), (0x8FEF_C000, 16 * 1024)]
MEM_REG_WINDOW_BASE = 0xC0000
MEM_REG_OUT_OF_WINDOW_WRITES = 0xC000C
MEM_REG_OUT_OF_WINDOW_LAST = 0xC0010


def pack(reg: int, **values: int) -> int:
    word = 0
    for name, value in values.items():
        lsb, width = FIELDS[reg][name]
        if value < 0 or value >= 1 << width:
            raise ValueError(f"{name}={value} does not fit {width} bits")
        word |= value << lsb
    return word


def unpack(reg: int, word: int, name: str) -> int:
    lsb, width = FIELDS[reg][name]
    return (word >> lsb) & ((1 << width) - 1)
