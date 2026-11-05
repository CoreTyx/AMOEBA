# AMOEBA Top-Level Wrapper: Pad Ring and Off-Chip Link

**Rev 1.1 · 2026-10-24 · §3 rewritten as the admitted pinout, for test (supersedes the pad list, §2's Option B and the training sequence). Rev 1.0 · 2026-09-15 · Partition decided: on-chip PLIC + UART (Option A) is the primary config; implemented on `feature/top_level`, Linux boots over the link in simulation (see `docs/impl_plan_onchip_periph.md` §0)**

The ASIC (65 nm, ~1 mm²) is `wallypipelinedcore` in the `pkg/config_asic.vh`
configuration (RV64IMAC, soft-float, Sv39, 8 KiB I$/D$) plus CLINT, a link
bridge and a pad ring. A **16-bit** multiplexed address/data bus to a VCU118
is the only functional path off-chip. The FPGA is memory and everything else.
Companion: `fpga/asic/BRINGUP.md` (branch `fpga/linux_boot`) — this plan
agrees with its settled decisions and closes its open item 1 (the protocol).

**Pad budget is 52 total, including power, ground and DFT** (BRINGUP.md §2).

## 1. Constraints that set the frame

| Fact | Source | Consequence |
|---|---|---|
| No on-chip memory (`UNCORE_RAM`, `DTIM`, `IROM` all 0) | `pkg/config.vh` | Every L1 miss crosses the link; the link *is* the memory system |
| `RESET_VECTOR = 0x8000_0000` = `EXT_MEM_BASE` | `pkg/config.vh` | First instruction fetch is off-chip; the FPGA holds `rst_n` until it is ready to serve it |
| Line = 128 b, `AHBW = 64`, `BURST_EN = 1` | `pkg/config.vh`, `buscachefsm.sv:147` | Off-chip traffic is ~100 % **full-line bursts from a line-aligned base** (no wrap, no critical-word-first). **The beat count is 2, not 8** — see "the burst length is a parameter" below |
| All regions < 4 GB, bits 30:29 zero | `pkg/config.vh` | Address is two 16-bit words; the address goes over whole |
| Linux is a silicon deliverable | — | Miss penalty is the chip's performance; every spare pad wants to be bus width |
| 52 pads **total** incl. 11 power/ground | `fpga/asic/BRINGUP.md` §2 | 32-bit bus does not fit; 16-bit bidir with scan muxed onto it |
| CVW aborts bursts on `FlushD` | `ebu`, prior FPGA debug | Bridge must never abort an off-chip transfer (§5) |

**The burst length is a parameter, not 8.** `buscachefsm` derives `HBURST` from
`BeatCountThreshold = LINELEN/AHBW - 1`, and only 1, 4, 8 and 16 beats have a
named AHB encoding; every other count falls through to `3'b001`, INCR with
undefined length. At the 512-bit line this design started from that was
`INCR8`, and the link hardcoded it in three places. The line was then shrunk to
128 bits for area, making it two beats and `3'b001`, and nothing caught it: the
core asked for 2 beats, the link insisted on 8, and the DUT hung on the second
transaction with no assertion and no diagnostic.

The link now takes the count as a parameter. `hdl/forte_chip.sv` is the single
place it is decided — `DCACHE_LINELENINBITS / AHBW` — and it threads that one
expression to both halves of the bridge, to the FIFO sizing and (from the same
`config.vh`) to the testbench slave. `forte_link_core` asserts `HBURST` against
`forte_link_pkg::hburst_for(BEATS)`, which is a copy of `buscachefsm`'s
`LocalBurstType`, so the next line resize either propagates or fails on the
first transaction. A one-beat line is rejected at elaboration: on the wire it
would be indistinguishable from an uncached single, and a single is the one case
that needs the `{HWSTRB, HSIZE}` header word the link does not carry.

The *cost* of the shorter line is on the link, not in the link's logic: the
fixed per-transaction overhead is 2 header cycles + 2·`TA`, which at 2 beats is
6 cycles of overhead against 8 of payload. Per byte moved the 128-bit line is
about 32 % worse than the 512-bit one (1.14 vs 1.68 B/cycle at `TA=2`). That is
a consequence of the area decision, not a defect, but it belongs next to the
miss-penalty numbers in §4.
| `ZICNTR=0`, `SSTC=0` in the ASIC config | `pkg/config_asic.vh` | Core never consumes `MTIME_CLINT`; CLINT stays on-die anyway (~2 k GE, `mtime` = core cycles, BRINGUP.md §2) |
| `USE_SRAM` = `ifdef AMOEBA_USE_SRAM` | `pkg/config_asic.vh` | Sim/netlist mismatch risk; regress with macros before freeze |

## 2. Partition

**Always on-chip:** core, I$/D$, CLINT, link bridge, pad ring, scan mux.
**Always off-chip:** memory (DDR4 via MIG at `0x8000_0000`), SPI, GPIO, SDC.
**Open:** PLIC and UART.

Note on hierarchy: `wallypipelinedcore` is the pipeline + AHB master + interrupt
inputs; it has no peripherals. UART/CLINT/PLIC/decoder live in `uncore`, which
`wallypipelinedsoc` wraps. The plan instantiates `wallypipelinedcore` directly
under a new `forte_uncore` (§10), so the peripheral set is ours to choose and
no CVW file is edited.

| | A: PLIC + UART on-chip | B: only CLINT on-chip | **C: CLINT + UART on-chip, PLIC off** |
|---|---|---|---|
| Console when FPGA MMIO decode is wrong | works | dead | **works** |
| FPGA console via `amoeba_bus_mon` AHB snoop (all PYNQ tooling) | **breaks** — THR writes never leave the die; needs a physical UART receiver with per-clock divisor | works unchanged | breaks, as A |
| Console observable with no FPGA build | scope on `uart_tx` | no | **yes** |
| Interrupt path diagnosable | only via PLIC regs over the link | ILA on all of it; `meip`/`seip` on pads | **same as B** |
| PLIC fixable post-silicon | no | yes | **yes** |
| UART interrupt | internal to PLIC | n/a | `uart_irq` pad (+1) or polled 8250 |
| PLIC claim/complete | 3 cycles | ~100–150 cycles | ~100–150 cycles |
| Pads used of 52 | 42 | 40 | **42** (43 with `uart_irq`) |

*(Current pad count: 32 signal + 11 power/ground = 43 used, 9 spare. `burst` was
removed — it was always 1 — and `clk_out` took its pad; `fault_inject` holds one.)*
| CVW changes | none | `forte_uncore` | `forte_uncore` |

**Recommendation: B**, which is also what `fpga/asic/BRINGUP.md` settles on.
The case for an on-chip UART (a console independent of the FPGA parser,
probeable with a scope) is real, but the merged FPGA flow shows the other
side of it: the entire PYNQ console path is `amoeba_bus_mon` snooping UART
writes on the AHB, and every bring-up script reads it. With the UART on the
die those writes never leave the chip; the FPGA would need a real UART
receiver whose divisor tracks the guest's per-clock programming — the exact
bug class BRINGUP.md §7 warns about. Off-chip, the snoop, `tohost`, and the
scripts work unchanged. The UART on the FPGA is still probeable — on the
reconstructed AHB, with an ILA. An on-chip PLIC is a black box when interrupts
fail; off-chip it is observable and replaceable. Linux polls the UART (no
`interrupts` in `amoeba_baremetal_linux.dts`), so no PLIC is on the boot path.
The TB snoops console output via RVFI stores to `0x1000_0000` (`top_tb.svh`),
so simulation is unchanged either way.

**What B/C touch.** Do *not* widen `EXT_MEM` to cover peripheral addresses:
`pmachecker.sv` marks `EXT_MEM` cacheable, idempotent and AMO-allowed, all
wrong for MMIO. Instead:

| File | Change |
|---|---|
| `pkg/config_asic.vh` | **Done.** `PLIC_SUPPORTED=1`, `UART_SUPPORTED=1` (decode only, so `adrdecs`/PMA treat them as uncached peripherals); `GPIO/SPI/SDC/BOOTROM=0`; `USE_SRAM` define-driven. Derived from `config_baremetal_linux.vh`. Selectable as `CONFIG=asic` in `sim/`, `synth/`, `fpga/pynq/`, `testcode/linux/`; builds and passes `tc_mul_div` in Verilator after the `bpred.sv` `BPDirWrongM` fix (`ZIHPM=0` left it undriven — no pruned config had ever been elaborated by Verilator). |
| `hdl/forte_uncore.sv` (new, from `uncore.sv`) | Keep `adrdecs`, CLINT, `ahbapbbridge`, ext port, `HRDATA`/`HREADY`/`HRESP` muxes, `hseldelayreg`. Keep UART (C) or drop it (B). No PLIC: fold `HSELPLIC` (and `HSELUART` for B) into `HSELEXT` and its delayed copy. `MExtInt`/`SExtInt` become inputs. |
| `hdl/forte_soc.sv` (new, from `wallypipelinedsoc.sv`) | `wallypipelinedcore` + `forte_uncore`. Ports: AHB ext port, `meip`/`seip`, `UARTSin`/`UARTSout` (C). |
| ASIC top | Tie off removed ports; 2-flop synchronisers on `meip`/`seip`. |
| Testbench link model | Instantiate CVW `plic_apb` + `uartPC16550D` behind it so CI runs unchanged. |
| Untouched | Every file under `hdl/core/`, `cvw_t`, `parameter-defs.vh`, Linux DTS (except dropping `interrupts` on the UART node for polled mode), OpenSBI. |

`HREADY`/`HRESP` muxes in `uncore.sv` already OR in the `HSELEXTD` terms, so
wait states are inherited for free (there is no error path; `HRESPEXT` is tied low).

## 3. Pinout, as admitted

**This section is the current description of the chip's pins (2026-10-24,
`postsynth_verif` @ `517f7f2`), and it is written for someone extending how the
chip is tested.** Where §2, §4, §6 or §10 disagree with it, they describe
earlier plans and this section wins. Its sources are the RTL itself
(`hdl/forte_top.sv`, `hdl/forte_chip.sv`, `hdl/forte_link_phy.sv`,
`hdl/forte_link_pkg.sv`, `hdl/forte_dft_lock.sv`) and the pin-level bench that
emulates the bring-up FPGA (`hvl/pin/`), which drives the synthesized netlist
through these pins only and is the executable version of everything below.

