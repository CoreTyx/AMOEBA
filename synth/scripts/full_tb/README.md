# Full scan testbench

`tb_scan.sv` verifies eight scan chains in a scanned `forte_top` netlist through
the package pins. Chain c0–c7 inputs use `io[7:0]`; outputs use `io[15:8]`.
The scandef supplies register-to-cell assignments. Chain lengths and output
inversions are measured from the pins. Internal hookups provide diagnostics;
pin comparisons determine pass/fail.

## Test structure

| Phase | Operation |
|---|---|
| A — Chain lengths | Flush zeros, inject a one to measure each chain's length and inversion, then check a repeating `0011` pattern. |
| M — Scan map | Check map lengths, inversion parity, register-bit uniqueness, and register classifications. |
| B — Reset baseline | Apply functional reset, release it, wait 200 clocks with `ready=0`, then unload and compare resettable bits. Save the observed state as the baseline. |
| C — Round trip | Shift random data and compare outputs with inputs delayed by the measured chain lengths, accounting for inversion. |
| D — Baseline capture | Load the baseline, capture once in test mode, and compare all scanned cells. |
| E — PC | Load fixed, walking-bit, and random PC patterns with other registers at baseline; capture once and compare all scanned cells. |
| P — Registers | Load individual data, ECC, sticky-fault, and legal MPP patterns; capture once and compare all scanned cells. Also load all six privilege copies with U mode. |
| H — Hardening | Inject ECC and privilege-copy errors or a reserved MPP value; capture once and check ECC repair, stored copies, and `MSECFAULT` flags. |
| F — Reset recovery | Load all ones, the inverted baseline, or random data; apply functional reset and compare resettable bits. |

A/M/B run first on every invocation. The default remaining order is C/D/E/P/H/F.
A map or constrained-baseline failure blocks dependent cases.

Each independent D/E/P/H case receives a functional reset with scan disabled
before pattern loading. Reset remains asserted while entering scan and is
released `RST_LAT` shift clocks before loading ends (default: four). No reset
occurs between loading and capture. With `SCAN_UNLOAD_RESET`, reset is asserted
after capture for unloading. F applies a functional reset after loading.

The bench keeps `ready=rvalid=0` and supplies no external memory responses.
These pins do not directly freeze the processor. Single-capture D/E/P/H cases
use the first functional edge after reset: the IFU's reset fetch-check
interlock is expected to stall the pipeline, with control cells at their
checked reset baseline. Expected changes are limited to the specified ECC
repair and fault flags. This depends on `RST_LAT` matching the reset pipeline,
no HPTW fault, and no active flush overriding the stall. A mismatch remains a
failure and requires checking these conditions as well as the scan path.

Load-only checks verify scan transport without a target capture. Because
unloading destroys register contents, `SCAN_OP=both` prepares and reloads
independently before capture.

Reset comparisons exclude bits declared unreset. Observed X/Z values remain
visible; unconstrained baseline bits receive zero only when constructing load
stimulus. P/H ECC cases with incomplete mappings are skipped because constant
and merged-bit constraints are not established by the map. Map round trips do
not independently prove every register-to-cell assignment.

### Scope of the checks

| Checks | Requirement and limits |
|---|---|
| A/C | Check shift transport, chain lengths, and inversion at the pins. They do not depend on a functional pipeline stall or prove combinational fault coverage. |
| M | Checks map consistency against measured lengths/parity and rejects duplicate or unclassified entries. Loading and reading through the same map cannot independently prove bit order or logical polarity. |
| B/F | Check reset plus startup without memory responses at the configured reset vector. The 200-clock wait observes a naturally reached state, not a scan-reconstructed state. These are configuration-specific reset/startup checks, not a claim that every flop is permanently frozen by `ready=0`. F also checks recovery from arbitrary scanned control/data state. |
| D/E/P | Check directed first-edge capture under the reset fetch-check interlock. Full-cell comparisons also detect changes outside the target register. Arbitrary PC/data patterns need not represent executable instructions or legal long-running architectural states. ECC patterns use valid codewords; control cells remain at baseline. |
| H | Checks sampled ECC data/Hamming single-bit repair, sampled double-bit detection, privilege-copy fault flags, reserved-MPP detection, and sticky-flag accumulation. Stored privilege copies are expected to hold while stalled. Scan readback does not directly observe the voted privilege output or demonstrate copy scrubbing after the stall releases. |

