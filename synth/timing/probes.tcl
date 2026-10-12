# Probes: the worst path through one specific piece of the design.
#
# The group table in summary.rpt answers "which area is worst".  In this core
# that is usually the same long stall chain seen from different ends, which says
# little about any single block.  A probe pins a path down by its start, a net
# it must pass through, and its end, so the multiplier, the ALU, a cache read
# and so on each get their own number -- and a change to one of them shows up in
# its own row from one run to the next.
#
# Probes read the mapped netlist only; they do not steer optimization.

# Registers by instance path, as the pins a path can start or end on.
proc probe_regs {pat} { return [filter_collection [all_registers -edge_triggered] "full_name =~ $pat"] }
proc probe_ck   {pat} { return [get_pins -quiet -of_objects [probe_regs $pat] -filter "name == CK"] }
proc probe_d    {pat} { return [get_pins -quiet -of_objects [probe_regs $pat] -filter "pin_direction == in && name != CK"] }
proc probe_pin  {pat} { return [get_pins -quiet $pat] }

# label  -from  -through  -to     ("" = unconstrained)
# Each entry is a command that returns a collection, evaluated when the probe runs.
set core chip/soc/core
set dp   $core/ieu/dp
set dc   $core/lsu/bus.dcache.dcache
set ic   $core/ifu/bus.icache.icache
set mul  $core/mdu.mdu/ftmul

