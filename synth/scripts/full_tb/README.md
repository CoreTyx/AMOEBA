# Full scan testbench

`src/tb_scan.sv` verifies eight scan chains in a scanned `forte_top` netlist through
the package pins. Chain c0–c7 inputs use `io[7:0]`; outputs use `io[15:8]`.
The scandef supplies register-to-cell assignments. Chain lengths and output
inversions are measured from the pins. Internal hookups provide diagnostics;
pin comparisons determine pass/fail.

## Netlist interface compatibility

This bench targets the 16-bit bidirectional `io[15:0]`/`dir` interface of the
existing DFT netlist. The current `hdl/` RTL and normal pin bench use separate
8-bit `io_in`/`io_out` buses. Porting DFT to that interface is an open action
item. The existing netlist, cached map, and phase input remain usable here;
regenerating metadata alone does not port the testbench to a different link
protocol or pad interface.

The DFT build compiles its own legacy link package and agent from `src/`.
The normal pin bench compiles the current package/agent from `hdl/` and
`hvl/pin/`. Compile one protocol version per simulation, not both.

## Directory structure

| Path | Contents |
|---|---|
| `src/tb_scan.sv` | Pin-level testbench, scan tasks, directed phases, and summaries. |
| `src/scan_random.svh` | Randomized multi-register and fault cases. |
| `src/scan_exec.svh` | Instruction builder and functional-to-scan checks. |
| `src/forte_link_pkg_legacy.sv` | Protocol package for the existing 16-bit DFT netlist. |
| `src/pin_link_agent_legacy.sv` | Matching memory/link agent with DFT handoff control. |
| `src/scan_map.awk` | Netlist/scandef-to-map generator. |
| `src/internal_hookups.py` | Optional diagnostic hookup/report generator. |
| `src/set_scan_phase.py` | Explicit phase-file editing utility; not called by the runner. |
| `run.sh`, `regress.sh` | Build/run entry points and regression driver. |
| `paths.sh`, `scan_phase.txt` | Local path configuration and verified phase input, when supplied. |
| `sim/` | Cached generated metadata, compiled simulator, and current logs. |
| `regressions/` | Archived per-run logs, commands, traces, and summaries. |
| `generated/` | Checked-in hookup include/report snapshots; not used by the runner. |

Run commands from `full_tb/`; source layout changes do not require regenerating
netlist-derived metadata. The runner uses the matching legacy protocol sources
in `src/`, independently of the current RTL link interface.

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
| R — Randomized scan | Change multiple registers together, with valid ECC, legal MPP, inert controls, and coherent privilege copies. Alternate valid patterns, SEC repair, DED detection, overall-parity-only characterization, and one-copy privilege faults. |
| I — Instruction to scan | Serve short generated RV64 instruction sequences over the real link, reach WFI, then read instruction/operand registers and CSR state through scan. |

A/M/B run first on every invocation. The default remaining order is C/D/E/P/H/F/R/I.
A map or constrained-baseline failure blocks dependent cases.

Each independent D/E/P/H/R case receives a functional reset with scan disabled
before pattern loading. Reset remains asserted while entering scan and is
released `RST_LAT` shift clocks before loading ends (default: four). No reset
occurs between loading and capture. By default, reset is asserted after capture
for unloading. `SCAN_UNLOAD_NO_RESET` disables this protection for diagnostics.
F applies a functional reset after loading.

Outside I, the bench keeps `ready=rvalid=0` and supplies no external memory responses.
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
ECC faults are not injected by H. R characterizes them explicitly: the current
RTL decoder neither flags nor repairs an overall-parity-only error because its
Hamming syndrome is zero. That expected behavior is not a claim of complete
SECDED protection. The external `fault_inject` pin, memory ECC, DFT lock
transitions, and timing/ATPG fault coverage remain outside these checks.

### Randomized scan and instruction execution

R runs 100 iterations by default. Edge values include zero, all ones, the
64-bit sign bit, signed maximum, checkerboards, and random data. Multiple
registers change in each case, while control cells and privilege copies retain
the baseline. MPP is restricted to 00/01/11. Fault cases start with clear
`MSECFAULT`, so the expected new flag is observable. Complete ECC mappings are
required for randomized codewords; exclusions report partial coverage. R logs
case categories and distinct SEC stimulus bits per register. These are stimulus
counts, not exhaustive fault-coverage measurements. `SCAN_OP`, filters,
sentinels, repetitions, and the existing seed apply to R.

