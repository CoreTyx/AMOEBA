# Full scan testbench

## Run flow

**Create `paths.sh` beside `run.sh` before running the bench or regression.**
Use VCS and matching netlist, scandef, logical-phase and simulation models.
The synthesis/scan flow is documented in [DFT_FLOW.md](../../DFT_FLOW.md).

```bash
# From synth/, after configuring the VM's synthesis libraries:
make                         # loads Synopsys; full-scope synthesis and insertion
cd scripts/full_tb
# Create paths.sh here, then:
./run.sh --regen
./regress.sh
```

Example local `paths.sh` (ordinary Bash assignments; no export needed):

```bash
NETLIST=/path/to/synout/dft/forte_top.gate.v
SCANDEF=/path/to/synout/dft/forte_top.scandef
LOGICAL_PHASE=/path/to/synout/dft/forte_top.scan_phase.txt
STDCELL_MODELS=(/path/to/cells/*.v)
SRAM_MODELS=(/path/to/srams/*.v)
PAD_MODELS=(/path/to/pads.v)
VCS_FLAGS=()
# --timing uses this separate post-P&R output set. Set the actual filenames.
PNR_DIR=/groups/ece427-group4/experiment2/pnr/pnrout
PNR_NETLIST="$PNR_DIR/your_postroute_netlist.v"
SDF="$PNR_DIR/your_postroute_delays.sdf"
SDF_CORNER=min                          # min | typ | max
PNR_SCANDEF="$PNR_DIR/forte_top.scandef"
PNR_LOGICAL_PHASE="$PNR_DIR/forte_top.scan_phase.txt"
# Optional if hdl/ and hvl/ are not at their repository-relative locations:
# LINK_PKG=/path/to/forte_link_pkg.sv
# LINK_AGENT=/path/to/pin_link_agent.sv
```

Library/model paths accept files, globs, directories or Bash arrays. Keep
netlists and licensed models local. The default simulation is zero-delay.
`--timing` selects `PNR_NETLIST`, `SDF` and the PNR metadata from this file.
It never falls back to the synthesis `NETLIST`, `SCANDEF` or `LOGICAL_PHASE`.

`--regen` creates the scan map and enabled internal hookups in `sim/`
(zero-delay) or `sim/timing/` (post-P&R timing). Repeat
it after netlist, scandef, phase, mapping or hookup-generator changes; other
runs reuse the cached files. Update `src/scan_map.awk` when register names or
classifications change. The synthesis flow writes the logical phase file:
`0` means physical Q matches the RTL bit, `1` means inverted storage. Keep it
from the same synthesis/insertion run; Q/QN scan-path inversion is accounted
for separately. Without explicit `LOGICAL_PHASE`, the runner checks local
`scan_phase.txt`, then the file beside the scandef. No stale checked-in hookup
snapshot is used.

```bash
./run.sh                                      # reuse metadata; full defaults
./run.sh +SCAN_PHASES=S +SCAN_OP=both          # focused hold/resume
./run.sh +SCAN_PHASES=H +SCAN_OP=both +SCAN_SENTINEL
./run.sh +define+BREAK_SE                     # negative control: must fail
./run.sh +define+BREAK_MAP                    # negative control: must fail
./run.sh clean                               # preserve cached metadata
```

A/M/B are prerequisites and always execute. Remaining phases follow
`+SCAN_PHASES=<letters>`; default `CDEPHFRIS`. `+SCAN_CASE=<substring>` selects
cases; selecting no executable case fails. `+SCAN_REPEAT=n` repeats cases.
Plain runs default to load+capture checks (`SCAN_OP=both`), baseline sentinels,
R1000, I64 and eight S workloads. These defaults apply to timing runs too.
`+SCAN_NO_SENTINEL` disables baseline sentinels for focused debugging; the older
`+SCAN_SENTINEL` remains accepted but is no longer necessary.
Inputs launch after the clock edge (`+FPGA_TCO_PS`, default 2000 ps), and scan
outputs are sampled before the next shift edge. Test-mode entry waits three
clocks for the synchronizer. The default clock is 100 ns (10 MHz).

