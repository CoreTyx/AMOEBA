# Fault-tolerant integer execution and verification

The integer arithmetic, comparison, multiplication, and division paths use two
copies of each computation. A **replica** is one such copy: replica 0 is called
primary and replica 1 is called shadow. The hardware compares their results,
holds the pipeline when they disagree, and retries the operation. For supported
ALU and comparison operations, an additional computation can identify which
replica to use. If recovery cannot establish a usable result, the processor
raises a machine-mode exception with cause 16.

**FT** abbreviates fault tolerance. The **ALU** is the arithmetic and logic unit;
**CMP** denotes the independent register comparison. **ECC** means error-correcting
code for protected storage. A **CSR** is a software-accessible control and status
register. **ISA** means instruction set architecture, and **SoC** means the
system-on-chip containing the processor and its connected hardware.

The implementation is in `hdl/core`. `hdl/cvw` is the upstream reference tree.
The processor configuration is [pkg/config.vh](../../../pkg/config.vh), currently
with 64-bit integer registers and the dedicated integer divider enabled.
**XLEN** means the integer register width. A **word operation** computes a 32-bit
result; a **doubleword operation** computes a 64-bit result. On the 64-bit
processor, instructions such as ADDW and SRAW sign-extend their word result to
64 bits. This is distinct from building a processor with 32-bit registers.

## Testing strategy

Verification has three levels. Direct module tests check arithmetic and recovery
in detail. A processor test checks how recovery interacts with real instructions,
pipeline control, traps, and status registers. Software regressions and Linux
boot check longer execution with the normal memory system and test harness.
These levels have different configurations and do not imply the same coverage.

| Test entry point | Hardware under test | Stimulus and pass criterion |
| --- | --- | --- |
| `ft_shadow_regression` | Standalone `ft_alu`, `ft_mul`, `ft_div`, and two additional injectors | Directly supplied operands/control signals; expected results and recovery signals checked inside the testbench |
| `ft_core_test` | 64-bit processor and SoC through `rv64_core_wrapper` | Short machine-code programs in testbench read-only memory (ROM); checks completed instructions, pipeline holds, traps, and CSR reads |
| `isa_regression` | Processor using `pkg/config.vh` | Existing ISA-level software tests; each program reports success or failure through `tohost` |
| `ecc_baremetal_regression` | Processor with the shared fault-injection input enabled | Programs that run without an operating system and check their results; each reports through `tohost` |
| `linux_boot` | Processor with fault injection disabled | Boots the Linux image and waits for the configured success message on the UART serial console |
| `linux_boot_ecc_inject` | Processor with both execution-result and storage-ECC injection enabled | Same Linux boot criterion, with the hardware-generated injection events active |

### Do the testbenches test both RV32 and RV64 ISAs?

The standalone testbench tests **32-bit and 64-bit versions of the arithmetic
modules**. It does not fetch or decode instructions and does not instantiate a
processor. Consequently, these runs are not RV32/RV64 instruction-set compliance
tests. The two widths check parameter sizing, arithmetic boundaries, extension,
and truncation in the reusable modules.

The processor testbench instantiates the **64-bit processor only**. It executes
actual instructions, but its short programs cover the fault-recovery scenarios
listed below, not the complete ISA. The separate ISA-level software regression
also uses the processor configuration in `pkg/config.vh`; the standalone
32-bit module run does not turn it into a 32-bit processor regression.

Word instructions on the 64-bit processor are a separate subject. The standalone
64-bit ALU tests include word shifts, word rotations, and sign extension, as well
as doubleword operations. Testing these word operations does not require an
RV32 processor.

### What are the six configurations?

[sim/Makefile](../../../sim/Makefile), target `ft_shadow_regression`, runs the
standalone testbench once for each pair below:

| `FT_XLEN` → testbench `TEST_XLEN` | `FT_THRESHOLD` → testbench `THRESHOLD` → module `TE_THRESHOLD` |
| --- | --- |
| 32 | 1 |
| 32 | 2 |
| 32 | 3 |
| 64 | 1 |
| 64 | 2 |
| 64 | 3 |

Thus there are **two module widths × three mismatch thresholds = six runs**.
These are not six processor builds or six Linux boots. All six use the same
standalone testbench and its local extension settings described below.

