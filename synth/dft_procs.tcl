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

# Bind the four preserved chip nets after mapping and change_names.  Run once,
# from synthesis.tcl, before the pre-DFT checkpoint is written: the bindings
# are saved in the .ddc with the design.
#   dft_unlocked   existing_dft Constant   the DFT lock flop, 1 out of reset
#   test_mode_s    existing_dft Constant   test_mode after the tmsync flops;
#                                          DRC cannot carry the port constant
#                                          through two non-scan flops
#   scan_en_dft    spec ScanEnable         scan_en & dft_unlocked
#   test_mode_dft  spec TestMode           test_mode_s & dft_unlocked
proc dft_bind_hookups {{chip chip}} {
  foreach net {dft_unlocked test_mode_s} {
    lassign [dft_trace_driver $chip/$net 1] pin active kind
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
  set_dont_touch [get_nets [list $chip/scan_en_dft $chip/test_mode_dft $chip/test_mode_s $chip/dft_unlocked]] false
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