The admitted build is `PERIPH_ONCHIP = 1`: PLIC and UART on the die (Option A
of §2, not the B that §2 recommends). Clock target 100 MHz.

### 3.1 Summary

32 signal pads, plus power and ground. The budget is 52; with the 11-pad
power/ground placeholder, 43 are used and 9 are spare.

| Pin | Dir | Group | One line |
|---|---|---|---|
| `core_clk` | in | clock | The only clock. Runs the core, and (tied on the die) the link domain. |
| `rst_n` | in | reset | Asynchronous assert, synchronous release; the FPGA owns it. |
| `io[15:0]` | bidir | link | Address, then data, 16 bits at a time. Scan in/out in test mode. |
| `dir` | out | link | 1 = the chip drives `io`, 0 = the chip has released it. |
| `req` | out | link | `io` carries the address this cycle (two cycles per transaction). |
| `wr` | out | link | 1 = write, held for the whole transaction. |
| `clk_out` | out | link | The link clock, forwarded; the FPGA samples chip outputs with it. |
| `ready` | in | link | FPGA: room for a whole transaction plus one in reserve. |
| `rvalid` | in | link | FPGA: `io` carries a read data word this cycle. |
| `irq[1:0]` | in | interrupts | Level interrupts into the on-die PLIC (sources 3 and 6). |
| `uart_tx` | out | console | 16550 UART transmit. |
| `uart_rx` | in | console | 16550 UART receive. |
| `test_mode` | in | test | Static: remaps `io` to eight scan chains each way. |
| `scan_en` | in | test | Per cycle: shift (1) or capture (0). |
| `fault_inject` | in | test | Master enable for the on-die fault injectors. |
| `status` | out | debug | LED heartbeat at three rates: stalled, active, quiet. |

Pad cells (`forte_top`, under `SYNTHESIS`): `io_in` for every input, `io_out`
for every output, and one `io_tri` per `io` lane, each lane with its **own**
tristate control (test mode drives the two halves in opposite directions, so a
shared enable would make scan unobservable). The `io_tri` `t` pin is
**active-high tristate**: `t = 0` drives, `t = 1` releases; it is derived in one
place as `t = ~io_oe`.

**What the pad ring does not have, which matters for test.** No pull-ups or
pull-downs (the `io_in` cell has no pull terminal), so `test_mode`, `scan_en`
and `fault_inject` must be **driven low by the board** in functional use and
`uart_rx` must be **driven high**. A floating `test_mode` on an unlocked part
can put the chip into test mode. There is also no dedicated clock-input cell for
`core_clk`, no clock-output cell for `clk_out`, and no power/ground pads in the
RTL: those are floorplan decisions.

### 3.2 Each pin: why it exists and exactly what it does

**`core_clk` (in).** The single clock from the FPGA; there is no PLL. Inside,
it feeds two clock trees: the core domain, and a small link domain next to the
pads (`forte_top` ties `link_clk` to the same pad; `docs/impl_plan_link_clocking.md`
§4). The two domains are joined by async FIFOs, so the link side's capture
margin does not depend on the core tree's insertion delay. In test mode this is
also the **scan shift clock**: there is no separate scan clock pin, because
standard scan shifts on the functional clock, and a dedicated one would cost two
bus pins.

