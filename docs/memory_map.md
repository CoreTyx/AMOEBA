# Processor memory map, custom CSRs, and trap causes

This document describes the 64-bit processor built from
[`pkg/config.vh`](../pkg/config.vh) and the working RTL in `hdl/core`.
Addresses below are physical byte addresses. The memory system is little-endian.
A byte is 8 bits, a word is 32 bits, and a doubleword is 64 bits.

There are two register interfaces:

- **Memory-mapped control/status registers** are peripheral addresses accessed
  with ordinary loads and stores. Their permissions follow virtual-memory and
  physical-memory protection. An address is not restricted to machine mode just
  because its register controls a processor feature.
- **Instruction-addressed CSRs** use the 12-bit CSR number in RISC-V CSR
  instructions such as `csrr` and `csrw`. These numbers are not memory addresses.
  The custom CSRs listed here require machine-mode privilege.

The simulation wrapper uses `wallypipelinedsoc` and `uncore`. The ASIC uses
`forte_soc` and `forte_uncore`. The ASIC's `PERIPH_ONCHIP` parameter controls where
UART and PLIC accesses are serviced; it does not relocate their addresses.

## Physical address regions

| Physical address or range | Function | Availability |
| --- | --- | --- |
| `0x0200_0000–0x0200_ffff` | Core-local interrupt controller (CLINT): software interrupt and timer | Both SoCs |
| `0x0200_f000–0x0200_f007` | Design-for-test (DFT) lock, overriding this part of the CLINT region | ASIC only; simulation SoC reads zero here |
| `0x0c00_0000–0x0fff_ffff` | Platform-level interrupt controller (PLIC) | Simulation SoC; on-chip ASIC when `PERIPH_ONCHIP=1`, external when `=0` |
| `0x1000_0000–0x1000_0007` | 16550-style UART serial interface | Same placement options as PLIC |
| **`0x1007_000b`** | **Per-unit fault-injection control byte** | Both SoCs; always on-chip in the ASIC |
| `0x8000_0000–0x8fff_ffff` | External memory, 256 MiB | Both SoCs; ASIC accesses use the external link |

The reset PC is `0x8000_0000`. The simulation software-to-host completion address
`0x8080_0000` is an ordinary external-memory location monitored by the test harness;
it is not an on-chip CSR. FPGA host-side control registers belong to a separate
host address space and are not processor CSRs.

The peripheral regions are uncached, non-idempotent device memory. This prevents
normal cache fills and speculative/repeated device accesses. They do not permit
instruction fetch or atomic memory operations. Physical-memory protection (PMP)
and page permissions still apply. The address checker also enforces each
peripheral's supported access sizes. See
[`adrdecs.sv`](../hdl/core/mmu/adrdecs.sv) and
[`pmachecker.sv`](../hdl/core/mmu/pmachecker.sv).

## Fault-injection control: `0x1007_000b`

`FI_CONTROL` is an **8-bit read/write register**, reset value **`0x3f`**. Use `lbu`
and `sb`, or a `volatile uint8_t` pointer. Halfword, word, and doubleword accesses
are not supported; neighboring bytes are not aliases of this register. Alignment
or physical-access checks reject unsupported accesses before the peripheral.

Each bit selects a group of artificial fault injectors:

| Bit | Unit | Signals affected |
| --- | --- | --- |
| 0 | ALU | Architectural result, extended arithmetic/address result, and widened shift result, in both ALU replicas |
| 1 | Comparison | Extended register-comparison difference, in both comparison replicas inside `ft_alu` |
| 2 | Multiplier | Full product from both `ft_mul` replicas |
| 3 | Divider | Quotient and remainder from both `ft_div` replicas |
| 4 | Integer register-file ECC | Both protected register-file read paths |
| 5 | Pipeline-register ECC | `RD1EReg`, `RD2EReg`, `ImmExtEReg`, `SrcAMReg`, `IEUResultMReg`, `WriteDataMReg`, and `IFResultWReg` in the integer datapath |
| 7:6 | Reserved | Read zero; writes ignored |

ECC means error-correcting code. Bits 4 and 5 select storage-error injection;
bits 0–3 select faults in duplicated execution results. ALU and comparison are
independent despite sharing the `ft_alu` module.

The external `fault_inject` pin remains the master enable:

```text
injector enabled = fault_inject pin AND FI_CONTROL[unit bit]
```

