#!/usr/bin/env python3
"""Clock period and pin I/O delays for the pin bench, from the SDC PnR signed off with.

    sdc_delays.py <file.sdc> [--sh | --plusargs max|min] [--env K=V ...]

Reads create_clock, set_input_delay / set_output_delay (-max/-min) and
set_false_path, for the forte_top ports, and turns them into the pin bench's
timing (hvl/pin/pin_tb.sv and its agents):

  CLK_PS                 create_clock -period on core_clk
  IN_MAX_PS / IN_MIN_PS  set_input_delay -max / -min over io_in, ready, rvalid:
                         the bench launches EVERY input that long after the
                         core_clk posedge -- IN_MAX in the max (setup) corner,
                         IN_MIN in the min (hold) corner
  OUT_MAX_*_PS / OUT_MIN_*_PS
                         set_output_delay -max / -min, LINK = io_out, req, wr
                         and SLOW = uart_tx, status: the pad window
                         (hvl/pin/pin_cycle_trace.sv) and the sample points
                         T - OUT_MAX of the link and UART agents

It REFUSES (exit 1, with the reason) rather than guess:
  - no create_clock on core_clk, or more than one
  - a link port (io_in, ready, rvalid, io_out, req, wr) or a slow output
    (uart_tx, status) with no -max or no -min delay (and no false path)
  - an input with neither a delay nor set_false_path -from
  - delays against a clock that is not core_clk's (a virtual clock is accepted
    only with the same period and waveform), or with -clock_fall,
    -reference_pin, or a generated clock
  - IN_MIN < 0 (the bench launches after the edge), IN_MAX >= T/2 (inbound
    link pins are captured on the NEGEDGE: forte_link_phy.sv), OUT_MAX >= T,
    an OUT_MIN that would let an output change before the other group's
    sample point, or a link sample point T - OUT_MAX not after IN_MAX (the
    bench's FPGA model samples, then launches at the next edge)
  - any Tcl it cannot evaluate in a command that names one of these ports.

Default output is a human summary; --sh prints shell assignments, --plusargs
prints the bench plusargs for one corner.  Tcl variables, [expr], [getenv]
(from the environment or --env), [get_ports], [get_clocks], [all_inputs],
[all_outputs], [remove_from_collection], [list] and set_units -time are
understood.  Times are in the SDC's time unit (ns unless set_units says).
"""
import ast
import operator
import os
import re
import sys

LINK_W = 8
INPUTS = (["core_clk", "rst_n"] + [f"io_in[{i}]" for i in range(LINK_W)] +
          ["ready", "rvalid", "irq[0]", "irq[1]", "uart_rx", "test_mode", "scan_en", "fault_inject"])
OUTPUTS = ([f"io_out[{i}]" for i in range(LINK_W)] + ["req", "clk_out", "wr", "uart_tx", "status"])
PORTS = INPUTS + OUTPUTS
LINK_IN = [f"io_in[{i}]" for i in range(LINK_W)] + ["ready", "rvalid"]
LINK_OUT = [f"io_out[{i}]" for i in range(LINK_W)] + ["req", "wr"]
SLOW_OUT = ["uart_tx", "status"]
OTHER_IN = ["rst_n", "irq[0]", "irq[1]", "uart_rx", "test_mode", "scan_en", "fault_inject"]
CLOCK_PORT = "core_clk"


class SdcError(Exception):
    pass


class Ports(tuple):
    """A collection of port names (what get_ports returns)."""


class Clocks(tuple):
    """A collection of clock names (what get_clocks returns)."""


class Opaque(str):
    """Something we do not model (get_pins, get_cells, ...): fine unless used on a port."""


