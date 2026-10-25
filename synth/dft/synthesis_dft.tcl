# Adapted copy of ../synthesis.tcl. Run through ./run.sh; never overwrites the
# normal synth outputs. Modes: inventory (default), baseline, scan.
# Current RTL supports inventory/baseline only; see plan.md for scan hookup work.
set dft_dir [file dirname [file normalize [info script]]]
proc dft_env {name default} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return $default
}
set dft_mode [dft_env DFT_MODE inventory]
set dft_tier [dft_env DFT_TIER 1]
if {$dft_mode ni {inventory baseline scan}} { error "Unknown DFT_MODE" }
if {$dft_tier ni {1 2 3 4}} { error "DFT_TIER must be 1, 2, 3 or 4" }
file mkdir reports outputs work
source [file join $dft_dir .. dc_warn.tcl]

if {[getenv ECE411_MIN_POWER] eq "1"} {
   set power_enable_minpower true
}
set hdlin_ff_always_sync_set_reset true
set hdlin_ff_always_async_set_reset true
set hdlin_infer_multibit default_all
set hdlin_check_no_latch true
set hdlin_while_loop_iterations 2000000000
set_host_options -max_cores [getenv ECE411_DC_CORES]
set_app_var report_default_significant_digits 6
set design_toplevel [getenv DESIGN_TOP]
if {$design_toplevel ne "forte_top"} { error "This DFT interface targets forte_top" }

define_design_lib WORK -path ./work
set alib_library_analysis_path [getenv STD_CELL_ALIB]

set symbol_library [list generic.sdb]
set synthetic_library [list dw_foundation.sldb]
set target_library [getenv STD_CELL_LIB]
set sram_library [getenv SRAM_LIB]

if {$sram_library eq ""} {
   set link_library [list "*" $target_library $synthetic_library]
} else {
   set link_library [concat [list "*"] $target_library $synthetic_library $sram_library]
}

get_license DC-Ultra-Features
get_license DC-Ultra-Opt

set repo_root [getenv REPO_ROOT]
lappend search_path "$repo_root/pkg" "$repo_root/hdl/core" "$repo_root/third_party/opentitan" "$repo_root/third_party/cvw/config/rv64gc"

set pkg_src [getenv PKG_SRCS]

if {$pkg_src ne ""} {
   if {![analyze -library WORK -format sverilog $pkg_src]} {
      error "Package analysis failed"
   }
}

set modules [split [getenv HDL_SRCS] " "]
foreach module $modules {
   if {![analyze -library WORK -format sverilog "${module}"]} {
      error "Analysis failed: $module"
   }
}

elaborate $design_toplevel
current_design $design_toplevel

if {![link]} { error "Unresolved references; fix libraries before measuring area" }
check_design > reports/check_design_elab.rpt
source [file join $dft_dir scan_selection.tcl]

# Preserve hierarchy in BOTH baseline and scan experiments, for comparable
# selection and area. This is not automatically comparable to a flattened run.
set hierarchy [get_cells -quiet -hierarchical -filter "is_hierarchical == true"]
if {[sizeof_collection $hierarchy]} { set_ungroup $hierarchy false }
set registers [all_registers -cells]
set selected [remove_from_collection $registers $registers]
set inv [open reports/register_inventory.tsv w]
puts $inv "first_tier\tinstance"
foreach_in_collection cell $registers {
    set name [get_object_name $cell]
    set first [dft_first_tier $name]
    puts $inv "$first\t$name"
    if {$first > 0 && $first <= $dft_tier} {
        set selected [add_to_collection $selected $cell]
    }
}
close $inv
set sel [open reports/selected_registers.txt w]
foreach_in_collection cell $selected { puts $sel [get_object_name $cell] }
close $sel
# all_registers object counts are not bit counts, especially before mapping.
echo "Register objects: [sizeof_collection $registers]; selected objects: [sizeof_collection $selected]"
if {$dft_mode eq "inventory"} {
    write_file -format ddc -hierarchy -output outputs/elaborated.ddc
    echo "Inventory only: no scan replacement, stitching or MBIST insertion performed."
    exit
}

set_wire_load_model -name "5K_hvratio_1_1"
set_wire_load_mode enclosed
source [dft_env DFT_SDC [file join $dft_dir constraints.sdc]]
set ports_before [lsort [get_object_name [get_ports *]]]

