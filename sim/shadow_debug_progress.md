# SHARD Debug Progress — test_fwd_depth failure

**Date:** 2026-10-05 (RESOLVED 2026-10-06)
**Branch:** sai-shard-impl
**Status:** ✅ RESOLVED. SHARD now passes baremetal 5/5, ISA 9/9, FreeRTOS 5/5, and
boots Linux 6.6 to userspace. Debug instrumentation removed. See the final
reconstruction doc `hdl/core/shadow/SHARD_IMPLEMENTATION.md` §8 for the three fixes.

This file is the raw debug trail (kept for provenance). The actual root cause turned
out to be TWO distinct bugs, NOT the forwarding-eviction theory below:
  (1) the shadow D-cache re-read was DESTRUCTIVE (missed on a dirty line → refill
      overwrote the just-stored value) — disabled in V1; and
  (2) the RQ head's regfile commit was gated by `~FlushW`, dropping the retiring
      W-stage instruction on every interrupt (FreeRTOS stale-rs failures).
The sections below are the as-written investigation notes and remain accurate as to
the HDL facts (flopenrc clear-gated-by-enable, IFU PCMReg no-clear, etc.).

---

## 1. How to reproduce

```bash
cd sim
make run_verilator_top_tb PROG=../testcode/baremetal/test_fwd_depth.c
# log: sim/verilator/test_fwd_depth/simulation.log
```

Current failure (Spike co-sim mismatch, NOT a SHARD SecFault):

```
[13030000] Spike Monitor Error ... order 230
inst       h00004522  (lw x10,8(x2)  @ pc=0x8000116a)
rd_wdata   ---> hffffffffefc6ed3f   (spike expects h00000007)
mem_addr        h8fefffd8
mem_rdata  ---> hffffffffefc6ed3f   (spike h00000007)
```

The 4 other baremetal tests + the earlier parts of this test pass; failure is
specifically in `outer()` / nested-call forwarding.

---

## 2. The test region that fails

`outer(3)` (sym `outer.constprop.0` @ 0x8000114e) calls `inner(3)` then `inner(4)`.
`inner(x)` returns `x*2+1` → `inner(3)=7`, `inner(4)=9`. Stack frame of outer: sp=0x8fefffd0.

```
8000114e outer: addi x2,x2,-32          ; sp = 0x8fefffd0
80001150        li   x10,3
80001152        sd   x1,24(x2)
80001154        auipc x1,0x0
80001158        jalr -22(x1)            ; call inner(3)  -> returns x10=7
8000115c        sw   x10,8(x2)          ; STORE a=7 at sp+8 = 0x8fefffd8   <-- corrupting store
8000115e        li   x10,4
80001160        auipc x1,0x0
80001164        jalr -34(x1)            ; call inner(4)  -> returns x10=9
80001168        sw   x10,12(x2)         ; store b=9 at sp+12 = 0x8fefffdc
8000116a        lw   x10,8(x2)          ; LOAD a from 0x8fefffd8  -> reads GARBAGE (should be 7)
8000116c        ld   x1,24(x2)
8000116e        lw   x15,12(x2)
80001170        addi x2,x2,32
80001172        addw x10,x10,x15
80001174        ret

8000113e inner: addi x2,x2,-16
80001140        slliw x10,x10,1         ; t = x*2
80001144        sw   x10,12(x2)
80001146        lw   x10,12(x2)
80001148        addi x2,x2,16           ; restore sp
8000114a        addiw x10,x10,1         ; ret value = t+1
8000114c        ret
```

The failing `lw` at 0x8000116a reads memory that was written by `sw x10,8(x2)` at
0x8000115c. So **memory at 0x8fefffd8 was already corrupted at store time** — the `sw`
stored a *stale/wrong* `x10` instead of 7. The load itself is fine.

---

## 3. Architecture facts (verified this session)