`TE_THRESHOLD` is the number of consecutive mismatching observations allowed
before escalation. The initial mismatch counts as observation one. Threshold 1
allows no ordinary retry before diagnosis or an unresolved fault; threshold 2
allows one further mismatching observation; threshold 3 allows two. Divider
observations are completed division attempts, not individual iteration clocks.
The processor instances use the module default of 3. A single
`ft_shadow_test` invocation defaults to width 64 and threshold 2 unless overridden.

### Where and why are Zba, Zbb, and Zbkb enabled?

At the top of
[ft_recompute_fault_tb.sv](../../../hvl/ft_shadow/ft_recompute_fault_tb.sv),
`test_config()` copies the configuration structure and changes these fields:

```systemverilog
changed.XLEN = TEST_XLEN;
changed.LOG_XLEN = $clog2(TEST_XLEN);
changed.ZBA_SUPPORTED = 1;
changed.ZBB_SUPPORTED = 1;
changed.ZBKB_SUPPORTED = 1;
```

The returned structure is named `TP` and is passed to the standalone `ft_alu`,
`ft_mul`, and `ft_div` instances. These assignments do not modify `pkg/config.vh`
or the configuration used by the processor and Linux tests.

Zba provides operations including SLLI.UW. Zbb provides operations including
min/max and rotations. Zbkb also enables shared rotation hardware. Enabling
these options in the standalone test allows its ALU control inputs to select
those arithmetic paths, even though these three options are currently disabled
in the processor configuration. This checks that the protection logic works
with these optional ALU operations. It does **not** verify their instruction
decoding, all instructions in these extensions, or every combination of extension
settings. All three options are enabled together in this test.

### Standalone module testbench

[ft_recompute_fault_tb.sv](../../../hvl/ft_shadow/ft_recompute_fault_tb.sv)
provides its own clock, reset, operands, operation controls, and instruction-valid
signal. It directly instantiates the three protected execution modules; there
is no instruction memory, decoder, register file, processor pipeline, or trap
handler. Its `check()` task stops simulation with `$fatal` on a failed condition.
A successful run prints `PASS ft_recompute_fault_tb` with its width, threshold,
and check count. A timeout also fails the run.

Expected arithmetic results use separate SystemVerilog expressions, including
`==`, signed/unsigned `<`, addition, subtraction, shifts, and rotation expressions.
They do not reuse the tested hardware's subtraction sign bit as the comparison reference.
The operand set includes zero, one, all ones, signed limits, word boundaries,
and a mixed-bit pattern.

The checks cover:

- ADD/SUB, signed and unsigned comparison, SLT/SLTU, and signed/unsigned min/max
  over pairs of the nine operand patterns, including subtraction overflow cases.
- SLL/SRL/SRA at every legal shift amount, with the operand patterns above.
  The 64-bit build also checks word-result sign extension, five-bit word shift
  amount masking, and SLLI.UW zero extension before shifting. Register and
  immediate instructions share these arithmetic paths; this test supplies
  controls directly and does not test their distinct instruction encodings.
- Rotations at every legal shift amount, including word rotations in the
  64-bit build. Rotation recovery uses retry and unresolved reporting, not the
  shift diagnostic relation.
- Transient faults on both replicas and all four ALU/comparison injection sites;
  persistent faults in selected result, arithmetic, shift, and comparison bits;
  correct replica selection and its indicators; and output masking during recovery.
- Shift faults at every shift amount, on both replicas, at selected low and
  high boundary bits. SLLI.UW has an additional low-bit fault sweep in the
  64-bit build. This is not an exhaustive test of every bit/operand/fault combination.
- Independent ALU and comparison recovery: either controller can isolate a
  replica first, then the other can recover and select the opposite replica.
- First-mismatch capture timing and preservation of the captured values across
  retries, including a fault whose value changes during retry; reset, flush,
  invalid instructions, and subsequent operations.
- Ambiguous diagnoses where both replicas pass or both fail; unsupported
  recovery examples such as persistent ROR and word SUBW faults; an arithmetic
  disagreement during shift diagnosis; and unresolved faults held until acceptance.