# ---- a small Tcl reader --------------------------------------------------------
def split_commands(text):
    """Commands as lists of raw words, with line numbers.  Handles comments,
    backslash-newline, ';', braces, brackets and quotes."""
    text = re.sub(r"\\\r?\n\s*", " ", text)
    cmds, words, cur = [], [], []
    depth_b = depth_k = 0
    inq = False
    line = 1
    start_line = 1
    i, n = 0, len(text)
    at_cmd_start = True
    while i < n:
        c = text[i]
        if at_cmd_start and not words and not cur and c == "#" and depth_b == depth_k == 0 and not inq:
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "\\" and i + 1 < n:
            cur.append(text[i:i + 2]); i += 2; continue
        if c == "\n":
            line += 1
        if depth_b == 0 and depth_k == 0 and not inq:
            if c in " \t\r":
                if cur:
                    words.append("".join(cur)); cur = []
                i += 1; continue
            if c in "\n;":
                if cur:
                    words.append("".join(cur)); cur = []
                if words:
                    cmds.append((start_line, words))
                words = []
                at_cmd_start = True
                i += 1
                start_line = line
                continue
        if not words and not cur:
            start_line = line
        at_cmd_start = False
        if c == "{" and not inq and depth_k == 0:
            depth_b += 1
        elif c == "}" and not inq and depth_k == 0 and depth_b:
            depth_b -= 1
        elif c == "[" and depth_b == 0:
            depth_k += 1
        elif c == "]" and depth_b == 0 and depth_k:
            depth_k -= 1
        elif c == '"' and depth_b == 0 and depth_k == 0:
            inq = not inq
        cur.append(c)
        i += 1
    if cur:
        words.append("".join(cur))
    if words:
        cmds.append((start_line, words))
    return cmds


_BINOPS = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
           ast.Div: operator.truediv, ast.Mod: operator.mod, ast.Pow: operator.pow}


def safe_expr(s):
    def ev(node):
        if isinstance(node, ast.Expression):
            return ev(node.body)
        if isinstance(node, ast.Num):                       # Python < 3.8
            return node.n
        if isinstance(node, getattr(ast, "Constant", ())) and isinstance(node.value, (int, float)):
            return node.value
        if isinstance(node, ast.BinOp) and type(node.op) in _BINOPS:
            return _BINOPS[type(node.op)](ev(node.left), ev(node.right))
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.USub, ast.UAdd)):
            v = ev(node.operand)
            return -v if isinstance(node.op, ast.USub) else v
        raise SdcError(f"expr: cannot evaluate '{s}'")
    try:
        return ev(ast.parse(s.strip(), mode="eval"))
    except SyntaxError:
        raise SdcError(f"expr: cannot evaluate '{s}'")


def glob_to_re(p):
    out = []
    i = 0
    while i < len(p):
        c = p[i]
        if c == "\\" and i + 1 < len(p):
            out.append(re.escape(p[i + 1])); i += 2; continue
        out.append(".*" if c == "*" else "." if c == "?" else re.escape(c))
        i += 1
    return re.compile("^" + "".join(out) + "$")


def match_ports(patterns, pool):
    res = []
    for p in patterns:
        rx = glob_to_re(p)
        hit = [q for q in pool if rx.match(q) or rx.match(q.split("[")[0])]
        if not hit:
            raise SdcError(f"get_ports '{p}' matches no forte_top port")
        res += [h for h in hit if h not in res]
    return Ports(res)


def fmt_num(v):
    return f"{v:g}"


TCL_CONTROL = {"if", "for", "foreach", "while", "proc", "source", "eval", "uplevel", "upvar", "array",
               "namespace", "switch", "catch", "return", "global", "variable", "lappend", "dict"}
FLAT_SDC_HINT = ("give the SDC that PnR wrote out (write_sdc: flat commands, literal values), "
                 "not a Tcl constraints script")