H does not exhaust every fault location or combination. Overall-parity-only
ECC faults are not injected: the current RTL decoder flags SEC/DED only when
the Hamming syndrome is nonzero. The external `fault_inject` pin, memory ECC,
DFT lock transitions, functional execution, and timing/ATPG fault coverage are
outside these checks.

### Optional retention diagnostics

`SCAN_SWEEP` adds D's 50-clock functional hold and 1/2/4/8/16/50-clock sweeps
in both test and functional modes. It also adds E's four 50-clock holds at
external-memory PCs. Only selected phases/cases run. The standard suite and
regression omit these longer holds.

These diagnostics compare against unchanged loaded state, but that expectation
is conditional: a blocked external link does not establish a continuous global
stall, flushes can override a fetch stall, and scan loading does not restore
unscanned cache/bus/fetch state. Test mode selects scan access; it does not
freeze functional logic when scan enable is low. To establish retention as a
functional requirement, verify the relevant stall/flush conditions and account
for intentional register updates throughout the interval.

Explicitly requested diagnostic mismatches still fail the invocation and keep
their X/Z observations and snapshots. They are not silently waived or counted
as passing DFT coverage.

## Setup and commands

Run with VCS and matching netlist, scandef, standard-cell, SRAM, and pad models.
The runner performs zero-delay simulation with timing checks disabled; a
nonempty `SDF` setting is rejected.

Create `paths.sh` beside `run.sh`. The runner sources this file; assignments
do not need `export`. Bash arrays are not exported to child processes.

```bash
NETLIST=/path/to/forte_top.gate.v
SCANDEF=/path/to/forte_top.scandef
STDCELL_MODELS=(/path/to/cells/*.v)
SRAM_MODELS=(/path/to/srams/*.v)
PAD_MODELS=(/path/to/pads.v)
# Optional verified physical-Q-to-logical polarity corrections:
LOGICAL_PHASE=/path/to/scan_phase.txt
# Optional compiler flags:
VCS_FLAGS=(+define+ARM_UD_MODEL -debug_acc+all -kdb -j4)
# Optional: omit hierarchical diagnostics while retaining pin checks.
SCAN_HOOKUPS=0
```

Paths are resolved relative to the caller's working directory. Model settings
accept files, directories, or arrays of paths/globs. `SCANDEF` defaults to
`forte_top.scandef` beside the netlist. `LOGICAL_PHASE` defaults to
`scan_phase.txt` beside `run.sh` when that file exists. `SCAN_HOOKUPS` defaults
to `1`.

From this directory, with VCS available in the shell:

```bash
./run.sh --regen  # Generate metadata once, or after regenerating the netlist.
./run.sh +SCAN_OP=both +SCAN_UNLOAD_RESET
./run.sh +SCAN_PHASES=E '+SCAN_CASE=E reset value' +SCAN_OP=both
./run.sh +SCAN_PHASES=P +SCAN_CASE=PP1Reg +SCAN_OP=both +SCAN_REPEAT=3
./run.sh +SCAN_PHASES=H +SCAN_OP=both +SCAN_SENTINEL
./run.sh +SCAN_PHASES=D +SCAN_SWEEP
./run.sh +SCAN_PHASES=E '+SCAN_CASE=E functional hold' +SCAN_SWEEP +SCAN_UNLOAD_RESET
./run.sh +SCAN_PHASES=EPHD +SCAN_OP=both
./run.sh clean
```

An alternate paths file may be supplied as the first argument, for example
`./run.sh /path/to/other-paths.sh`. The default `paths.sh` is excluded from Git.
Compiler options such as `+define+SCAN_FSDB` go to VCS; runtime
plusargs go to the simulation executable. `--` sends subsequent arguments
directly to the executable.

