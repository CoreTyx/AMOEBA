# SHARD — Shadow Hardware Audit Redundancy Design (Rev 8)

**Target RTL:** CORE-V-Wally (`wallypipelinedcore`), RV64GC, 5-stage in-order
pipeline (F, D, E, M, W).
**Purpose of this document:** the authoritative description of what the RTL on
this branch implements, precise enough to re-port SHARD onto another Wally.
`shadow_review.md` holds the per-class status table and the original design
critique; `shadow_thread.md` holds the design history (Rev 5 → Rev 8).

Rev 8 replaces the coupled, detect-and-log shadow of Rev 1–7 with a **decoupled
shadow that gates every architectural commit**. A detected fault no longer sets a
flag after the damage is done: the faulty instruction never commits, and the
pipeline replays it.

---

## 1. Principle

> The main pipeline proposes; the shadow verifies and commits.

Nothing the main pipeline computes reaches architectural state unverified. There
are exactly three ways an instruction can change state, and each has its own
gate:

| State | How the main pipeline's effect is held back | Who releases it |
|---|---|---|
| Integer register file | Result waits in the **RQ**; the regfile has a single write port owned by the shadow | Shadow commit at sW |
| Memory (ordinary stores, AMO and SC writes) | Store waits in the **SQ**, a real store buffer; the main pipeline never writes the D-cache or bus for these | Shadow commit marks the entry verified; the LSU drain engine then writes it |
| Everything else: CSRs and privilege mode, traps, xRET, FP registers and flags, device (uncacheable) reads, fences, cache-block ops, misaligned / FP / big-endian memory accesses | The instruction is **held in the Memory stage** until the shadow is *quiescent* (every older instruction verified and committed, SQ empty) | Memory-stage checks verify it in place, then it acts directly |

On a mismatch nothing is committed, so recovery is exact: flush, and re-execute
from the faulting instruction (§8).

Threat model: transient or permanent faults, or a trojan, in the back-end
datapath and its control — ALU/bit-manipulation, address generation, operand
forwarding, branch resolution, load formatting, store data and address, AMO and
CSR datapaths, CSR storage, the multipliers. Boundaries are listed in §11.

---

## 2. Module inventory

Under `hdl/core/shadow/`:

| file | role |
|------|------|
| `shadow_fifo.sv` | Collapsing FIFO shared by all four queues. `entry[0]` is always the oldest element; supports simultaneous push/pop and a partial flush that keeps the `keep` oldest entries |
| `shadow_iq.sv` | Instruction Queue: PC, 32-bit instruction, compressed flag |
| `shadow_oq.sv` | Operand Queue: the rs1/rs2 values the main pipeline used, its ALU sum, the raw load word, and its decoded datapath controls |
| `shadow_rq.sv` | Result Queue: Rd, RegWrite, result; plus the associative forwarding lookup for main Execute |
| `shadow_sq.sv` | Store Queue (store buffer): physical address, size, data; a count of verified entries |
| `shadow_sqmerge.sv` | Store-to-load byte merge used by the LSU (instantiated twice) |
| `shadow_hzu.sv` | The shadow's own forwarding unit (sM/sW bypass over the regfile) |
| `shadow_pipeline.sv` | sD → sE → sM → sW; sole writer of the regfile |
| `shadow_verifier.sv` | The sM comparison: eight fault classes |
| `shadow_csr.sv` | CSR state mirror |
| `shadow_residue.sv` | Mod-3 residue generator for the multiplier checks |

Integration: `wally/wallypipelinedcore.sv` (queues, retirement, serialization,
fault response), `lsu/lsu.sv` (store buffer hold / drain / merge), `ieu/datapath.sv`
+ `ieu/regfile.sv` (Execute-stage regfile read, shadow read ports), `ieu/ieu.sv`,
`ieu/controller.sv` (exports), `hazard/hazard.sv`, `ifu/ifu.sv` (redirect),
`privileged/{trap,privdec,csr,csrm,csrs,privileged}.sv` (trap gating, cause 16,
mirror), `mdu/mdu.sv`, `fpu/fma/fma.sv`, `fpu/fpu.sv` (residue checks),
`lsu/{atomic,lrsc}.sv` (reservation clear).

---