class Sdc:
    def __init__(self, env):
        self.env = env
        self.vars = {}
        self.time_scale = 1.0          # SDC time unit in ns
        self.clocks = {}               # name -> dict(period, waveform, ports, generated)
        self.in_dly = {}               # port -> {"max": [(v, clk)], "min": [...]}
        self.out_dly = {}
        self.fp_from, self.fp_to = set(), set()
        self.ignored = {}
        self.notes = []
        self.line = 0
        self.depth = 0                 # inside [command substitution]

    # -- substitution ---------------------------------------------------------
    def subst(self, w):
        """Evaluate one word.  Returns str, or a Ports/Clocks/Opaque object when
        the whole word is a single command substitution."""
        if w.startswith("{") and w.endswith("}"):
            return w[1:-1]
        if w.startswith('"') and w.endswith('"') and len(w) >= 2:
            w = w[1:-1]
        if w.startswith("[") and w.endswith("]") and self._matching(w) == len(w) - 1:
            return self.call(w[1:-1])
        m = re.fullmatch(r"\$(?:\{([^}]*)\}|([A-Za-z0-9_:]+))", w)
        if m:                                  # a bare $var keeps a collection a collection
            name = m.group(1) or m.group(2)
            if name not in self.vars:
                raise SdcError(f"unknown variable ${name}")
            return self.vars[name]
        out, i = [], 0
        while i < len(w):
            c = w[i]
            if c == "\\" and i + 1 < len(w):
                out.append(w[i + 1]); i += 2; continue
            if c == "$":
                m = re.match(r"\$(\{([^}]*)\}|([A-Za-z0-9_:]+))", w[i:])
                if m:
                    name = m.group(2) or m.group(3)
                    if name not in self.vars:
                        raise SdcError(f"unknown variable ${name}")
                    v = self.vars[name]
                    out.append(" ".join(v) if isinstance(v, tuple) else str(v))
                    i += m.end(); continue
            if c == "[":
                j = self._matching(w, i)
                v = self.call(w[i + 1:j])
                out.append(" ".join(v) if isinstance(v, tuple) else str(v))
                i = j + 1; continue
            out.append(c); i += 1
        return "".join(out)

    def _matching(self, w, i=0):
        d = 0
        for j in range(i, len(w)):
            if w[j] == "[":
                d += 1
            elif w[j] == "]":
                d -= 1
                if d == 0:
                    return j
        raise SdcError(f"unbalanced [ in {w}")

    def call(self, text):
        cmds = split_commands(text)
        if len(cmds) != 1:
            raise SdcError(f"cannot evaluate [{text}]")
        self.depth += 1
        try:
            return self.run(cmds[0][1])
        finally:
            self.depth -= 1

    def tcl_list(self, s):
        """Words of a Tcl list (braces removed)."""
        if isinstance(s, tuple):
            return list(s)
        return [x[1:-1] if x.startswith("{") and x.endswith("}") else x for x in split_words(s)]

    # -- commands ---------------------------------------------------------------
    def run(self, raw):
        name = raw[0]
        if name == "set" and len(raw) == 3:
            self.vars[raw[1]] = self.subst(raw[2])
            return self.vars[raw[1]]
        if name == "set" and len(raw) == 2:
            return self.vars.get(raw[1], "")
        if name == "expr":
            return fmt_num(safe_expr(" ".join(str(self.subst(w)) for w in raw[1:])))
        if name == "getenv":
            k = str(self.subst(raw[1]))
            if k not in self.env:
                raise SdcError(f"getenv {k}: not set (pass --env {k}=...)")
            return self.env[k]
        if name == "list":
            vals = [self.subst(w) for w in raw[1:]]
            if vals and all(isinstance(v, Ports) for v in vals):
                return Ports(dict.fromkeys(p for v in vals for p in v))
            if vals and all(isinstance(v, Clocks) for v in vals):
                return Clocks(dict.fromkeys(c for v in vals for c in v))
            return " ".join(" ".join(v) if isinstance(v, tuple) else str(v) for v in vals)
        if name == "get_ports":
            args = [self.subst(w) for w in raw[1:]]
            pats = []
            for a in args:
                if isinstance(a, str) and a.startswith("-"):
                    if a in ("-quiet", "-nocase"):
                        continue
                    raise SdcError(f"get_ports {a}: option not supported")
                pats += self.tcl_list(a)
            return match_ports(pats, PORTS)
        if name == "get_clocks":
            args = [a for a in (self.subst(w) for w in raw[1:]) if not str(a).startswith("-")]
            names = []
            for a in args:
                for p in self.tcl_list(a):
                    rx = glob_to_re(p)
                    hit = [c for c in self.clocks if rx.match(c)]
                    if not hit:
                        raise SdcError(f"get_clocks '{p}': no such clock")
                    names += hit
            return Clocks(names)
        if name == "all_clocks":
            return Clocks(self.clocks)
        if name == "all_inputs":
            return Ports(INPUTS)
        if name == "all_outputs":
            return Ports(OUTPUTS)
        if name == "remove_from_collection":
            a, b = self.subst(raw[1]), self.subst(raw[2])
            if isinstance(a, Ports) and isinstance(b, Ports):
                return Ports(x for x in a if x not in b)
            if isinstance(a, Clocks) and isinstance(b, Clocks):
                return Clocks(x for x in a if x not in b)
            return Opaque("collection")
        if name in ("get_pins", "get_cells", "get_nets", "get_lib_cells", "get_lib_pins", "current_design",
                    "get_designs", "all_registers", "get_object_name"):
            return Opaque(name)
        if name == "set_units":
            self.set_units(raw[1:])
            return ""
        if name == "create_clock":
            self.create_clock(raw[1:], generated=False)
            return ""
        if name == "create_generated_clock":
            self.create_clock(raw[1:], generated=True)
            return ""
        if name in ("set_input_delay", "set_output_delay"):
            self.io_delay(name, raw[1:])
            return ""
        if name == "set_false_path":
            self.false_path(raw[1:])
            return ""
        if name in ("set_max_delay", "set_min_delay", "set_multicycle_path"):
            self.path_exception(name, raw[1:])
            return ""
        # Tcl control flow could hide or condition constraints: never skip it.
        if name in TCL_CONTROL:
            raise SdcError(f"Tcl '{name}' -- {FLAT_SDC_HINT}")
        # An unknown command whose VALUE is used would silently become "".
        if self.depth:
            raise SdcError(f"unknown command '{name}' inside [...] -- {FLAT_SDC_HINT}")
        # Everything else is a constraint the bench does not model (loads,
        # transitions, uncertainty, ...): evaluate its words (so a reference to
        # an unknown variable still fails loudly), list it, and go on.
        for w in raw[1:]:
            try:
                self.subst(w)
            except SdcError:
                pass
        self.ignored[name] = self.ignored.get(name, 0) + 1
        return ""

    def opts(self, args, flags, valued):
        """Split args into options and positionals."""
        o, pos = {}, []
        i = 0
        while i < len(args):
            a = args[i]
            if a in flags:
                o[a] = True; i += 1
            elif a in valued:
                if i + 1 >= len(args):
                    raise SdcError(f"{a} needs a value")
                o[a] = self.subst(args[i + 1]); i += 2
            elif a.startswith("-") and not re.match(r"^-[0-9.]", a):
                raise SdcError(f"option {a} not understood")
            else:
                pos.append(self.subst(a)); i += 1
        return o, pos

    def time(self, v):
        return float(safe_expr(str(v))) * self.time_scale

    def set_units(self, args):
        for i, a in enumerate(args):
            if a == "-time" and i + 1 < len(args):
                m = re.match(r"^([0-9.]*)\s*(ps|ns|us|fs)$", str(self.subst(args[i + 1])).strip())
                if not m:
                    raise SdcError(f"set_units -time {args[i + 1]} not understood")
                k = float(m.group(1) or 1)
                self.time_scale = k * {"fs": 1e-6, "ps": 1e-3, "ns": 1.0, "us": 1e3}[m.group(2)]

    def create_clock(self, args, generated):
        flags = {"-add", "-invert", "-combinational"}
        valued = {"-name", "-period", "-waveform", "-source", "-divide_by", "-multiply_by",
                  "-edges", "-edge_shift", "-master_clock", "-comment"}
        o, pos = self.opts(args, flags, valued)
        ports = []
        for p in pos:
            if isinstance(p, Ports):
                ports += list(p)
            elif isinstance(p, Opaque):
                pass
            elif p:
                ports += list(match_ports(self.tcl_list(p), PORTS))
        name = str(o.get("-name") or (ports[0] if ports else ""))
        if not name:
            raise SdcError("create_clock with neither -name nor a source")
        if generated:
            self.clocks[name] = dict(period=None, waveform=None, ports=ports, generated=True)
            return
        if "-period" not in o:
            raise SdcError(f"create_clock {name}: no -period")
        per = self.time(o["-period"])
        wf = tuple(self.time(x) for x in self.tcl_list(o["-waveform"])) if "-waveform" in o else (0.0, per / 2)
        self.clocks[name] = dict(period=per, waveform=wf, ports=ports, generated=False)

    def io_delay(self, cmd, args):
        flags = {"-max", "-min", "-rise", "-fall", "-clock_fall", "-add_delay", "-level_sensitive",
                 "-network_latency_included", "-source_latency_included"}
        valued = {"-clock", "-reference_pin"}
        o, pos = self.opts(args, flags, valued)
        ports = [p for p in pos if isinstance(p, Ports)]
        vals = [p for p in pos if not isinstance(p, (Ports, Opaque, Clocks))]
        if len(ports) != 1 or len(vals) != 1:
            if any(isinstance(p, Opaque) for p in pos) and not ports:
                self.notes.append(f"line {self.line}: {cmd} on non-port objects ignored")
                return
            raise SdcError(f"{cmd}: expected one delay value and one port collection")
        for bad in ("-clock_fall", "-reference_pin", "-level_sensitive"):
            if bad in o:
                raise SdcError(f"{cmd} {bad} on {', '.join(ports[0])}: not supported by the bench")
        clk = o.get("-clock")
        if isinstance(clk, Clocks):
            if len(clk) != 1:
                raise SdcError(f"{cmd}: -clock must name one clock")
            clk = clk[0]
        if clk is None:
            raise SdcError(f"{cmd} on {', '.join(ports[0])}: no -clock")
        clk = str(clk)
        if clk not in self.clocks:
            raise SdcError(f"{cmd}: unknown clock {clk}")
        v = self.time(vals[0])
        kinds = [k for k in ("max", "min") if f"-{k}" in o] or ["max", "min"]
        table = self.in_dly if cmd == "set_input_delay" else self.out_dly
        for p in ports[0]:
            d = table.setdefault(p, {"max": [], "min": []})
            for k in kinds:
                if "-add_delay" not in o and not ("-rise" in o or "-fall" in o):
                    d[k] = []          # without -add_delay a new value replaces the old
                d[k].append((v, clk, self.line))

    def false_path(self, args):
        valued = {"-from", "-to", "-through", "-rise_from", "-fall_from", "-rise_to", "-fall_to", "-comment"}
        o, pos = self.opts(args, {"-setup", "-hold", "-rise", "-fall"}, valued)
        if "-setup" in o or "-hold" in o:
            self.notes.append(f"line {self.line}: set_false_path {'-setup' if '-setup' in o else '-hold'} "
                              f"treated as a full false path")
        for k, s in (("-from", self.fp_from), ("-to", self.fp_to)):
            v = o.get(k)
            if isinstance(v, str) and not isinstance(v, Opaque) and v.strip():
                try:                       # plain names resolve like get_ports
                    v = match_ports(self.tcl_list(v), PORTS)
                except SdcError:
                    v = None               # cells or pins: not ours
            if isinstance(v, Ports):
                s.update(v)

    def path_exception(self, cmd, args):
        valued = {"-from", "-to", "-through", "-rise_from", "-fall_from", "-rise_to", "-fall_to", "-comment"}
        try:
            o, pos = self.opts(args, {"-setup", "-hold", "-start", "-end", "-ignore_clock_latency",
                                      "-rise", "-fall"}, valued)
        except SdcError:
            self.ignored[cmd] = self.ignored.get(cmd, 0) + 1
            return
        for k in ("-from", "-to", "-through"):
            v = o.get(k)
            if isinstance(v, Ports) and set(v) & set(LINK_IN + LINK_OUT + SLOW_OUT):
                raise SdcError(f"{cmd} {k} {', '.join(v)}: an exception on a link/slow port; the bench "
                               f"models set_input/output_delay only -- resolve it by hand")
        self.ignored[cmd] = self.ignored.get(cmd, 0) + 1

    def load(self, text):
        for line, words in split_commands(text):
            self.line = line
            try:
                self.run(words)
            except SdcError as e:
                raise SdcError(f"line {line}: {e}")


