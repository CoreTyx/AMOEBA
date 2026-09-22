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

---

---

# SHARD V1 Implementation — As-Built Details

*Branch: `sai-shard-impl`. All file paths relative to repo root.*

This section records exactly what was implemented and tested. The design spec above (Rev 5) describes the full intended system; V1 is a correct but reduced subset. Use this section as a complete blueprint to re-implement SHARD on any other branch of this repo.

---

## V1 Scope vs. Rev 5 Spec

| Rev 5 feature | V1 status | Notes |
|---|---|---|
| IQ shift register (PC, Instr32, PCSrc, FRM_snap, IsHWCSR, IsDummy, DummySel, InstrValid) | **Implemented** | Entry is 104 bits (RV64). IsDummy and DummySel added beyond Rev 5. |
| OQ shift register (forwarded operands + decoded ALU controls) | **Implemented** | OQ is wider than Rev 5: carries full E-stage controller state snapshot, not just 5×64-bit operands. |
| RQ shift register + main-D associative forwarding | **Implemented** | Reduced field set: no FP result, no fflags, no ReadData, no TrapReturnTarget. MemAddr always 0 in V1. |
| SQ shift register + N-entry conflict detector | **Implemented** | ByteMask is hardwired to all-1s (full XLEN granularity). Conflict at 4-byte (word) granularity. |
| Shadow pipeline sD→sE→sM→sW | **Implemented** | Shares main stall/flush exactly (synchronous shadow). Shadow has no independent stall. |
| Shadow ALU (independent re-execution) | **Implemented** | Duplicate `alu` instance with `comparator` for branches. |
| Shadow forwarding (shadow HZU) | **shadow_hzu.sv coded but NOT wired** | V1 uses OQ operands directly — no intra-shadow forwarding needed because OQ already carries post-forwarded operands from main. shadow_hzu.sv is in the tree for future use. |
| Verification at sW: ALU result + branch outcome | **Implemented** | |
| SkipVerify for FP, DIV, LR/SC, AMO, CSR, fence, WFI, loads | **Implemented** | Loads (opcode 0000011) are also skipped — D-cache re-read not implemented in V1. |
| D-cache re-read for stores/loads (sM) | **NOT implemented** | sM only pops SQ (address captured); no actual cache access. |
| VBC for JALR | **NOT implemented** | VBC_StallE tied to 0. |
| VBC for exceptions (TrapM) | **NOT implemented** | |
| MRET/SRET mepc re-read | **NOT implemented** | |
| shadow_fdivsqrt.sv | **NOT created** | DIV/FP-DIV covered by SkipVerify. |
| FP register file write via shadow | **NOT implemented** | FP results are SkipVerify; shadow does not write fregfile. |
| FP fflags verification | **NOT implemented** | |
| csrharden bit [6] = ShadowFaultW | **Implemented** | SecFaultM[6] = ShadowFaultW; no trap generated, MSECFAULT register only. |
| mdu.sv: plain mul/div (removed ft_mul/ft_div) | **Implemented** | Shadow-of-MDU audit removed; SHARD verifies the full W-stage result instead. |
| RVFI monitor fix for delayed regfile write | **Implemented** | Uses `RdW`/`RegWriteW_s`/`ResultW_s` from main W-stage. |

---

## Clocking Convention

All four shadow queues (IQ, OQ, SQ, RQ) are **negedge-clocked**. The shadow pipeline stage registers are **posedge-clocked** (standard `flopenrc`). This split means:

- Queue push happens at negedge T after main posedge-T has resolved all combinational paths (forwarded operands, stall/flush signals, etc.).
- Shadow pipeline stages advance at posedge T+1, reading the negedge-T queue head combinationally.
- Shadow writes the regfile at negedge T (from sW), while main reads the regfile for forwarding at posedge T+1 (Execute stage).

The 1-cycle negedge bypass in `wallypipelinedcore.sv` (see §RQ Forwarding Negedge Bypass) closes the one-posedge window where R1E was stale after the shadow negedge write.

---

## Module-by-Module As-Built Specification

### `shadow_iq.sv` — Instruction Queue

**Location**: `hdl/core/shadow/shadow_iq.sv`

**Interface**: Parameterized `#(cvw_t P, int N = 3)`.

**Entry width** (RV64, N=3):
```
ENTRY_W = P.XLEN + 32 + 1 + 3 + 1 + 1 + 1 + 1 = 104 bits
Fields: {PC[63:0], Instr32[31:0], PCSrc[0], FRM_snap[2:0], IsHWCSR[0], IsDummy[0], DummySel[0], InstrValid[0]}
```

Two extra fields beyond Rev 5: **IsDummy** (instruction is a AMOEBA dummy instruction) and **DummySel** (which shadow physical register the dummy writes). These are piped through the shadow pipeline so sW can redirect the regfile write to the correct shadow register for dummy instructions.

**Push timing**: negedge clk, fires when `~StallD`.

**Push sources** (from `wallypipelinedcore.sv` instantiation):
- `PCF` ← `PCSpillF` (post-spill fetch PC)
- `InstrD` ← `InstrD` (main Decode instruction word)
- `PCSrcD` ← `PCSrcE` (**Execute-stage** PCSrc — see Timing Note below)
- `FRM_D` ← `FRM_REGW[2:0]` (live FRM at Decode time)
- `IsHWCSR_D` ← `1'b0` (hardwired off in V1)
- `IsDummyD` ← `InjectD` (AMOEBA dummy injection flag)
- `DummySelD` ← `DummySelD` (shadow register select for dummy)
- `InstrValidD` ← `InstrValidD`

**Flush behavior**: On `FlushD`, only the valid bit (bit 0) of every entry is cleared. Data fields are preserved (useful for debug).

**Shift behavior**: On `~StallD & ~FlushD`, entries shift: `entry[N-1] ← entry[N-2] ← ... ← entry[0] ← new_push`.

**Head output**: `entry[N-1]` exposed as combinational outputs `sPC`, `sInstr32`, `sPCSrc`, `sFRM_snap`, `sIsHWCSR`, `sIsDummy`, `sDummySel`, `sInstrValid`.

