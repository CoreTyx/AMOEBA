# FreeRTOS on Wally

Runs FreeRTOS on the Wally RISC-V core using the existing `examples/C/common`
BSP (crt.S, syscalls.c, test.ld) as the foundation. No modifications to Wally
sources are needed.

## Directory layout

```
freertos_wally/
├── README.md
├── Makefile
├── FreeRTOSConfig.h
├── main.c
├── wally_clint.h          # CLINT register definitions from config.vh
├── wally_uart.h           # UART register definitions from config.vh
└── port/
    └── portmacro_wally.h  # Any Wally-specific port overrides
```

FreeRTOS-Kernel is expected at `~/FreeRTOS-Kernel` (cloned separately).
The Wally common BSP is used directly from `examples/C/common`.

## Quick start

```bash
# 1. Setup (if not done already)
../../../setup.sh
git clone --depth=1 https://github.com/FreeRTOS/FreeRTOS-Kernel.git ~/FreeRTOS-Kernel
# If the current repository (cvw) isn't on branch main, checkout branch main

# 2. Build
cd freertos_wally
make

# 3. Run on your stripped config
wsim --sim verilator your_config --elf freertos_wally

# 4. Watch UART output
tail -f ~/Documents/amoeba/cvw/sim/verilator/logs/none_uart.out
```

## What it tests

- M-mode trap handler (FreeRTOS port layer uses mtvec)
- CLINT timer interrupt (mtimecmp drives FreeRTOS tick)
- Context switching between tasks
- UART output via printf (reuses Wally syscalls.c)
- Basic heap allocation (heap_4)

## ISA flags

Compiled with `-march=rv64imac -mabi=lp64` matching your stripped config.
`_zbkb` is omitted here because the compiler multilib doesn't include it —
the extension is still present in the RTL and will be exercised by the kernel
if any zbkb instructions appear from inlining, but we don't force it.
