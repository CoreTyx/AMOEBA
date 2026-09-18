# RTL plan: execute-unit shadow checking for CORE-V Wally

**Status:** implementation requirements for this repository

**Audience:** the engineer modifying `hdl/cvw` and its integration/configuration.

This plan is based on the RTL currently in this repository, not on the five-way FU organization described in the source paper that motivated the original draft.

## 1. Objective and non-goals

Add spatial duplication and temporal retry to selected integer execution units so that a single transient or persistent fault in one copy is detected before an incorrect result is architecturally consumed. The initial implementation protects:

* the complete integer `alu` instance used by `hdl/cvw/ieu/datapath.sv`, including both outputs (`ALUResult` and `Sum`);
* the standalone `comparator` instance used to produce branch `FlagsE`; and
* the `mul` datapath inside `hdl/cvw/mdu/mdu.sv`, including its registered partial products and the full 2*XLEN product used for MUL/MULH/MULHSU/MULHU.

The implementation must not duplicate or modify the iterative divider, the FPU, the LSU AMO ALU, caches, register-file storage, or ECC logic in this phase. DMR does not protect a shared corrupted operand, so ECC remains an independent check and must not be hidden by a matching shadow result.

The active target is the AMOEBA Linux configuration in `pkg/config.vh`: RV64IMAC with
Zicsr/Zifencei, M/S/U privilege, Sv39, A (`ZAAMO` + `ZALRSC`), external AHB memory,
CLINT, UART, caches, and no PLIC. `F_SUPPORTED=0`, `D_SUPPORTED=0`, `Q_SUPPORTED=0`,
and `IDIV_ON_FPU=0`. There is no FPU or floating-point register path in this target;
do not add FPU hooks or require F/D-enabled elaboration for this feature. The design
should still avoid assumptions that break other legal Wally configurations, but Linux
verification and synthesis requirements in this plan are for the checked-in `pkg/config.vh`.

The target also has ZBA/ZBB/ZBS/ZBC and scalar-crypto extensions disabled, Zicond and
cache-block operations disabled, Sv48/Sv57/SvPBMT/SvNAPOT/SvINVAL/SvADU disabled,
hardware performance counters disabled, PMP entries set to zero, branch prediction
disabled, and direct (non-vectored) interrupts. These settings reduce the protected ALU
operation set and must be reflected in elaboration/tests rather than inferred from the
stock `rv64gc` Wally configuration.

## 2. Wally RTL facts that constrain the design

### 2.1 Pipeline and stall model

Wally has fetch/decode/execute/memory/writeback stages. `hdl/cvw/hazard/hazard.sv` computes the global stall/flush chain:

```text
StallF <- StallD <- StallE <- StallM <- StallW
```

and flushes the first stage after the last stalled stage. `StallE` is already asserted for `DivBusyE`; decode hazards are generated in `ieu/controller.sv`, not in `hazard.sv`. `ForwardAE`/`ForwardBE` are also generated in `controller.sv` and select the datapath muxes in `datapath.sv`. There is no forwarding-control logic in `hazard.sv` to gate directly.

The shadow logic must integrate with this existing chain. It must not create a second pipeline-control mechanism or independently hold only the E registers.

### 2.2 Integer ALU and address path

`datapath.sv` forms `SrcAE` and `SrcBE` after forwarding and the PC/immediate muxes, then instantiates:

```text
alu(SrcAE, SrcBE, ..., ALUResultE, IEUAdrE)
```

Inside `alu.sv`, `Sum` is always the arithmetic sum/subtraction result and is used as `IEUAdrE`; `ALUResult` is selected through the logical/shift/bit-manipulation result mux. Therefore a checker that compares only the register-writeback result is insufficient: both `ALUResult` and `Sum` must be checked, and the selected result plus address must be held until the check is complete. `IEUAdrE` feeds both branch/jump target logic and the LSU address path.

The complete `alu` includes Zba/Zbb/Zbc/Zbs, crypto, and conditional-zeroing paths when those parameters are enabled. The first implementation duplicates the complete module; it must not silently duplicate only the add/shift subset while claiming all integer ALU operations are covered.

