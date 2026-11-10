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

## Follow-up: clock-crossing verification and the duplex question

Done after `1f6ed9d`, in scratch worktrees (`../AMOEBA-cdc-chk`, `../AMOEBA-cdcfix`, both deleted afterwards). None of the bench instrumentation below is committed: the RTL passed it, so it is recorded here rather than kept. Logs in `sim/verilator/io_split/cdc_chk/` and `.../cdcfix/` (gitignored).

### What was checked by reading the RTL

- The only core↔link crossings are the two `prim_fifo_async`s. Their pointers are Gray-coded, come straight from flops, and go through `prim_flop_2sync`. Data crosses only through FIFO storage.
- Each domain has its own reset synchroniser (`forte_rst_sync`), and each FIFO side is reset by its own domain.
- The occupancy `forte_link_phy` reads (`rdepth_o`) is computed from the synchronised write pointer, so it can only lag the true value. A write therefore cannot start with a beat missing.
- The only other cross-domain path is the test-mode `io_out` mux (`scan_q` is core clock, functional `io_o` is link clock), and `test_mode` is static during functional use.
- The 8+8 split added no crossing: `hcnt`, `beat_r`, `sub` are all link-domain. It removed one cross-domain mux (the test-mode `io_oe` override).

### Why the existing bench could not prove it

`make cdc` / `cdc_sweep` drift the two clocks through every phase, but an RTL flop always captures the value from before the edge, so a synchroniser never resolves anything marginal. The FIFO's own Gray assertions (`prim_assert.sv` `ASSERT`) compile to nothing under `ECE411_VERILATOR`. And the bench's flit balance counts transactions, not words.

### Stress matrix (scratch instrumentation)

A metastability model in `prim_flop_2sync` (a bit that changed < 0.5 ns before the edge resolves old or new at random), a word scoreboard and pointer checks on both FIFOs, and a `LINK_PHASE` knob. Run over 31 configurations: link 4× faster to 4× slower than core, 0.99 and 1.01 drift, 1:1 at fixed skews 0.05–9.95 ns (the silicon case), with and without random FPGA-side gaps. The slowest link clocks ran with a longer reset in the scratch bench (see the limitation below).

| Result | |
|---|---|
| 31 configurations | **all PASS**; every word through both FIFOs exactly once, in order, unchanged |
| 1:1 skew cases | every pointer change lands in the window (~73k samples per run, ~36k resolved to the old value) |
| Binary pointers swapped in by hand, `+CDC_META` | caught immediately (Gray check, or pointer going backwards) |
| Same, without `+CDC_META` | **passes the whole bench**: the committed bench alone cannot tell a Gray-safe crossing from a broken one |
| Gap | at exactly 2:1 and 4:1 slow-link no edge happened to land in the window; the 0.68 and 0.99 drift runs cover the slow-link side |

**Bench limitation found (left as is):** `hvl/cdc/forte_cdc_tb.sv` holds reset for a fixed 37.3 ns, and `masked_memory.sv` loads its image only on a clock edge in reset, on the link clock. With `LINK_HALF` above ~18 ns, or `LINK_PHASE` large enough that the first link edge comes after 37.3 ns, memory stays empty: the core fetches zeros, traps to 0 and the run times out, which looks like a link failure and is not one (shown with `LINK_HALF=40`). Every configured run (`make cdc`, `cdc_sweep`) has a link edge inside reset and is unaffected, so the bench is not changed; a slower or later link clock needs a longer reset first.

### Follow-up commit

`forte_link_phy`: every write-beat pop must find a beat (with this log update). Without it, a pop that found the FIFO empty would put the previous beat on the wire silently. Written as `if (...) $fatal` (see the open item below). Checked that it bites: a phy hacked to start a write before its beats are buffered fails on it at once.

Not committed: the metastability model, the FIFO checker, the `LINK_PHASE` knob and a `make cdc_meta` target were built as a permanent option and then dropped, since the RTL passed them. Their last run: 8/8 configurations, 323,881 synchroniser samples inside the window (every pointer change in the 1:1 cases); binary pointers swapped into the FIFO by hand failed within 0.4-1.2 µs with the model and passed without it.

Not in this set: the stale SRAM black boxes in `gen_blackbox_libs.py` ("Pre-existing breakage" item 2) are left to be fixed later.

### Open: Verilator never runs `assert`

No Verilator flow in the repo passes `--assert`, and Verilator drops immediate assertions without it. Every `assert (...) else $fatal` in the RTL has therefore never run in a Verilator regression: in `forte_link_phy` the beat-count, buffered-before-start and inbound-overflow checks, and in `forte_link_core` the HADDR/HBURST/HSIZE checks. Shown directly: the hacked phy above reached the state the buffered-before-start `assert` guards, and it stayed silent. They do run under VCS (`-assert svaext`, including the pin bench). The `if (...) $fatal` checks run everywhere. Adding `--assert` to the Verilator flows may surface failures in assertions that have never been exercised; that decision is left open.

