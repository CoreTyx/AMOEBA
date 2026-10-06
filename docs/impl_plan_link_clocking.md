# Link Clocking: Three Architectures

**Rev 0.2 · 2026-10-02 · DECIDED: Option 3 + `clk_out`, training removed, loopback deferred**

> **Decisions (2026-10-02).**
> 1. **Option 3** — separate link clock domain with async FIFOs (§4), using
>    OpenTitan `prim_fifo_async` (§4.2). Chosen on
>    *robustness*, not frequency: the packaging is non-standard, so pad and
>    package parasitics — and the uncertainty on them — are uncharacterised.
>    Shrinking the capture domain buys margin that does not depend on knowing
>    those numbers. The frequency decoupling in §4.4 is then a second dividend
>    rather than the justification.
> 2. **`clk_out`** (§6), so the FPGA consumes outbound data source-synchronously
>    and constrains its input delay as a *skew* against `clk_out` (ASIC pad +
>    package + board + FPGA pin) rather than an absolute flight time. It
>    forwards the **link** clock — see §6.1.
> 3. **Training removed** (§7). `hdl/forte_link_train.sv` is deleted; the gate
>    moves to the FPGA.
> 4. **Loopback deferred** (§7.2), pending the DFT/debug discussion: `io[15:0]`
>    currently doubles as the scan/debug port, so loopback's mode encoding and
>    the scan-pin proposal in §11 are coupled and must be settled together.
>
> Option 2 (§3) is therefore superseded for the inbound path — Option 3
> subsumes it — but the early-tap *concept* still governs where `clk_out` is
> tapped from.

The off-chip link (`docs/top_level_plan.md` §4, `hdl/forte_link_master.sv`)
currently shares one clock with the core and compensates for on-die clock-tree
delay by capturing inbound pins on the falling edge. That costs half a period
of setup budget and caps the link at ~83 MHz by §6's own arithmetic — **below
the 100 MHz `options.json` already targets.** This document compares three ways
out and names the one decision that picks between them.

## 1. The problem, precisely

Matched FMC traces get `clk` and `io[15:0]` to the ASIC's *pads* at the same
instant. They do not arrive at the *flop* together:

| Signal | Pad → capture flop | Delay |
|---|---|---|
| `io[15:0]` | pad → local route → flop **D** | ~0.3–0.5 ns |
| `clk` | pad → buffer → **whole clock tree** → flop **CK** | *ins* ≈ 1–2 ns |

The asymmetry is *inside the die*, so no amount of board-level trace matching
touches it. The clock tree is deep because it balances ~50k flops across 1 mm².

Consequences, with the board term cancelled on matched traces:

- **Hold (FPGA → ASIC).** Violated when `Tco_fpga(min) + trace < ins(max)`.
  With Tco 1.5–3 ns and *ins* 1–2 ns ±30–50 % over PVT these are the same size:
  it is a coin flip you cannot call before parts exist.
- **Setup (ASIC → FPGA).** Needs `T > ins + Tco + trace + Tsu`. *ins* eats the
  budget and the FPGA has no visibility into it.

*ins* is a **manufactured quantity**. Every option below is a different answer
to "how do we stop caring what it turns out to be."

## 2. Option 1 — single domain, negedge capture (status quo)

`hdl/forte_link_master.sv:94-95`. Inbound pins are captured on the falling
edge, then re-registered on the rising edge.

This is the minimal correct structure for a **same-frequency, static-unknown-
phase** boundary: a 180° phase-compensating capture followed by a retiming
stage. Two flops, no pointers, no metastability budget, and the shift tracks
PVT for free because it derives from the same clock. An async FIFO here would
be a heavier version of the same thing that additionally solves a problem that
does not exist (frequency offset) — this is what §6 means by "async FIFOs move
a frequency boundary, not a phase one."

- **Hold margin:** T/2 + *ins* − Tco − trace. Generous.
- **Setup:** T/2 > *ins* + Tco + trace + Tsu ≈ 6 ns → **T > 12 ns, ~83 MHz.**
- **Cost:** 2 flops per inbound bit. Zero pads, zero CDC.
- **Problem: it does not meet the configured 100 MHz target.** At T = 10 ns,
  T/2 = 5 ns < 6 ns. Either `options.json` drops to ≤ 83 MHz or this option is
  already insufficient. This conflict is live and unresolved.

