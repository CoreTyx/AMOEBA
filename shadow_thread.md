# SHARD: Shadow Hardware Audit Redundancy Design — Rev 5

## Overview

SHARD adds a run-behind shadow pipeline to AMOEBA for area-efficient redundant execution and result verification. The shadow thread executes the same instructions as the main thread, N cycles behind, and compares results before committing them to the shared register file. All large structures (caches, register files, TLBs, privilege unit) are shared — SHARD saves these entirely compared to a naive second thread.

The existing SECDED ECC layer and SHARD are orthogonal: ECC corrects bit-flip faults in storage; SHARD detects structural and logic-level faults (wrong ALU results, wrong store data, wrong branch outcomes, wrong cache writes, control-flow hijacks). ECC-corrected values are treated as correct by SHARD.

**Rev 5 changes from Rev 4**: Verify-Before-Commit (VBC) for JALR and exceptions; IQ gains `FRM_snap` and `IsHWCSR` bits; full special instruction coverage (WFI, ECALL, EBREAK, MRET, SRET, sfence.vma, HW-incremented CSRs, misaligned accesses, cache block ops); SQ conflict detector extended to all N entries; integer DIV unified with FDIVSQRT in one shadow unit; shadow sMemory hardened for HPTW, D-cache miss, and big-endian.

---

## Design Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| N (delay depth) | 3 (default), max 5 | Configured in `cvw_t` struct; all stall counts are N-dependent |
| IQ width | **101 bits/entry** | {PC[63:0], Instr32[31:0], PCSrc[0], FRM_snap[2:0], IsHWCSR[0]} |
| OQ width | 320 bits/entry | {ForwardedSrcA[63:0], ForwardedSrcB[63:0], FwdFRs1[63:0], FwdFRs2[63:0], FwdFRs3[63:0]} |
| RQ width | ~535 bits/entry | See Stage 5 for full entry definition |
| SQ width | ~128 bits/entry | {PA, WriteData[63:0], ByteMask[7:0]} |
| Queue depth | N entries each | All queues N-deep for stall absorption |

---

## High-Level Architecture

```
Main Thread:    [F] → [D] → [E] → [M] → [W]
                 ↓      ↑    ↓             ↓
                IQ     OQ  (shared FUs)   RQ
                        ↓         ↑        ↓
Shadow Thread:  ← N → [sD] → [sE] → [sM] → [sW] → verify → write regfile
                                        ↑
                                    D-cache re-fetch
                                    (HPTW-gated)
```

- **Main thread** no longer writes to the register file directly. At Writeback it pushes to the RQ.
- **Shadow thread** pulls instructions from IQ, operands from OQ, re-executes independently, and at sWriteback compares against the RQ head before writing to the shared register file.
- **Match** → shadow writes the RQ's result (not its own) to regfile — deterministic committed state.
- **Mismatch** → MSECFAULT CSR logged; retry or M-mode trap depending on context.
- **VBC** → for JALR and exceptions, main stalls before the PC changes, giving shadow time to verify first.

---

## Stage 1 — Shadow Fetch: Instruction Queue (IQ)

Main pushes to the IQ tail at the Fetch→Decode boundary, after decompression and branch resolution. Shadow pops from the IQ head at sDecode.

### IQ Entry Fields

| Field | Width | Description |
|-------|-------|-------------|
| PC | 64 | Instruction PC. For spill instructions (`spill.sv`), stores the first-half fetch address (`PCF`), not `PCSpillF`. Consistent with retry flush target. |
| Instr32 | 32 | Expanded 32-bit instruction post-decompressor. Shadow uses this for all FU control signals (Funct3, W64, Funct7, etc.) at sExecute — OQ provides operands only. |
| PCSrc | 1 | Branch taken/not-taken at main's resolution. Shadow independently recomputes branch condition at sDecode and compares. |
| FRM_snap | 3 | `FRM_REGW` captured at Decode time for FP instructions with `rm=DYN`. Shadow drives this to the shared FPU at sExecute — not the live `FRM_REGW`. Prevents rounding-mode mismatch if FCSR changes in the N-cycle window. |
| IsHWCSR | 1 | Set for CSR reads of hardware-incremented registers (mcycle, minstret, time, mhpmcounter*, mip, mtime). Shadow SkipVerify for these — counter drift between main and shadow reads would cause false-positive faults. |