- Multiplier recovery using `13 * 11`, with transient and persistent faults on
  either product replica. Divider recovery using unsigned `100 / 7`, with
  faults in the primary quotient and shadow remainder. Divider inputs are
  removed after launch to check that retries use saved operands. These focused
  recovery cases do not exhaust signed division, word division, or multiplication
  variants. At threshold 1, a sampled MUL/DIV mismatch is unresolved without retry.

Most recovery tests use SystemVerilog `force` to set an injector's private event,
bit index, and fault kind. Holding these settings produces a repeatable persistent
fault; removing them produces a transient fault. They are testbench controls,
not processor input ports. The standalone tests check the module's `unresolved`
output; only the processor test below checks that it becomes a real exception.

Two additional `ft_fault_inject` instances run without forced internals. The
bench checks disabled pass-through for 1,024 clocks, then 16,384 enabled clocks:
512-clock event spacing, staggered events between the two instances, fault-kind
coverage, at most one changed bit per output, out-of-range index handling, and
seed restoration on reset. This samples the actual injection generator; it does
not exhaust its entire sequence or every injector combination in the processor.

### Processor integration testbench

[ft_core_fault_tb.sv](../../../hvl/ft_shadow/ft_core_fault_tb.sv) instantiates
`rv64_core_wrapper`, including the SoC and processor. It supplies a 256-entry
ROM of 32-bit instruction words at address `0x80000000`. Its memory responder
immediately acknowledges requests and returns ROM data; it is not a general
read/write RAM or a variable-latency memory model. The programs and exception
handler are encoded directly in the testbench. This test has no Spike or DPI
co-simulation dependency.

The bench watches the processor's instruction-completion outputs
(`monitor_valid`, PC, destination register/value, and trap indication). It records
register writes and counts completed branches and traps, then compares them with
the expected program result. The exception handler reads `mcause`, `mepc`, and
`mftstatus`, so the test checks the software-visible trap and status path.

The `ft_core_test` Makefile target copies `pkg/config.vh` into its build directory
and sets `BPRED_SUPPORTED=1` in that copy. Other configuration values remain from
`pkg/config.vh`; the FT modules use threshold 3. Enabling branch prediction here
allows faults to be tested after loop branches have been trained as taken.
It does not enable prediction for the ordinary software or Linux builds.

Each of the following 21 scenarios starts from reset:

| Scenario ID | Behavior checked |
| --- | --- |
| 0 | Healthy branch loop and expected register result |
| 1–2 | ALU-result isolation and comparison isolation, respectively |
| 3–4 | Unresolved BNE and BGE comparisons produce cause-16 traps |
| 5 | Transient ALU-result fault recovers |
| 6 | Fault in the extended address arithmetic is isolated |
| 7–8 | Persistent multiplier fault traps; transient multiplier fault recovers |
| 9–11 | Persistent quotient fault traps; transient division fault recovers; persistent remainder fault traps |
| 12–15 | Comparison, ALU, MUL, and DIV terminal faults survive an external pipeline hold after injection is removed, then produce one precise trap |
| 16 | Shared `fault_inject` input drives the actual FT and ECC injectors; 1,024 loop branches complete correctly, recovery stalls occur, no trap occurs, and ECC correction is recorded in MSECFAULT rather than MFTSTATUS |
| 17–18 | Quotient/remainder injection after the division has entered M cannot change its already-accepted result |
| 19–20 | The same late quotient/remainder injection while M is held for additional cycles |

Directed scenarios force private injector controls. Scenario 16 releases those
forces and enables the real injection generators. The pipeline-delay scenarios
force `ExternalStall`, which holds the pipeline; they do not model a particular
cache miss or bus transaction.

During FT stalls the bench checks the held execute PC, all five stage-stall
signals, suppression of branch redirection and execute flushing, and absence of
instruction completion. It checks simultaneous branch-target and register
comparison calculations, including predicted-taken branches. Trap cases check
one cause-16 exception, the PC of the faulting instruction, suppression of the
normal program result, and sticky status read by the handler. Recovery cases
check the final arithmetic/program result and status without a trap.

A separate `hazard` instance in this testbench directly checks that older CSR,
return, and trap flush requests take priority over an FT stall, including the
interrupted-WFI case. These are direct hazard-control checks; they do not mean
all of those instructions execute in the processor programs above.

Each scenario prints a `PASS core scenario=...` line. The final success line is
`PASS ft_core_fault_tb`. A failed check or scenario timeout stops the simulation.