## 3. Option 2 — single domain, early clock-tree tap

Keep one clock and the two-flop structure. Add a **floorplan and CTS
constraint**: the ~19 inbound capture flops are placed next to the pads and
fed from an *early tap* of the clock tree. The existing posedge second stage
already retimes them into the core domain, so the deliberate skew is free.

Their effective insertion drops from the full-tree 1–2 ns to a local 200–400 ps,
and the arithmetic changes qualitatively:

- **Hold:** needs `Tco(min) + trace > ins_early` = 0.4 ns. Satisfied with
  Tco(min) ≈ 1.5 ns. **Posedge capture becomes safe** — the negedge stage is no
  longer load-bearing and the T/2 setup penalty disappears.
- **Setup:** T > 0.4 + 3 + 1 + 0.3 = **4.7 ns → ~210 MHz** on the I/O.
- **Real ceiling:** link frequency still equals core frequency, so the limit
  becomes the *core's* Fmax, not the I/O's.
- **Cost:** no pads, no CDC, no RTL change. A constraint and a floorplan note.

**This is what fixes the 100 MHz conflict, for free.** It removes the I/O as
the frequency limiter and hands the budget back to the core. What it cannot do
is let the link run *faster than* the core.

Deliverables: a `set_max_skew`/`set_clock_latency` constraint on the inbound
flop group, a pad-adjacent placement region, and a post-CTS report showing the
inbound hold path passing on **posedge** capture (which is the evidence the
negedge stage may be retired).

## 4. Option 3 — two clock domains, async FIFOs

Give the link its own clock domain next to the pads. Cross into the core with
async FIFOs.

The FIFOs are *not* what fixes the timing — a FIFO cannot un-capture a word
sampled at the wrong instant, and its write port is a flop with the same setup
and hold window as any other. What fixes the timing is that **the capture
domain becomes small**: a few hundred flops in a corner of the die has a 2–3
level clock tree (200–400 ps) rather than a 5–8 level one. Same mechanism as
Option 2, reached structurally instead of by constraint.

What Option 3 adds over Option 2 is **frequency decoupling**: the link may run
faster than the core. Since the measured 2.10× boot penalty is *entirely* line
serialization (3.25 M line reads × ~34 cycles at 16 bits/cycle — `top_level_plan.md`
§9), and a narrow bridge beside the pads closes timing far more easily than an
RV64 core does, this is the lever that attacks the real cost.

### 4.1 Structure — two FIFOs, not three

An earlier sketch had three: outbound data, inbound data, and a separate
command/order FIFO. **Collapse the command FIFO into the outbound data FIFO.**

Two independent async FIFOs do not preserve ordering *relative to each other* —
each has its own pointer synchroniser. Push a descriptor to one and its data to
the other and the link side can observe the command before the data is visible.
It is recoverable (write data first, equal synchroniser depths) but that is a
fragile invariant which breaks silently when someone changes one FIFO's depth,
and which a 1:1-ratio simulation will never expose.

```
  core clock domain          |  link clock domain
                             |
  AHB slave front end        |
    descriptor + data   ---> | FIFO out (16b) ---> link FSM ---> pads
                             |                      |  drives dir/req/wr
    read data           <--- | FIFO in  (16b) <--- capture <--- pads
```

- **FIFO out:** one descriptor word (`{wr, size, strb}`), two address
  words, then 4 or 32 data words. Single crossing, ordering free.
- **FIFO in:** read data words, in order. Responses need no tagging.
- **`dir` polarity** falls out of the descriptor the link FSM just popped —
  exactly what `wr_r` does today, delivered across the boundary.
- Depth: one line each way (32 × 16 b = 512 b) plus slack.

### 4.2 FIFO: OpenTitan `prim_fifo_async` (DECIDED 2026-10-02)

Chosen over PULP `common_cells`/`cdc_fifo_gray` and the Cummings SNUG reference
on the grounds that it is already proven through a tapeout, carries formal CDC
properties, and is Apache 2.0. Do not write Gray-pointer logic by hand.

**Confirm the following against the version actually vendored** — the shape is
OpenTitan's standard `prim` convention, but port names and parameter
constraints must be read off the source, not assumed:

- Parameters `Width` and `Depth`; **`Depth` must be a power of two** for the
  Gray-coded pointers.