def split_words(s):
    cmds = split_commands(s.replace("\n", " "))
    return cmds[0][1] if cmds else []


# ---- the bench's numbers --------------------------------------------------------
def derive(sdc):
    errs, warns = [], []
    src = [n for n, c in sdc.clocks.items() if CLOCK_PORT in c["ports"]]
    if len(src) != 1:
        raise SdcError(f"need exactly one create_clock on {CLOCK_PORT}, found {len(src)}: {src}")
    cname = src[0]
    clk = sdc.clocks[cname]
    T = clk["period"]
    if clk["waveform"] != (0.0, T / 2):
        errs.append(f"clock {cname} waveform {clk['waveform']} is not 50% duty from 0: the bench's clock is")

    def ok_clock(c, what):
        if c == cname:
            return True
        k = sdc.clocks[c]
        if k["generated"]:
            errs.append(f"{what}: relative to generated clock {c} -- not modelled")
            return False
        if k["ports"]:
            errs.append(f"{what}: relative to clock {c} on {k['ports']}, not {cname}")
            return False
        if abs(k["period"] - T) > 1e-9 or k["waveform"] != clk["waveform"]:
            errs.append(f"{what}: virtual clock {c} differs from {cname} (period {k['period']} vs {T})")
            return False
        warns.append(f"delays relative to virtual clock {c} taken as {cname} (same period and waveform)")
        return True

    def bound(table, ports, kind, agg, group):
        vals = []
        for p in ports:
            d = table.get(p, {}).get(kind, [])
            if not d:
                return None, p
            for v, c, ln in d:
                if ok_clock(c, f"{group} {p} (line {ln})"):
                    vals.append(v)
        return agg(vals), None

    res = {"CLK_NAME": cname, "T": T}
    # -- inputs --
    for k, agg in (("max", max), ("min", min)):
        v, missing = bound(sdc.in_dly, LINK_IN, k, agg, "input")
        if missing:
            errs.append(f"link input {missing} has no set_input_delay -{k}")
        res[f"IN_{k.upper()}"] = v
    for p in OTHER_IN:
        if p in sdc.fp_from:
            continue
        d = sdc.in_dly.get(p)
        if not d or not (d["max"] or d["min"]):
            errs.append(f"input {p} has neither set_input_delay nor set_false_path -from")
        else:
            for k in ("max", "min"):
                for v, c, ln in d[k]:
                    ok_clock(c, f"input {p} (line {ln})")
            warns.append(f"input {p} has its own delay ({', '.join(fmt_num(v) for v, _, _ in d['max'] + d['min'])} ns) "
                         f"but the bench launches every input at the link-input delay")
    # -- outputs --
    for grp, ports in (("LINK", LINK_OUT), ("SLOW", SLOW_OUT)):
        if all(p in sdc.fp_to for p in ports):
            warns.append(f"{'/'.join(ports)}: false path -to, no output window checked")
            res[f"OUT_MAX_{grp}"] = res[f"OUT_MIN_{grp}"] = None
            continue
        for k, agg in (("max", max), ("min", min)):
            v, missing = bound(sdc.out_dly, ports, k, agg, "output")
            if missing:
                errs.append(f"output {missing} has no set_output_delay -{k}")
            res[f"OUT_{k.upper()}_{grp}"] = v
    if "clk_out" in sdc.out_dly:
        warns.append("clk_out has an output delay: the bench reports clk_out's insertion delay but does not check it")
    for p in LINK_IN:
        if p in sdc.fp_from:
            errs.append(f"link input {p} is a false path: its negedge capture would go untimed")
    for p in LINK_OUT:
        if p in sdc.fp_to and not all(q in sdc.fp_to for q in LINK_OUT):
            errs.append(f"link output {p} is a false path")
    if errs:
        raise SdcError("\n  ".join(dict.fromkeys(errs)))

    # -- sanity of the numbers against the bench's model ----------------------------
    imax, imin = res["IN_MAX"], res["IN_MIN"]
    if imin < 0:
        errs.append(f"input delay -min {fmt_num(imin)} ns < 0: the bench launches inputs after the core_clk edge")
    if imax >= T / 2:
        errs.append(f"input delay -max {fmt_num(imax)} ns >= T/2 = {fmt_num(T / 2)} ns: io_in/ready/rvalid are "
                    f"captured on the core_clk NEGEDGE (forte_link_phy.sv), which leaves no setup time")
    if imin > imax:
        errs.append(f"input delay -min {fmt_num(imin)} > -max {fmt_num(imax)}")
    groups = [g for g in ("LINK", "SLOW") if res[f"OUT_MAX_{g}"] is not None]
    for g in groups:
        omax, omin = res[f"OUT_MAX_{g}"], res[f"OUT_MIN_{g}"]
        if omax >= T:
            errs.append(f"{g} output delay -max {fmt_num(omax)} ns >= T = {fmt_num(T)} ns")
        if omax <= 0:
            errs.append(f"{g} output delay -max {fmt_num(omax)} ns <= 0: no sample point before the next edge")
        if omin > omax:
            errs.append(f"{g} output delay -min {fmt_num(omin)} > -max {fmt_num(omax)}")
        elif omin > 0:
            # A positive -min says the board's hold ends before the next edge E.
            # What E launches reaches the pad after E, so the hold side is met
            # by construction, and the SDC's whole requirement is "quiet over
            # (E - max, E)": exactly the window for -min 0.  Use that.
            warns.append(f"{g} output delay -min {fmt_num(omin)} ns is positive (the board's hold ends before the "
                         f"edge): checked as -min 0, i.e. no output change from {fmt_num(omax)} ns before the "
                         f"core_clk edge until the edge")
            res[f"OUT_MIN_{g}"] = 0.0
    if groups:
        first_settle = min(res[f"OUT_MAX_{g}"] for g in groups)
        for g in groups:
            if res[f"OUT_MIN_{g}"] >= first_settle:
                errs.append(f"{g} output delay -min {fmt_num(res[f'OUT_MIN_{g}'])} ns >= the smallest -max "
                            f"{fmt_num(first_settle)} ns: that group may change before the trace samples it")
        res["TRACE_SAMPLE"] = T - first_settle
    else:
        res["TRACE_SAMPLE"] = 0.75 * T
    # The link agent decides at its sample point and launches at the next
    # edge + IN_MAX.  The golden was made with the sample point after the
    # launch; the other order makes the agent answer a cycle earlier.
    if res["OUT_MAX_LINK"] is not None and T - res["OUT_MAX_LINK"] <= imax:
        errs.append(f"link sample point T - output_delay(max) = {fmt_num(T - res['OUT_MAX_LINK'])} ns is not after "
                    f"the input launch {fmt_num(imax)} ns: the bench's FPGA model needs to sample after it launches")
    if errs:
        raise SdcError("\n  ".join(dict.fromkeys(errs)))
    if clk.get("ports") and len(sdc.clocks) > 1:
        others = [c for c in sdc.clocks if c != cname]
        warns.append(f"other clocks defined: {others}")
    return res, list(dict.fromkeys(warns))


