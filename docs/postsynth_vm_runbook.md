# Post-synthesis verification on the VCS VM

How to run the pin-level post-synthesis checks of `forte_top` on a machine with
VCS.  You need no prior knowledge of the bench; the background is in
[`hvl/pin/README.md`](../hvl/pin/README.md).  The commands below are the whole
procedure.

## What this run proves

The bench in `hvl/pin/` stands in for the bring-up FPGA.  It drives `forte_top`
through its pads only (link, UART, `irq`, reset), so the RTL and the
synthesized netlist run the same bench.  On the VM every program runs twice:

1. On the **RTL** (`DUT=rtl`).  The RTL is built with `SYNTHESIS` defined, so
   it uses the same SRAM macros and pad cells as the netlist.
2. On the **netlist** (`DUT=gate`).  The bench then requires the netlist's pin
   activity to match the RTL's **cycle for cycle**.

Before this bench, every test ran 2-state under Verilator.  VCS is 4-state.  The
X/Z checks and the `xstress` stage exist only here, so expect X problems to
show up here first.

Program correctness against the ISA reference (Spike) is established
separately, in the RTL flow under `sim/`.  This run checks that the chip
matches its RTL at the pins.

## Prerequisites

| Need | Notes |
|---|---|
| VCS on `PATH` | One licence is enough.  Everything runs sequentially. |
| `python3`, `bash`, `tar` | Standard. |
| The synthesized netlist | `make -C synth synth DESIGN_TOP=forte_top` writes `synth/outputs/forte_top.gate.v`. |
| Verilog simulation models | Standard cells; the SRAM macros `rf_sp_64_128` and `rf_sp_64_46` (others are harmless extras); the pad cells `io_in`, `io_out`, `io_tri`. |
| `images.tgz` | Prebuilt program images (about 8 MB).  The VM has no RISC-V toolchain, so programs are compiled elsewhere; see below. |
| Branch `postsynth_verif` | Contains the bench and the test fixes it depends on. |

### Getting `images.tgz`

Build it on any machine that has `riscv64-unknown-elf-gcc` (the same setup as
the main regression):

```bash
git checkout postsynth_verif
make -C testcode/linux           # soft-float Linux image; skip if build/boot.lst is current
hvl/pin/images.sh pack           # writes sim/pin/images.tgz
```

The archive is not in git.  Rebuild it whenever a test program, `bin/startup.s`
or the Linux image changes.  The VM runs exactly the images in the archive.

## Setup (once per checkout)

```bash
git fetch origin
git checkout postsynth_verif
mkdir -p sim/pin
tar -C sim/pin -xzf /path/to/images.tgz        # creates sim/pin/images/ with a MANIFEST
```

Edit `hvl/pin/vm_paths.sh`.  These are bash arrays, so globs work:

```bash
NETLIST=/path/to/synth/outputs/forte_top.gate.v
SDF=                                   # leave empty: post-synthesis is zero-delay
STDCELL_MODELS=(/path/to/stdcells/*.v)
SRAM_MODELS=(/path/to/sram_models/rf_sp_*.v)
PAD_MODELS=(/path/to/io_cells.v)
```

The RTL reference build uses `SRAM_MODELS` and `PAD_MODELS` as well.  If either
is left empty, the RTL build falls back to the behavioural stand-ins in
`hvl/pin/models/`.  That is fine for a smoke test but is **not** a sign-off
comparison.

## Run, step 1: the quick stages (minutes)

```bash
hvl/pin/vm_run.sh preflight selftest build
```

| Stage | Checks | If it fails |
|---|---|---|
| `preflight` | Every path in `vm_paths.sh` exists.  The netlist defines `forte_top` with all 16 bench-facing ports.  Every SRAM macro and pad cell the netlist instantiates is defined by a model. | The failing path or module is named in `SUMMARY`.  Fix `vm_paths.sh`. |
| `selftest` | The harness's own tests under VCS, against independent models: legal traffic, 13 deliberate protocol violations each detected with the right message, and 3 deliberate bench faults that must fail.  It includes the 3 X/Z checks Verilator could not run. | Send `sim/pin/vm_results/selftest.log` and the per-check logs in `sim/pin/selftest/vcs/`. |
| `build` | Compiles the bench against the RTL and the netlist. | Send the last ~50 lines of `sim/pin/build/vcs_<rtl|gate>/build.log`. |

None of this code had been compiled with VCS before the first VM run.  Compile
problems will show up in this step, and they are usually quick to fix.  Report
them before starting the long run.