**IQ write-enable**: Gated by `~IFUStallF`. During a spill stall, no push occurs until the final merged instruction is ready.

**IQ flush**: On all main pipeline FlushD events (misprediction, trap, CSRWriteFence, fence.i). VBC holds a stall before the trap flush fires; the IQ flush still occurs when VBC releases.

**Why IQ beats banked I-cache re-fetch**: At N=3, IQ is 303 bits of flop with 0 extra logic. A PC-only queue + banked I-cache approach requires 192–321 bits flop plus ~4700 GE of logic (I-cache banking control, second ITLB read port on the 32-entry CAM, decompressor). IQ is correct by ≈15×.

---

## Stage 2 — Shadow Decode (sDecode): Operand Queue and Forwarding

Shadow gets register operands from the **Operand Queue (OQ)** rather than reading the register file. This avoids adding extra read ports to the FF-based register files.

**OQ push timing**: Main pushes `{ForwardedSrcAE, ForwardedSrcBE, FFwdSrcAE, FFwdSrcBE, FFwdSrcCE}` at the Execute→Memory clock boundary — the exact post-forwarding operands the ALU used. For variable-latency instructions (DIV stall via DivBusyE), OQ push fires once when DivBusyE falls and the instruction transitions from E to M — not per-cycle during the stall.

**Area comparison (register file read ports vs. OQ):**
- Adding 2 shadow integer read ports + 3 shadow FP read ports to the FF-based regfiles: ~18000 GE
- OQ (N=3 × 320 bits of flop): ~7680 GE — less than half the cost

**Coverage note**: Shadow uses main's forwarded operands, so forwarding logic errors are not independently checked by shadow. This is covered by `flopenrc_ecc` (SECDED) on all pipeline registers carrying forwarded values.

**Shadow forwarding (3-tier, Rev 5):**
1. Shadow sExecute bypass: sRdE matches rs1 or rs2 → forward `sEUResultE`
2. Shadow sMemory bypass: sRdM matches rs1 or rs2 → forward `sIFResultM`
3. **FP rs3 bypass (FMA accumulator)**: sRdE or sRdM matches rs3 → forward as `ShadowForwardCE`
4. OQ value (base post-forwarded operand, no regfile access)

`shadow_hzu.sv` generates `ShadowForwardAE`, `ShadowForwardBE`, and `ShadowForwardCE` from comparisons of sRdE, sRdM against shadow's rs1D, rs2D, rs3D.

**Branch/Jump verification at sDecode**: Shadow computes the branch outcome independently and asserts `shadow_branch_taken == IQ.PCSrc`. Mismatch → fault. For JALR, PCSrc=1 trivially; meaningful verification of the target address is handled by VBC (Stage 6). For JAL, the link address is in RQ.IntResult and verified at sWriteback.

---

## Stage 3 — Shadow Execute (sExecute): Functional Units

Shadow's sExecute uses IQ.Instr32 for all FU control signals and OQ operands for data.

| Unit | Latency | Type | Shadow treatment |
|------|---------|------|-----------------|
| ALU, BMU, KMU | 1 cycle | Single-cycle | Shadow duplicate instance |
| Integer MUL (`mul.sv`) | 2 cycles (pipelined) | Pipelined | Shared; main wins port arbitration; shadow stalls on conflict |
| FP FMA, fcmp, fcvt (`fpu.sv`) | 2 cycles (pipelined) | Pipelined | Shared; main wins port arbitration; shadow stalls on conflict |
| Integer DIV + FP FDIVSQRT | ~64 / 32–40 cycles | Iterative | **One** combined private radix-2 shadow instance |

**Integer DIV routing (Rev 5 fix)**: In CVW, integer division routes through `fpu.sv`'s FDIVSQRT unit (`IntDivE` path, same physical hardware as FP div/sqrt). Shadow's private unit is therefore one combined `shadow_fdivsqrt.sv` handling both integer div and FP div/sqrt — exactly mirroring the main unit's architecture.

**Pipelined FU arbitration**: Shadow checks, one cycle ahead, whether main's Execute will use the same pipelined FU. If yes, shadow stalls at sExecute. Main always wins. Backpressure: sExecute stall → sDecode stall → IQ head held → IQ fills → main Fetch/Decode stalls after N cycles.