## io_in / io_out independence (duplex): measured, not implemented

Both buses are in the link domain, so letting them run independently adds no clock crossing. The question is whether it pays.

**Traffic.** Wally is AHB-Lite: one transaction at a time, in order. A dirty miss does writeback then fill. The bridge completes the write on AHB once its beats are in the FIFO, so the fill is accepted about 2 cycles later and queues behind the write on `io_out`.

**Measured** (scratch counters in `forte_dut_wrap`, Linux boot, cycles 0–150M):

| | |
|---|---|
| Writes / fill reads queued behind a write | 1,347,567 / 1,347,343 (essentially every writeback) |
| Wait per queued read | **22.0 cycles** (2.0 with the write still waiting to be buffered, 20 with it on the pins) |
| Cycles spent waiting | 29.6M = **19.8 %** of the window (30.6 % in the write-heavy 60–70M stretch) |
| Writes queued behind a read | 0 (as AHB-Lite predicts) |
| `io_out` / `io_in` busy | 21.0 % / 23.5 %, never in the same cycle |

Projected over the full boot (2.6M writes): ~57M of 616M cycles, **≈ 9 %**. About 20 of the 22 cycles are recoverable, **≈ 8 %**: more than the narrower link cost.

**What it would take.** The read has to overtake the write on `io_out`. Done right:
- Keep one FIFO per direction across the crossing. Two async FIFOs do not preserve relative order, so a read could pass a write to the same line with no check able to see both.
- Reorder in the link domain, after the crossing. The phy pulls the whole write out at once (a second 64-bit beat register), sees the read command behind it, sends the read header first if the line differs, then the write header and data while the read data returns on `io_in`. Same line: keep the order. No read within ~4 cycles: send the write.
- Split the phy into an `io_out` FSM and an `io_in` FSM, at most one read outstanding. FIFO sizes and the `ready` guard band are unchanged.
- Cost: ~450 GE (~0.2 % of the chip). The FPGA slave must accept a new header while still returning read data; framing is otherwise unchanged.

**Decision (2026-11-06): not now.** Recorded here so it can be picked up later.

## Rebased onto `main` (2026-11-06)

`area_io_opt` was branched from `postsynth_verif` at `517f7f2`. That branch then moved on and was merged into `main` (PR #47, `c47f809`, 8 commits, including the one-array-per-cache SRAM rework). Both commits here were rebased onto `c47f809` so the branch merges cleanly.

- **Conflicts:** `hvl/pin/vm_paths.example.sh` (a comment; both edits kept) and `docs/top_level_plan.md`. On `main`, §3 had been rewritten as the admitted pinout for test, describing the 16-bit bus; its §3.1–3.4, §3.7 and §3.8 were rewritten for the 8+8 link in that structure, and §4's protocol block and "Why two one-way buses" were restored.
- **Auto-merged:** `hvl/pin/pin.sh`, `hvl/pin/selftest/run.sh`, `synth/timing/probes.tcl`. `hvl/cdc/run.sh` came out identical to `main`, which made the same prim-path fix in `7396afa`.
- **Unchanged by the rebase:** the link RTL, and the cache line length (so BEATS = 2). No commit on `main` references the old `io`/`dir` ports.

Gates on the rebased tree (`a13923d`; the final commits differ from it only in this log):

| Gate | Result |
|---|---|
| ISA regression, forte DUT | 16/16 |
| `make link_abort DUT=forte` | PASS, 8737 aborted and drained |
| ISA, random `ready`/`rvalid` gaps (`+LINK_GAPS=1 +LINK_SEED=7`) | 16/16 |
| FreeRTOS, forte DUT | 5/5 (first attempt could not build: the scratch worktree had no FreeRTOS-Kernel submodule; rerun with the same pinned commit, `ce221a8`) |
| Baremetal, forte DUT | 3/3 |
| Legacy DUT spot check (`tc_mul_div`) | PASS |
| `make cdc` / `make cdc_sweep` | PASS (24,449 transactions) / 6/6 ratios |
| Pin bench selftest, Verilator / VCS | 25 / 0 / 4 skipped; 30 / 0 / 1 skipped |
| SpyGlass lint, forte_top | 0 fatals, 0 errors, the same 15 warnings |
| Linux boot, forte DUT | **PASS**: `AMOEBA_LINUX_BOOT_OK` at cycle 677,978,564; 10,890,355 link transactions, flits balanced, 0 aborts |

The boot took 10 % more cycles than before the rebase (616.4M). The link code is identical in both, so the difference comes from what the rebase brought in from `main`; the cache rework is the likely cause, but it was not measured separately.
