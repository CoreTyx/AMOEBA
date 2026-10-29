###############################################################################
# pynq-z2.xdc
#
# This design has NO PL I/O, and that is not an omission.
#
# The PS7's DDR and FIXED_IO pins are placed by the board preset, not from here.
# The PL clock is FCLK_CLK0 from inside the PS7, so it is constrained by the
# PS7's own IP-level XDC and must NOT be given a create_clock here -- doing so
# creates a second, conflicting clock on the same net.  Everything the host
# talks to goes over AXI.  That leaves nothing to place.
#
# There used to be two PMODA pins here for a serial console.  They were removed
# because the console the PS reads is the AHB snoop in amoeba_bus_mon, and a
# physical UART is redundant with it, would emit garbage without per-clock
# retuning of the guest's baud divisor (FCLK_CLK0 is 25 MHz; the drivers assume
# the simulation's 100 MHz), and tests PL scaffolding rather than anything that
# goes to the ASIC.  See the header of rtl/amoeba_pynq_top.sv.
#
# If you do bring a signal out, the PMODA mapping from the installed board file
# (.../board_files/.../pynq-z2/A.0/part0_pins.xml) is:
#
#   JA1  Y18      JA7   U18        pin 5  GND     pin 11  GND
#   JA2  Y19      JA8   U19        pin 6  VCC     pin 12  VCC
#   JA3  Y16      JA9   W18
#   JA4  Y17      JA10  W19
#
# All 3.3 V, with 200 ohm series protection resistors.  CAUTION: on the PYNQ-Z2
# these pins are physically shared with the Raspberry Pi 40-pin header -- the
# same board file lists Y18/Y19 as raspberry_pi_tri_i_2/3.  PMODB is not shared:
# JB1 = W14, JB2 = Y14.
#
# This file is still added by tcl/build.tcl, so it is the place to put timing
# exceptions or debug-core constraints when they are needed.
###############################################################################

###############################################################################
# Stage C: the link on real pins (LINK_PINS=1, docs/impl_plan_fpga_linux.md s5)
#
# Everything below is inside `if {[llength [get_ports -quiet link_a_clk]]}`,
# so a build without AMOEBA_LINK_PINS -- which has none of these ports --
# reads this file unchanged.
#
# Side A is the chip: amoeba_top's 23 link pins on the RASPBERRY PI header.
# Side B is the FPGA end: amoeba_link_slave's 23 on the ARDUINO header.  A
# ribbon joins A<->B pin for pin.  The clock goes B -> A: aclk leaves on
# link_b_clk (an ODDR) and comes back on link_a_clk, which MUST be a
# clock-capable pin -- U18 is IO_L12P_T1_MRCC_34, the only MRCC on the RPi
# header in bank 34.  Package pins are from the installed board file
# (pynq-z2/A.0/part0_pins.xml, queried for BANK / IS_CLK_CAPABLE with
# Vivado); the header pin NUMBERS next to them are NOT in the board file and
# must be taken from the PYNQ-Z2 schematic before a ribbon is made.  Fill in
# the "hdr" column; nothing in the build depends on it.
#
# All 3.3 V (LVCMOS33).  Bank 13 and 34/35 pins are mixed on the RPi header,
# which is fine for single-ended LVCMOS33.  The RPi pins Y16/Y17 (I2C, with
# on-board pull-ups) and the Arduino I2C pins P15/P16 are deliberately not
# used.  U13 is PUDC_B: a plain I/O after configuration, Vivado notes it.
#
# Timing: the two halves are timed at the period inside themselves; the
# A<->B paths are declared asynchronous in build.tcl's generated
# link_pins.xdc, because the loop delay (ODDR clk-to-out + ribbon + IBUF +
# BUFG, ~5-8 ns) is what the IDELAY eye sweep MEASURES.  set_input_delay
# below therefore only bounds the pad-to-flop paths within a half.
###############################################################################

