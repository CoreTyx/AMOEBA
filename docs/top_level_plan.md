# AMOEBA Top-Level Wrapper: Pad Ring and Off-Chip Link

**Rev 1.0 · 2026-09-15 · Partition decided: on-chip PLIC + UART (Option A) is the primary config; implemented on `feature/top_level`, Linux boots over the link in simulation (see `docs/impl_plan_onchip_periph.md` §0)**

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
| No on-chip memory (`UNCORE_RAM`, `DTIM`, `IROM` all 0) | `pkg/config_asic.vh` | Every L1 miss crosses the link; the link *is* the memory system |
| `RESET_VECTOR = 0x8000_0000` = `EXT_MEM_BASE` | `pkg/config_asic.vh` | First instruction fetch is off-chip; link must be trained before the core leaves reset |
| Line = 512 b, `AHBW = 64`, `BURST_EN = 1` | `pkg/config_asic.vh`, `buscachefsm.sv:153` | Off-chip traffic is ~100 % 64 B **INCR8 from a line-aligned base** (no wrap, no critical-word-first) |
| All regions < 4 GB, bits 30:29 zero | `pkg/config_asic.vh` | Address is two 16-bit words; `HSIZE` rides in bits 30:29 of the high word |
| Linux is a silicon deliverable | — | Miss penalty is the chip's performance; every spare pad wants to be bus width |
| 52 pads **total** incl. 11 power/ground | `fpga/asic/BRINGUP.md` §2 | 32-bit bus does not fit; 16-bit bidir with scan muxed onto it |
| CVW aborts bursts on `FlushD` | `ebu`, prior FPGA debug | Bridge must never abort an off-chip transfer (§5) |
| `ZICNTR=0`, `SSTC=0` in the ASIC config | `pkg/config_asic.vh` | Core never consumes `MTIME_CLINT`; CLINT stays on-die anyway (~2 k GE, `mtime` = core cycles, BRINGUP.md §2) |
| `USE_SRAM` = `ifdef AMOEBA_USE_SRAM` | `pkg/config_asic.vh` | Sim/netlist mismatch risk; regress with macros before freeze |

## 2. Partition

**Always on-chip:** core, I$/D$, CLINT, link bridge, pad ring, scan mux.
**Always off-chip:** memory (DDR4 via MIG at `0x8000_0000`), SPI, GPIO, SDC.
**Open:** PLIC and UART.

Note on hierarchy: `wallypipelinedcore` is the pipeline + AHB master + interrupt
inputs; it has no peripherals. UART/CLINT/PLIC/decoder live in `uncore`, which
`wallypipelinedsoc` wraps. The plan instantiates `wallypipelinedcore` directly
under a new `amoeba_uncore` (§10), so the peripheral set is ours to choose and
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
| CVW changes | none | `amoeba_uncore` | `amoeba_uncore` |

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
| `hdl/amoeba_uncore.sv` (new, from `uncore.sv`) | Keep `adrdecs`, CLINT, `ahbapbbridge`, ext port, `HRDATA`/`HREADY`/`HRESP` muxes, `hseldelayreg`. Keep UART (C) or drop it (B). No PLIC: fold `HSELPLIC` (and `HSELUART` for B) into `HSELEXT` and its delayed copy. `MExtInt`/`SExtInt` become inputs. |
| `hdl/amoeba_soc.sv` (new, from `wallypipelinedsoc.sv`) | `wallypipelinedcore` + `amoeba_uncore`. Ports: AHB ext port, `meip`/`seip`, `UARTSin`/`UARTSout` (C). |
| ASIC top | Tie off removed ports; 2-flop synchronisers on `meip`/`seip`. |
| Testbench link model | Instantiate CVW `plic_apb` + `uartPC16550D` behind it so CI runs unchanged. |
| Untouched | Every file under `hdl/core/`, `cvw_t`, `parameter-defs.vh`, Linux DTS (except dropping `interrupts` on the UART node for polled mode), OpenSBI. |

`HREADY`/`HRESP` muxes in `uncore.sv` already OR in the `HSELEXTD` terms, so
wait states are inherited for free (there is no error path; `HRESPEXT` is tied low).

## 3. Pad list — 52 total

