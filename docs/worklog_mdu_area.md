# Work log: sequential multiplier (area for DFT)

Branch `mdu_area_opt`, from `main` at `1c44a28`.  Goal: cut chip area to make room
for DFT logic.  Multiplies and divides are a small share of the dynamic
instruction mix, so the MDU trades latency for area.

## What changed

**Multiplier (`hdl/core/mdu/mul.sv`)**: a sequential shift-add (radix-2)
multiplier replaces four 32x32 array multipliers, four 128-bit partial-product
registers and a four-input 128-bit adder.

- One (XLEN+2)-bit adder, used again every cycle.  Per bit that is a sum and a
  carry function of three inputs (two LUT3s); the row is used once per cycle.
- `Acc` (XLEN+1 bits): the running high half; its top bit is each step's carry
  out, the sign of the partial sum.  `MQ` (XLEN bits): the multiplier shifts out
  at the bottom while the product's low half shifts in at the top.
- 65 cycles: a load cycle, then 64 steps.  Signed forms cost nothing extra: the
  multiplicand is sign-extended, and for `mulh` the last step subtracts (the
  multiplier's sign bit has weight -2^63).
- Timing: the only late input to the adder is `MQ[0]`, a register.  `A`'s
  add-or-subtract form comes from registers that are steady for the whole
  multiply, the last step is flagged by a register a step ahead, and the load
  cycle keeps a "first step reads B" mux off the path.

A truly bit-serial design, a single full adder and a one-bit carry register,
would need about 64 x 64 cycles per multiply; the 64/65-cycle target needs one
full-width row of LUT pairs, used once per cycle.

**`hdl/core/ft_shadow/ft_mul.sv`**: runs the multiplier in Memory on the saved
transaction (`saved_a`/`saved_b`/`saved_funct3`, loaded as the multiply leaves
Execute) and holds the pipeline until DONE.

- Removed: the Execute-stage operand registers and their cycle counter (131
  flops), the separate 128-bit captured product, and the `HoldE` port (`mdu`,
  `wallypipelinedcore` updated).
- The fault injector now writes the completed product back into the
  multiplier's own product register, which doubles as the captured result
  (`mul.sv` `Load`/`PIn`).
- The residue check is unchanged.  The operands are steady for the whole
  multiply, so the expected residue is pipelined: the operand residues are
  registered (8 flops) and their product is captured with the result.  On `main`
  this path was the chip's worst (-0.297 ns).
- Phases: RUN -> COMPARE -> DONE; a failed check restarts the multiplier on the
  saved operands.

**Divider: unchanged.**  The first commit on this branch also set
`IDIV_BITSPERCYCLE` 2 -> 1 (one subtractor instead of two).  The follow-up
commit reverts that: it saved only 389 um^2 (`ft_div` 5,889 -> 5,500,
unconstrained), and a 64-bit divide went from 32 to 64 iterations.

**Benches and probes**: `ft_recompute_fault_tb` waits for the multiplier's check
instead of a fixed number of cycles, and no longer connects `HoldE`.  The
`synth/timing/probes.tcl` multiplier probes point at the new registers.

## Area and timing

**Every number below was measured with the one-bit divider**, before it was
reverted.  The multiplier's share is 18,551 um^2 unconstrained; with the divider
back at two bits per cycle the saving is that, minus the divider's 389 um^2.
The branch as it now stands has not been resynthesized.

`make synth DESIGN_TOP=forte_top`, `clock` 2500 ps, SRAM macros left as black
boxes.  The calibrated flow (`make -C synth timing`) does not run on `main`:
`gen_blackbox_libs.py` predates the `sram_sp_*` macros (the known item in
`worklog_io_split.md`).

The SDC's `create_clock` is on the `core_clk` port, behind the black-box pad
cell, so with it as committed nothing inside the chip is timed.  For these runs
it was moved to the `chip/core_clk` pin, in scratch copies only.

| | `main` | this branch | change |
|---|---|---|---|
| Total cell area | 177,026 um^2 | 155,505 um^2 | **-21,521 (-12.2 %)** |
| Sequential cells | 15,137 | 14,504 | -633 |
| Chip worst slack | -0.297 ns (mul residue) | -0.223 ns (link FIFO, not the MDU) | |
| Worst path into `ft_mul` | -0.297 | -0.097 | |
| Worst path into `ft_div` | -0.260 | -0.190 | |

DC flattens the MDU when it is timed, so the per-unit split comes from the
unconstrained runs (area-only, same flow): MDU 28,865 -> 9,925 um^2 (-65.6 %),
`ft_mul` 22,429 -> 3,878, `ft_div` 5,889 -> 5,500.  The divider's remaining area
is mostly fault-tolerance registers (saved operands, captured result) and three
64-bit negators.

A first version (64 cycles, no load cycle, `Cnt == 63` decoded on the step path,
residue unpipelined) had multiplier and divider paths up to 0.12 ns worse than
`main`; the load cycle, the registered last-step flag and the pipelined residue
fixed them at a cost of 687 um^2.

## Verification

- Scratch unit check of `mul.sv` against a reference product (not committed):
  20,257 products (all corner pairs x 4 funct3, plus 20,000 random), 0 errors,
  exactly 65 cycles each; restart while busy and `Load` checked.
- Gate (`timing_gate/gate.sh`, `GATE_NAME=mdu-area`): `ft_core_test`,
  `ft_control_test`, `ft_shadow_regression` (thresholds 1-3), ECC, cache and
  CSR-harden unit tests, `baremetal_regression`, `isa_regression`,
  `ecc_baremetal_regression`, ISA regression on the forte DUT (16/16),
  `link_abort`, `make cdc`, FreeRTOS 5/5: all PASS.  (FreeRTOS first failed in
  the fresh worktree for want of the `third_party/FreeRTOS-Kernel` submodule;
  rerun at the pinned `ce221a8` it passed.)
- Linux boot, baseline: `main` at `1c44a28`, forte DUT, reached
  `AMOEBA_LINUX_BOOT_OK` at cycle 677,978,564.
- Everything above ran with the one-bit divider.  The reverted divider is
  `main`'s, which passed all of it; the combination (new multiplier, two-bit
  divider) was not rerun before pushing.
- Linux boot, this branch (one-bit divider): **still running when this was committed**, same
  image as the baseline, `LINUX_TIMEOUT=1500000000`.  Its result and cycle
  count, the cost of the slower multiply and divide, are to be added here.