## 3. Retirement into the queues

An instruction that leaves the Memory stage unflushed is certain to retire:

```
MExitM = InstrValidM & ~StallW & ~FlushW
```

| Queue | Pushed | Popped | Depth |
|-------|--------|--------|-------|
| IQ | `MExitM` | sD → sE | 8 |
| OQ | `MExitM` | sE → sM | 8 |
| SQ | `MExitM & SQStoreM` (the instruction is a queued store) | LSU drain (`sqPop`) | 8 |
| RQ | first cycle the instruction is in W (`InstrValidW & ~WPushed`) | shadow commit | 8 |

Two properties make the shadow independent of main-pipeline stalls:

1. **Only retiring instructions are pushed**, in order, so the *k*-th entry of
   every queue belongs to the same instruction. There is no alignment to recover
   and no "skip verification this cycle": every retired instruction is verified.
2. **The RQ push does not wait for `StallW`.** W-stage values are registered and
   stable, so the result is pushed on the instruction's first W cycle. Anything
   that stalls the pipeline while waiting for the shadow therefore cannot starve
   the shadow of the very instruction it is waiting on.

Pushes are blocked from a shadow fault until the redirect (`ShardPushOK`), because
the main pipeline then holds wrong-path instructions.

`InFlight` counts instructions between `MExitM` and shadow commit.
`ShadowIdleM = (InFlight == 0) & ~RecPending`.

Backpressure: the pipeline freezes (`ShardStallW` → `StallWCause`) when the RQ holds
`DEPTH-1` entries. The instruction already in W still has room, and every IQ/OQ
entry belongs to an instruction that is in the RQ or in W, so no queue can
overflow. In normal operation the shadow drains as fast as the main pipeline
retires and RQ occupancy stays at 3–4, so this is an interlock, not a steady-state
stall. (It was exercised by temporarily setting the depth to 4.)

---

## 4. Main-pipeline operand sourcing

The regfile holds verified state only, and the shadow commits to it at a time
unrelated to main-pipeline stalls. So the regfile is **read in Execute**,
combinationally (`regf.a1/a2 = Rs1E/Rs2E`), and the operand is the newest of:

```
M-stage result  >  W-stage result  >  newest matching RQ entry  >  regfile
```

This is stateless: an instruction held in Execute for any number of cycles always
sees the current architectural value, with no capture-and-hold shim. (The former
`RD1EReg`/`RD2EReg` pipeline registers are gone; the regfile read ports keep their
SECDED decode.) The regfile still writes on the falling edge, so a shadow commit
is visible to an Execute read in the same cycle.

Consequence used by the checks: **`ForwardedSrcAE/BE` is the exact architectural
value of x[rs1]/x[rs2] for every instruction**, whether or not the instruction
uses that field.

---

## 5. Shadow pipeline — `shadow_pipeline.sv`

Free-running: an instruction leaves the IQ as soon as its RQ entry is certain to
exist when it reaches sM, then moves one stage per cycle. Latency from `MExitM`
to commit is four cycles.

- **sD** — IQ head. `AdvanceDE = iqValid & (rqCount + rqPush > #valid stages)`.
- **sE** — Operands come from **verified state only**: the regfile through the
  shadow's own read ports (`a4/a5`), bypassed by `shadow_hzu` from sM and sW.
  They are compared with the operands the main pipeline used (`OQ`); a
  difference is the **OP** fault. The shadow then re-executes with its own `alu`,
  `comparator`, `extend` and link adder, using the main pipeline's decoded
  controls. Next-PC continuity is checked against the previous instruction's
  outcome.
- **sM** — `shadow_verifier` compares against the OQ, RQ and SQ records. The RQ
  entry is `entry[sValidW]`, the SQ entry is `entry[NVerified + (sW holds a store)]`.
- **sW** — `Commit = valid & no fault`: write the regfile, pop the RQ, mark the SQ
  entry verified. `Fault = valid & any fault`: commit nothing.

The shadow has no load-use hazard: a load's value (the RQ result, verified against
the raw word) is available in sM.

### Fault classes (`FaultClass[7:0]`, also the low byte of `mtval` on a cause-16 trap)