**`rst_n` (in).** Active-low. Asserting it is asynchronous in both domains;
releasing it goes through a two-flop synchronizer per domain
(`forte_rst_sync`), so the domains leave reset on their own clock edges and the
FIFO pointers on both sides of the crossing come up consistent. While
`rst_n = 0`, the link parks immediately (asynchronously): `dir = 1`, `req = 0`,
`wr = 0`, and the chip **drives `io` to 0**. There is no link training: the
first transaction after release is always a line read of `0x8000_0000`
(`RESET_VECTOR`), so the FPGA can check the first header (`0x8000`, `0x0000`,
`wr = 0`) and pull reset again if it is wrong. The FPGA holds `rst_n` low until
memory is loaded. Reset also re-enables DFT (§3.10).

**`io[15:0]` (bidir).** The only data path off the chip. It carries nothing but
addresses and data; what a transaction *is* (read or write, where the address
is) is on the dedicated pins below, so neither side decodes the bus. Sixteen
bits is what fits the pad budget (§4). Who drives it in each mode is in §3.3.

**`dir` (out).** The single source of truth for who owns `io` in functional
mode: `1` = the chip drives it, `0` = the chip has released it. The chip
guarantees `TA` (= 2) idle cycles on every change of owner, and the FPGA may
drive `io` only while `dir = 0`, after those cycles, and only with `rvalid`. In
**test mode `dir` does not describe the bus** (§3.3): it comes from a scanned
flop and toggles during shift.

**`req` (out).** High for exactly two consecutive cycles at the start of every
transaction, while `io` carries the address: `A[31:16]`, then `A[15:0]`. Never
high with `dir = 0`, never mid-transaction.

**`wr` (out).** `1` for a write, `0` for a read, valid with the first `req`
cycle and held until the transaction's last word. It is a pin rather than a bus
field so the transaction type is readable on a scope and costs no bus cycle.

**`clk_out` (out).** The link clock driven back out. The FPGA samples the chip's
outputs (`io`, `dir`, `req`, `wr`) relative to it, so the chip's own pad and
clock-insertion delay cancel on the chip-to-FPGA path. It must be tapped off the
link tree at the same depth as the `io` output flops (a CTS constraint, not RTL).
It is also the first thing to scope at bring-up: a toggling `clk_out` proves the
die is receiving and distributing a clock. It replaced a `burst` pin that was
always 1.

**`ready` (in).** The FPGA's "I can take a whole transaction, and one more in
reserve". It is advisory, not a handshake: the chip samples it through two
registers and starts a transaction a cycle later, so a `req` can arrive up to
`GUARD` = 3 cycles after `ready` fell. **The FPGA must drop `ready` while it
still has room for one more transaction**, never when it is actually full.
Once a transaction starts there is no flow control in either direction.

**`rvalid` (in).** The FPGA's "`io` carries a read data word this cycle". Gaps
are allowed: words do not have to be back to back.

**`irq[1:0]` (in).** Level-sensitive interrupts, each through a two-flop
synchronizer, into the on-die PLIC: `irq[0]` is PLIC source 3, `irq[1]` source 6
(the IDs Wally reserves for GPIO and SPI, which this chip does not have). The
UART's own interrupt is source 10, internal. Software claims and completes them
at the PLIC (`0x0C00_0000`); the FPGA must hold the level until software clears
the cause on the FPGA side. (A `PERIPH_ONCHIP = 0` build reuses these two pins
as `meip`/`seip`; it is not the admitted build.)

**`uart_tx`, `uart_rx`.** A PC16550D-compatible UART at `0x1000_0000`. Baud =
`f_core / (32 x divisor)` (the 16x oversampling is preceded by a fixed divide by
2, `UART_PRESCALE = 1`). For example 115 200 baud at 100 MHz is divisor 27
(0.5 % error). `uart_rx` is synchronized; it must idle high (no pull-up on the
die). The console exists on the die so it can be read with a scope or a
USB-serial cable even when the link or the FPGA's decode is broken.

**`test_mode` (in).** **Static for a whole test session**, not toggled per
pattern. When 1 (and the part is unlocked, §3.10) it remaps the bus to eight
scan chains each way and forces the `io` pad directions from the scan mapping
instead of from `dir`. Details in §3.3 and §3.7.

**`scan_en` (in).** **Per cycle**: 1 = shift, 0 = capture. It is qualified with
`test_mode` (and the lock), so a glitch on it in functional mode cannot shift a
running core.

**`fault_inject` (in).** A board strap, synchronized on the die, that enables
the fault-injection hardware. It is ANDed per unit with `FI_CONTROL`
(`0x1007_000b`, one byte, **resets to 0**; bit 0 ALU, 1 comparison, 2 MUL,
3 DIV, 4 register-file ECC, 5 pipeline ECC, 6 cache correctable, 7 cache
uncorrectable), so injection needs both the pin and software. With the pin low,
all checking (ECC, the shadow FT units, TMR) stays on; only injection is off.
What the checkers saw is counted in 18 read-only, 16-bit saturating counters at
`0x1008_0000 + 4i` (§3.6).

**`status` (out).** A free-running heartbeat from the link domain whose *rate*
says what the link is doing, so it never freezes: ~6 Hz stalled, ~1.5 Hz
active, ~0.4 Hz quiet. Details in §3.9. Only a dead clock freezes it, and
`clk_out` is the instrument for that.

### 3.3 The bidirectional pins: who drives `io` in each mode

`io` has three owners over time: the chip, the FPGA, and (in test mode) both,
one half each. The per-lane enable inside the chip is `io_oe`; the pad sees
`t = ~io_oe`.

| Mode | `test_mode` | `io[15:8]` | `io[7:0]` | `dir` pin | FPGA may drive |
|---|---|---|---|---|---|
| Reset (`rst_n = 0`) | 0 | chip drives 0 | chip drives 0 | 1 | nothing |
| Functional idle | 0 | chip drives 0 | chip drives 0 | 1 | nothing |
| Header, write data | 0 | chip drives | chip drives | 1 | nothing |
| Read turnaround (`TA` cycles each side) | 0 | released | released | 0 | nothing yet |
| Read data | 0 | released | released | 0 | all 16, only with `rvalid` |
| Test mode, part unlocked | 1 | **chip drives** (scan out) | **released** (scan in) | meaningless | `io[7:0]` only |
| Test mode, part locked | 1 | as functional | as functional | as functional | as functional |

Three consequences for anyone building the tester or the FPGA side:

1. **In functional mode the bus is never floating except during a read.** The
   chip drives zeros whenever it is idle, so the FPGA's `io` buffers must be
   inputs whenever `dir = 1`. The bench checks that it never drives while
   `dir = 1`, and treats any X on `io` while the chip owns it as an error.
2. **In test mode, `dir` is not the direction.** Only `io_oe` is overridden.
   `dir`, `req` and `wr` still come from their functional flops, which are in
   the scan chains, so they toggle pseudo-randomly while shifting. The FPGA or
   tester must set its own `io` buffer directions **from `test_mode`, which it
   drives**, not from `dir`: `io[7:0]` outputs from the tester, `io[15:8]`
   inputs to it.
3. **A locked part ignores `test_mode`.** The pads stay functional, so a tester
   that raises `test_mode` on a locked part sees the link, not scan.

### 3.4 Talking to the chip: the link protocol

All timing is in link-clock cycles (= `core_clk` cycles). `BEATS` is the number
of 64-bit beats in a cache line, `128 / 64 = 2`, so a transaction carries
`W = 4 x BEATS = 8` data words. `TA = 2`.

**Who launches and who samples.**

- The FPGA launches `io`, `ready` and `rvalid` on the `core_clk` rising edge.
  The chip captures them on the **falling** edge and re-registers them on the
  rising edge, so the FPGA's clock-to-out plus board delay must stay under half
  a period (5 ns at 100 MHz). The bench uses 2 ns.
- The FPGA samples the chip's outputs a fixed delay after the `clk_out` rising
  edge. The bench uses 5 ns.

**Only one kind of traffic crosses.** Every off-chip access is a full cache-line
burst at a line-aligned address in `0x8000_0000`–`0x8FFF_FFFF`: a line fill
(read) or a writeback (write). Everything else (CLINT, PLIC, UART, the DFT lock,
`FI_CONTROL`, the fault counters) is on the die. So the link carries no size,
no byte strobes, and no burst length; the FPGA increments the address by 8
bytes per beat.

**Write (10 cycles):**

```
cycle   0         1         2    3    4    5    6    7    8    9    10
req     1         1         0    0    0    0    0    0    0    0    0
wr      1         1         1    1    1    1    1    1    1    1    0
dir     1         1         1    1    1    1    1    1    1    1    1
io      A[31:16]  A[15:0]   b0w0 b0w1 b0w2 b0w3 b1w0 b1w1 b1w2 b1w3 0
```

Each 64-bit beat goes as four words, least significant first (`b0w0` =
`beat0[15:0]`). The chip starts a write only once all of it is buffered on the
die, so the words are back to back and the FPGA must take one every cycle.

**Read (14 cycles plus any FPGA latency):**

```
cycle   0         1         2   3   4..        last+1  last+2   then
req     1         1         0   0   0          0       0        0
wr      0         0         0   0   0          0       0        0
dir     1         1         0   0   0          0       0        1
io      A[31:16]  A[15:0]   --  --  FPGA words (rvalid=1)  --  --  chip drives
```

After the two address words the chip drops `dir` and releases the bus. The FPGA
counts `TA` cycles in which it has seen `dir = 0`, then drives the 8 words, least
significant first, each with `rvalid = 1`. Gaps (`rvalid = 0`) may come anywhere,
which is how memory latency is expressed. After the last word the FPGA releases
`io`; the chip waits `TA` cycles and raises `dir`. With no gaps a read is
`2 + 8 + 2 x TA = 14` cycles.

**Rules the FPGA must keep:**

- Never drive `io` while `dir = 1`, or before `TA` cycles of `dir = 0`.
- Exactly `W` words per read, never more, each with `rvalid`.
- Accept a `req` up to `GUARD` = 3 cycles after dropping `ready`.
- Never abort or shorten a transaction: neither side can.

The bench's `pin_link_agent` enforces all of these and is a reference for the
FPGA's link slave.

**Booting it.** Hold `rst_n` low, load the image at `0x8000_0000`, release
`rst_n`, and serve reads. Software ends a test by writing a value to `tohost`
(in cacheable memory, so it needs a `fence.i` or a flush to actually leave the
chip). That is a convention between the program and the FPGA, not a pin.

### 3.5 Interrupts and console

`irq[1:0]` and the UART are covered in §3.2. Two notes for test: the UART is
the only output a program can use with no link at all (scope or USB-serial on
`uart_tx`), and `irq` lets the FPGA interrupt the core at a cycle of its
choosing, which is how the bench's `irq` test exercises the PLIC through pins.

### 3.6 Test features reachable by software

All of these are on-die MMIO and are exercised through ordinary loads and stores
over the link. None needs `test_mode`.

| Address | What | Reset | Notes |
|---|---|---|---|
| `0x0200_F000` | DFT lock (§3.10) | 1 (unlocked) | Write 0 to lock until reset; ANDed with `test_mode` and `scan_en`. |
| `0x1007_000b` | `FI_CONTROL`, one byte | 0 | Per-unit injection enables, ANDed with the `fault_inject` pin. Byte access only. |
| `0x1008_0000 + 4i` | Fault counters `i = 0..17` | 0 | Read-only, 16-bit saturating, `{16'b0, count}`. 0/1 register-file SEC/DED, 2/3 pipeline SEC/DED, 4/5 I$ SEC/DED, 6/7 D$ SEC/DED, 8/9 ALU mismatch/unresolved, 10/11 CMP, 12/13 MUL residue, 14/15 DIV residue, 16/17 privilege-mode TMR corrected/uncorrectable. Only reset clears them. |

`docs/memory_map.md` predates the 8-unit mask and the counters being on the
ASIC; where it disagrees, this table is current.

### 3.7 Test mode: what is real today and what is not

What the RTL implements (`forte_chip`):

- `test_mode_dft = test_mode & dft_unlocked` and `scan_en_dft = scan_en &
  dft_unlocked`.
- With `test_mode_dft = 1`: `io[7:0]` are `scan_in[7:0]` (released, `t = 1`) and
  `io[15:8]` are `scan_out[7:0]` (driven, `t = 0`): eight chains each way, shifted
  on `core_clk`.
- **The chains are stubs.** Each "chain" is one flop (`scan_q`) that loads
  `io[7:0]` when `scan_en` is high and drives `io[15:8]`. They reserve the
  structure and let the bench check the pad directions. DFT insertion replaces
  them. Today `scan_out[k]` is `scan_in[k]` delayed by one cycle, which is a
  usable loopback test of the 16 pads in their test directions and nothing more.
- Intended chain allocation: CSRs on chain 0, the rest balanced across 1–7
  (shift time is set by the longest chain).

What DFT insertion still has to add, whichever interface is used (§3.8):

1. **The chains themselves**, with the `dft_unlocked` flop excluded
   (`set_scan_element false`). If it is in a chain, scan can unlock the part.
