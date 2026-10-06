SHELL=/bin/bash -o pipefail
.SHELLFLAGS += -e

PKG_SRCS  := $(shell find $(CURDIR)/../pkg -name '*.sv')
CORE_SV   := $(CURDIR)/../hdl/core/cvw.sv
# cvw.sv listed explicitly first in VER/VCS_SRCS (package must precede modules); exclude from CORE_SRCS.
CORE_SRCS := $(filter-out $(CORE_SV), $(shell find $(CURDIR)/../hdl/core -name '*.sv' -o -name '*.v' 2>/dev/null))
# Exclude hdl/cvw/ and hdl/core/ from generic hdl find; CORE_SV + CORE_SRCS handle hdl/core/.
HDL_SRCS  := $(filter-out $(CURDIR)/../hdl/cvw/% $(CURDIR)/../hdl/core/%, $(shell find $(CURDIR)/../hdl -name '*.sv')) $(CORE_SRCS)
COMM_HVL  := $(shell find $(CURDIR)/../hvl/common                -name '*.sv' -o -name '*.v' -o -name '*.o' -o -name '*.so')
VCS_HVL   := $(COMM_HVL) $(shell find $(CURDIR)/../hvl/vcs       -name '*.sv' -o -name '*.v' -o -name '*.o' -o -name '*.so')
VER_HVL   := $(COMM_HVL) $(shell find $(CURDIR)/../hvl/verilator -name '*.sv' -o -name '*.v' -o -name '*.o' -o -name '*.so' -o -name '*.cpp')
SRAM_SRCS := $(shell find $(CURDIR)/../sram/output -name '*.v')
# Vendored OpenTitan primitives for the link's clock-domain crossing
# (third_party/opentitan/README.md).  prim_assert.sv is a macro header, included
# by prim_fifo_async rather than compiled, so it is an incdir and not a source.
PRIM_SRCS := $(CURDIR)/../third_party/opentitan/prim_flop_2sync.sv $(CURDIR)/../third_party/opentitan/prim_fifo_async.sv
PRIM_INC  := +incdir+$(CURDIR)/../third_party/opentitan
HDRS      := $(shell find $(CURDIR)/../hvl -name '*.svh') $(CURDIR)/../hvl/common/rvfi_reference.json
DW_IP     := $(shell python3 $(CURDIR)/../bin/get_options.py dw_ip)
VCS_SRCS  := $(PKG_SRCS) $(CORE_SV) $(HDL_SRCS) $(PRIM_SRCS) $(VCS_HVL) $(SRAM_SRCS) $(DW_IP)
VER_SRCS  := $(PKG_SRCS) $(CORE_SV) $(HDL_SRCS) $(PRIM_SRCS) $(VER_HVL) $(SRAM_SRCS) $(DW_IP)

# ── Waveform tracing for the baremetal / ISA / FreeRTOS tiers ─────────────────
# Off by default.  Verilator's trace hooks cost roughly 50x in wall time -- the
# ISA regression drops from hours to minutes without them -- and every one of
# these tests reports pass/fail through tohost, so a waveform is only wanted once
# something has already failed.
#
# Turn it back on per-invocation; the traced binaries build into their own
# directories, so both coexist and switching costs no rebuild of the other:
#
#     make run_verilator_top_tb_no_spike TRACE=1 PROG=../testcode/isa_level_testing/tc_mul_div.c
#     make regression TRACE=1
#
# Output lands in sim/verilator/<testname>/dump.fst as before.
TRACE ?= 0
ifeq ($(TRACE),1)
  TRACE_VFLAGS     := --trace-fst --trace-structs
  TRACE_DEF        :=
  TRACE_CFLAGS     :=
  BUILD_DIR        := build_trace
  NO_SPIKE_DIR     := build_no_spike_trace
else
  TRACE_VFLAGS     :=
  TRACE_DEF        := +define+ECE411_NO_TRACE
  TRACE_CFLAGS     := -DECE411_NO_TRACE
  BUILD_DIR        := build
  NO_SPIKE_DIR     := build_no_spike
endif

# ── AMOEBA random-instruction-insertion traces ────────────────────────────────
# ECE411_DUMMY_TRACE is ON by default, including in CI.  dummygen and dummymask
# only print when the divider is enabled (Enabled = |rand_instr_insert_freq), so
# every test that does not write CSR 0x7c1 produces no output at all and CI logs
# stay exactly as quiet as before.  Only tc_rand_instr_insert and tc_insert_trace
# enable it, and those are the tests whose logs we want.
#   [dummy] <time> cycle <n>  CAPTURE/INJECT ...   (hdl/core/ieu/dummygen.sv)
#   [dmask] <time>  rs1/rs2 <raw> -> <masked>      (hdl/core/ieu/dummymask.sv)
# Turn it off with DUMMY_TRACE=0; as with EXTRA_DEFINES that does not invalidate
# an existing build directory, so touch this Makefile when switching.
DUMMY_TRACE ?= 1
ifeq ($(DUMMY_TRACE),1)
  DUMMY_TRACE_DEF  := +define+ECE411_DUMMY_TRACE
else
  DUMMY_TRACE_DEF  :=
endif

# ECE411_RETIRE_TRACE is OPT-IN and must stay that way.  Unlike the two above it
# prints one line for every retired instruction whether or not insertion is
# enabled (hvl/common/top_tb.svh), which on a FreeRTOS or Linux run is millions
# of lines.  Enabling it switches build directory so it can never be served from
# -- or poison -- the default cached build that CI restores.
#
#     make run_verilator_top_tb_no_spike RETIRE_TRACE=1 \
#          PROG=../testcode/isa_level_testing/tc_insert_trace.c
RETIRE_TRACE ?= 0
ifeq ($(RETIRE_TRACE),1)
  RETIRE_TRACE_DEF := +define+ECE411_RETIRE_TRACE
  RETIRE_SUFFIX    := _retire
else
  RETIRE_TRACE_DEF :=
  RETIRE_SUFFIX    :=
endif
BUILD_DIR    := $(BUILD_DIR)$(RETIRE_SUFFIX)
NO_SPIKE_DIR := $(NO_SPIKE_DIR)$(RETIRE_SUFFIX)

