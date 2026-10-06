# SHARD — Shadow Hardware Audit Redundancy Design

**Target RTL:** CORE-V-Wally (`wallypipelinedcore`), RV64GC, classic 5-stage
in-order pipeline (F, D, E, M, W).
**Status (this branch):** passes baremetal (5/5), ISA (9/9), FreeRTOS (5/5), and
boots Linux 6.6 + OpenSBI 1.4 to userspace.
**Purpose of this document:** a from-scratch reconstruction guide precise enough
to re-port SHARD onto a newer/upstream Wally. It documents the *actual*
implemented V1 (not the aspirational design in `shadow_thread.md` /
`shadow_review.md`), including the bugs that had to be fixed and why.

---

## 1. Concept and threat model

SHARD runs a **second, redundant copy of the back-end pipeline that trails the
main pipeline by a fixed queue depth N (=3)**. The main pipeline executes
normally; every retiring instruction's inputs and outputs are captured into a
set of FIFOs. N cycles later the *shadow* pipeline re-decodes, re-executes, and
re-verifies each instruction against what the main pipeline produced. On a
mismatch it raises a security fault (`SecFaultW` → MSECFAULT reporting).

The defining architectural decision — and the one that makes everything else
subtle — is:

> **The architectural register file is written by the SHADOW, not the main
> pipeline.** The main pipeline never commits golden state to the regfile.

So the main pipeline's W-stage result is *proposed*; it travels through the
Result Queue (RQ), and the shadow commits it to the regfile N cycles later. The
main pipeline therefore reads a register file that is **stale by N cycles**, and
a dedicated forwarding path (RQ associative forwarding) bridges that gap.

Threat model (as implemented): transient/permanent faults or a trojan in the
back-end datapath (ALU/BMU, result muxing, branch resolution) produce a wrong
result that the independent shadow recomputation catches. Coverage boundaries
(not verified in V1) are listed in §10.

---

## 2. Pipeline timing / the N-behind invariant

All shadow state advances with the **same `StallX`/`FlushX` signals as the main
pipeline** (a "coupled-stall" shadow). The shadow stages use identical flop
enables/clears:

| shadow reg | enable | clear |
|------------|--------|-------|
| sD→sE | `~StallE` | `FlushE` |
| sE→sM | `~StallM` | `FlushM` |
| sM→sW | `~StallW` | `FlushW` |

Capture points and consumption points (steady state, no stalls):

| Queue | pushed at (main stage) | consumed at (shadow stage) | depth |
|-------|------------------------|----------------------------|-------|
| IQ (instruction) | D | sD | N=3 |
| OQ (operands) | E→M | sE | N=3 |
| SQ (stores) | M | sM | N=3 |
| RQ (results) | W | sW | N=3 |

Because the shadow's own sD→sE→sM→sW uses the same stall/flush as the main
D→E→M→W, and the queues are N deep, the head of each queue lines up with the
shadow stage that consumes it. The regfile commit happens at sW from the **RQ
head**.

**Key latency identity (why forwarding depth == queue depth):** with exactly one
RQ push per `~StallW` cycle, N RQ entries == an N-cycle window == the time from
"result produced at main W" to "shadow writes it to the regfile." The RQ
forwarding (§6) covers precisely that window, so the hand-off from forwarding to
regfile is seamless — *provided* exactly one entry is pushed per `~StallW`
cycle and the shadow pops in lockstep. Violating that one-stream invariant is
the root of most bugs (§8).

---

## 3. Module inventory

All under `hdl/core/shadow/`:

| file | role |
|------|------|
| `shadow_iq.sv` | Instruction Queue: PC, Instr32, PCSrc, FRM, IsHWCSR, IsDummy/Sel, InstrValid |
| `shadow_oq.sv` | Operand Queue: post-forward SrcA/SrcB, imm, PC+4, and all ALU/BMU control bits |
| `shadow_sq.sv` | Store Queue: PA, WriteData, ByteMask, Valid (for store tracking) |
| `shadow_rq.sv` | Result Queue: Rd, Result, RegWrite, MemRW, PC, flags, **InstrValid**; also the main-pipeline RQ **forwarding** CAM |
| `shadow_pipeline.sv` | sD→sE→sM→sW: shadow ALU/comparator, memory handling, regfile write port, verify |
| `shadow_verifier.sv` | per-instruction compare (result / branch / memory) → SecFault |
| `shadow_hzu.sv` | (present but **not instantiated** in V1 — coupled-stall model makes intra-shadow hazards impossible; OQ delivers post-forwarded operands) |