Reading the register returns the programmed bits, including while the pin is
low. Writing a zero bit disables that group's artificial corruption; writing a
one allows it while the pin is high. The register can be rewritten in either
direction. Reset enables all six groups, so the pin retains its all-units behavior
until software selects a different mask. The DFT lock does not gate this pin.

Turning injection off does not disable ECC, replica checking, recovery, or
trapping. It does not clear MFTSTATUS or MSECFAULT, cancel an already-detected
terminal fault, or restart an injector's sequence. Execution injectors retain
their local LFSRs and staggered one-clock events every 512 clocks. A bit enables
both replicas' injectors for that unit; it does not select a particular replica,
fault bit, or fault kind.

### Software access

```c
#include <stdint.h>

#define FI_CONTROL (*(volatile uint8_t *)(uintptr_t)0x1007000b)

FI_CONTROL = 0x04;  // Allow multiplier injection only, while the pin is high.
__asm__ volatile ("fence iorw, iorw" ::: "memory");
uint8_t selected_units = FI_CONTROL;  // Reads 0x04 regardless of pin state.

FI_CONTROL = 0;     // Disable all artificial fault injection.
__asm__ volatile ("fence iorw, iorw" ::: "memory");
```

Supervisor/user software needs an appropriate mapping and permission to reach
this physical address. Firmware can restrict access using PMP and page tables.
The peripheral bus does not impose an additional machine-mode-only check.

### Hardware path and write timing

The load/store unit's physical-address checker recognizes the exact address as
a byte-only peripheral. The core's AHB bus reaches the SoC's AHB-to-APB bridge;
[`fault_inject_apb.sv`](../hdl/core/uncore/fault_inject_apb.sv) commits a write only
when APB select, enable, write, and byte strobe 3 are asserted. Address offset
`0xb` selects byte lane 3 of the 64-bit bus. Bits `[29:24]` provide the six enables;
read data places them in the same byte lane with all other bits zero.

```text
AHB address decode -> APB bridge -> faultcontrol.FaultInjectMask
  -> wallypipelinedsoc / forte_soc
  -> wallypipelinedcore: AND each bit with fault_inject
       [0,1,4,5] -> IEU -> datapath -> ALU, comparison, register-file ECC, pipeline ECC
       [2,3]     -> MDU -> multiplier, divider
```

The register is in the core clock domain. Its update takes effect after the
clock edge that accepts the APB write. Bus wait states and idle/busy AHB cycles
do not independently write it. No new package pins are added.

## CLINT registers

[`clint_apb.sv`](../hdl/core/uncore/clint_apb.sv) implements one hart's timer and
software interrupt. CLINT is on-chip in both ASIC peripheral configurations.

| Physical address | Register | Access and reset | Meaning |
| --- | --- | --- | --- |
| `0x0200_0000` | `msip` | Read/write bit 0, reset 0 | Set bit 0 to assert the machine software interrupt; clear it to deassert |
| `0x0200_4000` | `mtimecmp` | Read/write 64 bits, reset all ones | Machine timer interrupt is pending when `mtime >= mtimecmp` |
| `0x0200_bff8` | `mtime` | Read/write 64 bits, reset 0 | Increments once per core clock except during writes |

Use aligned doubleword loads/stores for these registers. The timer registers
honor byte write strobes; the RV64 `msip` write logic consumes bus bit 0. Unused
CLINT offsets read zero and ignore writes, apart from the ASIC DFT-lock override.
`TIMECLK` does not drive this implementation's counter. The standard `time` CSR,
when enabled by configuration and CSR permissions, observes the timer value;
there is no instruction-addressed `mtime` CSR at `0xb01`.

## DFT lock: ASIC `0x0200_f000`

[`forte_dft_lock.sv`](../hdl/forte_dft_lock.sv) implements bit 0, `unlocked`, with
reset value 1. Use an aligned doubleword access at `0x0200_f000`, or byte access
to that exact address. The ASIC reserves the containing doubleword for this
register. A write with byte lane 0 enabled and data bit 0 clear locks DFT; writing
one cannot unlock it. Only reset restores the unlocked state. Upper read bits
are zero, and writes outside byte lane 0 do not change it.

`forte_chip` ANDs `test_mode` and `scan_en` with `unlocked`. This register controls
scan/test access, not fault injection. It remains on-chip with
`PERIPH_ONCHIP=0`. The simulation SoC has no DFT lock at this address.

## PLIC registers

