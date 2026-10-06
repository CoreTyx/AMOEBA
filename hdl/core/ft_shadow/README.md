# Runtime fault injection and recovery

The working implementation is under `hdl/core`; `hdl/cvw` remains the pristine
upstream reference. Simulation, lint, and synthesis manifests select the working
core and read `cvw.sv` before its consumers.

## Hierarchy and interfaces

```
wallypipelinedcore
  ALUFi* -> ieu -> dp -> ftalu (ft_alu)
                          replica[0/1].compute (alu)
                          replica[0/1].compare (addsub)
                          alu_ctrl + cmp_ctrl (ft_shadow_ctrl)
  MULFi* -> mdu.mdu -> ftmul (ft_mul)
  DIVFi* -> mdu.mdu -> ftdiv (ft_div)
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

All injectors are always instantiated. Their enable is a driven input; there is
no elaboration-time injection parameter. Three independent control bundles are
**intentionally undriven local hooks in `wallypipelinedcore`**, with no ports above
that module and no RTL constants. A future test/DFT controller supplies these
signals. Testbenches must explicitly drive every bundle to known values;
`hvl/common/top_tb.svh` forces all controls to zero for ordinary ISA/Linux runs.
`ft_core_fault_tb` drives the same hooks for integration tests.

A narrow `verilator lint_off UNDRIVEN` region covers only these declarations.
It documents the deliberate unfinished connection without hiding other undriven
core signals. The hooks are not a synthesizable stimulus source by themselves;
connect a controller before using injection in hardware.

| Bundle | Controls | Bit index width |
| --- | --- | --- |
| ALU/CMP | `ALUFiEnable`, `ALUFiTarget[1:0]`, `ALUFiKind[1:0]`, `ALUFiChannel[1:0]`, `ALUFiBit` | `$clog2(XLEN+2)` |
| MUL | `MULFiEnable`, `MULFiTarget[1:0]`, `MULFiKind[1:0]`, `MULFiBit` | `$clog2(2*XLEN)` |
| DIV | `DIVFiEnable`, `DIVFiTarget[1:0]`, `DIVFiKind[1:0]`, `DIVFiChannel`, `DIVFiBit` | `$clog2(XLEN)` |

`Target = 00` disables replica selection, `01` selects primary, `10` shadow,
and `11` both. `Kind = 00` XORs the selected bit, `01` forces zero, `10` forces
one, and `11` is reserved/no-op. Enable zero and out-of-range indices are no-ops.
The merged wrapper checks the channel width **before narrowing** the index, so
an extended bit cannot alias architectural bit zero.

| ALU/CMP channel | Injected value | Width |
| --- | --- | --- |
| `00` | Architectural ALU result | XLEN |
| `01` | Extended ALU arithmetic/address computation | XLEN+1 |
| `10` | Physical shift result before slicing/sign extension | XLEN+2 |
| `11` | Extended architectural comparison difference | XLEN+1 |

MUL injects the full product; DIV channel zero selects quotient and one selects
remainder in the integer divider (`IDIV_ON_FPU=0`). Configurations using FPU
integer division retain their existing FPU path. A shift fault uses the same physical position during normal and
alternate computations, before either is sliced. Bits discarded by the normal
architectural slice alone do not create an architectural mismatch.

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
one reports a sampled mismatch as unresolved without a retry.

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
path consumes its PC; younger redirects remain suppressed. An older M-stage trap, return, or CSR flush also takes priority
over a younger FT stall so the pipeline can flush, rather than deadlocking
behind a newly mismatching instruction.

The custom read-only CSR `mftstatus` stays at `0x7c2`:

| Bit | Reset-sticky event |
| --- | --- |
| 0 | ALU replica isolated |
| 1 | CMP replica isolated |
| 2 | MUL replica isolated (reserved by its current recovery policy) |
| 3 | DIV replica isolated (reserved by its current recovery policy) |
| 4 | Register/pipeline ECC SEC |
| 5 | Register/pipeline ECC DED |
| 6 | FT unresolved |

ECC logic, CSR addresses, and ordinary instruction timing are unchanged.
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
make -C sim ft_core_lint
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
operations. Existing MUL/DIV tests remain in that bench.
The unit fixture explicitly enables Zba/Zbb/Zbkb so this coverage does not depend
on the production configuration's optional instruction selection.

The independent core bench uses its own tiny ROM and a retirement scoreboard.
Its generated configuration enables branch prediction for this fixture. It
trains branches to predicted-taken, drives only core-local injection hooks,
and checks simultaneous target/comparison operands, pipeline holding, absence
of destructive flushes/redirects, correct retirement, BNE/BGE cause-16 trapping,
precise fault PCs, multiplier faults through MDU, and sticky CSR reads. A hazard
priority probe covers older CSR/return/trap flushes, including interrupted WFI. Normal ISA/Linux tests explicitly
disable all three runtime bundles.