### Software tests, Linux, and CI

The software targets use the common processor harness in
[top_tb.svh](../../../hvl/common/top_tb.svh), rather than either FT testbench.
This harness loads a program image through `simple_memory_w_mask` in
[masked_memory.sv](../../../hvl/common/masked_memory.sv), connected to the
processor's external memory interface. `ECE411_SIM_INJECT` makes it drive
`fault_inject=1`; without that build define it drives zero.

`isa_regression` runs the existing programs in
[testcode/isa_level_testing](../../../testcode/isa_level_testing) with injection
disabled. `ecc_baremetal_regression` runs
[testcode/baremetal_ecc](../../../testcode/baremetal_ecc) with injection enabled.
Despite the `ecc` target name, the shared input enables both ECC storage
injection and FT execution-result injection. Program success is reported through
`tohost`, the test harness's software-to-simulator completion interface.

The Linux targets use `testcode/linux/build/boot.lst`. The default success marker
is `AMOEBA_LINUX_BOOT_OK` on the UART. Kernel panic, Oops, other configured failure
messages, or timeout fail the run. `LINUX_PASS` can select an earlier milestone;
a run with an earlier marker only verifies reaching that milestone. Linux with
injection enabled exercises naturally scheduled transient events, not directed
persistent faults or every possible bit position.

[ci.yml](../../../.github/workflows/ci.yml) runs all six standalone width/threshold
pairs and the 21-scenario processor test in `ci-ft-shadow`. It also contains the
software/ECC regressions and Linux boot with injection enabled.
[linux-boot.yml](../../../.github/workflows/linux-boot.yml) provides Linux boot
with injection disabled. The separate `ecc_secded_dected_test` and
`csr_harden_test` targets check ECC coding and privilege/security error handling;
they are not substitutes for the FT processor trap/status tests.

Run from the repository root with the repository's simulation and software-build
dependencies installed:

```sh
# All six standalone module runs.
make -C sim ft_shadow_regression

# One standalone run at the processor's width and default threshold.
make -C sim ft_shadow_test FT_XLEN=64 FT_THRESHOLD=3

# Processor programs and pipeline/trap/status checks.
make -C sim ft_core_test

# Software and operating-system execution.
make -C sim isa_regression
make -C sim ecc_baremetal_regression
make -C sim linux_boot
make -C sim linux_boot_ecc_inject
```

The standalone build uses `-Wall -Wno-fatal`: warnings are reported but do not
fail the build. Processor simulations use
[verilator_warn.vlt](../../../sim/verilator_warn.vlt), which suppresses width
warnings under `hdl/core`. A passing simulation therefore does not establish
that all RTL is warning-free. There is no separate FT core lint test.

## Processor structure and signal paths

The processor has five stages: F fetches instructions, D decodes them, E executes
them, M handles memory access and exceptions, and W writes results back to the
register file. Signal suffixes such as `E` and `M` identify these stages.
**IEU** is the integer execution unit; **MDU** is the multiply/divide unit.

The instance hierarchy below shows the shared injection enable. Module names
are in parentheses where they differ from the instance name.

```text
rv64_core_wrapper.fault_inject
  soc (wallypipelinedsoc).fault_inject
    core (wallypipelinedcore).fault_inject
      ieu.fault_inject
        dp (datapath).fault_inject
          ftalu (ft_alu).fi_enable
            replica[0/1].compute (alu)
            replica[0/1].compare (addsub)
            alu_ctrl and cmp_ctrl (ft_shadow_ctrl)
          regf (regfile).inject_en
          seven ECC pipeline registers: injection-enable inputs
      mdu.mdu (mdu).fault_inject
        ftmul (ft_mul).fi_enable
        div.ftdiv (ft_div).fi_enable
```

The repeated `mdu.mdu` names denote a conditional hierarchy scope followed by the
MDU instance. The divider path shown is the dedicated integer divider used by
the current configuration. Configurations that use the floating-point divider
for integer division do not use `ft_div`. If an execution unit is omitted by the
processor configuration, its FT status and stall outputs are tied inactive.

### ALU, comparison, and addresses

[datapath.sv](../ieu/datapath.sv) supplies two independent operand pairs to
[ft_alu.sv](ft_alu.sv):

