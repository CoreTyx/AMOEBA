foreach dir $env(INCDIRS) {
    set_option incdir $dir
}
foreach def $env(LINT_DEFINES) {
    set_option define $def
}
read_file -type verilog $env(PKG_SRCS) $env(HDL_SRCS)
if {$env(SRAM_LIB) != ""} {
    set_option enable_gateslib_autocompile yes
    read_file -type gateslibdb $env(SRAM_LIB)
}
read_file -type awl $env(LINT_DIR)/lint.awl

set_option top $env(DESIGN_TOP)
set_option language_mode verilog
set_option enableSV09 yes
set_option enable_save_restore no
set_option mthresh 2000000000
set_option sgsyn_loop_limit 2000000000

current_goal Design_Read -top $env(DESIGN_TOP)

current_goal lint/lint_turbo_rtl -top $env(DESIGN_TOP)

set_parameter checkfullstruct true
# Without this, W123 skips the behavioral RAM arrays in generic/mem as too large.
set_parameter handle_large_bus yes

# Waivers live in lint.awl (read above).
run_goal
