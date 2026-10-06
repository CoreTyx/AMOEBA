# SHARD — FINAL DETAILED IMPLEMENTATION (Rev 6 / V2)

> This section is the authoritative description of what the RTL on branch
> `sai-shard-impl` actually implements after the V2 verification work. The
> original Rev 5 design review (the critique that motivated these fixes) is
> preserved below under "Original design review (Rev 5 critique)". Companion
> docs: `hdl/core/shadow/SHARD_IMPLEMENTATION.md` (module-level reconstruction
> guide), `shadow_thread.md` §"Rev 6" (the plan), `sim/shadow_debug_progress.md`
> (debug trail).

## 0. Validation status (V2)

- `make baremetal_regression` → **5/5**
- `make isa_regression` → **9/9**
- `make freertos_regression` → **5/5**
- `make linux_boot` → OpenSBI 1.4 → Linux 6.6 → userspace `AMOEBA_LINUX_BOOT_OK`.
  All V2 changes are confined to the *verification* path (see §1), so commit/boot
  behavior is unchanged.
- **Load-data verification is live and non-vacuous:** 1208 loads re-derived and
  matched in `sorting_algo`, 0 false faults across all tiers; a 1-bit fault
  injection fires it 17× (true-positive).

## 1. The single most important structural fact about V2

**Every V2 change is confined to the shadow *verification* datapath and cannot
affect architectural state.** The main register file is committed from the RQ
head alone (`shadow_we3/a3/wd3 = f(rq_*)`); RQ→main forwarding is `f(RQ entries)`
only. Neither depends on the IQ, OQ, SQ, the shadow ALU, or the verifier. So the
verifier can be made as strict as we like with **zero risk** to the booting
machine: a false mismatch only sets the (non-trapping) MSECFAULT alarm. This is
why V2 could tighten verification aggressively while keeping Linux booting.

## 2. What SHARD can independently verify (and what it structurally cannot)

SHARD is a **trailing shadow**, not a symmetric dual thread. The main pipeline
(leading thread T0) has already performed every memory/bus/CSR side effect and
retired before the shadow (trailing T1) sees the instruction. Two consequences:

1. **The "single physical action" requirement from the RMT literature
   (`improvement_ideas.md`) is satisfied by construction.** The shadow never
   issues to the bus/cache/CSR (the destructive V1 re-read is *disabled* — see
   §4). So AMOs are not double-issued, fences are not double-barriered, CSRs are
   not double-written. Nothing special is needed to "decouple side effects"; the
   shadow simply has none.
2. **Independent verification requires the shadow to recompute the value.** The
   shadow's operands arrive via the OQ *already forwarded by the main*, so it can
   independently recompute:
   - **ALU / bit-manip results** (own ALU) — detects FU datapath faults.
   - **Branch direction** (own comparator).
   - **Effective addresses** (own address adder) — detects AGU/immediate-sum
     datapath faults for loads, stores, (and AMOs by extension).
   It **cannot** independently reproduce values that depend on state it does not
   model: loaded data (memory array — SECDED-covered), CSR values (no CSR
   mirror), AMO memory old-values, or operand *selection* (forwarding muxes feed
   the OQ). These are documented coverage boundaries (§6), not bugs.

## 3. Verification mechanism (`shadow_verifier.sv`, Rev 6)

At sW the verifier compares the shadow's recomputation against the RQ entry,
gated to be **sound under transient queue slip**:

```
pc_match        = (sPC == rq_PC)                 // shadow (IQ path) vs RQ agree on instruction
result_mismatch = rq_IntWriteEn & ~isLoad & (sALUResult != rq_IntResult)
branch_mismatch = isBranch       & (sBranchTaken != rq_PCSrc)
ea_mismatch     = (isLoad|isStore) & (sEA != mainEA)     // mainEA = RQ.MemAddr
fault = rq_InstrValid & sInstrValid_W & sOQValid_W & pc_match
        & ~rq_SkipVerify & (result_mismatch | branch_mismatch | ea_mismatch)
```

