"""PS-side observation of the PL-to-DDR path.

WHAT THIS CAN AND CANNOT DO.  There is no facility on Zynq-7000 for the PS to
capture AXI beats crossing an HP port -- the interconnect between the port and
the DDR controller is hard silicon with no trace buffer.  If you want the
transactions themselves, that is a System ILA, and it lives in the PL.

What the PS *can* see is the port's own state.  Each AFI (HP) port exposes a
small register block, and two of those registers are FIFO occupancy counters
that move when traffic moves.  That is enough to answer the one question the
PL-side AHB probe cannot: when the core issues a read and never gets an answer,
did the request reach the PS at all?

  probe says            AFI says          conclusion
  --------------------  ----------------  ----------------------------------
  XACT > 0, BEAT == 0   unchanged         the bridge swallowed it; nothing
                                          ever reached the PS
  XACT > 0, BEAT == 0   moved             the PS got the request and did not
                                          answer -- suspect the port config,
                                          the address, or DDR itself

WHY THE DELTA IS THE MEASUREMENT.  The field decode below is from UG585 and is
used to *label* the registers, not to carry the argument.  A FIFO level read at
one instant is a sample of a queue that drains in nanoseconds, so an absolute
value means very little from Python.  What means something is comparison: if
every register on a port reads identically before and after a run in which the
core allegedly hammered memory, that port did nothing.  That conclusion holds
even if a field name here is wrong.
"""

from typing import Dict, Optional, Tuple

from .mmio import Mmio

AFI_BASE = 0xF800_8000
AFI_STRIDE = 0x1000
AFI_PORTS = 4

# ONLY EVER READ A PORT THE PS7 BLOCK ACTUALLY ENABLES.
#
# An AFI register block belongs to its port, and a port that PCW_USE_S_AXI_HPn
# left disabled is not clocked.  A /dev/mem read of an unclocked block does not
# return zero and does not fault: the access never completes and the PS hangs
# there forever, exactly like a PL access that no slave decodes.  Reading all
# four ports to "see everything" wedges the machine on any design that wires
# fewer than four -- which is this one, and most others.
#
# bd_pynq.tcl sets PCW_USE_S_AXI_HP0 and nothing else, so HP0 is the only safe
# port here.  Widen this ONLY together with the PS7 config, never ahead of it.
AFI_ENABLED_PORTS = (0,)

# AND THE ENABLED PORT IS ONLY SAFE ONCE THE PL IS RUNNING.
#
# HP0's slave interface is clocked by S_AXI_HP0_ACLK, which this design drives
# from FCLK0 -- a clock that exists only after the bitstream is downloaded and
# the PS7 clock generator is programmed.  Sample before that and the port is as
# unclocked as a disabled one, with the same unrecoverable result.  Callers
# must not sample until the fabric clock has been measured non-zero; the
# driver's --afi path enforces that, so do not bypass it.

AFI_SPAN = AFI_STRIDE * AFI_PORTS

# offset -> (name, is_a_counter)
#
# "is_a_counter" marks the two occupancy registers, the ones expected to move
# under traffic.  The rest are configuration and should be identical across a
# run; if one of them changes, something reconfigured the port underneath us
# and that is itself worth seeing.
AFI_REGS: Dict[int, Tuple[str, bool]] = {
    0x00: ("rdchan_ctrl",      False),
    0x04: ("rdchan_issuingcap", False),
    0x08: ("rdqos",            False),
    0x0C: ("rddatafifo_level", True),
    0x10: ("rddebug",          True),
    0x14: ("wrchan_ctrl",      False),
    0x18: ("wrchan_issuingcap", False),
    0x1C: ("wrqos",            False),
    0x20: ("wrdatafifo_level", True),
    0x24: ("wrdebug",          True),
}


class Afi:
    """Reader for the enabled AFI port register blocks.

    Construction can fail -- /dev/mem needs root, and a kernel with strict
    /dev/mem restrictions will refuse the mapping outright.  That is a reason
    to say so and carry on, not to lose the rest of a diagnosis, so callers
    should use `open_quietly()` rather than the constructor.
    """

    def __init__(self, ports=AFI_ENABLED_PORTS):
        bad = [p for p in ports if p not in range(AFI_PORTS)]
        if bad:
            raise ValueError(f"no such AFI port: {bad}")
        self.ports = tuple(ports)
        self._m = Mmio(AFI_BASE, AFI_SPAN)

    def read(self) -> Dict[Tuple[int, int], int]:
        """{(port, offset): value} for the enabled ports only.

        See AFI_ENABLED_PORTS: touching a disabled port hangs the PS.
        """
        out = {}
        for port in self.ports:
            for off in AFI_REGS:
                out[(port, off)] = self._m.read(port * AFI_STRIDE + off)
        return out

    def close(self) -> None:
        self._m.close()


def open_quietly() -> Optional[Afi]:
    try:
        return Afi()
    except Exception:
        return None


def report(before: Dict[Tuple[int, int], int],
           after: Dict[Tuple[int, int], int],
           *, port: int = 0, out=None) -> bool:
    """Print what moved on one port.  Returns True if anything did.

    Only one port is printed because only one is wired: the design connects
    the core's memory master to HP0 and leaves HP1..3 unused -- and those are
    not merely uninteresting, they are unreadable.  See AFI_ENABLED_PORTS.
    """
    import sys
    out = out or sys.stderr

    moved = []
    for off, (name, _counter) in sorted(AFI_REGS.items()):
        b = before.get((port, off))
        a = after.get((port, off))
        if b is None or a is None:
            continue
        if b != a:
            moved.append(f"{name} 0x{b:08x} -> 0x{a:08x}")

    if moved:
        print(f"#   AFI{port}: moved during the run: {'; '.join(moved)}",
              file=out)
        print(f"#   AFI{port}: the request path to the PS is alive -- the PS "
              "side saw traffic.", file=out)
        return True

    print(f"#   AFI{port}: every register identical before and after the run.",
          file=out)
    print("#   AFI: this is WEAK EVIDENCE and on its own proves nothing.  "
          "These registers\n"
          "#        are instantaneous FIFO occupancy, not counters, so they "
          "only show\n"
          "#        traffic that is in flight AT THE MOMENT OF THE READ.  A "
          "core that\n"
          "#        wedges in the first microseconds leaves them empty no "
          "matter what\n"
          "#        crossed the port beforehand.  Believe an idle reading "
          "only when the\n"
          "#        core is still actively driving the bus while you sample.",
          file=out)
    return False