- Independent clock and reset per side (`clk_wr_i`/`rst_wr_ni`,
  `clk_rd_i`/`rst_rd_ni`), valid/ready on both sides, and occupancy outputs
  (`wdepth_o`/`rdepth_o`) — the occupancy output is load-bearing here, see
  below.
- Crossings use `prim_flop_2sync`, which brings its own SDC expectations.

#### Depth, and why the outbound FIFO must hold a whole transaction

`top_level_plan.md` §4 states the invariant: *"There is no mid-transaction
handshake in either direction, so the ASIC never stalls once started."* The
FPGA has no way to absorb an ASIC underrun — there is no pin for it and adding
one would be a protocol change.

Therefore **the link side must not begin a transaction until the entire thing is
buffered.** For a burst write that is 1 descriptor + 2 address + 32 data = **35
words**, so `Depth = 64` outbound. The start condition is not "descriptor
present" but "descriptor present **and** `rdepth_o >= word_count`", which is why
the occupancy output matters rather than just `rvalid_o`.

Inbound, a burst read delivers 32 words back to back with no backpressure
available, so the FIFO must hold a full line: `Depth = 32` is the arithmetic
minimum and is sufficient only because transactions are strictly one at a time
and the core drains before the next starts. `Depth = 64` costs little and
removes the dependency on that argument.

| FIFO | Direction | Width | Depth | Worst case |
|---|---|---|---|---|
| outbound | core → link | 16 | 64 | burst write: 1 + 2 + 32 = 35 |
| inbound | link → core | 16 | 64 (32 minimum) | burst read: 32 |

Consequence for writes: the core-side front end pulls all eight beats into the
FIFO before the link side transmits, so a burst write pays its fill latency up
front. Writebacks are not latency-critical, and burst *reads* push only 3 words
outbound, so the hot path is unaffected.

#### Integration points that bite

1. **Reset.** Each side needs its own reset, asserted asynchronously but
   released **synchronously in its own domain**. One `rst_n` pad still
   suffices — two `forte_rst_sync` instances, one per clock. A single reset
   released asynchronously to both sides can leave the two pointers mutually
   inconsistent, which is the classic failure of this structure.
2. **SDC.** Pointer synchronisers need `set_false_path` or
   `set_max_delay -datapath_only`, and DC must not optimise across them. Use
   the constraints OpenTitan ships rather than writing them.
3. **Verification.** The regression must sweep **non-integer** clock ratios.
   1:1 and 2:1 hide the crossing bugs that 1:1.37 exposes immediately.
4. **DFT.** Two clock domains means two scan clocks or one shared slow scan
   clock, plus a decision on the FIFO storage array.
5. Do not reimplement full/empty. That is the part that is subtly wrong when
   hand-written, and the reason for picking a proven module.

### 4.3 Where the link clock comes from

There is no PLL on the die (§6), so the link clock is a second clock *input*
pad, also sourced by the FPGA. Both clocks therefore come from one oscillator
and are frequency-related, which keeps the ratio clean and predictable — the
ASIC still treats them as unrelated, which is what the FIFOs are for.

### 4.4 Latency

A crossing is paid each way, roughly 3 cycles per pointer synchronisation. At
link:core ratio *R*, a 64 B line read costs about `41/R + 3` core cycles
against today's 38:

| R | core cycles | vs today |
|---|---|---|
| 1 | 44 | 16 % **worse** |
| 1.2 | ~37 | break-even |
| 2 | 23.5 | 38 % better |
| 4 | 13.3 | 65 % better |

**This option only pays above ~1.2×.** The architecture decision and the
frequency decision are one decision, not two.

### 4.5 Costs

- **+1 pad** for the link clock, **+1 for `clk_out`** → 44 used, 8 spare.
  Power/ground remains spare-pad priority #1 per §3, and the 11 currently
  budgeted are a placeholder that non-standard packaging makes *more* likely to
  grow, not less.
- **Area:** §5 budgets the current bridge at ~400–500 GE. Two line-deep FIFOs
  plus pointers and synchronisers is ~5–10 k GE (less with a RAM macro) — a
  10–20× increase in a block whose stated philosophy was minimality.