| bit | name | check |
|-----|------|-------|
| 0 | OP | rs1/rs2 values the main pipeline used ≠ shadow's (forwarding select, RQ forwarding, regfile read) |
| 1 | NPC | instruction is not at the PC its predecessor leads to (fall-through or shadow-computed branch/jump target) |
| 2 | RES | ALU / link result ≠ RQ result |
| 3 | EA | ALU sum ≠ the main pipeline's (effective address, branch/jump target) |
| 4 | BR | branch/jump direction |
| 5 | LD | load result ≠ independent `subwordread` of the raw word |
| 6 | ST | SQ entry: address page offset, size, or data. Data is the shadow's own rs2, or for an AMO the shadow's own `amoalu(old value, rs2)` |
| 7 | RD | RQ record's Rd / RegWrite ≠ the instruction's |

The next-PC chain breaks at a trap (`StreamBreak = TrapM`) and after an xRET; the
first instruction after either is not checked. After a fault the chain is set to
the restart PC, so the replay must begin exactly there.

`FaultPC` is the PC the faulting instruction *should* have had (the chain's
expectation), not the PC the main pipeline fetched; for a next-PC fault the two
differ.

---

## 6. Store buffer — `lsu.sv`

### 6.1 Classification (Memory stage)

```
SimpleMemOKM = naturally aligned & ~FP & ~big-endian & ~DTIM & no cache-block op
SQStoreM     = MemRWM[0] & SimpleMemOKM & LSURWM[0]      // store, AMO, successful SC
SerialMemM   = (|MemRWM & ~SimpleMemOKM) | (MemRWM[1] & ~CacheableM) | |CMOpM
```

- A **queued** store (`SQStoreM`) presents nothing to the cache or bus; an AMO
  presents only its read. It still goes through the MMU, so translation, PMP/PMA
  and page faults behave as before. Its `{PAdrM, size, IMAWriteDataM}` is pushed
  at `MExitM`. Uncacheable (device) stores are queued too and drain to the bus.
- A **serialized** access (misaligned, FP, big-endian, cache-block op, or a read of
  uncacheable memory, which may have side effects) waits for quiescence and then
  runs through the unmodified legacy path.

### 6.2 Holds

```
HoldM = ((NonMemSerialM | SerialMemM) & ~ShadowQuiescentM)   // wait for the shadow
      | ShardPreFaultM                                        // failed a check; about to replay
      | (MemRWM[0] & SimpleMemOKM & SQFull)                   // store, SQ full
      | ((ITLBMiss | DTLBMiss) & ~WalkOK)                     // page walk waits for an empty SQ
ShadowQuiescentM = ShadowIdleM & SQEmpty & ~SQBusy
WalkOK           = SQEmpty & ~SQBusy
```

A hold stalls the pipeline (`LSUStallM`) and hides the M-stage instruction from the
cache and bus (read/write, cache-block op and D-cache flush are masked). All
Memory-stage side effects in Wally are already gated by `~StallW`, so holding an
instruction there is safe for every class.

Page table walks read PTEs — and with Svadu write one — straight through the
D-cache, so the HPTW's miss inputs are gated by `WalkOK`: a walk starts only with
the SQ empty.

### 6.3 Drain engine

Modeled on the HPTW (a second requester that takes over the LSU while the
pipeline is stalled):

```
IDLE     head verified & ~CommittedM  →  SQStart: hide the M-stage instruction,
         present the head's address (the cache reads its set)
WR       replay the head as an ordinary store; wait out a miss or the bus; pop
ADR      present the next head's address when several stores drain in a row
RESTORE  present the M-stage instruction's own address again; skipped when it
         makes no cache access of its own
```

While the engine owns the LSU its address, size, data and read/write replace the
IEU/HPTW requests (`SQDrainSel`), translation is disabled, faults are masked, and a
pipeline flush does not reach the cache (`LSUFlushW` is masked) — the store being
written is verified and older than anything a flush discards. Drains only ever
interleave with aligned cacheable loads and non-memory instructions; every other
memory operation requires an empty SQ first.

### 6.4 Store-to-load forwarding

`shadow_sqmerge` merges, byte by byte and newest last, every SQ entry whose
physical doubleword address equals the load's over the word read from the cache.
The merged word feeds `subwordread`, the AMO ALU, and `RawReadDataWordM` (which the
shadow re-derives the load from). The merge is instantiated twice and the copies
compared (`LoadFwdFaultM`).

