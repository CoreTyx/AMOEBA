###############################################################################
# build_forte.tcl -- project, block design and bitstream for DUT=forte.
#
#   vivado -mode batch -source tcl/build_forte.tcl -tclargs \
#          <srcs.f> <part> <board> <out_dir> <defines> <incdirs> \
#          <fclk_mhz> <stage> <board_repo>
#
# stage: bd (stop once the block design validates), synth, or bit.
###############################################################################

if {[llength $argv] < 9} {
    puts "ERROR: expected 9 tclargs, got [llength $argv]"
    exit 1
}
lassign $argv srcs_f part board out_dir defines incdirs fclk_mhz stage board_repo mem_backend
if {$mem_backend eq ""} { set mem_backend BRAM }

if {$board eq "none" && $stage eq "bit"} {
    puts "ERROR: board=none has no PYNQ-Z2 DDR/MIO preset; it cannot make a usable bitstream."
    exit 1
}

set script_dir [file dirname [file normalize [info script]]]
set proj_dir   [file join $out_dir proj]

puts "=== forte PYNQ-Z2 build: $part, board $board, $fclk_mhz MHz, stage $stage -> $out_dir ==="

file mkdir $out_dir
create_project -force forte $proj_dir -part $part
if {$board_repo ne "" && $board_repo ne "none"} {
    set_param board.repoPaths $board_repo
}

set fh [open $srcs_f r]
set srcs [split [string trim [read $fh]] "\n"]
close $fh
add_files -norecurse $srcs
set_property file_type SystemVerilog [get_files *.sv]

# Headers must be in the project for IPI's module-reference elaboration, and
# must stay "Verilog Header" (see build.tcl for what goes wrong otherwise).
set headers {}
foreach d $incdirs {
    foreach f [glob -nocomplain [file join $d *.vh] [file join $d prim_assert.sv]] {
        lappend headers $f
    }
}
if {[llength $headers]} {
    add_files -norecurse -fileset sources_1 $headers
    set_property file_type {Verilog Header} [get_files -of_objects [get_filesets sources_1] *.vh]
}
set_property include_dirs   $incdirs [get_filesets sources_1]
set_property verilog_define $defines [get_filesets sources_1]
update_compile_order -fileset sources_1

source [file join $script_dir bd_forte.tcl]
if {![forte_build_bd board $board fclk_mhz $fclk_mhz mem_backend $mem_backend]} {
    puts "ERROR: block design could not be built"
    exit 1
}

make_wrapper -files [get_files forte.bd] -top -import
set_property top forte_wrapper [current_fileset]
update_compile_order -fileset sources_1
add_files -fileset constrs_1 -norecurse [file join $script_dir .. constraints forte_emu.xdc]

if {$stage eq "bd"} {
    puts "=== block design validated; stopping at stage 'bd' ==="
    exit 0
}

launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: synthesis failed -- see $proj_dir/forte.runs/synth_1"
    exit 1
}
if {$stage eq "synth"} {
    open_run synth_1
    report_utilization    -file [file join $out_dir utilization.rpt]
    report_timing_summary -file [file join $out_dir timing.rpt]
    puts "=== synthesized; stopping at stage 'synth' ==="
    exit 0
}

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: implementation failed -- see $proj_dir/forte.runs/impl_1"
    exit 1
}

open_run impl_1
report_utilization -hierarchical -hierarchical_depth 4 -file [file join $out_dir utilization_hier.rpt]
report_utilization    -file [file join $out_dir utilization.rpt]
report_timing_summary -file [file join $out_dir timing.rpt]
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
puts "  post-route WNS : $wns ns"
if {$wns < 0} {
    puts "WARNING: timing not met at $fclk_mhz MHz."
}

set bit [glob -nocomplain [file join $proj_dir forte.runs impl_1 *.bit]]
if {[llength $bit]} {
    file copy -force [lindex $bit 0] [file join $out_dir forte.bit]
}
set hwh [glob -nocomplain [file join $proj_dir forte.gen sources_1 bd forte hw_handoff forte.hwh]]
if {[llength $hwh]} {
    file copy -force [lindex $hwh 0] [file join $out_dir forte.hwh]
} else {
    puts "WARNING: no .hwh found; PYNQ's Overlay() needs it"
}
puts "=== done: $out_dir/forte.bit ==="
exit 0