I runs 16 independent instruction sequences by default. It reuses
`src/pin_link_agent_legacy.sv`, the 16-bit pin driver preserved from
post-synthesis functional verification. The agent models the off-chip FPGA's
memory interface. Each sequence initializes a 4 KiB instruction window at `RESET_VEC`; no ELF,
toolchain, software runtime, or external image is needed. There are no data
loads/stores. Instruction fetches exercise multiple cache lines, read latency
from 0 to 15 link cycles, and ready/rvalid gap profiles of 0/10/25 percent.
Uninitialized memory remains X in a four-state simulator.

Eight case categories rotate through ADD, XOR, variable shift, low-half MUL,
RANDINSTRFREQ CSR operations, MSCRATCH operations, reserved-MPP WARL behavior,
and a directly observable nonzero RANDINSTRFREQ write. Operands include edge
values before randomized 64-bit pairs. CSR tests use CSRRW/CSRRS/CSRRC and
read-after-write, including RV64-to-32-bit truncation. CSRRW with x0 writes
zero; CSRRS/CSRRC with x0 do not write. MPP writes cover legal values and verify
that reserved 10 retains the previous legal value. MSECFAULT W1C is exercised
on a clean baseline; H/R separately check injected faults.

Each sequence ends with settled x5/x6 writes, a line-aligned WFI, then
`add x0,x5,x6`. Interrupts remain disabled and current privilege remains M.
WFI stalls Memory/Execute through the hazard unit. After a bounded
4096–4127-cycle execution interval, the bench disables the link agent, selects
scan in the same post-edge slot, and reads the state. No reset or extra
functional rising edge occurs between the selected endpoint and scan mode.
Each subsequent sequence resets from scratch; aborted link transactions are
not resumed. The instruction memory remains identical during `SCAN_REPEAT`.

Elapsed time does not establish success. Scan must show WFI in M with its PC,
the following ADD in E with its PC, expected x5/x6 codewords in RD1E/RD2E,
expected RANDINSTRFREQ and MPP values, and clear MSECFAULT. Fetch PC must be
known, aligned, and inside the terminal window; at least two completed
instruction-line reads and no memory writes are required. All required mapped bits must exist
unambiguously; missing endpoint mappings fail the phase. Other dynamically
executing pipeline cells are unconstrained because their values are not part
of this oracle. Internal hookups remain diagnostic only.

The first 32 sequences cover zero, all ones plus one, signed minimum/all ones,
and signed maximum/sign-bit operand pairs. Later sequences use random pairs.
Low-period CSR cases include periods 0, 1, 0xffffffff, and 0x80000000 with
distinctive upper 32 bits. Low-period insertion tests read RANDINSTRFREQ into x5 and then disable
insertion before the endpoint. Nonzero direct-readout cases use periods at
least 2^31 from a fresh reset: the initial divider strobe is accounted for,
and no previous captured dummy is carried into the case. Settling NOPs allow
operand writes to commit before raw register-file codewords are captured.

I executes for `SCAN_OP=capture|both`; it has no scan-loaded stimulus to verify.
`SCAN_OP=load` explicitly skips I and reports partial coverage. Link errors,
an incorrect endpoint, unknown checked bits, or mismatched values fail the run.
Passing I establishes these microsequences, not general program correctness,
all CSR semantics, or architectural-register-file scan coverage.

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
./run.sh +SCAN_OP=both
./run.sh +SCAN_PHASES=E '+SCAN_CASE=E reset value' +SCAN_OP=both
./run.sh +SCAN_PHASES=P +SCAN_CASE=PP1Reg +SCAN_OP=both +SCAN_REPEAT=3
./run.sh +SCAN_PHASES=H +SCAN_OP=both +SCAN_SENTINEL
./run.sh +SCAN_PHASES=D +SCAN_SWEEP
./run.sh +SCAN_PHASES=E '+SCAN_CASE=E functional hold' +SCAN_SWEEP +SCAN_UNLOAD_RESET
./run.sh +SCAN_PHASES=EPHD +SCAN_OP=both
./run.sh +SCAN_PHASES=R +SCAN_RANDOM_ITERS=1000 +SCAN_OP=both +SCAN_UNLOAD_RESET +SCAN_TIMEOUT_NS=1000000000
./run.sh +SCAN_PHASES=I +SCAN_EXEC_ITERS=64 +SCAN_OP=both +SCAN_UNLOAD_RESET
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
| `08_full_suite` | Run all phases, including R100 and I16, with load verification where applicable. |
| `09_randomized` | Run 1000 multi-register/fault iterations with load verification and an extended watchdog. |
| `10_instruction_scan` | Run 64 instruction sequences across all eight categories and bounded link latency/gap profiles. |