| Inputs | Source and purpose |
| --- | --- |
| `A`, `B` | `SrcAE`, `SrcBE`: multiplexers choose register data or PC/immediate values for arithmetic, addresses, and branch targets |
| `cmp_a`, `cmp_b` | `ForwardedSrcAE`, `ForwardedSrcBE`: register operands, including results forwarded from older instructions that have not yet written the register file |
| `cmp_sgnd` | `BranchSignedE`: chooses signed or unsigned comparison |
| `valid`, `flush`, `advance` | `InstrValidE`, `FlushE`, `~StallM`: identify a valid instruction, discard it on a flush, and acknowledge its transfer into M |

A branch can therefore compute `PC + immediate` and compare two register values
at the same time. Both checks are enabled for every valid execute instruction;
comparison checking is not limited to branch instructions.

| Output | Width and destination |
| --- | --- |
| `ALUResult` | XLEN; becomes `ALUResultE`, passes through the IEU result selection and `IEUResultMReg`, then the writeback path to the register file when that instruction selects an ALU result |
| `Sum` | XLEN; becomes `IEUAdrE`, used by the instruction-fetch unit for branch/jump targets and captured by the load/store unit's `AddressMReg` as `IEUAdrM` on an accepted E-to-M transfer |
| `flags` | Two bits `{eq, lt}`; becomes `FlagsE`, used by the IEU controller to decide whether a branch is taken |
| `stall_req`, `unresolved` | OR of the separate ALU and comparison controller requests; becomes `FTStallE`, `FTUnresolvedE` |
| `pe_primary`, `pe_shadow`, `cmp_pe_primary`, `cmp_pe_shadow` | Indicate which replica each controller has isolated; routed through IEU to the core's status logic |

Inside `ft_alu`, each `alu` instance provides XLEN+1 arithmetic and XLEN+2 shift
results for checking. These extended values, diagnostic controls, and saved
first-mismatch results remain inside `ft_alu`. The datapath/IEU/core interfaces
carry only the result widths listed above. [comparator.sv](../ieu/comparator.sv)
remains available to the atomic-memory ALU and other consumers; architectural
branch comparison uses the subtraction instances inside `ft_alu`.

### Arithmetic and shift diagnosis

[addsub.sv](../generic/addsub.sv) supplies the extended arithmetic used by
[alu.sv](../ieu/alu.sv) and the independent comparison paths. Comparison subtracts
two XLEN+1 operands. Unsigned operands are zero-extended; signed operands are
sign-extended. `eq` tests the complete difference for zero; `lt` is its highest
bit. The extra bit prevents overflow from reversing the ordering. ALU SLT/SLTU
and signed/unsigned Zbb min/max also derive ordering from extended subtraction.

For diagnosis, let `Ae` and `Be` be the already-extended operands. The diagnostic
computation must have the following relation to the saved first-mismatch result,
with arithmetic modulo the extended width:

| Operation | Ordinary computation | Diagnostic computation |
| --- | --- | --- |
| ADD | `Ae + Be` | `~Ae + ~Be + 1`, the complement of the ordinary result |
| SUB/comparison | `Ae - Be` | `~Ae + Be`, the complement of the ordinary result |

Full-width ADD/SUB and SLT/SLTU support this diagnosis. ADD/SUB also check the
architectural result's complement relation. SLT/SLTU check that the selected
Boolean result agrees with the corresponding arithmetic sign bit in both
computations. Word ADDW/SUBW, min/max, rotations, and other operations without a
supported diagnostic relation retry and then report unresolved if disagreement
persists. Their ordinary duplicated execution still checks for disagreement.

[shifter.sv](../ieu/shifter.sv) uses an XLEN+2-bit non-rotate shift result: 66 bits
for a 64-bit datapath and 34 bits for a 32-bit datapath. Word operands are
normalized before shifting; SLLI.UW zero-extends its low 32-bit operand. Diagnosis
displaces the normalized input left by two bits and repeats the same shift.
The check compares ordinary `[XLEN-1:0]` with diagnostic `[XLEN+1:2]`. For word
results it compares ordinary `[31:0]` with diagnostic `[33:2]` before sign
extension. Architectural shift-amount masking is preserved.

