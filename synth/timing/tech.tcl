# Process scaling for the calibrated timing flow.
#
# The design is synthesized with whatever library is available (FreePDK45 here)
# but the question being asked is about another one (TSMC 65GP).  The two are
# tied together by one number:
#
#     K = FO4(target library, signoff corner) / FO4(calibration library)
#
# A delay of d in the calibration library is taken to be K*d in the target.
# Rather than derate every cell, the whole problem is moved into the calibration
# library's time base: the 2.5 ns target period becomes 2.5/K, and so does every
# other absolute time (uncertainty, pad and SRAM budgets, I/O delays).  Cell
# delay, setup, clock-to-Q and wire load then all scale together, the optimizer
# sees the same relative pressure it will see in the real flow, and reports are
# multiplied back by K at the end.  Depths are also given in FO4, which needs no
# conversion at all.
#
# Needs: reports/fo4.txt (written by fo4.tcl) and tech.cfg.

proc tech_read_cfg {path} {
   global TECH
   set f [open $path r]
   while {[gets $f line] >= 0} {
      set line [string trim [lindex [split $line "#"] 0]]
      if {[llength $line] != 2} { continue }
      set name [lindex $line 0]
      set TECH($name) [lindex $line 1]
      if {[info exists ::env($name)] && $::env($name) ne ""} { set TECH($name) $::env($name) }
   }
   close $f
}

tech_read_cfg tech.cfg

set f [open reports/fo4.txt r]
set TECH(CAL_FO4_PS) [string trim [gets $f]]
close $f

set TECH(K) [expr {double($TECH(TARGET_FO4_PS)) / $TECH(CAL_FO4_PS)}]

# 65 nm nanoseconds -> calibration-library nanoseconds, and back.
proc ns65 {t}  { global TECH; return [expr {double($t) / $TECH(K)}] }
proc to65 {t}  { global TECH; return [expr {double($t) * $TECH(K)}] }
# Calibration-library nanoseconds -> FO4.
proc to_fo4 {t} { global TECH; return [expr {1000.0 * $t / $TECH(CAL_FO4_PS)}] }

echo [format "tech: calibration FO4 %.2f ps, target FO4 %.2f ps, K = %.4f" \
         $TECH(CAL_FO4_PS) $TECH(TARGET_FO4_PS) $TECH(K)]
echo [format "tech: %.3f ns target period is synthesized as %.3f ns (%.1f FO4)" \
         $TECH(PERIOD_NS) [ns65 $TECH(PERIOD_NS)] [to_fo4 [ns65 $TECH(PERIOD_NS)]]]
