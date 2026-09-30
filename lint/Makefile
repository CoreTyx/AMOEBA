SHELL=/bin/bash -o pipefail
.SHELLFLAGS += -e

# Paths derive from this directory rather than a fixed location, so the repo can
# live anywhere. Note the Synopsys module puts GNU Make 3.80 first on PATH, which
# lacks $(abspath)/$(realpath); hence the shell-based REPO_ROOT.
export LINT_DIR   := $(CURDIR)
export REPO_ROOT  := $(shell cd $(CURDIR)/.. && pwd)

export PKG_SRCS   := $(REPO_ROOT)/pkg/types.sv
# cvw.sv holds the cvw package and must be read before any module that imports it.
CORE_PKG          := $(REPO_ROOT)/hdl/core/cvw.sv
CORE_SRCS         := $(filter-out $(CORE_PKG), $(shell find $(REPO_ROOT)/hdl/core -name '*.sv' -o -name '*.v'))
TOP_SRCS          := $(REPO_ROOT)/hdl/ahb_to_memitf.sv $(REPO_ROOT)/hdl/rv64_core_wrapper.sv
export HDL_SRCS   := $(CORE_PKG) $(sort $(CORE_SRCS)) $(TOP_SRCS)
export INCDIRS    := $(REPO_ROOT)/pkg $(REPO_ROOT)/hdl/core
export SRAM_LIB   := $(shell find $(REPO_ROOT)/sram/output/ -name "*.db" 2>/dev/null)
export DESIGN_TOP := rv64_core_wrapper
# Same ECE411_* defines the simulator derives from options.json (e.g. ECE411_NO_FLOAT).
export LINT_DEFINES := $(patsubst +define+%,%,$(shell python3 $(REPO_ROOT)/bin/get_options.py no_float))

# SpyGlass intermittently fails to create its work tree on NFS home directories,
# so it runs in a scratch directory on local disk and only the reports are kept.
LINT_TMP ?= /tmp

.PHONY: lint
lint: clean
	mkdir -p reports
	set -e; \
	wdir=$$(mktemp -d "$(LINT_TMP)/$$USER-amoeba-lint.XXXXXX"); \
	trap 'rm -rf "$$wdir"' EXIT; \
	cd "$$wdir"; \
	sg_shell -licqueue < "$(LINT_DIR)/lint.tcl" |& tee "$(LINT_DIR)/reports/lint.log"; \
	mv spyglass-1/consolidated_reports/*_lint_lint_turbo_rtl/*.rpt "$(LINT_DIR)/reports/"
	mv reports/moresimple_turbo.rpt reports/lint.rpt
	bash check_lint_error.sh

.PHONY: clean
clean:
	rm -rf spyglass-1 WORK *.log reports
