# Implementation Plan: FPGA emulation of the frozen `forte_top`, driven like the bring-up FPGA

**Rev 0.2 · 2026-10-28 · branch `fpga/rtl_freeze` (worktree `rtl_freeze_fpga_em`), forked from `postsynth_verif` @ `8babc55` (confirmed as the freeze base)**

Rev 0.2: team answers folded in (§12). `fault_inject` becomes a PS-controlled
fault-tolerance knob with a phase-aware pattern generator (§5.4.1); DFT tests
are deferred but `fbu_scan` is still built; the split-clock build is required
(§3.4, P5); the ribbon loopback moves to the backlog (§13); FPGA-only script
commands live in their own dialect, and `hvl/pin/` is not touched (§10.3).

Goal: put the frozen ASIC top, `hdl/forte_top.sv`, **unmodified**, into the
PYNQ-Z2 fabric. Surround it with gateware that talks to it **through its 32
signal pins only**, exactly as the bring-up FPGA will talk to the die. Then
stress every pin group from PS-side firmware:

- the control interface (`rst_n`, `irq[1:0]`, `fault_inject`, `test_mode`, `scan_en`)
- the data interface (`io[15:0]`, `dir`, `req`, `wr`, `ready`, `rvalid`, `clk_out`)
- the console (`uart_tx`, `uart_rx`)
- the status interface (`status`)

There is a second goal, and it matters as much as the first. The gateware
written here *is* the bring-up FPGA's gateware. It is written board-agnostic,
proven against the frozen RTL on the PYNQ, and ported to the bring-up board
later. Every bug found in it now is one that is not found with a socketed
die on the bench.

Sources this plan builds on, all read for it:

| Source | What it contributes |
|---|---|
| `hdl/forte_top.sv`, `forte_chip.sv`, `forte_link_{pkg,core,phy}.sv`, `forte_dft_lock.sv`, `forte_uncore.sv` | The DUT and its pin contract |
| `docs/top_level_plan.md` §3 (rev 1.1) | The admitted pinout and link protocol. **Authoritative**; §4–§6 there are partly historical |
| `hvl/pin/` (`pin_tb.sv`, `pin_link_agent.sv`, `pin_uart_agent.sv`, `tests/*.cmd`) | The bring-up FPGA *in simulation*. It is the executable spec for the gateware and the source of the command-script language |
| `feature/top_level` @ `083c49b`: `fpga/pynq/**`, `docs/impl_plan_fpga_linux.md` | The previous ASIC-in-fabric effort (`amoeba_top` + `amoeba_link_slave`). Stage A/B passed on the board, including Linux over the link |
| `fpga/linux_boot` @ `fbcde0d`: `fpga/pynq/**`, `fpga/asic/BRINGUP.md` | The PS↔PL infrastructure (block design, `amoeba_ctl`, `sw/amoeba/`), the DDR path and the bring-up ladder |

---

## 1. What changed since the last FPGA run, and why this is not a recompile

`feature/top_level` ran `amoeba_top`. The frozen top differs on every axis the
gateware touches:

| Aspect | `amoeba_top` (last on FPGA) | `forte_top` (frozen) | Consequence for the gateware |
|---|---|---|---|
| Link header | 2 words + a 3rd attribute word for singles | 2 words; no singles; `BEATS = 128/64 = 2` | `amoeba_link_slave` cannot be reused as is. Port it to `forte_link_pkg` |
| Burst | INCR8 (512-bit line) | 2 beats per line (`HBURST = INCR`, undefined length) | The memory backend sees 16-byte lines, not 64-byte |
| Training | LFSR training plus echo; `status` = trained | None. The FPGA checks the first header (`0x8000`,`0x0000`,`wr=0`) and re-asserts `rst_n` if it is wrong | A **boot gate** moves into the gateware |
| Pins | `burst` pin | `burst` → `clk_out`; `fault_inject` added | New pin drivers and monitors |
| Clocking | One domain | `core_clk` and `link_clk` domains with async FIFOs (`prim_fifo_async`), tied to one pad in `forte_top` | Nothing to do in the default build. The split-clock build (§3.4, P5) is how the FIFOs get stressed |
| Ready | Handshake-ish | Advisory, with `GUARD = 3`: the slave must drop `ready` while it still has room for one more transaction | The ready policy becomes a test knob |
| Status | Trained + heartbeat | Three rates from a free-running counter: 2^23 (stalled), 2^25 (active), 2^27 (quiet) half-periods | Measured exactly in the PL (§5.7) |
| Security | none | DFT lock at `0x0200_F000` (sticky, ANDs `test_mode`/`scan_en`); `FI_CONTROL` at `0x1007_000B` (8 units, **resets to 0**); 18 fault counters at `0x1008_0000` | New control-interface tests (§7.1) |
| Memories | Behavioural arrays | Under `SYNTHESIS`, `USE_SRAM=1`: `rf_sp_*` and `sram_sp_*` macro wrappers | FPGA stand-ins for 13 macros (§4.2) |
| Console | AHB snoop by hierarchical reference | `uart_tx`/`uart_rx` pins only | The UART transceiver becomes the *only* console |

**Design rule for this effort: pins only.** The old wrapper reached into the
die with hierarchical references (`top.chip.soc.core.*`) for the console,
`tohost`, the retired count and the trace. None of that exists on silicon. The
default build has **no** hierarchical taps. An optional `EMU_TAPS` build adds
retired/trap counters as an *oracle only* (§4.4). No pass/fail decision may
depend on it, so every test also runs on the real die.

---

## 2. Branch and directory setup

Done:

```
git worktree add -b fpga/rtl_freeze ../rtl_freeze_fpga_em postsynth_verif
```

Next (step P0.1). Import the FPGA tree from the branch that has the ASIC-wrapper
work, and leave `hdl/` exactly as frozen:

```
git checkout feature/top_level -- fpga/ docs/impl_plan_fpga_linux.md
```

`fpga/linux_boot` is an ancestor of `feature/top_level`, so this brings both.
The `amoeba_*` ASIC files that `fpga/pynq` referenced from `hdl/` (`amoeba_top`,
`amoeba_link_master`, `amoeba_link_train`, ...) are **not** imported. The
`DUT=asic` path that needs them is retired on this branch, and only `DUT=soc`
(soft core, regression baseline) and `DUT=forte` remain.

**Rule: nothing under `hdl/` or `pkg/` changes on this branch.** A CI check
(`fpga/scripts/check_frozen.sh`) diffs `hdl/ pkg/ sram/` against the freeze
commit and fails on any change. FPGA-specific behaviour comes from **replacement
modules for cells the RTL instantiates by name** (pads, SRAM macros) and from
nothing else.

### 2.1 Directory layout

```
fpga/
  bringup/                    BOARD-AGNOSTIC bring-up gateware: goes to the bring-up board unchanged
    rtl/
      fbu_pkg.sv              register offsets, error codes, trace record format, line-if types
      fbu_link_slave.sv       far end of forte_link_pkg: header capture, read serve, write collect
      fbu_link_check.sv       synthesizable port of pin_link_agent's checks + lane coverage
      fbu_link_trace.sv       transaction trace ring (pin_trace.log-compatible records)
      fbu_pin_ctl.sv          rst_n sequencer, boot gate, irq/test pins, triggers
      fbu_fi_gen.sv           fault_inject pattern generator, phase mirror of the chip's fault generator (§5.4.1)
      fbu_line_cdc.sv         async FIFO pair for the line interface (split build; the bring-up board needs it too)
      fbu_scan.sv             test-mode driver: io[7:0] out, io[15:8] in, pattern + capture RAMs (built; tests deferred)
      fbu_uart.sv             8N1 RX from uart_tx, TX into uart_rx, fractional baud, error injection
      fbu_status_mon.sv       status half-period meter + classifier; clk_out edge counter
      fbu_mailbox.sv          optional "magic memory" window: event log + PS-supplied read data
      fbu_regs.sv             AXI4-Lite register file for all of the above (map in §6)
      fbu_top.sv              ties the above together; ports = the 32 chip pins + line-if + AXI-Lite
    tb/
      tb_fbu_vs_pin.sv        fbu_top vs pin_link_agent on forte_top, trace-compared (§8.1)
  pynq/                       board-specific (Zynq-7020)
    rtl/
      emu/emu_pads.sv         io_in / io_out / io_tri stand-ins (from hvl/pin/models/pad_behav.sv)
      emu/emu_srams.sv        rf_sp_* / sram_sp_* stand-ins mapped to BRAM/LUTRAM
      emu/emu_taps.sv         EMU_TAPS only: retired/trap counters by hierarchical reference
      forte_emu_dut.sv        forte_top + in-fabric pin wiring + fbu_top
      fbu_mem_bram.sv         line backend: 128-bit dual-port BRAM, port B on AXI-Lite for PS load
      fbu_mem_axi_hp.sv       line backend: native AXI3 master on S_AXI_HP0 to the DDR carve-out
      forte_pynq_top.sv       PL top for DUT=forte (+ _v.v Verilog shim for IPI, as today)
      split/forte_top_split.sv  SPLIT build: forte_top's pad ring with a separate link_clk pin, frozen forte_chip inside (§3.4)
      split/fbu_clkgen.sv     SPLIT build: core/link MMCMs, DRP retune, BUFGCE link_clk pause
    tcl/bd_pynq.tcl           + DUT=forte branch (no ahblite_axi_bridge/protocol converter), CLOCKS=single|split
    constraints/forte_emu.xdc LEDs and PMOD JA: status, clk_out/16, uart_tx/uart_rx to a USB-serial
    tb/tb_forte_emu.sv        Verilator: whole PL top + PS model running .cmd scripts (§8.2)
    sw/forte/                 PS firmware, Python package (§10)
    sw/run_cmd.py, run_suite.py, trace_to_pin.py, check_regs_forte.py
  bringup/tests/              fe_*.c DUT programs, *.cmd scripts in the fbu dialect (§10.3), build.sh
  scripts/check_frozen.sh     also diffs split/forte_top_split.sv against hdl/forte_top.sv (one port allowed to differ)
hvl/pin/                      NOT modified: read-only source of the bench's .cmd scripts, models and PRNG
```

`fpga/bringup/` gets no Xilinx primitives and no PS assumptions: AXI4-Lite in,
a line interface out, the chip's pins on the side. The board-specific parts are
the memory backend, clocking and pin placement.

---

## 3. System architecture on the PYNQ-Z2

```
 PS (ARM, Linux, Python)                         PL (FCLK_CLK0 = core_clk, 25 MHz nominal)
 ───────────────────────                         ─────────────────────────────────────────────────────────
 sw/forte  ── M_AXI_GP0 ──► fbu_regs (0x43C0_0000) ─┬─ fbu_pin_ctl ── rst_n, irq[1:0], fault_inject,
                                                   │                  test_mode, scan_en ───────────┐
                                                   ├─ fbu_scan ─────── io[7:0] (test mode only) ────┤
                                                   ├─ fbu_uart ─────── uart_rx ─────────────────────┤
          ◄── uart RX FIFO, trace, counters ───────┤◄─────────────────── uart_tx ──────────────────┤   forte_top
                                                   ├─ fbu_status_mon ◄── status, clk_out ───────────┤   (frozen,
                                                   ├─ fbu_link_check ◄── all link pins (passive) ───┤    emu_pads,
                                                   ├─ fbu_link_trace                                │    emu_srams)
                                                   └─ fbu_link_slave ◄─► io[15:0], dir, req, wr, ───┘
                                                            │            ready, rvalid
                                                     line-if (16 B)
                                     ┌──────────────────────┴───────────────────────┐
                              fbu_mem_bram (MEM_BACKEND=BRAM)           fbu_mem_axi_hp (MEM_BACKEND=AXI)
                              port B ◄── M_AXI_GP0 (0x4400_0000)        S_AXI_HP0 ──► DDR carve-out 0x1000_0000
```

### 3.1 The in-fabric pin boundary

`forte_emu_dut.sv` instantiates `forte_top` and `fbu_top` and wires the 32 pins
as nets:

- **`io[15:0]`** is one `wire` with two tristate drivers: `forte_top`'s
  `io_tri` stand-ins (`t = ~io_oe`, per lane, as frozen) and `fbu_top`'s
  `assign io = fbu_io_oe ? fbu_io_o : 'z`. Vivado converts the internal
  tristate to mux logic. This is the same construction that passed stage A/B on
  `feature/top_level` (`amoeba_asic_wrapper.sv:233-241`). The per-lane
  `t` is preserved, so test mode's split direction (`io[7:0]` in, `io[15:8]`
  out) is real in the fabric.
- All other pins are plain nets.
- **Contention cannot be observed electrically in fabric.** The resolved mux
  silently picks one driver. `fbu_link_check` therefore enforces the rule at
  the pins: the FPGA drives `io` only while `dir=0`, after `TA`, with `rvalid`,
  and in test mode only on `io[7:0]`. Any violation is a sticky error. That is
  the same rule the bench enforces, and the same one the real board needs.

### 3.2 Clocking

- **Default:** one clock. `FCLK_CLK0` = `core_clk`, and `forte_top` ties
  `link_clk` to it internally. Target **25 MHz**: the soft core's HPTW→D$ path
  was 38 ns of 40 on both earlier DUTs. Expect the same here, and confirm at P2.