TIMEOUT      ?= 10000000
PROG_NAME ?= $(notdir $(basename $(PROG)))

ECE411_NO_FLOAT = $(shell python3 $(CURDIR)/../bin/get_options.py no_float)
# The compiler needs the Verilog define above; rvfi_reference.py instead
# expects the literal token "no_float" when the F extension is absent.
RVFI_NO_FLOAT    = $(if $(strip $(ECE411_NO_FLOAT)),no_float,)

export VCS_ARCH_OVERRIDE=linux

# DUT selects the device under test.  legacy is rv64_core_wrapper
# (wallypipelinedsoc + ahb_to_memitf, the CI reference); forte is the ASIC
# top behind hvl/common/forte_dut_wrap.sv, talking to memory over the
# 16-bit link through forte_link_model.  Same testbench, same checkers.
#
#     make run_isa_level DUT=forte PROG=...
#     make linux_boot    DUT=forte
#
# Run-time link knobs (forte only): +LINK_GAPS=1 withholds ready/rvalid at
# random, +LINK_SEED=<n> picks the pattern.  Pass via LINK_ARGS.
DUT ?= legacy
ifeq ($(DUT),legacy)
  DUT_DEF :=
  DUT_TAG :=
else ifeq ($(DUT),forte)
  DUT_DEF := +define+ECE411_DUT_FORTE
  DUT_TAG := _forte
else
  $(error DUT=$(DUT) is not known -- use legacy or forte)
endif
LINK_ARGS ?=

BUILD_DIR    := $(BUILD_DIR)$(DUT_TAG)
NO_SPIKE_DIR := $(NO_SPIKE_DIR)$(DUT_TAG)

export VCS_ARCH_OVERRIDE=linux

# Standalone --binary unit testbenches (ft_shadow_test, ecc_secded_dected_test,
# csr_harden_test).  Like the SoC builds they need the repo's FindBin.pm, and
# --binary pulls in Verilator's coroutine-based timing runtime, which GCC 10/11
# only compile with -fcoroutines.  The flag is probed so other compilers are unaffected.
UNIT_TB_CFLAGS    := $(shell echo | $(CXX) -std=c++20 -fcoroutines -x c++ -E - >/dev/null 2>&1 && echo -CFLAGS -fcoroutines)
UNIT_TB_VERILATOR  = PERL5LIB="$(CURDIR)/perl5:$${PERL5LIB}" verilator $(UNIT_TB_CFLAGS)
CVW_INCDIRS  = +incdir+$(CURDIR)/../hdl/core +incdir+$(CURDIR)/../pkg +incdir+$(CURDIR)/../third_party/cvw/config/rv64gc
# Extra +define+... passed on the command line, e.g.
#   make build_isa_tests EXTRA_DEFINES=+define+ECE411_SOME_FLAG
# (ECE411_DUMMY_TRACE and ECE411_RETIRE_TRACE have their own switches above.)
# Changing this does not invalidate an existing build directory; run the matching
# clean (or touch this Makefile) to force a recompile.
EXTRA_DEFINES ?=
COMMON_FLAGS = +incdir+$(CURDIR)/../hvl/common $(CVW_INCDIRS) $(PRIM_INC) $(ECE411_NO_FLOAT) +define+DW_SUPPRESS_WARN +incdir+$(DW)/sim_ver $(DUMMY_TRACE_DEF) $(RETIRE_TRACE_DEF) $(EXTRA_DEFINES)
VCS_FLAGS    = $(COMMON_FLAGS) +incdir+$(CURDIR)/../hvl/vcs -licqueue -full64 -lca -sverilog -timescale=1ps/1ps -debug_acc+all -kdb -suppress=LCA_FEATURES_ENABLED -msg_config=vcs_warn_gen.config -xprop=../xprop.config -xprop=flowctrl -assert svaext
VER_FLAGS    = $(COMMON_FLAGS) $(DUT_DEF) +incdir+$(CURDIR)/../hvl/verilator $(TRACE_DEF) -Wall --timescale 1ps/1ps -Mdir $(BUILD_DIR) -O3 --output-split 20000 --output-split-cfuncs 200 -CFLAGS "-O3 -flto -DNDEBUG $(TRACE_CFLAGS)" -LDFLAGS "-flto" --x-assign fast --x-initial fast $(TRACE_VFLAGS) --cc --exe ../verilator_warn.vlt +define+ECE411_VERILATOR --threads $(shell nproc)
NO_SPIKE_VER_FLAGS = $(COMMON_FLAGS) $(DUT_DEF) +define+ECE411_NO_SPIKE_DPI +define+ECE411_NO_SPIKE_PRINTER $(TRACE_DEF) +incdir+$(CURDIR)/../hvl/verilator -Wall --timescale 1ps/1ps -Mdir $(NO_SPIKE_DIR) -O3 --output-split 20000 --output-split-cfuncs 200 -CFLAGS "-O3 -flto -DNDEBUG $(TRACE_CFLAGS)" -LDFLAGS "-flto" --x-assign fast --x-initial fast $(TRACE_VFLAGS) --cc --exe ../verilator_warn.vlt +define+ECE411_VERILATOR --threads $(shell nproc)
ECC_INJECT_DIR       := build_ecc_inject$(RETIRE_SUFFIX)
ECC_INJECT_VER_FLAGS = $(COMMON_FLAGS) +define+ECE411_NO_SPIKE_DPI +define+ECE411_NO_SPIKE_PRINTER +define+ECE411_SIM_INJECT $(TRACE_DEF) +incdir+$(CURDIR)/../hvl/verilator -Wall --timescale 1ps/1ps -Mdir $(ECC_INJECT_DIR) -O3 --output-split 20000 --output-split-cfuncs 200 -CFLAGS "-O3 -flto -DNDEBUG $(TRACE_CFLAGS)" -LDFLAGS "-flto" --x-assign fast --x-initial fast $(TRACE_VFLAGS) --cc --exe ../verilator_warn.vlt +define+ECE411_VERILATOR --threads $(shell nproc)
LINUX_ECC_INJECT_DIR := build_linux_ecc_inject
# Same flags as the Linux boot simulator but ECE411_SIM_INJECT enables the shared
# fault_inject input for ECC and FT LFSR injection. Waveforms and Spike co-sim are
# compiled out; RVFI is suppressed for the same reason as the plain Linux boot.
LINUX_ECC_INJECT_VER_FLAGS = $(COMMON_FLAGS) +define+ECE411_NO_SPIKE_DPI +define+ECE411_NO_SPIKE_PRINTER \
	+define+ECE411_LINUX +define+ECE411_NO_TRACE +define+ECE411_NO_RVFI +define+ECE411_SIM_INJECT \
	+incdir+$(CURDIR)/../hvl/verilator \
	-Wall --timescale 1ps/1ps -Mdir $(LINUX_ECC_INJECT_DIR) -O3 --output-split 20000 --output-split-cfuncs 200 \
	-CFLAGS "-O3 -flto -DNDEBUG -DECE411_NO_TRACE" -LDFLAGS "-flto" --x-assign fast --x-initial fast \
	--cc --exe ../verilator_warn.vlt +define+ECE411_VERILATOR --threads 1

