source dc_warn.tcl

set hdlin_ff_always_sync_set_reset true
set hdlin_ff_always_async_set_reset true
set hdlin_infer_multibit default_all
set hdlin_check_no_latch true
set hdlin_auto_save_templates true
# set power_enable_minpower true
set_host_options -max_cores 4
set_app_var report_default_significant_digits 6
set design_toplevel forte_top

get_license DC-Ultra-Features
get_license DC-Ultra-Opt

set SynopsysInstall [getenv "DCROOT"]
set search_path [list . \
[format "%s%s" $SynopsysInstall /libraries/syn] \
[format "%s%s" $SynopsysInstall /dw/sim_ver] \
]

set symbol_library [list generic.sdb]
set synthetic_library [list dw_foundation.sldb]

define_design_lib WORK -path ./work

define_name_rules nameRules -restricted "!@#$%^&*()\\-" -case_insensitive

set cell_path [getenv TSMC_DB_DIR]
set search_path [concat $search_path $cell_path]

set alib_library_analysis_path ./

set verilogout_show_unconnected_pins "true"

set target_library [format "%s" [getenv TSMC_DB_FAST]]

set sram_library_44 [getenv SRAM_DB_FAST_44]
set sram_library_128 [getenv SRAM_DB_FAST_128]
set sram_library_68 [getenv SRAM_DB_FAST_68]
set sram_library_32_45 [getenv SRAM_DB_FAST_32_45]
set sram_library_32_128 [getenv SRAM_DB_FAST_32_128]
set sram_library_16_46 [getenv SRAM_DB_FAST_16_46]
set sram_library_16_128 [getenv SRAM_DB_FAST_16_128]
set sram_library_64_46 [getenv SRAM_DB_FAST_64_46]
set sram_library_64_53 [getenv SRAM_DB_FAST_64_53]
set sram_library_64_137 [getenv SRAM_DB_FAST_64_137]

set sram_library_256_53 [getenv SRAM_DB_FAST_256_53]
set sram_library_256_137 [getenv SRAM_DB_FAST_256_137]
set sram_library_128_53 [getenv SRAM_DB_FAST_128_53]
set sram_library_128_137 [getenv SRAM_DB_FAST_128_137]


set link_library [list "*" \
    [concat "*" $target_library $synthetic_library $sram_library_44] \
    [concat "*" $target_library $synthetic_library $sram_library_128] \
    [concat "*" $target_library $synthetic_library $sram_library_68] \
    [concat "*" $target_library $synthetic_library $sram_library_32_45] \
    [concat "*" $target_library $synthetic_library $sram_library_32_128] \
    [concat "*" $target_library $synthetic_library $sram_library_16_46] \
    [concat "*" $target_library $synthetic_library $sram_library_16_128] \
    [concat "*" $target_library $synthetic_library $sram_library_64_46] \
    [concat "*" $target_library $synthetic_library $sram_library_64_53] \
    [concat "*" $target_library $synthetic_library $sram_library_64_137] \
    [concat "*" $target_library $synthetic_library $sram_library_256_53] \
    [concat "*" $target_library $synthetic_library $sram_library_256_137] \
    [concat "*" $target_library $synthetic_library $sram_library_128_53] \
    [concat "*" $target_library $synthetic_library $sram_library_128_137]]

# ------------------------------------------------------------
# Config Files
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/cvw.sv
analyze -library WORK -format sverilog ../hdl/forte_link_pkg.sv
#analyze -library WORK -format sverilog ../pkg/types.sv

# ------------------------------------------------------------
# Async FIFOs
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/prim_assert.sv
analyze -library WORK -format sverilog ../hdl/prim_fifo_async.sv
analyze -library WORK -format sverilog ../hdl/prim_flop_2sync.sv

# ------------------------------------------------------------
# IO Drivers
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../io_drivers/io_in.sv
analyze -library WORK -format sverilog ../io_drivers/io_out.sv
analyze -library WORK -format sverilog ../io_drivers/io_tri.sv

# ------------------------------------------------------------
# Behavorial SRAM Models
# ------------------------------------------------------------

