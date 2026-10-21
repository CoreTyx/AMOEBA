# Measure the fanout-of-4 inverter delay (FO4) of a standard-cell library.
#
# FO4 is the unit the timing flow uses to carry numbers between processes: a
# path that is N FO4 deep in one library is close to N FO4 deep in another, so
# the ratio of two libraries' FO4 is the factor that converts delay between
# them (see tech.tcl).
#
# The measurement is a chain of six inverters in which every stage drives four
# identical inverters.  The delays of stages 3 and 4 are averaged: by then the
# input slew has settled to what an FO4 stage itself produces, and the pair
# covers one rising and one falling transition.
#
# Run standalone against ANY library, including the real 65 nm one:
#   STD_CELL_LIB=/path/lib.db FO4_INV=INVD1 FO4_INV_IN=I FO4_INV_OUT=ZN \
#     dc_shell -f fo4.tcl
# The result goes to reports/fo4.txt as a single number in picoseconds.

proc fo4_env {name default} {
   if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
   return $default
}

proc measure_fo4 {} {
   set inv  [fo4_env FO4_INV     INV_X1]
   set ipin [fo4_env FO4_INV_IN  A]
   set opin [fo4_env FO4_INV_OUT ZN]

   file mkdir work
   set f [open work/fo4_chain.v w]
   puts $f "module fo4_chain(input in, output out);"
   puts $f "  wire n0, n1, n2, n3, n4, n5, n6;"
   puts $f "  assign n0 = in;"
   puts $f "  assign out = n6;"
   for {set i 1} {$i <= 6} {incr i} {
      puts $f "  $inv u$i (.$ipin (n[expr {$i-1}]), .$opin (n$i));"
      # three more loads on every stage output: fanout of four in total
      foreach l {a b c} {
         puts $f "  $inv l$i$l (.$ipin (n$i), .$opin ());"
      }
   }
   puts $f "endmodule"
   close $f

   read_verilog work/fo4_chain.v
   current_design fo4_chain
   link
   # Gate loading only: no wire-load model, so the number is the cells' own.
   set_load 0 [all_outputs]
   set_max_delay 100 -from [get_ports in] -to [get_ports out]

   set path [get_timing_paths -from [get_ports in] -to [get_ports out]]
   array set arr {}
   foreach_in_collection pt [get_attribute $path points] {
      set arr([get_object_name [get_attribute $pt object]]) [get_attribute $pt arrival]
   }
   set d3 [expr {$arr(u3/$opin) - $arr(u2/$opin)}]
   set d4 [expr {$arr(u4/$opin) - $arr(u3/$opin)}]
   set fo4_ps [expr {1000.0 * ($d3 + $d4) / 2.0}]
   remove_design -all
   return $fo4_ps
}

# Standalone use.
if {![info exists fo4_as_library]} {
   set target_library [getenv STD_CELL_LIB]
   set link_library   [list "*" $target_library]
   set fo4_ps [measure_fo4]
   file mkdir reports
   set f [open reports/fo4.txt w]
   puts $f [format "%.3f" $fo4_ps]
   close $f
   echo [format "FO4 of %s: %.2f ps" $target_library $fo4_ps]
   exit
}