# ── No-Spike simulator (shared by ISA-level tests and FreeRTOS tests) ──────────
verilator/$(NO_SPIKE_DIR)/Vtop_tb: $(VER_SRCS) $(HDRS) $(CURDIR)/Makefile
	mkdir -p verilator/$(NO_SPIKE_DIR)
	python3 check_sus.py
	python3 ../bin/rvfi_reference.py 1 $(RVFI_NO_FLOAT)
	cd verilator ;\
	PERL5LIB="$(CURDIR)/perl5:$${PERL5LIB}" verilator $(NO_SPIKE_VER_FLAGS) $(VER_SRCS) --top-module top_tb |& tee $(NO_SPIKE_DIR)/compile.log
	cd verilator/$(NO_SPIKE_DIR) ;\
	$(MAKE) --jobs=$(shell echo $(shell nproc)-2 | bc) -f Vtop_tb.mk |& tee -a compile.log

.PHONY: run_verilator_top_tb_no_spike
run_verilator_top_tb_no_spike: verilator/$(NO_SPIKE_DIR)/Vtop_tb $(PROG)
	mkdir -p verilator/$(PROG_NAME)
	find ./verilator -maxdepth 1 -type f -delete
	python3 ../bin/generate_memory_file.py -8 $(PROG)
	python3 $(CURDIR)/../bin/get_options.py clock
	python3 $(CURDIR)/../bin/get_options.py bmem_x
	cd verilator && ./$(NO_SPIKE_DIR)/Vtop_tb \
		+TIMEOUT_ECE411=$(TIMEOUT) $(LINK_ARGS) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py clock) \
		+BRAM_0_ON_X_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py bmem_x) \
		+MEMLST_ECE411="$(CURDIR)/bin/memory_8.lst" \
		|& tee $(PROG_NAME)/simulation.log
	-cp verilator/dump.fst verilator/$(PROG_NAME)/dump.fst 2>/dev/null

# Convenience aliases — both ISA tests and FreeRTOS tests use the no-spike simulator
.PHONY: run_isa_level
run_isa_level: verilator/$(NO_SPIKE_DIR)/Vtop_tb $(PROG)
	$(MAKE) run_verilator_top_tb_no_spike PROG=$(PROG)

.PHONY: run_verilator_top_tb_freertos
run_verilator_top_tb_freertos: verilator/$(NO_SPIKE_DIR)/Vtop_tb $(PROG)
	$(MAKE) run_verilator_top_tb_no_spike PROG=$(PROG)

.PHONY: build_isa_tests
build_isa_tests: verilator/$(NO_SPIKE_DIR)/Vtop_tb
	@echo "ISA/FreeRTOS simulator built (ECE411_NO_SPIKE_DPI)"

.PHONY: build_freertos
build_freertos: verilator/$(NO_SPIKE_DIR)/Vtop_tb
	@echo "FreeRTOS simulator built (ECE411_NO_SPIKE_DPI)"

# ── ECC inject simulator (ECE411_SIM_INJECT enables inject_en=1 in testbench) ──
verilator/$(ECC_INJECT_DIR)/Vtop_tb: $(VER_SRCS) $(HDRS) $(CURDIR)/Makefile
	mkdir -p verilator/$(ECC_INJECT_DIR)
	python3 check_sus.py
	python3 ../bin/rvfi_reference.py 1 $(RVFI_NO_FLOAT)
	cd verilator ;\
	PERL5LIB="$(CURDIR)/perl5:$${PERL5LIB}" verilator $(ECC_INJECT_VER_FLAGS) $(VER_SRCS) --top-module top_tb |& tee $(ECC_INJECT_DIR)/compile.log
	cd verilator/$(ECC_INJECT_DIR) ;\
	$(MAKE) --jobs=$(shell echo $(shell nproc)-2 | bc) -f Vtop_tb.mk |& tee -a compile.log

.PHONY: run_ecc_inject
run_ecc_inject: verilator/$(ECC_INJECT_DIR)/Vtop_tb $(PROG)
	mkdir -p verilator/$(PROG_NAME)
	find ./verilator -maxdepth 1 -type f -delete
	python3 ../bin/generate_memory_file.py -8 $(PROG)
	python3 $(CURDIR)/../bin/get_options.py clock
	python3 $(CURDIR)/../bin/get_options.py bmem_x
	cd verilator && ./$(ECC_INJECT_DIR)/Vtop_tb \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py clock) \
		+BRAM_0_ON_X_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py bmem_x) \
		+MEMLST_ECE411="$(CURDIR)/bin/memory_8.lst" \
		|& tee $(PROG_NAME)/simulation.log
	-cp verilator/dump.fst verilator/$(PROG_NAME)/dump.fst 2>/dev/null

