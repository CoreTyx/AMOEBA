# Runtime fault injection and recovery

The working implementation is under `hdl/core`; `hdl/cvw` remains the pristine
upstream reference. Simulation and lint manifests select the working core and
read `cvw.sv` before its consumers. The synthesis manifest still gathers both
working and upstream HDL; it does not explicitly order the working package first.

## Hierarchy and interfaces

```
wallypipelinedcore
  fault_inject -> ieu -> dp -> ftalu (ft_alu)
                          replica[0/1].compute (alu)
                          replica[0/1].compare (addsub)
                          alu_ctrl + cmp_ctrl (ft_shadow_ctrl)
  fault_inject -> mdu.mdu -> ftmul (ft_mul)
                         -> ftdiv (ft_div)
```

The merged `ft_alu` produces XLEN `ALUResult`, XLEN `Sum`, and
`flags[1:0] = {eq, lt}`, along with aggregate `stall_req`/`unresolved` and
separate ALU/CMP primary/shadow PE indicators. `Sum` remains the address/branch
target. `A`/`B` are the existing muxed ALU operands; `cmp_a`/`cmp_b` are forwarded
register values and `cmp_sgnd` selects comparison signedness. A branch therefore
calculates its target and register comparison simultaneously with different
operands. Architectural comparison no longer instantiates a standalone wrapper.
`comparator.sv` keeps its original interface for AMO and other consumers.

Each ALU child provides private `ArithWide` (XLEN+1) and `ShiftWide` (XLEN+2)
results to its enclosing `ft_alu`. These signals, normal snapshots, diagnostic
controls, and alternate computations terminate inside the merged wrapper.
Datapath, IEU, and core have no widened result ports.

## Runtime controls

All injectors are always instantiated. The shared `fault_inject` input replaces
`ecc_inject_en` through the wrapper, SoC, and core. It enables both the existing
ECC storage injection and the `fi_enable` inputs of `ft_alu`, `ft_mul`, and
`ft_div`. There are no undriven core hooks or external bit/kind/channel controls.

Each `ft_fault_inject` contains a 16-bit Galois LFSR with polynomial
`x^16 + x^14 + x^13 + x^11 + 1`. The low bits select the physical bit index;
`[15:14]` selects XOR (`00`), stuck-at-zero (`01`), stuck-at-one (`10`), or
no corruption (`11`). An out-of-range index skips the event for non-power-of-two
widths. A nine-bit counter permits a one-cycle event every 512 clocks. LFSR and
counter run while disabled; enable gates corruption only. Reset restores the
seed and suppresses corruption. Distinct nonzero seeds stagger events across
replicas and injection sites, allowing transient faults to clear during retry.

| Injection site in each replica | Width |
| --- | --- |
| Architectural ALU result | XLEN |
| Extended ALU arithmetic/address computation | XLEN+1 |
| Physical shift result before slicing/sign extension | XLEN+2 |
| Extended architectural comparison difference | XLEN+1 |
| MUL full product | 2*XLEN |
| DIV quotient and remainder, separately | XLEN each |

DIV injection applies to the integer divider (`IDIV_ON_FPU=0`); configurations
using FPU integer division retain their existing path. Shift injection precedes
normal/alternate slicing; bits discarded by the normal architectural slice
alone do not create an architectural mismatch.

`hvl/common/top_tb.svh` drives `fault_inject` low for ordinary ISA/Linux runs and
high with `ECE411_SIM_INJECT`. The existing ECC injection test targets therefore
exercise ECC and FT injection together. Directed FT tests force private injector
events and selections to reproduce persistent faults, simultaneous faults, and
specific boundary bits without exposing those controls in the core interface.

## Arithmetic and comparison

`generic/addsub.sv` is the shared width-parameterized arithmetic helper. ALU
and comparison have independent arithmetic paths because their operands differ.
Comparison computes an XLEN+1 subtraction. Unsigned inputs are zero extended;
signed inputs are sign extended. Equality tests the entire difference for zero,
and less-than is its highest bit. SLT/SLTU and signed/unsigned Zbb min/max also
use extended subtraction, avoiding the overflow of an XLEN signed difference.