**PCSrc Timing Note**: The IQ stores `PCSrcE` (Execute-stage signal) when the instruction is in Decode. This means the captured PCSrc is the branch outcome for the *previous* instruction (which is in Execute when the push fires at negedge), not for the instruction being pushed. In practice this is harmless:
- Taken branches trigger `FlushD`, which clears all IQ valid bits before shadow processes the branch entry.
- Not-taken branches: `PCSrcE = 0` for the previous instruction is almost always 0 as well. The shadow verifier's `branch_mismatch` check is gated by `isBranch` derived from the IQ entry's own opcode, so the mismatch for non-branch-surrounding instructions cannot spuriously fire.
- This is a V1 approximation. A correct fix is to delay the IQ push by one cycle or latch PCSrcE at the cycle when the instruction advances from Decode to Execute.

---

### `shadow_oq.sv` — Operand Queue

**Location**: `hdl/core/shadow/shadow_oq.sv`

**Entry width** (RV64, N=3):
```
ENTRY_W = 5*64 + CTL_W  where CTL_W = 3+3+3+4+4+3+1+2+3+7+5+1+1+1+2+5+1+1+1+1 = 52
Total: 320 + 52 = 372 bits/entry. Three entries = 1116 bits.
```

This is wider than the Rev 5 spec's 320-bit estimate because the OQ carries not just 5×64-bit operands but also the full decoded ALU control state:
```
Fields: SrcAE, SrcBE, ForwardedSrcBE, PCLinkE, ImmExtE,
        W64E, UW64E, SubArithE, ALUSelectE[2:0], BSelectE[3:0], ZBBSelectE[3:0],
        BALUControlE[2:0], BMUActiveE, CZeroE[1:0], Funct3E[2:0], Funct7E[6:0],
        Rs2E[4:0], ALUResultSrcE, JumpE, BranchSignedE, MemRWE[1:0],
        RdE[4:0], RegWriteE, InstrValidE, DummyE, DummySelE
```

**Push timing**: negedge clk.

**Push behavior** (from `wallypipelinedcore.sv`):
- `StallM = 1` → hold all entries (instruction in E stalled, no shift)
- `FlushE = 1` or `FlushM = 1` → inject null entry at position 0, shift others
- Normal → shift with current E-stage snapshot

**Push sources** (from `wallypipelinedcore.sv`):
- `SrcAE` ← `SrcAE_s` (from `datapath.SrcAE_out` — post-mux after SrcAE mux, i.e., ALUSrcAE-selected operand)
- `SrcBE` ← `SrcBE_s` (from `datapath.SrcBE_out` — post-mux SrcBE)
- `ForwardedSrcBE` ← `ForwardedSrcBE` (pre-SrcBE-mux raw forwarded B, used as store data)
- `PCLinkE` ← `PCLinkE` (PC+4 for JAL/JALR link address)
- `ImmExtE` ← `ImmExtE_s` (from `datapath.ImmExtE_out`)
- Control signals (`W64E`, `ALUSelectE`, etc.) ← exported from `ieu` as `*_out` ports

**Rationale for carrying full control state**: Shadow sE re-runs the `alu` instance with OQ operands and OQ control signals. This avoids routing IQ.Instr32 back through a controller decode at sE, and eliminates any risk of OQ/IQ decode mismatch.

---

### `shadow_sq.sv` — Store Queue

**Location**: `hdl/core/shadow/shadow_sq.sv`

**Entry width** (RV64, N=3):
```
ENTRY_W = PA_BITS + XLEN + XLEN/8 + 1  (56+64+8+1 = 129 bits for PA_BITS=56, XLEN=64)
Fields: {PA[PA_BITS-1:0], WriteData[63:0], ByteMask[7:0], Valid[0]}
```

**Push timing**: negedge clk, at main M-stage when `StoreM = MemRWM[0]`.
Push sources (from `wallypipelinedcore.sv`):
- `IEUAdrM[PA_BITS-1:0]` — physical store address (note: lower XLEN bits of IEUAdrM)
- `WriteDataM` — store write data
- `ByteMaskM` ← `{(P.XLEN/8){1'b1}}` — **hardwired all-1s** in V1 (no sub-word granularity tracking)

**Pop**: shadow sM pops by asserting `sM_pop`, which is `sInstrValid_M & sMemRW_M[0] & ~StallM & ~FlushM`.

**Conflict detector** (N-entry combinational):
```systemverilog
conflict[g] = sq[g].valid
            & (sq[g].PA[PA_BITS-1:2] == IEUAdrE_PA[PA_BITS-1:2])
            & ((sq[g].ByteMask & ByteMaskE) != '0)
```
- Granularity: 4-byte word (`PA[1:0]` ignored — comparison at `[PA_BITS-1:2]`)
- `ByteMaskE` ← `{(P.XLEN/8){1'b1}}` (all-1s in V1)
- `ShadowConflictStallE` = `StoreE & (|conflict[N-1:0])`
- `StoreE` = `MemRWE[0]`

**Important V1 note**: Because ByteMask is all-1s, the conflict detector fires on any PA[word-aligned] overlap between an incoming E-stage store and any SQ entry. This is conservative (may stall more than necessary for sub-word stores) but never misses a real conflict.

---

### `shadow_rq.sv` — Result Queue

**Location**: `hdl/core/shadow/shadow_rq.sv`

**Entry width** (RV64, N=3):
```
ENTRY_W = 5 + XLEN + 1 + XLEN + 2 + 1 + XLEN + 1 + 1 + 1 + 1 + 1
        = 5 + 64 + 1 + 64 + 2 + 1 + 64 + 1 + 1 + 1 + 1 + 1 = 206 bits
Fields (MSB→LSB): Rd[4:0], IntResult[63:0], IntWriteEn[0], MemAddr[63:0],
                  MemRW[1:0], HasStore[0], PC[63:0], SkipVerify[0],
                  IsFaultedInstr[0], DummyW[0], DummySelW[0], InstrValid[0]
```

This is substantially smaller than the Rev 5 spec (~535 bits): no FP result, no fflags, no ReadData, no ByteMask, no TrapReturnTarget. MemAddr is always pushed as `'0` in V1 (address verification not implemented).

