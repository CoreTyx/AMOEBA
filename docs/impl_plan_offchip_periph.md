# Implementation Plan — Off-Chip PLIC and UART (primary tapeout config)

**Rev 0.3 · 2026-09-15 · Config B in `docs/top_level_plan.md` §2 · post-merge of `fpga/linux_boot`**

On-chip: `wallypipelinedcore`, I$/D$, CLINT, link bridge, pad ring.
Off-chip (FPGA): memory, UART, PLIC (optional), everything else. External
interrupts enter as `meip`/`seip` pads. **40 of 52 pads.**
Config: `pkg/config_asic.vh`, `CONFIG=asic`, `PERIPH_ONCHIP=0`.

This is the partition `fpga/asic/BRINGUP.md` settles on (core + CLINT + APB
bridge + partial decode on the die; UART and PLIC "addressed over the same bus
as memory, so they cost no pins, and stay editable in the FPGA").

Items marked ◆ are identical in the on-chip plan; build them once. The two
configs differ by one parameter, `PERIPH_ONCHIP`, so both come from one tree.

---

## 0. Already done on `feature/top_level`

| Item | State |
|---|---|
| Merge of `fpga/linux_boot` | Done (`3ec5402`). Brings `pkg/config_*.vh`, `amoeba_config_select.vh`, `CONFIG=` in `sim/`, `synth/`, `fpga/pynq/`, `testcode/linux/` Makefiles, the PYNQ flow, `fpga/asic/BRINGUP.md`. |
| `pkg/config_asic.vh` | Done. `config_baremetal_linux.vh` + `PLIC_SUPPORTED=1` (decode only), `USE_SRAM` under `AMOEBA_USE_SRAM`, `GPIO=0` firm. |
| `CONFIG=asic` | Done in all four Makefiles. `synth` adds `AMOEBA_USE_SRAM`; `testcode/linux` reuses the `baremetal_linux` image and DTS. |
| `hdl/core/ifu/bpred/bpred.sv` | Fixed: `BPDirWrongM` undriven when `ZIHPM_SUPPORTED=0`. Verilator `-Wall` made every pruned config unbuildable in sim; only Vivado had ever elaborated them. |

---

## 1. File-by-file

### 1.1 Config and package

| File | Change |
|---|---|
| `pkg/config_asic.vh` ◆ | Done. Open item in the header: `*_WAYSIZEINBYTES` 2048 vs 4096 (BRINGUP.md §3 and the measured 2.57× boot say 4096; area says decide after macros). |
| `pkg/amoeba_link_pkg.sv` ◆ new | `LINK_W=16`, `TA=2`, `WORDS_PER_BEAT=4`, `WORDS_PER_LINE=32`, `PERIPH_ONCHIP`; `link_addr_pack(HADDR[31:0], HSIZE[1:0])` → two words, size in bits 30:29 of the high word; `link_size_to_mask(size, offset)`. One source of truth for the bridge, the TB model and the FPGA slave. |

### 1.2 SoC (new files under `hdl/`; `hdl/core/` gets only the bpred fix)

| File | Change |
|---|---|
| `hdl/amoeba_uncore.sv` new, from `hdl/core/uncore/uncore.sv` | Keep `adrdecs`, HSEL unswizzle, `ahbapbbridge #(P, 1)` with `HSEL({HSELCLINT})`, `clint_apb`, the `HRDATA`/`HRESP`/`HREADY` muxes, `hseldelayreg`. **`HSELEXT_o = HSELEXT \| HSELPLIC \| HSELUART`** and the same for the delayed copy, so peripheral accesses leave over the link with the PMA still marking them uncached and non-idempotent. Remove `plic`, `uart`, `gpio`, `spi`, `sdc`, `ram`, `bootrom` blocks. Inputs `MExtIntIn`, `SExtIntIn` → `MExtInt`, `SExtInt`. `if (PERIPH_ONCHIP)` keeps the on-die UART/PLIC branch for the other plan. |
| `hdl/amoeba_soc.sv` new, from `hdl/core/wally/wallypipelinedsoc.sv` | `wallypipelinedcore #(P)` + `amoeba_uncore`. Ports: `clk`, `reset_ext`, `reset`, `ExternalStall`, the AHB ext port, `meip`, `seip`. Includes `amoeba_config_select.vh` like `rv64_core_wrapper.sv` now does. |

### 1.3 Link and top

| File | Change |
|---|---|
| `hdl/amoeba_link_master.sv` ◆ new | AHB-Lite slave on the ext port → 16-bit link. Starts only after `ready=1`; `req` for two cycles with `HADDR[31:16]`, `HADDR[15:0]` straight through (`HREADYEXT=0` holds the AHB address phase — no latch); `wr=HWRITE`, `burst=(HBURST==INCR8)` held. Write: `HWDATA` as 4 words LSW-first, `HREADYEXT` on the 4th. Read: `dir↓`, TA, 4×`rvalid` words → beat register → `HREADYEXT`; after the last word TA, `dir↑`. `HTRANS` masked once started; word counter always completes (abort invariant). `HRESPEXT=0` — no error path (BRINGUP.md §2). Inbound pins captured on negedge, re-registered on posedge. `ifndef SYNTHESIS` SVA: `HADDR[55:32]==0`, `HADDR[30:29]==0`; never IDLE mid-transfer; TA on every `dir` edge. |
| `hdl/amoeba_link_train.sv` ◆ new | LFSR on `io[15:0]` with `dir=1` for 2^12 cycles; `dir=0`; expect echo; match → `core_rst_n=1`, `status=1`; N failures → hold reset, `status=0`. Then `status` = retire heartbeat. |
| `hdl/amoeba_rst_sync.sv` ◆ new | Async assert / 2-FF release for `rst_n`; 2-FF sync on `meip`, `seip`. |
| `hdl/amoeba_chip.sv` ◆ new | Pad-less top: `rst_sync`, `link_train`, `amoeba_soc`, `link_master`, scan mux (`test_mode`: `io_i[7:0]`→`scan_in`, `scan_out`→`io_o[15:8]`; 2 chains, CSRs stitched first per BRINGUP.md §2). DFT and gate-level boundary. |
| `hdl/amoeba_top.sv` ◆ new | Pads. Sim/FPGA: `assign io = io_oe ? io_o : 'z`. Synth: `ifdef AMOEBA_PADLIB` instantiates the 65 nm IO cells. `DESIGN_TOP`. |
| `hdl/rv64_core_wrapper.sv` ◆ | Phase 0: RVFI taps move to `hvl/common/rvfi_tap.sv`; this stays as the legacy DUT and CI reference. |

### 1.4 Testbench (`hvl/common/`)

| File | Change |
|---|---|
| `rvfi_tap.sv` ◆ new | The `monitor_*` taps from `rv64_core_wrapper.sv:222-498` as a module `bind`-attached to `wallypipelinedcore`. Serves both DUTs. |
| `amoeba_ext_bus.sv` new | "The FPGA" in simulation: AHB-Lite slave-side decoder routing PLIC/UART regions to CVW `plic_apb` + `uart_apb` via `ahbapbbridge #(P,2)` and everything else to `ahb_to_memitf` → `mem_itf`. Outputs `meip`, `seip`; exposes `uart.uartPC` for the console tap. Used with and without the link. This is the executable spec of the FPGA slave's downstream side. |
| `amoeba_link_model.sv` ◆ new | Link slave BFM: pins → AHB-Lite master into `amoeba_ext_bus`. `ready` = may-start; ≥32-word write buffer; honours TA; plusarg-seeded `ready` withholding and `rvalid` gaps. Checks: never drives while `dir=1` or inside TA; never samples X while `dir=1`; one link transaction per AHB burst (vs. a bound monitor on the DUT's ext port); word counts. |
| `top_tb.svh` | DUT select: `ECE411_DUT_AMOEBA` → `amoeba_top` + `link_model` + `ext_bus`; `ECE411_LINK_BYPASS` → `amoeba_soc` straight into `ext_bus`; else legacy. `monitor_*` from `rvfi_tap_i`. Linux UART tap path → `ext_bus.uart.uartPC.*` (today `dut.soc.uncoregen.uncore.uartgen.uart.uartPC`, `top_tb.svh:156-165`). Misaligned refs → `rvfi_tap_i`. `TOHOST_ADDR` snoop on `mem_itf` unchanged. |
| `tests/link_abort/*.S` new | Mispredicted branches across line boundaries; `fence.i` storms; `mtimecmp` deltas of 1–8 during `tc_mem_stress`-style writebacks. Coverage: ≥1 transfer completed after the core went IDLE. |
| `tests/link_irq/*.S` new | `meip`/`seip` from the TB PLIC; claim/complete over the link; latency bound, no lost edge. |

### 1.5 Build and CI

| File | Change |
|---|---|
| `sim/Makefile` | `DUT ?= legacy` (`legacy` \| `amoeba` \| `amoeba_nolink`) alongside the existing `CONFIG`; per-DUT `-Mdir`s; `LINK_SEED`, `LINK_GAPS`. `check_ipc.sh` gains a per-test floor for `DUT=amoeba` vs `legacy`. |
| `synth/Makefile`, `lint/Makefile` | `DESIGN_TOP = amoeba_top`. **Fix the source list** (still wrong after the merge): `HDL_SRCS` = top-level `hdl/*.sv` + `hdl/core/**`; drop `third_party/cvw/src` and `hdl/cvw` — today every CVW module is analyzed three times and the synthesized copy is not the simulated one. `fpga/pynq/Makefile:85-96` already does it right; copy that. |
| `synth/synthesis.tcl` | `report_area -hierarchy` so `uncore`/`link`/`core` are separable — this is how the A-vs-B number is produced. |
| `synth/constraints.sdc` | Replace the class template: `create_clock clk`; `set_input_delay -min/-max` on link inputs (FPGA Tco + trace) and `set_output_delay` on link outputs, both vs. `clk`; negedge capture on inbound; `set_propagated_clock` post-CTS so the inbound hold path is checked against the real tree; `set_load`, `set_dont_touch` on pads; false paths on `test_mode`/`scan_en` in functional mode. |
| `.github/workflows/ci.yml`, `linux-boot.yml` | Matrix `dut: [legacy, amoeba_nolink, amoeba]` × `config: [full, asic]`. Today no workflow builds any pruned config in Verilator. |

### 1.6 FPGA (`fpga/`)

The PYNQ flow is the rehearsal; BRINGUP.md §6's rule is **keep the
AHB-facing structure identical** so `amoeba_ctl`, `amoeba_bus_mon`,
`amoeba_bus_probe`, `amoeba_trace`, `amoeba_retire` and `sw/amoeba/` carry
over. The link slave therefore reconstructs AHB-Lite, and the console stays
the `amoeba_bus_mon` snoop of UART writes on that bus — which works under this
partition precisely because the UART traffic leaves the chip.

| File | Change |
|---|---|
| `fpga/pynq/rtl/amoeba_link_slave.sv` new | Synthesizable port of `hvl/common/amoeba_link_model.sv` from `amoeba_link_pkg`: link pins → AHB-Lite master. IDELAY on inbound, ODELAY/MMCM phase on outbound, both set by the training sweep. Adds BRINGUP.md §2's out-of-window poison (`0xBAADC0DE_DEADBEEF`), out-of-window counter, and no-request watchdog. |
| `fpga/pynq/rtl/amoeba_ext_bus.sv` | The same file as the TB's, compiled into the fabric: UART (+ PLIC) at their current addresses + the memory path. `meip`/`seip` → DUT pads. |
| `fpga/pynq/rtl/amoeba_soc_wrapper.sv` | Becomes a thin shim that instantiates `amoeba_top` (Tier 4a: `io` tristate resolved in the fabric; Tier 4b: through FMC) and `amoeba_link_slave`, and presents the reconstructed AHB on the same ports it has today. `MEM_BRAM` backend (`amoeba_mem_bram` + `ahb_to_memitf`) and the AXI/DDR backend are untouched. |
| `fpga/pynq/rtl/amoeba_pynq_top.sv` | `dut` hierarchy for the commit-trace taps becomes `dut.chip.soc.core.*` (Tier 4a only; on silicon there is no trace). |
| `fpga/pynq/rtl/amoeba_ctl.sv` | Adds `status` readback, training-sweep control (IDELAY tap / MMCM phase, retry count), link watchdog status. Register map extended, `sw/check_regs.py` re-run. |
| `fpga/pynq/rtl/amoeba_bus_probe.sv` | Points at the link pins too (`dir`, `req`, `wr`, `burst`, `ready`, `rvalid`, `io`). |
| `fpga/pynq/tb/tb_link_slave.sv` new | `amoeba_link_model` driving `amoeba_link_slave` back-to-back through a loopback so both ends are checked against the same package. |
| `fpga/pynq/tcl/bd_pynq.tcl`, `constraints/pynq-z2.xdc` | Tier 4a: no pin changes. Tier 4b: link pins on PMOD/Arduino headers for a two-board or loopback-cable check of real turnaround. |
| `fpga/vcu118/` new | Same `rtl/`, new board: constraints (link + `status` in one HP/HR bank matching the pad-library I/O voltage), DDR4 via MIG behind an L2 (BRINGUP.md §3), and a host transport replacing the PS: JTAG-to-AXI for bring-up, XDMA later. `sw/amoeba/mmio.py` `Mmio` swaps per BRINGUP.md §6; the register map and `check_regs.py` stay. |
| `testcode/linux/dts/amoeba_baremetal_linux.dts` | **Unchanged** (no plic node, polled UART). Adding an FPGA PLIC later = add the node and the UART `interrupts` property; no silicon change. |

---

## 2. Testing tiers

Each tier is gated by the previous one being green. Tiers 4–5 map onto
BRINGUP.md §8 stages 2–7.

| Tier | DUT / config | What runs | Gate |
|---|---|---|---|
| **0 Config on legacy DUT** | `rv64_core_wrapper`, `CONFIG=asic` | ISA (no-Spike), FreeRTOS suite, `make linux_boot CONFIG=asic`. **Never run before on any pruned config in Verilator.** | All green — this proves `config_asic.vh` itself before any new RTL exists |
| **0b Refactor** | `legacy`, full + asic | `rvfi_tap` bound; synth/lint source lists fixed | Bit-identical RVFI stream and IPC vs. tier 0 |
| **1 SoC, no link** | `amoeba_nolink` = `amoeba_soc` → `amoeba_ext_bus` | Same suites; PLIC/UART now outside the DUT on the AHB side | All green; console via the moved tap; `report_area -hierarchy` of `amoeba_soc` |
| **2 Link in sim** | `amoeba` = `amoeba_top` → `link_model` → `ext_bus` | Suites with `LINK_GAPS=0`, then `=1` over 5 seeds; `link_abort`; `link_irq`; **Linux boot over the link** | All green; abort coverage nonzero; IPC ≥ floor; SVA clean |
| **3 Top + training** | `amoeba`, training on | Reset/training directed tests; lint; synth with real SDC, `AMOEBA_USE_SRAM` | Lint clean; timing met; **post-CTS inbound hold passes on negedge capture**; area report |
| **4a FPGA, single-chip** | `amoeba_top` RTL in the PYNQ/VCU118 fabric, `io` resolved internally, `link_slave` + `ext_bus` alongside | BRINGUP.md stages 2–5: `heartbeat_app`, `tc_*` regression on `MEM_BRAM=1`, then `tc_mem_stress`/`tc_mem_align` on DDR, then **Linux over the new protocol** (`sw/run_linux.py`) | Linux to `AMOEBA_LINUX_BOOT_OK` via the `bus_mon` console |
| **4b FPGA, real pads** | `amoeba_top` on one board/FMC, `link_slave` across a cable | Same, with real TA and turnaround; training converges over an MMCM phase sweep | Same |
| **5 Netlist** | gate-level `amoeba_top` + SDF | One FreeRTOS test through the link; `USE_SRAM=1` regression at RTL | Green |

---

## 3. Friction notes

- Every PLIC/UART access is a link transaction and the interrupt path crosses the die boundary twice; `link_irq` bounds latency rather than asserting the on-chip 3-cycle claim.
- `amoeba_ext_bus` is new slave-side decode, but it exists in Tier 1 before any link does, and it doubles as the FPGA slave's spec.
- The FPGA console (`amoeba_bus_mon` snoop) and `tohost` snoop work **unchanged**, because both the UART writes and the HTIF store leave the chip on the reconstructed AHB.
- No change to the Linux image, DTS, OpenSBI, or `sw/amoeba/regs.py`'s view of memory.
