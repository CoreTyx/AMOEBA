## PYNQ-Z2 LEDs for DUT=forte (forte_pynq_top.sv):
##   LD0 status pin, LD1 chip released, LD2 tohost seen, LD3 link error or boot gate gave up
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_false_path -to [get_ports {led[*]}]