**Push timing**: negedge clk, from main W-stage when `~StallW`.
Push sources (from `wallypipelinedcore.sv`):
- `RdW` ← `RdW` (destination register from controller)
- `ResultW` ← `ResultW_s` (from `datapath.ResultW_out` — full ResultW mux output)
- `RegWriteW` ← `RegWriteW_s` (from `ieu.RegWriteW_out`)
- `PCW` ← `PCW` (W-stage PC, registered from PCM at posedge)
- `MemRWW` ← registered `MemRWM` via `flopenrc MemRWWReg`
- `HasStoreW` ← `1'b0` (not tracked in V1)
- `SkipVerifyW` ← `1'b0` (decided at sW from IQ.SkipVerify instead)
- `IsFaultedInstrW` ← `1'b0`
- `DummyW` ← `DummyW` (from controller)
- `DummySelW` ← `DummySelW_s` (from `ieu.DummySelW_out`)
- `InstrValidW` ← registered `InstrValidM` via `flopenrc InstrValidWReg`

**StallW_prev removal**: An earlier version gated the push with `~StallW_prev` to prevent double-push on stall exit. This was removed because it caused skipped RQ entries during long stalls (e.g., 42-cycle I-cache miss): the instruction in M would sit there, then advance to W at stall exit — and without StallW_prev removal, the push at the first negedge after stall exit was suppressed, permanently losing that instruction from the RQ.

**N-entry associative forwarding** (for main D-stage):
- Scans all N entries from entry[0] (newest) down to entry[N-1] (oldest)
- Priority encoder: `for j = N-1 downto 0: if valid && we && rd!=0 && rd==Rs1D → hit`
- Newest entry wins (because the inner loop overwrites the hit with the newest match)
- Outputs: `RQ_HitA`, `RQ_ValA` (for rs1), `RQ_HitB`, `RQ_ValB` (for rs2)
- The scan is done against `Rs1D = Rs1E_rq` and `Rs2D = Rs2E_s` — these are actually **E-stage** register indices (Rs1 piped one stage from D to E, Rs2 exported from `ieu` as `Rs2E_out`), providing forwarding to the E-stage operands that are about to be computed.

---

### `shadow_pipeline.sv` — Shadow Pipeline

**Location**: `hdl/core/shadow/shadow_pipeline.sv`

**Stages**: sD (combinational decode from IQ head) → sE (shadow ALU) → sM (SQ pop) → sW (verification + regfile write).

**Stall/flush**: Shadow uses the **same** `StallD/E/M/W` and `FlushD/E/M/W` as main. Shadow has no independent stall source in V1.

#### SkipVerify Opcode Decode (combinational at sD)

`is_skip_verify(Instr32)` returns 1 for:
```
FP arith:       op == 7'b1010011 | 1000011 | 1000111 | 1001011 | 1001111
Int DIV/REM:    op == 7'b0110011 && f7 == 7'b0000001
LR/SC/AMO:      op == 7'b0101111
CSR (any):      op == 7'b1110011 && funct3 != 000
WFI/ECALL/EBREAK/MRET/SRET: op == 7'b1110011 && funct3 == 000 (covers all SYSTEM funct3=000)
Fence/fence.i:  op == 7'b0001111
FP load/store:  op == 7'b0000111 | 0100111
Integer load:   op == 7'b0000011   ← V1 addition; D-cache re-read not implemented
```

`sSkipVerifyD = is_skip_verify(sInstr32_in) | sIsHWCSR_in | sIsDummy_in`

SkipVerify is computed at sD and piped through sE→sM→sW.

#### sD Stage (combinational)

Extracts `sRs1D = sInstr32[19:15]`, `sRs2D = sInstr32[24:20]`, `sRdD = sInstr32[11:7]`, `sSkipVerifyD`, `sIsBranchD` from IQ head. No register reads.

#### sD → sE Pipeline Registers

`flopenrc` instances for: `sPC_E`, `sInstr32_E`, `sPCSrc_E`, `sRs1_E`, `sRs2_E`, `sRd_E`, `sSkipVerify_E`, `sIsBranch_E`, `sInstrValid_E`, `sIsDummy_E`, `sDummySel_E`.

Enable: `~StallE`. Clear: `FlushE`.

#### sE Stage — Shadow ALU

Operands come directly from OQ head (`oq_SrcAE`, `oq_SrcBE`). No intra-shadow forwarding in V1 (OQ already carries post-forwarded operands from main).

```systemverilog
alu #(P) salu(oq_SrcAE, oq_SrcBE, oq_W64E, oq_UW64E, oq_SubArithE,
              oq_ALUSelectE, oq_BSelectE, oq_ZBBSelectE,
              oq_Funct3E, oq_Funct7E, oq_Rs2E,
              oq_BALUControlE, oq_BMUActiveE, oq_CZeroE,
              sALUResultE, sIEUAdrE);
comparator #(P.XLEN) scomp(oq_SrcAE, oq_SrcBE, oq_BranchSignedE, sFlagsE);
mux2 #(P.XLEN) saltresult(oq_ImmExtE, oq_PCLinkE, oq_JumpE, sAltResultE);
mux2 #(P.XLEN) sieuresult(sALUResultE, sAltResultE, oq_ALUResultSrcE, sIEUResultE);
```

The shadow ALU re-uses the same `alu.sv` and `comparator.sv` modules as main. Control signals come from OQ, not from re-decoding IQ.Instr32. This is a key area saving over a full second pipeline (no second controller).

#### sE → sM Pipeline Registers

`flopenrc` instances for: `sPC_M`, `sInstr32_M`, `sPCSrc_M`, `sRs1_M`, `sRs2_M`, `sRd_M`, `sSkipVerify_M`, `sIsBranch_M`, `sInstrValid_M`, `sIEUResultM`, `sIEUAdrM`, `sFlagsM`, `sMemRW_M`, `sRegWrite_M`, `sIsDummy_M`, `sDummySel_M`.

`sRegWrite_M = oq_RegWriteE & sInstrValid_E` — gated by shadow validity.

#### sM Stage

V1 sM: pops the SQ head when shadow's instruction is a store and the pipeline advances.
```systemverilog
assign sM_pop = sInstrValid_M & sMemRW_M[0] & ~StallM & ~FlushM;
```
No actual D-cache access. No address comparison with SQ entry. The SQ pop is needed so SQ entries don't accumulate.

#### sM → sW Pipeline Registers

`flopenrc` instances for: `sPC_W`, `sInstr32_W`, `sPCSrc_W`, `sRd_W`, `sSkipVerify_W`, `sIsBranch_W`, `sInstrValid_W`, `sIEUResultW`, `sFlagsW`, `sIsDummy_W`, `sDummySel_W`.