Every standard regression invocation uses `SCAN_UNLOAD_RESET` to protect
unscanned logic during readout. Capture expectations remain unchanged. The
paired readback experiment below explicitly includes unprotected control runs.

Results are saved under `regressions/<timestamp>_<pid>/`. Each run has its
command, `console.log`, available `run.log`, `compile.log`, and `sim.log`, plus
phase results in `phases.txt`, and `pin_trace.log` for link transactions. Logs present before the regression are saved in
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

### Reset-protected readback

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

The default readout asserts reset after the loaded/captured state has been
recorded and after scan enable is high. It adds no clocks or delay before the
first readout sample. Reset remains asserted for the shift, then its previous
pin value is restored. All mapped readouts, including B/F and sentinels, use
this protection. A/C transport tests do not change. `SCAN_UNLOAD_RESET` remains
accepted as an explicit request for the default behavior. Use
`SCAN_UNLOAD_NO_RESET` for an unprotected diagnostic run; specifying both flags
is an error.

Reset is held while the original chain contents are shifted out. The scan cells
are not frozen: each shift edge advances their contents toward scan-out and
replaces them with zeros from scan-in. There is no extra reset capture edge
before the first sample. The expected result remains the loaded/captured state,
not reset values. H's
nonzero fault flags provide a check that protected readback preserves captured
results. The experiment assumes scan shifting takes priority over reset in
the selected cells; a mismatch must not be dismissed if that assumption fails.
Internal reset still takes propagation clocks after external assertion.
Readout logs report the first X/Z sample on each affected chain.

This option protects only unloading. It cannot repair state already corrupted
during capture or an optional retention diagnostic.

## Open action items

- [ ] **Port DFT to the new link interface.** Adapt scan pad connections,
  testbench/agent, DFT declarations, and pin constraints for separate 8-bit
  `io_in` and `io_out` buses, including byte serialization in functional phase
  I. Replace the isolated legacy protocol sources only after validating the
  new interface against a regenerated DFT netlist. Account for the current
  RTL's two-clock `test_mode` synchronizer: specify mode-entry and capture
  timing, keep its synchronizer cells off scan chains, and preserve the
  intended snapshot without inserting unintended functional or shift edges.
- [ ] **Update scan selection for the revised multiplier.** Review the
  sequential multiplier's state/registers against the existing PP1/PP2 scan
  selectors and map classifications. Re-establish the intended scanned state
  and coverage before verifying a newly synthesized netlist.
- [ ] **Identify the cause of unprotected readout corruption.** Reproduce a
  failing case with `SCAN_UNLOAD_NO_RESET` and compare it with protected
  readout. Trace the first divergence alongside effective scan enable,
  `dft_unlocked`, pad-output selection, clocks, and resets. Correct values
  before shifting followed by Xs during shifting establish the failure
  interval; they do not identify the responsible control signal.
- [ ] **Implement and validate a DFT-session pipeline halt.** Connect qualified
  `test_mode_dft` to the existing `ExternalStall` path, currently tied to zero
  in `hdl/forte_chip.sv`. The intended contract keeps pipeline advancement
  halted throughout DFT mode, including clocks with scan enable low. Scan
  enable selects shifting versus the stalled functional path; it does not
  release the DFT halt. Keep scan clocks running and verify scan mux priority
  over functional enables. This is a proposed RTL change, not implemented by
  the testbench.