if {[llength [get_ports -quiet link_a_clk]]} {

    # ---- side A: the chip, on the RPi header ---------------------------- hdr
    set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports link_a_clk]      ;# MRCC   ?
    set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} [get_ports {link_a_io[0]}]  ;#        ?
    set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33} [get_ports {link_a_io[1]}]  ;#        ?
    set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} [get_ports {link_a_io[2]}]  ;#        ?
    set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33} [get_ports {link_a_io[3]}]  ;#        ?
    set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports {link_a_io[4]}]  ;#        ?
    set_property -dict {PACKAGE_PIN F19 IOSTANDARD LVCMOS33} [get_ports {link_a_io[5]}]  ;#        ?
    set_property -dict {PACKAGE_PIN V10 IOSTANDARD LVCMOS33} [get_ports {link_a_io[6]}]  ;#        ?
    set_property -dict {PACKAGE_PIN V8  IOSTANDARD LVCMOS33} [get_ports {link_a_io[7]}]  ;#        ?
    set_property -dict {PACKAGE_PIN W10 IOSTANDARD LVCMOS33} [get_ports {link_a_io[8]}]  ;#        ?
    set_property -dict {PACKAGE_PIN B20 IOSTANDARD LVCMOS33} [get_ports {link_a_io[9]}]  ;#        ?
    set_property -dict {PACKAGE_PIN W8  IOSTANDARD LVCMOS33} [get_ports {link_a_io[10]}] ;#        ?
    set_property -dict {PACKAGE_PIN V6  IOSTANDARD LVCMOS33} [get_ports {link_a_io[11]}] ;#        ?
    set_property -dict {PACKAGE_PIN Y6  IOSTANDARD LVCMOS33} [get_ports {link_a_io[12]}] ;#        ?
    set_property -dict {PACKAGE_PIN B19 IOSTANDARD LVCMOS33} [get_ports {link_a_io[13]}] ;#        ?
    set_property -dict {PACKAGE_PIN U7  IOSTANDARD LVCMOS33} [get_ports {link_a_io[14]}] ;#        ?
    set_property -dict {PACKAGE_PIN C20 IOSTANDARD LVCMOS33} [get_ports {link_a_io[15]}] ;#        ?
    set_property -dict {PACKAGE_PIN Y8  IOSTANDARD LVCMOS33} [get_ports link_a_dir]      ;#        ?
    set_property -dict {PACKAGE_PIN A20 IOSTANDARD LVCMOS33} [get_ports link_a_req]      ;#        ?
    set_property -dict {PACKAGE_PIN Y9  IOSTANDARD LVCMOS33} [get_ports link_a_wr]       ;#        ?
    set_property -dict {PACKAGE_PIN U8  IOSTANDARD LVCMOS33} [get_ports link_a_burst]    ;#        ?
    set_property -dict {PACKAGE_PIN W6  IOSTANDARD LVCMOS33} [get_ports link_a_ready]    ;#        ?
    set_property -dict {PACKAGE_PIN Y7  IOSTANDARD LVCMOS33} [get_ports link_a_rvalid]   ;#        ?
    # spare RPi pins: F20 W9

    # ---- side B: the slave, on the Arduino header ------------------------
    set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports link_b_clk]      ;# D0
    set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVCMOS33} [get_ports {link_b_io[0]}]  ;# D1
    set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVCMOS33} [get_ports {link_b_io[1]}]  ;# D2 (PUDC_B)
    set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports {link_b_io[2]}]  ;# D3
    set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {link_b_io[3]}]  ;# D4
    set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports {link_b_io[4]}]  ;# D5
    set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVCMOS33} [get_ports {link_b_io[5]}]  ;# D6
    set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports {link_b_io[6]}]  ;# D7
    set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports {link_b_io[7]}]  ;# D8
    set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVCMOS33} [get_ports {link_b_io[8]}]  ;# D9
    set_property -dict {PACKAGE_PIN F16 IOSTANDARD LVCMOS33} [get_ports {link_b_io[9]}]  ;# D10
    set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVCMOS33} [get_ports {link_b_io[10]}] ;# D11
    set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS33} [get_ports {link_b_io[11]}] ;# D12
    set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33} [get_ports {link_b_io[12]}] ;# D13
    set_property -dict {PACKAGE_PIN Y11 IOSTANDARD LVCMOS33} [get_ports {link_b_io[13]}] ;# A0
    set_property -dict {PACKAGE_PIN Y12 IOSTANDARD LVCMOS33} [get_ports {link_b_io[14]}] ;# A1
    set_property -dict {PACKAGE_PIN W11 IOSTANDARD LVCMOS33} [get_ports {link_b_io[15]}] ;# A2
    set_property -dict {PACKAGE_PIN V11 IOSTANDARD LVCMOS33} [get_ports link_b_dir]      ;# A3
    set_property -dict {PACKAGE_PIN T5  IOSTANDARD LVCMOS33} [get_ports link_b_req]      ;# A4
    set_property -dict {PACKAGE_PIN U10 IOSTANDARD LVCMOS33} [get_ports link_b_wr]       ;# A5
    set_property -dict {PACKAGE_PIN T12 IOSTANDARD LVCMOS33} [get_ports link_b_burst]    ;# ICSP MOSI
    set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVCMOS33} [get_ports link_b_ready]    ;# ICSP MISO
    set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports link_b_rvalid]   ;# ICSP SCK

    # ---- things to look at ------------------------------------------------
    set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports status_led]      ;# LD0: trained & heartbeat
    set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVCMOS33} [get_ports uart_tx_pin]     ;# PMODB JB1: the chip's uart_tx

    # The bidirectional bus idles undriven for TA cycles at every turnaround
    # and while the chip is in reset; a weak pull keeps the receivers off the
    # threshold in that window.
    set_property PULLDOWN true [get_ports {link_a_io[*]}]
    set_property PULLDOWN true [get_ports {link_b_io[*]}]

    # Pad-to-flop within each half.  The slave's IN_REG flops go in the IOB;
    # the chip's negedge capture flops cannot (they are the ASIC's, not the
    # pad's) and are timed by the create_clock on link_a_clk.
    set_property IOB TRUE [get_cells -quiet -hier -filter {NAME =~ *slave/g_inreg*}]
}