#### sW Stage — Verification

Branch outcome decode from `sFlagsW`:
```systemverilog
case (sInstr32_W[14:12])  // funct3
  3'b000: sBranchTakenW =  sFlagsW[1];  // BEQ: Equal
  3'b001: sBranchTakenW = ~sFlagsW[1];  // BNE
  3'b100: sBranchTakenW =  sFlagsW[0];  // BLT: LessThan
  3'b101: sBranchTakenW = ~sFlagsW[0];  // BGE
  3'b110: sBranchTakenW =  sFlagsW[0];  // BLTU
  3'b111: sBranchTakenW = ~sFlagsW[0];  // BGEU
```

`FlagsE[1] = EQ` (from comparator), `FlagsE[0] = LT`.

`shadow_verifier` instantiation:
```systemverilog
shadow_verifier #(P) sv(
  .sInstr32(sInstr32_W),
  .sALUResult(sIEUResultW),
  .rq_IntResult(rq_IntResult),
  .rq_IntWriteEn(rq_IntWriteEn),
  .rq_SkipVerify(rq_SkipVerify | sSkipVerify_W),  // either side can declare skip
  .rq_InstrValid(rq_InstrValid & sInstrValid_W),   // both must be valid
  .sBranchTaken(sBranchTakenW),
  .rq_PCSrc(sPCSrc_W),
  .isBranch(sIsBranch_W),
  .rq_PC(rq_PC),
  ...
);
```

SkipVerify is asserted if either the RQ entry says skip OR shadow's sSkipVerify says skip. Verification requires both `rq_InstrValid` and `sInstrValid_W` to be 1.

**Regfile write logic**:
```systemverilog
wire write_enable = rq_InstrValid & ~FlushW & (rq_IntWriteEn | rq_DummyW);
assign shadow_we3      = write_enable;
assign shadow_a3       = rq_Rd;
assign shadow_wd3      = rq_IntResult;
assign shadow_DummyW   = rq_DummyW   & write_enable;
assign shadow_DummySel = rq_DummySelW;
```

Shadow writes the **RQ's committed result** (not its own ALU result). This ensures the regfile always contains a value from the main pipeline, not from the shadow ALU — maintaining deterministic architectural state. The write fires even when shadow has a bubble (sInstrValid_W=0): when FlushD created a gap in the shadow pipeline while the RQ continued filling, shadow trusts main's result and writes it unconditionally, skipping verification for that entry.

**VBC**: `VBC_StallE = 1'b0` (stubbed in V1).

**RQ pop**: `sW_pop = ~StallW & ~FlushW` — fires every cycle the W stage advances.

---

### `shadow_verifier.sv` — Result Comparator

**Location**: `hdl/core/shadow/shadow_verifier.sv`

Pure combinational. Two comparisons:
1. `result_mismatch = rq_IntWriteEn && (sALUResult != rq_IntResult)`
2. `branch_mismatch = isBranch && (sBranchTaken != rq_PCSrc)`

Output:
- `SecFaultMatch = 1` if `!rq_InstrValid || rq_SkipVerify` (silent pass) or both mismatches false
- `SecFaultMismatch = 1` if either mismatch true (when valid + not-skip)
- `SecFaultPC = rq_PC` on mismatch

In V1, `SecFaultMismatch` propagates to `ShadowFaultW` → `csrharden.sv` bit [6] → `SecFaultM[6]` → `MSECFAULT` register. No pipeline flush or trap is generated.

---

### `shadow_hzu.sv` — Shadow Hazard Unit

**Location**: `hdl/core/shadow/shadow_hzu.sv`

Simple 2-tier priority encoder:
- `sForwardAE = 10 (sE bypass)` if `sRegWriteE && sRdE != 0 && sRdE == sRs1`
- `sForwardAE = 01 (sM bypass)` if `sRegWriteM && sRdM != 0 && sRdM == sRs1`
- `sForwardAE = 00 (use OQ value)`
Same for B.

**Status in V1**: Module is coded and in the file tree but not instantiated by `shadow_pipeline.sv`. Shadow operands come directly from OQ. The HZU becomes necessary in a V2 where shadow operates independently (e.g., different stall rate from main due to private FUs). For V1 (synchronous shadow), forwarding within the shadow pipeline is redundant because the OQ operands already include main's forwarding result.

---

## Integration Changes (Pipeline Files)

### `wallypipelinedcore.sv`

**New signals declared** (excerpt from the SHARD section):
```
shadow_we3, shadow_a3[4:0], shadow_wd3[63:0]   — shadow regfile write port
shadow_DummyW_sp, shadow_DummySel_sp            — dummy redirect flags from shadow_pipeline
RQ_HitA/B, RQ_ValA/B[63:0]                     — RQ forwarding outputs before bypass
iq_*, oq_*, rq_*, sq_*                         — queue head outputs
SrcAE_s, SrcBE_s, ImmExtE_s                    — E-stage operand exports from ieu
ResultW_s, RegWriteW_s, DummySelW_s            — W-stage RQ push exports from ieu
Rs1D_s, Rs2D_s                                 — D-stage register indices from ieu
Rs1E_rq                                         — Rs1D_s piped one stage to E
bypass_val_r, bypass_rd_r, bypass_valid_r      — negedge bypass registers
cstall_hitA/B, cstall_valA/B, cstall_valid     — conflict-stall hold registers
StallE_r                                        — previous-cycle StallE
DummyE_s, DummySelE_s                          — E-stage dummy flags (from InjectD/DummySelD)
MemRWW, InstrValidW                            — W-stage RQ push: registered MemRWM, InstrValidM
ShadowFaultW                                   — SecFaultW_s wired to privileged unit
```

**Extra pipeline registers added in wallypipelinedcore.sv**:
```systemverilog
flopenrc #(2) MemRWWReg     (clk, reset, FlushW, ~StallW, MemRWM, MemRWW);
flopenrc #(1) InstrValidWReg(clk, reset, FlushW, ~StallW, InstrValidM, InstrValidW);
flopenrc #(1) DummyEReg     (clk, reset, FlushE, ~StallE, InjectD, DummyE_s);
flopenrc #(1) DummySelEReg  (clk, reset, FlushE, ~StallE, DummySelD, DummySelE_s);
flopenrc #(5) Rs1E_rq_reg   (clk, reset, FlushE, ~StallE, Rs1D_s, Rs1E_rq);
```

