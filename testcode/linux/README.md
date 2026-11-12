# Linux boot test

Boots Linux 6.6 on the CVW core under Verilator and checks that it reached
userspace, then runs a handful of small user programs. The pass criterion is a
string printed by PID 1 over the SoC's NS16550 UART.

## Why this tier exists

The bare-metal, ISA-level and FreeRTOS tiers all run in M-mode. None of them
exercise the parts of CVW that are hardest to get right: S/U privilege
transitions, Sv39 page-table walks, hardware A/D bit updates, `sfence.vma`,
cache-block operations, or PLIC-routed device interrupts. A Linux boot hits all
of them, continuously, for hundreds of millions of cycles.

## Layout

```
Makefile                 image build: shim + OpenSBI + kernel + initramfs
boot_shim.S              reset-vector entry; sets a0=hartid, jumps to firmware
uart_smoke.S             console-path pre-flight (no firmware needed)
dts/amoeba.dts           device tree; forked from cvw/linux/devicetree/wally-virt.dts
configs/linux_amoeba.config   kernel fragment merged over riscv defconfig
initramfs/init.c         PID 1: prints the boot string, runs /bin/*, never exits
initramfs/initramfs.spec gen_init_cpio spec (creates /dev/console without root)
userland/                freestanding user programs run by /init (see below)
build/                   downloads and build products (gitignored)
```

## Memory layout

| Address | Contents |
|---|---|
| `0x8000_0000` | `boot_shim.bin` — reset vector |
| `0x8020_0000` | OpenSBI `fw_payload.bin` (device tree embedded) |
| `0x8040_0000` | Linux `Image`, with the initramfs built in |

OpenSBI starts 2 MB up so its payload lands on the 2 MB boundary the RISC-V boot
protocol expects. The gap costs nothing: the `.lst` format stores each blob
under its own `@address`, and the testbench memory is a sparse associative
array.

## Building and running

```bash
# Console-path pre-flight -- seconds, no kernel needed.  Run this first
# whenever the testbench changes.
make -C testcode/linux smoke
make -C sim linux_boot LINUX_MEMLST=$PWD/testcode/linux/build/uart_smoke.lst \
                       LINUX_PASS=AMOEBA_UART_OK LINUX_TIMEOUT=400000

# Full boot image (downloads Linux 6.6 + OpenSBI 1.4, both checksum-pinned)
make -C testcode/linux

# Build the simulator, then boot
make -C sim build_linux
make -C sim linux_boot
```

`make -C sim linux_boot` takes these overrides:

| Variable | Default | Purpose |
|---|---|---|
| `LINUX_PASS` | `AMOEBA_LINUX_BOOT_OK` | UART string that ends the run successfully |
| `LINUX_FAIL` | `Kernel panic\|Unable to handle kernel\|Oops:\|SBI panic` | `\|`-separated abort patterns |
| `LINUX_TIMEOUT` | `2000000000` | cycle budget |
| `LINUX_MEMLST` | `build/boot.lst` | image to load |

## Milestones

`LINUX_PASS` selects how far the boot has to get, so an early stage can be a
cheap CI gate while a full boot stays a nightly job. `boot_report.py` turns any
boot log into a table of these with per-phase cycle costs.

| | `LINUX_PASS=` | Proves |
|---|---|---|
| M0 | `OpenSBI v1.` | Shim, image loader, UART, M-mode firmware |
| M1 | `Linux version 6.6` | Kernel entry, SBI console |
| M2 | `printk: bootconsole` | Console handover to the 8250 driver |
| M3 | `Initmem setup node 0` | MMU enabled, page tables walked, memblock done |
| M4 | `Freeing unused kernel image` | Full kernel init, drivers probed |
| M5 | `AMOEBA_LINUX_BOOT_OK` | Userspace reached, U-mode syscalls work |
| M6 | `AMOEBA_LINUX_PROGS_OK` | fork/execve/wait4 work and every user program passed |

```bash
python3 testcode/linux/boot_report.py sim/verilator/linux_boot/simulation.log --wall 385
```

M5 is printed by `/init` *before* it starts any program, so it means exactly
what it did when `/init` printed one string and stopped; the boot nightly
(`linux-boot.yml`) still stops there. M6 is the userspace nightly
(`linux-userspace.yml`). Run it locally with:

```bash
make -C sim linux_boot LINUX_PASS=AMOEBA_LINUX_PROGS_OK \
  LINUX_FAIL='Kernel panic|Unable to handle kernel|Oops:|SBI panic|AMOEBA_PROG_FAIL'
```

## User programs

`/init` (`initramfs/init.c`) forks and `execve`s each program in turn as
`/bin/<name>`, waits for it, and prints `PROG_EXIT <name> <code>` (or
`PROG_EXIT <name> signal <n>` if it was killed). After the last it prints
`AMOEBA_LINUX_PROGS_OK` if every program exited 0, otherwise
`AMOEBA_PROG_FAIL <first failing name>`, and then spins forever.

Each program prints one result line, `PROG <name> PASS <checksum-hex>` or
`PROG <name> FAIL <reason>`, and exits 0 only on a pass. The checksum is
deterministic (no addresses, PIDs or times go into it), so it can be compared
across runs.

| Program | Checks |
|---|---|
| `arith` | Every RV64M instruction and the shift family against expected values, including divide-by-zero, `INT_MIN / -1` and the `*W` forms' sign extension; random-operand identities (`mul` against a software multiply, `q*b + r == a`); CRC-32 of `"123456789"` == `0xCBF43926`, and bitwise against table-driven CRC-32 over 4 KiB |
| `mem` | `brk` grow 64 KiB / fill / verify / shrink; anonymous `mmap` of 128 KiB read-faulted to the zero page then written (copy-on-write fault per page), verified, sub-word store merging, `munmap`, twice |
| `proc` | three `fork`ed children exiting with distinct codes, reaped out of order with `wait4`, then `-ECHILD`; pipe ping-pong of 4 messages with a child, EOF after it exits |
| `sys` | `getppid() == 1`, `uname` reports `Linux` / `6.6` / `riscv64`, `CLOCK_MONOTONIC` strictly increases across a busy loop |

Together they cost a few million cycles after M5 -- small next to the boot
itself; `boot_report.py` prints a per-program breakdown.

Everything under `userland/` is freestanding C: no libc, just

- `syscall.h` -- inline-asm `ecall` wrappers for the RISC-V Linux syscall
  ABI. RISC-V uses the asm-generic table, so there is no `fork`, `pipe`,
  `dup2` or `waitpid`; the wrappers use `clone(SIGCHLD)`, `pipe2`, `dup3` and
  `wait4` the way a libc would.
- `crt0.S` -- `_start` sets `gp`, calls `main(argc, argv, envp)`, and passes
  its return value to `exit_group`.
- `ulib.c` / `ulib.h` -- `mem*`/`str*`, line-buffered output (one `write` per
  line, so concurrent processes cannot interleave mid-line), CRC-32, and the
  `prog_pass` / `prog_fail` result-line helpers.

All are built with `-march=rv64imac -mabi=lp64 -O2 -ffreestanding -nostdlib
-nostartfiles -static` and stripped, by the same `CROSS_COMPILE` as the
kernel. `make -C testcode/linux userland` builds just them.

### Adding a program

1. Write `userland/<name>.c` with a `main` that prints its result line via
   `prog_pass(name, checksum)` or `return prog_fail(name, "reason")`, and
   returns 0 only on success. Use only syscalls in `syscall.h` (add a wrapper
   there if needed, and check the kernel config enables the feature).
2. Append `<name>` to `PROGS` in the `Makefile`. That one list drives the
   build, the `file /bin/<name>` lines appended to the initramfs spec, and the
   order `/init` runs them in -- nothing else needs editing.
3. Keep it short: the core runs about 100k cycles per second of wall time
   in Verilator. Aim for well under a million cycles; `fork` and `execve`
   are the expensive parts, not arithmetic.

## What makes this finish in hours instead of weeks

**Waveforms are compiled out, not disabled.** `make -C sim build_linux` builds
without `--trace-fst`. `+NO_DUMP_ALL_ECE411` is not enough — the SV-side
`$dumpvars` keeps writing regardless of the plusarg. Measured on a 20-core host
over 5M cycles: 2.2 kHz with tracing live, 116 kHz without, and a boot-length
trace would run to hundreds of GB. The build is also single-threaded on purpose:
on a single-hart in-order core, `--threads 4` measured 11% *slower* than
`--threads 1` at four times the CPU.

**The device tree must state the timer rate truthfully.** CVW's CLINT
increments MTIME once per system clock, so `timebase-frequency` is 100 MHz
(`TIMEBASE_HZ` in the Makefile). One jiffy (`HZ=100`) therefore costs 1,000,000
simulated cycles, and every `msleep(20)` costs two million.

