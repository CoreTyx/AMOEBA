# Full scan testbench

## Run flow

**Create `paths.sh` beside `run.sh` before running the bench or regression.**
Use VCS and matching netlist, scandef, logical-phase and simulation models.
The synthesis/scan flow is documented in [DFT_FLOW.md](../../DFT_FLOW.md).

```bash
# From synth/, after configuring the VM's synthesis libraries:
make synth DFT_SCOPE=full
make dft DFT_SCOPE=full
cd scripts/full_tb
# Create paths.sh here, then:
./run.sh --regen +SCAN_OP=both
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
# Optional if hdl/ and hvl/ are not at their repository-relative locations:
# LINK_PKG=/path/to/forte_link_pkg.sv
# LINK_AGENT=/path/to/pin_link_agent.sv
```

Library/model paths accept files, globs, directories or Bash arrays. Keep
netlists and licensed models local. This bench is zero-delay: nonempty `SDF`
is rejected and `SDF_CORNER` has no effect.

`--regen` creates the scan map and enabled internal hookups in `sim/`. Repeat
it after netlist, scandef, phase, mapping or hookup-generator changes; other
runs reuse the cached files. Update `src/scan_map.awk` when register names or
classifications change. The synthesis flow writes the logical phase file:
`0` means physical Q matches the RTL bit, `1` means inverted storage. Keep it
from the same synthesis/insertion run; Q/QN scan-path inversion is accounted
for separately. Without explicit `LOGICAL_PHASE`, the runner checks local
`scan_phase.txt`, then the file beside the scandef. No stale checked-in hookup
snapshot is used.

```bash
./run.sh +SCAN_OP=both                         # reuse metadata
./run.sh +SCAN_PHASES=S +SCAN_OP=both          # focused hold/resume
./run.sh +SCAN_PHASES=H +SCAN_OP=both +SCAN_SENTINEL
./run.sh +define+BREAK_SE                     # negative control: must fail
./run.sh +define+BREAK_MAP                    # negative control: must fail
./run.sh clean                               # preserve cached metadata
```

A/M/B are prerequisites and always execute. Remaining phases follow
`+SCAN_PHASES=<letters>`; default `CDEPHFRIS`. `+SCAN_CASE=<substring>` selects
cases; selecting no executable case fails. `+SCAN_REPEAT=n` repeats cases.
Inputs launch after the clock edge (`+FPGA_TCO_PS`, default 2000 ps), and scan
outputs are sampled before the next shift edge. Test-mode entry waits three
clocks for the synchronizer.

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
| R: randomized | Combine edge/random register patterns with valid, SEC, DED, parity-only and TMR cases; default 100 iterations. |
| I: instructions | Execute short RV64 sequences through the link agent; check scan-visible PCs, pipeline operands, CSRs, WFI endpoint and absence of unexpected memory writes; default 16 sequences. |
| S: resumable hold | Run generated memory/arithmetic/CSR programs, interrupt with unload/restore, resume and compare against uninterrupted execution. |

`SCAN_OP=capture` (default) loads, captures and reads back. `load` omits capture.
`both` checks load/readback first, then independently resets/reloads and checks
capture; failed loads block capture. F substitutes reset for capture. I has no
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

Each of four default programs exercises integer arithmetic, multiply/divide,
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

Default coverage is 20 cases: 12 full sessions, four hold-only and four pause
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

`./regress.sh` runs 11 jobs: repeated baseline, E load-only, D capture, E/P/H/F,
the full suite, R1000, I64 and S with eight programs. H includes sentinels.
`./regress.sh --unload-reset` runs nine directed comparisons: four matched
protected/unprotected cases plus protected hardening readout. Runs continue
after failures and execute sequentially because they share `sim/`.

Current logs are `sim/run.log`, `compile.log`, `sim.log` and `pin_trace.log`.
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
if enabled. Netlist timing, physical implementation and ATPG coverage are VM
signoff tasks, not conclusions of this zero-delay bench.