**Private radix-2 instance (DIV + FDIVSQRT)**: Shadow's combined radix-2 unit is ~¼ the area of main's SRT radix-4. Takes up to 4× longer. Shadow stalls and backpressures. Must produce bit-exact IEEE 754 / RISC-V spec results.

**fflags isolation**: Shadow drives `IQ.FRM_snap` to the shared FPU at sExecute (not live FRM_REGW). `ShadowSetFflagsM[4:0]` routes ONLY to `shadow_verifier.sv` for comparison with `RQ.fflags` — never to `csru.sv`. Shadow never modifies FCSR.

---

## Stage 4 — Shadow Memory (sMemory): D-Cache Re-Fetch

All cacheable stores and loads result in a real D-cache access by shadow. Shadow never skips the cache access for cacheable addresses (except SkipVerify instructions).

### Conflict Detection (Rev 5: All N Entries)

Rev 4 only checked the SQ head. Rev 5 scans **all N SQ entries and all N RQ load entries**:

```
ShadowConflictStall =
  OR_i( SQ[i].valid &&
        NextMStore.PA[63:3] == SQ[i].PA[63:3] &&
        (NextMStore.ByteMask & SQ[i].ByteMask) != 0 )
  ||
  OR_i( RQ[i].IsLoad && RQ[i].valid &&
        NextMStore.PA[63:3] == RQ[i].MemAddr[63:3] &&
        (NextMStore.ByteMask & RQ[i].ByteMask) != 0 )
```

Detection at main's Execute stage (1 cycle before M stage commit). Counter holds `StallE` for N-1 cycles. Shadow is NOT stalled — it completes sMemory for the conflicting instruction during the stall window. Area: ~N × 100 gates ≈ 300 gates total.

**Conflict timing (N=3)**:
- Shadow sMemory for instruction K: cycle T+N+2 = T+5
- Conflicting store K+m at main M (no stall): T+4 — writes before shadow reads
- Fix: stall K+m at main Execute for N-1=2 cycles → M stage shifts to T+6
- Shadow reads clean cache at T+5; main commits overwrite at T+6. Correct.

**Shadow sM for a STORE:**
1. Pop SQ head `{PA_h, Data_h, Mask_h}`
2. Assert: `shadow_computed_addr == PA_h` (address correct) and `shadow_computed_data[Mask_h] == Data_h[Mask_h]` (ALU correct)
3. Issue D-cache load at `PA_h` (conflict-free, guaranteed by stall)
4. Assert: `D_cache_load[Mask_h] == Data_h[Mask_h]` (cache write correct)

**Shadow sM for a LOAD:**
1. Peek RQ head for `MemAddr` and `ReadData`; assert `shadow_computed_addr == MemAddr`
2. Issue D-cache load at `MemAddr` (conflict-free, guaranteed by stall)
3. Assert: `D_cache_load == ReadData` (full data match)

### Shadow sMemory Hardening (Rev 5)

**HPTW arbitration**: When main has a D-TLB miss, `SelHPTW` seizes the D-cache for page table walks. Shadow gates its D-cache request: `shadow_dcache_req = shadow_dcache_want & ~SelHPTW`. Shadow stalls at sMemory until SelHPTW deasserts. Shadow has the PA from SQ/RQ and needs no DTLB.

**Shadow D-cache miss**: If shadow's re-read misses (line evicted since main's access), shadow stalls at sMemory until the line fills (natural D-cache miss stall mechanism). The ShadowConflictStall counter pauses during shadow's D-cache miss — the stall guarantee does not expire prematurely.

**Big-endian mode**: When `BigEndianM` is asserted, shadow applies the same byte-swap to its D-cache read data before comparing against `RQ.ReadData`. Applied in `shadow_verifier.sv`.

**Misaligned accesses (ZICCLSM_SUPPORTED=1)**: Shadow mirrors `align.sv`. Shadow's sMemory detects misalignment from Instr32 size field + address alignment bits, issues **two** D-cache reads at the two aligned fragment addresses, merges using the same shift/mask logic as `align.sv`, and compares the merged result against `RQ.ReadData`. For misaligned stores, SQ stores the full double-line data; the conflict detector checks both aligned addresses. Area: ~100–200 extra gates in shadow_pipeline.sv sMemory stage.

### Store Queue (SQ)