- **`TA` stops being a cycle count.** It is sized in *pad output-enable
  switching time*, an absolute duration. `TA = 2` is 40 ns at 50 MHz but 10 ns
  at 200 MHz, possibly shorter than the pad can turn around. It must be
  re-parameterised against the link period. Getting this wrong is a crowbar
  through the pad ring in silicon, not a simulation failure.
- **The abort rule needs re-deriving.** Today the bridge knows when a
  transaction completes because it drives the pins. Once a descriptor is
  queued across a crossing, the core-side half must track outstanding
  transactions, and the `beat_ok`/`htrans_q` reasoning in
  `forte_link_master.sv:120-129` does not survive intact. In-order FIFOs give
  response matching for free, so this is a re-derivation, not a redesign.
- **CDC verification.** §6's "no CDC on the ASIC" is a deliberate
  simplification. Crossings are where tapeouts die.

## 5. Comparison

| | 1: negedge | 2: early tap | 3: two domains |
|---|---|---|---|
| New pads | 0 | 0 | +1 |
| New RTL | none | none | bridge split + 2 FIFOs |
| CDC crossings | 0 | 0 | 2 |
| I/O Fmax | ~83 MHz | ~210 MHz | ~210 MHz link, core independent |
| Meets 100 MHz target | **no** | yes | yes |
| Link faster than core | no | no | **yes** |
| Line read (core cycles) | 38 | 38 | 23.5 at R=2 |
| Bridge area | ~500 GE | ~500 GE | ~5–10 k GE |
| Added tapeout risk | none | negligible | CDC |

## 6. `clk_out` is orthogonal

A forwarded clock from the ASIC (+1 pad) fixes the **ASIC → FPGA** direction in
*all three* options, by making the FPGA's capture clock carry the same *ins* as
the data so it cancels. It also makes *ins* directly measurable: the FPGA reads
the phase of `clk_out` against its own reference and gets the number, instead
of searching for it. That is worth having independently of this decision, and
it replaces the phase-sweep half of training (§7) with arithmetic.

### 6.1 With Option 3, `clk_out` forwards the LINK clock

This matters and is easy to get wrong. The `io` output registers live in the
**link** domain, so `clk_out` must forward the **link** clock. Forwarding the
core clock would have the FPGA capturing link-domain data with a core-domain
clock, which cancels nothing.

Option 3 also makes `clk_out`'s matching constraint nearly free. In Options 1
and 2 it had to be tapped from a leaf of the big core tree, balanced against the
`io` output flops across the die. In Option 3 the `clk_out` driver and the `io`
output flops are both inside the small link domain, a few hundred microns apart
— the skew between them is small by placement rather than by constraint. The
two decisions reinforce each other.

It is also the best bring-up instrument on the chip. Scope `clk_out` and you
know the die is receiving and distributing a clock before anything else has to
work — strictly better than §6's "`status` heartbeat is the clock-alive
indicator", which only moves once the link trains *and* transactions flow.

## 7. What training is actually for — and why it goes away

Three jobs were being run together under one word. Separating them:

| Job | Question | Timing content |
|---|---|---|
| **A. Phase calibration** | *When* do I sample? | all of it |
| **B. Wiring verification** | Is lane 7 bonded? Shorted to lane 8? Did the FMC seat? | none |
| **C. Core-reset gate** | Is it safe to let the core fetch? | none |

**Job A is deletable.** Option 2 or 3 removes it by construction; `clk_out`
reduces what remains to a measurement. The sweeps, the retries, and the
`RETRY_TA` state added in `6ad99fe` all exist only to serve a *search*, and a
search is only needed when *ins* is unknown at run time.

**Job B does not need an LFSR at all.** Two arguments retire it.

*First, a directed memory test covers strictly more.* Write patterns, read
back, compare: that exercises the address path, `req`/`wr` framing,
real `dir` turnarounds, the FPGA's decode and memory, and the abort path. The
LFSR sends no address and tests no turnaround. Walking-ones is also a better
stuck-at pattern than pseudo-random. On coverage the directed test wins.

*Second -- and this is what kills the LFSR -- there is no bootstrap problem.*
The earlier version of this section argued that a directed test must be issued
by something, that the FPGA cannot issue it (the link is ASIC-master-only) and
the core cannot either (`BOOTROM`/`UNCORE_RAM`/`DTIM`/`IROM` are all 0 in
`config_asic.vh`, so every instruction arrives over the link under test). That
reasoning is wrong, because it ignores two facts:

1. **The first transaction is fully deterministic.** `RESET_VECTOR =
   0x8000_0000`, so it is a full-line read with header words `0x8000`, `0x0000`,
   `wr=0`, `dir=1`. The FPGA knows all of it in advance, and knows
   exactly what it loaded at that address.
2. **`rst_n` is under FPGA control.** The FPGA does not need the link proven
   before releasing the core. It releases it, judges the first header, and
   re-asserts `rst_n` within microseconds if the header is wrong -- killing a
   trap storm before it starts.

So the gate survives but moves to the FPGA, where there is a CPU, Python and an
ILA, rather than sitting behind a one-bit `status` pin. The inbound direction is
covered indirectly too: a stuck lane FPGA -> ASIC corrupts an instruction, the
next fetch address is not the expected one, and the FPGA sees that one
transaction later.

### 7.1 What the deterministic check does not cover

Two real gaps remain, and they are what the replacement must address:

- **Lane coverage of the first header is dreadful.** `0x8000` then `0x0000` is
  one lane high and thirty-one bit-positions low. A stuck-at-0 on `io[15]` is
  caught; a stuck-at-0 on `io[3]`, or a short between `io[2]` and `io[3]`, is
  not. Returned instruction data exercises more lanes but uncontrolled -- you
  are relying on the boot image's entropy. This is an excellent *smoke test*,
  not a *wiring verification*.
- **Nothing on the ASIC checks the inbound direction bit-exactly.** The core
  checks it by executing it, which detects corruption only when it yields an
  illegal instruction or a wrong branch, and reports via a trap storm. The
  FPGA's inference from the next fetch address handles gross faults and is weak
  for a marginal lane erroring ~1 in 10^4 bits -- that one boots and crashes
  mysteriously later.

### 7.2 Loopback, not an LFSR

The minimal ASIC-side structure for controlled bidirectional lane coverage is
**loopback**: a test mode in which the ASIC registers its inbound `io` word and
drives it back out on the next cycle, alternating `dir` per cycle.

| | LFSR training | Loopback |
|---|---|---|
| ASIC logic | FSM, 16-bit LFSR, comparator, 3 counters, retry path (~107 lines) | 16 flops, a mux, one control bit |
| Pattern | fixed at tapeout | **anything, chosen at run time by the FPGA** |
| Checking | on the ASIC, reported as 1 bit | fabric/BRAM/Python, fully visible |
| Both directions | yes | yes -- a word that returns correct proves both paths |
| Walking-ones, adjacent-lane shorts, custom BER runs | no | yes |

Strictly less silicon and strictly more capable, because pattern generation and
checking move to the side with memory, a CPU and the debug tooling. Re-runnable
at any time with any pattern, with no new bitstream.

Entry costs no pad: the link is idle while `rst_n` is asserted, so a pin's
meaning can be stolen in that window -- e.g. `rvalid` high at reset release
means "enter loopback". Unambiguous, because nothing else uses `rvalid` then.

### 7.3 Consequence

`hdl/forte_link_train.sv` is deleted, along with the LFSR, the retry path and
the `RETRY_TA` state added in `6ad99fe`. The bus-contention hazard that state
exists to prevent goes with it: no path reclaims the bus mid-transfer any more.
`forte_chip.sv` loses the training/link-master ownership mux and the
`trained`-gated `reset_ext`, and `status` becomes a pure link-activity and
fault indicator.

The replacement, in four parts:

1. **FPGA-side first-header check** -- the deterministic smoke test, plus
   plausibility checks (in range, line-aligned) on every subsequent address.
2. **`rst_n` as the abort** -- the gate, on the FPGA.
3. **Loopback mode** -- controlled lane verification and BER, run before reset
   release on first silicon and whenever wanted afterwards.
4. **A software memory test over the link** once boot works -- the broadest
   coverage of all, and the only one that exercises the abort path.

**Job C is the one that must survive.** `RESET_VECTOR = 0x8000_0000 =
EXT_MEM_BASE`, so the first instruction fetch crosses the link. A broken link
means the fetch returns noise, the core traps, the handler's fetch also returns
noise, and the result is a self-feeding trap storm at millions per second with
nothing pointing at the bus. Without the gate every link fault looks identical
and looks like a core fault. The gate is also basic bring-up hygiene: after
power-on the chip should sit quietly with `status` reporting link state, before
anyone commits to running software.