| # | Pad | Dir | Function |
|---|---|---|---|
| 1–11 | VDD core ×3, VDD IO ×3, GND ×5 | — | BRINGUP.md §2 placeholder until PDK IO cells and current draw are known. Spare pads below go here first. |
| 12 | `clk` | in | Single clock from FPGA. Core and link. No PLL. |
| 13 | `rst_n` | in | Async assert, sync release. FPGA holds low until memory loaded. |
| 14–29 | `io[15:0]` | bidir | Address words when `req=1`, else data words. Scan I/O in test mode. |
| 30 | `dir` | out | **1 = ASIC drives `io`, 0 = ASIC has released it.** Single source of truth for bus ownership; TA idle cycles guaranteed on every change. |
| 31 | `req` | out | `io` carries the address: high half, then low half, on consecutive cycles. Held for both. |
| 32 | `wr` | out | Held for the transaction. 1 = write. |
| 33 | `burst` | out | Held. 1 = 8 beats (32 words), 0 = 1 beat (4 words). |
| 34 | `ready` | in | **"May start."** ASIC begins `req` only when `ready=1` was sampled; once started the FPGA is committed. Registered on FPGA side. |
| 35 | `rvalid` | in | Read data word on `io` this cycle. Gaps allowed. |
| 36–37 | `meip`, `seip` | in | M/S external interrupt from the FPGA. Level, 2-flop sync. (Option A: `irq[1:0]` into on-chip PLIC IDs 3, 6.) |
| 38 | `test_mode` | in | `io[7:0]` → `scan_in[7:0]`, `io[15:8]` → `scan_out[7:0]`. Up to 8 chains; BRINGUP.md wants 1–2 with CSRs at the front. |
| 39 | `scan_en` | in | Shift / capture. |
| 40 | `status` | out | Link-trained, then heartbeat, or sticky halted. Drives an LED. |
| (41–42) | `uart_tx`, `uart_rx` | out/in | **Options A and C only.** |
| (43) | `uart_irq` | out | **Option C, optional.** |

**Used: B = 40, A/C = 42 (43 with `uart_irq`). Spare: 12 / 10.** Spend spares
in this order: (1) power/ground once the real SSN number for 16 bidirectional
pads is known, (2) a dedicated `scan_out` so a scan dump does not need the
bus released, (3) nothing else — do not widen the bus to 24 (512 b does not
divide evenly).

Match the pad-library I/O variant to the VCU118 bank the link lands in (HP
≤ 1.8 V, HR ≤ 3.3 V).

## 4. Link protocol

Bus content is only ever an address or data. Transaction type lives on pins,
held for the whole transaction. Nothing on the bus is decoded by either side.
This is BRINGUP.md §2's "command + 32-bit address" header with the command
beat replaced by the `wr`/`burst` pins: one cycle shorter and readable on a
scope.

```
req=1, cycle 0   io[15:0] = HADDR[31:16]   bits 30:29 carry HSIZE[1:0] (always zero
req=1, cycle 1   io[15:0] = HADDR[15:0]    in every configured region); bits 2:0 = byte offset
otherwise        io[15:0] = data word       64-bit beat as 4 words, least significant first
wr, burst        held from req until the last word
```

`ready` means "may start": the ASIC issues `req` only after sampling
`ready=1`, and the FPGA, having said so, accepts the whole transaction —
it holds ≥ 32 words of write buffer. There is no mid-transaction handshake
in either direction, so the ASIC never stalls once started. The FPGA
regenerates byte strobes from size + offset with the same `size_to_mask` as
`ahb_to_memitf.sv`; the ASIC lane-selects reads itself. Beat *n* of a burst
is at `base + 8n` (CVW is INCR8 from an aligned base); the FPGA increments.
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

| Transaction | Sequence | Cycles |
|---|---|---|
| Line read | `req`×2 · `dir`↓ · TA · 32 × `rvalid` words · TA · `dir`↑ | 34 + 2·TA (38 @ TA=2) |
| Line write | `req`×2 · 32 words | 34 |
| Single read | `req`×2 · TA · 4 words · TA | 6 + 2·TA |
| Single write | `req`×2 · 4 words | 6 |

Plus FPGA memory latency as `rvalid` gaps. 38 link cycles + L2/MIG latency is
a ~50–70 cycle miss at 1:1 clocks — the same range as a DRAM miss on a
commodity part (BRINGUP.md §2 reaches the same conclusion at 35). The
FPGA-side L2 (BRINGUP.md §3) is what keeps the crossing the only cost.

Width, per 64 B line: 16 b muxed = **38/34** cycles (read/write); 32 b muxed
= 21/17 but needs 56 pads; 8+8 split = 68/68; 16 b DDR = 20/18 but rejected
as a bring-up risk. 16 b bidirectional is the only one that fits.

## 5. Bridge: `amoeba_link_master` (~400–500 GE)

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
- Address phase: latched (`HADDR[31:0]`, `HWRITE`, `HSIZE[1:0]`, `HBURST==INCR8`; 36 flops) when it completes on the *uncore's* `HREADY` with `HTRANS==NONSEQ` — SEQ beats belong to the burst in flight, and the previous data phase may be the APB bridge's. A latch is unavoidable: in AHB the data phase of beat 0 overlaps the address phase of beat 1, so `HADDR` has moved on by the time the header is driven.
- Write: drive `HWDATA` as four words, least significant first; pulse `HREADYEXT` on the fourth. AHB holds the beat.
- Read: assemble four words into a 64-bit beat register; pulse `HREADYEXT`. No FIFO — an AHB-Lite master cannot back-pressure read data.
- Ignore `HADDR` after the first beat (the ebu re-presents it per beat; the FPGA increments).
- Contents: 36-FF address/attribute latch ×2 (working + pending), 48-FF beat register (the last word goes straight to `HRDATA`), 5-bit word counter, TA counter, 8-state FSM, output enable = `dir`. Implemented: `hdl/amoeba_link_master.sv`.
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
| `size[1:0]` on dedicated pads instead of address bits 30:29? | No; assertion covers it |
| Power/ground count (BRINGUP.md open item 6) | Eats the spare pads first; 11 is a placeholder |
| Scan: 1 or 2 chains, CSRs stitched to the front, chain map generated (BRINGUP.md open items 2–3) | 2 chains, CSRs first, map generated by the DFT flow |
| `halt_req` pad (+1) | Skip for v1 |

