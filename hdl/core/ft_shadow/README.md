# Shadow execution pipeline

This directory adds result-path DMR to the integer ALU, branch comparator, and
integer multiply/divide unit.  It is a fault **detection and containment** mechanism:
both replicas receive the same architectural inputs, their outputs are
compared before use, and a mismatch holds the original instruction.  Only
ordinary XLEN addition has a diagnostic relation sufficient to identify one
bad replica.  CMP and MUL persistent mismatches trap rather than guessing.

## Hierarchy and architectural boundary

```text
wallypipelinedsoc
  `- wallypipelinedcore
       FTStall = FTStallE | FTStallM ------> hazard: stalls F/D/E/M/W
       FTUnresolvedM ----------------------> trap: synchronous cause 16
       FTStatusSticky ---------------------> mftstatus CSR 0x7c0
       |- ieu
       |    |- controller: suppresses PCSrcE while FTStall is high
       |    `- datapath (E stage)
       |         |- ft_cmp -> FlagsE -> branch decision
       |         `- ft_alu -> ALUResultE, IEUAdrE -> result/address path
       `- mdu (M-stage result checking)
            `- ft_mul -> ProdM -> normal MDU result selection
            `- ft_div -> QuotM/RemM -> normal MDU result selection
```

The wrappers do not change instruction encodings, forwarding, register-file
writeback, or normal single-cycle timing when replicas agree.  A mismatch is
combinationally visible before its controller state changes, so the hazard
unit freezes the whole pipeline before the result, address, or branch decision
can advance.

## Common controller: `ft_shadow_ctrl`

`ft_shadow_ctrl` owns the retry FSM used by ALU, CMP, and MUL. `ft_div` has a
separate controller because retry requires resetting and rerunning multi-cycle
divider FSMs rather than resampling a held combinational result.

| State | `stall_req` | Meaning / next state |
| --- | --- | --- |
| `NORMAL` | asserted when `valid && mismatch` | First observed mismatch records count 1 and enters `RETRY` (or escalates when threshold is 1). |
| `RETRY` | asserted while mismatch persists | The held operation is sampled again. A matching retry returns to `NORMAL`; the `TE_THRESHOLD`-th consecutive mismatch escalates. |
| `RECOMPUTE` | always asserted | One diagnostic cycle for a wrapper-provided independent relation. Exactly one replica must pass. |
| `ISOLATED` | deasserted | The diagnosed-good replica is selected for subsequent operations until reset/flush. |
| `UNRESOLVED` | deasserted | One cycle pulse. The operation is released so the normal M-stage trap path captures it. |

`TE_THRESHOLD` defaults to 3.  Thus a persistent mismatch is sampled in
`NORMAL` plus two `RETRY` cycles before escalation.  `flush` or `reset` clears
the count, replica selection, and `pe_primary`/`pe_shadow`.  `pe_primary=1`
means primary was diagnosed bad; `use_shadow=1` then selects shadow.

`unresolved` is intentionally not a stall: outputs are masked in the wrapper,
then the same instruction advances exactly once to the standard trap logic.

## `ft_alu`: E-stage ALU and address protection

`ft_alu` duplicates Wally's `alu #(P)` and compares both `ALUResult` **and**
`Sum`.  `Sum` matters because it drives `IEUAdrE`, including load/store
addresses.  While retrying or unresolved, both public outputs are zeroed; the
global stall prevents those zeros from becoming architectural state.

### Recompute/isolation relation

Only an ordinary full-XLEN add is eligible:

```text
valid && !W64 && !SubArith && !BMUActive && ALUSelect == 3'b000
```

On escalation, the wrapper changes the duplicate ALU inputs for one cycle:

```text
normal:    r = A + B
recompute: r' = (-A) + (~B) = ~(A + B)
```

It saved each replica's first mismatching normal `{ALUResult, Sum}`.  In the
recompute cycle it tests each replica independently against the complement of
its own saved value.  One passing relation identifies the other replica as
bad; both-pass and both-fail are ambiguous and become `UNRESOLVED`.

This relation is deliberately not used for subtraction, RV64 W operations,
or bit-manipulation operations.  A persistent eligible-ALU fault therefore
costs threshold retry cycles plus one recompute cycle, then enters `ISOLATED`
without a trap.  A transient fault that disappears during retry has no
architectural effect beyond stall cycles.

## `ft_cmp`: E-stage branch comparison

`ft_cmp` duplicates `comparator` and compares `{eq, lt}` before those flags
reach the IEU branch controller.  It is valid for every E-stage instruction;
non-branch compares normally agree and add no latency.

There is no recompute relation today (`recompute_supported=0`).  A transient
mismatch retries and completes.  A persistent mismatch becomes `unresolved`,
masks `flags` to zero, and takes the custom trap.  It never sets a PE bit or
arbitrarily selects a replica.

