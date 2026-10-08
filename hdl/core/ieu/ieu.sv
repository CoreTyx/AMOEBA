///////////////////////////////////////////
// ieu.sv
//
// Written: David_Harris@hmc.edu 9 January 2021
// Modified:
//
// Purpose: Integer Execution Unit: datapath and controller
//
// Documentation: RISC-V System on Chip Design
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// https://github.com/openhwgroup/cvw
//
// Copyright (C) 2021-23 Harvey Mudd College & Oklahoma State University
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the “License”); you may not use this file
// except in compliance with the License, or, at your option, the Apache License version 2.0. You
// may obtain a copy of the License at
//
// https://solderpad.org/licenses/SHL-2.1/
//
// Unless required by applicable law or agreed to in writing, any work distributed under the
// License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions
// and limitations under the License.
////////////////////////////////////////////////////////////////////////////////////////////////

module ieu import cvw::*;  #(parameter cvw_t P) (
  input  logic              clk, reset,
  // ECC inject enable (from top-level, for DFT)
  input  logic              ecc_inject_en,
  // ECC error aggregation outputs (correctable / uncorrectable)
  output logic              RegEccSecErrW,
  output logic              RegEccDedErrW,
  output logic              RegEccDedErrPipeW,       // DED from W-stage pipeline reg only (for precise EPC)
  // Decode stage signals
  input  logic [31:0]       InstrD,                          // Instruction
  input  logic [1:0]        STATUS_FS,                       // is FPU enabled?
  input  logic [3:0]        ENVCFG_CBE,                      // Cache block operation enables
  input  logic              IllegalIEUFPUInstrD,             // Illegal instruction
  output logic              IllegalBaseInstrD,               // Illegal I-type instruction, or illegal RV32 access to upper 16 registers
  // Execute stage signals
  input  logic [P.XLEN-1:0] PCE,                             // PC
  input  logic [P.XLEN-1:0] PCLinkE,                         // PC + 4
  output logic              PCSrcE,                          // Select next PC (between PC+4 and IEUAdrE)
  input  logic              FWriteIntE, FCvtIntE,            // FPU writes to integer register file, FPU converts float to int
  output logic [P.XLEN-1:0] IEUAdrE,                         // Memory address
  output logic              IntDivE, W64E,                   // Integer divide, RV64 W-type instruction
  output logic [2:0]        Funct3E,                         // Funct3 instruction field
  output logic [P.XLEN-1:0] ForwardedSrcAE, ForwardedSrcBE,  // ALU src inputs before the mux choosing between them and PCE to put in srcA/B
  output logic [4:0]        RdE,                             // Destination register
  output logic              MDUActiveE,                      // Mul/Div instruction being executed
  output logic [3:0]        CMOpM,                           // 1: cbo.inval; 2: cbo.flush; 4: cbo.clean; 8: cbo.zero
  output logic              IFUPrefetchE,                    // instruction prefetch
  output logic              LSUPrefetchM,                    // datata prefetch
  // Memory stage signals
  input  logic              SquashSCW,                       // Squash store conditional, from LSU
  output logic [1:0]        MemRWE,                          // Read/write control goes to LSU
  output logic [1:0]        MemRWM,                          // Read/write control goes to LSU
  output logic [1:0]        AtomicM,                         // Atomic control goes to LSU
  output logic [P.XLEN-1:0] WriteDataM,                      // Write data to LSU
  output logic [2:0]        Funct3M,                         // Funct3 (size and signedness) to LSU
  output logic [P.XLEN-1:0] SrcAM,                           // ALU SrcA to Privileged unit and FPU
  output logic [4:0]        RdM,                             // Destination register
  input  logic [P.XLEN-1:0] FIntResM,                        // Integer result from FPU (fmv, fclass, fcmp)
  output logic              InvalidateICacheM, FlushDCacheM, // Invalidate I$, flush D$
  output logic              InstrValidD, InstrValidE, InstrValidM, // Instruction is valid
  output logic              BranchD, BranchE,
  output logic              JumpD, JumpE,
  // Writeback stage signals
  input  logic [P.XLEN-1:0] FIntDivResultW,                  // Integer divide result from FPU fdivsqrt)
  input  logic [P.XLEN-1:0] CSRReadValW,                     // CSR read value,
  input  logic [P.XLEN-1:0] MDUResultW,                      // multiply/divide unit result
  input  logic [P.XLEN-1:0] FCvtIntResW,                     // FPU's float to int conversion result
  input  logic              FCvtIntW,                        // FPU converts float to int
  output logic [4:0]        RdW,                             // Destination register
  input  logic [P.XLEN-1:0] ReadDataW,                       // LSU's read data
  // Hazard unit signals
  input  logic              StallD, StallE, StallM, StallW,  // Stall signals from hazard unit
  input  logic              FlushD, FlushE, FlushM, FlushW,  // Flush signals
  output logic              StructuralStallD,                // IEU detects structural hazard in Decode stage
  output logic              LoadStallD,                      // Structural stalls for load, sent to performance counters
  output logic              StoreStallD,                     // load after store hazard
  output logic              CSRReadM, CSRWriteM, PrivilegedM,// CSR read, CSR write, is privileged instruction
  output logic              CSRWriteFenceM,                  // CSR write or fence instruction needs to flush subsequent instructions
  // AMOEBA random instruction insertion
  input  logic              InjectD,                         // Inject DummyInstrD into Decode this cycle
  input  logic [31:0]       DummyInstrD,                     // Dummy instruction to inject
  input  logic              DummySelD,                       // Which shadow physical register the dummy writes
  output logic              DummyW,                          // Writeback stage holds a dummy instruction
  // SHARD: register file ports owned by the shadow pipeline (sole writer, two read ports)
  input  logic              shadow_we3,
  input  logic [4:0]        shadow_a3,
  input  logic [P.XLEN-1:0] shadow_wd3,
  input  logic [4:0]        sRs1E, sRs2E,
  output logic [P.XLEN-1:0] sRD1E, sRD2E,
  // SHARD: RQ associative forwarding (driven by shadow_rq)
  output logic [4:0]        Rs1E, Rs2E,                      // Execute-stage source registers for the RQ lookup
  input  logic              RQ_HitA,
  input  logic [P.XLEN-1:0] RQ_ValA,
  input  logic              RQ_HitB,
  input  logic [P.XLEN-1:0] RQ_ValB,
  // SHARD: what the main pipeline used, recorded for the shadow
  output logic [P.XLEN-1:0] SrcAE, SrcBE,                    // ALU operands
  output logic [P.XLEN-1:0] ForwardedSrcAM,                  // rs1 value in Memory stage
  output logic [27:0]       ShardCtlM,                       // datapath controls in Memory stage
  output logic              PCSrcM,                          // branch or jump redirected the PC
  output logic              RegWriteM,                       // integer register write, Memory stage
  output logic [2:0]        ResultSrcM,                      // result select, Memory stage
  output logic              FWriteIntM,                      // FPU result written to an integer register
  output logic              RegWriteW,                       // integer register write, Writeback stage
  output logic [P.XLEN-1:0] ResultW                          // Writeback-stage result
);

  logic [2:0] ImmSrcD;                                       // Select type of immediate extension
  logic [1:0] FlagsE;                                        // Comparison flags ({eq, lt})
  logic       ALUSrcAE, ALUSrcBE;                            // ALU source operands
  logic [2:0] ResultSrcW;                                    // Selects result in Writeback stage
  logic       ALUResultSrcE;                                 // Selects ALU result to pass on to Memory stage
  logic [2:0] ALUSelectE;                                    // ALU select mux signal
  logic       IntDivW;                                       // Integer divide instruction
  logic [3:0] BSelectE;                                      // Indicates if ZBA_ZBB_ZBC_ZBS instruction in one-hot encoding
  logic [3:0] ZBBSelectE;                                    // ZBB Result Select Signal in Execute Stage
  logic [2:0] BALUControlE;                                  // ALU Control signals for B instructions in Execute Stage
  logic       SubArithE;                                     // Subtraction or arithmetic shift
  logic       UW64E;                                         // .uw-type instruction

  logic [6:0] Funct7E;

  // AMOEBA: the injection point.  Only the IEU sees the dummy; the IFU's branch
  // predictor and the FPU keep decoding the real instruction, which is being held
  // in Decode for one cycle and will issue normally next cycle.
  logic [31:0] InstrDMux;
  assign InstrDMux = InjectD ? DummyInstrD : InstrD;

  // Forwarding signals
  logic [4:0] Rs1D, Rs2D;
  logic [1:0] ForwardAE, ForwardBE;                          // Select signals for forwarding multiplexers
  logic       BranchSignedE;                                 // Branch does signed comparison on operands
  logic       BMUActiveE;                                    // Bit manipulation instruction being executed
  logic [1:0] CZeroE;                                        // {czero.nez, czero.eqz} instructions active
  logic       RegWriteE;                                     // E-stage register write enable
  logic [2:0] ImmSrcE;                                       // Immediate format, Execute stage
  logic [27:0] ShardCtlE;                                    // Datapath controls recorded for the shadow

  controller #(P) c(
    .clk, .reset, .StallD, .FlushD, .InstrD(InstrDMux), .STATUS_FS, .ENVCFG_CBE, .ImmSrcD,
    .InjectD, .DummySelD, .DummyW, .DummySelW(),
    .IllegalIEUFPUInstrD, .IllegalBaseInstrD,
    .StructuralStallD, .LoadStallD, .StoreStallD, .Rs1D, .Rs2D, .Rs1E, .Rs2E,
    .StallE, .FlushE, .FlagsE, .FWriteIntE, .FTStall(1'b0),
    .PCSrcE, .ALUSrcAE, .ALUSrcBE, .ALUResultSrcE, .ALUSelectE,
    .Funct3E, .Funct7E, .IntDivE, .W64E, .UW64E, .SubArithE, .BranchD, .BranchE, .JumpD, .JumpE,
    .BranchSignedE, .BSelectE, .ZBBSelectE, .BALUControlE, .BMUActiveE, .CZeroE, .MDUActiveE,
    .FCvtIntE, .ForwardAE, .ForwardBE, .CMOpM, .IFUPrefetchE, .LSUPrefetchM,
    .StallM, .FlushM, .MemRWE, .MemRWM, .CSRReadM, .CSRWriteM, .PrivilegedM, .AtomicM, .Funct3M,
    .FlushDCacheM, .InstrValidM, .InstrValidE, .InstrValidD, .FWriteIntM,
    .StallW, .FlushW, .RegWriteE, .RegWriteM, .ResultSrcM, .RegWriteW, .IntDivW, .ResultSrcW, .CSRWriteFenceM, .InvalidateICacheM,
    .RdW, .RdE, .RdM);

  datapath #(P) dp(
    .clk, .reset, .ecc_inject_en,
    .ImmSrcD, .InstrD(InstrDMux), .Rs1E, .Rs2E, .StallE, .FlushE, .ForwardAE, .ForwardBE, .W64E, .UW64E, .SubArithE,
    .Funct3E, .Funct7E, .ALUSrcAE, .ALUSrcBE, .ALUResultSrcE, .ALUSelectE, .JumpE, .BranchSignedE,
    .PCE, .PCLinkE, .FlagsE, .IEUAdrE, .ForwardedSrcAE, .ForwardedSrcBE, .BSelectE, .ZBBSelectE, .BALUControlE, .BMUActiveE, .CZeroE,
    .StallM, .FlushM, .FWriteIntM, .FIntResM, .SrcAM, .WriteDataM, .FCvtIntW,
    .StallW, .FlushW, .RegWriteW, .IntDivW, .SquashSCW, .ResultSrcW, .ReadDataW, .FCvtIntResW,
    .CSRReadValW, .MDUResultW, .FIntDivResultW, .RdW,
    .shadow_we3, .shadow_a3, .shadow_wd3, .sRs1E, .sRs2E, .sRD1E, .sRD2E,
    .RQ_HitA, .RQ_ValA, .RQ_HitB, .RQ_ValB,
    .SrcAE_out(SrcAE), .SrcBE_out(SrcBE), .ForwardedSrcAM, .ResultW_out(ResultW),
    .RegEccSecErrW, .RegEccDedErrW, .RegEccDedErrPipeW);

  // SHARD: the shadow re-executes each retired instruction with the main pipeline's
  // decoded datapath controls, captured as the instruction moves to the Memory stage.
  flopenrc #(3) ImmSrcEReg(clk, reset, FlushE, ~StallE, ImmSrcD, ImmSrcE);
  assign ShardCtlE = {ALUSrcAE, ALUSrcBE, ImmSrcE, W64E, UW64E, SubArithE, ALUSelectE, BSelectE,
                      ZBBSelectE, BALUControlE, BMUActiveE, CZeroE, ALUResultSrcE, JumpE, BranchE};
  flopenrc #(28) ShardCtlMReg(clk, reset, FlushM, ~StallM, ShardCtlE, ShardCtlM);
  flopenrc #(1)  PCSrcMReg(clk, reset, FlushM, ~StallM, PCSrcE, PCSrcM);
endmodule