**W-stage PC register** (pre-existing but now also feeds RQ push):
```systemverilog
flopenrc #(P.XLEN) PCWReg(clk, reset, FlushW, ~StallW, PCM, PCW);
```

#### RQ Forwarding Negedge Bypass

```systemverilog
always_ff @(negedge clk) begin
  if (reset) begin
    bypass_valid_r <= 1'b0; bypass_rd_r <= '0; bypass_val_r <= '0;
  end else if (shadow_we3 & ~shadow_DummyW_sp) begin
    bypass_valid_r <= 1'b1; bypass_rd_r <= shadow_a3; bypass_val_r <= shadow_wd3;
  end else begin
    bypass_valid_r <= 1'b0;
  end
end
```

**Purpose**: Shadow writes the regfile at negedge T. The E-stage instruction (which just advanced from Decode at posedge T) captured R1E/R2E at posedge T — before the shadow write. At posedge T+1, R1E/R2E are re-read from the now-updated regfile. But `ForwardedSrcAE` is used as `WriteDataM` via the M-stage register (latched at posedge T+1 E→M). So the posedge T+1 E-stage computation uses correct R1E from the updated regfile, but the one-cycle gap at posedge T needs the bypass.

**Bypass priority**: lower than standard M/W forwarding and RQ associative scan. The bypass fills in only when RQ has no hit (`~RQ_HitA`).

**Dummy exclusion**: The bypass does not fire on dummy writes (`~shadow_DummyW_sp`) because dummy writes target shadow physical registers, not architectural registers, and should not be forwarded to main.

#### Conflict-Stall Forwarding Hold

```systemverilog
always_ff @(posedge clk) begin
  StallE_r <= StallE;
  if (reset | (~ShadowConflictStallE & ~StallE)) begin
    cstall_valid <= 1'b0;
  end else if (ShadowConflictStallE & ~cstall_valid) begin
    cstall_hitA  <= RQ_HitA_fwd; cstall_hitB  <= RQ_HitB_fwd;
    cstall_valA  <= RQ_ValA_fwd; cstall_valB  <= RQ_ValB_fwd;
    cstall_valid <= 1'b1;
  end
end
wire cstall_active = cstall_valid & (ShadowConflictStallE | (StallE_r & ~StallE));
```

**Purpose**: When `ShadowConflictStallE` fires, `StallW=0` (only E is stalled), so the RQ keeps shifting — evicting the entry the stalled E-stage instruction needs for forwarding. This logic captures the RQ hit/value at the first stall cycle (Rs2E is stable by then) and holds it through all stall cycles, plus one extra cycle after stall release so `WriteDataM` (latched at the first posedge after stall clears) sees the correct value.

**Release condition**: `reset | (~ShadowConflictStallE & ~StallE)` — clears when both the conflict stall and any other stall have ended. The one-extra-cycle extension uses `StallE_r & ~StallE`.

#### RVFI Monitor Fix

```systemverilog
// SHARD: shadow_pipeline writes regf at sW timing (N=3 cycles after main W).
// RVFI fires at main W — use main's W-stage signals for GPR reporting.
assign GPRAddr  = soc.core.RdW;
assign GPRWen   = soc.core.RegWriteW_s;
assign GPRValue = soc.core.ResultW_s;
```

Without this fix, the RVFI monitor would read `regf.we3/a3/wd3` which are driven by the shadow pipeline 3 cycles after the instruction retires in main — causing RVFI to see ghost writes at wrong cycle counts and miss real writes entirely.

---

### `ieu.sv`

New I/O ports added (all `input` or `output`):
- **Shadow write inputs**: `shadow_we3`, `shadow_a3[4:0]`, `shadow_wd3[63:0]`, `shadow_DummyW`, `shadow_DummySel`
- **RQ forwarding inputs**: `RQ_HitA`, `RQ_ValA[63:0]`, `RQ_HitB`, `RQ_ValB[63:0]`
- **OQ push outputs**: `SrcAE_out[63:0]`, `SrcBE_out[63:0]`, `ImmExtE_out[63:0]`
- **OQ control outputs**: `UW64E_out`, `SubArithE_out`, `ALUSelectE_out[2:0]`, `BSelectE_out[3:0]`, `ZBBSelectE_out[3:0]`, `BALUControlE_out[2:0]`, `BMUActiveE_out`, `CZeroE_out[1:0]`, `Funct7E_out[6:0]`, `Rs2E_out[4:0]`, `ALUResultSrcE_out`, `BranchSignedE_out`, `RegWriteE_out`
- **RQ push outputs**: `RegWriteW_out`, `DummySelW_out`, `ResultW_out[63:0]`
- **RQ scan D-stage outputs**: `Rs1D_out[4:0]`, `Rs2D_out[4:0]`

These are implemented as simple `assign` passthroughs from the local `controller` and `datapath` signals:
```systemverilog
assign UW64E_out = UW64E; assign SubArithE_out = SubArithE; // etc.
assign RegWriteW_out = RegWriteW; assign DummySelW_out = DummySelW;
assign Rs1D_out = Rs1D; assign Rs2D_out = Rs2D;
```

---

### `controller.sv`

One change: `RegWriteE` promoted from internal logic to output port (needed by `ieu.sv` to export as `RegWriteE_out` for the OQ push):
```diff
-logic RegWriteD, RegWriteE;
+logic RegWriteD;           // RegWriteE is now output port
+output logic RegWriteE;
```

---

### `datapath.sv`

**Regfile write port redirected to shadow**:
```systemverilog
regfile #(P.XLEN, P.E_SUPPORTED) regf(
  .clk, .reset,
  .we3(shadow_we3),     // was: RegWriteW (main pipeline)
  .a3(shadow_a3),       // was: RdW
  .wd3(shadow_wd3),     // was: ResultW
  .DummyW(shadow_DummyW), .DummySelW(shadow_DummySel),
  ...
);
```

Main no longer drives `we3/a3/wd3`. The main `RegWriteW` and `ResultW` values flow to shadow's RQ push instead.