## Post-PnR from vm_paths.sh (the .v and the .sdf only)

On the VM, with only the post-PnR netlist and its SDF:

```bash
cp hvl/pin/vm_paths.example.sh hvl/pin/vm_paths.sh   # once; fill in NETLIST, SDF,
                                                     # the models, IGNORE_CELLS
synth/scripts/full_tb/postpnr_dft.sh --quick --ignore-neg-delay   # minutes: setup check
synth/scripts/full_tb/postpnr_dft.sh --ignore-neg-delay           # hours: the full run
```

Paste back `synth/scripts/full_tb/results/<stamp>/SUMMARY`. It holds counts,
verdicts and RTL register names only. It never holds cell names, model text or
SDF values; the full logs stay in `results/<stamp>.tgz` on the VM.

| Stage | What it proves |
|---|---|
| 1 preflight | Every vm_paths file exists, `vcs` is on PATH, the netlist has `forte_top`, and the SDF has `TIMINGCHECK`. |
| 2 discover | Chain order, scan-path inversions and logical phase, found by simulating the netlist (below). |
| 3 zero-delay | All phases pass on the PnR netlist with the discovered data. `BREAK_SE` and `BREAK_MAP` fail. A failure here is the data or the logic, not timing. |
| 4 timing, per corner | Phase S with the SDF: 40 hold / scan-out / scan-in / resume cases. Then the 11 regression jobs. Timing checks are on, and any violation fails. |
| 5 holds, per corner | The pin bench's hold regression on the netlist with the SDF. Programs with 16 holds (and the IRQ case) give the same link traffic as without the holds. |

`--corners min,max` is the default; min covers hold. `--from N` skips earlier stages
(discovery is cached). `--ignore-neg-delay` lets `SDFCOM_NIOD` (negative IOPATH
delays) through, and marks every affected line "not sign-off".

**Without a scandef, `run.sh --regen` discovers the chains** (`--discover` forces
this even when there is a scandef). Results go in `sim/meta/<netlist key>/`:
1. `src/discover_cells.py` lists every flop of the netlist by its physical Q:
   a leaf cell with a connected Q or QN, excluding the SRAM and pad macros.
2. The bench, built with `+define+SCAN_DISCOVER` (`src/scan_discover.svh`), does
   the following after phase A has measured the chains:
   - It records every flop at reset.
   - It enters hold-mode scan with reset held and flushes zeros.
   - For each chain, it shifts one 1 in and watches which flop holds it at
     each step.
   - Random loads then settle any position that had more than one candidate.
     Every position must end with exactly one flop.
3. `src/discover_meta.py` writes `forte_top.scandef` (order, with `OUT Q|QN`
   from the inversions seen) and `forte_top.scan_phase.txt`:
   - A cell stores its bit inverted when its Q at reset is the complement of
     its register's reset value from `scan_map.awk`'s table.
   - Cells of a register with no reset value (`ReadDataMWReg`), or with an X at
     reset, are not listed and get no correction. The summary counts them as
     "not observed". Phases E, P and I check them by function.
4. When a scandef or phase file is also given, they are compared: SAME or
   DIFFERENT, as counts. The discovered ones are used.

SDF builds use the pin bench's rules, so both benches judge an SDF the same way:
- `hvl/pin/sdf_prep.sh`:
  - unpacks a `.gz` SDF;
  - checks for `TIMINGCHECK`;
  - writes `RECREM` as `SETUPHOLD` when no cell model has a `$recrem` check.
    Otherwise VCS silently drops those entries.
- VCS flags `-negdelay +neg_tchk +define+NTC +define+RECREM`, with `+define+ARM_UD_*`
  dropped.
- `hvl/pin/sdf_msgs.sh` judges the annotation. It accepts only:
  - `SDFCOM_UHICD` on wires into `forte_top` output ports;
  - `SDFCOM_IWSBA` on INTERCONNECT through an assign;
  - `SDFCOM_NIOD`, and only with `--ignore-neg-delay`.

  Each one is checked against its SDF line.
