###############################################################################
# bd_forte.tcl -- the PYNQ-Z2 block design for DUT=forte.
#
#   PS7 GP0 -> interconnect -> forte_pynq_top_v/s_axi_ctl  (4 KiB at ctl_base)
#                           -> forte_pynq_top_v/s_axi_mem  (1 MiB at mem_base)
#   FCLK_CLK0 -> everything; proc_sys_reset -> aresetn; led[3:0] -> pins
#
# Sourced by build_forte.tcl with the project open.  Reuses
# amoeba_bd_require_board and amoeba_assign from bd_pynq.tcl.
###############################################################################

source [file join [file dirname [info script]] bd_pynq.tcl]

proc forte_build_bd {args} {
    array set opt {
        bd_name          forte
        top              forte_pynq_top_v
        board            tul.com.tw:pynq-z2:part0:1.0
        fclk_mhz         25
        trace_depth_log2 11
        ctl_base         0x43C00000
        mem_base         0x44000000
    }
    array set opt $args

    if {![amoeba_bd_require_board $opt(board)]} { return 0 }
    if {$opt(board) ne "none"} {
        set_property board_part $opt(board) [current_project]
    }

    create_bd_design $opt(bd_name)
    current_bd_design $opt(bd_name)

    set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7]
    set preset [expr {$opt(board) eq "none" ? "0" : "1"}]
    apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
        -config [list make_external "FIXED_IO, DDR" apply_board_preset $preset \
                      Master "Disable" Slave "Disable"] $ps
    set_property -dict [list \
        CONFIG.PCW_USE_M_AXI_GP0             {1} \
        CONFIG.PCW_USE_S_AXI_HP0             {0} \
        CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ  $opt(fclk_mhz) \
        CONFIG.PCW_EN_CLK0_PORT              {1} \
        CONFIG.PCW_EN_RST0_PORT              {1} \
    ] $ps

    create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_ps7
    connect_bd_net [get_bd_pins ps7/FCLK_CLK0]     [get_bd_pins rst_ps7/slowest_sync_clk]
    connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_ps7/ext_reset_in]

    set dut [create_bd_cell -type module -reference $opt(top) dut]
    set_property CONFIG.TRACE_DEPTH_LOG2 $opt(trace_depth_log2) $dut
    connect_bd_net [get_bd_pins ps7/FCLK_CLK0]                [get_bd_pins dut/aclk]
    connect_bd_net [get_bd_pins rst_ps7/peripheral_aresetn]   [get_bd_pins dut/aresetn]
    connect_bd_net [get_bd_pins ps7/FCLK_CLK0]                [get_bd_pins ps7/M_AXI_GP0_ACLK]

    foreach slave {dut/s_axi_ctl dut/s_axi_mem} {
        apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
            -config [list Master {/ps7/M_AXI_GP0} Clk "Auto"] \
            [get_bd_intf_pins $slave]
    }

    make_bd_pins_external [get_bd_pins dut/led]
    set_property NAME led [get_bd_ports led_0]

    amoeba_assign dut/s_axi_ctl/reg0 $opt(ctl_base) 4K
    amoeba_assign dut/s_axi_mem/reg0 $opt(mem_base) 1M

    validate_bd_design
    save_bd_design
    return 1
}