- `fbu_*` runs on the same clock. In-fabric "board timing" is degenerate:
  - The chip's negedge capture in `forte_link_phy` becomes a half-cycle fabric
    path from the FPGA's launch flops (20 ns at 25 MHz, easily met).
  - The FPGA samples chip outputs on the next `core_clk` posedge. `clk_out`
    is the same net in fabric, so `fbu_link_slave` has a `CAPTURE_CLK`
    parameter. On the PYNQ the capture flops use `core_clk` with
    `clk_out` counted and checked (§5.7). On the bring-up board they use
    `clk_out` through a BUFG/BUFR, as `docs/top_level_plan.md` §3.4 requires.
- **Split build:** two clocks, see §3.4.
- `pl.py`'s `set_fclk0_mhz` (existing) reprograms the FCLK at every run.
  `Forte.check_fclk()` verifies it against wall time, as `Amoeba` does.
- **UART consequence:** baud = `f_core / (32 · div)`. At 25 MHz, 115 200 baud
  is div 6.78, and no divisor is good: div 7 is −3.1 %. The PL UART is
  divisor-exact, so this only matters for the optional external USB-serial
  cable on PMOD. For that, run `FCLK_CLK0 = 22.1184 MHz` (div 6, exact) if the
  PS PLL can reach it, or use 57 600 baud at div 13 (+4.3 %, no). **Decision:**
  the PL UART is the reference console. The PMOD cable is a convenience at a
  frequency picked for it.

### 3.3 Reset domains

| Reset | Source | Resets |
|---|---|---|
| `aresetn` | `proc_sys_reset` from `FCLK_RESET0_N` | `fbu_regs`, counters, trace, UART FIFOs, memory port B. **Never** tied to `rst_n`: the old design deadlocked the PS when the BRAM load port was reset from the core's reset (`tb_mem_axi.sv`) |
| `rst_n` (pin) | `fbu_pin_ctl` | `forte_top` only, plus the slave's per-transaction state. The slave **observes** `rst_n` the way the board does (it drives it) |

`rst_n` comes out of configuration **asserted**, like `CTRL.CORE_RESET` today.

### 3.4 Split-clock build (`CLOCKS=split`, phase P5)

**Why.** `forte_top` ties `link_clk` to the `core_clk` pad, so in the default
build the two `prim_fifo_async` instances cross between identical clocks and
their Gray-pointer synchronizers are never really exercised. The split build is
the only place before silicon where that crossing runs with independent
clocks. It also puts the FPGA side in the bring-up board's situation: link
logic clocked by its own copy of the link clock and checked against the
returned `clk_out` (which `forte_chip` derives from `link_clk`), with the
memory on a third clock. Off-chip robustness is the point of this build.

**How, without touching the freeze.**

- `fpga/pynq/rtl/split/forte_top_split.sv` is `forte_top`'s pad ring
  copied line for line (same `emu_pads` stand-ins), with one extra input,
  `link_clk`, wired to `forte_chip.link_clk`. `forte_chip` and everything
  below it are the frozen files, unmodified. `check_frozen.sh` diffs the copy
  against `hdl/forte_top.sv` and allows exactly that one port and one
  connection to differ, so the copy cannot drift from the taped-out ring.
- It is labelled a **CDC stress build**, not the tapeout configuration.

**Clocks** (`fbu_clkgen.sv`):

| Clock | Source | Range |
|---|---|---|
| `core_clk` | MMCM0 from `FCLK_CLK0` | 25 MHz (or the P0 Fmax) |
| `link_clk` | MMCM1 from `FCLK_CLK1`, which comes from a **different PS PLL** than `FCLK_CLK0`, so the two are truly asynchronous and drift in phase. `LINK_SRC=mmcm0` takes it from MMCM0 instead, for repeatable rational ratios | link/core ≈ 0.37, 0.8, 1.0004 (slow beat), 1.6, 2.3, bounded by the link domain's Fmax that P0 measures separately |
| `aclk` | `FCLK_CLK0` | PS, registers, memory backend |

- **Runtime control:** MMCM1 retuned over DRP from the PS (while `rst_n` is
  held), and a BUFGCE that **pauses** `link_clk` for N cycles at a trigger,
  including mid-transaction. A paused clock is legal for synchronous logic, so
  the expected outcome is a slower link, not an error.
- `fbu_clkgen` measures `link_clk` against `core_clk` continuously
  (`LINK_FREQ_MEAS`) so every result records the ratio it actually ran at.

**Where the gateware runs:**

