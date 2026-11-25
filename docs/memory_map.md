# Memory map, custom CSRs, and trap causes

Applies to the 64-bit configuration in [`pkg/config.vh`](../pkg/config.vh).
Addresses are physical; memory is little-endian. MMIO access follows PMP and page
permissions, with no additional machine-mode restriction. Peripheral regions are
uncached, non-idempotent, non-executable, and do not support atomics.

## Physical address map

| Address/range | Function | Availability |
| --- | --- | --- |
| `0x0200_0000–0x0200_ffff` | CLINT | Both SoCs, on-chip |
| `0x0200_f000–0x0200_f007` | DFT lock; overrides CLINT at this address | ASIC only; simulation SoC reads zero |
| `0x0c00_0000–0x0fff_ffff` | PLIC | Simulation SoC; ASIC on-chip with `PERIPH_ONCHIP=1`, external with `=0` |
| `0x1000_0000–0x1000_0007` | UART | Same placement as PLIC |
| `0x1007_000b` | FI_CONTROL | Both SoCs, always on-chip |
| `0x1008_0000–0x1008_0fff` | Fault counters: 23 saturating 16-bit counters, counter *i* as a 32-bit word at `+4*i`, software-clearable; and the I$/D$ last-uncorrectable-error records at `+0x60–0x6c` (see [Fault counters](#fault-counters)) | Both SoCs, on-chip |
| `0x8000_0000–0x8fff_ffff` | External memory, 256 MiB | Both SoCs |

Reset PC: `0x8000_0000`. Simulation completion address `0x8080_0000` is ordinary
memory monitored by the testbench. FPGA host registers use a separate address space.

## FI_CONTROL: `0x1007_000b`

Read/write **byte**, reset **`0x00`** (`0x3f` in `ECE411_SIM_INJECT` simulation builds,
which model boot software arming the six core units). Use `lbu`/`sb` or `volatile uint8_t`.
Wider accesses and neighboring addresses are rejected; neighboring bytes are not aliases.

| Bit | Injection group |
| --- | --- |
| 0 | ALU: architectural, extended arithmetic/address, and widened shift results in both replicas |
| 1 | Comparison: extended difference in both comparison replicas inside `ft_alu` |
| 2 | MUL: both full-product replicas |
| 3 | DIV: quotient and remainder in both replicas |
| 4 | Integer register-file ECC: both read paths |
| 5 | Pipeline ECC: `RD1EReg`, `RD2EReg`, `ImmExtEReg`, `SrcAMReg`, `IEUResultMReg`, `WriteDataMReg`, `IFResultWReg` |
| 6 | Cache correctable: one-bit flips into the next I$/D$ tag and line written (`cachefi.sv`) |
| 7 | Cache uncorrectable: two-bit flips, same placement as bit 6 |

Each injector enable is `fault_inject & FI_CONTROL[bit]`, registered in the core:
a change to the mask or the pin reaches the injectors one cycle later (the pin
additionally passes a two-flop synchroniser in `forte_chip`). Readback returns
the stored mask regardless of the master pin. Writing `0x04` selects MUL only;
writing zero disables all injection. The DFT lock does not gate injection.

The mask controls artificial corruption only. Detection, recovery, trapping,
pending faults, and status accumulation remain active. Mask writes neither clear
status nor restart injector sequences. Execution injectors retain local LFSRs
and staggered one-clock events every 512 clocks; the mask does not select the
replica, fault bit, or fault kind.

```text
AHB decode -> APB bridge -> fault_inject_apb.FaultInjectMask
  -> wallypipelinedsoc / forte_soc -> wallypipelinedcore: AND with fault_inject, then a flop
       bits 0,1,4,5 -> IEU -> datapath -> ALU, CMP, register-file ECC, pipeline ECC
       bits 2,3     -> MDU -> MUL, DIV
```

[`fault_inject_apb.sv`](../hdl/core/uncore/fault_inject_apb.sv) accepts writes on
core-clock edges with `PSEL & PENABLE & PWRITE & PSTRB[3]`. Byte lane 3 supplies
`PWDATA[29:24]`; readback uses the same bits, with all others zero. No package pins
are added. [`adrdecs.sv`](../hdl/core/mmu/adrdecs.sv) and
[`pmachecker.sv`](../hdl/core/mmu/pmachecker.sv) enforce the access rules.

## CLINT

Aligned 64-bit accesses; timer writes honor byte strobes, while `msip` consumes
data bit 0. Unused offsets read zero and ignore writes, except the ASIC DFT lock.
See [`clint_apb.sv`](../hdl/core/uncore/clint_apb.sv).

| Address | Register | Access / reset | Function |
| --- | --- | --- | --- |
| `0x0200_0000` | `msip` | RW bit 0 / 0 | Machine software interrupt |
| `0x0200_4000` | `mtimecmp` | RW 64 bits / all ones | Machine timer interrupt when `mtime >= mtimecmp` |
| `0x0200_bff8` | `mtime` | RW 64 bits / 0 | Increments each core clock except during writes; `TIMECLK` is unused |

The standard `time` CSR observes `mtime` when configuration and CSR permissions allow.

## DFT lock: ASIC `0x0200_f000`

Bit 0 (`unlocked`) resets to 1; upper bits read zero. A write with byte strobe 0
and data bit 0 clear locks DFT until reset. Writing one cannot unlock it. Use a
byte or aligned 64-bit access at the base address; other byte strobes have no effect.
`forte_chip` gates `test_mode` and `scan_en` with this bit. The register remains
on-chip with `PERIPH_ONCHIP=0`. See [`forte_dft_lock.sv`](../hdl/forte_dft_lock.sv).

## PLIC

Aligned 32-bit accesses. Sources 1–10; source 0 is unused. Context 0 is machine,
context 1 supervisor. Priorities and thresholds are three bits. Priorities,
enables, thresholds, and in-progress state reset to zero.

| Address | Register | Access / effect |
| --- | --- | --- |
| `0x0c00_0000 + 4*source` | Priority, sources 1–10 | RW 0–7; zero disables priority. Source 0 reads zero |
| `0x0c00_1000` | Pending | RO; source ID maps to bit number; bit 0 is zero |
| `0x0c00_2000` | Context 0 enable | RW source bitmap |
| `0x0c00_2080` | Context 1 enable | RW source bitmap |
| `0x0c20_0000` | Context 0 threshold | RW; eligible priority must exceed threshold |
| `0x0c20_0004` | Context 0 claim/complete | Read claims and returns ID; write nonzero ID to complete |
| `0x0c20_1000` | Context 1 threshold | RW |
| `0x0c20_1004` | Context 1 claim/complete | Same semantics as context 0 |

Use these canonical addresses: the PLIC decodes only the low 24 address bits.
Upper pending/enable words for 32+ sources are absent in this configuration.
ASIC sources: UART=10, `irq[0]`=3, `irq[1]`=6. Simulation sources 3/6/9 connect to
currently disabled GPIO/SPI/SDC. With `PERIPH_ONCHIP=0`, ASIC PLIC/UART transactions
and interrupt inputs are external. See [`plic_apb.sv`](../hdl/core/uncore/plic_apb.sv).

## UART: `0x1000_0000`

Byte accesses. `DLAB=LCR[7]` selects offsets 0 and 1.

| Offset | Register | Access / effect |
| --- | --- | --- |
| `0`, DLAB=0 | RBR / THR | Read consumes receive byte; write transmits byte |
| `0`, DLAB=1 | DLL | RW low divisor; reset 1 |
| `1`, DLAB=0 | IER | RW interrupt enables `[3:0]`; reset 0 |
| `1`, DLAB=1 | DLM | RW high divisor; reset 0 |
| `2` | IIR / FCR | Read interrupt ID; write FIFO control |
| `3` | LCR | RW; reset `0x03` |
| `4` | MCR | RW modem controls `[4:0]`; reset 0 |
| `5` | LSR | Read status: bit 0 RX ready, 5 TX holding empty, 6 TX empty; participates in clearing RX errors |
| `6` | MSR | Read modem status; clears delta bits `[3:0]` |
| `7` | SCR | RW scratch; reset 0 |

IER bits 0–3 enable RX, TX-empty, line-status, and modem-status interrupts.
FCR: bit 0 FIFO enable, bits 1/2 RX/TX reset, bits 7:6 RX trigger.
LCR: bits 1:0 data length, 2 stop bits, 5:3 parity, 6 break, 7 DLAB.
Test writes to LSR `[6:1]` and MSR `[3:0]` are supported.
See [`uartPC16550D.sv`](../hdl/core/uncore/uartPC16550D.sv).

## Disabled peripheral maps

These blocks are disabled in `pkg/config.vh` and absent from the ASIC uncore.
The simulation uncore instantiates them only when configured. All listed registers
use aligned 32-bit accesses; controls are RW unless stated otherwise.

**GPIO:** `0x1006_0000–0x1006_00ff` ([RTL](../hdl/core/uncore/gpio_apb.sv)).

| Offset(s) | Register(s) |
| --- | --- |
| `0x00` | Input value, RO |
| `0x04`, `0x08`, `0x0c` | Input enable, output enable, output value |
| `0x18`, `0x1c` | Rising-edge interrupt enable, pending |
| `0x20`, `0x24` | Falling-edge interrupt enable, pending |
| `0x28`, `0x2c` | High-level interrupt enable, pending |
| `0x30`, `0x34` | Low-level interrupt enable, pending |
| `0x38`, `0x3c`, `0x40` | Alternate-function enable, selection, output XOR |

GPIO pending bits are W1C.

**SPI / SD-card SPI:** bases `0x1004_0000` / `0x0001_3000`, each size `0x1000`,
with the same layout ([RTL](../hdl/core/uncore/spi_apb.sv)).

| Offset(s) | Register(s) |
| --- | --- |
| `0x00`, `0x04` | SCKDIV, SCKMODE: clock divisor and mode |
| `0x10`, `0x14`, `0x18` | CSID, CSDEF, CSMODE: chip-select controls |
| `0x28`, `0x2c` | DELAY0, DELAY1: transfer timing |
| `0x40` | FMT: frame format |
| `0x48` | TXDATA: write pushes data; read returns full status |
| `0x4c` | RXDATA: read pops data and reports empty status |
| `0x50`, `0x54` | TXMARK, RXMARK: FIFO interrupt thresholds |
| `0x70`, `0x74` | IE (RW), IP (RO): interrupt enable/pending |

Disabled ROM/RAM options add no CSRs. Neither SoC instantiates `trickbox_apb`.

## Custom CSRs

All require machine mode, reset to zero, and read zero in unimplemented bits.
Illegal accesses trap with cause 2. See [`csrm.sv`](../hdl/core/privileged/csrm.sv).

| CSR | Name | Access / function |
| --- | --- | --- |
| `0x7c0` | MSECFAULT | Read/W1C security and ECC events |
| `0x7c1` | RANDINSTRFREQ | RW low 32 bits: dummy-instruction period; zero disables |
| `0x7c2` | MFTSTATUS | RO sticky FT events; writes trap; only reset clears |

| Bit | MSECFAULT | MFTSTATUS |
| --- | --- | --- |
| 0 | Correctable triplicated privilege-mode disagreement | ALU replica isolated |
| 1 | Reserved `mstatus.MPP=2` detected | Comparison replica isolated |
| 2 | Illegal CSR access on a valid instruction | MUL isolation; currently zero |
| 3 | Privilege-mode disagreement without a majority | DIV isolation; currently zero |
| 4 | Register-file or pipeline ECC single-bit correction | Reserved zero |
| 5 | Register-file or pipeline ECC double-bit detection | Reserved zero |
| 6 | Reserved zero | Unresolved FT result reached M |
| 63:7 | Zero | Zero |

MSECFAULT updates as `(old | events) & ~written_clear_bits`: clearing wins on a
simultaneous event. Privilege-mode uncorrectable status also has a hardware output;
it does not use FT cause 16. See [`csrharden.sv`](../hdl/core/privileged/csrharden.sv).

MUL/DIV retry or report unresolved; they do not isolate replicas. Successful
ordinary retries set no MFTSTATUS bit; ALU/CMP isolation sets status without a
trap. Bit 6 records the unresolved indication even if another exception wins.
Flushes and injection-disable writes clear neither CSR; ECC events use MSECFAULT.

[`dummygen.sv`](../hdl/core/ieu/dummygen.sv) strobes every RANDINSTRFREQ clocks.
Each strobe can capture an eligible instruction and replay a previously captured
instruction when `LFSR[0]`, `DummyValid`, and `InsertOkD` are set. FI_CONTROL does
not affect dummy insertion.

## Fault counters

`0x1008_0000 + 4*i`, read with 32-bit loads; `{16'b0, count}`, saturating at
`0xFFFF` ([`faultcount_apb.sv`](../hdl/core/uncore/faultcount_apb.sv)).
SEC = corrected, DED = uncorrectable.  Reset clears them; so does software: a 32-bit
store of any value to counter *i*'s word clears that counter, and a store to
`+0x7c` (word 31) clears all of them.  An event in the cycle of the clear still
counts.  Machine mode only, like the rest of the block (PMP can hide it from S/U).

| *i* | Counts | *i* | Counts |
| --- | --- | --- | --- |
| 0 / 1 | Register-file SEC / DED | 12 / 13 | MUL residue mismatch / unresolved |
| 2 / 3 | Pipeline-register SEC / DED | 14 / 15 | DIV residue mismatch / unresolved |
| 4 / 5 | I$ SEC / DED (tag and data) | 16 / 17 | Privilege-mode TMR corrected / uncorrectable |
| 6 / 7 | D$ SEC / DED (tag and data) | 18 / 19 | I$ tag SEC / tag DED (a subset of 4 / 5) |
| 8 / 9 | ALU replica mismatch / unresolved | 20 / 21 | D$ tag SEC / tag DED (a subset of 6 / 7) |
| 10 / 11 | Compare replica mismatch / unresolved | 22 | D$ modified data lost: each cause-20/21 report |

Data-only counts are the totals minus the tag counters. Every counter-22 event is
also in counter 7; the rest of counter 7 (and all of counter 5) are uncorrectable
lines that were dropped and refetched with nothing lost.

### Last-error records

One record per cache for the latest uncorrectable error (each event counted by
counter 5 or 7), to tell a random upset from a bad cell: the same set and way
again and again points at the SRAM.

| Offset | Word | Contents |
| --- | --- | --- |
| `+0x60` | 24 | D$ record |
| `+0x64` | 25 | D$ line physical address `[31:0]` (only when TAG is 0) |
| `+0x68` | 26 | I$ record |
| `+0x6c` | 27 | I$ line physical address `[31:0]` (only when TAG is 0) |

Record bits: `[0]` VALID, `[1]` MULTIPLE (more than one error since the record
was last cleared; it holds the newest), `[2]` TAG (the tag was uncorrectable, so
the line's address is unknown), `[3]` LOST (D$: dirty data lost, the same event
as trap cause 20/21), `[5:4]` SOURCE (0 a lookup, 1 an eviction, 2 a flush,
3 the scrubber), `[11:8]` WAYS (the way(s) dropped, one bit each), `[27:16]` SET.
A store of any value to a record's either word clears that record; an error in
the same cycle wins.  Reset clears both; the clear-all word does not.  Words 23
and 28–31 read 0.

## Trap causes

`mcause`/`scause` bit 63 distinguishes interrupts (1) from exceptions (0).
See [`trap.sv`](../hdl/core/privileged/trap.sv).

| Exception cause | Meaning |
| --- | --- |
| 0 | Instruction address misaligned |
| 1 | Instruction access fault |
| 2 | Illegal instruction, including illegal CSR access |
| 3 | Breakpoint |
| 4, 5 | Load address misaligned, load access fault |
| 6, 7 | Store/atomic address misaligned, store/atomic access fault |
| 8, 9, 11 | Environment call from user, supervisor, machine mode |
| 12, 13, 15 | Instruction, load, store/atomic page fault |
| 16 | Custom FT unresolved result |
| 19 | Uncorrectable storage ECC: register file or pipeline register |
| 20 | Uncorrectable ECC in a dirty D$ line's data: the modified line is lost, `mtval` is its address |
| 21 | Uncorrectable ECC in a dirty D$ line's tag: the modified line is lost and its address is unknown |

Cause 16 uses the faulting M-stage PC in `mepc` and zero in `mtval`. ALU/CMP and
DIV terminal faults travel E→M with their instruction; MUL faults originate in M.
Backpressure retains pending faults. Trap entry suppresses the faulting result,
flushes younger instructions, and redirects to the `mtvec` base. Cause 19 uses the
saved ECC fault record for `mepc`/`mtval`. Cause 20 sets `mtval` to the lost line's
address (data error on a hit, eviction or flush). The line is reported and then
dropped -- never written back, so memory keeps its older copy, and a later access
reads that copy without a further trap. (Leaving it valid would re-trap on every
access, which in the firmware's own trap path loops before any report.) Cause 21 is raised instead when
the dirty line's tag itself is uncorrectable: the address is gone, so `mtval` is
only the address of the access that found the line's cache set, and software cannot
tell which page lost data. A clean line with an uncorrectable tag, or any
uncorrectable line in the I$, is dropped and refetched without a trap (it is counted).

`medeleg` is 16 bits, so causes 16/19/20/21 always enter machine mode. Interrupts and
instruction page/access/illegal-instruction faults precede cause 16; remaining
standard exceptions precede causes 19, 20 and 21. With `ZICCLSM_SUPPORTED=0`, load/store
misalignment precedes page/access faults. Other exception codes are not generated;
instruction misalignment is normally absent with compressed instructions enabled.

Firmware: the Linux image's OpenSBI
([`opensbi-1.4-amoeba-fail-stop.patch`](../testcode/linux/patches/opensbi-1.4-amoeba-fail-stop.patch))
handles causes 16, 19, 20 and 21 from any mode by printing `AMOEBA FAIL-STOP:` lines
(cause, `mepc`, `mtval`, trapping mode, `MSECFAULT`, `MFTSTATUS`) and halting the
hart. Stock OpenSBI would redirect them to Linux, which reports "unknown exception"
and sends `SIGILL` to whatever process is running. `make -C sim linux_failstop_cache_ded`
(CI job `ci-linux-failstop-cache-ded`) checks the cause-20/21 path under Linux.

| Interrupt cause | Source |
| --- | --- |
| 1, 3 | Supervisor, machine software interrupt |
| 5, 7 | Supervisor, machine timer interrupt |
| 9, 11 | Supervisor, machine external interrupt |

Delivery requires pending and enable bits plus the applicable global enable.
`mideleg` supports supervisor interrupt bits only (`0x222`). Exceptions use the
trap-vector base even when interrupt vectoring is enabled.

## Verification

Run from the repository root. All datapaths are 64-bit. The first three targets
run in FT CI; the C test is discovered by the existing ISA software regressions
for both the simulation and ASIC SoCs.

| Command | Coverage |
| --- | --- |
| `make -C sim ft_control_test` | [Bus test](../hvl/ft_shadow/ft_control_tb.sv): simulation uncore and both ASIC peripheral placements; reset, six mask bits, reserved bits, byte lane/strobes, APB phases, AHB idle/busy/wait states, and PMA size/address/execute/atomic restrictions |
| `make -C sim ft_core_test` | [Core test](../hvl/ft_shadow/ft_core_fault_tb.sv): executes `sb`/`lbu` for zero, each bit, and all bits; checks all 23 injector enables against mask and master pin. Existing scenarios cover recovery, precise traps, sticky status, and actual LFSR injection |
| `make -C sim ft_shadow_regression` | [Module test](../hvl/ft_shadow/ft_recompute_fault_tb.sv): arithmetic and recovery at mismatch thresholds 1, 2, and 3 |
| `make -C sim run_isa_level PROG=../testcode/isa_level_testing/tc_fault_control.c` | [C test](../testcode/isa_level_testing/tc_fault_control.c): reset mask, individual enables/disables, all 256 byte values, reserved bits, and repeated reads through core loads/stores. Uses the normal startup, UART reporting, and `tohost` pass/fail path with the master pin low; add `DUT=forte` for the ASIC SoC |