### Generated metadata

Normal runs reuse `sim/scan_map.generated.svh` and, when hookups are enabled,
`sim/scan_hookups.generated.svh`. Neither normal runs nor regressions run the
generators. Missing cached files produce an error requesting `--regen`.

Use `./run.sh --regen` to rebuild the map, diagnostic hookups, and hookup report,
then compile and simulate. The flag can be combined with phase/case arguments.
Regenerate after changing the netlist, scandef, logical-polarity corrections,
or generator scripts. Inputs are not automatically checked for freshness.

`LOGICAL_PHASE` / `scan_phase.txt` supplies verified polarity corrections. The
runner reads it during regeneration and never generates or overwrites it.
`./run.sh clean` preserves the cached map, hookups, report, and phase metadata.

## Regression

Run the fixed sequence and save logs for every invocation:

```bash
./regress.sh
```

The regression uses `paths.sh`, reuses cached metadata, and runs sequentially.
Generate metadata with `./run.sh --regen` before the first regression. It
continues after test failures so that each test receives its own result. Do not run another
regression or `run.sh` concurrently; they share the `sim/` build directory.

| Run | Check |
|---|---|
| `01_baseline_repeat` | Repeat the reset-PC load/capture case five times. |
| `02_pc_load` | Load and read back all E patterns without target capture. |
| `03_baseline_capture` | Verify baseline loading and one capture edge in D. |
| `04_pc_capture` | Check all E patterns with load verification and capture. |
| `05_registers` | Check P register patterns with load verification and capture. |
| `06_fault_injection` | Run H with load verification, capture, and a baseline sentinel before each case. |
| `07_reset_recovery` | Verify F pattern loading and recovery through reset. |
| `08_full_suite` | Run A/M/B/C/D/E/P/H/F together with load verification. |

Every standard regression invocation uses `SCAN_UNLOAD_RESET` to protect
unscanned logic during readout. Capture expectations remain unchanged. The
paired readback experiment below explicitly includes unprotected control runs.

Results are saved under `regressions/<timestamp>_<pid>/`. Each run has its
command, `console.log`, available `run.log`, `compile.log`, and `sim.log`, plus
phase results in `phases.txt`. Logs present before the regression are saved in
`preexisting/`. `summary.tsv` lists each run's status, exit code, elapsed
seconds, and verdict. Results are excluded from Git and preserved by
`run.sh clean`.

The regression exits with `0` for all PASS, `1` for any FAIL, or `2` when no run
failed but some reported partial coverage. PARTIAL means individual checks were
skipped; inspect their reasons in the corresponding simulation log.

H performs fault injection through scan: load a corrupted ECC codeword,
privilege copy, or MPP value, apply a capture clock, and check the repair or
fault flags. The external `fault_inject` pin remains low.

For additional checks of the bench's failure detection, run these separately:

```bash
./run.sh +define+BREAK_SE
./run.sh +define+BREAK_MAP
```

Each command is expected to fail: the first disables shifting, and the second
corrupts a scan-map inversion. A successful simulation for either command
requires investigation. These expected-failure runs are not part of the
regression's PASS count.

### Reset-protected readback experiment

Compare the three all-one P cases with reset released versus reset asserted
during unloading:

```bash
./regress.sh --unload-reset
```

This runs paired baseline-PC and PP2/CSRValW/RANDINSTRFREQ cases, followed by H
with protected readback. Each pair uses the same load/capture expectations;
only reset during readback differs. Logs and summaries use the same directory
layout as the standard regression. Control runs retain their actual FAIL
status, so the comparison can exit nonzero even when protected runs pass.

For one protected case:

```bash
./run.sh +SCAN_PHASES=P '+SCAN_CASE=RANDINSTRFREQreg all 1' +SCAN_OP=both +SCAN_UNLOAD_RESET
```