Shift injection affects the widened physical result before either slice is
selected, using the same physical bit position in both computations. Diagnosis
also checks consistency with the selected architectural result. An unrelated
arithmetic/address disagreement cannot be resolved by the shift relation.
Rotations use their ordinary word or full-width rotation and do not use the
input-displacement relation.

### Recovery controllers and first-mismatch capture

A **retry** repeats the ordinary computation. A **diagnostic computation** changes
the computation as described above to test each replica independently.
**Isolation** selects the one replica that passes diagnosis. **Unresolved** means
the hardware cannot select a result using its recovery checks.

`ft_alu` has two [ft_shadow_ctrl](ft_shadow_ctrl.sv) instances, `alu_ctrl` and
`cmp_ctrl`. Each has its own state, mismatch counter, and replica selection.
The ALU checker compares both the architectural result and extended arithmetic;
the comparison checker compares the complete extended difference.

On the first valid mismatch, that controller asserts `capture_normal` until the
next clock edge. The edge saves both replicas' ordinary results **after injection,
before output masking and before diagnostic recomputation**. The ALU controller
captures result, arithmetic, and shift values; the comparison controller captures
the differences. These saved values remain unchanged during retries and diagnosis.
They are the reference for each replica's diagnostic relation. Capturing them
again during a retry could replace the original evidence with a different fault
value or a diagnostic result. Reset or execute flush clears them.

A matching retry releases the hold. If mismatches reach `TE_THRESHOLD`, a
supported operation gets one diagnostic cycle. Exactly one passing replica
causes isolation of the other. Both passing or both failing is unresolved.
Isolation lasts until reset or execute flush, and the selected replica supplies
subsequent operations during that interval. The ALU and comparison controllers
may select different replicas, and either can recover while the other is isolated.

Their stall requests are ORed; their unresolved requests are also ORed.
`ALUResult`, `Sum`, and `flags` are all zero while either path stalls or is
unresolved. Thus branch-target arithmetic can be retried or diagnosed by the
ALU controller while the comparison controller independently handles the branch
condition. A comparison fault alone does not start ALU diagnosis.

### Multiplier and divider

[mdu.sv](../mdu/mdu.sv) connects the protected multiplier and dedicated integer
divider to the processor's result selection and writeback registers.

[ft_mul.sv](ft_mul.sv) compares the two full 2×XLEN products in M. It saves the
accepted execute operands and multiplication controls so that a mismatch can
reload the multiplier's private partial-product registers with the same
operation. These internal registers can advance during retry even when the
architectural pipeline is held. A matching retry releases the hold. Persistent
disagreement reaches unresolved at the threshold; MUL has no replica-isolation
diagnosis. Its public product is zero during a recovery hold or unresolved fault.
The MDU selects the instruction's product portion and handles word sign extension.
An M-stage flush clears recovery only when that stage can accept the flush.

[ft_div.sv](ft_div.sv) saves operands, signedness, and word control at launch.
It compares quotient and remainder only after both private divider state machines
finish the execute-stage division. A retry resets and restarts those state
machines using the saved inputs, even if forwarding inputs have since changed.
Its counter counts completed failed attempts. DIV has no replica-isolation
diagnosis; persistent disagreement becomes unresolved.

On the accepted E-to-M transfer, `quotreg` and `remreg` latch the checked quotient
and remainder. They hold through M-stage stalls, so later injector events or a
younger division cannot change the accepted result. An unresolved attempt cannot
load an unchecked value into these registers. The separate `divfaultreg` in the
MDU carries its unresolved indication into M alongside the instruction.

### Pipeline stalling and branch control

The fault-recovery hold follows this path:

```text
ft_alu.stall_req -> datapath -> IEU.FTStallE -----------+
                                                     +-> core.FTStall -> hazard
ft_mul.stall_req --+                                  |
                  +-> MDU.FTStallM -> core.FTStallM ---+
ft_div.stall_req --+
```

Despite the MDU output name `FTStallM`, divider mismatches are detected in E;
multiplier mismatches are detected in M.

[hazard.sv](../hazard/hazard.sv) adds `FTStall` to the W-stage stall cause. Its
normal backward propagation asserts `StallW`, `StallM`, `StallE`, `StallD`, and
`StallF`. Pipeline register enables hold the instructions and data in place;
this does not stop the clock. Recovery controllers and private MUL/DIV retry
logic continue working. Ordinary divider busy cycles use `DivBusyE` to hold E
while older stages can drain; a fault-recovery hold freezes all five stages.