Main's M stage pushes `{PA, WriteData[63:0], ByteMask[7:0]}` per store to SQ tail. Shadow's sM pops from SQ head when processing a store. SQ is a pure N-entry FIFO. The conflict comparator scans all N entries and wires its output to `hazard.sv` as `StallE`.

### MMIO / Non-Cacheable Addresses

Shadow verifies ALU path only: `shadow_computed_addr == SQ/RQ.MemAddr` and (for stores) `shadow_computed_data[Mask] == SQ.WriteData[Mask]`. No bus re-read. No MSECFAULT.

### Banked D-Cache

Existing `ram1p1rwbe` SRAMs split 2-way by set index parity. Main store and shadow load can access different banks in the same cycle. Same-bank conflict: main has priority, shadow stalls 1 cycle.

---

## Stage 6 — Verify-Before-Commit (VBC)

For instructions that change the PC based on register state or CSR state, a hardware fault could cause a control-flow deviation before shadow can catch it via normal post-hoc verification. VBC stalls main until shadow confirms the result.

### VBC for JALR

**Trigger**: JALR is at main's Execute stage.

**Mechanism**: Main asserts `StallE_JALRVBC`, holding JALR at Execute. Shadow, N cycles behind, eventually reaches the same JALR instruction at sExecute and independently computes the target address using IQ.Instr32 (offset field) and OQ.ForwardedSrcA (rs1 value).

**Release condition (PC-match, not fixed counter)**: `StallE_JALRVBC` deasserts when `shadow_sE_valid && shadow_sE_PC == JALR_PC_latched`. This correctly handles shadow stall cases (DIV, FPU arbitration conflicts) — the stall holds until shadow genuinely executes the JALR at sExecute, regardless of how long that takes.

**On match**: Main releases stall; any BPWrongE correction is applied; pipeline resumes.

**On mismatch**: Shadow reports fault → retry JALR (flush + re-fetch from JALR PC). Store scan not required (JALR is at Execute; no M-stage stores have committed).

**Cost**: N=3 cycles per JALR in steady state. Every indirect call/return (jalr x0, ra, 0) pays 3 cycles. Acceptable for AMOEBA's security priority.

### VBC for Exceptions (TrapM)

**Trigger**: `TrapM` fires at main's Memory stage (page fault, illegal instruction, ECALL, EBREAK, interrupt).

**Problem solved**: Without VBC, TrapM immediately triggers `FlushWCause`, preventing the M-stage instruction from advancing to Writeback and pushing to the RQ. Shadow would later reach sWriteback for that instruction with no corresponding RQ entry (orphan). VBC eliminates this class of problem entirely.

**Mechanism** (changes to `hazard.sv`):
```
VBC_TrapHold          = (VBC_TrapCounter != 0)
FlushWCause_effective = TrapM & ~WFIInterruptedM & ~VBC_TrapHold
StallM_ForTrapVBC     = TrapM & VBC_TrapHold
```
Counter starts at N-1 when TrapM first fires; decrements each cycle. After N cycles, `VBC_TrapHold` deasserts; the trap commits normally (FlushWCause fires, pipeline redirects to trap vector).

During the N-cycle stall, shadow verifies the N instructions in the window preceding the trap. The instruction that caused the trap either:
- Pushes a valid RQ entry when it advances to W (for exceptions like illegal instruction where the instruction completes)
- Is marked `IsFaultedInstr=1` in the RQ for cases where it cannot complete normally (page fault, access fault)

**Limitation**: If shadow is additionally stalled (e.g., DIV) during the N-cycle VBC window, some instructions may go unverified at the time the trap fires. Acceptable — exceptions are rare; the trap takes priority.

### No VBC for MRET/SRET

MRET does **not** set `FlushWCause` (confirmed: `hazard.sv` line 75 gates FlushWCause only on TrapM, not RetM). MRET completes normally through the W stage and pushes to the RQ. Back-to-back MRETs in the N-cycle window are impossible — each MRET asserts `RetM`, which flushes F/D/E stages and the IQ.

Shadow verifies MRET at sWriteback by:
1. SkipVerify for privilege state change (ECC protects STATUS register, MPP field)
2. Re-reading `mepc` (or `sepc` for SRET) at sExecute and comparing against `RQ.TrapReturnTarget`
3. Software CSR writes to mepc flush the pipeline (and IQ/RQ), so mepc cannot change between main's MRET and shadow's re-read N cycles later