### 2.3 Comparator and branch path

`hdl/cvw/ieu/comparator.sv` is not implemented using `alu.sv` subtraction. It computes `eq = (a == b)` and signed/unsigned less-than using MSB flipping and a behavioral `<`. It produces `{eq,lt}` as `FlagsE`; `controller.sv` converts those flags into branch decision `PCSrcE`. The comparator must consequently be duplicated as its own FU. The adder recompute relation does not apply to it in this RTL.

### 2.4 MDU timing

`mdu.sv` contains two distinct datapaths:

* `mul.sv` computes partial products in E, registers them with `FlushM`/`StallM`, and sums them combinationally into `ProdM` in M. It is effectively a one-cycle E→M pipeline, not a combinational E-stage result.
* `div.sv` is an iterative FSM. `DivBusyE` includes the start cycle and remains asserted while the divider runs. It is not a target for this feature. Because this target has `IDIV_ON_FPU=0`, integer DIV/REM use this RTL divider rather than an FPU divider.

The shadow multiplier must preserve the existing MUL result latency and stall behavior. Comparison of the duplicated product is an M-stage operation (before `PrelimResultM`), not an E-stage comparator pretending that the product is available in E.

### 2.5 AMO timing and coverage

AMO operations do not use the IEU ALU. `lsu/atomic.sv` invokes `lsu/amoalu.sv` in M; `amoalu` performs `amoadd` and bitwise operations and contains its own comparators for min/max. Consequently the IEU ALU shadow does **not** cover AMO arithmetic or AMO comparison. AMO protection is explicitly out of scope unless a later plan adds an independent M-stage AMO checker.

## 3. Required block decomposition

Create a reusable checker/controller block, but keep FU-specific datapath wrappers where timing differs.

| Protected block | Existing RTL boundary | Required comparison point | Result that may escape |
|---|---|---|---|
| ALU | complete `ieu/alu.sv` | combinational E result, before E/M transfer | checked `ALUResultE` and checked `IEUAdrE` |
| CMP | `ieu/comparator.sv` | combinational E result, before branch resolution | checked `FlagsE` |
| MUL | `mdu/mul.sv` | M product after the PP registers | checked `ProdM`, then existing MDU result path |

Each wrapper shall expose the primary and shadow outputs internally for verification and shall accept the same operands and control fields. The shadow copy gets the same post-forwarding operands and control signals as the primary copy. Do not compare internal partial products as a substitute for the architectural output comparison.

## 3A. Concrete RTL structure and file plan

The simulator compiles the working RTL under `hdl/core/`; `hdl/cvw/` is refreshed from
the Wally source by `bin/generate_rtl.sh`. New AMOEBA RTL must therefore have a clear
source-of-truth decision. For the current flow, place AMOEBA-specific modules under
`hdl/core/ft_shadow/` (or another directory included by the `hdl/core` source glob),
and do not put permanent edits only in `hdl/cvw/`, which the generator overwrites.
If the feature is later upstreamed into the Wally copy, mirror the modules and update
the generator flow deliberately.

The proposed modules are:

| Module | Location | Responsibility |
|---|---|---|
| `ft_shadow_pkg` | `hdl/core/ft_shadow/ft_shadow_pkg.sv` | Common state encoding, threshold widths, FU identifiers, and diagnostic bit definitions. No datapath logic. |
| `ft_shadow_ctrl` | `hdl/core/ft_shadow/ft_shadow_ctrl.sv` | Per-transaction DMR state machine: match, transient retry, recompute, isolate, and unresolved. Emits `Pending`, `StallReq`, selected-copy control, raw mismatch, `PE_p`, `PE_r`, and unresolved status. |
| `ft_alu` | `hdl/core/ft_shadow/ft_alu.sv` | Instantiates two complete `alu #(P)` modules and compares both `ALUResult` and `Sum`. Owns ALU recompute-mode eligibility and alternate operands. |
| `ft_cmp` | `hdl/core/ft_shadow/ft_cmp.sv` | Instantiates two `comparator #(P.XLEN)` modules, compares `{eq,lt}`, and uses retry-only behavior because CMP has no approved recompute relation. |
| `ft_mul` | `hdl/core/ft_shadow/ft_mul.sv` | Instantiates two `mul #(P.XLEN)` pipelines, compares `ProdM` in M, and controls product selection/retry without changing the PP-register latency. |
| `ft_stage_regs` | `hdl/core/ft_shadow/ft_stage_regs.sv` | Optional explicit E/M alignment registers for FT pending, unresolved, and isolation metadata when the existing Wally stage registers cannot carry the metadata safely. |

