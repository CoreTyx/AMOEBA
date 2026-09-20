# Implementation Plan — On-Chip PLIC and UART (area upper bound)

**Rev 0.4 · 2026-09-15 · Config A in `docs/top_level_plan.md` §2 · PRIMARY CONFIG · implementation in progress on `feature/top_level`**

On-chip: `wallypipelinedcore`, I$/D$, CLINT, PLIC, UART 16550, link bridge,
pad ring. Off-chip (FPGA): memory only. External interrupts enter as
`irq[1:0]` into PLIC source IDs 3 and 6. **42 of 52 pads** (off-chip list +
`uart_tx`, `uart_rx`; `irq[1:0]` replaces `meip`/`seip`).
Config: `pkg/config_asic.vh`, `CONFIG=asic`, `PERIPH_ONCHIP=1`.

Items marked ◆ are identical to the off-chip plan; build them once. §0 of
that plan (merge, config, `CONFIG=asic`, bpred fix) applies here unchanged.

## 0. Status

| Item | State |
|---|---|
| `pkg/amoeba_link_pkg.sv`, `hdl/amoeba_{uncore,soc,link_master,link_train,rst_sync,chip,top}.sv` | Written. `PERIPH_ONCHIP` knob in RTL; TB exercises `=1` only. |
| `hdl/rvfi_tap.sv` + `rv64_core_wrapper.sv` refactor (Phase 0) | Done; wrapper instantiates the tap. |
| `hvl/common/amoeba_dut_wrap.sv`, `amoeba_link_model.sv` | Written. Wrapper is port-compatible with `rv64_core_wrapper`, so `top_tb.svh` swaps one module name; `rvfi_reference.svh` untouched. Model drives `mem_itf` directly (decision: sim speed over FPGA parity). No `amoeba_ext_bus` needed for this config. `+LINK_TRACE` prints transactions; `+LINK_GAPS`/`+LINK_SEED` randomise `ready`/`rvalid`. |
| `sim/Makefile` | `DUT=legacy\|amoeba`, `LINK_ARGS`; build dirs keyed on DUT. Pruned configs skip `tc_branch_prediction` (`rdcycle`, no ZICNTR) and `tc_zbkb_and_smc` (no B/K) — both hang on the legacy DUT too. |
| `synth/`, `lint/` | `DESIGN_TOP ?= amoeba_top`; source list = `hdl/*.sv` + `hdl/core/**` (was triplicated); `constraints.sdc` rewritten with PLACEHOLDER I/O numbers. Not yet run (EWS only). |
| Tier 0 — legacy DUT, `CONFIG=asic` | **ISA 4/4, FreeRTOS 7/7, Linux boots** at 275 M cycles, IPC 0.266 (with the `rvfi_tap` refactor in place). |
| Tier 2 — amoeba DUT over the link, `CONFIG=asic` | **ISA 4/4, FreeRTOS 7/7, Linux boots to `AMOEBA_LINUX_BOOT_OK`** at 303 M cycles, IPC 0.240 — **+10 % cycles vs. the legacy path** (which itself pays ~5 cycles per beat through `ahb_to_memitf`); 4.19 M link transactions, 0.95 M pipelined accepts, no protocol-check errors. `make link_abort DUT=amoeba CONFIG=asic` green: 909 injected mid-burst aborts drained, every line re-requested and delivered. Gap sweep (`+LINK_GAPS`, seeds 1–3, `+LINK_FORCE_ABORT=5`) in progress. |
| Abort path — finding | This core never abandons a burst on the bus by itself: a flush cause present when the fetch stalls resolves in the first stall cycle, before the address phase reaches the bridge, and `CommittedF` holds interrupts off during a fill. The D-cache bus FSM has `Flush` tied low. So the drain path is proven by injection (`+LINK_FORCE_ABORT=n` forces the I-cache bus FSM's `Flush` for one cycle mid-burst; the cache FSM re-requests), not by workload. The PYNQ-observed abort should be re-examined with this in mind. |
| Bugs found by the first run | (1) accept on `HTRANS[1]` took SEQ beats as new requests; (2) combinational `HREADY→HTRANS→HREADYOUT` loop, fixed with a registered `HTRANS`; (3) last write word not registered; (4) an address phase completing during turnaround was dropped — single pending slot added. |
| Next | Legacy Linux baseline for the IPC delta (running); `link_irq` directed test; `USE_SRAM=1` regression; synth + lint on EWS (`DESIGN_TOP=amoeba_top`, `CONFIG=asic`); CI matrix rows; FPGA `link_slave`. |

---

## 1. File-by-file

### 1.1 Config and package

| File | Change |
|---|---|
| `pkg/config_asic.vh` ◆ | Done, same file. Under `PERIPH_ONCHIP=1` the PLIC/UART decodes feed on-die instances. `PLIC_GPIO_ID=3`, `PLIC_SPI_ID=6` become the two external IRQ IDs. |
| `pkg/amoeba_link_pkg.sv` ◆ | Same; `PERIPH_ONCHIP=1`. |
| `testcode/linux/dts/amoeba_baremetal_linux.dts` | **Changes** under this config if interrupt-driven UART is wanted: restore the plic node and the UART `interrupts` property (both were removed for `PLIC_SUPPORTED=0`). Polled UART with no DTS change also works. |

### 1.2 SoC

| File | Change |
|---|---|
| `hdl/amoeba_uncore.sv` (same file, `PERIPH_ONCHIP=1` branch) | `ahbapbbridge #(P, 3)` with `HSEL({HSELUART, HSELPLIC, HSELCLINT})`; `clint_apb`; `plic_apb` (`.UARTIntr`, `.GPIOIntr(irq_i[0])`, `.SPIIntr(irq_i[1])`, `.SDCIntr(0)`); `uart_apb` (`.SIN(UARTSin)`, `.SOUT(UARTSout)`, `.INTR(UARTIntr)`). `HSELEXT` passes through unchanged. `MExtInt`/`SExtInt` from `plic_apb`. |
| `hdl/amoeba_soc.sv` (same file) | Ports add `UARTSin`, `UARTSout`, `irq_i[1:0]`; no `meip`/`seip`. |

### 1.3 Link and top

| File | Change |
|---|---|
| `hdl/amoeba_link_master.sv` ◆, `amoeba_link_train.sv` ◆, `amoeba_rst_sync.sv` ◆ | Identical. `rst_sync` syncs `irq[1:0]` and `uart_rx`. PLIC/UART traffic never reaches the link; the only single-beat traffic is CBO/AMO corner cases. |
| `hdl/amoeba_chip.sv` ◆, `hdl/amoeba_top.sv` ◆ | Identical structure; +`uart_tx` output cell, +`uart_rx` input cell with pull-up, from the spare 12. |
| `hdl/rv64_core_wrapper.sv` ◆ | Phase 0 as off-chip. |

### 1.4 Testbench

| File | Change |
|---|---|
| `rvfi_tap.sv` ◆, `amoeba_link_model.sv` ◆ | Identical. |
| `amoeba_ext_bus.sv` | Memory-only branch: AHB → `ahb_to_memitf` → `mem_itf`. Drives nothing back. |
| `top_tb.svh` | Same DUT select. Linux UART tap → `dut.chip.soc.uncore.uart.uartPC.*`. `irq[1:0]` tied 0; `link_irq` drives them from a TB task. `uart_rx` tied 1. |
| `tests/link_abort/*.S` ◆ | Identical. |
| `tests/link_irq/*.S` | Asserts `irq[0]`/`irq[1]`; on-chip claim/complete; checks IDs 3 and 6. |

### 1.5 Build and CI

| File | Change |
|---|---|
| `sim/Makefile` ◆ | As off-chip, plus `PERIPH_ONCHIP=0/1` → `+define+AMOEBA_PERIPH_ONCHIP`; `-Mdir` keyed on it. |
| `synth/`, `lint/` ◆ | As off-chip. `report_area -hierarchy` for `uncore` under `PERIPH_ONCHIP=1` minus `=0` is the on-chip peripheral cost (expect ~10–15 k GE, dominated by the 16550 FIFOs). |
| `.github/workflows/*.yml` | `periph: [onchip, offchip]` on the `amoeba` rows. |

### 1.6 FPGA (`fpga/`)

**The console changes shape under this config, and that is the main
friction.** Today's FPGA console is `amoeba_bus_mon` snooping UART THR writes
on the AHB (`amoeba_pynq_top.sv` header: "NO SERIAL PINS"). With the 16550 on
the die those writes never leave the chip, so the snoop sees nothing. The
console must come off the physical `uart_tx` pad, and the 16550's divisor is
programmed by the guest against the core clock, so the receiver needs the
right baud per bring-up frequency — exactly the problem the PYNQ design chose
to avoid. `tohost` still works: it is a memory store and leaves the chip.

| File | Change |
|---|---|
| `fpga/pynq/rtl/amoeba_link_slave.sv` ◆ new | Identical. |
| `fpga/pynq/rtl/amoeba_ext_bus.sv` | Memory-only branch. |
| `fpga/pynq/rtl/amoeba_soc_wrapper.sv` | Shim around `amoeba_top` + `link_slave` as off-chip; `uart_tx`/`uart_rx` pass through. |
| `fpga/pynq/rtl/amoeba_uart_rx.sv` new | PL-side 16550-compatible receiver feeding `amoeba_ctl`'s console FIFO in place of the snoop. Either fixed divisor from `FCLK_MHZ`, or the deserializer the `amoeba_pynq_top.sv` header sketches: `amoeba_bus_mon` can no longer capture DLL/DLM writes (they are on-die), so the divisor must be a host-programmed register. |
| `fpga/pynq/rtl/amoeba_bus_mon.sv` | Console path disabled; `tohost` and cycle counter unchanged. |
| `fpga/pynq/rtl/amoeba_ctl.sv` | `irq[1:0]` drive register (default 0) for software-triggered IRQ tests; UART divisor register; `sw/check_regs.py` re-run. |
| `fpga/pynq/tcl/bd_pynq.tcl`, `constraints/pynq-z2.xdc` | `uart_tx`/`uart_rx` to a PMOD or the board USB-UART. |
| `fpga/vcu118/` new | As off-chip, plus the UART pins to the board's USB-UART bridge. |

---

## 2. Testing tiers

Same tiers as the off-chip plan (tier 0 — `CONFIG=asic` on the legacy DUT —
is identical and shared). Differences:

| Tier | Difference under on-chip |
|---|---|
| 1 SoC, no link | `amoeba_ext_bus` is memory-only; the console tap is inside the DUT. Closest to today's CI: the same PLIC/UART behind the same decoder. |
| 2 Link in sim | PLIC/UART never touch the link; add a directed uncached single-beat test (CBO) so the single-beat path is still covered. |
| 3 Top + training | `uart_tx`/`uart_rx` get I/O constraints; document the guest divisor vs. core clock at the tapeout frequency. |
| 4a/4b FPGA | Console via `amoeba_uart_rx` at a host-programmed divisor, not the snoop; `heartbeat_app`'s clock-calibration line (BRINGUP.md §7) is the first check. |
| Area | `report_area -hierarchy` delta = on-chip peripheral cost. |

---

## 3. Friction notes

- Least friction in **simulation**: no slave-side peripheral model, interrupts never cross the DUT boundary, the Linux tap is a path change.
- Most friction on the **FPGA and bench**: the console snoop that the whole PYNQ tooling (`run_freertos.py`, `run_linux.py`, `psmon.py`) reads from stops working; a physical-UART receiver with per-clock divisor handling replaces it. BRINGUP.md §7 documents this exact class of bug.
- Two more pads; the peripheral logic needs scan; the PLIC is unobservable on silicon except through its own registers.
