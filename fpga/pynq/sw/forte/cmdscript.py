"""The pin bench's command language (hvl/pin/pin_tb.sv), run on the board.

Same commands and meaning as the bench; `run`, `run_until_*` and timeouts count
chip cycles from CYC_TOTAL.  The PS polls, so console-triggered commands land
some cycles later than in the bench.

Console waits search the text received since the previous wait was satisfied,
as the bench's do.  Arming the PL matcher when the command starts would miss
text the chip printed while Python was still on its way there."""

from . import regs as R
from .device import Forte, record_lines


def unescape(s: str) -> str:
    return s.encode("latin-1").decode("unicode_escape")


def rest_after(line: str, n: int) -> str:
    parts = line.split(None, n)
    return parts[n] if len(parts) > n else ""


class Run:
    def __init__(self, dev: Forte, trace_path: str, uart_path: str, max_errors: int = 1):
        self.dev = dev
        self.trace = open(trace_path, "w")
        self.uart = open(uart_path, "wb")
        self.max_errors = max_errors
        self.errors = []
        self.link_errors = 0
        self.exit_code = None
        self.fail_reported = False
        self.tohost_cyc = None
        self.stop_cyc = None
        self.policy = "rand"
        self.console = bytearray()
        self.console_cursor = 0
        self.fail_pattern = None

    # ---- bookkeeping ----
    def error(self, msg: str) -> None:
        self.errors.append(msg)
        print(f"[FORTE] ERROR cyc {self.dev.link_cycles()}: {msg}")
        if self.total_errors() >= self.max_errors and self.stop_cyc is None:
            self.stop_cyc = self.dev.link_cycles() + 1

    def total_errors(self) -> int:
        return self.link_errors + len(self.errors)

    def stopped(self) -> bool:
        return self.total_errors() >= self.max_errors

    def after_stop(self, at: int) -> bool:
        return ((self.stop_cyc is not None and at > self.stop_cyc) or
                (self.tohost_cyc is not None and at > self.tohost_cyc))

    def service(self) -> None:
        self.link_errors = self.dev.link_errors()
        data, framing = self.dev.drain_uart(64)
        self.uart.write(data)
        self.console += data
        if self.fail_pattern is not None and not self.fail_reported and self.fail_pattern in self.console:
            self.fail_reported = True
            self.error("console printed the fail pattern")
        for b in framing:
            self.error(f"framing error on uart_tx (byte {b:02x})")
        for record in self.dev.drain_trace(64):
            at, lines = record_lines(record)
            if self.after_stop(at):
                continue
            for line in lines:
                self.trace.write(line + "\n")
                if line.startswith("T ") and self.tohost_cyc is None:
                    self.tohost_cyc = at

    def drain_all(self) -> None:
        while True:
            self.service()
            if not self.dev.rd(R.REG_UART_RX_DATA) >> 31 and not self.dev.rd(R.REG_TRACE_STAT) & 1:
                return

    def run_cycles(self, n: int, until=None) -> bool:
        """Wait n chip cycles, or until `until` holds.  A polling pass can take
        longer than a short budget, so when the budget runs out everything the
        chip already produced is drained and `until` checked once more."""
        start = self.dev.cycles()
        while True:
            self.service()
            if self.stopped():
                return False
            if until is not None and until():
                return True
            if self.dev.cycles() - start >= n:
                if until is None:
                    return True
                self.drain_all()
                return not self.stopped() and until()

    def finish(self) -> None:
        while True:
            before = self.dev.rd(R.REG_TRACE_LEVEL)
            self.service()
            if before == 0 and not self.dev.rd(R.REG_TRACE_STAT) & 1:
                break
        self.trace.close()
        self.uart.close()

    # ---- commands ----
    def execute(self, raw: str, lineno: int) -> str:
        """Run one line; returns a verdict string to stop with, or ''."""
        line = raw.rstrip("\r\n")
        words = line.split()
        if not words or words[0].startswith("#"):
            return ""
        cmd, args = words[0], words[1:]
        print(f"[FORTE] cmd {lineno}: {line}")
        d = self.dev
        if cmd == "mem_policy":
            if args[0] not in ("rand", "zero"):
                self.error(f"mem_policy {args[0]}: hardware has rand or zero only")
            self.policy = args[0]
        elif cmd == "load_lst":
            image = d.load_lst(args[0], self.policy)
            print(f"[FORTE] loaded {len(image)} words from {args[0]}")
        elif cmd == "reset":
            self.exit_code = None
            self.tohost_cyc = None
            d.reset(int(args[0]))
            self.run_cycles(int(args[0]) + 1)
        elif cmd == "run":
            self.run_cycles(int(args[0]))
        elif cmd == "run_until_tohost":
            if not self.run_cycles(int(args[0]), until=lambda: d.tohost() is not None):
                if self.stopped():
                    return f"FAIL {self.total_errors()} checker errors"
                return f"FAIL timeout: no tohost write in {args[0]} cycles"
            value = d.tohost()
            self.exit_code = value >> 1
            if self.tohost_cyc is None:
                self.tohost_cyc = d.rd64(R.REG_TOHOST_CYC_LO)
            print(f"[FORTE] tohost = {value:016x} (exit code {self.exit_code})")
            if not value & 1:
                self.error(f"tohost {value:016x} has bit 0 clear")
        elif cmd == "run_until_uart":
            want = unescape(rest_after(line, 2)).encode("latin-1")

            def printed():
                return self.console.find(want, self.console_cursor) >= 0

            if not self.run_cycles(int(args[0]), until=printed):
                if self.stopped():
                    return f"FAIL {self.total_errors()} checker errors"
                return f'FAIL timeout: console never printed "{want.decode()}" in {args[0]} cycles'
            self.console_cursor = self.console.find(want, self.console_cursor) + len(want)
        elif cmd == "expect_tohost":
            if self.exit_code != int(args[0]):
                self.error(f"exit code {self.exit_code}, expected {args[0]}")
        elif cmd == "uart_div":
            d.uart_div(int(args[0]))
        elif cmd == "uart_send":
            d.uart_send(unescape(rest_after(line, 1)).encode("latin-1"))
        elif cmd == "uart_send_ferr":
            d.uart_send(bytes([int(args[0], 16)]), R.UART_TX_BAD_STOP)
        elif cmd == "uart_gap":
            d.wr(R.REG_UART_TX_GAP, int(args[0]))
        elif cmd == "uart_fail":
            if self.fail_pattern is not None:
                self.error("uart_fail: one fail pattern per run")
            self.fail_pattern = unescape(rest_after(line, 1)).encode("latin-1")
        elif cmd == "irq":
            d.irq(int(args[0]), int(args[1]))
        elif cmd == "fault_inject":
            d.set_pins(fault_inject=int(args[0]))
        elif cmd == "dump_mem":
            base, nbytes, path = int(args[0], 16), int(args[1]), args[2]
            with open(path, "w") as fh:
                for i in range(0, nbytes, 8):
                    fh.write(f"{base + i:016x} {d.read_mem64(base + i):016x}\n")
        elif cmd == "dialect":
            pass
        elif cmd == "irq_clear_on":
            d.set_match(1, unescape(rest_after(line, 2)).encode("latin-1"))
            d.arm_trigger(1, R.TRIG_SRC_MATCH1, R.TRIG_IRQ_CLEAR, line=int(args[0]))
        elif cmd == "reset_at":
            # reset_at state <name> [cycles] | reset_at cycle <n> [cycles]
            length = int(args[2]) if len(args) > 2 else 16
            if args[0] == "state":
                d.arm_trigger(0, R.TRIG_SRC_STATE, R.TRIG_RESET, length=length,
                              arg0=R.LINK_STATES.index(args[1]))
            else:
                d.arm_trigger(0, R.TRIG_SRC_CYCLE, R.TRIG_RESET, length=length, arg0=int(args[1]))
        elif cmd == "fault_pattern":
            self.fault_pattern(args)
        elif cmd == "finish":
            return "PASS"
        else:
            self.error(f"line {lineno}: unknown command '{cmd}'")
        if self.stopped():
            return f"FAIL {self.total_errors()} checker errors"
        return ""

    def fault_pattern(self, args) -> None:
        """fault_pattern off | static | square <period> <high> | random <min> <span_mask> [seed]
        | pulse <cycles> | burst <periods> | phase <periods> <site-or-phase>... | single <site-or-phase>...
        A site is a group name (alu0, cmp, dcache, ...) and stands for all its phases."""
        d = self.dev
        mode = args[0]
        if mode == "off":
            d.fault_stop()
            return

        def phases(names):
            out = []
            for n in names:
                out += R.FI_SITE_PHASES[n] if n in R.FI_SITE_PHASES else [int(n, 0)]
            return out

        n = [int(a, 0) for a in args[1:] if a.lstrip("-").isdigit() or a.startswith("0x")]
        if mode == "static":
            d.fault_pattern(R.FI_STATIC, start=False)
        elif mode == "square":
            d.fault_pattern(R.FI_SQUARE, n[0], n[1])
        elif mode == "random":
            d.fault_pattern(R.FI_RANDOM, n[0], n[1], n[2] if len(n) > 2 else 1)
        elif mode == "pulse":
            d.fault_pattern(R.FI_PULSE, n[0])
        elif mode == "burst":
            d.fault_pattern(R.FI_BURST, n[0])
        elif mode == "phase":
            d.fault_pattern(R.FI_PHASE, int(args[1], 0), phases=phases(args[2:]))
        elif mode == "single":
            d.fault_pattern(R.FI_SINGLE, phases=phases(args[1:]))
        else:
            self.error(f"fault_pattern: unknown mode {mode}")

    def verdict(self, result: str) -> str:
        self.finish()
        if result == "PASS" and self.total_errors():
            result = f"FAIL {self.total_errors()} checker errors"
        return result
