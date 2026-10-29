# Milestone: FreeRTOS and Linux boot on the PYNQ-Z2 DDR backend

*2026-09-08.  A progress marker, not a handoff — work continues below.*

**Status: Linux 6.6 boots to userspace on the tapeout config
(`config_baremetal_linux`), on the FPGA, through DDR.**  The full FreeRTOS
`tc_*` regression suite passes on the same backend.  Booting Linux on the FPGA
was the hard requirement for proving the core out for tapeout; it is met.

Headline numbers from the passing run (25 MHz fabric clock):

| | |
|---|---|
| Boot to userspace (`AMOEBA_LINUX_BOOT_OK`) | 6.21 s wall, 155,261,082 cycles |
| Retired instructions | 67,957,020 (IPC ≈ 0.44 against DDR) |
| Traps (timer, ecall, faults) | 21,670 |
| FreeRTOS heartbeat soak | passes; fabric clock verified 25.000 MHz |

## What the FPGA emulation is

The DUT is `amoeba_soc_wrapper` — `wallypipelinedcore` (the tapeout boundary)
plus Wally's uncore scaffolding (address decode, AHB→APB bridge, CLINT,
NS16550) — kept byte-identical to what the utilization gate measures.  All
debug visibility is read-only hierarchical references; nothing outside the DUT
drives anything inside it except `ExternalStall`.

The PS (Cortex-A9 running PYNQ Linux) owns the experiment.  One fabric clock
(FCLK0 = 25 MHz, timing-closed), no clock-domain crossings.  The core's reset
is a PS-owned register that comes out of configuration asserted, so every run
is: load image → configure/clear monitors → release → observe.

Two memory backends, one parameter (`MEM_BACKEND`):

- **BRAM** — 128 KiB dual-port block RAM behind `ahb_to_memitf`; deterministic
  reference build.
- **AXI** — the core's AHB leaves the top for Xilinx `ahblite_axi_bridge` →
  AXI protocol converter → Zynq HP0 → the same DDR the PS uses.  The core's
  memory is a 256 MiB carve-out at PS physical `0x1000_0000`, address-clamped
  in RTL so the core cannot escape it.

Observability, all PS-readable over AXI-Lite (`amoeba_ctl`, 37 registers):
cycle/retire/trap counters, console FIFO (snooped off AHB writes to the UART —
there are no serial pins), tohost detection, and an external-bus probe with a
64-cycle capture buffer that records address/control/read-data and a per-cycle
core-reset bit.

### The four DDR-integration fixes this milestone rests on

1. **Reset-window traffic.**  Wally drives `HTRANS=NONSEQ` statically while
   held in reset.  `ahb_run` gates `HSEL`/`HTRANS` so no transfer can leave
   while the core is held; the bridge is reset per run but released
   `BRIDGE_LEAD=16` cycles *before* the core so it settles idle.
2. **TrustZone.**  `TZ_DDR_RAM=0` marks all DDR secure-only; the bridge's
   default `C_M_AXI_NON_SECURE=1` produced DECERR on every access.  Fixed with
   `CONFIG.C_M_AXI_NON_SECURE {0}`.
3. **Aborted bursts (the root cause of the final freeze).**  Wally cancels
   in-flight cache-line fills on any PC redirect (`.Flush(FlushD)` on
   `buscachefsm`).  The bridge has a designed termination path, but its only
   entries require `S_AHB_HSEL=1` — and on an abort Wally's address leaves the
   external region, dropping HSELEXT in exactly that cycle.  Fix: the bridge
   is the only slave on the exported bus, so `m_ahb_hsel = ahb_run` (always
   selected while running) and `m_ahb_htrans` masked to IDLE unless genuinely
   addressing external memory.  Every abort now lands in the bridge's
   `burst_term_with_idle` read-swallow path.