Future isolation options are a fully proved swapped-operand relation
(`lt(a,b) = !lt(b,a) && !eq(a,b)`) across signed/unsigned cases, or a third,
structurally diverse comparator.  Do not enable either without exhaustive
relation and flush/stall verification.

## `ft_mul`: M-stage multiplier protection

`ft_mul` replaces only Wally's integer `mul`; division remains unchanged.  It
duplicates the normal multiplier and compares its complete `2*XLEN` product in
M.  The wrapper preserves the original E-to-M partial-product register timing.

The wrapper saves `{ForwardedSrcAE, ForwardedSrcBE, Funct3E}` when the MUL
launches.  On a mismatch it asserts `replay_load`.  `replay_load` bypasses the
architectural `StallM` only for the two internal multiplier instances,
reloading their partial-product registers from the saved transaction while the
rest of the CPU remains frozen.  This is why MUL may retry safely despite
detection occurring in M.

MUL has no supported isolation relation.  The signedness/high-half variants
`MUL`, `MULH`, `MULHSU`, and `MULHU` make a simple negate-and-compare rule
unsound, particularly around signed minimum and unsigned operands.  Persistent
mismatch therefore becomes `unresolved` in M and traps.  Candidate future
designs are a per-`Funct3` proved relation, a residue checker, or a diverse
third multiplier.

## `ft_div`: iterative divider protection

`ft_div` replaces Wally's integer `div` when `M_SUPPORTED=1` and integer
division is not routed to the FPU. It instantiates two complete restoring
divider FSMs and compares both `QuotM` and `RemM` when the held `IntDivE`
operation reaches `DONE`. Comparing both catches a result-path fault whether
`Funct3M` later selects DIV, DIVU, REM, or REMU.

Normal divide latency and `DivBusyE` behavior are unchanged: both FSMs run in
E and retain the normal divider stall. On a completed mismatch, `ft_div`
asserts the M-stage FT stall, resets only its two private FSMs, and restarts
the unchanged E-stage transaction while the CPU remains frozen. Matching retry
outputs are released normally. A persistent mismatch after `TE_THRESHOLD`
completed attempts produces `unresolved`, masks quotient and remainder, and
takes the standard cause-16 trap.

DIV has no supported isolation relation and never sets `DIV_PE_*`. Both copies
use the same restoring algorithm, so DMR does not cover shared operand/control/
clock errors or symmetric algorithmic bugs. Future isolation requires a proved
quotient/remainder invariant, residue checker, or structurally diverse divider.

## Test-only injection: `ft_fault_inject`

`ft_fault_inject` sits after an individual replica output and before the DMR
comparison.  With `FAULT_INJECT=0` (all production instantiations), it
elaborates to `data_o = data_i`; it adds no functional fault source.  The
standalone `hvl/ft_shadow` testbench sets the parameter to 1.

| Signal | Semantics |
| --- | --- |
| `fi_enable` | Applies a combinational fault for as long as asserted. |
| `fi_target[0]`, `fi_target[1]` | Select primary and shadow respectively; `2'b11` faults both and demonstrates DMR's common-mode limitation. |
| `fi_kind` | `00` XOR selected bit; `01` stuck-at-0; `10` stuck-at-1; `11` no-op/reserved. |
| `fi_bit` | Index inside the injected output. |
| `fi_channel` | ALU: 0=`ALUResult`, 1=`Sum`; DIV: 0=`QuotM`, 1=`RemM`. |

Injection never modifies shared operands, control, valid, flush, pipeline
state, or controller state.  A one-cycle injection is transient; holding it
through retry/recompute models a persistent output fault.  Use stuck-at, not a
persistent XOR mask, for ALU isolation testing: XOR commutes with the ALU
complement relation and can evade diagnosis.

## Signals outside the wrappers

| Signal | Source -> destination | Semantics |
| --- | --- | --- |
| `FTStallE` | `datapath` -> core | OR of ALU/CMP `stall_req`. |
| `FTStallM` | `mdu` -> core -> `ieu` | OR of MUL/DIV `stall_req`; also suppresses younger E-stage redirects. |
| `FTStall` | core -> `hazard` | OR of E/M requests; added to `StallWCause`, using normal backward propagation to stall all stages. |
| `FTUnresolvedE` | `datapath` -> core | OR of ALU/CMP unresolved pulse. Registered into M with the held instruction. |
| `MDUUnresolvedM` | `mdu` -> core | OR of MUL/DIV unresolved pulses, already M-aligned. |
| `FTUnresolvedM` | core -> `privileged/trap` | `FTUnresolvedEReg OR MDUUnresolvedM`; synchronous fault input. |
| `ALU_PE_*`, `CMP_PE_*`, `MUL_PE_*`, `DIV_PE_*` | wrappers -> core | Sticky-until-flush/reset local isolation diagnosis; folded into status CSR. CMP/MUL/DIV are zero with current detect-and-trap policy. |

