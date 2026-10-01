# Link Clocking: Three Architectures

**Rev 0.1 · 2026-10-01 · Decision document, no RTL committed**

The off-chip link (`docs/top_level_plan.md` §4, `hdl/amoeba_link_master.sv`)
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

`hdl/amoeba_link_master.sv:94-95`. Inbound pins are captured on the falling
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
                             |                      |  drives dir/req/wr/burst
    read data           <--- | FIFO in  (16b) <--- capture <--- pads
```

- **FIFO out:** one descriptor word (`{wr, burst, size, strb}`), two address
  words, then 4 or 32 data words. Single crossing, ordering free.
- **FIFO in:** read data words, in order. Responses need no tagging.
- **`dir` polarity** falls out of the descriptor the link FSM just popped —
  exactly what `wr_r` does today, delivered across the boundary.
- Depth: one line each way (32 × 16 b = 512 b) plus slack.

### 4.2 Use a proven FIFO

Do not write the Gray-pointer logic. Silicon-proven, permissively licensed
options worth evaluating (**verify current licence and maturity before
adopting — listed from general knowledge, not from inspection**):

| Source | Notes |
|---|---|
| PULP `common_cells` — `cdc_fifo_gray` | Silicon-proven across many PULP tapeouts; ships CDC assertions |
| OpenTitan — `prim_fifo_async` | Heavily verified, formal CDC properties included |
| Cummings' SNUG reference FIFO | The canonical design; a paper, not a maintained repo |

Integration points that bite regardless of which you pick:

1. **Reset.** Both domains must be reset consistently; async-FIFO reset is a
   classic bug source. Decide whether reset is asserted asynchronously to both
   and released synchronously in each.
2. **SDC.** Pointer synchronisers need `set_false_path` or
   `set_max_delay -datapath_only`, and DC must not optimise across them.
3. **Verification.** The regression must sweep **non-integer** clock ratios.
   A 1:1 or 2:1 simulation hides the crossing bugs that 1:1.37 exposes
   immediately.

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

- **+1 pad** for the link clock (42 → 43 used; 9 spare). Power/ground remains
  spare-pad priority #1 per §3.
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
  `amoeba_link_master.sv:120-129` does not survive intact. In-order FIFOs give
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

It is also the best bring-up instrument on the chip. Scope `clk_out` and you
know the die is receiving and distributing a clock before anything else has to
work — strictly better than §6's "`status` heartbeat is the clock-alive
indicator", which only moves once the link trains *and* transactions flow.

## 7. What training is actually for

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

**Job B does not need an LFSR, and the LFSR is not there for fault coverage.**
A directed memory test — write patterns, read back, compare — covers *more*
than the LFSR does: it exercises the address path, `req`/`wr`/`burst` framing,
real `dir` turnarounds, the FPGA's decode and memory, and the abort path. The
LFSR sends no address and tests no turnaround. Walking-ones is also a *better*
stuck-at pattern than pseudo-random. On coverage, the directed test wins.

The LFSR's one irreducible advantage is the **bootstrap problem**: a directed
memory test must be *issued by something*. The FPGA cannot issue it — the link
is ASIC-master-only. The core could, but `config_asic.vh` has `BOOTROM`,
`UNCORE_RAM`, `DTIM` and `IROM` all at 0, so every instruction the core
executes arrives over the link being tested. **The core cannot test the link
because it needs the link to fetch the test.**

So the LFSR is not a better detector. It is the cheapest check the hardware can
perform *with no core, no code and no memory*: 16 flops and 4 XORs, both sides
generating the sequence from a seed with nothing stored. Its secondary virtues
are that a failure is unambiguous (no memory, decode or address map involved)
and that a long run gives crude per-lane bit-error evidence.

**Implication worth stating plainly:** if the die had even 1 KiB of boot ROM,
a directed self-test would be strictly better and the LFSR would be redundant.
It is a consequence of having no on-chip memory, not a virtue of its own.

**Job C is the one that must survive.** `RESET_VECTOR = 0x8000_0000 =
EXT_MEM_BASE`, so the first instruction fetch crosses the link. A broken link
means the fetch returns noise, the core traps, the handler's fetch also returns
noise, and the result is a self-feeding trap storm at millions per second with
nothing pointing at the bus. Without the gate every link fault looks identical
and looks like a core fault. The gate is also basic bring-up hygiene: after
power-on the chip should sit quietly with `status` reporting link state, before
anyone commits to running software.

## 8. The training setup, concretely

Post-`clk_out`, with Option 2 or 3. Runs **once**, automatically, after every
`rst_n` release, before the core leaves reset. It does not re-run during
normal operation (`amoeba_link_train` reaches `DONE` and stays).

| # | Who | What | Duration @50 MHz |
|---|---|---|---|
| 0 | FPGA | Drives `clk` (and `link_clk`), holds `rst_n` low, loads memory | — |
| 1 | FPGA | `clk_out` is already toggling — the clock tree runs regardless of reset. Measure its phase against the reference, derive *ins*, set capture shift (90° off `clk_out`) and launch ODELAY. **No ASIC cooperation; chip still in reset.** | µs |
| 2 | FPGA | Release `rst_n` | — |
| 3 | ASIC | `amoeba_rst_sync` releases; `amoeba_link_train` enters `TX`. Drives `TRAIN_LEN` LFSR words, `dir=1`, `req=0`. `status` low | 82 µs @4096 |
| 4 | FPGA | Checks every word against its own LFSR. A mismatch is a wiring fault — report it, do not sweep | — |
| 5 | ASIC | `dir=0`, releases the bus, waits `TA` | 40 ns |
| 6 | FPGA | Echoes the same `TRAIN_LEN` words with `rvalid=1` | 82 µs |
| 7 | ASIC | Compares each word. All match → `TA2` → `DONE` | — |
| 8 | ASIC | `trained=1`: `reset_ext` deasserts, core leaves reset 2 cycles later, link master takes the bus, first fetch issues at `0x8000_0000` | — |
| — | ASIC | Any mismatch or echo timeout → `FAIL`. Core held in reset, `status` reports it. **One attempt, no retries** | — |

Total ~165 µs. Both directions are verified: step 4 proves ASIC → FPGA, step 6
proves FPGA → ASIC — which is the *only* test of that direction, so the echo
cannot be dropped even though its sweep role is gone.

Why no retries once *ins* is known before step 3: a failure then means
something structural — an open lane, a shorted pair, a mis-wired FMC, an
unbonded pad. Nine more attempts fix none of those. This also makes `RETRY_TA`
unreachable, which retires the bus-contention hazard structurally rather than
handling it with a wait state.

Optional: make training re-runnable from a bench trigger for debugging. Not
needed for boot.

## 9. Recommendation

**Take Option 2 now, unconditionally.** It is required to meet the 100 MHz
`options.json` already targets, and it costs a CTS constraint and a floorplan
note — no pads, no RTL, no CDC, no new risk. It also retires the negedge stage
as load-bearing, which is worth having on its own.

**Take `clk_out` (+1 pad).** It fixes the outbound direction in every option,
makes *ins* measurable instead of searchable, deletes the phase-sweep half of
training, and is the best first-silicon diagnostic available.

**Decide Option 3 on the frequency target, not on the timing hazard.** The
hazard has a free fix (Option 2). Option 3's case is the 2.10× serialization
penalty, and it only pays above ~1.2× link:core. If the plan is a link clock
≥ 1.5× the core, it is the right architecture and the CDC risk is worth
managing with a proven FIFO. If the link stays at the core clock, it is
significant new tapeout risk buying nothing.

**Keep the LFSR and the gate in all three** — not for phase, and not because
the LFSR detects more than a directed test would, but because nothing else can
run before the core does.

## 10. Open items

| Item | Needs |
|---|---|
| `options.json` 100 MHz vs §6's ~83 MHz ceiling | Resolve; Option 2 is the fix, or lower the target |
| Core Fmax at the target library | Measure — it bounds Options 1 and 2, and sets the useful *R* for Option 3 |
| Link:core ratio target | **The decision that picks Option 3** |
| `TA` in absolute time, not cycles | Required before any link-clock increase |
| Async FIFO choice and licence | Evaluate PULP / OpenTitan; confirm maturity and reset scheme |
| Non-integer clock-ratio regression | Required if Option 3 proceeds |
| Pad budget | Option 2: 42. +`clk_out`: 43. +Option 3: 44. Spare 8, power/ground still a placeholder |