# ── Linux boot simulator (no waveforms, no co-simulation) ──────────────────────
# Waveform tracing is compiled out rather than merely disabled: +NO_DUMP_ALL only
# suppresses the C++ tracer, while the SV-side $dumpvars keeps writing regardless.
# Measured on a 20-core host at 5M cycles -- 2.2 kHz traced vs 116 kHz here, and a
# boot-length trace would run to hundreds of GB.  --threads 1 is deliberate: on a
# single-hart in-order core, 4 threads measured 11% SLOWER at 4x the CPU.
# ECE411_LINUX additionally narrows halt detection (Linux and OpenSBI both run
# through `j .` park loops) and makes untouched DRAM read as zero instead of 'x.
# RVFI shadow checker for the Linux tier.  Default OFF, which is a real loss of
# coverage and deliberate -- see testcode/linux/README.md.  The generated
# riscv-formal monitor hardcodes "a misaligned data access traps", but CVW sets
# ZICCLSM_SUPPORTED and handles misaligned accesses in hardware, so a Linux boot
# trips a false trap mismatch.  LINUX_RVFI=1 builds with the checker into a
# separate directory so both binaries can coexist.
LINUX_RVFI ?= 0
ifeq ($(LINUX_RVFI),1)
  LINUX_BUILD_DIR := build_linux_rvfi
  LINUX_RVFI_DEF  :=
else
  LINUX_BUILD_DIR := build_linux
  LINUX_RVFI_DEF  := +define+ECE411_NO_RVFI
endif
# CONFIG applies to the Linux simulator too, into its own -Mdir.  Note for
# CONFIG=baremetal_linux: that config sets ZICCLSM_SUPPORTED = 0, so misaligned
# accesses trap exactly as the generated monitor assumes, and LINUX_RVFI=1 is
# expected to work there without the false mismatch that forces it off on the
# main config.
LINUX_BUILD_DIR := $(LINUX_BUILD_DIR)$(DUT_TAG)

LINUX_VER_FLAGS = $(COMMON_FLAGS) $(DUT_DEF) +define+ECE411_NO_SPIKE_DPI +define+ECE411_NO_SPIKE_PRINTER \
	+define+ECE411_LINUX +define+ECE411_NO_TRACE $(LINUX_RVFI_DEF) +incdir+$(CURDIR)/../hvl/verilator \
	-Wall --timescale 1ps/1ps -Mdir $(LINUX_BUILD_DIR) -O3 --output-split 20000 --output-split-cfuncs 200 \
	-CFLAGS "-O3 -flto -DNDEBUG -DECE411_NO_TRACE" -LDFLAGS "-flto" --x-assign fast --x-initial fast \
	--cc --exe ../verilator_warn.vlt +define+ECE411_VERILATOR --threads 1

# Depends on this Makefile too: LINUX_RVFI changes the compiled defines, and
# without it make would leave a stale binary in place and silently ignore the
# flag change.
verilator/$(LINUX_BUILD_DIR)/Vtop_tb: $(VER_SRCS) $(HDRS) $(CURDIR)/Makefile
	mkdir -p verilator/$(LINUX_BUILD_DIR)
	python3 check_sus.py
	python3 ../bin/rvfi_reference.py 1 $(RVFI_NO_FLOAT)
	cd verilator ;\
	PERL5LIB="$(CURDIR)/perl5:$${PERL5LIB}" verilator $(LINUX_VER_FLAGS) $(VER_SRCS) --top-module top_tb |& tee $(LINUX_BUILD_DIR)/compile.log
	cd verilator/$(LINUX_BUILD_DIR) ;\
	$(MAKE) --jobs=$(shell echo $(shell nproc)-2 | bc) -f Vtop_tb.mk |& tee -a compile.log

.PHONY: build_linux
build_linux: verilator/$(LINUX_BUILD_DIR)/Vtop_tb
	@echo "Linux boot simulator built (ECE411_LINUX, waveforms compiled out)"

# ── Linux boot run ────────────────────────────────────────────────────────────
# LINUX_PASS selects the milestone: override it to stop at an earlier point in
# the boot, e.g. LINUX_PASS='Linux version 6.6' for a ~5M-cycle smoke test.
LINUX_DIR     ?= $(CURDIR)/../testcode/linux
# NOTE: one Linux image, built from testcode/linux's hardcoded config and dts.
# Per-CONFIG images (a soft-float build for baremetal_linux/asic) are NOT
# supported on this branch: they need per-config dts and kernel fragments that
# came with the commits dropped as redundant during the rebase onto
# Making_HDL_Synthesizable.  `linux_boot CONFIG=<pruned>` therefore boots the
# full RV64GC image, which will not match a pruned core.  Reinstating it belongs
# with whoever owns the Linux images.
LINUX_MEMLST  ?= $(LINUX_DIR)/build/boot.lst
LINUX_TIMEOUT ?= 2000000000
LINUX_PASS    ?= AMOEBA_LINUX_BOOT_OK
LINUX_FAIL    ?= Kernel panic|Unable to handle kernel|Oops:|SBI panic
LINUX_RUN_DIR ?= verilator/linux_boot

$(LINUX_MEMLST):
	$(MAKE) -C $(LINUX_DIR)

.PHONY: linux_boot
linux_boot: verilator/$(LINUX_BUILD_DIR)/Vtop_tb $(LINUX_MEMLST)
	mkdir -p $(LINUX_RUN_DIR)
	cd verilator && ./$(LINUX_BUILD_DIR)/Vtop_tb \
		+TIMEOUT_ECE411=$(LINUX_TIMEOUT) $(LINK_ARGS) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py clock) \
		+MEMLST_ECE411="$(LINUX_MEMLST)" \
		+UART_PASS_ECE411="$(LINUX_PASS)" \
		+UART_FAIL_ECE411="$(LINUX_FAIL)" \
		+UARTLOG_ECE411="$(CURDIR)/$(LINUX_RUN_DIR)/boot_uart.log" \
		|& tee $(CURDIR)/$(LINUX_RUN_DIR)/simulation.log

# ── Linux + ECC inject simulator ─────────────────────────────────────────────
# Combines the Linux boot environment (ECE411_LINUX) with LFSR error injection
# (ECE411_SIM_INJECT). Storage ECC corrects single-bit flips and the ft_*
# execution units retry transient mismatches under the same shared enable.
verilator/$(LINUX_ECC_INJECT_DIR)/Vtop_tb: $(VER_SRCS) $(HDRS) $(CURDIR)/Makefile
	mkdir -p verilator/$(LINUX_ECC_INJECT_DIR)
	python3 check_sus.py
	python3 ../bin/rvfi_reference.py 1 $(RVFI_NO_FLOAT)
	cd verilator ;\
	PERL5LIB="$(CURDIR)/perl5:$${PERL5LIB}" verilator $(LINUX_ECC_INJECT_VER_FLAGS) $(VER_SRCS) --top-module top_tb |& tee $(LINUX_ECC_INJECT_DIR)/compile.log
	cd verilator/$(LINUX_ECC_INJECT_DIR) ;\
	$(MAKE) --jobs=$(shell echo $(shell nproc)-2 | bc) -f Vtop_tb.mk |& tee -a compile.log