- `src/timing_report.py` counts violations per check kind, bench phase and
  register. It names no cells or pins.
- `IGNORE_CELLS` stubs come from `hvl/pin/pin.sh ignored-cells`.

## Timing simulation

Timing mode is for the **post-P&R netlist and matching post-P&R SDF**, both
under `/groups/ece427-group4/experiment2/pnr/pnrout` on the VM. Set their actual
filenames in `paths.sh` as `PNR_NETLIST` and `SDF`; the runner does not guess.
Synthesis and DFT insertion do not export SDF.

Provide `PNR_SCANDEF` and `PNR_LOGICAL_PHASE` matching the routed chains.
They default to `forte_top.scandef` and `forte_top.scan_phase.txt` under
`PNR_DIR`. P&R can reorder chains or rename cells, so synthesis metadata may
be reused only after verifying that chain order, names and polarity are
unchanged. Point these PNR variables explicitly at that verified metadata if
it lives elsewhere. Regenerate the hookups from the post-route netlist.
Missing PNR metadata is an error; synthesis metadata is never selected implicitly.

Build products, logs and cached metadata are separate under `sim/timing/`.
Run `--timing --regen` once for the post-route output set; later timing runs
reuse it. Switching PNR input paths requires regeneration. Ordinary runs retain
their synthesis cache under `sim/`.

```bash
./run.sh --timing --regen
# Focus on reset-free scan/restore during a running workload:
./run.sh --timing +SCAN_PHASES=S
# Explicit clock settings (ps): 10 MHz execution, 1 MHz scan/arming
./run.sh --timing +SCAN_OP=both +FUNC_PERIOD_PS=100000 +SCAN_PERIOD_PS=1000000
```

- Timing mode annotates `tb_scan.dut` with VCS `-sdf`, enables specify blocks,
  timing checks and negative timing checks (`+neg_tchk`), and retains notifiers.
  Nonempty SDF with a TIMINGCHECK section is required. Known suppression flags
  and the `FUNCTIONAL` library define are rejected.
- Defaults: functional period 100 ns (10 MHz); scan/arming period 1000 ns
  (1 MHz). Zero-delay mode uses 100 ns for both. The clock changes rate between
  complete pulses when TM or SE selects scan/arming. Legacy capture in test mode
  also uses the scan rate; this is not an at-speed capture test.
- `+FUNC_PERIOD_PS` and `+SCAN_PERIOD_PS` set the periods. Scan input launches
  20% into the falling-to-rising interval; output is sampled 80% into it.
  `+SCAN_SETTLE_PS` sets the post-rising-edge wait before the next control change
  or internal snapshot: 20000 ps in timing mode, 2000 ps otherwise.
- Link input launch and forwarded-clock output sampling remain controlled by
  `+FPGA_TCO_PS` (2000 ps) and `+FPGA_SAMPLE_PS` (5000 ps). These model the
  off-chip FPGA's delays. Choose them and the settle wait from the actual pad,
  clock-insertion and model delays. They must be below both clock half-periods.
  A clean zero-delay run does not establish that these margins suit your SDF.
- Timing-check violations and SDF annotation warnings/errors fail the runner,
  even if the functional bench prints PASS. `sim/timing/timing_summary.log` points to
  diagnostics in `compile.log` and `sim.log`; `+sdfverbose` keeps annotation
  messages visible. Inspect VCS's annotation coverage: a TIMINGCHECK section
  alone does not prove checks matched or were enabled by the library models.
- The default watchdog is 10 s of simulated time in timing mode (1 s otherwise).
  Increase `+SCAN_TIMEOUT_NS` for larger iteration counts or slower clocks.

SDF supplies cell/interconnect delays and setup/hold/recovery/removal constraints
for the matching Verilog models. It needs timing-capable standard-cell, pad and
SRAM models, not functional stubs. Check library defines and annotation coverage
before trusting a pass. Do not disable timing checks or notifiers to hide Xs.

