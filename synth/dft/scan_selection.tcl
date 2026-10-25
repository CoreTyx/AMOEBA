# Initial RTL-hierarchy policy, not a claim about mapped register counts.
# Return the first area tier that includes a register; 0 means never selected.
# Match against all_registers cell names, not whole datapath instances.
proc dft_first_tier {name} {
    foreach pattern {
        */dftlock/* */rstsync/* */linkrstsync/* */scan_q_reg*
        */dft_control/* */dft_scan/* */mbist/*
        */sramIP */sramIP/*
    } {
        if {[string match $pattern $name]} { return 0 }
    }
    foreach pattern {
        */soc/core/ieu/c/*
        */soc/core/ifu/pcreg/*
        */soc/core/priv/privmode/*
        */soc/core/priv/csr/csrsr/*
        */soc/core/priv/csr/csri/*
        */soc/core/priv/csr/csrm/*MTVECreg/*
        */soc/core/priv/csr/csrm/*MEPCreg/*
        */soc/core/priv/csr/csrm/*MCAUSEreg/*
        */soc/core/priv/csr/csrm/*MEDELEGreg/*
        */soc/core/priv/csr/csrm/*MIDELEGreg/*
        */soc/core/priv/csr/csrm/*PMPADDRreg/*
        */soc/core/priv/csr/csrm/*PMPCFGreg/*
        */soc/core/priv/csr/*csrs/*STVECreg/*
        */soc/core/priv/csr/*csrs/*SEPCreg/*
        */soc/core/priv/csr/*csrs/*SATPreg/*
    } {
        if {[string match $pattern $name]} { return 1 }
    }
    foreach pattern {
        */soc/core/ifu/*Instr*Reg/* */soc/core/ifu/*Flop/*
        */soc/core/ifu/*PC*Reg/* */soc/core/ifu/*PC*reg/*
        */soc/core/ieu/dp/RD1EReg/* */soc/core/ieu/dp/RD2EReg/*
        */soc/core/ieu/dp/ImmExtEReg/* */soc/core/ieu/dp/SrcAMReg/*
        */soc/core/ieu/dp/IEUResultMReg/* */soc/core/ieu/dp/WriteDataMReg/*
        */soc/core/ieu/dp/IFResultWReg/*
        */soc/core/priv/csr/csrm/* */soc/core/priv/csr/*csrs/*
    } {
        if {[string match $pattern $name]} { return 2 }
    }
    # Tier 3 has the SAME scan population as tier 2. Its extra feature is MBIST RTL.
    # Tier 4 is a full-core candidate, not automatically full-chip scan.
    if {[string match */soc/core/* $name]} { return 4 }
    return 0
}