> **Do not "optimise" this by declaring a lower frequency.** Understating it
> looks like a free 100x cut to every timer wait, and an earlier draft of this
> document recommended exactly that. It livelocks the kernel.
> `timebase-frequency` is what Linux uses to convert nanoseconds into MTIME
> ticks. Declaring 1 MHz against 100 MHz hardware makes the kernel's nanosecond
> 100x coarser than the hardware's, so each hrtimer deadline is programmed to an
> MTIME value that has *already* passed. The interrupt re-fires on return from
> the handler and the boot stops making forward progress. The symptom is a boot
> that runs for hundreds of millions of cycles while the heartbeat PC sits in
> `ktime_get`, `hrtimer_interrupt`, `clockevents_program_event` and
> `riscv_clock_next_event`.

**Timer cost is cut in the kernel config instead.** `CONFIG_HZ_PERIODIC=y` with
`CONFIG_HIGH_RES_TIMERS` off keeps the timer on a plain periodic tick, so the
boot pays one interrupt per 1,000,000 cycles instead of reprogramming a one-shot
comparator on every hrtimer expiry.

The kernel command line also carries `no5lvl no4lvl`. Linux probes SATP for
Sv57, then Sv48, then Sv39, keeping the deepest the hardware accepts; CVW
accepts all three, so an unhinted kernel would pick Sv57 and pay a five-level
page walk on every TLB miss. These force Sv39 and its three-level walk.

## Toolchain

The kernel's VDSO cannot be linked by a bare-metal `riscv64-unknown-elf-`
toolchain, so the Makefile uses a host `riscv64-linux-gnu-` (or
`riscv64-unknown-linux-gnu-`) compiler if there is one, else fetches
kernel.org's checksum-pinned nolibc cross compiler (see the Makefile).
`/init` and `userland/` are freestanding C against the Linux syscall ABI,
built by that same compiler, so no musl, glibc or buildroot is needed. A
richer busybox userland would need a full `riscv64-*-linux-gnu` toolchain with
a libc; that is deliberately out of scope here.

## Console plumbing

Two things about the console are worth knowing before debugging a silent boot.

**The console tap must come from the UART peripheral, not RVFI.** `monitor_mem_addr`
is driven from `IEUAdrW`, which is a *virtual* address. An RVFI-based snoop on
physical `0x10000000` therefore works only while the MMU is off -- it captures
OpenSBI perfectly and then goes silent at the exact moment Linux enables paging,
which looks identical to the kernel hanging. Under `ECE411_LINUX` the testbench
instead watches the 16550's own write strobe
(`dut.soc.uncoregen.uncore.uartgen.uart.uartPC`), which is physical by
construction and works in every privilege mode.

**Characters used to appear twice.** That was two independent printers -- the
ungated RVFI capture in `hvl/common/monitor.sv` and the CVW model's own
`$write` in `uartPC16550D.sv` -- each firing once per store, not a duplicated
bus write. Both are compiled out under `ECE411_LINUX`, leaving the single
cycle-stamped `[UART @<cycle>]` stream.

## A verification-IP bug this test found

The riscv-formal monitor's `clz` and `ctz` models were both wrong, and a Linux
boot is what exposed them. The generated loops assign on *every* set bit instead
of stopping at the first, so each ended up reporting the bit at the far end of
the word -- `ctz` returned the highest set bit and `clz` the lowest. The two
instructions were effectively swapped.

The boot died at 53.5M cycles on `ctz x6, x6` with `rs1 = 0xffffff0000000000`.
The core returned 40, which is correct -- that value has 40 trailing zeros. The
monitor demanded 63, the index of its highest set bit. A value whose lowest and
highest set bits differ is required to tell the two apart, which is why no
bare-metal test had ever caught it; the kernel's `__ffs()` hits it constantly.

`hvl/common/rvfimon.v` is patched locally for all four variants (`clz64`,
`clz32`, `ctz64`, `ctz32`) by reversing the iteration order. **That file is
generated**, so the same fix belongs upstream in `third_party/riscv-formal`, and
`make -C sim check-generated` will report `rvfimon.v` as stale until it lands
there. Note that the riscv-formal submodule's working tree is currently empty in
this checkout, so the file cannot be regenerated here in any case.
