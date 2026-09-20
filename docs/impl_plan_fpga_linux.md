# Implementation Plan — Linux on the FPGA through `amoeba_top`

**Rev 0.5 · 2026-09-20 · Tier 4 of `docs/impl_plan_onchip_periph.md` · PYNQ-Z2 first, VCU118 after**

Goal: the PYNQ-Z2 design that boots Linux today (`fpga/pynq`, `CONFIG=baremetal_linux`,
`MEM_BACKEND=AXI`) boots the same image with the ASIC top in the fabric and every
byte of memory traffic crossing the 16-bit link. Everything the PS-side tooling
reads — console, `tohost`, counters, trace — keeps working.

The design rule from `fpga/asic/BRINGUP.md` §6 is what makes this small: **keep
the AHB-facing structure identical.** The link slave reconstructs the AHB-Lite
master that `amoeba_soc_wrapper` exposes today, so `amoeba_pynq_top`,
`amoeba_ctl`, `amoeba_bus_probe`, `amoeba_mem_bram`, the block design and
`sw/amoeba/` see the same bus they see now.

```
today       amoeba_soc_wrapper ─── AHB ──► mem_bram | ahblite_axi_bridge → DDR
                     ▲ hierarchical taps (trace, retire)
                     ▲ bus_mon snoops HADDR/HWDATA/HTRANS (console, tohost)

stage A/B   amoeba_asic_wrapper
              ├ amoeba_top ──── io[15:0]+6 ctrl ────┐   (tristate resolved in fabric)
              └ amoeba_link_slave ◄─────────────────┘ ── AHB ──► same backends
                     ▲ taps now dut.top.chip.soc.core.*   (rehearsal only)
                     ▲ bus_mon snoops dut.top.chip.soc.HADDR/... by reference
stage C     same, io through IOBUFs on real header pins, ribbon to a second header
```

---

## 0. Status

| Item | State |
|---|---|
| `fpga/pynq/rtl/amoeba_link_slave.sv` | Written. INCR8/SINGLE AHB master, descriptor queue (4) + beat FIFO (16), line buffer, poison on HRESP, counters, training-direction LFSR check, `IN_REG` input stage. |
| `fpga/pynq/tb/tb_link_slave.sv`, `make test-link` | **Green.** 51 transactions against the real `amoeba_link_master` + `amoeba_link_train`: singles of every size, INCR8 both ways, pipelined accepts, one injected mid-burst abort. Monitor confirms 42 INCR8 + 9 SINGLE on the slave's bus, none terminated early; TA honoured on every `dir` edge. |
| `amoeba_asic_wrapper.sv`, `amoeba_pynq_top.sv` (`DUT_ASIC`), `amoeba_pynq_top_v.v`, `amoeba_ctl.sv` (0xA0–0xB8, STATUS 6–8), tcl, Makefile (`DUT=soc\|asic`, `TRAIN_LEN`) | Written. `lint` green for `TOP=amoeba_asic_wrapper` and `TOP=amoeba_pynq_top` at `DUT=asic CONFIG=asic`, and for the soft core at `DUT=soc`. `check-regs` green (44 offsets). |
| `sw/amoeba/regs.py`, `device.py`, `run_linux.py` | `start()` blocks on `STATUS.link_trained` when `CAPS.asic_link`; `wait_link()` raises with a diagnosis on `link_failed`/timeout; `link_stats()`, `set_irq()`; `run_linux.py` prints link stats. |
| `fpga/pynq/tb/tb_pynq_top.sv`, `make test-top DUT=asic CONFIG=asic TEST=…` | **Green, 7/7 FreeRTOS** (`images-bram/`): the whole PL top in Verilator, image loaded over the AXI window, `CTRL`/`STATUS`/`UART_DATA` driven as `device.py` does. Link trained 162 cycles after release (`TRAIN_LEN=64`); console text arrives through the internal-bus snoop; `tohost` seen. `tc_semaphore`: 204 k cycles vs 137 k on the soft core — the BRAM path serialises the link behind `ahb_to_memitf`'s 3 cycles/beat; the AXI/DDR path keeps the burst. |
| **Stage A** — `bit/asic-asic-BRAM` | **Passes on the PYNQ-Z2.** Vivado 2024.1, 30 min, 0 errors; 17.6 k LUT / 13.1 k FF / 113 BRAM (soft core: 15.8 k / 11.1 k / 104.5); WNS 0.70 ns at 25 MHz on the same HPTW→D$ path as the soft core (0.10 ns) — the link is not on any top path. One RTL fix for Vivado's parser (`f(x)[31:16]` → wire in `amoeba_link_master.sv`). On the board: `heartbeat_app` 99 beats, 250 M cycles, 228 M retired, mean period 100.00 ms, guest timer 24.999 MHz vs PL 25.000 MHz; `run_regression.py` **7/7**. |
| **Stage B** — `bit/asic-asic-AXI` | **Linux 6.6 boots to userspace on the PYNQ-Z2 through the ASIC top and the link**, from the DDR carve-out. `AMOEBA_LINUX_BOOT_OK` at **326.5 M cycles / 13.1 s** (soft core: 155.3 M / 6.2 s — **2.10×**). 4,198,683 link transactions (3.25 M rd, 0.95 M wr), within 0.2 % of the Verilator tier's 4.19 M; retrains 0, train_err 0, hresp_err 0. The sim tier's "+10 %" was against `ahb_to_memitf` (~5 cycles/beat); against a real INCR8 to DDR the link adds ≈34 cycles of serialization per line on top of the DDR latency, ≈170 M cycles over the boot. Link utilisation ≈41 % of 50 MB/s. This is the silicon's memory-path cost at link clk = core clk; the levers, in order, are I-cache size, a next-line read-ahead in the slave (hides latency, not serialization), and link clock > core clock (stage C's question). |
| Stage C/D | Not started. Note for C: the core's HPTW→D$ path is 38 ns of a 40 ns period on both DUTs, so `FCLK_MHZ=50` will not close on this part; sweep 10/25 (and 33 if the fabric allows). |
| Deviations from rev 0.2 | `R_LINK_ERR 0xB8` added ({train-pattern mismatches, HRESP beats}); `STATUS[8]` = the chip's `status` pad. `tb_pynq_top` is not optional any more: it is the stage-A gate that runs without Vivado. |

