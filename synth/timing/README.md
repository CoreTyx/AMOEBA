# Calibrated timing flow

Answers one question: **does `forte_top` meet 400 MHz on TSMC 65GP at the slow
corner, and if not, where does it miss?** — using the FreePDK45 library that is
available on the course machines.

```
make -C synth timing          # full run; read synth/timing/reports/summary.rpt
make -C synth timing_elab     # elaborate + link only, a few minutes
make -C synth timing_report   # re-report the last full run, no recompile
```

It is separate from `make synth`: its own script, constraints and output
directories, all under `synth/timing/`.

## How FreePDK45 stands in for 65 nm

Delay is carried between the two processes in units of FO4, the delay of an
inverter driving four copies of itself. `fo4.tcl` measures it for whatever
library `STD_CELL_LIB` points at. With

    K = FO4(65GP, slow corner) / FO4(FreePDK45)

the 2.5 ns target is synthesized as a `2.5 / K` ns clock, and every other
absolute time in the constraints is divided by K the same way. Reports multiply
back by K, and also give path depth in FO4, which needs no conversion.

Measured here: FreePDK45 (NanGate, typical corner) FO4 = 42.3 ps.

## What is a placeholder

Everything in `tech.cfg`. In order of how much it moves the answer:

| Knob | Default | Replace with |
|---|---|---|
| `TARGET_FO4_PS` | 40 | `dc_shell -f fo4.tcl` run against the real 65GP `.db` (set `FO4_INV`, `FO4_INV_IN`, `FO4_INV_OUT` to that library's inverter and pin names) |
| `SRAM_TACC_NS`, `SRAM_TSU_NS` | 0.80, 0.20 | the `rf_sp_*` compiler datasheets |
| `PAD_IN_NS`, `PAD_OUT_NS` | 0.50, 1.50 | the pad library |
| `CLK_UNCERTAINTY_FRAC` | 0.10 | the clock tree budget |

`summary.rpt` reprints every slack for target FO4 values from 30 to 50 ps, so
the sensitivity to the first of these is visible without rerunning.

## What the run does

1. `fo4.tcl` — measure the calibration library's FO4.
2. `gen_blackbox_libs.py` + `lc_shell` — timing models for the cells FreePDK45
   lacks: the `rf_sp_*` SRAM macros (clock-to-Q, setup, hold) and the
   `io_in`/`io_out`/`io_tri` pads (fixed delay).
3. `run_timing.tcl` — analyze, elaborate, constrain (`constraints_65.sdc`),
   `compile_ultra`, report (about 1.2 hours for `forte_top`). A source that fails to analyze or a cell that fails
   to link stops the run; either one would otherwise remove logic from the
   design and make the timing look better than it is.

## Reading `summary.rpt`

One row per path group, worst first. Groups are defined in `groups.tcl` by where
a path ends:

| Group | Paths ending at |
|---|---|
| `regfile_wr` | the register file array |
| `id_ex` | the D→E operand registers (register read, immediate) |
| `ex_mem` | the E→M registers (ALU result, store data, address) |
| `mem_wb` | the M→W registers |
| `ft_alu` | the fault-tolerant ALU's own state |
| `mul`, `div` | the multiplier and divider wrappers |
| `fetch_pc` | the PC register |
| `dcache`, `icache` | anything inside a cache, or starting from one |
| `fault_inject` | anything starting at the `fault_inject` pin |
| `link_io` | the link and slow pads |
| `other` | everything else |

Below the table, each worst path is broken down by the block its cells sit in,
in FO4. The full paths are in `reports/timing_<group>.rpt`.

## Reading `probes.rpt`

The group table says which area is worst, but in this core the worst path of
most groups is the same stall chain seen from different ends. `probes.rpt` pins
paths down instead: each probe in `probes.tcl` names a start, a net the path
must cross, and an end, and reports the worst path that fits. That gives the
multiplier, the ALU result, a cache read, the register-file write and so on a
number each, and a change to one block moves its own row. Compare this file
before and after a timing change.

## Limits

- Wire-load-model, pre-layout. It ranks paths and shows the effect of a change
  reliably; absolute slack is good to roughly ±20 %.
- Hold is not checked.
- `forte_top` puts the link on `core_clk`, so the `link_io` group is timed at
  400 MHz. That is a property of the top level, not of the core.