set TIMING_PROBES [subst -nocommands {
   "Register file"
   regfile_read        {probe_ck $dp/regf/rf_reg*}            {probe_pin $dp/regf/rd1*}            {probe_d $dp/RD1EReg/cw_stored*}
   regfile_write       {probe_ck $dp/IFResultWReg/*cw_stored*} {probe_pin $dp/regf/wd3*}            {probe_d $dp/regf/rf_reg*}
   regfile_bypass      {probe_ck $dp/IFResultWReg/*cw_stored*} {probe_pin $dp/regf/rd1*}            {probe_d $dp/RD1EReg/cw_stored*}
   instr_to_operand    {probe_ck $core/ifu/AlignedInstrRawDFlop/*} {probe_pin $dp/regf/rd1*}       {probe_d $dp/RD1EReg/cw_stored*}
   "Execute"
   alu_result          {probe_ck $dp/RD1EReg/cw_stored*}      {probe_pin $dp/ftalu/ALUResult*}     {probe_d $dp/IEUResultMReg/*cw_stored*}
   alu_result_fwd_M    {probe_ck $dp/IEUResultMReg/*cw_stored*} {probe_pin $dp/ftalu/ALUResult*}    {probe_d $dp/IEUResultMReg/*cw_stored*}
   alu_result_fwd_W    {probe_ck $dp/IFResultWReg/*cw_stored*} {probe_pin $dp/ftalu/ALUResult*}     {probe_d $dp/IEUResultMReg/*cw_stored*}
   alu_to_ft_stall     {probe_ck $dp/RD1EReg/cw_stored*}      {probe_pin $dp/ftalu/stall_req}      {}
   alu_to_dcache_addr  {probe_ck $dp/RD1EReg/cw_stored*}      {probe_pin $core/lsu/IEUAdrE*}       {probe_pin $dc/*/sramIP/A*}
   branch_to_pc        {probe_ck $dp/RD1EReg/cw_stored*}      {probe_pin $core/ifu/PCSrcE}         {probe_d $core/ifu/pcreg/*}
   "Multiply / divide"
   mul_E_product       {probe_ck $dp/RD1EReg/cw_stored*}      {probe_pin $mul/primary/ForwardedSrcAE*} {probe_d $mul/primary/PP1Reg/*}
   mul_M_result        {probe_ck $mul/primary/PP*Reg/*}       {probe_pin $mul/ProdM*}              {probe_d $core/mdu.mdu/MDUResultWReg/*}
   mul_M_to_ft_stall   {probe_ck $mul/primary/PP*Reg/*}       {probe_pin $mul/stall_req}           {}
   div_internal        {probe_ck $core/mdu.mdu/div.ftdiv/*}   {}                                   {probe_d $core/mdu.mdu/div.ftdiv/*}
   "Data cache"
   dc_tag_to_way       {probe_pin $dc/*/CacheTagMem/*/sramIP/CLK} {}                               {probe_d $dc/CacheWays*/selectedwaydatareg/*}
   dc_data_to_word     {probe_pin $dc/*/wordram.CacheDataMem/*/sramIP/CLK} {}                      {probe_d $dc/HitWordReg/*}
   dc_data_to_store    {probe_pin $dc/*/wordram.CacheDataMem/*/sramIP/CLK} {}                      {probe_pin $dc/*/sramIP/D*}
   dc_read_to_W        {}                                     {probe_pin $dc/ReadDataWord*}        {probe_d $core/lsu/ReadDataMWReg/*}
   "Instruction cache / fetch"
   ic_tag_to_way       {probe_pin $ic/*/CacheTagMem/*/sramIP/CLK} {}                               {probe_d $ic/CacheWays*/selectedwaydatareg/*}
   ic_data_to_word     {probe_pin $ic/*/wordram.CacheDataMem/*/sramIP/CLK} {}                      {probe_d $ic/HitWordReg/*}
   ic_read_to_instr    {}                                     {probe_pin $ic/ReadDataWord*}        {probe_d $core/ifu/AlignedInstrRawDFlop/*}
   pc_to_pc            {probe_ck $core/ifu/pcreg/*}           {}                                   {probe_d $core/ifu/pcreg/*}
   "Stall network and privileged"
   stall_from_hazard   {}                                     {probe_pin $core/hzu/StallW}         {}
   through_InjectD     {}                                     {probe_pin $core/ieu/InjectD}        {}
   priv_internal       {probe_ck $core/priv.priv/*}           {}                                   {probe_d $core/priv.priv/*}
   "Pads"
   fault_inject        {get_ports fault_inject}               {}                                   {}
   fault_inject_units  {probe_ck $core/faultinjectreg/*}      {}                                   {}
   link_in             {get_ports {io[*] ready rvalid}}       {}                                   {}
   link_out            {}                                     {}                                   {get_ports {io[*] dir req wr}}
}]

proc timing_probes {outfile} {
   global TIMING_PROBES TECH
   set f [open $outfile w]
   puts $f "Calibrated timing probes: [current_design_name]"
   puts $f [format "one cycle = %.1f FO4; slack in 65 nm ns at FO4 = %.1f ps; depth in FO4\n" \
               [to_fo4 [ns65 $TECH(PERIOD_NS)]] $TECH(TARGET_FO4_PS)]
   set detail {}
   set i 0
   while {$i < [llength $TIMING_PROBES]} {
      set label [lindex $TIMING_PROBES $i]
      if {[string match "* *" $label] || [string is upper [string index $label 0]]} {
         puts $f [format "\n%s\n%-20s %8s %7s %5s" $label probe slack_65 depth cells]
         incr i
         continue
      }
      set cmd [list get_timing_paths -delay_type max -max_paths 1]
      set missing ""
      foreach opt {-from -through -to} spec [lrange $TIMING_PROBES [expr {$i+1}] [expr {$i+3}]] {
         if {$spec eq ""} { continue }
         set col [eval $spec]
         if {[sizeof_collection $col] == 0} { set missing $opt; break }
         lappend cmd $opt $col
      }
      incr i 4
      if {$missing ne ""} { puts $f [format "%-20s   %s matches nothing" $label $missing]; continue }
      set paths [{*}$cmd]
      if {[sizeof_collection $paths] == 0} { puts $f [format "%-20s   no path" $label]; continue }
      array set d [timing_describe [index_collection $paths 0]]
      puts $f [format "%-20s %8.3f %7.1f %5d" $label [to65 $d(slack)] $d(depth) $d(cells)]
      lappend detail [format "%s\n  from %s\n  to   %s\n  %s\n" $label $d(from) $d(to) $d(trace)]
   }
   puts $f "\n\nWhere each probed path spends its time (FO4 per block):\n"
   foreach t $detail { puts $f $t }
   close $f
}