[controller.sv](../ieu/controller.sv) qualifies branch/jump selection `PCSrcE`
with no FT stall and no unresolved E/M fault. The core similarly qualifies
`BPWrongE` before sending prediction-recovery flush requests to the hazard unit.
These gates prevent untrusted branch results or prediction recovery from
redirecting fetch or discarding the instruction being diagnosed.

[bpred.sv](../ifu/bpred/bpred.sv) also drives `BPDirWrongM` to zero when the
optional prediction-performance counters (`ZIHPM_SUPPORTED`) are disabled,
along with the other unused prediction-error reporting outputs. This gives
those status signals defined values in that configuration.

An older M-stage trap, return, or CSR/fence flush takes priority over the FT
stall contribution. This allows older control changes to discard younger work
without waiting for its diagnosis. Independent memory or external stalls can
still delay advancement.

### Unresolved faults and precise traps

Unresolved state releases the FT recovery stall but keeps untrusted outputs
masked. It remains asserted until the relevant stage accepts the instruction;
an unrelated stall cannot make the fault disappear. Faults reach M as follows:

| Detection source | Route to `core.FTUnresolvedM` |
| --- | --- |
| ALU or comparison in E | `ft_alu.unresolved` → datapath/IEU `FTUnresolvedE` → core `FTUnresolvedERegPipe` |
| DIV in E | `ft_div.unresolved` → MDU `divfaultreg` → `MDU.FTUnresolvedM` |
| MUL in M | `ft_mul.unresolved` → `MDU.FTUnresolvedM` |

Both E-to-M fault registers use `~StallM` as their enable and `FlushM` as their
clear. The core ORs the registered ALU/comparison fault with the MDU fault and
passes it to `privileged.FTUnresolvedFaultM`.

[trap.sv](../privileged/trap.sv) treats this as a synchronous exception with
**cause 16**. When selected by the normal trap-priority logic, it enters machine
mode, records the faulting M-stage PC in `mepc`, writes 16 to `mcause` with the
interrupt bit clear, writes zero to `mtval`, and redirects to the `mtvec` base.
Normal trap entry updates privilege/status registers and flushes the faulting
result and younger instructions. The unresolved instruction does not complete
with the masked zero as its normal result. Cause 16 is outside the implemented
16-bit exception-delegation register, so it cannot be delegated to supervisor
mode. Interrupts and the higher-priority instruction faults in `trap.sv` retain
their priority; an unresolved indication is not a promise that cause 16 wins
against every simultaneous event.

### Software-visible status registers

A **CSR** is a control and status register accessed by RISC-V CSR instructions.
The FT feature uses the custom machine-mode CSR **MFTSTATUS (`mftstatus`, address
`0x7c2`)**. `FTStatus` is the internal seven-bit signal feeding this CSR.

The core ORs the two replica-isolation indicators for each execution function,
adds the unresolved M-stage indication, and accumulates these events in
`FTStatusSticky`. Once a bit is set, it remains set until processor reset,
including across pipeline flushes. The signal passes through `privileged` →
`csr` → [csrm.sv](../privileged/csrm.sv) for software reads.

| Bit | Meaning when set |
| --- | --- |
| 0 | The ALU controller has isolated a replica |
| 1 | The comparison controller has isolated a replica |
| 2 | MUL replica isolation; currently remains zero because MUL only retries or reports unresolved |
| 3 | DIV replica isolation; currently remains zero because DIV only retries or reports unresolved |
| 4–5 | Reserved, zero |
| 6 | An unresolved FT fault reached M |
| XLEN−1:7 | Zero |

MFTSTATUS is read-only; attempted writes are illegal CSR accesses. It does not
identify which replica failed, count retries, enable injection, or provide a
software clear. A transient mismatch recovered by ordinary retry sets no FT
status bit. Successful isolation sets the corresponding bit without requiring
a cause-16 trap. Bit 6 records the unresolved indication, independently of which
exception wins trap priority.

**MSECFAULT (`0x7c0`) is separate.** Its bits 4 and 5 record storage-ECC
single-error correction and double-error detection, respectively, alongside its
other security status. Its write-one-to-clear behavior applies to MSECFAULT,
not MFTSTATUS. Storage-ECC uncorrectable errors use the separate cause-19 path.
FT execution events are not added to MSECFAULT.