#analyze -library WORK -format sverilog ../SRAM/rf_sp_64_44.v
#analyze -library WORK -format sverilog ../SRAM/rf_sp_64_128.v
#analyze -library WORK -format sverilog ../SRAM/sram_dp_1024_68.v
#analyze -library WORK -format sverilog ../SRAM/rf_sp_32_45.v
#analyze -library WORK -format sverilog ../SRAM/rf_sp_32_128.v
#analyze -library WORK -format sverilog ../SRAM/rf_sp_16_46.v
#analyze -library WORK -format sverilog ../SRAM/rf_sp_16_128.v
#analyze -library WORK -format sverilog ../SRAM/rf_sp_64_46.v
#analyze -library WORK -format sverilog ../SRAM/rf_sp_64_53.v
#analyze -library WORK -format sverilog ../SRAM/rf_sp_64_137.v
#analyze -library WORK -format sverilog ../SRAM/sram_sp_256_53.v
#analyze -library WORK -format sverilog ../SRAM/sram_sp_256_137.v
#analyze -library WORK -format sverilog ../SRAM/sram_sp_128_53.v
#analyze -library WORK -format sverilog ../SRAM/sram_sp_128_137.v

# ------------------------------------------------------------
# Generic - basic combinational/sequential primitives
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/generic/adder.sv
analyze -library WORK -format sverilog ../hdl/core/generic/addsub.sv
analyze -library WORK -format sverilog ../hdl/core/generic/aplusbeq0.sv
analyze -library WORK -format sverilog ../hdl/core/generic/arrs.sv
analyze -library WORK -format sverilog ../hdl/core/generic/binencoder.sv
analyze -library WORK -format sverilog ../hdl/core/generic/counter.sv
analyze -library WORK -format sverilog ../hdl/core/generic/csa.sv
analyze -library WORK -format sverilog ../hdl/core/generic/decoder.sv
analyze -library WORK -format sverilog ../hdl/core/generic/lzc.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mux.sv
analyze -library WORK -format sverilog ../hdl/core/generic/neg.sv
analyze -library WORK -format sverilog ../hdl/core/generic/onehotdecoder.sv
analyze -library WORK -format sverilog ../hdl/core/generic/or_rows.sv
analyze -library WORK -format sverilog ../hdl/core/generic/lessthan.sv
analyze -library WORK -format sverilog ../hdl/core/generic/lowones.sv
analyze -library WORK -format sverilog ../hdl/core/generic/priorityonehot.sv
analyze -library WORK -format sverilog ../hdl/core/generic/prioritythermometer.sv

# ------------------------------------------------------------
# Generic - ECC
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/generic/ecc/ecc_bit_flip.sv
analyze -library WORK -format sverilog ../hdl/core/generic/ecc/ecc_dected_dec.sv
analyze -library WORK -format sverilog ../hdl/core/generic/ecc/ecc_dected_enc.sv
analyze -library WORK -format sverilog ../hdl/core/generic/ecc/ecc_secded_dec.sv
analyze -library WORK -format sverilog ../hdl/core/generic/ecc/ecc_secded_enc.sv
analyze -library WORK -format sverilog ../hdl/core/generic/ecc/ecc_flip_mask.sv 

# ------------------------------------------------------------
# Generic - flop
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/generic/flop/flop.sv
analyze -library WORK -format sverilog ../hdl/core/generic/flop/flopen.sv
analyze -library WORK -format sverilog ../hdl/core/generic/flop/flopenl.sv
analyze -library WORK -format sverilog ../hdl/core/generic/flop/flopenr.sv
analyze -library WORK -format sverilog ../hdl/core/generic/flop/flopenrc.sv
analyze -library WORK -format sverilog ../hdl/core/generic/flop/flopenrc_ecc.sv
analyze -library WORK -format sverilog ../hdl/core/generic/flop/flopr.sv
analyze -library WORK -format sverilog ../hdl/core/generic/flop/flopenrc_cw.sv
analyze -library WORK -format sverilog ../hdl/core/generic/flop/synchronizer.sv

# ------------------------------------------------------------
# Generic - memories
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram1p1rwbe.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram1p1rwbe_64x128.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram1p1rwbe_64x22.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram1p1rwbe_64x44.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram1p1rwbe_32x45.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram1p1rwbe_32x128.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram1p1rwbe_16x46.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram1p1rwbe_16x128.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram1p1rwbe_64x46.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram1p1rwbe_64x137.sv 
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram1p1rwbe_64x53.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram1p1rwbe_256x53.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram1p1rwbe_256x137.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram1p1rwbe_128x53.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram1p1rwbe_128x137.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram1p1rwe.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram2p1r1wbe.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram2p1r1wbe_1024x36.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram2p1r1wbe_1024x68.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram2p1r1wbe_128x64.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram2p1r1wbe_2048x64.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/ram2p1r1wbe_64x32.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/rom1p1r.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/rom1p1r_128x32.sv
analyze -library WORK -format sverilog ../hdl/core/generic/mem/rom1p1r_128x64.sv