2. **Reset control in test mode.** Every flop resets asynchronously from a
   synchronizer output (`forte_rst_sync`). ATPG needs those resets driven
   directly in test mode (a `test_mode` mux around each synchronizer), or it
   loses control of them.
3. **Clock-gate test enables.** Synthesis inserted roughly a thousand clock-gating
   cells (`SNPS_CLOCK_GATE_*`). Their test-enable pins must be tied to the
   qualified `scan_en` (or `test_mode`), or the flops behind them cannot shift.
4. **Falling-edge flops.** The link's inbound capture registers (`io`, `ready`,
   `rvalid`: 18 flops) clock on the falling edge. They need their own chain
   segment or lock-up latches at the edge boundaries.
5. **SRAM macros** (`rf_sp_*` for the caches) are not scannable. Their contents
   and the logic around them need either memory BIST or functional march tests
   run over the link (the current path, through the bench), and ATPG must treat
   the macros as black boxes with bypass or shadow logic.
6. **Pads in test mode.** `io[7:0]` are input-only and `io[15:8]` output-only, so
   scan never exercises the other direction of any `io` pad. The functional link
   tests do.

### 3.8 Alternative: a dedicated 5-pin scan interface, `io` out of test entirely

The comparison here is with the common minimal interface: `test_mode`,
`scan_en`, `scan_in`, `scan_out`, and a scan clock, with no scan function on
`io`. Since `test_mode` and `scan_en` already exist, this costs **3 more pads**
(2 if shift stays on `core_clk` and the fifth pin becomes a test reset instead).
`io` would then be a purely functional bus with no test-mode override.

| | Current: 8+8 chains on `io` | Dedicated 5-pin |
|---|---|---|
| Pads for test | 2 (`test_mode`, `scan_en`) + 16 shared | 5, none shared |
| Spare pads after | 9 | 6 (power/ground claims spares first) |
| Chains | 8 in, 8 out | 1 in, 1 out (more with compression) |
| Shift cycles per pattern, N scan flops | about N / 8 | about N (8x longer), or N / k with on-chip compression into k internal chains |
| `io` pad logic | per-lane direction override; the two halves go opposite ways | none: `io_oe` is always from `dir` |
| Tester or FPGA side | must flip half of `io` and ignore `dir`/`req`/`wr` in test mode | 4 static or slow pins plus 1 data pin each way; no bus |
| Depends on the `io` pads working | yes: a broken `io` lane loses a chain | no: scan works with the link dead |
| Scan while the link is in use | impossible (same pins) | possible in principle, but still needs test mode |
| What can test the `io` pads | scan (one direction each) plus functional link | functional link only |
| DFT lock | gates `test_mode` and `scan_en` | the same two gates; `scan_in`/`scan_out` are inert without them |
| Standard ATE / DFT flow | custom pin map | the default the tools expect |

**Arguments for the current scheme.** It is free in pads, and 8 parallel chains
make shift time 8x shorter without compression logic. It reuses pins the board
already routes to the FPGA, so the bring-up FPGA can be the tester.

**Arguments for the dedicated interface.**

- **Test is independent of the link.** If a pad's tristate is wrong, or the
  per-lane override is wrong (it has been once, in the behavioural model:
  a bus-wide enable made scan unobservable), or the board's bus routing has a
  fault, scan still works and can be used to diagnose the link. Today a link
  fault and a scan fault share pins and cannot be separated.
- **Simpler `io` logic.** The override on `io_oe`, and the rule that `dir` lies
  in test mode, disappear. Every test-mode subtlety in §3.3 goes away.
- **Standard flow.** One chain in, one out is what ATPG, compression (for example
  DFTMAX or EDT) and production testers expect. With compression, test time can
  match or beat 8 raw chains: k internal chains behind 1 scan-in and 1 scan-out
  for a few hundred to a few thousand gates.

**The costs.** Three pads from a spare pool that power and ground may need
first. Either 8x the shift time or a compression IP to buy it back. And a
second, slower path to the chip for the bring-up FPGA, which already drives
`io`.

**What would change in the RTL.** In `forte_top`: add three pad cells. In
`forte_chip`: drop `scan_q` and the `test_mode_dft` terms on `io_o` and
`io_oe`, and route the new pins to the inserted chains. The DFT lock and all of
§3.7's insertion work stay the same. The pin-level bench needs only its test-mode
check moved from `io` to the new pins.

**Recommendation for someone extending test.** The items in §3.7 (real chains,
reset and clock-gate control, the falling-edge flops, memory test) are needed
under either interface and are the larger job; do those first. Choose the
interface on the pad count once power and ground are settled. If at least 3
spare pads survive, the dedicated interface is the lower-risk choice, because
it lets scan diagnose a broken link.

### 3.9 `status`, and why it is three rates

`status` used to be a tap on a counter of completed link transactions, so the
blink was driven only by traffic and the pin **froze** whenever nothing
completed. That made the two states you most need to tell apart during bring-up
— the core halted or spinning in cache, and the link wedged mid-transaction —
produce exactly the same picture, and a frozen pin is also indistinguishable
from a very slow blink.

It is now a free-running counter in the link domain with only its *rate*
modulated, so "never frozen" is structural rather than aspirational:

| Condition | Rate @ 100 MHz | Means |
|---|---|---|
| `busy` and nothing completed for 2^17 link cycles (~1.3 ms) | `tick[23]` ≈ 5.96 Hz | **stalled** — a transaction started and never finished |
| something completed recently | `tick[25]` ≈ 1.49 Hz | **active** |
| idle and nothing completed recently | `tick[27]` ≈ 0.37 Hz | **quiet** — alive, no traffic |

The three are ~4× apart so they are told apart at a glance rather than by timing
them. All four numbers are parameters on `forte_chip`, because the real
frequency is not settled and because nothing can observe a 0.4 Hz blink in
simulation — a testbench has to be able to shrink them.

The one case this cannot cover is a dead `link_clk`, which freezes it. `clk_out`
is the instrument for that (§6.1 of the clocking plan) and is strictly better at
it, which is why `status` no longer tries to be the clock-alive indicator.

### 3.10 DFT locking, without efuses

This tapeout has no efuses, so there is nothing one-time-programmable to blow
after test. Scan reaches every flop on the die — register file and CSRs
included — so a part that leaves the tester with scan still reachable has no
protected state at all.

The substitute is one memory-mapped register, `hdl/forte_dft_lock.sv`, at
**`0x0200_F000`**:

- **resets to 1** (DFT permitted), so the part is testable from power-up and
  before any software runs — a part that came up locked could not be tested;
- **writing 0 locks it**, and `forte_chip` ANDs it with *both* `test_mode` and
  `scan_en`, so a locked part keeps its pads functional and cannot shift;
