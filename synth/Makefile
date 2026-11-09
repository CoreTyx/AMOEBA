include libs.mk

export REPORT_DIR			= reports

.PHONY: synth
synth: clean
	mkdir -p $(REPORT_DIR) $(SYN_OUT_DIR)
	dc_shell -64bit -f synthesis.tcl |& tee $(REPORT_DIR)/synthesis.log
	$(MAKE) smol_clean

.PHONY: dft
dft: synout/forte_top.pre_dft.ddc
	mkdir -p reports/dft synout/dft
	REPORT_DIR="$(CURDIR)/reports/dft" SYN_OUT_DIR="$(CURDIR)/synout/dft" \
		dc_shell -x 'set dft_standalone true; source dft_insert.tcl' |& tee reports/dft/dft.log

.PHONY: smol_clean
smol_clean:
	rm -f  command.log
	rm -f  default.svf
	rm -rf work

.PHONY: clean
clean: smol_clean
	rm -f  synthesis.log
	rm -rf $(REPORT_DIR)
	rm -rf $(SYN_OUT_DIR)