The IEU controller gates `PCSrcE` with `~FTStall`.  This prevents a branch or
jump from redirecting fetch while its compare/address result is untrusted,
including when an older multiply is replaying in M.

## Trap and CSR behavior

An unresolved wrapper result is converted into a normal precise exception:

```text
E ALU/CMP unresolved --(E->M register)--> FTUnresolvedM --+
M MUL/DIV unresolved --------------------------------------+-> trap ExceptionM
                                                            -> mcause = 16
```

Cause 16 is custom and machine-only: `trap.sv` excludes causes with bit 4 set
from standard `medeleg` handling.  Normal trap flush/MEPC/MTVAL machinery is
used; no separate FT trap pipeline exists.

`mftstatus` is a custom machine read-only CSR at `0x7c0`.  Its reset-sticky
bits are:

```text
[6] shadow unresolved   [5] ECC DED   [4] ECC SEC
[3] DIV isolated         [2] MUL isolated  [1] CMP isolated  [0] ALU isolated
```

The live status is ORed into `FTStatusSticky` every cycle and only reset clears
it.  A write to `mftstatus` is rejected as a read-only CSR access.  The CSR is
diagnostic only; reading it cannot clear a fault or release a stalled
instruction.

## ECC hook: current state and required future connection

The interface shape follows the `sai-ecc-csrhardening` work, but this branch
does **not** include ECC-protected storage or an ECC injection port.
`RegEccSecErrW` and `RegEccDedErrW` are currently tied to zero; consequently
`mftstatus[5:4]` always read zero.

When the hardening RTL is merged, retain this timing contract:

1. Add and route an ECC test/DFT injection enable only with the hardening
   storage implementation, to its selected register-file and ECC-protected
   pipeline-flop injection points. Do not route it to shadow FU injectors.
2. Aggregate corrected SEC and detected DED indications in W as one-cycle
   `RegEccSecErrW`/`RegEccDedErrW` events.  The existing core logic latches
   them into `mftstatus` on that cycle.
3. Keep ECC status independent of `FTStall`: ECC is a storage-integrity path,
   not an E/M recomputation request.  A corrected SEC may retire normally.
4. Before connecting DED, choose and implement one architectural policy.  The
   hardening branch's intended DED path is an uncorrectable-fault/NMI-or-reset
   action; the current branch only records DED in `mftstatus`.  Do not silently
   treat a DED as a recoverable shadow mismatch or permit corrupted W data to
   commit.

The hardening branch may also change `mftstatus` from read-only to W1C.  That
is a CSR-policy change and must be reconciled explicitly with the current
read-only implementation before merging.

## Shadow-related delta from `main`

| Area | Change and CPU effect |
| --- | --- |
| `ft_shadow/` | Adds controller and E/M wrappers; current working tree also adds injector and direct fault TB. |
| `ieu/datapath`, `ieu/ieu`, `ieu/controller` | Replaces native ALU/comparator with wrappers, exports E-stage FT status, and suppresses redirect while validation stalls. |
| `mdu/mdu` | Replaces native MUL and iterative DIV with redundant wrappers; DIV retry restarts its private FSMs. |
| `hazard` | Treats `FTStall` as a whole-pipeline stall. |
| `wallypipelinedcore`, `privileged/{trap,csr,csrm,privileged}` | Aligns unresolved faults to M, raises cause 16, and exposes sticky diagnostics at `0x7c0`. |
| `wallypipelinedsoc`, `amoalu` | Adds an AMO-protection TODO; AMO operations are not shadow-protected. ECC status placeholders remain in core, but no ECC injection port exists. |

### Ancillary branch deltas

The remaining changes relative to `main` do not alter shadow timing:

| Area | Effect |
| --- | --- |
| `pkg/amoeba_config_select.vh`, `config_{baremetal_linux,freertos,freertos_keystone}.vh` | Adds selectable configurations.  The minimal Linux configuration has `ZMMUL_SUPPORTED=1`, F/D disabled, and a reduced peripheral/extension set; this changes elaborated hardware only when selected. |
| `options.json`, `sim/Makefile`, `bin/rvfi_reference.py` | Makes the simulation/RVFI harness support an F-disabled interface; no integer core datapath behavior changes. |
| `testcode/linux/configs/linux_amoeba.config`, `testcode/linux/dts/amoeba.dts` | Makes Linux advertise and use the minimal non-F/D, no-PLIC hardware; affects boot software and the device description, not shadow RTL. |
| `.codex/shadow_pipeline_plan.md`, `.gitignore` | Planning and repository hygiene only; no hardware behavior. |

The active configuration must have `ZMMUL_SUPPORTED` for `ft_mul` to
instantiate. `ft_div` is active only when `M_SUPPORTED=1` and `IDIV_ON_FPU=0`;
an FPU-routed integer divider remains outside this scope. Disabling F/D does
not alter the integer shadow design.