Three gating terms make this **sound** (no false positives) despite the IQ/OQ/RQ
being filled at different pipeline points:
- `pc_match` — the IQ-fed shadow PC must equal the RQ PC (same instruction).
- `sOQValid_W` — the **OQ** (operand) path must also be valid. Around a load-use
  bubble the IQ (PC) stays valid while the OQ bubbles; without this gate the
  shadow would compare bubble operands (result 0) against a real RQ result and
  false-fault. `oq_InstrValidE` is threaded sE→sM→sW for this.
- `~isLoad` on the result compare — a load's architectural result is memory
  data, not an ALU output, so it is verified by **EA**, not by result equality.

Measured behavior: on correct code `SecFault==0` across all tiers; the EA
comparison is exercised and passes (`EA_OK`) on cycles where the memory op is
queue-aligned, and is soundly *skipped* (not faulted) during transient slip.

## 3a. Load-DATA verification (V2) — self-contained, alignment-free

In addition to the EA check, the shadow now **independently re-derives the loaded
value**. The LSU exports the raw aligned read word (`RawReadDataWordM` =
`ReadDataWordMuxM`, the D$/DTIM read-mux output *before* subword extract); it is
piped to W and carried, with `Funct3`, in the RQ entry alongside `MemAddr` and
`IntResult`. At sW the shadow instantiates its **own copy of `subwordread`**, fed
by `{rq_RawLoadWord, rq_MemAddr[3:0], rq_Funct3}`, and compares its result to
`rq_IntResult`:

```
rq_is_int_load     = (rq_MemRW == 2'b10) & rq_IntWriteEn & rq_InstrValid  // pure load, not AMO/store/FP
load_data_mismatch = rq_is_int_load & (subwordread(rawword,addr,funct3) != rq_IntResult)
SecFaultW          = sv_mismatch | load_data_mismatch
```

Because the raw word, address, size and result all live in the **same RQ entry**,
this check is **self-contained** — it needs no IQ/OQ/shadow-pipeline alignment and
no `pc_match`/`sOQValid` gating, so it is exercised on essentially every integer
load (measured: 1208 loads verified in `sorting_algo`, 29 in `test_fwd_depth`,
all correct, zero false faults). It covers the subword-extract / sign-extend
datapath with an independent logic copy; the raw SRAM word is SECDED-covered.
**True-positive validated:** injecting a 1-bit corruption into the shadow's raw
word fired `load_data_mismatch` 17× in `test_fwd_depth` (e.g. expected `0xd` vs
committed `0x5`), confirming the check is not vacuous.

## 4. Effective-address verification (loads/stores) — the V2 feature

- Main's observed access address `IEUAdrM` is piped to `IEUAdrW`
  (`wallypipelinedcore.sv`) and packed into the previously-unused **RQ.MemAddr**
  field (`shadow_rq.sv`).
- The shadow's own address adder output `sIEUAdrE` is piped sM→sW (`sIEUAdrW`).
- The verifier raises `ea_mismatch` when they differ for a load/store.
- Integer loads are **no longer SkipVerify** — they are EA-verified (their data
  is trusted: SECDED SRAM). This closes V1 limitation #1 (loads fully skipped)
  and the review's "VA-vs-PA address check" item: we compare the shadow's EA to
  the *main's actual access address*, not a VA to a PA, so it is correct under
  translation (both are the same post-AGU address).

## 5. Why the V1 destructive re-read stays disabled

The V1 shadow D-cache re-read drove the shared cache port; a forced read of a
just-stored **dirty** line mis-indexed and triggered a writeback+refill that
overwrote the store with stale memory (root-caused in
`sim/shadow_debug_progress.md`). V2 keeps `shadow_needs_dcache_M = 0`. Instead of a destructive second cache
access, the load *data* is re-verified by **capturing the raw read word at the
main's access and re-deriving** the loaded value in the shadow (§3a) — the
non-destructive realization of "re-read and verify the data" (and exactly the
LVQ/bypass-the-memory-interface principle from `improvement_ideas.md`). The load
*address* is independently checked (§4). Verifying that a store's write actually
landed in the array (a true post-write read) still requires the **deferred store
commit** (SQ as a store buffer, cache write issued post-verify, loads snoop the
SQ) — specified as Rev 7 below.

