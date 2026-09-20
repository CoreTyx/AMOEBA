SHELL=/bin/bash -o pipefail
.SHELLFLAGS += -e

# Packages first (analyze order matters), then the RTL.  The RTL is the same
# set simulation uses: hdl/*.sv plus the hdl/core/ working copy.  hdl/cvw/
# (pristine) and third_party/cvw/src are deliberately NOT here -- listing all
# three analyzed every CVW module three times and synthesized whichever copy
# won, which was not the one simulated.
export PKG_SRCS = $(PWD)/../pkg/types.sv $(PWD)/../hdl/core/cvw.sv $(PWD)/../pkg/amoeba_link_pkg.sv
export REPO_ROOT = $(abspath $(PWD)/..)
CORE_SRCS      := $(shell find $(PWD)/../hdl/core -name '*.sv' -o -name '*.v' 2>/dev/null | grep -v '/cvw\.sv$$' | sort)
TOP_SRCS       := $(sort $(wildcard $(PWD)/../hdl/*.sv))
export HDL_SRCS = $(TOP_SRCS) $(CORE_SRCS)
export SRAM_LIB = $(shell find $(PWD)/../sram/output/ -name "*.db")
# The ASIC top.  DESIGN_TOP=rv64_core_wrapper still synthesizes the legacy DUT.
export DESIGN_TOP ?= amoeba_top

.PHONY: lint
lint: clean
	mkdir -p reports
	sg_shell -licqueue < lint.tcl |& tee reports/lint.log
	mv spyglass-1/consolidated_reports/*_lint_lint_turbo_rtl/*.rpt reports/
	mv reports/moresimple_turbo.rpt reports/lint.rpt
	rm -rf spyglass-1 WORK *.log
	bash check_lint_error.sh

.PHONY: clean
clean:
	rm -rf spyglass-1 WORK *.log reports
