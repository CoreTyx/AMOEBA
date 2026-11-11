"""The pin bench's command language (hvl/pin/pin_tb.sv), run on the board.

Same commands and meaning as the bench; `run`, `run_until_*` and timeouts count
chip cycles from CYC_TOTAL.  The PS polls, so console-triggered commands land
some cycles later than in the bench.

Console waits search the text received since the previous wait was satisfied,
as the bench's do.  Arming the PL matcher when the command starts would miss
text the chip printed while Python was still on its way there."""

import random

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
        self.fail_patterns = []
        self.phase_delta = 0

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
        if not self.fail_reported and any(p in self.console for p in self.fail_patterns):
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
            if not self.dev.output_pending():
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
            if before == 0 and not self.dev.output_pending():
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
            self.fail_patterns.append(unescape(rest_after(line, 1)).encode("latin-1"))
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
        elif cmd == "fault_on_match":
            # fault_on_match <burst|pulse> <n> <text...>: start the pattern each time the console prints text
            mode = {"burst": R.FI_BURST, "pulse": R.FI_PULSE}[args[0]]
            d.fault_pattern(mode, int(args[1]), start=False)
            d.set_match(1, unescape(rest_after(line, 3)).encode("latin-1"))
            d.arm_trigger(2, R.TRIG_SRC_MATCH1, R.TRIG_FAULT, repeat=True)
        elif cmd == "expect_fi_events":
            rounds, periods = int(args[0]), int(args[1])
            for g, n in d.fault_events().items():
                want = rounds * periods * len(R.FI_SITE_PHASES[g])
                if n != want:
                    self.error(f"FI_EVENTS[{g}] = {n}, expected {want}")
        elif cmd == "fi_phase_ofs":
            d.wr(R.REG_FI_PHASE_OFS, int(args[0]) & 0x1FF)
        elif cmd == "calibrate_phase":
            self.calibrate_phase(int(args[0]), int(args[1]))
        elif cmd == "fault_trial":
            self.fault_trial(int(args[0], 16), unescape(args[1]).encode("latin-1"),
                             unescape(rest_after(line, 3)).encode("latin-1"))
        elif cmd == "target_site":
            self.target_site(int(args[0]), int(args[1], 16), int(args[2]),
                             None if args[3] == "none" else int(args[3]))
        elif cmd == "scan_session":
            self.scan_session(int(args[0]), int(args[1]))
        elif cmd == "status_clear":
            d.status_clear()
        elif cmd == "wait_status":
            # wait_status <none|stalled|active|quiet> <cycles>: until the status
            # pin's last two half-periods are equal and of that class
            want = args[0]
            if want not in R.STATUS_CLASSES:
                self.error(f"wait_status: unknown class {want}")
            elif not self.run_cycles(int(args[1]), until=lambda: d.status()["class"] == want):
                self.error(f"wait_status: status never {want} in {args[1]} cycles: {d.status()}")
            else:
                print(f"[FORTE] status {want}: {d.status()}")
        elif cmd == "expect_clkout":
            s = d.status()
            if s["clkout_edges"] != s["clkout_window"]:
                self.error(f"clk_out: {s['clkout_edges']} edges in a {s['clkout_window']}-cycle window")
            else:
                print(f"[FORTE] clk_out: {s['clkout_edges']} edges in {s['clkout_window']} cycles")
        elif cmd == "check_chip_counters":
            print("[FORTE] check_chip_counters: the chip's fault counters are not visible from the PS; skipped")
        elif cmd == "expect_phase_ofs":
            if d.rd(R.REG_FI_PHASE_OFS) != int(args[0]):
                self.error(f"FI_PHASE_OFS {d.rd(R.REG_FI_PHASE_OFS)}, expected {args[0]}")
        elif cmd == "expect_phase_delta":
            if self.phase_delta != int(args[0]):
                self.error(f"phase delta {self.phase_delta}, expected {args[0]}")
        elif cmd == "check_fi_rounds":
            self.check_fi_rounds(int(args[0]))
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

    # calibrate_phase's units and the phase fbu_fi_gen's mask must select for
    # their site to fire: the register file's 0x1FF, and one earlier for the
    # pipeline registers, whose flip mask samples the enable a cycle early.
    CAL_MASK_PHASE = {4: 0x1FF, 5: 0x1FE}
    FAULT_TRIGGER = 2

    def calibrate_phase(self, unit: int, periods: int) -> None:
        """Sweep a one-cycle pin pulse over all 512 phases, one fe_fault_cal.c
        round each; the one phase that detects gives the FI_PHASE_OFS correction."""
        d = self.dev
        if unit not in self.CAL_MASK_PHASE:
            self.error(f"calibrate_phase: unit {unit} has no single site; use 4 or 5")
            return
        d.fault_pattern(R.FI_PHASE, periods, start=False)
        d.set_match(1, b"CAL GO")
        d.arm_trigger(self.FAULT_TRIGGER, R.TRIG_SRC_MATCH1, R.TRIG_FAULT, repeat=True)
        hits = []
        for phase in range(512):
            word = phase // 32
            d.wr(R.REG_FI_PHASE_MASK + 4 * word, 1 << (phase % 32))
            if phase % 32 == 0 and phase > 0:
                d.wr(R.REG_FI_PHASE_MASK + 4 * (word - 1), 0)
            fired = d.trigger_fired(self.FAULT_TRIGGER)
            d.uart_send(str(unit).encode())
            if not self.run_cycles(10_000_000, until=lambda: d.trigger_fired(self.FAULT_TRIGGER) != fired
                                   and not d.fault_running()):
                self.error(f"calibrate_phase: the pulse at phase {phase} never ran")
                return
            d.uart_send(b"x")
            line = self.next_console_line(b"CAL d ")
            if line is None:
                self.error(f"calibrate_phase: no CAL line for phase {phase}")
                return
            detected, others = int(line.split()[2]), int(line.split()[4])
            if others:
                self.error(f"calibrate_phase: phase {phase} moved other units' counters by {others}")
            if detected:
                print(f"[FORTE] calibrate_phase unit {unit}: phase {phase:03x} detected {detected}")
                hits.append(phase)
        d.wr(R.REG_FI_PHASE_MASK + 4 * 15, 0)
        d.disarm_trigger(self.FAULT_TRIGGER)
        if len(hits) != 1:
            self.error(f"calibrate_phase unit {unit}: detections at {len(hits)} phases, expected exactly 1")
            return
        model = self.CAL_MASK_PHASE[unit]
        self.phase_delta = (hits[0] - model + 256) % 512 - 256
        old_ofs = d.rd(R.REG_FI_PHASE_OFS)
        new_ofs = (old_ofs + self.phase_delta) & 0x1FF
        d.wr(R.REG_FI_PHASE_OFS, new_ofs)
        print(f"[FORTE] calibrate_phase unit {unit}: site at mask phase {hits[0]:03x}, model {model:03x}: "
              f"delta {self.phase_delta}, FI_PHASE_OFS {old_ofs} -> {new_ofs}")

    def fault_trial(self, phase: int, release: bytes, text: bytes) -> None:
        """One fault_inject pulse at the chip phase, started when the console
        prints text; the program is told to begin with 'g' and released with
        the release bytes once the pulse is over."""
        d = self.dev
        d.fault_pattern(R.FI_SINGLE, phases=[phase], start=False)
        d.set_match(1, text)
        d.arm_trigger(self.FAULT_TRIGGER, R.TRIG_SRC_MATCH1, R.TRIG_FAULT, repeat=True)
        fired = d.trigger_fired(self.FAULT_TRIGGER)
        d.uart_send(b"g")
        if not self.run_cycles(10_000_000, until=lambda: d.trigger_fired(self.FAULT_TRIGGER) != fired
                               and not d.fault_running()):
            self.error(f"fault_trial: the pulse at phase {phase:03x} never ran")
            return
        d.disarm_trigger(self.FAULT_TRIGGER)
        d.uart_send(release)
        print(f"[FORTE] fault_trial: pulse at phase {phase:03x} done, released")

    def target_site(self, unit: int, phase: int, periods: int, counter) -> None:
        """One fe_fault_site.c round with the whole unit armed and the pin high
        only at the phase: counter alone must rise (none: nothing moves) and
        every kernel result must stay right."""
        d = self.dev
        d.fault_pattern(R.FI_PHASE, periods, phases=[phase], start=False)
        d.set_match(1, b"SITE GO")
        d.arm_trigger(self.FAULT_TRIGGER, R.TRIG_SRC_MATCH1, R.TRIG_FAULT, repeat=True)
        fired = d.trigger_fired(self.FAULT_TRIGGER)
        d.uart_send(str(unit).encode())
        if not self.run_cycles(10_000_000, until=lambda: d.trigger_fired(self.FAULT_TRIGGER) != fired
                               and not d.fault_running()):
            self.error(f"target_site: the pattern at phase {phase:03x} never ran")
            return
        d.disarm_trigger(self.FAULT_TRIGGER)
        d.uart_send(b"x")
        line = self.next_console_line(b"SITE d ")
        if line is None:
            self.error(f"target_site: no SITE line for unit {unit} phase {phase:03x}")
            return
        fields = line.split()
        deltas, wrong = [int(x) for x in fields[2:20]], int(fields[21])
        rose = deltas[counter] if counter is not None else 0
        moved = sum(n for i, n in enumerate(deltas) if i != counter)
        print(f"[FORTE] target_site unit {unit} phase {phase:03x}: counter {counter} rose {rose}, "
              f"others {moved}, wrong {wrong}")
        if counter is not None and rose == 0:
            self.error(f"target_site unit {unit} phase {phase:03x}: counter {counter} never rose")
        if moved:
            self.error(f"target_site unit {unit} phase {phase:03x}: other counters moved by {moved}")
        if wrong:
            self.error(f"target_site unit {unit} phase {phase:03x}: {wrong} wrong kernel results")

    # The latencies scan_session tries, from fbu_scan driving io[7:0] to it
    # capturing the chip's scan_q on io[15:8].
    SCAN_LATENCIES = range(1, 7)

    def scan_session(self, length: int, seed: int) -> None:
        """scan_session <len> <seed>: one test-mode session with a seeded random
        pattern, scan_en high three cycles in four.  The chip's stub loads
        scan_q from io[7:0] while scan_en is high and drives it on io[15:8], so
        the capture must be the pattern some fixed latency late, held while
        scan_en was low; exactly one latency may fit."""
        rng = random.Random(seed)
        pattern = [(rng.randrange(256), rng.randrange(4) != 0) for _ in range(length)]
        captured = self.dev.scan_session(pattern)

        def expected(latency):
            q = None
            out = []
            for j in range(length):
                if j >= latency and pattern[j - latency][1]:
                    q = pattern[j - latency][0]
                out.append(q)
            return out

        fits = [l for l in self.SCAN_LATENCIES
                if all(e is None or e == c for e, c in zip(expected(l), captured))]
        if len(fits) != 1:
            self.error(f"scan_session: capture fits latencies {fits}; first entries {captured[:12]}")
            return
        print(f"[FORTE] scan_session: {length} cycles, capture matches at latency {fits[0]}")

    def next_console_line(self, prefix: bytes, budget: int = 10_000_000):
        """The next whole console line starting with prefix, after console_cursor."""
        def complete():
            start = self.console.find(prefix, self.console_cursor)
            return start >= 0 and self.console.find(b"\n", start) >= 0

        if not self.run_cycles(budget, until=complete):
            return None
        start = self.console.find(prefix, self.console_cursor)
        end = self.console.find(b"\n", start)
        self.console_cursor = end + 1
        return self.console[start:end].decode("latin-1")

    # fe_fault_pin.c's per-round lines: "FI unit <u> PASS|FAIL d <18 deltas> ...".
    # A detect counter may not exceed what the pin let through, per 512-cycle
    # period of pin-high: one count per site event for the FT units (ALU 6
    # sites, CMP 2), two for the register file (both read ports),
    # five for the pipeline registers, three for the D$ (tag, line, repaired).
    FI_ROUND_DETECT = {0: (8, 6), 1: (10, 2), 2: (12, 1), 3: (14, 1), 4: (0, 2), 5: (2, 5), 6: (6, 3)}

    def check_fi_rounds(self, periods: int) -> None:
        rounds = [l.split() for l in self.console.decode("latin-1").splitlines() if l.startswith("FI unit ")]
        if len(rounds) != len(self.FI_ROUND_DETECT):
            self.error(f"check_fi_rounds: {len(rounds)} rounds reported, expected {len(self.FI_ROUND_DETECT)}")
        total_detected = 0
        for r in rounds:
            unit, verdict, deltas = int(r[2]), r[3], [int(x) for x in r[5:23]]
            counter, per_event = self.FI_ROUND_DETECT[unit]
            bound = periods * per_event
            total_detected += deltas[counter]
            print(f"[FORTE] FI unit {unit}: {verdict}, detect counter {counter} rose {deltas[counter]} (bound {bound})")
            if verdict != "PASS":
                self.error(f"fe_fault_pin unit {unit} failed: {' '.join(r)}")
            if deltas[counter] > bound:
                self.error(f"fe_fault_pin unit {unit}: counter {counter} rose {deltas[counter]}, "
                           f"more than the {bound} the pin allowed")
        if periods > 0 and total_detected == 0:
            self.error("check_fi_rounds: the pin was high and no unit detected a fault")

    def verdict(self, result: str) -> str:
        self.finish()
        if result == "PASS" and self.total_errors():
            result = f"FAIL {self.total_errors()} checker errors"
        return result