- **the clear is sticky** until reset. A register software could set back to 1
  would turn every code-execution bug into a scan unlock, which is the thing
  the lock exists to prevent.

It sits in a hole in the CLINT's region rather than a region of its own, because
every region the PMA will permit has to come from `pkg/config.vh` via `adrdecs`,
and the spare ones there (GPIO, SPI, SDC) are gated on `*_SUPPORTED` — enabling
one would also make CVW's `uncore.sv` instantiate that peripheral in the legacy
DUT. Decoding it in `forte_uncore` instead touches no CVW file and no shared
config. `CLINT_RANGE` is 64 KB and `clint_apb` implements only `msip` (+0x0000),
`mtimecmp` (+0x4000) and `mtime` (+0xBFF8), so +0xF000 collides with nothing, and
the select takes that address *away* from the CLINT so only one slave answers.

Covered by `testcode/isa_level_testing/tc_dft_lock.c`, through real loads and
stores — the flop is not the part most likely to be wrong, the path to it is.

**What this does not defend against, and it matters.** Reset re-enables DFT;
there is no non-volatile state, so the lock cannot survive a power cycle by
construction, and on this board `rst_n` is an FPGA *output*. This protects
against a runtime software compromise, not against physical access. It is also
only as good as the boot flow — nothing clears it automatically, so if boot
software never writes 0, DFT stays open for the life of the power cycle.
Clearing it belongs at the end of early init, after whatever last needs scan and
before any untrusted code runs. Finally, the `unlocked` flop **must be excluded
from the scan chains** and from any test-mode reset bypass DFT insertion adds;
that needs a `set_scan_element false` in an insertion script that does not exist
yet.

## 4. Link protocol

> **Partly historical.** The admitted protocol is in §3.4. In particular there
> is no single-transfer path and no third header word: every transfer is a
> full line, and the "attribute word" text below describes a path that was
> removed. Link training (§6) was also removed.

Bus content is only ever an address or data. Transaction type lives on pins,
held for the whole transaction. Nothing on the bus is decoded by either side.
This is BRINGUP.md §2's "command + 32-bit address" header with the command
beat replaced by the `wr` pin: one cycle shorter and readable on a
scope.

```
req=1, cycle 0   io[15:0] = HADDR[31:16]   the whole address; no bits are stolen
req=1, cycle 1   io[15:0] = HADDR[15:0]
req=1, cycle 2   io[15:0] = {HWSTRB[7:0], 5'b0, HSIZE[2:0]}   SINGLES ONLY (burst=0)
otherwise        io[15:0] = data word       64-bit beat as 4 words, least significant first
wr               held from req until the last word
```

**The attribute word.** A burst is `BEATS` aligned 64-bit beats with every lane
live, so it needs neither size nor strobes and skips the third header word —
line fills are ~100 % of the traffic and pay nothing. There is no `burst` pin:
every transfer is a full line, so it would have been tied to 1 for the life of
the part. Its pad went to `clk_out`. A single spends one
extra cycle and carries the real `HWSTRB`. This replaced an earlier encoding
that rode `HSIZE[1:0]` in address bits 30:29: that constrained every region to
have those bits clear (enforced only by a `ifndef SYNTHESIS` assertion, so in
silicon `0x2000_0000`/`0x4000_0000`/`0x6000_0000` would have aliased silently),
and it left the FPGA rebuilding byte strobes from size + offset — correct only
because Wally's `swbytemask` derives `HWSTRB` from the same two signals, an
equivalence nothing checked. Sending the strobes costs one cycle on a transfer
type the primary config barely issues and removes both hazards. The slave still
rebuilds the mask for *reads* (`HWSTRB` is a write signal) and the link model
asserts the two agree, so a CVW bump that changes the relationship is loud.

`ready` means **"may start, and I have one more transaction in reserve."** It
is a hint with a guard band, not a handshake: the ASIC samples it through two
input registers and asserts `req` a cycle later, so a `req` may legally arrive
up to `GUARD` = 3 cycles after the slave dropped `ready`. **A slave must
therefore deassert `ready` while a whole transaction still fits — never when it
is actually full.** Sizing for two outstanding lines instead of one deletes the
race; the testbench model is four lines deep and asserts on overflow, and the
FPGA slave must do the same. There is no mid-transaction handshake in either
direction, so the ASIC never stalls once started. Beat *n* of a burst is at
`base + 8n` (CVW bursts from a line-aligned base, incrementing, for `BEATS`
beats); the FPGA increments.
`HADDR[55:32]` is never nonzero on the bus because the PMA faults undefined
regions first (sim assertion).

**Turnaround.** `TA` is a parameter (default 2) sized to the pad library's
specified output-enable switching time. Only the ASIC counts.

```
ASIC drives io   <=>  dir = 1
FPGA drives io   <=>  dir = 0  and  rvalid = 1  and  a read is in flight
ASIC guarantees >= TA idle cycles after dir falls before the FPGA may drive,
and >= TA idle cycles after the last rvalid before it raises dir and drives.
```

**Training is not exempt.** A retry is the one moment the ASIC wants the bus
back while the FPGA is still using it — the FPGA sweeps its output phase blind
and its only feedback is that the pattern restarted, so it cannot know to stop
echoing. `forte_link_train` therefore holds `dir=0` for a whole `TRAIN_LEN`
after a mismatch (state `RETRY_TA`) before taking the bus; the longest echo
still in flight is `TRAIN_LEN - k` words. `+LINK_TRAIN_ERR=n` in the testbench
corrupts word *n* of the first echo so this path is exercised, and the model's
"driving io while dir=1" check is what proves there is no overlap.

`W = 4·BEATS` is the word count on the wire; at the current 128-bit line
`BEATS = 2` and `W = 8`.

| Transaction | Sequence | Cycles | @ 128 b line, TA=2 |
|---|---|---|---|
| Line read | `req`×2 · `dir`↓ · TA · *W* × `rvalid` words · TA · `dir`↑ | 2 + *W* + 2·TA | 14 |
| Line write | `req`×2 · *W* words | 2 + *W* | 10 |
| Single read | `req`×3 · TA · 4 words · TA | 7 + 2·TA | — (no single path) |
| Single write | `req`×3 · 4 words | 7 | — (no single path) |

Plus FPGA memory latency as `rvalid` gaps. At the 512-bit line this was 38 link
cycles, giving a ~50–70 cycle miss at 1:1 clocks — the same range as a DRAM miss
on a commodity part (BRINGUP.md §2 reaches the same conclusion at 35). At 128 b
the transaction is 14 cycles but moves a quarter as much, so the miss *rate*
rises and the per-byte cost rises with it; the FPGA-side L2 (BRINGUP.md §3) is
what keeps the crossing the only cost.