## 8. Bring-up sequence, concretely

With `clk_out` and §7.3's replacement for training. Nothing on the ASIC
sequences this any more -- the FPGA drives it, which is why each step names an
owner.

| # | Who | What | Duration @50 MHz |
|---|---|---|---|
| 0 | FPGA | Drives `clk` (and `link_clk`), holds `rst_n` low, loads memory | — |
| 1 | FPGA | `clk_out` is already toggling — the clock tree runs regardless of reset. Measure its phase against the reference, derive *ins*, set capture shift (90° off `clk_out`) and launch ODELAY. **No ASIC cooperation; chip still in reset.** | µs |
| 2 | FPGA | Release `rst_n` | — |
| 3 | FPGA | *First silicon / board change only:* assert loopback (`rvalid` high at reset release), drive walking-ones, adjacent-lane and pseudo-random patterns, check what returns. Proves every lane in both directions. Skipped on a known-good board | as long as wanted |
| 4 | FPGA | Release `rst_n` | — |
| 5 | ASIC | `forte_rst_sync` releases, core leaves reset, first fetch issues: `req` 2 cycles, `io = 0x8000, 0x0000`, `wr=0` | ~10 cycles |
| 6 | FPGA | **Check that header against the known expected value.** Wrong → re-assert `rst_n`, report which lanes disagreed | 1 transaction |
| 7 | FPGA | Return the loaded line. Then check every subsequent address for plausibility (in range, line-aligned); a corrupted inbound lane shows up as an unexpected next fetch | continuous |
| 8 | core | Boot proceeds. Early software runs a memory test over the link for the broadest coverage | — |

The ASIC contributes no sequencing at all, which is the point: every judgement
happens on the side with observability. Loopback (step 3) covers the lane
verification the LFSR used to claim; the header check (step 6) covers the gate.

Why no retries anywhere: once *ins* is known from `clk_out` before step 4, a
failure means something structural — an open lane, a shorted pair, a mis-wired
FMC, an unbonded pad. Retrying fixes none of them, and the FPGA is a far better
place to decide what to do next than a 9-deep counter on the die.

## 9. Decision and sequencing

Decided as recorded at the head of this document. What remains is the order of
work, because two of the four decisions interact.

**The gate has no home yet.** Deleting `forte_link_train.sv` removes the
on-die gate, and its replacement — the first-header checker and `rst_n` abort
policy — lives on the FPGA. But `fpga/pynq/` instantiates
`amoeba_soc_wrapper`, not `forte_top`, so there is currently no FPGA build
that speaks the link at all. **Delete training as part of the Option 3 change,
not before it**, so the design is never simultaneously without an on-die gate
and without an off-die one.

Suggested order:

1. **Choose and vendor the async FIFO** (§4.2). Blocks everything else in
   Option 3 and is a licence/submodule decision for the team, not a
   unilateral one.
2. **`clk_out` + `link_clk` pad-table update** (§3 of `top_level_plan.md`),
   together with the §11 scan-pin question since both change the pad table.
3. **Split the bridge** across the crossing: core-side AHB front end,
   link-side serializer/deserializer, two FIFOs, abort rule re-derived (§4.5).
4. **Delete `forte_link_train.sv`** and its wiring in the same change, plus
   the FPGA-side header checker.
5. **Loopback**, once the DFT/debug-pin question is settled.

Steps 3 and 4 are the ones that touch RTL verified by the regression, so they
want the non-integer-ratio sweep (§4.2) standing up first.## 9a. REQUIRED: the two-clock testbench

**Status: DONE. `hvl/cdc/forte_cdc_tb.sv` + `hvl/cdc/run.sh`, or `make cdc` /
`make cdc_sweep` from `sim/`.**

Results: all nine ISA programmes pass at 1:1.3701 with exact flit balance, and a
ratio sweep from 0.685 to 1.370 passes with **identical flit counts at every
ratio** — the strong form of the result, since it says nothing is lost,
duplicated or reordered however the two clocks happen to sit relative to each
other. `tc_link_abort` puts 15757 commands and 27380 beats through the crossing.

