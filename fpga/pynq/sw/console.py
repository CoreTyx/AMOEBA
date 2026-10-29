#!/usr/bin/env python3
"""An interactive terminal on the core's serial console.

  sudo python3 console.py --image ../images/uart_echo_app.elf   # load, run, attach
  sudo python3 console.py                       # attach to a core already running
  sudo python3 console.py --check               # and verify serial == snoop
  sudo python3 console.py --source snoop        # read the AHB snoop instead

Characters typed here go through amoeba_ctl's SER_TX FIFO into the PL
serializer, out as start/data/stop bits on the 16550's SIN -- amoeba_top's
uart_rx pad under DUT=asic -- and are read by the guest's receiver.  What the
guest prints comes back the same way and is deserialized into SER_DATA.  The
AHB snoop (UART_DATA) still sees every printed byte too, which is what
--check compares against: the two streams must be identical, and a divergence
means the serializer, the divisor or the deserializer is wrong.

With --image this loads the program and releases the core, the way
run_freertos.py does, and then attaches.  Without it nothing is loaded:
attach to something already running (run_linux.py --interactive leaves it
running, and so does run_freertos.py in another session), or use --start to
release the core if an image is ALREADY in memory.  --start on its own runs
whatever happens to be in DDR, which is usually nothing you want.

  Ctrl-]   detach          Ctrl-C is passed THROUGH to the guest
"""

import argparse
import os
import select
import sys
import termios
import time
import tty

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from amoeba import Amoeba, AmoebaError  # noqa: E402
from amoeba import image as _image  # noqa: E402

DETACH = 0x1D          # Ctrl-]


def attach(dev, *, source="serial", check=False, poll=0.002,
           out=None, echo_local=False, crlf=True):
    """Run the terminal loop until Ctrl-] or EOF.  Returns the byte counts.

    `crlf` translates LF to CRLF on the way to the screen only -- raw mode
    turns off the terminal's own ONLCR, so a guest that prints bare newlines
    (FreeRTOS's uart_puts does) otherwise walks down the screen a column at a
    time.  The buffers returned are the untranslated bytes, so --check still
    compares what actually crossed the wire.  A guest that already sends CRLF
    gets a doubled CR, which lands in the same column and is invisible.
    """
    out = out or sys.stdout.buffer
    read_main = dev.read_serial if source == "serial" else dev.read_console
    read_alt = dev.read_console if source == "serial" else dev.read_serial

    main_buf = bytearray()
    alt_buf = bytearray()
    sent = 0
    stdin_fd = sys.stdin.fileno()
    isatty = os.isatty(stdin_fd)
    saved = termios.tcgetattr(stdin_fd) if isatty else None
    if isatty:
        tty.setraw(stdin_fd)
    try:
        while True:
            chunk = read_main()
            if chunk:
                main_buf += chunk
                out.write(chunk.replace(b"\n", b"\r\n") if crlf else chunk)
                out.flush()
            if check:
                alt_buf += read_alt()
            r, _, _ = select.select([stdin_fd], [], [], 0 if chunk else poll)
            if not r:
                continue
            data = os.read(stdin_fd, 256)
            if not data:
                break
            if DETACH in data:
                data = data[:data.index(DETACH)]
                if data:
                    dev.write_serial(data)
                    sent += len(data)
                break
            dev.write_serial(data)
            sent += len(data)
            if echo_local:
                out.write(data)
                out.flush()
    finally:
        if isatty:
            termios.tcsetattr(stdin_fd, termios.TCSADRAIN, saved)

    # One last drain of both, so a --check comparison is not short by whatever
    # was in flight when the user detached.
    time.sleep(0.05)
    main_buf += read_main()
    alt_buf += read_alt()
    return bytes(main_buf), bytes(alt_buf), sent