## 6. Per-class status vs. `improvement_ideas.md`

| Class | "Single physical action" | Independent value check | Status |
|-------|--------------------------|-------------------------|--------|
| Load  | by construction (no re-issue) | **EA verified** + **DATA re-derived** (own subwordread) | **Implemented (Rev 6)** |
| Store | by construction | **EA verified**; **commit gated on independent AGU recompute** | **Implemented (Rev 6/7)** |
| ALU/branch | n/a | result / direction re-executed | **Implemented** (sound) |
| AMO   | by construction (never re-issued) | **`old OP rs2` recomputed by a 2nd `amoalu`** vs the written value | **Implemented (Rev 7)** |
| CSR   | by construction; write serialized by `CSRWriteFenceM` | **csrrw/s/c write value recomputed** by a 2nd modify+mux vs `CSRWriteValM` | **Implemented (Rev 7)** |
| next-PC | n/a | **sequential PC+ilen recomputed**, redirect-aware | **Implemented (Rev 7)** |
| Fence | by construction (shadow has no bus) | reached-PC + no prior mismatch (via next-PC/opcode) | boundary |

All Rev 7 checks follow the **independent-recompute** pattern used by the shadow
ALU: a second copy of the datapath (amoalu / CSR modify-mux / AGU adder) runs on
the same captured operands and a disagreement raises MSECFAULT.  This catches
transient faults (SEU) in either copy; a permanent/trojan fault common to both
copies is the documented shared-FU boundary (residue-check mitigation, §area).

The literature's LVQ/sync-barrier machinery exists to stop a *second* thread from
re-issuing side effects; SHARD's trailing shadow never issues them, so that half
is free. The remaining half — recomputing AMO/CSR *results* — needs state the
shadow does not yet model (a CSR mirror, an AMO old-value LVQ). That is the
honest boundary and the content of Rev 7.

## 7. Rev 7 — IMPLEMENTED (AMO / CSR / next-PC / gated store commit)

All four Rev 7 items are implemented and validated (each: sound — 0 false faults
across baremetal/ISA/FreeRTOS/Linux — plus a fault-injection true-positive).

1. **AMO** (`lsu.sv`): a second `amoalu` instance recomputes `old OP rs2` from the
   same operands the main AMO ALU used; `AMOFaultM = LSUAtomicM[1] & ~LSUFlushW &
   (ShadowAMOResultM != IMAWriteDataM)`, piped to W and folded into MSECFAULT.
   Validated: 30 AMOs/0 false, injection fires 72×.
2. **CSR** (`csr.sv`): a second csrrw/csrrs/csrrc modify+mux recomputes the write
   value from `CSRReadVal2M`/`CSRSrcM`; `CSRFaultM = CSRWriteM &
   InstrValidNotFlushedM & (ShadowCSRWriteValM != CSRWriteValM)`. Validated on
   FreeRTOS CSR traffic/0 false, injection fires. (No full CSR-state mirror
   needed — this verifies the modify datapath; opaque CSR *effects* remain a
   boundary.)
3. **Gated store commit** (`wallypipelinedcore.sv`): an independent AGU adder
   (`SrcAE+SrcBE`) recomputes the store EA at the commit point and checks it
   against `IEUAdrE`; mismatch raises MSECFAULT, and `GATE_STORE_ON_SECFAULT`
   (default 0) clears the store's write bit into the LSU so a mis-addressed store
   cannot corrupt memory — verify-before-commit without a store buffer. Validated:
   1032 stores/0 false, injection fires 1116×. This is the microarchitecture-
   appropriate realization of "deferred store commit"; see §7a for the heavier
   full-DIVA alternative and why it was not chosen.
4. **Next-PC continuity** (`shadow_pipeline.sv`, RQ-self-contained): consecutive
   committed RQ entries must satisfy `PC_{k+1} == PC_k + ilen` (ilen from the
   carried `Compressed` flag) unless `IsCtrlFlow` or a trap/redirect (FlushW since
   last commit) breaks the stream. Validated: 5754 checks/0 false, injection fires.