Use aligned **32-bit** loads/stores. There are two interrupt contexts: context 0
for machine mode and context 1 for supervisor mode. The current configuration
has ten source IDs (1–10); ID 0 means no interrupt. Priority and threshold fields
are three bits. Priorities, enables, thresholds, and in-progress state reset to
zero. Pending state reflects incoming interrupts.

| Physical address | Register | Access and effect |
| --- | --- | --- |
| `0x0c00_0000 + 4*source` | Source priority, IDs 1–10 | Read/write priority 0–7; zero disables the source's priority |
| `0x0c00_0000` | Priority for ID 0 | Reads zero; no usable interrupt source |
| `0x0c00_1000` | Pending bits for IDs 0–31 | Read-only; bit 0 is zero |
| `0x0c00_2000` | Context 0 enable bits | Read/write; source ID maps to the same bit number |
| `0x0c00_2080` | Context 1 enable bits | Read/write |
| `0x0c20_0000` | Context 0 threshold | Read/write; eligible priority must exceed the threshold |
| `0x0c20_0004` | Context 0 claim/complete | Read claims one interrupt and returns its ID; write its nonzero ID to complete it |
| `0x0c20_1000` | Context 1 threshold | Read/write |
| `0x0c20_1004` | Context 1 claim/complete | Same claim/complete semantics for supervisor context |

Offsets `+0x1004`, `+0x2004`, and `+0x2084` are upper pending/enable words for
configurations with at least 32 sources; they are not implemented for the current
ten-source configuration. Use the canonical addresses above: this PLIC decodes
only the low 24 address bits inside its larger physical region.

In the on-chip ASIC, UART is source 10, external `irq[0]` is source 3, and external
`irq[1]` is source 6. In the simulation SoC, IDs 3/6/9 connect to GPIO/SPI/SDC,
which are disabled in the current configuration. With off-chip ASIC peripherals,
PLIC/UART accesses leave through the external bus and interrupt inputs are
provided externally. See [`plic_apb.sv`](../hdl/core/uncore/plic_apb.sv) and
[`forte_uncore.sv`](../hdl/forte_uncore.sv).

## UART registers

Use **byte** loads/stores at `0x1000_0000 + offset`. `DLAB` is bit 7 of the line
control register; it selects the meanings of offsets 0 and 1.

| Offset | Register | Access and effect |
| --- | --- | --- |
| `0x0`, DLAB=0 | RBR / THR | Read receive byte (consumes it); write transmit byte |
| `0x0`, DLAB=1 | DLL | Read/write low divisor byte; reset 1 |
| `0x1`, DLAB=0 | IER | Read/write interrupt enables `[3:0]`; reset 0 |
| `0x1`, DLAB=1 | DLM | Read/write high divisor byte; reset 0 |
| `0x2` | IIR / FCR | Read interrupt identification; write FIFO control, including receive/transmit FIFO reset requests |
| `0x3` | LCR | Read/write line format and DLAB; reset `0x03` (8-bit data) |
| `0x4` | MCR | Read/write modem controls `[4:0]`; reset 0 |
| `0x5` | LSR | Read line status: bit 0 receive-ready, bit 5 transmit-holding-empty, bit 6 transmitter-empty; reads also participate in clearing receive-error indications |
| `0x6` | MSR | Read modem inputs/deltas; reading clears delta bits `[3:0]` |
| `0x7` | SCR | Read/write scratch byte; reset 0 |

IER bits 0–3 enable receive-data, transmit-empty, line-status, and modem-status
interrupts. FCR bit 0 enables FIFOs, bits 1/2 request receive/transmit FIFO resets,
and bits 7:6 select the receive trigger level. LCR bits 1:0 select data length,
bit 2 stop-bit selection, bits 5:3 parity controls, bit 6 break, and bit 7 DLAB.
The RTL additionally permits test writes to LSR `[6:1]` and MSR `[3:0]`.
See [`uartPC16550D.sv`](../hdl/core/uncore/uartPC16550D.sv) for serial timing and
status-update details.

## Configured but disabled peripheral maps

The following blocks have addresses in `pkg/config.vh` but their support bits
are zero. They are not usable MMIO registers in the current processor. The ASIC
uncore omits these blocks; enabling them in a configuration alone does not add
them to the ASIC. The simulation uncore conditionally instantiates them.

### GPIO, base `0x1006_0000`, 32-bit registers