def compare(serial: bytes, snoop: bytes) -> int:
    """Report the first divergence between the two console streams.

    They are the same bytes by two routes: the snoop takes them off the AHB
    as the guest stores them, the serial copy off the wire after the 16550
    serialized them.  One is allowed to be SHORTER (the tail is still in a
    FIFO); they are not allowed to DIFFER.
    """
    n = min(len(serial), len(snoop))
    for i in range(n):
        if serial[i] != snoop[i]:
            lo = max(0, i - 16)
            print(f"\n# MISMATCH at byte {i}: serial {serial[i]:#04x} "
                  f"({chr(serial[i])!r}), snoop {snoop[i]:#04x} ({chr(snoop[i])!r})",
                  file=sys.stderr)
            print(f"#   snoop  ...{snoop[lo:i + 16]!r}", file=sys.stderr)
            print(f"#   serial ...{serial[lo:i + 16]!r}", file=sys.stderr)
            return 1
    print(f"\n# streams agree over {n} bytes "
          f"(serial {len(serial)}, snoop {len(snoop)})", file=sys.stderr)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bitstream")
    ap.add_argument("--fclk", type=float, default=25.0)
    ap.add_argument("--source", choices=("serial", "snoop"), default="serial",
                    help="which copy of the console to display (default serial)")
    ap.add_argument("--check", action="store_true",
                    help="also read the other copy and compare them on exit")
    ap.add_argument("--baud", type=int,
                    help="pin the transceiver to this rate instead of following "
                         "the divisor the guest programmed")
    ap.add_argument("--image",
                    help="load this ELF and release the core before attaching")
    ap.add_argument("--start", action="store_true",
                    help="release the core without loading anything (only useful "
                         "if an image is already in memory)")
    ap.add_argument("--echo", action="store_true", help="echo typed characters locally")
    ap.add_argument("--raw", action="store_true",
                    help="do not translate LF to CRLF on the way to the screen")
    args = ap.parse_args()

    try:
        dev = Amoeba(bitstream=args.bitstream, fclk_mhz=args.fclk)
    except PermissionError:
        print("error: need root for /dev/mem (try sudo)", file=sys.stderr)
        return 2
    print(f"# {dev.describe()}", file=sys.stderr)
    if not dev.has_serial:
        print("error: this bitstream has no serial transceiver (CAPS[10]); "
              "rebuild, or use --source snoop for output only", file=sys.stderr)
        return 2

    dev.measure_fclk(0.2)
    if args.baud:
        got = dev.set_baud(args.baud)
        print(f"# serial pinned to {got} baud (asked {args.baud})", file=sys.stderr)
    st = dev.serial_stats()
    print(f"# serial: {st['baud']} baud (tick {st['tick']}), LCR {st['lcr']:#04x}"
          f"{'' if st['lcr'] == 0x03 else '  -- NOT 8N1, the deserializer assumes 8N1'}",
          file=sys.stderr)
    if args.image:
        dev.run(_image.load(args.image))
        print(f"# {os.path.basename(args.image)} loaded, core released",
              file=sys.stderr)
    elif dev.in_reset:
        if args.start:
            dev.start()
            print("# core released with nothing loaded -- it is running whatever "
                  "was in memory", file=sys.stderr)
        else:
            print("# note: the core is held in reset -- nothing will print. "
                  "Pass --image, or start it from run_freertos.py / "
                  "run_linux.py in another shell.", file=sys.stderr)

    print("# attached; Ctrl-] to detach", file=sys.stderr)
    rc = 0
    try:
        main_buf, alt_buf, sent = attach(dev, source=args.source, check=args.check,
                                         echo_local=args.echo, crlf=not args.raw)
        st = dev.serial_stats()
        if st["ferr"] or st["overflow"]:
            print(f"\n# serial: {st['ferr']} framing errors"
                  f"{', FIFO overflowed' if st['overflow'] else ''} -- the rate is "
                  f"wrong, or the FIFO was not drained fast enough", file=sys.stderr)
    except (AmoebaError, RuntimeError) as exc:
        print(f"\n# {exc}", file=sys.stderr)
        return 1
    finally:
        dev.close()

    print(f"\n# detached: {len(main_buf)} bytes in, {sent} typed", file=sys.stderr)
    if args.check:
        serial, snoop = ((main_buf, alt_buf) if args.source == "serial"
                         else (alt_buf, main_buf))
        rc = compare(serial, snoop)
    return rc


if __name__ == "__main__":
    sys.exit(main())