---

## 1. Stages

| Stage | What | Backend | Pass criterion |
|---|---|---|---|
| **A** | `amoeba_top` + `amoeba_link_slave` in the fabric, `io` internal | `MEM_BACKEND=BRAM` | `heartbeat_app` calibration line; `sw/run_regression.py` 7/7 FreeRTOS |
| **B** | same | `MEM_BACKEND=AXI` (DDR carve-out) | `tc_mem_stress`/`tc_mem_align` on DDR; **`sw/run_linux.py` to `AMOEBA_LINUX_BOOT_OK`** |
| **C** | `io` and controls on real pins, looped by ribbon to a second header; `link_slave` on the far pins | AXI | same as B, plus training converges across `FCLK_MHZ` ∈ {10, 25, 50} |
| **D** | VCU118: same RTL, new board dir, DDR4 via MIG, JTAG-to-AXI host transport | MIG | same as B |

A and B need no board wiring and no constraint changes: they are a recompile of
the design with a different DUT and prove the link + bridge + slave logic on
hardware. C is the first time real pad timing exists. D is the bring-up
platform.

---

## 2. File-by-file

### 2.1 New RTL (`fpga/pynq/rtl/`)

| File | Contents |
|---|---|
| `amoeba_link_slave.sv` new | The FPGA end of the link, synthesizable, from `pkg/amoeba_link_pkg.sv`. Same structure as `hvl/common/amoeba_link_model.sv` but the memory side is an **AHB-Lite master with the same burst shape the core emits today**: a line op from the header becomes one `HBURST=INCR8`, `HSIZE=3` burst from the aligned base (NONSEQ + 7 SEQ, address phase pipelined over the previous data phase); a single op becomes `HBURST=SINGLE` at the header's `HSIZE`, with `HWSTRB` from `size_to_mask`. Both backends already accept exactly this from `wallypipelinedsoc`, so `ahb_to_memitf` sees nothing new and `ahblite_axi_bridge` keeps an 8-beat line as one AXI burst. **The slave never terminates a burst early** — the ASIC-side bridge drains an aborted line on its own (`link_abort` test), so every transaction the slave starts runs to completion. Training echo on the first `dir` fall after reset and on any later `dir` fall with nothing outstanding; 2-word header → `addr_unpack`/`size_unpack`; write words → line buffer → the burst issued once the last word lands (a write is 34 link cycles, so the buffer is full before the bus is needed); read header → burst issued immediately, words streamed with `rvalid` as beats land, bus released after the last word; `ready` = idle ∧ line buffer free; TA counted on both `dir` edges. Outputs `trained`, `xact`, `rd`, `wr`, `retrain` counters for `amoeba_ctl`. Adds BRINGUP.md §2's poison (`0xBAADC0DE_DEADBEEF` for `HRESP`/out-of-window) and a no-request watchdog counter. Inbound pins registered on `aclk` posedge in stage A/B; stage C adds `IDELAYE2` on `io`/`dir`/`req`/`wr`/`burst` and an `ODELAY`-less MMCM phase on the outbound clock. |
| `amoeba_asic_wrapper.sv` new | Same ports as `amoeba_soc_wrapper` (clk, `reset_ext`, `reset`, `ExternalStall`, the AHB master, `UARTSin`/`UARTSout`) **plus** `link_trained`, `link_failed`, `link_stats`, `irq[1:0]`. Inside: `amoeba_top #(.TRAIN_LEN(TRAIN_LEN))` with `rst_n = ~reset_ext`, `amoeba_link_slave`, the 16-bit `io` net between them (Vivado turns an internal tristate into mux logic; that is fine in A/B and is replaced by `IOBUF`s in C). Port-by-port: `HCLK` = clk; `HRESETn` = the slave's synchronized reset (deasserts before the core's, which waits for training — the same order `BRIDGE_LEAD` already establishes); `HSELEXT` = 1 while a link transaction is open (everything on the link is external memory by definition); `HADDR` = `addr_unpack` zero-extended to `PA_BITS`; `HPROT`/`HMASTLOCK` constants; `HREADY` = the backend's `HREADYEXT` (the slave is the only master and there are no internal slaves behind it); `UARTSin`/`UARTSout` = the `uart_rx`/`uart_tx` pads; `reset` out = `top.chip.soc.reset` by reference (waves only); `ExternalStall` unconnected inside — see §3. |
| `amoeba_uart_rx.sv` new (stage C option) | Only if the console is ever to come off the `uart_tx` pin instead of the snoop: 16550-compatible receiver with a host-programmed divisor register. Not needed for A–D as long as the snoop (§2.2) stays. |