- **The MAIN register file is written by the SHADOW pipeline**, several cycles late.
  `shadow_pipeline.sv`:
  - `shadow_wd3 = rq_IntResult` (the MAIN pipeline's result, taken from RQ head)
  - `shadow_a3  = rq_Rd`
  - `write_enable = rq_InstrValid & ~FlushW & (rq_IntWriteEn | rq_DummyW)`
  - i.e. the regfile commit value is the main result, delayed by the time the entry
    takes to reach the RQ head (entry[N-1]). SecFault (verifier) is a *separate* alarm;
    it does not gate the committed value.
- Because the regfile is stale for N cycles, **`shadow_rq.sv` provides N-entry
  associative forwarding** (`RQ_HitA/ValA`, `RQ_HitB/ValB`) to the main D/E stage. This
  bridge is what covers the window between "result produced at main W" and "regfile
  written by shadow".
- **`flopenrc` clear is GATED BY ENABLE** (`hdl/core/generic/flop/flopenrc.sv`):
  ```
  if (reset) q<=0; else if (en) if (clear) q<=0; else q<=d;
  ```
  → a flush (`clear`) is IGNORED while the stage is stalled (`en=0`).
- **IFU `PCMReg` is a plain `flopenr` with NO clear** (`ifu.sv:421`):
  `flopenr PCMReg(clk,reset,~StallM,PCE,PCM);`
  → on a flush, PCM still latches `PCE` (the squashed instruction's PC) even though
  `InstrValidM` (in controller `controlregM`, clear=FlushM) is correctly cleared.
  This produces RQ "bubble" pushes that carry a *real* PC with `InstrValidW=0`
  (observed: PCW=0x80001146 and PCW=0x8000116a pushed with InstrValidW=0).

---

## 4. Queue push/shift disciplines (the inconsistency)

Three queues, three *different* bubble mechanisms — this is the core fragility:

| Queue | push stage | hold when | bubble inserted when | file |
|-------|-----------|-----------|----------------------|------|
| IQ | main D | `StallD` | `FlushD` → **invalidates ALL 3 entries in place** (no shift) | shadow_iq.sv:58 |
| OQ | main E→M | `StallM` | `FlushE \|\| FlushM` → push null (shift) | shadow_oq.sv:90 |
| RQ | main W | `StallW` | only `FlushW & FlushWCause` → push null; else push PCW/result | shadow_rq.sv:106 |

Observations:
- **IQ `FlushD` handling is almost certainly wrong**: it zeroes the valid bit of all
  three entries (`entry[i][0]<=0`), destroying instructions that are legitimately in
  flight and will still commit via OQ/RQ. FlushD should only stop the *current* D push.
- **OQ bubbles on `FlushE`**, but on `FlushE` the E-stage instruction (e.g. a branch
  resolving BPWrong, or the instr in E when RetM fires) actually proceeds E→M that same
  posedge (E→M reg clears on `FlushM`, not `FlushE`). So OQ may insert a bubble where a
  real instruction actually advanced — a count/position mismatch vs RQ.
- **RQ never explicitly bubbles on Ret/BPWrong** (FlushWCause excludes RetM/BPWrong),
  yet it receives an *implicit* bubble one cycle later because the squashed M-slot
  (InstrValidM=0, PCM=stale) advances into W and gets pushed.
- **Pop vs shift mismatch:** RQ shifts on `~StallW`; shadow pops head on
  `sW_pop = ~StallW & ~FlushW`. When `FlushW & ~StallW` (i.e. `LatestUnstalledW =
  ~StallW & StallM`, the WFI / shadow-stall case), the RQ shifts an entry OUT but the
  shadow does NOT consume it → that entry is never written to the regfile → silent
  value loss. (My earlier fix put shadow stalls into StallWCause, so ShadowDCacheStall
  no longer triggers this; WFI still can. Not confirmed as active in THIS test.)

---

## 5. Failure mechanism (current best model)

1. `inner(3)` computes return value 7 (`addiw x10` @ 0x8000114a) and `ret` @ 0x8000114c.
2. The `ret` (RetM) + the call's jalr (BPWrong) fire `FlushD/FlushE/FlushM` but
   `FlushWCause=0`. These flushes insert bubbles into the pipeline between inner's
   `addiw` (producer of x10=7) and outer's `sw x10,8(x2)` (consumer) @ 0x8000115c.
3. The bubbles over-fill / misalign the 3-deep RQ relative to OQ/IQ (different bubble
   rules above). The `x10=7` producing entry is evicted from the 3-deep RQ forwarding
   window **before** outer's `sw` reads x10, AND the shadow regfile write of x10 has
   not yet become readable (handoff gap). The `sw` therefore reads a stale `x10` and
   stores garbage to 0x8fefffd8.
4. Later `lw x10,8(x2)` @ 0x8000116a reads that garbage → Spike mismatch.

Why forwarding *should* normally work (and the invariant that's being violated):
with exactly one RQ push per `~StallW` cycle, 3 RQ entries == a 3-cycle window ==
the shadow-regfile write latency, so the forwarding→regfile handoff is seamless.
Flush bubbles that are inserted inconsistently across IQ/OQ/RQ break the
"one-consistent-stream" invariant and shorten the effective window for real values.

---

## 6. Trace evidence captured (window t=12.4us–13.05us)

- Window caught only the SECOND inner call (inner(4)); the corrupting store at
  0x8000115c (first call, a=7) is BEFORE 12.4us. **NEXT STEP: widen window to ~11.8us**
  to capture `sw x10,8(x2)` @ 0x8000115c and confirm the stale x10 at store time.
- Confirmed spurious RQ bubbles carrying real PCs:
  `PCW=0x80001146 InstrValidW=0` then `PCW=0x80001146 InstrValidW=1` (double entry for
  inner's lw), same for `0x8000116a`.
- A long `StallW=1` region t≈12.56–12.98us (noinline I-cache miss) — RQ correctly holds.
- At t=13030000 the real `lw` @ 0x8000116a already pushes
  `ResultW=0xffffffffefc6ed3f` → confirms memory was already corrupted upstream.

---

## 7. Candidate fixes (decide next session)

**A. Unify the three queues' bubble/shift discipline (RECOMMENDED, medium risk).**
Make each queue a faithful N-deep delayed replica of the main inter-stage register it
feeds, using the SAME (en, clear) as that register:
  - IQ should mirror D→E: shift on `~StallE`, push bubble on `FlushE`, hold on `StallE`
    (instead of shift on `~StallD` / invalidate-all on `FlushD`).
  - OQ should mirror E→M: bubble on `FlushM` only (not `FlushE`).
  - RQ already mirrors M→W reasonably; make its bubble rule `FlushW` (not just
    `FlushW & FlushWCause`) and ensure the shadow pop matches the shift.
Must re-verify steady-state alignment (currently sD reads IQ@t+3, sE reads OQ@t+4,
sW reads RQ@t+6 — these align with the shadow's own sD→sE→sM→sW which uses the same
stall/flush). Changing shift enables shifts timing by one; re-derive before trusting.

**B. Close the forwarding→regfile handoff gap (lower risk, narrower).**
Keep queues as-is but guarantee the producing value is available to the consumer at
all times: e.g. make the regfile write-first (internal read-during-write bypass) AND
extend/ää correct the RQ forwarding so an entry is never evicted before the shadow
has written it. The existing `cstall_*` hold logic (wallypipelinedcore.sv:543-571)
already patches the `StallE & ~StallW` eviction case; this would generalize it to the
flush-bubble eviction case. Risk: patch-on-patch, may not cover all paths.

**C. Fix the obvious sub-bugs regardless of A/B:**
  - IFU PCMReg: give it a flush clear so bubbles don't carry stale PCs (cosmetic for
    forwarding since any push still shifts, but correct for PC-based verification).
  - IQ FlushD invalidate-ALL → invalidate only the newest/incoming entry.
  - Make shadow pop == RQ shift (handle `FlushW & ~StallW`).

Recommendation: do **C** (clear sub-bugs) + **A** (unify disciplines), then re-run the
whole baremetal regression. A is the durable fix; the design is fragile because the
regfile-commit-latency vs forwarding-window equality depends on perfectly consistent
bubble accounting across the three capture points.

---

## 8. Instrumentation to REMOVE before regression/commit

1. `hdl/core/shadow/shadow_rq.sv` — `// synthesis translate_off` block after the
   forwarding `always_comb` (the `[RQdbg]` per-cycle entry dump).
2. `hdl/core/wally/wallypipelinedcore.sv` ~line 693 — the `[PUSH]` debug `always_ff`
   (`// DEBUG: trace shadow writes and stalls near new failure`).
Both are time-windowed (`$time >= 12400000 && <= 13050000`) and `translate_off`-guarded,
so harmless to simulation correctness, but strip them for the final build.

---

## 9. Prior fixes still in place (do not regress)

- `hazard.sv`: `StallWCause` includes
  `(ShadowDCacheStallM | ShadowVerifyConflictStallM) & ~FlushWCause`; `FlushWCause`
  is an output = `TrapM & ~WFIInterruptedM`.
- `shadow_rq.sv`: push holds on `StallW`; entry[0] = `(FlushW & FlushWCause) ? 0 :
  push_data`.
- SQ 4-byte-granularity fix + capture-and-hold for ShadowConflictStallE (per memory
  `project_shard_forwarding_fixes` — all 5 baremetal tests passed with those).

---

## 10. Immediate next actions

1. Widen debug window to ~11.8us–12.5us; capture `sw x10,8(x2)` @ 0x8000115c and the
   RQ/forwarding state; confirm x10 is stale at that store.
2. Apply fix C sub-bugs; re-run test_fwd_depth.
3. If still failing, apply fix A (unify queue disciplines); re-derive alignment.
4. Remove instrumentation; run `make baremetal_regression` (all 5 must pass), then
   isa_regression, freertos_regression, linux_boot.
5. Write final SHARD reconstruction documentation.