A mismatch indicates hardware trojan activity on the mepc→IFU path.

---

## Atomic and Special Instructions

| Instruction | Shadow behavior |
|-------------|----------------|
| **LR (load-reserved)** | Regular D-cache load (no reservation placed — spurious LR would overwrite main's reservation). Compare `D_cache_load` with `RQ.rd_value`. Known limitation: reservation integrity not independently checked. |
| **SC (store-conditional), success** | SQ has the store entry. Shadow D-cache load + compare (regular store path). |
| **SC, failure** | No memory write. Shadow verifies `RQ.rd_value == 1`. No cache access. Shadow writes 1 to rd at sWriteback per RISC-V spec (failed SC writes non-zero to rd — no suppression). |
| **AMO (AMOSWAP, AMOADD, etc.)** | Shadow issues D-cache load at AMO PA. By the time shadow verifies, main has written `f(orig, rs2)` to cache. Correct check: `D_cache_load == f(RQ.IntResult, shadow_rs2)` where `RQ.IntResult = orig_val` (RISC-V AMO: rd ← original mem value; cache ← computed value). Address check: `shadow_computed_addr == RQ.MemAddr`. SQ conflict detection applies. |
| **CSR read (software-written)** | Shadow re-reads same CSR at sExecute (Instr32 from IQ gives CSR address). Value guaranteed identical: software CSR writes flush IQ/RQ. Compare with `RQ.csr_rdata`. |
| **CSR read (hardware-updated)** | IQ.IsHWCSR=1 → SkipVerify. Covers: mcycle, minstret, time, mhpmcounter*, mip, mtime. Shadow pops IQ/OQ/RQ without comparison. No MSECFAULT. |
| **CSR write** | Not re-executed. ECC protects CSR arrays. |
| **WFI** | Shadow NOP: pop IQ/OQ/RQ, no computation, no cache access. The wake-interrupt flush propagates to IQ normally. |
| **ECALL / EBREAK** | Shadow NOP (pop IQ/OQ/RQ). VBC stalls main's trap effect for N cycles, giving shadow time to verify the N preceding instructions before the privilege transition. |
| **MRET / SRET** | Shadow NOP for privilege state change (SkipVerify). Shadow re-reads mepc (or sepc) at sExecute and compares against `RQ.TrapReturnTarget`. No VBC stall — MRET completes at W normally. |
| **sfence.vma** | Shadow NOP (same as fence). sfence.vma causes CSRWriteFenceM → IQ flush. Shadow's outstanding sMemory for any earlier instruction completes before the flush propagates. |
| **Fence / fence.i** | NOP for shadow — pop IQ/OQ/RQ, no computation or cache access. |
| **MMIO store/load** | ALU path only (address + data match). No bus access. No MSECFAULT. |
| **Branch / conditional jump** | Branch condition verified at sDecode vs. IQ.PCSrc. |
| **JALR** | VBC: main stalls at Execute until shadow's sExecute computes the same target (PC-match release). Mismatch → retry JALR. Link address (PC+4) also verified at sWriteback via `RQ.IntResult`. |
| **JAL** | Link address verified at sWriteback via `RQ.IntResult`. No VBC needed (target is PC-relative, not register-dependent). |
| **Misaligned load/store** | Shadow mirrors `align.sv`: detects misalignment from Instr32 size + address alignment, issues two D-cache reads, merges, compares against `RQ.ReadData`. SQ stores double-line data for misaligned stores; conflict detector checks both aligned addresses. |
| **cbo.zero** | Shadow re-reads the full cache line (CACHEWORDLEN-wide) at the CMO address and verifies all bytes are zero. |
| **cbo.clean / cbo.flush / cbo.inval** | SkipVerify — shadow pops IQ/OQ/RQ, no computation or cache access. Data is either gone (inval) or writeback correctness is not independently verifiable. |

---

## Stage 5 — Shadow Writeback (sWriteback): Verification and Register Commit

### Result Queue (RQ) Entry Structure

```
Rd[4:0],                IntResult[63:0],         IntWriteEn,
FRd[4:0],               FPResult[63:0],           FPWriteEn,
fflags[4:0],                                       // per-instruction FP exception flags
ReadData[63:0],                                    // load result
MemAddr[PA_BITS-1:0],   MemWriteEn, HasStore,
CSRRdata[63:0],         IsCSRRead,
PC[63:0],                                          // retry/flush target
IsLoad, ByteMask[7:0],                             // for conflict detection
TrapReturnTarget[63:0],                            // mepc/sepc for MRET/SRET [NEW Rev 5]
SkipVerify,                                        // fence, WFI, HW-CSR, cbo.clean/flush/inval
IsFaultedInstr                                     // set by VBC for trap-causing instruction
```
~535 bits/entry × N=3 → ~1605 bits total.

### Verification and Writeback

Shadow computes its result independently through the shadow pipeline. At sWriteback:
- For `SkipVerify` entries: shadow pops without comparison; writes to regfile if IntWriteEn or FPWriteEn
- For all other entries: compare shadow's result against the appropriate RQ field

**Match** → shadow writes RQ's result (not shadow's own) to regfile:
- Integer: `{we3=1, a3=RQ.Rd, wd3=RQ.IntResult}` — shadow drives the regfile write port; main never writes regfile directly
- FP: `{we4=1, a4=RQ.FRd, wd4=RQ.FPResult}`
- **FP-integer division** (`FIntDivResultW` path): Shadow intercepts this result path and drives the integer regfile write port. `shadow_verifier.sv` selects the correct write path based on IQ.Instr32 instruction type.
- **Failed SC**: Shadow writes 1 to `RQ.Rd` (per RISC-V spec). Main's `SquashSCW` gated `RegWriteW` — now irrelevant since main never writes regfile; shadow drives the write directly based on SC success/fail from SQ/RQ.