.PHONY: build_linux_ecc_inject
build_linux_ecc_inject: verilator/$(LINUX_ECC_INJECT_DIR)/Vtop_tb
	@echo "Linux+ECC inject simulator built (ECE411_LINUX + ECE411_SIM_INJECT, waveforms compiled out)"

LINUX_ECC_INJECT_RUN_DIR ?= verilator/linux_ecc_inject_boot

.PHONY: linux_boot_ecc_inject
linux_boot_ecc_inject: verilator/$(LINUX_ECC_INJECT_DIR)/Vtop_tb $(LINUX_MEMLST)
	mkdir -p $(LINUX_ECC_INJECT_RUN_DIR)
	cd verilator && ./$(LINUX_ECC_INJECT_DIR)/Vtop_tb \
		+TIMEOUT_ECE411=$(LINUX_TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py clock) \
		+MEMLST_ECE411="$(LINUX_MEMLST)" \
		+UART_PASS_ECE411="$(LINUX_PASS)" \
		+UART_FAIL_ECE411="$(LINUX_FAIL)" \
		+UARTLOG_ECE411="$(CURDIR)/$(LINUX_ECC_INJECT_RUN_DIR)/boot_uart.log" \
		|& tee $(CURDIR)/$(LINUX_ECC_INJECT_RUN_DIR)/simulation.log

.PHONY: freertos
freertos: verilator/$(NO_SPIKE_DIR)/Vtop_tb
	$(MAKE) -C $(CURDIR)/../testcode/freertos build
	$(MAKE) run_verilator_top_tb_no_spike PROG=$(CURDIR)/../testcode/freertos/freertos_wally.elf

# vcs_warn.config plus the generated hdl/core width-lint waiver (see that file).
# One entry per file: VCS truncates long lines in a message config file.
define vcs_msg_config
	cp vcs_warn.config $(1)/vcs_warn_gen.config
	printf '{ +lint=noCAWM-L,noWMIA-L,noULCO; +file=%s; }\n' $(CORE_SV) $(CORE_SRCS) >> $(1)/vcs_warn_gen.config
endef

vcs/top_tb: $(VCS_SRCS) $(HDRS) vcs_warn.config $(CURDIR)/Makefile
	mkdir -p vcs
	$(call vcs_msg_config,vcs)
	python3 check_sus.py
	python3 ../bin/rvfi_reference.py 1 $(RVFI_NO_FLOAT)
	cd vcs && vcs $(VCS_SRCS) $(VCS_FLAGS) -l compile.log -top top_tb -o top_tb
	bash check_compile_error.sh vcs

# No-Spike VCS build: the VCS counterpart of verilator/$(NO_SPIKE_DIR), for the
# ISA-level and FreeRTOS tests (they touch MMIO, which Spike's commit log omits).
VCS_NO_SPIKE_DIR := vcs_no_spike
$(VCS_NO_SPIKE_DIR)/top_tb: $(VCS_SRCS) $(HDRS) vcs_warn.config $(CURDIR)/Makefile
	mkdir -p $(VCS_NO_SPIKE_DIR)
	$(call vcs_msg_config,$(VCS_NO_SPIKE_DIR))
	python3 check_sus.py
	python3 ../bin/rvfi_reference.py 1 $(RVFI_NO_FLOAT)
	cd $(VCS_NO_SPIKE_DIR) && vcs $(VCS_SRCS) $(VCS_FLAGS) +define+ECE411_NO_SPIKE_DPI +define+ECE411_NO_SPIKE_PRINTER -l compile.log -top top_tb -o top_tb
	bash check_compile_error.sh $(VCS_NO_SPIKE_DIR)

.PHONY: run_vcs_top_tb
run_vcs_top_tb: vcs/top_tb $(PROG)
	mkdir -p spike
	python3 ../bin/generate_memory_file.py -8 $(PROG)
	rm -f vcs/dump.fsdb
	python3 $(CURDIR)/../bin/get_options.py clock
	python3 $(CURDIR)/../bin/get_options.py bmem_x
	cd vcs && ./top_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) $(LINK_ARGS) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py clock) \
		+BRAM_0_ON_X_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py bmem_x) \
		+MEMLST_ECE411="$(CURDIR)/bin/memory_8.lst" \
		+ELF_ECE411="$(CURDIR)/bin/spike_dpi.elf"

.PHONY: run_vcs_top_tb_no_spike
run_vcs_top_tb_no_spike: $(VCS_NO_SPIKE_DIR)/top_tb $(PROG)
	python3 ../bin/generate_memory_file.py -8 $(PROG)
	rm -f $(VCS_NO_SPIKE_DIR)/dump.fsdb
	python3 $(CURDIR)/../bin/get_options.py clock
	python3 $(CURDIR)/../bin/get_options.py bmem_x
	cd $(VCS_NO_SPIKE_DIR) && ./top_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py clock) \
		+BRAM_0_ON_X_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py bmem_x) \
		+MEMLST_ECE411="$(CURDIR)/bin/memory_8.lst"

../hvl/common/spike.so: ../hvl/common/spike_dpi.cpp
	g++ -shared -fPIC -O2 $< -o $@

# ── Spike DPI simulator (baremetal co-simulation) ───────────────────────────────
verilator/$(BUILD_DIR)/Vtop_tb: $(VER_SRCS) $(HDRS) ../hvl/common/spike.so $(CURDIR)/Makefile
	mkdir -p verilator/$(BUILD_DIR)
	python3 check_sus.py
	python3 ../bin/rvfi_reference.py 1 $(RVFI_NO_FLOAT)
	cd verilator ;\
	PERL5LIB="$(CURDIR)/perl5:$${PERL5LIB}" verilator $(VER_FLAGS) $(VER_SRCS) --top-module top_tb |& tee $(BUILD_DIR)/compile.log
	cd verilator/$(BUILD_DIR) ;\
	$(MAKE) --jobs=$(shell echo $(shell nproc)-2 | bc) -f Vtop_tb.mk |& tee -a compile.log

