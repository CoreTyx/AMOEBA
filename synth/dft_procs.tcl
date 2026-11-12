# dft_procs.tcl -- helpers shared by synthesis.tcl and dft_insert.tcl.
# Sourcing it only defines procs; nothing here changes the design.
#
# Q/QN AWARENESS.  Mapping is free to drive a net from a flop's QN, or from Q
# through an inverter, or to buffer it.  Two places care:
#
#   1. Constant hookups (dft_bind_hookups).  dft_unlocked and test_mode_s are
#      outputs of non-scan flops (the DFT lock, the test_mode synchroniser).
#      DRC must be told what they hold in test mode, and the value is only
#      known for the NET (both are 1).  The constant is placed on the flop
#      output pin that feeds the net, with its state corrected for every
#      inverter walked back through, so a QN pin or an inverting buffer can
#      never turn "unlocked" into a wrong 0 the way a hard-coded "Q pin, 1"
#      would.  The log line says which pin (Q/QN) and the state used.
#
#   2. Scan cells (dft_write_phase).  The scandef records which output each
#      cell shifts from ("( OUT QN )"): that is a scan-path inversion, which
#      the benches handle.  Separately, a flop can STORE the RTL bit inverted
#      (logical phase); the benches need that per cell.  dft_write_phase writes
#      it as <scandef instance path> <0|1>, the LOGICAL_PHASE format the bench
#      awk scripts read.  How it is decided is described at the proc.

# A lib pin's function with spaces and parentheses removed ("" if none).
proc dft_lib_function {pin} {
  set lp [get_lib_pins -quiet -of_objects $pin]
  if {[sizeof_collection $lp] == 0} { return "" }
  return [string map {" " "" "(" "" ")" ""} [get_attribute -quiet $lp function]]
}