**Mismatch** → fault response (see below).

### Main Thread Forwarding from RQ (N-parameterized)

With SHARD, the regfile is written N cycles after main computes. Main's Decode stage forwarding chain:
1. In-pipeline bypass: from M stage (`IEUResultM`) and from W stage (RQ push value — same cycle as main Writeback)
2. **RQ associative lookup**: N-entry scan for rs1/rs2 match → forward pending result. Parameterized by N: for N=5, scan 5 entries. Covers instructions 3 through N+2 cycles old.
3. Regfile: shadow-committed, ECC-protected values

### Fault Response

All faults log MSECFAULT (shadow fault bit + faulted instruction PC from `RQ.PC`).

**Multiple simultaneous faults**: Handle oldest-first. After retry or trap resolves the oldest fault, the newer fault will appear in the next shadow verification window.

**VBC JALR mismatch**: Flush to JALR.PC → retry. No HasStore scan required (JALR is at Execute; no M-stage stores have committed yet).

**Non-memory faults** (integer, FP, CSR read mismatch):
1. Scan RQ entries newer than the faulted entry for `HasStore == 1`
2. **No stores**: flush main pipeline to `RQ.PC` of faulted entry → re-execute. Safe — no memory side effects to undo.
3. **Stores present**: cannot undo committed D-cache writes → trap to M-mode with MSECFAULT. Software handler decides (idempotent retry or reset).

**Memory faults** (D-cache re-fetch mismatch for store/load verification): log MSECFAULT only, continue executing. Store already committed. M-mode software decides based on severity.

---

## Area Efficiency: SHARD vs. Full Pipeline Duplication

| Component | New Thread Cost | SHARD Cost | Area Saved |
|-----------|----------------|-----------|-----------|
| IFU (bpred, ITLB, decomp, FSM) | Duplicate (~30–40% of core) | IQ: 303 bits flop | ~30–40% of core |
| I-cache (32 KB) | 2× or 2-port | Not accessed by shadow | 32 KB SRAM |
| D-cache (32 KB) | 2× or 2-port | 2-bank (area-neutral) | 32 KB SRAM |
| Integer regfile (32×72 bits) | Duplicate | OQ + shadow drives 1 write port | Full regfile |
| FP regfile (32×64 bits) | Duplicate | OQ + shadow drives 1 write port | Full fregfile |
| DTLB (32-entry CAM) | Duplicate | Shadow uses PA from SQ/RQ | Full DTLB |
| Privilege unit + CSR regfile | Duplicate | Not touched by shadow | Full unit |
| ALU / BMU / KMU | Duplicate | Shadow duplicate | 0 saved |
| Integer MUL | Duplicate | Shared pipelined (1× total) | 1× MUL |
| FP FMA / fcmp / fcvt | Duplicate | Shared pipelined (1× total) | 1× FPU pipeline |
| DIV + FDIVSQRT (combined) | Duplicate | Combined radix-2 private (~0.25×) | ~0.75× combined |
| IQ + OQ + RQ + SQ queues | None | ~4800 bits flop + ~300 gates | (overhead) |
| VBC logic | None | ~100 gates | (overhead) |
| shadow_hzu, shadow_verifier | None | ~600–1200 gates combinational | (overhead) |