if {$dft_mode eq "scan"} {
    foreach cmd {set_scan_element set_scan_configuration set_dft_signal
                 set_scan_path create_test_protocol dft_drc preview_dft insert_dft
                 report_scan_path write_test_protocol} {
        if {![llength [info commands $cmd]]} { error "Missing DFT command/license: $cmd" }
    }
    set hookup [dft_env DFT_HOOKUP_TCL ""]
    if {$hookup eq "" || ![file isfile $hookup]} {
        error "Scan needs DFT_HOOKUP_TCL and integrated RTL hooks; see hookup.example.tcl"
    }
    source $hookup
    if {$dft_tier >= 3} {
        if {![info exists DFT_MBIST_CELL] || $DFT_MBIST_CELL eq ""} {
            error "Tier 3/4 requires integrated MBIST RTL and DFT_MBIST_CELL"
        }
        if {[sizeof_collection [get_cells -quiet $DFT_MBIST_CELL]] != 1} {
            error "MBIST controller instance does not resolve"
        }
    }
    if {![info exists DFT_HOOKS_READY] || !$DFT_HOOKS_READY} {
        error "Hookup is not ready; current scan_q stubs must be replaced first"
    }
    foreach var {DFT_LOCKED_MODE_PIN DFT_LOCKED_ENABLE_PIN DFT_CONTROL_CELL
                 DFT_SCAN_IN_PINS DFT_SCAN_OUT_PINS} {
        if {![info exists $var] || [set $var] eq ""} { error "Missing $var" }
    }
    if {[llength $DFT_SCAN_IN_PINS] != 8 || [llength $DFT_SCAN_OUT_PINS] != 8} {
        error "Expected exactly eight internal scan input and output hooks"
    }
    foreach name [concat [list $DFT_LOCKED_MODE_PIN $DFT_LOCKED_ENABLE_PIN] \
                          $DFT_SCAN_IN_PINS $DFT_SCAN_OUT_PINS] {
        if {[sizeof_collection [get_pins -quiet $name]] != 1} {
            error "Hook must resolve to exactly one pin: $name"
        }
    }
    set controls [get_cells -quiet $DFT_CONTROL_CELL]
    set lock [get_cells -quiet -hierarchical -filter "full_name =~ */dftlock/* && is_hierarchical == false"]
    if {[sizeof_collection $controls] != 1 || ![sizeof_collection $lock]} {
        error "Cannot identify DFT control instance or lock cells"
    }
    if {[sizeof_collection $selected] < 8} { error "Too few selected objects; review inventory patterns" }
    # Explicit partial scan: never fall back to the tool's default full scan.
    set_scan_element false $registers
    set_scan_element true $selected
    set_scan_element false $controls
    set_scan_element false $lock
    # Keep hookup boundaries stable without freezing unmapped GTECH cells.
    set_boundary_optimization $controls false
    set lock_boundary [get_cells -quiet -hierarchical -filter "full_name =~ */dftlock && is_hierarchical == true"]
    if {![sizeof_collection $lock_boundary]} { error "Missing lock hierarchy" }
    set_boundary_optimization $lock_boundary false
    set_scan_configuration -style multiplexed_flip_flop -chain_count 8 -clock_mixing no_mix

    set scan_period [dft_env DFT_SCAN_PERIOD 100.0]
    if {![string is double -strict $scan_period] || $scan_period <= 0} {
        error "DFT_SCAN_PERIOD must be positive, in library time units"
    }
    set test_default_period $scan_period
    set_dft_signal -view existing_dft -type ScanClock -port core_clk \
        -timing [list [expr {0.25*$scan_period}] [expr {0.75*$scan_period}]]
    set_dft_signal -view existing_dft -type Reset -port rst_n -active_state 0
    # Connect downstream of the lock; never specify raw scan_en as the hookup.
    set_dft_signal -view spec -type TestMode -active_state 1 \
        -hookup_pin [get_pins $DFT_LOCKED_MODE_PIN]
    set_dft_signal -view spec -type ScanEnable -active_state 1 \
        -hookup_pin [get_pins $DFT_LOCKED_ENABLE_PIN]
    for {set i 0} {$i < 8} {incr i} {
        set si [get_pins [lindex $DFT_SCAN_IN_PINS $i]]
        set so [get_pins [lindex $DFT_SCAN_OUT_PINS $i]]
        set_dft_signal -view spec -type ScanDataIn -hookup_pin $si
        set_dft_signal -view spec -type ScanDataOut -hookup_pin $so
        set_scan_path chain$i -view spec -scan_data_in $si -scan_data_out $so
    }
    # Required local setup, never automatic bypass of a lock or reset.
    if {![llength [info commands dft_site_setup]]} { error "Missing dft_site_setup" }
    dft_site_setup
}