# 1 if a sequential output pin is the inverting one (QN), else 0.  Uses the
# liberty function (IQN, !IQ, IQ'), then the pin name as a fallback.
proc dft_seq_pin_inverts {pin} {
  set fn [dft_lib_function $pin]
  if {[regexp {^(IQN|!IQ|IQ'|IQN1|!IQ1)$} $fn]} { return 1 }
  if {[regexp {^(IQ|!IQN|IQN'|IQ1)$} $fn]} { return 0 }
  return [regexp {N$} [get_attribute $pin name]]
}

# The single leaf driver of a net, or an error naming what was found.
proc dft_net_driver {net_name} {
  set net [get_nets -quiet $net_name]
  if {[sizeof_collection $net] != 1} {
    error "DFT: expected one net $net_name; found [sizeof_collection $net]"
  }
  set drv [get_pins -quiet -leaf -of_objects $net -filter "direction==out"]
  if {[sizeof_collection $drv] != 1} {
    error "DFT: $net_name requires exactly one mapped driver; found [sizeof_collection $drv]"
  }
  return $drv
}

# Walk from the driver of net_name back through single-input buffers and
# inverters to the cell that really produces the value: a flop output, or the
# first gate that is not a buffer/inverter.  want is the value of the NET in
# test mode.  Returns {pin active_state kind}: active_state is the value on
# that pin (want, flipped once per inverter crossed), and kind is Q or QN for
# a flop output, "comb" otherwise.
proc dft_trace_driver {net_name want} {
  set drv [dft_net_driver $net_name]
  set parity 0
  set walk [get_object_name $drv]
  for {set hop 0} {$hop < 32} {incr hop} {
    set cell [get_cells -of_objects $drv]
    if {[get_attribute -quiet $cell is_sequential] eq "true"} break
    set ins [get_pins -quiet -of_objects $cell -filter "direction==in"]
    if {[sizeof_collection $ins] != 1} break
    set in_name [get_attribute $ins name]
    set fn [dft_lib_function $drv]
    if {$fn eq $in_name} {
      set inv 0
    } elseif {$fn eq "!$in_name" || $fn eq "${in_name}'"} {
      set inv 1
    } else {
      break
    }
    set up [get_pins -quiet -leaf -of_objects [get_nets -quiet -of_objects $ins] -filter "direction==out"]
    if {[sizeof_collection $up] != 1} break
    set parity [expr {$parity ^ $inv}]
    set drv $up
    append walk " <- [get_object_name $drv]"
  }
  set cell [get_cells -of_objects $drv]
  if {[get_attribute -quiet $cell is_sequential] eq "true"} {
    set kind [expr {[dft_seq_pin_inverts $drv] ? "QN" : "Q"}]
  } else {
    set kind comb
  }
  set active [expr {$want ^ $parity}]
  puts "DFT hookup: $net_name=$want -> [get_object_name $drv] ($kind, [get_attribute $cell ref_name], $parity inversion(s), active_state $active)"
  puts "DFT hookup:   walk $walk"
  if {$kind ne "comb"} {
    # What the flop itself stores, for the log: QN shows the complement.
    set stored [expr {$active ^ ($kind eq "QN")}]
    puts "DFT hookup:   flop stores $stored in test mode"
  }
  return [list $drv $active $kind]
}

# Bind the five preserved chip nets after mapping and change_names.  Run once,
# from synthesis.tcl, before the pre-DFT checkpoint is written: the bindings
# are saved in the .ddc with the design.
#   dft_unlocked   existing_dft Constant 1 the DFT lock flop, 1 out of reset
#   test_mode_s    existing_dft Constant 1 test_mode after the tmsync flops;
#                                          DRC cannot carry the port constant
#                                          through two non-scan flops
#   hold_mode      existing_dft Constant 0 the hold-mode select flop.  DRC and
#                                          ATPG see legacy test mode: hold = 0,
#                                          so both RTL clock gates (cg_ns,
#                                          cg_scan) pass core_clk.  Hold mode
#                                          (1) is a debug-dump mode the benches
#                                          exercise, not an ATPG mode.
#   scan_en_dft    spec ScanEnable         scan_en & test_mode_dft
#   test_mode_dft  spec TestMode           test_mode_s & dft_unlocked
proc dft_bind_hookups {{chip chip}} {
  foreach {net want} {dft_unlocked 1 test_mode_s 1 hold_mode 0} {
    lassign [dft_trace_driver $chip/$net $want] pin active kind
    set_dft_signal -view existing_dft -type Constant -hookup_pin $pin -active_state $active
  }
  # Gate outputs with the net's own polarity: hook at the net's driver, so the
  # value on the pin is the value of the net (1 = shift / test).
  foreach {net type port} {scan_en_dft ScanEnable scan_en test_mode_dft TestMode test_mode} {
    set drv [dft_net_driver $chip/$net]
    puts "DFT hookup: $chip/$net -> [get_object_name $drv] ($type -port $port, active_state 1)"
    set_dft_signal -view spec -type $type -port $port -hookup_pin $drv -active_state 1
  }
  # Insertion may now add loads and optimise the control distribution.
  set_dont_touch [get_nets [list $chip/scan_en_dft $chip/test_mode_dft $chip/test_mode_s $chip/dft_unlocked $chip/hold_mode]] false
}

# ---- The clock split (hdl/forte_chip.sv: cg_ns, cg_scan) -------------------
#
# core_clk reaches the registers through two RTL clock gates (forte_clk_gate):
# cg_ns (test pin tied 0) clocks every non-scan register, cg_scan (test pin =
# scan_en_dft) clocks exactly the scan-selected ones.  Both pass the clock
# unless hold = test_mode_dft & hold_mode.  compile_ultra -gate_clock then
# infers integrated clock gates (ICGs) below them, and insert_dft would hook
# the test pin of every one of those to scan enable.  The procs here keep that
# hookup to the ICGs that gate scan flops and check the split itself.
#
# Clock tracing uses all_fanout/all_fanin -flat on the mapped netlist.  They
# follow timing arcs, so they cross buffers, inverters, the RTL gates' AND and
# an ICG's CK->GCK arc, and stop at a register's clock pin.

# Remove b from a, tolerating empty collections on either side.
proc dft_coll_minus {a b} {
  if {[sizeof_collection $a] == 0} { return {} }
  if {[sizeof_collection $b] == 0} { return $a }
  return [remove_from_collection $a $b]
}

# Leaf registers (sequential, not an ICG) whose clock pin is in the clock
# fanout of pin.
proc dft_clocked_regs {pin} {
  set ck [filter_collection [all_fanout -from $pin -flat -endpoints_only] "is_clock_pin==true"]
  if {[sizeof_collection $ck] == 0} { return {} }
  return [filter_collection [get_cells -of_objects $ck] "is_sequential==true && is_icg!=true"]
}

# Integrated clock-gating cells: leaf cells whose library cell carries
# clock_gating_integrated_cell (DC's is_icg).  These are the gates
# compile_ultra -gate_clock infers, plus any library ICG put in by the RTL or
# by replace_clock_gates.
proc dft_icg_cells {} {
  return [get_cells -hier * -quiet -filter "is_hierarchical==false && is_icg==true"]
}

# The pin of an ICG with library attribute clock_gate_<kind>_pin (kind: test,
# out, clock, enable), or "" if it has none.
proc dft_icg_pin {icg kind} {
  foreach_in_collection p [get_pins -quiet -of_objects $icg] {
    if {[get_attribute -quiet [get_lib_pins -quiet -of_objects $p] clock_gate_${kind}_pin] eq "true"} { return $p }
  }
  return ""
}

# 1 if a pin is tied off: unconnected, or its net has no driver, or the driver
# is a constant (DC's **logic_0**/**logic_1**, or a tie cell).
proc dft_pin_is_tied {pin} {
  set net [get_nets -quiet -of_objects $pin]
  if {[sizeof_collection $net] == 0} { return 1 }
  if {[regexp {\*Logic[01]\*} [get_object_name $net]]} { return 1 }
  set drv [get_pins -quiet -leaf -of_objects $net -filter "direction==out"]
  if {[sizeof_collection $drv] == 0} {
    return [expr {[sizeof_collection [get_ports -quiet -of_objects $net]] == 0}]
  }
  set ref [get_attribute [get_cells -of_objects [index_collection $drv 0]] ref_name]
  return [regexp -nocase {^\*\*logic_[01]\*\*$|^TIE|^LOGIC[01]} $ref]
}

# Scan-selected registers: dft_setup.tcl's scan_element attribute.
proc dft_selected_scan_regs {} {
  return [get_cells -hier * -quiet -filter "is_hierarchical==false && is_sequential==true && is_icg!=true && scan_element==true"]
}

# Print up to max object names, sorted, one per line with a prefix.
proc dft_list_cells {prefix coll {max 50}} {
  set names [lsort [get_object_name $coll]]
  foreach n [lrange $names 0 [expr {$max - 1}]] { puts "$prefix$n" }
  if {[llength $names] > $max} { puts "$prefix... and [expr {[llength $names] - $max}] more" }
}

# Cross-check the clock split:
#   - every scan flop is clocked through chip/cg_scan
#   - every flop clocked through chip/cg_scan is a scan flop
# A scan flop on cg_ns (or on the ungated core_clk/link_clk) would not shift
# in hold mode; a non-scan flop on cg_scan would load its functional D on every
# hold-mode shift, which is what the split is there to stop.
# scan: the scan flops; default the scan-selected registers (run after compile,
# before insertion).  After insertion pass the cells on the chains.
# strict 0 reports the second kind instead of failing: DFT_SCOPE=pc scans only
# the PC while cg_scan clocks the whole full-scope set.  The first kind is
# always an error.
proc dft_check_clock_split {{chip chip} {strict 1} {scan ""} {what "scan-selected"}} {
  foreach g {cg_ns cg_scan} {
    if {[sizeof_collection [get_pins -quiet $chip/$g/gclk]] != 1} {
      error "DFT clock split: no pin $chip/$g/gclk; is hdl/forte_chip.sv the clock-split RTL?"
    }
  }
  set on_scan [dft_clocked_regs [get_pins $chip/cg_scan/gclk]]
  set on_ns   [dft_clocked_regs [get_pins $chip/cg_ns/gclk]]
  if {$scan eq ""} { set scan [dft_selected_scan_regs] }
  set missing [dft_coll_minus $scan $on_scan]
  set extra   [dft_coll_minus $on_scan $scan]
  set n_missing [sizeof_collection $missing]
  set n_extra   [sizeof_collection $extra]
  puts "DFT clock split: cg_scan clocks [sizeof_collection $on_scan] flops, cg_ns [sizeof_collection $on_ns]; [sizeof_collection $scan] $what"
  puts "DFT clock split: $n_missing $what flops not under cg_scan, $n_extra flops under cg_scan not $what"
  if {$n_missing > 0} {
    puts "DFT clock split: ERROR: $what flops not clocked through $chip/cg_scan (would not shift in hold mode):"
    dft_list_cells "DFT clock split:   " $missing
  }
  if {$n_extra > 0} {
    set tag [expr {$strict ? "ERROR" : "WARNING"}]
    puts "DFT clock split: $tag: flops clocked through $chip/cg_scan that are not $what (they load functional data on every hold-mode shift):"
    dft_list_cells "DFT clock split:   " $extra
  }
  if {$n_missing > 0 || ($strict && $n_extra > 0)} {
    error "DFT clock split: cg_scan does not clock exactly the $what flops ($n_missing missing, $n_extra extra); see the log"
  }
}

# The gating cell of an RTL clock gate: from the driver of net_name back
# through single-input cells (buffers, inverters) to the first cell with more
# than one input (the AND of the behavioural model, or the ICG).
proc dft_clock_gate_cell {net_name} {
  set drv [dft_net_driver $net_name]
  for {set hop 0} {$hop < 16} {incr hop} {
    set cell [get_cells -of_objects $drv]
    set ins [get_pins -quiet -of_objects $cell -filter "direction==in"]
    if {[sizeof_collection $ins] != 1} break
    set up [get_pins -quiet -leaf -of_objects [get_nets -quiet -of_objects $ins] -filter "direction==out"]
    if {[sizeof_collection $up] != 1} break
    set drv $up
  }
  return $cell
}

# Report what chip/cg_ns and chip/cg_scan became after compile.  A library ICG
# carries its own clock-gating check.  The behavioural latch + AND does not:
# DC infers no check on that AND (FreePDK45 trial: the latch -> AND -> flop CK
# path was reported unconstrained), so the enable is not timed against the
# clock.  Give the AND one, -setup 0 -hold 0 (clock uncertainty supplies the
# margin); it is saved in the checkpoint and written to the gate-level SDC.
proc dft_rtl_clock_gate_checks {{chip chip}} {
  foreach g {cg_ns cg_scan} {
    set cell [dft_clock_gate_cell $chip/$g/gclk]
    set ref [get_attribute $cell ref_name]
    if {[get_attribute -quiet $cell is_icg] eq "true"} {
      puts "DFT clock gates: $chip/$g -> [get_object_name $cell] ($ref, integrated clock gate)"
    } else {
      set_clock_gating_check -setup 0 -hold 0 $cell
      puts "DFT clock gates: $chip/$g -> [get_object_name $cell] ($ref, discrete gate; clock-gating check added)"
    }
  }
}

# Decide which ICGs insert_dft may hook to scan enable, and tell it.  Run
# before dft_drc/insert_dft.  Each ICG is one of:
#   rtl       inside chip/cg_ns or chip/cg_scan: the RTL clock gates, whose
#             test pins are wired in RTL.  Never hooked.
#   hooked    on the clock path of at least one scan-selected flop: test pin
#             to scan enable, as before the split
#   excluded  gates no scan-selected flop: test pin stays tied 0.  Its flops
#             then load only when their own enable is true, in every mode.
# set_dft_clock_gating_configuration -exclude_elements takes the rtl and
# excluded ICGs plus the two RTL gate instances themselves.  Guard: no scan
# flop may be clocked through an excluded ICG (checked forward from each one,
# independently of how the sets were built).
# Returns {hooked_names excluded_names rtl_names} for dft_check_cg_hookups.
proc dft_cg_exclusions {{chip chip}} {
  set icgs [dft_icg_cells]
  set scan [dft_selected_scan_regs]
  set rtl  [filter_collection $icgs "full_name=~$chip/cg_ns/* || full_name=~$chip/cg_scan/*"]
  set upstream {}
  if {[sizeof_collection $scan] > 0} {
    set scan_ck [filter_collection [get_pins -of_objects $scan] "is_clock_pin==true"]
    set upstream [filter_collection [all_fanin -to $scan_ck -flat -only_cells] "is_hierarchical==false && is_icg==true"]
  }
  set hooked   [dft_coll_minus $upstream $rtl]
  set excluded [dft_coll_minus [dft_coll_minus $icgs $hooked] $rtl]
  set bad {}
  foreach_in_collection g $excluded {
    set out [dft_icg_pin $g out]
    if {$out eq ""} { error "DFT cg: [get_object_name $g] has no clock_gate_out_pin in its library cell" }
    set regs [dft_clocked_regs $out]
    set s [expr {[sizeof_collection $regs] ? [filter_collection $regs "scan_element==true"] : {}}]
    if {[sizeof_collection $s] > 0} { lappend bad "[get_object_name $g]: [lsort [get_object_name $s]]" }
  }
  if {[llength $bad] > 0} {
    foreach b $bad { puts "DFT cg: ERROR: scan flops behind excluded clock gate $b" }
    error "DFT cg: [llength $bad] excluded clock gates clock scan flops"
  }
  # Hierarchical SNPS_CLOCK_GATE* cells without an ICG inside are discrete
  # (latch + gate) clock gates; this proc does not see them, insert_dft would
  # hook them all.  Only happens with a library that has no ICG cells.
  set discrete 0
  foreach_in_collection h [get_cells -hier * -quiet -filter "is_hierarchical==true && ref_name=~SNPS_CLOCK_GATE*"] {
    if {[sizeof_collection [get_cells -quiet [get_object_name $h]/* -filter "is_icg==true"]] == 0} { incr discrete }
  }
  if {$discrete > 0} { puts "DFT cg: WARNING: $discrete clock gates are not integrated cells; their test pins are not managed here" }

  set excl [get_cells [list $chip/cg_ns $chip/cg_scan]]
  if {[sizeof_collection $rtl] > 0}      { set excl [add_to_collection $excl $rtl] }
  if {[sizeof_collection $excluded] > 0} { set excl [add_to_collection $excl $excluded] }
  set_dft_clock_gating_configuration -exclude_elements $excl
  puts "DFT cg: [sizeof_collection $hooked] ICGs hooked, [sizeof_collection $excluded] excluded (gate no scan flop), [sizeof_collection $rtl] inside $chip/cg_ns and $chip/cg_scan (RTL wiring kept)"
  return [list [get_object_name $hooked] [get_object_name $excluded] [get_object_name $rtl]]
}

# After insert_dft: check that exactly the planned ICGs had their test pin
# connected.  hooked: test pin driven (scan enable); excluded: still tied;
# rtl: whatever the RTL left (tied for cg_ns, driven for cg_scan), recorded
# by dft_cg_te_states before insertion.
proc dft_cg_te_states {names} {
  set st {}
  foreach n $names {
    set te [dft_icg_pin [get_cells $n] test]
    lappend st $n [expr {$te eq "" ? "none" : ([dft_pin_is_tied $te] ? "tied" : "driven")}]
  }
  return $st
}
proc dft_check_cg_hookups {plan rtl_before} {
  lassign $plan hooked excluded rtl
  set errs {}
  foreach {n st} [dft_cg_te_states $hooked]   { if {$st ne "driven"} { lappend errs "$n: test pin $st, expected hooked to scan enable" } }
  foreach {n st} [dft_cg_te_states $excluded] { if {$st ne "tied"}   { lappend errs "$n: test pin $st, expected left tied (excluded)" } }
  set now [dft_cg_te_states $rtl]
  foreach {n st} $rtl_before { if {[dict get $now $n] ne $st} { lappend errs "$n: test pin was $st before insert_dft, now [dict get $now $n]" } }
  foreach e $errs { puts "DFT cg: ERROR: $e" }
  if {[llength $errs] > 0} { error "DFT cg: [llength $errs] clock-gate test pins not as planned" }
  puts "DFT cg: after insert_dft: [llength $hooked] test pins on scan enable, [llength $excluded] tied, [llength $rtl] RTL gate pins unchanged"
}

# Scan cells from a scandef's SCANCHAINS section, in chain order from scan-in,
# as a flat list {chain index cell out_pin ...}.  out_pin is the scan output
# the scandef names (Q or QN; "" if it names none).  Same tokenising as the
# bench's scan_map.awk.
proc dft_scandef_cells {scandef} {
  set fh [open $scandef r]
  set text [read $fh]
  close $fh
  set cells {}
  set in_sc 0
  set chain ""; set mode ""; set want ""; set paren 0; set pdir ""
  set n 0
  foreach line [split $text "\n"] {
    if {[regexp {^\s*SCANCHAINS\s} $line]} { set in_sc 1; continue }
    if {[regexp {^\s*END\s+SCANCHAINS} $line]} { set in_sc 0; continue }
    if {!$in_sc} continue
    set line [string map {"(" " ( " ")" " ) " ";" " ; "} $line]
    foreach tok [regexp -all -inline {\S+} $line] {
      if {$want eq "name"} { set chain $tok; set n 0; set want ""; continue }
      if {$want eq "kw"}   { set mode $tok; set want ""; continue }
      switch -- $tok {
        "-" { set want name; set mode ""; continue }
        "+" { set want kw; continue }
        ";" { set mode ""; continue }
        "(" { set paren 1; set pdir ""; continue }
        ")" { set paren 0; continue }
      }
      if {$paren} {
        if {$pdir eq ""} {
          set pdir $tok
        } elseif {$pdir eq "OUT" && $n > 0} {
          lset cells end $tok
        }
        continue
      }
      # STOP is where the chain ends ("PIN <port>" or "<component> <input
      # pin>", e.g. the scan-out gate in front of io_out[k]): not a scan cell.
      if {$mode eq "FLOATING" || $mode eq "ORDERED"} {
        incr n
        lappend cells $chain $n $tok ""
      }
    }
  }
  return $cells
}

# Functional loads of an output pin: leaf input pins on its net, leaving out
# the scan path (scan-in pins of sequential cells).
proc dft_functional_loads {pin} {
  set net [get_nets -quiet -of_objects $pin]
  if {[sizeof_collection $net] == 0} { return 0 }
  set n 0
  foreach_in_collection ld [get_pins -quiet -leaf -of_objects $net -filter "direction==in"] {
    set c [get_cells -of_objects $ld]
    if {[get_attribute -quiet $c is_sequential] eq "true" &&
        [regexp {^(SI|TI|SD|SIN|SCAN_IN)$} [get_attribute $ld name]]} continue
    incr n
  }
  return $n
}

# Name of the net on an output pin, or "" when the net is DC-generated
# (n123, N123), unconnected, or part of the scan path (test_si*/test_so*,
# the ports insert_dft adds to carry a chain across a hierarchy boundary).
proc dft_design_net_name {pin} {
  set net [get_nets -quiet -of_objects $pin]
  if {[sizeof_collection $net] == 0} { return "" }
  set name [get_attribute $net name]
  if {[regexp {^([nN][0-9]+|SYNOPSYS_UNCONNECTED.*|\*Logic[01]\*|test_s[io][0-9]*)$} $name]} { return "" }
  return $name
}

# Write the per-cell logical phase for the benches, and a report.
#
# HOW PHASE IS DECIDED.  A flop stores its RTL bit inverted when mapping
# inverts its D input and takes the RTL signal from QN.  compile_ultra does
# this freely unless it is run with -no_seq_output_inversion (synthesis.tcl
# passes it; the compile_seqmap_enable_output_inversion variable does NOT stop
# compile_ultra).  DC keeps the RTL signal's name on the net that carries it,
# so the netlist shows the inversion: the RTL-named net hangs off QN and the
# net on Q, if any, is a generated nN.  That is the rule used here:
#   phase 1  the net on QN has a design name and the net on Q does not
#   phase 0  otherwise (Q named, both generated, or no QN)
# QN fanout alone is NOT evidence: logic that wants ~q legitimately reads QN of
# a true flop, and then the QN net is a generated name.  Checked on FreePDK45:
# without -no_seq_output_inversion this rule picked exactly the 14 cells whose
# reset values full_tb's phase B read inverted, and no others.  B and F remain
# the independent check.
#
# The report lists every phase-1 cell with both net names, cells whose Q and QN
# nets are both named (ambiguous: written 0), and, for information, cells read
# only from QN and cells with no functional load.
proc dft_write_phase {scandef out_file rpt_file} {
  set cells [dft_scandef_cells $scandef]
  set out [open $out_file w]
  set rpt [open $rpt_file w]
  puts $out "# Logical phase per scan cell, written by dft_insert.tcl from [file tail $scandef]."
  puts $out "# <scandef instance path> <0|1>: 1 = the flop stores the RTL bit inverted"
  puts $out "# (it has Q and QN and its RTL-named net is on QN; see dft_write_phase in dft_procs.tcl)."
  puts $rpt "DFT phase report: [file normalize $scandef]"
  puts $rpt "rule: phase 1 = a cell with both Q and QN pins whose QN net carries a design name and Q net does not;"
  puts $rpt "      a single-output cell (Q-only or QN-only) cannot be judged by net names and is written 0"
  puts $rpt ""
  puts $rpt [format "%-5s %5s %-4s %4s %4s %-5s %s" chain idx so Q QN phase cell]

  set total 0; set n_qn_so 0; set n_qn_only 0; set n_noload 0; set n_ph1 0; set n_missing 0; set n_amb 0; set n_single 0
  set notes {}
  foreach {chain idx name so_pin} $cells {
    incr total
    if {$so_pin eq "QN"} { incr n_qn_so }
    set c [get_cells -quiet $name]
    if {[sizeof_collection $c] != 1} {
      incr n_missing
      puts $out "$name 0"
      puts $rpt [format "%-5s %5d %-4s %4s %4s %-5s %s  (NOT FOUND in the design)" $chain $idx $so_pin - - 0 $name]
      continue
    }
    set q_loads 0; set qn_loads 0; set has_q 0; set has_qn 0; set q_name ""; set qn_name ""
    foreach_in_collection p [get_pins -quiet -of_objects $c -filter "direction==out"] {
      if {[dft_seq_pin_inverts $p]} {
        set has_qn 1
        incr qn_loads [dft_functional_loads $p]
        if {$qn_name eq ""} { set qn_name [dft_design_net_name $p] }
      } else {
        set has_q 1
        incr q_loads [dft_functional_loads $p]
        if {$q_name eq ""} { set q_name [dft_design_net_name $p] }
      }
    }
    # The last cell's scan-out pin also feeds the scan-out gate in front of
    # io_out; that gate counts as a load above.
    set qn_only [expr {$has_qn && $q_loads == 0 && $qn_loads > 0}]
    if {$qn_only} { incr n_qn_only; lappend notes "QN-only functional fanout: $name" }
    if {$q_loads + $qn_loads == 0} { incr n_noload; lappend notes "no functional load: $name" }
    # The rule compares the two outputs, so it needs both.  On a QN-only cell
    # (e.g. TSMC SDFFQNX*) the empty Q name would otherwise flag every cell
    # whose QN net is named, although the cell stores D as is.  With
    # compile_ultra -no_seq_output_inversion such cells hold the RTL bit.
    set single [expr {!($has_q && $has_qn)}]
    if {$single} { incr n_single }
    set ph [expr {!$single && $qn_name ne "" && $q_name eq "" ? 1 : 0}]
    if {$ph} { incr n_ph1; lappend notes "phase 1 (stored inverted): $name  Q net: -  QN net: $qn_name" }
    if {!$single && $qn_name ne "" && $q_name ne ""} {
      incr n_amb; lappend notes "AMBIGUOUS, written 0: $name  Q net: $q_name  QN net: $qn_name"
    }
    puts $out "$name $ph"
    puts $rpt [format "%-5s %5d %-4s %4d %4d %-5d %s" $chain $idx $so_pin $q_loads $qn_loads $ph $name]
  }
  puts $rpt ""
  puts $rpt "scan cells: $total"
  puts $rpt "scan output from QN (scan-path inversions, from the scandef): $n_qn_so"
  puts $rpt "phase 1 written (stored inverted): $n_ph1"
  puts $rpt "ambiguous (Q and QN nets both named), written 0: $n_amb"
  puts $rpt "single-output cells (Q-only or QN-only), written 0: $n_single"
  puts $rpt "functional fanout only from QN (information): $n_qn_only"
  puts $rpt "no functional load (constant/merged?): $n_noload"
  puts $rpt "not found in the design: $n_missing"
  foreach n $notes { puts $rpt "NOTE: $n" }
  close $out
  close $rpt
  puts "DFT phase: $total scan cells, $n_qn_so scan-out QN, $n_single single-output, $n_ph1 stored inverted -> $out_file"
  if {$n_missing > 0} { puts "DFT phase: WARNING: $n_missing scandef cells not found in the design (see $rpt_file)" }
  if {$n_ph1 > 0} { puts "DFT phase: WARNING: $n_ph1 scan cells are stored inverted; was compile_ultra run without -no_seq_output_inversion? (see $rpt_file)" }
  if {$n_amb > 0} { puts "DFT phase: WARNING: $n_amb scan cells have named nets on both Q and QN, written 0 (see $rpt_file)" }
}
