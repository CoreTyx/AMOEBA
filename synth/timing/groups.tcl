# Path groups for the calibrated timing flow: one per area of the design, so a
# single run reports the worst path in each instead of only the worst overall.
#
# Groups are defined by where a path ENDS (or, for the caches, also where it
# starts), using register instance names.  Those survive synthesis, whereas the
# combinational cells in between are renamed and merged.  A path that ends in
# none of them stays in the clock's own group, reported as `other`.

# name  direction  instance-name patterns
set TIMING_GROUPS {
   regfile_wr  to    {*/dp/regf/rf_reg*}
   id_ex       to    {*/dp/RD1EReg/* */dp/RD2EReg/* */dp/ImmExtEReg/*}
   ex_mem      to    {*/dp/SrcAMReg/* */dp/IEUResultMReg/* */dp/WriteDataMReg/* */lsu/AddressMReg/*}
   mem_wb      to    {*/dp/IFResultWReg/* */MDUResultWReg/* */lsu/ReadDataMWReg/*}
   ft_alu      to    {*/dp/ftalu/*}
   mul         to    {*/ftmul/*}
   div         to    {*ftdiv/*}
   fetch_pc    to    {*/ifu/pcreg/*}
   dcache      both  {*/lsu/*dcache/*}
   icache      both  {*/ifu/*icache/*}
}

# Blocks whose boundaries are kept through compile so a path can be broken down
# by the block each cell sits in.  Everything inside them is still free to be
# flattened and restructured.
set TIMING_KEEP_HIER {
   */core/ieu */ieu/c */ieu/dp */dp/regf */dp/ftalu */dp/ftalu/replica*compute
   */dp/RD1EReg */dp/RD2EReg */dp/ImmExtEReg */dp/SrcAMReg */dp/IEUResultMReg
   */dp/WriteDataMReg */dp/IFResultWReg
   */core/mdu.mdu */ftmul */ftmul/primary */ftmul/shadow *ftdiv
   */core/lsu */lsu/*dcache */core/ifu */ifu/*icache */core/hzu */core/priv.priv
   */soc/uncore
}

proc timing_group_names {} {
   global TIMING_GROUPS
   set names {}
   foreach {name dir patterns} $TIMING_GROUPS { lappend names $name }
   return [concat $names {fault_inject link_io}]
}

# Registers and hard macros whose instance path matches any of the patterns.
proc timing_endpoints {patterns} {
   set pool [add_to_collection -unique [all_registers] \
                [get_cells -quiet -hierarchical -filter "ref_name =~ rf_sp_* || ref_name =~ TS1N*"]]
   set found ""
   foreach p $patterns {
      set found [add_to_collection -unique $found [filter_collection $pool "full_name =~ $p"]]
   }
   return $found
}

proc timing_define_groups {} {
   global TIMING_GROUPS
   foreach {name dir patterns} $TIMING_GROUPS {
      set cells [timing_endpoints $patterns]
      if {[sizeof_collection $cells] == 0} {
         echo "Warning: timing group $name matches no registers"
         continue
      }
      echo [format "timing group %-12s %6d endpoints" $name [sizeof_collection $cells]]
      group_path -name $name -to $cells
      if {$dir eq "both"} { group_path -name $name -from $cells }
   }
   group_path -name fault_inject -from [get_ports fault_inject]
   group_path -name link_io -from [get_ports {io[*] ready rvalid}]
   group_path -name link_io -to   [get_ports {io[*] dir req wr uart_tx status}]
}

proc timing_keep_hierarchy {} {
   global TIMING_KEEP_HIER
   foreach p $TIMING_KEEP_HIER {
      set cells [get_cells -quiet -hierarchical -filter "is_hierarchical == true && full_name =~ $p"]
      if {[sizeof_collection $cells] > 0} { set_ungroup $cells false }
   }
}