Integration is entirely in `hdl/core/wally/wallypipelinedcore.sv` (queue
instantiations, the regfile write-port remux, the RQ-forwarding mux into the
main datapath, and the hazard-unit extensions). Supporting edits:
`hdl/core/lsu/lsu.sv` (PA export), `hdl/core/hazard/hazard.sv` (shadow stalls /
`FlushWCause`).

---

## 4. The queues in detail

### 4.1 IQ — `shadow_iq.sv`
- Entry = `{PC, Instr32, PCSrc, FRM(3), IsHWCSR, IsDummy, DummySel, InstrValid}`.
- Push stream mirrors main D. Holds on `StallD`. On `FlushD` it invalidates
  entries (bit0 = InstrValid). Shift+push real entry otherwise.
- Head feeds shadow sD, which re-derives Rs1/Rs2/Rd and the SkipVerify class
  combinationally.

### 4.2 OQ — `shadow_oq.sv`
- Entry = post-mux `SrcAE`, `SrcBE`, `ForwardedSrcBE` (store data), `PCLinkE`
  (PC+4), `ImmExtE`, plus every ALU/BMU control signal the shadow ALU needs
  (`W64E, UW64E, SubArithE, ALUSelectE, BSelectE, ZBBSelectE, BALUControlE,
  BMUActiveE, CZeroE, Funct3E, Funct7E, Rs2E, ALUResultSrcE, JumpE,
  BranchSignedE, MemRWE, RdE, RegWriteE, InstrValidE, DummyE, DummySelE`).
- **Operands are captured post-forwarding**, so the shadow ALU does not need any
  intra-shadow forwarding — this is why `shadow_hzu` is unused.
- Holds on `StallM`; pushes a null (bubble) entry on `FlushE||FlushM`; else real.

### 4.3 SQ — `shadow_sq.sv`
- Entry = `{PA, WriteData, ByteMask, Valid}` for each store, pushed at M.
- Holds on `StallM`; invalidated on `FlushM`. Popped by the shadow when a store
  passes sM (`sM_pop`).

### 4.4 RQ — `shadow_rq.sv` (the critical one)
- Entry packs `{Rd(5), Result(XLEN), RegWrite, MemAddr(XLEN, unused=0), MemRW(2),
  HasStore, PC(XLEN), SkipVerify, IsFaultedInstr, DummyW, DummySelW,
  InstrValid}`.
- Pushed at main W, one entry per `~StallW` cycle. **Holds on `StallW`.** The
  entry carries `InstrValidW`, which is exactly the main pipeline's own
  "did this instruction retire" signal.
- Head (`entry[N-1]`) feeds shadow sW → the regfile write and the verifier.
- **Also implements the main-pipeline forwarding CAM** (see §6): it scans all N
  entries for `Rd == Rs1/Rs2`, newest-wins, and drives `RQ_HitA/ValA`,
  `RQ_HitB/ValB`.

---

## 5. Shadow pipeline & regfile commit — `shadow_pipeline.sv`

- **sD:** decode IQ head → Rs1/Rs2/Rd, `is_skip_verify`, `is_branch`.
- **sE:** a full `alu` + `comparator` instance fed *directly* from OQ head
  operands. `mux2` chain reproduces the main IEU result mux (ALU vs link
  address). No forwarding needed (OQ already post-forwarded).
- **sM:** memory handling — **V1: no D-cache re-read** (see §8.1). Stores pop the
  SQ here.
- **sW:** `shadow_verifier` compares; the regfile write port is driven here.

### Regfile write port (the commit)
```
write_enable  = rq_InstrValid & (rq_IntWriteEn | rq_DummyW);   // NOT gated by FlushW
shadow_we3    = write_enable;
shadow_a3     = rq_Rd;
shadow_wd3    = rq_IntResult;            // the main pipeline's W result, delayed
shadow_DummyW = rq_DummyW & write_enable;
```
These drive the main `regfile` `we3/a3/wd3` (remuxed in wallypipelinedcore).
Note the committed *value* is the main result `rq_IntResult`; the shadow's
independently recomputed value is used only by the verifier to raise SecFault.
(A stricter design would commit the shadow-computed value; V1 commits the main
value delayed — the verification is an alarm, not a gate.)

---

## 6. RQ forwarding — bridging the stale regfile

The regfile is N cycles behind, so the main pipeline cannot read fresh values
from it. `shadow_rq` exposes an N-entry associative forwarding port, queried with
the **E-stage** register numbers (`Rs1E`, `Rs2E` in wallypipelinedcore —
`Rs1E_rq` is piped from D, `Rs2E_s` exported from the IEU), newest-entry-wins:

```
for j in [N-1 .. 0]:
  if rq_valid[j] & rq_we[j] & rq_rd[j]!=0:
     if rq_rd[j]==Rs1 -> HitA, ValA = rq_val[j]
     if rq_rd[j]==Rs2 -> HitB, ValB = rq_val[j]
```

`RQ_ValA/ValB` are muxed into the main datapath operand path. A small
**capture-and-hold** shim (`cstall_*` in wallypipelinedcore) latches the hit/value
when `StallE & ~StallW` (the RQ keeps shifting while E is stalled and would
otherwise evict the needed entry) and holds it through the stall plus one extra
cycle for the E→M hand-off.

The forwarding window (N entries) and the regfile-write latency (N cycles)
coincide by construction (§2), so: value is forwarded while it sits in the RQ;
on the cycle it reaches the head it is written to the regfile; the next cycle the
regfile read returns it. No gap — **as long as the one-push-per-`~StallW`
invariant holds.**

---

## 7. Verification semantics — `shadow_verifier.sv`

```
result_mismatch = rq_IntWriteEn && (sALUResult != rq_IntResult)
branch_mismatch = isBranch      && (sBranchTaken != rq_PCSrc)
mem_mismatch    = mem_result_valid && (... load/store data compare ...)
if (!rq_InstrValid || rq_SkipVerify) -> MATCH (pass)
else if (any mismatch)               -> MISMATCH -> SecFaultW, SecFaultPC=rq_PC
```

`SkipVerify` classes (decoded at sD, `is_skip_verify`): FP ops, integer DIV/REM,
LR/SC/AMO, CSR, fence/fence.i, WFI, ECALL/EBREAK/xRET, FP load/store. Dummy-
inserted and HW-CSR instructions also skip.

**V2 (Rev 6):** integer loads are **no longer SkipVerify** — they are
effective-address verified (§7.1). The verifier is additionally gated by
`pc_match` (shadow PC == RQ PC) and `sOQValid_W` (OQ operand path valid) so that
transient IQ/OQ/RQ queue slip around load-use bubbles is treated as
"can't-verify this cycle" rather than a false fault. The ALU-result compare
excludes loads (`~isLoad`) because a load's architectural result is memory data.