**RQ associative forwarding insertion**:
```systemverilog
// Standard M/W bypass
mux3 #(P.XLEN) faemux(R1E, ResultW, IFResultM, ForwardAE, FwdSrcA_mw);
mux3 #(P.XLEN) fbemux(R2E, ResultW, IFResultM, ForwardBE, FwdSrcB_mw);
// RQ forwarding: lower priority — fires only when standard forwarding has no match
assign ForwardedSrcAE = (RQ_HitA & (ForwardAE == 2'b00)) ? RQ_ValA : FwdSrcA_mw;
assign ForwardedSrcBE = (RQ_HitB & (ForwardBE == 2'b00)) ? RQ_ValB : FwdSrcB_mw;
```

The `ForwardAE == 2'b00` guard ensures that the standard forwarding mux's in-pipeline result (from M or W stage) always beats the RQ scan. This matters because the standard forwarding reflects the current W-stage result which may be newer than any RQ entry.

**OQ push outputs**:
```systemverilog
assign SrcAE_out = SrcAE;   // post-ALUSrcAE mux
assign SrcBE_out = SrcBE;   // post-ALUSrcBE mux
assign ImmExtE_out = ImmExtE;
assign ResultW_out = ResultW;  // full mux5 output = committed architectural result
```

---

### `mdu.sv`

**ft_mul/ft_div removed**: The shadow-aware `ft_mul` and `ft_div` wrappers (which ran a secondary shadow multiplier/divider for per-instruction verification) were replaced with the base `mul` and `div` modules. SHARD verifies the MDU result end-to-end at sW (when `ResultW_s` — which includes `MulDivResultW` — is pushed to RQ). This is simpler and catches any fault in the entire MDU→Writeback path, not just the multiplication step.

```diff
-ft_mul #(P) ftmul(..., MulActiveE, fi_enable(1'b0), ...);
+mul #(P.XLEN) multiplier(.clk, .reset, .StallM, .FlushM,
+  .ForwardedSrcAE, .ForwardedSrcBE, .Funct3E, .ProdM);
```
DIV/IDIV_ON_FPU: same pattern, `ft_div` replaced with `div`.

MDU outputs `FTStallM`, `FTUnresolvedM`, `MUL_PE_p/r`, `DIV_PE_p/r` removed.

---

### `privileged.sv` / `csr.sv` / `trap.sv`

- `FTUnresolvedFaultM` input removed from `privileged.sv` and `trap.sv` (no longer an exception source; SHARD uses the CSR-only MSECFAULT path)
- `FTStatus[6:0]` input removed from `csr.sv`, `csrm.sv`, and `privileged.sv`
- `MFTSTATUS` CSR address (`0x7C2`) and its read path removed from `csrm.sv`
- `ShadowFaultW` added as input to `privileged.sv` and `csr.sv`; forwarded to `csrharden`

---

### `csrharden.sv`

New port and assignment:
```systemverilog
input  logic       ShadowFaultW,        // SHARD shadow pipeline mismatch detected
output logic [6:0] SecFaultM            // [6] = ShadowFaultW

assign SecFaultM[6] = ShadowFaultW;
```

`SecFaultM[6]` is sticky in the MSECFAULT register (software must write-to-clear). No pipeline flush, no trap, no retry in V1.

---

### `hazard.sv`

One addition to `StallECause`:
```systemverilog
assign StallECause = (DivBusyE | FDivBusyE | ShadowConflictStallE) & ~FlushECause;
```

`ShadowConflictStallE` stalls the Execute stage (and by propagation, Decode and Fetch) when the incoming E-stage store conflicts with any SQ entry. Memory and Writeback stages continue draining normally (StallM/StallW are unaffected).

---

## Area Cost Analysis: SHARD V1 vs. Full SMT Thread

The following estimates use TSMC 7nm standard-cell equivalents (GE). "Full SMT" means a second complete in-order pipeline sharing only the memory hierarchy.

### New Logic Added (SHARD Overhead)

| Module | Dominant cost | GE estimate |
|---|---|---|
| `shadow_iq.sv` (N=3, 104-bit entries) | 312 bits of negedge flop | ~750 GE |
| `shadow_oq.sv` (N=3, ~372-bit entries) | 1116 bits of negedge flop | ~2690 GE |
| `shadow_rq.sv` (N=3, 206-bit entries) + forwarding | 618 bits flop + priority encoder | ~2000 GE |
| `shadow_sq.sv` (N=3, 129-bit entries) + conflict detector | 387 bits flop + N×comparator | ~1400 GE |
| `shadow_pipeline.sv` — sD/sE/sM/sW regs | ~10 × 64 + misc = ~730 bits posedge flop | ~1750 GE |
| Shadow `alu` duplicate | Same as main ALU | ~6000–8000 GE |
| Shadow `comparator` duplicate | | ~200 GE |
| `shadow_verifier.sv` | 64-bit comparator + 1-bit mux | ~200 GE |
| `shadow_hzu.sv` (coded, not connected) | ~10 comparators | ~60 GE |
| Negedge bypass flop (64+5+1 bits) | | ~170 GE |
| Conflict-stall hold registers (2×64+2×1+3 bits) | | ~350 GE |
| Hazard unit addition (one OR gate) | | < 5 GE |
| `csrharden.sv` bit [6] | 1 wire assignment | < 1 GE |
| Extra pipeline registers in wallypipelinedcore | MemRWW(2), InstrValidW(1), DummyE(1), DummySelE(1), Rs1E_rq(5) = 10 bits | ~24 GE |
| **Total SHARD overhead** | | **~15,600–17,600 GE** |

### Logic Saved vs. Full SMT Thread

| Component eliminated/shared | Area saved |
|---|---|
| IFU (branch predictor, ITLB, decompressor, fetch FSM) — full duplicate | ~40,000–60,000 GE |
| I-cache (32 KB SRAM + tag array) — full second copy | ~600,000 GE (SRAM) |
| D-cache (32 KB SRAM + tag array) — second copy | ~600,000 GE (SRAM); shared 2-bank in SHARD |
| Integer regfile (32×64b + ECC) — full duplicate | ~12,000 GE |
| FP regfile (32×64b) — full duplicate | ~10,000 GE |
| DTLB (32-entry CAM) — full duplicate | ~8,000 GE |
| Privileged unit + CSR bank — full duplicate | ~25,000 GE |
| Controller — full duplicate | ~5,000 GE |
| MDU (ft_mul/ft_div removed vs. second mul+div) | ~15,000–20,000 GE |
| **Total SMT thread cost (sans FUs)** | **~1,315,000+ GE** |

