///////////////////////////////////////////
// cachearray.sv
//
// Purpose: The cache's two SRAM macros -- one for tags, one for lines -- and the decode of what
//          they return.
//
//          Every way of every set lives in the same pair of macros: way w of set s is row
//          w*NUMSETS + s.  A macro returns one row per access, so the ways are looked up one after
//          another (the scan, sequenced by cachefsm.sv): the tag and the line of a way are read
//          together, in the same cycle, so the line of the way that hits is already out of the
//          array when its tag matches.
//
//          ReadWayQ names the way whose row the macros are returning.  It is registered with the
//          same enable as the macros' own address registers, so it stays true while the arrays hold
//          their output.
//
//          There is one tag decoder and one line decoder, on the macro outputs, and one tag
//          compare.  The decoded tag and line are registered; the registers keep a row only if it
//          belongs to the way the arrays are now addressing (or during the scan, every row): the
//          cycle after a scan stops on a hit, the arrays are already returning the next way's row,
//          and the registers must keep the hit.  Nor do they take a row the cycle after it was
//          written: what a macro returns then is not a read.
//
// A component of the AMOEBA RISC-V project.
////////////////////////////////////////////////////////////////////////////////////////////////

module cachearray import cvw::*; #(parameter cvw_t P,
                  parameter NUMWAYS, NUMSETS, TAGLEN, LINELEN, TAGCHECKR, LINECHECKR, TAG_ECC_SUPPORTED,
                  localparam int WAYBITS        = (NUMWAYS > 1) ? $clog2(NUMWAYS) : 1,
                  localparam int SETLEN         = $clog2(NUMSETS),
                  localparam int TAGCHECKWIDTH  = TAGCHECKR + 1,
                  localparam int TAGSTOREWIDTH  = TAGLEN + (TAG_ECC_SUPPORTED ? TAGCHECKWIDTH : 0),
                  localparam int LINECHECKWIDTH = LINECHECKR + 1) (
  input  logic                      clk,
  input  logic                      reset,
  input  logic                      CacheEn,        // Enable the arrays; disabled, they hold their output
  input  logic [WAYBITS-1:0]        RowWay,         // Way to access this cycle
  input  logic [SETLEN-1:0]         CacheSetTag,    // Set to access in the tag array
  input  logic [SETLEN-1:0]         CacheSetData,   // Set to access in the data array
  input  logic                      TagWe,          // Write TagStoreWrite into row {RowWay, CacheSetTag}
  input  logic                      DataWe,         // Write the line into row {RowWay, CacheSetData}
  input  logic [TAGSTOREWIDTH-1:0]  TagStoreWrite,  // Tag word to write: {tag, check bits}
  input  logic [LINELEN-1:0]        LineWriteFinal, // Line to write ...
  input  logic [LINECHECKWIDTH-1:0] LineCheckWriteFinal, // ... and its check bits
  input  logic [TAGLEN-1:0]         PAdrTag,        // Tag of the access
  input  logic                      ScanArrive,     // cachefsm: scanning; keep every row that arrives
  output logic [WAYBITS-1:0]        ReadWayQ,       // Way of the row the arrays are returning
  output logic                      TagReadQ,       // That tag row is a read (not the cycle after a tag write)
  output logic                      TagMatchLive,   // The arriving tag matches the access
  output logic                      TagSecErrLive,  // The arriving tag had a correctable error
  output logic                      TagDedErrLive,  // The arriving tag had an uncorrectable error
  output logic [TAGLEN-1:0]         Tag,            // Corrected tag, registered
  output logic [LINELEN-1:0]        CorrectedLine,  // Corrected line, registered
  output logic                      DataSecErr,     // That line had a correctable error
  output logic                      DataDedErr      // That line had an uncorrectable error
);

  localparam int DEPTH = NUMWAYS * NUMSETS;

  logic [$clog2(DEPTH)-1:0]  TagRow, DataRow;
  logic [TAGSTOREWIDTH-1:0]  TagStoreRead;
  logic [TAGLEN-1:0]         ReadTag, CorrectedTagLive;
  logic [LINELEN-1:0]        ReadDataLine, CorrectedLineLive;
  logic [LINECHECKWIDTH-1:0] ReadDataCheck;
  logic                      DataSecErrLive, DataDedErrLive;
  logic                      DataReadQ, KeepRow;

  if (NUMWAYS > 1) begin : rows
    assign TagRow  = {RowWay, CacheSetTag};
    assign DataRow = {RowWay, CacheSetData};
  end else begin : rows
    assign TagRow  = CacheSetTag;
    assign DataRow = CacheSetData;
  end

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Tag array (optional SECDED: each word holds the whole codeword, {tag, check bits})
  /////////////////////////////////////////////////////////////////////////////////////////////

  ram1p1rwe #(.USE_SRAM(P.USE_SRAM), .DEPTH(DEPTH), .WIDTH(TAGSTOREWIDTH)) CacheTagMem(.clk, .ce(CacheEn),
    .addr(TagRow), .dout(TagStoreRead), .din(TagStoreWrite), .we(TagWe));
  assign ReadTag = TagStoreRead[TAGSTOREWIDTH-1 -: TAGLEN];

  if (TAG_ECC_SUPPORTED) begin : tag_ecc
    cacheeccdec #(.DATA_WIDTH(TAGLEN), .R(TAGCHECKR)) tagdec (
      .codeword_i ({ReadTag, TagStoreRead[TAGCHECKWIDTH-1:0]}),
      .data_o     (CorrectedTagLive),
      .sec_err_o  (TagSecErrLive),
      .ded_err_o  (TagDedErrLive)
    );
  end else begin : tag_ecc_disabled
    assign CorrectedTagLive = ReadTag;
    assign TagSecErrLive = 1'b0;
    assign TagDedErrLive = 1'b0;
  end

  assign TagMatchLive = (CorrectedTagLive == PAdrTag);

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Data array (SECDED: one codeword per full line, stored whole as {line, check bits}).  Every
  // write is a whole line (see cache.sv WriteSelLogic), so there is no partial write to make.
  /////////////////////////////////////////////////////////////////////////////////////////////

  ram1p1rwe #(.USE_SRAM(P.USE_SRAM), .DEPTH(DEPTH), .WIDTH(LINELEN+LINECHECKWIDTH)) CacheDataMem(.clk, .ce(CacheEn),
    .addr(DataRow), .dout({ReadDataLine, ReadDataCheck}), .din({LineWriteFinal, LineCheckWriteFinal}), .we(DataWe));

  cacheeccdec #(.DATA_WIDTH(LINELEN), .R(LINECHECKR)) datadec (
    .codeword_i ({ReadDataLine, ReadDataCheck}),
    .data_o     (CorrectedLineLive),
    .sec_err_o  (DataSecErrLive),
    .ded_err_o  (DataDedErrLive)
  );

  /////////////////////////////////////////////////////////////////////////////////////////////
  // What the arrays are returning, and the decode registers
  /////////////////////////////////////////////////////////////////////////////////////////////

  flopenr #(WAYBITS+2) readreg(clk, reset, CacheEn, {RowWay, ~TagWe, ~DataWe}, {ReadWayQ, TagReadQ, DataReadQ});

  assign KeepRow = ScanArrive | (ReadWayQ == RowWay);
  flopen #(TAGLEN)    tagdecreg(clk, TagReadQ & KeepRow, CorrectedTagLive, Tag);
  flopen #(LINELEN+2) datadecreg(clk, DataReadQ & KeepRow, {CorrectedLineLive, DataSecErrLive, DataDedErrLive},
                                 {CorrectedLine, DataSecErr, DataDedErr});
endmodule