### 7.1 Effective-address verification (V2)
The main's observed access address `IEUAdrM` is piped to `IEUAdrW` and carried in
the RQ `MemAddr` field; the shadow's own address adder output is piped to
`sIEUAdrW`; the verifier raises a fault when `(isLoad|isStore) & (sIEUAdrW !=
rq_MemAddr)`. This is an independent check of the AGU / immediate-sum datapath,
non-destructive, and correct under translation (it compares the shadow EA to the
main's *actual* access address, not a VA to a PA).

### 7.2 Load-DATA verification (V2) — self-contained
The LSU exports `RawReadDataWordM` (the raw aligned read-mux word before subword
extract). It is piped to W and carried in the RQ entry with `Funct3` (next to the
existing `MemAddr` and `IntResult`). At sW the shadow runs its **own copy of
`subwordread`** on `{rq_RawLoadWord, rq_MemAddr[3:0], rq_Funct3}` and compares to
`rq_IntResult` (`load_data_mismatch`), gated to **pure loads** (`rq_MemRW==2'b10 &
rq_IntWriteEn`) so AMOs/stores/FP-loads are excluded. Because all operands live in
one RQ entry, the check is **self-contained** (no IQ/OQ/shadow-pipeline alignment,
no `pc_match` gating) and runs on essentially every integer load. It covers the
subword-extract/sign-extend datapath with an independent logic copy; the raw SRAM
word is SECDED-covered. `SecFaultW = sv_mismatch | load_data_mismatch`. Validated:
1208 loads checked in `sorting_algo` (0 false faults); 1-bit fault injection fires
it 17× (true-positive). See `shadow_review.md` §3a.

### 7.3 AMO / CSR / next-PC / gated-store verification (Rev 7)
All follow the **independent-recompute** pattern (a 2nd copy of the datapath on
the same captured operands; disagreement → MSECFAULT). Each is sound (0 false
faults on baremetal/ISA/FreeRTOS/Linux) and injection-validated (true-positive):
- **AMO** (`lsu.sv`): second `amoalu` vs `IMAWriteDataM` → `AMOFaultM`
  (30 AMOs / inj 72×).
- **CSR** (`csr.sv`): second csrrw/s/c modify+mux vs `CSRWriteValM` → `CSRFaultM`,
  gated to committing writes. Verifies the CSR modify datapath (no full CSR-state
  mirror; opaque CSR *effects* are a boundary).
- **Next-PC** (`shadow_pipeline.sv`, RQ-self-contained): `PC_{k+1} == PC_k+ilen`
  for sequential commits (`Compressed`/`IsCtrlFlow` carried in the RQ; traps
  suppressed via FlushW-since-last-commit). 5754 checks / inj fires.
- **Gated store commit** (`wallypipelinedcore.sv`): independent AGU adder recompute
  of the store EA vs `IEUAdrE` at the commit point → MSECFAULT, and (opt-in
  `GATE_STORE_ON_SECFAULT`, default 0) clears the LSU store write bit so a
  mis-addressed store cannot corrupt memory — verify-before-commit without a store
  buffer (1032 stores / inj 1116×). Full DIVA store-buffer + shadow-decoupling is
  the documented heavier alternative (`shadow_review.md` §7a).

---

## 8. Bugs found and fixed (essential for re-port)

These three were the difference between "4/5 baremetal" and "boots Linux." Each
is a direct consequence of breaking the §2 one-stream invariant or of the
destructive memory re-read.

### 8.1 Destructive D-cache re-read → **disabled in V1**
*Symptom:* `test_fwd_depth` stored 7 to `0x8fefffd8`, later loaded back garbage.
*Cause:* the shadow sM re-read the D-cache through a mux on the **single shared
cache port** (`lsu.sv`: `dcache_PAdr_mux = shadow_dcache_req ? shadow_pa : PAdrM`,
`dcache_RW_mux`, `dcache_NextSet_mux`). Forcing a read of a just-stored **dirty**
line missed (the forced NextSet/tag path addressed the wrong set) and triggered a
**writeback+refill that overwrote the dirty line with stale memory** — destroying
the committed store. The main load then read the corrupted line on the normal
path.
*Fix (`shadow_pipeline.sv`):* `shadow_needs_dcache_M = 1'b0` (shadow never drives
the cache port), `ShadowDCacheStallM = 0`; integer loads become `SkipVerify`
(they still *commit* via RQ→regfile, just aren't independently re-read); SQ still
pops one entry per store at sM (`sM_pop = shadow_is_store_M & ~StallM & ~FlushM`).
*Proper V2 (per `shadow_review.md`):* **deferred store commit** — make the SQ a
real store buffer, issue the D-cache write from the SQ head only after shadow
verify; main loads snoop the SQ. That removes the shared-port hazard entirely and
is the recommended long-term design. A read-only non-allocating snoop port is the
alternative.

### 8.2 RQ head dropped on trap/flush → **commit must NOT be gated by `FlushW`**
*Symptom:* under FreeRTOS timer interrupts, the trap handler's context-save read
**stale registers** (RVFI "mismatch with shadow rs2"). A write that the main
pipeline committed just before the trap was never written to the regfile.
*Cause:* the RQ pushed a forced bubble on a real flush
(`entry[0] <= (FlushW & FlushWCause) ? 0 : push_data`) **and** the commit/pop were
gated by `~FlushW` (`write_enable = ... & ~FlushW`, `sW_pop = ~StallW & ~FlushW`).
On an interrupt the W-stage instruction *does* retire (it is before the trap
boundary, `InstrValidW=1`), but the RQ shifted it out without committing it. The
trap squashes the **youngest** slot (RQ `entry[0]`), never the **head**.
*Fix:*
  - `shadow_rq.sv`: `entry[0] <= push_data` unconditionally (the `InstrValidW`
    field already encodes exactly what retires; genuinely squashed slots arrive
    with `InstrValidW=0`).
  - `shadow_pipeline.sv`: `write_enable = rq_InstrValid & (rq_IntWriteEn |
    rq_DummyW)` and `sW_pop = ~StallW` (pop matches the RQ shift exactly).

### 8.3 Shadow stalls must enter `StallWCause` (prior fix, retained)
*Cause:* `ShadowDCacheStallM`/`ShadowVerifyConflictStallM` were only in
`StallMCause`, so `StallM=1 & StallW=0` produced a spurious `LatestUnstalledW`
flush that desynced the queues.
*Fix (`hazard.sv`):* `StallWCause |= (ShadowDCacheStallM |
ShadowVerifyConflictStallM) & ~FlushWCause`, and `FlushWCause` is exported from
the hazard unit as `TrapM & ~WFIInterruptedM`. (With 8.1, the shadow no longer
asserts `ShadowDCacheStallM`, but the gating is harmless and correct to keep.)

### 8.4 Flop semantics that matter for a re-port
- `flopenrc` **gates `clear` behind `en`**: a flush is *ignored while the stage
  is stalled*. Reason carefully about any queue whose bubble logic assumes a
  flush always takes effect.
- The IFU `PCMReg` is a plain `flopenr` (no clear) → on a flush it still latches
  the squashed `PCE`. This makes RQ bubbles carry a stale-but-real PC
  (`InstrValidW=0`). Harmless to commit (gated by `InstrValid`), but do not use
  RQ `PC` of an invalid entry for anything.

---

## 9. Stall / flush interaction matrix (as implemented)

`hazard.sv` (after SHARD edits):
```
FlushWCause = TrapM & ~WFIInterruptedM                 // exported output
StallMCause = (WFIStallM | ShadowDCacheStallM | ShadowVerifyConflictStallM) & ~FlushMCause
StallWCause = (IFUStallF & ~FlushDCause) | (LSUStallM & ~FlushWCause) | ExternalStall
            | ((ShadowDCacheStallM | ShadowVerifyConflictStallM) & ~FlushWCause)
```
Invariants a re-port must preserve:
1. **One RQ push per `~StallW` cycle**; RQ holds on `StallW`.
2. **`sW_pop` == RQ shift condition** (`~StallW`). Never gate the head
   commit/pop by `FlushW`.
3. The RQ entry's `InstrValid` is the sole authority on whether it commits — do
   not second-guess it with flush causes.
4. Any new shadow-induced stall must appear in `StallWCause` (not only
   `StallMCause`) or it will desync the queues via `LatestUnstalledW`.

---

## 10. Coverage (Rev 6/7) and remaining boundaries

VERIFIED (independent recompute, each injection-validated):
- **Load/store effective address** (§7.1) and **load data** (§7.2).
- **ALU / bit-manip results** and **branch direction** (sound via pc_match + OQ-valid gating).
- **AMO result**, **CSR write value**, **next-PC continuity**, and **store-commit
  address gating** (§7.3).

Remaining boundaries (documented):
- **Store data** equals a forwarded operand the shadow also received via the OQ,
  so re-comparing it is an echo (forwarding boundary).
- **Post-write store-data re-read / full prevention** needs the DIVA store buffer
  + decoupled shadow (`shadow_review.md` §7a) — future Rev 8.
- **Address translation / DTLB** out of scope (shadow does not re-translate).
- **Shared MUL/FMA** permanent-fault — residue check recommended.
- **Forwarding-select (operand mux)** — shadow consumes post-forward operands.
- **CSR opaque side-effects** (privilege/counter state) — only the CSR modify
  datapath is verified, not the full CSR state machine.

See `shadow_review.md` "FINAL DETAILED IMPLEMENTATION" §7/§7a/§7b for the Rev 8
roadmap (decoupled-shadow store buffer, queue slimming, MUL residue check).

---

## 11. Re-port checklist (onto upstream Wally)

1. **Regfile remux:** route `regfile.we3/a3/wd3` from the shadow
   (`shadow_we3/a3/wd3`), not the main W stage. Add the DummyW/Sel redirect if
   using the dummy-instruction feature.
2. **Instantiate the four queues** at their capture points (IQ@D, OQ@E→M, SQ@M,
   RQ@W) with the exact hold/bubble rules in §4. Keep them N=3 unless you also
   re-derive the latency identity in §2.
3. **Wire RQ forwarding** (`RQ_HitA/ValA`, `RQ_HitB/ValB`) into the main operand
   mux, queried with E-stage Rs1/Rs2, plus the `cstall_*` capture-and-hold shim.
4. **Hazard unit:** export `FlushWCause`; add shadow stalls to **both**
   `StallMCause` and `StallWCause` (§8.3/§9).
5. **Honor the invariants in §9** — these are where it breaks in simulation.
6. **Do not add a destructive cache re-read** on the shared port (§8.1). If load
   verification is required, implement deferred store commit or a read-only
   snoop port.
7. Regression order that exposes problems progressively: baremetal (forwarding
   depth) → ISA → **FreeRTOS (interrupt/trap commit — exposes 8.2)** → Linux
   boot (MMU, sustained interrupts, atomics).

---

## 12. Validation evidence (this branch)

- `make baremetal_regression` → 5/5 (incl. `test_fwd_depth`, nested-call fwd).
- `make isa_regression` → 9/9 (21 UART sub-checks).
- `make freertos_regression` → 5/5 (queue/semaphore/timer-preempt/task-queue).
- `make linux_boot` → OpenSBI 1.4 → Linux 6.6 boots through MMU/Sv39, timer
  interrupts, atomics, driver init, to userspace `/init`.

Debug methodology and the raw traces that localized 8.1/8.2 are preserved in
`sim/shadow_debug_progress.md`.