`SDF_CORNER=min` selects the minimum entries in the SDF delay triplets; `max`
selects maximum entries and is useful for setup checks. This does not select a
new process/voltage/temperature library corner. Use appropriate fast/min-delay
and slow/max-delay exports as well. Slowing the clock helps setup, but generally
does not fix same-edge hold violations. Synthesis SDF lacks final routed
interconnect and clock-tree skew. Use post-route SDF and scan-mode min-delay STA
for physical hold qualification. Simulation only checks paths exercised by its
stimulus; full_tb is not exhaustive timing signoff.

The runner keeps timing checks enabled during reset, scan entry/exit and
functional capture as well as shifting. Library models can condition individual
checks on reset or scan mode: conventional reset-protected unload may disable
some cell checks. Use phase S for reset-free shifting and inspect the models
and annotation report before treating it as hold coverage. Recovery/removal or
hold reports on those transitions need investigation too; the runner does not
automatically waive startup violations.

## Phases

| Phase | Stimulus and checked result |
|---|---|
| A: transport | Measure eight chain lengths and inversion parity using zero/one stimulus; check repeating `0011` transport. |
| M: mapping | Match discovered lengths and parity to the scandef; reject duplicate register-bit mappings and unknown classifications. |
| B: baseline | Reset and run 200 clocks without memory responses; compare resettable bits and retain the resulting baseline. |
| C: round trip | Shift random data through every chain and compare with length/inversion correction. |
| D: capture | Load baseline, apply one capture edge, and compare every mapped scanned cell. |
| E: PC | Load zero, ones, checkerboards, walking ones/zeros and random PC patterns; retain other cells at baseline. |
| P: registers | Test individual data/ECC/sticky/MPP registers, using valid ECC codewords and coherent privilege copies. |
| H: hardening | Inject single/double ECC faults, inconsistent privilege copies and reserved MPP; check repair or retained values and MSECFAULT flags. |
| F: reset | Load ones, inverted baseline and random state; reset and compare all resettable scanned bits. |
| R: randomized | Combine edge/random register patterns with valid, SEC, DED, parity-only and TMR cases; default 1000 iterations. |
| I: instructions | Execute short RV64 sequences through the link agent; check scan-visible PCs, pipeline operands, CSRs, WFI endpoint and absence of unexpected memory writes; default 64 sequences. |
| S: resumable hold | Run generated memory/arithmetic/CSR programs, interrupt with unload/restore, resume and compare against uninterrupted execution. |

`SCAN_OP=both` (default) checks load/readback first, then independently
resets/reloads and checks capture; failed loads block capture.
`capture` omits the separate load/readback check. `load` omits capture. F substitutes reset for capture. I has no
scan-loaded stimulus, so `load` explicitly skips it.

D/E/P/H/R reset independently before loading. Capture is aligned to the first
functional edge after reset, relying on the IFU fetch-check interlock and inert
controls. `ready=rvalid=0` alone does not guarantee a processor stall. Optional
`+SCAN_SWEEP` runs longer retention experiments; mismatches still fail and the
single-edge premise must not be generalized to them.

**Conventional readout holds reset by default.** It shifts out the captured
pre-reset values because scan has priority over functional reset in selected
cells. Incoming bits destructively replace them; this is not resumable state
capture. `+SCAN_UNLOAD_NO_RESET` explicitly selects unprotected legacy readout;
`+SCAN_UNLOAD_RESET` selects protection. Phase S uses the separate reset-free
hold protocol below.

R includes zero/ones, extremes, checkerboards and random patterns. Incomplete
ECC mappings are explicitly excluded. Coverage reports describe sampled SEC
bits and cases, not exhaustive fault coverage. The current decoder's
parity-only behavior is characterized rather than assumed to repair.

I covers ADD/XOR/shifts/MUL, RANDINSTRFREQ changes, MSCRATCH and MPP WARL behavior
with edge/random operands and varied link latency/gaps. It loads instructions
into a defined 4 KiB window, executes to a controlled WFI pipeline endpoint,
and compares selected scan-visible state. It is not a complete program loader
or an independent ISA correctness oracle.

## Phase S: hold, scan, restore and resume

