# Work log: link pads, 16 tristate → 8 in + 8 out

Branch `area_io_opt`. Started 2026-11-05.

## Goal

Replace the 16-lane bidirectional link bus `io[15:0]` (sixteen `io_tri` pads, each
with its own tristate `t`, plus a `dir` pin and turnaround states) with eight
dedicated `io_in` pads and eight dedicated `io_out` pads. Nothing on the link
changes direction any more, so the direction-control logic and the `dir` pad are
removed.

## Decisions

| Item | Decision |
|---|---|
| Extra I/O removed | `dir` pad, per-lane `io_oe` / `io_t`, `LM_RD_TA` / `LM_RD_TA2`, `TA` constant |
| Top-level port names | `io_in[7:0]` (FPGA→ASIC), `io_out[7:0]` (ASIC→FPGA). These are also the PDK pad-cell module names; SV keeps modules and ports apart, so this is legal |
| Width | `LINK_W = 8` per direction |
| Header | `req=1` for `ADDR_WORDS = 4` cycles, `io_out` = A[31:24], A[23:16], A[15:8], A[7:0] |
| Data | 64-bit beat = `WORDS_PER_BEAT = 8` bytes, LSB first. Write on `io_out`; read on `io_in`, qualified by `rvalid` |
| Read start | The FPGA may drive the first read byte as soon as the header has been received. There is no turnaround |
| Scan | test mode: `io_in[7:0]` = scan_in[7:0], `io_out[7:0]` = scan_out[7:0]. There is no direction override any more |

## Steps

(updated as work lands)

### 1. RTL

| File | Change |
|---|---|
| `hdl/forte_link_pkg.sv` | `LINK_W` 16 → 8 (per direction); `ADDR_WORDS = 32/LINK_W = 4`; `WORDS_PER_BEAT = 8`; `TA` deleted. `link_st_t` is now `{LM_IDLE, LM_START, LM_HDR, LM_WDATA, LM_RD_DATA}` (3 bits, was 4 with 8 states); `link_slave_st_t` is now `{LS_IDLE, LS_HDR, LS_WDATA, LS_RD}`. Header comment rewritten for the two-bus protocol. |
| `hdl/forte_link_phy.sv` | Ports `io_o`/`io_i` only; `io_oe` and `dir` removed. LM_HDR0/LM_HDR1 collapse into one `LM_HDR` with a 2-bit header counter (byte select, no shift register). `LM_RD_TA`, `LM_RD_TA2`, `ta_cnt` and `TA_W` removed: a read goes from the last header byte straight to `LM_RD_DATA` and back to `LM_IDLE` on the last byte. Word/beat indexing is derived from `WORDS_PER_BEAT`, not hardcoded `[1:0]`/`3`. `beat_r` is 56 bits (was 48). The read-beat-count assertion moved from the end of TA2 to the last read word. |
| `hdl/forte_chip.sv` | Ports `io_o`/`io_i` (8 bits each); `io_oe` and `dir` removed. Scan mux is now just `io_o = test_mode_dft ? scan_q : lm_io_o`, with `scan_q <= io_i`. The test-mode pad-direction override is gone. |
| `hdl/forte_top.sv` | Ports `io_in[7:0]` (input) and `io_out[7:0]` (output) replace `inout io[15:0]`; `dir` port removed. `io_t` and the `io_tri` cells are gone. `g_link` instantiates 8 `io_in` + 8 `io_out` cells. 31 signal pads (was 32). |
| `hdl/forte_link_core.sv` | Unchanged; it only ever dealt in flits and beats. |

### 2. Testbenches