### 2.2 Changed RTL

| File | Change |
|---|---|
| `amoeba_pynq_top.sv` | New parameter `DUT_ASIC` (bit, default 0). `generate if (DUT_ASIC)` instantiates `amoeba_asic_wrapper dut` else `amoeba_soc_wrapper dut`, same port list. Hierarchical taps for `amoeba_trace`/`amoeba_retire` become `dut.top.chip.soc.core.*` and `amoeba_bus_mon`'s inputs become `dut.top.chip.soc.HADDR/HWDATA/HWRITE/HTRANS/HREADY` — the SoC's *internal* bus, since THR writes never reach the link (a `define` pair `DUT_CORE`/`DUT_BUS` keeps it to two lines). The `ahb_run` gate, `m_ahb_hsel = ahb_run` and the `m_ahb_htrans` mask stay as-is on the slave's reconstructed bus; they no longer do the work they were added for (the core's static NONSEQ in reset and Wally's FlushD burst aborts both stop at the die now — see §3) but they keep "nothing leaves while held" structural. `uart_txd_obs` ← `dut.uart_tx`. `CAPS_WORD` gains a `CAP_ASIC_LINK` bit so the driver knows which DUT it is talking to. |
| `amoeba_pynq_top_v.v` | Pass `DUT_ASIC` and `TRAIN_LEN` through (Verilog-2001 wrapper for the BD). |
| `amoeba_ctl.sv` | `R_STATUS` gains `link_trained` (bit 6) and `link_failed` (bit 7). New registers `R_LINK_XACT 0xA0`, `R_LINK_RD 0xA4`, `R_LINK_WR 0xA8`, `R_LINK_RETRAIN 0xAC`, `R_LINK_WDOG 0xB0`, `R_IRQ 0xB4` (write: drive `irq[1:0]`; default 0). `MON_CLEAR` clears the link counters too. `trace_stalling` is tied 0 under `DUT_ASIC`. |
| `amoeba_bus_probe.sv` | Unchanged for A/B (it watches `m_ahb_*`, which the slave now drives). Stage C: `bus_capsel` gains a link-pins capture source (`dir,req,wr,burst,ready,rvalid,io`). |
| `amoeba_bus_mon.sv` | Unchanged; its inputs are re-pointed by reference in `amoeba_pynq_top`. |
| `amoeba_soc_wrapper.sv` | Unchanged; still the soft-core DUT when `DUT_ASIC=0`. |

