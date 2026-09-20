// rvfi_tap.sv
//
// RVFI monitor taps for wallypipelinedcore, as a module of their own.
//
// This is the tap logic that used to live inline in rv64_core_wrapper.sv,
// moved out so that a DUT with the real ASIC top (amoeba_top) can be checked
// by the same monitor without the pipeline taps existing anywhere in the
// synthesizable hierarchy.  Every input is a signal read out of the core by
// hierarchical reference at the instantiation site; nothing here drives the
// core.  The body is verbatim from the wrapper: the M->W pipeline registers,
// the MDU stall stash, the interrupt-suppression bookkeeping and the FP
// register-file pipeline are unchanged, so the RVFI stream is bit-identical.
//
// Instantiate it once per DUT:
//   rv64_core_wrapper (legacy DUT)   connects soc.core.*
//   top_tb.svh, DUT=amoeba           connects dut.chip.soc.core.*
module rvfi_tap (
    input  logic        clk,
    input  logic        rst,

    // pipeline control
    input  logic        StallE, StallM, StallW,
    input  logic        FlushE, FlushM, FlushW,
    // fetch / decode
    input  logic        InstrValidM, InstrValidE, InstrValidD,
    input  logic [31:0] InstrRawD,
    input  logic [63:0] PCM, PCD, PCE,
    // traps
    input  logic        TrapM, RetM, InterruptM,
    input  logic [63:0] EPCM, TrapVectorM,
    input  logic [1:0]  PrivilegeModeW,
    // integer register file
    input  logic [4:0]  GPRAddr,
    input  logic        GPRWen,
    input  logic [63:0] GPRValue,
    input  logic [4:0]  Rs1D, Rs2D,
    input  logic [63:0] ForwardedSrcAE, ForwardedSrcBE,
    // memory
    input  logic [1:0]  MemRWM,
    input  logic [2:0]  Funct3M,
    input  logic [63:0] IEUAdrM, WriteDataM, ReadDataW,
`ifndef ECE411_NO_FLOAT
    // FP register file
    input  logic [4:0]  Frs1D_i, Frs2D_i, Frs3D_i,
    input  logic [63:0] Frs1DataD_i, Frs2DataD_i, Frs3DataD_i,
    input  logic        Frd_we4_i,
    input  logic [4:0]  Frd_a4_i,
    input  logic [63:0] Frd_wd4_i,
`endif

    output logic        monitor_valid,
    output logic [63:0] monitor_order,
    output logic [31:0] monitor_inst,
    output logic        monitor_trap,
    output logic        monitor_intr,
    output logic [1:0]  monitor_mode,
    output logic [1:0]  monitor_ixl,

    output logic [4:0]  monitor_rs1_addr,
    output logic [4:0]  monitor_rs2_addr,
    output logic [63:0] monitor_rs1_rdata,
    output logic [63:0] monitor_rs2_rdata,
    output logic [4:0]  monitor_rd_addr,
    output logic [63:0] monitor_rd_wdata,

`ifndef ECE411_NO_FLOAT
    output logic [5:0]  monitor_frs1_addr,
    output logic [5:0]  monitor_frs2_addr,
    output logic [5:0]  monitor_frs3_addr,
    output logic [63:0] monitor_frs1_rdata,
    output logic [63:0] monitor_frs2_rdata,
    output logic [63:0] monitor_frs3_rdata,
    output logic [5:0]  monitor_frd_addr,
    output logic [63:0] monitor_frd_wdata,
`endif

    output logic [63:0] monitor_pc_rdata,
    output logic [63:0] monitor_pc_wdata,
    output logic [63:0] monitor_mem_addr,
    output logic [7:0]  monitor_mem_rmask,
    output logic [7:0]  monitor_mem_wmask,
    output logic [63:0] monitor_mem_rdata,
    output logic [63:0] monitor_mem_wdata,
    output logic        monitor_mem_extamo
);

    // Fixed monitor outputs
    assign monitor_intr       = InterruptTakenPending & InstrValidW;
    assign monitor_mode       = PrivilegeModeW;
    assign monitor_ixl        = 2'b10;  // RV64 (XLEN=64)
    assign monitor_mem_extamo = 1'b0;   // no AMO

    logic [63:0] rvfi_order_ctr;
    always_ff @(posedge clk) begin
        if (rst) rvfi_order_ctr <= '0;
        else if (InstrValidW & ~StallW) rvfi_order_ctr <= rvfi_order_ctr + 1;
    end

    // Pipeline M→W registers
    logic        InstrValidW;
    logic [63:0] PCW;
    logic [31:0] InstrRawW;
    logic        TrapW;
    logic [1:0]  MemRWW;
    logic [2:0]  Funct3W;
    logic [63:0] IEUAdrW, WriteDataW;
    logic [4:0]  Rs1E, Rs2E, Rs1M, Rs2M, Rs1W, Rs2W;
    logic [63:0] Rs1DataM, Rs2DataM, Rs1DataW, Rs2DataW;
    // Stash for multi-cycle E-stage instructions (MDU divide/multiply).
    // StallM=0 during divide stall so ForwardedSrc*/WriteDataM change as the
    // previous instruction drains through M/W. Capture on the FIRST cycle of
    // E-stage stall when forwarding is still active, then hold until E→M.
    logic [63:0] Rs1DataE_stash, Rs2DataE_stash;
    logic        E_stash_valid;
    logic [31:0] InstrRawE_r, InstrRawM_r;
    // InterruptTakenPending: set when an external interrupt fires and its
    // interrupted instruction is suppressed from RVFI; cleared on the first
    // committed instruction of the interrupt handler (rvfi_intr=1 for it).
    logic        InterruptTakenPending;
    logic        IntrReported;
    assign IntrReported = InterruptTakenPending & InstrValidW & ~StallW;

    always_ff @(posedge clk) begin
        if (rst) begin
            InstrValidW <= '0; PCW <= '0; InstrRawW <= '0;
            InstrRawE_r <= '0; InstrRawM_r <= '0;
            TrapW <= '0; MemRWW <= '0; Funct3W <= '0;
            IEUAdrW <= '0; WriteDataW <= '0;
            Rs1E <= '0; Rs2E <= '0; Rs1M <= '0; Rs2M <= '0;
            Rs1W <= '0; Rs2W <= '0;
            Rs1DataM <= '0; Rs2DataM <= '0;
            Rs1DataW <= '0; Rs2DataW <= '0;
            Rs1DataE_stash <= '0; Rs2DataE_stash <= '0; E_stash_valid <= 0;
            InterruptTakenPending <= '0;
        end else begin
            // Clear intr pending when the first handler instruction is reported
            if (IntrReported) InterruptTakenPending <= '0;
            if (!StallE) InstrRawE_r <= FlushE ? '0 : InstrRawD;
            if (!StallM) InstrRawM_r <= FlushM ? '0 : InstrRawE_r;
            if (!StallW) begin
                if (TrapM & InterruptM) begin
                    // External interrupt: suppress the interrupted instruction (if any in M)
                    // and set pending so the first handler instruction gets rvfi_intr=1.
                    // No InstrValidM guard: interrupt can fire when M is a bubble; the
                    // suppress is harmless (InstrValidW becomes 0 either way) but
                    // InterruptTakenPending must be set regardless.
                    InstrValidW <= '0;
                    InterruptTakenPending <= '1;
                end else begin
                    InstrValidW <= (FlushW & ~TrapM) ? '0 : InstrValidM;
                end
                PCW         <= (FlushW & ~TrapM) ? '0 : PCM;
                InstrRawW   <= (FlushW & ~TrapM) ? '0 : InstrRawM_r;
                TrapW       <= TrapM & ~InterruptM;   // rvfi_trap only for exceptions
                MemRWW      <= FlushW ? '0 : MemRWM;
                Funct3W     <= Funct3M;
                IEUAdrW     <= IEUAdrM;
                WriteDataW  <= WriteDataM;
                Rs1W        <= Rs1M;
                Rs2W        <= Rs2M;
                Rs1DataW    <= Rs1DataM;
                Rs2DataW    <= Rs2DataM;
            end
            if (!StallE) begin
                Rs1E <= FlushE ? '0 : Rs1D;
                Rs2E <= FlushE ? '0 : Rs2D;
                // Non-stalling or advancing: reset stash; stale stash no longer relevant.
                E_stash_valid <= 0;
            end else if (FlushE) begin
                // E-stage instruction killed; clear stash.
                E_stash_valid <= 0;
            end else if (!E_stash_valid) begin
                // First cycle of E-stage stall (MDU busy): ForwardedSrcAE/BE are
                // correct here because R1E/R2E were loaded last cycle and the
                // previous instruction is still in M/W providing forwarded values.
                Rs1DataE_stash <= ForwardedSrcAE;
                Rs2DataE_stash <= ForwardedSrcBE;
                E_stash_valid  <= 1;
            end
            if (!StallM) begin
                Rs1M <= FlushM ? '0 : Rs1E;
                Rs2M <= FlushM ? '0 : Rs2E;
                // For stalled-E instructions (MDU), use the stash captured at first
                // stall cycle; for normal flow, capture ForwardedSrcAE/BE directly.
                if (E_stash_valid) begin
                    Rs1DataM <= FlushM ? '0 : Rs1DataE_stash;
                    Rs2DataM <= FlushM ? '0 : Rs2DataE_stash;
                end else begin
                    Rs1DataM <= FlushM ? '0 : ForwardedSrcAE;
                    Rs2DataM <= FlushM ? '0 : ForwardedSrcBE;
                end
            end
        end
    end

    function automatic logic [7:0] funct3_to_mask(input logic [2:0] funct3, input logic [2:0] offset);
        logic [7:0] m;
        m = '0;
        case (funct3[1:0])
            2'b00: m = 8'h01 << offset;
            2'b01: m = 8'h03 << {offset[2:1], 1'b0};
            2'b10: m = 8'h0F << {offset[2], 2'b0};
            2'b11: m = 8'hFF;
        endcase
        return m;
    endfunction

    assign monitor_valid      = InstrValidW & ~StallW & (|PCW);
    assign monitor_order      = rvfi_order_ctr;
    // For compressed instructions, only bits[15:0] are valid; zero-extend to 32 bits.
    assign monitor_inst       = (InstrRawW[1:0] != 2'b11) ? {16'h0000, InstrRawW[15:0]} : InstrRawW;
    assign monitor_trap       = TrapW;
    assign monitor_rs1_addr   = Rs1W;
    assign monitor_rs2_addr   = Rs2W;
    assign monitor_rs1_rdata  = Rs1DataW;
    assign monitor_rs2_rdata  = Rs2DataW;
    assign monitor_rd_addr    = GPRWen ? GPRAddr : '0;
    assign monitor_rd_wdata   = GPRWen ? GPRValue : '0;
    assign monitor_pc_rdata   = PCW;

    // Register RetM/TrapM and their associated target PCs at the M→W boundary.
    // mret and traps redirect the fetch immediately, so PCM/PCE are stale by the time
    // the instruction reaches W (pipeline bubbles fill the stages). Capture the authoritative
    // target (EPCM for mret, TrapVectorM for traps) while they are still valid in M.
    // For all other instructions the original W-stage lookahead (PCM/PCE/PCD) is correct
    // because the branch/jump target propagates into M/E by the time the instruction is in W.
    logic        RetW;
    logic [63:0] EPCW, TrapVectorW;
    always_ff @(posedge clk) begin
        if (rst) begin
            RetW <= '0; EPCW <= '0; TrapVectorW <= '0;
        end else if (!StallW) begin
            RetW        <= RetM;
            EPCW        <= EPCM;
            TrapVectorW <= TrapVectorM;
        end
    end

    logic [63:0] pc_wdata_seq;
    assign pc_wdata_seq = PCW + (InstrRawW[1:0] == 2'b11 ? 64'd4 : 64'd2);
    // Note: an interrupt taken in M must NOT redirect pc_wdata of the instruction
    // retiring in W. RVFI requires pc_wdata to be that instruction's architectural
    // next PC; the fetch discontinuity is expressed by rvfi_intr on the first handler
    // instruction (see InterruptTakenPending above), which rvfimon honors when
    // comparing the shadow PC against the next pc_rdata.
    assign monitor_pc_wdata = RetW                 ? EPCW        :   // mret/sret: return to saved EPC
                              TrapW                ? TrapVectorW :   // exception: jump to handler
                              InstrValidM          ? PCM         :   // normal: lookahead to M stage
                              InstrValidE          ? PCE         :
                              InstrValidD          ? PCD         :
                              pc_wdata_seq;

    assign monitor_mem_addr   = IEUAdrW & ~64'h7;
    assign monitor_mem_rmask  = MemRWW[1] ? funct3_to_mask(Funct3W, IEUAdrW[2:0]) : '0;
    assign monitor_mem_wmask  = MemRWW[0] ? funct3_to_mask(Funct3W, IEUAdrW[2:0]) : '0;
    assign monitor_mem_rdata  = ReadDataW << {IEUAdrW[2:0], 3'b0};
    assign monitor_mem_wdata  = WriteDataW;

    // -------------------------------------------------------------------------
    // FP register file tapping (D-stage reads pipelined to W-stage)
    // -------------------------------------------------------------------------
    `ifndef ECE411_NO_FLOAT
    // D-stage: fregfile reads are combinational from InstrD[19:15/24:20/31:27]
    logic [4:0]  Frs1D, Frs2D, Frs3D;
    logic [63:0] Frs1DataD, Frs2DataD, Frs3DataD;
    assign Frs1D     = Frs1D_i;
    assign Frs2D     = Frs2D_i;
    assign Frs3D     = Frs3D_i;
    assign Frs1DataD = Frs1DataD_i;
    assign Frs2DataD = Frs2DataD_i;
    assign Frs3DataD = Frs3DataD_i;

    // Pipeline D→E→M→W using same stall/flush as integer path
    logic [4:0]  Frs1E, Frs2E, Frs3E, Frs1M, Frs2M, Frs3M, Frs1W, Frs2W, Frs3W;
    logic [63:0] Frs1DataE, Frs2DataE, Frs3DataE;
    logic [63:0] Frs1DataM, Frs2DataM, Frs3DataM;
    logic [63:0] Frs1DataW, Frs2DataW, Frs3DataW;

    always_ff @(posedge clk) begin
        if (rst) begin
            Frs1E <= '0; Frs2E <= '0; Frs3E <= '0;
            Frs1M <= '0; Frs2M <= '0; Frs3M <= '0;
            Frs1W <= '0; Frs2W <= '0; Frs3W <= '0;
            Frs1DataE <= '0; Frs2DataE <= '0; Frs3DataE <= '0;
            Frs1DataM <= '0; Frs2DataM <= '0; Frs3DataM <= '0;
            Frs1DataW <= '0; Frs2DataW <= '0; Frs3DataW <= '0;
        end else begin
            if (!StallE) begin
                Frs1E     <= FlushE ? '0 : Frs1D;
                Frs2E     <= FlushE ? '0 : Frs2D;
                Frs3E     <= FlushE ? '0 : Frs3D;
                Frs1DataE <= FlushE ? '0 : Frs1DataD;
                Frs2DataE <= FlushE ? '0 : Frs2DataD;
                Frs3DataE <= FlushE ? '0 : Frs3DataD;
            end
            if (!StallM) begin
                Frs1M     <= FlushM ? '0 : Frs1E;
                Frs2M     <= FlushM ? '0 : Frs2E;
                Frs3M     <= FlushM ? '0 : Frs3E;
                Frs1DataM <= FlushM ? '0 : Frs1DataE;
                Frs2DataM <= FlushM ? '0 : Frs2DataE;
                Frs3DataM <= FlushM ? '0 : Frs3DataE;
            end
            if (!StallW) begin
                Frs1W     <= (FlushW & ~TrapM) ? '0 : Frs1M;
                Frs2W     <= (FlushW & ~TrapM) ? '0 : Frs2M;
                Frs3W     <= (FlushW & ~TrapM) ? '0 : Frs3M;
                Frs1DataW <= (FlushW & ~TrapM) ? '0 : Frs1DataM;
                Frs2DataW <= (FlushW & ~TrapM) ? '0 : Frs2DataM;
                Frs3DataW <= (FlushW & ~TrapM) ? '0 : Frs3DataM;
            end
        end
    end

    // W-stage FP write port (fregfile commits on negedge; we4/a4/wd4 are set by W-stage)
    assign monitor_frs1_addr  = {1'b0, Frs1W};
    assign monitor_frs2_addr  = {1'b0, Frs2W};
    assign monitor_frs3_addr  = {1'b0, Frs3W};
    assign monitor_frs1_rdata = Frs1DataW;
    assign monitor_frs2_rdata = Frs2DataW;
    assign monitor_frs3_rdata = Frs3DataW;
    assign monitor_frd_addr   = Frd_we4_i ? {1'b0, Frd_a4_i} : 6'b0;
    assign monitor_frd_wdata  = Frd_wd4_i;
`endif

endmodule