## 10. Integration with Wally

```
amoeba_top                      ASIC top, pads only. DESIGN_TOP for synth/lint.
├─ pad cells                    io[15:0] bidir (OE = dir), inputs with pulls
└─ amoeba_chip                  pad-less; what scan insertion and gate-level sim see
   ├─ amoeba_rst_sync           async assert, 2-FF release; core reset held until trained
   ├─ amoeba_link_train         LFSR + counter + status FSM; releases core reset
   ├─ amoeba_soc                replaces wallypipelinedsoc
   │  ├─ wallypipelinedcore #(P)   unmodified CVW
   │  └─ amoeba_uncore             adrdecs, CLINT, UART (C), ahbapbbridge, ext port, muxes
   ├─ amoeba_link_master        AHB-Lite slave on the ext port -> 16-bit address/data words; drop-in for ahb_to_memitf
   ├─ irq_sync                  meip/seip 2-FF
   └─ scan_mux                  test_mode: io[7:0] -> scan_in, scan_out -> io[15:8]

pkg/amoeba_link_pkg.sv          TA, word counts, size-in-address encoding: one source of
                                truth for the bridge, the TB link model, and the VCU118 link_slave
```

The seam: `amoeba_link_master` consumes exactly the external-AHB signals
`wallypipelinedsoc` exposes and `ahb_to_memitf` consumes today
(`rv64_core_wrapper.sv:190-210`). Nothing above or below it changes when the
bridge goes in.

| Phase | Work | Gate |
|---|---|---|
| 0 Refactor | Move RVFI taps from `rv64_core_wrapper` into `hvl/common/rvfi_tap.sv`, `bind`-attached to `wallypipelinedcore`; monitor refs move with them | Bit-identical RVFI stream and IPC on the full suite |
| 1 `amoeba_soc`/`amoeba_uncore` | Wrap `wallypipelinedcore`; GPIO/SPI/SDC gone; PLIC per §2. Config: `GPIO/SPI_SUPPORTED=0`; `PLIC_SUPPORTED=1` kept for PMA, `HSELPLIC` folded into `HSELEXT` | Full suite + Linux boot green; synth area delta |
| 2 Link | `amoeba_link_master` + TB `link_model` (words -> `mem_itf`), selectable `LINK=1`; `ahb_to_memitf` stays as reference | Full suite through the link; abort torture; IPC budget; SVA clean |
| 3 Reset/train | Sequencer holds core reset until echo matches; `status`; IRQ sync | Directed reset/IRQ tests; training-failure test keeps core in reset |
| 4 `amoeba_top` | Pad models, scan mux, `DESIGN_TOP=amoeba_top`, real SDC | Synth + lint clean; gate-level smoke with SDF; `USE_SRAM=1` regression |
| 5 VCU118 | `link_slave` from `amoeba_link_pkg`; TB `link_model` reused to self-check it | FreeRTOS + Linux on FPGA over the real protocol |

## 11. Verification plan

- **Two DUTs in CI.** `DUT ?= rv64_core_wrapper` in `sim/Makefile`; `amoeba_top` is a second matrix entry. Legacy path is the reference until tapeout.
- **`link_model` checks, not just transacts.** One link transaction per AHB burst (bound monitor on the ext port compares address/data/length); never X on `io` while `dir=1`; never drives while `dir=1` or inside a TA window; word-count integrity. Randomised `ready` back-pressure and `rvalid` gaps from a plusarg seed.
- **SVA in the bridge** (`ifndef SYNTHESIS`): never IDLE mid-transfer; `HREADYEXT` only with a complete beat; `dir` and `rvalid` mutually exclusive; `HADDR[55:32]==0` and `HADDR[30:29]==0` on every `req`; TA respected on every `dir` edge.
- **Abort torture** (directed asm): mispredicted branches across line boundaries; `fence.i` storms; timer interrupts with tiny `mtimecmp` deltas during `tc_mem_stress` writebacks. Coverage counter "transfer completed after core went IDLE" must be nonzero.
- **Cross-mode equivalence.** Same test with `LINK=0` and `LINK=1`; Spike checks each, so a divergence is localised to the bridge.
- **IPC budget** via `sim/get_ipc.sh`: link-mode IPC >= agreed fraction of direct-mode, per test; a latency regression fails CI.
- **SDC rewrite.** `synth/constraints.sdc` is the class template (0.2 ns in / 0.1 ns out). Needs real min/max I/O delays on `clk` (FPGA Tco + trace), negedge capture on inbound pins, propagated clock post-CTS so the inbound hold path is actually checked, tri-state modelling for `io`, `set_dont_touch` on pads.
- **Gate-level + SDF** on one FreeRTOS test through the link; **`USE_SRAM=1`** full regression once before freeze.
