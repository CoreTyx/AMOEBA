///////////////////////////////////////////
// mdu.sv
//
// Written: David_Harris@hmc.edu 9 January 2021
// Modified:
//
// Purpose: M extension multiply and divide
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

module mdu import cvw::*;  #(parameter cvw_t P) (
  input  logic              clk, reset,
  // Per-unit enables from the core; each injector selects bit and kind locally.
  input  logic              fault_inject_mul, fault_inject_div, // independent software-selected injection enables
  input  logic              StallM, StallW,
  input  logic              HoldE,                          // Execute's operands cannot be used this cycle (ECC stall)
  input  logic              FlushE, FlushM, FlushW,
  input  logic [P.XLEN-1:0] ForwardedSrcAE, ForwardedSrcBE, // inputs A and B from IEU forwarding mux output
  input  logic [2:0]        Funct3E, Funct3M,               // type of MDU operation
  input  logic              IntDivE, W64E,                  // Integer division/remainder, and W-type instructions
  input  logic              MDUActiveE,                     // Mul/Div instruction being executed
  output logic [P.XLEN-1:0] MDUResultW,                     // multiply/divide result
  output logic              DivBusyE,                       // busy signal to stall pipeline in Execute stage
  // Retry requests and M-aligned terminal faults; PE reports replica isolation,
  // which a single residue-checked unit never has.
  output logic              FTStallM, FTUnresolvedM,
  output logic              MUL_PE_p, MUL_PE_r, DIV_PE_p, DIV_PE_r
);

  logic [P.XLEN-1:0]        ProdM;                          // the half of the product the multiply returns
  logic [P.XLEN-1:0]        DivResultM;                     // quotient or remainder
  logic [P.XLEN-1:0]        PrelimResultM;                  // selected result before W truncation
  logic [P.XLEN-1:0]        MDUResultM;                     // result after W truncation
  logic                     W64M;                           // W-type instruction
  logic                     MulActiveE;
  logic                     MulFTStallM, MulUnresolvedM;
  logic                     DivFTStallM, DivUnresolvedM;

  // Multiplier.  The wrapper preserves the original E->M PP register
  // timing and retries only a held MUL transaction.
  // MUL retries its M-stage transaction by reloading the partial products.
  // DIV retries the held E-stage transaction by restarting the divider FSM;
  // its terminal fault is registered into M alongside the instruction.
  assign MulActiveE = MDUActiveE & ~IntDivE;
  ft_mul #(P) ftmul(.clk, .reset, .StallM, .FlushM, .HoldE,
    .ForwardedSrcAE, .ForwardedSrcBE, .Funct3E, .MulActiveE,
    // Corrupt selected product bits before the M-stage check.
    .fi_enable(fault_inject_mul),
    .ProdM, .stall_req(MulFTStallM), .unresolved(MulUnresolvedM));

  // Divider
  // Start a divide when a new division instruction is received and the divider isn't already busy or finishing
  // When IDIV_ON_FPU is set, use the FPU divider instead
  // In ZMMUL, with M_SUPPORTED = 0, omit the divider
  if ((P.IDIV_ON_FPU & P.F_SUPPORTED) | (!P.M_SUPPORTED)) begin : nodiv
    assign DivResultM = '0;
    assign DivBusyE = 1'b0;
    assign DivFTStallM = 1'b0;
    assign DivUnresolvedM = 1'b0;
  end else begin : div
    logic DivUnresolvedE;
    // Corrupt selected result bits before the E-stage completion check.
    // The resulting fault status is registered into M.
    ft_div #(P) ftdiv(.clk, .reset, .StallM, .FlushE, .FlushM, .DivSignedE(~Funct3E[0]), .RemE(Funct3E[1]),
        .W64E, .IntDivE, .ForwardedSrcAE, .ForwardedSrcBE,
        .fi_enable(fault_inject_div),
        .DivBusyE, .DivResultM, .stall_req(DivFTStallM), .unresolved(DivUnresolvedE));
    // Division completes in E. Carry its terminal fault through the same
    // E->M enable/flush as its instruction and PC before requesting a trap.
    flopenrc #(1) divfaultreg(clk, reset, FlushM, ~StallM, DivUnresolvedE, DivUnresolvedM);
  end

  assign FTStallM      = MulFTStallM | DivFTStallM;
  assign FTUnresolvedM = MulUnresolvedM | DivUnresolvedM;
  assign MUL_PE_p = 1'b0;
  assign MUL_PE_r = 1'b0;
  assign DIV_PE_p = 1'b0;
  assign DIV_PE_r = 1'b0;

  // Result multiplexer: the multiplier has already picked its half and the divider
  // quotient or remainder.  For ZMMUL, DivResultM is tied to 0, so the mux simplifies.
  assign PrelimResultM = Funct3M[2] ? DivResultM : ProdM;

  // Handle sign extension for W-type instructions
  flopenrc #(1) W64MReg(clk, reset, FlushM, ~StallM, W64E, W64M);
  if (P.XLEN == 64) begin : resmux // RV64 has W-type instructions
    assign MDUResultM = W64M ? {{32{PrelimResultM[31]}}, PrelimResultM[31:0]} : PrelimResultM;
  end else begin : resmux // RV32 has no W-type instructions
    assign MDUResultM = PrelimResultM;
  end

  // Writeback stage pipeline register
  flopenrc #(P.XLEN) MDUResultWReg(clk, reset, FlushW, ~StallW, MDUResultM, MDUResultW);
endmodule // mdu
