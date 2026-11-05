SHELL=/bin/bash -o pipefail
.SHELLFLAGS += -e

# forte_link_pkg.sv lives in hdl/ but is a PACKAGE, so it has to be analysed
# before every module that imports it.  It therefore stays in PKG_SRCS (read
# first) and is filtered OUT of the hdl glob, or it would be read twice and
# collide with itself.  Leaving it to the glob alone is what broke lint and
# synth: `sort` puts forte_link_pkg.sv after forte_chip, forte_link_core and
# forte_link_phy, every one of which imports it.
LINK_PKG       := $(CURDIR)/../hdl/forte_link_pkg.sv
export PKG_SRCS = $(CURDIR)/../pkg/types.sv
# Not $(abspath): the first make on the EWS PATH is 3.80, which lacks it and
# would leave REPO_ROOT empty.
export REPO_ROOT = $(shell cd $(CURDIR)/.. && pwd)
# The core is hdl/core ONLY.  hdl/cvw is the unmodified upstream tree it was
# forked from and defines every one of the same module names, so globbing all
# of hdl/ analyses each module twice and synthesizes whichever copy `find`
# happened to list last.  Same explicit list as lint/Makefile; the cvw package
# goes first because every core module imports it.
CORE_PKG       := $(CURDIR)/../hdl/core/cvw.sv
CORE_SRCS      := $(filter-out $(CORE_PKG),$(sort $(shell find $(CURDIR)/../hdl/core -name '*.sv')))
TOP_SRCS       := $(filter-out $(LINK_PKG),$(sort $(wildcard $(CURDIR)/../hdl/*.sv)))
export HDL_SRCS = $(CORE_PKG) $(CORE_SRCS) $(TOP_SRCS)
export SRAM_LIB = $(shell find $(CURDIR)/../sram/output/ -name "*.db")
# Overridable so `make synth DESIGN_TOP=forte_top` synthesizes the ASIC top.
export DESIGN_TOP ?= rv64_core_wrapper

# Vendored OpenTitan primitives for the link CDC (third_party/opentitan).
# prim_assert.sv is a macro header included by prim_fifo_async, so it goes on
# synthesis.tcl's search_path rather than into the source list.
PRIM_SRCS      := $(CURDIR)/../third_party/opentitan/prim_flop_2sync.sv \
                  $(CURDIR)/../third_party/opentitan/prim_fifo_async.sv
export HDL_SRCS := $(HDL_SRCS) $(PRIM_SRCS)
export PKG_SRCS := $(PKG_SRCS) $(LINK_PKG)

export STD_CELL_LIB=$(FREEPDK45)/stdcells.db
export STD_CELL_ALIB=$(FREEPDK45)/alib

export SNPSLMD_QUEUE=true

.PHONY: synth
synth: clean
	$(MAKE) outputs/synth.ddc

outputs/synth.ddc:
	mkdir -p reports outputs
	python3 $(CURDIR)/../bin/get_options.py clock
	python3 $(CURDIR)/../bin/get_options.py min_power
	python3 $(CURDIR)/../bin/get_options.py synth_cmd
	python3 $(CURDIR)/../bin/get_options.py synth_cmd_inc
	python3 $(CURDIR)/../bin/get_options.py synth_inc_iter
	export ECE411_CLOCK_PERIOD_PS=$(shell python3 $(CURDIR)/../bin/get_options.py clock) ;\
	export ECE411_MIN_POWER=$(shell python3 $(CURDIR)/../bin/get_options.py min_power) ;\
	export ECE411_COMPILE_CMD="$(shell python3 $(CURDIR)/../bin/get_options.py synth_cmd)" ;\
	export ECE411_COMPILE_CMD_INC="$(shell python3 $(CURDIR)/../bin/get_options.py synth_cmd_inc)" ;\
	export ECE411_COMPILE_ITER="$(shell python3 $(CURDIR)/../bin/get_options.py synth_inc_iter)" ;\
	export ECE411_DC_CORES=4 ;\
	dc_shell -f synthesis.tcl |& tee reports/synthesis.log
	rm -f  *.log
	rm -f  default.svf
	rm -rf work
	bash check_synth_error.sh

../sim/vcs/dump.fsdb.saif: ../sim/vcs/dump.fsdb
	cd ../sim/vcs && fsdb2saif -licqueue dump.fsdb -bt $(shell head -n1 ../sim/vcs/time.txt)ps -et $(shell tail -n1 ../sim/vcs/time.txt)ps -s top_tb/dut

../sim/verilator/dump.fst.saif: ../sim/verilator/dump.fst
	rm -f ../sim/verilator/dump.vcd
	cd ../sim/verilator && vcd2saif -pipe 'fst2vcd -f dump.fst | sed -E "s/logic/reg/g;s/int/reg/g" > dump.vcd' -input dump.vcd -output dump.fst.saif -time $(shell head -n1 ../sim/verilator/time.txt) $(shell tail -n1 ../sim/verilator/time.txt) -instance vtop/top_tb/dut

.PHONY: power_vcs
power_vcs: outputs/synth.ddc ../sim/vcs/dump.fsdb.saif
	mkdir -p reports outputs
	export ECE411_SAIF_FILE=../sim/vcs/dump.fsdb.saif ;\
	export ECE411_SAIF_TOP=top_tb/dut ;\
	export ECE411_POWER_RPT_PATH=./reports ;\
	dc_shell -f power.tcl |& tee reports/power.log

.PHONY: power_verilator
power_verilator: outputs/synth.ddc ../sim/verilator/dump.fst.saif
	mkdir -p reports outputs
	export ECE411_SAIF_FILE=../sim/verilator/dump.fst.saif ;\
	export ECE411_SAIF_TOP=vtop/top_tb/dut ;\
	export ECE411_POWER_RPT_PATH=./reports ;\
	dc_shell -f power.tcl |& tee reports/power.log

# ---- calibrated 65 nm timing flow (timing/README.md) -------------------------
# Synthesizes TIMING_TOP with FreePDK45 standing in for TSMC 65GP and reports
# every area of the design against the 400 MHz target.  Independent of `synth`:
# it has its own script, constraints and output directories under timing/.
#   make timing                    full run; summary in timing/reports/summary.rpt
#   make timing_elab               elaborate and link only (minutes, not hours)
#   make timing_report             re-report the last full run without recompiling
#   make timing TARGET_FO4_PS=45   any knob in timing/tech.cfg can be overridden
export TIMING_TOP ?= forte_top
TIMING_DIR := $(CURDIR)/timing
# lc_shell bundles older copies of these two libraries and will not start on
# the RHEL 9 EWS hosts unless the system ones are loaded ahead of them.
LC_SHELL   ?= env LD_PRELOAD="$(wildcard /lib64/libk5crypto.so.3 /lib64/libtinfo.so.5)" lc_shell

.PHONY: timing timing_elab timing_report
timing:        TIMING_MODE = full
timing_elab:   TIMING_MODE = elab
timing_report: TIMING_MODE = report
timing timing_elab timing_report:
	mkdir -p $(TIMING_DIR)/reports $(TIMING_DIR)/work
	cd $(TIMING_DIR) && dc_shell -f fo4.tcl |& tee reports/fo4.log
	cd $(TIMING_DIR) && python3 gen_blackbox_libs.py tech.cfg $$(cat reports/fo4.txt) work/forte_blackbox.lib
	cd $(TIMING_DIR) && $(LC_SHELL) -x 'read_lib work/forte_blackbox.lib; write_lib forte_blackbox -format db -output work/forte_blackbox.db; exit' |& tee reports/lc.log
	cd $(TIMING_DIR) && export ECE411_DC_CORES=4 TIMING_MODE=$(TIMING_MODE) ;\
	dc_shell -f run_timing.tcl |& tee reports/run_timing_$(TIMING_MODE).log
	rm -f $(TIMING_DIR)/*.log $(TIMING_DIR)/default.svf $(TIMING_DIR)/lc_output.txt $(TIMING_DIR)/moduleparamid

.PHONY: dv
dv:
	timeout $(ECE411_GUI_TIMEOUT) design_vision -f dv.tcl

.PHONY: clean
clean:
	rm -f  *.log
	rm -f  default.svf
	rm -rf work
	rm -rf reports
	rm -rf outputs