`ft_shadow_ctrl` may be parameterized and reused, but the ALU/CMP and MUL wrappers must
remain separate because ALU/CMP resolve in E while MUL resolves after the E→M PP
registers. The generic controller must not hide this timing distinction.

### 3A.1 ALU/CMP datapath integration

Modify `hdl/core/ieu/datapath.sv` as follows:

1. Keep the existing forwarding muxes (`faemux`, `fbemux`) and PC/immediate source muxes
   unchanged. `ft_alu` receives the resulting `SrcAE`, `SrcBE`, and every existing ALU
   control input: `W64`, `UW64`, `SubArith`, `ALUSelect`, B/ZBB/BALU controls, funct fields,
   `BMUActive`, and `CZero`.
2. Replace the single `alu` instance with `ft_alu`. Its checked outputs drive the existing
   `ALUResultE` and `IEUAdrE` nets, so `altresultmux` and `ieuresultmux` retain ownership
   of jump/immediate result selection.
3. Replace `comp` with `ft_cmp`. Its selected, confirmed output drives the existing
   `FlagsE` net consumed by `controller.sv`; no branch-controller redesign is needed.
4. Add valid/operation-qualified inputs so NOPs, bubbles, flushed instructions, and
   non-ALU instructions do not create mismatches or update FT state. The qualification
   must use the same `InstrValidE`/control state that identifies the current instruction.
5. Do not put the FT checker after `ieuresultmux`: jump link results and immediate/lui
   results are not produced by the ALU FU and must not be falsely diagnosed as ALU faults.

The `ft_alu` output contract should include at least:

```text
ALUResultCheckedE, SumCheckedE, ALUMatchE, ALUPendingE, ALUStallReqE,
ALUUnresolvedE, ALU_PE_p, ALU_PE_r
```

The `ft_cmp` contract should include:

```text
FlagsCheckedE, CMPMatchE, CMPPendingE, CMPStallReqE,
CMPUnresolvedE, CMP_PE_p, CMP_PE_r
```

The selected output must be driven to a safe value, or held behind the existing stage
enable, whenever `Pending` or `Unresolved` is asserted. There must be no combinational
path from an unconfirmed shadow output to `PCSrcE`, `IEUAdrE`, or an E/M result register.

### 3A.2 MUL/MDU integration

Modify `hdl/core/mdu/mdu.sv` at the existing `mul` instantiation:

1. Replace `mul #(P.XLEN) mul(...)` with `ft_mul #(P) ftmul(...)`.
2. Pass the same `clk`, `reset`, `StallM`, `FlushM`, `ForwardedSrcAE`,
   `ForwardedSrcBE`, and `Funct3E` to both internal `mul` instances.
3. Preserve the existing `ProdM` interface and the existing `PrelimResultM` mux. The
   checked product, not a sliced result, must feed `PrelimResultM`.
4. Add an M-stage `MULPendingM`/`MULStallReqM` or equivalent metadata path. A product
   mismatch discovered after the PP registers must prevent the current M instruction
   from advancing and must not be misreported as `DivBusyE`.
5. Ensure `Funct3M` and `W64M` remain aligned with the product selected after retry or
   recompute. No alternate product may bypass `W64M` sign extension.

The `ft_mul` contract should include:

```text
ProdCheckedM, MULMatchM, MULPendingM, MULStallReqM,
MULUnresolvedM, MUL_PE_p, MUL_PE_r
```

The exact retry mechanism must hold or replay the E-stage MUL transaction through both
PP pipelines. It must not restart `div.sv`, alter `DivBusyE`, or introduce a second MDU
result latency visible to the controller.

### 3A.3 Core-level control wiring

Modify `hdl/core/wally/wallypipelinedcore.sv` to collect the wrapper status signals and
connect them to the existing control blocks:

```text
ieu/datapath ── ALU/CMP FT status ──┐
mdu/ft_mul   ── MUL FT status ──────┼─> FT aggregation
ECC status   ────────────────┘  (reserved; tied off in this phase)
                                      ├─> hazard FT stall inputs
                                      ├─> controller decode-hazard input
                                      ├─> privileged/trap fault path
                                      └─> optional diagnostic CSR
```

The aggregation must distinguish E-stage and M-stage requests. E-stage ALU/CMP pending
holds the current execute transaction through the normal global `StallE` chain. M-stage
MUL pending holds the M transaction through `StallM`; the existing stage propagation
then holds earlier stages. A single OR signal is acceptable only after the individual
stage semantics are preserved.

Modify `hdl/core/hazard/hazard.sv` with explicit inputs such as `FTStallE` and
`FTStallM`, rather than overloading `ExternalStall`. The intended equations are the
existing equations with FT causes included before stage propagation and gated by the
existing flush causes:

```text
StallECause = (DivBusyE | FDivBusyE | FTStallE) & ~FlushECause
StallMCause = (WFIStallM | FTStallM) & ~FlushMCause
```

`FDivBusyE` is tied inactive in the current no-F/D configuration, but preserve the
generic port behavior. FT stall requests must not be allowed to stall a stage whose
instruction is being flushed.

Modify `hdl/core/ieu/controller.sv` rather than `hazard.sv` for decode-side dependency
handling. Add the FT-pending status and include it in the existing `MatchDE`/
`StructuralStallD` logic. The controller remains the owner of `ForwardAE` and `ForwardBE`.
The dependent D instruction must not advance or select a result from a producer whose FT
status is pending, isolated-but-not-confirmed, or unresolved.

### 3A.4 Precise fault path

Use a dedicated FT metadata register path rather than trying to infer an FT exception in
`trap.sv` from a raw combinational E signal:

```text
ALU/CMP unresolved E ─> FT E/M metadata register ─> FTUnresolvedFaultM
MUL unresolved M     ────────────────────────────> FTUnresolvedFaultM
FTUnresolvedFaultM   ─> privileged.sv ─> trap.sv
```

The metadata must be enabled, stalled, and flushed with the instruction it describes.
At minimum it carries `valid`, unresolved fault, FU identifier, and any selected
diagnostic bits. It must align with Wally’s existing `InstrValidM`, `PCM`, and `InstrM`.

Modify these interfaces together:

* `wallypipelinedcore.sv`: connect FT metadata and diagnosis signals;
* `privileged/privileged.sv`: accept the M-stage FT fault and pass it to trap/CSR logic;
* `privileged/trap.sv`: include it in `ExceptionM` and the explicit `CauseM` priority;
* `privileged/csr.sv` or a dedicated CSR submodule: add any approved machine-only
  diagnostic readback through the existing CSR mux, not a parallel CSR access path.

The no-F/D target means no changes are required in `fpu.sv`, `fhazard.sv`, floating-point
register files, or FPU result muxes. The existing `ECE411_NO_FLOAT` build define and
`pkg/config.vh` must remain consistent so the wrapper does not reference an elaborated-away
FPU hierarchy.

### 3A.5 ECC branch compatibility and tie-offs

The ECC integration point is assumed to match the `sai-ecc-csrhardening` branch. That
branch does not expose the earlier draft’s hypothetical `EccFaultAE`/`EccFaultBE` E-stage
ports. Its actual hooks are:

* `ecc_inject_en`, a top-level/testbench injection enable passed through
  `wallypipelinedsoc.sv`, `wallypipelinedcore.sv`, `ieu.sv`, and `datapath.sv`;
* `RegEccSecErrW`, an aggregate correctable-error indication from the register file and
  the ECC-protected IEU pipeline registers; and
* `RegEccDedErrW`, an aggregate uncorrectable-error indication from those same paths.

The branch protects the register file and seven XLEN-wide IEU pipeline registers with
`flopenrc_ecc`: `R1E`, `R2E`, `ImmExtE`, `SrcAM`, `IEUResultM`, `WriteDataM`, and
`IFResultW`. `privmode` also exposes a separate `PrivModeUncorrectableFaultW` path for
its TMR-hardened privilege-mode state, and the branch combines that with a sticky
`RegEccDedErrW` state in the top-level core.

For the shadow-pipeline implementation phase, preserve these interfaces structurally but
leave them inactive:

1. Tie `ecc_inject_en` to `1'b0` at the AMOEBA top-level/testbench boundary, or preserve
   the port and drive it from a constant-zero internal net. Do not enable injection in
   normal Linux, lint, or shadow-pipeline regressions.
2. Declare the reserved ECC-to-shadow status wires in `wallypipelinedcore.sv` and connect
   them to `1'b0` at the FT wrapper boundary. Do not use the W-stage aggregate
   `RegEccDedErrW` as an E-stage operand fault: it is too late and is not aligned with
   `SrcAE`/`SrcBE` or the current FT transaction.
3. Keep `RegEccSecErrW`, `RegEccDedErrW`, and `PrivModeUncorrectableFaultW` disconnected
   from FT mismatch counters, survivor selection, and FT trap generation for now. Their
   eventual ownership remains with the ECC/CSR-hardening path.
4. Do not add an invented `EccFaultAE`/`EccFaultBE` port to `ft_alu`, `ft_cmp`, or
   `ft_mul`. If future ECC work needs operand-valid suppression, add a separately named,
   stage-aligned adapter after the ECC branch defines that contract.

This leaves the shadow block’s ECC inputs present only as reserved, zeroed ports (or
omits them behind a clearly documented tie-off), so later ECC integration cannot be
confused with a functional ECC connection in this phase.

## 4. Checker state machine and retry semantics

Make `TE_THRESHOLD` a positive parameter in the relevant Wally configuration/parameter path, with default `3`. Do not hard-code it in a module. Counters and state shall reset on reset, flush, and completion of the instruction; they shall not count invalid or flushed instructions.

For each FU and each valid operation:

1. If all protected outputs match, select the primary output, clear the mismatch count, and allow normal stage progression.
2. If outputs mismatch and the count is below `TE_THRESHOLD`, suppress the output, hold the instruction and its operands/control, increment the count, and retry the same operation. The instruction must not be allowed to update M, W, memory, or branch PC state during this interval.
3. Once the threshold is reached, enter exactly one recompute transaction using the FU-specific relation in §5. No normal result is posted during recompute.
4. After recompute, isolate a diagnosed bad copy for that FU until reset. A persistent mismatch after isolation is unresolved and must trap; there is no automatic re-enabling of an isolated copy.

The implementation must define whether the threshold counts the first mismatch as count 1 or count 0 and use that definition consistently in RTL, assertions, and tests. The recommended definition is “first mismatch increments to 1; recompute starts when the current mismatch is the `TE_THRESHOLD`th consecutive mismatch.”

State must be per FU, not one global counter. An ALU/CMP operation and a MUL operation cannot overwrite each other’s retry state. The valid/opcode/operand identity associated with a pending transaction must be latched so that changing decode or forwarding inputs cannot change a retry.

## 5. Recompute and diagnosis requirements

### 5.1 ALU

The initial implementation shall use the existing adder semantics only for recompute:

* normal arithmetic result: `Fn = OP1 + OP2` with the appropriate W/subtract controls;
* alternate transaction: `OP1' = ~OP1 + 1`, `OP2' = ~OP2`;
* expected relation: `Fn == ~Fr` for the arithmetic result.