One finding worth keeping: the bench first reported a timeout on programmes that
had in fact passed. `tohost` is at `0x8080_0000`, inside cacheable `EXT_MEM`, so
the store lands in the D-cache and never reaches the link — the programmes write
it and then sit in `wfi; j .-8` forever. A memory-side detector alone therefore
never fires. `top_tb.svh` does not hit this because its primary detector is the
RVFI monitor at store retirement and its AHB-level one is a documented safety
net that is in practice dead code. The CDC bench has no RVFI, so it checks the
M stage directly and keeps the memory-side check only as corroboration.

`forte_top` ties `link_clk` to the `core_clk` pad, so the ISA regression runs
both domains from one clock. RTL has no clock tree, so simulation sees **zero
skew** between them: `prim_fifo_async`'s Gray-coded pointers always cross at the
same phase, the synchronisers never resolve anything marginal, and the entire
reason for taking option 3 goes unexercised. A green regression says nothing
about the CDC.

What exists today:

- `third_party/opentitan/tb/run.sh` — the FIFO alone at Width=65, Depth=16,
  ratio 1:1.37, 2000 words with backpressure. Proves the vendored module, not
  its integration.
- The `[FLIT]` balance line in `forte_dut_wrap` (`cmd_push`/`cmd_pop`/
  `beat_push`/`beat_pop`) plus the stale-beat and 8-beats-per-read assertions.
  These are the checks that caught the reset-gating bug in `a76988e`, and they
  are what a two-clock run should be gated on.

What was needed, and what was built: a testbench that instantiates
**`forte_chip` directly** (not `forte_top`, which ties the clocks) and drives
`core_clk` and `link_clk` from independent generators at a non-integer ratio —
1:1.37 as in the FIFO bench, plus a sweep. It runs the existing ISA programmes
through it and requires the flit balance to be exact and the assertions silent.

It is a separate top rather than a mode in `top_tb.svh` for two reasons. The
Verilator flow drives `clk` from a C++ harness, so the shared bench cannot
generate a second clock at all; and the FPGA side has to move wholesale into the
link domain, because the link model *is* the FPGA and the memory behind it is the
FPGA's memory. Left on the core clock, `mem_resp` is a one-cycle pulse in the
wrong domain and the model's handshake misses it at a non-integer ratio,
producing failures that say nothing about the DUT. Built with
`verilator --binary --timing`, as `third_party/opentitan/tb` already does for the
FIFO alone.

This verifies the crossing under conditions strictly **worse** than the chip
will see, since the real part has one clock source with bounded tree skew. If it
passes at 1:1.37 with arbitrary phase it will pass at 1:1.

Also still owed: a non-integer-ratio sweep in CI, per §4.2 point 3.

## 10. Open items

| Item | Needs |
|---|---|
| `options.json` 100 MHz vs §6's ~83 MHz ceiling | Resolve; Option 2 is the fix, or lower the target |
| Core Fmax at the target library | Measure — it bounds Options 1 and 2, and sets the useful *R* for Option 3 |
| Link:core ratio target | **The decision that picks Option 3** |
| `TA` in absolute time, not cycles | Required before any link-clock increase |
| ~~Async FIFO choice~~ | **Decided: OpenTitan `prim_fifo_async`.** Remaining: vendor it, confirm port names and the power-of-two depth constraint against the actual source |
| Loopback entry encoding | `rvalid` high at reset release is free; confirm no conflict with the FPGA slave's own reset behaviour |
| First-header checker in fabric | ~20 LUTs; decide whether it also re-asserts `rst_n` automatically or only flags |
| **Non-integer clock-ratio regression** | **Done -- `hvl/cdc/`, `make cdc_sweep`. See §9a. Still owed: wiring it into CI.** |
| Pad budget | 44 used (42 + `link_clk` + `clk_out`), 8 spare. Power/ground placeholder more likely to grow with non-standard packaging |
| **SDC carries no package term** | `constraints.sdc` input/output delays are PLACEHOLDER and do not name pad or package delay at all. With packaging as the stated risk, the budget must break out package explicitly |
| **DFT/debug vs `io[15:0]`** | `io` currently doubles as the scan port. Settles both the loopback mode encoding and whether scan moves off the bus (§11) |
| Who runs CTS, and can they express a skew group | Reduced by Option 3 but not eliminated — `clk_out`'s tap still needs it |

## 11. `io[15:0]` as the scan port: 8 chains in, 8 chains out

