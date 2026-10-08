# SHARD Rev 8 — Porting Specification

**What this is.** A complete, self-contained specification of SHARD (Shadow
Hardware Audit Redundancy Design) as implemented at commit `3a1df55` on CORE-V-Wally
(`wallypipelinedcore`, the AMOEBA fork). It is written for an engineer or agent who
must re-implement SHARD on the same Wally core under a different configuration and
who **cannot read the original source**. Every new module is reproduced in full;
every edit to an existing Wally file is given as exact code with the reason for it.

**How to use it.** Read §1–§4 for the model. §5–§12 are the implementation, in the
order to build it. §14 lists every trap that was hit while building it — read it
before debugging, not after. §15 says what changes with the configuration. §17 is
how to prove the port is right.

**Conventions.** A suffix `D/E/M/W` on a signal is the main pipeline stage it
belongs to. A leading `s` (`sValidE`, `sInstrM`) is a shadow pipeline stage. "Main"
means the ordinary Wally pipeline. *Queued* means an instruction whose effect is
deferred through a queue; *serialized* means an instruction that is held in the
Memory stage until the shadow has caught up. *Quiescent* is defined in §3.

## 0. Status of what is described

| | |
|---|---|
| Validated configuration | `pkg/config.vh`: RV64GC, FPU present (`F`/`D`/`ZFH`), `IDIV_ON_FPU=1`, `ZICCLSM=1`, `ZICBOM/ZICBOZ/ZICBOP=1`, `SVADU=1`, `BIGENDIAN=1`, S and U modes, Sv39/48/57, D-cache 4 ways × 4 KiB, 64-byte lines, bus + cache (no DTIM), branch predictor on |
| Evidence on that config | bare-metal 5/5 with Spike co-simulation, ISA 9/9, FreeRTOS 5/5, ECC-injection 8/8, OpenSBI 1.4 + Linux 6.6 to userspace (191,579,897 cycles). An instrumented boot showed zero faults over 50.4M verified instructions. 123 fault injections: all that hit a retiring instruction were detected and recovered |
| Pruned no-FP Linux config | `pkg/config_baremetal_linux.vh` (`F=0`, `IDIV_ON_FPU=0`, `ZICCLSM=0`, `ZICBO*=0`, `SVADU=0`, `BIGENDIAN=0`, `PMP_ENTRIES=0`, D-cache 4 × 2 KiB). The same RTL **elaborates and builds unchanged**. With that configuration genuinely selected (§15) and the instrumentation of §17.2, eight programs were run — `exit_test`, `basic_arith`, `test_fwd_depth`, `sorting_algo`, `tc_shard_spec`, `tc_mul_div`, `tc_forwarding`, `tc_compressed` — and all pass with zero shadow faults, Memory-stage faults, replays and cause-16 traps (store buffer, AMO, LR/SC, CSR mirror with a trap and `mret`, multiply, and divide in the MDU all exercised). A ninth, `tc_branch_prediction`, cannot run on that configuration: it executes `rdcycle`, the configuration has `ZICNTR_SUPPORTED = 0`, and the run ended in the test's own trap-halt loop right after the first sub-test banner. It is not counted either way. No Linux boot was run on it: the existing boot image is hard-float and does not match that config |
| Not implemented | Verification of integer divide/remainder results. §13 specifies a check; it has **not** been built or tested |
| Not validated | RV32; a configuration with no D-cache; DTIM |

Everything in §5–§12 is exactly what was validated. Where this document proposes
something that was not built, it says so in bold.

---

## 1. The model

> The main pipeline proposes; the shadow verifies and commits.

SHARD adds a second, trailing copy of the back end of the pipeline. Through Rev 7
that copy only *detected*: it trailed by a fixed number of cycles, shared the main
pipeline's stalls, and raised a flag after the main pipeline had already written
memory and CSRs. Rev 8 makes it the commit point. Nothing the main pipeline
computes becomes architectural state until the shadow has verified it.

There are exactly three ways an instruction can change state. Each has one gate:

| State | How the main pipeline's effect is held back | What releases it |
|---|---|---|
| **Integer register file** | The result waits in the Result Queue (RQ). The regfile has one write port and only the shadow drives it. Main Execute reads *through* the RQ | Shadow commit |
| **Memory** — ordinary stores, the write half of an AMO, a successful SC | The store waits in the Store Queue (SQ), a real store buffer. The main pipeline never writes the D-cache or the bus for these. Loads see the buffer through a byte-merge | Shadow commit marks the entry verified; a drain engine in the LSU then writes it |
| **Everything else** — CSR writes, privilege mode, traps, xRET, FP registers and flags, reads of device (uncacheable) memory, fences, cache-block operations, and memory accesses the buffer cannot represent (misaligned, FP, big-endian) | The instruction is **held in the Memory stage** until the shadow is quiescent | Memory-stage checks verify it in place; then it acts directly, as in stock Wally |

Because nothing is committed before it is verified, the response to a fault is
exact: discard, and re-execute from the faulting instruction.

```
            F    D    E         M                W
main:      ─┬────┬────┬─────────┬────────────────┬──────────────
                      │ regfile │ leave M        │ first cycle
                      │ read    │ unflushed      │ in W
                      ▲         ▼                ▼
                      │      ┌──────┐ ┌──────┐ ┌──────┐
       RQ forwarding  │      │  IQ  │ │  OQ  │ │  RQ  │   ┌──────┐
       (newest match) └──────┤      │ │      │ │      │   │  SQ  │◄── leave M, queued store
                             └──┬───┘ └──┬───┘ └──┬───┘   └─┬──┬─┘
                                ▼        ▼        ▼         │  │
shadow:                         sD ────► sE ────► sM ──► sW │  │ verified ─► LSU drain ─► D-cache / bus
                                         ▲ own operands  │  │  │
                                         │ (regfile+bypass) ▼  │
                                         └── regfile ◄── commit ┘ (mark SQ entry verified)
```

### 1.1 Why the earlier design could not simply be extended

Three properties of the Rev ≤7 shadow each block prevention, and Rev 8 is the
smallest change that removes all three:

1. **Coupled stalls.** If the shadow only advances when the main pipeline does,
   then anything in the main pipeline that waits for the shadow waits forever.
   Holding a store until it is verified is exactly such a wait. So the shadow must
   advance on its own (queue occupancy), and its input must not depend on the main
   pipeline being unstalled.
2. **Queues filled at four different stages.** Rev ≤7 pushed the IQ at Decode, the
   OQ at E→M, the SQ at M and the RQ at W, including instructions later flushed,
   and re-aligned by comparing PCs. Around every mispredict or load-use bubble the
   comparison was skipped. A commit gate cannot skip. Rev 8 pushes only instructions
   that are certain to retire, in order, so entry *k* of every queue is the same
   instruction.
3. **Operands taken from the main pipeline.** If the shadow re-executes with the
   operands the main pipeline forwarded, a wrong forwarding select and wrong store
   data are echoed, not detected. Rev 8's shadow reads its operands from the
   committed register file and its own later stages.

### 1.2 What happens to each instruction class

Every retired instruction goes through the shadow and gets the OP, EA, RD and NPC
checks of §5.3, whatever else applies. "Held" means held in the Memory stage until
the shadow is quiescent (§7.2).

| Class | State it changes, and the gate | In the Memory stage | Checked by |
|---|---|---|---|
| ALU, shifts, bit-manipulation, `lui`, `auipc` | register → RQ | nothing special | shadow re-execution (RES) |
| Conditional branch | none | — | shadow comparator (BR), target (EA), successor's PC (NPC) |
| `jal`, `jalr` | link register → RQ | — | RES (link), BR, EA (target), NPC |
| Aligned load from cacheable memory; `lr` | register → RQ (`lr` also sets the reservation) | reads the cache at once; buffered store bytes merged in | EA (shadow and Memory stage), LD, duplicated merge |
| Aligned store (any region) | memory → SQ | presents nothing to the cache/bus; held only if the SQ is full | ST (address, size, data from the shadow's own `rs2`) |
| `sc` | memory → SQ if the reservation held; register (0/1) → RQ | as a store | ST; the success flag itself is trusted |
| AMO | register (old value) → RQ; memory (new value) → SQ | reads the cache only | LD on the old value; ST with the shadow's own AMO ALU; second AMO ALU in M |
| `mul*` | register → RQ | — | mod-3 residue in M; operands by OP |
| `div*`, `rem*` | register → RQ | — | **operands only** (§13) |
| CSR instruction that only reads | register → RQ | — | read value against the CSR mirror |
| CSR instruction that writes | CSR at once (serialized) | held; operands compared with the regfile; read and write values checked; then acts | CSR mirror (before and after) |
| Exception, interrupt | `xepc`/`xcause`/`xtval`/`mstatus`/privilege (serialized) | held until quiescent, then `TrapM` | CSR mirror's own trap entry |
| `mret`, `sret` | `mstatus`, privilege (serialized) | held, then acts | CSR mirror's own return |
| `wfi`, `fence`, `fence.i`, `sfence.vma` | cache/TLB state (serialized) | held, then acts | operands against the regfile |
| Misaligned access, read of device memory, FP load/store, cache-block operation, anything in big-endian mode | memory or device, directly (serialized) | held, hidden from the cache/bus, then runs through the legacy path | operands against the regfile; address by the second AGU adder — before it runs |
| Any other FP instruction | FP register / flags (serialized) | held, then acts | integer operands against the regfile; FMA product residue |

### 1.3 Four walk-throughs

**A store followed at once by a load of the same word.** The store leaves M without
touching the cache and enters the SQ (and IQ/OQ). The load, next cycle, reads the
cache — stale for those bytes — and the merge overlays the store's bytes from the
SQ. Four cycles after the store left M the shadow commits it: its SQ entry becomes
verified. The drain engine stalls the pipeline for two or three cycles, writes the
store through the normal cache write path, and the SQ is empty again.

**A CSR write.** It reaches M while the instruction ahead of it is in W. `HoldM`
stalls the pipeline. The instruction in W pushes its result into the RQ anyway;
the shadow verifies and commits it; any store drains. Four or so cycles later the
shadow is quiescent. In that cycle the regfile is architecturally current, so the
CSR instruction's `rs1` value is compared with it, the value it read is compared
with the mirror, and the value it will write is compared with the second datapath's.
If all agree it commits at that M→W edge exactly as in stock Wally (and Wally's
usual refetch of the following instruction happens). It then flows through the
shadow like any instruction, for its register result.

**An interrupt.** `InterruptM` asserts with some instruction in M and others still
unverified. `TrapPendingM` holds M. When the shadow is quiescent `TrapM` fires:
the M-stage instruction is flushed, the CSRs and the mirror take the trap entry in
the same cycle, and the shadow's next-PC chain is broken so the handler's first
instruction is not expected at the old PC.

**A transient fault in the ALU.** The wrong result goes into the RQ and may be
forwarded to younger instructions, which may branch on it or store it. The shadow
recomputes the result from its own operands, sees RES, and commits nothing. The
queues are emptied (so the younger instructions' results and stores vanish), and
the pipeline is redirected to the faulting instruction's PC. Everything from there
is re-executed; the second time the result is right.

---

## 2. Properties of Wally that SHARD depends on

Check each of these in the target tree before starting. Each is used by a specific
part of the design; if one does not hold, that part must change.

**W1 — `flopenrc` ignores `clear` while not enabled.** `if (reset) q<=0; else if
(en) if (clear) q<=0; else q<=d;`. A flush asserted while a stage is stalled does
nothing to that stage. Every SHARD stall therefore yields to flush causes (§8).

**W2 — bubbles and valid bits.** `InstrValidD/E/M` come from the controller's
pipeline registers and are cleared by flushes. A bubble has all-zero controls
(`MemRWM=0`, `CSRWriteM=0`, …). SHARD adds `InstrValidW`.

**W3 — Memory-stage effects commit at the M→W edge.** In stock Wally any
instruction can be stalled in M by an instruction-fetch stall, so every
architectural effect in M is already gated by `~StallW` (and most by `~FlushW`):
CSR writes use `InstrValidNotFlushedM = InstrValidM & ~StallW & ~FlushW`; the
privilege-mode flops and `mstatus` update only with `~StallW`; the PC register
loads only with `~StallF`. *This is why holding any instruction in M is safe.*
The exceptions, which SHARD handles explicitly, are:
  - LSU operations **start** regardless of `StallW` (cache lookup, miss handling,
    bus access). SHARD hides the M-stage request from the cache and bus while it
    holds the instruction (§7).
  - `mretM`/`sretM` are not gated by `FlushW`. Stock Wally relies on `TrapM` having
    priority. SHARD masks them in the cycle of a redirect (§9.2).
  - `FRegWriteM` sets `mstatus.FS` dirty without a `FlushW` gate (§9.4).
  - The LR reservation is set/cleared without a `FlushW` gate (§7.7).

**W4 — the hazard unit gates stalls with flush causes.** `StallWCause` terms are
ANDed with `~FlushWCause`, so a trap goes through in one cycle even if the LSU is
asking for a stall. "Flush cause for D, E, M and W" is what `TrapM` produces; a
SHARD redirect is added as exactly that.

**W5 — Writeback-stage values are registered and stable.** `IFResultW`,
`ReadDataW`, `CSRReadValW`, `MDUResultW`, `SquashSCW`, `RdW`, `RegWriteW`,
`ResultSrcW` are all loaded at the M→W edge and hold while `StallW`. So `ResultW`
is valid from the instruction's *first* cycle in W.

**W6 — the regfile writes on the falling clock edge** and reads combinationally, so
a write in a cycle is visible to a read in the second half of the same cycle.

**W7 — forwarding is complete.** `ForwardAE/BE` select the M-stage or W-stage
result when `Rs1E/Rs2E` matches `RdM/RdW`, and Decode stalls (`LoadStallD`,
`CSRRdStallD`, `MDUStallD`, `FCvtIntStallD`) cover every case where the M-stage
value is not yet available. These comparisons use the raw instruction fields
whether or not the instruction uses them as registers. With SHARD's change in §6,
the consequence is: **`ForwardedSrcAE` and `ForwardedSrcBE` are the exact
architectural values of `x[InstrE[19:15]]` and `x[InstrE[24:20]]` for every
instruction in every cycle it spends in Execute.** The operand checks rely on this.

**W8 — the LSU request chain.** The IEU's request (`MemRWM`, `Funct3M`, `AtomicM`,
`IEUAdrExtM`, `WriteDataM`, `CMOpM`) passes through the HPTW, which substitutes its
own request while `SelHPTW`: `PreLSURWM`, `LSUFunct3M`, `LSUFunct7M`, `LSUAtomicM`,
`LSUCMOpM`, `IHAdrM`, `IHWriteDataM`. `PreLSURWM` goes to the MMU (translation,
PMP/PMA and page-fault checks) and to `atomic`, which produces `LSURWM` (an SC that
loses its reservation becomes `00`). `LSURWM` is what the cache (`CacheRWM`) and bus
(`BusRW`) see. `DisableTranslation` makes the MMU pass the address through.
`LSUFlushW = HPTWFlushW | FlushW` cancels the operation at the cache and bus.
`GatedStallW = StallW & ~SelHPTW` is the cache's and bus's "pipeline is stalled"
input. `LSUStallM` enters `StallWCause`.

**W9 — the D-cache protocol** (`cache.sv`, `cachefsm.sv`). This is what the drain
engine must obey.
  - The SRAMs have one port and are synchronous. The set to read is chosen one
    cycle ahead: normally `NextSet` (the *Execute* instruction's address), so that
    data and tags are ready when the instruction is in M. When the FSM is busy, or
    `SelHPTW`, the set is taken from `PAdr` (the M-stage physical address) instead.
  - `CacheRW` is `{read, write}`. A hit completes in `STATE_ACCESS` in one cycle; a
    write hit writes at the end of that cycle. A miss goes `ACCESS → (WRITEBACK →)
    FETCH → WRITE_LINE → ADDRESS_SETUP → ACCESS`; a store miss merges the store
    data into the fetched line in `WRITE_LINE`. `CacheStall` is high throughout
    except in `ADDRESS_SETUP`, which is the cycle the pipeline advances.
  - `Stall` (pipeline stalled): the FSM does not accept a new access, and
    `CacheEn = (~Stall | StallConditions) | (state != ACCESS) | …` holds the SRAM
    outputs. So an instruction stalled in M keeps the set it read.
  - `FlushStage` forces the FSM to `ACCESS` and disables every write enable in the
    same cycle. That is how an exception or interrupt cancels the M-stage access.
  - `CacheCommitted = (state != ACCESS)`. `CommittedM = SelHPTW | DCacheCommittedM |
    BusCommittedM` means "an operation is in flight that must not be interrupted".
  - The set index must lie in the page offset (`NextSet` is 12 bits), which is
    already a Wally requirement.

**W10 — the HPTW is the template for a second LSU requester.** It starts in the
first cycle of the M-stage (or F-stage) access that missed the TLB, asserting
`HPTWFlushW` to cancel that access and `HPTWStall` to stall the pipeline. Each
level has an `ADR` state (present the address, `RW=00`, the cache reads the set
because `SelHPTW` forces `PAdr`) and an `RD` state. With Svadu, `LEAF → UPDATE_PTE →
LEAF` is an address cycle followed by a write. In `LEAF` it switches the address
back to the original access while `SelHPTW` is still 1, so the cache re-reads the
original set before the access is replayed in `IDLE`. In the `FAULT` state it
presents registered fault flags for one cycle with `HPTWStall = 0`.

**W11 — traps.** `TrapM = (ExceptionM & ~CommittedF) | InterruptM`, where
`InterruptM` additionally requires `InstrValidM` and `~(CommittedM | CommittedF)`.
A trap in M flushes D, E, M and W (the M-stage instruction does not retire).

**W12 — a CSR write or fence refetches.** `CSRWriteFenceM = CSRWriteM | FenceM`
flushes D and E and refetches from `NextValidPCE`. The instruction after a CSR
write is always squashed once.

**W13 — the multiply/divide unit.** `mul` registers four partial products at the
E→M edge and sums them combinationally in M (`ProdM`, 2·XLEN bits). With
`IDIV_ON_FPU=0`, `div` is iterative: it stalls Execute (`DivBusyE`) and presents
`QuotM`/`RemM` in M. With `IDIV_ON_FPU=1` integer divide runs on the FPU's
`fdivsqrt` and returns through `FIntDivResultW`.

**W14 — the next-PC chain in the IFU.** `PC1NextF` (prediction / branch
correction) → `pcmux2` (`CSRWriteFenceM` selects `NextValidPCE`) → `pcmux3`
(`{TrapM, RetM}` selects `EPCM` / `TrapVectorM`) → reset mux → `PCF`.

**W15 — AMOEBA-specific logic present in the validated tree.** If the target lacks
any of these, drop the corresponding lines; none of them is needed by SHARD.
  - The integer regfile stores SECDED codewords and decodes on each read port;
    several datapath pipeline registers are `flopenrc_ecc`. Their `sec/ded` flags
    are ORed into `RegEccSecErrW/RegEccDedErrW`. An uncorrectable error is latched
    and raises a trap with `mcause = 19`, using a captured EPC.
  - *Dummy instruction injection* (`dummygen`, `InjectD`, `DummyW`): the IEU can
    replace the Decode instruction with a harmless ALU instruction for one cycle.
    A dummy has `InstrValidE/M = 0`, so it never retires, is never pushed into a
    SHARD queue, and is never verified. The regfile's `DummyW/DummySelW` inputs
    (redirect a write to a spare register) are tied to 0.
  - `csrharden` collects a 7-bit vector into the sticky custom CSR `MSECFAULT`
    (`0x7C0`); bit 6 is SHARD's "a fault was detected".
  - The privilege mode register is triplicated (`privmode`).

---

## 3. Vocabulary and the signals that tie the design together

All of these are in `wallypipelinedcore` unless noted.

| Signal | Definition | Meaning |
|---|---|---|
| `MExitM` | `InstrValidM & ~StallW & ~FlushW` | The M-stage instruction moves to W this cycle. From here it is certain to retire |
| `InstrValidW` | `MExitM` registered (`flopenrc`, clear `FlushW`, enable `~StallW`) | W holds a retired instruction |
| `ShardPushOK` | `~RecPending & ~sFault` | Queues may be pushed. False from a shadow fault until the redirect |
| `QPushM` | `MExitM & ShardPushOK` | Push IQ and OQ (and SQ if `SQStoreM`) |
| `RQPushW` | `InstrValidW & ~WPushed & ShardPushOK` | Push the RQ, once per W-stage instruction, on its first cycle |
| `WPushed` | next = `StallW & (WPushed \| RQPushW)` | This W-stage instruction's result is already in the RQ |
| `InFlight` | += `QPushM`, −= `sCommit`; 0 on `sFault` | Instructions past M that the shadow has not committed |
| `ShadowIdleM` | `(InFlight == 0) & ~RecPending` | Every retired instruction is verified and committed, so the regfile is architecturally current |
| `ShadowQuiescentM` (LSU) | `ShadowIdleM & SQEmpty & ~SQBusy` | …and no store is buffered or being drained. This is when a serialized instruction may act and a trap may be taken |
| `NonMemSerialM` | see §11 | The M-stage instruction has an irreversible effect outside memory, or a trap is pending |
| `SerialMemM` (LSU) | see §7.1 | The M-stage memory access cannot go through the store buffer |
| `SQStoreM` (LSU) | see §7.1 | The M-stage instruction will push an SQ entry when it leaves M |
| `HoldM` (LSU) | see §7.2 | Stall the pipeline and hide the M-stage instruction from the cache and bus |
| `sCommit`, `sCommitStore`, `sFault`, `sFaultPC`, `sFaultClass` | from `shadow_pipeline` | Shadow commit of the sW instruction; it owned an SQ entry; or it failed |
| `RecPending`, `RecPC` | set by `sFault`, cleared by the redirect | A shadow fault flushed the queues; the main pipeline still has to be redirected |
| `ShardLocalFaultM` | see §11 | The M-stage instruction failed a Memory-stage check |
| `ShardRedirectM`, `ShardRedirectPCM` | see §12 | Flush D/E/M/W and refetch |
| `ShadowFaultTrapM` | see §12 | A fault that could not be recovered is presented to the trap logic as an exception (cause 16) |

The time line of one ordinary instruction *k* with nothing in its way:

```
cycle        c0            c1               c2            c3            c4            c5
main         k in M        k in W (1st)
             MExitM ───►   IQ,OQ(,SQ) hold k
                           RQPushW  ───►    RQ holds k
shadow                     sD: IQ head=k    sE            sM            sW
                           AdvanceDE        operands,     verify vs     Commit:
                                            ALU, OQ head  OQ/RQ/SQ      regfile written (falling edge),
                                                                        RQ popped, SQ entry verified
                                                                                      InFlight back to 0;
                                                                                      drain may start
```

So the commit latency is four cycles after the instruction leaves M, and an
instruction *k+1* that is serialized waits in M from `c1` to `c5` when *k* is the
only thing ahead of it.

---

## 4. Queues and retirement

### 4.1 What is pushed, when, and what it carries

| Queue | Push | Pop | Entry |
|---|---|---|---|
| IQ | `QPushM` | shadow `sD → sE` | `PCM`, `InstrM` (32-bit, already decompressed), `CompressedM` |
| OQ | `QPushM` | shadow `sE → sM` | `ForwardedSrcAM`, `ForwardedSrcBM` (= `WriteDataM`), `IEUAdrM`, `RawReadDataWordM`, 28 datapath control bits, `PCSrcM`, `RegWriteM`, `ResultSrcM`, `FWriteIntM`, `ViaSQ` (= `SQStoreM`), `AMO` (= `AtomicM[1]`), `LoadChk` |
| SQ | `QPushM & SQStoreM` | LSU drain engine (`sqPop`) | physical address `PAdrM`, size `Funct3M[1:0]`, data `IMAWriteDataM` |
| RQ | `RQPushW` | shadow commit | `RdW`, `RegWriteW`, `ResultW` |

`LoadChk = MemRWM[1] & ~FpLoadStoreM & ~BigEndianM`: an integer little-endian load,
LR, or AMO read, whose result the shadow re-derives from the raw word.

All four are flushed by `sFault`; the SQ keeps its verified entries (they belong to
instructions older than the fault and must still be written).

### 4.2 Why these push points

- **IQ, OQ, SQ at `MExitM`.** An instruction that has entered M can only be
  squashed by `FlushW`, i.e. by a trap on itself or a redirect. `MExitM` excludes
  both. So nothing pushed ever has to be removed, and no queue needs tail rollback.
- **RQ on the first cycle in W, independent of `StallW`.** This is the property
  that prevents deadlock. Suppose instruction *k* is in W and *k+1* in M is waiting
  for the shadow to verify *k* (it is serialized, or the SQ is full of *k*'s
  store). The wait stalls the pipeline, so `StallW = 1`. If the RQ push waited for
  `~StallW`, *k*'s result would never reach the shadow. Because W-stage values are
  stable (W5), the result is pushed immediately and `WPushed` remembers it.
- **Alignment.** The shadow owns one RQ entry for each instruction in `sE`, `sM`,
  `sW`, in order. `sW` uses RQ entry 0, `sM` uses entry `sValidW`. An instruction
  leaves the IQ only when `rqCount + rqPush > sValidE + sValidM + sValidW`, i.e.
  when its own RQ entry is guaranteed to be there by the time it reaches `sM`. In
  practice the RQ entry appears exactly one cycle after the IQ entry.

### 4.3 Depth and backpressure

All four queues have depth `SHARD_DEPTH = 8`. In steady state the IQ and OQ hold
one or two entries and the RQ three or four, because the shadow consumes one
instruction per cycle and never stalls. The SQ does fill: the drain takes two or
three cycles per store.

`ShardBackpressureW = (rqCount >= SHARD_DEPTH-1)` freezes the whole main pipeline
(a `StallWCause` term). The instruction already in W still has a slot (it pushes
regardless of the stall), and every IQ/OQ entry belongs to an instruction that is
in the RQ or in W, so no queue can overflow. With depth 8 this never fires in
normal operation; it was exercised by building with depth 4, where it fires
constantly and everything still passes. **Keep the depth at least two above the
steady-state RQ occupancy (so ≥ 8 in practice): at depth 4 the threshold of 3 is
reached all the time and costs performance.** Only depths 8 and 4 were built;
nothing in the FIFO or the index arithmetic assumes a power of two, but no other
value was tried.

A queued store that finds the SQ full is held in M (`HoldM`, §7.2) until the drain
frees a slot.

### 4.4 `shadow_fifo.sv` — the FIFO all four queues use

A collapsing shift FIFO. `entry[0]` is always the oldest element, so a consumer
that trails the head by *n* elements reads `entry[n]` with no pointer arithmetic,
and "newest match wins" is "highest valid index wins". Entries at index ≥ `count`
hold stale data and readers must qualify them.

- `pop` removes `entry[0]`; every other entry shifts down.
- `push` writes at index `count - pop`.
- `flush` sets `count = keep - pop` and discards a simultaneous push. `keep = 0` for
  IQ/OQ/RQ; the SQ passes its verified count.

```systemverilog
///////////////////////////////////////////
// shadow_fifo.sv
//
// Purpose: SHARD collapsing FIFO shared by the IQ, OQ, RQ and SQ.
//          entry[0] is always the oldest element, so a consumer that trails the
//          head by k elements reads entry[k] directly.  Entries at index >= count
//          hold stale data and must be qualified by the reader.
//
//          pop   removes entry[0] and shifts every other element down.
//          push  appends at the tail (after any simultaneous pop).
//          flush keeps only the `keep` oldest elements (a simultaneous pop removes
//                one of them) and discards any simultaneous push.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_fifo #(parameter int W = 8, parameter int DEPTH = 8) (
  input  logic                       clk, reset,
  input  logic                       flush,
  input  logic [$clog2(DEPTH+1)-1:0] keep,
  input  logic                       push,
  input  logic [W-1:0]               din,
  input  logic                       pop,
  output logic [W-1:0]               entry [DEPTH],
  output logic [$clog2(DEPTH+1)-1:0] count
);

  localparam int CW = $clog2(DEPTH+1);

  logic [CW-1:0] CountAfterPop;

  assign CountAfterPop = count - {{(CW-1){1'b0}}, pop};

  always_ff @(posedge clk) begin
    if (reset) count <= '0;
    else if (flush) count <= keep - {{(CW-1){1'b0}}, pop};
    else count <= CountAfterPop + {{(CW-1){1'b0}}, push};
  end

  always_ff @(posedge clk) begin
    for (int i = 0; i < DEPTH; i++) begin
      if (push & ~flush & (CountAfterPop == CW'(i))) entry[i] <= din;
      else if (pop & (i < DEPTH-1))                  entry[i] <= entry[(i+1) % DEPTH];
    end
  end

endmodule
```

### 4.5 `shadow_iq.sv`

```systemverilog
///////////////////////////////////////////
// shadow_iq.sv
//
// Purpose: SHARD Instruction Queue.  One entry per instruction that leaves the
//          main Memory stage without being flushed, i.e. per instruction that is
//          certain to retire.  The head feeds shadow sD.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_iq import cvw::*; #(parameter cvw_t P, parameter int DEPTH = 8) (
  input  logic                       clk, reset,
  input  logic                       Flush,        // recovery: discard every entry
  // Push: main M-stage exit
  input  logic                       Push,
  input  logic [P.XLEN-1:0]          PCM,
  input  logic [31:0]                InstrM,
  input  logic                       CompressedM,
  // Pop: shadow sD -> sE advance
  input  logic                       Pop,
  // Head (shadow sD)
  output logic                       sValid,
  output logic [P.XLEN-1:0]          sPC,
  output logic [31:0]                sInstr,
  output logic                       sCompressed
);

  localparam int ENTRY_W = P.XLEN + 32 + 1;

  logic [ENTRY_W-1:0]         entry [DEPTH];
  logic [$clog2(DEPTH+1)-1:0] count;

  shadow_fifo #(.W(ENTRY_W), .DEPTH(DEPTH)) fifo(.clk, .reset, .flush(Flush), .keep('0),
    .push(Push), .din({PCM, InstrM, CompressedM}), .pop(Pop), .entry, .count);

  assign sValid = (count != '0);
  assign {sPC, sInstr, sCompressed} = entry[0];

endmodule
```

### 4.6 `shadow_oq.sv`

The 37 control bits are, in order: `ALUSrcA, ALUSrcB, ImmSrc[2:0], W64, UW64,
SubArith, ALUSelect[2:0], BSelect[3:0], ZBBSelect[3:0], BALUControl[2:0], BMUActive,
CZero[1:0], ALUResultSrc, Jump, Branch` (these 28 arrive as `ShardCtlM`, §6.4), then
`PCSrc, RegWrite, ResultSrc[2:0], FWriteInt, ViaSQ, AMO, LoadChk`. If the target's
ALU takes different control inputs (for example no bit-manipulation extensions),
keep the ports and let the unused ones be constant; the shadow instantiates the
same `alu` module as the main datapath and must be given exactly what that module
takes.

```systemverilog
///////////////////////////////////////////
// shadow_oq.sv
//
// Purpose: SHARD Operand Queue.  Pushed together with the IQ when an instruction
//          leaves the main Memory stage.  Carries what the main pipeline used and
//          observed for that instruction: the forwarded register operands, the
//          ALU sum (effective address / branch target), the raw load word, and
//          the decoded datapath controls.  The head feeds shadow sE, which checks
//          the operands against its own and re-executes the instruction.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_oq import cvw::*; #(parameter cvw_t P, parameter int DEPTH = 8) (
  input  logic              clk, reset,
  input  logic              Flush,           // recovery: discard every entry
  input  logic              Push,            // main M-stage exit
  input  logic              Pop,             // shadow sE -> sM advance
  // Main M-stage values
  input  logic [P.XLEN-1:0] ForwardedSrcAM,  // rs1 value the main pipeline used
  input  logic [P.XLEN-1:0] ForwardedSrcBM,  // rs2 value the main pipeline used
  input  logic [P.XLEN-1:0] IEUAdrM,         // ALU sum: effective address or branch/jump target
  input  logic [P.XLEN-1:0] RawLoadWordM,    // aligned read word (after store-queue merge) before subword extract
  input  logic              ALUSrcAM, ALUSrcBM,
  input  logic [2:0]        ImmSrcM,
  input  logic              W64M, UW64M, SubArithM,
  input  logic [2:0]        ALUSelectM,
  input  logic [3:0]        BSelectM, ZBBSelectM,
  input  logic [2:0]        BALUControlM,
  input  logic              BMUActiveM,
  input  logic [1:0]        CZeroM,
  input  logic              ALUResultSrcM, JumpM, BranchM,
  input  logic              PCSrcM,          // main took the branch/jump
  input  logic              RegWriteM,
  input  logic [2:0]        ResultSrcM,
  input  logic              FWriteIntM,
  input  logic              ViaSQM,          // this instruction pushed a store-queue entry
  input  logic              AMOM,            // atomic memory operation (store data is the AMO result)
  input  logic              LoadChkM,        // integer load/LR/AMO read whose data the shadow re-derives
  // Head (shadow sE)
  output logic [P.XLEN-1:0] s_ForwardedSrcA,
  output logic [P.XLEN-1:0] s_ForwardedSrcB,
  output logic [P.XLEN-1:0] s_IEUAdr,
  output logic [P.XLEN-1:0] s_RawLoadWord,
  output logic              s_ALUSrcA, s_ALUSrcB,
  output logic [2:0]        s_ImmSrc,
  output logic              s_W64, s_UW64, s_SubArith,
  output logic [2:0]        s_ALUSelect,
  output logic [3:0]        s_BSelect, s_ZBBSelect,
  output logic [2:0]        s_BALUControl,
  output logic              s_BMUActive,
  output logic [1:0]        s_CZero,
  output logic              s_ALUResultSrc, s_Jump, s_Branch,
  output logic              s_PCSrc,
  output logic              s_RegWrite,
  output logic [2:0]        s_ResultSrc,
  output logic              s_FWriteInt,
  output logic              s_ViaSQ,
  output logic              s_AMO,
  output logic              s_LoadChk
);

  localparam int CTL_W   = 37;
  localparam int ENTRY_W = 4*P.XLEN + CTL_W;

  logic [ENTRY_W-1:0]         entry [DEPTH];
  logic [$clog2(DEPTH+1)-1:0] count;

  shadow_fifo #(.W(ENTRY_W), .DEPTH(DEPTH)) fifo(.clk, .reset, .flush(Flush), .keep('0),
    .push(Push),
    .din({ForwardedSrcAM, ForwardedSrcBM, IEUAdrM, RawLoadWordM,
          ALUSrcAM, ALUSrcBM, ImmSrcM, W64M, UW64M, SubArithM,
          ALUSelectM, BSelectM, ZBBSelectM, BALUControlM, BMUActiveM, CZeroM,
          ALUResultSrcM, JumpM, BranchM, PCSrcM, RegWriteM, ResultSrcM, FWriteIntM,
          ViaSQM, AMOM, LoadChkM}),
    .pop(Pop), .entry, .count);

  assign {s_ForwardedSrcA, s_ForwardedSrcB, s_IEUAdr, s_RawLoadWord,
          s_ALUSrcA, s_ALUSrcB, s_ImmSrc, s_W64, s_UW64, s_SubArith,
          s_ALUSelect, s_BSelect, s_ZBBSelect, s_BALUControl, s_BMUActive, s_CZero,
          s_ALUResultSrc, s_Jump, s_Branch, s_PCSrc, s_RegWrite, s_ResultSrc, s_FWriteInt,
          s_ViaSQ, s_AMO, s_LoadChk} = entry[0];

endmodule
```

### 4.7 `shadow_rq.sv`

Besides being a FIFO it is the forwarding source for main Execute: an associative
lookup of `Rs1E`/`Rs2E` over all valid entries with `RegWrite` set and `Rd != 0`,
scanning oldest to newest so the newest match wins. It exposes its two oldest
entries to the shadow.

```systemverilog
///////////////////////////////////////////
// shadow_rq.sv
//
// Purpose: SHARD Result Queue.  Holds the result of every instruction that has
//          retired from the main pipeline but has not yet been verified and
//          committed to the register file by the shadow.  Pushed once per
//          instruction on its first cycle in main W; popped by the shadow commit.
//
//          Because the register file only holds verified state, the main Execute
//          stage reads through this queue: an associative lookup over all valid
//          entries, newest match wins.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_rq import cvw::*; #(parameter cvw_t P, parameter int DEPTH = 8) (
  input  logic                       clk, reset,
  input  logic                       Flush,        // recovery: discard every entry
  // Push: main W stage
  input  logic                       Push,
  input  logic [4:0]                 RdW,
  input  logic                       RegWriteW,
  input  logic [P.XLEN-1:0]          ResultW,
  // Pop: shadow commit
  input  logic                       Pop,
  // Forwarding to the main Execute stage
  input  logic [4:0]                 Rs1E, Rs2E,
  output logic                       RQ_HitA, RQ_HitB,
  output logic [P.XLEN-1:0]          RQ_ValA, RQ_ValB,
  // The two oldest entries: shadow sW owns entry 0 when it is occupied, and shadow
  // sM owns the entry behind it
  output logic [4:0]                 sRd [2],
  output logic                       sRegWrite [2],
  output logic [P.XLEN-1:0]          sResult [2],
  output logic [$clog2(DEPTH+1)-1:0] Count
);

  localparam int ENTRY_W = 5 + 1 + P.XLEN;

  logic [ENTRY_W-1:0] entry [DEPTH];

  shadow_fifo #(.W(ENTRY_W), .DEPTH(DEPTH)) fifo(.clk, .reset, .flush(Flush), .keep('0),
    .push(Push), .din({RdW, RegWriteW, ResultW}), .pop(Pop), .entry, .count(Count));

  assign {sRd[0], sRegWrite[0], sResult[0]} = entry[0];
  assign {sRd[1], sRegWrite[1], sResult[1]} = entry[1];

  // Newest matching entry wins: scan oldest to newest so later matches override
  always_comb begin
    RQ_HitA = 1'b0; RQ_ValA = '0;
    RQ_HitB = 1'b0; RQ_ValB = '0;
    for (int j = 0; j < DEPTH; j++) begin
      logic [4:0] Rd;
      logic       RegWrite;
      logic [P.XLEN-1:0] Result;
      {Rd, RegWrite, Result} = entry[j];
      if ((j < Count) & RegWrite & (Rd != 5'b0)) begin
        if (Rd == Rs1E) begin RQ_HitA = 1'b1; RQ_ValA = Result; end
        if (Rd == Rs2E) begin RQ_HitB = 1'b1; RQ_ValB = Result; end
      end
    end
  end

endmodule
```

### 4.8 `shadow_sq.sv`

`NVerified` counts the oldest entries the shadow has committed. They form a prefix
because the shadow commits stores in order. `Verify` (shadow commit of a queued
store) increments it; `Pop` (the drain wrote the head) decrements it and shifts.
`Flush` keeps exactly the verified prefix. A fault and a commit never happen in the
same cycle, so `Flush` and `Verify` never coincide.

```systemverilog
///////////////////////////////////////////
// shadow_sq.sv
//
// Purpose: SHARD Store Queue: the store buffer between the main pipeline and
//          memory.  A store (or the write half of an AMO / successful SC) enters
//          here when it leaves main M and is never written to the D-cache or bus
//          by the main pipeline.  The oldest NVerified entries have been verified
//          by the shadow and may be written to memory by the LSU drain engine;
//          the rest are still speculative and are discarded on recovery.
//          Main loads see every entry through the LSU's byte-merge.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_sq import cvw::*; #(parameter cvw_t P, parameter int DEPTH = 8) (
  input  logic                       clk, reset,
  input  logic                       Flush,        // recovery: discard the unverified entries
  // Push: main M-stage exit of a store
  input  logic                       Push,
  input  logic [P.PA_BITS-1:0]       PAdrM,
  input  logic [1:0]                 SizeM,
  input  logic [P.XLEN-1:0]          WriteDataM,
  // Shadow commit of the oldest unverified store
  input  logic                       Verify,
  // LSU drain engine wrote the head to memory
  input  logic                       Pop,
  // Contents
  output logic [P.PA_BITS-1:0]       sqPA [DEPTH],
  output logic [1:0]                 sqSize [DEPTH],
  output logic [P.XLEN-1:0]          sqData [DEPTH],
  output logic [$clog2(DEPTH+1)-1:0] Count,
  output logic [$clog2(DEPTH+1)-1:0] NVerified
);

  localparam int CW      = $clog2(DEPTH+1);
  localparam int ENTRY_W = P.PA_BITS + 2 + P.XLEN;

  logic [ENTRY_W-1:0] entry [DEPTH];

  shadow_fifo #(.W(ENTRY_W), .DEPTH(DEPTH)) fifo(.clk, .reset, .flush(Flush), .keep(NVerified),
    .push(Push), .din({PAdrM, SizeM, WriteDataM}), .pop(Pop), .entry, .count(Count));

  // A fault at shadow sW raises Flush instead of Verify, so the two never coincide
  always_ff @(posedge clk)
    if (reset) NVerified <= '0;
    else       NVerified <= NVerified + {{(CW-1){1'b0}}, Verify} - {{(CW-1){1'b0}}, Pop};

  for (genvar i = 0; i < DEPTH; i++) begin : unpack
    assign {sqPA[i], sqSize[i], sqData[i]} = entry[i];
  end

endmodule
```

---

## 5. The shadow pipeline

### 5.1 Behaviour

The shadow has four stages. `sD` is not a register: it is the IQ head. `sE`, `sM`,
`sW` each have a valid bit and payload registers. There is **no stall logic**: an
instruction that has entered `sE` moves one stage per cycle and commits (or faults)
three cycles later. The only gate is at the entrance.

**sD → sE.**
```
AdvanceDE = iqValid & ~Fault & (rqCount + rqPush > sValidE + sValidM + sValidW)
iqPop     = AdvanceDE
```
The count condition guarantees that the instruction's RQ entry exists by the time
it is in `sM` (each instruction already in the shadow owns one RQ entry; the new
one needs one more). `sE` latches PC, instruction and compressed flag from the IQ.

**sE — operands, operand check, re-execution, next-PC check.** The OQ head is this
instruction's record (popped as it leaves `sE`).
- Source registers are decoded by the shadow from the instruction word:
  `sRs1E = sInstrE[19:15]`, `sRs2E = sInstrE[24:20]`. They address the regfile's
  shadow read ports.
- `shadow_hzu` selects each operand: the `sM` instruction's value if it writes that
  register, else the `sW` instruction's, else the regfile. This is the main
  pipeline's forwarding rule applied to the shadow's own stages, and it is computed
  independently of `ForwardAE/BE`.
- **OP check:** `sOpFaultE = (sForwardedSrcAE != oqForwardedSrcA) |
  (sForwardedSrcBE != oqForwardedSrcB)`. Unconditional — both fields are compared
  for every instruction, relying on W7. This is what verifies the main pipeline's
  forwarding selects, its RQ forwarding and its regfile read.
- Re-execution uses the shadow's own instances of `extend` (immediate), `alu` and
  `comparator`, driven by the shadow's operands, the shadow's PC, instruction
  fields taken from the instruction word (`funct3`, `funct7`, `rs2` field), and the
  main pipeline's decoded controls from the OQ. The link address is
  `sPCE + (compressed ? 2 : 4)`.
  `sTakenE = Jump | (Branch & ((funct3[2] ? lt : eq) ^ funct3[0]))`, the same
  formula the controller uses.
- **Next-PC check.** A register pair `NPCValid`/`NPCExpected` holds where the next
  retired instruction must be: the previous instruction's
  `sTaken ? {sSum[XLEN-1:1], 1'b0} : PC+len`. `sNPCFaultE = NPCValid & (sPCE !=
  NPCExpected)`. The chain is broken (`NPCValid ← 0`) by `StreamBreak` (= `TrapM`)
  and after an `mret`/`sret` (decoded by the shadow from the instruction word: the
  target is a CSR). On a fault it is set to the restart PC (`NPCValid ← 1`,
  `NPCExpected ← FaultPC`), so the replay must begin exactly there.
- `sRestartPCE = NPCValid ? NPCExpected : sPCE` travels with the instruction and
  becomes `FaultPC`. **The restart PC is where the instruction should have been,
  not where the main pipeline fetched it.** For a next-PC fault these differ, and
  restarting at the fetched PC would resume on the wrong path.

**sM — verification** (`shadow_verifier`). The RQ entry is `entry[sValidW]` and the
SQ entry is `entry[sqNVerified + (sValidW & sViaSQW)]` — the oldest unverified
store, unless `sW` holds an older store that is being verified this cycle. The
instruction's *value* for forwarding and commit is chosen here:
`sValM = ALUClass ? sIEUResultM : rqResult`, where `ALUClass = (ResultSrc == 000) &
~FWriteInt`. For every other class (load, CSR read, multiply/divide, SC, FP→int)
the shadow has no way to produce the value and takes the main pipeline's, which is
checked by other means or is a stated boundary (§18).

**sW — commit or fault.**
```
Fault       = sValidW & |sFaultW
Commit      = sValidW & ~|sFaultW
CommitStore = Commit & sViaSQW
shadow_we3  = Commit & sRegWriteW ;  shadow_a3 = sRdW ;  shadow_wd3 = sValW
```
`Fault` clears all three shadow stages at the next edge. The regfile ignores a
write to `x0` itself.

### 5.2 `shadow_hzu.sv`

```systemverilog
///////////////////////////////////////////
// shadow_hzu.sv
//
// Purpose: SHARD shadow forwarding unit.  The shadow sources its operands from
//          verified state only: the committed register file, bypassed by the
//          results of the older instructions still in shadow sM and sW.  This
//          select is computed from the shadow's own decode of the instruction
//          word and is independent of the main pipeline's ForwardAE/BE logic.
//
//          Select encoding (same as the main pipeline):
//            00 = register file, 01 = sW bypass, 10 = sM bypass
//
//          The shadow never needs a load-use stall: every result, including
//          load data, is already available when its producer is in sM.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_hzu (
  input  logic [4:0] sRs1E, sRs2E,       // source registers of the instruction in shadow sE
  input  logic [4:0] sRdM, sRdW,         // destination registers in shadow sM and sW
  input  logic       sRegWriteM,         // sM holds a valid instruction that writes sRdM
  input  logic       sRegWriteW,         // sW holds a valid instruction that writes sRdW
  output logic [1:0] sForwardAE,
  output logic [1:0] sForwardBE
);

  always_comb begin
    sForwardAE = 2'b00;
    sForwardBE = 2'b00;
    if (sRs1E != 5'b0)
      if      (sRegWriteM & (sRdM == sRs1E)) sForwardAE = 2'b10;
      else if (sRegWriteW & (sRdW == sRs1E)) sForwardAE = 2'b01;

    if (sRs2E != 5'b0)
      if      (sRegWriteM & (sRdM == sRs2E)) sForwardBE = 2'b10;
      else if (sRegWriteW & (sRdW == sRs2E)) sForwardBE = 2'b01;
  end

endmodule
```

### 5.3 `shadow_verifier.sv`

Fault vector (also `mtval[7:0]` when a shadow fault escalates to a trap):

| bit | name | condition |
|---|---|---|
| 0 | OP | from `sE`: an operand the main pipeline used differs from the shadow's |
| 1 | NPC | from `sE`: instruction is not where its predecessor leads |
| 2 | RES | `ALUClass & RegWrite & (sIEUResult != rqResult)` |
| 3 | EA | `sSum != mIEUAdr` — every instruction: the ALU sum is a pure function of the operands and controls, so it must match whether or not it is an address |
| 4 | BR | `sTaken != mPCSrc` |
| 5 | LD | `LoadChk & (subwordread(mRawLoadWord, mIEUAdr[3:0], funct3) != rqResult)` |
| 6 | ST | `ViaSQ & (~sqValid \| sqPA[11:0] != sSum[11:0] \| sqSize != funct3[1:0] \| sqData != StoreData)`, with `StoreData = AMO ? amoalu(rqResult, sSrcB, funct7, funct3) : sSrcB` |
| 7 | RD | `rqRd != sInstr[11:7] \| rqRegWrite != mRegWrite` |

Notes that matter when porting:
- The SQ address compare uses only the page offset. Above it the SQ holds a
  *physical* address and the shadow has a *virtual* one; translation is not
  re-done. The full virtual address is covered by EA.
- For an AMO the old memory value is the instruction's own register result
  (`rqResult`), which LD has checked against the raw word. So the AMO result is
  recomputed from the shadow's own `rs2` and a checked old value.
- For a store, `sqData` is the full `XLEN`-bit `rs2` (the LSU replicates sub-word
  data later), so the compare is on all bits.
- RD ties the RQ record (pushed at W) to the IQ/OQ record (pushed at M): it catches
  a slipped or corrupted RQ entry.

```systemverilog
///////////////////////////////////////////
// shadow_verifier.sv
//
// Purpose: SHARD per-instruction verification, evaluated in shadow sM.
//          Compares what the shadow computed from verified state against what the
//          main pipeline recorded for the same instruction in the OQ, RQ and SQ.
//          Any set bit of Fault stops the instruction from committing.
//
//          Fault bits:
//            [0] OP   register operand the main pipeline used differs from the
//                     shadow's (forwarding select, RQ forwarding, regfile read)
//            [1] NPC  instruction is not at the PC its predecessor leads to
//            [2] RES  ALU / link result
//            [3] EA   ALU sum: effective address or branch/jump target
//            [4] BR   branch/jump direction
//            [5] LD   load data does not re-derive from the raw read word
//            [6] ST   store-queue entry (address, size or data)
//            [7] RD   destination register or write enable of the result record
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_verifier import cvw::*; #(parameter cvw_t P) (
  // Faults found in shadow sE
  input  logic                 sOpFault, sNPCFault,
  // Shadow recomputation
  input  logic [31:0]          sInstr,
  input  logic [P.XLEN-1:0]    sIEUResult,      // ALU or link result
  input  logic [P.XLEN-1:0]    sSum,            // ALU sum
  input  logic                 sTaken,          // branch/jump redirects the PC
  input  logic [P.XLEN-1:0]    sSrcB,           // shadow's rs2 value (store data)
  // Main pipeline record (OQ)
  input  logic [P.XLEN-1:0]    mIEUAdr,
  input  logic [P.XLEN-1:0]    mRawLoadWord,
  input  logic                 mPCSrc,
  input  logic                 mRegWrite,
  input  logic                 mALUClass,       // result comes from the IEU datapath
  input  logic                 mLoadChk,
  input  logic                 mViaSQ,
  input  logic                 mAMO,
  // Main pipeline record (RQ)
  input  logic [4:0]           rqRd,
  input  logic                 rqRegWrite,
  input  logic [P.XLEN-1:0]    rqResult,
  // Main pipeline record (SQ)
  input  logic                 sqValid,
  input  logic [P.PA_BITS-1:0] sqPA,
  input  logic [1:0]           sqSize,
  input  logic [P.XLEN-1:0]    sqData,
  output logic [7:0]           Fault
);

  logic [P.LLEN-1:0] LoadDataLLEN;
  logic [P.XLEN-1:0] AMOResult, StoreData;

  // Loaded value re-derived from the raw read word with an independent subword extract.
  // Only little-endian integer accesses set mLoadChk.
  subwordread #(P) loadextract(
    .ReadDataWordMuxM({{(P.LLEN-P.XLEN){1'b0}}, mRawLoadWord}), .PAdrM(mIEUAdr[3:0]),
    .Funct3M(sInstr[14:12]), .FpLoadStoreM(1'b0), .BigEndianM(1'b0), .ReadDataM(LoadDataLLEN));

  // Value an AMO must write: old memory value (its register result) combined with the
  // shadow's own rs2
  if (P.ZAAMO_SUPPORTED) begin : amo
    amoalu #(P) amoalu(.ReadDataM(rqResult), .IHWriteDataM(sSrcB),
      .LSUFunct7M(sInstr[31:25]), .LSUFunct3M(sInstr[14:12]), .AMOResultM(AMOResult));
  end else begin : amo
    assign AMOResult = sSrcB;
  end
  assign StoreData = mAMO ? AMOResult : sSrcB;

  assign Fault[0] = sOpFault;
  assign Fault[1] = sNPCFault;
  assign Fault[2] = mALUClass & mRegWrite & (sIEUResult != rqResult);
  assign Fault[3] = (sSum != mIEUAdr);
  assign Fault[4] = (sTaken != mPCSrc);
  assign Fault[5] = mLoadChk & (LoadDataLLEN[P.XLEN-1:0] != rqResult);
  assign Fault[6] = mViaSQ & (~sqValid | (sqPA[11:0] != sSum[11:0]) | (sqSize != sInstr[13:12]) |
                              (sqData != StoreData));
  assign Fault[7] = (rqRd != sInstr[11:7]) | (rqRegWrite != mRegWrite);

endmodule
```

### 5.4 `shadow_pipeline.sv`

```systemverilog
///////////////////////////////////////////
// shadow_pipeline.sv
//
// Purpose: SHARD shadow pipeline sD -> sE -> sM -> sW.
//          The shadow re-executes every instruction the main pipeline retired, in
//          order, from verified state only, and is the sole writer of the register
//          file.  It is decoupled from the main pipeline's stalls: an instruction
//          enters sE as soon as its IQ entry and its RQ entry exist, and then moves
//          one stage per cycle.
//
//            sD  IQ head.  Decode source registers.
//            sE  Operands from the register file with sM/sW bypass (shadow_hzu),
//                checked against the operands the main pipeline used (OQ).  ALU,
//                branch comparator, immediate and link address recomputed.
//                Next-PC continuity checked.
//            sM  shadow_verifier compares against the OQ, RQ and SQ records.
//            sW  Commit: write the register file, release the RQ entry and mark
//                the store-queue entry verified -- or, on any fault, commit
//                nothing and raise Fault so the core can flush and replay.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_pipeline import cvw::*; #(parameter cvw_t P, parameter int DEPTH = 8) (
  input  logic                       clk, reset,
  input  logic                       StreamBreak,     // main took a trap: the next retired PC is not sequential
  // IQ head (sD)
  input  logic                       iqValid,
  input  logic [P.XLEN-1:0]          iqPC,
  input  logic [31:0]                iqInstr,
  input  logic                       iqCompressed,
  output logic                       iqPop,
  // OQ head (sE)
  input  logic [P.XLEN-1:0]          oqForwardedSrcA, oqForwardedSrcB,
  input  logic [P.XLEN-1:0]          oqIEUAdr, oqRawLoadWord,
  input  logic                       oqALUSrcA, oqALUSrcB,
  input  logic [2:0]                 oqImmSrc,
  input  logic                       oqW64, oqUW64, oqSubArith,
  input  logic [2:0]                 oqALUSelect,
  input  logic [3:0]                 oqBSelect, oqZBBSelect,
  input  logic [2:0]                 oqBALUControl,
  input  logic                       oqBMUActive,
  input  logic [1:0]                 oqCZero,
  input  logic                       oqALUResultSrc, oqJump, oqBranch,
  input  logic                       oqPCSrc,
  input  logic                       oqRegWrite,
  input  logic [2:0]                 oqResultSrc,
  input  logic                       oqFWriteInt,
  input  logic                       oqViaSQ, oqAMO, oqLoadChk,
  output logic                       oqPop,
  // RQ: two oldest entries, occupancy, and this cycle's push
  input  logic [4:0]                 rqRd [2],
  input  logic                       rqRegWrite [2],
  input  logic [P.XLEN-1:0]          rqResult [2],
  input  logic [$clog2(DEPTH+1)-1:0] rqCount,
  input  logic                       rqPush,
  // SQ contents
  input  logic [P.PA_BITS-1:0]       sqPA [DEPTH],
  input  logic [1:0]                 sqSize [DEPTH],
  input  logic [P.XLEN-1:0]          sqData [DEPTH],
  input  logic [$clog2(DEPTH+1)-1:0] sqCount, sqNVerified,
  // Register file: shadow read ports and the only write port
  output logic [4:0]                 sRs1E, sRs2E,
  input  logic [P.XLEN-1:0]          sRD1E, sRD2E,
  output logic                       shadow_we3,
  output logic [4:0]                 shadow_a3,
  output logic [P.XLEN-1:0]          shadow_wd3,
  // Commit / fault
  output logic                       Commit,          // sW instruction verified and committed (pops the RQ)
  output logic                       CommitStore,     // ... and it owns the oldest unverified SQ entry
  output logic                       Fault,           // sW instruction failed verification
  output logic [P.XLEN-1:0]          FaultPC,         // where to resume: the PC that instruction should have had
  output logic [7:0]                 FaultClass
);

  localparam int CW = $clog2(DEPTH+1);

  // Stage occupancy
  logic              sValidE, sValidM, sValidW;
  logic              AdvanceDE;

  // sE
  logic [P.XLEN-1:0] sPCE, sPCLinkE, sImmExtE;
  logic [31:0]       sInstrE;
  logic              sCompressedE;
  logic [1:0]        sForwardAE, sForwardBE;
  logic [P.XLEN-1:0] sForwardedSrcAE, sForwardedSrcBE, sSrcAE, sSrcBE;
  logic [P.XLEN-1:0] sALUResultE, sSumE, sAltResultE, sIEUResultE;
  logic [1:0]        sFlagsE;
  logic              sBranchSignedE, sTakenE;
  logic              sOpFaultE, sNPCFaultE;
  logic              sRetE;
  logic              NPCValid;
  logic [P.XLEN-1:0] NPCExpected, sRestartPCE;

  // sM
  logic [P.XLEN-1:0] sRestartPCM, sIEUResultM, sSumM, sSrcBM, sIEUAdrM, sRawLoadWordM, sValM;
  logic [31:0]       sInstrM;
  logic              sTakenM, sOpFaultM, sNPCFaultM;
  logic              sPCSrcM, sRegWriteM, sALUClassM, sLoadChkM, sViaSQM, sAMOM;
  logic [7:0]        sFaultM;
  logic              rqSelM;
  logic [CW-1:0]     sqIdxM;

  // sW
  logic [P.XLEN-1:0] sRestartPCW, sValW;
  logic [4:0]        sRdW;
  logic              sRegWriteW, sViaSQW;
  logic [7:0]        sFaultW;

  ///////////////////////////////////////////
  // sD: an instruction leaves the IQ once its RQ entry is certain to be present
  // when it reaches sM (every instruction in sE, sM, sW owns one RQ entry, in order).
  ///////////////////////////////////////////

  assign AdvanceDE = iqValid & ~Fault &
    ((rqCount + {{(CW-1){1'b0}}, rqPush}) >
     ({{(CW-1){1'b0}}, sValidE} + {{(CW-1){1'b0}}, sValidM} + {{(CW-1){1'b0}}, sValidW}));
  assign iqPop = AdvanceDE;

  always_ff @(posedge clk)
    if (reset | Fault) sValidE <= 1'b0;
    else               sValidE <= AdvanceDE;

  always_ff @(posedge clk)
    if (AdvanceDE) begin
      sPCE         <= iqPC;
      sInstrE      <= iqInstr;
      sCompressedE <= iqCompressed;
    end

  ///////////////////////////////////////////
  // sE: operand sourcing, operand check, re-execution, next-PC continuity
  ///////////////////////////////////////////

  assign sRs1E = sInstrE[19:15];
  assign sRs2E = sInstrE[24:20];

  shadow_hzu hzu(.sRs1E, .sRs2E, .sRdM(sInstrM[11:7]), .sRdW,
    .sRegWriteM(sValidM & sRegWriteM), .sRegWriteW(sValidW & sRegWriteW),
    .sForwardAE, .sForwardBE);

  mux3 #(P.XLEN) sfaemux(sRD1E, sValW, sValM, sForwardAE, sForwardedSrcAE);
  mux3 #(P.XLEN) sfbemux(sRD2E, sValW, sValM, sForwardBE, sForwardedSrcBE);

  // The main pipeline must have used exactly the operands the shadow derives from
  // verified state.  This covers the forwarding selects, RQ forwarding and regfile read.
  assign sOpFaultE = (sForwardedSrcAE != oqForwardedSrcA) | (sForwardedSrcBE != oqForwardedSrcB);

  extend #(P) sext(.InstrD(sInstrE[31:7]), .ImmSrcD(oqImmSrc), .ImmExtD(sImmExtE));
  assign sPCLinkE = sPCE + (sCompressedE ? 'd2 : 'd4);

  mux2 #(P.XLEN) ssrcamux(sForwardedSrcAE, sPCE, oqALUSrcA, sSrcAE);
  mux2 #(P.XLEN) ssrcbmux(sForwardedSrcBE, sImmExtE, oqALUSrcB, sSrcBE);

  alu #(P) salu(sSrcAE, sSrcBE, oqW64, oqUW64, oqSubArith, oqALUSelect, oqBSelect, oqZBBSelect,
    sInstrE[14:12], sInstrE[31:25], sInstrE[24:20], oqBALUControl, oqBMUActive, oqCZero,
    sALUResultE, sSumE);

  assign sBranchSignedE = ~(sInstrE[14:13] == 2'b11) & oqBranch;
  comparator #(P.XLEN) scomp(sForwardedSrcAE, sForwardedSrcBE, sBranchSignedE, sFlagsE);
  assign sTakenE = oqJump | (oqBranch & ((sInstrE[14] ? sFlagsE[0] : sFlagsE[1]) ^ sInstrE[12]));

  mux2 #(P.XLEN) saltresultmux(sImmExtE, sPCLinkE, oqJump, sAltResultE);
  mux2 #(P.XLEN) sieuresultmux(sALUResultE, sAltResultE, oqALUResultSrc, sIEUResultE);

  // Next-PC continuity: each retired instruction must sit where its predecessor leads
  // (fall-through, or the shadow's own branch/jump target).  A trap and an xRET break
  // the chain; the first instruction after one is not checked.  When the chain is
  // intact the expected PC, not the PC the main pipeline actually fetched, is where a
  // replay must resume -- for a next-PC fault the two differ.
  assign sNPCFaultE  = NPCValid & (sPCE != NPCExpected);
  assign sRestartPCE = NPCValid ? NPCExpected : sPCE;
  assign sRetE = (sInstrE[6:0] == 7'b1110011) & (sInstrE[19:7] == 13'b0) &
                 ((sInstrE[31:20] == 12'b000100000010) | (sInstrE[31:20] == 12'b001100000010));

  always_ff @(posedge clk)
    if (reset | StreamBreak) NPCValid <= 1'b0;
    else if (Fault)          NPCValid <= 1'b1;     // the replay must start at FaultPC
    else if (sValidE)        NPCValid <= ~sRetE;

  always_ff @(posedge clk)
    if (Fault)        NPCExpected <= FaultPC;
    else if (sValidE) NPCExpected <= sTakenE ? {sSumE[P.XLEN-1:1], 1'b0} : sPCLinkE;

  assign oqPop = sValidE & ~Fault;

  ///////////////////////////////////////////
  // sE -> sM
  ///////////////////////////////////////////

  always_ff @(posedge clk)
    if (reset | Fault) sValidM <= 1'b0;
    else               sValidM <= sValidE;

  always_ff @(posedge clk)
    if (sValidE) begin
      sRestartPCM   <= sRestartPCE;
      sInstrM       <= sInstrE;
      sIEUResultM   <= sIEUResultE;
      sSumM         <= sSumE;
      sTakenM       <= sTakenE;
      sSrcBM        <= sForwardedSrcBE;
      sOpFaultM     <= sOpFaultE;
      sNPCFaultM    <= sNPCFaultE;
      sIEUAdrM      <= oqIEUAdr;
      sRawLoadWordM <= oqRawLoadWord;
      sPCSrcM       <= oqPCSrc;
      sRegWriteM    <= oqRegWrite;
      sALUClassM    <= (oqResultSrc == 3'b000) & ~oqFWriteInt;
      sLoadChkM     <= oqLoadChk;
      sViaSQM       <= oqViaSQ;
      sAMOM         <= oqAMO;
    end

  ///////////////////////////////////////////
  // sM: verification against the RQ and SQ records
  ///////////////////////////////////////////

  // sW owns RQ entry 0 when occupied, so sM's entry is right behind it.  Likewise the
  // store in sM owns the oldest unverified SQ entry unless sW holds an older store.
  assign rqSelM = sValidW;
  assign sqIdxM = sqNVerified + {{(CW-1){1'b0}}, sValidW & sViaSQW};

  shadow_verifier #(P) verifier(
    .sOpFault(sOpFaultM), .sNPCFault(sNPCFaultM),
    .sInstr(sInstrM), .sIEUResult(sIEUResultM), .sSum(sSumM), .sTaken(sTakenM), .sSrcB(sSrcBM),
    .mIEUAdr(sIEUAdrM), .mRawLoadWord(sRawLoadWordM), .mPCSrc(sPCSrcM), .mRegWrite(sRegWriteM),
    .mALUClass(sALUClassM), .mLoadChk(sLoadChkM), .mViaSQ(sViaSQM), .mAMO(sAMOM),
    .rqRd(rqRd[rqSelM]), .rqRegWrite(rqRegWrite[rqSelM]), .rqResult(rqResult[rqSelM]),
    .sqValid(sqIdxM < sqCount), .sqPA(sqPA[sqIdxM[$clog2(DEPTH)-1:0]]),
    .sqSize(sqSize[sqIdxM[$clog2(DEPTH)-1:0]]), .sqData(sqData[sqIdxM[$clog2(DEPTH)-1:0]]),
    .Fault(sFaultM));

  // Value this instruction leaves in its destination register: the shadow's own result
  // where it can recompute it, otherwise the main pipeline's result record.
  assign sValM = sALUClassM ? sIEUResultM : rqResult[rqSelM];

  ///////////////////////////////////////////
  // sM -> sW
  ///////////////////////////////////////////

  always_ff @(posedge clk)
    if (reset | Fault) sValidW <= 1'b0;
    else               sValidW <= sValidM;

  always_ff @(posedge clk)
    if (sValidM) begin
      sRestartPCW <= sRestartPCM;
      sRdW       <= sInstrM[11:7];
      sRegWriteW <= sRegWriteM;
      sViaSQW    <= sViaSQM;
      sValW      <= sValM;
      sFaultW    <= sFaultM;
    end

  ///////////////////////////////////////////
  // sW: commit or fault
  ///////////////////////////////////////////

  assign Fault       = sValidW & (|sFaultW);
  assign FaultPC     = sRestartPCW;
  assign FaultClass  = sFaultW;
  assign Commit      = sValidW & ~(|sFaultW);
  assign CommitStore = Commit & sViaSQW;

  assign shadow_we3 = Commit & sRegWriteW;
  assign shadow_a3  = sRdW;
  assign shadow_wd3 = sValW;

endmodule
```

---

## 6. Main datapath edits (IEU)

### 6.1 `regfile.sv` — two more read ports

Add read ports 4 and 5 (addresses `a4`, `a5`, data `rd4`, `rd5`) for the shadow.
Nothing else changes: one write port (`we3/a3/wd3`), written on the falling edge.
In the AMOEBA regfile each read port decodes a SECDED codeword; the new ports get a
decoder and error flags but no fault injector. In a stock (non-ECC) regfile this is
just:

```systemverilog
  assign rd4 = (a4 != 0) ? rf[a4] : '0;
  assign rd5 = (a5 != 0) ? rf[a5] : '0;
```

The AMOEBA version as built:

```systemverilog
module regfile #(parameter XLEN, E_SUPPORTED) (
  input  logic             clk, reset,
  input  logic             we3,
  input  logic [4:0]       a1, a2, a3,
  input  logic [XLEN-1:0]  wd3,
  input  logic             DummyW,
  input  logic             DummySelW,
  output logic [XLEN-1:0]  rd1, rd2,
  input  logic             inject_en,
  output logic             sec_err_rd1, ded_err_rd1,
  output logic             sec_err_rd2, ded_err_rd2,
  // SHARD: read ports 4 and 5 serve the shadow pipeline's own operand sourcing
  input  logic [4:0]       a4, a5,
  output logic [XLEN-1:0]  rd4, rd5,
  output logic             sec_err_rd4, ded_err_rd4,
  output logic             sec_err_rd5, ded_err_rd5
);

  localparam ARCHREGS = E_SUPPORTED ? 16 : 32;
  localparam NUMREGS  = ARCHREGS + 2;
  localparam logic [5:0] SHADOW0 = 6'(ARCHREGS);

  // SECDED check-bit count and total codeword width
  localparam int R  = (XLEN <=   1) ? 2 :
                      (XLEN <=   4) ? 3 :
                      (XLEN <=  11) ? 4 :
                      (XLEN <=  26) ? 5 :
                      (XLEN <=  57) ? 6 :
                      (XLEN <= 120) ? 7 : 8;
  localparam int CW = XLEN + R + 1;  // e.g. 64+7+1 = 72 for RV64

  // Storage array holds encoded codewords.
  // All-zeros is the valid SECDED codeword for data=0 (Hamming bits and
  // overall parity are all 0 when data is 0), so reset to '0 is correct.
  logic [CW-1:0] rf [NUMREGS-1:1];
  logic [5:0]    WriteIdx;
  integer i;

  // Dummy writes are redirected to shadow registers and cannot alter
  // architectural register state.
  assign WriteIdx = DummyW ? (SHADOW0 | {5'b0, DummySelW}) : {1'b0, a3};

  // ── Write path ────────────────────────────────────────────────────────────────
  // Encode wd3 combinationally, then latch the codeword on the falling clock edge.
  logic [CW-1:0] cw_wr3;
  ecc_secded_enc #(.DATA_WIDTH(XLEN)) enc_wr (.data_i(wd3), .codeword_o(cw_wr3));

  always_ff @(negedge clk)
    if (reset) for (i = 1; i < NUMREGS; i++) rf[i] <= '0;
    else       if (we3 & (WriteIdx != '0))    rf[WriteIdx] <= cw_wr3;

  // ── Read port 1 ───────────────────────────────────────────────────────────────
  logic [CW-1:0] cw_rd1_raw, cw_rd1_inj;

  assign cw_rd1_raw = (a1 != '0) ? rf[a1] : '0;

  ecc_bit_flip  #(.CW_WIDTH(CW)) inj1 (
    .clk, .reset, .inject_en,
    .codeword_i(cw_rd1_raw),
    .codeword_o(cw_rd1_inj)
  );

  ecc_secded_dec #(.DATA_WIDTH(XLEN)) dec1 (
    .codeword_i(cw_rd1_inj),
    .data_o    (rd1),
    .sec_err_o (sec_err_rd1),
    .ded_err_o (ded_err_rd1)
  );

  // ── Read port 2 ───────────────────────────────────────────────────────────────
  logic [CW-1:0] cw_rd2_raw, cw_rd2_inj;

  assign cw_rd2_raw = (a2 != '0) ? rf[a2] : '0;

  ecc_bit_flip  #(.CW_WIDTH(CW)) inj2 (
    .clk, .reset, .inject_en,
    .codeword_i(cw_rd2_raw),
    .codeword_o(cw_rd2_inj)
  );

  ecc_secded_dec #(.DATA_WIDTH(XLEN)) dec2 (
    .codeword_i(cw_rd2_inj),
    .data_o    (rd2),
    .sec_err_o (sec_err_rd2),
    .ded_err_o (ded_err_rd2)
  );

  // ── Read ports 4 and 5 (shadow) ───────────────────────────────────────────────
  logic [CW-1:0] cw_rd4_raw, cw_rd5_raw;

  assign cw_rd4_raw = (a4 != '0) ? rf[a4] : '0;
  assign cw_rd5_raw = (a5 != '0) ? rf[a5] : '0;

  ecc_secded_dec #(.DATA_WIDTH(XLEN)) dec4 (
    .codeword_i(cw_rd4_raw),
    .data_o    (rd4),
    .sec_err_o (sec_err_rd4),
    .ded_err_o (ded_err_rd4)
  );

  ecc_secded_dec #(.DATA_WIDTH(XLEN)) dec5 (
    .codeword_i(cw_rd5_raw),
    .data_o    (rd5),
    .sec_err_o (sec_err_rd5),
    .ded_err_o (ded_err_rd5)
  );

endmodule
```

### 6.2 `datapath.sv`

Four changes relative to stock Wally:

1. **The regfile is written only by the shadow.** `we3/a3/wd3` come from
   `shadow_we3/shadow_a3/shadow_wd3`. `RegWriteW`/`RdW`/`ResultW` no longer reach
   the regfile; `ResultW` is exported for the RQ.
2. **The regfile is read in Execute, not Decode.** `a1 = Rs1E`, `a2 = Rs2E`, and the
   read data is `R1E`/`R2E` directly. The `R1D→R1E` and `R2D→R2E` pipeline
   registers are **deleted**. Reason: the shadow commits to the regfile at times
   unrelated to main-pipeline stalls. A value latched in Decode would go stale if
   its producer was committed (and removed from the RQ) while the consumer sat
   stalled in Execute. A combinational read in Execute is always current.
3. **RQ forwarding sits below the M/W bypasses:**
   ```systemverilog
   mux3 #(P.XLEN) faemux(R1E, ResultW, IFResultM, ForwardAE, FwdSrcA_mw);
   assign ForwardedSrcAE = (RQ_HitA & (ForwardAE == 2'b00)) ? RQ_ValA : FwdSrcA_mw;
   ```
   Priority: M-stage result, W-stage result, newest RQ match, regfile. A W-stage
   instruction and its own RQ entry can both be present (the RQ push happens on the
   first W cycle); they hold the same value, so the order between them does not
   matter.
4. **`ForwardedSrcAM`**: a plain `flopenrc` of `ForwardedSrcAE` at the E→M edge.
   Together with `WriteDataM` (the existing register of `ForwardedSrcBE`) it is what
   the main pipeline "used", recorded in the OQ and checked in M.

`SrcAE`/`SrcBE` (the ALU inputs after the PC/immediate muxes) are exported for the
second AGU adder.

```systemverilog
module datapath import cvw::*;  #(parameter cvw_t P) (
  input  logic              clk, reset,
  // ECC inject enable (from top-level, for DFT)
  input  logic              ecc_inject_en,
  // Decode stage signals
  input  logic [2:0]        ImmSrcD,                 // Selects type of immediate extension
  input  logic [31:0]       InstrD,                  // Instruction in Decode stage
  input  logic [4:0]        Rs1E, Rs2E,              // Source registers of the instruction in Execute
  // Execute stage signals
  input  logic [P.XLEN-1:0] PCE,                     // PC in Execute stage
  input  logic [P.XLEN-1:0] PCLinkE,                 // PC + 4 (of instruction in Execute stage)
  input  logic [2:0]        Funct3E,                 // Funct3 field of instruction in Execute stage
  input  logic [6:0]        Funct7E,                 // Funct7 field of instruction in Execute stage
  input  logic              StallE, FlushE,          // Stall, flush Execute stage
  input  logic [1:0]        ForwardAE, ForwardBE,    // Forward ALU operands from later stages
  input  logic              W64E,UW64E,              // W64/.uw-type instruction
  input  logic              SubArithE,               // Subtraction or arithmetic shift
  input  logic              ALUSrcAE, ALUSrcBE,      // ALU operands
  input  logic              ALUResultSrcE,           // Selects result to pass on to Memory stage
  input  logic [2:0]        ALUSelectE,              // ALU mux select signal
  input  logic              JumpE,                   // Is a jump (j) instruction
  input  logic              BranchSignedE,           // Branch comparison operands are signed (if it's a branch)
  input  logic [3:0]        BSelectE,                // One hot encoding of ZBA_ZBB_ZBC_ZBS instruction
  input  logic [3:0]        ZBBSelectE,              // ZBB mux select signal
  input  logic [2:0]        BALUControlE,            // ALU Control signals for B instructions in Execute Stage
  input  logic              BMUActiveE,              // Bit manipulation instruction being executed
  input  logic [1:0]        CZeroE,                  // {czero.nez, czero.eqz} instructions active
  output logic [1:0]        FlagsE,                  // Comparison flags ({eq, lt})
  output logic [P.XLEN-1:0] IEUAdrE,                 // Address computed by ALU
  output logic [P.XLEN-1:0] ForwardedSrcAE, ForwardedSrcBE, // ALU sources before the mux chooses between them and PCE to put in srcA/B
  // Memory stage signals
  input  logic              StallM, FlushM,          // Stall, flush Memory stage
  input  logic              FWriteIntM, FCvtIntW,    // FPU writes integer register file, FPU converts float to int
  input  logic [P.XLEN-1:0] FIntResM,                // FPU integer result
  output logic [P.XLEN-1:0] SrcAM,                   // ALU's Source A in Memory stage to privilege unit for CSR writes
  output logic [P.XLEN-1:0] WriteDataM,              // Write data in Memory stage
  // Writeback stage signals
  input  logic              StallW, FlushW,          // Stall, flush Writeback stage
  input  logic              RegWriteW, IntDivW,      // Write register file, integer divide instruction
  input  logic              SquashSCW,               // Squash a store conditional when a conflict arose
  input  logic [2:0]        ResultSrcW,              // Select source of result to write back to register file
  input  logic [P.XLEN-1:0] FCvtIntResW,             // FPU convert fp to integer result
  input  logic [P.XLEN-1:0] ReadDataW,               // Read data from LSU
  input  logic [P.XLEN-1:0] CSRReadValW,             // CSR read result
  input  logic [P.XLEN-1:0] MDUResultW,              // MDU (Multiply/divide unit) result
  input  logic [P.XLEN-1:0] FIntDivResultW,          // FPU's integer divide result
  input  logic [4:0]        RdW,                     // Destination register
  // SHARD: the shadow pipeline is the only writer of the register file, and reads it
  // through its own two ports
  input  logic              shadow_we3,
  input  logic [4:0]        shadow_a3,
  input  logic [P.XLEN-1:0] shadow_wd3,
  input  logic [4:0]        sRs1E, sRs2E,
  output logic [P.XLEN-1:0] sRD1E, sRD2E,
  // SHARD: RQ associative forwarding of retired-but-uncommitted results
  input  logic              RQ_HitA,
  input  logic [P.XLEN-1:0] RQ_ValA,
  input  logic              RQ_HitB,
  input  logic [P.XLEN-1:0] RQ_ValB,
  // SHARD: values recorded for the shadow
  output logic [P.XLEN-1:0] SrcAE_out,               // ALU operands after the PC/immediate muxes
  output logic [P.XLEN-1:0] SrcBE_out,
  output logic [P.XLEN-1:0] ForwardedSrcAM,          // rs1 value used, in Memory stage (rs2 is WriteDataM)
  output logic [P.XLEN-1:0] ResultW_out,             // W-stage result on its way to the RQ
  // ECC error aggregation outputs
  output logic              RegEccSecErrW,           // any correctable ECC error (regfile or pipeline reg)
  output logic              RegEccDedErrW,           // any uncorrectable ECC error → fault signal
  output logic              RegEccDedErrPipeW        // DED from W-stage pipeline reg only (IFResultM→IFResultW)
);

  // Fetch stage signals
  // Decode stage signals
  logic [P.XLEN-1:0] ImmExtD;                        // Extended immediate in Decode stage
  // Execute stage signals
  logic [P.XLEN-1:0] R1E, R2E;                       // Source operands read from register file
  logic [P.XLEN-1:0] ImmExtE;                        // Extended immediate in Execute stage
  logic [P.XLEN-1:0] SrcAE, SrcBE;                   // ALU operands
  logic [P.XLEN-1:0] ALUResultE, AltResultE, IEUResultE; // ALU result, Alternative result (ImmExtE or PC+4), result of execution stage
  // Memory stage signals
  logic [P.XLEN-1:0] IEUResultM;                     // Result from execution stage
  logic [P.XLEN-1:0] IFResultM;                      // Result from either IEU or single-cycle FPU op writing an integer register
  // Writeback stage signals
  logic [P.XLEN-1:0] SCResultW;                      // Store Conditional result
  logic [P.XLEN-1:0] ResultW;                        // Result to write to register file
  logic [P.XLEN-1:0] IFResultW;                      // Result from either IEU or single-cycle FPU op writing an integer register
  logic [P.XLEN-1:0] IFCvtResultW;                   // Result from IEU, signle-cycle FPU op, or 2-cycle FCVT float to int
  logic [P.XLEN-1:0] MulDivResultW;                  // Multiply always comes from MDU.  Divide could come from MDU or FPU (when using fdivsqrt for integer division)

  // ECC error signals from register file read ports
  logic sec_err_rd1, ded_err_rd1;
  logic sec_err_rd2, ded_err_rd2;
  logic sec_err_rd4, ded_err_rd4;
  logic sec_err_rd5, ded_err_rd5;

  // ECC error signals from the 5 pipeline registers (sec / ded per instance)
  logic sec_imme, ded_imme;   // ImmExtD → ImmExtE
  logic sec_srcam, ded_srcam; // SrcAE → SrcAM
  logic sec_ieumm, ded_ieumm; // IEUResultE → IEUResultM
  logic sec_wdm,  ded_wdm;    // ForwardedSrcBE → WriteDataM
  logic sec_ifrw, ded_ifrw;   // IFResultM → IFResultW

  // SHARD: the register file holds verified state only, and the shadow commits to it
  // at a time unrelated to the main pipeline's stalls.  It is therefore read in Execute,
  // combinationally, so that an instruction held in Execute always sees the current
  // committed value underneath the M/W bypasses and the RQ.  Injected dummy instructions
  // never retire, so their shadow-register write port is tied off.
  regfile #(P.XLEN, P.E_SUPPORTED) regf(
    .clk, .reset,
    .we3(shadow_we3), .a1(Rs1E), .a2(Rs2E), .a3(shadow_a3),
    .wd3(shadow_wd3),
    .DummyW(1'b0), .DummySelW(1'b0),
    .rd1(R1E), .rd2(R2E),
    .inject_en(ecc_inject_en),
    .sec_err_rd1, .ded_err_rd1,
    .sec_err_rd2, .ded_err_rd2,
    .a4(sRs1E), .a5(sRs2E), .rd4(sRD1E), .rd5(sRD2E),
    .sec_err_rd4, .ded_err_rd4,
    .sec_err_rd5, .ded_err_rd5
  );
  extend #(P) ext(.InstrD(InstrD[31:7]), .ImmSrcD, .ImmExtD);

  // Execute stage pipeline register (ECC-protected)
  flopenrc_ecc #(P.XLEN) ImmExtEReg(clk, reset, FlushE, ~StallE, ecc_inject_en, ImmExtD,         ImmExtE,    sec_imme,  ded_imme);

  // Standard M/W bypass forwarding mux
  logic [P.XLEN-1:0] FwdSrcA_mw, FwdSrcB_mw;
  mux3  #(P.XLEN)  faemux(R1E, ResultW, IFResultM, ForwardAE, FwdSrcA_mw);
  mux3  #(P.XLEN)  fbemux(R2E, ResultW, IFResultM, ForwardBE, FwdSrcB_mw);
  // RQ associative forwarding applies when neither the M nor the W stage produces the
  // register: those are newer than any RQ entry, which in turn is newer than the regfile.
  assign ForwardedSrcAE = (RQ_HitA & (ForwardAE == 2'b00)) ? RQ_ValA : FwdSrcA_mw;
  assign ForwardedSrcBE = (RQ_HitB & (ForwardBE == 2'b00)) ? RQ_ValB : FwdSrcB_mw;
  comparator #(P.XLEN) comp(ForwardedSrcAE, ForwardedSrcBE, BranchSignedE, FlagsE);
  mux2  #(P.XLEN)  srcamux(ForwardedSrcAE, PCE, ALUSrcAE, SrcAE);
  mux2  #(P.XLEN)  srcbmux(ForwardedSrcBE, ImmExtE, ALUSrcBE, SrcBE);
  alu   #(P)       alu(SrcAE, SrcBE, W64E, UW64E, SubArithE, ALUSelectE, BSelectE, ZBBSelectE, Funct3E, Funct7E, Rs2E, BALUControlE, BMUActiveE, CZeroE, ALUResultE, IEUAdrE);
  mux2  #(P.XLEN)  altresultmux(ImmExtE, PCLinkE, JumpE, AltResultE);
  mux2  #(P.XLEN)  ieuresultmux(ALUResultE, AltResultE, ALUResultSrcE, IEUResultE);

  // Memory stage pipeline registers (ECC-protected)
  flopenrc_ecc #(P.XLEN) SrcAMReg     (clk, reset, FlushM, ~StallM, ecc_inject_en, SrcAE,          SrcAM,      sec_srcam, ded_srcam);
  flopenrc_ecc #(P.XLEN) IEUResultMReg(clk, reset, FlushM, ~StallM, ecc_inject_en, IEUResultE,     IEUResultM, sec_ieumm, ded_ieumm);
  flopenrc_ecc #(P.XLEN) WriteDataMReg(clk, reset, FlushM, ~StallM, ecc_inject_en, ForwardedSrcBE, WriteDataM, sec_wdm,   ded_wdm);
  flopenrc     #(P.XLEN) FwdSrcAMReg  (clk, reset, FlushM, ~StallM, ForwardedSrcAE, ForwardedSrcAM);

  // Writeback stage pipeline register (ECC-protected)
  flopenrc_ecc #(P.XLEN) IFResultWReg (clk, reset, FlushW, ~StallW, ecc_inject_en, IFResultM,      IFResultW,  sec_ifrw,  ded_ifrw);

  // floating point inputs: FIntResM comes from fclass, fcmp, fmv; FCvtIntResW comes from fcvt
  if (P.F_SUPPORTED) begin : fpmux
    mux2  #(P.XLEN)  resultmuxM(IEUResultM, FIntResM, FWriteIntM, IFResultM);
    mux2  #(P.XLEN)  cvtresultmuxW(IFResultW, FCvtIntResW, FCvtIntW, IFCvtResultW);
    if (P.IDIV_ON_FPU & P.F_SUPPORTED) begin
      mux2  #(P.XLEN)  divresultmuxW(MDUResultW, FIntDivResultW, IntDivW, MulDivResultW);
    end else begin
      assign MulDivResultW = MDUResultW;
    end
  end else begin : fpmux
    assign IFResultM = IEUResultM;
    assign IFCvtResultW = IFResultW;
    assign MulDivResultW = MDUResultW;
  end
  mux5  #(P.XLEN) resultmuxW(IFCvtResultW, ReadDataW, CSRReadValW, MulDivResultW, SCResultW, ResultSrcW, ResultW);

  // handle Store Conditional result if atomic extension supported
  if (P.ZALRSC_SUPPORTED) assign SCResultW = {{(P.XLEN-1){1'b0}}, SquashSCW};
  else                    assign SCResultW = '0;

  // ECC error aggregation
  assign RegEccSecErrW = sec_err_rd1 | sec_err_rd2 | sec_err_rd4 | sec_err_rd5
                       | sec_imme
                       | sec_srcam | sec_ieumm | sec_wdm | sec_ifrw;
  assign RegEccDedErrW = ded_err_rd1 | ded_err_rd2 | ded_err_rd4 | ded_err_rd5
                       | ded_imme
                       | ded_srcam | ded_ieumm | ded_wdm | ded_ifrw;
  // Separate W-stage pipeline reg DED: instruction in W when this fires, so MEPC should use PCW
  assign RegEccDedErrPipeW = ded_ifrw;

  assign SrcAE_out   = SrcAE;
  assign SrcBE_out   = SrcBE;
  assign ResultW_out = ResultW;

endmodule
```

### 6.3 `controller.sv`

Only ports change: `Rs1E` (already an internal register) becomes an output next to
`Rs2E`; `RegWriteM` and `ResultSrcM` (already internal) become outputs. Remove the
corresponding internal declarations.

```diff
-  output logic [4:0]  Rs1D, Rs2D, Rs2E,
+  output logic [4:0]  Rs1D, Rs2D, Rs1E, Rs2E,
 ...
+  output logic        RegWriteE, RegWriteM,    // E/M-stage register write enable
+  output logic [2:0]  ResultSrcM,              // M-stage result select
 ...
-  logic [4:0] Rs1E;
-  logic [2:0]  ResultSrcD, ResultSrcE, ResultSrcM;
+  logic [2:0]  ResultSrcD, ResultSrcE;
-  logic        RegWriteM;
```

(`RegWriteE = IEURegWriteE | FWriteIntE` is not a stock output either; it exists in
the AMOEBA controller and is unused by Rev 8.)

`ResultSrc` encoding, used by the shadow to classify the result: `000` IEU result
(or an FP-to-integer result if `FWriteInt`), `001` memory read data, `010` CSR read
value, `011` multiply/divide, `100` SC result.

### 6.4 `ieu.sv`

New ports, and one small block that captures the datapath controls in M:

```systemverilog
  // The shadow re-executes each retired instruction with the main pipeline's
  // decoded datapath controls, captured as the instruction moves to the Memory stage.
  flopenrc #(3) ImmSrcEReg(clk, reset, FlushE, ~StallE, ImmSrcD, ImmSrcE);
  assign ShardCtlE = {ALUSrcAE, ALUSrcBE, ImmSrcE, W64E, UW64E, SubArithE, ALUSelectE, BSelectE,
                      ZBBSelectE, BALUControlE, BMUActiveE, CZeroE, ALUResultSrcE, JumpE, BranchE};
  flopenrc #(28) ShardCtlMReg(clk, reset, FlushM, ~StallM, ShardCtlE, ShardCtlM);
  flopenrc #(1)  PCSrcMReg(clk, reset, FlushM, ~StallM, PCSrcE, PCSrcM);
```

`ShardCtlM` bit map: `[27]` ALUSrcA, `[26]` ALUSrcB, `[25:23]` ImmSrc, `[22]` W64,
`[21]` UW64, `[20]` SubArith, `[19:17]` ALUSelect, `[16:13]` BSelect, `[12:9]`
ZBBSelect, `[8:6]` BALUControl, `[5]` BMUActive, `[4:3]` CZero, `[2]` ALUResultSrc,
`[1]` Jump, `[0]` Branch.

```systemverilog
module ieu import cvw::*;  #(parameter cvw_t P) (
  input  logic              clk, reset,
  // ECC inject enable (from top-level, for DFT)
  input  logic              ecc_inject_en,
  // ECC error aggregation outputs (correctable / uncorrectable)
  output logic              RegEccSecErrW,
  output logic              RegEccDedErrW,
  output logic              RegEccDedErrPipeW,       // DED from W-stage pipeline reg only (for precise EPC)
  // Decode stage signals
  input  logic [31:0]       InstrD,                          // Instruction
  input  logic [1:0]        STATUS_FS,                       // is FPU enabled?
  input  logic [3:0]        ENVCFG_CBE,                      // Cache block operation enables
  input  logic              IllegalIEUFPUInstrD,             // Illegal instruction
  output logic              IllegalBaseInstrD,               // Illegal I-type instruction, or illegal RV32 access to upper 16 registers
  // Execute stage signals
  input  logic [P.XLEN-1:0] PCE,                             // PC
  input  logic [P.XLEN-1:0] PCLinkE,                         // PC + 4
  output logic              PCSrcE,                          // Select next PC (between PC+4 and IEUAdrE)
  input  logic              FWriteIntE, FCvtIntE,            // FPU writes to integer register file, FPU converts float to int
  output logic [P.XLEN-1:0] IEUAdrE,                         // Memory address
  output logic              IntDivE, W64E,                   // Integer divide, RV64 W-type instruction
  output logic [2:0]        Funct3E,                         // Funct3 instruction field
  output logic [P.XLEN-1:0] ForwardedSrcAE, ForwardedSrcBE,  // ALU src inputs before the mux choosing between them and PCE to put in srcA/B
  output logic [4:0]        RdE,                             // Destination register
  output logic              MDUActiveE,                      // Mul/Div instruction being executed
  output logic [3:0]        CMOpM,                           // 1: cbo.inval; 2: cbo.flush; 4: cbo.clean; 8: cbo.zero
  output logic              IFUPrefetchE,                    // instruction prefetch
  output logic              LSUPrefetchM,                    // datata prefetch
  // Memory stage signals
  input  logic              SquashSCW,                       // Squash store conditional, from LSU
  output logic [1:0]        MemRWE,                          // Read/write control goes to LSU
  output logic [1:0]        MemRWM,                          // Read/write control goes to LSU
  output logic [1:0]        AtomicM,                         // Atomic control goes to LSU
  output logic [P.XLEN-1:0] WriteDataM,                      // Write data to LSU
  output logic [2:0]        Funct3M,                         // Funct3 (size and signedness) to LSU
  output logic [P.XLEN-1:0] SrcAM,                           // ALU SrcA to Privileged unit and FPU
  output logic [4:0]        RdM,                             // Destination register
  input  logic [P.XLEN-1:0] FIntResM,                        // Integer result from FPU (fmv, fclass, fcmp)
  output logic              InvalidateICacheM, FlushDCacheM, // Invalidate I$, flush D$
  output logic              InstrValidD, InstrValidE, InstrValidM, // Instruction is valid
  output logic              BranchD, BranchE,
  output logic              JumpD, JumpE,
  // Writeback stage signals
  input  logic [P.XLEN-1:0] FIntDivResultW,                  // Integer divide result from FPU fdivsqrt)
  input  logic [P.XLEN-1:0] CSRReadValW,                     // CSR read value,
  input  logic [P.XLEN-1:0] MDUResultW,                      // multiply/divide unit result
  input  logic [P.XLEN-1:0] FCvtIntResW,                     // FPU's float to int conversion result
  input  logic              FCvtIntW,                        // FPU converts float to int
  output logic [4:0]        RdW,                             // Destination register
  input  logic [P.XLEN-1:0] ReadDataW,                       // LSU's read data
  // Hazard unit signals
  input  logic              StallD, StallE, StallM, StallW,  // Stall signals from hazard unit
  input  logic              FlushD, FlushE, FlushM, FlushW,  // Flush signals
  output logic              StructuralStallD,                // IEU detects structural hazard in Decode stage
  output logic              LoadStallD,                      // Structural stalls for load, sent to performance counters
  output logic              StoreStallD,                     // load after store hazard
  output logic              CSRReadM, CSRWriteM, PrivilegedM,// CSR read, CSR write, is privileged instruction
  output logic              CSRWriteFenceM,                  // CSR write or fence instruction needs to flush subsequent instructions
  // AMOEBA random instruction insertion
  input  logic              InjectD,                         // Inject DummyInstrD into Decode this cycle
  input  logic [31:0]       DummyInstrD,                     // Dummy instruction to inject
  input  logic              DummySelD,                       // Which shadow physical register the dummy writes
  output logic              DummyW,                          // Writeback stage holds a dummy instruction
  // SHARD: register file ports owned by the shadow pipeline (sole writer, two read ports)
  input  logic              shadow_we3,
  input  logic [4:0]        shadow_a3,
  input  logic [P.XLEN-1:0] shadow_wd3,
  input  logic [4:0]        sRs1E, sRs2E,
  output logic [P.XLEN-1:0] sRD1E, sRD2E,
  // SHARD: RQ associative forwarding (driven by shadow_rq)
  output logic [4:0]        Rs1E, Rs2E,                      // Execute-stage source registers for the RQ lookup
  input  logic              RQ_HitA,
  input  logic [P.XLEN-1:0] RQ_ValA,
  input  logic              RQ_HitB,
  input  logic [P.XLEN-1:0] RQ_ValB,
  // SHARD: what the main pipeline used, recorded for the shadow
  output logic [P.XLEN-1:0] SrcAE, SrcBE,                    // ALU operands
  output logic [P.XLEN-1:0] ForwardedSrcAM,                  // rs1 value in Memory stage
  output logic [27:0]       ShardCtlM,                       // datapath controls in Memory stage
  output logic              PCSrcM,                          // branch or jump redirected the PC
  output logic              RegWriteM,                       // integer register write, Memory stage
  output logic [2:0]        ResultSrcM,                      // result select, Memory stage
  output logic              FWriteIntM,                      // FPU result written to an integer register
  output logic              RegWriteW,                       // integer register write, Writeback stage
  output logic [P.XLEN-1:0] ResultW                          // Writeback-stage result
);

  logic [2:0] ImmSrcD;                                       // Select type of immediate extension
  logic [1:0] FlagsE;                                        // Comparison flags ({eq, lt})
  logic       ALUSrcAE, ALUSrcBE;                            // ALU source operands
  logic [2:0] ResultSrcW;                                    // Selects result in Writeback stage
  logic       ALUResultSrcE;                                 // Selects ALU result to pass on to Memory stage
  logic [2:0] ALUSelectE;                                    // ALU select mux signal
  logic       IntDivW;                                       // Integer divide instruction
  logic [3:0] BSelectE;                                      // Indicates if ZBA_ZBB_ZBC_ZBS instruction in one-hot encoding
  logic [3:0] ZBBSelectE;                                    // ZBB Result Select Signal in Execute Stage
  logic [2:0] BALUControlE;                                  // ALU Control signals for B instructions in Execute Stage
  logic       SubArithE;                                     // Subtraction or arithmetic shift
  logic       UW64E;                                         // .uw-type instruction

  logic [6:0] Funct7E;

  // AMOEBA: the injection point.  Only the IEU sees the dummy; the IFU's branch
  // predictor and the FPU keep decoding the real instruction, which is being held
  // in Decode for one cycle and will issue normally next cycle.
  logic [31:0] InstrDMux;
  assign InstrDMux = InjectD ? DummyInstrD : InstrD;

  // Forwarding signals
  logic [4:0] Rs1D, Rs2D;
  logic [1:0] ForwardAE, ForwardBE;                          // Select signals for forwarding multiplexers
  logic       BranchSignedE;                                 // Branch does signed comparison on operands
  logic       BMUActiveE;                                    // Bit manipulation instruction being executed
  logic [1:0] CZeroE;                                        // {czero.nez, czero.eqz} instructions active
  logic       RegWriteE;                                     // E-stage register write enable
  logic [2:0] ImmSrcE;                                       // Immediate format, Execute stage
  logic [27:0] ShardCtlE;                                    // Datapath controls recorded for the shadow

  controller #(P) c(
    .clk, .reset, .StallD, .FlushD, .InstrD(InstrDMux), .STATUS_FS, .ENVCFG_CBE, .ImmSrcD,
    .InjectD, .DummySelD, .DummyW, .DummySelW(),
    .IllegalIEUFPUInstrD, .IllegalBaseInstrD,
    .StructuralStallD, .LoadStallD, .StoreStallD, .Rs1D, .Rs2D, .Rs1E, .Rs2E,
    .StallE, .FlushE, .FlagsE, .FWriteIntE, .FTStall(1'b0),
    .PCSrcE, .ALUSrcAE, .ALUSrcBE, .ALUResultSrcE, .ALUSelectE,
    .Funct3E, .Funct7E, .IntDivE, .W64E, .UW64E, .SubArithE, .BranchD, .BranchE, .JumpD, .JumpE,
    .BranchSignedE, .BSelectE, .ZBBSelectE, .BALUControlE, .BMUActiveE, .CZeroE, .MDUActiveE,
    .FCvtIntE, .ForwardAE, .ForwardBE, .CMOpM, .IFUPrefetchE, .LSUPrefetchM,
    .StallM, .FlushM, .MemRWE, .MemRWM, .CSRReadM, .CSRWriteM, .PrivilegedM, .AtomicM, .Funct3M,
    .FlushDCacheM, .InstrValidM, .InstrValidE, .InstrValidD, .FWriteIntM,
    .StallW, .FlushW, .RegWriteE, .RegWriteM, .ResultSrcM, .RegWriteW, .IntDivW, .ResultSrcW, .CSRWriteFenceM, .InvalidateICacheM,
    .RdW, .RdE, .RdM);

  datapath #(P) dp(
    .clk, .reset, .ecc_inject_en,
    .ImmSrcD, .InstrD(InstrDMux), .Rs1E, .Rs2E, .StallE, .FlushE, .ForwardAE, .ForwardBE, .W64E, .UW64E, .SubArithE,
    .Funct3E, .Funct7E, .ALUSrcAE, .ALUSrcBE, .ALUResultSrcE, .ALUSelectE, .JumpE, .BranchSignedE,
    .PCE, .PCLinkE, .FlagsE, .IEUAdrE, .ForwardedSrcAE, .ForwardedSrcBE, .BSelectE, .ZBBSelectE, .BALUControlE, .BMUActiveE, .CZeroE,
    .StallM, .FlushM, .FWriteIntM, .FIntResM, .SrcAM, .WriteDataM, .FCvtIntW,
    .StallW, .FlushW, .RegWriteW, .IntDivW, .SquashSCW, .ResultSrcW, .ReadDataW, .FCvtIntResW,
    .CSRReadValW, .MDUResultW, .FIntDivResultW, .RdW,
    .shadow_we3, .shadow_a3, .shadow_wd3, .sRs1E, .sRs2E, .sRD1E, .sRD2E,
    .RQ_HitA, .RQ_ValA, .RQ_HitB, .RQ_ValB,
    .SrcAE_out(SrcAE), .SrcBE_out(SrcBE), .ForwardedSrcAM, .ResultW_out(ResultW),
    .RegEccSecErrW, .RegEccDedErrW, .RegEccDedErrPipeW);

  // SHARD: the shadow re-executes each retired instruction with the main pipeline's
  // decoded datapath controls, captured as the instruction moves to the Memory stage.
  flopenrc #(3) ImmSrcEReg(clk, reset, FlushE, ~StallE, ImmSrcD, ImmSrcE);
  assign ShardCtlE = {ALUSrcAE, ALUSrcBE, ImmSrcE, W64E, UW64E, SubArithE, ALUSelectE, BSelectE,
                      ZBBSelectE, BALUControlE, BMUActiveE, CZeroE, ALUResultSrcE, JumpE, BranchE};
  flopenrc #(28) ShardCtlMReg(clk, reset, FlushM, ~StallM, ShardCtlE, ShardCtlM);
  flopenrc #(1)  PCSrcMReg(clk, reset, FlushM, ~StallM, PCSrcE, PCSrcM);
endmodule
```

---

## 7. The store buffer — `lsu.sv`

This is the largest and most delicate part. It has five pieces: classification,
holds, request masking, the drain engine, and store-to-load forwarding.

### 7.1 Classification of the M-stage access

```systemverilog
  assign AlignedM = (Funct3M[1:0] == 2'b00) | ((Funct3M[1:0] == 2'b01) & ~IEUAdrM[0]) |
                    ((Funct3M[1:0] == 2'b10) & (IEUAdrM[1:0] == 2'b00)) |
                    ((Funct3M[1:0] == 2'b11) & (IEUAdrM[2:0] == 3'b000));
  assign SimpleMemOKM = AlignedM & ~FpLoadStoreM & ~BigEndianM & ~SelDTIM & ~(|CMOpM);
  assign SerialMemM = ((|MemRWM) & ~SimpleMemOKM) | (MemRWM[1] & ~CacheableM) | (|CMOpM);
  assign SQStoreM   = MemRWM[0] & SimpleMemOKM & LSURWM[0];
```

- **Simple** = naturally aligned, integer, little-endian, not DTIM, not a
  cache-block operation. Such an access maps onto exactly one SQ entry (one
  address, one size, `XLEN` bits of data) and one merged read word.
- **Queued store** (`SQStoreM`): a simple access with a write half — a store, an
  AMO, or an SC that kept its reservation (`LSURWM[0]` is what `atomic`/`lrsc`
  leaves after squashing a failed SC). It may be cacheable or not: a device store
  is queued too and drains to the bus later.
- **Serialized access** (`SerialMemM`): anything not simple, plus any *read* of
  uncacheable memory. A device read can have side effects, so it must not happen
  on a path that might be squashed, and it must come after every older store has
  reached the device. Serialized accesses run through the unmodified legacy path
  once the shadow is quiescent.
- A simple cacheable load, LR, or AMO read needs nothing: it reads the cache
  immediately and takes buffered bytes from the merge.

`CacheableM` and `SelDTIM` come from the MMU's PMA check of `PAdrM` and are
meaningful once the TLB has hit. That is sufficient: a TLB miss is handled first
(§7.2).

### 7.2 Holds

```systemverilog
  assign SQEmpty = (sqCount == '0);
  assign SQFull  = (sqCount == SQ_DEPTH[$clog2(SQ_DEPTH+1)-1:0]);
  assign ShadowQuiescentM = ShadowIdleM & SQEmpty & ~SQBusy;
  assign WalkOK = SQEmpty & ~SQBusy;

  assign HoldM = ((NonMemSerialM | SerialMemM) & ~ShadowQuiescentM) | ShardPreFaultM |
                 (MemRWM[0] & SimpleMemOKM & SQFull) |
                 ((ITLBMissOrUpdateAF | DTLBMissOrUpdateDAM) & ~WalkOK);
```

`HoldM` does two things, and both are required:
1. it stalls the pipeline — it is part of `ShardLSUStallM`, which is ORed into
   `CacheBusHPWTStall` and therefore into `LSUStallM` → `StallWCause` (gated there
   by `~FlushWCause`, so a trap or redirect still goes through);
2. it hides the M-stage instruction from the cache and bus (§7.3). Without this
   the access would start anyway (W3).

The four reasons:

| Term | Waits for | Why |
|---|---|---|
| `(NonMemSerialM \| SerialMemM) & ~ShadowQuiescentM` | every older instruction verified and committed, SQ empty, drain idle | The instruction's effect cannot be deferred or undone. `NonMemSerialM` also carries "a trap is pending" (§9.1) |
| `ShardPreFaultM` | the redirect | The instruction failed a Memory-stage check outside the LSU; it must not touch memory while it waits to be replayed |
| `MemRWM[0] & SimpleMemOKM & SQFull` | a free SQ slot | Uses the pre-squash write bit so the hold does not depend on the SC result |
| `(ITLBMiss \| DTLBMiss) & ~WalkOK` | SQ empty | A page walk reads PTEs, and with Svadu writes one, directly through the D-cache. A buffered store to that PTE would be missed or later overwrite the walker's update |

**The HPTW's miss inputs are gated by `WalkOK`**:
`.ITLBMissOrUpdateAF(ITLBMissOrUpdateAF & WalkOK)`, `.DTLBMissOrUpdateDAM(
DTLBMissOrUpdateDAM & WalkOK)`. While the SQ is not empty the HPTW sees no miss —
so it asserts neither its stall nor its flush — and `HoldM` stalls and masks
instead. When the SQ has drained and the drain engine is idle, the gate opens and
the walk starts exactly as in stock Wally. The walker and the drain engine can
therefore never be active together: the engine starts only with `~CommittedM`
(which includes `SelHPTW`) and a non-empty SQ; a walk starts only with an empty SQ
and an idle engine.

**Progress.** A hold always ends. The shadow does not depend on the main pipeline
being unstalled (§4.2), so every instruction that is past M gets verified and
committed (or faults, which flushes the held instruction). The drain engine needs
only the cache/bus, which the held instruction is not using.

### 7.3 Request masking

Three kinds of request reach the cache and bus from the M-stage instruction and
all must be hidden while it is held or while the drain engine owns the LSU:

```systemverilog
  assign ShardMaskM = HoldM | SQOwnsLSUM;

  // read/write to the cache, bus and DTIM
  always_comb
    if (SQDrainSel | SelHPTW) LSURWMaskedM = LSURWM;                       // their own request
    else if (ShardMaskM)      LSURWMaskedM = 2'b00;                        // held / restoring
    else                      LSURWMaskedM = {LSURWM[1], LSURWM[0] & ~SimpleMemOKM};
```
`LSURWMaskedM` replaces `LSURWM` in `CacheRWM`, `BusRW` and `DTIMMemRWM`. The last
line is the heart of the store buffer: **a queued store, SC or AMO presents only
its read half to memory.** A plain store presents nothing at all (no cache lookup,
no miss); an AMO becomes a read. Only a non-simple access writes from M.

The other two are raw IEU signals that bypass the request chain:
```systemverilog
  assign FlushDCache            = FlushDCacheM & ~SelHPTW & ~ShardMaskM;
  assign CacheableOrFlushCacheM = CacheableM | (FlushDCacheM & ~ShardMaskM);
  assign CacheCMOpM = (CacheableM & ~SelHPTW & ~ShardMaskM) ? CMOpM : '0;   // if ZICBOZ/ZICBOM
  assign BusCMOZero = LSUCMOpM[3] & ~CacheableM & ~ShardMaskM;
```
A `fence.i` waiting in M would otherwise start flushing the D-cache at once (before
the buffered stores are in it), and a waiting cache-block operation would act on
whatever address the drain engine is presenting.

`BusAtomic` is tied to 0 (both the cached and the no-cache branch): an AMO only
reads from M, so the bus must never see a locked read-modify-write.

The MMU is **not** masked. It keeps seeing the M-stage instruction's request
(`PreLSURWM`) during a hold, so translation, PMP/PMA and page-fault results stay
valid — a pending fault keeps `TrapPendingM` asserted while it waits.

### 7.4 The drain engine

A four-state machine modeled on the HPTW (W10). It replays the SQ head as an
ordinary store through the unmodified LSU write path, so a hit, a miss with
eviction, and an uncached bus write all work without touching the cache or bus
logic.

```systemverilog
  assign SQStart    = (SQState == SQ_IDLE) & (sqNVerified != '0) & ~CommittedM;
  assign SQRestoreM = MemRWM[1] | ((|MemRWM) & ~SimpleMemOKM) | (|CMOpM) | FlushDCacheM;
  always_comb
    case (SQState)
      SQ_IDLE:    SQNextState = SQStart ? SQ_WR : SQ_IDLE;
      SQ_ADR:     SQNextState = SQ_WR;
      SQ_WR:      if (DCacheBusStallM)      SQNextState = SQ_WR;
                  else if (sqNVerified > 1) SQNextState = SQ_ADR;
                  else if (SQRestoreM)      SQNextState = SQ_RESTORE;
                  else                      SQNextState = SQ_IDLE;
      default:    SQNextState = SQ_IDLE;
    endcase

  assign SQBusy     = (SQState != SQ_IDLE);
  assign SQOwnsLSUM = SQBusy | SQStart;
  assign SQDrainSel = SQStart | (SQState == SQ_ADR) | (SQState == SQ_WR);
  assign sqPop      = (SQState == SQ_WR) & ~DCacheBusStallM;
  assign ShardLSUStallM = HoldM | SQOwnsLSUM;
```

| Cycle | What the LSU presents | What the cache does |
|---|---|---|
| `IDLE` with `SQStart` | head's address, `RW = 00`; M-stage instruction masked | reads the head's set (address taken from `PAdr` because the "HPTW-style" select is on) |
| `WR` | head's address, size, data, `RW = 01` | hit: writes at the end of the cycle. Miss: `CacheStall` until the line is fetched and merged; uncacheable: bus write, `BusStall` until done. `sqPop` in the cycle the stall is low |
| `ADR` (only when another verified entry follows) | the new head's address, `RW = 00` | reads its set |
| `RESTORE` (only if `SQRestoreM`) | the M-stage instruction's own address (translation on), `RW = 00` | reads that instruction's set, so the data and tags it needs are at the SRAM outputs when it resumes |

While `SQDrainSel` the engine's values replace the IEU/HPTW request:
```systemverilog
  assign PreLSURWM    = SQDrainSel ? {1'b0, SQState == SQ_WR} : HPreLSURWM;
  assign LSUFunct3M   = SQDrainSel ? {1'b0, sqSize[0]} : HLSUFunct3M;
  assign LSUFunct7M   = SQDrainSel ? 7'b0 : HLSUFunct7M;
  assign LSUAtomicM   = SQDrainSel ? 2'b00 : HLSUAtomicM;
  assign LSUCMOpM     = SQDrainSel ? 4'b0 : HLSUCMOpM;
  assign IHAdrM       = SQDrainSel ? {{(P.XLEN+2-P.PA_BITS){1'b0}}, sqPA[0]} : HIHAdrM;
  assign IHWriteDataM = SQDrainSel ? sqData[0] : HIHWriteDataM;
```
(`H…` are the HPTW's outputs, renamed; in a configuration without virtual memory
they are assigned straight from the IEU signals.) In addition:

- `DisableTranslation |= SQDrainSel` — the SQ holds a physical address.
- The four MMU fault outputs are ANDed with `~SQDrainSel`. The store passed its
  PMP/PMA checks when it executed, and privilege mode and PMP configuration cannot
  have changed since (changing either is serialized, which requires an empty SQ).
- The cache's and the misaligned-access unit's `SelHPTW` inputs get
  `SelHPTW | SQOwnsLSUM`, so the cache indexes with `PAdr` and no alignment shift
  is applied.
- `GatedStallW = StallW & ~SelHPTW & ~SQOwnsLSUM`. The engine stalls the pipeline
  itself; the cache and bus must not see that stall, or `CacheEn` would hold the
  SRAMs and the address cycle would read nothing. **This includes the `SQStart`
  cycle.**
- `LSUFlushW = HPTWFlushW | (FlushW & ~SQBusy)`. A pipeline flush (trap, redirect)
  must not cancel the engine's write: that store is verified and older than
  anything the flush discards. The pipeline is flushed normally; the engine
  finishes and then stalls the refilled pipeline as usual.
- The write-data mux selects FP data on the raw `FpLoadStoreM`; gate it with
  `~SQDrainSel` (an FP store may be the instruction waiting in M).

**When the engine may start.** `~CommittedM`: the cache FSM is in `ACCESS`, the bus
FSM is idle and the HPTW is idle. The M-stage instruction is then either not using
the cache, or in the first cycle of an access (cancelled by the mask and replayed
after `RESTORE`), or finished and merely stalled (re-evaluated after `RESTORE`; a
hit is idempotent). The engine never starts while a load is in the middle of a
miss.

**What it can interleave with.** Only simple cacheable loads and non-memory
instructions. Every serialized access, every page walk, and a D-cache flush
require `SQEmpty` first, and no store can enter the SQ while one of those sits in
M, so the engine never runs against the misaligned-access FSM, a bus access by the
main pipeline, a cache-block operation or the walker.

**`RESTORE` is skipped** when the M-stage instruction makes no cache access of its
own (a non-memory instruction or a queued plain store). The next cycle is `IDLE`,
the pipeline advances, and the cache reads `NextSet` for the Execute instruction
as it normally would.

**Cost.** Two stalled cycles per isolated store (start + write), three with
`RESTORE`; consecutive verified stores cost two each plus one restore.

### 7.5 Store-to-load forwarding

`shadow_sqmerge` takes the word read from memory (`ReadDataWordMuxM`, after the
cache/bus/DTIM select and before the endian swap and sub-word extract), the
access's physical address, and all SQ entries. For each entry below `sqCount`
whose word address (`PA[PA_BITS-1:log2(LLEN/8)]`) equals the access's, it overwrites
the bytes selected by that entry's size and offset with the entry's data
(replicated the way `subwordwrite` replicates it). Entries are applied oldest
first, so the newest store to a byte wins. Verified and unverified entries are
treated alike: all are older than the instruction in M.

The result `ReadDataWordFwdM` replaces `ReadDataWordMuxM` everywhere downstream:
the endian swap, `subwordread`, and therefore the AMO ALU's old value and the
HPTW's read data. Its low `XLEN` bits are `RawReadDataWordM`, which goes into the
OQ: the shadow re-derives the load result from it.

Because the match is on the full physical word address the merge is exact, and a
partial overlap (a byte store followed by a word load) simply merges — there is no
"stall on partial overlap" case. Accesses the merge cannot represent (misaligned,
uncacheable) are serialized and therefore always run with an empty SQ, where the
merge is the identity.

The merge is instantiated twice on the same inputs and the outputs compared:
`LoadFwdFaultM = MemRWM[1] & ~SQOwnsLSUM & (ReadDataWordFwdM !=
ReadDataWordFwdCheckM)`. It sits in the main load path *ahead* of the raw word the
shadow checks against, so without the duplicate a fault in it would be invisible.

```systemverilog
///////////////////////////////////////////
// shadow_sqmerge.sv
//
// Purpose: SHARD store-to-load forwarding.  Every store buffered in the store queue
//          is older than the instruction in the main Memory stage, whether or not the
//          shadow has verified it yet.  Merge their bytes over the word read from the
//          cache, oldest first so that the newest store to a byte wins.
//
//          The match is on the full physical word address, so it is exact; entries
//          are naturally aligned and never cross a word.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_sqmerge import cvw::*; #(parameter cvw_t P, parameter int DEPTH = 8) (
  input  logic [P.LLEN-1:0]          ReadDataWordM,    // word read from the cache
  input  logic [P.PA_BITS-1:0]       PAdrM,            // physical address of the access
  input  var logic [P.PA_BITS-1:0]   sqPA [DEPTH],
  input  var logic [1:0]             sqSize [DEPTH],
  input  var logic [P.XLEN-1:0]      sqData [DEPTH],
  input  logic [$clog2(DEPTH+1)-1:0] sqCount,
  output logic [P.LLEN-1:0]          ReadDataWordFwdM  // word with the buffered stores merged in
);

  localparam LLENBYTES   = P.LLEN/8;
  localparam LLENADRBITS = $clog2(LLENBYTES);

  always_comb begin
    ReadDataWordFwdM = ReadDataWordM;
    for (int i = 0; i < DEPTH; i++) begin
      logic [LLENBYTES-1:0] Mask;
      logic [P.LLEN-1:0]    Data;
      Mask = (('d2**('d2**sqSize[i]))-'d1) << sqPA[i][LLENADRBITS-1:0];
      case (sqSize[i])
        2'b00:   Data = {LLENBYTES{sqData[i][7:0]}};
        2'b01:   Data = {(LLENBYTES/2){sqData[i][15:0]}};
        2'b10:   Data = {(LLENBYTES/4){sqData[i][31:0]}};
        default: Data = {(P.LLEN/P.XLEN){sqData[i]}};
      endcase
      if ((i < sqCount) & (sqPA[i][P.PA_BITS-1:LLENADRBITS] == PAdrM[P.PA_BITS-1:LLENADRBITS]))
        for (int b = 0; b < LLENBYTES; b++)
          if (Mask[b]) ReadDataWordFwdM[8*b +: 8] = Data[8*b +: 8];
    end
  end

endmodule
```

### 7.6 The second AMO ALU

A second `amoalu` on the same inputs as the first; `AMOFaultM = LSUAtomicM[1] &
(ShadowAMOResultM != IMAWriteDataM)`. It is redundant with the shadow's own AMO
check for queued AMOs, and it is the only check for an AMO that writes directly
(big-endian mode). **It must not be gated with `~LSUFlushW`** (§14, P5).

### 7.7 LR/SC — `atomic.sv`, `lrsc.sv`

An LR is a simple load; an SC that keeps its reservation is a queued store. The
reservation register is not rolled back by a redirect, so it is simply dropped:

```systemverilog
  always_comb begin // ReservationValidM (next value of valid reservation)
    if (ShardRedirectM) ReservationValidM = 1'b0;
    else if (lrM) ReservationValidM = 1'b1;
    else if (scM) ReservationValidM = 1'b0;
    else ReservationValidM = ReservationValidW;
  end
```
`ShardRedirectM` is a new input of `lrsc`, passed through `atomic` from the LSU's
port list. A replayed SC then fails, which the architecture allows, and software
retries the LR/SC sequence.

### 7.8 New ports of `lsu`

```systemverilog
module lsu import cvw::*;  #(parameter cvw_t P, parameter int SQ_DEPTH = 8) (
  ...
  input  logic                    ShadowIdleM,       // every retired instruction verified and committed
  input  logic                    NonMemSerialM,     // M-stage instruction has an irreversible non-memory effect, or a trap is pending
  input  logic                    ShardPreFaultM,    // M-stage instruction failed a check outside the LSU
  input  logic                    ShardRedirectM,    // recovery or retry redirect: discard the LR reservation
  input  var logic [P.PA_BITS-1:0] sqPA [SQ_DEPTH],  // store queue contents, oldest first
  input  var logic [1:0]          sqSize [SQ_DEPTH],
  input  var logic [P.XLEN-1:0]   sqData [SQ_DEPTH],
  input  logic [$clog2(SQ_DEPTH+1)-1:0] sqCount, sqNVerified,
  output logic                    sqPop,             // drain engine wrote the head to memory
  output logic                    SQStoreM,          // M-stage instruction enters the SQ when it leaves M
  output logic [P.PA_BITS-1:0]    SQPAdrM,           // = PAdrM
  output logic [P.XLEN-1:0]       SQWriteDataM,      // = IMAWriteDataM (store data, or the AMO result)
  output logic                    ShadowQuiescentM,
  output logic [P.XLEN-1:0]       RawReadDataWordM,  // merged read word before sub-word extract
  output logic                    AMOFaultM,
  output logic                    LoadFwdFaultM
);
```

### 7.9 `lsu.sv` as built

Everything above in context. Lines not mentioned are stock Wally.

```systemverilog
module lsu import cvw::*;  #(parameter cvw_t P, parameter int SQ_DEPTH = 8) (
  input  logic                    clk, reset,
  input  logic                    StallM, FlushM, StallW, FlushW,
  output logic                    LSUStallM,                            // LSU stalls pipeline during a multicycle operation
  // connected to cpu (controls)
  input  logic [1:0]              MemRWE,                               // Read/Write control
  input  logic [1:0]              MemRWM,                               // Read/Write control
  input  logic [2:0]              Funct3M,                              // Size of memory operation
  input  logic [6:0]              Funct7M,                              // Atomic memory operation function
  input  logic [1:0]              AtomicM,                              // Atomic memory operation
  input  logic                    FlushDCacheM,                         // Flush D cache to next level of memory
  input  logic [3:0]              CMOpM,                                // 1: cbo.inval; 2: cbo.flush; 4: cbo.clean; 8: cbo.zero
  input  logic                    LSUPrefetchM,                         // Prefetch; presently unused
  output logic                    CommittedM,                           // Delay interrupts while memory operation in flight
  output logic                    SquashSCW,                            // Store conditional failed disable write to GPR
  output logic                    DCacheMiss,                           // D cache miss for performance counters
  output logic                    DCacheAccess,                         // D cache memory access for performance counters
  // address and write data
  input  logic [P.XLEN-1:0]       IEUAdrE,                              // Execution stage memory address
  output logic [P.XLEN-1:0]       IEUAdrM,                              // Memory stage memory address
  input  logic [P.XLEN-1:0]       WriteDataM,                           // Write data from IEU
  output logic [P.LLEN-1:0]       ReadDataW,                            // Read data to IEU or FPU
  // cpu privilege
  input  logic [1:0]              PrivilegeModeW,                       // Current privilege mode
  input  logic                    BigEndianM,                           // Swap byte order to big endian
  input  logic                    sfencevmaM,                           // Virtual memory address fence, invalidate TLB entries
  output logic                    DCacheStallM,                         // D$ busy with multicycle operation
  output logic [P.XLEN-1:0]       IEUAdrxTvalM,                         // IEUAdrM, but could be spilled onto the next cacheline or virtual page.
  // fpu
  input  logic [P.FLEN-1:0]       FWriteDataM,                          // Write data from FPU
  input  logic                    FpLoadStoreM,                         // Selects FPU as store for write data
  // faults
  output logic                    LoadPageFaultM, StoreAmoPageFaultM,   // Page fault exceptions
  output logic                    LoadMisalignedFaultM,                 // Load address misaligned fault
  output logic                    LoadAccessFaultM,                     // Load access fault (PMA)
  output logic                    HPTWInstrAccessFaultF,                // HPTW generated access fault during instruction fetch
  output logic                    HPTWInstrPageFaultF,                  // HPTW generated access fault during instruction fetch
  // cpu hazard unit (trap)
  output logic                    StoreAmoMisalignedFaultM,             // Store or AMO address misaligned fault
  output logic                    StoreAmoAccessFaultM,                 // Store or AMO access fault
  // connect to ahb
  output logic [P.PA_BITS-1:0]    LSUHADDR,                             // Bus address from LSU to EBU
  input  logic [P.XLEN-1:0]       HRDATA,                               // Bus read data from LSU to EBU
  output logic [P.XLEN-1:0]       LSUHWDATA,                            // Bus write data from LSU to EBU
  input  logic                    LSUHREADY,                            // Bus ready from LSU to EBU
  output logic                    LSUHWRITE,                            // Bus write operation from LSU to EBU
  output logic [2:0]              LSUHSIZE,                             // Bus operation size from LSU to EBU
  output logic [2:0]              LSUHBURST,                            // Bus burst from LSU to EBU
  output logic [1:0]              LSUHTRANS,                            // Bus transaction type from LSU to EBU
  output logic [P.XLEN/8-1:0]     LSUHWSTRB,                            // Bus byte write enables from LSU to EBU
  // page table walker
  input  logic [P.XLEN-1:0]       SATP_REGW,                            // SATP (supervisor address translation and protection) CSR
  input  logic                    STATUS_MXR, STATUS_SUM, STATUS_MPRV,  // STATUS CSR bits: make executable readable, supervisor user memory, machine privilege
  input  logic [1:0]              STATUS_MPP,                           // Machine previous privilege mode
  input  logic                    ENVCFG_PBMTE,                         // Page-based memory types enabled
  input  logic                    ENVCFG_ADUE,                          // HPTW A/D Update enable
  input  logic [P.XLEN-1:0]       PCSpillF,                             // Fetch PC
  input  logic                    ITLBMissOrUpdateAF,                   // ITLB miss causes HPTW (hardware pagetable walker) walk or update access bit
  output logic [P.XLEN-1:0]       PTE,                                  // Page table entry write to ITLB
  output logic [2:0]              PageType,                             // Type of page table entry to write to ITLB
  output logic                    ITLBWriteF,                           // Write PTE to ITLB
  output logic                    SelHPTW,                              // During a HPTW walk the effective privilege mode becomes S_MODE
  input var logic [7:0]           PMPCFG_ARRAY_REGW[P.PMP_ENTRIES-1:0], // PMP configuration from privileged unit
  input var logic [P.PA_BITS-3:0] PMPADDR_ARRAY_REGW[P.PMP_ENTRIES-1:0], // PMP address from privileged unit
  // SHARD store buffer.  The main pipeline never writes memory with an ordinary store:
  // the store enters the store queue when it leaves the Memory stage, and this LSU's
  // drain engine writes it to the D-cache or bus once the shadow has verified it.
  input  logic                    ShadowIdleM,                            // every retired instruction has been verified and committed
  input  logic                    NonMemSerialM,                          // M-stage instruction has an irreversible effect outside memory, or a trap is pending
  input  logic                    ShardPreFaultM,                         // M-stage instruction failed a check outside the LSU: it must not access memory
  input  logic                    ShardRedirectM,                         // recovery or retry redirect: discard the LR reservation
  input  var logic [P.PA_BITS-1:0] sqPA [SQ_DEPTH],                       // store queue contents, oldest first
  input  var logic [1:0]          sqSize [SQ_DEPTH],
  input  var logic [P.XLEN-1:0]   sqData [SQ_DEPTH],
  input  logic [$clog2(SQ_DEPTH+1)-1:0] sqCount, sqNVerified,             // entries held, and how many of the oldest are verified
  output logic                    sqPop,                                  // drain engine wrote the head to memory
  output logic                    SQStoreM,                               // M-stage instruction enters the store queue when it leaves M
  output logic [P.PA_BITS-1:0]    SQPAdrM,                                // ... with this physical address
  output logic [P.XLEN-1:0]       SQWriteDataM,                           // ... and this data (store data, or the AMO result)
  output logic                    ShadowQuiescentM,                       // nothing retired is unverified and no store is buffered
  output logic [P.XLEN-1:0]       RawReadDataWordM,                       // aligned load word (after store-queue merge), before subword extract
  output logic                    AMOFaultM,                              // second AMO ALU disagrees with the first
  output logic                    LoadFwdFaultM                           // the two store-queue merges disagree
);
  localparam logic MISALIGN_SUPPORT = P.ZICCLSM_SUPPORTED & P.DCACHE_SUPPORTED;
  localparam MLEN = MISALIGN_SUPPORT ? 2*P.LLEN : P.LLEN; // widen buffer for misaligned accessess

  logic [P.XLEN+1:0]     IEUAdrExtM;                             // Memory stage address zero-extended to PA_BITS or XLEN whichever is longer
  logic [P.XLEN+1:0]     IEUAdrExtE;                             // Execution stage address zero-extended to PA_BITS or XLEN whichever is longer
  logic [P.PA_BITS-1:0]  PAdrM;                                  // Physical memory address
  logic [P.XLEN+1:0]     IHAdrM;                                 // Either IEU or HPTW memory address

  logic [1:0]            PreLSURWM;                              // IEU or HPTW Read/Write signal
  logic [1:0]            LSURWM;                                 // IEU or HPTW Read/Write signal gated by LR/SC
  logic [2:0]            LSUFunct3M;                             // IEU or HPTW memory operation size
  logic [6:0]            LSUFunct7M;                             // AMO function gated by HPTW
  logic [1:0]            LSUAtomicM;                             // AMO signal gated by HPTW
  logic [3:0]            LSUCMOpM;                               // CMOpM gated by HPTW

  logic                  GatedStallW;                            // Hazard unit StallW gated when SelHPTW = 1

  logic                  LSUBusStallM;                           // Bus interface busy with multicycle operation masked by HPTWFlushW
  logic                  HPTWStall;                              // HPTW busy with multicycle operation
  logic                  DCacheBusStallM;                        // Cache or bus stall
  logic                  CacheBusHPWTStall;                      // Cache, bus, or hptw is requesting a stall
  logic                  SelSpillE;                              // Align logic detected a spill and needs to stall

  logic                  CacheableM;                             // PMA indicates memory address is cacheable
  logic                  BusCommittedM;                          // Bus memory operation in flight, delay interrupts
  logic                  DCacheCommittedM;                       // D$ memory operation started, delay interrupts

  logic [P.LLEN-1:0]     DTIMReadDataWordM;                      // DTIM read data
  logic [MLEN-1:0]       DCacheReadDataWordM;                    // D$ read data
  logic [MLEN-1:0]       LSUWriteDataSpillM;                     // Final write data
  logic [MLEN/8-1:0]     ByteMaskSpillM;                         // Selects which bytes within a word to write
  logic [P.LLEN-1:0]     DCacheReadDataWordSpillM;               // D$ read data
  logic [P.LLEN-1:0]     ReadDataWordMuxM;                       // DTIM or D$ read data
  logic [P.LLEN-1:0]     LittleEndianReadDataWordM;              // Endian-swapped read data
  logic [P.LLEN-1:0]     ReadDataM;                              // Final read data

  logic [P.XLEN-1:0]     IHWriteDataM;                           // IEU or HPTW write data
  logic [P.XLEN-1:0]     IMAWriteDataM;                          // IEU, HPTW, or AMO write data
  logic [P.LLEN-1:0]     IMAFWriteDataM;                         // IEU, HPTW, AMO, or FPU write data
  logic [P.LLEN-1:0]     LittleEndianWriteDataM;                 // Ending-swapped write data
  logic [P.LLEN-1:0]     LSUWriteDataM;                          // Final write data
  logic [(P.LLEN-1)/8:0] ByteMaskM;                              // Selects which bytes within a word to write
  logic [(P.LLEN-1)/8:0] ByteMaskExtendedM;                      // Selects which bytes within a word to write
  logic [1:0]            MemRWSpillM;
  logic                  SpillStallM;

  logic                  DTLBMissM;                              // DTLB miss causes HPTW walk
  logic                  DTLBWriteM;                             // Writes PTE and PageType to DTLB
  logic                  LSULoadAccessFaultM;                    // Load access fault
  logic                  LSUStoreAmoAccessFaultM;                // Store access fault
  logic                  HPTWFlushW;                             // HPTW needs to flush operation
  logic                  LSUFlushW;                              // HPTW or hazard unit flushes operation
  logic                  SelDTIM;                                // Select DTIM rather than bus or D$
  logic [P.XLEN-1:0]     WriteDataZM;
  logic                  LSULoadPageFaultM, LSUStoreAmoPageFaultM;
  logic                  DTLBMissOrUpdateDAM;

  // SHARD store buffer
  typedef enum logic [1:0] {SQ_IDLE, SQ_ADR, SQ_WR, SQ_RESTORE} sqstatetype;
  sqstatetype            SQState, SQNextState;
  logic                  SQBusy;                                 // drain engine owns the LSU
  logic                  SQDrainSel;                             // LSU is addressing or writing the store queue head
  logic                  SQStart;                                // drain engine takes the LSU this cycle
  logic                  SQOwnsLSUM;                             // drain engine owns the LSU this cycle
  logic                  SQRestoreM;                             // M-stage instruction needs its cache set re-read after a drain
  logic                  SQEmpty, SQFull;
  logic                  WalkOK;                                 // HPTW may start a walk: nothing buffered that it could miss or overwrite
  logic                  AlignedM;                               // naturally aligned access
  logic                  SimpleMemOKM;                           // access the store queue / byte-merge can represent
  logic                  SerialMemM;                             // memory operation that must wait until the shadow is quiescent
  logic                  HoldM;                                  // M-stage instruction must wait this cycle
  logic                  ShardLSUStallM;                         // stall from a hold or the drain engine
  logic                  ShardMaskM;                             // hide the M-stage instruction from the cache and bus
  logic [1:0]            LSURWMaskedM;                           // read/write presented to the cache, bus and DTIM
  logic [1:0]            HPreLSURWM;                             // IEU or HPTW requests, before the drain engine's
  logic [1:0]            HLSUAtomicM;
  logic [2:0]            HLSUFunct3M;
  logic [6:0]            HLSUFunct7M;
  logic [3:0]            HLSUCMOpM;
  logic [P.XLEN+1:0]     HIHAdrM;
  logic [P.XLEN-1:0]     HIHWriteDataM;
  logic                  MMULoadAccessFaultM, MMUStoreAmoAccessFaultM;
  logic                  MMULoadPageFaultM, MMUStoreAmoPageFaultM;
  logic [P.LLEN-1:0]     ReadDataWordFwdM;                       // read word with buffered stores merged in
  logic [P.LLEN-1:0]     ReadDataWordFwdCheckM;                  // second copy of the merge

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Pipeline for IEUAdr E to M
  // Zero-extend address to 34 bits for XLEN=32
  /////////////////////////////////////////////////////////////////////////////////////////////

  flopenrc #(P.XLEN) AddressMReg(clk, reset, FlushM, ~StallM, IEUAdrE, IEUAdrM);
  if(MISALIGN_SUPPORT) begin : ziccslm_align
    logic [P.XLEN-1:0] IEUAdrSpillE;
    logic [P.XLEN-1:0] IEUAdrSpillM;
    align #(P) align(.clk, .reset, .StallM, .FlushM, .IEUAdrE, .IEUAdrM, .Funct3M, .FpLoadStoreM,
                     .MemRWM,
                     .DCacheReadDataWordM, .CacheBusHPWTStall, .SelHPTW(SelHPTW | SQOwnsLSUM),
                     .ByteMaskM, .ByteMaskExtendedM, .LSUWriteDataM, .ByteMaskSpillM, .LSUWriteDataSpillM,
                     .IEUAdrSpillE, .IEUAdrSpillM, .IEUAdrxTvalM, .SelSpillE, .DCacheReadDataWordSpillM, .SpillStallM);
    assign IEUAdrExtM = {2'b00, IEUAdrSpillM};
    assign IEUAdrExtE = {2'b00, IEUAdrSpillE};
  end else begin : no_ziccslm_align
    assign IEUAdrExtM = {2'b00, IEUAdrM};
    assign IEUAdrExtE = {2'b00, IEUAdrE};
    assign SelSpillE = 1'b0;
    assign DCacheReadDataWordSpillM = DCacheReadDataWordM;
    assign ByteMaskSpillM = ByteMaskM;
    assign LSUWriteDataSpillM = LSUWriteDataM;
    assign MemRWSpillM = MemRWM;
    assign {SpillStallM} = 1'b0;
    assign IEUAdrxTvalM = IEUAdrM;
  end

    if(P.ZICBOZ_SUPPORTED) begin : cboz
      assign WriteDataZM = LSUCMOpM[3] ? 0 : WriteDataM;
   end else begin : cboz
      assign WriteDataZM = WriteDataM;
    end

  /////////////////////////////////////////////////////////////////////////////////////////////
  // HPTW (only needed if VM supported)
  // MMU include PMP and is needed if any privileged supported
  /////////////////////////////////////////////////////////////////////////////////////////////

  if(P.VIRTMEM_SUPPORTED) begin : hptw
    hptw #(P) hptw(.clk, .reset, .MemRWM, .AtomicM, .ITLBMissOrUpdateAF(ITLBMissOrUpdateAF & WalkOK), .ITLBWriteF,
      .DTLBMissOrUpdateDAM(DTLBMissOrUpdateDAM & WalkOK), .DTLBWriteM,
      .FlushW, .DCacheBusStallM, .SATP_REGW, .PCSpillF,
      .STATUS_MXR, .STATUS_SUM, .STATUS_MPRV, .STATUS_MPP, .ENVCFG_ADUE, .PrivilegeModeW,
      .ReadDataM(ReadDataM[P.XLEN-1:0]), // ReadDataM is LLEN, but HPTW only needs XLEN
      .WriteDataM(WriteDataZM), .Funct3M, .LSUFunct3M(HLSUFunct3M), .Funct7M, .LSUFunct7M(HLSUFunct7M),
      .IEUAdrExtM, .PTE, .IHWriteDataM(HIHWriteDataM), .PageType, .PreLSURWM(HPreLSURWM), .LSUAtomicM(HLSUAtomicM),
      .IHAdrM(HIHAdrM), .CMOpM, .LSUCMOpM(HLSUCMOpM), .HPTWStall, .SelHPTW,
      .HPTWFlushW, .LSULoadAccessFaultM, .LSUStoreAmoAccessFaultM,
      .LoadAccessFaultM, .StoreAmoAccessFaultM, .HPTWInstrAccessFaultF,
      .LoadPageFaultM, .StoreAmoPageFaultM, .LSULoadPageFaultM, .LSUStoreAmoPageFaultM, .HPTWInstrPageFaultF
);
  end else begin // No HPTW, so signals are not multiplexed
    assign HPreLSURWM = MemRWM;
    assign HIHAdrM = IEUAdrExtM;
    assign HLSUFunct3M = Funct3M;
    assign HLSUFunct7M = Funct7M;
    assign HLSUAtomicM = AtomicM;
    assign HLSUCMOpM = CMOpM;
    assign HIHWriteDataM = WriteDataZM;
    assign LoadAccessFaultM = LSULoadAccessFaultM;
    assign StoreAmoAccessFaultM = LSUStoreAmoAccessFaultM;
    assign LoadPageFaultM = LSULoadPageFaultM;
    assign StoreAmoPageFaultM = LSUStoreAmoPageFaultM;
    assign {HPTWStall, SelHPTW, PTE, PageType, DTLBWriteM, ITLBWriteF, HPTWFlushW} = '0;
    assign {HPTWInstrAccessFaultF, HPTWInstrPageFaultF} = '0;
   end

  // CommittedM indicates the cache, bus, or HPTW are busy with a multiple cycle operation.
  // CommittedM is 1 after the first cycle and until the last cycle.  Partially completed memory
  // operations delay interrupts until the next instruction by suppressing pending interrupts in
  // the trap module.
  assign CommittedM = SelHPTW | DCacheCommittedM | BusCommittedM;
  assign GatedStallW = StallW & ~SelHPTW & ~SQOwnsLSUM;
  assign DCacheBusStallM = DCacheStallM | LSUBusStallM;
  assign CacheBusHPWTStall = DCacheBusStallM | HPTWStall | ShardLSUStallM;
  assign LSUStallM = CacheBusHPWTStall | SpillStallM;

  /////////////////////////////////////////////////////////////////////////////////////////////
  // MMU and misalignment fault logic required if privileged unit exists
  /////////////////////////////////////////////////////////////////////////////////////////////
  if(P.ZICSR_SUPPORTED == 1) begin : dmmu
    logic DisableTranslation;                             // During HPTW walk or D$ flush disable virtual memory address translation
    logic WriteAccessM;
    logic DataUpdateDAM;                                  // DTLB hit needs to update dirty or access bits

    assign DisableTranslation = SelHPTW | FlushDCacheM | SQDrainSel;
    assign WriteAccessM = PreLSURWM[0];
    mmu #(.P(P), .TLB_ENTRIES(P.DTLB_ENTRIES), .IMMU(0))
    dmmu(.clk, .reset, .SATP_REGW, .STATUS_MXR, .STATUS_SUM, .STATUS_MPRV, .STATUS_MPP, .ENVCFG_PBMTE, .ENVCFG_ADUE,
      .PrivilegeModeW, .DisableTranslation, .VAdr(IHAdrM), .Size(LSUFunct3M[1:0]),
      .PTE, .PageTypeWriteVal(PageType), .TLBWrite(DTLBWriteM), .TLBFlush(sfencevmaM),
      .PhysicalAddress(PAdrM), .TLBMiss(DTLBMissM), .Cacheable(CacheableM), .Idempotent(), .SelTIM(SelDTIM),
      .InstrAccessFaultF(), .LoadAccessFaultM(MMULoadAccessFaultM),
      .StoreAmoAccessFaultM(MMUStoreAmoAccessFaultM), .InstrPageFaultF(), .LoadPageFaultM(MMULoadPageFaultM),
      .StoreAmoPageFaultM(MMUStoreAmoPageFaultM),
      .LoadMisalignedFaultM, .StoreAmoMisalignedFaultM,
      .UpdateDA(DataUpdateDAM), .CMOpM(LSUCMOpM),
      .AtomicAccessM(|LSUAtomicM), .ExecuteAccessF(1'b0),
      .WriteAccessM, .ReadAccessM(PreLSURWM[1]),
      .PMPCFG_ARRAY_REGW, .PMPADDR_ARRAY_REGW);

    assign DTLBMissOrUpdateDAM = DTLBMissM | (P.SVADU_SUPPORTED & DataUpdateDAM);
  end else begin  // No MMU, so no PMA/page faults and no address translation
    assign DTLBMissOrUpdateDAM = '0;
    assign {DTLBMissM, MMULoadAccessFaultM, MMUStoreAmoAccessFaultM, LoadMisalignedFaultM, StoreAmoMisalignedFaultM} = '0;
    assign {MMULoadPageFaultM, MMUStoreAmoPageFaultM} = '0;
    assign PAdrM = IHAdrM[P.PA_BITS-1:0];
    assign CacheableM = 1'b1;
    assign SelDTIM = P.DTIM_SUPPORTED & ~P.BUS_SUPPORTED; // if no PMA then select dtim if there is a DTIM.  If there is
    // a bus then this is always 0. Cannot have both without PMA.
  end

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Memory System (options)
  // 1. DTIM
  // 2. DTIM and bus
  // 3. Bus
  // 4. Cache and bus
  /////////////////////////////////////////////////////////////////////////////////////////////

  // Pause IEU memory request if TLB miss.  After TLB fill, replay request.
  // Discard memory request on pipeline flush
  // A pipeline flush must not abort the drain engine's write: that store has been
  // verified and is older than anything the flush discards.
  assign LSUFlushW = HPTWFlushW | (FlushW & ~SQBusy);

  if (P.DTIM_SUPPORTED) begin : dtim
    logic [P.PA_BITS-1:0] DTIMAdr;
    logic [1:0]           DTIMMemRWM;

    // The DTIM uses untranslated addresses, so it is not compatible with virtual memory.
    mux2 #(P.PA_BITS) DTIMAdrMux(IEUAdrExtE[P.PA_BITS-1:0], IEUAdrExtM[P.PA_BITS-1:0], MemRWM[0], DTIMAdr);
    assign DTIMMemRWM = SelDTIM ? LSURWMaskedM : 0;
    dtim #(P) dtim(.clk, .reset, .ce(~GatedStallW),
              .MemRWM(DTIMMemRWM),
              .DTIMAdr, .FlushW(LSUFlushW), .WriteDataM(LSUWriteDataM),
              .ReadDataWordM(DTIMReadDataWordM[P.LLEN-1:0]), .ByteMaskM(ByteMaskM));
  end else
    assign DTIMReadDataWordM = '0;
  if (P.BUS_SUPPORTED) begin : bus
    if(P.DCACHE_SUPPORTED) begin : dcache
      localparam   LLENWORDSPERLINE = P.DCACHE_LINELENINBITS/P.LLEN;             // Number of LLEN words in cacheline
      localparam   LLENLOGBWPL = $clog2(LLENWORDSPERLINE);                       // Log2 of ^
      localparam   BEATSPERLINE = P.DCACHE_LINELENINBITS/P.AHBW;                 // Number of AHBW words (beats) in cacheline
      localparam   AHBWLOGBWPL = $clog2(BEATSPERLINE);                           // Log2 of ^
      localparam   LINELEN = P.DCACHE_LINELENINBITS;                             // Number of bits in cacheline
      localparam   LLENPOVERAHBW = P.LLEN / P.AHBW;                              // Number of AHB beats in a LLEN word. AHBW cannot be larger than LLEN. (implementation limitation)
      localparam   CACHEWORDLEN = P.ZICCLSM_SUPPORTED ? 2*P.LLEN : P.LLEN;       // Width of the cache's input and output data buses.  Misaligned doubles width for fast access

      logic [LINELEN-1:0]      FetchBuffer;                                      // Temporary buffer to hold partially fetched cacheline
      logic [P.PA_BITS-1:0]    DCacheBusAdr;                                     // Cacheline address to fetch or writeback.
      logic [AHBWLOGBWPL-1:0]  BeatCount;                                        // Position within a cacheline.  ahbcacheinterface to cache
      logic                    DCacheBusAck;                                     // ahbcacheinterface completed fetch or writeback
      logic                    SelBusBeat;                                       // ahbcacheinterface selects position in cacheline with BeatCount
      logic [1:0]              CacheBusRW;                                       // Cache sends request to ahbcacheinterface
      logic [1:0]              BusRW;                                            // Uncached bus memory access
      logic                    CacheableOrFlushCacheM;                           // Memory address is cacheable or operation is a cache flush
      logic [1:0]              CacheRWM;                                         // Cache read (10), write (01), AMO (11)
      logic                    FlushDCache;                                      // Suppress d cache flush if there is an ITLB miss.
      logic                    BusCMOZero;
      logic [3:0]              CacheCMOpM;
      logic                    BusAtomic;

      if(P.ZICBOZ_SUPPORTED) begin
        assign BusCMOZero = LSUCMOpM[3] & ~CacheableM & ~ShardMaskM;
        assign CacheCMOpM = (CacheableM & ~SelHPTW & ~ShardMaskM) ? CMOpM : '0;
      end else begin
        assign BusCMOZero = 1'b0;
        assign CacheCMOpM = '0;
      end
      // SHARD: an AMO only reads here; its write goes through the store queue, so the
      // bus never sees a locked read-modify-write.
      assign BusAtomic = 1'b0;
      assign BusRW = (~CacheableM & ~SelDTIM )? LSURWMaskedM : '0;
      assign CacheableOrFlushCacheM = CacheableM | (FlushDCacheM & ~ShardMaskM);
      assign CacheRWM = (CacheableM & ~SelDTIM) ? LSURWMaskedM : '0;
      assign FlushDCache = FlushDCacheM & ~SelHPTW & ~ShardMaskM;            // exclusion-tag: lsu FlushDCacheSelHPTW

      cache #(.P(P), .PA_BITS(P.PA_BITS), .LINELEN(P.DCACHE_LINELENINBITS), .NUMSETS(P.DCACHE_WAYSIZEINBYTES*8/LINELEN),
              .NUMWAYS(P.DCACHE_NUMWAYS), .LOGBWPL(LLENLOGBWPL), .WORDLEN(CACHEWORDLEN), .MUXINTERVAL(P.LLEN), .READ_ONLY_CACHE(0)) dcache(
        .clk, .reset, .Stall(GatedStallW & ~SelSpillE), .SelBusBeat, .FlushStage(LSUFlushW),
        .CacheRW(CacheRWM),
        .FlushCache(FlushDCache), .NextSet(IEUAdrExtE[11:0]), .PAdr(PAdrM),
        .ByteMask(ByteMaskSpillM), .BeatCount(BeatCount[AHBWLOGBWPL-1:AHBWLOGBWPL-LLENLOGBWPL]),
        .WriteData(LSUWriteDataSpillM), .SelHPTW(SelHPTW | SQOwnsLSUM),
        .CacheStall(DCacheStallM), .CacheMiss(DCacheMiss), .CacheAccess(DCacheAccess),
        .CacheCommitted(DCacheCommittedM),
        .CacheBusAdr(DCacheBusAdr), .ReadDataWord(DCacheReadDataWordM),
        .FetchBuffer, .CacheBusRW(CacheBusRW),
        .CacheBusAck(DCacheBusAck), .InvalidateCache(1'b0), .InvalidateFlushStage(LSUFlushW), .CMOpM(CacheCMOpM));

      ahbcacheinterface #(.P(P), .BEATSPERLINE(BEATSPERLINE), .AHBWLOGBWPL(AHBWLOGBWPL), .LINELEN(LINELEN),  .LLENPOVERAHBW(LLENPOVERAHBW), .READ_ONLY_CACHE(0)) ahbcacheinterface(
        .HCLK(clk), .HRESETn(~reset), .Flush(LSUFlushW),
        .HRDATA, .HWDATA(LSUHWDATA), .HWSTRB(LSUHWSTRB),
        .HSIZE(LSUHSIZE), .HBURST(LSUHBURST), .HTRANS(LSUHTRANS), .HWRITE(LSUHWRITE), .HREADY(LSUHREADY),
        .BeatCount, .SelBusBeat, .CacheReadDataWordM(DCacheReadDataWordM[P.LLEN-1:0]), .WriteDataM(LSUWriteDataM),
        .Funct3(LSUFunct3M), .HADDR(LSUHADDR), .CacheBusAdr(DCacheBusAdr), .CacheBusRW, .BusAtomic, .BusCMOZero, .CacheableOrFlushCacheM,
        .CacheBusAck(DCacheBusAck), .FetchBuffer, .PAdr(PAdrM),
        .Cacheable(CacheableOrFlushCacheM), .BusRW, .Stall(GatedStallW),
        .BusStall(LSUBusStallM), .BusCommitted(BusCommittedM));

      mux3 #(P.LLEN) UnCachedDataMux(.d0(DCacheReadDataWordSpillM), .d1({LLENPOVERAHBW{FetchBuffer[P.XLEN-1:0]}}),
                                    .d2({{P.LLEN-P.XLEN{1'b0}}, DTIMReadDataWordM[P.XLEN-1:0]}),
                                    .s({SelDTIM, ~(CacheableOrFlushCacheM)}), .y(ReadDataWordMuxM));
    end else begin : passthrough
      // No Cache, use simple ahbinterface instead of ahbcacheinterface
      logic [1:0] BusRW;                    // Non-DTIM memory access, ignore cacheableM
      logic [P.XLEN-1:0] FetchBuffer;
      assign BusRW = ~SelDTIM ? LSURWMaskedM : 0;

      assign LSUHADDR = PAdrM;
      assign LSUHSIZE = LSUFunct3M;

      ahbinterface #(P.XLEN, 1'b1) ahbinterface(.HCLK(clk), .HRESETn(~reset), .Flush(LSUFlushW), .HREADY(LSUHREADY),
        .HRDATA(HRDATA), .HTRANS(LSUHTRANS), .HWRITE(LSUHWRITE), .HWDATA(LSUHWDATA),
        .HWSTRB(LSUHWSTRB), .BusRW, .BusAtomic(1'b0), .ByteMask(ByteMaskM[P.XLEN/8-1:0]), .WriteData(LSUWriteDataM[P.XLEN-1:0]),
        .Stall(GatedStallW), .BusStall(LSUBusStallM), .BusCommitted(BusCommittedM), .FetchBuffer(FetchBuffer));

    // Mux between the 2 sources of read data, 0: Bus, 1: DTIM
      if(P.DTIM_SUPPORTED) mux2 #(P.XLEN) ReadDataMux2(FetchBuffer, DTIMReadDataWordM[P.XLEN-1:0], SelDTIM, ReadDataWordMuxM[P.XLEN-1:0]);
      else assign ReadDataWordMuxM[P.XLEN-1:0] = FetchBuffer[P.XLEN-1:0];
      assign LSUHBURST = 3'b0;
      assign {DCacheStallM, DCacheCommittedM, DCacheMiss, DCacheAccess, DCacheReadDataWordM} = '0;
    end
  end else begin : nobus // block: bus, only DTIM
    assign {LSUHWDATA, LSUHADDR, LSUHWRITE, LSUHSIZE, LSUHBURST, LSUHTRANS, LSUHWSTRB} = '0;
    assign DCacheReadDataWordM = '0;
    assign ReadDataWordMuxM = DTIMReadDataWordM;
    assign {LSUBusStallM, BusCommittedM} = '0;
    assign {DCacheMiss, DCacheAccess} = '0;
    assign {DCacheStallM, DCacheCommittedM} = '0;
  end

  /////////////////////////////////////////////////////////////////////////////////////////////
  // SHARD store buffer
  /////////////////////////////////////////////////////////////////////////////////////////////

  // Classify the M-stage access.  A naturally aligned little-endian integer access maps
  // onto one store-queue entry / one merged read word.  Anything else (misaligned,
  // floating-point, big-endian, DTIM, cache-block operation, or a read of uncacheable
  // memory, which may have side effects) executes directly, on its own, once the shadow
  // has verified everything older and the store queue is empty.
  assign AlignedM = (Funct3M[1:0] == 2'b00) | ((Funct3M[1:0] == 2'b01) & ~IEUAdrM[0]) |
                    ((Funct3M[1:0] == 2'b10) & (IEUAdrM[1:0] == 2'b00)) |
                    ((Funct3M[1:0] == 2'b11) & (IEUAdrM[2:0] == 3'b000));
  assign SimpleMemOKM = AlignedM & ~FpLoadStoreM & ~BigEndianM & ~SelDTIM & ~(|CMOpM);
  assign SerialMemM = ((|MemRWM) & ~SimpleMemOKM) | (MemRWM[1] & ~CacheableM) | (|CMOpM);

  assign SQEmpty = (sqCount == '0);
  assign SQFull  = (sqCount == SQ_DEPTH[$clog2(SQ_DEPTH+1)-1:0]);
  assign ShadowQuiescentM = ShadowIdleM & SQEmpty & ~SQBusy;

  // A page table walk reads PTEs, and may write one, straight through the D-cache, so
  // it waits until no store is buffered.
  assign WalkOK = SQEmpty & ~SQBusy;

  // Hold the M-stage instruction (stall, and hide it from the cache and bus) while
  //  - it needs the shadow to be quiescent and it is not,
  //  - it is a store and the store queue is full, or
  //  - a page table walk is waiting for the store queue to empty, or
  //  - it failed a check and is about to be replayed.
  assign HoldM = ((NonMemSerialM | SerialMemM) & ~ShadowQuiescentM) | ShardPreFaultM |
                 (MemRWM[0] & SimpleMemOKM & SQFull) |
                 ((ITLBMissOrUpdateAF | DTLBMissOrUpdateDAM) & ~WalkOK);

  // Drain engine.  Modeled on the HPTW: it stalls the pipeline, takes over the LSU's
  // address/data/control inputs, and replays the head of the store queue as an ordinary
  // store (cache hit or miss, or an uncached bus write).
  //   IDLE     when the head is verified and no memory operation is in flight, hide the
  //            M-stage instruction and present the head's address so the cache reads
  //            its set (SQStart)
  //   WR       write; wait out a cache miss or the bus
  //   ADR      present the next head's address when several stores are drained in a row
  //   RESTORE  present the M-stage instruction's own address again so the cache holds
  //            the right set when that instruction resumes; skipped when it makes no
  //            cache access of its own
  assign SQStart = (SQState == SQ_IDLE) & (sqNVerified != '0) & ~CommittedM;
  assign SQRestoreM = MemRWM[1] | ((|MemRWM) & ~SimpleMemOKM) | (|CMOpM) | FlushDCacheM;
  always_comb
    case (SQState)
      SQ_IDLE:    SQNextState = SQStart ? SQ_WR : SQ_IDLE;
      SQ_ADR:     SQNextState = SQ_WR;
      SQ_WR:      if (DCacheBusStallM)      SQNextState = SQ_WR;
                  else if (sqNVerified > 1) SQNextState = SQ_ADR;
                  else if (SQRestoreM)      SQNextState = SQ_RESTORE;
                  else                      SQNextState = SQ_IDLE;
      default:    SQNextState = SQ_IDLE;
    endcase
  always_ff @(posedge clk)
    if (reset) SQState <= SQ_IDLE;
    else       SQState <= SQNextState;

  assign SQBusy     = (SQState != SQ_IDLE);
  assign SQOwnsLSUM = SQBusy | SQStart;
  assign SQDrainSel = SQStart | (SQState == SQ_ADR) | (SQState == SQ_WR);
  assign sqPop      = (SQState == SQ_WR) & ~DCacheBusStallM;

  assign ShardLSUStallM = HoldM | SQOwnsLSUM;
  assign ShardMaskM     = HoldM | SQOwnsLSUM;

  // Requests from the IEU or HPTW, overridden by the drain engine
  assign PreLSURWM    = SQDrainSel ? {1'b0, SQState == SQ_WR} : HPreLSURWM;
  assign LSUFunct3M   = SQDrainSel ? {1'b0, sqSize[0]} : HLSUFunct3M;
  assign LSUFunct7M   = SQDrainSel ? 7'b0 : HLSUFunct7M;
  assign LSUAtomicM   = SQDrainSel ? 2'b00 : HLSUAtomicM;
  assign LSUCMOpM     = SQDrainSel ? 4'b0 : HLSUCMOpM;
  assign IHAdrM       = SQDrainSel ? {{(P.XLEN+2-P.PA_BITS){1'b0}}, sqPA[0]} : HIHAdrM;
  assign IHWriteDataM = SQDrainSel ? sqData[0] : HIHWriteDataM;

  // The drained store passed its PMP/PMA checks when it executed
  assign LSULoadAccessFaultM     = MMULoadAccessFaultM & ~SQDrainSel;
  assign LSUStoreAmoAccessFaultM = MMUStoreAmoAccessFaultM & ~SQDrainSel;
  assign LSULoadPageFaultM       = MMULoadPageFaultM & ~SQDrainSel;
  assign LSUStoreAmoPageFaultM   = MMUStoreAmoPageFaultM & ~SQDrainSel;

  // The drain engine and the HPTW own the LSU while they are active.  Otherwise the
  // M-stage instruction is hidden from the cache and bus while it is held, and a queued
  // store, SC or AMO presents only its read half: just a direct (non-queued) access
  // writes memory from the Memory stage.
  always_comb
    if (SQDrainSel | SelHPTW) LSURWMaskedM = LSURWM;
    else if (ShardMaskM)      LSURWMaskedM = 2'b00;
    else                      LSURWMaskedM = {LSURWM[1], LSURWM[0] & ~SimpleMemOKM};

  // What the M-stage instruction pushes into the store queue when it leaves M (a failed
  // SC has LSURWM[0] low and pushes nothing)
  assign SQStoreM     = MemRWM[0] & SimpleMemOKM & LSURWM[0];
  assign SQPAdrM      = PAdrM;
  assign SQWriteDataM = IMAWriteDataM;

  // Store-to-load forwarding.  Accesses that cannot be merged only run with the queue
  // empty.  The merge sits in the main load path ahead of everything the shadow can
  // re-derive, so it is computed twice and the copies compared.
  shadow_sqmerge #(.P(P), .DEPTH(SQ_DEPTH)) sqmerge(.ReadDataWordM(ReadDataWordMuxM), .PAdrM,
    .sqPA, .sqSize, .sqData, .sqCount, .ReadDataWordFwdM);
  shadow_sqmerge #(.P(P), .DEPTH(SQ_DEPTH)) sqmergecheck(.ReadDataWordM(ReadDataWordMuxM), .PAdrM,
    .sqPA, .sqSize, .sqData, .sqCount, .ReadDataWordFwdM(ReadDataWordFwdCheckM));
  assign LoadFwdFaultM = MemRWM[1] & ~SQOwnsLSUM & (ReadDataWordFwdM != ReadDataWordFwdCheckM);

  // The shadow re-derives every integer load from this word with its own subword extract
  assign RawReadDataWordM = ReadDataWordFwdM[P.XLEN-1:0];

  // SHARD independent AMO verification.  A second, separate amoalu instance recomputes
  // the atomic result from the same operands the main amoalu used.  The shadow verifies
  // a queued AMO again from its own operands; this local check also covers an AMO that
  // writes memory directly, and stops a bad one before it leaves the Memory stage.
  if (P.ZAAMO_SUPPORTED) begin : shadow_amo
    logic [P.XLEN-1:0] ShadowAMOResultM;
    amoalu #(P) shadow_amoalu(.ReadDataM(ReadDataM[P.XLEN-1:0]), .IHWriteDataM,
                              .LSUFunct7M, .LSUFunct3M, .AMOResultM(ShadowAMOResultM));
    assign AMOFaultM = LSUAtomicM[1] & (ShadowAMOResultM != IMAWriteDataM);
  end else begin : no_shadow_amo
    assign AMOFaultM = 1'b0;
  end

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Atomic operations
  /////////////////////////////////////////////////////////////////////////////////////////////

  if (P.ZAAMO_SUPPORTED | P.ZALRSC_SUPPORTED) begin : atomic
    atomic #(P) atomic(.clk, .reset, .StallW, .ShardRedirectM, .ReadDataM(ReadDataM[P.XLEN-1:0]), .IHWriteDataM, .PAdrM,
      .LSUFunct7M, .LSUFunct3M, .LSUAtomicM, .PreLSURWM, .LSUFlushW,
      .IMAWriteDataM, .SquashSCW, .LSURWM);
  end else begin : lrsc
    assign SquashSCW = 1'b0;
    assign LSURWM = PreLSURWM;
    assign IMAWriteDataM = IHWriteDataM;
  end

  if (P.F_SUPPORTED)
    if (P.FLEN >= P.XLEN)
      mux2 #(P.LLEN) datamux({{{P.LLEN-P.XLEN}{1'b0}}, IMAWriteDataM}, FWriteDataM, FpLoadStoreM & ~SQDrainSel, IMAFWriteDataM);
    else
      mux2 #(P.LLEN) datamux(IMAWriteDataM, {{{P.XLEN-P.FLEN}{1'b0}}, FWriteDataM}, FpLoadStoreM & ~SQDrainSel, IMAFWriteDataM);

  else assign IMAFWriteDataM = IMAWriteDataM;

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Subword Accesses
  /////////////////////////////////////////////////////////////////////////////////////////////

  subwordread #(P) subwordread(.ReadDataWordMuxM(LittleEndianReadDataWordM), .PAdrM(PAdrM[3:0]), .BigEndianM,
    .FpLoadStoreM, .Funct3M(LSUFunct3M), .ReadDataM);
  subwordwrite #(P.LLEN) subwordwrite(.LSUFunct3M, .IMAFWriteDataM, .LittleEndianWriteDataM);

  // Compute byte masks
  swbytemask #(P.LLEN, P.ZICCLSM_SUPPORTED) swbytemask(.Size(LSUFunct3M), .Adr(PAdrM[$clog2(P.LLEN/8)-1:0]), .ByteMask(ByteMaskM), .ByteMaskExtended(ByteMaskExtendedM));

  /////////////////////////////////////////////////////////////////////////////////////////////
  // MW Pipeline Register
  /////////////////////////////////////////////////////////////////////////////////////////////

  flopen #(P.LLEN) ReadDataMWReg(clk, ~StallW, ReadDataM, ReadDataW);

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Big Endian Byte Swapper
  //  hart works little-endian internally
  //  swap the bytes when read from big-endian memory
  /////////////////////////////////////////////////////////////////////////////////////////////

  if (P.BIGENDIAN_SUPPORTED) begin : endian
    endianswap #(P.LLEN) storeswap(.BigEndianM, .a(LittleEndianWriteDataM), .y(LSUWriteDataM));
    endianswap #(P.LLEN) loadswap(.BigEndianM, .a(ReadDataWordFwdM), .y(LittleEndianReadDataWordM));
  end else begin
    assign LSUWriteDataM = LittleEndianWriteDataM;
    assign LittleEndianReadDataWordM = ReadDataWordFwdM;
  end
endmodule
```

---

## 8. Hazard unit and instruction fetch

### 8.1 `hazard.sv`

Two new inputs. The redirect is a flush cause for all four stages; the SHARD stall
is a `StallWCause` term that yields to flushes like every other.

```systemverilog
  input  logic  ShardRedirectM,       // recovery/retry: flush the whole pipeline and refetch
  input  logic  ShardStallW,          // queues nearly full, or the Memory stage awaits a replay
  ...
  assign FlushDCause = TrapM | RetM | CSRWriteFenceM | BPWrongE | ShardRedirectM;
  assign FlushECause = TrapM | RetM | CSRWriteFenceM |(BPWrongE & ~(DivBusyE | FDivBusyE)) | ShardRedirectM;
  assign FlushMCause = TrapM | RetM | CSRWriteFenceM | ShardRedirectM;
  assign FlushWCause = (TrapM & ~WFIInterruptedM) | ShardRedirectM;
  ...
  assign StallMCause = WFIStallM & ~FlushMCause;
  assign StallWCause = (IFUStallF & ~FlushDCause) | (LSUStallM & ~FlushWCause) | ExternalStall
                    | (ShardStallW & ~FlushWCause);
```

`ShardStallW = ShardBackpressureW | ShardLocalFaultM` (§11). The holds of §7.2 and
the drain engine arrive through `LSUStallM`. A redirect "flushes W" in the same
sense a trap does: the M→W register loads a bubble. An instruction already in W
has retired into the queues and is not affected.

```systemverilog
module hazard (
  input  logic  BPWrongE, CSRWriteFenceM, RetM, TrapM,
  input  logic  StructuralStallD,
  input  logic  LSUStallM, IFUStallF,
  input  logic  FPUStallD, ExternalStall,
  input  logic  DivBusyE, FDivBusyE,
  input  logic  ShardRedirectM,       // SHARD recovery/retry: flush the whole pipeline and refetch
  input  logic  ShardStallW,          // SHARD: the shadow's queues are nearly full, or the Memory stage awaits a replay
  input  logic  wfiM, IntPendingM,
  input  logic  InjectD,
  // Stall & flush outputs
  output logic StallF, StallD, StallE, StallM, StallW,
  output logic FlushD, FlushE, FlushM, FlushW
);

  logic                                       StallFCause, StallDCause, StallECause, StallMCause, StallWCause;
  logic                                       LatestUnstalledD, LatestUnstalledE, LatestUnstalledM, LatestUnstalledW;
  logic                                       FlushDCause, FlushECause, FlushMCause, FlushWCause;

  logic WFIStallM, WFIInterruptedM;

  // WFI logic
  assign WFIStallM = wfiM & ~IntPendingM;         // WFI waiting for an interrupt or timeout
  assign WFIInterruptedM = wfiM & IntPendingM;    // WFI detects a pending interrupt.  Retire WFI; trap if interrupt is enabled.

  // stalls and flushes
  // loads: stall for one cycle if the subsequent instruction depends on the load
  // branches and jumps: flush the next two instructions if the branch is taken in EXE
  // CSR Writes: stall all instructions after the CSR until it completes, except that PC must change when branch is resolved
  //             this also applies to other privileged instructions such as M/S/URET, ECALL/EBREAK
  // Exceptions: flush entire pipeline
  // Ret instructions: occur in M stage.  Might be possible to move earlier, but be careful about hazards

  // General stall and flush rules:
  // A stage must stall if the next stage is stalled
  // If any stages are stalled, the first stage that isn't stalled must flush.

  // Flush causes
  // Traps (TrapM) flush the entire pipeline.
  //   However, breakpoint and ecall traps must finish the writeback stage (commit their results) because these instructions complete before trapping.
  // Trap returns (RetM) also flush the entire pipeline after the RetM (all stages except W) because all the subsequent instructions must be discarded.
  // Similarly, CSR writes and fences flush all subsequent instructions and refetch them in light of the new operating modes and cache/TLB contents
  // Branch misprediction is found in the Execute stage and must flush the next two instructions.
  //   However, an active division operation resides in the Execute stage, and when the BP incorrectly mispredicts the divide as a taken branch, the divide must still complete
  // When a WFI is interrupted and causes a trap, it flushes the rest of the pipeline but not the W stage, because the WFI needs to commit
  // SHARD: a redirect (replay after a detected fault) flushes every stage like a trap.
  // The Writeback stage holds an instruction that already retired into the shadow's
  // queues; the redirect only clears what would have followed it.
  assign FlushDCause = TrapM | RetM | CSRWriteFenceM | BPWrongE | ShardRedirectM;
  assign FlushECause = TrapM | RetM | CSRWriteFenceM |(BPWrongE & ~(DivBusyE | FDivBusyE)) | ShardRedirectM;
  assign FlushMCause = TrapM | RetM | CSRWriteFenceM | ShardRedirectM;
  assign FlushWCause = (TrapM & ~WFIInterruptedM) | ShardRedirectM;

  // Stall causes
  //  Most data dependency stalls are identified in the decode stage
  //  Division stalls in the execute stage
  //  Flushing any stage has priority over the corresponding stage stall.
  //    Even if the register gave clear priority over enable, various FSMs still need to disable the stall, so it's best to gate the stall here with flush
  //  The IFU and LSU stall the entire pipeline on a cache miss, bus access, or other long operation.
  //    The IFU stalls the entire pipeline rather than just Fetch to avoid complications with instructions later in the pipeline causing Exceptions
  //    A trap could be asserted at the start of a IFU/LSU stall, and should flush the memory operation
  assign StallFCause = 1'b0;
  // AMOEBA: a dummy instruction insertion holds Decode for one cycle so the real
  // instruction is replayed, while Execute accepts the injected instruction below.
  assign StallDCause = (StructuralStallD | FPUStallD | InjectD) & ~FlushDCause;
  assign StallECause = (DivBusyE | FDivBusyE) & ~FlushECause;
  assign StallMCause = WFIStallM & ~FlushMCause;
  // Need to gate IFUStallF when the equivalent FlushFCause = FlushDCause = 1.
  // assign StallWCause = ((IFUStallF & ~FlushDCause) | LSUStallM) & ~FlushWCause;
  // Because FlushWCause is a strict subset of FlushDCause, FlushWCause is factored out.
  // Use normal backward stall propagation to freeze F through W.
  // SHARD: freeze the pipeline while the shadow's queues are nearly full, and hold an
  // instruction that failed a Memory-stage check until its replay redirect.  The stall
  // is not needed for an instruction to reach the shadow -- the Writeback stage pushes
  // its result regardless of StallW -- so the shadow always drains and releases it.
  assign StallWCause = (IFUStallF & ~FlushDCause) | (LSUStallM & ~FlushWCause) | ExternalStall
                    | (ShardStallW & ~FlushWCause);

  // Stall each stage for cause or if the next stage is stalled
  // coverage off: StallFCause is always 0
  assign StallF = StallFCause | StallD;
  // coverage on
  assign StallD = StallDCause | StallE;
  assign StallE = StallECause | StallM;
  assign StallM = StallMCause | StallW;
  assign StallW = StallWCause;

  // detect the first stage that is not stalled

  assign LatestUnstalledD = ~StallD & StallF; // coverage tag: StallD always equals StallF
  // AMOEBA: Decode stalling while Execute advances normally inserts a bubble into Execute.
  // During an insertion that slot carries the dummy instruction instead, so suppress the flush.
  assign LatestUnstalledE = ~StallE & StallD & ~InjectD;
  assign LatestUnstalledM = ~StallM & StallE;
  assign LatestUnstalledW = ~StallW & StallM;

  // Each stage flushes if the previous stage is the last one stalled (for cause) or the system has reason to flush
  assign FlushD = LatestUnstalledD | FlushDCause; // coverage tag: LatestUnstalledD always 0
  assign FlushE = LatestUnstalledE | FlushECause;
  assign FlushM = LatestUnstalledM | FlushMCause;
  assign FlushW = LatestUnstalledW | FlushWCause;
endmodule
```

### 8.2 `ifu.sv`

One mux after the trap/return mux, with priority over everything except reset:

```systemverilog
  input  logic                 ShardRedirectM,
  input  logic [P.XLEN-1:0]    ShardRedirectPCM,
  ...
  mux3 #(P.XLEN) pcmux3(PC2NextF, EPCM, TrapVectorM, {TrapM, RetM}, PC3NextF);
  mux2 #(P.XLEN) pcmuxshard(PC3NextF, ShardRedirectPCM, ShardRedirectM, UnalignedPCNextF);
```

Nothing else in the IFU changes. The redirect PC register is loaded because the
redirect clears every stall cause, so `StallF = 0` in that cycle.

---

## 9. Privileged unit

### 9.1 `trap.sv` — traps wait for the shadow; cause 16

```systemverilog
  input  logic  ShadowFaultTrapM,        // SHARD: an unrecovered fault presented as an exception
  output logic  ShadowFaultTrapTakenM,   // cause 16 selected and accepted
  input  logic  ShadowQuiescentM,
  output logic  TrapPendingM,            // a trap is ready and waits only for the shadow
  ...
  assign ExceptionM = ... | HardwareErrorFaultM | ShadowFaultTrapM;
  assign TrapPendingM = (ExceptionM & ~CommittedF) | InterruptM;
  assign TrapM = TrapPendingM & ShadowQuiescentM;
  assign ShadowFaultTrapTakenM = TrapM & ~InterruptM & (CauseM == 5'd16);
```
and in the cause priority chain, immediately after the interrupt entries and before
every other exception:
```systemverilog
    else if (ShadowFaultTrapM)                                CauseM = 5'd16;
```

A trap rewrites `mepc`/`mcause`/`mstatus` and the privilege mode, none of which can
be rolled back, so it is taken only when nothing older is unverified.
`TrapPendingM` is ORed into `NonMemSerialM`, so the pipeline is held (and the
M-stage instruction hidden from memory) until then.

Two details:
- `TrapPendingM` must be a **direct stall**, not something that waits for a
  convenient cycle. The HPTW presents a page fault for exactly one cycle (its
  `FAULT` state) with its own stall low. If the trap cannot be taken in that cycle
  and nothing else stalls, the faulting instruction leaves M untrapped. With the
  stall, the walker returns to `IDLE`, the TLB still misses, the walk repeats, and
  the fault is presented again — by which time the shadow has caught up.
- Cause 16 is ≥ 16, so the existing `DelegateM` expression (`~CauseM[4]`) never
  delegates it: it always goes to M-mode. It sits *above* the M-stage
  instruction's own exceptions because that instruction is not trusted.

Exact change to `hdl/core/privileged/trap.sv`, as a unified diff against the tree before Rev 8 (`-` lines are what was there: stock AMOEBA Wally, plus the Rev 7 detect-only hooks where shown):

```diff
--- a/hdl/core/privileged/trap.sv
+++ b/hdl/core/privileged/trap.sv
@@ -34,6 +34,8 @@ module trap import cvw::*;  #(parameter cvw_t P) (
   input  logic                 LoadAccessFaultM, StoreAmoAccessFaultM, EcallFaultM, InstrPageFaultM,
   input  logic                 LoadPageFaultM, StoreAmoPageFaultM,              // various trap sources
   input  logic                 HardwareErrorFaultM,                             // IEU ECC DED — uncorrectable hardware error
+  input  logic                 ShadowFaultTrapM,                                // SHARD: a fault persisted through its retries, or cannot be replayed
+  output logic                 ShadowFaultTrapTakenM,                           // cause 16 selected and accepted
   input  logic                 wfiM, wfiW,                                      // wait for interrupt instruction
   input  logic [1:0]           PrivilegeModeW,                                  // current privilege mode
   input  logic [11:0]          MIP_REGW, MIE_REGW, MIDELEG_REGW,                // interrupt pending, enabled, and delegate CSRs
@@ -41,6 +43,8 @@ module trap import cvw::*;  #(parameter cvw_t P) (
   input  logic                 STATUS_MIE, STATUS_SIE,                          // machine/supervisor interrupt enables
   input  logic                 InstrValidM,                                     // current instruction is valid, not flushed
   input  logic                 CommittedM, CommittedF,                          // LSU/IFU has committed to a bus operation that can't be interrupted
+  input  logic                 ShadowQuiescentM,                                // SHARD: every retired instruction is verified and committed
+  output logic                 TrapPendingM,                                    // SHARD: a trap is ready and waits only for the shadow
   output logic                 TrapM,                                           // Trap is occurring
   output logic                 InterruptM,                                      // Interrupt is occurring
   output logic                 ExceptionM,                                      // exception is occurring
@@ -92,10 +96,15 @@ module trap import cvw::*;  #(parameter cvw_t P) (
                       BothInstrPageFaultM | LoadPageFaultM | StoreAmoPageFaultM |
                       BreakpointFaultM | EcallFaultM |
                       LoadAccessFaultM | StoreAmoAccessFaultM |
-                      HardwareErrorFaultM;
+                      HardwareErrorFaultM | ShadowFaultTrapM;
   // coverage on
-  assign TrapM = (ExceptionM & ~CommittedF) | InterruptM;
+  // SHARD: a trap changes privileged state that cannot be rolled back, so it is taken
+  // only once the shadow has verified and committed every older instruction.  Until
+  // then the trapping instruction is held in the Memory stage (see the LSU's HoldM).
+  assign TrapPendingM = (ExceptionM & ~CommittedF) | InterruptM;
+  assign TrapM = TrapPendingM & ShadowQuiescentM;
   assign HardwareErrorTrapM = TrapM & ~InterruptM & (CauseM == 5'd19);
+  assign ShadowFaultTrapTakenM = TrapM & ~InterruptM & (CauseM == 5'd16);
 
   ///////////////////////////////////////////
   // Cause priority defined in privileged spec
@@ -113,6 +122,9 @@ module trap import cvw::*;  #(parameter cvw_t P) (
     else if (ValidIntsM[9])                                   CauseM = 5'd9;  // delegated Supervisor External Int
     else if (ValidIntsM[1])                                   CauseM = 5'd1;  // delegated Supervisor Sw Int
     else if (ValidIntsM[5])                                   CauseM = 5'd5;  // delegated Supervisor Timer Int
+    // SHARD fault: whatever sits in the Memory stage is not trusted, so this outranks
+    // every exception that instruction might raise
+    else if (ShadowFaultTrapM)                                CauseM = 5'd16;
     else if (BothInstrPageFaultM)                             CauseM = 5'd12;
     else if (BothInstrAccessFaultM)                           CauseM = 5'd1;
     else if (IllegalInstrFaultM)                              CauseM = 5'd2;
```

### 9.2 `privdec.sv` — an xRET must not act in the cycle it is flushed

```systemverilog
  input  logic         ShardRedirectM,
  ...
  assign sretM = PrivilegedM & (InstrM[31:20] == 12'b000100000010) & rs1zeroM & P.S_SUPPORTED &
                 (PrivilegeModeW == P.M_MODE | PrivilegeModeW == P.S_MODE & ~STATUS_TSR) & ~ShardRedirectM;
  assign mretM = PrivilegedM & (InstrM[31:20] == 12'b001100000010) & rs1zeroM &
                 (PrivilegeModeW == P.M_MODE) & ~ShardRedirectM;
```
An `mret` can be sitting in M, held, when a shadow fault on an older instruction
redirects the pipeline. In the redirect cycle `StallW = 0`, and `mretM` is not
gated by `FlushW` (W3): without the mask it would change the privilege mode and
`mstatus` as it is being squashed.

### 9.3 `csr.sv` — the CSR checks and the cause-16 metadata

Ports added: `ForwardedSrcAM`, `ShadowFaultEPCM`, `ShadowFaultMtvalM` (inputs);
`CSRFaultM`, `CSRStateFaultM` (outputs); `CSRMirrorResyncM` (input).

Cause-16 metadata, next to the existing cause-19 handling:
```systemverilog
      16:                     NextFaultMtvalM = ShadowFaultMtvalM;
  ...
  assign UnalignedNextEPCM = TrapM ? ((CauseM == 5'd19) ? EccDedFaultEPCM :
                                      (CauseM == 5'd16) ? ShadowFaultEPCM : PCM) : CSRWriteValM;
```
(Without the AMOEBA cause-19 logic this is `TrapM ? ((CauseM == 5'd16) ?
ShadowFaultEPCM : PCM) : CSRWriteValM`.)

The checks:
```systemverilog
  // The checking side takes rs1 from ForwardedSrcAM, a different register from the
  // main CSR datapath's SrcAM, and the one compared with the register file.
  assign ShadowCSRSrcM = InstrM[14] ? {{(P.XLEN-5){1'b0}}, InstrM[19:15]} : ForwardedSrcAM;

  shadow_csr #(P) shadowcsr(.clk, .reset, .StallW,
    .CSRWriteCommitM(CSRWriteM & InstrValidNotFlushedM), .CSRAdrM, .CSROpM(InstrM[13:12]), .CSRSrcM(ShadowCSRSrcM),
    .TrapM, .InterruptM, .CauseM, .mretM, .sretM, .PCM, .EccDedFaultEPCM, .ShadowFaultEPCM,
    .NextFaultMtvalM, .FSDirtyM(FRegWriteM | WriteFRMM | SetOrWriteFFLAGSM), .Resync(CSRMirrorResyncM),
    .PrivilegeModeW, .MSTATUS_REGW, .MSTATUSH_REGW, .MEDELEG_REGW, .MIDELEG_REGW,
    .MTVEC_REGW, .MSCRATCH_REGW, .MEPC_REGW, .MCAUSE_REGW, .MTVAL_REGW,
    .STVEC_REGW, .SSCRATCH_REGW, .SEPC_REGW, .SCAUSE_REGW, .STVAL_REGW, .SATP_REGW,
    .MirrorHitM, .MirrorReadValM, .StateFault(CSRStateFaultM));

  assign ShadowCSROldValM = MirrorHitM ? MirrorReadValM : CSRReadVal2M;
  always_comb
    case (InstrM[13:12])
      2'b01:   ShadowCSRWriteValM = ShadowCSRSrcM;                     // csrrw[i]
      2'b10:   ShadowCSRWriteValM = ShadowCSROldValM | ShadowCSRSrcM;  // csrrs[i]
      2'b11:   ShadowCSRWriteValM = ShadowCSROldValM & ~ShadowCSRSrcM; // csrrc[i]
      default: ShadowCSRWriteValM = CSRReadValM;
    endcase
  // An illegal access traps instead of committing, so it is not checked
  assign CSRFaultM = InstrValidM & ~IllegalCSRAccessM &
                     ((CSRReadM & MirrorHitM & (MirrorReadValM != CSRReadValM)) |
                      (CSRWriteM & (ShadowCSRWriteValM != CSRWriteValM)));
```

- **Read check**: for a mirrored CSR, the value the instruction reads must equal
  the mirror's.
- **Write check**: the value about to be written must equal one recomputed by a
  second csrrw/csrrs/csrrc datapath, using the mirror's old value where there is
  one (otherwise the main read value — then only the modify datapath is
  duplicated), and using `ForwardedSrcAM` rather than the main CSR path's `SrcAM`.
  `ForwardedSrcAM` is the register the Memory-stage operand check compares with
  the regfile (§11), so the write source is verified end to end.
- `CSRFaultM` is combinational on stable M-stage state. It must be gated by
  `InstrValidM` only — **not** by `~StallW`/`~FlushW` (§14, P4).
- `IllegalCSRAccessM` gating: an illegal access reads 0 from the main CSR mux and
  then traps; comparing it with the mirror would turn a legitimate
  illegal-instruction trap into a SHARD fault.
- `FRegWriteM` into `csr` is `FRegWriteM & ~ShardRedirectM` (connected that way in
  `privileged.sv`), so a squashed FP instruction does not mark `mstatus.FS` dirty
  in one copy only.

`csrm.sv` and `csrs.sv` only gain output ports for registers that were internal,
so the mirror can be compared with them: `MSCRATCH_REGW`, `MTVAL_REGW`,
`MCAUSE_REGW` from `csrm`; `SSCRATCH_REGW`, `STVAL_REGW`, `SCAUSE_REGW` from `csrs`
(assigned 0 in `csr.sv` when there is no supervisor mode).

Exact change to `hdl/core/privileged/csr.sv`, as a unified diff against the tree before Rev 8 (`-` lines are what was there: stock AMOEBA Wally, plus the Rev 7 detect-only hooks where shown):

```diff
--- a/hdl/core/privileged/csr.sv
+++ b/hdl/core/privileged/csr.sv
@@ -38,6 +38,7 @@ module csr import cvw::*;  #(parameter cvw_t P) (
   input  logic [P.XLEN-1:0]        PCM,                       // program counter, next PC going to trap/return logic
   input  logic [P.XLEN-1:0]        PCSpillM,                  // program counter, next PC going to trap/return logic aligned after an instruction spill
   input  logic [P.XLEN-1:0]        SrcAM, IEUAdrxTvalM,       // SrcA and memory address from IEU
+  input  logic [P.XLEN-1:0]        ForwardedSrcAM,            // SHARD: rs1 value on the path that is checked against the register file
   input  logic                     CSRReadM, CSRWriteM,       // read or write CSR
   input  logic                     PrivModeSecFaultW,         // TMR correctable fault from privmode
   input  logic                     PrivModeUncorrectableFaultW, // TMR uncorrectable fault from privmode
@@ -45,6 +46,7 @@ module csr import cvw::*;  #(parameter cvw_t P) (
   input  logic                     RegEccDedErrW,             // IEU ECC DED, retained for MSECFAULT logging
   input  logic                     ShadowFaultW,              // SHARD shadow pipeline mismatch
   input  logic [P.XLEN-1:0]        EccDedFaultEPCM, EccDedFaultMtvalM, // captured DED trap metadata
+  input  logic [P.XLEN-1:0]        ShadowFaultEPCM, ShadowFaultMtvalM, // captured SHARD fault trap metadata
   input  logic                     TrapM,                     // trap is occurring
   input  logic                     mretM, sretM,              // return instruction
   input  logic                     InterruptM,                // interrupt is occurring
@@ -100,7 +102,9 @@ module csr import cvw::*;  #(parameter cvw_t P) (
   output logic [P.XLEN-1:0]        CSRReadValW,               // value read from CSR
   output logic                     IllegalCSRAccessM,         // Illegal CSR access: CSR doesn't exist or is inaccessible at this privilege level
   output logic                     BigEndianM,                // memory access is big-endian based on privilege mode and STATUS register endian fields
-  output logic                     CSRFaultM,                 // Rev 7: SHARD — shadow CSR write-value recompute disagrees with main
+  output logic                     CSRFaultM,                 // SHARD: CSR instruction's read or write value fails verification
+  output logic                     CSRStateFaultM,            // SHARD: CSR mirror differs from the CSR file
+  input  logic                     CSRMirrorResyncM,          // SHARD: reload the CSR mirror after reporting a state fault
   output logic [31:0]              RAND_INSTR_INSERT_FREQ_REGW // AMOEBA: dummy instruction insertion divider period
 );
 
@@ -115,6 +119,7 @@ module csr import cvw::*;  #(parameter cvw_t P) (
   logic [P.XLEN-1:0]       MSTATUS_REGW, SSTATUS_REGW, MSTATUSH_REGW;
   logic [P.XLEN-1:0]       STVEC_REGW, MTVEC_REGW;
   logic [P.XLEN-1:0]       MEPC_REGW, SEPC_REGW;
+  logic [P.XLEN-1:0]       MSCRATCH_REGW, MTVAL_REGW, MCAUSE_REGW, SSCRATCH_REGW, STVAL_REGW, SCAUSE_REGW;
   logic [31:0]             MCOUNTINHIBIT_REGW, MCOUNTEREN_REGW, SCOUNTEREN_REGW;
   logic                    WriteMSTATUSM, WriteMSTATUSHM, WriteSSTATUSM;
   logic                    CSRMWriteM, CSRSWriteM, CSRUWriteM;
@@ -156,6 +161,8 @@ module csr import cvw::*;  #(parameter cvw_t P) (
       0, 4, 6, 13, 15, 5, 7:  NextFaultMtvalM = IEUAdrxTvalM; // Instruction misaligned, Load/Store Misaligned/page/access faults
       // Hardware error (ECC DED): use metadata captured when the error was detected.
       19:                     NextFaultMtvalM = EccDedFaultMtvalM;
+      // SHARD fault: which checks failed
+      16:                     NextFaultMtvalM = ShadowFaultMtvalM;
       default:                NextFaultMtvalM = '0; // Ecall, interrupts
     endcase
 
@@ -208,21 +215,45 @@ module csr import cvw::*;  #(parameter cvw_t P) (
   end
 
   ///////////////////////////////////////////
-  // Rev 7: SHARD independent CSR write-value verification.
-  // A separate replica of the csrrw/csrrs/csrrc modify+select datapath recomputes the
-  // value to be written from the same old-value (CSRReadVal2M) and source (CSRSrcM); a
-  // disagreement on a committing CSR write (transient fault in one copy) raises CSRFaultM.
-  // This verifies the CSR ALU datapath without a full CSR-state mirror.
+  // SHARD CSR verification.
+  // shadow_csr holds an independent copy of the trap-handling and translation CSRs.
+  // Before a CSR instruction commits:
+  //  - the value it read must equal the mirror's (mirrored CSRs), and
+  //  - the value it is about to write must equal one recomputed by a second copy of
+  //    the csrrw/csrrs/csrrc datapath, from the mirror's old value where there is one.
+  // The source operand was checked against the register file before this point (CSR
+  // writes wait for the shadow to be quiescent).  A mismatch makes the instruction
+  // replay instead of committing.  In addition the mirror compares its whole state
+  // with the CSR file every cycle (CSRStateFaultM).
   ///////////////////////////////////////////
-  logic [P.XLEN-1:0] ShadowCSRWriteValM;
+  logic [P.XLEN-1:0] ShadowCSRSrcM, ShadowCSROldValM, ShadowCSRWriteValM, MirrorReadValM;
+  logic              MirrorHitM;
+
+  // The checking side takes rs1 from ForwardedSrcAM, a different register from the
+  // main CSR datapath's SrcAM, and the one compared with the register file.
+  assign ShadowCSRSrcM = InstrM[14] ? {{(P.XLEN-5){1'b0}}, InstrM[19:15]} : ForwardedSrcAM;
+
+  shadow_csr #(P) shadowcsr(.clk, .reset, .StallW,
+    .CSRWriteCommitM(CSRWriteM & InstrValidNotFlushedM), .CSRAdrM, .CSROpM(InstrM[13:12]), .CSRSrcM(ShadowCSRSrcM),
+    .TrapM, .InterruptM, .CauseM, .mretM, .sretM, .PCM, .EccDedFaultEPCM, .ShadowFaultEPCM,
+    .NextFaultMtvalM, .FSDirtyM(FRegWriteM | WriteFRMM | SetOrWriteFFLAGSM), .Resync(CSRMirrorResyncM),
+    .PrivilegeModeW, .MSTATUS_REGW, .MSTATUSH_REGW, .MEDELEG_REGW, .MIDELEG_REGW,
+    .MTVEC_REGW, .MSCRATCH_REGW, .MEPC_REGW, .MCAUSE_REGW, .MTVAL_REGW,
+    .STVEC_REGW, .SSCRATCH_REGW, .SEPC_REGW, .SCAUSE_REGW, .STVAL_REGW, .SATP_REGW,
+    .MirrorHitM, .MirrorReadValM, .StateFault(CSRStateFaultM));
+
+  assign ShadowCSROldValM = MirrorHitM ? MirrorReadValM : CSRReadVal2M;
   always_comb
     case (InstrM[13:12])
-      2'b01:   ShadowCSRWriteValM = CSRSrcM;                 // csrrw[i]
-      2'b10:   ShadowCSRWriteValM = CSRReadVal2M | CSRSrcM;  // csrrs[i]
-      2'b11:   ShadowCSRWriteValM = CSRReadVal2M & ~CSRSrcM; // csrrc[i]
+      2'b01:   ShadowCSRWriteValM = ShadowCSRSrcM;                     // csrrw[i]
+      2'b10:   ShadowCSRWriteValM = ShadowCSROldValM | ShadowCSRSrcM;  // csrrs[i]
+      2'b11:   ShadowCSRWriteValM = ShadowCSROldValM & ~ShadowCSRSrcM; // csrrc[i]
       default: ShadowCSRWriteValM = CSRReadValM;
     endcase
-  assign CSRFaultM = CSRWriteM & InstrValidNotFlushedM & (ShadowCSRWriteValM != CSRWriteValM);
+  // An illegal access traps instead of committing, so it is not checked
+  assign CSRFaultM = InstrValidM & ~IllegalCSRAccessM &
+                     ((CSRReadM & MirrorHitM & (MirrorReadValM != CSRReadValM)) |
+                      (CSRWriteM & (ShadowCSRWriteValM != CSRWriteValM)));
 
   ///////////////////////////////////////////
   // CSR Write values
@@ -230,7 +261,9 @@ module csr import cvw::*;  #(parameter cvw_t P) (
 
   assign CSRAdrM = InstrM[31:20];
   // A registered DED record supplies MEPC only when cause 19 actually wins trap priority.
-  assign UnalignedNextEPCM = TrapM ? ((CauseM == 5'd19) ? EccDedFaultEPCM : PCM) : CSRWriteValM;
+  // Likewise a SHARD fault trap reports the instruction that failed verification.
+  assign UnalignedNextEPCM = TrapM ? ((CauseM == 5'd19) ? EccDedFaultEPCM :
+                                      (CauseM == 5'd16) ? ShadowFaultEPCM : PCM) : CSRWriteValM;
   assign NextEPCM = P.ZCA_SUPPORTED ? {UnalignedNextEPCM[P.XLEN-1:1], 1'b0} : {UnalignedNextEPCM[P.XLEN-1:2], 2'b00}; // 3.1.15 alignment
   assign NextCauseM = TrapM ? {InterruptM, CauseM}: {CSRWriteValM[P.XLEN-1], CSRWriteValM[4:0]};
   assign NextMtvalM = TrapM ? NextFaultMtvalM : CSRWriteValM;
@@ -273,7 +306,7 @@ module csr import cvw::*;  #(parameter cvw_t P) (
     .UngatedCSRMWriteM, .CSRMWriteM, .MTrapM, .CSRAdrM,
     .NextEPCM, .NextCauseM, .NextMtvalM, .MSTATUS_REGW, .MSTATUSH_REGW,
     .CSRWriteValM, .CSRMReadValM, .MTVEC_REGW,
-    .MEPC_REGW, .MCOUNTEREN_REGW, .MCOUNTINHIBIT_REGW,
+    .MEPC_REGW, .MSCRATCH_REGW, .MTVAL_REGW, .MCAUSE_REGW, .MCOUNTEREN_REGW, .MCOUNTINHIBIT_REGW,
     .MEDELEG_REGW, .MIDELEG_REGW,.PMPCFG_ARRAY_REGW, .PMPADDR_ARRAY_REGW,
     .MIP_REGW, .MIE_REGW, .SecFaultM, .WriteMSTATUSM, .WriteMSTATUSHM,
     .IllegalCSRMAccessM, .IllegalCSRMWriteReadonlyM,
@@ -288,7 +321,7 @@ module csr import cvw::*;  #(parameter cvw_t P) (
       .NextEPCM, .NextCauseM, .NextMtvalM, .SSTATUS_REGW,
       .STATUS_TVM,
       .CSRWriteValM, .PrivilegeModeW,
-      .CSRSReadValM, .STVEC_REGW, .SEPC_REGW,
+      .CSRSReadValM, .STVEC_REGW, .SEPC_REGW, .SSCRATCH_REGW, .STVAL_REGW, .SCAUSE_REGW,
       .SCOUNTEREN_REGW,
       .SATP_REGW, .MIP_REGW, .MIE_REGW, .MIDELEG_REGW, .MTIME_CLINT, .STCE,
       .WriteSSTATUSM, .IllegalCSRSAccessM, .STimerInt, .SENVCFG_REGW);
@@ -296,6 +329,7 @@ module csr import cvw::*;  #(parameter cvw_t P) (
     assign WriteSSTATUSM = 1'b0;
     assign CSRSReadValM = '0;
     assign SEPC_REGW = '0;
+    assign {SSCRATCH_REGW, STVAL_REGW, SCAUSE_REGW} = '0;
     assign STVEC_REGW = '0;
     assign SCOUNTEREN_REGW = '0;
     assign SATP_REGW = '0;
```

### 9.4 `privileged.sv`

Passes the new signals through: inputs `ForwardedSrcAM`, `ShadowQuiescentM`,
`ShardRedirectM`, `ShadowFaultTrapM`, `ShadowFaultEPCM`, `ShadowFaultMtvalM`,
`CSRMirrorResyncM`; outputs `TrapPendingM`, `ShadowFaultTrapTakenM`, `CSRFaultM`,
`CSRStateFaultM`. `privdec` gets `ShardRedirectM`; `csr` gets
`.FRegWriteM(FRegWriteM & ~ShardRedirectM)`.

Exact change to `hdl/core/privileged/privileged.sv`, as a unified diff against the tree before Rev 8 (`-` lines are what was there: stock AMOEBA Wally, plus the Rev 7 detect-only hooks where shown):

```diff
--- a/hdl/core/privileged/privileged.sv
+++ b/hdl/core/privileged/privileged.sv
@@ -35,6 +35,7 @@ module privileged import cvw::*;  #(parameter cvw_t P) (
   // CSR Reads and Writes, and values needed for traps
   input  logic              CSRReadM, CSRWriteM,                            // Read or write CSRs
   input  logic [P.XLEN-1:0] SrcAM,                                          // GPR register to write
+  input  logic [P.XLEN-1:0] ForwardedSrcAM,                                 // SHARD: rs1 value on the checked path
   input  logic [31:0]       InstrM,                                         // Instruction
   input  logic [31:0]       InstrOrigM,                                     // Original compressed or uncompressed instruction in Memory stage for Illegal Instruction MTVAL
   input  logic [P.XLEN-1:0] IEUAdrxTvalM,                                   // address from IEU
@@ -98,12 +99,20 @@ module privileged import cvw::*;  #(parameter cvw_t P) (
   output logic              BigEndianM,                                     // Use big endian in current privilege mode
   // Fault outputs
   output logic              wfiM, IntPendingM,                              // Stall in Memory stage for WFI until interrupt pending or timeout
-  output logic              CSRFaultM,                                      // Rev 7: SHARD shadow CSR write-value mismatch
+  output logic              CSRFaultM,                                      // SHARD: CSR instruction's read or write value fails verification
+  output logic              CSRStateFaultM,                                 // SHARD: CSR mirror differs from the CSR file
+  input  logic              CSRMirrorResyncM,                               // SHARD: reload the CSR mirror
   output logic [31:0]       RAND_INSTR_INSERT_FREQ_REGW,                    // AMOEBA: dummy instruction insertion divider period
   output logic              PrivModeUncorrectableFaultW,                   // TMR uncorrectable privilege mode fault
   input  logic              RegEccSecErrW,                                 // IEU ECC SEC (correctable 1-bit flip)
   input  logic              RegEccDedErrW,                                 // IEU ECC DED, retained for MSECFAULT logging
   input  logic              ShadowFaultW,                                  // SHARD shadow pipeline mismatch
+  input  logic              ShadowQuiescentM,                              // SHARD: every retired instruction is verified and committed
+  input  logic              ShardRedirectM,                                // SHARD recovery/retry redirect
+  output logic              TrapPendingM,                                  // SHARD: a trap waits for the shadow to become quiescent
+  input  logic              ShadowFaultTrapM,                              // SHARD: unrecovered fault presented to trap logic (cause 16)
+  input  logic [P.XLEN-1:0] ShadowFaultEPCM, ShadowFaultMtvalM,            // captured trap metadata
+  output logic              ShadowFaultTrapTakenM,                         // cause 16 was selected and consumed
   input  logic              EccDedFaultM,                                  // registered DED fault presented to trap logic
   input  logic [P.XLEN-1:0] EccDedFaultEPCM, EccDedFaultMtvalM,             // captured trap metadata
   output logic              EccDedTrapTakenM                               // cause 19 was selected and consumed
@@ -141,16 +150,17 @@ module privileged import cvw::*;  #(parameter cvw_t P) (
   privdec #(P) pmd(.clk, .reset, .StallW, .FlushW, .InstrM(InstrM[31:7]),
     .PrivilegedM, .IllegalIEUFPUInstrM, .IllegalCSRAccessM,
     .PrivilegeModeW, .STATUS_TSR, .STATUS_TVM, .STATUS_TW, .TrapM, .IllegalInstrFaultM,
-    .EcallFaultM, .BreakpointFaultM, .sretM, .mretM, .RetM, .wfiM, .wfiW, .sfencevmaM);
+    .EcallFaultM, .BreakpointFaultM, .sretM, .mretM, .RetM, .wfiM, .wfiW, .sfencevmaM, .ShardRedirectM);
 
   // Control and Status Registers
   csr #(P) csr(.clk, .reset, .FlushM, .FlushW, .StallE, .StallM, .StallW,
-    .InstrM, .InstrOrigM, .PCM, .PCSpillM, .SrcAM, .IEUAdrxTvalM,
+    .InstrM, .InstrOrigM, .PCM, .PCSpillM, .SrcAM, .ForwardedSrcAM, .IEUAdrxTvalM,
     .CSRReadM, .CSRWriteM, .PrivModeSecFaultW, .PrivModeUncorrectableFaultW,
     .RegEccSecErrW, .RegEccDedErrW, .ShadowFaultW, .EccDedFaultEPCM, .EccDedFaultMtvalM,
+    .ShadowFaultEPCM, .ShadowFaultMtvalM,
     .TrapM, .mretM, .sretM, .InterruptM,
     .MTimerInt, .MExtInt, .SExtInt, .MSwInt,
-    .MTIME_CLINT, .InstrValidM, .FRegWriteM, .LoadStallD, .StoreStallD,
+    .MTIME_CLINT, .InstrValidM, .FRegWriteM(FRegWriteM & ~ShardRedirectM), .LoadStallD, .StoreStallD,
     .BPDirWrongM, .BTAWrongM, .RASPredPCWrongM, .BPWrongM,
     .sfencevmaM, .ExceptionM, .InvalidateICacheM, .ICacheStallF, .DCacheStallM, .DivBusyE, .FDivBusyE,
     .IClassWrongM, .IClassM, .DCacheMiss, .DCacheAccess, .ICacheMiss, .ICacheAccess,
@@ -161,7 +171,8 @@ module privileged import cvw::*;  #(parameter cvw_t P) (
     .SATP_REGW, .PMPCFG_ARRAY_REGW, .PMPADDR_ARRAY_REGW,
     .SetFflagsM, .FRM_REGW, .ENVCFG_CBE, .ENVCFG_PBMTE, .ENVCFG_ADUE,
     .EPCM, .TrapVectorM,
-    .CSRReadValW, .IllegalCSRAccessM, .BigEndianM, .CSRFaultM, .RAND_INSTR_INSERT_FREQ_REGW);
+    .CSRReadValW, .IllegalCSRAccessM, .BigEndianM, .CSRFaultM, .CSRStateFaultM, .CSRMirrorResyncM,
+    .RAND_INSTR_INSERT_FREQ_REGW);
 
   // pipeline early-arriving trap sources
   privpiperegs ppr(.clk, .reset, .StallD, .StallE, .StallM, .FlushD, .FlushE, .FlushM,
@@ -173,9 +184,10 @@ module privileged import cvw::*;  #(parameter cvw_t P) (
     .InstrMisalignedFaultM, .InstrAccessFaultM, .HPTWInstrAccessFaultM, .HPTWInstrPageFaultM, .IllegalInstrFaultM,
     .BreakpointFaultM, .LoadMisalignedFaultM, .StoreAmoMisalignedFaultM,
     .LoadAccessFaultM, .StoreAmoAccessFaultM, .EcallFaultM, .InstrPageFaultM,
-    .LoadPageFaultM, .StoreAmoPageFaultM, .HardwareErrorFaultM(EccDedFaultM), .PrivilegeModeW,
+    .LoadPageFaultM, .StoreAmoPageFaultM, .HardwareErrorFaultM(EccDedFaultM),
+    .ShadowFaultTrapM, .ShadowFaultTrapTakenM, .PrivilegeModeW,
     .MIP_REGW, .MIE_REGW, .MIDELEG_REGW, .MEDELEG_REGW, .STATUS_MIE, .STATUS_SIE,
-    .InstrValidM, .CommittedM, .CommittedF,
+    .InstrValidM, .CommittedM, .CommittedF, .ShadowQuiescentM, .TrapPendingM,
     .TrapM, .wfiM, .wfiW, .InterruptM, .ExceptionM, .HardwareErrorTrapM(EccDedTrapTakenM),
     .IntPendingM, .DelegateM, .CauseM);
 endmodule
```

### 9.5 The CSR state mirror — `shadow_csr.sv`

An independent second copy of the privileged state that hardware *uses* or that a
trap handler relies on:

- privilege mode;
- `mstatus` (every stored field), with the `sstatus` view and, on RV32, `mstatush`;
- `medeleg`, `mideleg`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`;
- `stvec`, `sscratch`, `sepc`, `scause`, `stval`, `satp`.

It has its own storage, its own address decode, its own write-enable decode (from
its own privilege mode), its own WARL legalization, and its own trap-entry and
trap-return updates including its own delegation decision. It is driven by the
same committed events as the CSR file:

| Event | Input | Mirror action |
|---|---|---|
| A CSR instruction commits its write | `CSRWriteCommitM = CSRWriteM & InstrValidNotFlushedM` | computes `WriteVal = op(its own read view, CSRSrcM)` and writes the addressed register through its own legalization |
| Trap | `TrapM`, `InterruptM`, `CauseM` | decides M or S from its own `medeleg`/`mideleg`/privilege; updates `xepc`, `xcause`, `xtval`, the `mstatus` interrupt stack, and the privilege mode |
| `mret` / `sret` | `mretM`, `sretM` | restores the interrupt stack and privilege mode |
| FP state written | `FSDirtyM` | `FS ← 11` |

What it shares with the main CSR file, and therefore does not check: *which* cause
was selected (`CauseM`), the `mtval` value on a trap (`NextFaultMtvalM`), the trap
PC source (`PCM`), and the decode of `mret`/`sret`.

It provides three checks: the read and write checks of §9.3, and the **state
check** — every mirrored register equals the main one in every cycle:
`StateFault = (mPriv != PrivilegeModeW) | (mMSTATUS != MSTATUS_REGW) | …`. That
catches a wrong legalization, a wrong trap or return side effect, a missed or
spurious write, and an upset in either copy's storage, one cycle after it happens.

**Not mirrored**: `mie`/`mip` and their supervisor views (hardware-driven bits),
counters and counter enables, `menvcfg`/`senvcfg`, PMP, `fcsr`, custom CSRs. For
those only the modify datapath is duplicated.

**`Resync`** reloads the whole mirror from the main registers. It is pulsed one
cycle after a cause-16 trap is taken while `StateFault` is set, so that a state
fault is reported once instead of forever (§12.4).

**When porting, keep the mirror's update rules identical to the target's
`csrsr.sv`, `csrm.sv`, `csrs.sv` and `privmode.sv`.** The code below reproduces
those files' behaviour as of this tree, field by field and in the same priority
order (trap, `mret`, `sret`, `mstatus` write, `mstatush` write, `sstatus` write, FP
dirty). If the target's versions differ — a different `MEDELEG_MASK`, extra
`mstatus` fields, a different `satp` legality rule — the mirror must be changed to
match, or the state check will fire.

```systemverilog
///////////////////////////////////////////
// shadow_csr.sv
//
// Purpose: SHARD CSR state mirror.  An independent second copy of the trap-handling
//          and translation state of the CSR file:
//
//            privilege mode, mstatus (and its sstatus view), medeleg, mideleg,
//            mtvec, mscratch, mepc, mcause, mtval,
//            stvec, sscratch, sepc, scause, stval, satp
//
//          The mirror keeps its own storage and applies its own decode, its own
//          WARL legalization and its own trap-entry / trap-return updates, from the
//          same committed events that update the main CSR file (a retiring CSR
//          instruction, a trap, an xRET).  CSR writes and traps only happen once the
//          shadow pipeline is quiescent, so the events arrive in architectural order
//          and the write operand has already been checked against the register file.
//
//          It provides three checks:
//           - read:  the value a CSR instruction reads must equal the mirror's;
//           - write: the value a CSR instruction is about to write must equal the
//                    one the mirror computes from its own old value (both are
//                    checked in csr.sv before the instruction commits);
//           - state: every mirrored register must equal the main one in every
//                    cycle.  This catches a wrong legalization, a wrong trap or
//                    return side effect, a missed or spurious write, and an upset in
//                    either copy's storage.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_csr import cvw::*; #(parameter cvw_t P) (
  input  logic              clk, reset,
  input  logic              StallW,
  // Committed events
  input  logic              CSRWriteCommitM,     // a CSR instruction writes its CSR this cycle
  input  logic [11:0]       CSRAdrM,
  input  logic [1:0]        CSROpM,              // 01 write, 10 set, 11 clear
  input  logic [P.XLEN-1:0] CSRSrcM,             // rs1 value or zero-extended immediate
  input  logic              TrapM, InterruptM,
  input  logic [4:0]        CauseM,
  input  logic              mretM, sretM,
  input  logic [P.XLEN-1:0] PCM,
  input  logic [P.XLEN-1:0] EccDedFaultEPCM, ShadowFaultEPCM,
  input  logic [P.XLEN-1:0] NextFaultMtvalM,
  input  logic              FSDirtyM,            // floating-point state written
  input  logic              Resync,              // reload the mirror from the main CSR file
  // Main CSR state
  input  logic [1:0]        PrivilegeModeW,
  input  logic [P.XLEN-1:0] MSTATUS_REGW, MSTATUSH_REGW,
  input  logic [15:0]       MEDELEG_REGW,
  input  logic [11:0]       MIDELEG_REGW,
  input  logic [P.XLEN-1:0] MTVEC_REGW, MSCRATCH_REGW, MEPC_REGW, MCAUSE_REGW, MTVAL_REGW,
  input  logic [P.XLEN-1:0] STVEC_REGW, SSCRATCH_REGW, SEPC_REGW, SCAUSE_REGW, STVAL_REGW, SATP_REGW,
  // Checks
  output logic              MirrorHitM,          // CSRAdrM is a mirrored CSR
  output logic [P.XLEN-1:0] MirrorReadValM,      // its value as a CSR instruction reads it
  output logic              StateFault           // some mirrored register differs from the main one
);

  localparam MSTATUS  = 12'h300;
  localparam MEDELEG  = 12'h302;
  localparam MIDELEG  = 12'h303;
  localparam MTVEC    = 12'h305;
  localparam MSTATUSH = 12'h310;
  localparam MSCRATCH = 12'h340;
  localparam MEPC     = 12'h341;
  localparam MCAUSE   = 12'h342;
  localparam MTVAL    = 12'h343;
  localparam SSTATUS  = 12'h100;
  localparam STVEC    = 12'h105;
  localparam SSCRATCH = 12'h140;
  localparam SEPC     = 12'h141;
  localparam SCAUSE   = 12'h142;
  localparam STVAL    = 12'h143;
  localparam SATP     = 12'h180;

  localparam MEDELEG_MASK = P.ZCA_SUPPORTED ? 16'hB3FE : 16'hB3FF;
  localparam MIDELEG_MASK = 12'h222;

  // Mirror storage
  logic [1:0]        mPriv;
  logic              mTSR, mTW, mTVM, mMXR, mSUM, mMPRV;
  logic [1:0]        mFS, mMPP;
  logic              mSPP, mMPIE, mSPIE, mMIE, mSIE, mMBE, mSBE, mUBE;
  logic [15:0]       mMEDELEG;
  logic [11:0]       mMIDELEG;
  logic [P.XLEN-1:0] mMTVEC, mMSCRATCH, mMEPC, mMCAUSE, mMTVAL;
  logic [P.XLEN-1:0] mSTVEC, mSSCRATCH, mSEPC, mSCAUSE, mSTVAL, mSATP;

  // Status views
  logic              vTSR, vTW, vTVM, vMXR, vSUM, vMPRV, vSD;
  logic [1:0]        vFS, vSXL, vUXL;
  logic [P.XLEN-1:0] mMSTATUS, mSSTATUS, mMSTATUSH;

  logic [P.XLEN-1:0] WriteVal, TVECWriteVal, TrapEPC, NextEPC;
  logic              WrM, WrS;
  logic              Delegate, MTrap, STrap;
  logic [1:0]        TrapPriv, NextPriv, MPPNext;
  logic              LegalSatpMode;

  ///////////////////////////////////////////
  // Read views (what a CSR instruction would read)
  ///////////////////////////////////////////

  assign vTSR  = P.S_SUPPORTED & mTSR;
  assign vTW   = P.U_SUPPORTED & mTW;
  assign vTVM  = P.S_SUPPORTED & mTVM;
  assign vMXR  = P.S_SUPPORTED & mMXR;
  assign vSUM  = P.S_SUPPORTED & P.VIRTMEM_SUPPORTED & mSUM;
  assign vMPRV = P.U_SUPPORTED & mMPRV;
  assign vFS   = P.F_SUPPORTED ? mFS : 2'b00;
  assign vSD   = (vFS == 2'b11);
  assign vSXL  = P.S_SUPPORTED ? 2'b10 : 2'b00;
  assign vUXL  = P.U_SUPPORTED ? 2'b10 : 2'b00;

  if (P.XLEN == 64) begin : status64
    assign mMSTATUS  = {vSD, 25'b0, mMBE, mSBE, vSXL, vUXL, 9'b0,
                        vTSR, vTW, vTVM, vMXR, vSUM, vMPRV,
                        2'b00, vFS, mMPP, 2'b0,
                        mSPP, mMPIE, mUBE, mSPIE, 1'b0,
                        mMIE, 1'b0, mSIE, 1'b0};
    assign mSSTATUS  = {vSD, 29'b0, vUXL, 12'b0,
                        vMXR, vSUM, 1'b0,
                        2'b00, vFS, 4'b0,
                        mSPP, 1'b0, mUBE, mSPIE,
                        3'b0, mSIE, 1'b0};
    assign mMSTATUSH = '0;
  end else begin : status32
    assign mMSTATUS  = {vSD, 8'b0,
                        vTSR, vTW, vTVM, vMXR, vSUM, vMPRV,
                        2'b00, vFS, mMPP, 2'b0,
                        mSPP, mMPIE, mUBE, mSPIE, 1'b0, mMIE, 1'b0, mSIE, 1'b0};
    assign mMSTATUSH = {26'b0, mMBE, mSBE, 4'b0};
    assign mSSTATUS  = {vSD, 11'b0,
                        vMXR, vSUM, 1'b0,
                        2'b00, vFS, 4'b0,
                        mSPP, 1'b0, mUBE, mSPIE,
                        3'b0, mSIE, 1'b0};
  end

  always_comb begin
    MirrorHitM     = 1'b1;
    MirrorReadValM = '0;
    case (CSRAdrM)
      MSTATUS:  MirrorReadValM = mMSTATUS;
      MSTATUSH: if (P.XLEN == 32) MirrorReadValM = mMSTATUSH;
                else              MirrorHitM = 1'b0;
      MEDELEG:  if (P.S_SUPPORTED) MirrorReadValM = {{(P.XLEN-16){1'b0}}, mMEDELEG};
                else               MirrorHitM = 1'b0;
      MIDELEG:  if (P.S_SUPPORTED) MirrorReadValM = {{(P.XLEN-12){1'b0}}, mMIDELEG};
                else               MirrorHitM = 1'b0;
      MTVEC:    MirrorReadValM = mMTVEC;
      MSCRATCH: MirrorReadValM = mMSCRATCH;
      MEPC:     MirrorReadValM = mMEPC;
      MCAUSE:   MirrorReadValM = mMCAUSE;
      MTVAL:    MirrorReadValM = mMTVAL;
      SSTATUS:  if (P.S_SUPPORTED) MirrorReadValM = mSSTATUS;
                else               MirrorHitM = 1'b0;
      STVEC:    if (P.S_SUPPORTED) MirrorReadValM = mSTVEC;
                else               MirrorHitM = 1'b0;
      SSCRATCH: if (P.S_SUPPORTED) MirrorReadValM = mSSCRATCH;
                else               MirrorHitM = 1'b0;
      SEPC:     if (P.S_SUPPORTED) MirrorReadValM = mSEPC;
                else               MirrorHitM = 1'b0;
      SCAUSE:   if (P.S_SUPPORTED) MirrorReadValM = mSCAUSE;
                else               MirrorHitM = 1'b0;
      STVAL:    if (P.S_SUPPORTED) MirrorReadValM = mSTVAL;
                else               MirrorHitM = 1'b0;
      SATP:     if (P.S_SUPPORTED) MirrorReadValM = mSATP;
                else               MirrorHitM = 1'b0;
      default:  MirrorHitM = 1'b0;
    endcase
  end

  ///////////////////////////////////////////
  // Next-state inputs
  ///////////////////////////////////////////

  // Value written by the CSR instruction, from the mirror's own old value
  always_comb
    case (CSROpM)
      2'b01:   WriteVal = CSRSrcM;
      2'b10:   WriteVal = MirrorReadValM | CSRSrcM;
      2'b11:   WriteVal = MirrorReadValM & ~CSRSrcM;
      default: WriteVal = MirrorReadValM;
    endcase

  assign WrM = CSRWriteCommitM & (mPriv == P.M_MODE);
  assign WrS = CSRWriteCommitM & (|mPriv) & P.S_SUPPORTED;

  // Trap target privilege, from the mirror's own delegation registers
  assign Delegate = P.S_SUPPORTED & ~CauseM[4] &
                    (InterruptM ? mMIDELEG[CauseM[3:0]] : mMEDELEG[CauseM[3:0]]) &
                    (mPriv == P.U_MODE | mPriv == P.S_MODE);
  assign TrapPriv = Delegate ? P.S_MODE : P.M_MODE;
  assign MTrap    = TrapM & (TrapPriv == P.M_MODE);
  assign STrap    = TrapM & (TrapPriv == P.S_MODE) & P.S_SUPPORTED;

  always_comb
    if      (TrapM) NextPriv = TrapPriv;
    else if (mretM) NextPriv = (mMPP == 2'b10) ? P.M_MODE : mMPP;
    else if (sretM) NextPriv = {1'b0, mSPP};
    else            NextPriv = mPriv;

  always_comb
    if      (WriteVal[12:11] == P.U_MODE & P.U_SUPPORTED) MPPNext = P.U_MODE;
    else if (WriteVal[12:11] == P.S_MODE & P.S_SUPPORTED) MPPNext = P.S_MODE;
    else if (WriteVal[12:11] == P.M_MODE)                 MPPNext = P.M_MODE;
    else                                                  MPPNext = mMPP;

  assign TVECWriteVal = WriteVal[0] ? {WriteVal[P.XLEN-1:6], 6'b000001} : {WriteVal[P.XLEN-1:2], 2'b00};

  // Hardware-error (19) and SHARD (16) traps report a captured PC
  assign TrapEPC = (CauseM == 5'd19) ? EccDedFaultEPCM : (CauseM == 5'd16) ? ShadowFaultEPCM : PCM;
  always_comb begin
    NextEPC = TrapM ? TrapEPC : WriteVal;
    NextEPC[0] = 1'b0;
    if (!P.ZCA_SUPPORTED) NextEPC[1] = 1'b0;
  end

  if (P.XLEN == 64) begin : satp64
    assign LegalSatpMode = P.SV39_SUPPORTED &
                           ((WriteVal[63:60] == 4'b0) | (WriteVal[63:60] == P.SV39) |
                            (P.SV48_SUPPORTED & WriteVal[63:60] == P.SV48) |
                            (P.SV57_SUPPORTED & WriteVal[63:60] == P.SV57));
  end else begin : satp32
    assign LegalSatpMode = P.SV32_SUPPORTED;
  end

  ///////////////////////////////////////////
  // State update
  ///////////////////////////////////////////

  always_ff @(posedge clk)
    if (reset)             mPriv <= P.M_MODE;
    else if (Resync)       mPriv <= PrivilegeModeW;
    else if (~StallW)      mPriv <= P.U_SUPPORTED ? NextPriv : P.M_MODE;

  always_ff @(posedge clk)
    if (reset) begin
      {mTSR, mTW, mTVM, mMXR, mSUM, mMPRV} <= '0;
      mFS <= 2'b00; mMPP <= 2'b00;
      {mSPP, mMPIE, mSPIE, mMIE, mSIE, mMBE, mSBE, mUBE} <= '0;
    end else if (Resync) begin
      {mTSR, mTW, mTVM, mMXR, mSUM, mMPRV} <= MSTATUS_REGW[22:17];
      mFS   <= MSTATUS_REGW[14:13];
      mMPP  <= MSTATUS_REGW[12:11];
      mSPP  <= MSTATUS_REGW[8];
      mMPIE <= MSTATUS_REGW[7];
      mUBE  <= MSTATUS_REGW[6];
      mSPIE <= MSTATUS_REGW[5];
      mMIE  <= MSTATUS_REGW[3];
      mSIE  <= MSTATUS_REGW[1];
      mMBE  <= (P.XLEN == 64) ? MSTATUS_REGW[P.XLEN-27] : MSTATUSH_REGW[5];
      mSBE  <= (P.XLEN == 64) ? MSTATUS_REGW[P.XLEN-28] : MSTATUSH_REGW[4];
    end else if (~StallW) begin
      if (TrapM) begin
        if (TrapPriv == P.M_MODE) begin
          mMPIE <= mMIE;
          mMIE  <= 1'b0;
          mMPP  <= mPriv;
        end else if (P.S_SUPPORTED) begin
          mSPIE <= mSIE;
          mSIE  <= 1'b0;
          mSPP  <= mPriv[0];
        end
      end else if (mretM) begin
        mMIE  <= mMPIE;
        mMPIE <= 1'b1;
        mMPP  <= P.U_SUPPORTED ? P.U_MODE : P.M_MODE;
        mMPRV <= mMPRV & (mMPP == P.M_MODE);
      end else if (sretM & P.S_SUPPORTED) begin
        mSIE  <= mSPIE;
        mSPIE <= P.S_SUPPORTED;
        mSPP  <= 1'b0;
        mMPRV <= 1'b0;
      end else if (WrM & (CSRAdrM == MSTATUS)) begin
        mTSR  <= P.S_SUPPORTED & WriteVal[22];
        mTW   <= P.U_SUPPORTED & WriteVal[21];
        mTVM  <= P.S_SUPPORTED & WriteVal[20];
        mMXR  <= P.S_SUPPORTED & WriteVal[19];
        mSUM  <= P.VIRTMEM_SUPPORTED & WriteVal[18];
        mMPRV <= P.U_SUPPORTED & WriteVal[17];
        mFS   <= WriteVal[14:13];
        mMPP  <= MPPNext;
        mSPP  <= P.S_SUPPORTED & WriteVal[8];
        mMPIE <= WriteVal[7];
        mSPIE <= P.S_SUPPORTED & WriteVal[5];
        mMIE  <= WriteVal[3];
        mSIE  <= P.S_SUPPORTED & WriteVal[1];
        mUBE  <= P.U_SUPPORTED & P.BIGENDIAN_SUPPORTED & WriteVal[6];
        if (P.XLEN == 64) begin
          mMBE <= P.BIGENDIAN_SUPPORTED & WriteVal[P.XLEN-27];
          mSBE <= P.S_SUPPORTED & P.BIGENDIAN_SUPPORTED & WriteVal[P.XLEN-28];
        end
      end else if ((P.XLEN == 32) & WrM & (CSRAdrM == MSTATUSH)) begin
        mMBE  <= P.BIGENDIAN_SUPPORTED & WriteVal[5];
        mSBE  <= P.S_SUPPORTED & P.BIGENDIAN_SUPPORTED & WriteVal[4];
      end else if (WrS & (CSRAdrM == SSTATUS)) begin
        mMXR  <= P.S_SUPPORTED & WriteVal[19];
        mSUM  <= P.VIRTMEM_SUPPORTED & WriteVal[18];
        mFS   <= WriteVal[14:13];
        mSPP  <= P.S_SUPPORTED & WriteVal[8];
        mSPIE <= P.S_SUPPORTED & WriteVal[5];
        mSIE  <= P.S_SUPPORTED & WriteVal[1];
        mUBE  <= P.U_SUPPORTED & P.BIGENDIAN_SUPPORTED & WriteVal[6];
      end else if (FSDirtyM) mFS <= 2'b11;
    end

  always_ff @(posedge clk)
    if (reset) begin
      mMEDELEG <= '0; mMIDELEG <= '0;
      mMTVEC <= '0; mMSCRATCH <= '0; mMEPC <= '0; mMCAUSE <= '0; mMTVAL <= '0;
      mSTVEC <= '0; mSSCRATCH <= '0; mSEPC <= '0; mSCAUSE <= '0; mSTVAL <= '0; mSATP <= '0;
    end else if (Resync) begin
      mMEDELEG <= MEDELEG_REGW; mMIDELEG <= MIDELEG_REGW;
      mMTVEC <= MTVEC_REGW; mMSCRATCH <= MSCRATCH_REGW; mMEPC <= MEPC_REGW;
      mMCAUSE <= MCAUSE_REGW; mMTVAL <= MTVAL_REGW;
      mSTVEC <= STVEC_REGW; mSSCRATCH <= SSCRATCH_REGW; mSEPC <= SEPC_REGW;
      mSCAUSE <= SCAUSE_REGW; mSTVAL <= STVAL_REGW; mSATP <= SATP_REGW;
    end else begin
      if (WrM & (CSRAdrM == MEDELEG) & P.S_SUPPORTED) mMEDELEG <= WriteVal[15:0] & MEDELEG_MASK;
      if (WrM & (CSRAdrM == MIDELEG) & P.S_SUPPORTED) mMIDELEG <= WriteVal[11:0] & MIDELEG_MASK;
      if (WrM & (CSRAdrM == MTVEC))                   mMTVEC <= TVECWriteVal;
      if (WrM & (CSRAdrM == MSCRATCH))                mMSCRATCH <= WriteVal;
      if (MTrap | (WrM & (CSRAdrM == MEPC)))          mMEPC <= NextEPC;
      if (MTrap | (WrM & (CSRAdrM == MCAUSE)))        mMCAUSE <= TrapM ? {InterruptM, {(P.XLEN-6){1'b0}}, CauseM}
                                                                      : {WriteVal[P.XLEN-1], {(P.XLEN-6){1'b0}}, WriteVal[4:0]};
      if (MTrap | (WrM & (CSRAdrM == MTVAL)))         mMTVAL <= TrapM ? NextFaultMtvalM : WriteVal;
      if (WrS & (CSRAdrM == STVEC))                   mSTVEC <= TVECWriteVal;
      if (WrS & (CSRAdrM == SSCRATCH))                mSSCRATCH <= WriteVal;
      if (STrap | (WrS & (CSRAdrM == SEPC)))          mSEPC <= NextEPC;
      if (STrap | (WrS & (CSRAdrM == SCAUSE)))        mSCAUSE <= TrapM ? {InterruptM, {(P.XLEN-6){1'b0}}, CauseM}
                                                                      : {WriteVal[P.XLEN-1], {(P.XLEN-6){1'b0}}, WriteVal[4:0]};
      if (STrap | (WrS & (CSRAdrM == STVAL)))         mSTVAL <= TrapM ? NextFaultMtvalM : WriteVal;
      if (WrS & (CSRAdrM == SATP) & P.VIRTMEM_SUPPORTED &
          (mPriv == P.M_MODE | ~vTVM) & LegalSatpMode) mSATP <= WriteVal;
    end

  ///////////////////////////////////////////
  // State check
  ///////////////////////////////////////////

  assign StateFault = (mPriv != PrivilegeModeW) | (mMSTATUS != MSTATUS_REGW) | (mMSTATUSH != MSTATUSH_REGW) |
                      (mMEDELEG != MEDELEG_REGW) | (mMIDELEG != MIDELEG_REGW) |
                      (mMTVEC != MTVEC_REGW) | (mMSCRATCH != MSCRATCH_REGW) | (mMEPC != MEPC_REGW) |
                      (mMCAUSE != MCAUSE_REGW) | (mMTVAL != MTVAL_REGW) |
                      (mSTVEC != STVEC_REGW) | (mSSCRATCH != SSCRATCH_REGW) | (mSEPC != SEPC_REGW) |
                      (mSCAUSE != SCAUSE_REGW) | (mSTVAL != STVAL_REGW) | (mSATP != SATP_REGW);

endmodule
```

---

## 10. Checks on the shared multipliers

The shadow has an ALU but no multiplier, divider or FPU, so results of those units
are taken from the main pipeline. For the multipliers a **mod-3 residue check**
closes the gap. `2^2 ≡ 1 (mod 3)`, so the residue of an unsigned number is the sum
of its 2-bit digits mod 3, and `res(a)·res(b) ≡ res(a·b)`. Any product error that
is not a multiple of 3 is caught — in particular every single-bit error (±2^k).
Unlike a duplicated datapath the check is arithmetically unrelated to the
multiplier, so a permanent fault or a trojan in the array cannot defeat both.

### 10.1 `shadow_residue.sv`

```systemverilog
///////////////////////////////////////////
// shadow_residue.sv
//
// Purpose: SHARD mod-3 residue generator, used to check the shared multipliers.
//          2^2 = 1 (mod 3), so the residue of an unsigned number is the sum of its
//          2-bit digits mod 3.  A multiplier that returns a wrong product violates
//          res(a) * res(b) = res(a*b) (mod 3) unless the error is itself a multiple
//          of 3; in particular every single-bit error (+-2^k) is caught.
//
//          Unlike a duplicated datapath, the check is arithmetically different from
//          the multiplier, so a permanent fault or a trojan in the array cannot
//          corrupt both in the same way.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_residue #(parameter int WIDTH = 64) (
  input  logic [WIDTH-1:0] a,
  output logic [1:0]       residue   // a mod 3
);

  localparam int DIGITS = (WIDTH + 1) / 2;

  logic [2*DIGITS-1:0] Padded;

  assign Padded = {{(2*DIGITS-WIDTH){1'b0}}, a};

  always_comb begin
    residue = 2'd0;
    for (int i = 0; i < DIGITS; i++) begin
      logic [2:0] Sum;
      Sum = {1'b0, residue} + {1'b0, Padded[2*i +: 2]};   // at most 2 + 3
      residue = (Sum >= 3'd3) ? 2'(Sum - 3'd3) : Sum[1:0];
    end
  end

endmodule
```

### 10.2 Integer multiply — `mdu.sv`

`mul` produces the full `2·XLEN`-bit product `ProdM` for all four flavours.
Signedness is handled by reading values as integers: a signed `XLEN`-bit operand is
its unsigned reading minus `sign·2^XLEN`, and `2^XLEN ≡ 1 (mod 3)` because `XLEN` is
even; likewise a product that can be negative (`mulh`, `mulhsu`) is the unsigned
reading of `ProdM` minus its top bit. Subtracting 1 mod 3 is `r==0 ? 2 : r-1`.

- Execute: `ResAE`, `ResBE` from `ForwardedSrcAE/BE`; adjust A if signed (`mulh`,
  `mulhsu`) and B if signed (`mulh`); multiply the two residues (0, 1, 2 or 4 → 1).
- Register `{ResABE, MulE, SignedAE}` at the E→M edge (`flopenrc`, clear `FlushM`,
  enable `~StallM`) — the same edge at which `mul` registers its partial products.
  `MulE = MDUActiveE & ~IntDivE`.
- Memory: residue of `ProdM`, adjusted if the product is signed;
  `MULFaultM = MulM & (ResProdAdjM != ResABM)`.

The operands themselves are verified by the shadow's OP check, so the multiply is
covered from verified operands to the full product. **Not covered:** the selection
of the low or high half and the W-form sign extension after `ProdM`.

```systemverilog
module mdu import cvw::*;  #(parameter cvw_t P) (
  input  logic              clk, reset,
  input  logic              StallM, StallW,
  input  logic              FlushE, FlushM, FlushW,
  input  logic [P.XLEN-1:0] ForwardedSrcAE, ForwardedSrcBE, // inputs A and B from IEU forwarding mux output
  input  logic [2:0]        Funct3E, Funct3M,               // type of MDU operation
  input  logic              IntDivE, W64E,                  // Integer division/remainder, and W-type instructions
  input  logic              MDUActiveE,                     // Mul/Div instruction being executed
  output logic [P.XLEN-1:0] MDUResultW,                     // multiply/divide result
  output logic              DivBusyE,                       // busy signal to stall pipeline in Execute stage
  output logic              MULFaultM                       // SHARD: product fails its residue check
);

  logic [P.XLEN*2-1:0]      ProdM;                          // double-width product from mul
  logic [P.XLEN-1:0]        QuotM, RemM;                    // quotient and remainder from intdivrestoring
  logic [P.XLEN-1:0]        PrelimResultM;                  // selected result before W truncation
  logic [P.XLEN-1:0]        MDUResultM;                     // result after W truncation
  logic                     W64M;                           // W-type instruction

  mul #(P.XLEN) multiplier(.clk, .reset, .StallM, .FlushM,
    .ForwardedSrcAE, .ForwardedSrcBE, .Funct3E, .ProdM);

  // SHARD mod-3 residue check of the multiplier.  The multiplier is not duplicated in
  // the shadow, so the check must not share its failure modes: res(A)*res(B) is
  // compared with res(ProdM).  For a signed operand the value is the unsigned reading
  // minus sign*2^XLEN, and 2^XLEN = 1 (mod 3); likewise the product as an integer is
  // the unsigned reading of ProdM minus its sign bit when the product can be negative
  // (mulh, mulhsu).  The shadow separately verifies that A and B are the right operands.
  logic [1:0] ResAE, ResBE, ResAAdjE, ResBAdjE, ResABE, ResABM, ResProdM, ResProdAdjM;
  logic       SignedAE, SignedBE, MulE, MulM, SignedProdM;
  logic [3:0] ResMulE;

  assign SignedAE = (Funct3E == 3'b001) | (Funct3E == 3'b010);   // mulh, mulhsu
  assign SignedBE = (Funct3E == 3'b001);                         // mulh
  shadow_residue #(P.XLEN) resa(.a(ForwardedSrcAE), .residue(ResAE));
  shadow_residue #(P.XLEN) resb(.a(ForwardedSrcBE), .residue(ResBE));
  // subtract the sign (mod 3): r - 1 = r + 2
  assign ResAAdjE = (SignedAE & ForwardedSrcAE[P.XLEN-1]) ? ((ResAE == 2'd0) ? 2'd2 : ResAE - 2'd1) : ResAE;
  assign ResBAdjE = (SignedBE & ForwardedSrcBE[P.XLEN-1]) ? ((ResBE == 2'd0) ? 2'd2 : ResBE - 2'd1) : ResBE;
  assign ResMulE  = ResAAdjE * ResBAdjE;                         // 0, 1, 2 or 4
  assign ResABE   = (ResMulE == 4'd4) ? 2'd1 : ResMulE[1:0];
  assign MulE     = MDUActiveE & ~IntDivE;

  flopenrc #(4) ResMReg(clk, reset, FlushM, ~StallM, {ResABE, MulE, SignedAE}, {ResABM, MulM, SignedProdM});

  shadow_residue #(2*P.XLEN) resp(.a(ProdM), .residue(ResProdM));
  assign ResProdAdjM = (SignedProdM & ProdM[2*P.XLEN-1]) ? ((ResProdM == 2'd0) ? 2'd2 : ResProdM - 2'd1) : ResProdM;
  assign MULFaultM   = MulM & (ResProdAdjM != ResABM);

  if ((P.IDIV_ON_FPU & P.F_SUPPORTED) | (!P.M_SUPPORTED)) begin : nodiv
    assign QuotM    = '0;
    assign RemM     = '0;
    assign DivBusyE = 1'b0;
  end else begin : intdiv
    div #(P) intdivider(.clk, .reset, .StallM, .FlushE, .DivSignedE(~Funct3E[0]), .W64E, .IntDivE,
        .ForwardedSrcAE, .ForwardedSrcBE,
        .DivBusyE, .QuotM, .RemM);
  end

  // Result multiplexer
  // For ZMMUL, QuotM and RemM are tied to 0, so the mux automatically simplifies
  always_comb
    case (Funct3M)
      3'b000: PrelimResultM = ProdM[P.XLEN-1:0];          // mul
      3'b001: PrelimResultM = ProdM[P.XLEN*2-1:P.XLEN];   // mulh
      3'b010: PrelimResultM = ProdM[P.XLEN*2-1:P.XLEN];   // mulhsu
      3'b011: PrelimResultM = ProdM[P.XLEN*2-1:P.XLEN];   // mulhu
      3'b100: PrelimResultM = QuotM;                      // div
      3'b101: PrelimResultM = QuotM;                      // divu
      3'b110: PrelimResultM = RemM;                       // rem
      3'b111: PrelimResultM = RemM;                       // remu
    endcase

  // Handle sign extension for W-type instructions
  flopenrc #(1) W64MReg(clk, reset, FlushM, ~StallM, W64E, W64M);
  if (P.XLEN == 64) begin : resmux // RV64 has W-type instructions
    assign MDUResultM = W64M ? {{32{PrelimResultM[31]}}, PrelimResultM[31:0]} : PrelimResultM;
  end else begin : resmux // RV32 has no W-type instructions
    assign MDUResultM = PrelimResultM;
  end

  // Writeback stage pipeline register
  flopenrc #(P.XLEN) MDUResultWReg(clk, reset, FlushW, ~StallW, MDUResultM, MDUResultW);
endmodule // mdu
```

### 10.3 FMA significand multiply — `fma.sv`, `fpu.sv`

Only relevant when the target has an FPU. Inside `fma`:
`PmResidueFault = res(Pm) != res(Xm)·res(Ym)` on the `NF+1`-bit significands and the
`2·NF+2`-bit product. In `fpu.sv` it is qualified and registered:

```systemverilog
  flopenrc #(1) FMAFaultMReg(clk, reset, FlushM, ~StallM,
    PmResidueFaultE & FPUActiveE & (PostProcSelE == 2'b10), FMAFaultM);
```
(`PostProcSelE == 2'b10` is "the result comes from the FMA".) Without an FPU the
core ties `FMAFaultM` to 0 in the existing `else` branch.

Exact change to `hdl/core/fpu/fma/fma.sv`, as a unified diff against the tree before Rev 8 (`-` lines are what was there: stock AMOEBA Wally, plus the Rev 7 detect-only hooks where shown):

```diff
--- a/hdl/core/fpu/fma/fma.sv
+++ b/hdl/core/fpu/fma/fma.sv
@@ -40,7 +40,8 @@ module fma import cvw::*;  #(parameter cvw_t P) (
   output logic                         Ps,                     // the product's sign
   output logic                         Ss,                     // the sum's sign
   output logic [P.NE+1:0]              Se,                     // the sum's exponent
-  output logic [$clog2(P.FMALEN+1)-1:0] SCnt                    // normalization shift count
+  output logic [$clog2(P.FMALEN+1)-1:0] SCnt,                   // normalization shift count
+  output logic                         PmResidueFault          // SHARD: significand product fails its mod-3 residue check
 );
 
   //  OpCtrl:
@@ -74,6 +75,18 @@ module fma import cvw::*;  #(parameter cvw_t P) (
   // multiplication of the mantissa's
   fmamult #(P) mult(.Xm, .Ym, .Pm);
 
+  // SHARD mod-3 residue check of the significand multiplier: res(Xm)*res(Ym) = res(Pm).
+  // The FPU is not duplicated, so its largest shared block gets an arithmetically
+  // independent check instead.
+  logic [1:0] ResXm, ResYm, ResXmYm, ResPm;
+  logic [3:0] ResMul;
+  shadow_residue #(P.NF+1)   resx(.a(Xm), .residue(ResXm));
+  shadow_residue #(P.NF+1)   resy(.a(Ym), .residue(ResYm));
+  shadow_residue #(2*P.NF+2) resp(.a(Pm), .residue(ResPm));
+  assign ResMul  = ResXm * ResYm;                               // 0, 1, 2 or 4
+  assign ResXmYm = (ResMul == 4'd4) ? 2'd1 : ResMul[1:0];
+  assign PmResidueFault = (ResPm != ResXmYm);
+
   // calculate the signs and take the operation into account
   fmasign sign(.OpCtrl, .Xs, .Ys, .Zs, .Ps, .As, .InvA);
```

---

## 11. Core integration — `wallypipelinedcore.sv`

This is where retirement, serialization, the Memory-stage checks and the fault
response live. The logic, in the order it appears:

### 11.1 Retirement and the queues

```systemverilog
  localparam int SHARD_DEPTH = 8;
  localparam int SHARD_CW    = $clog2(SHARD_DEPTH+1);

  assign MExitM = InstrValidM & ~StallW & ~FlushW;
  flopenrc #(1) InstrValidWReg(clk, reset, FlushW, ~StallW, InstrValidM, InstrValidW);
  flopenrc #(1) CompressedMReg(clk, reset, FlushM, ~StallM, CompressedE, CompressedM);

  assign ShardPushOK = ~RecPending & ~sFault;
  assign QPushM      = MExitM & ShardPushOK;

  assign RQPushW = InstrValidW & ~WPushed & ShardPushOK;
  always_ff @(posedge clk)
    if (reset) WPushed <= 1'b0;
    else       WPushed <= StallW & (WPushed | RQPushW);

  always_ff @(posedge clk)
    if (reset | sFault) InFlight <= '0;
    else                InFlight <= InFlight + {{SHARD_CW{1'b0}}, QPushM} - {{SHARD_CW{1'b0}}, sCommit};

  assign ShadowIdleM = (InFlight == '0) & ~RecPending;
  assign ShardBackpressureW = (rqCount >= SHARD_CW'(SHARD_DEPTH-1));
```
`CompressedE` is the IFU's existing "the Execute instruction was 16 bits" output.
`InFlight` is one bit wider than the queue count (`[SHARD_CW:0]`).

The push window: from the cycle of a shadow fault (`sFault`, combinational) until
the redirect clears `RecPending`, nothing is pushed. In that window the main
pipeline is still running wrong-path instructions; they retire from M and W but
enter no queue, and the redirect then loads a bubble into W. Flush has priority
over push inside the FIFO, so an instruction that left M in the fault cycle is not
pushed either.

### 11.2 Serialization

```systemverilog
  assign NonMemSerialM = (InstrValidM & (CSRWriteFenceM | PrivilegedM | InvalidateICacheM | FlushDCacheM |
                                         FRegWriteM | FpLoadStoreM | FWriteIntM)) | TrapPendingM;
```
| Term | Instructions |
|---|---|
| `CSRWriteFenceM` | any CSR instruction that writes; `fence`, `fence.i` |
| `PrivilegedM` | `ecall`, `ebreak`, `mret`, `sret`, `wfi`, `sfence.vma` (and the Svinval forms) |
| `InvalidateICacheM`, `FlushDCacheM` | `fence.i` (already covered; kept explicit) |
| `FRegWriteM`, `FpLoadStoreM`, `FWriteIntM` | every floating-point instruction: writes an FP register, is an FP load/store, or writes an integer register from the FPU (and may set flags). All zero without an FPU |
| `TrapPendingM` | an exception on the M-stage instruction or an interrupt, not yet taken |

A CSR instruction that only reads (`CSRReadM` without `CSRWriteM`) is **not**
serialized: it has no side effect and its value is checked against the mirror.
Memory instructions are classified in the LSU (`SerialMemM`).

### 11.3 Memory-stage checks

```systemverilog
  flopenrc #(P.XLEN) ShadowEAMReg(clk, reset, FlushM, ~StallM, SrcAE + SrcBE, ShadowEAM);
  assign EAFaultM = (|MemRWM) & (ShadowEAM != IEUAdrM);

  assign RegA4 = ShadowIdleM ? InstrM[19:15] : sRs1E;
  assign RegA5 = ShadowIdleM ? InstrM[24:20] : sRs2E;
  assign OperandFaultM = ShadowIdleM & ((ForwardedSrcAM != sRD1E) | (WriteDataM != sRD2E));

  assign ShardPreFaultM   = InstrValidM & (EAFaultM | OperandFaultM | CSRFaultM | MULFaultM | FMAFaultM);
  assign ShardLocalFaultM = ShardPreFaultM | (InstrValidM & (AMOFaultM | LoadFwdFaultM));
```

- **EA**: a second adder computes `SrcAE + SrcBE` and a second register carries it
  to M, where it is compared with `IEUAdrM` (the LSU's address register) for every
  memory instruction. The shadow also checks the address, but afterwards; this
  check stops a serialized access *before* it touches memory.
- **Operand**: once `ShadowIdleM`, every instruction older than the one in M has
  been committed, so the regfile holds exactly the architectural values that
  instruction should have read. The regfile's shadow read ports are free (the
  shadow is empty), so they are re-addressed with the M-stage instruction's
  register fields and compared with `ForwardedSrcAM`/`WriteDataM`. This is how an
  instruction that waits for quiescence — and therefore acts before the shadow
  ever sees it — has its operands verified before it acts. It applies to whatever
  is in M whenever the shadow is idle, not only to serialized instructions.
  `RegA4/RegA5` are what the core passes to the IEU's `sRs1E/sRs2E` ports.
- **`ShardPreFaultM`** (faults computed outside the LSU) feeds `HoldM`, which
  stalls and masks. **`ShardLocalFaultM`** (all of them) feeds the stall
  `ShardStallW` and the redirect. The two LSU-originated faults are deliberately
  kept out of the mask (§14, P6).

### 11.4 Connections

- `ieu`: `.sRs1E(RegA4), .sRs2E(RegA5), .sRD1E, .sRD2E, .Rs1E, .Rs2E, .RQ_HitA, …,
  .SrcAE, .SrcBE, .ForwardedSrcAM, .ShardCtlM, .PCSrcM, .RegWriteM, .ResultSrcM,
  .FWriteIntM, .RegWriteW(RegWriteW_s), .ResultW(ResultW_s)`.
- `lsu #(.P(P), .SQ_DEPTH(SHARD_DEPTH))`: `MemRWM` connected directly (no gating in
  the core); the ports of §7.8.
- `hazard`: `.ShardRedirectM, .ShardStallW(ShardBackpressureW | ShardLocalFaultM)`.
- `ifu`: `.ShardRedirectM, .ShardRedirectPCM`.
- `privileged`: the ports of §9.4; in the no-`ZICSR` `else` branch tie
  `TrapPendingM`, `ShadowFaultTrapTakenM`, `CSRFaultM`, `CSRStateFaultM` to 0.
- `mdu`: `.MULFaultM` (tie to 0 in the no-multiplier branch). `fpu`: `.FMAFaultM`
  (tie to 0 in the no-FPU branch).
- OQ: `ForwardedSrcBM = WriteDataM`, `RawLoadWordM = RawReadDataWordM`, the 28
  control bits unpacked from `ShardCtlM` per §6.4, `ViaSQM = SQStoreM`,
  `AMOM = AtomicM[1]`, `LoadChkM = MemRWM[1] & ~FpLoadStoreM & ~BigEndianM`.
- SQ: `.Push(QPushM & SQStoreM), .PAdrM(SQPAdrM), .SizeM(Funct3M[1:0]),
  .WriteDataM(SQWriteDataM), .Verify(sCommitStore), .Pop(sqPop)`.
- RQ: `.Push(RQPushW), .RdW, .RegWriteW(RegWriteW_s), .ResultW(ResultW_s),
  .Pop(sCommit)`.
- `shadow_pipeline`: `.StreamBreak(TrapM)`.
- All four queues: `.Flush(sFault)`.

### 11.5 `wallypipelinedcore.sv` as built

```systemverilog
module wallypipelinedcore import cvw::*; #(parameter cvw_t P) (
   input  logic                  clk, reset,
   // ECC inject enable (from top-level, for DFT)
   input  logic                  ecc_inject_en,
   // Privileged
   input  logic                  MTimerInt, MExtInt, SExtInt, MSwInt,
   input  logic [63:0]           MTIME_CLINT,
   // Bus Interface
   input  logic [P.AHBW-1:0]     HRDATA,
   input  logic                  HREADY, HRESP,
   output logic                  HCLK, HRESETn,
   output logic [P.PA_BITS-1:0]  HADDR,
   output logic [P.AHBW-1:0]     HWDATA,
   output logic [P.XLEN/8-1:0]   HWSTRB,
   output logic                  HWRITE,
   output logic [2:0]            HSIZE,
   output logic [2:0]            HBURST,
   output logic [3:0]            HPROT,
   output logic [1:0]            HTRANS,
   output logic                  HMASTLOCK,
   input  logic                  ExternalStall,
   output logic                  PrivModeUncorrectableFaultW  // TMR uncorrectable privilege mode fault — wire to reset/NMI
);

  logic                          StallF, StallD, StallE, StallM, StallW;
  logic                          FlushD, FlushE, FlushM, FlushW;
  logic                          TrapM, RetM;

  //  signals that must connect through DP
  logic                          IntDivE, W64E;
  logic                          CSRReadM, CSRWriteM, PrivilegedM;
  logic [1:0]                    AtomicM;
  logic [P.XLEN-1:0]             ForwardedSrcAE, ForwardedSrcBE;
  logic [P.XLEN-1:0]             SrcAM;
  logic [2:0]                    Funct3E;
  logic [31:0]                   InstrD;
  logic [31:0]                   InstrM, InstrOrigM;
  logic [P.XLEN-1:0]             PCSpillF, PCE, PCLinkE;
  logic [P.XLEN-1:0]             PCM, PCSpillM;
  logic [P.XLEN-1:0]             CSRReadValW, MDUResultW;
  logic [P.XLEN-1:0]             EPCM, TrapVectorM;
  logic [1:0]                    MemRWE;
  logic [1:0]                    MemRWM;
  logic                          InstrValidD, InstrValidE, InstrValidM;
  logic                          InstrMisalignedFaultM;
  logic                          IllegalBaseInstrD, IllegalFPUInstrD, IllegalIEUFPUInstrD;
  logic                          InstrPageFaultF, LoadPageFaultM, StoreAmoPageFaultM;
  logic                          LoadMisalignedFaultM, LoadAccessFaultM;
  logic                          StoreAmoMisalignedFaultM, StoreAmoAccessFaultM;
  logic                          InvalidateICacheM, FlushDCacheM;
  logic                          PCSrcE;
  logic                          CSRWriteFenceM;
  logic                          DivBusyE;
  logic                          StructuralStallD;
  logic                          LoadStallD;
  logic                          StoreStallD;
  logic                          SquashSCW;
  logic                          MDUActiveE;                      // Mul/Div instruction being executed
  logic                          ENVCFG_ADUE;                     // HPTW A/D Update enable
  logic                          ENVCFG_PBMTE;                    // Page-based memory type enable
  logic [3:0]                    ENVCFG_CBE;                      // Cache Block operation enables
  logic [3:0]                    CMOpM;                           // 1: cbo.inval; 2: cbo.flush; 4: cbo.clean; 8: cbo.zero
  logic                          IFUPrefetchE, LSUPrefetchM;      // instruction / data prefetch hints
  // AMOEBA random instruction insertion
  logic [31:0]                   RAND_INSTR_INSERT_FREQ_REGW;     // rand_instr_insert_freq CSR
  logic [31:0]                   DummyInstrD;                     // dummy instruction to inject
  logic                          InjectD;                         // inject a dummy this cycle
  logic                          DummySelD;                       // shadow register the dummy writes
  logic                          DummyW;                          // Writeback holds a dummy instruction
  logic                          InsertOkD;                       // pipeline permits an insertion

  // floating point unit signals
  logic [2:0]                    FRM_REGW;
  logic [4:0]                    RdE, RdM, RdW;
  logic                          FPUStallD;
  logic                          FWriteIntE;
  logic [P.FLEN-1:0]             FWriteDataM;
  logic [P.XLEN-1:0]             FIntResM;
  logic [P.XLEN-1:0]             FCvtIntResW;
  logic                          FCvtIntW;
  logic                          FDivBusyE;
  logic                          FRegWriteM;
  logic                          FpLoadStoreM;
  logic [4:0]                    SetFflagsM;
  logic [P.XLEN-1:0]             FIntDivResultW;

  // memory management unit signals
  logic                          ITLBWriteF;
  logic                          ITLBMissOrUpdateAF;
  logic [P.XLEN-1:0]             SATP_REGW;
  logic                          STATUS_MXR, STATUS_SUM, STATUS_MPRV;
  logic [1:0]                    STATUS_MPP, STATUS_FS;
  logic [1:0]                    PrivilegeModeW;
  logic [P.XLEN-1:0]             PTE;
  logic [2:0]                    PageType;
  logic                          sfencevmaM;
  logic                          SelHPTW;

  // PMA checker signals
  /* verilator lint_off UNDRIVEN */ // these signals are undriven in configurations without a privileged unit
  var logic [P.PA_BITS-3:0]      PMPADDR_ARRAY_REGW[P.PMP_ENTRIES-1:0];
  var logic [7:0]                PMPCFG_ARRAY_REGW[P.PMP_ENTRIES-1:0];
  /* verilator lint_on UNDRIVEN */

  // IMem stalls
  logic                          IFUStallF;
  logic                          LSUStallM;

  // cpu lsu interface
  logic [2:0]                    Funct3M;
  logic [P.XLEN-1:0]             IEUAdrE;
  logic [P.XLEN-1:0]             WriteDataM;
  logic [P.XLEN-1:0]             IEUAdrM;
  logic [P.XLEN-1:0]             IEUAdrxTvalM;
  logic [P.LLEN-1:0]             ReadDataW;
  logic                          CommittedM;

  // AHB ifu interface
  logic [P.PA_BITS-1:0]          IFUHADDR;
  logic [2:0]                    IFUHBURST;
  logic [1:0]                    IFUHTRANS;
  logic [2:0]                    IFUHSIZE;
  logic                          IFUHWRITE;
  logic                          IFUHREADY;

  // AHB LSU interface
  logic [P.PA_BITS-1:0]          LSUHADDR;
  logic [P.XLEN-1:0]             LSUHWDATA;
  logic [P.XLEN/8-1:0]           LSUHWSTRB;
  logic                          LSUHWRITE;
  logic                          LSUHREADY;

  logic                          BPWrongE, BPWrongM;
  logic                          BPDirWrongM;
  logic                          BTAWrongM;
  logic                          RASPredPCWrongM;
  logic                          IClassWrongM;
  logic [3:0]                    IClassM;
  logic                          InstrAccessFaultF, HPTWInstrAccessFaultF, HPTWInstrPageFaultF;
  logic [2:0]                    LSUHSIZE;
  logic [2:0]                    LSUHBURST;
  logic [1:0]                    LSUHTRANS;

  logic                          DCacheMiss;
  logic                          DCacheAccess;
  logic                          ICacheMiss;
  logic                          ICacheAccess;
  logic                          BigEndianM;
  logic                          FCvtIntE;
  logic                          CommittedF;
  logic                          BranchD, BranchE, JumpD, JumpE;
  logic                          DCacheStallM, ICacheStallF;
  logic                          wfiM, IntPendingM;
  logic                          RegEccSecErrW, RegEccDedErrW;  // ECC error aggregates from IEU
  logic                          RegEccDedErrPipeW;               // DED from W-stage pipeline reg only
  logic [P.XLEN-1:0]             PCW;                             // W-stage PC (PCM registered)

  // SHARD
  localparam int SHARD_DEPTH = 8;                            // IQ/OQ/RQ/SQ depth
  localparam int SHARD_CW    = $clog2(SHARD_DEPTH+1);
  // main pipeline values recorded for the shadow
  logic [4:0]          Rs1E, Rs2E;
  logic [P.XLEN-1:0]   SrcAE, SrcBE;
  logic [P.XLEN-1:0]   ForwardedSrcAM;
  logic [27:0]         ShardCtlM;
  logic                PCSrcM, RegWriteM, FWriteIntM;
  logic [2:0]          ResultSrcM;
  logic [P.XLEN-1:0]   ResultW_s;
  logic                RegWriteW_s;
  logic                CompressedE, CompressedM;
  logic                InstrValidW;
  logic [P.XLEN-1:0]   RawReadDataWordM;
  // retirement into the queues
  logic                MExitM;                               // instruction leaves Memory unflushed: it will retire
  logic                ShardPushOK;                          // no recovery in progress
  logic                QPushM;                               // IQ/OQ (and SQ) push
  logic                RQPushW, WPushed;                     // RQ push, once per Writeback-stage instruction
  logic [SHARD_CW:0]   InFlight;                             // retired instructions not yet committed by the shadow
  logic                ShadowIdleM;
  logic                ShardBackpressureW;
  logic [4:0]          RegA4, RegA5;                         // regfile read ports 4/5: the shadow's, or the Memory-stage check's
  // IQ / OQ heads
  logic                iqValid, iqPop, oqPop;
  logic [P.XLEN-1:0]   iqPC;
  logic [31:0]         iqInstr;
  logic                iqCompressed;
  logic [P.XLEN-1:0]   oqForwardedSrcA, oqForwardedSrcB, oqIEUAdr, oqRawLoadWord;
  logic                oqALUSrcA, oqALUSrcB;
  logic [2:0]          oqImmSrc;
  logic                oqW64, oqUW64, oqSubArith;
  logic [2:0]          oqALUSelect;
  logic [3:0]          oqBSelect, oqZBBSelect;
  logic [2:0]          oqBALUControl;
  logic                oqBMUActive;
  logic [1:0]          oqCZero;
  logic                oqALUResultSrc, oqJump, oqBranch, oqPCSrc, oqRegWrite;
  logic [2:0]          oqResultSrc;
  logic                oqFWriteInt, oqViaSQ, oqAMO, oqLoadChk;
  // RQ
  logic                RQ_HitA, RQ_HitB;
  logic [P.XLEN-1:0]   RQ_ValA, RQ_ValB;
  logic [4:0]          rqRd [2];
  logic                rqRegWrite [2];
  logic [P.XLEN-1:0]   rqResult [2];
  logic [SHARD_CW-1:0] rqCount;
  // SQ
  logic [P.PA_BITS-1:0] sqPA [SHARD_DEPTH];
  logic [1:0]          sqSize [SHARD_DEPTH];
  logic [P.XLEN-1:0]   sqData [SHARD_DEPTH];
  logic [SHARD_CW-1:0] sqCount, sqNVerified;
  logic                sqPop, SQStoreM;
  logic [P.PA_BITS-1:0] SQPAdrM;
  logic [P.XLEN-1:0]   SQWriteDataM;
  // shadow pipeline
  logic                shadow_we3;
  logic [4:0]          shadow_a3;
  logic [P.XLEN-1:0]   shadow_wd3;
  logic [4:0]          sRs1E, sRs2E;
  logic [P.XLEN-1:0]   sRD1E, sRD2E;
  logic                sCommit, sCommitStore, sFault;
  logic [P.XLEN-1:0]   sFaultPC;
  logic [7:0]          sFaultClass;
  // serialization, recovery
  logic                NonMemSerialM;                        // M-stage instruction changes state the shadow cannot defer
  logic                ShadowQuiescentM;
  logic                TrapPendingM;
  logic                RecPending;                           // shadow fault seen; pipeline not yet redirected
  logic [P.XLEN-1:0]   RecPC;
  logic                ShardRedirectM;
  logic [P.XLEN-1:0]   ShardRedirectPCM;
  // Memory-stage checks and fault response
  localparam logic [1:0] SHARD_RETRY_LIMIT = 2'd3;           // consecutive faults before a replay becomes a trap
  logic                EAFaultM, OperandFaultM, AMOFaultM, LoadFwdFaultM, CSRFaultM;
  logic [P.XLEN-1:0]   ShadowEAM;                            // effective address from the second AGU adder
  logic                MULFaultM, FMAFaultM;
  logic                CSRStateFaultM, CSRMirrorResyncM, EscalateStateM;
  logic                ShardPreFaultM, ShardLocalFaultM;
  logic                RedirectRecM, RedirectLocalM, EscalateLocalM, EscalateRecM;
  logic [1:0]          RetryCount;
  logic                ShadowFaultTrapM, ShadowFaultTrapTakenM;
  logic [P.XLEN-1:0]   ShadowFaultEPCM, ShadowFaultMtvalM;
  logic                ShadowFaultW;
  logic                          EccDedFaultM, EccDedTrapTakenM; // registered DED trap record and acknowledgement
  logic [P.XLEN-1:0]             EccDedFaultEPCM, EccDedFaultMtvalM;
  logic                          RegEccDedErrSticky;              // latched DED fault — cleared only by reset
  logic                          PrivModeUncorrectableFaultW_priv; // from privileged unit before ECC OR

  // instruction fetch unit: PC, branch prediction, instruction cache
  ifu #(P) ifu(.clk, .reset,
    .StallF, .StallD, .StallE, .StallM, .StallW, .FlushD, .FlushE, .FlushM, .FlushW,
    .CompressedE,
    .InstrValidE, .InstrValidD,
    .BranchD, .BranchE, .JumpD, .JumpE, .ICacheStallF, .InjectD,
    // Fetch
    .HRDATA, .PCSpillF, .IFUHADDR,
    .IFUStallF, .IFUHBURST, .IFUHTRANS, .IFUHSIZE, .IFUHREADY, .IFUHWRITE,
    .ICacheAccess, .ICacheMiss,
    // Execute
    .PCLinkE, .PCSrcE, .IEUAdrE, .IEUAdrM, .PCE, .BPWrongE,  .BPWrongM,
    // Mem
    .CommittedF, .EPCM, .TrapVectorM, .RetM, .TrapM, .ShardRedirectM, .ShardRedirectPCM, .InvalidateICacheM, .CSRWriteFenceM,
    .InstrD, .InstrM, .InstrOrigM, .PCM, .PCSpillM, .IClassM, .BPDirWrongM,
    .BTAWrongM, .RASPredPCWrongM, .IClassWrongM,
    // Faults out
    .IllegalBaseInstrD, .IllegalFPUInstrD, .InstrPageFaultF, .IllegalIEUFPUInstrD, .InstrMisalignedFaultM,
    // mmu management
    .PrivilegeModeW, .PTE, .PageType, .SATP_REGW, .STATUS_MXR, .STATUS_SUM, .STATUS_MPRV,
    .STATUS_MPP, .ENVCFG_PBMTE, .ENVCFG_ADUE, .ITLBWriteF, .sfencevmaM, .ITLBMissOrUpdateAF,
    // pmp/pma (inside mmu) signals.
    .PMPCFG_ARRAY_REGW,  .PMPADDR_ARRAY_REGW, .InstrAccessFaultF);

  // integer execution unit: integer register file, datapath and controller
  ieu #(P) ieu(.clk, .reset,
     .ecc_inject_en, .RegEccSecErrW, .RegEccDedErrW, .RegEccDedErrPipeW,
     // Decode Stage interface
     .InstrD, .STATUS_FS, .ENVCFG_CBE, .IllegalIEUFPUInstrD, .IllegalBaseInstrD,
     // Execute Stage interface
     .PCE, .PCLinkE, .FWriteIntE, .FCvtIntE, .IEUAdrE, .IntDivE, .W64E,
     .Funct3E, .ForwardedSrcAE, .ForwardedSrcBE, .MDUActiveE, .CMOpM, .IFUPrefetchE, .LSUPrefetchM,
     // Memory stage interface
     .SquashSCW,  // from LSU
     .MemRWE,     // read/write control goes to LSU
     .MemRWM,     // read/write control goes to LSU
     .AtomicM,    // atomic control goes to LSU
     .WriteDataM, // Write data to LSU
     .Funct3M,    // size and signedness to LSU
     .SrcAM,      // to privilege and fpu
     .RdE, .RdM, .FIntResM, .FlushDCacheM,
     .BranchD, .BranchE, .JumpD, .JumpE,
     // Writeback stage
     .CSRReadValW, .MDUResultW, .FIntDivResultW, .RdW, .ReadDataW(ReadDataW[P.XLEN-1:0]),
     .InstrValidM, .InstrValidE, .InstrValidD, .FCvtIntResW, .FCvtIntW,
     // hazards
     .StallD, .StallE, .StallM, .StallW, .FlushD, .FlushE, .FlushM, .FlushW,
     .StructuralStallD, .LoadStallD, .StoreStallD, .PCSrcE,
     .CSRReadM, .CSRWriteM, .PrivilegedM, .CSRWriteFenceM, .InvalidateICacheM,
     // random instruction insertion
     .InjectD, .DummyInstrD, .DummySelD, .DummyW,
     // SHARD
     .shadow_we3, .shadow_a3, .shadow_wd3, .sRs1E(RegA4), .sRs2E(RegA5), .sRD1E, .sRD2E,
     .Rs1E, .Rs2E, .RQ_HitA, .RQ_ValA, .RQ_HitB, .RQ_ValB,
     .SrcAE, .SrcBE, .ForwardedSrcAM, .ShardCtlM, .PCSrcM, .RegWriteM, .ResultSrcM, .FWriteIntM,
     .RegWriteW(RegWriteW_s), .ResultW(ResultW_s));

  ///////////////////////////////////////////
  // AMOEBA: random instruction insertion
  ///////////////////////////////////////////
  // An insertion is blocked whenever Execute cannot accept a new instruction this cycle
  // (a divide occupying Execute, or a stall originating in Memory/Writeback) or the
  // pipeline is about to be flushed anyway.  All of these are Memory/Execute stage
  // signals that do not depend on the decode-stage instruction, so qualifying the
  // strobe with them cannot form a combinational loop through the injection mux.
  // Structural stalls in Decode are deliberately *not* excluded: injecting into a
  // bubble that would have been inserted anyway costs no performance.
  assign InsertOkD = ~DivBusyE & ~FDivBusyE & ~StallM & ~RetM & ~CSRWriteFenceM;

  dummygen dummygen(.clk, .reset,
    .FreqW(RAND_INSTR_INSERT_FREQ_REGW),
    .InstrD, .InstrValidD, .InsertOkD,
    .InjectD, .DummyInstrD, .DummySelD);

  lsu #(.P(P), .SQ_DEPTH(SHARD_DEPTH)) lsu(
    .clk, .reset, .StallM, .FlushM, .StallW, .FlushW,
    // CPU interface
    .MemRWE, .MemRWM, .Funct3M, .Funct7M(InstrM[31:25]), .AtomicM,
    .CommittedM, .DCacheMiss, .DCacheAccess, .SquashSCW,
    .FpLoadStoreM, .FWriteDataM, .IEUAdrE, .IEUAdrM, .WriteDataM,
    .ReadDataW, .FlushDCacheM, .CMOpM, .LSUPrefetchM,
    // connected to ahb (all stay the same)
    .LSUHADDR,  .HRDATA, .LSUHWDATA, .LSUHWSTRB, .LSUHSIZE,
    .LSUHBURST, .LSUHTRANS, .LSUHWRITE, .LSUHREADY,
    // connect to csr or privilege and stay the same.
    .PrivilegeModeW, .BigEndianM, // connects to csr
    .PMPCFG_ARRAY_REGW,           // connects to csr
    .PMPADDR_ARRAY_REGW,          // connects to csr
    // hptw keep i/o
    .SATP_REGW,                   // from csr
    .STATUS_MXR,                  // from csr
    .STATUS_SUM,                  // from csr
    .STATUS_MPRV,                 // from csr
    .STATUS_MPP,                  // from csr
    .ENVCFG_PBMTE,                // from csr
    .ENVCFG_ADUE,                 // from csr
    .sfencevmaM,                  // connects to privilege
    .DCacheStallM,                // connects to privilege
    .IEUAdrxTvalM,                // connects to privilege
    .LoadPageFaultM,              // connects to privilege
    .StoreAmoPageFaultM,          // connects to privilege
    .LoadMisalignedFaultM,        // connects to privilege
    .LoadAccessFaultM,            // connects to privilege
    .HPTWInstrAccessFaultF,       // connects to privilege
    .HPTWInstrPageFaultF,         // connects to privilege
    .StoreAmoMisalignedFaultM,    // connects to privilege
    .StoreAmoAccessFaultM,        // connects to privilege
    .PCSpillF, .ITLBMissOrUpdateAF, .PTE, .PageType, .ITLBWriteF, .SelHPTW,
    .LSUStallM,
    // SHARD store buffer
    .ShadowIdleM, .NonMemSerialM, .ShardPreFaultM, .ShardRedirectM,
    .sqPA, .sqSize, .sqData, .sqCount, .sqNVerified, .sqPop,
    .SQStoreM, .SQPAdrM, .SQWriteDataM, .ShadowQuiescentM,
    .RawReadDataWordM, .AMOFaultM, .LoadFwdFaultM);

  if (P.BUS_SUPPORTED) begin : ebu
    ebu #(P) ebu(// IFU connections
      .clk, .reset,
      // IFU interface
      .IFUHADDR, .IFUHBURST, .IFUHTRANS, .IFUHREADY, .IFUHSIZE,
      // LSU interface
      .LSUHADDR, .LSUHWDATA, .LSUHWSTRB, .LSUHSIZE, .LSUHBURST,
      .LSUHTRANS, .LSUHWRITE, .LSUHREADY,
      // BUS interface
      .HREADY, .HRESP, .HCLK, .HRESETn,
      .HADDR, .HWDATA, .HWSTRB, .HWRITE, .HSIZE, .HBURST,
      .HPROT, .HTRANS, .HMASTLOCK);
  end else begin
    assign {IFUHREADY, LSUHREADY, HCLK, HRESETn, HADDR, HWDATA,
            HWSTRB, HWRITE, HSIZE, HBURST, HPROT, HTRANS, HMASTLOCK} = '0;
  end

  // global stall and flush control
  hazard hzu(
    .BPWrongE, .CSRWriteFenceM, .RetM, .TrapM,
    .StructuralStallD,
    .LSUStallM, .IFUStallF,
    .FPUStallD, .ExternalStall,
    .DivBusyE, .FDivBusyE,
    .ShardRedirectM, .ShardStallW(ShardBackpressureW | ShardLocalFaultM),
    .wfiM, .IntPendingM, .InjectD,
    // Stall & flush outputs
    .StallF, .StallD, .StallE, .StallM, .StallW,
    .FlushD, .FlushE, .FlushM, .FlushW);

  // privileged unit
  if (P.ZICSR_SUPPORTED) begin : priv
    privileged #(P) priv(
      .clk, .reset,
      .FlushD, .FlushE, .FlushM, .FlushW, .StallD, .StallE, .StallM, .StallW,
      .CSRReadM, .CSRWriteM, .SrcAM, .ForwardedSrcAM, .PCM, .PCSpillM,
      .InstrM, .InstrOrigM, .CSRReadValW, .EPCM, .TrapVectorM,
      .RetM, .TrapM, .sfencevmaM, .InvalidateICacheM, .DCacheStallM, .ICacheStallF,
      .InstrValidM, .CommittedM, .CommittedF,
      .FRegWriteM, .LoadStallD, .StoreStallD,
      .BPDirWrongM, .BTAWrongM, .BPWrongM,
      .RASPredPCWrongM, .IClassWrongM, .DivBusyE, .FDivBusyE,
      .IClassM, .DCacheMiss, .DCacheAccess, .ICacheMiss, .ICacheAccess, .PrivilegedM,
      .InstrPageFaultF, .LoadPageFaultM, .StoreAmoPageFaultM,
      .InstrMisalignedFaultM, .IllegalIEUFPUInstrD,
      .LoadMisalignedFaultM, .StoreAmoMisalignedFaultM,
      .MTimerInt, .MExtInt, .SExtInt, .MSwInt,
      .MTIME_CLINT, .IEUAdrxTvalM, .SetFflagsM,
      .InstrAccessFaultF, .HPTWInstrAccessFaultF, .HPTWInstrPageFaultF, .LoadAccessFaultM, .StoreAmoAccessFaultM, .SelHPTW,
      .PrivilegeModeW, .SATP_REGW,
      .STATUS_MXR, .STATUS_SUM, .STATUS_MPRV, .STATUS_MPP, .STATUS_FS,
      .PMPCFG_ARRAY_REGW, .PMPADDR_ARRAY_REGW,
      .FRM_REGW, .ENVCFG_CBE, .ENVCFG_PBMTE, .ENVCFG_ADUE, .wfiM, .IntPendingM, .BigEndianM,
      .CSRFaultM, .CSRStateFaultM, .CSRMirrorResyncM, .ShadowQuiescentM, .ShardRedirectM, .TrapPendingM,
      .ShadowFaultTrapM, .ShadowFaultEPCM, .ShadowFaultMtvalM, .ShadowFaultTrapTakenM,
      .RAND_INSTR_INSERT_FREQ_REGW,
      .RegEccSecErrW, .RegEccDedErrW, .ShadowFaultW,
      .EccDedFaultM, .EccDedFaultEPCM, .EccDedFaultMtvalM, .EccDedTrapTakenM,
      .PrivModeUncorrectableFaultW(PrivModeUncorrectableFaultW_priv));
  end else begin
    assign {CSRReadValW, PrivilegeModeW,
            SATP_REGW, STATUS_MXR, STATUS_SUM, STATUS_MPRV, STATUS_MPP, STATUS_FS, FRM_REGW,
            // PMPCFG_ARRAY_REGW, PMPADDR_ARRAY_REGW,
            ENVCFG_CBE, ENVCFG_PBMTE, ENVCFG_ADUE,
            EPCM, TrapVectorM, RetM, TrapM,
            sfencevmaM, BigEndianM, wfiM, IntPendingM, EccDedTrapTakenM, PrivModeUncorrectableFaultW_priv,
            TrapPendingM, ShadowFaultTrapTakenM} = '0;
    // Without a CSR to program it, dummy instruction insertion stays disabled.
    assign RAND_INSTR_INSERT_FREQ_REGW = '0;
    assign CSRFaultM = 1'b0;
    assign CSRStateFaultM = 1'b0;
  end

  // W-stage PC: used as MEPC when the DED error comes from the W-stage pipeline register
  flopenrc #(P.XLEN) PCWReg(clk, reset, FlushW, ~StallW, PCM, PCW);

  ///////////////////////////////////////////////////////////////////////////
  // SHARD — Shadow Hardware Audit Redundancy Design
  //
  // The main pipeline proposes; the shadow verifies and commits.  Nothing the main
  // pipeline computes reaches architectural state unverified:
  //  - register results wait in the RQ until the shadow commits them to the regfile;
  //  - stores wait in the SQ until the shadow verifies them, then drain to memory;
  //  - anything else with an irreversible effect (CSR write, trap, xRET, FP state,
  //    device access, ...) is held in the Memory stage until the shadow has verified
  //    every older instruction (NonMemSerialM here, SerialMemM in the LSU).
  // On a mismatch the shadow commits nothing, the queues are flushed, and the main
  // pipeline is redirected to replay from the faulting instruction.
  ///////////////////////////////////////////////////////////////////////////

  // An instruction that leaves the Memory stage unflushed is certain to retire.  That is
  // where it enters the IQ/OQ (and SQ); its result follows into the RQ from Writeback.
  assign MExitM = InstrValidM & ~StallW & ~FlushW;
  flopenrc #(1) InstrValidWReg(clk, reset, FlushW, ~StallW, InstrValidM, InstrValidW);
  flopenrc #(1) CompressedMReg(clk, reset, FlushM, ~StallM, CompressedE, CompressedM);

  // From a shadow fault until the redirect, the main pipeline holds wrong-path
  // instructions: nothing they produce may enter the queues.
  assign ShardPushOK = ~RecPending & ~sFault;
  assign QPushM      = MExitM & ShardPushOK;

  // The Writeback-stage result is stable for as long as the instruction sits there, so
  // push it on the first cycle rather than waiting for StallW to clear.  The shadow can
  // then finish verifying an instruction that the rest of the pipeline is waiting on.
  assign RQPushW = InstrValidW & ~WPushed & ShardPushOK;
  always_ff @(posedge clk)
    if (reset) WPushed <= 1'b0;
    else       WPushed <= StallW & (WPushed | RQPushW);

  always_ff @(posedge clk)
    if (reset | sFault) InFlight <= '0;
    else                InFlight <= InFlight + {{SHARD_CW{1'b0}}, QPushM} - {{SHARD_CW{1'b0}}, sCommit};

  assign ShadowIdleM = (InFlight == '0) & ~RecPending;

  // Freeze the main pipeline one short of a full RQ: the instruction already in
  // Writeback still has room, and every IQ/OQ entry belongs to an instruction that is
  // in the RQ or in Writeback, so no queue can overflow.
  assign ShardBackpressureW = (rqCount >= SHARD_CW'(SHARD_DEPTH-1));

  // Instructions whose effect cannot be deferred or undone wait in Memory until the
  // shadow is quiescent.  A pending trap waits the same way.
  assign NonMemSerialM = (InstrValidM & (CSRWriteFenceM | PrivilegedM | InvalidateICacheM | FlushDCacheM |
                                         FRegWriteM | FpLoadStoreM | FWriteIntM)) | TrapPendingM;

  // Memory-stage checks.  These cover what the trailing shadow cannot re-derive, and
  // what must be right before an instruction with a direct, irreversible effect runs.
  //  EA       second AGU adder and second address register on every memory access
  //  Operand  once the shadow is idle the register file is architecturally current, so
  //           the operands of the instruction in Memory must equal it (read through
  //           the shadow's ports, which are free then).  This verifies in place every
  //           instruction that waits for quiescence before acting.
  //  AMO, LoadFwd, CSR   duplicated datapaths in the LSU and CSR file
  //  MUL, FMA mod-3 residue checks of the two multipliers, which the shadow shares
  flopenrc #(P.XLEN) ShadowEAMReg(clk, reset, FlushM, ~StallM, SrcAE + SrcBE, ShadowEAM);
  assign EAFaultM = (|MemRWM) & (ShadowEAM != IEUAdrM);

  assign RegA4 = ShadowIdleM ? InstrM[19:15] : sRs1E;
  assign RegA5 = ShadowIdleM ? InstrM[24:20] : sRs2E;
  assign OperandFaultM = ShadowIdleM & ((ForwardedSrcAM != sRD1E) | (WriteDataM != sRD2E));

  assign ShardPreFaultM   = InstrValidM & (EAFaultM | OperandFaultM | CSRFaultM | MULFaultM | FMAFaultM);
  assign ShardLocalFaultM = ShardPreFaultM | (InstrValidM & (AMOFaultM | LoadFwdFaultM));

  // Fault response.
  //  Shadow fault (sFault): the queues are flushed at once; the main pipeline is
  //   redirected to the faulting instruction as soon as no bus operation is in flight
  //   (the condition an interrupt waits for).
  //  Memory-stage fault: the instruction is held, then flushed and refetched.
  // Either way nothing was committed, so the replay is exact.  A fault that repeats
  // SHARD_RETRY_LIMIT times with no instruction committing in between is not transient:
  // it becomes a precise cause-16 trap at the faulting instruction instead.
  // A CSR mirror state fault cannot be replayed away at all (one of the two copies is
  // already wrong), so it traps at once; the mirror is reloaded after the trap is taken
  // so that the fault is reported once.
  always_ff @(posedge clk)
    if (reset)             RecPending <= 1'b0;
    else if (sFault)       RecPending <= 1'b1;
    else if (RedirectRecM) RecPending <= 1'b0;
  flopen #(P.XLEN) RecPCReg(clk, sFault, sFaultPC, RecPC);

  assign RedirectRecM   = RecPending & ~CommittedM & ~CommittedF;
  assign EscalateRecM   = sFault & (RetryCount == SHARD_RETRY_LIMIT - 2'd1);
  assign EscalateLocalM = ShardLocalFaultM & ~RecPending & ~CommittedF & ~ShadowFaultTrapM &
                          (RetryCount == SHARD_RETRY_LIMIT - 2'd1);
  assign RedirectLocalM = ShardLocalFaultM & ~RecPending & ~CommittedF & ~ShadowFaultTrapM &
                          (RetryCount != SHARD_RETRY_LIMIT - 2'd1);

  assign ShardRedirectM   = RedirectRecM | RedirectLocalM;
  assign ShardRedirectPCM = RecPending ? RecPC : PCM;

  assign EscalateStateM = CSRStateFaultM & ~ShadowFaultTrapM & ~CSRMirrorResyncM;
  flopr #(1) CSRMirrorResyncReg(clk, reset, ShadowFaultTrapTakenM & CSRStateFaultM, CSRMirrorResyncM);

  always_ff @(posedge clk)
    if (reset | EscalateRecM | EscalateLocalM) RetryCount <= '0;
    else if (sFault | RedirectLocalM)          RetryCount <= sCommit ? 2'd1 : RetryCount + 2'd1;
    else if (sCommit)                          RetryCount <= '0;

  always_ff @(posedge clk)
    if (reset | ShadowFaultTrapTakenM)         ShadowFaultTrapM <= 1'b0;
    else if (EscalateRecM | EscalateLocalM | EscalateStateM) ShadowFaultTrapM <= 1'b1;
  flopen #(P.XLEN) ShadowFaultEPCReg(clk, EscalateRecM | EscalateLocalM | EscalateStateM, sFault ? sFaultPC : PCM, ShadowFaultEPCM);
  flopen #(P.XLEN) ShadowFaultMtvalReg(clk, EscalateRecM | EscalateLocalM | EscalateStateM,
    {{(P.XLEN-16){1'b0}}, CSRStateFaultM, FMAFaultM, MULFaultM, LoadFwdFaultM, AMOFaultM, CSRFaultM, OperandFaultM, EAFaultM,
     sFault ? sFaultClass : 8'b0}, ShadowFaultMtvalM);

  // MSECFAULT[6] logs every detection, recovered or not
  assign ShadowFaultW = sFault | RedirectLocalM | EscalateLocalM | EscalateStateM;

  shadow_iq #(.P(P), .DEPTH(SHARD_DEPTH)) siq(.clk, .reset, .Flush(sFault),
    .Push(QPushM), .PCM, .InstrM, .CompressedM, .Pop(iqPop),
    .sValid(iqValid), .sPC(iqPC), .sInstr(iqInstr), .sCompressed(iqCompressed));

  shadow_oq #(.P(P), .DEPTH(SHARD_DEPTH)) soq(.clk, .reset, .Flush(sFault),
    .Push(QPushM), .Pop(oqPop),
    .ForwardedSrcAM, .ForwardedSrcBM(WriteDataM), .IEUAdrM, .RawLoadWordM(RawReadDataWordM),
    .ALUSrcAM(ShardCtlM[27]), .ALUSrcBM(ShardCtlM[26]), .ImmSrcM(ShardCtlM[25:23]),
    .W64M(ShardCtlM[22]), .UW64M(ShardCtlM[21]), .SubArithM(ShardCtlM[20]),
    .ALUSelectM(ShardCtlM[19:17]), .BSelectM(ShardCtlM[16:13]), .ZBBSelectM(ShardCtlM[12:9]),
    .BALUControlM(ShardCtlM[8:6]), .BMUActiveM(ShardCtlM[5]), .CZeroM(ShardCtlM[4:3]),
    .ALUResultSrcM(ShardCtlM[2]), .JumpM(ShardCtlM[1]), .BranchM(ShardCtlM[0]),
    .PCSrcM, .RegWriteM, .ResultSrcM, .FWriteIntM,
    .ViaSQM(SQStoreM), .AMOM(AtomicM[1]), .LoadChkM(MemRWM[1] & ~FpLoadStoreM & ~BigEndianM),
    .s_ForwardedSrcA(oqForwardedSrcA), .s_ForwardedSrcB(oqForwardedSrcB),
    .s_IEUAdr(oqIEUAdr), .s_RawLoadWord(oqRawLoadWord),
    .s_ALUSrcA(oqALUSrcA), .s_ALUSrcB(oqALUSrcB), .s_ImmSrc(oqImmSrc),
    .s_W64(oqW64), .s_UW64(oqUW64), .s_SubArith(oqSubArith),
    .s_ALUSelect(oqALUSelect), .s_BSelect(oqBSelect), .s_ZBBSelect(oqZBBSelect),
    .s_BALUControl(oqBALUControl), .s_BMUActive(oqBMUActive), .s_CZero(oqCZero),
    .s_ALUResultSrc(oqALUResultSrc), .s_Jump(oqJump), .s_Branch(oqBranch),
    .s_PCSrc(oqPCSrc), .s_RegWrite(oqRegWrite), .s_ResultSrc(oqResultSrc), .s_FWriteInt(oqFWriteInt),
    .s_ViaSQ(oqViaSQ), .s_AMO(oqAMO), .s_LoadChk(oqLoadChk));

  shadow_rq #(.P(P), .DEPTH(SHARD_DEPTH)) srq(.clk, .reset, .Flush(sFault),
    .Push(RQPushW), .RdW, .RegWriteW(RegWriteW_s), .ResultW(ResultW_s), .Pop(sCommit),
    .Rs1E, .Rs2E, .RQ_HitA, .RQ_HitB, .RQ_ValA, .RQ_ValB,
    .sRd(rqRd), .sRegWrite(rqRegWrite), .sResult(rqResult), .Count(rqCount));

  shadow_sq #(.P(P), .DEPTH(SHARD_DEPTH)) ssq(.clk, .reset, .Flush(sFault),
    .Push(QPushM & SQStoreM), .PAdrM(SQPAdrM), .SizeM(Funct3M[1:0]), .WriteDataM(SQWriteDataM),
    .Verify(sCommitStore), .Pop(sqPop),
    .sqPA, .sqSize, .sqData, .Count(sqCount), .NVerified(sqNVerified));

  shadow_pipeline #(.P(P), .DEPTH(SHARD_DEPTH)) spipe(.clk, .reset, .StreamBreak(TrapM),
    .iqValid, .iqPC, .iqInstr, .iqCompressed, .iqPop,
    .oqForwardedSrcA, .oqForwardedSrcB, .oqIEUAdr, .oqRawLoadWord,
    .oqALUSrcA, .oqALUSrcB, .oqImmSrc, .oqW64, .oqUW64, .oqSubArith,
    .oqALUSelect, .oqBSelect, .oqZBBSelect, .oqBALUControl, .oqBMUActive, .oqCZero,
    .oqALUResultSrc, .oqJump, .oqBranch, .oqPCSrc, .oqRegWrite, .oqResultSrc, .oqFWriteInt,
    .oqViaSQ, .oqAMO, .oqLoadChk, .oqPop,
    .rqRd, .rqRegWrite, .rqResult, .rqCount, .rqPush(RQPushW),
    .sqPA, .sqSize, .sqData, .sqCount, .sqNVerified,
    .sRs1E, .sRs2E, .sRD1E, .sRD2E,
    .shadow_we3, .shadow_a3, .shadow_wd3,
    .Commit(sCommit), .CommitStore(sCommitStore),
    .Fault(sFault), .FaultPC(sFaultPC), .FaultClass(sFaultClass));

  // Capture an uncorrectable ECC error before presenting it to trap logic.  This
  // breaks the combinational DED -> TrapM -> flush/bus -> DED feedback path.
  // The existing PC attribution rule is preserved: an IFResultW error uses PCW;
  // all other aggregated errors use the current memory-stage PC.
  always_ff @(posedge clk) begin
    if (reset) begin
      EccDedFaultM      <= 1'b0;
      EccDedFaultEPCM   <= '0;
      EccDedFaultMtvalM <= '0;
    end else if (EccDedTrapTakenM) begin
      EccDedFaultM <= 1'b0;
    end else if (!EccDedFaultM && RegEccDedErrW) begin
      EccDedFaultM      <= 1'b1;
      EccDedFaultEPCM   <= RegEccDedErrPipeW ? PCW : PCM;
      EccDedFaultMtvalM <= (|MemRWM) ? IEUAdrxTvalM : '0;
    end
  end

  // DED fault is sticky: once a double-bit error is seen it holds until reset
  always_ff @(posedge clk)
    if (reset) RegEccDedErrSticky <= 1'b0;
    else       RegEccDedErrSticky <= RegEccDedErrSticky | RegEccDedErrW;

  // Combine privilege-mode TMR fault with sticky IEU ECC uncorrectable (DED) fault
  assign PrivModeUncorrectableFaultW = PrivModeUncorrectableFaultW_priv | RegEccDedErrSticky;

  // multiply/divide unit
  if (P.ZMMUL_SUPPORTED) begin : mdu
    mdu #(P) mdu(.clk, .reset, .StallM, .StallW, .FlushE, .FlushM, .FlushW,
      .ForwardedSrcAE, .ForwardedSrcBE,
      .Funct3E, .Funct3M, .IntDivE, .W64E, .MDUActiveE,
      .MDUResultW, .DivBusyE, .MULFaultM);
  end else begin // no M instructions supported
    assign MDUResultW = '0;
    assign DivBusyE   = 1'b0;
    assign MULFaultM  = 1'b0;
  end

  // floating point unit
  if (P.F_SUPPORTED) begin : fpu
    fpu #(P) fpu(
      .clk, .reset,
      .FRM_REGW,                           // Rounding mode from CSR
      .InstrD,                             // instruction from IFU
      .ReadDataW(ReadDataW[P.FLEN-1:0]),   // Read data from memory
      .ForwardedSrcAE,                     // Integer input being processed (from IEU)
      .StallE, .StallM, .StallW,           // stall signals from HZU
      .FlushE, .FlushM, .FlushW,           // flush signals from HZU
      .RdE, .RdM, .RdW,                    // which FP register to write to (from IEU)
      .STATUS_FS,                          // is floating-point enabled?
      .FRegWriteM,                         // FP register write enable
      .FpLoadStoreM,
      .ForwardedSrcBE,                     // Integer input for intdiv
      .Funct3E, .Funct3M, .IntDivE, .W64E, // Integer flags and functions
      .FPUStallD,                          // Stall the decode stage
      .FWriteIntE, .FCvtIntE,              // integer register write enable, conversion operation
      .FWriteDataM,                        // Data to be written to memory
      .FIntResM,                           // data to be written to integer register
      .FCvtIntResW,                        // fp -> int conversion result to be stored in int register
      .FCvtIntW,                           // fpu result selection
      .FDivBusyE,                          // Is the divide/sqrt unit busy (stall execute stage)
      .IllegalFPUInstrD,                   // Is the instruction an illegal fpu instruction
      .SetFflagsM,                         // FPU flags (to privileged unit)
      .FIntDivResultW, .FMAFaultM);
  end else begin                           // no F_SUPPORTED or D_SUPPORTED; tie outputs low
    assign {FPUStallD, FWriteIntE, FCvtIntE, FIntResM, FCvtIntW, FRegWriteM,
            IllegalFPUInstrD, SetFflagsM, FpLoadStoreM, FMAFaultM,
            FWriteDataM, FCvtIntResW, FIntDivResultW, FDivBusyE} = '0;
  end

endmodule
```

---

## 12. Fault response

### 12.1 The logic

```systemverilog
  localparam logic [1:0] SHARD_RETRY_LIMIT = 2'd3;

  always_ff @(posedge clk)
    if (reset)             RecPending <= 1'b0;
    else if (sFault)       RecPending <= 1'b1;
    else if (RedirectRecM) RecPending <= 1'b0;
  flopen #(P.XLEN) RecPCReg(clk, sFault, sFaultPC, RecPC);

  assign RedirectRecM   = RecPending & ~CommittedM & ~CommittedF;
  assign EscalateRecM   = sFault & (RetryCount == SHARD_RETRY_LIMIT - 2'd1);
  assign EscalateLocalM = ShardLocalFaultM & ~RecPending & ~CommittedF & ~ShadowFaultTrapM &
                          (RetryCount == SHARD_RETRY_LIMIT - 2'd1);
  assign RedirectLocalM = ShardLocalFaultM & ~RecPending & ~CommittedF & ~ShadowFaultTrapM &
                          (RetryCount != SHARD_RETRY_LIMIT - 2'd1);

  assign ShardRedirectM   = RedirectRecM | RedirectLocalM;
  assign ShardRedirectPCM = RecPending ? RecPC : PCM;

  assign EscalateStateM = CSRStateFaultM & ~ShadowFaultTrapM & ~CSRMirrorResyncM;
  flopr #(1) CSRMirrorResyncReg(clk, reset, ShadowFaultTrapTakenM & CSRStateFaultM, CSRMirrorResyncM);

  always_ff @(posedge clk)
    if (reset | EscalateRecM | EscalateLocalM) RetryCount <= '0;
    else if (sFault | RedirectLocalM)          RetryCount <= sCommit ? 2'd1 : RetryCount + 2'd1;
    else if (sCommit)                          RetryCount <= '0;

  always_ff @(posedge clk)
    if (reset | ShadowFaultTrapTakenM)         ShadowFaultTrapM <= 1'b0;
    else if (EscalateRecM | EscalateLocalM | EscalateStateM) ShadowFaultTrapM <= 1'b1;
  flopen #(P.XLEN) ShadowFaultEPCReg(clk, EscalateRecM | EscalateLocalM | EscalateStateM,
                                     sFault ? sFaultPC : PCM, ShadowFaultEPCM);
  flopen #(P.XLEN) ShadowFaultMtvalReg(clk, EscalateRecM | EscalateLocalM | EscalateStateM,
    {{(P.XLEN-16){1'b0}}, CSRStateFaultM, FMAFaultM, MULFaultM, LoadFwdFaultM, AMOFaultM, CSRFaultM,
     OperandFaultM, EAFaultM, sFault ? sFaultClass : 8'b0}, ShadowFaultMtvalM);

  assign ShadowFaultW = sFault | RedirectLocalM | EscalateLocalM | EscalateStateM;   // -> MSECFAULT[6]
```

### 12.2 A shadow fault

1. Cycle *t*: `sW` holds an instruction with a non-zero fault vector. `Fault = 1`,
   `Commit = 0`: no regfile write, no RQ pop, no SQ verify.
2. Edge *t → t+1*: IQ, OQ, RQ emptied; SQ truncated to its verified prefix; shadow
   stages cleared; `InFlight ← 0`; `RecPending ← 1`; `RecPC ← FaultPC`; the
   next-PC chain is set to expect `FaultPC`.
3. While `RecPending`: `ShardPushOK = 0`, so wrong-path instructions still in the
   main pipeline enter no queue. `ShadowIdleM = 0`, so nothing serialized acts and
   no trap is taken. Verified stores keep draining.
4. As soon as `~CommittedM & ~CommittedF` (the condition an interrupt waits for —
   no cache miss, bus access or walk in flight): `ShardRedirectM` for one cycle,
   D/E/M/W flushed, `PCF ← RecPC`, `RecPending ← 0`.
5. Fetch resumes at the faulting instruction. Architectural state is exactly as it
   was before that instruction: the regfile and memory hold only verified effects
   and nothing serialized ran while anything was unverified.

### 12.3 A Memory-stage fault

The instruction in M fails a check. `ShardLocalFaultM` stalls the pipeline
(`ShardStallW`); if the failing check is outside the LSU the instruction is also
hidden from memory (`ShardPreFaultM` → `HoldM`). When `~CommittedF` (and no shadow
recovery is pending, which would flush it anyway), `RedirectLocalM`: flush,
`PCF ← PCM`. The redirect cycle is a flush cycle, so the instruction's own effect
is cancelled exactly as a trap on it would cancel it. Older instructions in W and
in the queues are unaffected and continue through the shadow.

### 12.4 Escalation

`RetryCount` counts fault events with no shadow commit in between. On the third
(`SHARD_RETRY_LIMIT`) the fault is not transient:

- a Memory-stage fault is *not* redirected again; instead `ShadowFaultTrapM` is
  set. The instruction stays held (the fault persists), the trap logic sees an
  exception, and the trap is taken when the shadow is quiescent;
- a shadow fault is redirected as usual *and* `ShadowFaultTrapM` is set; the
  refetched instruction is held in M by `TrapPendingM` and the trap is taken;
- `mepc = ShadowFaultEPCM` (the faulting instruction), `mcause = 16`, always to
  M-mode, `mtval = ShadowFaultMtvalM`:

| `mtval` bit | meaning |
|---|---|
| 7:0 | shadow fault vector (§5.3), valid when the escalation came from a shadow fault |
| 8 | EA |
| 9 | Operand |
| 10 | CSR read/write value |
| 11 | AMO |
| 12 | store-queue merge |
| 13 | MUL residue |
| 14 | FMA residue |
| 15 | CSR state |

  Bits 8–15 are the live values of those checks at the escalation cycle.

A **CSR state fault** cannot be replayed away — one of the two copies is already
wrong — so it sets `ShadowFaultTrapM` at once. One cycle after that trap is taken,
`CSRMirrorResyncM` reloads the mirror from the main registers so the fault is
reported once. (Which copy was right is unknowable with two copies; the handler is
told, and decides.)

`MSECFAULT[6]` (`ShadowFaultW`) is set on every detection, recovered or not.

There is no enable bit and no detect-only mode.

---

## 13. Integer divide — **specified here, NOT implemented or tested**

`div`/`divu`/`rem`/`remu` (and the W forms) are the one class of plain integer
instruction whose result is not checked: the shadow verifies the operands and
takes the quotient or remainder from the main pipeline. Nothing in §5–§12 covers
it. This section specifies a check that fits the same pattern as the multiplier's.
Treat it as a design to be implemented and validated, with the caveats stated.

**Applies to** the `IDIV_ON_FPU = 0` divider (`mdu/div.sv`), which presents both
`QuotM` and `RemM` in the Memory stage. (With `IDIV_ON_FPU = 1` only the selected
result leaves the FPU; the same check would have to sit inside `fdivsqrt`'s integer
post-processing.)

**Relation checked.** For operands *n*, *d* and results *q*, *r* read as integers
of width *w* (64, or 32 for the W forms; signed or unsigned per the instruction):

```
normal case:        n = q·d + r      and   |r| < |d|      and   (r == 0  or  sign(r) == sign(n))
divide by zero:     q == all ones (w bits)   and   r == n
signed overflow:    (n == -2^(w-1), d == -1)   →   q == n   and   r == 0
```
The first relation with the range and sign conditions determines *q* and *r*
uniquely, so checking all three is equivalent to checking the divide.

**Checking `n = q·d + r` without a multiplier.** Use residues. *Do not reuse the
mod-3 residue here.* An error *e* in the quotient changes `q·d` by `e·d`, which is
invisible mod 3 whenever *d* is a multiple of 3 — one divisor in three. Use the
modulus `M = 2^16 − 1 = 65535` instead: a single-bit quotient error is then missed
only when *d* is a multiple of 65535, and a single-bit remainder error is never
missed. (A wider modulus is stronger still; the cost is one 16×16 multiply.)

- Residue mod `2^16 − 1` of an unsigned value: add its 16-bit digits with
  end-around carry (fold the sum until it fits 16 bits; treat `0xFFFF` as 0).
- `2^32 ≡ 2^64 ≡ 1 (mod 65535)`, so a signed *w*-bit value has residue
  `res_unsigned − sign` (mod *M*), as in §10.2.

**Signals** (names are suggestions):

| Stage | Compute |
|---|---|
| Execute, registered at the E→M edge (`flopenrc`, clear `FlushM`, enable `~StallM`). Execute is stalled during the divide and `ForwardedSrcAE/BE` are stable and exact (W7), so sampling at the edge the instruction leaves Execute is correct | `n = W64E ? A[31:0] : A`, `d = W64E ? B[31:0] : B`; `Sgn = ~Funct3E[0]` (the divider's `DivSignedE`); `sn = Sgn & n[w-1]`, `sd = Sgn & d[w-1]`; `ResN = res(n) − sn`, `ResD = res(d) − sd`; `Div0 = (d == 0)`; `Ovf = Sgn & (n == 100…0) & (d == 111…1)`; `DAbs = sd ? −d : d` (w bits); `DivM = IntDivE`; keep `n` (w bits) for the divide-by-zero and overflow compares |
| Memory | `q = QuotM`, `r = RemM` (low 32 bits for W forms); `sq = Sgn & q[w-1]`, `sr = Sgn & r[w-1]`; `ResQ = res(q) − sq`, `ResR = res(r) − sr`; `RAbs = sr ? −r : r` |
| | `RelFault = ((ResQ·ResD + ResR) mod M) != ResN` |
| | `RangeFault = (RAbs >= DAbs) \| (Sgn & (r != 0) & (sr != sn))` |
| | `DIVFaultM = DivM & ( Div0 ? (q != all ones \| r != n) : Ovf ? (q != n \| r != 0) : (RelFault \| RangeFault) )` |

Then OR `DIVFaultM` into `ShardPreFaultM` (§11.3) and give it an `mtval` bit. The
response is the existing one: hold, replay, escalate.

**Things to verify when implementing** (they are read off `div.sv`, not tested):
- For W forms the divider left-justifies the dividend (`{A[31:0], 32'b0}`) and runs
  half the steps; the 32-bit quotient and remainder are taken to be the low 32 bits
  of `QuotM`/`RemM`. Confirm in simulation, including the divide-by-zero remainder,
  which the divider takes from the original `ForwardedSrcAE`.
- The architectural result goes through `PrelimResultM` and the W sign extension in
  `mdu.sv` after this point; like the multiply's half-select that mux is not
  covered.
- Soundness first: run the regressions and a Linux boot with a counter on
  `DIVFaultM` and require zero, as in §17, before trusting it. `tc_mul_div` and
  `tc_shard_spec` exercise signed, unsigned and W divides; add divide-by-zero and
  `INT_MIN / -1` cases.

An exact alternative is to compute `q·d + r` with the main multiplier, which is
idle while a divide occupies Execute; it needs operand muxing into `mul` and one
extra cycle per divide, and was not designed in detail.

---

## 14. Pitfalls — every one of these was hit or analysed while building Rev 8

**Deadlocks**

- **P1 — a wait on the shadow that also blocks the shadow's input.** Any hold that
  waits for the shadow stalls the pipeline, including W. If the RQ push needed
  `~StallW`, the instruction in W — usually the very one being waited for — would
  never reach the shadow. The RQ push must depend only on "first cycle in W".
- **P2 — a shadow that advances with the main pipeline.** Same deadlock, one level
  up. The shadow's only inputs are queue occupancy and its own state.
- **P3 — page walk with stores buffered.** If the walker is allowed to start it
  owns the LSU and the drain engine cannot run; if it is made to wait by its own
  stall-and-flush mechanism, its flush cancels the drain engine's writes. Gate the
  walker's *inputs* (`WalkOK`) and let `HoldM` do the waiting.

**Combinational loops and oscillations**

- **P4 — a fault signal gated by the stall it causes.** `CSRFaultM` was originally
  gated by `InstrValidNotFlushedM` (which contains `~StallW`). A Memory-stage fault
  stalls the pipeline, which cleared the fault, which released the stall. Every
  Memory-stage fault signal must be a function of M-stage state only: gate with
  `InstrValidM`, never with `StallW` or `FlushW`.
- **P5 — a fault signal gated by the flush it causes.** `AMOFaultM` was originally
  `… & ~LSUFlushW`. The fault raises the redirect, the redirect is `FlushW`, which
  is `LSUFlushW`, which cleared the fault. Remove the term.
- **P6 — LSU faults in the LSU mask.** `ShardMaskM` controls
  `CacheableOrFlushCacheM`, which selects the read-data mux, which feeds
  `LoadFwdFaultM` and `AMOFaultM`. Feeding those two back into `HoldM` closes a
  loop. They stall through the hazard unit (`ShardStallW`) instead and never enter
  the mask; only faults computed outside the LSU go into `ShardPreFaultM`.
- **P7 — injecting or deriving anything from `StallE`/`FlushE` into `PCSrcE`.**
  `FlushE` depends on `BPWrongE`, which depends on `PCSrcE`. (Relevant to
  injection hooks, §17.3.)

**Things that leak past a hold**

- **P8 — the LSU starts without being asked twice.** Stalling is not enough; the
  request must be hidden from the cache and bus (§7.3), including in the cycle the
  drain engine starts.
- **P9 — `FlushDCacheM` and `CMOpM` are raw IEU signals.** They reach the cache
  without passing through the read/write chain and need their own masks, and so
  does `CacheableOrFlushCacheM` (a `fence.i` waiting in M makes an *uncacheable*
  drain look cacheable to the bus interface).
- **P10 — `FpLoadStoreM` selects the write data.** During a drain it must not.
- **P11 — the mask must not apply to the drain engine or the walker.** A hold on
  the M-stage instruction is usually still asserted while the engine writes; if the
  mask zeroed `LSURWM` unconditionally the engine's own write would vanish.
  `LSURWMaskedM` passes `LSURWM` through whenever `SQDrainSel | SelHPTW`.
- **P12 — the cache must not see the engine's stall.** `GatedStallW` needs
  `~SQOwnsLSUM` (start cycle included) or the SRAM read of the head's set never
  happens and the write uses stale tags.
- **P13 — a pipeline flush must not cancel the drain write.** `LSUFlushW` is masked
  while `SQBusy`.
- **P14 — `mret`/`sret`, `mstatus.FS` and the LR reservation are not flush-gated**
  (§9.2, §9.3, §7.7).
- **P15 — the HPTW's one-cycle `FAULT` state.** A trap that cannot be taken in that
  cycle must stall, or the faulting instruction retires (§9.1).

**Correctness of the checks**

- **P16 — restart at the expected PC**, and re-arm the next-PC chain with it
  (§5.1).
- **P17 — an illegal CSR access must not be compared with the mirror** (§9.3).
- **P18 — the CSR checks must not take `rs1` from the path they are checking.**
  Use `ForwardedSrcAM`, not `SrcAM`.
- **P19 — the Operand check needs `ShadowIdleM`**, not merely an empty RQ: an
  instruction in W that has not yet been pushed is still unverified. `InFlight`
  counts from `MExitM`, which covers it.
- **P20 — residue sign corrections need an even operand width** (`2^XLEN ≡ 1 mod
  3`). True for 32 and 64.
- **P21 — a mod-3 residue is not adequate for divide** (§13).
- **P22 — the bus must never see `BusAtomic`.**

**Verification environment**

- **P23 — the testbench observes retirement from main W**, which under Rev 8 is
  *proposed*, not committed (§16).
- **P24 — anything that tapped `regf.a1/a2` as the Decode register numbers** now
  gets Execute's.

---

## 15. What depends on the configuration

The RTL above is parameterised by the existing `cvw_t P`; no SHARD file is
configuration-specific. What changes is which paths exist and which checks have
anything to do.

**How the simulator picks a configuration.** In the validated tree the simulation
wrapper (`hdl/rv64_core_wrapper.sv`) has `` `include "config.vh" `` at file scope,
so every simulation target elaborates `pkg/config.vh` regardless of
`+define+AMOEBA_CONFIG_*` (those select a config only in the synthesis/FPGA tops
through `amoeba_config_select.vh`). To simulate another configuration, make the
wrapper include it. The pruned-config evidence in §0 was obtained by substituting
`config_baremetal_linux.vh` for `config.vh`. That configuration also raises one
Verilator warning unrelated to SHARD (`bpred.sv`: `BPDirWrongM` not driven under that
configuration's predictor settings), which is fatal under `-Wall` unless waived.

### 15.1 No FPU; divider in the MDU (`F_SUPPORTED = 0`, `IDIV_ON_FPU = 0`)

- The core's existing no-FPU branch ties `FRegWriteM`, `FpLoadStoreM`,
  `FWriteIntE`, `FCvtIntE`, `SetFflagsM`, `FWriteDataM`, `FDivBusyE`, … to 0. Add
  `FMAFaultM` to that list. `FWriteIntM` (from the controller's pipeline register)
  is then always 0.
- Consequences, all automatic: no instruction is serialized for being FP;
  `SimpleMemOKM`'s `~FpLoadStoreM` is constant; the OQ's `FWriteInt` bit is 0 so
  `ALUClass = (ResultSrc == 000)`; the mirror's `FS` view is forced to 0 on both
  sides (main and mirror each still store the bits written to `mstatus[14:13]`,
  and both mask them in the view); `FSDirtyM` never fires; `LLEN = XLEN`.
- `fma.sv`/`fpu.sv` are not instantiated; skip §10.3.
- **Integer divide now runs in `mdu/div.sv` and is unverified.** This is the one
  material gap for a no-FP Linux core. §13 is written for exactly this divider.
- Instrumentation or injection code that references `fpu.*` hierarchically will not
  elaborate; remove those lines.

### 15.2 No misaligned access, no cache-block operations, no Svadu

- **`ZICCLSM = 0`.** The misaligned-access unit (`align`) is not instantiated and
  the cache word is `LLEN` wide; the one edit to its instance (`.SelHPTW(SelHPTW |
  SQOwnsLSUM)`) does not apply. A misaligned access raises
  `Load/StoreAmoMisalignedFaultM`. It is still classified `SerialMemM` (not
  aligned), so it waits for quiescence and then traps — correct, and nothing to
  change. OpenSBI emulates it.
- **`ZICBOM = ZICBOZ = 0`.** `CMOpM` is constant 0; the `CacheCMOpM`/`BusCMOZero`
  generate branch is the constant one; `WriteDataZM = WriteDataM`. The `|CMOpM`
  terms in `SimpleMemOKM`, `SerialMemM` and `SQRestoreM` fold away.
- **`SVADU = 0`.** The walker never writes a PTE. The `WalkOK` gate is still
  required as built: a walk's PTE *reads* go through the cache, and the design
  relies on the SQ being empty rather than on the byte-merge for them. (The merge
  does sit in the walker's read path, so relaxing the gate for read-only walks is
  plausible, but it was not tested and saves little.)
- **`BIGENDIAN_SUPPORTED = 0`.** `BigEndianM` is constant 0; no access is
  serialized for endianness.

### 15.3 Cache and bus

- **Geometry** (ways, way size, line length) does not appear anywhere in SHARD. The
  drain engine uses the cache's own hit/miss/evict machinery; the merge matches on
  the full physical word address. The only assumption is Wally's own: the set index
  lies within the page offset. The pruned config's 4 × 2 KiB D-cache needs no
  change.
- **Word size.** An SQ entry is one naturally aligned access of at most `XLEN`
  bits. The merge works on `LLEN/8` bytes and compares `PA[PA_BITS-1:log2(LLEN/8)]`.
- **Bus without a D-cache** (`BUS_SUPPORTED = 1`, `DCACHE_SUPPORTED = 0`): the code
  handles it (the read/write mask and `BusAtomic = 0` are applied in that branch;
  `CommittedM` is the bus FSM's), and the drain becomes a bus write per store. The
  `ADR` and `RESTORE` cycles are then harmless no-ops. **Not validated.**
- **DTIM.** `SimpleMemOKM` excludes `SelDTIM`, so every DTIM access is serialized
  and runs through the legacy path with the SQ empty. **Not validated.** (The DTIM is
  addressed with the untranslated address, as in stock Wally.)
- **Uncacheable regions** need no configuration: device stores are queued and
  drained to the bus in order; device reads are serialized.
- **No PMP** (`PMP_ENTRIES = 0`): nothing changes. With PMP, the drain relies on
  PMP state not changing while a store is buffered, which holds because PMP CSR
  writes are serialized.

### 15.4 RV32 or another `XLEN` — **not validated**

Everything is written against `P.XLEN`/`P.LLEN`, with these width-dependent points:

- `AlignedM`: `Funct3M[1:0] == 2'b11` (doubleword) does not occur.
- The merge: `LLENBYTES = 4` (or 8 on RV32 with `D`, where `LLEN = 64 > XLEN`; the
  replication cases cover both).
- `shadow_csr`: the RV32 branches for `mstatus`, `mstatush` (MBE/SBE live there)
  and `satp` (`SV32`) are written but have never been elaborated.
- Residue checks: 32 is even, so the sign corrections hold; the product is 64 bits.
- `shadow_verifier` passes `mIEUAdr[3:0]` and a zero-extended raw word to
  `subwordread`; check against the target's `subwordread` port widths.
- The injection hooks in §17.3 use literal 64-bit concatenations.

### 15.5 Other parameters

| Parameter | Effect |
|---|---|
| `ZAAMO_SUPPORTED`, `ZALRSC_SUPPORTED` | `atomic`/`lrsc`, the LSU's second `amoalu` and the verifier's `amoalu` are generated only when present; without `ZAAMO`, `AMOFaultM = 0` and the verifier's store data is `rs2` |
| `VIRTMEM_SUPPORTED = 0` | no HPTW: assign the `H…` signals straight from the IEU signals (the existing `else` branch); the TLB-miss term of `HoldM` is 0 |
| `S_SUPPORTED = 0` / `U_SUPPORTED = 0` | the mirror's supervisor registers stay 0 and `csr.sv` assigns the main ones 0; `MirrorHitM` is 0 for supervisor addresses |
| `ZCA_SUPPORTED` | the mirror's `xepc` alignment and `MEDELEG_MASK`; the compressed flag in the IQ |
| `BPRED_SUPPORTED`, predictor type | none. The next-PC check works on retired PCs |
| Bit-manipulation / crypto / `ZICOND` extensions | the shadow instantiates the same `alu` with the same parameter, so it follows automatically; the control bits concerned are constant when an extension is off |
| `IDIV_BITSPERCYCLE` | none (divide is not checked; §13 is independent of it) |
| `SSTC`, `PLIC`, counters | none; not mirrored |
| `ZICNTR_SUPPORTED = 0` | none for SHARD. A test that executes `rdcycle` (the repository's `tc_branch_prediction` does) takes an illegal-instruction trap and cannot be used on such a configuration |
| `SHARD_DEPTH` | 8 as built, 4 exercised for stress only; no other value tried (§4.3) |
| `SHARD_RETRY_LIMIT` | 3 as built; `RetryCount` is 2 bits |

---

## 16. Effects on the test environment

- **RVFI and co-simulation still observe main Writeback.** The wrapper reports an
  instruction when `InstrValidW & ~StallW`, with `RdW`/`RegWriteW`/`ResultW` as the
  register write. In a fault-free run that stream is exactly what the shadow
  commits, so RVFI and Spike co-simulation pass unchanged. Under fault injection
  the main pipeline can retire a wrong-path instruction that the shadow then
  squashes; the monitor sees it, and — more importantly — the testbench's
  `tohost` detector, which watches RVFI store retirement, can end the test on a
  wrong-path "exit(n)" store that never reaches memory. Injection runs must be
  judged at the store-buffer drain (§17.3).
- **The wrapper's register-number taps.** It read `ieu.dp.regf.a1/a2` as the
  Decode-stage `rs1/rs2`; those are now Execute-stage. Tap the controller's
  `Rs1D/Rs2D` instead.
- **The riscv-formal monitor treats a misaligned access as a trap.** Outside the
  Linux build there is no waiver, so a test with misaligned accesses must run
  without the monitor (`+define+ECE411_NO_RVFI`). Not SHARD-specific.
- **Performance.** Cycles to completion, Rev 7 → Rev 8: `sorting_algo` 10,426 →
  12,421 (+19%); `tc_branch_prediction` 245,075 → 251,266 (+2.5%); FreeRTOS
  `tc_timer_preempt` 265,652 → 286,351 (+7.8%); Linux boot about 173M → 191.6M
  (+11%). The cost is the single-ported D-cache: each drained store stalls the
  pipeline two or three cycles. Reading the regfile in Execute lengthens that
  stage; it has not been through timing closure.
- **Synthesis.** The second `amoalu`, CSR modify datapath, store-queue merge and AGU
  adder are identical copies of logic next to them; a synthesis tool will merge
  them unless told not to.

---

## 17. Proving a port

### 17.1 Order of bring-up

1. Build. Run one trivial program. With the instrumentation of §17.2 it must show
   every instruction committed by the shadow and zero faults.
2. Programs with calls and memory traffic (forwarding depth, store-to-load).
3. Tests with traps, interrupts and CSR traffic (an RTOS). This is where the trap
   gating, the mirror and `mret` handling first run.
4. `tc_shard_spec` (§17.4): AMO, LR/SC, signed multiplies, CSR round trips.
5. With an FPU or misaligned support: `tc_shard_direct`.
6. Linux boot: virtual memory, page walks with stores buffered, device I/O through
   the store buffer, `wfi`, delegation, `sret`.
7. Stress the interlocks: rebuild with `SHARD_DEPTH = 4`; everything must still
   pass.
8. Fault injection (§17.3).

### 17.2 Soundness instrumentation

A false fault does not fail a test — it is replayed away — so "the tests pass" does
not show the checks are sound. Count the events. The blocks below were present for
validation and removed afterwards; they print a line per fault (first 40), a
summary every 2^23 cycles, and totals at the end. **Required result: `faults=0
localfaults=0 redirects=0 traps16=0` on every run, with the per-check counters
non-zero for the classes the program uses.**

In `shadow_pipeline.sv`, before `endmodule`:

```systemverilog
  // synthesis translate_off
  // SHARD_DEBUG (temporary)
  longint unsigned dbg_commits, dbg_faults, dbg_stores, dbg_loads;
  always_ff @(posedge clk) begin
    if (reset) begin dbg_commits <= 0; dbg_faults <= 0; dbg_stores <= 0; dbg_loads <= 0; end
    else begin
      if (Commit) dbg_commits <= dbg_commits + 1;
      if (CommitStore) dbg_stores <= dbg_stores + 1;
      if (sValidM & sLoadChkM) dbg_loads <= dbg_loads + 1;
      if (Fault) dbg_faults <= dbg_faults + 1;
      if (sValidM & (|sFaultM) & (dbg_faults < 40))
        $display("[SHARD] t=%0t sM FAULT cls=%b pc=%h instr=%h | res s=%h rq=%h | sum s=%h m=%h | taken s=%b m=%b | srcB=%h raw=%h | rqRd=%0d rqRW=%b mRW=%b | sq idx=%0d cnt=%0d nv=%0d pa=%h sz=%0d data=%h | commits=%0d",
          $time, sFaultM, sRestartPCM, sInstrM, sIEUResultM, rqResult[rqSelM], sSumM, sIEUAdrM, sTakenM, sPCSrcM, sSrcBM, sRawLoadWordM,
          rqRd[rqSelM], rqRegWrite[rqSelM], sRegWriteM, sqIdxM, sqCount, sqNVerified, sqPA[sqIdxM[$clog2(DEPTH)-1:0]], sqSize[sqIdxM[$clog2(DEPTH)-1:0]], sqData[sqIdxM[$clog2(DEPTH)-1:0]], dbg_commits);
      if (sValidE & sOpFaultE & (dbg_faults < 40))
        $display("[SHARD] t=%0t sE OPFAULT pc=%h instr=%h sA=%h mA=%h sB=%h mB=%h fwdA=%b fwdB=%b", $time, sPCE, sInstrE, sForwardedSrcAE, oqForwardedSrcA, sForwardedSrcBE, oqForwardedSrcB, sForwardAE, sForwardBE);
      if (sValidE & sNPCFaultE & (dbg_faults < 40))
        $display("[SHARD] t=%0t sE NPCFAULT pc=%h exp=%h", $time, sPCE, NPCExpected);
    end
  end
  final $display("[SHARD] SUMMARY commits=%0d stores=%0d loads=%0d faults=%0d", dbg_commits, dbg_stores, dbg_loads, dbg_faults);
  // synthesis translate_on
```

In `wallypipelinedcore.sv`, before the queue instantiations (drop the `fpu.` line
without an FPU):

```systemverilog
  // synthesis translate_off
  // SHARD_DEBUG (temporary)
  longint unsigned dbg_localfaults, dbg_redir, dbg_traps, dbg_holdcyc, dbg_draincyc, dbg_bpcyc, dbg_cyc, dbg_opchk;
  longint unsigned dbg_mul, dbg_fma, dbg_csrrd, dbg_csrwr, dbg_amo, dbg_ldfwd, dbg_ea, dbg_trapsM, dbg_serial, dbg_sqpush;
  always_ff @(posedge clk) begin
    if (reset) begin dbg_localfaults <= 0; dbg_redir <= 0; dbg_traps <= 0; dbg_holdcyc <= 0; dbg_draincyc <= 0; dbg_bpcyc <= 0; dbg_cyc <= 0; dbg_opchk <= 0; end
    else begin
      dbg_cyc <= dbg_cyc + 1;
      if (lsu.HoldM) dbg_holdcyc <= dbg_holdcyc + 1;
      if (lsu.SQBusy) dbg_draincyc <= dbg_draincyc + 1;
      if (ShardBackpressureW) dbg_bpcyc <= dbg_bpcyc + 1;
      if (InstrValidM & ShadowIdleM & ~StallW & ~FlushW) dbg_opchk <= dbg_opchk + 1;
      if (MExitM & mdu.mdu.MulM) dbg_mul <= dbg_mul + 1;
      if (MExitM & (FRegWriteM | FWriteIntM) & fpu.fpu.FMAFaultMReg.q !== 1'bx & (fpu.fpu.PostProcSelM == 2'b10)) dbg_fma <= dbg_fma + 1;
      if (MExitM & CSRReadM & priv.priv.csr.MirrorHitM) dbg_csrrd <= dbg_csrrd + 1;
      if (MExitM & CSRWriteM) dbg_csrwr <= dbg_csrwr + 1;
      if (MExitM & AtomicM[1]) dbg_amo <= dbg_amo + 1;
      if (MExitM & MemRWM[1] & (lsu.ReadDataWordFwdM != lsu.ReadDataWordMuxM)) dbg_ldfwd <= dbg_ldfwd + 1;
      if (MExitM & (|MemRWM)) dbg_ea <= dbg_ea + 1;
      if (TrapM) dbg_trapsM <= dbg_trapsM + 1;
      if (MExitM & (NonMemSerialM | lsu.SerialMemM)) dbg_serial <= dbg_serial + 1;
      if (QPushM & SQStoreM) dbg_sqpush <= dbg_sqpush + 1;
      if (ShardRedirectM) dbg_redir <= dbg_redir + 1;
      if (dbg_cyc[22:0] == '1)
        $display("[SHARD] WINDOW cyc=%0d commits=%0d shadowfaults=%0d localfaults=%0d redirects=%0d traps16=%0d | mul=%0d csr_rd=%0d csr_wr=%0d amo=%0d ld_fwd=%0d traps=%0d serialized=%0d sq_push=%0d hold=%0d drain=%0d",
          dbg_cyc, spipe.dbg_commits, spipe.dbg_faults, dbg_localfaults, dbg_redir, dbg_traps, dbg_mul, dbg_csrrd, dbg_csrwr, dbg_amo, dbg_ldfwd, dbg_trapsM, dbg_serial, dbg_sqpush, dbg_holdcyc, dbg_draincyc);
      if (ShadowFaultTrapTakenM) begin dbg_traps <= dbg_traps + 1; $display("[SHARD] t=%0t CAUSE16 TRAP epc=%h mtval=%h", $time, ShadowFaultEPCM, ShadowFaultMtvalM); end
      if (RedirectLocalM | EscalateLocalM) begin
        dbg_localfaults <= dbg_localfaults + 1;
        if (dbg_localfaults < 40)
          $display("[SHARD] t=%0t LOCALFAULT pc=%h instr=%h ea=%b op=%b csr=%b amo=%b ldfwd=%b mul=%b fma=%b | A=%h rfA=%h B=%h rfB=%h | retry=%0d esc=%b",
            $time, PCM, InstrM, EAFaultM, OperandFaultM, CSRFaultM, AMOFaultM, LoadFwdFaultM, MULFaultM, FMAFaultM, ForwardedSrcAM, sRD1E, WriteDataM, sRD2E, RetryCount, EscalateLocalM);
      end
      if (EscalateStateM) $display("[SHARD] t=%0t CSR STATE FAULT pc=%h", $time, PCM);
      if (RedirectRecM & (dbg_redir < 40)) $display("[SHARD] t=%0t RECOVERY redirect pc=%h", $time, RecPC);
    end
  end
  final $display("[SHARD] CHECKS mul=%0d fma=%0d csr_rd(mirror)=%0d csr_wr=%0d amo=%0d ld_fwd=%0d ea=%0d traps=%0d serialized=%0d sq_push=%0d", dbg_mul, dbg_fma, dbg_csrrd, dbg_csrwr, dbg_amo, dbg_ldfwd, dbg_ea, dbg_trapsM, dbg_serial, dbg_sqpush);
  final $display("[SHARD] CORE cycles=%0d hold=%0d drain=%0d backpressure=%0d opchk=%0d localfaults=%0d redirects=%0d traps16=%0d", dbg_cyc, dbg_holdcyc, dbg_draincyc, dbg_bpcyc, dbg_opchk, dbg_localfaults, dbg_redir, dbg_traps);
  // synthesis translate_on
```

Reference counts from the validated Linux boot (config.vh): 50,417,723 instructions
committed; 8,996,635 stores through the SQ; 8,810,989 loads re-derived; 32,705 loads
with a byte from the SQ; 17,906,966 memory accesses through the EA check; 4,472,459
Memory-stage operand checks; 1,064,651 serialized instructions; 75,169 AMOs; 74,175
mirrored CSR reads and 72,405 CSR writes; 325 traps; 85,827 multiplies; drain owned
the LSU for 57.2M of 191.6M cycles; holds 5.0M cycles; backpressure 0.

### 17.3 Fault injection

Each check must be shown to fire and the response to work. The hooks below flip
one bit at a named point for exactly one victim instruction (or for every
qualifying instruction when `+SHARD_INJ_PERSIST=1`), selected by plusargs:
`+SHARD_INJ=<id> +SHARD_INJ_N=<which qualifying instruction>`.

Control block, in `wallypipelinedcore.sv` (simulation only). The victim is chosen
when it *arrives* in Execute or Memory and stays the victim until it leaves, so the
injection disappears on the replay; qualifiers use registered arrival flags, never
`StallE/FlushE/StallW` directly (P4, P7). The last `always_ff` judges the test by
the `tohost` store that actually drains (P23); the testbench's own RVFI-based
`tohost` detector must be disabled while `inj_sel != 0`.

```systemverilog
  // SHARD_INJ (temporary fault injection)
  int unsigned inj_sel, inj_n, inj_persist;
  longint unsigned inj_evt;
  logic inj_qual, inj_hit, inj_hold, inj_on, EArrE, MArrM, inj_eclass, inj_mclass;
  initial begin
    inj_sel = 0; inj_n = 0; inj_persist = 0;
    void'($value$plusargs("SHARD_INJ=%d", inj_sel));
    void'($value$plusargs("SHARD_INJ_N=%d", inj_n));
    void'($value$plusargs("SHARD_INJ_PERSIST=%d", inj_persist));
  end
  always_ff @(posedge clk) begin
    EArrE <= ~reset & InstrValidD & ~StallE & ~FlushE;
    MArrM <= ~reset & InstrValidE & ~StallM & ~FlushM;
  end
  always_comb begin
    inj_qual = 1'b0;
    case (inj_sel)
      1, 2:    inj_qual = EArrE & InstrValidE & ~(|MemRWE) & ~MDUActiveE & ~BranchE & ~JumpE;
      3:       inj_qual = EArrE & InstrValidE & BranchE;
      13:      inj_qual = EArrE & InstrValidE & (MemRWE == 2'b10);
      17:      inj_qual = EArrE & InstrValidE & (|MemRWE);
      12:      inj_qual = EArrE & InstrValidE & fpu.fpu.FPUActiveE & (fpu.fpu.PostProcSelE == 2'b10);
      4:       inj_qual = MArrM & InstrValidM & (MemRWM == 2'b10);
      5, 6:    inj_qual = MArrM & InstrValidM & (MemRWM == 2'b01) & (AtomicM == 2'b00);
      7:       inj_qual = MArrM & InstrValidM & AtomicM[1];
      8:       inj_qual = MArrM & InstrValidM & CSRWriteM;
      11:      inj_qual = MArrM & InstrValidM & (ResultSrcM == 3'b011) & ~Funct3M[2];
      14:      inj_qual = MArrM & InstrValidM & MemRWM[1];
      9:       inj_qual = 1'b1;
      10:      inj_qual = ~StallF;
      15:      inj_qual = RQPushW & RegWriteW_s;
      16:      inj_qual = QPushM;
      default: inj_qual = 1'b0;
    endcase
  end
  assign inj_eclass = (inj_sel == 1) | (inj_sel == 2) | (inj_sel == 3) | (inj_sel == 13) | (inj_sel == 12) | (inj_sel == 17);
  assign inj_mclass = (inj_sel == 4) | (inj_sel == 5) | (inj_sel == 6) | (inj_sel == 7) | (inj_sel == 8) | (inj_sel == 11) | (inj_sel == 14);
  assign inj_hit = inj_qual & ((inj_evt == inj_n) | ((inj_persist != 0) & (inj_evt >= inj_n)));
  always_ff @(posedge clk) begin
    if (reset) inj_evt <= 0; else if (inj_qual) inj_evt <= inj_evt + 1;
    if (reset) inj_hold <= 1'b0;
    else if (inj_eclass) inj_hold <= StallE & (inj_hold | inj_hit);
    else if (inj_mclass) inj_hold <= StallM & (inj_hold | inj_hit);
    else inj_hold <= 1'b0;
    if (inj_hit) $display("[SHARD] t=%0t INJECT id=%0d evt=%0d pcE=%h pcM=%h", $time, inj_sel, inj_evt, PCE, PCM);
  end
  // Under injection the main pipeline may retire a wrong-path tohost store that is later
  // squashed, so judge the test by the store that actually drains to memory.
  always_ff @(posedge clk)
    if ((inj_sel != 0) & sqPop & (sqPA[0] == 56'h80800000) & sqData[0][0]) begin
      if (sqData[0] == 64'd1) $display("TB: committed tohost exit(0) -- test PASSED");
      else                    $display("TB: committed tohost exit(%0d) -- test FAILED", sqData[0] >> 1);
      $finish;
    end
  assign inj_on = inj_hit | inj_hold;
```

Injection points (each is a temporary one-line change; `INJ(k)` stands for
`(top_tb.dut.soc.core.inj_on & (top_tb.dut.soc.core.inj_sel == k))`, an absolute
hierarchical reference — adjust the path to the target's testbench):

`hdl/core/wally/wallypipelinedcore.sv`

```diff
-    .Push(QPushM & SQStoreM), .PAdrM(SQPAdrM), .SizeM(Funct3M[1:0]), .WriteDataM(SQWriteDataM),
+    .Push(QPushM & SQStoreM), .PAdrM(SQPAdrM ^ {52'b0, inj_on & (inj_sel == 6), 3'b0}), .SizeM(Funct3M[1:0]), .WriteDataM(SQWriteDataM ^ {56'b0, inj_on & (inj_sel == 5), 7'b0}),
```

`hdl/core/wally/wallypipelinedcore.sv`

```diff
-    .Push(RQPushW), .RdW, .RegWriteW(RegWriteW_s), .ResultW(ResultW_s), .Pop(sCommit),
+    .Push(RQPushW), .RdW, .RegWriteW(RegWriteW_s), .ResultW(ResultW_s ^ {59'b0, inj_on & (inj_sel == 15), 4'b0}), .Pop(sCommit),
```

`hdl/core/wally/wallypipelinedcore.sv`

```diff
-    .Push(QPushM), .PCM, .InstrM, .CompressedM, .Pop(iqPop),
+    .Push(QPushM), .PCM(PCM ^ {59'b0, inj_on & (inj_sel == 16), 4'b0}), .InstrM, .CompressedM, .Pop(iqPop),
```

`hdl/core/ieu/datapath.sv`

```diff
-  assign ForwardedSrcAE = (RQ_HitA & (ForwardAE == 2'b00)) ? RQ_ValA : FwdSrcA_mw;
+  assign ForwardedSrcAE = ((RQ_HitA & (ForwardAE == 2'b00)) ? RQ_ValA : FwdSrcA_mw) ^ {61'b0, (top_tb.dut.soc.core.inj_on & (top_tb.dut.soc.core.inj_sel == 2)), 2'b0};
```

`hdl/core/ieu/datapath.sv`

```diff
-ecc_inject_en, IEUResultE,     IEUResultM, sec_ieumm, ded_ieumm);
+ecc_inject_en, IEUResultE ^ {60'b0, (top_tb.dut.soc.core.inj_on & (top_tb.dut.soc.core.inj_sel == 1)), 3'b0},     IEUResultM, sec_ieumm, ded_ieumm);
```

`hdl/core/ieu/controller.sv`

```diff
-  assign PCSrcE = (JumpE | BranchE & BranchTakenE) & ~FTStall;
+  assign PCSrcE = ((JumpE | BranchE & BranchTakenE) & ~FTStall) ^ (top_tb.dut.soc.core.inj_on & (top_tb.dut.soc.core.inj_sel == 3));
```

`hdl/core/lsu/lsu.sv`

```diff
-  flopenrc #(P.XLEN) AddressMReg(clk, reset, FlushM, ~StallM, IEUAdrE, IEUAdrM);
+  flopenrc #(P.XLEN) AddressMReg(clk, reset, FlushM, ~StallM, IEUAdrE ^ {60'b0, (top_tb.dut.soc.core.inj_on & (top_tb.dut.soc.core.inj_sel == 13)) | (top_tb.dut.soc.core.inj_on & (top_tb.dut.soc.core.inj_sel == 17)), 3'b0}, IEUAdrM);
```

`hdl/core/lsu/lsu.sv`

```diff
-  flopen #(P.LLEN) ReadDataMWReg(clk, ~StallW, ReadDataM, ReadDataW);
+  flopen #(P.LLEN) ReadDataMWReg(clk, ~StallW, ReadDataM ^ {62'b0, (top_tb.dut.soc.core.inj_on & (top_tb.dut.soc.core.inj_sel == 4)), 1'b0}, ReadDataW);
```

`hdl/core/lsu/lsu.sv`

```diff
-    .sqPA, .sqSize, .sqData, .sqCount, .ReadDataWordFwdM);
+    .sqPA, .sqSize, .sqData, .sqCount, .ReadDataWordFwdM(ReadDataWordFwdInjM));
+  logic [P.LLEN-1:0] ReadDataWordFwdInjM;
+  assign ReadDataWordFwdM = ReadDataWordFwdInjM ^ {58'b0, (top_tb.dut.soc.core.inj_on & (top_tb.dut.soc.core.inj_sel == 14)), 5'b0};
```

`hdl/core/lsu/atomic.sv`

```diff
-    mux2 #(P.XLEN) wdmux(IHWriteDataM, AMOResultM, LSUAtomicM[1], IMAWriteDataM);
+    mux2 #(P.XLEN) wdmux(IHWriteDataM, AMOResultM ^ {63'b0, (top_tb.dut.soc.core.inj_on & (top_tb.dut.soc.core.inj_sel == 7))}, LSUAtomicM[1], IMAWriteDataM);
```

`hdl/core/privileged/csr.sv`

```diff
-      default: CSRWriteValM = CSRReadValM;
-    endcase
-  end
+      default: CSRWriteValM = CSRReadValM;
+    endcase
+    CSRWriteValM = CSRWriteValM ^ {58'b0, (top_tb.dut.soc.core.inj_on & (top_tb.dut.soc.core.inj_sel == 8)), 5'b0};
+  end
```

`hdl/core/privileged/csrm.sv`

```diff
-  flopenr #(P.XLEN) MSCRATCHreg(clk, reset, WriteMSCRATCHM, CSRWriteValM, MSCRATCH_REGW);
+  flopenr #(P.XLEN) MSCRATCHreg(clk, reset, WriteMSCRATCHM | (top_tb.dut.soc.core.inj_on & (top_tb.dut.soc.core.inj_sel == 9)), (top_tb.dut.soc.core.inj_on & (top_tb.dut.soc.core.inj_sel == 9)) ? (MSCRATCH_REGW ^ 64'h10) : CSRWriteValM, MSCRATCH_REGW);
```

`hdl/core/ifu/ifu.sv`

```diff
-  mux2 #(P.XLEN) pcresetmux({UnalignedPCNextF[P.XLEN-1:1], 1'b0}, P.RESET_VECTOR[P.XLEN-1:0], reset, PCNextF);
+  mux2 #(P.XLEN) pcresetmux({UnalignedPCNextF[P.XLEN-1:1], 1'b0} ^ {59'b0, (top_tb.dut.soc.core.inj_on & (top_tb.dut.soc.core.inj_sel == 10)), 4'b0}, P.RESET_VECTOR[P.XLEN-1:0], reset, PCNextF);
```

`hdl/core/mdu/mul.sv`

```diff
-  assign ProdM = PP1M + PP2M + PP3M + PP4M; //ForwardedSrcAE * ForwardedSrcBE;
+  assign ProdM = (PP1M + PP2M + PP3M + PP4M) ^ {110'b0, (top_tb.dut.soc.core.inj_on & (top_tb.dut.soc.core.inj_sel == 11)), 17'b0}; //ForwardedSrcAE * ForwardedSrcBE;
```

`hvl/common/top_tb.svh`

```diff
-        if (!rst && mon_itf.valid[0] && mon_itf.mem_wmask[0] != '0 &&
-                mon_itf.mem_addr[0] == TOHOST_ADDR) begin
+        if (!rst && mon_itf.valid[0] && mon_itf.mem_wmask[0] != '0 && (dut.soc.core.inj_sel == 0) &&
+                mon_itf.mem_addr[0] == TOHOST_ADDR) begin
```

`hdl/core/fpu/fma/fmamult.sv`

```diff
-  assign Pm = Xm * Ym;
+  assign Pm = (Xm * Ym) ^ {{(2*P.NF+1-9){1'b0}}, (top_tb.dut.soc.core.inj_on & (top_tb.dut.soc.core.inj_sel == 12)), 9'b0};
```

Results on the validated configuration (123 transient runs over `tc_shard_spec` and
`tc_shard_direct`; "passes" means the test's real exit store drained with code 0):

| id | injected fault | caught by | outcome |
|---|---|---|---|
| 1 | main ALU result | shadow RES | replayed, passes |
| 2 | forwarded rs1 | shadow OP (+RES/EA); Memory-stage Operand check when the victim was serialized | replayed, passes |
| 3 | branch decision | shadow BR | replayed, passes |
| 4 | load result after sub-word extract | shadow LD | replayed, passes |
| 5 | store data entering the SQ | shadow ST | replayed, passes; the bad store never drained |
| 6 | store address entering the SQ | shadow ST | replayed, passes |
| 7 | AMO result | AMO (Memory stage) | replayed, passes |
| 8 | CSR write value | CSR (Memory stage) | replayed, passes |
| 9 | `mscratch` storage | CSR state | cause-16 trap, mirror resynchronised |
| 10 | `PCNextF` for one fetch | — | corrected by the branch-misprediction logic before anything retired; nothing to detect |
| 11 | multiplier product | MUL residue | replayed, passes |
| 12 | FMA significand product | FMA residue | replayed, passes |
| 13, 17 | load / any memory address register | EA (Memory stage) | replayed, passes |
| 14 | one copy of the store-queue merge | LoadFwd | replayed, passes |
| 15 | RQ result record | shadow RES | replayed, passes |
| 16 | retired PC entering the IQ | shadow NPC (+EA) | replayed at the expected PC, passes |
| 1, 4, 5, 11, 12 persistent | | same check, three times | cause-16 trap, `mepc` = faulting PC, `mtval` = the class |

An injection that lands on an instruction the pipeline squashes anyway (for
example the instruction after a CSR write, which is always refetched — W12) is,
correctly, not reported. Expect a few such "undetected" runs and confirm each by
looking at what the victim was.

### 17.4 Tests

`tc_shard_spec.c` — store-to-load forwarding, AMO, LR/SC, signed and unsigned
multiplies and divides, CSR round trips with a trap and `mret`. Runs with the RVFI
monitor. It includes `test_utils.h`, which provides `sim_exit(code)` (write
`(code << 1) | 1` to the `tohost` symbol) and nothing else this test needs.

```c
// tc_shard_spec.c
//
// Exercises the instruction classes SHARD defers through its queues and the CSR
// state mirror, which the other test tiers barely touch:
//   - store-to-load forwarding out of the store queue (overlapping sub-word stores)
//   - AMOs and LR/SC (their write half goes through the store queue)
//   - signed/unsigned multiplies (mod-3 residue check) and divides
//   - CSR reads/writes of mirrored CSRs, a trap and an mret (CSR state mirror)
//
// Run with the no-Spike simulator (the Spike co-simulation path cannot follow AMOs):
//   make -C sim run_verilator_top_tb_no_spike PROG=../testcode/shard/tc_shard_spec.c
//
// Exit code 0 = pass; otherwise the number of the first failing check.

#include <stdint.h>
#include "../isa_level_testing/test_utils.h"

static volatile uint64_t mem[16] __attribute__((aligned(64)));
static volatile uint64_t trap_cause;
static volatile uint64_t trap_count;

#define CHECK(id, cond) do { if (!(cond)) sim_exit(id); } while (0)

// Trap handler: record mcause, skip the trapping instruction, return.
void trap_entry(void);
__asm__(
    ".align 2\n"
    ".globl trap_entry\n"
    "trap_entry:\n"
    "  csrrw t6, mscratch, t6\n"      // free a register
    "  csrr  t6, mcause\n"
    "  sd    t6, trap_cause, t5\n"
    "  ld    t6, trap_count\n"
    "  addi  t6, t6, 1\n"
    "  sd    t6, trap_count, t5\n"
    "  csrr  t6, mepc\n"
    "  addi  t6, t6, 4\n"
    "  csrw  mepc, t6\n"
    "  csrrw t6, mscratch, t6\n"
    "  mret\n");

#define AMO(name, insn)                                                        \
    static inline uint64_t name(volatile void *p, uint64_t v) {                \
        uint64_t r;                                                            \
        __asm__ volatile (insn " %0, %2, (%1)"                                 \
                          : "=&r"(r) : "r"(p), "r"(v) : "memory");             \
        return r;                                                              \
    }
AMO(amoswap_d, "amoswap.d")
AMO(amoadd_d,  "amoadd.d")
AMO(amoand_d,  "amoand.d")
AMO(amoor_d,   "amoor.d")
AMO(amoxor_d,  "amoxor.d")
AMO(amomin_d,  "amomin.d")
AMO(amomaxu_d, "amomaxu.d")
AMO(amoadd_w,  "amoadd.w")
AMO(amoswap_w, "amoswap.w")
AMO(amomax_w,  "amomax.w")

#define MULOP(name, insn)                                                      \
    static inline uint64_t name(uint64_t a, uint64_t b) {                      \
        uint64_t r;                                                            \
        __asm__ volatile (insn " %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));      \
        return r;                                                              \
    }
MULOP(op_mul,    "mul")
MULOP(op_mulh,   "mulh")
MULOP(op_mulhsu, "mulhsu")
MULOP(op_mulhu,  "mulhu")
MULOP(op_mulw,   "mulw")
MULOP(op_div,    "div")
MULOP(op_rem,    "rem")
MULOP(op_divu,   "divu")

static void test_forwarding(void) {
    volatile uint64_t *p = &mem[0];
    uint64_t a, b, c, d, e;
    // Stores followed at once by loads of the same word: the loads must see every
    // store still sitting in the store queue, byte by byte, newest last.
    __asm__ volatile (
        "sd  %[v0], 0(%[p])\n"
        "sb  %[v1], 3(%[p])\n"
        "ld  %[a], 0(%[p])\n"
        "sh  %[v2], 6(%[p])\n"
        "lw  %[b], 0(%[p])\n"
        "ld  %[c], 0(%[p])\n"
        "sw  %[v3], 4(%[p])\n"
        "lhu %[d], 6(%[p])\n"
        "lbu %[e], 3(%[p])\n"
        : [a]"=&r"(a), [b]"=&r"(b), [c]"=&r"(c), [d]"=&r"(d), [e]"=&r"(e)
        : [p]"r"(p), [v0]"r"(0x1122334455667788UL), [v1]"r"(0xAAUL),
          [v2]"r"(0xBBCCUL), [v3]"r"(0xDEADBEEFUL)
        : "memory");
    CHECK(1, a == 0x11223344AA667788UL);
    CHECK(2, b == 0xFFFFFFFFAA667788UL);
    CHECK(3, c == 0xBBCC3344AA667788UL);
    CHECK(4, d == 0xDEAD);
    CHECK(5, e == 0xAA);
    CHECK(6, mem[0] == 0xDEADBEEFAA667788UL);

    // A run of stores to different words, then read them all back.
    for (int i = 1; i < 16; i++) mem[i] = 0x0101010101010101UL * (uint64_t)i;
    uint64_t sum = 0;
    for (int i = 1; i < 16; i++) sum += mem[i];
    CHECK(7, sum == 0x0101010101010101UL * 120);
}

static void test_atomics(void) {
    mem[1] = 100;
    CHECK(10, amoswap_d(&mem[1], 7) == 100 && mem[1] == 7);
    CHECK(11, amoadd_d(&mem[1], 5) == 7 && mem[1] == 12);
    CHECK(12, amoand_d(&mem[1], 0xA) == 12 && mem[1] == 8);
    CHECK(13, amoor_d(&mem[1], 0x30) == 8 && mem[1] == 0x38);
    CHECK(14, amoxor_d(&mem[1], 0xFF) == 0x38 && mem[1] == 0xC7);
    CHECK(15, amomin_d(&mem[1], (uint64_t)-5) == 0xC7 && mem[1] == (uint64_t)-5);
    CHECK(16, amomaxu_d(&mem[1], 9) == (uint64_t)-5 && mem[1] == (uint64_t)-5);

    mem[2] = 0x00000001FFFFFFFFUL;                       // low word = -1
    CHECK(17, amoadd_w(&mem[2], 2) == (uint64_t)-1 && mem[2] == 0x0000000100000001UL);
    CHECK(18, amoswap_w((volatile uint32_t *)&mem[2] + 1, 0x80000000UL) == 1 &&
              mem[2] == 0x8000000000000001UL);
    CHECK(19, amomax_w(&mem[2], (uint64_t)-7) == 1 && mem[2] == 0x8000000000000001UL);

    // Back-to-back AMOs on one word: each must read the previous one's buffered write.
    mem[3] = 0;
    for (int i = 0; i < 20; i++) amoadd_d(&mem[3], (uint64_t)i);
    CHECK(20, mem[3] == 190);

    // LR/SC: success, then an SC with no reservation must fail and leave memory alone.
    uint64_t old, rc, rc2;
    mem[4] = 55;
    __asm__ volatile (
        "lr.d %[old], (%[p])\n"
        "addi %[old], %[old], 1\n"
        "sc.d %[rc], %[old], (%[p])\n"
        "sc.d %[rc2], %[bad], (%[p])\n"
        : [old]"=&r"(old), [rc]"=&r"(rc), [rc2]"=&r"(rc2)
        : [p]"r"(&mem[4]), [bad]"r"(999UL) : "memory");
    CHECK(21, rc == 0 && mem[4] == 56);
    CHECK(22, rc2 != 0 && mem[4] == 56);
    uint32_t oldw;
    __asm__ volatile (
        "lr.w %[old], (%[p])\n"
        "sc.w %[rc], %[v], (%[p])\n"
        : [old]"=&r"(oldw), [rc]"=&r"(rc) : [p]"r"(&mem[4]), [v]"r"(77UL) : "memory");
    CHECK(23, rc == 0 && oldw == 56 && mem[4] == 77);
}

static void test_muldiv(void) {
    volatile uint64_t m1 = (uint64_t)-1, m3 = (uint64_t)-3, five = 5;
    volatile uint64_t big = 0x8000000000000000UL, x = 0x123456789ABCDEF1UL, y = 0xFEDCBA9876543211UL;
    CHECK(40, op_mul(m3, five) == (uint64_t)-15);
    CHECK(41, op_mulh(m3, five) == (uint64_t)-1);
    CHECK(42, op_mulhu(m1, m1) == 0xFFFFFFFFFFFFFFFEUL);
    CHECK(43, op_mulhsu(m1, m1) == (uint64_t)-1);
    CHECK(44, op_mulhsu(five, m1) == 4);
    CHECK(45, op_mulh(big, big) == 0x4000000000000000UL);
    CHECK(46, op_mulh(big, m1) == 0);
    CHECK(47, op_mulhu(big, m1) == 0x7FFFFFFFFFFFFFFFUL);
    CHECK(48, op_mulw(0x7FFFFFFF, 2) == (uint64_t)-2);
    CHECK(49, op_mul(x, y) == x * y);
    CHECK(50, op_mulhu(x, y) == (uint64_t)(((unsigned __int128)x * y) >> 64));
    CHECK(51, op_mulh(x, y) == (uint64_t)(((__int128)(int64_t)x * (int64_t)y) >> 64));
    CHECK(52, op_mulhsu(y, x) == (uint64_t)(((__int128)(int64_t)y * (unsigned __int128)x) >> 64));
    CHECK(53, op_div(100, 7) == 14 && op_rem(100, 7) == 2);
    CHECK(54, op_div((uint64_t)-100, 7) == (uint64_t)-14 && op_divu(m1, 2) == 0x7FFFFFFFFFFFFFFFUL);
}

static void test_csr(void) {
    uint64_t a, b, c, d, old_tvec, ms0, ms1, ms2;
    __asm__ volatile ("csrr %0, mtvec" : "=r"(old_tvec));
    __asm__ volatile ("csrw mtvec, %0" :: "r"((uint64_t)&trap_entry));
    __asm__ volatile ("csrr %0, mtvec" : "=r"(a));
    CHECK(70, a == (uint64_t)&trap_entry);

    __asm__ volatile (
        "csrw  mscratch, %[v]\n"
        "csrr  %[a], mscratch\n"
        "csrrs %[b], mscratch, %[s]\n"
        "csrrc %[c], mscratch, %[k]\n"
        "csrrw %[d], mscratch, x0\n"
        : [a]"=&r"(a), [b]"=&r"(b), [c]"=&r"(c), [d]"=&r"(d)
        : [v]"r"(0x00FF00FF00FF00FFUL), [s]"r"(0xF000UL), [k]"r"(0xFFUL));
    CHECK(71, a == 0x00FF00FF00FF00FFUL);
    CHECK(72, b == 0x00FF00FF00FF00FFUL);
    CHECK(73, c == 0x00FF00FF00FFF0FFUL);
    CHECK(74, d == 0x00FF00FF00FFF000UL);

    __asm__ volatile ("csrw mepc, %1\n csrr %0, mepc" : "=&r"(a) : "r"(0x80001237UL));
    CHECK(75, a == 0x80001236UL);                        // bit 0 is not writable

    // mstatus.MIE set and clear (no interrupt source is enabled in mie)
    __asm__ volatile (
        "csrr  %[m0], mstatus\n"
        "csrsi mstatus, 8\n"
        "csrr  %[m1], mstatus\n"
        "csrci mstatus, 8\n"
        "csrr  %[m2], mstatus\n"
        : [m0]"=&r"(ms0), [m1]"=&r"(ms1), [m2]"=&r"(ms2));
    CHECK(76, (ms1 & 8) == 8 && (ms2 & 8) == 0 && ((ms0 ^ ms2) & ~8UL) == 0);

    // Trap and return: ecall from M-mode, the handler skips it and mrets.
    trap_cause = 0; trap_count = 0;
    __asm__ volatile ("ecall" ::: "memory");
    __asm__ volatile ("ecall" ::: "memory");
    CHECK(77, trap_count == 2 && trap_cause == 11);
    __asm__ volatile ("csrr %0, mcause" : "=r"(a));
    CHECK(78, a == 11);
    __asm__ volatile ("csrr %0, mstatus" : "=r"(a));
    CHECK(79, ((a >> 11) & 3) == 0 && (a & 0x80));       // after mret: MPP = U, MPIE = 1

    __asm__ volatile ("csrw mtvec, %0" :: "r"(old_tvec));
}

int main(void) {
    test_forwarding();
    test_atomics();
    test_muldiv();
    test_csr();
    // Again, so every path also runs warm (caches filled, predictors trained).
    test_forwarding();
    test_atomics();
    test_muldiv();
    sim_exit(0);
}
```

`tc_shard_direct.c` — misaligned accesses and floating point (FMA, FP load/store,
FP divide, conversion). Needs `ZICCLSM` and an FPU, and a simulator built without
the RVFI monitor.

```c
// tc_shard_direct.c
//
// Exercises the memory and floating-point instructions SHARD does not defer: they wait
// in the Memory stage until the shadow is quiescent, are checked there, and then act
// directly.
//   - misaligned loads and stores, inside a doubleword, across doublewords and across
//     a cache line
//   - floating point, including fused multiply-add (FMA residue check), FP load/store,
//     FP divide and FP-to-integer conversion
//
// The riscv-formal RVFI monitor models a misaligned access as a trap, so this test
// must run in a simulator built without it:
//   make -C sim run_verilator_top_tb_no_spike NO_SPIKE_DIR=build_no_spike_norvfi \
//        EXTRA_DEFINES=+define+ECE411_NO_RVFI PROG=../testcode/shard/tc_shard_direct.c
//
// Exit code 0 = pass; otherwise the number of the first failing check.

#include <stdint.h>
#include "../isa_level_testing/test_utils.h"

static volatile uint64_t mem[16] __attribute__((aligned(64)));

#define CHECK(id, cond) do { if (!(cond)) sim_exit(id); } while (0)

static void test_misaligned(void) {
    volatile uint8_t *b = (volatile uint8_t *)&mem[8];   // start of a 64-byte cache line
    uint64_t r0, r1, r2, r3;
    mem[8] = 0; mem[9] = 0; mem[7] = 0;
    __asm__ volatile (
        "sw  %[v0], 1(%[b])\n"          // misaligned inside one doubleword
        "lw  %[r0], 1(%[b])\n"
        "sd  %[v1], 5(%[b])\n"          // crosses a doubleword
        "ld  %[r1], 5(%[b])\n"
        "sd  %[v2], -3(%[b])\n"         // crosses a cache line
        "ld  %[r2], -3(%[b])\n"
        "lhu %[r3], 7(%[b])\n"          // crosses a doubleword
        : [r0]"=&r"(r0), [r1]"=&r"(r1), [r2]"=&r"(r2), [r3]"=&r"(r3)
        : [b]"r"(b), [v0]"r"(0x11223344UL), [v1]"r"(0x0102030405060708UL),
          [v2]"r"(0xA1A2A3A4A5A6A7A8UL)
        : "memory");
    CHECK(30, r0 == 0x11223344);
    CHECK(31, r1 == 0x0102030405060708UL);
    CHECK(32, r2 == 0xA1A2A3A4A5A6A7A8UL);
    CHECK(33, r3 == 0x0506);
    CHECK(34, mem[7] == 0xA6A7A80000000000UL);
    CHECK(35, mem[8] == 0x060708A1A2A3A4A5UL);
    CHECK(36, mem[9] == 0x0000000102030405UL);
}

static void test_fp(void) {
    uint64_t r0, r1, r2, r3, r4, r5;
    __asm__ volatile ("li t0, 0x2000\n csrs mstatus, t0" ::: "t0");    // FS = initial
    __asm__ volatile (
        "fmv.d.x ft0, %[a]\n"
        "fmv.d.x ft1, %[b]\n"
        "fmv.d.x ft2, %[c]\n"
        "fmadd.d ft3, ft0, ft1, ft2\n"    // 3*5+1 = 16
        "fmv.x.d %[r0], ft3\n"
        "fmul.d  ft4, ft0, ft1\n"         // 15
        "fmv.x.d %[r1], ft4\n"
        "fmsub.d ft5, ft3, ft4, ft0\n"    // 16*15-3 = 237
        "fmv.x.d %[r2], ft5\n"
        "fadd.d  ft6, ft5, ft2\n"         // 238
        "fmv.x.d %[r3], ft6\n"
        "fsd     ft6, 0(%[p])\n"          // FP store, then integer and FP loads
        "ld      %[r4], 0(%[p])\n"
        "fld     ft7, 0(%[p])\n"
        "fdiv.d  ft7, ft7, ft1\n"         // 238/5 = 47.6
        "fcvt.l.d %[r5], ft7, rtz\n"      // 47
        : [r0]"=&r"(r0), [r1]"=&r"(r1), [r2]"=&r"(r2), [r3]"=&r"(r3), [r4]"=&r"(r4), [r5]"=&r"(r5)
        : [a]"r"(0x4008000000000000UL), [b]"r"(0x4014000000000000UL),
          [c]"r"(0x3FF0000000000000UL), [p]"r"(&mem[10])
        : "ft0", "ft1", "ft2", "ft3", "ft4", "ft5", "ft6", "ft7", "memory");
    CHECK(60, r0 == 0x4030000000000000UL);
    CHECK(61, r1 == 0x402E000000000000UL);
    CHECK(62, r2 == 0x406DA00000000000UL);
    CHECK(63, r3 == 0x406DC00000000000UL);
    CHECK(64, r4 == 0x406DC00000000000UL);
    CHECK(65, r5 == 47);
}

int main(void) {
    test_misaligned();
    test_fp();
    // Again, so every path also runs warm (caches filled, predictors trained).
    test_misaligned();
    test_fp();
    sim_exit(0);
}
```

---

## 18. What is not covered

- **Decode.** The shadow re-executes with the main pipeline's decoded datapath
  controls (which ALU operation, which immediate format, operand select). It takes
  register numbers, the immediate bits, `funct3`/`funct7` and the destination from
  the instruction word itself.
- **The decompressor and the fetched instruction bits.** The IQ holds the expanded
  32-bit instruction from the main pipeline. Only PC continuity is checked.
- **Address translation**: TLB, HPTW, PMP/PMA. The SQ address check uses the page
  offset.
- **Raw memory data**: the word the cache or bus returns is trusted; everything
  done to it afterwards is checked.
- **Integer divide/remainder** (§13), and with an FPU every FP result except the
  FMA significand product.
- **The result select after the multiplier** (low/high half, W sign extension).
- **CSRs outside the mirror** (§9.5); **which** trap cause is selected; `mtval` on
  a trap; the SC success flag.
- **The checker itself**: verifier, queues and commit port have no self-test.
- **Design-level faults common to both copies** of the duplicated blocks. Only the
  residue checks are algorithmically independent.

---

## 19. Checklist

1. Regfile: two extra read ports; write port driven only by the shadow.
2. Datapath: regfile read addressed from Execute; `R1D→R1E`/`R2D→R2E` registers
   removed; RQ forwarding below the M/W bypasses; `ForwardedSrcAM`.
3. Controller/IEU: export `Rs1E`, `RegWriteM`, `ResultSrcM`, `FWriteIntM`;
   `ImmSrcE`; `ShardCtlM`; `PCSrcM`.
4. Queues: `shadow_fifo`, IQ, OQ, RQ, SQ; pushes exactly as §4.1.
5. Shadow: `shadow_hzu`, `shadow_verifier`, `shadow_pipeline`.
6. LSU: classification, `HoldM`, masks (read/write, D-cache flush, cache-block op,
   `CacheableOrFlushCacheM`, `BusAtomic`), HPTW input gating, drain engine and its
   request muxes, fault masks, `GatedStallW`, `LSUFlushW`, FP write-data select,
   merge ×2, second `amoalu` without the flush gate, reservation drop.
7. Hazard: redirect in all four flush causes; `ShardStallW`.
8. IFU: redirect mux.
9. Trap: `TrapPendingM`, `TrapM` gated by quiescence, cause 16.
10. `privdec`: xRET masked by the redirect. `privileged`: `FRegWriteM` masked.
11. CSR file: export the six registers; `shadow_csr`; read/write checks; cause-16
    EPC and `mtval`.
12. MDU (and FPU if present): residue checks.
13. Core: `MExitM`, `InstrValidW`, `WPushed`, `InFlight`, backpressure,
    `NonMemSerialM`, EA and Operand checks, fault response, connections.
14. Wrapper/testbench taps.
15. Instrument; run §17.1; require zero faults; inject; remove instrumentation.