.PHONY: build
build: verilator/$(BUILD_DIR)/Vtop_tb

.PHONY: run_verilator_top_tb
run_verilator_top_tb: verilator/$(BUILD_DIR)/Vtop_tb $(PROG)
	mkdir -p spike verilator/$(PROG_NAME)
	find ./verilator -maxdepth 1 -type f -delete
	python3 ../bin/generate_memory_file.py -8 $(PROG)
	python3 $(CURDIR)/../bin/get_options.py clock
	python3 $(CURDIR)/../bin/get_options.py bmem_x
	cd verilator && ./$(BUILD_DIR)/Vtop_tb \
		+TIMEOUT_ECE411=$(TIMEOUT) $(LINK_ARGS) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py clock) \
		+BRAM_0_ON_X_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py bmem_x) \
		+MEMLST_ECE411="$(CURDIR)/bin/memory_8.lst" \
		+ELF_ECE411="$(CURDIR)/bin/spike_dpi.elf" \
		|& tee $(PROG_NAME)/simulation.log
	-cp verilator/dump.fst verilator/$(PROG_NAME)/dump.fst 2>/dev/null

.PHONY: covrep
covrep: vcs/top_tb.vdb
	cd vcs && urg -dir top_tb.vdb

.PHONY: verdi
verdi:
	mkdir -p verdi
	cd verdi && timeout $(ECE411_GUI_TIMEOUT) $(VERDI_HOME)/bin/verdi -ssf $(CURDIR)/vcs/dump.fsdb

.PHONY: spike
spike: $(ELF)
	mkdir -p spike
	spike --isa=$(shell python3 $(CURDIR)/../bin/get_options.py arch) -m0x80000000:0x10000000 --log-commits $(ELF) |& tail -n +6 > spike/spike.log

.PHONY: interactive_spike
interactive_spike: $(ELF)
	spike --isa=$(shell python3 $(CURDIR)/../bin/get_options.py arch) -m0x80000000:0x10000000 --log-commits -d $(ELF)

REGRESSION_TESTS  ?= $(shell find $(CURDIR)/../testcode/baremetal -name '*.c')
ISA_LEVEL_TESTS   ?= $(shell find $(CURDIR)/../testcode/isa_level_testing -name '*.c' ! -name 'test_utils.h')
# The pruned configs have no hardware counters (ZICNTR=0: rdcycle traps, and
# bare metal has no OpenSBI to emulate it) and no B/K extensions, so the two
# tests that need them cannot run there.
ifneq ($(filter $(CONFIG),asic baremetal_linux freertos freertos_keystone),)
  ISA_LEVEL_TESTS := $(filter-out %tc_branch_prediction.c %tc_zbkb_and_smc.c,$(ISA_LEVEL_TESTS))
endif
FREERTOS_TESTS    ?= $(shell find $(CURDIR)/../testcode/freertos -name 'tc_*.c')

RISCV_FORMAL_MONITOR_DIR = $(CURDIR)/../third_party/riscv-formal/monitor
RISCV_FORMAL_MONITOR     = $(RISCV_FORMAL_MONITOR_DIR)/generate.py
RVFIMON_ISA          ?= rv64imafdc_zb
# Local fixes on top of the generated monitor, applied in order.  Applied by
# generated-files and re-applied by check-generated, so regenerating cannot
# silently drop them.
RVFIMON_PATCHES      = $(CURDIR)/../patches/rvfimon-clz-ctz.patch $(CURDIR)/../patches/rvfimon-div-overflow.patch

.PHONY: generate-rtl
generate-rtl:
	bash $(CURDIR)/../bin/generate_rtl.sh

.PHONY: generated-files
generated-files:
	python3 $(CURDIR)/../bin/rvfi_reference.py 1 $(RVFI_NO_FLOAT)
	cd $(RISCV_FORMAL_MONITOR_DIR) && \
	    python3 generate.py -i $(RVFIMON_ISA) -a -r 0 -c 1 > $(CURDIR)/../hvl/common/rvfimon.v
	for p in $(RVFIMON_PATCHES); do patch -s $(CURDIR)/../hvl/common/rvfimon.v < $$p; done

.PHONY: check-generated
check-generated:
	@tmp=$$(mktemp -d); \
	python3 $(CURDIR)/../bin/rvfi_reference.py 1 $(RVFI_NO_FLOAT); \
	cd $(RISCV_FORMAL_MONITOR_DIR) && python3 generate.py -i $(RVFIMON_ISA) -a -r 0 -c 1 > $$tmp/rvfimon.v; \
	for p in $(RVFIMON_PATCHES); do \
		patch -s $$tmp/rvfimon.v < $$p || { echo "ERROR: $$p no longer applies to the generated monitor."; echo "The submodule moved; rebase or drop the patch if it is upstream now."; rm -rf $$tmp; exit 1; }; \
	done; \
	diff $(CURDIR)/../hvl/common/rvfimon.v $$tmp/rvfimon.v || (echo "ERROR: rvfimon.v is stale — run 'make generated-files'" && rm -rf $$tmp && exit 1); \
	rm -rf $$tmp; \
	echo "Generated files are up to date."

# ── Regression targets ──────────────────────────────────────────────────────────

.PHONY: baremetal_regression
baremetal_regression: verilator/$(BUILD_DIR)/Vtop_tb
	@pass=0; fail=0; total=0; \
	for test in $(REGRESSION_TESTS); do \
		total=$$((total+1)); \
		echo "=== [$$total] Running $$test ==="; \
		if $(MAKE) -s run_verilator_top_tb PROG=$$test; then \
			echo "  PASS: $$test"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$test"; fail=$$((fail+1)); \
		fi; \
	done; \
	echo ""; \
	echo "=== Baremetal Regression Summary: $$pass/$$total tests passed ==="; \
	[ $$fail -eq 0 ] || exit 1

