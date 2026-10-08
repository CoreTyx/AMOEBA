# SHARD — FINAL DETAILED IMPLEMENTATION (Rev 8)

> This section is the authoritative summary of what the RTL on branch
> `sai-shard-impl` implements. The module-level description is
> `hdl/core/shadow/SHARD_IMPLEMENTATION.md`; the design history is
> `shadow_thread.md`. The Rev 5 design review that motivated most of this work is
> preserved below under "Original design review (Rev 5 critique)", with a table
> of what became of each recommendation (§6).

## 0. Validation status

- `make baremetal_regression` → **5/5** (Spike co-simulation)
- `make isa_regression` → **9/9**
- `make freertos_regression` → **5/5**
- `make linux_boot` → OpenSBI 1.4 → Linux 6.6 → userspace `AMOEBA_LINUX_BOOT_OK`
- `make ecc_baremetal_regression` → **8/8** (not a SHARD test, but the regfile and
  Execute-stage read path it exercises changed)
- **Soundness:** 0 shadow faults, 0 Memory-stage faults, 0 replays and 0 cause-16
  traps in every one of those runs, measured with temporary instrumentation
  (since removed). The instrumented Linux boot is summarised in §0a.
- **Effectiveness:** every check fires under fault injection, and a transient
  fault is recovered with the test still passing (`SHARD_IMPLEMENTATION.md` §13.3).

### 0a. What the checks saw during the instrumented Linux boot

The boot reached `AMOEBA_LINUX_BOOT_OK` after 191,579,897 cycles (the Rev 7
figure was about 173M, so roughly +11%). Counters were also printed every 8.4M cycles;
all 22 windows show zero faults.

| | count |
|---|---|
| Instructions verified and committed by the shadow | 50,417,723 |
| Shadow faults / Memory-stage faults / replays / cause-16 traps | 0 / 0 / 0 / 0 |
| Stores committed through the store buffer | 8,996,635 |
| Loads re-derived from the raw word | 8,810,989 |
| Loads that took at least one byte from the store buffer | 32,705 |
| Memory accesses through the second AGU adder check | 17,906,966 |
| Instructions operand-checked against the regfile in the Memory stage | 4,472,459 |
| Instructions that waited for a quiescent shadow (serialized) | 1,064,651 |
| AMOs | 75,169 |
| CSR reads checked against the mirror / CSR writes checked | 74,175 / 72,405 |
| Traps taken (each one a mirror trap-entry check) | 325 |
| Integer multiplies residue-checked | 85,827 |
| FMA operations | 0 (the kernel uses no FP; covered by `tc_shard_direct`) |
| Cycles the store-buffer drain owned the LSU | 57,210,975 (30%; mostly cache-miss handling for those stores) |
| Cycles an instruction was held in the Memory stage | 4,981,478 (2.6%) |

The bare-metal, ISA and FreeRTOS regressions and the two `testcode/shard` tests
were run with the same instrumentation: zero faults in each.

## 1. What changed in Rev 8, in one paragraph

Through Rev 7 the shadow trailed the main pipeline by a fixed three cycles, shared
its stalls, and could only raise a flag: by the time it disagreed, the main
pipeline had already written memory and CSRs, and the register write went ahead
regardless. Rev 8 turns the shadow into the commit point. It is decoupled from the
main pipeline's stalls, it sources its operands from verified state rather than
from the main pipeline, stores wait in a real store buffer until it has verified
them, anything that cannot be deferred waits in the Memory stage until it has
caught up, and a mismatch flushes and replays instead of logging.

## 2. The structural facts to keep in mind

1. **Three gates, no exceptions.** A register write waits in the RQ; a store waits
   in the SQ; everything else waits in the Memory stage for the shadow to be
   quiescent and is checked there. (`SHARD_IMPLEMENTATION.md` §1.)
2. **The verification path is no longer isolated from commit.** In Rev 6/7 a wrong
   verifier could only raise a spurious flag. Now a false mismatch costs a replay,
   and three in a row at one instruction is a trap. Soundness is therefore a
   functional requirement, not a nicety, and is what the instrumented runs in §0
   establish.
3. **Every retired instruction is verified.** The queues are filled only by
   instructions certain to retire, in order, so there is no alignment to lose and
   no "cannot verify this cycle" case. Rev 6/7's `pc_match` / `sOQValid` gating,
   which silently skipped verification around every mispredict and load-use
   bubble, is gone.
4. **The shadow does not consume the main pipeline's operands.** It reads the
   committed regfile through its own ports and bypasses from its own stages. The
   main pipeline's operands are recorded only to be compared. This is what makes
   store-data and forwarding-select verification independent rather than an echo.
5. **Trailing means no double side effects.** The shadow never touches the bus,
   the cache or a CSR. The single D-cache port is shared by the main pipeline's
   reads, the HPTW, and the store-buffer drain engine, which is built like the
   HPTW (a second requester that owns the LSU while the pipeline is stalled). The
   Rev 1 destructive re-read cannot recur: nothing reads the cache on the shadow's
   behalf.

## 3. Per-class status