SHARD is unambiguously more area-efficient than a second full thread.

---

## Prior Art Context

SHARD is novel in its specific combination. The closest prior works:

- **AR-SMT (Rotenberg, FTCS 1999)** and **SRT (Reinhardt & Mukherjee, ISCA 2000)**: Introduced leading/trailing thread paradigm with FIFO queues (IQ, OQ, SQ analogs) for OoO SMT processors. SRT deliberately avoids D-cache re-reads via a Load Value Queue (LVQ). SHARD's D-cache re-read in a continuous in-order shadow pipeline is distinct.
- **DIVA checker (Austin, MICRO 1999)**: Attaches a small checker at OoO commit that re-reads the D-cache for load verification and maintains a checker-exclusive register file. SHARD applies these concepts to a continuous N-cycle in-order pipeline.
- **Chico (Michigan, MTV 2007)**: "Golden register file" written only by the checker — same concept as SHARD's regfile-exclusive-to-shadow model.

**Key novel claims**: (1) D-cache re-read in a continuous N-cycle in-order shadow pipeline sharing the same cache; (2) stall-main (not shadow) for store-store conflicts to guarantee shadow reads clean cache state; (3) VBC for JALR and exceptions applied to a hardware-trojan threat model (not just soft errors); (4) main thread architecturally prohibited from writing the register file — only shadow does, after verification.

---

## Files to Create

```
hdl/core/shadow/
  shadow_iq.sv         — IQ FIFO (N × 101 bits: PC + Instr32 + PCSrc + FRM_snap + IsHWCSR)
  shadow_oq.sv         — OQ FIFO (N × 320 bits: 5 × 64-bit forwarded operands)
  shadow_sq.sv         — SQ FIFO (N × 128 bits) + all-N-entry ShadowConflictStall comparator
  shadow_rq.sv         — RQ FIFO (N × ~535 bits) + main-thread N-entry associative forwarding mux
  shadow_hzu.sv        — 3-tier shadow bypass (rs1, rs2, rs3; sE→sE and sM→sE)
  shadow_pipeline.sv   — sDecode → sExecute → sMemory → sWriteback; VBC signal ports
  shadow_verifier.sv   — Per-type comparison; HW-CSR skip; big-endian swap; FIntDiv path; cbo.zero
  shadow_fdivsqrt.sv   — Combined radix-2 serial unit: integer div + FP div/sqrt (IEEE 754 bit-exact)
```

## Files to Modify

```
hdl/core/wally/wallypipelinedcore.sv  — Instantiate shadow_pipeline; wire IQ/OQ/RQ/SQ; VBC stall signals to hazard
hdl/core/ieu/datapath.sv             — Push to OQ at E→M boundary; push to RQ at Writeback; remove regfile write from main
hdl/core/ieu/ieu.sv                  — Shadow drives we3/a3/wd3; N-entry RQ associative lookup in Decode forwarding
hdl/core/fpu/fpu.sv                  — Remove fregfile write from main (goes to RQ); FIntDivResultW → shadow verifier
hdl/core/lsu/lsu.sv                  — SQ push on store M stage; shadow D-cache port; SelHPTW gate for shadow request
hdl/core/cache/cacheway.sv           — 2-bank SRAM split (even/odd set index) for parallel main+shadow access
hdl/core/hazard/hazard.sv            — ShadowConflictStall → StallE; VBC_TrapHold → StallM; JALR VBC → StallE
hdl/core/privileged/csrharden.sv     — Shadow fault bit + faulted PC in MSECFAULT; TrapReturnTarget field
pkg/types.sv                         — iq_entry_t (101b), oq_entry_t (320b), rq_entry_t (~535b), sq_entry_t (128b)
```

---

## Verification Plan