| Offsets | Registers / behavior when the block is enabled |
| --- | --- |
| `0x00` | Input value, read-only |
| `0x04` | Input enable |
| `0x08`, `0x0c` | Output enable, output value |
| `0x18`, `0x1c` | Rising-edge interrupt enable, pending |
| `0x20`, `0x24` | Falling-edge interrupt enable, pending |
| `0x28`, `0x2c` | High-level interrupt enable, pending |
| `0x30`, `0x34` | Low-level interrupt enable, pending |
| `0x38`, `0x3c` | Alternate I/O-function enable, selection |
| `0x40` | Output XOR mask |

Pending registers use write-one-to-clear. Other control registers are read/write.
The configured region extends through `0x1006_00ff`.
See [`gpio_apb.sv`](../hdl/core/uncore/gpio_apb.sv).

### SPI and SD-card SPI

SPI base is `0x1004_0000`, region size `0x1000`. The SD-card SPI instance has base
`0x0001_3000`, region size `0x1000`, and uses the same register layout. Use aligned
32-bit accesses for the listed registers when the block is enabled.

| Offset | Register | Meaning |
| --- | --- | --- |
| `0x00`, `0x04` | SCKDIV, SCKMODE | Serial clock divisor, phase/polarity |
| `0x10`, `0x14`, `0x18` | CSID, CSDEF, CSMODE | Chip-select index, default levels, operating mode |
| `0x28`, `0x2c` | DELAY0, DELAY1 | Chip-select/transfer timing |
| `0x40` | FMT | Frame protocol, endianness, direction, and length |
| `0x48` | TXDATA | Write transmit data; read FIFO-full status |
| `0x4c` | RXDATA | Read receive data and FIFO-empty status; read consumes data |
| `0x50`, `0x54` | TXMARK, RXMARK | FIFO interrupt thresholds |
| `0x70`, `0x74` | IE, IP | Interrupt enables (read/write), pending (read-only) |

Other listed controls are read/write. See
[`spi_apb.sv`](../hdl/core/uncore/spi_apb.sv). Disabled boot ROM, tightly integrated
memories, and uncore RAM are memory options, not additional control registers.
The `trickbox_apb` module is not instantiated by either current SoC.

## Custom instruction-addressed CSRs

All three are 64-bit machine-mode CSRs. Unimplemented upper bits read zero.
Access from insufficient privilege or an illegal write uses the illegal
instruction exception (cause 2). These CSR numbers do not overlap the MMIO
address of FI_CONTROL. See [`csrm.sv`](../hdl/core/privileged/csrm.sv).

| CSR number | Name | Access | Reset |
| --- | --- | --- | --- |
| `0x7c0` | MSECFAULT | Read; write-one-to-clear event bits | 0 |
| `0x7c1` | RANDINSTRFREQ | Read/write low 32 bits | 0 |
| `0x7c2` | MFTSTATUS | Read-only; writes rejected | 0 |

### MSECFAULT (`0x7c0`)

| Bit | Event |
| --- | --- |
| 0 | Correctable disagreement in triplicated privilege-mode storage |
| 1 | Reserved `mstatus.MPP=2` encoding detected |
| 2 | Illegal CSR access on a valid instruction |
| 3 | Uncorrectable privilege-mode disagreement: no majority |
| 4 | Register-file or pipeline-register ECC single-bit correction |
| 5 | Register-file or pipeline-register ECC double-bit detection; the associated hardware-error path uses cause 19 |
| 6 | Reserved, zero |
| 63:7 | Zero |

Bits accumulate until software writes ones to clear them or resets the processor.
The implemented update is `(old | events) & ~written_clear_bits`, so clearing
wins if the same event is asserted on that edge. Writing zero leaves a bit alone.
Privilege-mode uncorrectable status also has a hardware output; it is not mapped
to FT cause 16. See [`csrharden.sv`](../hdl/core/privileged/csrharden.sv).

### RANDINSTRFREQ (`0x7c1`)

Low 32 bits program the divider period for random dummy-instruction insertion;
zero disables insertion. The generator strobes once per programmed period and
alternates preparation/insertion, so an insertion opportunity occurs every two
periods before pipeline constraints. This feature is separate from artificial
fault injection and is not controlled by FI_CONTROL. See
[`dummygen.sv`](../hdl/core/ieu/dummygen.sv).

### MFTSTATUS (`0x7c2`)

| Bit | Event |
| --- | --- |
| 0 | ALU controller isolated a replica |
| 1 | Comparison controller isolated a replica |
| 2 | MUL isolation; currently zero because MUL only retries or reports unresolved |
| 3 | DIV isolation; currently zero because DIV only retries or reports unresolved |
| 5:4 | Reserved, zero |
| 6 | Unresolved FT result reached M |
| 63:7 | Zero |