### 2.3 Sources and build (`fpga/pynq/`)

| File | Change |
|---|---|
| `Makefile` | `DUT ?= soc` (`soc` \| `asic`) → `DUT_ASIC` parameter and `REPORT_TAG`/`BITDIR` gain `-asic`. `SHARED_SRCS` += `$(REPO)/pkg/amoeba_link_pkg.sv $(REPO)/hdl/amoeba_*.sv` (not `rvfi_tap.sv`, not `rv64_core_wrapper.sv`). `INCDIRS` unchanged (`pkg` already there). `CONFIG=asic` already exists. New target `test-link` (§2.5). `images` target: `CONFIG=asic` → the `baremetal_linux` image, as in `sim/Makefile`. |
| `tcl/build.tcl`, `tcl/bd_pynq.tcl` | Plumb `opt(dut)` → `CONFIG.DUT_ASIC` on the top; nothing else in the BD changes (same `m_ahb_*`, same `ahblite_axi_bridge`, same carve-out). |
| `tcl/synth_ooc.tcl` / `utilization` | Works as-is; the report for `DUT=asic` is the first fabric-resource number for the ASIC top (expect the link to be noise next to the core). |
| `constraints/pynq-z2.xdc` | A/B: unchanged. C: add the link pins on the RPi header (`io[15:0]`, `dir`, `req`, `wr`, `burst`, `ready`, `rvalid` = 22) and the far end on the Arduino header, `IOSTANDARD LVCMOS33`, `set_input_delay`/`set_output_delay` relative to `FCLK_CLK0` with the ribbon's flight time, and `set_property IOB TRUE` on the link flops. `status` → LED, `uart_tx` → PMOD for a scope. |

### 2.4 Software (`fpga/pynq/sw/`)

| File | Change |
|---|---|
| `amoeba/regs.py` | New register offsets and `STATUS` bits; `CAPS.asic_link`. `check_regs.py` re-run — it fails the build if RTL and driver disagree. |
| `amoeba/device.py` | `Amoeba.release()` waits for `STATUS.link_trained` (or fails on `link_failed`) before it starts streaming the console; `link_stats()` accessor. |
| `run_freertos.py`, `run_linux.py`, `run_regression.py` | Unchanged logic. `run_linux.py` prints link stats with its summary. The ladder in `BRINGUP.md` §8 gains a rung: `cycles > 0, link_trained = 0` → link, not core. |
| `psmon.py` | Unchanged. |

### 2.5 Tests and CI

| File | Change |
|---|---|
| `fpga/pynq/tb/tb_link_slave.sv` new | Verilator unit test of the slave against the real bridge: `amoeba_link_master` driven by a small AHB master BFM (singles, INCR8 reads/writes, back-to-back, one injected mid-burst IDLE) → `amoeba_link_slave` → `amoeba_mem_bram` (backdoor-loaded). Checks data, word counts, TA on every `dir` edge, training echo, that an abort drains on the ASIC side and the slave still runs its INCR8 to completion, and — with an AHB monitor on the slave's bus — that every line op is exactly one INCR8 (NONSEQ + 7 SEQ, consecutive addresses, no early termination) and every single op is one SINGLE. `make test-link`, alongside `test-mem`. |
| `fpga/pynq/tb/tb_pynq_top.sv` new (optional) | `amoeba_pynq_top #(DUT_ASIC=1, MEM_BRAM=1)` in Verilator with an AXI-Lite loader BFM running one `tc_*.elf`: the whole fabric design before Vivado. Worth it if stage A does not come up first time. |
| `.github/workflows/ci.yml` | `make -C fpga/pynq lint DUT=asic CONFIG=asic` and `test-link` next to the existing `lint`/`test-mem`. Vivado stays EWS-only. |