| File | Change |
|---|---|
| `hvl/common/forte_link_model.sv` | Slave behind the ISA/baremetal/FreeRTOS/Linux regressions. Ports `io_out` (from the chip) and `io_in` (to the chip); no `dir`. Header assembled over 4 bytes. Read data streams right after the header, with no TA wait; the first `LS_RD` cycle is held off while `rd_start` clears the line buffer. Dir/TA checks are replaced by "req fell after N header words". |
| `hvl/common/forte_dut_wrap.sv` | New port wiring. `+LINK_PINS` prints `io_out`/`io_in`/`req`/`wr`/`rvalid` instead of the dir/ownership column. Probes use `LM_RD_DATA` instead of the TA states. |
| `hvl/cdc/forte_cdc_tb.sv` | Tristate loop removed; chip `io_o`/`io_i` wired straight to the model. |
| `hvl/cdc/run.sh` | Unchanged after the rebase onto `main`. Commit `1c0c0d9` had moved `prim_flop_2sync.sv`/`prim_fifo_async.sv` from `third_party/opentitan/` to `hdl/` and this script still pointed at the old paths, so `make cdc` could not build at `517f7f2`; this change fixed it there, and `main` made the identical fix in `7396afa`. |
| `hvl/pin/pin_link_agent.sv` | Two buses; A_RD_TA/A_RD_REL, contention, dir and TA checks removed. New check: `io_out` is never X/Z, even outside a transaction. `+FPGA_IO_IDLE=0|x|z` (default `0`) sets what `io_in` carries between read words. |
| `hvl/pin/pin_tb.sv` | New port wiring. |
| `hvl/pin/selftest/pin_selftest_tb.sv` | Chip-side BFM rewritten for two buses. Violations that only existed because of `dir` are re-targeted: 1 = req held into read data, 3 = req held into write data, 8 = X on idle `io_out` (4-state), 13 = watchdog via a read the FPGA never answers. 2 = short header (2 of 4 words). |
| `hvl/pin/models/pad_behav.sv` | `io_tri` stand-in removed. |
| `hvl/pin/pin.sh`, `README.md`, `vm_paths.example.sh`, `selftest/run.sh` | Port list, checks, knob docs. |

### 3. Synthesis, constraints, docs

| File | Change |
|---|---|
| `synth/timing/constraints_65.sdc`, `synth/constraints.sdc` | `link_in = {io_in[*] ready rvalid}`, `link_out = {io_out[*] req wr}`. Also dropped the stale `burst` port from `constraints.sdc`. |
| `synth/timing/probes.tcl`, `synth/timing/groups.tcl` | Same port rename in the link probes and the `link_io` path group. |
| `synth/dft.tcl` | **Untracked, not committed.** ScanDataOut `io_o[8]` → `io_o[0]`; comments updated. |
| `synth/timing/tech.cfg`, `gen_blackbox_libs.py`, `timing/README.md` | Untouched. They describe the pad kit, which still has `io_tri`, and `tech.cfg` carries uncommitted user edits. |
| `docs/top_level_plan.md` | Intro, §1, §3 pad list (pad 30 freed), §4 protocol + "why two one-way buses" + new cycle table, §5/§6/§10/§11 references. |
| `docs/impl_plan_link_clocking.md` | §11 scan mapping updated; the dir/io_oe items in §11.2 are marked historical. |
| `docs/postsynth_vm_runbook.md`, `bin/vcd_first_x.py`, `sim/Makefile` | Wording only. |

Left alone on purpose: `docs/impl_plan_offchip_periph.md` and `docs/impl_plan_onchip_periph.md`. They are historical implementation plans, already out of date in other ways (`forte_link_train`, `burst`), and they describe what was built at the time.

## Link cost, 128-bit line (BEATS = 2)

| Transaction | Before (16-bit bidir, TA = 2) | After (8 in + 8 out) |
|---|---|---|
| Line read | 2 hdr + 2·TA + 8 words = 14 cycles | 4 hdr + 16 bytes = 20 cycles |
| Line write | 2 hdr + 8 words = 10 cycles | 4 hdr + 16 bytes = 20 cycles |
| Signal pads | 32 | 31 |

Observed on the wire (`tc_alu_and_shift`, `+LINK_PINS`): the reset fetch header is `80 00 00 00` over 4 `req` cycles, and 16 read bytes arrive on `io_in` with `rvalid`, with no turnaround gap.

## Test runs

Logs are in `sim/verilator/io_split/` (gitignored).

