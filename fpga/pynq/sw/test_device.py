#!/usr/bin/env python3
"""Offline tests for the driver.  No board, no /dev/mem, no root.

    python3 test_device.py

These exist because this driver has now broken twice in ways that only showed
up on hardware, after a bitstream download and a password prompt: once a stale
local in a refactor (NameError deep inside load()), once a method called as a
property.  Neither needed an FPGA to catch -- they needed the code to be run at
all.  A fake MMIO makes every path here executable in milliseconds.

What is deliberately NOT tested: anything about whether the RTL is correct.
That is what fpga/pynq/tb/ and the on-board soak are for.  This checks that the
Python does what it says.
"""

import io
import os
import struct
import sys
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from amoeba import image as _image                       # noqa: E402
from amoeba import psmon                                 # noqa: E402
from amoeba import regs as R                             # noqa: E402
from amoeba.device import Amoeba, AmoebaError            # noqa: E402

MEM_KB = 128


class FakeMem:
    """A byte array behind the Mmio interface."""

    def __init__(self, size):
        self.buf = bytearray(size)
        self.length = size

    def read(self, off):
        return struct.unpack_from("<I", self.buf, off)[0]

    def write(self, off, val):
        struct.pack_into("<I", self.buf, off, val & 0xFFFFFFFF)

    def write_bytes(self, off, data):
        pad = (-len(data)) % 4
        self.buf[off:off + len(data) + pad] = data + b"\x00" * pad

    def read_bytes(self, off, length):
        return bytes(self.buf[off:off + length])

    def fill(self, off, length, value=0):
        b = struct.pack("<I", value) * (length // 4)
        self.buf[off:off + len(b)] = b


class FakeSparseMem:
    """Mmio's interface over a 256 MiB span without allocating one.

    The DDR tests care about WHICH RANGES load() touches, not about the bytes,
    and a FakeMem for the carve-out would allocate a quarter of a gigabyte per
    test.  Writes go in a dict; fills are recorded as (offset, length).
    """

    def __init__(self, size):
        self.length = size
        self.words = {}
        self.fills = []

    def read(self, off):
        return self.words.get(off, 0)

    def write(self, off, val):
        self.words[off] = val & 0xFFFFFFFF

    def write_bytes(self, off, data):
        for i in range(0, len(data), 4):
            chunk = data[i:i + 4].ljust(4, b"\x00")
            self.words[off + i] = struct.unpack("<I", chunk)[0]

    def read_bytes(self, off, length):
        out = bytearray()
        for i in range(0, ((length + 3) // 4) * 4, 4):
            out += struct.pack("<I", self.words.get(off + i, 0))
        return bytes(out[:length])

    def fill(self, off, length, value=0):
        self.fills.append((off, length))
        for i in range(0, ((length + 3) // 4) * 4, 4):
            self.words[off + i] = value & 0xFFFFFFFF


class FakeCtl:
    """The control block's observable behaviour, including reset semantics."""

    def __init__(self, mem_kb=MEM_KB, is_bram=True, has_trace=True):
        self.regs = {}
        self.regs[R.R_ID] = R.ID_MAGIC
        self.regs[R.R_VERSION] = 0x0001_0000
        self.regs[R.R_CAPS] = ((mem_kb & 0xFFFF) << 16) \
            | (R_TRACE_BIT if has_trace else 0) | (1 if is_bram else 0)
        self.regs[R.R_CTRL] = R.CTRL_CORE_RESET      # comes out of config held
        self.starts = 0
        self.halts = 0
        self.log = []

    def read(self, off):
        if off == R.R_STATUS:
            in_rst = self.regs[R.R_CTRL] & R.CTRL_CORE_RESET
            return R.ST_CORE_RESET if in_rst else 0
        return self.regs.get(off, 0)

    def write(self, off, val):
        if off == R.R_CTRL:
            was = self.regs[R.R_CTRL] & R.CTRL_CORE_RESET
            now = val & R.CTRL_CORE_RESET
            if was and not now:
                self.starts += 1
                self.log.append("start")
            if now and not was:
                self.halts += 1
                self.log.append("halt")
        self.regs[off] = val


R_TRACE_BIT = 1 << 8


def make_dev(mem_kb=MEM_KB, **kw):
    dev = object.__new__(Amoeba)
    dev.ctl = FakeCtl(mem_kb=mem_kb, **kw)
    dev._mem = FakeMem(mem_kb * 1024)
    return dev


def make_ddr_dev(mem_kb=MEM_KB):
    """An AXI/DDR build.  mem_kb is still whatever MEM_KB the bitstream was
    built with -- the point being that the driver must ignore it."""
    dev = object.__new__(Amoeba)
    dev.ctl = FakeCtl(mem_kb=mem_kb, is_bram=False)
    dev._mem = FakeSparseMem(R.DDR_CARVEOUT_SIZE)
    return dev


def make_image(base=R.EXT_MEM_BASE, size=4096, tohost=None, memsz=None):
    if tohost is None:
        tohost = R.tohost_addr(MEM_KB, True)
    data = bytes((i * 7 + 3) & 0xFF for i in range(size))
    seg = _image.Segment(paddr=base, data=data,
                         memsz=memsz if memsz is not None else size)
    return _image.Image(entry=base, segments=[seg],
                        symbols={"tohost": tohost}, path="fake.elf")


# ---------------------------------------------------------------- tests ----
FAILED = []
print("driver tests (no hardware)")


def test(fn):
    name = fn.__name__[2:].replace("_", " ")   # strip the leading "t_" only
    try:
        fn()
        print(f"  ok    {name}")
    except Exception as exc:                                  # noqa: BLE001
        FAILED.append(name)
        print(f"  FAIL  {name}: {exc.__class__.__name__}: {exc}")
        traceback.print_exc(limit=3)
    return fn


@test
def t_load_writes_the_image():
    dev, img = make_dev(), make_image(size=1024)
    dev.load(img)
    assert dev._mem.buf[:1024] == img.segments[0].data


@test
def t_load_zeroes_first():
    dev, img = make_dev(), make_image(size=64)
    dev._mem.buf[5000] = 0xAB              # residue from a previous run
    dev.load(img)
    assert dev._mem.buf[5000] == 0, "stale byte survived the zero pass"


@test
def t_load_can_skip_zeroing():
    dev, img = make_dev(), make_image(size=64)
    dev._mem.buf[5000] = 0xAB
    dev.load(img, zero=False)
    assert dev._mem.buf[5000] == 0xAB


@test
def t_verify_catches_corruption():
    dev, img = make_dev(), make_image(size=256)
    real = dev._mem.write_bytes

    def flaky(off, data):
        real(off, data)
        dev._mem.buf[off + 10] ^= 0xFF     # a bit rots on the way in
    dev._mem.write_bytes = flaky
    try:
        dev.load(img)
    except AmoebaError as exc:
        assert "readback differs" in str(exc), exc
        return
    raise AssertionError("corruption was not detected")


@test
def t_refuses_oversized_image():
    dev = make_dev()
    img = make_image(size=64, memsz=MEM_KB * 1024 + 8)
    try:
        dev.load(img)
    except AmoebaError as exc:
        assert "outside" in str(exc), exc
        return
    raise AssertionError("oversized image was accepted")


@test
def t_refuses_tohost_mismatch():
    dev = make_dev()
    img = make_image(size=64, tohost=0x8080_0000)
    try:
        dev.load(img)
    except AmoebaError as exc:
        assert "tohost" in str(exc), exc
        return
    raise AssertionError("tohost mismatch was accepted")


@test
def t_refuses_to_load_while_running():
    dev, img = make_dev(), make_image(size=64)
    dev.start()
    try:
        dev.load(img)
    except AmoebaError as exc:
        assert "running" in str(exc), exc
        return
    raise AssertionError("load while running was accepted")


@test
def t_legacy_workaround_releases_then_rehalts():
    dev, img = make_dev(), make_image(size=64)
    dev.load(img, legacy_axi_reset=True)
    assert dev.ctl.log == ["start", "halt"], dev.ctl.log
    assert dev.in_reset, "core left running after a legacy load"


@test
def t_legacy_workaround_rehalts_even_on_error():
    dev = make_dev()
    img = make_image(size=64, tohost=0x8080_0000)   # fails the tohost check
    try:
        dev.load(img, legacy_axi_reset=True)
    except AmoebaError:
        pass
    # The check runs before the release, so the core must never have started.
    assert dev.ctl.log == [], dev.ctl.log
    assert dev.in_reset


@test
def t_run_orders_halt_load_start():
    dev, img = make_dev(), make_image(size=64)
    dev.start()                       # pretend a previous run left it going
    dev.ctl.log.clear()
    dev.run(img)
    assert dev.ctl.log[0] == "halt", dev.ctl.log
    assert dev.ctl.log[-1] == "start", dev.ctl.log
    assert not dev.in_reset


@test
def t_describe_reads_caps():
    dev = make_dev(mem_kb=64, has_trace=False)
    d = dev.describe()
    assert "64 KiB" in d and "BRAM" in d and "trace=no" in d, d


@test
def t_describe_ignores_caps_mem_kb_on_ddr():
    # CAPS[31:16] carries the MEM_KB build parameter verbatim, and an AXI
    # build leaves it at its default -- so believing it reports a 128 KiB
    # block RAM that is not in the design.
    d = make_ddr_dev(mem_kb=128).describe()
    assert "256 MiB" in d and "AXI/DDR" in d, d


@test
def t_mem_bytes_follows_the_backend():
    assert make_dev(mem_kb=128).mem_bytes == 128 * 1024
    assert make_ddr_dev(mem_kb=128).mem_bytes == R.DDR_CARVEOUT_SIZE


@test
def t_ddr_accepts_an_image_far_past_the_bram_window():
    # 1 MiB in is nowhere near the carve-out's end but well past a 128 KiB
    # block RAM.  A DDR build must not inherit the BRAM size limit.
    dev = make_ddr_dev()
    img = make_image(size=64, tohost=R.tohost_addr(MEM_KB, False))
    img.segments[0] = _image.Segment(paddr=R.EXT_MEM_BASE + (1 << 20),
                                     data=img.segments[0].data, memsz=64)
    dev.load(img)          # must not raise


@test
def t_ddr_zero_is_scoped_to_the_image_and_the_htif_page():
    # A full scrub of the carve-out is 256 MiB through an uncached mapping.
    # Zeroing must cover what the program uses and stop there.
    dev = make_ddr_dev()
    img = make_image(size=4096, tohost=R.tohost_addr(MEM_KB, False))
    dev.load(img)

    total = sum(n for _, n in dev._mem.fills)
    assert total < (1 << 20), dev._mem.fills
    page = R.tohost_addr(MEM_KB, False) - R.EXT_MEM_BASE
    assert (page, 4096) in dev._mem.fills, dev._mem.fills


@test
def t_ddr_zero_all_scrubs_the_whole_carveout():
    dev = make_ddr_dev()
    img = make_image(size=4096, tohost=R.tohost_addr(MEM_KB, False))
    dev.load(img, zero_all=True)
    assert (0, R.DDR_CARVEOUT_SIZE) in dev._mem.fills, dev._mem.fills


@test
def t_tohost_mismatch_names_the_right_target():
    # The generic message used to say "build with TARGET=pynq" on every
    # mismatch, which on a DDR build is advice to rebuild the image exactly
    # the way it already is.  Each backend must point at the other one.
    ddr = make_ddr_dev()
    img = make_image(size=64, tohost=R.tohost_addr(MEM_KB, True))   # BRAM image
    try:
        ddr.load(img)
    except AmoebaError as e:
        assert "IMAGE_TARGET=pynq-ddr" in str(e), e
    else:
        assert False, "should have refused"

    bram = make_dev()
    img2 = make_image(tohost=R.tohost_addr(MEM_KB, False))          # DDR image
    try:
        bram.load(img2)
    except AmoebaError as e:
        assert "IMAGE_TARGET=pynq" in str(e) and "pynq-ddr" not in str(e), e
    else:
        assert False, "should have refused"


@test
def t_ddr_refuses_the_legacy_reset_workaround():
    # It releases the core before the image is written.  Harmless against a
    # zeroed block RAM; on DDR the core would run the PREVIOUS image while the
    # PS overwrites it.
    dev = make_ddr_dev()
    img = make_image(size=64, tohost=R.tohost_addr(MEM_KB, False))
    try:
        dev.load(img, legacy_axi_reset=True)
    except AmoebaError as e:
        assert "unsafe" in str(e), e
        assert dev.ctl.starts == 0, "core was released before refusing"
    else:
        assert False, "should have refused"


@test
def t_image_tohost_is_a_method_not_a_property():
    # The API is inconsistent -- load_base/load_end/file_bytes are properties,
    # tohost() is a method -- and calling it wrong yields a TypeError deep in
    # an f-string rather than anything legible.  Pin the shape.
    img = make_image(size=8)
    assert callable(img.tohost)
    assert isinstance(img.tohost(), int)


@test
def t_top_word_of_memory_is_reachable():
    dev = make_dev()
    off = MEM_KB * 1024 - 4
    dev._mem.write(off, 0x5A5A_5A5A)
    assert dev._mem.read(off) == 0x5A5A_5A5A


@test
def t_afi_report_sees_a_register_move():
    """The whole point of the AFI snapshot is the delta.  A port that did
    something must not read as silent."""
    before = {(0, off): 0 for off in psmon.AFI_REGS}
    after = dict(before)
    after[(0, 0x0C)] = 3                       # rddatafifo_level
    buf = io.StringIO()
    assert psmon.report(before, after, out=buf) is True
    assert "rddatafifo_level" in buf.getvalue()


@test
def t_afi_report_calls_an_idle_port_idle():
    """And the converse, which is the reading that actually accuses the
    bridge -- so it must not fire on noise from another port."""
    before = {(p, off): 0 for p in range(psmon.AFI_PORTS)
              for off in psmon.AFI_REGS}
    after = dict(before)
    after[(1, 0x0C)] = 7                       # a port we do not use
    buf = io.StringIO()
    assert psmon.report(before, after, port=0, out=buf) is False
    assert "WEAK EVIDENCE" in buf.getvalue()


@test
def t_afi_never_touches_a_disabled_port():
    """Reading an AFI block whose port PCW left disabled hangs the PS with no
    timeout -- it cannot be caught at runtime, so it has to be caught here.
    The first version of this module looped over all four and wedged the
    board."""
    class RecordingMmio:
        def __init__(self, base, length, **kw):
            self.touched = []

        def read(self, off):
            self.touched.append(off)
            return 0

    real, psmon.Mmio = psmon.Mmio, RecordingMmio
    try:
        afi = psmon.Afi()
        afi.read()
        touched_ports = {off // psmon.AFI_STRIDE for off in afi._m.touched}
    finally:
        psmon.Mmio = real

    assert touched_ports <= set(psmon.AFI_ENABLED_PORTS), (
        f"read touched ports {sorted(touched_ports)}, "
        f"enabled are {list(psmon.AFI_ENABLED_PORTS)}")
    assert touched_ports, "read touched nothing at all"


@test
def t_afi_ports_do_not_overlap_and_fit_the_mapping():
    """A stride typo would silently alias two ports onto each other and make
    every delta read as movement."""
    assert psmon.AFI_SPAN == psmon.AFI_STRIDE * psmon.AFI_PORTS
    assert max(psmon.AFI_REGS) < psmon.AFI_STRIDE
    assert psmon.AFI_BASE % 4096 == 0


def main():
    if FAILED:
        print(f"\n{len(FAILED)} failed: {', '.join(FAILED)}")
        return 1
    print("\nall passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