Diagnostic transformations apply **after extension**, modulo the helper width:

| Operation | Normal | Alternate |
| --- | --- | --- |
| ADD | `Ae + Be` | `~Ae + ~Be + 1 = ~normal` |
| SUB/CMP | `Ae - Be` | `~Ae + Be = ~normal` |

Ordinary full-width ADD/SUB and SLT/SLTU support isolation. SLT/SLTU additionally
check that each saved/live architectural Boolean agrees with its arithmetic
sign bit. ADDW/SUBW and other unsupported BMU operations retry and then report
unresolved. Min/max keep their architectural behavior but have no isolation
relation. MUL/DIV retain their existing retry-and-trap algorithms; threshold
one reports a sampled mismatch as unresolved without a retry. DIV captures
its operands, signedness, and word control at launch; forwarding changes during
iteration cannot change a retry. A successful final retry holds the divider's
DONE state until the instruction advances. The checked quotient and remainder
are registered on that same E→M edge and held through M-stage stalls. Later
injector events or a younger divider retry cannot change the accepted result.
DIV's E-stage terminal fault is
registered into M with the instruction before requesting cause 16. MUL retains
its M-stage fault through stalls and clears it on an accepted M-stage flush.

## Capture and independent recovery

ALU and CMP each own an independent controller, snapshots, and healthy-replica
selection. Comparison remains valid for every valid execute instruction, as in
the previous architectural comparison wrapper.

`capture_normal` is a combinational write-enable pulse asserted while a valid
instruction first mismatches in NORMAL. At that clock edge it captures the
**unmasked post-injection normal outputs**, before entering RETRY or RECOMPUTE.
It works even at threshold one. Each lane holds these private snapshots for all
retries and the diagnostic cycle. Capturing repeatedly would overwrite the
reference with alternate results or a later fault value and corrupt diagnosis.

`TE_THRESHOLD` counts consecutive mismatching observations. A matching retry
returns to NORMAL; persistent supported faults get one alternate-computation
cycle. Exactly one passing replica permits isolation of the failing replica.
Both passing or both failing is ambiguous and reports unresolved. Isolation
persists until reset/flush, and the two lanes may select different replicas.
One lane may recover while the other is already isolated.

Stall and unresolved requests are ORed across the controllers. **All** public
results (`ALUResult`, `Sum`, `flags`) are zeroed while either request is active.
A terminal unresolved indication remains asserted, with outputs masked, until
`advance` acknowledges the instruction's E→M transfer (`~StallM`). Independent
backpressure or a simultaneous fault in the other lane cannot discard it.
Reset/execute flush clears both controllers and snapshots. Sticky core status
survives a pipeline flush and clears on reset.

An ADD/SUB address calculation used by a branch is covered by ALU diagnosis;
its comparison is covered independently by CMP diagnosis. A CMP-only fault does
not unnecessarily switch the target-calculation controller into diagnosis.
Both calculations stay attached to the held execute instruction throughout
recovery, and the branch resolves only after trusted outputs are available.

## Shift diagnosis

The non-rotate shifter is XLEN+2 bits (66 for RV64, 34 for RV32). Word operands
are normalized and SLLI.UW zero extends its operand before the two-bit input
displacement. Architectural shift-amount masking is unchanged. SLL/SRL/SRA,
register/immediate forms, word shifts, and SLLI.UW use:

- Full-width: normal `[XLEN-1:0]` equals alternate `[XLEN+1:2]`.
- RV64 word: normal `[31:0]` equals alternate `[33:2]`, before sign extension.

Diagnosis also verifies the architectural result agrees with the corresponding
shift slice. An independent arithmetic/address disagreement during shift
recovery remains unresolved. Rotations retain the original XLEN/32-bit ring
and retry-and-trap policy; the displacement relation does not apply to rotates.

## Pipeline containment and status

FT stalls hold all architectural pipeline stages. Branch/jump redirection is
suppressed during FT stalls and unresolved E/M faults. Prediction-recovery
flush requests are qualified at the hazard input so predicted-taken branches
cannot flush their held execute instruction during diagnosis. Unresolved
releases a masked instruction to M, where the existing precise cause-16 trap
path consumes its PC; younger redirects remain suppressed. An older M-stage
trap, return, or CSR flush also takes priority over a younger FT stall so the
pipeline can flush, rather than deadlocking behind a newly mismatching instruction.

