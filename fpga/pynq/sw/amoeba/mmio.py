"""Minimal memory-mapped register access.

One implementation over /dev/mem rather than a pynq backend and a fallback.
PYNQ's own MMIO is a /dev/mem mapping underneath, so a second path would buy
nothing but a second thing that can be subtly different -- and this way the
driver also runs on a plain Zynq Linux with no PYNQ installed.  pynq is used
only to download the bitstream, and only if it is there.

Register access is 32-bit word at a time.  The control block and the image
window are both AXI4-Lite slaves, and while they do honour byte strobes,
letting Python's buffer machinery choose an access width for a device mapping
is the sort of thing that works on one kernel and not the next.

DDR IS DIFFERENT, and it has to be, because a 256 MiB carve-out written a word
at a time from Python takes hours.  `wordwise=False` selects slice assignment
straight onto the mapping, which is a memcpy.  That is safe there and only
there: the carve-out is ordinary DRAM, not a peripheral, so no access-width
rule applies to it.

WHY O_SYNC IS NOT OPTIONAL.  It makes the kernel map the region uncached.  On
Zynq-7000 the HP ports are NOT coherent with the Cortex-A9 caches (that is what
ACP is for), so an image written through a cached mapping can sit in the A9's
L1 or L2 while the PL reads stale DDR underneath it.  The symptom is a core
that fetches garbage from memory the PS can read back correctly -- which reads
as a bitstream or bridge fault and is neither.  The cost is that these writes
run at uncached speed, which is why load() does not scrub the whole carve-out.
"""

import mmap
import os
import struct

PAGE = mmap.PAGESIZE


class Mmio:
    def __init__(self, base: int, length: int, *, wordwise: bool = True):
        if base % 4:
            raise ValueError("base must be word-aligned")
        self.base = base
        self.length = length
        self.wordwise = wordwise

        page_base = base & ~(PAGE - 1)
        self._delta = base - page_base
        span = ((self._delta + length + PAGE - 1) // PAGE) * PAGE

        self._fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        try:
            self._map = mmap.mmap(self._fd, span, mmap.MAP_SHARED,
                                  mmap.PROT_READ | mmap.PROT_WRITE,
                                  offset=page_base)
        except Exception:
            os.close(self._fd)
            raise

    # ---- single word ------------------------------------------------------
    def read(self, offset: int) -> int:
        self._check(offset, 4)
        return struct.unpack_from("<I", self._map, self._delta + offset)[0]

    def write(self, offset: int, value: int) -> None:
        self._check(offset, 4)
        struct.pack_into("<I", self._map, self._delta + offset, value & 0xFFFFFFFF)

    # ---- bulk -------------------------------------------------------------
    def write_bytes(self, offset: int, data: bytes) -> None:
        """Word-at-a-time and zero-padded to a word boundary, or a memcpy
        when the mapping is not wordwise.

        The pad matters in the wordwise case: a program image whose last
        section does not end on a 4-byte boundary would otherwise leave the
        final bytes unwritten, and the symptom is a corrupt tail rather than
        an error.  Slice assignment writes the exact length, so it needs no
        pad.
        """
        self._check(offset, len(data))
        if not self.wordwise:
            start = self._delta + offset
            self._map[start:start + len(data)] = data
            return
        pad = (-len(data)) % 4
        if pad:
            data = data + b"\x00" * pad
        for i in range(0, len(data), 4):
            struct.pack_into("<I", self._map, self._delta + offset + i,
                             struct.unpack_from("<I", data, i)[0])

    def read_bytes(self, offset: int, length: int) -> bytes:
        self._check(offset, length)
        if not self.wordwise:
            start = self._delta + offset
            return bytes(self._map[start:start + length])
        out = bytearray()
        for i in range(0, ((length + 3) // 4) * 4, 4):
            out += struct.pack("<I", self.read(offset + i))
        return bytes(out[:length])

    # Chunked so a fill over the whole carve-out does not first build a
    # 256 MiB bytes object in the interpreter.
    _FILL_CHUNK = 1 << 20

    def fill(self, offset: int, length: int, value: int = 0) -> None:
        self._check(offset, length)
        if not self.wordwise:
            if value & 0xFFFFFFFF not in (0, 0xFFFFFFFF):
                raise ValueError(
                    "a byte-wise fill can only write a uniform byte; use 0 "
                    "or 0xFFFFFFFF, or write_bytes() for a pattern")
            byte = b"\x00" if value == 0 else b"\xff"
            start = self._delta + offset
            done = 0
            while done < length:
                n = min(self._FILL_CHUNK, length - done)
                self._map[start + done:start + done + n] = byte * n
                done += n
            return
        for i in range(0, ((length + 3) // 4) * 4, 4):
            self.write(offset + i, value)

    # ---- housekeeping -----------------------------------------------------
    def _check(self, offset: int, length: int) -> None:
        if offset < 0 or offset + length > self.length:
            raise IndexError(
                f"access at +0x{offset:x}[{length}] is outside the "
                f"0x{self.length:x}-byte window at 0x{self.base:08x}")

    _closed = False

    def close(self) -> None:
        """Idempotent, and safe to call from __del__.

        Left to interpreter shutdown these mappings are torn down in an
        arbitrary order while device memory is still mapped, which is not a
        situation worth relying on -- a 256 MiB uncached /dev/mem mapping is
        not an ordinary anonymous one.  Closing deterministically costs
        nothing and removes the question.
        """
        if self._closed:
            return
        self._closed = True
        try:
            self._map.close()
        finally:
            os.close(self._fd)

    def __del__(self):
        try:
            self.close()
        except Exception:
            pass

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()


def download_bitstream(path: str) -> None:
    """Deprecated shim.  Use amoeba.pl.program(), which also sets FCLK0.

    Kept because programming without setting the clock is exactly the bug this
    module used to have, and a caller still reaching for this name should get
    the fixed behaviour rather than the old one.
    """
    from .pl import program
    program(path)