### 7a. Why not the full DIVA store buffer / shadow decoupling
The classic "SQ-as-store-buffer, cache write issued post-verify, loads snoop the
SQ" requires (a) **decoupling the shadow** from the main (SHARD is coupled-stall;
holding a store for the N-behind shadow to verify deadlocks — the shadow needs the
main to advance to fill its queues), (b) a **deferred cache-write path that shares
the single D-cache port** (the exact hazard that caused the V1 destructive-re-read
bug), (c) **store-to-load forwarding** (CAM + byte-merge in the load path), and
(d) a **recovery/replay** mechanism to make prevention meaningful. That is a
ground-up rearchitecture (a future "Rev 8"/decoupled-shadow design). The Rev 7
gated-commit above achieves the same security property for the independently-
checkable part (store address) at the commit point, safely and incrementally.

## 7b. Remaining future work
- Decoupled-shadow + full store buffer with load forwarding + replay (Rev 8).
- MUL/FMA residue check (shared-FU permanent-fault coverage).
- Independent operand-select (forwarding mux) verification.

---

# Original design review (Rev 5 critique)

Bottom line: the architecture is sound and the area argument vs. a second thread holds, but (1) the queues, not the duplicated FUs, are the dominant overhead and are ~2.5× fatter than they need to be, (2) three things are functionally wrong as written (PA comparison at Execute, VA-vs-PA address checks, RQ orphan on FlushW), and (3) the biggest structural win is deferring D-cache store commit to after shadow verification, which removes the JALR VBC stall, the conflict-stall machinery, and the "stores present → trap" dead end in one move.

Must-fix correctness issues

Conflict detector compares PA at Execute, but PA doesn't exist at Execute. In Wally the DTLB lookup happens in M on IEUAdrM; at E you only have the VA. Either compare page-offset bits only ([11:3] + byte mask — VA and PA agree on these, conservative on synonyms, and a 9-bit comparator instead of ~53 bits), or move detection to M. Compare against lsu.sv/dtlb to confirm the stage.

shadow_computed_addr == RQ.MemAddr / SQ.PA compares a VA to a PA. Shadow computes rs1+imm (VA); SQ/RQ hold the PA needed for the re-read. With translation on, this check fails on every access. Options: store VA too (+64 bits/entry, expensive), or check only [11:0] and explicitly accept that the DTLB/translation path is out of scope (ECC on TLB entries covers storage, not lookup logic). State this as a coverage boundary.

Trap VBC still orphans the trapping instruction. FlushWCause clears the W register, so the doc's "pushes a valid RQ entry when it advances to W" doesn't happen. At release time (N=3) shadow has the trapping instruction at sM and will hit an empty RQ one cycle later. Simplest fix: assert a shadow-pipeline flush (sD/sE/sM) on FlushWCause — at that moment every instruction older than the trap is already verified, so the flush discards exactly the trapping instruction and nothing else. This also removes the IsFaultedInstr field and its special-casing.

VBC hold latches must clear on flush, or you deadlock. JALR at E, older instruction at M traps → E is flushed, the JALR is gone from the IQ, shadow never executes it, StallE_JALRVBC never releases. Same for interrupts and mispredict-flush of the JALR itself. Specify clear-on-FlushE/IQ-flush explicitly. A consolidated stall/flush matrix (source → stages stalled → queues flushed → VBC latches cleared) belongs in the doc; there are now ~6 stall sources scattered across sections and their interactions are where this design will break in simulation.

Conflict-stall counter is fragile; use the actual condition. Fixed N-1 count with pause-on-shadow-miss, pause-on-HPTW, etc. is a bug farm. Hold the store until the matching SQ/RQ entries are popped — that's the exact condition, and it's one OR of N valid&match bits.

Structural recommendations (largest wins first)

1. Deferred store commit — SQ becomes a real store buffer. Main writes the SQ at M but the D-cache write is issued from the SQ head only after shadow verifies address+data. Consequences:

Stores are the only irreversible side effect in the retry window. With them deferred, every non-memory fault becomes flush+retry; the "HasStore in window → M-mode trap" case disappears.
JALR VBC disappears (a wrong JALR target can no longer commit anything before shadow catches it), saving 3 cycles per indirect call/return — currently ~10–15% IPC on call-heavy code.
Conflict detection disappears (shadow reads before the write lands).
The store re-read (verifying the cache write landed) goes away; you lose direct coverage of the cache write path, but note your current response for that fault class is log-and-continue anyway, and SECDED on the SRAM covers data corruption. If you want it, keep it as a sampled check.
Cost: main loads must snoop the SQ (N-entry page-offset CAM — the same comparators the conflict detector already needed — plus a byte-merge mux at M→W, and stall on partial overlap rather than merge). AMOs need to execute against SQ-forwarded data or stall on SQ hit. This is what DIVA (Austin, MICRO'99) effectively does at checker commit; it's the natural endpoint of your "main never writes golden state" principle applied to memory.

Keep exception VBC — privilege/CSR state changes are the other irreversible effect and exceptions are rare enough that the stall is free.

2. Slim the RQ from ~535 to ~150 bits/entry. An instruction has one result. IntResult, FPResult, ReadData, CSRRdata, TrapReturnTarget are five 64-bit fields of which exactly one is ever valid — collapse to Result[63:0] + a 2–3-bit type tag. RQ.PC is redundant: shadow pops IQ and RQ in lockstep and already carries the PC. MemAddr for stores duplicates SQ.PA. Result ≈ Rd(5)+FP-sel(1)+Result(64)+PA(56)+ByteMask(8)+fflags(5)+flags(~6) ≈ 146 bits. This also collapses the main-thread RQ forwarding mux to a single 64-bit N:1.

3. Slim the OQ from 320 to 192 bits. No instruction uses 2 integer + 3 FP operands. Three 64-bit slots with an int/FP select at push (FMA is the only 3-source case). Clock-gate unused slots per instruction type — the OQ is pushed every cycle and is your largest single toggle source.

Net: queue flops drop from ~4800 to ~1700 bits (IQ 306 + OQ 576 + RQ ~450 + SQ 384). At ~7 GE per enabled flop plus read muxes, that's ~35k GE → ~13k GE — larger than everything else in SHARD combined, and larger than the duplicated ALU/BMU/KMU. The doc's "303 bits, 0 extra logic" for the IQ is optimistic: each FIFO needs pointers and an N:1 read mux. Implement queues as circular buffers, not shift registers (N× less toggling per push).

4. Replace shadow_fdivsqrt with multiplicative verification. Integer: check q·d + r == n and 0 ≤ r < d (plus the spec's div-by-zero/overflow cases) using the shared MUL — 2–3 cycles instead of 64–128, and it removes the private radix-2 divider entirely. FP div/sqrt: compute the residual n − q·d (or n − q·q) with one FMA and check it against the ±½ ulp bound implied by the rounding mode; this is the standard FMA-based correctly-rounded-quotient check (see Cornea/Harrison/Tang, Scientific Computing on Itanium, and Ercegovac & Lang, Digital Arithmetic), with care for tie and subnormal cases. Bonus: multiply-vs-divide is algorithmically diverse, which is exactly what you want against a trojan in the divider. Also fixes the current behaviour where any DIV stalls main for the full shadow-divider latency minus 3 cycles.

5. Add a next-PC continuity check at sDecode. Shadow computes expected next PC (PC+2/4, or PC+imm on taken branch/JAL — needs a 1-bit "was compressed" flag in the IQ) and asserts IQ[k+1].PC == expected. ~64-bit adder + compare, ~600–800 GE. Without it, the "control-flow hijack" coverage claimed in the overview only holds for JALR and branch conditions; a fault in the IFU target adder or the PC mux is invisible today. PCSrc becomes redundant with this check.

Area / power / timing specifics
Shared MUL and FMA are a shared fault point. Both threads run the same hardware, so a stuck-at or trojan in the multiplier produces identical wrong results twice — only transients are caught. For the stated threat model this is the largest coverage hole. Cheapest mitigation: residue (mod-3 or mod-255) checking on the multiplier array, ~5–10% of multiplier area, standard for permanent-fault detection. The private, algorithmically different DIV was a genuine strength of Rev 5 — extend that philosophy rather than the sharing one.
Forwarding-select logic is unverified. Shadow consumes main's post-forwarded operands, so a wrong ForwardAE/BE select is invisible; ECC on the pipeline registers doesn't help because the fault is in mux control. Cheap fix: push the 2-bit select codes into the OQ, and have shadow recompute the expected select from its rs fields vs. the Rd history it already holds in sE/sM/RQ. A few dozen gates. This also closes the hole in JALR verification (shadow's rs1 comes from the OQ).
StallE from the conflict comparator is a timing bomb. ALU output → comparator → hazard OR → global stall enable fanning out to every F/D/E flop. Even with the page-offset compare, don't put this on StallE; register it and apply it as a D-cache FSM hold on the store in M (the same path LSUStallM already uses). Similarly, derive IQ-full one cycle early (almost-full flag) so it's a registered stall term.
RQ associative forwarding lands on the ALU input path. Wally's forward mux in E is typically near-critical. Do the RQ match+mux in D in parallel with the FF-regfile read (RQ contents are stable flops) so E sees the same 3-way mux as today.
Verifier → regfile write enable. A 64-bit compare gating we3 that fans out to 32×64 write enables is a real path. Register the match and commit one cycle later (sW → sC); the forwarding window grows by one entry, which is cheap now that the RQ is slim.
VBC JALR release (if you keep it): tag with the IQ write pointer at push and release on pop of that index — a 2-bit compare instead of a 64-bit PC compare.
D-cache re-read power. Every cacheable load (and, today, store) costs a full tag+all-ways data read; that's plausibly +30–40% D-cache dynamic energy. Store the hit-way index (2 bits for 4-way) in RQ/SQ and re-read only that way's word — ~4× less read energy, and comparing that way's tag adds coverage of way selection. Banking by set parity is not area-neutral: two 16 KB macros carry duplicated periphery (~5–10%) and add a mux level on the read path; with way-hinted reads the bank-conflict rate matters less and you might not need banking at all.
Misaligned stores: don't widen every SQ entry to 128-bit data for a rare case; push two SQ entries.
PC width: the IQ stores 64-bit PCs for a ≤57-bit VA space. If you're willing to argue canonical-form, store [VA_BITS-1:0] and sign-extend.
Retry loop protection: a permanent fault in retryable logic causes infinite flush+retry. Add a per-PC retry counter that escalates to the M-mode trap after k attempts.
Fault-tolerance efficacy

Rated against the stated threat model (structural/logic faults and trojans, not soft errors):

Detection, integer/branch/load datapath: strong — duplicated ALU/BMU/KMU, independent branch resolution, cache re-read for loads. ~8/10.
Detection, MUL/FPU: weak for permanent faults (shared hardware). ~3/10 without residue checks; ~7/10 with.
Detection, control flow: JALR and branch condition only; IFU next-PC, forwarding control, hazard unit, DTLB lookup are uncovered. ~4/10; ~7/10 with the continuity and forwarding-select checks.
Recovery: partial. Non-memory faults without stores in the window are retryable; anything else is detect-and-trap or log-only. Deterministic (trojan) faults are never fixed by retry, so the value is in detection latency (~N+4 cycles) and containment, and containment is exactly what deferred store commit buys you. ~5/10 as written; ~8/10 with deferred commit and retry escalation.
Checker integrity: the verifier, the shadow-only regfile write port, and the queues are single points with no self-check. A comparator stuck at "match" silently disables SHARD. Consider a periodic canary (inject a known mismatch, expect MSECFAULT) or a dual-rail compare — a few hundred gates for a large assurance gain, and it's what an evaluator will ask about first.

Overall as written: ~6/10 — a solid detector for the ALU-centric fault classes with real coverage gaps in exactly the shared and control paths a trojan designer would target. With items 1, 4, 5, residue checks, and forwarding-select verification: ~8.5/10, at lower area and higher IPC than Rev 5.