| Run | Command | Result |
|---|---|---|
| Verilator build, forte DUT | `make verilator/build_no_spike_forte/Vtop_tb DUT=forte` (`-Wall`, warnings fatal) | First build: 2 WIDTHEXPAND warnings (phy header index, dut_wrap trace compare). Fixed with an explicit `hsel` and a cast. Clean after that |
| Single ISA test + pin trace | `run_verilator_top_tb_no_spike DUT=forte PROG=tc_alu_and_shift.c LINK_ARGS=+LINK_PINS=60` | PASS; `[FLIT] cmd_push=132 cmd_pop=132 beat_push=260 beat_pop=260` |
| Pin bench suite, Verilator | `SIM=verilator hvl/pin/selftest/run.sh` | **25 passed, 0 failed, 4 skipped** (violations 6/8/11/12 need 4-state) |
| Pin bench suite, VCS (4-state) | `SIM=vcs hvl/pin/selftest/run.sh`, with an unfilled `vm_paths.sh` copy so the behavioural pad/SRAM models are used | **30 passed, 0 failed, 1 skipped** (SRAM sign-off models exist only on the VM). All 13 violations are caught, including the X/Z ones; the X-stress smoke run (`+FPGA_IO_IDLE=x +FPGA_X_IN_RESET`) passes; rtl and rtl_sva traces match cycle for cycle |
| CDC, two clocks | `make cdc` | PASS: 24418 transactions, flits balanced |
| CDC sweep, 6 ratios 0.68–1.37 | `make cdc_sweep` | PASS at every ratio |
| ISA regression, forte DUT | `make isa_regression DUT=forte TIMEOUT=4000000` | **16/16 passed** |
| Link abort torture | `make link_abort DUT=forte` | **PASS**: 33134 transactions, 8721 aborted and drained, 2066 pipelined |
| ISA regression, random `ready`/`rvalid` gaps | `make isa_regression DUT=forte TIMEOUT=8000000 LINK_ARGS="+LINK_GAPS=1 +LINK_SEED=7"` | **16/16 passed** |
| FreeRTOS regression, forte DUT | `make freertos_regression DUT=forte` | **5/5 passed** |
| Baremetal regression, forte DUT (Spike co-sim) | `make baremetal_regression DUT=forte` | **3/3 passed** |
| Linux boot, forte DUT (final gate) | `make linux_boot DUT=forte` (detached tmux, 4.3 h wall) | **PASS**: `AMOEBA_LINUX_BOOT_OK` at cycle 616,408,477. 10,846,597 link transactions (8,240,913 reads, 2,605,684 writes, 2,694,950 pipelined), 0 aborts, no protocol-check errors or assertions |
| Legacy DUT spot check (CI's build also compiles `hdl/forte_*`) | `make run_verilator_top_tb_no_spike PROG=tc_mul_div.c` | builds warning-clean (`-Wall`), PASS |
| SpyGlass lint, forte_top | `make -C lint lint DESIGN_TOP=forte_top` | 0 fatals, 0 errors, 15 warnings, none in a changed file: 8 × SGDC_waive24 (lint.awl names `rv64_core_wrapper`, the default top), 6 × SYNTH_5064/5143 in `prim_fifo_async.sv`, 1 × AsyncResetOtherUse in the reset synchroniser. Not comparable with HEAD, where forte_top lint could not build (next section) |

## Pre-existing breakage found along the way

Not caused by this change, and found because the gates were run:

1. **`1c0c0d9` moved the OpenTitan prims** from `third_party/opentitan/` to `hdl/`, but `hvl/cdc/run.sh`, `synth/Makefile` and `lint/Makefile` (forte_top branch) still named the old paths. So at `517f7f2`, `make cdc`, `make -C synth timing` and `make -C lint lint DESIGN_TOP=forte_top` all failed at analysis. **Fixed in this change**, because the gates need them; `hvl/cdc/run.sh` was also fixed on `main` (`7396afa`), so after the rebase this change carries only the `synth/Makefile` and `lint/Makefile` fixes.
2. **Calibrated timing flow black boxes are stale** (`synth/timing/gen_blackbox_libs.py`): `rf_sp_64_53`/`rf_sp_64_137` are declared 53/137 bits wide, but the wrappers drive 56/140 (`{3'd0, D}`). The cells also have no `RETN`/`EMA` pins, which the wrappers have driven since `11ded8a`. `make -C synth timing` fails at link (LINK-3, LINK-1). **Not fixed in the repo.** The right macro widths and the EMA width are your call. For the before/after area comparison, both scratch worktrees got the same local patch (56/140 bits, `RETN` + 3-bit `EMA` pins).

## Performance, same programs before and after (forte DUT, Verilator, 2.5 ns clock)

Before = HEAD `517f7f2` in a scratch worktree; after = this change. Both run `run_verilator_top_tb_no_spike DUT=forte`. Every program PASSES on both, with identical link transaction counts.

| Program | Before (cycles) | After (cycles) | Δ | Link transactions | Character |
|---|---|---|---|---|---|
| `tc_alu_and_shift` | 254,600 | 254,826 | +0.09 % | 131 | UART-bound |
| `tc_mul_div` | 277,469 | 277,697 | +0.08 % | 133 | UART-bound |
| `sorting_algo` | 47,804 | 48,440 | +1.33 % | 70 | compute, warm caches |
| `basic_arith` | 1,134 | 1,329 | +17.20 % | 21 | tiny, cold-cache dominated |

Read: the narrower link costs about 6 cycles per line read and 10 per line write (§ link cost above). That is invisible once the caches are warm (≤ 1.3 % here) and worst for cold-start, miss-dominated code (+17 % on an 1100-cycle program). The Linux boot is the realistic worst case. It took 616.4 M cycles. No forte-DUT boot exists at HEAD to compare against (the 353.9 M boot in older notes is the legacy DUT, which never touches the link), and a baseline boot is another ~4 h. Upper bound from the transaction counts: 8.24 M reads × 6 + 2.61 M writes × 10 ≈ 75.5 M extra cycles if none of it overlapped, so the boot is at most ~14 % slower than before (baseline ≥ ~541 M). Pipelined accepts hide part of that, so the real figure is lower.

## Synthesis, before and after (`make -C synth timing`, FreePDK45 calibrated to 65 nm, 2.6 ns target)

Both runs used the same scripts (your uncommitted `tech.cfg`, PERIOD 2.6) and the same scratch black-box patch from "Pre-existing breakage" item 2. Key reports are copied to `sim/verilator/io_split/synth_{base,new}/` (gitignored).

| Metric | Before | After | Δ |
|---|---|---|---|
| Link phy flops (`chip/phy/*`, sequential cells) | 216 (1115.3 µm²) | 204 (1072.0 µm²) | **−12 flops, −43.4 µm² (−3.9 %)** |
| forte_top local area (chip glue + phy + status + scan mux, flattened) | 9357.3 µm² | 9264.0 µm² | −93.4 µm² (−1.0 %) |
| Sequential cells, whole chip | 15822 | 15810 | −12 |
| Total cell area, whole chip | 194439 µm² | 194819 µm² | +380 µm² (+0.2 %): compile noise, see below |
| `link_io` worst slack | −0.202 ns | −0.203 ns | unchanged |
| Link pad cells | 16 `io_tri` + 1 `io_out` (dir) | 8 `io_in` + 8 `io_out` | −1 pad, no tristate cells |

How to read it:
- The **link logic did shrink**. The phy lost 12 flops net: io capture 2×16 → 2×8, io_o 16 → 8, ta_cnt, io_oe, dir and one state bit gone, against beat_r +8, hcnt +2 and wcnt +1. Its combinational logic lost the TA states and the output-enable fan-out. The flattened top-level glue that holds all of this is 93 µm² smaller.
- The **whole-chip total is noise**, not a cost. `compile_ultra` re-optimises the unchanged core differently on each run: the `mul` group went from −0.367 ns to −0.072 ns and `dcache` from −0.086 to 0.000 with no RTL change there. ±0.2 % of 194k µm² (±400 µm²) swamps a ~100 µm² saving. The saving is real but small.
- The biggest savings are not in this report. Pad cells are black boxes (area 0) here. In silicon, 16 bidirectional `io_tri` cells become 8 input + 8 output cells, which are normally smaller and need no per-pad enable routing, and one pad site is freed.
- `link_io` (−0.20 ns) is a one-gate path dominated by the pad model and the I/O delay constraints, so it was never going to move with this change.