.PHONY: isa_regression
isa_regression: verilator/$(NO_SPIKE_DIR)/Vtop_tb
	@pass=0; fail=0; total=0; \
	for test in $(ISA_LEVEL_TESTS); do \
		total=$$((total+1)); \
		echo "=== [$$total] Running $$test ==="; \
		if $(MAKE) -s run_verilator_top_tb_no_spike PROG=$$test; then \
			echo "  PASS: $$test"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$test"; fail=$$((fail+1)); \
		fi; \
	done; \
	echo ""; \
	echo "=== ISA Regression Summary: $$pass/$$total tests passed ==="; \
	[ $$fail -eq 0 ] || exit 1

.PHONY: freertos_regression
freertos_regression: verilator/$(NO_SPIKE_DIR)/Vtop_tb
	@pass=0; fail=0; total=0; \
	for test in $(FREERTOS_TESTS); do \
		total=$$((total+1)); \
		name=$$(basename $$test .c); \
		echo "=== [$$total] Running $$name ==="; \
		if rm -f $(CURDIR)/../testcode/freertos/freertos_wally.elf && \
		   $(MAKE) -C $(CURDIR)/../testcode/freertos build PROG=$$test && \
		   $(MAKE) -s run_verilator_top_tb_no_spike PROG=$(CURDIR)/../testcode/freertos/freertos_wally.elf; then \
			echo "  PASS: $$name"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$name"; fail=$$((fail+1)); \
		fi; \
	done; \
	echo ""; \
	echo "=== FreeRTOS Regression Summary: $$pass/$$total tests passed ==="; \
	[ $$fail -eq 0 ] || exit 1

# Abort torture for the link bridge: tc_link_abort must pass AND the bridge
# must have finished at least one transfer after the core abandoned it
# (forte_dut_wrap prints the count at the end of every run).  The core does
# not abort bursts on its own in bare metal (see forte_dut_wrap.sv), so the
# wrapper injects a flush into every 3rd I-fetch burst with +LINK_FORCE_ABORT.
.PHONY: link_abort
link_abort:
	[ "$(DUT)" = "forte" ] || { echo "link_abort needs DUT=forte"; exit 1; }
	$(MAKE) run_verilator_top_tb_no_spike PROG=$(CURDIR)/../testcode/isa_level_testing/tc_link_abort.c LINK_ARGS="+LINK_FORCE_ABORT=3 $(LINK_ARGS)"
	@line=$$(grep -E '^\[LINK\] transactions' verilator/tc_link_abort/simulation.log); echo "$$line"; \
	case "$$line" in *"aborted=0 "*) echo "link_abort: no aborted transfers observed -- the abort path was not exercised"; exit 1;; esac
	@grep -q 'test PASSED' verilator/tc_link_abort/simulation.log

# Two-clock CDC run (docs/impl_plan_link_clocking.md s9a).  Not part of the
# ordinary flow: it has its own Verilator build because the clocks are generated
# in SystemVerilog, which this flow's C++ harness cannot do.  hvl/cdc/run.sh.
.PHONY: cdc
cdc:
	$(CURDIR)/../hvl/cdc/run.sh $(if $(PROG),$(PROG),)

.PHONY: cdc_sweep
cdc_sweep:
	SWEEP=1 $(CURDIR)/../hvl/cdc/run.sh $(if $(PROG),$(PROG),)

.PHONY: regression
regression:
	$(MAKE) baremetal_regression
	$(MAKE) isa_regression
	$(MAKE) freertos_regression

# ── VCS regressions (EWS only): same test lists, 4-state simulation with X-prop ─
.PHONY: vcs_baremetal_regression
vcs_baremetal_regression: vcs/top_tb
	@pass=0; fail=0; total=0; \
	for test in $(REGRESSION_TESTS); do \
		total=$$((total+1)); \
		echo "=== [$$total] VCS: $$test ==="; \
		if $(MAKE) -s run_vcs_top_tb PROG=$$test > /dev/null 2>&1 && grep -q "test PASSED" vcs/simulation.log; then \
			echo "  PASS: $$test"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$test (see sim/vcs/simulation.log)"; fail=$$((fail+1)); \
			cp vcs/simulation.log vcs/$$(basename $$test .c).fail.log 2>/dev/null || true; \
		fi; \
	done; \
	echo ""; \
	echo "=== VCS Baremetal Regression Summary: $$pass/$$total tests passed ==="; \
	[ $$fail -eq 0 ] || exit 1

.PHONY: vcs_isa_regression
vcs_isa_regression: $(VCS_NO_SPIKE_DIR)/top_tb
	@pass=0; fail=0; total=0; \
	for test in $(ISA_LEVEL_TESTS); do \
		total=$$((total+1)); \
		echo "=== [$$total] VCS: $$test ==="; \
		if $(MAKE) -s run_vcs_top_tb_no_spike PROG=$$test > /dev/null 2>&1 && grep -q "test PASSED" $(VCS_NO_SPIKE_DIR)/simulation.log; then \
			echo "  PASS: $$test"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$test (see sim/$(VCS_NO_SPIKE_DIR)/simulation.log)"; fail=$$((fail+1)); \
			cp $(VCS_NO_SPIKE_DIR)/simulation.log $(VCS_NO_SPIKE_DIR)/$$(basename $$test .c).fail.log 2>/dev/null || true; \
		fi; \
	done; \
	echo ""; \
	echo "=== VCS ISA Regression Summary: $$pass/$$total tests passed ==="; \
	[ $$fail -eq 0 ] || exit 1

.PHONY: vcs_regression
vcs_regression:
	$(MAKE) vcs_baremetal_regression
	$(MAKE) vcs_isa_regression

# ── Standalone RTL unit tests ─────────────────────────────────────────────────
# Self-checking testbenches live in hvl/; their build/run entry points live here
# alongside the SoC, ECC, and ISA regression targets.
FT_THRESHOLD ?= 2
FT_TB_DIR = verilator/ft_shadow_tb_64_$(FT_THRESHOLD)
.PHONY: ft_shadow_test ft_shadow_regression
# Three standalone 64-bit module runs at mismatch thresholds 1, 2, and 3.
# These runs do not instantiate a processor or execute instructions.
ft_shadow_regression:
	@set -e; for threshold in 1 2 3; do $(MAKE) ft_shadow_test FT_THRESHOLD=$$threshold; done