1. **Unit tests**: shadow_iq, shadow_oq, shadow_sq (all-N-entry scan), shadow_rq, shadow_hzu (rs3 path), shadow_verifier — isolated directed testbenches
2. **Golden path**: full existing test suite; zero MSECFAULT on clean execution; all VBC stalls release correctly
3. **IQ FRM_snap**: FP instruction with rm=DYN; FCSR.frm changed in N-cycle window; shadow uses snapped FRM; no false fault
4. **HW-CSR SkipVerify**: `csrr mcycle` → shadow does not compare; no MSECFAULT; counter reads correctly forwarded
5. **JALR VBC (match)**: JALR with correct ALU → VBC holds N cycles → shadow matches → stall releases; pipeline resumes
6. **JALR VBC (mismatch)**: inject ALU fault in JALR target computation → VBC holds → shadow detects mismatch → retry from JALR PC; execution correct after retry
7. **JALR VBC + shadow stall**: JALR followed immediately by a shadow DIV stall → VBC hold extends past N cycles → releases only when shadow sExecute fires for JALR (PC-match based)
8. **Exception VBC (ECALL)**: ECALL → VBC stall N cycles → all N preceding instructions shadow-verified → trap fires; no orphan RQ entries; trap handler runs correctly
9. **Exception VBC (page fault)**: load to unmapped VA → VBC stall → preceding instructions verified → trap fires; MSECFAULT has correct faulted PC
10. **WFI**: WFI stalls main for multiple cycles; shadow processes WFI IQ entry as NOP; wake interrupt fires; IQ flush; no false fault on resumed execution
11. **MRET verification**: shadow re-reads mepc at sExecute; compares against RQ.TrapReturnTarget; match passes; inject mepc tamper (hardware trojan sim) → MSECFAULT
12. **Branch fault**: flip IQ.PCSrc for a branch → shadow detects mismatch at sDecode; MSECFAULT logged; pipeline continues
13. **FMA rs3 forwarding**: back-to-back FMA where rs3 = previous FMA result → ShadowForwardCE active; result correct; no false fault
14. **Pipelined FU arbitration (long stream)**: 5 consecutive FMAs → shadow stalls repeatedly; IQ fills after N cycles → main stalls; all results verified correct; no deadlock
15. **DIV via FDIVSQRT path**: integer DIV instruction → shadow_fdivsqrt handles IntDivE; bit-exact result vs. main SRT radix-4; no stall coupling
16. **SQ all-entry conflict scan**: 3 stores within N cycles, store 1 and store 3 to same PA bytes → conflict detected on store 3 (not just head); correct 2-cycle stall; store 1 verified clean
17. **HPTW arbitration**: D-TLB miss → HPTW seizes cache → shadow sMemory request gated; shadow stalls until SelHPTW clears; no false fault
18. **Shadow D-cache miss**: evict shadow's target line between main access and shadow re-read → shadow stalls until line refills; conflict stall counter pauses; correct result
19. **Big-endian**: execute in big-endian mode; shadow applies byte-swap before compare; correct load verification; no false fault
20. **SC failure**: SC fails → shadow writes 1 to rd; no cache access; no MSECFAULT; rd=1 visible to next instruction
21. **AMO**: AMOADD → main writes f(orig, rs2) to cache; shadow re-reads → D_cache_load == f(RQ.IntResult, shadow_rs2) → passes; inject AMO compute fault → MSECFAULT
22. **Multiple simultaneous faults**: inject two ALU mismatches in the same N-cycle window → oldest-first handling; both eventually caught across two retry/trap cycles
23. **Retry with no stores**: inject non-memory fault, no HasStore in RQ window → flush+retry; execution resumes correctly from faulted PC
24. **Trap with stores in window**: inject non-memory fault, HasStore in RQ window → M-mode trap fires; MSECFAULT has correct PC
25. **Misaligned load**: unaligned LW to 4-byte-straddling address → shadow issues two D-cache reads; merged result matches RQ.ReadData; no false fault
26. **cbo.zero**: main zeros a cache line → shadow re-reads; verifies all bytes zero → passes; inject non-zero byte in cache line → MSECFAULT
27. **cbo.inval / cbo.flush**: shadow SkipVerify → no MSECFAULT; normal pipeline continues; subsequent accesses to that address verify correctly