- [ ] **Audit activity outside the pipeline stall.** `ExternalStall` asserts
  StallW and propagates back through M/E/D/F, but is not a whole-chip freeze.
  Review flush/reset priority, sticky fault updates, ECC repair, multicycle
  units, cache/bus FSMs, asynchronous FIFOs, and APB side effects, including
  writes to the DFT lock. Define which actions must be inhibited throughout
  the DFT session, which fault-detection/repair actions remain intentional,
  and how in-flight link transactions complete or are quiesced. Do not stop
  the scan clock or assume a stalled pipeline stops these independent paths.
- [ ] **Verify shift/capture transitions after the RTL change.** With reset
  deasserted, check that effective scan enable remains known and asserted for
  every shift edge, scan contents advance correctly, pipeline advancement and
  unintended writes are inhibited, and the pad mux remains in scan mode.
  Deassert scan enable while keeping `test_mode` asserted and verify that the
  pipeline remains halted. Check the intended ECC repair and sticky fault
  updates separately: those paths are not universally gated by pipeline stall.
  Verify normal pipeline advancement is permitted again when qualified test
  mode is low, subject to other functional stalls. Exercise DFT-lock
  qualification and active link transactions at entry. This does not establish execution
  resumption after destructive scan shifting.
- [ ] **Repeat netlist verification and regenerate metadata.** After changing
  RTL/DFT insertion and regenerating the netlist, use `--regen`, run the
  standard regression, and compare protected/unprotected readout on the same
  cases. Keep reset-protected readout as the supported default until the
  unprotected procedure and its control requirements are verified. A pipeline
  stall alone is not established as a fix for the current corruption.
- [ ] **Independently verify scan mapping.** Establish register-bit order and
  physical-Q-to-logical polarity independently of the map used for both
  loading and reading. Resolve incomplete/merged-bit constraints explicitly.
- [ ] **Expand functional and fault coverage.** Add checked data loads/stores,
  interrupts and privilege transitions, additional CSR semantics, observable
  privilege-voter behavior, and broader fault-location/combination coverage.
  Test external fault-injection controls and memory ECC separately. Treat
  overall-parity-only ECC behavior as a documented RTL limitation, not proof
  of complete SECDED protection.
- [ ] **Establish implementation-level DFT coverage.** Review DFT rule checks
  and the supported tester/ATPG procedure, obtain stuck-at/transition fault
  coverage, and verify scan/capture timing with the applicable cell models,
  delay annotation, and corners. Zero-delay pin comparisons do not replace
  these checks.

### Selecting the stall control

| Candidate | Effect | Assessment |
|---|---|---|
| `test_mode_dft` | Requests a pipeline stall for the entire DFT session, including clocks with scan enable low. | Recommended for the intended halted-pipeline scan/readout contract. Verify entry/exit timing and define behavior of independent functional state. |
| Effective `scan_en_dft` | Requests the pipeline stall during shift; releases that request when scan enable goes low. | Insufficient for a halt that must persist through capture. Appropriate only for a separately specified protocol that intentionally permits functional pipeline advancement during capture. |

The legacy DFT target qualifies raw `test_mode` with `dft_unlocked`. Current
RTL uses `test_mode_dft = test_mode_s & dft_unlocked`, where `test_mode_s` is
the synchronized pin, and `scan_en_dft = scan_en & dft_unlocked`. Do not drive
a processor stall directly from an unqualified external DFT pin: a locked part should not acquire a new
stall path from a pin whose scan access is disabled. Currently scan enable and
pad-mode qualification are separate. Confirm their supported combinations
against the inserted scan-cell controls and test procedure.

Under the proposed halt contract, a scan-enable-low clock samples the stalled
functional path; it is not a normal advancing pipeline capture. D/E/P then
check retention under the explicit DFT halt, and H/R still check the specified
fault/repair updates. I executes its instructions before asserting test mode.
Document this distinction when interpreting coverage. Functional or ATPG
capture that requires pipeline advancement needs an explicit halt-release
mechanism/procedure. The halt does not make destructive scan readout resumable.

## DFT pin-link agent handoff

`src/pin_link_agent_legacy.sv` preserves the DFT-specific optional `enable`
input, defaulting to one. The normal pin bench uses the separate current
`hvl/pin/pin_link_agent.sv` with the new interface. The DFT bench connects the
legacy agent's enable to `link_active`, enabling it only for phase I's
functional execution and disabling it before selecting the scan pad mux.

Disabling the agent:

- Immediately releases all `io` pins, including the optional idle-X drive, and
  drives `ready=rvalid=0` through combinational output gates.
- Discards the active transaction and pending output decisions, resets the
  transaction state to idle, and restores first-transaction checking for the
  next session.
- Prevents a launcher delayed by TCO from restoring active outputs and makes
  the sampler skip protocol checks while disabled, including a sample already
  waiting through its sampling delay.
- Preserves cumulative error counters and memory contents. It does not resume
  an aborted transaction; the next instruction case resets the DUT first.

The output ports use internal `ready_drive`/`rvalid_drive` variables plus the
enable gates. Link transaction encoding, memory operations, PRNG, and launch/
sample timing algorithms retain their existing behavior when enabled. Phase I
sets its latency/gap profiles in the testbench; those profiles are not a new
link protocol. The `enable` control is a simulation-agent control, not a new
chip input or an RTL processor-stall implementation.

## Runtime controls

| Argument | Default | Meaning |
|---|---|---|
| `SCAN_PHASES=<letters>` | `CDEPHFRI` | Execute phases in this order after mandatory A/M/B. Letters may repeat. A/M/B entries do not repeat prerequisites. |
| `SCAN_RANDOM_ITERS=<n>` | `100` | Positive R iteration count. Increase for additional multi-register and fault stimulus. |
| `SCAN_EXEC_ITERS=<n>` | `16` | Positive I sequence count. Categories rotate every eight cases; at least eight covers every category. |
| `SCAN_CASE=<substring>` | All cases | Select case labels by a case-sensitive substring. Quote arguments containing spaces. A/M/B/C are unaffected. A filter yielding no executable case fails. |
| `SCAN_OP=capture` | `capture` | Load, capture, and unload. F loads, resets, and unloads. |
| `SCAN_OP=load` | — | Load and unload without target capture or F recovery reset. |
| `SCAN_OP=both` | — | Check the load, then independently reload and run the capture/reset check. A failed load blocks that case's capture/reset check. |
| `SCAN_SENTINEL` | Off | Check the single-capture baseline before each selected D/E/P/H case/repetition. A failed sentinel blocks the target. |
| `SCAN_REPEAT=<n>` | `1` | Repeat selected cases with identical stimulus and fresh preparation. Must be positive. |
| `SCAN_SEED=<n>` | `1` | Seed stimulus generation. Reproduction requires the same seed and phase order. |
| `SCAN_SWEEP` | Off | Enable optional D duration sweeps/50-clock hold and E's four 50-clock holds. Diagnostic mismatches fail the invocation. |
| `SCAN_UNLOAD_RESET` | On | Explicitly request the default reset-protected mapped readout. |
| `SCAN_UNLOAD_NO_RESET` | Off | Disable reset protection during mapped readout for diagnostics. Cannot be combined with `SCAN_UNLOAD_RESET`. |
| `SCAN_TIMEOUT_NS=<n>` | `100000000` | Positive simulation watchdog duration in ns. |
| `FPGA_TCO_PS=<n>` | `2000` | Delay after a rising clock edge for reset/mode changes. Must be greater than zero and less than 50000 ps. |
| `SCAN_NO_DUMP` | Off | Suppress large failure scan dumps. |
| `SCAN_TRACE_CYCLES` | Off | Print drive/sample details for each scan cycle. |
| `SCAN_TRACE_SHIFT` | Off | Print shift progress. |

## Timing and outputs

The clock period is 100 ns. Scan inputs change 10 ns after the falling edge;
outputs are sampled 40 ns after that edge, before the next rising capture edge.
Reset and mode changes occur after rising edges using `FPGA_TCO_PS`. This
argument models external driver timing. I's link agent samples forwarded-clock
outputs using `FPGA_SAMPLE_PS` (default 5000 ps). I chooses its own bounded
latency/gap profiles rather than `FPGA_RD_LAT`/`FPGA_GAP_PCT` overrides.

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

D/E/P/H/F/R comparison counters include load-only and capture/reset comparisons.
With `SCAN_OP=both`, one selected case normally contributes two comparisons;
sentinels add another. `selected_cases` counts cases before repetitions.

I contributes one scan comparison per executed sequence/repetition; `SCAN_OP=both`
does not add a scan-load comparison to an instruction-driven sequence.
