# FreeRTOS on Wally - Makefile
#
# Mirrors the pattern of examples/C/hello/Makefile exactly:
#   - uses examples/C/common/{crt.S, syscalls.c, test.ld}
#   - produces TARGET, TARGET.objdump, TARGET.memfile
#   - run via: wsim --sim verilator <config> --elf freertos_wally
#
# Requires FreeRTOS-Kernel cloned at $(FREERTOS_KERNEL_DIR)

TARGET = freertos_wally

# ---- Paths ----
# Adjust WALLY to point at your cvw root if not set in environment
WALLY           ?= $(HOME)/Documents/amoeba/cvw
COMMON          := $(WALLY)/examples/C/common
FREERTOS_KERNEL_DIR ?= $(HOME)/FreeRTOS-Kernel

# FreeRTOS RISC-V port - GCC/RISC-V port supports RV32 and RV64
FREERTOS_PORT   := $(FREERTOS_KERNEL_DIR)/portable/GCC/RISC-V

# ---- Toolchain ----
CC      := riscv64-unknown-elf-gcc
OBJDUMP := riscv64-unknown-elf-objdump

# ---- Flags ----
# rv64imac matches your stripped config (no FPU -> lp64 not lp64d)
# _zbkb omitted: not in compiler multilib; RTL still has it
# MARCH   := rv64imac_zicsr
MABI    := lp64
MARCH_CC  := rv64imac_zicsr        # what GCC uses for multilib selection
MARCH_AS  := rv64imac_zicsr  # what the assembler needs to accept CSR instructions

CFLAGS  := -march=$(MARCH_CC) -mabi=$(MABI) -mcmodel=medany \
           -O2 -gdwarf-2 \
           -nostdlib -static \
           -fno-tree-loop-distribute-patterns \
           -ffunction-sections -fdata-sections \
           -Wa,-march=$(MARCH_AS)
# CFLAGS  := -march=$(MARCH) -mabi=$(MABI) -mcmodel=medany \
           -O2 -gdwarf-2 \
           -nostdlib -static \
           -fno-tree-loop-distribute-patterns \
           -ffunction-sections -fdata-sections

# Include paths
INC     := -I. \
           -I$(COMMON) \
           -I$(FREERTOS_KERNEL_DIR)/include \
           -I$(FREERTOS_PORT) \
           -I$(FREERTOS_PORT)/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions

# LDFLAGS := -T$(COMMON)/test.ld -Wl,--gc-sections
LDFLAGS := -Tfreertos_wally.ld -Wl,--gc-sections
LDLIBS  :=


# ---- Sources ----
# Wally common BSP (unchanged - same as hello example)
# BSP_SRCS := $(COMMON)/crt.S \
#             $(COMMON)/syscalls.c

BSP_SRCS := freertos_crt.S \
            $(COMMON)/syscalls.c

# FreeRTOS kernel
FREERTOS_SRCS := \
    $(FREERTOS_KERNEL_DIR)/tasks.c \
    $(FREERTOS_KERNEL_DIR)/queue.c \
    $(FREERTOS_KERNEL_DIR)/list.c \
    $(FREERTOS_KERNEL_DIR)/timers.c \
    $(FREERTOS_KERNEL_DIR)/event_groups.c \
    $(FREERTOS_KERNEL_DIR)/portable/MemMang/heap_4.c \
    $(FREERTOS_PORT)/port.c \
    $(FREERTOS_PORT)/portASM.S

# Application
APP_SRCS := main.c

ALL_SRCS := $(BSP_SRCS) $(FREERTOS_SRCS) $(APP_SRCS)

# ---- Default target ----
all: $(TARGET).memfile

# ---- Link ----
$(TARGET): $(ALL_SRCS) Makefile
	$(CC) $(CFLAGS) $(INC) $(LDFLAGS) -o $@ $(ALL_SRCS) $(LDLIBS)
	@echo "Built: $@"

# ---- Objdump (required by extractFunctionRadix.sh) ----
$(TARGET).objdump: $(TARGET)
	$(OBJDUMP) -S -D $< > $@
	@echo "Objdump: $@"

# ---- Memfile + addr/lab (matches testbench Makefile pattern) ----
$(TARGET).memfile: $(TARGET).objdump
	elf2hex $(TARGET) $(TARGET).memfile
	extractFunctionRadix.sh $(TARGET).objdump
	@echo "Memfile: $(TARGET).memfile"
	@echo "Addr:    $(TARGET).objdump.addr"
	@echo "Lab:     $(TARGET).objdump.lab"

# ---- Run ----
# Pass your config name as CONFIG=your_config (default: rv64gc for testing)
CONFIG ?= amoeba
run: $(TARGET).memfile
	wsim --sim verilator $(CONFIG) --elf $(TARGET)

# ---- Clean ----
clean:
	rm -f $(TARGET) $(TARGET).objdump $(TARGET).objdump.addr \
	      $(TARGET).objdump.lab $(TARGET).memfile

.PHONY: all run clean