The core accumulates these bits in `FTStatusSticky`; only reset clears them.
A pipeline flush or disabling injection does not clear them. Successful ordinary
retry sets no bit. Successful ALU/comparison isolation sets its status bit without
a cause-16 exception. Bit 6 records arrival of the unresolved indication even if
another exception wins trap priority. This CSR does not record ECC events, select
which replica to inject, or identify the isolated replica.

## Trap causes

A trap transfers control to a privilege-mode handler. In RV64, `mcause[63]=0`
means a synchronous exception; `mcause[63]=1` means an interrupt. The number below
occupies the low cause bits. `scause` uses the same encoding for delegated traps.
The implementation selects causes in [`trap.sv`](../hdl/core/privileged/trap.sv).

### Synchronous exceptions

| Cause | Meaning |
| --- | --- |
| 0 | Instruction address misaligned |
| 1 | Instruction access fault |
| 2 | Illegal instruction, including illegal CSR access |
| 3 | Breakpoint |
| 4 | Load address misaligned |
| 5 | Load access fault |
| 6 | Store/atomic address misaligned |
| 7 | Store/atomic access fault |
| 8 | Environment call from user mode |
| 9 | Environment call from supervisor mode |
| 11 | Environment call from machine mode |
| 12 | Instruction page fault |
| 13 | Load page fault |
| 15 | Store/atomic page fault |
| **16** | **Custom FT unresolved result** |
| **19** | **Hardware error from uncorrectable storage ECC** |

Other cause numbers are not generated by this processor's trap selector.
Cause 0 in the reset branch of that selector is a default value, not a software
reset exception. With compressed instructions enabled, the implementation does
not normally generate instruction-address-misaligned faults.

For cause 16, `mepc` holds the faulting M-stage instruction PC and `mtval=0`.
ALU/comparison and divider terminal faults are carried from E into M with their
instruction; multiplier faults originate in M. An unrelated stall cannot discard
a pending terminal fault. Trap entry suppresses the faulting normal result,
flushes younger work, and redirects to the machine trap-vector base in `mtvec`.

For cause 19, a saved ECC fault record supplies `mepc` and `mtval` when that cause
wins selection. The generic trap path retains this error's recorded PC rather
than substituting an unrelated current instruction PC.

The implemented `medeleg` is 16 bits. Causes 16 and 19 therefore always enter
machine mode. Lower exceptions follow supported `medeleg` bits and the current
privilege mode. Interrupts and instruction page/access/illegal-instruction faults
have priority over cause 16. Cause 19 is lower in the selector than the other
listed synchronous exceptions. `ZICCLSM_SUPPORTED=0` in the current configuration
places load/store misalignment ahead of their page/access faults.

### Interrupts

| Cause | Source |
| --- | --- |
| 1 | Supervisor software interrupt |
| 3 | Machine software interrupt (CLINT `msip`) |
| 5 | Supervisor timer interrupt |
| 7 | Machine timer interrupt (CLINT timer comparison) |
| 9 | Supervisor external interrupt (PLIC context 1 or external input) |
| 11 | Machine external interrupt (PLIC context 0 or external input) |

Interrupt delivery also requires the corresponding pending and enable bits and
global privilege-mode interrupt enable. `mideleg` supports delegation of supervisor
software/timer/external interrupt bits (mask `0x222`); machine interrupt causes
are not delegated. Synchronous exceptions use the trap-vector base even when
interrupt vectoring is configured.

## Verification of fault-control mapping

Run these targets from the repository root:

```sh
make -C sim ft_control_test
make -C sim ft_core_test
make -C sim ft_shadow_regression
```

`ft_control_test` drives AHB transactions through the simulation uncore and both
ASIC peripheral-placement configurations. It checks reset/readback, all six
individual bits, reserved bits, the byte-3 data lane and strobe, setup versus
access phase, idle/busy transfers, external-bus wait states, and physical-access
rules for neighboring addresses, wider accesses, instruction fetch, and atomics.

`ft_core_test` executes real `sb`/`lbu` instructions to select zero, each individual
unit, and all units, checking completed load values. It checks the enable input
of every execution-result and ECC injector while toggling the master pin. Its
other scenarios cover recovery, precise traps, sticky status, and actual shared
injection with the reset mask. `ft_shadow_regression` checks arithmetic/recovery
on 64-bit modules at thresholds 1, 2, and 3. All three targets run in the FT CI job.
