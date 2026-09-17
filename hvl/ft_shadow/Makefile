ROOT := ../..
BUILD := build
VERILATOR ?= verilator

# This manifest is deliberately small and independent of sim/ and hvl/.
SRCS := $(ROOT)/pkg/types.sv \
        $(ROOT)/hdl/core/cvw.sv \
        $(wildcard $(ROOT)/hdl/core/generic/*.sv) \
        $(ROOT)/hdl/core/generic/flop/flopenrc.sv \
        $(ROOT)/hdl/core/generic/flop/flopen.sv \
        $(ROOT)/hdl/core/ieu/shifter.sv \
        $(wildcard $(ROOT)/hdl/core/ieu/aes/*.sv) \
        $(wildcard $(ROOT)/hdl/core/ieu/sha/*.sv) \
        $(wildcard $(ROOT)/hdl/core/ieu/bmu/*.sv) \
        $(wildcard $(ROOT)/hdl/core/ieu/kmu/*.sv) \
        $(ROOT)/hdl/core/ieu/alu.sv \
        $(ROOT)/hdl/core/ieu/comparator.sv \
        $(ROOT)/hdl/core/mdu/mul.sv \
        $(ROOT)/hdl/core/mdu/divstep.sv \
        $(ROOT)/hdl/core/mdu/div.sv \
        $(ROOT)/hdl/core/ft_shadow/ft_fault_inject.sv \
        $(ROOT)/hdl/core/ft_shadow/ft_shadow_ctrl.sv \
        $(ROOT)/hdl/core/ft_shadow/ft_alu.sv \
        $(ROOT)/hdl/core/ft_shadow/ft_cmp.sv \
        $(ROOT)/hdl/core/ft_shadow/ft_mul.sv \
        $(ROOT)/hdl/core/ft_shadow/ft_div.sv \
        ft_recompute_fault_tb.sv

.PHONY: run clean
run: $(BUILD)/Vft_recompute_fault_tb
	./$(BUILD)/Vft_recompute_fault_tb

$(BUILD)/Vft_recompute_fault_tb: $(SRCS) Makefile
	$(VERILATOR) --binary --timing -Wall -Wno-fatal --top-module ft_recompute_fault_tb \
		+incdir+$(ROOT)/pkg +incdir+$(ROOT)/hdl/core -Mdir $(BUILD) $(SRCS)
	$(MAKE) -C $(BUILD) -f Vft_recompute_fault_tb.mk Vft_recompute_fault_tb

clean:
	$(RM) -r $(BUILD)