def ps(v):
    return int(round(v * 1000))


def plusargs(res, corner):
    T = res["T"]
    a = [f"+CLK_PS={ps(T)}",
         f"+FPGA_TCO_PS={ps(res['IN_MAX'] if corner == 'max' else res['IN_MIN'])}",
         f"+PIN_TRACE_SAMPLE_PS={ps(res['TRACE_SAMPLE'])}"]
    if res["OUT_MAX_LINK"] is not None:
        a += ["+FPGA_SAMPLE_REF=core", f"+FPGA_SAMPLE_PS={ps(T - res['OUT_MAX_LINK'])}",
              f"+OUT_MAX_LINK_PS={ps(res['OUT_MAX_LINK'])}", f"+OUT_MIN_LINK_PS={ps(res['OUT_MIN_LINK'])}"]
    if res["OUT_MAX_SLOW"] is not None:
        a += [f"+UART_SAMPLE_PS={ps(T - res['OUT_MAX_SLOW'])}",
              f"+OUT_MAX_SLOW_PS={ps(res['OUT_MAX_SLOW'])}", f"+OUT_MIN_SLOW_PS={ps(res['OUT_MIN_SLOW'])}"]
    return a


def summary(res, warns, sdc, path):
    T = res["T"]
    L = [f"SDC {path}",
         f"  clock          {res['CLK_NAME']} on {CLOCK_PORT}: period {fmt_num(T)} ns",
         f"  inputs         io_in/ready/rvalid launched {fmt_num(res['IN_MAX'])} ns (max corner) / "
         f"{fmt_num(res['IN_MIN'])} ns (min corner) after core_clk; negedge capture at {fmt_num(T / 2)} ns"]
    for g, names in (("LINK", "io_out/req/wr"), ("SLOW", "uart_tx/status")):
        if res[f"OUT_MAX_{g}"] is None:
            L.append(f"  outputs {g:5s}  {names}: false path, unchecked")
        else:
            omax, omin = res[f"OUT_MAX_{g}"], res[f"OUT_MIN_{g}"]
            hold = (f"held until {fmt_num(-omin)} ns after the next edge" if omin < 0 else
                    f"held until {fmt_num(omin)} ns before the next edge" if omin > 0 else "held until the next edge")
            L.append(f"  outputs {g:5s}  {names}: settled by {fmt_num(T - omax)} ns after the edge "
                     f"(-max {fmt_num(omax)}), {hold} (-min {fmt_num(omin)})")
    L.append(f"  trace sample   {fmt_num(res['TRACE_SAMPLE'])} ns after the edge")
    fp = sorted(sdc.fp_from & set(INPUTS))
    if fp:
        L.append(f"  false path     from {', '.join(fp)}")
    if sdc.ignored:
        L.append("  ignored        " + ", ".join(f"{k} x{v}" for k, v in sorted(sdc.ignored.items())))
    if "set_clock_latency" in sdc.ignored:
        L.append("  WARNING        set_clock_latency is not modelled: the bench's core_clk pin is the delays' reference")
    for w in warns + sdc.notes:
        L.append(f"  WARNING        {w}")
    return "\n".join(L)