SHARD V1 costs **~16,000 GE** of new overhead while eliminating the need for the ~1.3M GE+ of duplicated structures a full SMT thread requires. The net is approximately **98.8% area savings** relative to a full second thread. Even counting the shadow ALU duplicate (~7,000 GE), SHARD overhead is negligible relative to the full duplicated pipeline.

### Comparison to Specific Shadow ALU Cost

The dominant SHARD overhead is the shadow ALU duplicate at ~6–8k GE. If only ALU fault detection is required (and memory access/branch/control flow security is out of scope), the break-even analysis still firmly favors SHARD: the next cheapest scheme (adding a checker at commit with a second ALU and register file read ports) costs ~18,000 GE at minimum (regfile read ports alone: ~9,000 GE for 2 extra integer ports).

---

## Reconstruction Guide for a New Branch

This section is a step-by-step recipe to re-implement SHARD from scratch on a clean branch of this repo (e.g., starting from `main`).

### Step 0: Prerequisites

Ensure the base branch has:
- AMOEBA dummy instruction framework (`dummygen.sv`, `InjectD`/`DummySelD`/`DummyW` signals in IEU)
- `flopenrc_ecc` pipeline register (ECC hardening branch)
- `regfile` with `DummyW`/`DummySelW`/`we3`/`a3`/`wd3` ports
- `csrharden.sv` with the `SecFaultM` bus

If any of these are missing, merge the relevant feature branches first.

### Step 1: Create `hdl/core/shadow/` Directory and Queue Files

#### 1a. `shadow_iq.sv`

Entry width: `ENTRY_W = P.XLEN + 32 + 1 + 3 + 1 + 1 + 1 + 1` (104 bits for RV64).  
Fields in pack order (MSB→LSB): `{PC, Instr32, PCSrc, FRM_snap, IsHWCSR, IsDummy, DummySel, InstrValid}`.  
Clocking: **negedge**.  
Shift direction: `entry[N-1]` is head (output); `entry[0]` gets new push.  
Stall: `~StallD` gates the shift.  
Flush: Set only `entry[i][0]` (InstrValid) to 0 for all i on `FlushD`. Preserve data.

#### 1b. `shadow_oq.sv`

Capture the full E-stage decoded state. Fields: `{SrcAE, SrcBE, ForwardedSrcBE, PCLinkE, ImmExtE, [all ALU controls], MemRWE, RdE, RegWriteE, InstrValidE, DummyE, DummySelE}`.  
Clocking: **negedge**.  
`StallM = 1` → hold. `FlushE | FlushM` → inject null entry at 0.

#### 1c. `shadow_sq.sv`

Fields: `{PA[PA_BITS-1:0], WriteData[XLEN-1:0], ByteMask[XLEN/8-1:0], Valid}`.  
Clocking: **negedge**.  
Push when `StoreM` (= `MemRWM[0]`). Pop when `sM_pop`.  
Conflict detector: for each entry, check `valid & (PA[PA_BITS-1:2] == incoming_PA[PA_BITS-1:2]) & (ByteMask & incoming_ByteMask != 0)`.  
`ShadowConflictStallE = StoreE & (|conflict)`.

#### 1d. `shadow_rq.sv`

Fields: `{Rd[4:0], IntResult[XLEN-1:0], IntWriteEn, MemAddr[XLEN-1:0], MemRW[1:0], HasStore, PC[XLEN-1:0], SkipVerify, IsFaultedInstr, DummyW, DummySel, InstrValid}`.  
Clocking: **negedge**. Push at W-stage when `~StallW`.  
Associative forwarding: scan all N entries; newest match (entry[0] highest priority, entry[N-1] lowest). Output `RQ_HitA/B`, `RQ_ValA/B`. Gate on `valid && IntWriteEn && Rd != 0`.  
**Do not add StallW_prev guard** — it causes missed RQ entries on long stalls.

### Step 2: Create `shadow_pipeline.sv`

Instantiate the shadow stages:
- **sD**: decode `sRs1`, `sRs2`, `sRd` from IQ head `sInstr32`; compute `sSkipVerifyD` and `sIsBranchD`.
- **sD→sE**: `flopenrc` on `~StallE`/`FlushE` for all sD fields.
- **sE**: duplicate `alu` instance with OQ operands and OQ controls. Duplicate `comparator`. `mux2` for altresult/ieuresult.
- **sE→sM**: `flopenrc` on `~StallM`/`FlushM`.
- **sM**: just pop SQ on store advance (V1). No cache access.
- **sM→sW**: `flopenrc` on `~StallW`/`FlushW`.
- **sW**: decode branch outcome from `sFlagsW` + `sInstr32_W[14:12]`. Instantiate `shadow_verifier`. Drive regfile write port from RQ values. `sW_pop = ~StallW & ~FlushW`.

`VBC_StallE = 1'b0` (stub).

### Step 3: Create `shadow_verifier.sv`

```systemverilog
assign result_mismatch = rq_IntWriteEn && (sALUResult != rq_IntResult);
assign branch_mismatch = isBranch && (sBranchTaken != rq_PCSrc);
if (!rq_InstrValid || rq_SkipVerify) → match, no fault
else if (result_mismatch || branch_mismatch) → mismatch, fault
```

### Step 4: Create `shadow_hzu.sv`

2-tier priority encoder for `sForwardAE` and `sForwardBE`. Not wired in V1 but needed for V2.

### Step 5: Modify `controller.sv`

Promote `RegWriteE` from `logic` declaration to output port.

### Step 6: Modify `datapath.sv`

1. Add `shadow_we3/a3/wd3/DummyW/DummySel` input ports. Feed to `regfile` instead of `RegWriteW/RdW/ResultW`.
2. Add `RQ_HitA/B/ValA/B` input ports. Insert RQ bypass after the M/W forwarding mux:
   ```systemverilog
   assign ForwardedSrcAE = (RQ_HitA & (ForwardAE==2'b00)) ? RQ_ValA : FwdSrcA_mw;
   ```
3. Export `SrcAE_out = SrcAE`, `SrcBE_out = SrcBE`, `ImmExtE_out = ImmExtE`, `ResultW_out = ResultW`.