| Class | Independent check | If it fails | Status |
|-------|-------------------|-------------|--------|
| ALU / bit-manipulation | shadow ALU on shadow-sourced operands | replay | **Implemented** |
| Operand forwarding (ForwardAE/BE, RQ forwarding, regfile read) | shadow sources operands itself and compares; Memory-stage operand check for serialized instructions | replay | **Implemented (Rev 8)** |
| Branch direction / target | shadow comparator and adder | replay | **Implemented** |
| Next PC | shadow-computed successor, including taken branches and jumps | replay at the expected PC | **Implemented (Rev 8: full, not just fall-through)** |
| Load address | shadow adder; second AGU adder and address register | replay | **Implemented** |
| Load data | second `subwordread` on the raw word; duplicated store-queue merge | replay | **Implemented** |
| Store address and **data** | SQ entry vs the shadow's own address and rs2; the store is not written until this passes | replay; store discarded | **Implemented (Rev 8)** |
| AMO | shadow `amoalu` on its own rs2 and the verified old value; second `amoalu` in the LSU; write deferred through the SQ | replay | **Implemented (Rev 8)** |
| LR / SC | LR as a load; SC write deferred through the SQ | replay; reservation dropped | **Implemented (Rev 8)** |
| CSR values and **state** | CSR state mirror: read value, write value, trap/xRET effects, storage | replay; divergence traps | **Implemented (Rev 8)** |
| Integer multiply | mod-3 residue of the full product | replay | **Implemented (Rev 8)** |
| FMA | mod-3 residue of the significand product | replay | **Implemented (Rev 8)** |
| Traps, xRET, FP state, device reads, fences, cache-block ops | held until the shadow is quiescent, operands checked against the regfile | replay | **Implemented (Rev 8)** |
| Persistent fault | retry counter | precise cause-16 trap | **Implemented (Rev 8)** |

## 4. Fault response

Default-on, with no detect-only mode.

- Shadow mismatch → the instruction and everything younger is discarded from the
  queues, the main pipeline is redirected to it, nothing was committed.
- Memory-stage check failure → the instruction is held, flushed and refetched.
- Third consecutive fault with no commit in between → `mcause = 16` trap to M-mode,
  `mepc` = the faulting instruction, `mtval` = which checks failed.
- CSR mirror divergence → cause-16 trap immediately (it cannot be replayed away).
- `MSECFAULT[6]` records every detection.

## 5. Boundaries

Not covered, by design or for lack of an independent source:

- **Decode**: the shadow uses the main pipeline's decoded datapath controls.
- **Address translation**, HPTW, TLB.
- **Fetch**: instruction bits are trusted; only PC continuity is checked.
- **Floating point other than the FMA multiplier, and integer divide** (which
  shares `fdivsqrt`). FP instructions are serialized and their integer operands are
  checked, but their results are not recomputed.
- **Raw memory data** as read from the cache.
- **CSRs outside the mirror**: `mie`/`mip`, counters, `*envcfg`, PMP, `fcsr`.
- **The checker itself** has no self-test.
- **Identical duplicates** (AMO ALU, CSR datapath, store-queue merge, AGU adder)
  catch a transient in either copy, not a design-level fault common to both; only
  the residue checks are algorithmically diverse. Synthesis must not merge them.

## 6. What became of the Rev 5 review's recommendations

| Recommendation | Rev 8 |
|----------------|-------|
| Deferred store commit (SQ as a store buffer, loads snoop it) | Done. Byte-merge on the full physical word address, so partial overlap merges instead of stalling |
| Stores are the only irreversible effect → every other fault becomes flush+retry | Done; the remaining irreversible effects are serialized instead |
| Remove JALR verify-before-commit and conflict detection | Gone; neither is needed |
| Keep exception verify-before-commit | Done, as "traps wait for a quiescent shadow" |
| PA comparison belongs in M | The SQ match and the drain use the M-stage physical address |
| VA-vs-PA address check | The shadow checks the virtual EA against the main pipeline's, and the SQ entry's page offset; translation is a stated boundary |
| Trap must not orphan the RQ | Moot: only instructions certain to retire are pushed |
| Conflict-stall counter is fragile | Gone; waits are on the actual condition |
| Slim the RQ | Done: Rd, RegWrite, result (70 bits) |
| Slim the OQ | Partly: two operands, sum, raw load word, 37 control bits |
| Next-PC continuity check | Done, including branch and jump targets |
| Residue check on the shared multipliers | Done (MUL and FMA) |
| Forwarding-select verification | Done, by independent operand sourcing rather than select recomputation |
| Retry-loop protection | Done (escalation to a trap) |
| Stall terms should be registered | The store-buffer holds enter through the existing `LSUStallM` path; backpressure is a registered count |
| Circular-buffer queues | Not done: the queues are collapsing shift FIFOs (simpler head-relative reads) |
| Multiplicative verification of divide / sqrt | Not done |
| Checker self-test (canary) | Not done |
| RQ forwarding in D rather than E | Not done; the regfile read moved to E as well, which has not been through timing closure |

## 7. Remaining future work

- An independent decoder in the shadow.
- Divide / square-root verification (multiplicative or residue).
- A checker self-test.
- Report RVFI at shadow commit instead of main Writeback, so that the monitor and
  Spike co-simulation remain meaningful under fault injection.
- Timing closure of the Execute-stage regfile read, and `dont_touch` on the
  duplicated checkers.
- Drain performance: the store drain costs two to three stalled cycles per store
  because the D-cache has one port (`SHARD_IMPLEMENTATION.md` §12).

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