set compile_cmd [getenv ECE411_COMPILE_CMD]
if {![regexp {^compile_ultra( |$)} $compile_cmd]} {
    error "This copy expects compile_ultra, as configured in the project"
}
if {[regexp {(^| )-retime( |$)} $compile_cmd]} {
    error "Disable retiming for the first matched partial-scan comparison"
}
if {![regexp {(^| )-no_autoungroup( |$)} $compile_cmd]} { append compile_cmd " -no_autoungroup" }
if {$dft_mode eq "scan"} { append compile_cmd " -scan" }
eval $compile_cmd
for {set i 0} {$i < [getenv ECE411_COMPILE_ITER]} {incr i} {
    set incremental_cmd [getenv ECE411_COMPILE_CMD_INC]
    if {[regexp {(^| )-retime( |$)} $incremental_cmd]} { error "Disable incremental retiming" }
    append incremental_cmd " -no_autoungroup"
    if {$dft_mode eq "scan"} { append incremental_cmd " -scan" }
    eval $incremental_cmd
}

if {$dft_mode eq "scan"} {
    # Freeze authorization only AFTER technology mapping. Freezing GTECH cells
    # before compile can prevent their mapping into the actual target library.
    set controls [get_cells -quiet $DFT_CONTROL_CELL]
    set lock [get_cells -quiet -hierarchical -filter "full_name =~ */dftlock/* && is_hierarchical == false"]
    if {[sizeof_collection $controls] != 1 || ![sizeof_collection $lock]} {
        error "Lost the mapped DFT control/lock boundary"
    }
    set_dont_touch $controls true
    set_dont_touch $lock true
    create_test_protocol
    dft_drc -verbose > reports/dft_drc_pre.rpt
    preview_dft -show all > reports/preview_dft.rpt
    insert_dft
    dft_drc -verbose > reports/dft_drc_post.rpt
    report_scan_path -view existing_dft -chain all > reports/scan_chains.rpt
    write_test_protocol -output outputs/forte_top.scan.spf
    if {[lsort [get_object_name [get_ports *]]] ne $ports_before} {
        error "Insertion changed top-level ports; review unintended test pins before use"
    }
}
current_design $design_toplevel
# Functional timing view; DFT DRC/protocol above uses the test configuration.
set_case_analysis 0 [get_ports test_mode]
set_case_analysis 0 [get_ports scan_en]
report_area -hierarchy > reports/area.rpt
report_qor > reports/qor.rpt
report_timing -delay max -max_paths 20 > reports/timing.rpt
report_constraint -all_violators > reports/violators.rpt
check_design > reports/check_design_final.rpt
set cap [dft_env DFT_MAX_MAPPED_AREA ""]
if {$cap ne ""} {
    if {![string is double -strict $cap] || $cap <= 0} { error "Invalid DFT_MAX_MAPPED_AREA" }
    set area [get_attribute [current_design] area]
    if {$area > $cap} { error "Mapped cell area $area exceeds configured cap $cap" }
}
change_names -rules verilog -hierarchy
write_file -format ddc -hierarchy -output outputs/forte_top.$dft_mode.ddc
write_file -format verilog -hierarchy -output outputs/forte_top.$dft_mode.v
write_sdc outputs/forte_top.functional.sdc
# Protocol names preceded final change_names: regenerate the protocol for the
# actual emitted netlist, rather than handing downstream tools stale names.
if {$dft_mode eq "scan"} {
    report_scan_path -view existing_dft -chain all > reports/scan_chains.rpt
    write_test_protocol -output outputs/forte_top.scan.spf
}
echo "Candidate written; DRC, ATPG coverage, lock tests and placed timing still require review."
exit
