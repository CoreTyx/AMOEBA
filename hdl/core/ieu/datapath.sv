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
  // Per-unit injection enables after the core applies the software mask and master pin.
  input  logic              fault_inject_alu, fault_inject_cmp,
  input  logic              fault_inject_regfile, fault_inject_pipeline, // independent ECC groups
  // Decode stage signals
  input  logic [2:0]        ImmSrcD,                 // Selects type of immediate extension
  input  logic [31:0]       InstrD,                  // Instruction in Decode stage
  input  logic [4:0]        Rs1D, Rs2D, Rs2E,             // Source registers
  input  logic              InjectD,                 // AMOEBA: decode stage holds an injected dummy instruction
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
  input  logic              InstrValidE,             // current execute-stage instruction is valid
  output logic [1:0]        FlagsE,                  // Comparison flags ({eq, lt})
  output logic [P.XLEN-1:0] IEUAdrE,                 // Address computed by ALU
  output logic [P.XLEN-1:0] ForwardedSrcAE, ForwardedSrcBE, // ALU sources before the mux chooses between them and PCE to put in srcA/B
  // FT control feeds hazard/trap handling; PE bits are diagnostic only.
  output logic              FTStallE, FTUnresolvedE,
  output logic              EccStallE,               // an operand of Execute is uncorrected this cycle; hold the pipeline while its register repairs itself
  output logic              ALU_PE_p, ALU_PE_r, CMP_PE_p, CMP_PE_r,
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
  input  logic              DummyW,                  // AMOEBA: writeback is an inserted dummy instruction
  input  logic              DummySelW,               // AMOEBA: which shadow register the dummy writes
  // ECC error aggregation outputs
  output logic              RegEccSecErrW,           // any correctable ECC error (regfile or pipeline reg)
  output logic              RegEccDedErrW,           // any uncorrectable ECC error → fault signal
  output logic              RegEccDedErrPipeW,       // DED from W-stage pipeline reg only (IFResultM→IFResultW)
  output logic [31:0]       RegfileSecCount
  // Hazard Unit signals
);

  // Fetch stage signals
  // Decode stage signals
  // SECDED codeword of an XLEN-bit value: {data, overall parity, ECC_R Hamming bits}
  localparam int ECC_R  = (P.XLEN <= 57) ? 6 : 7;
  localparam int ECC_CW = P.XLEN + ECC_R + 1;
  logic [ECC_CW-1:0] R1D, R2D;                       // Codewords read from Rs1 (RD1), Rs2 (RD2)
  logic [ECC_CW-1:0] R1DRaw, R2DRaw;                 // Register file read codewords before dummy operand masking
  logic [P.XLEN-1:0] ImmExtD;                        // Extended immediate in Decode stage
  // Execute stage signals
  logic [P.XLEN-1:0] R1E, R2E;                       // Source operands read from register file
  logic [P.XLEN-1:0] ImmExtE;                        // Extended immediate in Execute stage
  logic [P.XLEN-1:0] SrcAE, SrcBE;                   // ALU operands
  logic [P.XLEN-1:0] ALUResultE, AltResultE, IEUResultE; // ALU result, Alternative result (ImmExtE or PC+4), result of execution stage
  // Memory stage signals
  logic [P.XLEN-1:0] IEUResultM;                     // Result from execution stage
  logic [P.XLEN-1:0] IFResultM;                      // Result from either IEU or single-cycle FPU op writing an integer register
  logic [P.XLEN-1:0] IEUResultRawM, IFResultRawM;    // The same before ECC correction, for forwarding
  // Writeback stage signals
  logic [P.XLEN-1:0] SCResultW;                      // Store Conditional result
  logic [P.XLEN-1:0] ResultW;                        // Result to write to register file
  logic [P.XLEN-1:0] IFResultW;                      // Result from either IEU or single-cycle FPU op writing an integer register
  logic [P.XLEN-1:0] IFCvtResultW;                   // Result from IEU, signle-cycle FPU op, or 2-cycle FCVT float to int
  logic [P.XLEN-1:0] IFResultRawW, IFCvtResultRawW, ResultRawW; // IFResultW, IFCvtResultW and ResultW before ECC correction, for forwarding
  logic [P.XLEN-1:0] MulDivResultW;                  // Multiply always comes from MDU.  Divide could come from MDU or FPU (when using fdivsqrt for integer division)

  // ECC error signals from register file read ports

  // ECC error signals from the 7 pipeline registers (sec / ded per instance)
  logic sec_rd1e, ded_rd1e;   // R1D → R1E
  logic sec_rd2e, ded_rd2e;   // R2D → R2E
  logic sec_imme, ded_imme;   // ImmExtD → ImmExtE
  logic sec_srcam, ded_srcam; // SrcAE → SrcAM
  logic sec_ieumm, ded_ieumm; // IEUResultE → IEUResultM
  logic sec_wdm,  ded_wdm;    // ForwardedSrcBE → WriteDataM
  logic sec_ifrw, ded_ifrw;   // IFResultM → IFResultW

  // Decode stage
  regfile #(P.XLEN, P.E_SUPPORTED) regf(
    .clk, .reset,
    .we3(RegWriteW), .a1(Rs1D), .a2(Rs2D), .a3(RdW),
    .wd3(ResultW),
    .DummyW, .DummySelW,
    .rd1(R1DRaw), .rd2(R2DRaw),
    .inject_en(fault_inject_regfile)
  );

  // AMOEBA: obfuscate the operands of inserted dummy instructions.  The mask is
  // applied as a codeword, so the operand registers still receive a valid
  // codeword -- masking the data bits alone would look like a burst error and
  // would spray sec/ded reports on every injection.
  dummymask #(P.XLEN) dmask(
    .clk, .reset, .InjectD,
    .Rd1D(R1DRaw), .Rd2D(R2DRaw),
    .Rd1MaskedD(R1D), .Rd2MaskedD(R2D)
  );
  extend #(P) ext(.InstrD(InstrD[31:7]), .ImmSrcD, .ImmExtD);

  // Execute stage pipeline registers (ECC-protected)
  //
  // Execute works on register contents before ECC correction (q_raw).  The
  // correction is a full decode, and here it would sit in front of the ALU on the
  // forwarding loop.  Everything Execute computes ends in a pipeline register, so
  // instead a single-bit error in any register it reads stalls the pipeline for
  // the one cycle that register takes to repair itself (EccStallE, below).
  // Corrected outputs are still used wherever a value has an effect of its own:
  // store data, CSR write data and the register file write.
  //
  // The two operand registers take the register file's codeword as it was read,
  // so a register file error is not looked for in Decode: it arrives here with
  // the operand and is found, stalled on and repaired like an error in the
  // operand register itself.
  flopenrc_cw #(P.XLEN) RD1EReg(.clk, .reset, .clear(FlushE), .en(~StallE), .inject_en(fault_inject_pipeline),
    .cw(R1D), .q(), .q_raw(R1E), .sec_err_o(sec_rd1e), .ded_err_o(ded_rd1e));
  flopenrc_cw #(P.XLEN) RD2EReg(.clk, .reset, .clear(FlushE), .en(~StallE), .inject_en(fault_inject_pipeline),
    .cw(R2D), .q(), .q_raw(R2E), .sec_err_o(sec_rd2e), .ded_err_o(ded_rd2e));
  flopenrc_ecc #(P.XLEN) ImmExtEReg(.clk, .reset, .clear(FlushE), .en(~StallE), .inject_en(fault_inject_pipeline),
    .d(ImmExtD), .q(), .q_raw(ImmExtE), .sec_err_o(sec_imme), .ded_err_o(ded_imme));

  mux3  #(P.XLEN)  faemux(R1E, ResultRawW, IFResultRawM, ForwardAE, ForwardedSrcAE);
  mux3  #(P.XLEN)  fbemux(R2E, ResultRawW, IFResultRawM, ForwardBE, ForwardedSrcBE);
  mux2  #(P.XLEN)  srcamux(ForwardedSrcAE, PCE, ALUSrcAE, SrcAE);
  mux2  #(P.XLEN)  srcbmux(ForwardedSrcBE, ImmExtE, ALUSrcBE, SrcBE);
  // ALU drives both the architectural result and LSU address.
  ft_alu #(P) ftalu(
    .clk, .reset, .flush(FlushE), .valid(InstrValidE), .advance(~StallM), .A(SrcAE), .B(SrcBE),
    .cmp_a(ForwardedSrcAE), .cmp_b(ForwardedSrcBE), .cmp_sgnd(BranchSignedE), .flags(FlagsE),
    .W64(W64E), .UW64(UW64E), .SubArith(SubArithE), .ALUSelect(ALUSelectE),
    .BSelect(BSelectE), .ZBBSelect(ZBBSelectE), .Funct3(Funct3E), .Funct7(Funct7E),
    .Rs2E, .BALUControl(BALUControlE), .BMUActive(BMUActiveE), .CZero(CZeroE),
    .fi_enable(fault_inject_alu), .cmp_fi_enable(fault_inject_cmp),
    .ALUResult(ALUResultE), .Sum(IEUAdrE), .stall_req(FTStallE),
    .unresolved(FTUnresolvedE), .pe_primary(ALU_PE_p), .pe_shadow(ALU_PE_r),
    .cmp_pe_primary(CMP_PE_p), .cmp_pe_shadow(CMP_PE_r));
  mux2  #(P.XLEN)  altresultmux(ImmExtE, PCLinkE, JumpE, AltResultE);
  mux2  #(P.XLEN)  ieuresultmux(ALUResultE, AltResultE, ALUResultSrcE, IEUResultE);
  // Memory stage pipeline registers (ECC-protected)
  flopenrc_ecc #(P.XLEN) SrcAMReg(.clk, .reset, .clear(FlushM), .en(~StallM), .inject_en(fault_inject_pipeline),
    .d(SrcAE), .q(SrcAM), .q_raw(), .sec_err_o(sec_srcam), .ded_err_o(ded_srcam));
  flopenrc_ecc #(P.XLEN) IEUResultMReg(.clk, .reset, .clear(FlushM), .en(~StallM), .inject_en(fault_inject_pipeline),
    .d(IEUResultE), .q(IEUResultM), .q_raw(IEUResultRawM), .sec_err_o(sec_ieumm), .ded_err_o(ded_ieumm));
  flopenrc_ecc #(P.XLEN) WriteDataMReg(.clk, .reset, .clear(FlushM), .en(~StallM), .inject_en(fault_inject_pipeline),
    .d(ForwardedSrcBE), .q(WriteDataM), .q_raw(), .sec_err_o(sec_wdm), .ded_err_o(ded_wdm));

  // Writeback stage pipeline register (ECC-protected)
  flopenrc_ecc #(P.XLEN) IFResultWReg(.clk, .reset, .clear(FlushW), .en(~StallW), .inject_en(fault_inject_pipeline),
    .d(IFResultM), .q(IFResultW), .q_raw(IFResultRawW), .sec_err_o(sec_ifrw), .ded_err_o(ded_ifrw));

  // The registers Execute reads uncorrected.  SrcAM and WriteDataM are not among
  // them: nothing is forwarded from either.
  assign EccStallE = sec_rd1e | sec_rd2e | sec_imme | sec_ieumm | sec_ifrw;

  // floating point inputs: FIntResM comes from fclass, fcmp, fmv; FCvtIntResW comes from fcvt
  if (P.F_SUPPORTED) begin : fpmux
    mux2  #(P.XLEN)  resultmuxM(IEUResultM, FIntResM, FWriteIntM, IFResultM);
    mux2  #(P.XLEN)  resultrawmuxM(IEUResultRawM, FIntResM, FWriteIntM, IFResultRawM);
    mux2  #(P.XLEN)  cvtresultmuxW(IFResultW, FCvtIntResW, FCvtIntW, IFCvtResultW);
    mux2  #(P.XLEN)  cvtresultrawmuxW(IFResultRawW, FCvtIntResW, FCvtIntW, IFCvtResultRawW);
    if (P.IDIV_ON_FPU & P.F_SUPPORTED) begin
      mux2  #(P.XLEN)  divresultmuxW(MDUResultW, FIntDivResultW, IntDivW, MulDivResultW);
    end else begin
      assign MulDivResultW = MDUResultW;
    end
  end else begin : fpmux
    assign IFResultM = IEUResultM;
    assign IFResultRawM = IEUResultRawM;
    assign IFCvtResultW = IFResultW;
    assign IFCvtResultRawW = IFResultRawW;
    assign MulDivResultW = MDUResultW;
  end
  // ResultW is written to the register file, ResultRawW is forwarded to Execute.
  // They differ only in which copy of the W-stage pipeline register they select.
  mux5  #(P.XLEN) resultmuxW(IFCvtResultW, ReadDataW, CSRReadValW, MulDivResultW, SCResultW, ResultSrcW, ResultW);
  mux5  #(P.XLEN) resultrawmuxW(IFCvtResultRawW, ReadDataW, CSRReadValW, MulDivResultW, SCResultW, ResultSrcW, ResultRawW);

  // handle Store Conditional result if atomic extension supported
  if (P.ZALRSC_SUPPORTED) assign SCResultW = {{(P.XLEN-1){1'b0}}, SquashSCW};
  else                    assign SCResultW = '0;

  // ECC error aggregation.  Register file errors are reported by the operand
  // registers that carry them into Execute (sec_rd1e, sec_rd2e).
  assign RegEccSecErrW = sec_rd1e | sec_rd2e | sec_imme
                       | sec_srcam | sec_ieumm | sec_wdm | sec_ifrw;
  assign RegEccDedErrW = ded_rd1e | ded_rd2e | ded_imme
                       | ded_srcam | ded_ieumm | ded_wdm | ded_ifrw;

  // Single-bit errors corrected on the two register operands: errors read out of
  // the register file, and errors in the operand registers themselves.  Each one
  // is flagged for exactly one cycle, the cycle the operand register repairs it.
  always_ff @(posedge clk)
    if (reset) RegfileSecCount <= '0;
    else       RegfileSecCount <= RegfileSecCount + {31'b0, sec_rd1e} + {31'b0, sec_rd2e};
  // Separate W-stage pipeline reg DED: instruction in W when this fires, so MEPC should use PCW
  assign RegEccDedErrPipeW = ded_ifrw;

endmodule