**Status: decided 2026-10-04. Scan stays on the link bus. Loopback is ruled
out (§7.2), which closes the mode-collision question this section used to
carry.**

`io[7:0]` are `scan_in[7:0]` and `io[15:8]` are `scan_out[7:0]` when
`test_mode=1` — eight parallel chains each way, which is what `forte_chip.sv`
already muxes:

```systemverilog
  assign io_o  = test_mode ? {scan_q, 8'h00} : lm_io_o;
  assign io_oe = test_mode ? {8'hFF, 8'h00}  : {LINK_W{lm_io_oe}};
```

The eight one-flop `scan_q` stubs reserve the structure; DFT insertion replaces
them with the real chains.

**Chain allocation.** CSRs on chain 0, registers from the other subsystems
spread across 1–7. Shift time per pattern is set by the *longest* chain, not by
the total flop count, so the eight should come out close to equal length —
balance is worth asking the DFT flow for explicitly rather than taking whatever
the default stitching produces.

### 11.1 The shift clock is `core_clk`, not a pin

Standard scan shifts on the functional clock. The tester drives `core_clk`
through its own pad, so a dedicated scan clock buys nothing and costs two of the
sixteen bus pins, leaving seven chains each way instead of eight — a 14 % longer
shift for no gain. It would also put the chains in a second clock domain whose
relationship to the functional one has to be constrained and verified.

What test mode *does* need is controllability of the things scan assumes it
owns:

- **`core_clk`** — already a pad, already tester-driven.
- **Reset** — the chains must not be held in reset while shifting, and the two
  reset synchronisers (`forte_chip.sv`) are themselves flops on the chain.
  Whether `test_mode` bypasses them or DFT inserts its own control is an open
  question for whoever runs the scan insertion.
- **Clock gating** — any gate between the `core_clk` tree and a scanned flop has
  to be forced transparent while `scan_en` is high. There is no deliberate
  gating in the RTL today, so this is a constraint on insertion rather than a
  change here.

### 11.2 Consequences that are now mandatory

Keeping scan on the bus makes three things required rather than optional:

1. **Per-bit output enables in the behavioural pad.** `forte_top.sv` drives all
   sixteen pads from `io_oe[0]`, and test mode sets `io_oe = {8'hFF, 8'h00}` —
   bit 0 is *low*, so the pad tristates the whole bus and **scan-out is
   unobservable even in simulation.** It must become a genvar loop over
   `io_oe[i]`.
2. **The `dir`/`io_oe` test-mode override stays.** `dir` is a scanned flop, so
   during shift it toggles pseudo-randomly; anything deriving `io_oe` from `dir`
   in test mode would flip all sixteen pad directions every shift cycle. The
   override is load-bearing, not cosmetic.
3. **`scan_en` must be qualified with `test_mode`.** Done — `forte_chip.sv` used
   to clock the chain on `scan_en` alone, so a stray assertion during normal
   operation would shift the chain under a running core.

Both pins are additionally ANDed with the **DFT lock** register at
`0x0200_F000` (`hdl/forte_dft_lock.sv`, §3.2 of `top_level_plan.md`), which
resets to 1 and which boot software clears once it no longer needs scan — this
part has no efuses, so a register is the only available substitute. `test_mode`
is gated as well as `scan_en`, deliberately: `scan_en` alone would leave a
locked part able to enter test mode, which remaps the pads and parks the link.
Note that the `unlocked` flop must be **excluded from the chains**, and that
reset re-enables DFT, so this defends against a runtime compromise and not
against physical access — `rst_n` is an FPGA output.

A fourth, non-blocking: while `test_mode` is high the link is unusable, since
`io` is the scan port. Scan and functional traffic are mutually exclusive by
construction, which is fine — but it does mean `io` cannot be used for
parametric pad tests in test mode. A flow with boundary scan would revisit that.

### 11.3 Withdrawn: moving scan onto the idle functional pads

An earlier revision of this section proposed putting scan on `uart_rx`,
`irq[0]`, `status` and `uart_tx` — pins that are functionally idle in test mode
— to get scan off the bidirectional bus at zero pad cost. That is a *two*-chain
scheme, and it was the wrong trade: it solves a pad-sharing problem the design
does not have while cutting observability by a factor of four and giving up the
ability to put CSRs on a chain of their own. Recorded here so it is not
re-proposed.