Hold is selected at entry: SE=1/TM=0 for three clocks, then SE=0/TM=1 for three
clocks. Non-scan state must remain held while scan cells shift on SE=1 edges.
Exit uses SE=TM=0 for three clocks; two are held and the last may resume.
Legacy phases enter with SE low and preserve their functional capture edges.

Each of eight default programs exercises integer arithmetic, multiply/divide,
loads/stores across a 16 KiB data region, branches, CSR swaps and dummy
insertion. It writes a register/CSR signature, fences, reports through tohost
and reaches WFI. The uninterrupted reference records completion, signature,
data memory, ordered external writes and final scan state.

Per program, S executes:

- Three full sessions at selected execution positions: drain/pause the link,
  arm/enter hold, unload with zeros, reload the saved state, unload/compare it,
  reload again, exit and resume. Both reload paths check the expected zeros.
- One hold-only (`tm`) control with the same hold/shift duration but no shifts.
- One link-pause (`ctl`) control with no test-mode/scan-enable activity.

Default coverage is 40 cases: 24 full sessions, eight hold-only and eight pause
controls. `+SCAN_RESUME_ITERS=n`, `+SCAN_RESUME_N=n1,n2,...` and
`+SCAN_RESUME_BUDGET=n` control workload count, interruption positions and
execution budget. **Reset is never asserted inside a resumable session.**
The final reference/result readout is a separate protected, destructive scan.

S also checks available internal observations: RF codewords, MSCRATCH/MTVEC/
MEPC/MCAUSE/MTVAL, DFT permission, effective scan enable, and scan registers
for hold-only cases. Changes are latched even if later restored. Functional
entry and the first resume edge may legitimately change state. Missing required
probes produce explicit partial coverage, not a qualified pass. Arming-pattern
and clock-gate shared-value heuristics are diagnostic only.

For paused-link isolation, only a definite `1` on req/wr counts as an asserted
handshake and fails. X/Z warns once per pin/value category per session and has
separate sample counts; summaries show `isolation=WARN`. Warnings do not prove
internal isolation. Agent errors, retention changes, permission loss, effective
scan-enable violations and scan-data mismatches remain fatal.

All 13 output bits have event-based Z diagnostics, including startup and
control transitions. `OUTPUT Z SUMMARY` reports episodes per bit. These are
warnings, not electrical measurements or proof of a sustained fault; a control
change can be reported before combinational pad logic settles.

## Regression and results

`./regress.sh --timing` runs the same jobs with SDF and saves timing summaries.
`./regress.sh` runs 11 jobs: repeated baseline, E load-only, D capture, E/P/H/F,
the full suite, R1000, I64 and S with eight programs. Sentinels are enabled
by default. The PC load-only job intentionally exercises that explicit mode;
other jobs use `SCAN_OP=both`. That load-only job disables sentinels so a capture
failure cannot block the independent load diagnostic.
`./regress.sh --unload-reset` runs nine directed comparisons: four matched
protected/unprotected cases plus protected hardening readout. Runs continue
after failures and execute sequentially because they share `sim/`.

Current logs are `sim/run.log`, `compile.log`, `sim.log` and `pin_trace.log`
under `sim/`; timing runs keep the corresponding files under `sim/timing/`.
Archives and `summary.tsv` are in `regressions/<timestamp>_<pid>/`. Standalone
runs require `DFT TB PASS`; explicit skips are labeled partial coverage. The
regression returns 0 for all passes, 1 for any failure, and 2 for partial-only
coverage. A warning-only pad observation does not make coverage partial.

The cell order comes from the scandef, so round trips alone cannot establish
semantic mapping independently. Unreset bits are excluded from reset-value
comparisons. Matching X values does not establish known architectural state.
S compares observable completion/state, not every instruction retirement.
Timer/IRQ boundaries, short asynchronous pulses, active UART, MMU/atomic cases
and Linux scan/resume need additional directed qualification. UART and input
synchronizers continue running during hold; MTIME and PLIC state are held.
Counters, scrubbers and disabled processor features need separate qualification
if enabled. Mapped timing simulation requires the VM. Physical timing signoff and ATPG
coverage remain separate tasks; a full_tb pass does not establish them.