This relation is valid only for the ordinary add operation with matching width and no other ALU result selection. For subtract, shifts, comparisons, logical operations, bit-manipulation, crypto, Zicond, and operations whose result is not `Sum`, the first version shall not claim algebraic localization. A mismatch in those modes may be retried and then reported unresolved, or the feature may be disabled for those opcodes via an explicit `ALU_FT_SUPPORTED` decode. The choice must be visible in the interface and tests; silently applying the add relation to every `ALUSelectE` is prohibited.

For address generation, both ALU instances must produce and compare `Sum`. A diagnosed ALU fault invalidates both the register result and address result. No address or branch target may be consumed from an unconfirmed copy.

### 5.2 MUL

The normal operation is the exact signed/unsigned operation selected by `Funct3E`. The recompute transaction negates operand A in two's complement and expects the corresponding product to be the negation of the original product, with comparison performed at the full 2*XLEN product before MULH-family slicing and W sign extension. This relation is valid only where the selected multiplication semantics preserve it; the wrapper must verify MUL, MULH, MULHSU, and MULHU explicitly rather than assume a single signedness case covers all four.

Because `mul.sv` has E→M registers, recompute must either (a) replay the saved operation through the same PP registers and compare in M, or (b) add an equivalent shadow pipeline. It must not feed an alternate product combinationally into the normal MDU result mux and claim one-cycle completion.

### 5.3 CMP

CMP has no approved algebraic recompute relation in this RTL. It receives DMR and retry only. If mismatch persists through the threshold, classify it as unresolved and request the fault trap; do not attempt the ALU add relation on `{eq,lt}`.

## 6. Pipeline integration requirements

### 6.1 E-stage ALU/CMP hold

Add an FT stall request as an input to the existing global hazard logic. On an ALU/CMP retry or recompute, the current E instruction and all source/control state used by it must remain stable. The resulting stall must propagate through Wally’s normal `StallF` through `StallW` chain. Flush has priority over a stall, consistent with `hazard.sv`.

The implementation must not hold only the `R1E/R2E` registers while allowing `PCE`, control signals, or instruction-valid pipeline state to change. Either the existing stage registers are held by the global stall or the FT wrapper latches a complete transaction and uses that transaction exclusively until completion.

### 6.2 Forwarding and decode hazards

The generated plan’s instruction to gate forwarding in `hazard.sv` is incompatible with this RTL: `hazard.sv` does not generate `ForwardAE`/`ForwardBE`; `ieu/controller.sv` does. The implementation shall extend the controller’s decode hazard logic so a D-stage consumer cannot advance while its E-stage producer is pending FT validation/retry. The existing `MatchDE` and `StructuralStallD` mechanism is the preferred integration point.

Forwarding selections must refer to the confirmed producer result only. During an FT retry, the dependent instruction must not select an unconfirmed `IFResultM`/`ResultW`. Add assertions for no consumer advance and no forwarding of an unconfirmed result.

### 6.3 MDU interaction

Do not fold FT retry state into `DivBusyE`. Divider state remains controlled by `div.sv`. For MUL, preserve the current one-cycle E→M product pipeline and add a distinct pending/retry signal that cannot falsely restart an iterative divide. If a cycle contains DIV, the shadow multiplier logic is inactive.

### 6.4 Result and side-effect gating

The following must be gated until the relevant check completes:

* `IEUAdrE` used by IFU branch/jump selection and LSU memory addressing;
* `FlagsE` used to form `PCSrcE`;
* IEU result entering `IEUResultM`;
* MUL product entering `MDUResultM`/`MDUResultW`.

No FT retry may issue an LSU read/write, AMO transaction, register-file write, CSR side effect, or branch redirect. Existing `Flush*` behavior on traps/mispredictions must discard an in-flight FT transaction cleanly.

## 7. Fault reporting and privileged integration

### 7.1 Precise unresolved fault