- `fbu_link_slave`, `fbu_link_check` and `fbu_link_trace` run on `link_clk`
  (the FPGA's copy) with `clk_out` checked against it. That is the bring-up
  board arrangement.
- `fbu_pin_ctl`, `fbu_fi_gen` and `fbu_uart` stay on `core_clk`. The UART baud
  is `core_clk`-derived, and the fault-inject phase mirror (§5.4.1) needs
  `core_clk`.
- The line interface crosses from `link_clk` to the backend's `aclk` through
  `fbu_line_cdc` (Xilinx-free async FIFOs, so it ports to the VCU118).
  Registers cross with a req/ack handshake.
- `rst_n` is released at a random phase with respect to both clocks.
  `forte_chip` synchronizes it separately per domain (`rstsync`,
  `linkrstsync`), so the two domains leave reset a variable number of cycles
  apart. This is a case the single-clock build cannot produce.
- **Status pin:** the heartbeat runs in the link domain (`forte_chip`: "a
  dead `link_clk` still freezes it"), so in the split build its half-periods
  are counted in `link_clk` cycles. `fbu_status_mon` measures in both clocks
  and checks against the link one.

**Correlation:** with asynchronous clocks a cycle-exact match with the pin
bench is impossible. `trace_to_pin.py --order-only` compares the transaction
sequence (addresses, data, R/W, abort flags) and ignores `cyc`.

**Pre-hardware:** `tb_forte_emu` gets a split variant. It runs Verilator with
two incommensurate clock periods, a random release phase and random pauses,
and P5 builds no bitstream until it passes the SPLIT group in simulation.

---

## 4. Emulation-only RTL (`fpga/pynq/rtl/emu/`, `forte_emu_dut.sv`)

### 4.1 `emu_pads.sv`

Vivado defines `SYNTHESIS`, so `forte_top` instantiates `io_in`, `io_out` and
`io_tri`. These are copies of `hvl/pin/models/pad_behav.sv` (three one-line
modules) so the FPGA and the pin bench model the pads identically. A
`check_frozen.sh` step diffs the two files' module bodies.

### 4.2 `emu_srams.sv`

`USE_SRAM=1` under `SYNTHESIS`, so the cache arrays go through
`hdl/core/generic/mem/ram1p1rwbe_*.sv` to these macros, all instantiated by the
frozen RTL:

`rf_sp_16_128, rf_sp_16_46, rf_sp_32_128, rf_sp_32_45, rf_sp_64_128,
rf_sp_64_137, rf_sp_64_44, rf_sp_64_46, rf_sp_64_53, sram_sp_128_137,
sram_sp_128_53, sram_sp_256_137, sram_sp_256_53`

They are derived from `hvl/pin/models/sram_behav.sv`: registered address,
combinational read from it, active-low `CEN`/`WEN`, **no byte enables** (the
wrappers do not connect `BWEB`). Mapping registered-address/async-read to a
synchronous BRAM read is exact, and Vivado infers BRAM from it. Two
FPGA-specific changes:

- `RETN !== 1` cannot read X in hardware. Instead, a sticky `emu_sram_retn_err`
  flag is ORed into a CAPS-visible error. It is set if any instance ever sees
  `RETN=0` while `CEN=0`.
- The padded macros (`rf_sp_32_45` is 48 wide at the port, and so on) keep
  their port widths exactly. That reproduces the wrapper's padding and
  dropping behaviour, which is part of what the netlist does.

This exercises the **same macro hookup as silicon** (the full-row write that
the D$ relies on merging into), which a `USE_SRAM=0` build would not.

### 4.3 `forte_emu_dut.sv`

`forte_top` + `fbu_top` + the `io` net (§3.1). Its parameters are
`PERIPH_ONCHIP = 1` (admitted) and nothing else. `forte_top` does not pass
`STATUS_*` through, so status rates are the silicon defaults, which is what we
want.

### 4.4 `emu_taps.sv` (`EMU_TAPS` builds only)

These are hierarchical references for **diagnosis**: retired instructions,
traps and current PC, from `forte_top.chip.soc.core.*`, as `amoeba_retire`
does today. They are exposed in a separate register page (`0xF00`), and
`CAPS[EMU_TAPS]` says they exist. Rules:

- No test's verdict reads them.
- Hierarchical names in a synthesized design are fragile. Vivado may not keep
  them through `flatten_hierarchy`, so the build uses `keep_hierarchy` on
  `forte_top`. If that changes timing or utilization materially, drop the taps
  rather than fight it.

---

## 5. Bring-up gateware (`fpga/bringup/rtl/`)

Each block lists its source to port from and its spec.

### 5.1 `fbu_link_slave.sv`: far end of the link

**Port from** `feature/top_level:fpga/pynq/rtl/amoeba_link_slave.sv` (structure,
counters, `IN_REG`) and `hvl/pin/pin_link_agent.sv` (behaviour, decisions,
checks). **Spec:** `docs/top_level_plan.md` §3.4 and `hdl/forte_link_pkg.sv`.

- **Parameters.** `BEATS = 2` (asserted against the build config at elaboration
  via `pkg/config.vh`), `TA = 2`, `GUARD = 3`, `MEM_BASE/LIMIT =
  0x8000_0000/0x8FFF_FFFF`, `RESET_VEC = 0x8000_0000`, `IN_REG`
  (extra capture stage, for real pins).
- **Header.** On `req` with `dir=1`, take `io` as `A[31:16]`, then `A[15:0]`.
  `wr` is sampled in header cycle 0.
- **Write.** Collect `W = 4·BEATS = 8` words back to back (no flow control
  exists). Assemble the line, then commit it to the line interface **only
  when complete**. If `rst_n` falls mid-write, the partial line is
  **discarded** and counted (`LINK_RST_ABORT`). Silicon cannot finish it, and
  committing half a line is how memory gets corrupted by a reset.
- **Read.** Issue a line read to the backend at the header. Count `TA` cycles of
  `dir=0`. Wait for the line, then drive the 8 words LSW first with `rvalid`.
  Release `io` after the last word.
- **Latency and gap model**, identical to `pin_link_agent` so that traces are
  comparable (§8.1):
  - xorshift64 `prng` seeded `0x9E3779B97F4A7C15 ^ seed·0x2545F4914F6CDD1D`
  - one `rand64()` per link cycle while `gap_pct > 0` and `rst_n = 1`
  - `gap = rand % 100 < gap_pct`, matched exactly. The bench is not changed.
    The PRNG runs ahead of use, so a pipelined constant-modulus reducer
    computes the remainder several cycles early (§11)
  - `ready = !gap` in idle; `rvalid` withheld on `gap` in read data; `rd_latency`
    fixed cycles before the first word
- **Deterministic mode (`LINK_CFG.DET=1`).** The backend's real latency must
  not perturb the cycle trace. The slave serves the first word at exactly
  `TA + rd_latency` after the header, and requires the line to be ready by
  then; if it is not, `LAT_OVERRUN` is counted. With `rd_latency` ≥ the
  backend's worst case (BRAM: ~4; DDR: measure, expect ~40–80 at 25 MHz), the
  link trace is a pure function of the program and seed, as in simulation.
- **Natural mode (`DET=0`).** Serve as soon as the line arrives, plus the
  configured gaps. This is how the real board will behave.
- **Ready policy** (`READY_POLICY`):
  - `NORMAL`: ready while ≥ 2 lines of buffer remain (the bench's rule)
  - `RANDOM`: the bench's `!gap`
  - `BACKPRESSURE n`: hold ready low for n cycles every m transactions
  - `ADVERSARIAL`: drop ready exactly k cycles before a predicted `req` and
    accept up to `GUARD`
  - `FORCED_LOW`: the core starves; used for the stall-status test
- **Stall injection** (`STALL_INJ`): at transaction N, withhold `rvalid` for
  C cycles mid-read (legal: gaps are allowed). With C > 2^17 this drives
  `status` into "stalled" (§7.4).
- **tohost.** Writes covering `TOHOST_ADDR` (default `0x8080_0000`) with a
  non-zero value latch `TOHOST_VALID`. This is the bench's convention,
  observed **on the link**, not by snoop.
- **Out-of-window or misaligned addresses** cannot be generated by a correct
  chip. If one arrives anyway, the slave still completes the transaction (never
  abort, `fpga/asic/BRINGUP.md` §"always answer"). Reads return poison
  `0xBAADC0DE_DEADBEEF`, writes are dropped, and both raise a checker error.

### 5.2 `fbu_link_check.sv`: passive protocol checker

This is a synthesizable port of every check in `pin_link_agent.sv` plus
`pin_tb.sv`'s pin monitors. Each check has a bit in `LINK_ERR` (sticky). The
first error's code and cycle are latched, with a count per check.

| Bit | Check (sim origin) |
|---|---|
| 0 | `req` while `dir=0` |
| 1 | `req` not exactly 2 cycles / `req` dropped after one word |
| 2 | `req` mid-transaction (write data, read TA, read data) |
| 3 | `wr` changed inside header or dropped during write data |
| 4 | `dir` fell during write data / rose during read latency or data |
| 5 | `dir` rose ≤ `TA` cycles after last `rvalid` |
| 6 | FPGA drove `io` while `dir=1` (functional) or `io[15:8]` in test mode |
| 7 | address outside `EXT_MEM` |
| 8 | address not line-aligned |
| 9 | first transaction after `rst_n` release is not a read of `0x8000_0000` |
| 10 | `req` > `GUARD` cycles after `ready` fell (also: max distance kept in `REQ_AFTER_READY_MAX`) |
| 11 | watchdog: transaction not finished in `WDOG` cycles (default 1000) |
| 12 | `rvalid` word count ≠ `W` for a read (self-check of the slave) |
| 13 | link pins not parked within 2 cycles of `rst_n` falling (`dir=1, req=0, wr=0, io=0`) |
| 14 | `io` not 0 while chip idle and `dir=1` (`docs/top_level_plan.md` §3.3: "chip drives zeros") |
| 15 | test mode: `io[15:8]` changed while `scan_en=0` for >1 cycle (stub chain must hold) |

**Lane coverage** (from `docs/impl_plan_link_clocking.md` §7.2, "controlled
lane coverage"): four 32-bit registers, each holding `{seen1[15:0],
seen0[15:0]}` per lane, for header words, write data, read data, and test-mode
scan. A run passes the "all lanes" criterion only if every lane has been seen
at both values in every direction it has.

**Histograms** (8 bins each, PS-readable): read latency to first `rvalid`;
transaction length in cycles; `ready`-low run lengths; `req`-after-`ready`-fell
distance.

### 5.3 `fbu_link_trace.sv`

This is a ring buffer of transaction records. Each record is `{cyc[47:0], wr,
addr[31:0], beat0[63:0], beat1[63:0]}` for `L` (line) events, plus `T`
(tohost), `I` (irq edge), `E` (checker error) and `R` (reset edge) records.
It uses the same fields as `pin_trace.log`, so `trace_to_pin.py` emits a file
that `hvl/pin/pin.sh compare` accepts unchanged.

- **Modes:** `OFF`, `ALL` (stop when full), `RING` (keep the last N), and
  `TRIG_ERR` (freeze N/2 records after the first checker error).
- **Depth:** 2048 records (~10 BRAM36). That is small enough for the BRAM
  backend budget (the old `asic-asic-BRAM` used 113 of 140 tiles). With the AXI
  backend the depth parameter goes to 8192.
- **Full Linux traces** (4 M transactions) are out of scope for BRAM. An
  optional streaming mode reuses `fpga/linux_boot`'s AXI DMA S2MM path into
  the carve-out tail. It is deferred: the old DMA software was never
  written, so don't depend on it.

### 5.4 `fbu_pin_ctl.sv`: the control interface driver

This block is what makes the control interface stress-testable. Every output
is a register, and some can also be driven by **triggers**, so that timing
is cycle-exact rather than at Python speed (≈µs-ms jitter).

- **`rst_n`**:
  - `PIN_CTRL.RST_N` (static)
  - `RST_PULSE` (assert for n cycles, then release)
  - `RST_TRIG` (assert at a cycle, at the k-th transaction in link-FSM state S
    plus d cycles, on a checker error, or at pseudo-random intervals from its
    own seed)
  - `RST_COUNT` counts every reset issued
- **Boot gate:**
  - After every release, expect the first header `0x8000, 0x0000, wr=0`
    within `BG_TIMEOUT` cycles.
  - On mismatch or timeout, re-assert `rst_n`, count `BG_FAIL`, latch the
    header seen, retry up to `BG_RETRIES`, then hold reset and flag.
  - `BG_SELFTEST` inverts the expected value, so the gate's failure path is
    proven on every build ("prove a test can fail", `fpga/linux_boot`
    lessons).
- **`irq[1:0]`**:
  - static levels
  - `IRQ_TRIG` per line: assert at a cycle, on a mailbox event, or periodically
    with a random interval
  - deassert on PS write, or on a mailbox "ack" event
  - `IRQ_LAT` measures cycles from assert to the program's mailbox ack (§5.8),
    min/max/last
- **`fault_inject`:** driven by `fbu_fi_gen` (§5.4.1). The PS turns it on and
  off at any time, live, with `PIN_CTRL[1]`, or hands it to a pattern.
- **`test_mode`, `scan_en`:** static from `PIN_CTRL` (held 0 in every current
  test). Under `fbu_scan` control during a scan session. `TEST_TRIG` can raise
  `test_mode` at a cycle or event. Both exist for the deferred DFT tests.
- **`uart_rx`:** normally from `fbu_uart`. `PIN_CTRL.RX_FORCE` holds it low or
  high (stuck-low = continuous break; board-without-pull-up case).
- **Cycle counters:** `CYC_SINCE_RST` (64-bit, from release) and `CYC_TOTAL`.

Before `rst_n` release every input is defined. The FPGA must never present
X-equivalent garbage: `uart_rx = 1`, `test_mode = scan_en = fault_inject = 0`
and `irq = 0` unless a test asks otherwise. That is the board contract from
`docs/top_level_plan.md` §3.1, which says the pads have no pulls.


### 5.4.1 `fbu_fi_gen.sv`: the `fault_inject` pattern generator

**What the pin does in the frozen RTL.** The pin is not a fault. It is a
**master enable** for injectors that already exist in the core:

```
fault_inject pin ─► synchronizer (2 flops, core_clk) ─► AND FI_CONTROL[7:0] ─► faultinjectreg (1 flop) ─► FaultInjectUnits
                    forte_chip.sv:131                    0x1007_000B, resets 0   wallypipelinedcore.sv:112
```

The faults themselves come from one shared generator, `ft_fault_gen`. It has a
9-bit counter and a 16-bit LFSR (seed `0xFFFF`), both free-running from reset.
Every injection site fires **when the counter equals its own `PHASE`**, which
is once every 512 `core_clk` cycles. The LFSR at that moment picks the bit (and,
for the FT channels, XOR / stuck-0 / stuck-1 / no-op). A site corrupts only if
its unit is enabled in that cycle. The site phases, from the RTL:

| Unit (bit) | Site | `PHASE` | Notes |
|---|---|---|---|
| ALU (0) | replica 0 result / arith / shift | `0x1FE` / `0x1EE` / `0x1DE` | `ft_alu.sv`, `0x1FE − 64·i` etc. |
| ALU (0) | replica 1 result / arith / shift | `0x1BE` / `0x1AE` / `0x19E` | |
| CMP (1) | replica 0 / 1 | `0x1CE` / `0x18E` | |
| MUL (2) | result | `0x17E` | residue checked |
| DIV (3) | result | `0x15E` | residue checked |
| RF ECC (4) | both read ports | `0x1FF` (default) | read path only: nothing accumulates in the array |
| Pipe ECC (5) | all seven ECC pipeline registers, same bit | `0x1FF` (default) | mask chosen one cycle early (`ecc_flip_mask`) |
| Cache SEC/DED (6/7) | I$ | `0x13E` | the event **arms**; the flip lands on the next word written to the array (fill, store, correction write-back) |
| Cache SEC/DED (6/7) | D$ | `0x11E` | same |

Two consequences shape the generator:

1. **With the pin held high and a unit armed, the injection rate is fixed by
   the RTL.** Each site injects once per 512 cycles, about 48 800 events/s
   per site at 25 MHz. The pin cannot make it faster. It can only choose
   **which** of those events are allowed through.
2. **The timing is deterministic from reset.** The FPGA drives both
   `core_clk` and `rst_n`, so it can mirror the chip's counter exactly:
   `FI_PHASE_NOW = (CYC_SINCE_RST − FI_PHASE_OFS) mod 512`. `FI_PHASE_OFS` is
   a constant of the RTL (reset-synchronizer depth plus reset pipeline). It is
   measured once by CTRL-12b and then checked on every build. With the mirror,
   the pin can target individual sites or individual events. The pin-to-enable
   latency is `L = 3` cycles (`L = 4` for the pipeline mask, which samples one
   cycle early), and the generator compensates for it.

**Modes** (`FI_PATTERN[3:0]`). Each mode can start from a trigger
(`FI_PATTERN[7:4]`: immediate, at cycle, `UART_MATCH`, mailbox event, `rst_n`
release) and can be gated by a global window `FI_WIN_START`/`FI_WIN_STOP`:

| Mode | Pin behaviour | Use |
|---|---|---|
| `STATIC` | `= PIN_CTRL[1]` | the PS on/off switch. Hold high for a whole run (§5.4.2) |
| `SQUARE` | period `ARG0`, high for `ARG1` cycles | gating tests, the pin's duty cycle against event count |
| `RANDOM` | on/off dwell uniform in [`ARG0`, `ARG1`] from an LFSR seeded by `FI_SEED` | toggling under load, the chaos tests |
| `PULSE` | one pulse of `ARG0` cycles | synchronizer probe (1, 2, 3 cycles) |
| `BURST` | high for exactly `ARG0` × 512 cycles, aligned to mirror phase 0 | **budgeted injection**: every enabled site fires exactly `ARG0` times. Keeps the chip's counters below saturation and makes the expected count exact |
| `PHASE` | high only on mirror phases set in the 512-bit `FI_PHASE_MASK` (minus `L`), for `ARG0` consecutive 512-cycle periods (0 = forever) | **site targeting**: e.g. only ALU replica 1's result channel, or only the D$ and not the I$. This is finer than `FI_CONTROL`'s per-unit grain, with no RTL change |
| `SINGLE` | `PHASE` for one period: exactly one event at one site | the "one fault, one count" unit test |

**Accounting.** All of this is in the PL, never in Python:

- `FI_HIGH_CYC` and `FI_EDGES` count the pin's high time and edges.
- `FI_EVENTS[s]` is one counter per site group: ALU0, ALU1, CMP, MUL, DIV,
  RF/pipe, I$, D$. It counts the cycles in which the **synchronized** pin
  would have been high at that group's phase. That is the exact number of
  events the chip allowed through for the armed units.
- The chip's counters must then satisfy `delta ≤ FI_EVENTS`. Equality is not
  expected: a corrupted value counts only when it is used and detected, and FT
  kind `11` or an out-of-range bit index is a no-op. `SINGLE` and `BURST` on a
  workload that saturates the channel (`fe_fault_*` kernels) are designed to
  make `delta` predictable.

### 5.4.2 Can `fault_inject` stay on throughout? Yes, for bits 0–6

- **The pin itself: yes, always.** It can be held high from configuration,
  through every reset. `FI_CONTROL` resets to `0x00`, so nothing is injected
  until software arms units. Every boot that wants injection runs a prologue
  that writes `FI_CONTROL` (`fe_fi_arm.S`, linked into any image with
  `FI_ARM=0x7F`).
- **Units 0–6 (FT ALU/CMP/MUL/DIV, RF ECC, pipeline ECC, cache SEC): yes.** The
  RTL is designed to survive this continuously:
  - "One event every 512 clocks leaves time for a transient mismatch to
    retry" (`ft_fault_inject.sv`).
  - The RF injector sits on the read path only, so flips do not accumulate.
  - Cache SEC flips are stored, but each write carries at most one, and a
    write replaces the whole word, so flips cannot pile up in one codeword.
    The next read corrects them. The scrubber does **not**: it is disabled in
    the frozen RTL (Q9).

  **`fault_inject = 1, FI_CONTROL = 0x7F` therefore becomes the background
  condition for the soak and chaos tests (SYS-06/07) and for CTRL-20.** This is
  the actual fault-tolerance claim, tested on live hardware: the same results
  as an injection-off run, with no unresolved or uncorrectable events.
- **Unit 7 (cache DED): no, only in dedicated tests.**
  - On a clean line or in the I$, the line is dropped and refetched, which is
    transparent (counters 5/7).
  - On a **dirty D$ line**, the data is lost and the core takes **cause 20**,
    with `mtval` set to the line address (`trap.sv`, `wallypipelinedcore.sv`).
    Continuous DED would trap roughly every 512 cycles whenever the D$ holds
    dirty data. Linux and FreeRTOS have no handler for that.
  - With bits 6 and 7 both set, a quarter of the cache events are DED
    (`cachefi.sv`).
  - So bit 7 runs only under CTRL-21's handler, in `BURST`/`SINGLE` mode.
- **The chip's fault counters do not survive "always on" as totals.** They are
  16-bit, saturating, read-only, and cleared only by reset
  (`faultcount_apb.sv`). A site that detects every event saturates in about
  1.3 s at 25 MHz. So:
  1. Long runs judge correctness by results and by the counters that must
     stay 0 (DED 1/3/5/7, unresolved 9/11/13/15, TMR-uncorrectable 17), which
     saturation cannot hide.
  2. Rate checks use `BURST` windows or periodic resets.
  3. An `EMU_TAPS` build can tap `FaultEvents` into 32-bit PL counters as an
     oracle.

  The same limit applies to silicon bring-up scripts, and is worth knowing now.
- **RF ECC (bit 4) and pipeline ECC (bit 5) armed together lose the RF's
  faults.** Both act at phase `0x1FF`. Their flips never meet: the pipeline's
  is in `RD1E`/`RD2E` at count 511, the RF's is in the read those registers
  capture at the end of that cycle (a standalone testbench of the real modules,
  `sim/verilator/ecc_cancel_tb/`, counts exactly the sum of the two). In the
  chip, though, the pipeline's correctable error raises `EccStallE`
  (`datapath.sv`), which holds `RD1E`/`RD2E` for the cycle the register
  repairs itself, so the RF-flipped read is never captured, and at count 0
  Decode reads again, clean. Measured (`fe_fault_rfpipe`, RTL bench, pin
  high): counter 0 is 605 with `0x10`, 3866 with `0x20` (pipeline flips in
  `RD1E`/`RD2E` count there) and 3870 with `0x30`. No wrong result and no
  DED, only lost RF coverage. The pin separates them (the pipeline samples
  it at `0x1FE`, the RF at `0x1FF`, CTRL-12b), and CTRL-20 arms `0x5F` and
  `0x6F` in turn.

### 5.5 `fbu_scan.sv`: test-mode driver

**Built and simulated, not exercised on hardware yet** (DFT testing is
deferred, §7.1). It is in every bitstream, so the deferred tests need no
rebuild. `tb_fbu_vs_pin` runs `fe_scan.cmd` (`scan_session`, also on the PS)
against the frozen RTL with the core held in reset, to prove the block works.
Registers `SCAN_*` (§6); the PS writes the pattern and reads the capture one
entry at a time.


- When `test_mode=1`, the slave's `io` driver is disabled. `fbu_scan` drives
  `io[7:0]` from a 1024 × 8 pattern RAM and captures `io[15:8]` into a
  1024 × 8 capture RAM, one entry per cycle, with `scan_en` from a 1024 × 1
  pattern (or constant).
- The **directions come from `test_mode`, never from `dir`**
  (`docs/top_level_plan.md` §3.3 point 2). `dir`/`req`/`wr` are ignored and only
  recorded.
- What the frozen RTL implements is the stub. `scan_q <= io[7:0]` when
  `test_mode & scan_en & unlocked`, and `io[15:8] = scan_q`. So the expected
  capture is the input delayed one cycle while `scan_en=1`, held while
  `scan_en=0`, and the PS checks this exactly. That is a full pad-direction and
  loopback test of all 16 `io` lanes in their test directions.
- Locked part: the same session must show the **functional** pins instead (the
  link stays as it was and `io[15:8]` does not follow `io[7:0]`).

### 5.6 `fbu_uart.sv`

**Port from** `feature/top_level:fpga/pynq/rtl/amoeba_uart_xcvr.sv`, minus the
bus-shadow divisor (no bus on silicon).

- **RX (from `uart_tx`).** Divisor register in 16.16 fixed point (core clocks
  per bit), 16× oversampling and mid-bit vote. 4 KiB FIFO to the PS with a
  sticky overflow bit, plus counts of framing errors, and break detection.
- **TX (into `uart_rx`).**
  - Own fractional divisor, so a **baud mismatch** of ±x % can be set
    deliberately.
  - Inter-byte gap in bit times.
  - Per-byte error injection, from a 4 KiB FIFO with a per-entry control byte:
    - stop bit 0 (framing error)
    - parity bit inverted, when the chip is configured for parity
    - break of n bit times
    - glitch: a low pulse of n core cycles, < ½ bit, which must not start a
      character
- **Mirror** `uart_tx`/`uart_rx` to PMOD JA (xdc) for an external
  USB-serial cable or a scope. This is "the console works with the link dead"
  (`docs/top_level_plan.md` §3.5).
- **Pattern matcher.** `UART_MATCH` holds a 32-byte string. When the RX stream
  matches it, `UART_MATCH_CYC` is latched and an optional trigger fires (for
  example, raise `irq` or `fault_inject` exactly when the program prints
  `ARMED`). This removes Python latency from handshakes.

### 5.7 `fbu_status_mon.sv`

- It measures every `status` half-period in core cycles and keeps last, min,
  max and edge count, plus a 4-bin classifier. The frozen RTL makes the half
  periods **exactly** `2^23` (stalled), `2^25` (active) and `2^27` (quiet) link
  cycles while the condition is steady, so the check is equality, not a tolerance.
- **Phase alignment caveat.** `tick` is free-running from link reset, and the
  selector switches taps combinationally. A transition leaves one or two
  odd-length half-periods: the one the switch cuts short and, if the pin
  flips at the switch, the one from there to the new tap's next edge (a chip
  reset does the same). The classifier reports the *last two equal*
  half-periods, and `STAT_GLITCH` counts half-periods of none of the three
  lengths. `make -C fpga/pynq test-status-mon` checks all of this with the
  rates shrunk; the real rates are checked on the board (`fe_status.cmd`).
- At 25 MHz a quiet half-period is 5.4 s, so a quiet-classification test takes
  ~11 s. Stalled (0.34 s) and active (1.34 s) are quick.
- `clk_out`: count rising edges over a 2^20-cycle `core_clk` window. They
  must be equal. In fabric this is trivially true, so it is really a liveness
  and connection check. On the bring-up board the same block measures the die's
  clock.

### 5.8 `fbu_mailbox.sv` (optional, enabled per test)

This is a "magic memory" window at `MBX_BASE` (default `0x8FF0_0000`, 1 MiB,
top of `EXT_MEM`) that the bare-metal `fe_*` programs use as a side channel.
It is **just memory to the chip**: every access is an ordinary line fill or
writeback, so no RTL assumption is involved.

- **Reads in the window** are logged `{cyc, addr}` into an event FIFO and can
  return data from 8 PS-written registers instead of memory. This is PS→DUT
  messaging without reloading the image. A program that wants a fresh value
  reads a never-touched line, so every message is a guaranteed cache miss.
- **The doorbell idiom**, for interrupt latency: the ISR's first action is a load
  from `MBX_BASE + 16·k` with an unused `k`. The resulting line fill is
  timestamped at the pins, so `IRQ_LAT` = header cycle − irq assert cycle.
- **Writes in the window** (after eviction or `fence.i`) are logged likewise.
- Disabled for Linux and FreeRTOS (`MBX_EN=0`). The window must not overlap
  their memory.

### 5.9 `fbu_regs.sv` and `fbu_top.sv`

`fbu_regs` is AXI4-Lite with a full 12-bit decode. Unmapped reads return
`0xDEADC0DE` and never error: Zynq GP has no timeout, so an error response
must never be needed. Reading a 64-bit `_LO` register latches `_HI`, as in
`amoeba_ctl`. `fbu_top` instantiates §5.1–5.8 and exposes the 32 pins, the
line interface and AXI-Lite.

### 5.10 Line interface and backends

```
line_rd_req(addr[31:0]) -> line_rd_rsp(data[127:0])        one outstanding
line_wr(addr[31:0], data[127:0]) -> line_wr_ack            one outstanding; ordered after reads
```

- **`fbu_mem_bram.sv`** is a 128-bit × 8 K (128 KiB) true dual-port BRAM. Port
  B is an AXI4-Lite slave at `0x4400_0000` for PS load and dump. The address
  wraps with the window. Port B uses `aresetn`. The PS writes only while
  `rst_n=0`, because the ports are not arbitrated (inherited rule).
- **`fbu_mem_axi_hp.sv`** (`MEM_BACKEND=AXI`) is a native AXI3 master on
  `S_AXI_HP0`, connected directly (both AXI3, 64-bit). It does one AR/R or
  AW/W/B per line: `LEN=1` (2 × 64-bit), `SIZE=3`, `INCR`, ID 0, and
  `AxPROT = 000`, i.e. **secure**: the board's `TZ_DDR_RAM` leaves every DDR
  segment secure-only and a non-secure access returns DECERR while the PS
  reads the same memory fine (the TrustZone lesson, `bd_pynq.tcl`). EXT_MEM maps
  to the carve-out as `0x1000_0000 | (addr & 0x0FFF_FFFF)`; the board boots
  with `mem=256M`, and the block design clamps the master's address window to
  the carve-out as well. This **replaces** `ahblite_axi_bridge` +
  `axi_protocol_converter`:
  - The slave is the master now, and it never aborts, so the bridge's abort
    and sticky-HRESP wedges (`fpga/linux_boot` lessons, project memory) can no
    longer happen.
  - It removes ~1 k LUT.
  - **Ordering.** Writes are posted, up to 4 waiting for B: in DET mode the
    slave keeps `ready` high whatever its two-line queue holds, so a writeback
    burst must not wait for DDR. A read waits for every outstanding B (AXI
    orders nothing between the read and write channels); one read is
    outstanding at a time (the link is serial).
  - **Chip reset.** A read accepted or outstanding while `rst_n` is low gets
    no response: the slave would take a late one as the next read's line. The
    burst still completes on AXI. Writes complete as issued, as on the bench.
  - **Outside EXT_MEM** nothing reaches AXI: reads return poison with
    `rsp_err`, writes are counted and dropped.
  - `RRESP`/`BRESP` ≠ OKAY sets a sticky `MEM_ERR` with the first error's line
    and response, and the line is still served (poison for reads).
  - **Status:** read/write/dropped counts and read latency (request to
    response) max and sum, `MEM_*` registers (§6). The maximum sets the
    DET-mode `rd_latency`; `sw/run_cmd.py` prints them and fails a run on
    `MEM_ERR`.
  - **PS side.** `Forte` reads `CAPS.MEM_AXI` and maps the carve-out through
    `/dev/mem` with `O_SYNC` (uncached: HP0 is not coherent with the A9's
    caches). Trace runs fill the same three windows as the BRAM build with the
    bench's unwritten pattern; `load_lst(fill=False)` loads an image alone.
    Words outside EXT_MEM (the sim models' UART LSR word) are skipped, as in
    the BRAM build.
  - **Load the bitstream once per boot.** Reloading any HP0 design wedges the
    PS within 4-5 loads: the configuration DMA's DDR reads time out
    (`INT_STS 0x220000`), `fpga_manager` stays in `write init error`, and a
    soft reboot halts (power cycle needed). `forte-AXI` failed on load 4 and
    AMOEBA's `baremetal_linux-AXI` on load 5, both with the chip never
    released; BRAM builds reload freely. `Forte` therefore loads only when
    `/run/forte_loaded` (cleared at boot, voided by any `pl.program`) names a
    different bitstream. Every run ends with the chip held in reset
    (`Forte.hold`, also on SIGTERM), so HP0 is idle whenever the PS acts. The
    `MEM_*` counters then count from the load: `run_cmd.py` prints per-run
    differences, and a sticky `MEM_ERR` from an earlier run is reported, not
    charged to the current one. Configuration registers that only a PL reset
    clears (FI mode, seed, latency, phase offset and mask, triggers, console
    match, UART timing, memory window, scan) are written back to their reset
    values by `configure()` from `regs.CONFIG_RESET`, which is checked against
    the bitstream after each load: without it, `fe_fault_site`'s last phase
    mask gated CTRL-20's static pin to one phase and its traces ran up to 22
    cycles fast.
  - **Board results (rd_latency 64, 25 MHz).** smoke and sorting_algo, 30
    runs from one load: all PASS, traces match the bench cycle for cycle,
    read latency mean 14 and max 24 cycles, no HP0 errors.
  - **Verification.** `make test-mem-axi-hp`: the backend against an AXI3
    model that applies a write only when it sends B (so a read issued early
    reads stale data), with random ready and latency, SLVERR lines and chip
    resets. `make test-fbu-ddr`: the full `fbu_vs_pin` gate on the PL top with
    `MEM_AXI`, an HP0/DDR model holding the bench's memory, and
    `FORCE_RD_LAT=64` on both sides (DET mode needs `rd_latency` ≥ the
    backend's worst case).

---

## 6. Register map (`fbu_top`, `0x43C0_0000`, 4 KiB)

**The source of truth is `fpga/bringup/rtl/fbu_pkg.sv` (`REG_*`).** This
table follows it. `check_regs_forte.py` parses `fbu_pkg.sv` and
`sw/forte/regs.py` and fails on any disagreement. Every register is 32 bits
wide and written whole. "W" registers act on the write, and no read has a
side effect: FIFOs pop through their own `*_POP` register.

**Implemented** (P1):

| Offset | Name | Access | Fields |
|---|---|---|---|
| 0x000 | ID | RO | `0x46425530` "FBU0" |
| 0x004 | VERSION | RO | `0x0001_0000` |
| 0x008 | CAPS | RO | [3:0] BEATS, [4] MEM_AXI (DDR backend), [15:8] log2 trace depth |
| 0x00C | SCRATCH | RW | |
| 0x010 | SOFT_RESET | W | resets the gateware below the register file (the chip is held in reset meanwhile) |
| 0x100 | PIN_CTRL | RW | [0] RELEASE (rst_n, resets 0), [1] FAULT_INJECT, [2] TEST_MODE, [3] SCAN_EN, [5:4] IRQ, [6] RX_FORCE_EN, [7] RX_FORCE_VAL |
| 0x104 | PIN_IN | RO | [15:0] io, [16] dir, [17] req, [18] wr, [19] status, [20] uart_tx, [21] rst_n, [22] ready, [23] rvalid, [24] clk_out |
| 0x108 | RST_PULSE | W | hold rst_n low for N cycles |
| 0x10C | RST_COUNT | RO | rst_n assertions |
| 0x120 | BOOTGATE | RW | [0] EN, [1] SELFTEST, [7:4] RETRIES, [31:16] TIMEOUT (default 1000) |
| 0x124 | BOOTGATE_STAT | RO | [15:0] fails, [16] gave up, [17] last header's wr |
| 0x128 | BOOTGATE_HDR | RO | last header {A[31:16], A[15:0]} |
| 0x12C | BOOTGATE_PASSES | RO | [15:0] |
| 0x170/174 | LINK_CYC_LO/HI | RO | link cycles since rst_n release |
| 0x178/17C | CYC_TOTAL_LO/HI | RO | cycles since the FPGA's reset |
| 0x200 | LINK_CFG | RW | [0] DET (resets 1), [7:1] GAP_PCT, [31:16] RD_LAT |
| 0x204 | LINK_WDOG | RW | [15:0] watchdog cycles (1000), [17:16] MUTATE (self-test) |
| 0x208/20C | PRNG_INIT_LO/HI | RW | `fbu_pkg::prng_seed_state(seed)` |
| 0x210 | PRNG_LOAD | W | load PRNG_INIT into the generator |
| 0x214/218 | MEM_BASE / MEM_LIMIT | RW | EXT_MEM window checked on every header |
| 0x21C | RESET_VEC | RW | expected first fetch |
| 0x220 | LINK_ERR | RO | sticky, bit per `link_err_t` |
| 0x224 | LINK_ERR_COUNT | RO | |
| 0x228 | FIRST_ERR | RO | `link_err_t` |
| 0x22C/230 | FIRST_ERR_CYC_LO/HI | RO | |
| 0x234/238 | LINK_RD / LINK_WR | RO | finished transactions |
| 0x240 | MEM_STAT | RO | [0] memory error seen (sticky), [9:8] its RRESP/BRESP; zero in BRAM builds |
| 0x244 | MEM_ERR_ADDR | RO | line of the first memory error |
| 0x248/24C | MEM_READS / MEM_WRITES | RO | lines sent to the backend |
| 0x250 | MEM_DROPPED | RO | writes outside EXT_MEM |
| 0x254 | MEM_LAT_MAX | RO | longest read, request to response, in clk cycles |
| 0x258/25C | MEM_LAT_SUM_LO/HI | RO | sum of read latencies (48 bits) |
| 0x280 | TOHOST_ADDR | RW | default `0x8080_0000` |
| 0x284 | TOHOST_STAT | RO | [0] seen (cleared while rst_n is low) |
| 0x288/28C | TOHOST_VAL_LO/HI | RO | |
| 0x300 | TRACE_CTRL | RW | [0] EN, [1] STOP_ON_ERROR |
| 0x304 | TRACE_LEVEL | RO | records waiting |
| 0x308/30C | TRACE_WRITTEN / TRACE_DROPPED | RO | |
| 0x310 | TRACE_POP | W | drop the head record |
| 0x314 | TRACE_STAT | RO | [0] head valid, [1] overflow |
| 0x318 | TRACE_CLEAR | W | |
| 0x340–0x364 | TRACE_HEAD[10] | RO | the head record (`fbu_link_trace.sv` format) |
| 0x400 | UART_RX_BIT | RW | core cycles per received bit (32 = div 1) |
| 0x404 | UART_TX_PERIOD | RW | transmitted bit period, 1/256 cycle |
| 0x408 | UART_TX_GAP | RW | idle bit times between frames |
| 0x40C | UART_RX_DATA | RO | [31] valid, [8] framing error, [7:0] byte |
| 0x410 | UART_RX_POP | W | |
| 0x414 | UART_TX_PUSH | W | [9:8] kind (byte, bad stop, break, idle), [7:0] data |
| 0x418 | UART_STAT | RO | [0] rx overflow, [1] tx full, [2] tx overflow, [3] tx busy |
| 0x41C/420 | UART_RX_LEVEL / UART_TX_LEVEL | RO | |
| 0x424/428/42C | UART_N_RX / N_TX / N_FERR | RO | |
| 0x430 | UART_MATCH_LEN | RW | [7:0] matcher 0, [15:8] matcher 1 |
| 0x434 | UART_MATCH_CTRL | RW | write [1:0]: clear matcher; read [1:0]: hit |
| 0x438 | UART_CLEAR | W | |
| 0x440–0x45C | UART_MATCH0[8] | RW | pattern, last byte in byte 0 |
| 0x460–0x47C | UART_MATCH1[8] | RW | |
| 0x500 | STAT_LAST | RO | last whole `status` half-period, in clk cycles |
| 0x504 / 0x508 | STAT_MIN / STAT_MAX | RO | since the last clear |
| 0x50C | STAT_EDGES | RO | edges since the last clear |
| 0x510 | STAT_CLASS | RW | R [1:0] none/stalled/active/quiet (the last two equal half-periods), [8] pin now; W clears the statistics |
| 0x514 | STAT_GLITCH | RO | half-periods of none of the three lengths |
| 0x518 | CLKOUT_EDGES | RO | `clk_out` rising edges in the last whole window |
| 0x51C | CLKOUT_WINDOW | RO | the window, 2^20 clk cycles |
| 0x600 | SCAN_CTRL | RW | W [0] start; RW [1] `scan_en` from the pattern (else PIN_CTRL[3]); R [8] running, [9] done |
| 0x604 | SCAN_LEN | RW | session length, 0..1024 cycles |
| 0x608 | SCAN_ADDR | RW | the pattern/capture entry the PS accesses |
| 0x60C | SCAN_PATTERN | W | [7:0] `io[7:0]`, [8] `scan_en`; then SCAN_ADDR + 1 |
| 0x610 | SCAN_CAPTURE | RO | `io[15:8]` captured at SCAN_ADDR |

**Reserved for later stages** (offsets kept free): `0x0F0–0x0FC` split
clock; `0x110–0x11C` RST_TRIG; `0x130–0x14C` IRQ_TRIG and latency;
`0x150–0x1FC` fault-inject generator (§5.4.1); `0x240–0x27C` lane coverage,
histograms, ready policy and stalls; `0x2A0–0x2FC` mailbox; `0x500–0x51C`
status monitor (now used); `0x600–0xEFF` scan (`0x600–0x610` used); `0xF00` EMU_TAPS.

**Trace depth on the board.** Draining one record over AXI-Lite takes 11
accesses. A busy link can produce one every 14 cycles, faster than the PS
can drain. The 2 048-record FIFO therefore bounds what a board run can
compare cycle for cycle. Longer runs report `TRACE_DROPPED` and are judged
on results and error counters. (`tb_fbu_vs_pin` builds `fbu_top` with a
32 k-record FIFO.)

---

## 7. Test plan

Every test is a **DUT program** (RISC-V bare-metal, `bin/startup.s`
conventions: `tohost = (code<<1)|1` then `fence.i`) plus a **command script** in
the pin bench's language or the FPGA's `fbu` dialect (§10.3). The bench's own
`hvl/pin/tests/*.cmd` run on the FPGA unmodified (`sw/run_cmd.py`). Scripts
that need FPGA-only commands are `fbu`-dialect files in `fpga/bringup/tests/`
and never run on the bench. `hvl/pin/` stays the post-synthesis bench and is not
modified.

**Global pass criteria for every test** (on top of its own):

1. `LINK_ERR == 0`, `MEM_ERR == 0`, `LAT_OVERRUN == 0` (DET mode),
   `CAPS.sram_retn_err == 0`
2. no UART RX overflow and no `uart_fail` pattern seen
3. `BOOTGATE_STAT.fails == 0`, unless the test is the gate's own self-test
4. exit code as expected
5. the status class seen at the end matches the test's expectation, where it
   states one

New DUT programs go in `fpga/bringup/tests/fe_*.c` with their `.cmd` (prefix
`fe_`, "FPGA emulation"). `fpga/bringup/tests/build.sh` builds them with the
same toolchain flags and startup as `hvl/pin/images.sh`. It reads that script's
settings and does not edit it.

### 7.1 Control interface (CTRL)

| ID | Name | Stimulus | DUT program | Pass |
|---|---|---|---|---|
| CTRL-01 | Reset park | Assert `rst_n` at random cycles in each link state (idle, HDR, WDATA, RD_TA, RD_DATA, RD_TA2) via `RST_TRIG at-xact-in-state`, 100× per state | any long-running (`fe_mem_march`) | check 13 (parked ≤ 2 cycles: `dir=1, req=0, wr=0, io=0`) never fires; `LINK_RST_ABORT` = number of mid-transaction resets |
| CTRL-02 | First fetch after reset | After every release in CTRL-01 | — | check 9 never fires; boot gate passes every time |
| CTRL-03 | Reset storm, then correctness | 10 000 resets at random intervals (`RST_TRIG random`), then a final clean run | `fe_reset_marker` (prints a boot counter read from the mailbox) then `tc_*` suite | final run passes; each boot printed its banner (no partial-boot hangs); memory reloaded only once (proves resets never corrupted memory via partial writes) |
| CTRL-04 | Reset pulse width | `RST_PULSE` n = 1, 2, 3, 4, 16 cycles | `smoke` | every width produces a clean reboot (`forte_rst_sync` asserts asynchronously, so even 1 cycle must reset) |
| CTRL-05 | Boot gate self-test | `BOOTGATE.SELFTEST=1` | `smoke` | the gate re-asserts reset `retries` times, then gives up and flags; with SELFTEST=0 it passes. Proves the gate can fail |
| CTRL-06 | irq level, each line | `irq.cmd` (exists) | `hvl/pin/tests/irq.c` | as in sim: `IRQ3`, `IRQ6` printed |
| CTRL-07 | irq latency | `IRQ_TRIG` at random cycles, 1000×, mailbox doorbell ack | `fe_irq_latency` (PLIC claim → doorbell load → complete → wait for deassert) | every irq acked; `IRQ_LAT` min/max recorded; max < bound set from sim (Q4); no lost or spurious claims (the program counts claims, the PL counts asserts) |
| CTRL-08 | irq both lines, priorities, threshold | both asserted in the same cycle and staggered by 0..8 cycles | `fe_plic_both` (priority 3 vs 6 and swapped, threshold above/below, M and S contexts) | claim order and IDs as the PLIC spec; held level re-claims until the PL deasserts |
| CTRL-09 | irq glitch | 1-, 2- and 3-cycle irq pulses | `fe_plic_both` (pending poll) | defined, repeatable behaviour (2-flop sync: a 1-cycle pulse may be missed). **Records** the behaviour rather than failing; it must be identical to the RTL sim result for the same cycle (correlation, §8.1) |
| CTRL-10 | fault_inject gating, per unit | PS toggles the pin live: low → high (`BURST` K=64) → low, handshaked by `UART_MATCH` | `fe_fault_pin`: for each `FI_CONTROL` bit 0..6, arm only that unit, run a kernel that keeps that channel busy, print all 18 counters per phase | counters move **only** in pin-high phases and only the expected ones (map below); `delta ≤ FI_EVENTS` for that site group; all results correct (SEC corrects, FT recovers); pin low ⇒ counters frozen even with `FI_CONTROL=0x7F` |
| CTRL-11 | fault_inject toggling under load | `RANDOM` dwell 1..100 k cycles, 10 min | `fe_fault_pin` long mode + `tc_ecc_stress` + `tc_link_abort`, `FI_CONTROL=0x7F` | results correct; DED/unresolved/TMR-uncorrectable counters stay 0; no cause 19/20 trap; `FI_HIGH_CYC` > 0 |
| CTRL-12 | fault_inject pulse width | `PULSE` 1, 2, 3, 4 cycles, swept over all 512 mirror phases | `fe_fault_pin` | records which widths/phases get through (2-flop sync + one flop); must equal the RTL sim for the same cycles (correlation, §8.1) |
| CTRL-12b | Phase calibration | `SINGLE` with a 1-phase mask swept over 0..511, one unit armed at a time | `fe_fault_pin` | each unit's counter moves only at its sites' phases (§5.4.1 table) + one constant offset; that offset is `FI_PHASE_OFS`, identical across units, builds and resets |
| CTRL-13 | `FI_CONTROL` access rules | — | `tc_fault_control` (exists) | passes (reset 0x00, byte-only, readback independent of pin) |
| CTRL-20 | **Always-on fault tolerance** | pin high from before release (`STATIC`), never dropped; repeated at 3 `RANDOM` link gap settings | prologue `FI_ARM=0x7F` + SYS-01 ISA suite, `baremetal_ecc`, FreeRTOS `tc_*` | every result identical to the injection-off run; counters 1/3/5/7, 9/11/13/15 and 17 stay 0; no cause 19/20 trap; status never reports stalled. Bits 4+5 together only after the §5.4.2 sim check |
| CTRL-21 | Cache DED traps | bit 7 only (then 6+7), `SINGLE`/`BURST` at the D$ and I$ phases | `fe_cache_ded`: cause-20 handler logs `mcause`/`mtval`/`mepc` and rebuilds the line from a shadow copy; dirties known lines, also runs from clean lines and the I$ | every trap has `mcause=20` and `mtval` inside a line the program dirtied; clean-line and I$ DEDs are silent drops (counters 5/7 move, results correct, no trap); no cause-19 trap and no `PrivModeUncorrectable`; with 6+7 the DED fraction is ≈ ¼ |
| CTRL-22 | Site targeting | `PHASE` mask selecting one site at a time (ALU0 vs ALU1, CMP0 vs CMP1, I$ vs D$) with the whole unit armed | `fe_fault_pin` | only the targeted site's detector moves; proves the replicas and caches are checked independently |
| CTRL-14 *(deferred, DFT)* | DFT unlocked: scan stub loopback | `test_mode=1`, scan session: walking 1/0 and random on `io[7:0]` with `scan_en` patterns | none (core held or idle) | capture = input delayed 1 cycle while `scan_en=1`, held while 0; `LANE_COV_SCAN` complete; `io[7:0]` never driven by the chip |
| CTRL-15 *(deferred, DFT)* | DFT lock blocks test mode | Program locks (writes 0 to `0x0200_F000`), prints `LOCKED`; `UART_MATCH` → `TEST_TRIG` raises `test_mode`+`scan_en` while the core keeps running memory traffic | `fe_dft_lock` | link keeps working (program completes, no checker errors); scan session shows functional pins; readback of lock = 0 |
| CTRL-16 *(deferred, DFT)* | Lock is sticky; reset reopens | Program writes 1 after locking, reads back; PL resets; program reads again | `tcf_dft_lock` (exists) + `fe_dft_lock` phase 2 | write 1 ignored (reads 0); after `rst_n` reads 1; CTRL-14 passes again after reset |
| CTRL-17 *(deferred, DFT)* | test_mode on an unlocked running part | Raise `test_mode` mid-run, unlocked | `fe_mem_march` | **Expected to break the link** (documents why the board must strap `test_mode` low). Pass = the checker flags it and a subsequent reset recovers fully. Not a silicon defect test, a board-contract test |
| CTRL-18 *(deferred, DFT)* | scan_en alone in functional mode | Toggle `scan_en` randomly with `test_mode=0` for a full run | `tc_*` suite | no effect: all pass |
| CTRL-19 | Floating-equivalent inputs | `uart_rx` stuck low through reset release (`RX_FORCE`) | `uart_echo` | documented: break/framing errors counted by the chip's LSR; program still boots (console input path is independent) |

**`FI_CONTROL` bit → counters** (`hdl/core/uncore/fault_inject_apb.sv`,
`faultcount_apb.sv`): 0 ALU → 8/9 · 1 CMP → 10/11 · 2 MUL → 12/13 ·
3 DIV → 14/15 · 4 RF ECC → 0/1 · 5 pipeline ECC → 2/3 · 6 cache SEC → 4, 6 ·
7 cache DED → 5, 7. Counters 16/17 (privilege-mode TMR) have no mask bit and
no injector, so they are expected to stay 0. Every test records them.

**DFT deferral.** CTRL-14..18 (scan loopback, DFT lock, test mode mid-run,
`scan_en` in functional mode) stay specified here but are not scheduled. In
every scheduled test `test_mode = scan_en = 0`. `fbu_scan` is built and
sim-checked (§5.5), so these tests need only scripts when they come back.

### 7.2 UART (UART)

| ID | Name | Stimulus | DUT program | Pass |
|---|---|---|---|---|
| UART-01 | Echo | `uart_echo.cmd` (exists) | `uart_echo` | `echo:ping` |
| UART-02 | LSR framing error | `uart_lsr.cmd` (exists) | `uart_lsr` | LSR[7], LSR[3] set |
| UART-03 | Divisor sweep | program sets div ∈ {1, 2, 3, 7, 13, 27, 255, 256, 65535}, prints `DIV n READY`; PS retunes both PL divisors by `UART_MATCH` → register write | `fe_uart_baud` | 64-byte random echo correct at every divisor |
| UART-04 | Baud tolerance | TX into `uart_rx` at ±1, ±2, ±3, ±4, ±5 % | `fe_uart_baud` echo | 0 errors within ±3 %; record where it breaks. 16550 theory gives ~±4–5 % at 8N1 |
| UART-05 | Line formats | LCR 5/6/7/8 bits, 1/2 stop, odd/even/stick parity; PL configured to match; parity errors injected | `fe_uart_fmt` | data correct; LSR PE set exactly for the flipped-parity bytes |
| UART-06 | Break | PL sends breaks of 1, 2 and 10 char times | `fe_uart_fmt` | LSR BI set once per break; following byte received clean |
| UART-07 | Glitch rejection | low pulses of 1/16, 2/16, 7/16 bit | `uart_echo` | no spurious characters for < ½-bit pulses; record the threshold |
| UART-08 | RX FIFO / overrun | burst of 64 bytes, gap 0, program not reading | `fe_uart_stress` | LSR OE set; FIFO keeps the first 16; IIR/trigger levels per FCR (1/4/8/14) as specified |
| UART-09 | Interrupt-driven RX via PLIC (source 10) | sustained 10 KiB stream | `fe_uart_stress` IRQ mode | checksum matches; no overrun at div ≥ 2 |
| UART-10 | TX throughput | program streams 64 KiB as fast as THR allows | `fe_uart_stress` TX mode | PL receives all bytes, checksum, no framing errors; idle gaps ≤ program overhead |
| UART-11 | Console with the link degraded | `READY_POLICY BACKPRESSURE` heavy + max gaps | `uart_echo` | console still correct (UART is on-die; only the program slows) |

### 7.3 Data interface: the link (LINK)

| ID | Name | Stimulus | DUT program | Pass |
|---|---|---|---|---|
| LINK-01 | Smoke + correlation | DET mode, seed 1, gap 0, latency L | `smoke`, `sorting_algo` | FPGA trace == pin-bench trace (`pin.sh compare`) cycle for cycle |
| LINK-02 | Gap/latency sweep | gap_pct ∈ {0, 10, 30, 60, 90}, rd_latency ∈ {0, 1, 7, 64, 500}, 8 seeds each | ISA suite subset + `fe_mem_march` | all pass; correlation holds for every (seed, gap, latency) in DET mode |
| LINK-03 | Ready policies | NORMAL, RANDOM, BACKPRESSURE(1k/10k), ADVERSARIAL | `fe_mem_march`, `tc_link_abort` | `REQ_AFTER_READY_MAX` ≤ 3; never a req outside the guard band; all pass |
| LINK-04 | Memory march | March C- and walking ones/zeros over 1 MiB (BRAM: 96 KiB) with strides that defeat both 8 KiB caches | `fe_mem_march` | 0 miscompares |
| LINK-05 | Writeback storm | dirty-line thrash; read-modify-write across line boundaries; byte/half/word stores then line reads | `fe_wb_storm` | 0 miscompares; `LINK_WR` ≈ expected from the access pattern |
| LINK-06 | Abort storm | — | `tc_link_abort` (exists) | passes; this is the frozen `forte_link_core` abort rule under real fetch flushes |
| LINK-07 | Lane coverage | — | `fe_lane_cov`: touches lines whose addresses set every `A[31:4]` bit pattern reachable in EXT_MEM, writes/reads walking-1 and walking-0 data | all four `LANE_COV_*` registers complete (header lanes only where the address space allows; `A[30:28]` stay 0 by the PMA: documented) |
| LINK-08 | Data patterns from the FPGA side | PS fills memory with all-0, all-1, 0x5555/0xAAAA, and random patterns before release | `fe_checksum` (sums regions and prints) | checksums match the PS's |
| LINK-09 | Long transaction latency | rd_latency up to WDOG−50 | `smoke` | pass; the watchdog does **not** fire; then latency = WDOG+10 makes it fire (prove the watchdog) |
| LINK-10 | DDR backend natural mode | `MEM_BACKEND=AXI`, DET=0 | full ISA + FreeRTOS + `fe_*` suites | all pass; histograms recorded |
| LINK-11 | Checker self-test | `LINK_CFG` mutate bits (as `+FPGA_MUTATE`): corrupt reset fetch, drop a word, drive while `dir=1` | `smoke` | each mutation produces exactly its checker error. Proves the checker can fail |

### 7.4 Status interface (STAT)

| ID | Name | Stimulus | DUT program | Pass |
|---|---|---|---|---|
| STAT-01 | Active | — | `fe_mem_march` loop | `STAT_CLASS` = active; two consecutive half-periods = 2^25 |
| STAT-02 | Quiet | — | `fe_quiet`: warm the caches, then spin in a cached loop (no `wfi` needed) | quiet; half-period = 2^27 (~11 s at 25 MHz) |
| STAT-03 | Stalled | `STALL_INJ`: hold `rvalid` mid-read for 2^18 cycles | `fe_mem_march` | stalled (2^23) during the stall; back to active after; program still correct |
| STAT-04 | Stalled by ready | `READY_POLICY FORCED_LOW` 2^18 cycles | `fe_mem_march` | **record** the class. The phy sits in `LM_START` with `busy=1`, so the RTL predicts "stalled". Confirms the pin documents what a starved chip looks like |
| STAT-05 | In reset | `rst_n=0` | — | `status` frozen while in reset (tick reset), documented; resumes on release |
| STAT-06 | clk_out | — | any | `CLKOUT_EDGES == CLKOUT_WINDOW` |
| STAT-07 | Transitions | alternate active/quiet phases every 20 s | `fe_quiet` phases | classifier follows; `STAT_GLITCH` counts one odd half-period per transition |

### 7.5 Whole top level (SYS)

| ID | Name | Program | Pass |
|---|---|---|---|
| SYS-01 | ISA suite | `testcode/isa_level_testing/tc_*.c` + `tcf_*.c` (forte-only, this is the ASIC top) | all pass, DET and natural |
| SYS-02 | Baremetal + ECC | `testcode/baremetal/*`, `testcode/baremetal_ecc/*` with `fault_inject=1`, `FI_CONTROL=0x7F` armed by the `FI_ARM` prologue (silicon resets it to 0; `ECE411_SIM_INJECT` does not exist on the FPGA; bit 7 traps, so it is CTRL-21's alone) | all pass; counters non-zero for each armed unit exercised |
| SYS-03 | FreeRTOS | `testcode/freertos/tc_*` (7) + `heartbeat_app` | 7/7; heartbeat guest timer within 0.1 % of `CYC_TOTAL` (catches a wrong `configCPU_CLOCK_HZ`) |
| SYS-04 | Linux | `testcode/linux` image, milestones M0..M5 from `hvl/pin/tests/linux.cmd`, console **only** from `fbu_uart` | `AMOEBA_LINUX_BOOT_OK`; link counts within a few % of the pin bench's M-cycle numbers scaled |
| SYS-05 | Fuzz corpus | `hvl/pin/fuzz` Cascade programs (F-stages) | same exit codes as the pin bench |
| SYS-06 | Soak | Linux + random irq (as user-space-irrelevant noise via PLIC sources) + **always-on injection** (pin high, `FI_CONTROL=0x7F` armed by the boot prologue) + RANDOM ready, 12 h; repeated once in the split build | no checker error, no panic; must-be-zero counters stay 0 (§5.4.2) |
| SYS-07 | All-pins chaos | SYS-03 under simultaneous `FI_PATTERN` `RANDOM` (0x7F armed), `IRQ_TRIG` random, gap 30 %, UART RX noise bytes, and in the split build `LINK_PAUSE` random | passes; this is the "entire top level at once" test |


### 7.5b Split clock (SPLIT, `CLOCKS=split` builds only)

Each test inherits the global criteria and records `LINK_FREQ_MEAS`.

| ID | Name | Stimulus | Program | Pass |
|---|---|---|---|---|
| SPLIT-01 | Ratio sweep | link/core ∈ {0.37, 0.8, 1.6, 2.3} (`LINK_SRC=mmcm0`) × LINK-02 gap/latency corners | SYS-01 ISA suite, `fe_mem_march`, FreeRTOS `tc_*` | all pass at every ratio; transaction order matches the bench (`--order-only`) |
| SPLIT-02 | Asynchronous drift | `link_clk` from `FCLK_CLK1` at 25.01 MHz vs `core_clk` 25.00 MHz (the phase walks through every alignment every ~100 µs), 4 h | `fe_mem_march` + `tc_link_abort` loop | 0 miscompares, 0 checker errors; the Gray-pointer crossing has seen every phase thousands of times |
| SPLIT-03 | Reset release phase | 10 000 `RST_TRIG random` releases at random phase vs both clocks, all ratios | `fe_reset_marker` | boot gate passes every time; checks 9/13 never fire; no transaction before both domains are out of reset |
| SPLIT-04 | Link clock pause | `LINK_PAUSE` 1..10 000 cycles at random points, including mid-header, mid-write and in TA | `fe_mem_march`, `tc_link_abort` | no checker error; every transaction completes; the core waits (abort rule respected); status may show stalled during long pauses and returns to active |
| SPLIT-05 | Slow link, core pressure | ratio 0.37 + BACKPRESSURE ready | `tc_link_abort`, `fe_wb_storm` | outbound FIFO fills, no lost or duplicated commands (write count = expected) |
| SPLIT-06 | Fast link, starved FIFO | ratio 2.3 + gap 0 | `fe_mem_march` | FIFO empty edge cases: no spurious beats, `LINK_RD/WR` exact |
| SPLIT-07 | Retune between runs | DRP steps through 8 link frequencies, held in reset between | `smoke` per step | every step boots; measured ratio within 0.1 % of the programmed one |
| SPLIT-08 | Status in the link domain | ratios 0.5 and 2.0 | `smoke`, `fe_idle` | half-periods equal 2^23/2^25/2^27 **`link_clk`** cycles exactly |

### 7.6 What this plan cannot test, said up front

From `fpga/asic/BRINGUP.md` "limits" and the in-fabric topology: real pad
timing, the negedge capture margin, `clk_out` insertion-delay cancellation,
asynchronous reset release against a clock edge (fabric reset is synchronous to
`FCLK`), PVT and power. The split build (§3.4) covers the async FIFOs' Gray
crossings and random-phase reset release between domains, with in-fabric
timing only. The ribbon loopback (backlog, §13) would add real pin timing. The
rest belongs to the VCU118 bring-up board.

---

## 8. Pre-hardware verification of the gateware

No bitstream is built until the gateware has passed in simulation against
the frozen RTL. This is the `tb_pynq_top` discipline from `feature/top_level`.

### 8.1 `fpga/bringup/tb/tb_fbu_vs_pin.sv` (Verilator, `make -C fpga/pynq test-fbu`)

- Instance A: `forte_top` + `pin_link_agent` + `pin_uart_agent` (the bench as
  is). Instance B: `forte_top` + `fbu_top` + a behavioural line memory.
- Same image, same seed, same knobs. B's trace (pulled through the AXI-Lite
  model) is converted by `trace_to_pin.py`, then `pin.sh compare` A B **must
  match cycle for cycle**.
- This gates P1. It proves `fbu_link_slave` implements the bench's protocol,
  decisions and checks exactly, and gives the bench and the FPGA one ground truth.
- The same harness runs every `fbu_link_check` error with the mutations of
  LINK-11.
- Sample-point equivalence: the bench samples at `clk_out` + 5 ns and launches
  at `core_clk` + 2 ns. The gateware samples at the next posedge and launches
  from flops. The resulting fixed offset is documented, and `trace_to_pin.py`
  normalises `cyc` so traces line up. Settling the exact offset is the first
  task of P1.

### 8.2 `fpga/pynq/tb/tb_forte_emu.sv` (Verilator, `make test-forte`)

This is the whole PL top (`forte_pynq_top` with `fbu_mem_bram`) plus a Python
or SV model of the PS that executes `.cmd` scripts through AXI-Lite, exactly
as `sw/forte` will. CTRL-01..05, -10, -12b, UART-01..03, LINK-01, LINK-11
and STAT-03 (shrunken) are run here first, plus one `fbu_scan` session as a
block check. A `CLOCKS=split` variant runs SPLIT-01/03/04 in simulation. Status tests are not run in sim at
the real rates. `forte_top` cannot shrink them, so they use a forced-short
variant of `fbu_status_mon` only.

### 8.3 Lint

`make -C fpga/pynq lint DUT=forte` (Verilator) covers `forte_pynq_top` and
`fbu_top` standalone. `check_frozen.sh` and `check_regs_forte.py` run in the
same target.

---

## 9. Phases and exit criteria

| Phase | Work | Exit criterion |
|---|---|---|
| **P0** Setup | Import `fpga/` from `feature/top_level`; Makefile `DUT=forte` source list (`pkg/*`, `hdl/core/**`, `hdl/forte_*.sv`, `hdl/prim_*.sv`, `fpga/pynq/rtl/emu/*`, `fpga/bringup/rtl/*`); `check_frozen.sh`; `emu_pads`, `emu_srams`; out-of-context synth of `forte_top` + stand-ins (`make utilization TOP=forte_emu_dut`) | Vivado elaborates `forte_top` under `SYNTHESIS` with no black boxes; LUT/FF/BRAM and WNS at 25 MHz recorded; frozen diff empty |
| **P1** Gateware in sim | §5 blocks; `tb_fbu_vs_pin`; `tb_forte_emu`; `sw/forte` against the sim PS model; RTL-sim check of the RF/pipe shared phase (§5.4.2) | trace equality on `smoke`, `sorting_algo`, `irq`, `uart_echo`, `tc_link_abort` for 4 seeds; every LINK-11 mutation caught; CTRL-10/12b pass in sim with `FI_PHASE_OFS` matching the RTL; one `fbu_scan` session passes; lint/check-regs green |
| **P2** Board, BRAM | `bd_pynq.tcl` `DUT=forte MEM_BACKEND=BRAM`; bitstream; `sw/forte` on board | CTRL-01..06, UART-01..02, LINK-01 (trace equal to sim), STAT-01/06, SYS-01 |
| **P3** Board, DDR | `fbu_mem_axi_hp`; `MEM_BACKEND=AXI` | full §7 catalogue except SYS-06/07, SPLIT and the deferred DFT tests; CTRL-20/21 pass; Linux boots (SYS-04) |
| **P4** Stress | soak and chaos (SYS-06/07); flaky-test triage; results report | 12 h soak clean; report in `fpga/pynq/RESULTS_rtl_freeze.md` |
| **P5** Split clock | `forte_top_split`, `fbu_clkgen`, `fbu_line_cdc`; `tb_forte_emu` split variant; `bd_pynq.tcl CLOCKS=split`; P0-style OOC timing of the link domain alone to set the ratio ceiling | SPLIT-01..08 pass; SYS-06 repeated in the split build (12 h) clean |
| **P6** VCU118 port | `fpga/vcu118/` with the same `fpga/bringup/` gateware; JTAG-to-AXI or equivalent host transport; `sw/forte` with only `Mmio` swapped; `CAPTURE_CLK=clk_out`. The PYNQ-Z2 stays the deployed emulation platform | the P2 suite passes against the soft-emulated die on the VCU118 before silicon arrives |

---

### 9.1 P0 results (2026-10-28, Vivado 2024.1, `make -C fpga/pynq utilization`)

OOC synthesis of `forte_emu_dut` (frozen `forte_top` + `rtl/emu/` stand-ins),
xc7z020clg400-1, 40 ns constraint:

| LUT | FF | DSP48 | BRAM36 tiles | WNS @ 25 MHz | Est. Fmax |
|---|---|---|---|---|---|
| 22 840 / 53 200 (42.9 %) | 13 484 (12.7 %) | 16 (7.3 %) | 6 (4.3 %) | +17.9 ns | 45.3 MHz |

- **No black boxes.** Every pad and macro resolved by a stand-in.
- **SRAMs:** only four macros are instantiated by the frozen RTL, one tag and
  one data array per cache: `sram_sp_128_53`/`_137` (I$) and
  `sram_sp_256_53`/`_137` (D$). All four became block RAM (write-first,
  4 RAMB18 + 4 RAMB36). The nine `rf_sp_*` branches of `ram1p1rwe` are
  dead parameter combinations since 4f54add. The async FIFOs and the UART TX
  FIFO went to LUTRAM.
- **`io`:** the 16 lanes' tristates were converted to logic (Synth 8-5799,
  the only critical warnings), as on `feature/top_level`.
- **Assertions:** `prim_fifo_async`'s concurrent assertions are ignored by
  synthesis (Synth 8-2898), as expected.
- **Pruning checked by hand:**
  - Both cache scrubbers are removed entirely, because `SCRUBBER_ENABLED`
    defaults to 0 in `cache.sv` and no instance sets it (Q9).
  - `ft_shadow_ctrl`'s RECOMPUTE/ISOLATED states are removed in the MUL
    instance, which ties `recompute_supported` to 0. That is by design.
- **Fmax:** the worst-*slack* path is the half-cycle path `scan_q` → the
  link phy's negedge capture flop (2 ns against 20 ns), which `fit_report.sh`
  turns into an Fmax as if it were a full cycle. The full-cycle critical
  path has 18.09 ns of slack (21.9 ns, 27 levels), so ≈45 MHz holds.
- **§11 BRAM risk retired:** the chip uses 6 of 140 tiles, so a 128 KiB BRAM
  backend (~32 tiles) fits easily. The 45 MHz is a post-synthesis estimate;
  P2's place-and-route gives the real number.

## 10. PS-side firmware (`fpga/pynq/sw/forte/`)

Python on PYNQ Linux, `/dev/mem` via the existing `amoeba/mmio.py`. Everything
timing-critical is in the PL (triggers, matchers, patterns). Python sets
up, waits and reads results, so its scheduling jitter never decides a
verdict.

### 10.1 Modules

| Module | Contents |
|---|---|
| `regs.py` | offsets and fields, generated from `fbu_pkg.sv`; checked by `check_regs_forte.py` |
| `device.py` | `class Forte`: open overlay, `set_fclk`/`check_fclk` (reuse `amoeba/pl.py`), `check_id`, `caps`; `hold()`, `release()`, `pulse_reset(n)`; `load(img)` (refuses unless `rst_n=0`; zero, write, verify; checks `tohost` symbol against `TOHOST_ADDR`, as `Amoeba.load` does); `run(img, script)`; `errors()` decodes `LINK_ERR`/first-error into the bench's message strings |
| `pins.py` | `irq()`, `test_mode()`, `scan_en()`, trigger configuration, `boot_gate()` |
| `fault.py` | `on()`/`off()` (live, `PIN_CTRL[1]`), `pattern(mode, ...)`, `target(sites)` builds `FI_PHASE_MASK` from the §5.4.1 site table, `calibrate()` (CTRL-12b, stores `FI_PHASE_OFS` per build), `events()`, `chip_counters()` read through the mailbox dump, `check(delta ≤ events, must-be-zero set)`, saturation flagging |
| `clocks.py` | split build: `set_link_mhz()` over DRP, `link_src()`, `pause(n, trigger)`, `ratio()` from `LINK_FREQ_MEAS` |
| `link.py` | latency/gap/ready/stall knobs; counters; histograms; lane coverage report |
| `uart.py` | `read()`, `send(bytes, ctl)`, `set_div()`, matcher; `Console` thread for interactive use (reuse `feature/top_level` `console.py`) |
| `status.py` | read and classify; `wait_class(cls, timeout)` |
| `scan.py` | load patterns, run session, check stub loopback, lane report (deferred DFT tests; kept working by the P1 sim check) |
| `trace.py` | drain records; `to_pin_log()` (same format as `pin_trace.log`) |
| `mailbox.py` | event pop, rdata set |
| `cmdscript.py` | interpreter for the pin bench command language (§10.3) |
| `image.py` | reuse `amoeba/image.py` (ELF) + `.lst` loader (`bin/generate_memory_file.py -8` format), so `load_lst $MEM` works unchanged |

### 10.2 Runners

- `run_cmd.py <program> <script.cmd> [--seed --gap --lat --det --backend]`
  runs one test. It writes `runs/<name>/{RESULT, uart.log, pin_trace.log,
  regs.json}`, the same layout as `sim/pin/runs/`, so `pin.sh compare` and
  existing triage habits work. The verdict line is `PIN_TB_RESULT: PASS|FAIL
  <why>`, as in the bench.
- `run_suite.py <suite.yaml>` runs the §7 catalogue (IDs, sweeps, seeds),
  writes JSON + JUnit XML, and exits non-zero on any failure.
  `--correlate <sim run dir>` compares traces automatically.
- `trace_to_pin.py`, `check_regs_forte.py`; the existing `deploy.sh` and
  `find_board.sh` are reused.
- `test_device_forte.py`: offline unit tests on a fake MMIO (the
  `test_device.py` pattern). For example: `load` refuses while released;
  `cmdscript` maps each command to the right register sequence; the verdict
  logic fails on any sticky error.

### 10.3 Command language: bench dialect plus a separate `fbu` dialect

`hvl/pin/pin_tb.sv` stays the post-synthesis bench and gains nothing.
`cmdscript.py` accepts two dialects:

- **`pin` dialect** (the default). Exactly the bench's commands, with the
  bench's meaning, so `hvl/pin/tests/*.cmd` run on the FPGA unmodified:
  `mem_policy`, `load_lst`, `load_bin`, `reset <cycles>`, `run <cycles>`,
  `run_until_tohost`, `run_until_uart`, `expect_tohost`, `uart_div`,
  `uart_send`, `uart_send_ferr`, `uart_gap`, `uart_fail`, `irq`,
  `fault_inject`, `dump_mem`, `finish`. A script in this dialect that uses an
  `fbu` command is rejected, so a "bench" script can never silently depend on
  FPGA-only behaviour. Two notes:
  - `run <cycles>` polls `CYC_SINCE_RST`, so it waits at least that long,
    never an exact number of cycles. Anything that needs an exact cycle uses a
    trigger command.
  - `mem_policy x` maps to `rand`, because hardware has no X. `x` is accepted
    with a warning.
- **`fbu` dialect.** The file's first line is `dialect fbu`, and it lives in
  `fpga/bringup/tests/`. Everything above, plus:

| Command | Effect |
|---|---|
| `link <knob> <val>` | `det`, `gap`, `lat`, `seed`, `ready <mode> <a> <b>`, `stall <xact> <cyc>`, `wdog <n>`, `mutate <n>` |
| `reset_at <cycle\|xact N state S +d\|random seed>` | arm `RST_TRIG` |
| `reset_pulse <n>` | |
| `boot_gate <on\|off\|selftest> [retries timeout]` | |
| `irq_at <line> <cycle\|uart "text"\|random a b>` | arm `IRQ_TRIG` |
| `fault_inject <0\|1>` | (bench command, same meaning) the live on/off switch, `STATIC` mode |
| `fault_pattern <square p h\|random lo hi seed\|pulse n\|burst k\|phase <sites…> [periods]\|single <site>\|off> [at <cycle\|uart "text"\|release>] [window a b]` | arm `fbu_fi_gen`; sites by name (`alu0.result`, `cmp1`, `mul`, `dcache`, …) |
| `expect_fi <group> <op> <n>` / `expect_fault_delta <counter> <op> <events\|n>` | PL event counts vs the chip's counters (read back via the program's mailbox dump) |
| `clock link <mhz\|async mhz>` / `clock pause <n> [at …]` | split build only; rejected otherwise |
| `test_mode <0\|1>` / `scan_en <0\|1>` / `test_at uart "text"` | deferred DFT tests |
| `scan <pattern-file\|walk\|random n> [scan_en mode]` / `expect_scan stub` | deferred DFT tests |
| `uart_cfg <rx_div> <tx_div> [tx_err_pct]` / `uart_send_ctl <hex> <ctl>` / `uart_break <bits>` / `uart_glitch <cycles>` / `rx_force <0\|1\|off>` | |
| `expect_status <stalled\|active\|quiet> <timeout_s>` | |
| `expect_counter <name> <op> <value>` | assert on any `fbu_regs` counter (`LINK_RST_ABORT >= 1`, `REQ_AFTER_READY_MAX <= 3`, ...) |
| `expect_lane_cov <hdr\|wr\|rd\|scan>` | |
| `mbx_data <i> <hex>` / `expect_irq_lat <max>` | |
| `expect_no_errors` | the global criteria now, not only at `finish` |

**Correlation with the bench:** `tb_fbu_vs_pin` (§8.1) uses only `pin`-dialect
scripts, so the cycle-exact gate never depends on a command the bench lacks.

---|---|
| `link <knob> <val>` | `det`, `gap`, `lat`, `seed`, `ready <mode> <a> <b>`, `stall <xact> <cyc>`, `wdog <n>`, `mutate <n>` |
| `reset_at <cycle\|xact N state S +d\|random seed>` | arm `RST_TRIG` |
| `reset_pulse <n>` | |
| `boot_gate <on\|off\|selftest> [retries timeout]` | |
| `irq_at <line> <cycle\|uart "text"\|random a b>` | arm `IRQ_TRIG` |
| `fault_pattern <static v\|square p d\|random seed\|pulse n>` | |
| `test_mode <0\|1>` / `scan_en <0\|1>` / `test_at uart "text"` | |
| `scan <pattern-file\|walk\|random n> [scan_en mode]` | run a session; `expect_scan stub` checks the loopback |
| `uart_cfg <rx_div> <tx_div> [tx_err_pct]` / `uart_send_ctl <hex> <ctl>` / `uart_break <bits>` / `uart_glitch <cycles>` / `rx_force <0\|1\|off>` | |
| `expect_status <stalled\|active\|quiet> <timeout_s>` | |
| `expect_counter <name> <op> <value>` | assert on any `fbu_regs` counter (`LINK_RST_ABORT >= 1`, `REQ_AFTER_READY_MAX <= 3`, ...) |
| `expect_lane_cov <hdr\|wr\|rd\|scan>` | |
| `mbx_data <i> <hex>` / `expect_irq_lat <max>` | |
| `expect_no_errors` | the global criteria now, not only at `finish` |

---

## 11. Resource and risk notes

| Risk | Mitigation |
|---|---|
| BRAM budget in the BRAM backend: 128 KiB memory (~32 tiles at 128-bit width) + cache macros + trace + UART FIFOs + scan RAMs; old `asic-asic-BRAM` used 113/140 | Trace 2 k records; scan RAMs in LUTRAM; P0 OOC synth reports it before any gateware is written. Fallback: `MEM_KB=64` for BRAM builds (tests with larger footprints run on AXI only) |
| 25 MHz may not close with `forte_top`'s link domain + macros | P0 measures; 20 MHz is acceptable (only UART divisors and status wall-times change) |
| Vivado drops or alters internal tristate on `io` | Proven pattern on `feature/top_level`; P0 inspects the post-synth netlist for the mux and P1's `tb_forte_emu` runs on the *post-synthesis* functional netlist once (`write_verilog -mode funcsim`) |
| Trace equality fails on a cosmetic offset | §8.1 normalisation is P1's first task; mismatch triage via `bin/vcd_first_x.py`-style first-divergence report in `trace_to_pin.py` |
| `% 100` of a 64-bit PRNG in hardware | The bench is not changed, so the gateware matches `rand64() % 100` exactly. The PRNG sequence does not depend on the data, so the next value and its remainder are computed several cycles ahead in a pipelined constant-modulus reducer, with no timing pressure |
| Fault counters saturate within seconds under continuous injection | §5.4.2: judge long runs by results and the must-be-zero counters; `BURST` for rate checks; `EMU_TAPS` oracle |
| RF and pipeline ECC injectors share phase `0x1FF` | P1 RTL-sim check (§5.4.2) before CTRL-20 arms both |
| `forte_top_split.sv` drifts from `forte_top.sv` | `check_frozen.sh` diff with one allowed difference |
| Link-domain Fmax caps the split-clock ratios | P5 measures it first; the ratio set is scaled to fit |
| Python latency in handshakes | all cycle-critical actions use PL triggers (`UART_MATCH`, `RST_TRIG`, `IRQ_TRIG`, `TEST_TRIG`) |
| Doc drift | `docs/memory_map.md` still says `FI_CONTROL` resets to `0x3F` with 6 units and that the fault counters are "not routed on the ASIC"; the RTL says reset `0x00`, 8 units, counters present at `PSEL[5]`. Tests follow the RTL; fix the doc separately (it is not `hdl/`, so not frozen) |

---

## 12. Decisions (rev 0.2) and remaining questions

| # | Question | Decision |
|---|---|---|
| Q1 | Freeze commit | `postsynth_verif` (this branch's base, `8babc55`) |
| Q2 | Cache-uncorrectable (bit 7) behaviour | It traps: cause 20 on a dirty D$ line; clean lines and the I$ drop and refetch. CTRL-21 is the oracle. Bit 7 is never part of always-on injection |
| Q3 | New commands in `pin_tb.sv`? | No. Separate `fbu` dialect (§10.3); `hvl/pin/` untouched |
| Q5 | PRNG modulo | Follows from Q3: the bench is unchanged and the gateware matches `% 100` exactly (§11) |
| Q6 | Bring-up board | VCU118 (P6). The PYNQ-Z2 is the deployed emulation platform |
| Q7 | P5 scope | Split-clock build is required (P5). The ribbon loopback goes to the backlog (§13) |
| — | `fault_inject` from the PS | Yes: live on/off plus the pattern generator (§5.4.1); always on for bits 0–6 (§5.4.2) |
| — | DFT | Tests deferred; `fbu_scan` built and sim-checked |

Still open:

1. **Q4: interrupt-latency bound.** Is there a spec number, or do we take the
   RTL sim's measured max plus a margin?
2. **Q8: counter saturation.** Is "16-bit, saturating, reset-only clear" the
   intended silicon behaviour for long-running fault-tolerance demos? It cannot
   change now. The question is whether bring-up and demo software should plan
   on periodic resets.
3. **Q10: SECDED never reports a flip of the overall parity bit.**
   `ecc_secded_dec.sv` (every `flopenrc_cw`/`flopenrc_ecc`: the register-file
   read path and the pipeline registers) sets `sec_err_o` only when the
   syndrome is non-zero; a flip of the parity bit alone (syndrome 0, parity
   wrong) raises neither flag. The data is right, but the error is not counted
   and the register does not repair itself, so the flip stays; a later
   single upset in the same word then decodes as DED (trap) where standard
   SECDED would have corrected both in turn. About 1 in 72 injected flips is
   never counted (197 of 200 per site in the standalone testbench). The usual
   fix is `sec_err_o = parity_check`; the RTL is frozen, so this goes to the
   decoder's owner.
4. **Q9: cache scrubber disabled.** `cache.sv` defaults `SCRUBBER_ENABLED`
   to 0, and neither the I$ nor the D$ instance overrides it, so the frozen
   RTL (and Vivado, §9.1) has no scrubber. Is that intended for tapeout? If
   so, a stored cache SEC flip in a line that is never read again stays
   latent until eviction. The FPGA tests are written for the RTL as frozen.
   **Measured cost** (Vivado OOC, same flow as §9.1, `SCRUBBER_ENABLED=1` on
   both caches in a scratch copy of `lsu.sv`/`ifu.sv`, `hdl/` untouched):
   +72 LUT (+0.3 %), +37 FF (+0.3 %), no BRAM/DSP change. The worst
   full-cycle path grows from 21.9 ns (27 levels) to 28.5 ns (39 levels),
   HPTW walker state → D$ data-array write data, through the scrubber's
   correction write-back mux. Fmax drops from ≈45 to ≈35 MHz, still above
   25 MHz. `SCRUB_INTERVAL_CYCLES=0`, so a tuned interval adds its counter
   (≈log2(interval) FFs). The ASIC timing effect needs a DC run to confirm.
   Decision (2026-10-28): proceed without the scrubber.

---

### 12.1 Findings in the frozen RTL

What the FPGA tests found in the RTL as frozen (`8babc55`). The RTL does not
change on this branch; each finding goes to its owner. F1 to F5 are defects;
F6 and F7 are behaviour the tests and software must allow for.

**F1. An I$ ECC repair can be written to the wrong set (silent wrong code).**
`STATE_ECC_WRITEBACK` (`cachefsm.sv`) writes the corrected tag and line back
into the hit way after a correctable error. In `cache.sv`, a `FlushStage`
makes the I$ array address follow `NextSet` for the new PC:
`AdrSelMuxSelData = {FlushCache, ((SelAdrData | SelHPTW) & ~((READ_ONLY_CACHE == 1) & FlushStage))}`
(likewise for the tag). That override is Wally's and is safe for fills, but
if a Decode flush (branch mispredict, trap, FT replay) lands in the cycle of
the repair write, the repair goes to the new PC's set. The I$ then holds a
line under the wrong address: a later fetch with the same tag in that set
hits it and runs another function's code, with no fault reported.
- Found by CTRL-20: `tc_pmp_deny` armed `0x5F` at gap setting `g10s4l7`
  (`+FPGA_GAP_PCT=10 +FPGA_SEED=4 +FPGA_RD_LAT=7`) hangs on the RTL pin bench
  and on the gateware alike. At cycle 523 266 a hit on `0x80001c14` (set 0x01,
  way 1, injected SEC) is repaired while `FlushD`/`FlushE` redirect to
  `0x8000133c`, and the repair lands in set 0x33, way 1. At cycle 757 938 the
  fetch of `0x80001f30` (same tag `0x200007`, set 0x33) hits it and executes
  `0x80001c10`'s instructions; decoding goes out of step at a compressed
  instruction, traps as illegal at `0x80001f40`, leaves `ra` in zeroed padding,
  and the test's handler then traps forever. Every unit armed alone passes;
  the injection only supplies the correctable error and moves the timing.
- In silicon a real upset does the same. Likely fix: no `FlushStage` override
  of the array address while in `STATE_ECC_WRITEBACK`, or no repair write for
  a flushed I$ access.

**F2. SECDED never reports a flip of the overall parity bit** (Q10). Fix with
a test on `debug/ecc-syndrome-fix` (pushed for review): `sec_err_o =
parity_check`; the repo's ECC suite passes with it.

**F3. A dirty D$ line with an uncorrectable error livelocks a demand miss**
(CTRL-21). Evicting it raises cause 20 at once (`TrapM = ExceptionM &
~CommittedF`); the trap's flush abandons the refill before the victim is
replaced, the line stays valid, and the retried access picks the same victim
and traps again. Only a D$ flush (`fence.i`, there is no Zicbom) drops it,
trapping once more as it does (`mtval` = the line). Every cause-20 handler
must recover with `fence.i`, never by touching other lines of the set.

**F4. An uncorrectable tag on a clean line is never counted** (CTRL-21).
`TagDedErr = TagDedErrWay & HitWay`, a way with a DED tag never hits, and a
clean victim's tag is not checked. Harmless (the line misses and is
refetched) but invisible: the I$ DED counter (5) cannot move from injection
with the scrubber off (Q9), because a fill takes the tag and data flips
together.

**F5. RF and pipeline ECC armed together lose the RF's faults** (§5.4.2). The
pipeline flip's `EccStallE` holds `RD1E`/`RD2E` in the cycle that would
capture the RF-flipped read: 605 RF detections alone, +4 with both. No wrong
result; lost coverage only.

**F6. The fault counter starts 4 cycles after the link** (CTRL-12b): the
chip's reset synchronisers. `FI_PHASE_OFS` resets to 4; calibration measures
it.

**F7. The divider's fault check sees only completing divides** (CTRL-10,
CTRL-22). A periodic loop can complete every divide on the other parity from
the injector's phase and detect nothing; tests jitter the loop. Coverage on
real code is low.

## 13. Backlog (TODO, not scheduled)

- **`REG_SOFT_RESET` should reset the configuration registers** (§5.10), so
  their reset values live only in `fbu_top` and `regs.CONFIG_RESET` goes.
  Needs a rebuild and the gates.
- **Root-cause the HP0 reload wedge** (§5.10). Candidates: AFI/HP0 state
  the PL teardown leaves behind, or the boot design's PS7 settings for HP0
  that `fpga_manager` loads do not apply. Sample the AFI registers
  (`psmon.py`) before and after loads; try a reload with HP0 clock-gated.
  Until then, one load per boot.
- **Review the `irq.c` wait-loop fix with the bench owners** (changed on
  `fpga/rtl_freeze` only). `while (!(seen3 && seen6)) wfi;` ran with MIE on:
  IRQ6 taken between the `seen6` load and `wfi` returned into `wfi` and the
  chip slept for good. Not an RTL bug: the reference pin bench hangs the
  same way with the FBU's irq edge times. At rd_latency 0 the window is never
  hit; at 56-128 with gaps it is (the DDR gate's `irq/script_irq_g30s1` and
  `g60s3`). An IRQ6 edge swept on the bench (g30s1, rd_latency 64) hangs for
  exactly 11 cycles (8844-8854); with the check made under MIE off, `wfi`
  then MIE on, all 137 edge times tried (8600-9600) pass. Decide whether
  `postsynth_verif` takes the fix.
- **Real-pins ribbon loopback** (was P5a). `forte_top` pins out through PYNQ
  headers and looped by ribbon to the `fbu_top` pins. That is about 64 header
  pins (RPi + Arduino + 2 PMOD give roughly that many). Capture on the returned
  `clk_out`, IDELAY/MMCM eye sweeps (the `link_eye.py` idea), full suite at
  10/25 MHz. Re-pins `feature/top_level`'s stage-C design for 32 signals.
- **DFT tests** CTRL-14..18 on hardware (scripts only; gateware is in place).
- Fix `docs/memory_map.md` (`FI_CONTROL` reset and width, fault counters).
- **CTRL-22 shift-channel margin.** ALU replica 0's shift channel (`1de`)
  detected only 2 times in 256 periods on the board (9 in sim); raise the
  `1de` and `19e` rounds in `fe_fault_site.cmd` to 1024 periods.
- **CTRL-22 RF/pipeline separation with both armed.** Let `target_site` take
  an `FI_CONTROL` mask, arm `0x30`, and check that the pin high only at `1FE`
  moves the pipeline counter alone and only at `1FF` the RF counter alone
  (§5.4.2: with the pin high at both, the pipeline flip's stall drops the RF
  flip).
