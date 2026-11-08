# write_funcsim.tcl -- a synthesis checkpoint as a functional-simulation
# netlist (UNISIM primitives), for the netlist benches.
#
#   vivado -mode batch -source write_funcsim.tcl -tclargs <in.dcp> <out.v>
lassign $argv dcp out
open_checkpoint $dcp
write_verilog -force -mode funcsim $out
puts "funcsim: $out (top [get_property TOP [current_design]])"