`SCAN_UNLOAD_RESET` asserts reset after the loaded/captured state has been
recorded and after scan enable is high. It adds no clocks or delay before the
first readout sample. Reset remains asserted for the shift, then its previous
pin value is restored. All mapped readouts, including B/F and sentinels, use
this option. A/C transport tests do not change.

The expected result remains the loaded/captured state, not reset values. H's
nonzero fault flags provide a check that protected readback preserves captured
results. The experiment assumes scan shifting takes priority over reset in
the selected cells; a mismatch must not be dismissed if that assumption fails.
Internal reset still takes propagation clocks after external assertion.
Readout logs report the first X/Z sample on each affected chain.

This option protects only unloading. It cannot repair state already corrupted
during capture or an optional retention diagnostic.

## Runtime controls

| Argument | Default | Meaning |
|---|---|---|
| `SCAN_PHASES=<letters>` | `CDEPHF` | Execute phases in this order after mandatory A/M/B. Letters may repeat. A/M/B entries do not repeat prerequisites. |
| `SCAN_CASE=<substring>` | All cases | Select case labels by a case-sensitive substring. Quote arguments containing spaces. A/M/B/C are unaffected. A filter yielding no executable case fails. |
| `SCAN_OP=capture` | `capture` | Load, capture, and unload. F loads, resets, and unloads. |
| `SCAN_OP=load` | — | Load and unload without target capture or F recovery reset. |
| `SCAN_OP=both` | — | Check the load, then independently reload and run the capture/reset check. A failed load blocks that case's capture/reset check. |
| `SCAN_SENTINEL` | Off | Check the single-capture baseline before each selected D/E/P/H case/repetition. A failed sentinel blocks the target. |
| `SCAN_REPEAT=<n>` | `1` | Repeat selected cases with identical stimulus and fresh preparation. Must be positive. |
| `SCAN_SEED=<n>` | `1` | Seed stimulus generation. Reproduction requires the same seed and phase order. |
| `SCAN_SWEEP` | Off | Enable optional D duration sweeps/50-clock hold and E's four 50-clock holds. Diagnostic mismatches fail the invocation. |
| `SCAN_UNLOAD_RESET` | Off | Assert reset during mapped scan readout, preserving the loaded/captured comparison and scan clocks. |
| `SCAN_TIMEOUT_NS=<n>` | `100000000` | Positive simulation watchdog duration in ns. |
| `FPGA_TCO_PS=<n>` | `2000` | Delay after a rising clock edge for reset/mode changes. Must be greater than zero and less than 50000 ps. |
| `SCAN_NO_DUMP` | Off | Suppress large failure scan dumps. |
| `SCAN_TRACE_CYCLES` | Off | Print drive/sample details for each scan cycle. |
| `SCAN_TRACE_SHIFT` | Off | Print shift progress. |

## Timing and outputs

The clock period is 100 ns. Scan inputs change 10 ns after the falling edge;
outputs are sampled 40 ns after that edge, before the next rising capture edge.
Reset and mode changes occur after rising edges using `FPGA_TCO_PS`. This
argument models external driver timing. `FPGA_SAMPLE_PS` is not used.

In test mode the bench drives only `io[7:0]`. In functional mode it releases the
bus. No weak pull-downs are applied.

Generated includes, builds, and logs are written under `sim/`. `run.log`
contains runner output, `compile.log` contains compiler output, and `sim.log`
contains simulation output. Optional hookups record register observations
before and after capture; failed comparisons print both snapshots when
available. `+define+SCAN_FSDB` enables FSDB dumping when the simulator provides
the Verdi tasks.

Phase summaries report PASS, FAIL, SKIP, or PARTIAL. A passing run with explicit
skips reports its skip count. Any mismatch, timeout, simulator error, or missing
passing verdict makes the runner return nonzero. `clean` removes generated
simulation outputs and preserves logical-polarity metadata.

D/E/P/H/F comparison counters include load-only and capture/reset comparisons.
With `SCAN_OP=both`, one selected case normally contributes two comparisons;
sentinels add another. `selected_cases` counts cases before repetitions.