### Step 7: Modify `ieu.sv`

Add all shadow ports from `datapath.sv`. Forward `RegWriteW`, `DummySelW`, `ResultW`, `Rs1D`, `Rs2D`, and all E-stage control signals as outputs using `assign` passthroughs.

### Step 8: Modify `mdu.sv`

Replace `ft_mul`→`mul`, `ft_div`→`div`. Remove `FTStallM`, `FTUnresolvedM`, PE outputs.

### Step 9: Modify `privileged.sv` / `csr.sv` / `csrm.sv` / `trap.sv`

- Remove `FTUnresolvedFaultM` from `trap.sv` ExceptionM sum and `privileged.sv` I/O.
- Remove `FTStatus[6:0]` from `csr.sv`, `csrm.sv` I/O and remove `MFTSTATUS` CSR (0x7C2).
- Add `ShadowFaultW` input to `privileged.sv` and `csr.sv`; thread to `csrharden`.

### Step 10: Modify `csrharden.sv`

Add `ShadowFaultW` input port. Assign `SecFaultM[6] = ShadowFaultW`.

### Step 11: Modify `hazard.sv`

Add `ShadowConflictStallE` input. Add to StallECause:
```systemverilog
assign StallECause = (DivBusyE | FDivBusyE | ShadowConflictStallE) & ~FlushECause;
```

### Step 12: Modify `wallypipelinedcore.sv`

1. **Declare all SHARD signals** (see §Integration Changes above for the full list).
2. **Add extra pipeline registers**: `MemRWWReg`, `InstrValidWReg`, `DummyEReg`, `DummySelEReg`, `Rs1E_rq_reg`.
3. **Instantiate four queues**: `shadow_iq`, `shadow_oq`, `shadow_rq`, `shadow_sq` with `N=3`.
   - IQ push: `PCF=PCSpillF`, `InstrD`, `PCSrcD=PCSrcE` (use Execute-stage PCSrc), `FRM_D=FRM_REGW`, `IsHWCSR_D=1'b0`, `IsDummyD=InjectD`, `DummySelD`, `InstrValidD`.
   - OQ push: all E-stage signals from `ieu` `*_out` ports.
   - RQ push: `RdW`, `ResultW=ResultW_s`, `RegWriteW=RegWriteW_s`, `PCW`, `MemRWW`, `HasStoreW=1'b0`, `SkipVerifyW=1'b0`, `IsFaultedInstrW=1'b0`, `DummyW`, `DummySelW=DummySelW_s`, `InstrValidW`. RQ scan: `Rs1D=Rs1E_rq`, `Rs2D=Rs2E_s`.
   - SQ push: `IEUAdrM[PA_BITS-1:0]`, `WriteDataM`, `ByteMaskM={XLEN/8{1'b1}}`, `StoreM=MemRWM[0]`.
4. **Negedge bypass**: implement the `bypass_valid_r/rd_r/val_r` flops; merge with RQ outputs as `RQ_HitA_fwd/ValA_fwd`.
5. **Conflict-stall hold**: implement `cstall_*` logic; produce `final_hitA/B/valA/B`.
6. **Instantiate `shadow_pipeline`** with all queue head outputs; route `shadow_we3/a3/wd3` to `ieu` shadow write ports; route `final_hitA/B/valA/B` as `RQ_HitA/B/ValA/B` to `ieu`.
7. **Wire `ShadowConflictStallE`** from SQ to `hazard`.
8. **Wire `ShadowFaultW = SecFaultW_s`** to `privileged`.
9. **Wire `final_hitA/B/valA/B`** to `ieu` after the conflict-stall hold logic.

### Step 13: Fix RVFI Monitor (`rv64_core_wrapper.sv`)

```systemverilog
assign GPRAddr  = soc.core.RdW;
assign GPRWen   = soc.core.RegWriteW_s;
assign GPRValue = soc.core.ResultW_s;
```

This is required because shadow writes the regfile N cycles after main's W-stage, misaligning RVFI's per-instruction commit reporting.

### Step 14: Add Tests

**Baremetal tests** (in `testcode/baremetal/`):
- `test_fwd_depth.c`: exercises RQ forwarding at distances 1–7+ using `__asm__` spacers and volatile dependency chains. Tests that forwarding is correct from M/W-stage bypass (dist 1–3), RQ forwarding (dist 4–6), and regfile (dist 7+).
- `test_sp_fwd.c`: exercises sp-update-then-store forwarding at distances 1–5. Noinline functions trigger I-cache miss stalls that stress the conflict-stall hold and negedge bypass.

**ISA-level tests** (in `testcode/isa_level_testing/`):
- `tc_forwarding.c`: structured forwarding test covering M/W bypass, RQ forwarding, regfile reads, SP forwarding, dependency chains, load-use hazards, write-after-write, and nested calls.

---

## Known V1 Limitations

1. **No D-cache re-read**: stores and loads are SkipVerify. Shadow does not independently verify memory access results. A faulty store data path or cache write would not be detected.

2. **No VBC**: JALR target faults, exception-window faults, and MRET/SRET tampering are not caught.

3. **PCSrc timing off-by-one**: IQ captures `PCSrcE` (Execute-stage) when the instruction is in Decode. Functionally correct due to flush propagation but not cycle-exact per the Rev 5 spec.

4. **ByteMask all-1s**: SQ conflict detector is overly conservative for sub-word stores. May stall unnecessarily on byte/halfword store pairs that don't overlap at byte granularity.

5. **No FP verification**: FP instructions are SkipVerify. FP register file is not written by shadow.

6. **No AMO verification**: AMO instructions are SkipVerify.

7. **No CSR re-read**: CSR read instructions are SkipVerify.

8. **MSECFAULT is non-trapping**: `SecFaultM[6] = ShadowFaultW` is logged to the MSECFAULT register but does not generate a trap or pipeline flush. Software must poll MSECFAULT.

9. **`shadow_hzu.sv` not connected**: intra-shadow forwarding is absent. This is correct for V1 (synchronous shadow with OQ operands) but means a V2 with independent shadow stalls would need to re-wire it.

10. **MemAddr always 0 in RQ**: The RQ `MemAddr` field is pushed as `'0`. Store address verification (shadow sM check against SQ PA) is not implemented.
