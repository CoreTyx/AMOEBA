SHELL=/bin/bash -o pipefail
.SHELLFLAGS += -e

# ---- Repo layout ----
REPO_ROOT := $(abspath ../..)
BIN_DIR   := $(REPO_ROOT)/bin
HVL_DIR   := $(REPO_ROOT)/hvl
HDL_DIR   := $(REPO_ROOT)/hdl
PKG_DIR   := $(REPO_ROOT)/pkg
SIM_DIR   := $(REPO_ROOT)/sim
CVW_DIR   := $(REPO_ROOT)/third_party/cvw

# ---- FreeRTOS kernel ----
FREERTOS_KERNEL_DIR ?= $(REPO_ROOT)/third_party/FreeRTOS-Kernel
FREERTOS_PORT       := $(FREERTOS_KERNEL_DIR)/portable/GCC/RISC-V
FREERTOS_PORT_CHIP  := $(FREERTOS_PORT)/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions

# ---- Userland workload (must define int app_main(void)) ----
PROG ?= $(abspath sorting_algo_app.c)

# ---- Toolchain ----
# The same compiler as every other test tier (bin/toolchain.mk).  Override by
# setting CROSS_COMPILE.
include $(BIN_DIR)/toolchain.mk
CC      := $(CROSS_COMPILE)gcc
OBJDUMP := $(CROSS_COMPILE)objdump

# ---- ISA: rv64imac (no FPU, matches AMOEBA amoeba config) ----
MARCH := rv64imac_zicsr
MABI  := lp64

CFLAGS := -march=$(MARCH) -mabi=$(MABI) -mcmodel=medany \
          -O2 -gdwarf-2 \
          -ffreestanding -nostdlib -static \
          -fno-tree-loop-distribute-patterns \
          -ffunction-sections -fdata-sections \
          -Wa,-march=$(MARCH)

# Add stub headers when the cross-sysroot has no bare-metal libc at its top
# level (a Linux toolchain's glibc headers are under usr/include, and are not
# meant for freestanding code)
_SYSROOT := $(shell $(CC) -print-sysroot 2>/dev/null)
ifeq ($(wildcard $(_SYSROOT)/include/stdlib.h),)
_STUB_INC := -isystem $(abspath stub_include)
endif

INC := -I$(abspath .) \
       -I$(FREERTOS_KERNEL_DIR)/include \
       -I$(FREERTOS_PORT) \
       -I$(FREERTOS_PORT_CHIP) \
       $(_STUB_INC)

LDFLAGS := -Tfreertos_wally.ld \
           -Wl,--gc-sections \
           -Wl,--build-id=none

# ---- Sources ----
BSP_SRCS := freertos_crt.S syscalls_amoeba.c

FREERTOS_SRCS := \
    $(FREERTOS_KERNEL_DIR)/tasks.c \
    $(FREERTOS_KERNEL_DIR)/queue.c \
    $(FREERTOS_KERNEL_DIR)/list.c \
    $(FREERTOS_KERNEL_DIR)/timers.c \
    $(FREERTOS_KERNEL_DIR)/event_groups.c \
    $(FREERTOS_KERNEL_DIR)/portable/MemMang/heap_4.c \
    $(FREERTOS_PORT)/port.c \
    $(FREERTOS_PORT)/portASM.S

APP_SRCS := freertos_main.c $(PROG)
ALL_SRCS := $(BSP_SRCS) $(FREERTOS_SRCS) $(APP_SRCS)

ELF := freertos_wally.elf

# ====================================================================
.PHONY: build clean

build: $(ELF) $(SIM_DIR)/bin/memory_8.lst

$(FREERTOS_KERNEL_DIR)/tasks.c:
	@echo ""
	@echo "ERROR: FreeRTOS-Kernel not found at $(FREERTOS_KERNEL_DIR)"
	@echo "       Run: git submodule update --init third_party/FreeRTOS-Kernel"
	@echo ""
	@exit 1

$(ELF): $(FREERTOS_KERNEL_DIR)/tasks.c $(ALL_SRCS) freertos_wally.ld
	$(CC) $(CFLAGS) $(INC) $(LDFLAGS) -o $@ $(ALL_SRCS)
	$(OBJDUMP) -S -D $@ > $(ELF:.elf=.dis)

$(SIM_DIR)/bin/memory_8.lst: $(ELF)
	$(MAKE) -f $(BIN_DIR)/program.mk PROG=$(abspath $<) IMAGE_DIR=$(SIM_DIR)/bin CROSS_COMPILE=$(CROSS_COMPILE)

clean:
	rm -rf $(ELF) $(ELF:.elf=.dis) dump.fst