---

## 3. Flow changes and things that stop being true

- **The DUT no longer has `ExternalStall`.** `amoeba_trace` uses it to back-pressure the core when its FIFO fills; `amoeba_chip` ties it low (it is not a pad). Under `DUT_ASIC` the trace runs in windowed / drop-on-overflow mode only — `trace_stalling` reads 0 and `trace_overflow` is the signal to watch. This is the correct rehearsal of silicon, where there is no such pin either.
- **Reset sequencing gains a step.** Today: load image → `CORE_RESET=0` → core fetches. Now: load image → `CORE_RESET=0` → `rst_n` rises → **training (2 × `TRAIN_LEN` + TA cycles, ~0.4 ms at 25 MHz for the default 4096)** → core released → first fetch. `device.release()` blocks on `STATUS.link_trained`. `BRIDGE_LEAD` is still right: the slave must be out of reset before `rst_n` rises, and it is.
- **The FPGA never sees an aborted burst.** Wally's FlushD abort — the reason for the always-selected `HSEL`, the `HTRANS` mask and the `hready_in` rewiring in `amoeba_pynq_top` — is absorbed inside the ASIC: the link master drains the full line and discards it. Every INCR8 the slave issues runs 8 beats, so `ahblite_axi_bridge`'s burst-termination path is never entered. The defensive wiring stays because it is cheap, not because it is needed.
- **The core's un-parked AHB in reset also stops at the die.** The link master is gated on `trained` and the slave idles until a `req`, so nothing appears on the exported bus before the core is released. `bus_rstxact` reading non-zero under `DUT_ASIC` now means a slave bug, full stop.
- **The console path is unchanged in A–D but by a different mechanism.** `amoeba_bus_mon` reads the *internal* AHB of the SoC by hierarchical reference — the same technique the trace already uses ("Vivado synthesizes read-only cross-module references"). On silicon that bus is inside the package, which is why the on-chip-UART decision costs a physical receiver later; the rehearsal does not need it.
- **`HRESETn`/`m_ahb_hresetn`**: the bridge reset is now the slave's; keep it tied to `core_hold_req` as today so a stale `HRESP` cannot survive a run.
- **Address translation moves one module down**: `m_ahb_haddr = DDR_CARVEOUT | ((A − EXT_MEM_BASE) & RANGE)` applies to the address the slave unpacks from the header. Same clamp, same guard.
- **DDR burst efficiency is preserved.** A line op is one INCR8 on the exported AHB and one 8-beat AXI burst at the HP port, as today. The +10 % cycle cost seen in simulation is the link's serialization, not extra DDR round trips; expect the same ratio on the board.
- **`FCLK_MHZ` becomes a real variable in stage C.** Sweep 10/25/50; training must converge at each and `heartbeat_app`'s calibration line must agree with the PS wall clock at each (BRINGUP.md §7).
- **Two images, still.** `CONFIG=asic` uses the `baremetal_linux` image and DTS, exactly as in simulation. Nothing in `testcode/linux` changes.

---

## 4. Order of work

1. ~~`amoeba_link_slave.sv` + `tb_link_slave.sv`, `make test-link` green.~~ Done.
2. ~~`amoeba_asic_wrapper.sv`, `amoeba_pynq_top.sv` `DUT_ASIC` generate, `amoeba_ctl` registers, `regs.py`, `check-regs` green, `lint DUT=asic CONFIG=asic` green.~~ Done, plus `make test-top DUT=asic CONFIG=asic` 7/7.
3. ~~Stage A bitstream: `make bitstream DUT=asic CONFIG=asic MEM_BACKEND=BRAM`; `deploy`; `heartbeat_app`; `run_regression.py`.~~ Done, 7/7 on the board.
4. ~~Stage B bitstream: `MEM_BACKEND=AXI`; `run_linux.py`.~~ Done: 326.5 M cycles vs 155.3 M, 2.10× — see §0 for why the simulation's +10 % did not transfer.
5. Stage C: pins, ribbon, `FCLK_MHZ` sweep.
6. Stage D: `fpga/vcu118/` per `docs/impl_plan_onchip_periph.md` §1.6.