# ------------------------------------------------------------
# Integer execution unit - BMU
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/ieu/bmu/bitreverse.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/bmu/byteop.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/bmu/clmul.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/bmu/cnt.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/bmu/ext.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/bmu/popcnt.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/bmu/zbb.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/bmu/zbc.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/bmu/bmuctrl.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/bmu/bitmanipalu.sv

# ------------------------------------------------------------
# Integer execution unit - AES
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/ieu/aes/galoismultforward8.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/aes/galoismultinverse8.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/aes/aessbox8.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/aes/aesinvsbox8.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/aes/aesmixcolumns8.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/aes/aesinvmixcolumns8.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/aes/aessbox32.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/aes/aesinvsbox64.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/aes/aesshiftrows64.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/aes/aesinvshiftrows64.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/aes/aesmixcolumns32.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/aes/aesinvmixcolumns32.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/aes/aes32e.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/aes/aes32d.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/aes/aes64e.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/aes/aes64d.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/aes/aes64ks1i.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/aes/aes64ks2.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/aes/rconlut32.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/aes/rotate.sv

# ------------------------------------------------------------
# Integer execution unit - KMU
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/ieu/kmu/packer.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/kmu/zipper.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/kmu/zbkb.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/kmu/zbkx.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/kmu/zknde32.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/kmu/zknde64.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/kmu/zknh32.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/kmu/zknh64.sv

# ------------------------------------------------------------
# Integer execution unit - SHA
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/ieu/sha/sha256.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/sha/sha512_32.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/sha/sha512_64.sv

# ------------------------------------------------------------
# Integer execution unit
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/ieu/dummymask.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/regfile.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/extend.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/comparator.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/alu.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/shifter.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/controller.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/datapath.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/dummygen.sv
analyze -library WORK -format sverilog ../hdl/core/ieu/ieu.sv

# ------------------------------------------------------------
# Multiply / Divide unit
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/mdu/divstep.sv
analyze -library WORK -format sverilog ../hdl/core/mdu/div.sv
analyze -library WORK -format sverilog ../hdl/core/mdu/mul.sv
analyze -library WORK -format sverilog ../hdl/core/mdu/mdu.sv

# ------------------------------------------------------------
# Instruction fetch / branch prediction
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/ifu/bpred/satCounter2.sv
analyze -library WORK -format sverilog ../hdl/core/ifu/bpred/twoBitPredictor.sv
analyze -library WORK -format sverilog ../hdl/core/ifu/bpred/gsharebasic.sv
analyze -library WORK -format sverilog ../hdl/core/ifu/bpred/localbpbasic.sv
analyze -library WORK -format sverilog ../hdl/core/ifu/bpred/localaheadbp.sv
analyze -library WORK -format sverilog ../hdl/core/ifu/bpred/localrepairbp.sv
analyze -library WORK -format sverilog ../hdl/core/ifu/bpred/gshare.sv
analyze -library WORK -format sverilog ../hdl/core/ifu/bpred/icpred.sv
analyze -library WORK -format sverilog ../hdl/core/ifu/bpred/RASPredictor.sv
analyze -library WORK -format sverilog ../hdl/core/ifu/bpred/btb.sv
analyze -library WORK -format sverilog ../hdl/core/ifu/bpred/bpred.sv

analyze -library WORK -format sverilog ../hdl/core/ifu/decompress.sv
analyze -library WORK -format sverilog ../hdl/core/ifu/irom.sv
analyze -library WORK -format sverilog ../hdl/core/ifu/spill.sv
analyze -library WORK -format sverilog ../hdl/core/ifu/ifu.sv