An unresolved FT result is an instruction-caused synchronous exception. Add a valid, stage-aligned fault signal to the same pipeline path as the other M-stage exception inputs. Since Wally’s trap machinery takes exceptions in M (`privileged.sv` → `trap.sv`), an E-stage unresolved result must be held/replayed or pipelined to M with the instruction PC, instruction-valid state, and any required `mtval` information. It must not be emitted as an asynchronous global trap request that loses instruction identity.

Extend `trap.sv`’s `ExceptionM` and cause-priority chain with a custom synchronous cause. The selected code must be checked against the implemented Wally cause width (`CauseM` is 5 bits) and existing causes. Use the first available custom exception value, document it as implementation-defined, and ensure `MEDELEG` indexing cannot address outside its implemented range. The FT cause must have an explicit priority relative to illegal, instruction, load/store, breakpoint, ecall, and misaligned exceptions; the recommended priority is after instruction faults/illegal instruction and before data faults, but the choice must be encoded and tested.

`mtval` behavior must be specified. The minimum acceptable behavior is zero for an FT fault; retaining the faulting instruction PC in the normal `mepc` path is mandatory.

### 7.2 Interrupts

An interrupt must not preempt an instruction while its FT retry/recompute transaction is active. Gate the existing `InstrValidM`/interrupt-take point or otherwise prevent the instruction from reaching the interrupt sampling point until FT resolves. Once the instruction is confirmed or the unresolved exception is taken, restore normal interrupt sampling. Do not alter Wally’s `CommittedM`/`CommittedF` bus-commit rules.

### 7.3 Diagnostic CSR

Expose sticky, machine-readable diagnosis state only after the CSR address and privilege implementation is agreed. Wally currently dispatches CSR reads through `csr.sv` into `csrm/csrs/csru/csrc`; merely adding wires in the FT block will not create a readable CSR.

Requirements for the eventual diagnostic CSR:

* use a machine custom CSR address in the `0x7C0–0x7FF` range not claimed by this tree;
* reads from S/U must be rejected by the existing CSR privilege decoder, and writes must be rejected as read-only;
* expose sticky isolated/unresolved bits for ALU, CMP, and MUL, with reset semantics documented;
* do not expose transient comparator outputs as architectural state unless explicitly required;
* do not use a CSR write as the mechanism for clearing a permanent isolation bit unless a future safety review approves it.

## 8. ECC interface contract for this phase

ECC implementation is out of scope, and the assumed source is the
`sai-ecc-csrhardening` branch described in §3A.5. Do not implement ECC encode/decode,
ECC-protected storage, or ECC fault handling as part of the shadow pipeline.

The shadow RTL shall reserve—but tie off—the following integration signals:

| Reserved signal | Branch meaning | Shadow-pipeline behavior now |
|---|---|---|
| `ecc_inject_en` | Test/DFT injection enable | Drive `0` |
| `RegEccSecErrW` | Correctable ECC error aggregate at W | Leave disconnected from FT; optionally observe in ECC-only diagnostics |
| `RegEccDedErrW` | Uncorrectable ECC error aggregate at W | Leave owned by the ECC path; do not use as an E-stage FT input |
| `PrivModeUncorrectableFaultW` | Uncorrectable privilege-mode TMR fault | Leave owned by CSR hardening; do not OR into FT fault status |

The earlier draft’s `EccFaultAE`, `EccFaultBE`, and `EccFaultRegfileE` ports are not
part of this assumed branch interface and must not be invented. In particular, a W-stage
aggregate cannot suppress an E-stage result without an explicit stage-alignment contract.
ECC status must not increment FT mismatch counters, select a survivor, or convert an FT
match into an FT diagnosis. Future work may add a dedicated ECC-to-FT adapter once the
ECC branch provides a valid-aligned operand/storage fault contract.

## 9. RTL-level requirements checklist

The implementation is complete only when all of the following are true:

1. `alu.sv` is duplicated at its actual module boundary, and both `ALUResult` and `Sum` are compared under the same valid/control transaction.
2. `comparator.sv` is duplicated independently; branch resolution uses only checked `FlagsE`.
3. `mul.sv` is duplicated with matching PP register timing; full products are compared in M before result slicing.
4. Divider, FPU (absent in the target), AMO ALU, register file, caches, and ECC remain outside this change unless separately enabled by an explicit future feature.
5. Retry/recompute state is per FU, parameterized, reset/flush-safe, and holds the complete transaction.
6. The controller’s `StructuralStallD`/forwarding logic and hazard’s global stall chain both reflect FT pending state; no unconfirmed result can be forwarded.
7. LSU, IFU, CSR, register-file writeback, and branch redirect side effects are gated until confirmation.
8. An unresolved fault reaches Wally’s existing M-stage trap machinery precisely, with a documented custom cause and priority.
9. Interrupts are deferred during retry/recompute without changing normal committed-bus behavior.
10. Assertions and directed tests cover every supported ALUSelect mode, branch flag, address-generation use, MUL result type, W64 behavior, flush, load-use dependency, divider coexistence, branch redirect, load/store, CSR, interrupt, and unresolved fault.
11. The `sai-ecc-csrhardening`-compatible hooks are present only as structural tie-offs:
    `ecc_inject_en=0`, no ECC status feeds FT control, and no invented E-stage ECC fault
    ports are used.

## 10. Resolved design questions and remaining decisions

Resolved from this RTL:

* The initial boundary is module-level DMR, not a five-way split: `alu.sv` is monolithic from the integration point of view, even though it contains internal subfunctions.
* CMP is structurally independent and has no subtraction-based recompute relation.
* MUL has one registered E→M stage; DIV is iterative and already stalls with `DivBusyE`.
* AMO operations use `lsu/amoalu.sv` in M and are not covered by IEU ALU shadowing.
* Forwarding controls belong in `ieu/controller.sv`, while stage stall propagation belongs in `hazard.sv`.
* The checked-in target is integer-only: `F_SUPPORTED=0`, `D_SUPPORTED=0`, `Q_SUPPORTED=0`, and `IDIV_ON_FPU=0`; integer division uses `mdu/div.sv`.
* Linux-relevant atomics are enabled (`ZAAMO_SUPPORTED=1`, `ZALRSC_SUPPORTED=1`), while PLIC, PMP, branch prediction, vectored interrupts, and optional deeper virtual-memory extensions are disabled in `pkg/config.vh`.
* The assumed ECC branch interface is known: `ecc_inject_en`, `RegEccSecErrW`,
  `RegEccDedErrW`, and `PrivModeUncorrectableFaultW`; all are outside FT control for this
  phase and are disconnected or tied low as specified in §3A.5 and §8.

Decisions required before coding the integration patch:

1. Exact supported ALU opcode/mode set for algebraic recompute versus retry-then-trap.
2. Exact custom exception encoding within Wally’s 5-bit `CauseM` path and its priority.
3. Exact custom diagnostic CSR address and whether sticky state is reset-only or has an approved machine-mode clear operation.
4. Whether the project wants AMO protection in a subsequent, separate M-stage checker.

These are the only intentional open questions. They must be recorded in the implementation change and test plan rather than guessed by a coding agent.

## 11. Verification and measurement

Add fault-injection hooks or testbench force points at each primary/shadow output and at the shared operands. Demonstrate detection of a single-copy fault, correct survivor selection where a valid recompute relation exists, unresolved trapping where it does not, and no false detection from normal Wally stalls/flushes.

Measure and document actual latency in this RTL:

* normal ALU/CMP path;
* one TE retry;
* PE recompute and resume;
* MUL retry, including its PP register cycle; and
* unresolved trap entry.

Do not reuse cycle counts from the SHAKTI-F paper. Run lint and the Linux boot/simulation regressions with the checked-in integer-only `pkg/config.vh`; do not compile against the stock `third_party/cvw/config/rv64gc/config.vh`, which enables F/D and has materially different optional-extension and memory/peripheral settings.
