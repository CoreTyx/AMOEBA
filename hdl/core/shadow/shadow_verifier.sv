///////////////////////////////////////////
// shadow_verifier.sv
//
// Purpose: SHARD per-instruction verification, evaluated in shadow sM.
//          Compares what the shadow computed from verified state against what the
//          main pipeline recorded for the same instruction in the OQ, RQ and SQ.
//          Any set bit of Fault stops the instruction from committing.
//
//          Fault bits:
//            [0] OP   register operand the main pipeline used differs from the
//                     shadow's (forwarding select, RQ forwarding, regfile read)
//            [1] NPC  instruction is not at the PC its predecessor leads to
//            [2] RES  ALU / link result
//            [3] EA   ALU sum: effective address or branch/jump target
//            [4] BR   branch/jump direction
//            [5] LD   load data does not re-derive from the raw read word
//            [6] ST   store-queue entry (address, size or data)
//            [7] RD   destination register or write enable of the result record
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_verifier import cvw::*; #(parameter cvw_t P) (
  // Faults found in shadow sE
  input  logic                 sOpFault, sNPCFault,
  // Shadow recomputation
  input  logic [31:0]          sInstr,
  input  logic [P.XLEN-1:0]    sIEUResult,      // ALU or link result
  input  logic [P.XLEN-1:0]    sSum,            // ALU sum
  input  logic                 sTaken,          // branch/jump redirects the PC
  input  logic [P.XLEN-1:0]    sSrcB,           // shadow's rs2 value (store data)
  // Main pipeline record (OQ)
  input  logic [P.XLEN-1:0]    mIEUAdr,
  input  logic [P.XLEN-1:0]    mRawLoadWord,
  input  logic                 mPCSrc,
  input  logic                 mRegWrite,
  input  logic                 mALUClass,       // result comes from the IEU datapath
  input  logic                 mLoadChk,
  input  logic                 mViaSQ,
  input  logic                 mAMO,
  // Main pipeline record (RQ)
  input  logic [4:0]           rqRd,
  input  logic                 rqRegWrite,
  input  logic [P.XLEN-1:0]    rqResult,
  // Main pipeline record (SQ)
  input  logic                 sqValid,
  input  logic [P.PA_BITS-1:0] sqPA,
  input  logic [1:0]           sqSize,
  input  logic [P.XLEN-1:0]    sqData,
  output logic [7:0]           Fault
);

  logic [P.LLEN-1:0] LoadDataLLEN;
  logic [P.XLEN-1:0] AMOResult, StoreData;

  // Loaded value re-derived from the raw read word with an independent subword extract.
  // Only little-endian integer accesses set mLoadChk.
  subwordread #(P) loadextract(
    .ReadDataWordMuxM({{(P.LLEN-P.XLEN){1'b0}}, mRawLoadWord}), .PAdrM(mIEUAdr[3:0]),
    .Funct3M(sInstr[14:12]), .FpLoadStoreM(1'b0), .BigEndianM(1'b0), .ReadDataM(LoadDataLLEN));

  // Value an AMO must write: old memory value (its register result) combined with the
  // shadow's own rs2
  if (P.ZAAMO_SUPPORTED) begin : amo
    amoalu #(P) amoalu(.ReadDataM(rqResult), .IHWriteDataM(sSrcB),
      .LSUFunct7M(sInstr[31:25]), .LSUFunct3M(sInstr[14:12]), .AMOResultM(AMOResult));
  end else begin : amo
    assign AMOResult = sSrcB;
  end
  assign StoreData = mAMO ? AMOResult : sSrcB;

  assign Fault[0] = sOpFault;
  assign Fault[1] = sNPCFault;
  assign Fault[2] = mALUClass & mRegWrite & (sIEUResult != rqResult);
  assign Fault[3] = (sSum != mIEUAdr);
  assign Fault[4] = (sTaken != mPCSrc);
  assign Fault[5] = mLoadChk & (LoadDataLLEN[P.XLEN-1:0] != rqResult);
  assign Fault[6] = mViaSQ & (~sqValid | (sqPA[11:0] != sSum[11:0]) | (sqSize != sInstr[13:12]) |
                              (sqData != StoreData));
  assign Fault[7] = (rqRd != sInstr[11:7]) | (rqRegWrite != mRegWrite);

endmodule