4. **`s_ahb_hready_in`** now takes the core's combined bus `HREADY`
   (as CVW's own `fpgaTopArtyA7.sv` wires it), not a self-loop of the
   bridge's `hready_out`.

Also fixed en route: retire/trap counters exist in every build
(`amoeba_retire`), and traps are edge-detected at M (the old walk-to-W tap was
structurally zero because traps flush W in the same cycle).

## How to run: FreeRTOS

```bash
# Host: bitstream (Vivado on PATH), images, deploy
source ~/Xilinx/Vivado/2024.1/settings64.sh
make -C fpga/pynq bitstream MEM_BACKEND=AXI TRACE=0
make -C fpga/pynq images
make -C fpga/pynq deploy MEM_BACKEND=AXI          # rsyncs sw/, bit, images/

# Board (ssh xilinx@192.168.2.99):
cd ~/amoeba/sw
sudo python3 run_freertos.py --bitstream ../amoeba.bit \
    --image ../images/heartbeat_app.elf --fclk 25 --soak 10
# Regression images: tc_*.elf in ~/amoeba/images/ (exit code = HTIF result)
```

Soak mode cross-checks the PL cycle counter against wall time (true fabric
clock) and against the guest's heartbeat rate (the clock the guest *believes*)
— the only tier that catches a wrong `configCPU_CLOCK_HZ`/timebase.

## How to run: Linux

```bash
# Host: image (Linux 6.6 + OpenSBI 1.4, checksum-pinned downloads).
# TIMEBASE_HZ MUST equal the real FCLK0 -- MTIME ticks off HCLK.
make -C testcode/linux CONFIG=baremetal_linux TIMEBASE_HZ=25000000

# Host: ship the two boot blobs (separate dir -- deploy.sh mirrors images/
# with --delete and would evict the tc_* regression images)
rsync -av testcode/linux/build/baremetal_linux/boot_shim.bin \
  testcode/linux/build/baremetal_linux/opensbi/platform/generic/firmware/fw_payload.bin \
  xilinx@192.168.2.99:amoeba/linux/

# Board:
cd ~/amoeba/sw
sudo python3 run_linux.py --bitstream ../amoeba.bit --dir ../linux --timeout 600
```

`run_linux.py` loads `boot_shim.bin` at `0x8000_0000` and `fw_payload.bin`
(OpenSBI + embedded DT + kernel + initramfs) at `0x8020_0000`, verifies both,
releases the core, and stamps milestones M0–M5 with wall time and PL cycles.
It **ignores tohost by design**: `0x8080_0000` (the AXI tohost watch address)
lies inside the kernel image and is written as ordinary memory.  Exit 0 = M5
reached; 3 = panic pattern; 1 = timeout (missed milestones listed).
Per-phase analysis: `python3 testcode/linux/boot_report.py <log> --wall <s>`.

## Board one-time setup (and its sharp edges)

The 256 MiB carve-out must be kept away from PS Linux.  Persistent method that
survives power cycles, needs no packages, and does not touch `boot.scr`:

```bash
sudo mount /dev/mmcblk0p1 /mnt        # the REAL FAT boot partition
printf 'bootargs=root=/dev/mmcblk0p2 rw earlyprintk rootfstype=ext4 rootwait devtmpfs.mount=1 uio_pdrv_genirq.of_id="generic-uio" clk_ignore_unused mem=256M\n' \
  | sudo tee /mnt/uEnv.txt
sudo umount /mnt                      # clean umount IS the flush guarantee
```

PYNQ's `boot.scr` imports `/uEnv.txt` before booting the FIT, and U-Boot's
FDT fixup overrides the devicetree `chosen/bootargs` with the imported value.
Verify after power-cycling: `/proc/cmdline` ends with `mem=256M`;
`grep "System RAM" /proc/iomem` stops at `0fffffff`.  The driver refuses to
map the carve-out until this is true.

Operational hazards, learned the hard way:

- **`/boot` may not be the boot partition.**  It is a plain rootfs directory
  when the FAT mount fails after a hard power cut; check `findmnt /boot`
  before trusting any file there.  `fsck.vfat -a /dev/mmcblk0p1` repairs it.
- **`reboot` is broken on this board** ("Reboot failed -- System halted");
  halt works, so `shutdown -h now` then the power switch.  Consequence: every
  write to the FAT partition needs an explicit `sync`/clean umount before
  cutting power, or it arrives as a 0-byte file.
- A run that reports AHB **error responses** is not trustworthy until the
  bitstream is reloaded (the bridge's HRESP latch clears on the per-run reset,
  but treat errors as a red flag, not a statistic).

## Versions and pins

| Component | Version / pin |
|---|---|
| FPGA toolchain | Vivado 2024.1 (`~/Xilinx/Vivado/2024.1`) |
| Board | PYNQ-Z2 (XC7Z020-1CLG400-1), PYNQ Linux SD image, board at `xilinx@192.168.2.99` (`BOARD_HOST` in `fpga/pynq/Makefile`) |
| Fabric clock | FCLK0 = 25 MHz (`FCLK_MHZ ?= 25`; design timing-closed there) |
| Core config | `pkg/config_baremetal_linux.vh` — RV64 IMAC+Zicsr+Zifencei, S/U, Sv39, no PMP, no PLIC, CLINT+UART, `EXT_MEM_RANGE` 256 MiB |
| CVW | `third_party/cvw` @ `28c6cce87` |
| FreeRTOS kernel | `third_party/FreeRTOS-Kernel` @ `ce221a8bb` (V10.4.0-kernel-only-844) |
| Guest Linux / firmware | Linux **6.6**, OpenSBI **1.4** (checksum-pinned downloads in `testcode/linux/Makefile`) |
| Kernel cross-toolchain | kernel.org crosstool gcc **13.2.0** nolibc (auto-downloaded), or host `riscv64-linux-gnu-` |
| Baremetal toolchain | `riscv64-unknown-elf-gcc` 13.2.0 |
| Lint | Verilator 5.026 |
| PS-side software | `fpga/pynq/sw/` — pure Python 3 over `/dev/mem` (`O_SYNC`, uncached), no PYNQ-framework dependency; 24 unit tests (`test_device.py`), register map cross-checked against RTL (`check_regs.py`) |

Xilinx IP: `ahblite_axi_bridge` v3.0, PS7 preset from the PYNQ-Z2 board files
(install via Vivado Store, or `BOARD_REPO=`).  `opt_design_pre.tcl` works
around a Vivado 2024.1 power-opt crash (`pwropt.maxFaninFanoutToNetRatio`).

## Future work

1. **Busybox initramfs with a scripted `rcS`** (software only).  Replaces the
   print-and-spin `init.S`; makes the Linux boot a programmable regression
   vehicle (e.g. `memtester` as a Linux-driven DDR soak).  First step toward
   the shell, and useful on its own.
2. **Interactive shell — console input path** (PL scaffolding only, no DUT
   changes).  Output is snooped; input needs a transmitter into the DUT's
   `UARTSin` port: `amoeba_bus_mon` already shadows DLAB and will capture the
   guest's `DLL`/`DLM` writes, so a small serializer can drive `UARTSin` at
   exactly `PCLK/(16·divisor)` — matching the guest's receiver regardless of
   the devicetree's nominal UART clock.  Plus two ctl registers and a raw-mode
   stdin pump in `run_linux.py`.  The polled 8250 (`irq = 0`) already services
   RX.  Est. 2–3 days.
3. **Runtime carve-out via CMA** (optional): base register + smaller clamp
   window + `pynq.allocate`, for running on unmodified SD cards.  Does not
   cover the 256 MiB Linux case; `uEnv.txt` remains the answer there.
4. **Trace on the AXI build** (`TRACE=1`) when a divergence needs
   reference-model lockstep.
5. **Watch items**: the reset-distribution net's WNS swing (0.897→0.054→0.353
   ns across recent builds — placement noise so far, on a half-cycle path);
   the driver-teardown segfault (mitigated by deterministic close, never
   root-caused); `testcode/freertos/README.md` is a stale stub.