# ------------------------------------------------------------
# MMU / TLB
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/mmu/tlb/tlbcamline.sv
analyze -library WORK -format sverilog ../hdl/core/mmu/tlb/tlbcam.sv
analyze -library WORK -format sverilog ../hdl/core/mmu/tlb/tlblru.sv
analyze -library WORK -format sverilog ../hdl/core/mmu/tlb/tlbmixer.sv
analyze -library WORK -format sverilog ../hdl/core/mmu/tlb/tlbramline.sv
analyze -library WORK -format sverilog ../hdl/core/mmu/tlb/tlbram.sv
analyze -library WORK -format sverilog ../hdl/core/mmu/tlb/tlbcontrol.sv
analyze -library WORK -format sverilog ../hdl/core/mmu/tlb/vm64check.sv
analyze -library WORK -format sverilog ../hdl/core/mmu/tlb/tlb.sv

analyze -library WORK -format sverilog ../hdl/core/mmu/adrdec.sv
analyze -library WORK -format sverilog ../hdl/core/mmu/adrdecs.sv
analyze -library WORK -format sverilog ../hdl/core/mmu/pmpadrdec.sv
analyze -library WORK -format sverilog ../hdl/core/mmu/pmpchecker.sv
analyze -library WORK -format sverilog ../hdl/core/mmu/pmachecker.sv
analyze -library WORK -format sverilog ../hdl/core/mmu/hptw.sv
analyze -library WORK -format sverilog ../hdl/core/mmu/mmu.sv

# ------------------------------------------------------------
# Privileged architecture / CSR
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/privileged/csrc.sv
analyze -library WORK -format sverilog ../hdl/core/privileged/csri.sv
analyze -library WORK -format sverilog ../hdl/core/privileged/csrm.sv
analyze -library WORK -format sverilog ../hdl/core/privileged/csrs.sv
analyze -library WORK -format sverilog ../hdl/core/privileged/csrsr.sv
analyze -library WORK -format sverilog ../hdl/core/privileged/csru.sv
analyze -library WORK -format sverilog ../hdl/core/privileged/csrharden.sv
analyze -library WORK -format sverilog ../hdl/core/privileged/csr.sv
analyze -library WORK -format sverilog ../hdl/core/privileged/privmode.sv
analyze -library WORK -format sverilog ../hdl/core/privileged/privdec.sv
analyze -library WORK -format sverilog ../hdl/core/privileged/privpiperegs.sv
analyze -library WORK -format sverilog ../hdl/core/privileged/trap.sv
analyze -library WORK -format sverilog ../hdl/core/privileged/privileged.sv

# ------------------------------------------------------------
# LSU
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/lsu/endianswap.sv
analyze -library WORK -format sverilog ../hdl/core/lsu/subwordread.sv
analyze -library WORK -format sverilog ../hdl/core/lsu/subwordwrite.sv
analyze -library WORK -format sverilog ../hdl/core/lsu/swbytemask.sv
analyze -library WORK -format sverilog ../hdl/core/lsu/align.sv
analyze -library WORK -format sverilog ../hdl/core/lsu/amoalu.sv
analyze -library WORK -format sverilog ../hdl/core/lsu/lrsc.sv
analyze -library WORK -format sverilog ../hdl/core/lsu/atomic.sv
analyze -library WORK -format sverilog ../hdl/core/lsu/dtim.sv
analyze -library WORK -format sverilog ../hdl/core/lsu/lsu.sv

# ------------------------------------------------------------
# Cache
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/cache/cacheeccbits.sv
analyze -library WORK -format sverilog ../hdl/core/cache/cacheeccdec.sv
analyze -library WORK -format sverilog ../hdl/core/cache/cacheeccenc.sv
analyze -library WORK -format sverilog ../hdl/core/cache/cachescrubber.sv
analyze -library WORK -format sverilog ../hdl/core/cache/cacheLRU.sv
analyze -library WORK -format sverilog ../hdl/core/cache/subcachelineread.sv
analyze -library WORK -format sverilog ../hdl/core/cache/cacheway.sv
analyze -library WORK -format sverilog ../hdl/core/cache/cachefsm.sv
analyze -library WORK -format sverilog ../hdl/core/cache/cache.sv
analyze -library WORK -format sverilog ../hdl/core/cache/cachefi.sv
analyze -library WORK -format sverilog ../hdl/core/cache/cachearray.sv