## Run, step 2: the long stages (hours)

```bash
hvl/pin/vm_run.sh regress xstress
```

| Stage | Runs | Pass means |
|---|---|---|
| `regress` | Each image in `MANIFEST`: on `rtl`, then on `gate`, then a trace comparison.  `linux_m3` runs on `rtl` only. | Both runs end in `PIN_TB_RESULT: PASS` **and** the traces match cycle for cycle. |
| `xstress` | Directed and baremetal images, on `rtl` and `gate`, with the bus driven X whenever nobody owns it and every input X while `rst_n` is low. | Still passes: no X gets into the chip, and reset dominates. |
| `xmem` (optional, not in the default list) | As `xstress`, plus never-written memory reads back X. | **Informational.**  The D-cache's line-wide ECC can encode X when a store merges into a line filled from never-written memory.  Real silicon never sees that.  Treat failures as leads. |

### Time budget

The longest images on the RTL, in core cycles: `rtos_tc_sorting_result` ≈ 1.1M,
`linux_m0` (to the OpenSBI banner) ≈ 5.7M, `linux_m3` (MMU on, page tables
walked) ≈ 83M.  Every run's timeout is 10M cycles, or the per-milestone
timeouts in its `.cmd`.  The full Linux boot (416M cycles) is too long for VCS
and is run locally under Verilator instead.

To split the long run:

```bash
ONLY='^(smoke|uart_echo|irq|bm_.*)$' hvl/pin/vm_run.sh regress   # a subset (regex on image name)
SKIP_RTL=1 hvl/pin/vm_run.sh regress                             # reuse earlier RTL runs, rerun gate only
XLIST='^smoke$' hvl/pin/vm_run.sh xstress                        # narrow xstress
```

Stages can be run in any order after `build`.  `SUMMARY` is appended to, not
overwritten, so one file covers several sessions.

## What to send back

1. **Always:** `sim/pin/vm_results/SUMMARY`.  It holds one line per run and the
   first errors of anything that failed.
2. **If asked:** `sim/pin/vm_results.tgz`, which every `vm_run.sh` invocation
   rewrites.  It holds every run's `sim.log`, `pin_trace.log` (link
   transactions) and `uart.log` (console).

A `regress` line reads:

```
PASS smoke                                rtl=PASS gate=PASS trace=MATCH     12s
FAIL isa_tc_amo                           rtl=PASS gate=FAIL trace=DIFF     310s
       gate: [FPGA-LINK] ERROR @... cyc 1234: X/Z on io in write word 3 of 80001230: xxxx
```

## Reading a failure

| Symptom | Likely meaning |
|---|---|
| `rtl=FAIL` | A bench or program problem, not the netlist.  Report it; it should also fail locally under Verilator. |
| `rtl=PASS gate=FAIL` with an X/Z error | An X escaped on the netlist: an uninitialised flop or macro reaching a pin.  The error names the pin and the cycle. |
| `rtl=PASS gate=PASS trace=DIFF` | The netlist does something different at the pins.  `cmp_<name>.log` shows the first differing transaction. |
| `watchdog: read ... has not finished` | A link transaction hung, e.g. `dir` never fell for a read. |
| `timeout: no tohost write` | The program never finished, or never flushed its result (`fence.i`). |
| `framing error ... div N?` | The console speed disagrees with the program's UART setup.  The message suggests the divisor it actually saw. |
| `first transaction is ..., expected read of 80000000` | The chip's first fetch after reset is wrong: reset or the link is broken. |

Each run's directory is `sim/pin/runs/vcs_<dut>/<image>/`.  To rerun one image
by hand with waveforms or extra plusargs:

```bash
SIM=vcs DUT=gate hvl/pin/pin.sh run sim/pin/images/smoke.lst +MAX_ERRORS=5
SIM=vcs DUT=gate hvl/pin/pin.sh run sim/pin/images/irq.lst sim/pin/images/irq.cmd
hvl/pin/pin.sh compare sim/pin/runs/vcs_rtl/smoke sim/pin/runs/vcs_gate/smoke
```

The plusargs are listed in `hvl/pin/README.md`.  `+FPGA_TCO_PS` and
`+FPGA_SAMPLE_PS` move the bench's drive and sample points, which matters once
an SDF is in use.

## Later: post-place-and-route

The same procedure applies.  Point `NETLIST` at the post-PnR netlist and set
`SDF` (with `SDF_CORNER` = `min`, `typ` or `max`) in `vm_paths.sh`.  The build
then back-annotates delays on `pin_tb.dut` and enables timing checks.