---

## 7. Memory-stage checks

These cover what a trailing shadow cannot re-derive, and what must be right
*before* a serialized instruction acts.

| check | where | what |
|-------|-------|------|
| **EA** | core | second AGU adder and second address register vs `IEUAdrM`, every memory access |
| **Operand** | core | once `ShadowIdleM`, the regfile is architecturally current, so the M-stage instruction's `ForwardedSrcAM` / `WriteDataM` must equal it. Read through the shadow's ports, which are free then. This verifies in place every instruction that waited for quiescence |
| **AMO** | `lsu.sv` | second `amoalu` vs the first |
| **LoadFwd** | `lsu.sv` | the two store-queue merges |
| **CSR** | `csr.sv` | value read = CSR mirror's; value to be written = second csrrw/s/c datapath fed from the mirror's old value and from `ForwardedSrcAM` (not the main CSR path's `SrcAM`) |
| **MUL** | `mdu.sv` | mod-3 residue: `res(A)·res(B) = res(ProdM)`, with sign corrections for mulh/mulhsu |
| **FMA** | `fma.sv` | mod-3 residue of the significand product `Xm·Ym = Pm` |
| **CSR state** | `shadow_csr.sv` | every mirrored register equals the main one, every cycle |

A failing check sets `ShardLocalFaultM`: the instruction is held (stall) and, for
the checks outside the LSU, hidden from memory (`ShardPreFaultM` → `HoldM`).

### 7.1 CSR state mirror — `shadow_csr.sv`

An independent second copy of: privilege mode, `mstatus` (and its `sstatus` view),
`medeleg`, `mideleg`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `stvec`,
`sscratch`, `sepc`, `scause`, `stval`, `satp`. It has its own storage, address
decode, WARL legalization, and trap-entry / xRET updates (including its own
delegation decision), driven by the same committed events as the CSR file. CSR
writes and traps happen only at quiescence, so events arrive in architectural
order.

Not mirrored: `mie`/`mip` (hardware-driven bits), counters and counter enables,
`menvcfg`/`senvcfg`, PMP, `fcsr`, custom CSRs. For these only the write datapath is
duplicated.

### 7.2 Residue checks

The multipliers are the one large block the shadow does not duplicate. A mod-3
residue check is arithmetically unrelated to the array, so a permanent fault or a
trojan cannot corrupt both the same way; every single-bit product error is caught.
The integer divider (on the FPU's `fdivsqrt` in this configuration) has no check.

---

## 8. Fault response

```
shadow fault (sFault)      queues flushed at once (SQ keeps its verified entries);
                           RecPending; redirect to FaultPC when ~CommittedM & ~CommittedF
Memory-stage fault         instruction held; redirect to PCM when ~CommittedF
either, 3rd time running   cause-16 trap instead of another replay; mepc = faulting PC, mtval = classes
CSR state fault            cause-16 trap at once; mirror reloaded after the trap is taken
```

- The redirect (`ShardRedirectM`) is a flush cause for every stage, exactly like a
  trap, and selects `ShardRedirectPCM` in the IFU. An xRET waiting in M is masked in
  the redirect cycle; the LR reservation is dropped (the replayed SC fails and
  software retries).
- `RetryCount` counts faults with no shadow commit in between. At
  `SHARD_RETRY_LIMIT` (3) the fault is not transient, and it becomes a precise
  trap: `mcause = 16` (never delegated), `mepc` = the faulting instruction,
  `mtval` = `{CSRState, FMA, MUL, LoadFwd, AMO, CSR, Operand, EA, FaultClass[7:0]}`.
- `MSECFAULT[6]` is set on every detection, recovered or not.
- **Traps wait for the shadow.** `TrapM = TrapPendingM & ShadowQuiescentM`; a pending
  trap holds the M-stage instruction (through `NonMemSerialM`) until then. A trap
  changes privileged state that cannot be rolled back, so it may only be taken
  when nothing older is still unverified.

Default-on: there is no enable parameter and no detect-only mode.

---

## 9. Hazard unit

```
FlushD/E/M/WCause |= ShardRedirectM
StallWCause       |= ShardStallW & ~FlushWCause        // backpressure | Memory-stage fault hold
LSUStallM          includes HoldM and the drain engine  // already gated by ~FlushWCause
```

The former `ShadowDCacheStallM` / `ShadowVerifyConflictStallM` inputs and the
exported `FlushWCause` are gone.

---

## 10. Invariants a re-port must preserve

1. Push only at `MExitM` (IQ, OQ, SQ) and once per W-stage instruction (RQ). Never
   push a flushed instruction.
2. The RQ push must not depend on `StallW`.
3. Nothing may write the regfile except shadow commit; nothing may write memory
   from the Memory stage except a serialized access running at quiescence, the
   HPTW, and the drain engine.
4. Any wait for the shadow must stall through `StallW` *and* mask the M-stage
   instruction's cache/bus request; it must yield to a flush cause.
5. A page walk, and any access the byte-merge cannot represent, requires an empty
   SQ.
6. A redirect must squash everything a trap would, plus xRET.
7. The drain engine starts only with `~CommittedM`, and its write is immune to
   pipeline flushes.

---

## 11. Coverage and boundaries

Each row was validated both ways: sound (0 faults across all tiers and a Linux
boot, §13) and effective (an injected fault fires it, §13.3).

| Class | Independent check | Response |
|-------|-------------------|----------|
| ALU / bit-manipulation result | shadow ALU on shadow operands (RES) | replay |
| Operand forwarding (ForwardAE/BE, RQ forwarding, regfile read) | shadow sources operands itself (OP); Memory-stage Operand check for serialized instructions | replay |
| Branch direction, branch/jump target | shadow comparator and adder (BR, EA) | replay |
| Next PC | shadow-computed successor (NPC) | replay at the expected PC |
| Load / store effective address | shadow adder (EA) + second AGU adder and register | replay |
| Load data | second `subwordread` on the raw word (LD); duplicated store-queue merge | replay |
| Store data and address | SQ entry vs shadow's own rs2 and address (ST); store never reaches memory unverified | replay |
| AMO | shadow `amoalu` on its own operands (ST) + second `amoalu` in the LSU | replay |
| CSR read/write value, trap and xRET effects, CSR storage | CSR state mirror | replay; state divergence traps |
| Integer multiply | mod-3 residue | replay |
| FMA significand multiply | mod-3 residue | replay |
| Persistent fault of any of the above | retry counter | cause-16 trap |

Boundaries (not covered):

- **Decode.** The shadow re-executes with the main pipeline's decoded datapath
  controls; it derives register numbers, immediates and funct fields from the
  instruction word itself.
- **Address translation.** The shadow does not re-translate; the SQ address check
  uses the page offset. HPTW and TLB are out of scope.
- **Fetch.** Instruction bits are trusted; only PC continuity is checked. A
  transient wrong `PCNextF` is corrected by the existing misprediction logic
  before anything retires.
- **Floating point beyond the FMA multiplier, and integer divide** (which shares
  `fdivsqrt`). FP instructions are serialized and their integer operands checked,
  but their results are not recomputed.
- **Raw memory data.** The word read from the cache is trusted (the SRAMs' own
  protection applies); what happens to it afterwards is checked.
- **Non-mirrored CSRs** (§7.1), the SC success flag, trap *cause* selection.
- **The checker itself.** The verifier, queues and commit port have no self-check.
- **Duplicated blocks are identical copies**: a second `amoalu`, CSR datapath,
  store-queue merge, AGU adder catch transient faults in either copy, not a
  design-level trojan common to both. Synthesis must be told not to merge them.

---

## 12. Cost

Measured against the Rev 7 commit, same tests, cycles to completion:

| test | Rev 7 | Rev 8 | change |
|------|-------|-------|--------|
| `sorting_algo` | 10,426 | 12,421 | +19% |
| `tc_branch_prediction` | 245,075 | 251,266 | +2.5% |
| FreeRTOS `tc_timer_preempt` | 265,652 | 286,351 | +7.8% |

The cost is the store drain: two stalled cycles per isolated store (three when the
M-stage instruction must have its cache set restored), because the D-cache has one
port. Serialized instructions wait about four cycles for the shadow to catch up.
Reading the regfile in Execute lengthens that stage's path; this has not been
through timing closure.

---

## 13. Validation

### 13.1 Regressions

`make baremetal_regression` 5/5 (Spike co-simulation), `make isa_regression` 9/9,
`make freertos_regression` 5/5, `make ecc_baremetal_regression` 8/8, and
`make linux_boot` → `AMOEBA_LINUX_BOOT_OK` after 191,579,897 cycles.

Soundness was established with temporary instrumentation (counters and
time-windowed prints, since removed): zero shadow faults, Memory-stage faults,
replays and cause-16 traps in every regression and across the whole Linux boot,
during which the shadow verified and committed 50.4M instructions, 9.0M stores
went through the store buffer, and every check listed in §11 except the FMA
residue saw real traffic (the kernel uses no floating point; `tc_shard_direct`
covers it). The per-check counts are in `shadow_review.md` §0a. The clean build
boots in exactly the same number of cycles as the instrumented one.

### 13.2 Tests added

`testcode/shard/tc_shard_spec.c` (store-to-load forwarding, AMO, LR/SC, multiplies,
CSR round-trips with a trap and `mret`) and `testcode/shard/tc_shard_direct.c`
(misaligned accesses, FP including FMA). Neither is part of a regression target:
the first runs on the ordinary no-Spike simulator, the second needs a build without
the RVFI monitor, which models a misaligned access as a trap. The run commands
are in each file's header.

### 13.3 Fault injection

Each check was shown to fire, and the response to work, by temporary injection
hooks (since removed): a single-instruction bit flip at the named point, with the
test judged by the `tohost` store that actually drained to memory.

| injected fault | caught by | outcome |
|----------------|-----------|---------|
| main ALU result | RES | replayed, test passes |
| forwarded rs1 | OP (+RES/EA); Operand check when the victim was serialized | replayed, passes |
| branch decision | BR | replayed, passes |
| load result after extract | LD | replayed, passes |
| store data into the SQ | ST | replayed, passes; bad store never drained |
| store address into the SQ | ST | replayed, passes |
| AMO result | AMO (Memory stage) | replayed, passes |
| CSR write value | CSR (Memory stage) | replayed, passes |
| multiplier product | MUL residue | replayed, passes |
| FMA significand product | FMA residue | replayed, passes |
| load / store address register | EA (Memory stage) | replayed, passes |
| one copy of the store-queue merge | LoadFwd | replayed, passes |
| RQ result record | RES | replayed, passes |
| retired PC | NPC (+EA) | replayed at the expected PC, passes |
| `mscratch` storage upset | CSR state | cause-16 trap |
| any of the above made permanent | same check, three times | cause-16 trap, `mepc` = faulting PC |

Injections that landed on an instruction the pipeline later squashed (after a CSR
write's refetch, say) were, correctly, not reported. A transient flip of
`PCNextF` was corrected by the branch-misprediction logic before anything retired.

One consequence for the testbench: RVFI and the `tohost` monitor observe
retirement from main W, which under Rev 8 is *proposed*, not committed. In a
fault-free run the two are the same stream. Under injection the monitor can see a
wrong-path instruction retire that the shadow then squashes; injection runs were
therefore judged at the store-buffer drain.

---

## 14. Re-port checklist

1. Regfile: single write port from the shadow; read ports 1/2 addressed from
   Execute; two more read ports for the shadow.
2. Record `ForwardedSrcAM`, the datapath controls and `PCSrcE` in M.
3. Queues and pushes exactly as §3.
4. RQ forwarding into the Execute operand mux, below the M/W bypasses.
5. LSU: classification, `HoldM`, drain engine, merge, `WalkOK` gating of the HPTW,
   request masking (§6). Make every cache/bus write conditional on drain / HPTW /
   non-queued access.
6. Trap gating on quiescence; `NonMemSerialM`.
7. Redirect: hazard flush causes, IFU mux, xRET mask, reservation clear.
8. Memory-stage checks and the fault-response logic (§7, §8).
9. Bring-up order that exposes problems progressively: baremetal → ISA →
   FreeRTOS (traps, interrupts, CSRs) → `tc_shard_*` → Linux boot (MMU, atomics,
   device I/O). Then inject.