The custom read-only CSR `mftstatus` stays at `0x7c2`:

| Bit | Reset-sticky event |
| --- | --- |
| 0 | ALU replica isolated |
| 1 | CMP replica isolated |
| 2 | MUL replica isolated (reserved by its current recovery policy) |
| 3 | DIV replica isolated (reserved by its current recovery policy) |
| 4–5 | Reserved, read as zero |
| 6 | FT unresolved |

FTSTATUS contains only `ft_*` events. ECC SEC/DED remain in `MSECFAULT`
(`0x7c0`, bits 4/5); its contents and write-one-to-clear behavior are unchanged.
FTSTATUS clears only on reset, rejects writes, and retains the existing bit
positions and CSR address. Ordinary instruction timing is unchanged.
Identical faults in both replicas may agree without detection; replication
cannot identify such common-mode failures from agreement alone. Persistent XOR
in arithmetic can preserve both complement relations; it correctly produces an
ambiguous diagnosis instead of claiming a healthy replica.

## Verification

Run from the repository root (the ccache override is useful in a restricted
workspace):

```sh
CCACHE_DISABLE=1 make -C sim ft_shadow_regression
CCACHE_DISABLE=1 make -C sim ft_core_test
CCACHE_DISABLE=1 make -C sim isa_regression
CCACHE_DISABLE=1 make -C sim linux_boot
```

The merged unit regression runs RV32/RV64 at thresholds 1, 2, and 3. Independent
reference operators check comparison boundaries, signed subtraction overflow,
SLT/SLTU, min/max, every legal shift amount, word extension, SLLI.UW, and rotation.
Runtime injection covers both replicas and every channel, physical shift faults
at every legal amount and low/sign boundary bits, transient recovery,
persistent isolation/trapping, capture timing, stable retry snapshots, independent
replica selection, invalid indices, reserved kinds, reset/flush, and subsequent
operations. MUL/DIV tests cover transient and persistent faults on both
replicas and divider quotient/remainder channels. Divider tests remove the live
forwarding operands after launch to verify replay uses the saved transaction.
ALU/CMP terminal faults are held under downstream backpressure before acceptance.
The unit fixture explicitly enables Zba/Zbb/Zbkb so this coverage does not depend
on the production configuration's optional instruction selection.

The independent core bench uses its own tiny ROM and a retirement scoreboard.
Its generated configuration enables branch prediction for this fixture. It
trains branches to predicted-taken, forces private injector events/selections,
and checks simultaneous target/comparison operands, pipeline holding, absence
of destructive flushes/redirects, correct retirement, BNE/BGE cause-16 trapping,
precise fault PCs, multiplier and divider faults through MDU, and sticky CSR
reads. Four terminal-fault cases independently stall the pipeline after ALU,
CMP, MUL, or DIV diagnosis and disable injection, then verify one precise trap
when the stall is removed. Four additional cases inject quotient/remainder
faults only after E→M acceptance, with and without M-stage backpressure, and
verify the already-checked division still retires correctly. A hazard
priority probe covers older CSR/return/trap flushes, including interrupted WFI.
An additional scenario enables the actual shared `fault_inject` input and LFSRs,
checks 1,024 correctly retired loop branches, and confirms ECC corrections appear
only in MSECFAULT. The unit bench also checks unforced LFSR operation, event
spacing, seed reset, disabled pass-through, fault-kind coverage, and invalid indices.

CI runs the complete six-configuration unit matrix and the independent core
integration bench in the fault-tolerant regression job.

RTL uses implicit generate constructs consistent with the surrounding core.
`TE_THRESHOLD` must be positive; the simulation entry point and testbench
validate it. Parameter diagnostics stay out of synthesizable modules. Injector
bit indices use `$clog2(WIDTH)` directly for the execution-result widths used
here. The standalone unit matrix enables width warnings, but `-Wno-fatal` makes
them nonfatal. Core simulations, including the integration bench, use
`sim/verilator_warn.vlt`, which suppresses width warnings throughout `hdl/core`.