# ------------------------------------------------------------
# EBU / AHB
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/ebu/controllerinput.sv
analyze -library WORK -format sverilog ../hdl/core/ebu/ahbinterface.sv
analyze -library WORK -format sverilog ../hdl/core/ebu/ahbcacheinterface.sv
analyze -library WORK -format sverilog ../hdl/core/ebu/busfsm.sv
analyze -library WORK -format sverilog ../hdl/core/ebu/buscachefsm.sv
analyze -library WORK -format sverilog ../hdl/core/ebu/ebufsmarb.sv
analyze -library WORK -format sverilog ../hdl/core/ebu/ebu.sv

# ------------------------------------------------------------
# Hazard
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/hazard/hazard.sv

# ------------------------------------------------------------
# FPU - FMA
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/fpu/fma/fmasign.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fma/fmamult.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fma/fmalza.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fma/fmaalign.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fma/fmaexpadd.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fma/fmaadd.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fma/fma.sv

# ------------------------------------------------------------
# FPU - Divide / Square Root
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/fpu/fdivsqrt/fdivsqrtcycles.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fdivsqrt/fdivsqrtexpcalc.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fdivsqrt/fdivsqrtfgen2.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fdivsqrt/fdivsqrtfgen4.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fdivsqrt/fdivsqrtuslc2.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fdivsqrt/fdivsqrtuslc4.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fdivsqrt/fdivsqrtuslc4cmp.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fdivsqrt/fdivsqrtuotfc2.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fdivsqrt/fdivsqrtuotfc4.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fdivsqrt/fdivsqrtstage2.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fdivsqrt/fdivsqrtstage4.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fdivsqrt/fdivsqrtiter.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fdivsqrt/fdivsqrtpreproc.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fdivsqrt/fdivsqrtpostproc.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fdivsqrt/fdivsqrtfsm.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fdivsqrt/fdivsqrt.sv

# ------------------------------------------------------------
# FPU - Postprocessing
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/fpu/postproc/cvtshiftcalc.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/postproc/divshiftcalc.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/postproc/fmashiftcalc.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/postproc/negateintres.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/postproc/normshift.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/postproc/resultsign.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/postproc/roundsign.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/postproc/round.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/postproc/shiftcorrection.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/postproc/specialcase.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/postproc/flags.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/postproc/postprocess.sv

# ------------------------------------------------------------
# FPU - main units
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/fpu/fmtparams.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/unpackinput.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/unpack.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fround.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fclassify.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fcmp.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fsgninj.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fli.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fcvt.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fregfile.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fctrl.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fhazard.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/packoutput.sv
analyze -library WORK -format sverilog ../hdl/core/fpu/fpu.sv

# ------------------------------------------------------------
# Fault-Tolerant Shadow Logic
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/ft_shadow/ft_alu.sv
analyze -library WORK -format sverilog ../hdl/core/ft_shadow/ft_div.sv
analyze -library WORK -format sverilog ../hdl/core/ft_shadow/ft_fault_inject.sv
analyze -library WORK -format sverilog ../hdl/core/ft_shadow/ft_mul.sv
analyze -library WORK -format sverilog ../hdl/core/ft_shadow/ft_shadow_ctrl.sv
analyze -library WORK -format sverilog ../hdl/core/ft_shadow/ft_fault_gen.sv
analyze -library WORK -format sverilog ../hdl/core/ft_shadow/residue15.sv

# ------------------------------------------------------------
# RVVI
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/rvvi/csrindextoaddr.sv
analyze -library WORK -format sverilog ../hdl/core/rvvi/priorityaomux.sv
analyze -library WORK -format sverilog ../hdl/core/rvvi/regchangedetect.sv
analyze -library WORK -format sverilog ../hdl/core/rvvi/packetizer.sv
analyze -library WORK -format sverilog ../hdl/core/rvvi/triggergen.sv
analyze -library WORK -format sverilog ../hdl/core/rvvi/rvvisynth.sv

# ------------------------------------------------------------
# Uncore
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/uncore/spi_fifo.sv
analyze -library WORK -format sverilog ../hdl/core/uncore/spi_controller.sv
analyze -library WORK -format sverilog ../hdl/core/uncore/uartPC16550D.sv
analyze -library WORK -format sverilog ../hdl/core/uncore/uart_apb.sv
analyze -library WORK -format sverilog ../hdl/core/uncore/clint_apb.sv
analyze -library WORK -format sverilog ../hdl/core/uncore/gpio_apb.sv
analyze -library WORK -format sverilog ../hdl/core/uncore/plic_apb.sv
analyze -library WORK -format sverilog ../hdl/core/uncore/spi_apb.sv
analyze -library WORK -format sverilog ../hdl/core/uncore/trickbox_apb.sv
analyze -library WORK -format sverilog ../hdl/core/uncore/fault_inject_apb.sv
analyze -library WORK -format sverilog ../hdl/core/uncore/ahbapbbridge.sv
analyze -library WORK -format sverilog ../hdl/core/uncore/ram_ahb.sv
analyze -library WORK -format sverilog ../hdl/core/uncore/rom_ahb.sv
analyze -library WORK -format sverilog ../hdl/core/uncore/uncore.sv
analyze -library WORK -format sverilog ../hdl/core/uncore/faultcount_apb.sv