Width, per line: 16 b muxed is what the pad budget allows; 32 b muxed would be
roughly half the data cycles but needs 56 pads; 8+8 split is twice as many; 16 b
DDR was rejected as a bring-up risk. 16 b bidirectional is the only one that
fits. Note that the fixed 2 + 2·TA overhead does not shrink with the line, so
the narrower the line the more of the link's time is header and turnaround —
the 512-bit line amortised that over 32 data cycles, the 128-bit one over 8.

## 5. Bridge: `forte_link_master` (~400–500 GE)

**Invariant: once `req` is accepted, the bridge always finishes the word
count. Never abort, shorten, or reorder. If the core abandons the burst, drain
into a bit bucket and return to IDLE.**

- Once started the FSM ignores `HTRANS`. At each non-final beat boundary it
  completes the AHB beat only if `HTRANS` *a cycle ago* was SEQ (the master
  holds SEQ for the whole beat; a flush in the boundary cycle cannot raise
  NONSEQ because `~Flush` gates it). Looking at `HTRANS` combinationally would
  loop — Wally's `HTRANS` mux depends on `HREADY`. After a flush the bridge
  drains silently; the master only issues a new NONSEQ while `HREADY=1`, so it
  waits for IDLE.
- One pending slot: an address phase that completes while the bridge is busy
  (at the final beat's pulse, or in a turnaround state when the uncore's
  delayed select is "none") is latched and started next. No `HREADYOUT` is
  ever asserted while it is pending, or its stalled data phase would complete
  with garbage.
- Address phase: latched (`HADDR[31:0]`, `HWRITE`, `HSIZE[2:0]`, `HWSTRB[7:0]`, `HBURST==INCR8`; 45 flops) when it completes on the *uncore's* `HREADY` with `HTRANS==NONSEQ` — SEQ beats belong to the burst in flight, and the previous data phase may be the APB bridge's. A latch is unavoidable: in AHB the data phase of beat 0 overlaps the address phase of beat 1, so `HADDR` has moved on by the time the header is driven.
- Write: drive `HWDATA` as four words, least significant first; pulse `HREADYEXT` on the fourth. AHB holds the beat.
- Read: assemble four words into a 64-bit beat register; pulse `HREADYEXT`. No FIFO — an AHB-Lite master cannot back-pressure read data.
- Ignore `HADDR` after the first beat (the ebu re-presents it per beat; the FPGA increments).
- Contents: 36-FF address/attribute latch ×2 (working + pending), 48-FF beat register (the last word goes straight to `HRDATA`), 5-bit word counter, TA counter, 8-state FSM, output enable = `dir`. Implemented: `hdl/forte_link_master.sv`.
- All inbound pins (`io` while `dir=0`, `ready`, `rvalid`) captured on negedge, re-registered on posedge (§6).
- No error path. `HRESPEXT = 0` always.

## 6. Clocking and bring-up

Link clock = core clock, sourced by the FPGA. No PLL, no CDC on the ASIC, no
forwarded clock. **Link clock <= ~50 MHz.**

The ASIC's flops see `clk` late by pad + clock-tree insertion (*ins*, ~1-2 ns,
+-30-50 % over PVT). That creates one hazard and one nuisance:

- **FPGA -> ASIC hold.** If FPGA Tco + trace < *ins*, a posedge capture on
  the ASIC samples the new word. Fix: **capture all inbound pins (`io` when
  `dir=0`, `ready`, `rvalid`) on the falling edge**, then re-register on
  posedge. Hold margin = T/2 + *ins* - Tco - trace; setup needs
  T/2 > *ins* + Tco + trace + Tsu ~ 6 ns, i.e. link <= ~80 MHz.
- **ASIC -> FPGA setup.** Needs T > *ins* + Tco + trace + Tsu ~ 5-6 ns.
  Met by frequency; the FPGA centres its IDELAYE3 taps during training.

The FPGA measures *ins* empirically: IDELAY sweep on the LFSR pattern for the
inbound direction, output-phase sweep (ODELAY or MMCM) on the echo for the
outbound. The post-CTS SDC check (real I/O delays, propagated clock) must show
the inbound hold path passing on negedge capture; that is the proof this
reasoning holds for the actual tree. `status` heartbeat is the clock-alive
indicator. Async FIFOs are still the wrong tool: they move a frequency
boundary, not a phase one.

If the link ever needs to run faster than ~50 MHz, add one `clk_out` pad
(core clock forwarded from the same pad ring as `io`) and lock the FPGA's
capture and launch to it; then *ins* drops out of both paths.

**Superseded in part — see `docs/impl_plan_link_clocking.md` (2026-10-01).**
The ~83 MHz ceiling this section derives is below the 100 MHz `options.json`
already targets, so the negedge scheme as it stands does not meet the
configured clock. That document compares three fixes (negedge as-is, an early
clock-tree tap for the inbound flops, and a separate link clock domain with
async FIFOs). It also retires training: phase calibration is deletable, and
the LFSR is unnecessary because the first fetch is deterministic and `rst_n`
is an FPGA output, so the gate can live on the FPGA. Controlled lane coverage
comes from a loopback mode instead -- less silicon than the LFSR and more
capable, since the FPGA picks the pattern. `hdl/forte_link_train.sv` is
slated for deletion.

**Reset / training sequence**

1. FPGA loads kernel + initramfs; `rst_n` low.
2. `rst_n` released; wrapper holds SoC internal `reset` (existing `reset_ext`/`reset` split).
3. Bridge enters `TRAIN`: LFSR pattern on `io[15:0]`, `dir=1`, 2^12 cycles. FPGA centres IDELAY. `status=0`.
4. `dir=0`; FPGA echoes the pattern while sweeping its output phase. Match → `status=1`, SoC reset released, fetch from `0x8000_0000`. N failures → stay in reset, `status` low (dead link visible on the LED).

Cost: a 12-bit counter and a 32-bit LFSR.

## 7. Verification

1. **Protocol-in-the-loop regression.** Link model speaking address/data words on one side, existing `mem_itf` on the other, in place of `masked_memory`. Whole Spike + RVFI suite runs through the real protocol unmodified. Highest value per hour.
2. **Abort torture.** Mispredicts during I-fetch, `fence.i`, traps during fill, interrupts during writeback.
3. **FPGA proof.** Port `fpga/pynq/` flow to VCU118; real `link_slave`; FreeRTOS suite + pruned Linux boot over the actual protocol before tapeout.
4. **Gate-level + SDF** on pad ring, turnaround, abort paths.
5. **Regress with `USE_SRAM=1`** at least once before freeze.
6. **Split the top.** ASIC top is a separate module from `rv64_core_wrapper.sv` so RVFI taps cannot reach synthesis.

## 8. Deferred