ft_shadow_test:
	@test "$(FT_THRESHOLD)" -ge 1 || { echo "FT_THRESHOLD must be a positive integer" >&2; exit 1; }
	mkdir -p $(FT_TB_DIR)
	$(UNIT_TB_VERILATOR) --binary --timing -j 4 -O2 --top-module ft_recompute_fault_tb -GTHRESHOLD=$(FT_THRESHOLD) \
	    $(CURDIR)/../pkg/types.sv \
	    $(CURDIR)/../hdl/core/cvw.sv \
	    $(wildcard $(CURDIR)/../hdl/core/generic/*.sv) \
	    $(CURDIR)/../hdl/core/generic/flop/flopenrc.sv \
	    $(CURDIR)/../hdl/core/generic/flop/flopen.sv \
	    $(CURDIR)/../hdl/core/ieu/shifter.sv \
	    $(wildcard $(CURDIR)/../hdl/core/ieu/aes/*.sv) \
	    $(wildcard $(CURDIR)/../hdl/core/ieu/sha/*.sv) \
	    $(wildcard $(CURDIR)/../hdl/core/ieu/bmu/*.sv) \
	    $(wildcard $(CURDIR)/../hdl/core/ieu/kmu/*.sv) \
	    $(CURDIR)/../hdl/core/ieu/alu.sv \
	    $(CURDIR)/../hdl/core/mdu/mul.sv \
	    $(CURDIR)/../hdl/core/mdu/divstep.sv \
	    $(CURDIR)/../hdl/core/mdu/div.sv \
	    $(wildcard $(CURDIR)/../hdl/core/ft_shadow/*.sv) \
	    $(CURDIR)/../hvl/ft_shadow/ft_recompute_fault_tb.sv \
	    +incdir+$(CURDIR)/../pkg +incdir+$(CURDIR)/../hdl/core \
	    -Mdir $(FT_TB_DIR) -Wall -Wno-fatal --timescale 1ps/1ps \
	    2>&1 | tee $(FT_TB_DIR)/compile.log
	$(FT_TB_DIR)/Vft_recompute_fault_tb

.PHONY: ecc_baremetal_regression
ecc_baremetal_regression: verilator/$(ECC_INJECT_DIR)/Vtop_tb
	@pass=0; fail=0; total=0; \
	for src in $(CURDIR)/../testcode/baremetal_ecc/*.c; do \
		total=$$((total+1)); \
		name=$$(basename $$src .c); \
		echo "=== [$$total] ECC inject: $$name ==="; \
		if $(MAKE) -s run_ecc_inject PROG=$$src; then \
			echo "  PASS: $$name"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$name"; fail=$$((fail+1)); \
		fi; \
	done; \
	echo ""; \
	echo "=== ECC Baremetal Regression: $$pass/$$total tests passed ==="; \
	[ $$fail -eq 0 ] || exit 1

# ── ECC test suite (add sub-targets here as new ECC modules are added) ────────
.PHONY: ecc_test ecc_secded_dected_test csr_harden_test ecc_baremetal_regression
ecc_test: ecc_secded_dected_test csr_harden_test ecc_baremetal_regression

ecc_secded_dected_test:
	mkdir -p verilator/ecc_tb
	$(UNIT_TB_VERILATOR) --binary -O2 --top-module ecc_tb \
	    $(wildcard $(CURDIR)/../hdl/core/generic/ecc/*.sv) \
	    $(CURDIR)/../hvl/ecc/ecc_tb.sv \
	    -Mdir verilator/ecc_tb --Wall --timescale 1ps/1ps 2>&1 | tee verilator/ecc_tb/compile.log
	verilator/ecc_tb/Vecc_tb

csr_harden_test:
	mkdir -p verilator/csr_harden_tb
	$(UNIT_TB_VERILATOR) --binary --timing -O2 --top-module csr_harden_tb \
	    $(CURDIR)/../hdl/core/cvw.sv \
	    $(CURDIR)/../hdl/core/generic/flop/flopenl.sv \
	    $(CURDIR)/../hdl/core/privileged/privmode.sv \
	    $(CURDIR)/../hdl/core/privileged/csrharden.sv \
	    $(CURDIR)/../hvl/ecc/csr_harden_tb.sv \
	    -Mdir verilator/csr_harden_tb \
	    +incdir+$(CURDIR)/../hdl/core \
	    +incdir+$(CURDIR)/../pkg \
	    -Wall -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-GENUNNAMED \
	    --timescale 1ps/1ps 2>&1 | tee verilator/csr_harden_tb/compile.log
	verilator/csr_harden_tb/Vcsr_harden_tb

.PHONY: clean
clean:
	rm -rf bin vcs $(VCS_NO_SPIKE_DIR) verdi verilator spike

# Independent full-core runtime-injection/retirement/precise-trap regression.
.PHONY: ft_core_test
ft_core_test:
	mkdir -p verilator/ft_core_tb
	# Enable prediction only in this processor test to exercise predicted-taken faults.
	python3 -c 'import pathlib,re; p=pathlib.Path("../pkg/config.vh"); pathlib.Path("verilator/ft_core_tb/config.vh").write_text(re.sub(r"(localparam logic BPRED_SUPPORTED\s*=\s*)[01]", r"\g<1>1", p.read_text()))'
	$(UNIT_TB_VERILATOR) --binary --timing -j 4 -O2 --top-module ft_core_fault_tb $(CURDIR)/verilator_warn.vlt \
	    $(PKG_SRCS) $(CORE_SV) $(HDL_SRCS) $(SRAM_SRCS) \
	    $(CURDIR)/../hvl/ft_shadow/ft_core_fault_tb.sv \
	    +incdir+$(CURDIR)/verilator/ft_core_tb $(CVW_INCDIRS) +incdir+$(CURDIR)/../hvl/common $(ECE411_NO_FLOAT) \
	    -Mdir verilator/ft_core_tb -Wall --timescale 1ps/1ps \
	    2>&1 | tee verilator/ft_core_tb/compile.log
	verilator/ft_core_tb/Vft_core_fault_tb