## Artificial fault injection

The external `fault_inject` input propagates through
[rv64_core_wrapper.sv](../../rv64_core_wrapper.sv),
[wallypipelinedsoc.sv](../wally/wallypipelinedsoc.sv), and
[wallypipelinedcore.sv](../wally/wallypipelinedcore.sv) as shown above. It enables
execution-result injection and storage-ECC injection together. A value of zero
disables artificial corruption; checking and recovery remain active. There is
no CSR or external bit/kind/replica selector for this input.

Each execution injection site uses [ft_fault_inject.sv](ft_fault_inject.sv).
Its 16-bit linear-feedback shift register (LFSR) generates a deterministic
sequence. The low bits select a physical result bit; bits `[15:14]` select the
fault kind. A nine-bit counter schedules a one-clock event every 512 clocks.
Distinct seeds give the sites different event phases.

| Kind | Effect on the selected bit during the event |
| --- | --- |
| `00` | Invert it (XOR) |
| `01` | Force zero |
| `10` | Force one |
| `11` | Leave the result unchanged |

An out-of-range index leaves the result unchanged. Forcing a bit to its existing
value also makes no change. Thus a scheduled event does not always create a
mismatch. The force-zero/force-one kinds last one event clock in normal hardware
operation; a directed test must hold them active to model a persistent fault.
The generator and counter keep running when disabled. Reset restores their seed
and phase and suppresses corruption. The LFSR uses feedback polynomial
`x^16 + x^14 + x^13 + x^11 + 1`.

There are fourteen execution-result injection sites in the current configuration:

| Location | Sites | Width per site |
| --- | --- | --- |
| `ft_alu.replica[0/1].result_fi` | One per ALU replica | XLEN |
| `ft_alu.replica[0/1].arith_fi` | One per ALU replica | XLEN+1 |
| `ft_alu.replica[0/1].shift_fi` | One per ALU replica, before result slicing | XLEN+2 |
| `ft_alu.replica[0/1].cmp_fi` | One per comparison replica | XLEN+1 |
| `ft_mul.primary_fi`, `shadow_fi` | One per product replica | 2×XLEN |
| `ft_div.primary_quot_fi`, `shadow_quot_fi` | One per quotient replica | XLEN |
| `ft_div.primary_rem_fi`, `shadow_rem_fi` | One per remainder replica | XLEN |

The same top-level enable reaches the existing ECC injectors on both integer
register-file read paths and these seven `flopenrc_ecc` instances in `datapath`:

| Register | Stored data |
| --- | --- |
| `RD1EReg`, `RD2EReg` | Register operands entering E |
| `ImmExtEReg` | Extended instruction immediate entering E |
| `SrcAMReg` | Selected first ALU operand entering M |
| `IEUResultMReg` | IEU result entering M |
| `WriteDataMReg` | Store data entering M |
| `IFResultWReg` | Selected integer/floating-point result entering W |

These ECC paths use `ecc_bit_flip` before decoding the protected value. Their
correction/detection indications are aggregated by the datapath and propagated
as `RegEccSecErrW`/`RegEccDedErrW` through privileged CSR logic to MSECFAULT.
They use the existing ECC mechanism, not the FT result-injection generator or
MFTSTATUS. The shared enable does not add injection to every register or memory
in the processor.

## Coverage and protection limits

Agreement between two replicas does not detect identical errors in both.
Diagnosis requires exactly one passing relation; for example, some persistent
XOR faults preserve both complement relations and therefore remain unresolved.
Once a controller isolates a replica, it uses the selected replica until flush
or reset rather than continuing two-replica checking on that path.

The execution injectors model faults on the listed output signals. They do not
model every internal gate, shared operand/control fault, recovery-controller
fault, clock fault, or storage fault. ECC covers its own protected storage paths.
Ordinary instruction timing has no added retry/diagnostic cycle when results
agree, but this statement is not a synthesis timing or area measurement.

The standalone checks, processor scenarios, software regressions, and Linux
boot complement one another. None is an exhaustive ISA, fault-space, or formal
correctness proof. In particular, the processor test checks reads and sticky FT
status behavior; it is not a dedicated test of every CSR access-permission case.