- Implicit sequential addressing (skip `req` for `last + 64`): 2 of 38 cycles, adds decode. No (BRINGUP.md §2 agrees: address costs time, not pins).
- Sideband next-address over the idle `req` pin during reads (needs a tap before `ebufsmarb`). Phase 2 at most.
- Error pin / in-band error status. Not in v1; FPGA logs errors.
- Separate link/core clocks. Only if needed; FIFO boundary already placed for it.

## 9. Open items

| Item | Recommendation |
|---|---|
| Option A, B or C (§2) | B (BRINGUP.md agrees); C only if a scope-probeable console outweighs breaking the snoop tooling |
| L1 way size: 2 KiB (config) or 4 KiB (BRINGUP.md, measured 2.57× faster boot)? | 4 KiB if macro area allows — it is the VIPT ceiling and the only performance lever left at 16 bits. **Measured 2026-09-20 on the PYNQ-Z2, ASIC top over the link from DDR: Linux to userspace in 326.5 M cycles vs 155.3 M native — 2.10×, all of it line serialization (3.25 M line reads × ≈34 cycles at 16 bits/cycle), not latency.** Every line the I-cache does not miss is 34 cycles back. |
| VCU118 bank / FMC pins for the link | One bank for the whole link; match pad-library I/O voltage to it |
| Link clock target | <= 50 MHz; above that, add `clk_out`. The 2.10× above is at link clk = core clk; a faster link clock is the second lever after cache size (stage C of `impl_plan_fpga_linux.md`) |
| Linux rootfs | Initramfs in the 256 MB window |
| ~~`size[1:0]` on dedicated pads instead of address bits 30:29?~~ | **Settled 2026-09-30: neither.** A third header word on singles costs 0 pads and ~0 cycles (bursts skip it) and carries the real `HWSTRB` as well, so the address goes over whole. §4. |
| Power/ground count (BRINGUP.md open item 6) | Eats the spare pads first; 11 is a placeholder |
| Scan: 1 or 2 chains, CSRs stitched to the front, chain map generated (BRINGUP.md open items 2–3) | 2 chains, CSRs first, map generated by the DFT flow |
| `halt_req` pad (+1) | Skip for v1 |

## 10. Integration with Wally

```
forte_top                      ASIC top, pads only. DESIGN_TOP for synth/lint.
├─ pad cells                    io[15:0] bidir (OE = dir), inputs with pulls
└─ forte_chip                  pad-less; what scan insertion and gate-level sim see
   ├─ forte_rst_sync           async assert, 2-FF release; core reset held until trained
   ├─ forte_link_train         LFSR + counter + status FSM; releases core reset
   ├─ forte_soc                replaces wallypipelinedsoc
   │  ├─ wallypipelinedcore #(P)   unmodified CVW
   │  └─ forte_uncore             adrdecs, CLINT, UART (C), ahbapbbridge, ext port, muxes
   ├─ forte_link_master        AHB-Lite slave on the ext port -> 16-bit address/data words; drop-in for ahb_to_memitf
   ├─ irq_sync                  meip/seip 2-FF
   └─ scan_mux                  test_mode: io[7:0] -> scan_in, scan_out -> io[15:8]

hdl/forte_link_pkg.sv          TA, word counts, size-in-address encoding: one source of
                                truth for the bridge, the TB link model, and the VCU118 link_slave
```

The seam: `forte_link_master` consumes exactly the external-AHB signals
`wallypipelinedsoc` exposes and `ahb_to_memitf` consumes today
(`rv64_core_wrapper.sv:190-210`). Nothing above or below it changes when the
bridge goes in.

| Phase | Work | Gate |
|---|---|---|
| 0 Refactor | Move RVFI taps from `rv64_core_wrapper` into `hvl/common/rvfi_tap.sv`, `bind`-attached to `wallypipelinedcore`; monitor refs move with them | Bit-identical RVFI stream and IPC on the full suite |
| 1 `forte_soc`/`forte_uncore` | Wrap `wallypipelinedcore`; GPIO/SPI/SDC gone; PLIC per §2. Config: `GPIO/SPI_SUPPORTED=0`; `PLIC_SUPPORTED=1` kept for PMA, `HSELPLIC` folded into `HSELEXT` | Full suite + Linux boot green; synth area delta |
| 2 Link | `forte_link_master` + TB `link_model` (words -> `mem_itf`), selectable `LINK=1`; `ahb_to_memitf` stays as reference | Full suite through the link; abort torture; IPC budget; SVA clean |
| 3 Reset/train | Sequencer holds core reset until echo matches; `status`; IRQ sync | Directed reset/IRQ tests; training-failure test keeps core in reset |
| 4 `forte_top` | Pad models, scan mux, `DESIGN_TOP=forte_top`, real SDC | Synth + lint clean; gate-level smoke with SDF; `USE_SRAM=1` regression |
| 5 VCU118 | `link_slave` from `forte_link_pkg`; TB `link_model` reused to self-check it | FreeRTOS + Linux on FPGA over the real protocol |

## 11. Verification plan

- **Two DUTs in CI.** `DUT ?= rv64_core_wrapper` in `sim/Makefile`; `forte_top` is a second matrix entry. Legacy path is the reference until tapeout.
- **`link_model` checks, not just transacts.** One link transaction per AHB burst (bound monitor on the ext port compares address/data/length); never X on `io` while `dir=1`; never drives while `dir=1` or inside a TA window; word-count integrity. Randomised `ready` back-pressure and `rvalid` gaps from a plusarg seed.
- **SVA in the bridge** (`ifndef SYNTHESIS`): never IDLE mid-transfer; `HREADYEXT` only with a complete beat; `dir` and `rvalid` mutually exclusive; `HADDR[55:32]==0` and `HADDR[30:29]==0` on every `req`; TA respected on every `dir` edge.
- **Abort torture** (directed asm): mispredicted branches across line boundaries; `fence.i` storms; timer interrupts with tiny `mtimecmp` deltas during `tc_mem_stress` writebacks. Coverage counter "transfer completed after core went IDLE" must be nonzero.
- **Cross-mode equivalence.** Same test with `LINK=0` and `LINK=1`; Spike checks each, so a divergence is localised to the bridge.
- **IPC budget** via `sim/get_ipc.sh`: link-mode IPC >= agreed fraction of direct-mode, per test; a latency regression fails CI.
- **SDC rewrite.** `synth/constraints.sdc` is the class template (0.2 ns in / 0.1 ns out). Needs real min/max I/O delays on `clk` (FPGA Tco + trace), negedge capture on inbound pins, propagated clock post-CTS so the inbound hold path is actually checked, tri-state modelling for `io`, `set_dont_touch` on pads.
- **Gate-level + SDF** on one FreeRTOS test through the link; **`USE_SRAM=1`** full regression once before freeze.
