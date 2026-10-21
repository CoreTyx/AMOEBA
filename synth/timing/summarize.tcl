# One-page result of a calibrated timing run.
#
# For the worst path in every group: slack in the calibration library and
# converted to 65 nm, how much of the cycle the path uses, its depth in FO4, and
# a breakdown of that depth by the block each cell sits in.  Then the same
# slacks re-evaluated at other target FO4 values, since the 65 nm number in
# tech.cfg is an estimate until someone measures it on the real library.

# Block a path point belongs to: the instance path of the cell's parent, with
# the common prefix removed.
proc timing_block_of {obj} {
   set name [get_object_name $obj]
   if {[get_attribute -quiet $obj object_class] eq "port"} { return "port:$name" }
   set block [file dirname [file dirname $name]]
   regsub {^chip/soc/core/} $block {} block
   regsub {^chip/soc/} $block {} block
   if {$block eq "." || $block eq ""} { set block "top" }
   return $block
}

# What one timing path looks like: its slack, the time it had and used, its
# depth and cell count, its ends, and where the depth went block by block.
proc timing_describe {p} {
   global TECH
   set slack [get_attribute $p slack]
   set open  [get_attribute -quiet $p startpoint_clock_open_edge_value]
   set close [get_attribute -quiet $p endpoint_clock_close_edge_value]
   if {$open eq "" || $close eq ""} { set open 0.0; set close [ns65 $TECH(PERIOD_NS)] }
   set avail [expr {$close - $open}]

   set first 1; set prev 0.0; set start 0.0; set cells 0
   set blocks {}; set bdelay {}
   foreach_in_collection pt [get_attribute $p points] {
      set obj [get_attribute $pt object]
      set arr [get_attribute $pt arrival]
      if {$first} { set start $arr; set prev $arr; set first 0 }
      if {[get_attribute -quiet $obj pin_direction] eq "out"} { incr cells }
      set b [timing_block_of $obj]
      if {[llength $blocks] > 0 && [lindex $blocks end] eq $b} {
         lset bdelay end [expr {[lindex $bdelay end] + $arr - $prev}]
      } else {
         lappend blocks $b; lappend bdelay [expr {$arr - $prev}]
      }
      set prev $arr
   }
   set trace {}
   foreach b $blocks d $bdelay {
      if {[to_fo4 $d] >= 0.5} { lappend trace [format "%s %.1f" $b [to_fo4 $d]] }
   }
   return [list slack $slack avail $avail used [expr {$avail - $slack}] \
              depth [to_fo4 [expr {$prev - $start}]] cells $cells \
              from [get_object_name [get_attribute $p startpoint]] \
              to   [get_object_name [get_attribute $p endpoint]] \
              trace [join $trace "  >  "]]
}

proc timing_summarize {outfile} {
   global TECH
   set period [ns65 $TECH(PERIOD_NS)]
   set sweep {30 35 40 45 50}
   set rows {}

   foreach g [concat [timing_group_names] my_clk] {
      if {[sizeof_collection [get_path_groups -quiet $g]] == 0} { continue }
      set paths [get_timing_paths -delay_type max -group $g -max_paths 1]
      if {[sizeof_collection $paths] == 0} { continue }
      array set d [timing_describe [index_collection $paths 0]]
      set label [expr {$g eq "my_clk" ? "other" : $g}]

      set row [format "%-13s %8.3f %8.3f %6.0f%% %7.1f %5d %7.1f" $label $d(slack) [to65 $d(slack)] \
                  [expr {100.0 * $d(used) / $d(avail)}] $d(depth) $d(cells) \
                  [expr {1000.0 / ($TECH(PERIOD_NS) * $d(used) / $d(avail))}]]
      set srow [format "%-13s" $label]
      foreach f $sweep {
         set kk [expr {double($f) / $TECH(CAL_FO4_PS)}]
         append srow [format " %8.3f" [expr {[to65 $d(avail)] - $d(used) * $kk}]]
      }
      lappend rows [list $d(slack) $row $srow \
                       [format "%s  (slack %.3f ns at 65 nm)\n  from %s\n  to   %s\n  %s\n" \
                           $label [to65 $d(slack)] $d(from) $d(to) $d(trace)]]
   }
   set rows [lsort -real -index 0 $rows]

   set f [open $outfile w]
   puts $f "Calibrated timing summary: [current_design_name]"
   puts $f [format "target %.3f ns (%.0f MHz) at FO4 = %.1f ps;  calibration library FO4 = %.2f ps;  K = %.4f" \
               $TECH(PERIOD_NS) [expr {1000.0 / $TECH(PERIOD_NS)}] $TECH(TARGET_FO4_PS) $TECH(CAL_FO4_PS) $TECH(K)]
   puts $f [format "one cycle = %.1f FO4, of which %.0f%% is clock uncertainty\n" \
               [to_fo4 $period] [expr {100.0 * $TECH(CLK_UNCERTAINTY_FRAC)}]]
   puts $f "Worst path per group, worst first.  slack_cal is what the tool saw; slack_65 = K * slack_cal."
   puts $f "used = share of the available time (a full or half cycle) the path takes, including"
   puts $f "uncertainty and setup.  depth = startpoint to endpoint, in FO4.  fmax = frequency this"
   puts $f "group alone would allow.\n"
   puts $f [format "%-13s %8s %8s %7s %7s %5s %7s" group slack_cal slack_65 used depth cells fmax]
   puts $f [format "%-13s %8s %8s %7s %7s %5s %7s" "" ns ns "" FO4 "" MHz]
   foreach r $rows { puts $f [lindex $r 1] }

   puts $f "\nslack_65 (ns) if the target library's FO4 were different, same netlist:"
   set hdr [format "%-13s" "FO4 (ps)"]
   foreach s $sweep { append hdr [format " %8d" $s] }
   puts $f $hdr
   foreach r $rows { puts $f [lindex $r 2] }

   puts $f "\nWhere each worst path spends its time (FO4 per block, blocks under 0.5 FO4 omitted):\n"
   foreach r $rows { puts $f [lindex $r 3] }
   close $f
}
