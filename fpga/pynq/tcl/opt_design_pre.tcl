# Runs inside the impl_1 process, immediately before opt_design.
#
# WHY THIS FILE EXISTS.  opt_design ends with a "Power Optimization Task" that
# picks BRAM WRITE_MODE settings.  On this design that task aborts itself:
#
#   INFO:    [Pwropt 34-322] Received HACOOException
#   WARNING: [Pwropt 34-321] HACOOException: Too many TFIs and TFOs in design,
#            exiting pwropt.  You can change this limit with the param
#            pwropt.maxFaninFanoutToNetRatio
#
# and then Vivado 2024.1 segfaults tearing down the half-built BDD manager
# (Cudd_RecursiveDeref, via ~HACOOPwrOptMgr).  The whole impl run dies with
# "Abnormal program termination (11)".  It is a tool bug on the bail-out path,
# not a fault in the design -- so the fix is to not take that path.
#
# The default ratio is 1000.  Raising it lets the task run to completion
# normally, which is the only exit from pwroptMain that does not go through the
# broken cleanup.  Power optimisation of a handful of BRAMs is worth nothing to
# us either way; what we need is for it to stop crashing the build.
#
# Reached this file because the build died in opt_design again?  The bigger
# hammer is to skip the step outright, in build.tcl:
#     set_property STEPS.OPT_DESIGN.IS_ENABLED false [get_runs impl_1]
# We have ~0.5 ns of slack at 30 MHz, so losing opt_design's QoR is survivable.
set_param pwropt.maxFaninFanoutToNetRatio 1000000000
