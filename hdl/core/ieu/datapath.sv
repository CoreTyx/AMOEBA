///////////////////////////////////////////
// datapath.sv
//
// Written: David_Harris@hmc.edu, Sarah.Harris@unlv.edu
// Created: 9 January 2021
// Modified: Saipranavvk saipranavvk@gmail.com 4 September 2026
//           ECC hardening: all seven XLEN-wide data pipeline registers
//           replaced with flopenrc_ecc instances.  The register file now
//           exposes sec/ded error ports.  All SEC/DED signals are OR'd into
//           RegEccSecErrW / RegEccDedErrW and exported to the privileged unit.
//
// Purpose: Wally Integer Datapath
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
// Licensed under the Solderpad Hardware License v 2.1 (the "License"); you may not use this file
// except in compliance with the License, or, at your option, the Apache License version 2.0. You
// may obtain a copy of the License at
//
// https://solderpad.org/licenses/SHL-2.1/
//
// Unless required by applicable law or agreed to in writing, any work distributed under the
// License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions
// and limitations under the License.
////////////////////////////////////////////////////////////////////////////////////////////////

module datapath import cvw::*;  #(parameter cvw_t P) (
  input  logic              clk, reset,
  // ECC inject enable (from top-level, for DFT)
  input  logic              ecc_inject_en,
  // Decode stage signals
  input  logic [2:0]        ImmSrcD,                 // Selects type of immediate extension
  input  logic [31:0]       InstrD,                  // Instruction in Decode stage
  input  logic [4:0]        Rs1E, Rs2E,              // Source registers of the instruction in Execute
  // Execute stage signals
  input  logic [P.XLEN-1:0] PCE,                     // PC in Execute stage
  input  logic [P.XLEN-1:0] PCLinkE,                 // PC + 4 (of instruction in Execute stage)
  input  logic [2:0]        Funct3E,                 // Funct3 field of instruction in Execute stage
  input  logic [6:0]        Funct7E,                 // Funct7 field of instruction in Execute stage
  input  logic              StallE, FlushE,          // Stall, flush Execute stage
  input  logic [1:0]        ForwardAE, ForwardBE,    // Forward ALU operands from later stages
  input  logic              W64E,UW64E,              // W64/.uw-type instruction
  input  logic              SubArithE,               // Subtraction or arithmetic shift
  input  logic              ALUSrcAE, ALUSrcBE,      // ALU operands
  input  logic              ALUResultSrcE,           // Selects result to pass on to Memory stage
  input  logic [2:0]        ALUSelectE,              // ALU mux select signal
  input  logic              JumpE,                   // Is a jump (j) instruction
  input  logic              BranchSignedE,           // Branch comparison operands are signed (if it's a branch)
  input  logic [3:0]        BSelectE,                // One hot encoding of ZBA_ZBB_ZBC_ZBS instruction
  input  logic [3:0]        ZBBSelectE,              // ZBB mux select signal
  input  logic [2:0]        BALUControlE,            // ALU Control signals for B instructions in Execute Stage
  input  logic              BMUActiveE,              // Bit manipulation instruction being executed
  input  logic [1:0]        CZeroE,                  // {czero.nez, czero.eqz} instructions active
  output logic [1:0]        FlagsE,                  // Comparison flags ({eq, lt})
  output logic [P.XLEN-1:0] IEUAdrE,                 // Address computed by ALU
  output logic [P.XLEN-1:0] ForwardedSrcAE, ForwardedSrcBE, // ALU sources before the mux chooses between them and PCE to put in srcA/B
  // Memory stage signals
  input  logic              StallM, FlushM,          // Stall, flush Memory stage
  input  logic              FWriteIntM, FCvtIntW,    // FPU writes integer register file, FPU converts float to int
  input  logic [P.XLEN-1:0] FIntResM,                // FPU integer result
  output logic [P.XLEN-1:0] SrcAM,                   // ALU's Source A in Memory stage to privilege unit for CSR writes
  output logic [P.XLEN-1:0] WriteDataM,              // Write data in Memory stage
  // Writeback stage signals
  input  logic              StallW, FlushW,          // Stall, flush Writeback stage
  input  logic              RegWriteW, IntDivW,      // Write register file, integer divide instruction
  input  logic              SquashSCW,               // Squash a store conditional when a conflict arose
  input  logic [2:0]        ResultSrcW,              // Select source of result to write back to register file
  input  logic [P.XLEN-1:0] FCvtIntResW,             // FPU convert fp to integer result
  input  logic [P.XLEN-1:0] ReadDataW,               // Read data from LSU
  input  logic [P.XLEN-1:0] CSRReadValW,             // CSR read result
  input  logic [P.XLEN-1:0] MDUResultW,              // MDU (Multiply/divide unit) result
  input  logic [P.XLEN-1:0] FIntDivResultW,          // FPU's integer divide result
  input  logic [4:0]        RdW,                     // Destination register
  // SHARD: the shadow pipeline is the only writer of the register file, and reads it
  // through its own two ports
  input  logic              shadow_we3,
  input  logic [4:0]        shadow_a3,
  input  logic [P.XLEN-1:0] shadow_wd3,
  input  logic [4:0]        sRs1E, sRs2E,
  output logic [P.XLEN-1:0] sRD1E, sRD2E,
  // SHARD: RQ associative forwarding of retired-but-uncommitted results
  input  logic              RQ_HitA,
  input  logic [P.XLEN-1:0] RQ_ValA,
  input  logic              RQ_HitB,
  input  logic [P.XLEN-1:0] RQ_ValB,
  // SHARD: values recorded for the shadow
  output logic [P.XLEN-1:0] SrcAE_out,               // ALU operands after the PC/immediate muxes
  output logic [P.XLEN-1:0] SrcBE_out,
  output logic [P.XLEN-1:0] ForwardedSrcAM,          // rs1 value used, in Memory stage (rs2 is WriteDataM)
  output logic [P.XLEN-1:0] ResultW_out,             // W-stage result on its way to the RQ
  // ECC error aggregation outputs
  output logic              RegEccSecErrW,           // any correctable ECC error (regfile or pipeline reg)
  output logic              RegEccDedErrW,           // any uncorrectable ECC error → fault signal
  output logic              RegEccDedErrPipeW        // DED from W-stage pipeline reg only (IFResultM→IFResultW)
);

  // Fetch stage signals
  // Decode stage signals
  logic [P.XLEN-1:0] ImmExtD;                        // Extended immediate in Decode stage
  // Execute stage signals
  logic [P.XLEN-1:0] R1E, R2E;                       // Source operands read from register file
  logic [P.XLEN-1:0] ImmExtE;                        // Extended immediate in Execute stage
  logic [P.XLEN-1:0] SrcAE, SrcBE;                   // ALU operands
  logic [P.XLEN-1:0] ALUResultE, AltResultE, IEUResultE; // ALU result, Alternative result (ImmExtE or PC+4), result of execution stage
  // Memory stage signals
  logic [P.XLEN-1:0] IEUResultM;                     // Result from execution stage
  logic [P.XLEN-1:0] IFResultM;                      // Result from either IEU or single-cycle FPU op writing an integer register
  // Writeback stage signals
  logic [P.XLEN-1:0] SCResultW;                      // Store Conditional result
  logic [P.XLEN-1:0] ResultW;                        // Result to write to register file
  logic [P.XLEN-1:0] IFResultW;                      // Result from either IEU or single-cycle FPU op writing an integer register
  logic [P.XLEN-1:0] IFCvtResultW;                   // Result from IEU, signle-cycle FPU op, or 2-cycle FCVT float to int
  logic [P.XLEN-1:0] MulDivResultW;                  // Multiply always comes from MDU.  Divide could come from MDU or FPU (when using fdivsqrt for integer division)

  // ECC error signals from register file read ports
  logic sec_err_rd1, ded_err_rd1;
  logic sec_err_rd2, ded_err_rd2;
  logic sec_err_rd4, ded_err_rd4;
  logic sec_err_rd5, ded_err_rd5;

  // ECC error signals from the 5 pipeline registers (sec / ded per instance)
  logic sec_imme, ded_imme;   // ImmExtD → ImmExtE
  logic sec_srcam, ded_srcam; // SrcAE → SrcAM
  logic sec_ieumm, ded_ieumm; // IEUResultE → IEUResultM
  logic sec_wdm,  ded_wdm;    // ForwardedSrcBE → WriteDataM
  logic sec_ifrw, ded_ifrw;   // IFResultM → IFResultW

  // SHARD: the register file holds verified state only, and the shadow commits to it
  // at a time unrelated to the main pipeline's stalls.  It is therefore read in Execute,
  // combinationally, so that an instruction held in Execute always sees the current
  // committed value underneath the M/W bypasses and the RQ.  Injected dummy instructions
  // never retire, so their shadow-register write port is tied off.
  regfile #(P.XLEN, P.E_SUPPORTED) regf(
    .clk, .reset,
    .we3(shadow_we3), .a1(Rs1E), .a2(Rs2E), .a3(shadow_a3),
    .wd3(shadow_wd3),
    .DummyW(1'b0), .DummySelW(1'b0),
    .rd1(R1E), .rd2(R2E),
    .inject_en(ecc_inject_en),
    .sec_err_rd1, .ded_err_rd1,
    .sec_err_rd2, .ded_err_rd2,
    .a4(sRs1E), .a5(sRs2E), .rd4(sRD1E), .rd5(sRD2E),
    .sec_err_rd4, .ded_err_rd4,
    .sec_err_rd5, .ded_err_rd5
  );
  extend #(P) ext(.InstrD(InstrD[31:7]), .ImmSrcD, .ImmExtD);

  // Execute stage pipeline register (ECC-protected)
  flopenrc_ecc #(P.XLEN) ImmExtEReg(clk, reset, FlushE, ~StallE, ecc_inject_en, ImmExtD,         ImmExtE,    sec_imme,  ded_imme);

  // Standard M/W bypass forwarding mux
  logic [P.XLEN-1:0] FwdSrcA_mw, FwdSrcB_mw;
  mux3  #(P.XLEN)  faemux(R1E, ResultW, IFResultM, ForwardAE, FwdSrcA_mw);
  mux3  #(P.XLEN)  fbemux(R2E, ResultW, IFResultM, ForwardBE, FwdSrcB_mw);
  // RQ associative forwarding applies when neither the M nor the W stage produces the
  // register: those are newer than any RQ entry, which in turn is newer than the regfile.
  assign ForwardedSrcAE = (RQ_HitA & (ForwardAE == 2'b00)) ? RQ_ValA : FwdSrcA_mw;
  assign ForwardedSrcBE = (RQ_HitB & (ForwardBE == 2'b00)) ? RQ_ValB : FwdSrcB_mw;
  comparator #(P.XLEN) comp(ForwardedSrcAE, ForwardedSrcBE, BranchSignedE, FlagsE);
  mux2  #(P.XLEN)  srcamux(ForwardedSrcAE, PCE, ALUSrcAE, SrcAE);
  mux2  #(P.XLEN)  srcbmux(ForwardedSrcBE, ImmExtE, ALUSrcBE, SrcBE);
  alu   #(P)       alu(SrcAE, SrcBE, W64E, UW64E, SubArithE, ALUSelectE, BSelectE, ZBBSelectE, Funct3E, Funct7E, Rs2E, BALUControlE, BMUActiveE, CZeroE, ALUResultE, IEUAdrE);
  mux2  #(P.XLEN)  altresultmux(ImmExtE, PCLinkE, JumpE, AltResultE);
  mux2  #(P.XLEN)  ieuresultmux(ALUResultE, AltResultE, ALUResultSrcE, IEUResultE);

  // Memory stage pipeline registers (ECC-protected)
  flopenrc_ecc #(P.XLEN) SrcAMReg     (clk, reset, FlushM, ~StallM, ecc_inject_en, SrcAE,          SrcAM,      sec_srcam, ded_srcam);
  flopenrc_ecc #(P.XLEN) IEUResultMReg(clk, reset, FlushM, ~StallM, ecc_inject_en, IEUResultE,     IEUResultM, sec_ieumm, ded_ieumm);
  flopenrc_ecc #(P.XLEN) WriteDataMReg(clk, reset, FlushM, ~StallM, ecc_inject_en, ForwardedSrcBE, WriteDataM, sec_wdm,   ded_wdm);
  flopenrc     #(P.XLEN) FwdSrcAMReg  (clk, reset, FlushM, ~StallM, ForwardedSrcAE, ForwardedSrcAM);

  // Writeback stage pipeline register (ECC-protected)
  flopenrc_ecc #(P.XLEN) IFResultWReg (clk, reset, FlushW, ~StallW, ecc_inject_en, IFResultM,      IFResultW,  sec_ifrw,  ded_ifrw);

  // floating point inputs: FIntResM comes from fclass, fcmp, fmv; FCvtIntResW comes from fcvt
  if (P.F_SUPPORTED) begin : fpmux
    mux2  #(P.XLEN)  resultmuxM(IEUResultM, FIntResM, FWriteIntM, IFResultM);
    mux2  #(P.XLEN)  cvtresultmuxW(IFResultW, FCvtIntResW, FCvtIntW, IFCvtResultW);
    if (P.IDIV_ON_FPU & P.F_SUPPORTED) begin
      mux2  #(P.XLEN)  divresultmuxW(MDUResultW, FIntDivResultW, IntDivW, MulDivResultW);
    end else begin
      assign MulDivResultW = MDUResultW;
    end
  end else begin : fpmux
    assign IFResultM = IEUResultM;
    assign IFCvtResultW = IFResultW;
    assign MulDivResultW = MDUResultW;
  end
  mux5  #(P.XLEN) resultmuxW(IFCvtResultW, ReadDataW, CSRReadValW, MulDivResultW, SCResultW, ResultSrcW, ResultW);

  // handle Store Conditional result if atomic extension supported
  if (P.ZALRSC_SUPPORTED) assign SCResultW = {{(P.XLEN-1){1'b0}}, SquashSCW};
  else                    assign SCResultW = '0;

  // ECC error aggregation
  assign RegEccSecErrW = sec_err_rd1 | sec_err_rd2 | sec_err_rd4 | sec_err_rd5
                       | sec_imme
                       | sec_srcam | sec_ieumm | sec_wdm | sec_ifrw;
  assign RegEccDedErrW = ded_err_rd1 | ded_err_rd2 | ded_err_rd4 | ded_err_rd5
                       | ded_imme
                       | ded_srcam | ded_ieumm | ded_wdm | ded_ifrw;
  // Separate W-stage pipeline reg DED: instruction in W when this fires, so MEPC should use PCW
  assign RegEccDedErrPipeW = ded_ifrw;

  assign SrcAE_out   = SrcAE;
  assign SrcBE_out   = SrcBE;
  assign ResultW_out = ResultW;

endmodule
