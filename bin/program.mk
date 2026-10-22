# Builds one test program into the memory image the testbench loads.
#
#   make -f bin/program.mk PROG=<file.c|.s|.S|.asm|.elf> [IMAGE_DIR=<dir>]
#
# A C file is linked behind bin/startup.s; an assembly file supplies its own
# _start; an ELF is taken as already built.  Everything is compiled with the
# toolchain from bin/toolchain.mk (override with CROSS_COMPILE).
#
# Writes to IMAGE_DIR (default sim/bin):
#   <name>.elf      the program (not written for an ELF input)
#   <name>.dis      its disassembly
#   spike_dpi.elf   link to the ELF, which the Spike co-simulation loads
#   memory_8.lst    $readmemh image, one 64-bit word per address
#
# The outputs are rebuilt on every run: memory_8.lst and spike_dpi.elf are
# shared by every program, so a stale one would silently run the wrong test.

SHELL       := /bin/bash
.SHELLFLAGS := -eo pipefail -c

BIN       := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
IMAGE_DIR ?= $(abspath $(BIN)/../sim/bin)

ifeq ($(strip $(PROG)),)
$(error PROG is not set: make -f bin/program.mk PROG=<file.c|.s|.S|.asm|.elf>)
endif

include $(BIN)/toolchain.mk

SRC  := $(abspath $(PROG))
NAME := $(notdir $(basename $(SRC)))
EXT  := $(suffix $(SRC))

ARCH := $(shell python3 $(BIN)/get_options.py arch)
ABI  := $(shell python3 $(BIN)/get_options.py abi)

CFLAGS := -march=$(ARCH) -mabi=$(ABI) -mcmodel=medany \
          -ffreestanding -nostartfiles -nostdlib -static -Wl,--no-relax \
          -Ofast -flto -Wall -Wextra -Wno-unused \
          -T $(BIN)/link.ld

ifeq ($(EXT),.elf)
ELF     := $(SRC)
else
ELF     := $(IMAGE_DIR)/$(NAME).elf
STARTUP := $(if $(filter .s .S .asm,$(EXT)),,$(BIN)/startup.s)
endif

LST := $(IMAGE_DIR)/memory_8.lst

# The testbench's memory returns 0 for unwritten MMIO, so a UART LSR of 0 would
# have the program poll ~130 times per character.  Seed THRE=1 (byte 5 of the
# word at 0x10000000) so every character goes out on the first poll.
UART_SEED := @$(shell printf '%08x' $$((0x10000000 >> 3)))\n0000200000000000\n

.PHONY: all
all:
	mkdir -p $(IMAGE_DIR)
	rm -f $(LST) $(IMAGE_DIR)/spike_dpi.elf $(IMAGE_DIR)/$(NAME).dis $(if $(filter-out .elf,$(EXT)),$(ELF))
ifneq ($(EXT),.elf)
	$(CROSS_COMPILE)gcc $(CFLAGS) $(STARTUP) $(SRC) -lgcc -o $(ELF)
endif
	ln -sf $(ELF) $(IMAGE_DIR)/spike_dpi.elf
	$(CROSS_COMPILE)objdump -D -Mnumeric $(ELF) > $(IMAGE_DIR)/$(NAME).dis
	$(CROSS_COMPILE)objcopy -O verilog --verilog-data-width=8 $(ELF) $(LST).tmp
	printf '$(UART_SEED)' >> $(LST).tmp
	mv $(LST).tmp $(LST)