def main(argv):
    env = dict(os.environ)
    args, mode, corner = [], "summary", None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--env":
            k, _, v = argv[i + 1].partition("="); env[k] = v; i += 2; continue
        if a == "--sh":
            mode = "sh"
        elif a == "--plusargs":
            mode, corner = "plusargs", argv[i + 1]; i += 1
            if corner not in ("max", "min"):
                print("--plusargs takes max or min", file=sys.stderr); return 2
        elif a.startswith("-"):
            print(__doc__); return 2
        else:
            args.append(a)
        i += 1
    if len(args) != 1:
        print(__doc__); return 2
    sdc = Sdc(env)
    try:
        with open(args[0]) as f:
            sdc.load(f.read())
        res, warns = derive(sdc)
    except (SdcError, OSError) as e:
        print(f"sdc_delays: {args[0]}: REFUSED\n  {e}", file=sys.stderr)
        return 1
    if mode == "sh":
        print(f"CLK_NAME={res['CLK_NAME']}")
        print(f"CLK_PS={ps(res['T'])}")
        for k in ("IN_MAX", "IN_MIN", "OUT_MAX_LINK", "OUT_MIN_LINK", "OUT_MAX_SLOW", "OUT_MIN_SLOW", "TRACE_SAMPLE"):
            print(f"{k}_PS={'' if res[k] is None else ps(res[k])}")
        print(f"PLUSARGS_MAX='{' '.join(plusargs(res, 'max'))}'")
        print(f"PLUSARGS_MIN='{' '.join(plusargs(res, 'min'))}'")
    elif mode == "plusargs":
        print(" ".join(plusargs(res, corner)))
    else:
        print(summary(res, warns, sdc, args[0]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
