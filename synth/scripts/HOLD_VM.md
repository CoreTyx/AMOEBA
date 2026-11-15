# DFT hold: VM handoff

For the detailed explanation, see [change scope](#scope-of-the-changes),
[mode selection](#selecting-and-entering-hold-mode),
[block behavior](#behavior-in-each-processor-block) and
[local verification](#exactly-what-was-verified-locally).

## Run flow

Use the complete `dft-hold-integration` source revision: `hdl/`, synthesis
Tcl/constraints, `synth/scripts/full_tb/`, and `hvl/pin/`. RTL, synthesis
protections, and phase S belong together. The pin-only `vm_bundle.tgz` does
not include synthesis/DFT scripts. Keep netlists and libraries on the VM.

```bash
cd synth
set -o pipefail
mkdir -p hold_results
make synth DFT_SCOPE=full 2>&1 | tee hold_results/synth.log
# Check success and the hold/clock-gating gates below before continuing.
make dft DFT_SCOPE=full 2>&1 | tee hold_results/dft.log
# Check success and post-insertion DRC before continuing.
cd scripts/full_tb
# Create paths.sh HERE before running anything; see README.md.
# NETLIST, SCANDEF and LOGICAL_PHASE must name outputs from this same make dft.
./run.sh --regen +SCAN_OP=both 2>&1 | tee ../../hold_results/full.log
./regress.sh 2>&1 | tee ../../hold_results/regression.log
```

Check each command's exit status before proceeding. `make dft` writes the
logical phase file; `--regen` rebuilds the testbench scan map and hookups from
it and the new netlist/scandef. Repeat after every netlist or scan-selection
change; subsequent runs reuse metadata.

## Required gates

| Check | Required result |
|---|---|
| Hold selector | `hold_mode` still depends on `sesync`; scan-enable arming survived synthesis |
| Clock gating | No ICG feeds both scanned and unscanned flops; scan registers excluded from inferred clock gating |
| Hold coverage | Zero unexpected unscanned core/linkcore flops without hold dependence; do not accept failures using `DFT_HOLD_COVERAGE=warn` |
| Test-enable hookups | Intended ICG exclusions/hookups preserved after insertion; investigate unrecognized discrete clock gates |
| Scan insertion | Full scope, valid connectivity/polarity, zero DRC errors |
| Full suite/regression | `DFT TB PASS`, no skipped required checks; phase S actually executes |
| Physical implementation | Timing, area and fanout acceptable for the target library/clock, including hold/control paths |

Hold-cone dependence is structural evidence, not proof of state retention.
Phase S provides complementary behavioral checks.

## Focused tests

Run sequentially from `full_tb/`. Archive `sim/` logs before each next command.

```bash
./run.sh +SCAN_PHASES=S
./run.sh +SCAN_PHASES=S +SCAN_RESUME_ITERS=1 +SCAN_RESUME_N=4000 '+SCAN_CASE=session'
./run.sh +define+BREAK_SE       # Must fail: shifting disabled
./run.sh +define+BREAK_MAP      # Must fail: polarity map corrupted
./run.sh +SCAN_OP=both          # Restore a normal build and verify it passes
./regress.sh --unload-reset    # Compare conventional protected/unprotected readout
```

Phase S pauses a quiet link, arms hold, unloads/restores in-flight scan state,
and resumes. It compares completion, signature/memory, link writes and final
stopped scan state with an uninterrupted run. It includes hold-only and
link-pause controls. **Do not reset during resumable hold**: reset destroys
the state being preserved. Conventional phases' protected-unload default is
a separate reset/readout test.

Investigate unprotected conventional failures independently; phase S passing
does not prove every legacy capture/readout sequence works without reset.
Keep failures visible and examine the failing phase's entry protocol.

After zero-delay verification, run functional gate simulation with VM-generated
SDF through `hvl/pin`: set `NETLIST`, `SDF` and `SDF_CORNER` in its separate
`hvl/pin/vm_paths.sh`, then build/run with `SIM=vcs DUT=gate` (see
`docs/postsynth_vm_runbook.md`). `full_tb` explicitly rejects SDF; timed scan
verification needs a supported tester/timing flow or a separate bench update.
Inspect timing reports/violations as well as functional verdicts. Do not mask
hold/control timing problems with blanket false paths.

## Local scope and limitations

`hvl/pin/hold_regress.sh` compares normal RTL execution with 16 holds per
program/profile, using memory/arithmetic/CSR workloads, representative state
checks on each frozen clock, and ordered pin-trace comparison ignoring cycle
timestamps. It cannot exercise inserted chains, ICG test enables, mapped
non-scan retention, four-state startup or SDF timing.
An additional four-hold IRQ case verifies level-sensitive service and identical
UART output, for 100 hold sessions in the complete local regression.

The protocol requires a quiet link and settling clocks for mode selection.
UART and external-input synchronizers continue running: lossless short IRQ
pulses or continuous UART traffic during long holds are not guaranteed.
Independently synchronized mode pins require CDC/protocol review; edge-aligned
RTL simulation does not prove metastability safety. Bare-metal runs do not
establish coverage of an active page-table walk.

Retain source revision/patch, target library/clock, synthesis/insertion reports,
netlist/scandef/phase checksums, local configuration, commands, simulator
version, phase summaries and expected negative-control failures. Protected
artifacts stay on the VM.

## Scope of the changes

There are two layers to this integration:

1. **Restore the existing hold implementation together with its DFT flow.**
   Commit `97e1bdc` reverses the revert on `dft` and restores 70 files, including
   the single-clock hold RTL, synthesis protections, diagnostic hookups and
   `full_tb` phase S. This is integration of existing work, not a new processor
   implementation. At this review the integrated `hdl/` matches `dft-hold`.
2. **Add native validation and strengthen the pin bench.** The subsequent
   working-tree changes add `hold_regress.sh`, the memory/CSR workload and IRQ
   hold script, improve `dft_hold`, fix short-command parsing, reject zero-cycle
   passes, allow `JOBS` for compilation, and update documentation. These changes
   remain uncommitted. They do not change the restored processor RTL.

| Area | Main files | Purpose |
|---|---|---|
| Session selection and isolation | `hdl/forte_chip.sv`, `forte_link_phy.sv` | Select capture versus hold mode; qualify scan enable; isolate the external link |
| Pipeline and state retention | `hdl/core/`, `hdl/forte_soc.sv`, `forte_uncore.sv`, `forte_link_core.sv` | Carry the hold through the core, uncore and core side of the link |
| Synthesis/insertion | `synth/dft_setup.tcl`, `dft_procs.tcl`, `dft_insert.tcl`, `synthesis.tcl` | Preserve controls, keep clock gating compatible with retention, check coverage and hookups |
| Mapped-netlist verification | `synth/scripts/full_tb/src/scan_resume.svh`, `tb_scan.sv`, `internal_hookups.py` | Implement phase S and diagnose corruption of scanned and unscanned state |
| Link-agent suspension | `hvl/pin/pin_link_agent.sv` | Add `hold_ready` and `paused` for a drained, suspended gate-level link session |
| New native verification | `hvl/pin/pin_tb.sv`, `pin.sh`, `hold_regress.sh`, `tests/hold_state.c`, `tests/irq_hold.cmd` | Verify freeze/resume behavior on RTL and compare with reference execution |

Legacy `wallypipelinedsoc` instantiations tie the added core `DFTHold` input
to zero. The complete DFT session interface described here is the ASIC
`forte_top` path. Updating generic module interfaces does not mean the legacy
top has acquired the same session protocol.

## What the stall system preserves

The objective is to interrupt execution, read scan state, restore that exact
state, and continue the program. There are three kinds of storage:

| Storage | During a hold-mode shift | Before resuming |
|---|---|---|
| Selected scan flops, such as pipeline/CSR bits | Intentionally change on every shift clock as bits pass through them | Reload the captured values, with the correct chain order and logical polarity |
| Unscanned flops, such as register-file and controller state | Must retain their pre-shift state | Already contain the state needed for continuation |
| SRAM arrays, such as cache data/tags | Must not be written by intermediate scan values | Must still contain the original data and metadata |

The clock continues running. Hold is implemented through register enables,
blocked state-machine updates and masked side effects, rather than stopping
the entire processor clock. Combinational outputs can still change while scan
bits move. The requirement is that those changing values cannot commit writes,
take traps, advance controllers or otherwise corrupt retained state.

This is stronger than an ordinary pipeline stall. During a cache miss, for
example, the pipeline waits while the cache controller and bus keep working.
During DFT shifting those controllers must also stop: their inputs may be
temporary scan bits rather than valid instructions and addresses.

## Selecting and entering hold mode

The control logic is in [forte_chip.sv](../../hdl/forte_chip.sv):

```text
test_mode_s   = test_mode after a two-flop core-clock synchronizer
scan_en_s     = scan_en after a separate two-flop synchronizer
hold_mode     = samples scan_en_s while test_mode_s is low;
                retains its value while test_mode_s is high
test_mode_dft = test_mode_s AND dft_unlocked
scan_en_dft   = raw scan_en AND test_mode_dft
hold          = test_mode_dft AND hold_mode

hold -> ExternalStall -> pipeline stall propagation
     -> DFTHold       -> core/uncore/controller retention
     -> FIFO masks    -> no core-side push/pop
     -> hold_link     -> synchronized link-domain input isolation
```

`dft_unlocked` is the software-controlled DFT permission latch. Reset unlocks
it; software can clear it until the next reset. A locked chip cannot enter
effective DFT test mode. It and the mode-selection controls must stay outside
the scan chains so shifting cannot change permission or drop the session.

Two protocols share the same pins:

| Protocol | Before raising test mode | Behavior once synchronized test mode is active |
|---|---|---|
| Conventional capture | Keep `scan_en` low, selecting `hold_mode=0` | `scan_en=1` shifts; `scan_en=0` permits functional capture |
| Resumable hold | Arm with `scan_en=1` while `test_mode=0`, selecting `hold_mode=1` | `scan_en=1` shifts; `scan_en=0` retains state |

Thus the stall is **not tied directly to `scan_en`**: dropping scan enable
between shifts must not let the processor advance. It is also **not an
unconditional consequence of `test_mode`**: conventional capture still needs
functional edges. The latched mode selects which behavior is wanted.

The supported, edge-aligned tester sequence is:

| Step | Pins/actions | Reason |
|---|---|---|
| Drain | Hold external `ready` low; allow an existing transaction to finish; wait for an idle link | Prevent switching the shared I/O pins during a wire transaction |
| Arm | `test_mode=0`, `scan_en=1` for at least three core clocks | Set the mode latch without shifting: effective scan enable is still zero |
| Enter | Raise `test_mode`, lower `scan_en`, wait three core clocks | Allow synchronization and hold assertion to settle; the first two edges are still functional in this protocol |
| Inspect | Shift out and reload, or leave `scan_en=0` to check retention | Preserve unscanned state throughout the session |
| Exit | Lower `test_mode`, keep `scan_en=0`, wait three core clocks | The first two edges remain held; functional execution resumes on the third |
| Release | Restore normal link handshakes | Resume external transactions after leaving the session |

The native `dft_hold` command requires eight consecutive quiet-link samples,
with a default 10,000-clock timeout. It then follows the arm/entry/exit sequence
and checks that hold actually asserts and releases. Its state snapshot is
taken after entry settles, not before the permitted entry-time execution.

Holding link `ready` low is a quiescence step, not a guaranteed processor
stall. The core can still execute from its caches or advance independent work.
The processor-wide freeze comes from `hold` driving the dedicated controls,
not from assuming that backpressure eventually stops every pipeline stage.

These timing statements assume the documented tester launch convention and
settling clocks. Two independent synchronizers do not prove safe alignment for
arbitrary asynchronous changes or eliminate the need for CDC analysis.
`scan_en_s` selects the mode; actual shifting uses qualified raw `scan_en`.

## Behavior in each processor block

### Pipeline, hazards and instruction fetch

In [hazard.sv](../../hdl/core/hazard/hazard.sv), `ExternalStall` is a cause of
`StallW`. Stalls propagate backward:

```text
StallW -> StallM -> StallE -> StallD -> StallF
```

F/D/E/M/W mean Fetch, Decode, Execute, Memory and Writeback. Holding W therefore
holds every stage, including the PC and pipeline registers whose enables are
`~StallX`. This also stops normal instruction retirement and writeback.

Holding stages is insufficient if a branch/trap can still flush them. The
hazard unit masks `FlushD/E/M/W` with `~DFTHold`. Consequently a held cycle
has all five stalls asserted and all four flushes deasserted. Intermediate
scan encodings cannot discard an instruction by generating a false flush.

The IFU also has state outside the main pipeline: fetch-check history,
instruction-page-fault records, cacheability selection, delayed stalls and
instruction-spill assembly. `DFTHold` freezes those registers and the spill
FSM. This preserves both halves of an instruction crossing a fetch boundary.
Branch-predictor updates normally depend on stage advancement, but prediction
is disabled in the current production configuration; these runs do not verify
hold with an active predictor.

### Integer datapath, register file and ECC

The datapath explicitly qualifies register-file write enable as
`RegWriteW & ~DFTHold`. This matters even though Writeback is stalled:
`RegWriteW`, destination and result bits can themselves be scan cells. Without
the mask, passing scan bits could repeatedly overwrite unrelated registers.

Pipeline ECC registers need another protection. Ordinarily an ECC register
may repair a correctable error while its normal load enable is low. A partially
shifted codeword can look like an error. `flopenrc_cw` disables that repair
when `DFTHold` is asserted; normal loads are stopped separately by stage
stalls. `DFTHold` in this primitive is not a replacement for its normal enable.
ECC injection-mask state is also held so the effective stored value does not
change through the fault-injection path during a session.

The combinational ALU need not stop evaluating. Its pipeline outputs,
fault-tolerant result/history registers and architectural write destinations
are what must be prevented from updating.

### Load/store unit and caches

The LSU retains delayed write data, memory-access checks, saved access faults,
TLB-miss history and cache-versus-uncached selections. An interrupted load or
store must resume as the same operation, with the same data and permissions.

For both instruction and data caches, the hold reaches the cache FSM. It
blocks state advancement, request latching, returned-hit/refill bookkeeping,
lookup starts, and flush-walk progression. The normal cache array enable is
masked low. Since SRAM writes require the array enable as well as a write
enable, scan-driven addresses/data cannot overwrite tag/data arrays. Cache-way
valid/dirty state and read bookkeeping also rely on that array enable.
Replacement-state updates are inhibited through the normal cache enable;
separate invalidation paths have additional hold qualification.

There is a configuration boundary here: `CacheEnArray` also includes the
background scrubber's ownership signal. The scrubber is disabled by the
current cache parameter defaults. `cachescrubber.sv` has no `DFTHold` input;
enabling scrubbing would require freezing its FSM/counters and preventing
scrub grants/writes during hold. The present results do not establish that
configuration as safe.

The local checker watches both cache FSMs and rejects an enabled tag/data
write during hold. It does not snapshot every SRAM bit. The resumed memory
workload supplies an additional functional check on exercised data.

### MMU, TLBs, PMP and page-table walker

The MMU translates virtual addresses and checks access permissions. Its TLBs
cache translations; PMP checks physical-region permissions. During hold:

- TLB writes, TLB flushes and replacement-history updates are suppressed.
- Registered PMP matches and delayed access-fault/miss results retain state.
- The page-table walker retains its FSM, captured PTE, page type and access
  bookkeeping. It must not consume changing scan inputs as a new translation.

These controls are present in the RTL. The native hold workloads, however,
recorded walker state `11` (`IDLE`) at all 100 entries. Normal execution of
the separate page-walk/fault ISA tests passed, but **an active page walk held
mid-translation remains unverified**. Merely probing the walker does not
establish coverage of its active states.

### Multiply/divide and fault-tolerant checking

Multiply and divide are multi-cycle operations; stopping the pipeline alone
normally lets them finish. Hold instead freezes their internal progress.
The multiplier retains its accumulator, multiplier/product shift register,
step count and loading/busy state. The divider blocks new starts and holds
its FSM, step counter, residual and quotient registers.

The `ft_mul`/`ft_div` wrappers also retain captured results and checking phases.
ALU/comparison fault-tolerant controllers hold their retry/recompute state,
saved results and diagnosis counters. A shift-induced mismatch must not start
a retry, change which result is trusted, or advance a pending diagnosis.

The recorded regression entered hold with the multiplier busy three times
and the divider in `BUSY` twice. That is evidence for some active arithmetic
cases, not exhaustive coverage of every retry phase, operand or terminal
fault. The native checker directly probes multiplier state and the divider's
FSM/checking phase; it does not snapshot all divider arithmetic registers.
The resumed program's arithmetic checks provide complementary evidence.

### Floating-point unit: disabled in this configuration

`F_SUPPORTED=0`, so this top does not instantiate an active FPU. These runs
provide no evidence for floating-point hold/resume behavior. Enabling it
requires reviewing its pipeline and multi-cycle engines; pipeline backpressure
alone is not a sufficient retention argument for an optional execution unit.

### CSRs, privilege, traps and WFI

Normal CSR accesses are qualified by a valid instruction, `~StallW` and
`~FlushW`, so the global pipeline stall suppresses software CSR writes.
Privilege-mode copies also use `~StallW` as their load enable. Trap assertion
is explicitly masked by `~DFTHold`, preventing temporary scan values from
creating a new exception or interrupt entry. WFI's timeout counter is stopped.

`MSECFAULT` is different from an ordinary software-written CSR: hardware can
set sticky bits every cycle. It receives an explicit hold guard, as do core
sticky fault/trap records. Otherwise shifting an invalid ECC/control value
could leave a permanent fault bit even after the correct scan state is restored.

The current configuration disables `ZICNTR`, `ZIHPM` and the associated CSR
performance counters. `csrc.sv` has no explicit hold input; for example its
cycle event is always one. Re-enabling those counters requires a hold review
and likely explicit update gating. Freezing CLINT `MTIME` does not establish
that an enabled `mcycle` would freeze.

### Fault injection, randomization and event counters

Core fault-injection selection, its LFSR/event count, dummy-instruction
generation state and operand-mask LFSRs stop updating. This preserves the
position in those sequences rather than consuming additional values while
execution is suspended. Registered ECC injection masks likewise retain state.
The core's fault-event record and sticky statuses are held so transient
scan values are not counted as real processor faults.

The uncore fault-counter peripheral holds both its counters and edge-detection
history. Holding only the count would be insufficient if its previous-event
bits moved and caused a missed or duplicate event on resume.

Normal fault-injection tests passed separately with `DFTHold=0`. They do not
prove behavior when a real injected fault, pending retry or asynchronous fault
pulse overlaps a hold. The new 100-session regression does not intentionally
inject such a fault.

### Bus arbitration, APB bridge and peripherals

The external bus unit holds arbitration state, beat count, saved instruction
requests, delayed write data/strobes and refill capture enables. It cannot
advance a burst just because a scanned bus-control bit changes.

The uncore AHB-to-APB bridge retains the selected peripheral, address, write
direction, transaction history and enable phase. The outgoing peripheral
select is masked as `PSELP = PSEL & ~DFTHold`. This prevents an in-flight
APB access from repeatedly committing while the bridge's state is held.
On resume the bridge is intended to continue its saved transaction; exhaustive
exactly-once testing at every APB phase has not been performed.

CLINT's `MTIME` stops incrementing and its read-data register is held.
APB-select masking also prevents software writes to timer/interrupt registers
during hold. This preserves processor-visible timer progress across the held
interval; physical wall-clock time still passes.

The PLIC retains pending/in-progress interrupt state and configuration.
Incoming synchronized interrupt levels may change while it is frozen. A
level still asserted on resume can be serviced then; a short pulse that comes
and goes during hold is not guaranteed to be remembered.

The UART keeps transmitting and receiving. It receives no APB access while
peripheral select is masked, but its serial engine is not frozen. Long holds
can therefore affect receive buffering and interrupt levels. The directed IRQ
test verifies level-sensitive service and matching output in its particular
scenario, not unlimited lossless UART/interrupt traffic during hold.

### Link core, asynchronous FIFOs and link PHY

`forte_link_core` is the core-clock side of the external-memory link. Its
transaction FSM, beat bookkeeping, pending state and registered bus controls
are held. The outgoing FIFO's core-side `wvalid` and incoming FIFO's core-side
`rready` are masked, preventing a push or pop. The asynchronous FIFOs themselves
and their pointer synchronizers are not globally stopped.

The PHY is a separate link-clock state machine. `hold_link` is a synchronized
copy of hold that makes its sampled `ready` and `rvalid` low. This protects the
shared I/O pins from being interpreted as memory traffic while they carry scan
bits. It does not make an arbitrary in-flight transaction safe to interrupt:
the external link must already be quiet before mode entry. The heartbeat and
link clock continue running.

The restored link-agent additions serve gate-level phase S:
`hold_ready` prevents new handshakes while letting existing traffic drain;
`paused` suspends the agent's sampling/checking/state updates after it is idle.
Independent bench monitors must still check link isolation while the agent is
paused. The native `dft_hold` command instead masks the pad handshakes and
leaves the agent running, so normal protocol checking remains active.

### Reset and controls that keep running

Reset synchronizers, mode synchronizers, the hold-mode latch, link-domain hold
synchronizer and external-input synchronizers are not frozen as core execution
state. They are needed to enter/leave the session or observe the environment.
Reset retains priority in the storage elements: asserting it destroys retained
processor state. Independent test cases may reset before loading a program;
the hold inside a running case must not reset.

## Exactly what was verified locally

Recorded WSL results (2026-11-14) are from Verilator 5.052, using
`SIM=verilator DUT=rtl`:
`SYNTHESIS` is defined and the pin flow uses local behavioral SRAM/pad stand-ins.
This is two-state RTL simulation with no inserted scan cells or real ICG test
pins. It is not VCS, a standard-cell netlist, SDF, formal equivalence, or a
full ISA compliance suite.

### Main hold regression: 100 sessions

| Workload | Profiles | Holds/profile | Checks |
|---|---|---|---|
| `basic_arith.c` | Fast and gapped | 16 | Arithmetic, memory, return code, retained state and complete ordered pin trace |
| `sorting_algo.c` | Fast and gapped | 16 | Longer program/data behavior, retained state and complete ordered pin trace |
| `hold_state.c` | Fast and gapped | 16 | 16 rounds over 256 64-bit words, dirty memory, multiply/divide identities, `mscratch`/`mepc` write/readback, retained state and pin trace |
| `irq.c` with `irq_hold.cmd` | Directed IRQ sequence | 4 total | Level-sensitive IRQ service, retained state, ordered pin trace and UART bytes |

Fast means `FPGA_GAP_PCT=0`, `FPGA_RD_LAT=0`, held `scan_en=0`. Gapped means
`FPGA_GAP_PCT=25`, `FPGA_RD_LAT=7`, held `scan_en=1`. These are two paired
configurations, not the complete timing-by-scan-enable cross product. The gap
agent uses its default seed; there is no seed sweep. The schedule is fixed.
The `FPGA_*` arguments configure the behavioral model of the off-chip FPGA's
memory/link driving duties. They do not select FPGA emulation of the processor;
the native DUT is RTL simulated by Verilator.

The 16 session lengths are `1, 2, 3, 17, 200, 1000, 1, 50, 5000, 3, 31, 200,
127, 4096, 1, 31` clocks. Functional gaps between sessions are
`0, 1, 2, 3, 7, 31, 127, 509, 1021, 4093, 8191, 16381, 50000, 100003, 250001,
7` clocks, plus protocol/drain overhead. This covers short holds, long holds,
closely spaced entries, startup/cache activity and later execution. Some late
holds in the short arithmetic program occur after its exit indication; they
check retained idle/exit state rather than additional live instructions.

Each reference/held pair must exit successfully and produce the same ordered
link records with timestamps removed. Both allow 10,000 clocks after `tohost`
to drain the exit fence's remaining writebacks. Otherwise a reference ending
at the first `tohost` event can have a shorter trace for a harmless reason.
The IRQ pair additionally compares UART bytes. A pass means the executed
checks agree; it is not proof that every internal bit has been examined.

### State checked on each frozen clock

The pin bench checks hold asserted, `req=wr=0`, all pipeline stalls asserted,
all flushes clear, no register-file write, no APB select, no core-side FIFO
push/pop, and no enabled cache tag/data write. It compares all implemented
nonzero register-file rows as raw stored codewords, plus these snapshot groups:

| Group in an error message | Snapshot contents |
|---|---|
| 0 | Fetch/decode/execute/memory PCs, Decode and Memory instructions |
| 1 | CLINT `MTIME` |
| 2 | Instruction/data cache FSM states |
| 3 | Bus-arbiter state; link-core state, beat count and pending flag |
| 4 | Fault LFSR/count, sticky FT status and registered register-ECC trap record |
| 5 | `MSECFAULT`, `mscratch`, `mtvec`, `RANDINSTRFREQ` |
| 6 | Multiplier checking phase, accumulator, product shift register and count; divider checking phase and FSM |
| 7 | Page-walker state and captured PTE |
| 8 | PLIC pending/in-progress bits and fault-counter array |

This detects an observed value changing and later changing back; checking only
entry and exit would miss that. It still observes selected state, not every
pipeline bit, every CSR, every cache word or every controller register.

### Additional checks, run separately from `hold_regress.sh`

| Check | Recorded result | What it establishes |
|---|---|---|
| 16 repository ISA programs on the pin bench | 16 pass | Normal execution with hold disabled, including arithmetic, AMOs, compressed instructions, page walk/fault/permission tests, random instruction insertion, fault control, link traffic and DFT lock |
| CSR hardening unit test | Pass | Existing privilege/security checks still work in that unit test |
| Full-core fault test | 48,297 checks pass | Existing injected-fault/retirement/precise-trap scenarios still work with hold disabled |
| Zero-cycle and zero-length controls | Rejected | Empty execution and invalid hold lengths cannot claim success |
| In-flight read with short quiet timeout | Rejected for expected timeout | The bench does not silently enter hold before the wire transfer drains |
| Same delayed read with sufficient quiet timeout | Pass | The bench can drain an existing transfer and enter a valid hold |
| Temporary RTL mutation removing the `MTIME` hold guard | Fails at frozen cycle 0, group 1 | The freeze checker detects a real retained-state update bug |
| 10 public-fixture runner/map checks | Pass | Generation/reuse/clean behavior, stale metadata rejection, invalid phase rejection, argument routing and rejection of missing/failing/nonzero simulator verdicts |

The parser previously used one four-conversion `$sscanf` for commands with
optional words. The installed simulator could return EOF after reading a valid
short command, causing it to be skipped. Parsing optional words independently
and rejecting zero-cycle runs prevents the observed false pass. Required hold
counts additionally prevent a regression from passing without its sessions.

The ISA runs use each program's own checks and the pin protocol checker, not
Spike/RVFI instruction-by-instruction comparison. The full-core fault test was
run with new-version lint warnings nonfatal; its behavioral assertions/checks
remained active. Public fixtures validate tooling only. The mutation and
fixture scripts live in temporary/ignored output, not as new tracked self-tests.

Reproduce the main regression from the repository root with Verilator 5.052
on `PATH` and the RISC-V bare-metal compiler available:

```bash
JOBS=1 hvl/pin/hold_regress.sh
# Separate existing unit tests:
CCACHE_DISABLE=1 make -C sim csr_harden_test
CCACHE_DISABLE=1 make -C sim ft_core_test \
  UNIT_TB_CFLAGS='-CFLAGS -fcoroutines -Wno-fatal'
```

Run sequentially: pin-program compilation uses a shared memory-image output.
Recorded main logs are in `sim/pin/hold_regress/20261114_173701_3/`;
the aggregate summary and copied control/unit logs are in
`sim/pin/hold_validation/`, with the normal-program summary in
`sim/pin/hold_native_isa/`. These are ignored local artifacts, not tracked
deliverables or evidence of a new VM run.

## Why the synthesis changes and phase S are still essential

RTL does not contain actual scan muxes. Even `DFT_HOLD_SE=1` in the local
regression only exercises the mode/control path while functional storage is
held. On silicon the selected flops instead shift, so unscanned logic sees
many intermediate values that native hold simulation never produces.

The restored synthesis flow addresses two implementation hazards:

- Optimization must not collapse the synchronized scan-enable/mode-selection
  path. The flow preserves the selector and synchronizers, prevents their
  retiming/scanning, protects the `sesync` boundary, and checks that the
  synthesized selector still depends on the intended source.
- An integrated clock gate (ICG) can be forced open by a test-enable pin.
  If it feeds both scanned and unscanned flops, shift clocks can update retained
  state despite the ordinary gate enable being inactive. The flow excludes
  scanned registers from inferred clock gating, checks for mixed groups,
  controls ICG test-enable exclusions, and verifies hookups after insertion.

The hold-coverage check examines unscanned flops under the SoC and link core,
following hold dependence through data paths, clock-gate enables and supported
retimed copies. UART/reset-related state has defined exemptions. This checks
whether a hold dependence exists, not whether the Boolean function guarantees
retention for all inputs. It also does not prove SRAM retention, external-link
protocol correctness, or physical timing.

Gate-level phase S supplies a stronger behavioral experiment: run a small
instruction workload as a reference, stop a second run at selected points,
drain/pause the link, enter hold, unload/reload twice to check repeatability,
restore the original scan image, exit without reset and compare completion,
signature/data, link writes and final WFI scan state. Hold-only (`tm`) and
link-pause-only (`ctl`) controls help distinguish shifting failures from hold
or link-quiescence failures. With defaults this is 12 full sessions plus four
hold-only and four link-pause controls across four programs.

That implementation was restored, not newly executed against a mapped netlist
on WSL. Historical FreePDK45 results are recorded in `HANDOFF.md`; a new target
netlist needs the VM acceptance runs above. Unprotected conventional capture
readout is a separate open issue: its protocol intentionally permits functional
edges. A resumable-hold pass does not justify removing protected readout from
all conventional tests.
Protected conventional readout can reset unscanned state, so it is not a
substitute for demonstrating preservation and resumption of a running program.