# ------------------------------------------------------------
# Wally core / SoC
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/core/wally/wallypipelinedcore.sv
analyze -library WORK -format sverilog ../hdl/core/wally/wallypipelinedsoc.sv

# ------------------------------------------------------------
# Top-level AHB interface
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/ahb_to_memitf.sv

# ------------------------------------------------------------
# Top-level
# ------------------------------------------------------------

analyze -library WORK -format sverilog ../hdl/forte_dft_lock.sv
analyze -library WORK -format sverilog ../hdl/forte_link_core.sv
analyze -library WORK -format sverilog ../hdl/forte_link_phy.sv
analyze -library WORK -format sverilog ../hdl/forte_rst_sync.sv
analyze -library WORK -format sverilog ../hdl/forte_uncore.sv
analyze -library WORK -format sverilog ../hdl/forte_soc.sv
analyze -library WORK -format sverilog ../hdl/forte_chip.sv
analyze -library WORK -format sverilog ../hdl/forte_top.sv

elaborate $design_toplevel
current_design $design_toplevel

set_wire_load_model -name tsmc65_wl10

create_clock -period 4 -name sdc_top_clk core_clk
set_clock_uncertainty 0.3 sdc_top_clk

set_fix_hold sdc_top_clk

#Inputs
#add core_clk?
set inputs [get_ports {rst_n ready rvalid uart_rx test_mode scan_en fault_inject irq[1] irq[0]}]

# Inouts
set inout [get_ports {io[15] io[14] io[13] io[12] io[11] io[10] io[9] io[8] io[7] io[6] io[5] io[4] io[3] io[2] io[1] io[0]}]

# Outputs
set outputs [get_ports {dir req clk_out wr uart_tx status}]


group_path -name INREG  -from $inputs
group_path -name OUTREG -to   $outputs
group_path -name IOREG_IN  -from $inout
group_path -name IOREG_OUT -to   $inout

# Apply input delays to data inputs and bidirectional pins.
set_input_delay -clock sdc_top_clk -min 0.4 \ [add_to_collection $inputs $inout]
set_input_delay -clock sdc_top_clk -max 1.5 \ [add_to_collection $inputs $inout]

# Output delays for output pins and bidirectional pins.
set_output_delay -clock sdc_top_clk -min 1.5 \ [add_to_collection $outputs $inout]
set_output_delay -clock sdc_top_clk -max 1.5 \ [add_to_collection $outputs $inout]

set_false_path -from [get_clocks sdc_top_clk] -to [get_ports clk_out]

set_max_transition 3 $inputs
set_max_transition 3 $inout
set_max_transition 3 $outputs

set_load -pin_load 2 [add_to_collection $inout $outputs]

link

# Select scan registers and preserve the three control nets before mapping.
source dft_setup_full.tcl
compile_ultra -scan -gate_clock -retime

change_names -rules verilog -hierarchy
change_names -rules nameRules -hierarchy

# CHANGED: moved dir variables up and create output dirs (redirects fail if a dir is missing)
set report_dir  [getenv REPORT_DIR]
set syn_out_dir [getenv SYN_OUT_DIR]
file mkdir $report_dir/pre_dft
file mkdir $report_dir/scan_mode
file mkdir $syn_out_dir

