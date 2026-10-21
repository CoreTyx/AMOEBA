# Calibrated timing run: synthesize forte_top with FreePDK45 standing in for
# TSMC 65GP, and report each area of the design against the 400 MHz target.
#
# Driven by `make -C synth timing`, which runs fo4.tcl and builds the black-box
# library first.  Run from synth/timing.  Environment:
#   PKG_SRCS HDL_SRCS REPO_ROOT   source lists, from the Makefile
#   STD_CELL_LIB STD_CELL_ALIB    calibration library
#   TIMING_TOP                    design to synthesize (forte_top)
#   TIMING_MODE                   full    analyze, compile, report (default)
#                                 elab    stop after elaborate + link: checks the
#                                         source list and black boxes in minutes
#                                 report  re-report outputs/<top>.ddc, no compile
#   TIMING_FLAT=1                 let compile dissolve every block boundary
#   TIMING_COMPILE_CMD            override the compile command

source ../dc_warn.tcl

set hdlin_ff_always_sync_set_reset true
set hdlin_ff_always_async_set_reset true
set hdlin_infer_multibit default_all
set hdlin_check_no_latch true
set hdlin_while_loop_iterations 2000000000
set_host_options -max_cores [getenv ECE411_DC_CORES]
set_app_var report_default_significant_digits 4

define_design_lib WORK -path ./work
set alib_library_analysis_path [getenv STD_CELL_ALIB]

set symbol_library    [list generic.sdb]
set synthetic_library [list dw_foundation.sldb]
set target_library    [getenv STD_CELL_LIB]
set link_library      [list "*" $target_library $synthetic_library work/forte_blackbox.db]

get_license DC-Ultra-Features
get_license DC-Ultra-Opt

proc timing_env {name default} {
   if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
   return $default
}

source tech.tcl
source groups.tcl
source summarize.tcl
source probes.tcl

set design_toplevel [getenv TIMING_TOP]
set mode [timing_env TIMING_MODE full]
file mkdir outputs

if {$mode eq "report"} {
   read_ddc outputs/$design_toplevel.ddc
   current_design $design_toplevel
   link
} else {
   set repo_root [getenv REPO_ROOT]
   lappend search_path "$repo_root/pkg" "$repo_root/hdl/core" "$repo_root/third_party/opentitan"

   # analyze returns 0 on a source it could not read.  That has to be fatal: the
   # module simply goes missing, and with it every path through it.
   foreach src [concat [getenv PKG_SRCS] [getenv HDL_SRCS]] {
      if {![analyze -library WORK -format sverilog $src]} {
         echo "Error: analyze failed on $src"
         exit 1
      }
   }

   elaborate $design_toplevel
   current_design $design_toplevel

   # Likewise a cell nothing resolves is a path nobody times.  Stop rather than
   # report a slack that silently leaves the caches or the pads out.
   if {![link]} {
      echo "Error: unresolved references in $design_toplevel (see the LINK-5 warnings above)."
      echo "       Add the cell to gen_blackbox_libs.py or the file to the source list."
      exit 1
   }

   echo "---- library cells standing in for 65 nm hard macros and pads ----"
   foreach_in_collection c [get_cells -quiet -hierarchical -filter "ref_name =~ rf_sp_* || ref_name =~ TS1N* || ref_name =~ io_*"] {
      echo [format "  %-28s %s" [get_attribute $c ref_name] [get_object_name $c]]
   }

   if {$mode eq "elab"} {
      redirect reports/registers_elab.txt {
         foreach_in_collection c [all_registers] { echo [get_object_name $c] }
      }
      echo "elaborate-only run: register names in reports/registers_elab.txt"
      exit
   }

   check_design > reports/check_design.rpt

   set_wire_load_model -name "5K_hvratio_1_1"
   set_wire_load_mode enclosed

   source constraints_65.sdc

   # Path groups before compile, so every area is optimized and not only the one
   # holding the single worst path; a tenth of a period of critical range keeps
   # the optimizer working on the near-critical paths in each.
   timing_define_groups
   set_critical_range [expr {0.10 * [ns65 $TECH(PERIOD_NS)]}] [current_design]

   # Keep the major block boundaries so each path can be broken down by block.
   if {[timing_env TIMING_FLAT 0] ne "1"} { timing_keep_hierarchy }

   eval [timing_env TIMING_COMPILE_CMD "compile_ultra -gate_clock"]

   current_design $design_toplevel
   # Saved before any reporting, so a report can be redone without recompiling.
   write_file -format ddc -hierarchy -output outputs/$design_toplevel.ddc
}

# Ungrouping renames cells, so the groups are rebuilt on the mapped netlist.
timing_define_groups

timing_summarize reports/summary.rpt
timing_probes    reports/probes.rpt

report_qor                                  > reports/qor.rpt
report_area -hierarchy                      > reports/area.rpt
report_timing -delay max -max_paths 1       > reports/timing.rpt
report_constraint -all_violators -max_delay > reports/violators.rpt
foreach g [timing_group_names] {
   report_timing -delay max -group $g -max_paths 5 -nets -input_pins \
      -transition_time -capacitance > reports/timing_$g.rpt
}

exit