# CHANGED: duplicated report blocks replaced by one proc, called with the output dir
proc gate_reports {dir} {
  global design_toplevel
  set p "$dir/$design_toplevel.gate"
  report_area                      > "${p}.area.rpt"
  report_area -hier                > "${p}.area_hierarchical.rpt"
  report_timing -delay max         > "${p}.setup.rpt"
  report_timing -delay min         > "${p}.hold.rpt"
  report_timing -max_path 50       > "${p}.timing.rpt"
  report_timing_requirement        > "${p}.timing_req.rpt"
  report_constraint                > "${p}.constraint.rpt"
  report_attribute                 > "${p}.attribute.rpt"
  report_constraint -all_violators > "${p}.viol.rpt"
  check_design                     > "${p}.check.rpt"
  report_hierarchy                 > "${p}.hierarchy.rpt"
  report_resources                 > "${p}.resources.rpt"
  report_reference                 > "${p}.reference.rpt"
  report_cell                      > "${p}.cell.rpt"
  report_power -verbose            > "${p}.power.rpt"
}

gate_reports $report_dir/pre_dft

# Bind the preserved control nets to their final mapped pins. Precompile RTL
# pin names are not stable through mapping, even when the net is dont_touch.
foreach net_name {dft_unlocked scan_en_dft test_mode_dft} {
  set control_net [get_nets chip/$net_name]
  if {[sizeof_collection $control_net] != 1} {
    error "DFT: expected one preserved net chip/$net_name; found [sizeof_collection $control_net]"
  }
  set control_drv [get_pins -leaf -of_objects $control_net -filter "direction==out"]
  if {[sizeof_collection $control_drv] != 1} {
    error "DFT: $net_name requires exactly one mapped driver; found [sizeof_collection $control_drv]"
  }
  puts "DFT hookup: $net_name -> [get_object_name $control_drv]"
  switch -- $net_name {
    dft_unlocked {
      # Analysis assumption only; hardware still requires clocked reset/unlock.
      set_dft_signal -view existing_dft -type Constant \
        -hookup_pin $control_drv -active_state 1
    }
    scan_en_dft {
      set_dft_signal -view spec -type ScanEnable -port scan_en \
        -hookup_pin $control_drv -active_state 1
    }
    test_mode_dft {
      set_dft_signal -view spec -type TestMode -port test_mode \
        -hookup_pin $control_drv -active_state 1
    }
  }
}
# Insertion may now add loads and optimize the mapped control distribution.
set_dont_touch [get_nets {chip/scan_en_dft chip/test_mode_dft chip/dft_unlocked}] false

# Immutable pre-insertion checkpoint for subsequent make dft iterations.
# DDC retains the DFT signal definitions and scan-element attributes; ordinary
# Tcl variables/collection handles are deliberately not used by dft_insert.tcl.
file mkdir synout
write -format ddc -hierarchy -output synout/forte_top.pre_dft.ddc
set dft_standalone false
source dft_insert_full.tcl


# CHANGED: case analysis scoped to the functional-mode reports and removed afterward
set scan_ports [get_ports {test_mode scan_en}]
set_case_analysis 0 $scan_ports

gate_reports $report_dir
remove_case_analysis $scan_ports

# CHANGED: new scan shift-mode timing reports (scan_en=1, test_mode=1)
set_case_analysis 1 $scan_ports
set p "$report_dir/scan_mode/$design_toplevel.gate"
report_timing -delay max         > "${p}.setup.rpt"
report_timing -delay min         > "${p}.hold.rpt"
report_constraint -all_violators > "${p}.viol.rpt"
remove_case_analysis $scan_ports

write_sdf $syn_out_dir/$design_toplevel.gate.sdf
write_sdc $syn_out_dir/$design_toplevel.gate.sdc

write -format verilog -hierarchy -output $syn_out_dir/$design_toplevel.gate.v
write -format ddc -hierarchy -output $syn_out_dir/$design_toplevel.gate.ddc


# CHANGED: file list built with globs so pre_dft/scan_mode reports and the checkpoint are included
set output_files [concat \
    [glob -nocomplain $report_dir/*.rpt] \
    [glob -nocomplain $report_dir/pre_dft/*.rpt] \
    [glob -nocomplain $report_dir/scan_mode/*.rpt] \
    [glob -nocomplain $syn_out_dir/$design_toplevel.gate.*] \
    [list synout/forte_top.pre_dft.ddc]]

foreach f $output_files {
    if {[file exists $f]} {
        if {[catch {exec chmod 777 $f} err]} {
            puts "ERROR: chmod failed for $f: $err"
        } else {
            puts "Permissions updated: $f"
        }
    } else {
        puts "WARNING: Output file does not exist: $f"
    }
}

# CHANGED: start_gui removed (hangs or fails in batch runs)
exit