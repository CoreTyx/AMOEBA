// Generated debug buses; include inside tb_scan.
// *_raw_internal is physical Q: .Q or ~.QN; NO logical polarity correction.
// *_internal estimates the RTL value as physical Q XOR map_ph.
// *_pin_internal probes the scandef-selected Q or QN output.
// If Q is unconnected, raw Q is derived as ~QN (and vice versa).
// An unconnected Q pin is never probed when connected QN is available.
// Unavailable bits have available=0 and remain Z in raw/pin/estimated buses.
// No logical constants are assumed; the testbench displays unavailable bits as '-'.
// No map entry does not prove that synthesis optimized a bit away.

// ============================================================================
// Register FTStatusSticky: 3 mapped bits, width 7
// ============================================================================

// Bus declarations
wire [6:0] FTStatusSticky_internal;
wire [6:0] FTStatusSticky_raw_internal;
wire [6:0] FTStatusSticky_pin_internal;
wire [6:0] FTStatusSticky_raw_internal_available;

// ---- FTStatusSticky_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign FTStatusSticky_raw_internal[0] = dut.chip.soc_core_FTStatusSticky_reg_0_.Q; // c0[1]
assign FTStatusSticky_raw_internal[1] = dut.chip.soc_core_FTStatusSticky_reg_1_.Q; // c0[2]
assign FTStatusSticky_raw_internal[2] = 1'bz; // unavailable physical Q
assign FTStatusSticky_raw_internal[3] = 1'bz; // unavailable physical Q
assign FTStatusSticky_raw_internal[4] = 1'bz; // unavailable physical Q
assign FTStatusSticky_raw_internal[5] = 1'bz; // unavailable physical Q
assign FTStatusSticky_raw_internal[6] = dut.chip.soc_core_FTStatusSticky_reg_6_.Q; // c0[3]

// ---- FTStatusSticky_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign FTStatusSticky_internal[0] = FTStatusSticky_raw_internal[0];
assign FTStatusSticky_internal[1] = FTStatusSticky_raw_internal[1];
assign FTStatusSticky_internal[2] = 1'bz; // unavailable logical estimate
assign FTStatusSticky_internal[3] = 1'bz; // unavailable logical estimate
assign FTStatusSticky_internal[4] = 1'bz; // unavailable logical estimate
assign FTStatusSticky_internal[5] = 1'bz; // unavailable logical estimate
assign FTStatusSticky_internal[6] = FTStatusSticky_raw_internal[6];

// ---- FTStatusSticky_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign FTStatusSticky_pin_internal[0] = dut.chip.soc_core_FTStatusSticky_reg_0_.Q;
assign FTStatusSticky_pin_internal[1] = dut.chip.soc_core_FTStatusSticky_reg_1_.Q;
assign FTStatusSticky_pin_internal[2] = 1'bz; // unavailable scan pin
assign FTStatusSticky_pin_internal[3] = 1'bz; // unavailable scan pin
assign FTStatusSticky_pin_internal[4] = 1'bz; // unavailable scan pin
assign FTStatusSticky_pin_internal[5] = 1'bz; // unavailable scan pin
assign FTStatusSticky_pin_internal[6] = dut.chip.soc_core_FTStatusSticky_reg_6_.Q;

// ---- FTStatusSticky_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign FTStatusSticky_raw_internal_available[0] = 1'b1;
assign FTStatusSticky_raw_internal_available[1] = 1'b1;
assign FTStatusSticky_raw_internal_available[2] = 1'b0;
assign FTStatusSticky_raw_internal_available[3] = 1'b0;
assign FTStatusSticky_raw_internal_available[4] = 1'b0;
assign FTStatusSticky_raw_internal_available[5] = 1'b0;
assign FTStatusSticky_raw_internal_available[6] = 1'b1;

// ============================================================================
// Register ieu_c_RdEReg: 5 mapped bits, width 5
// ============================================================================

// Bus declarations
wire [4:0] ieu_c_RdEReg_internal;
wire [4:0] ieu_c_RdEReg_raw_internal;
wire [4:0] ieu_c_RdEReg_pin_internal;
wire [4:0] ieu_c_RdEReg_raw_internal_available;

// ---- ieu_c_RdEReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ieu_c_RdEReg_raw_internal[0] = ~dut.chip.soc_core_ieu_c_RdEReg_q_reg_0_.QN; // c0[4]
assign ieu_c_RdEReg_raw_internal[1] = dut.chip.soc_core_ieu_c_RdEReg_q_reg_1_.Q; // c0[5]
assign ieu_c_RdEReg_raw_internal[2] = ~dut.chip.soc_core_ieu_c_RdEReg_q_reg_2_.QN; // c0[6]
assign ieu_c_RdEReg_raw_internal[3] = dut.chip.soc_core_ieu_c_RdEReg_q_reg_3_.Q; // c0[7]
assign ieu_c_RdEReg_raw_internal[4] = ~dut.chip.soc_core_ieu_c_RdEReg_q_reg_4_.QN; // c0[8]

// ---- ieu_c_RdEReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ieu_c_RdEReg_internal[0] = ieu_c_RdEReg_raw_internal[0];
assign ieu_c_RdEReg_internal[1] = ieu_c_RdEReg_raw_internal[1];
assign ieu_c_RdEReg_internal[2] = ieu_c_RdEReg_raw_internal[2];
assign ieu_c_RdEReg_internal[3] = ieu_c_RdEReg_raw_internal[3];
assign ieu_c_RdEReg_internal[4] = ieu_c_RdEReg_raw_internal[4];

// ---- ieu_c_RdEReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ieu_c_RdEReg_pin_internal[0] = dut.chip.soc_core_ieu_c_RdEReg_q_reg_0_.QN;
assign ieu_c_RdEReg_pin_internal[1] = dut.chip.soc_core_ieu_c_RdEReg_q_reg_1_.Q;
assign ieu_c_RdEReg_pin_internal[2] = dut.chip.soc_core_ieu_c_RdEReg_q_reg_2_.QN;
assign ieu_c_RdEReg_pin_internal[3] = dut.chip.soc_core_ieu_c_RdEReg_q_reg_3_.Q;
assign ieu_c_RdEReg_pin_internal[4] = dut.chip.soc_core_ieu_c_RdEReg_q_reg_4_.QN;

// ---- ieu_c_RdEReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ieu_c_RdEReg_raw_internal_available[0] = 1'b1;
assign ieu_c_RdEReg_raw_internal_available[1] = 1'b1;
assign ieu_c_RdEReg_raw_internal_available[2] = 1'b1;
assign ieu_c_RdEReg_raw_internal_available[3] = 1'b1;
assign ieu_c_RdEReg_raw_internal_available[4] = 1'b1;

// ============================================================================
// Register ieu_c_RdMReg: 5 mapped bits, width 5
// ============================================================================

// Bus declarations
wire [4:0] ieu_c_RdMReg_internal;
wire [4:0] ieu_c_RdMReg_raw_internal;
wire [4:0] ieu_c_RdMReg_pin_internal;
wire [4:0] ieu_c_RdMReg_raw_internal_available;

// ---- ieu_c_RdMReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ieu_c_RdMReg_raw_internal[0] = ~dut.chip.soc_core_ieu_c_RdMReg_q_reg_0_.QN; // c0[9]
assign ieu_c_RdMReg_raw_internal[1] = ~dut.chip.soc_core_ieu_c_RdMReg_q_reg_1_.QN; // c0[10]
assign ieu_c_RdMReg_raw_internal[2] = ~dut.chip.soc_core_ieu_c_RdMReg_q_reg_2_.QN; // c0[11]
assign ieu_c_RdMReg_raw_internal[3] = ~dut.chip.soc_core_ieu_c_RdMReg_q_reg_3_.QN; // c0[12]
assign ieu_c_RdMReg_raw_internal[4] = ~dut.chip.soc_core_ieu_c_RdMReg_q_reg_4_.QN; // c0[13]

// ---- ieu_c_RdMReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ieu_c_RdMReg_internal[0] = ieu_c_RdMReg_raw_internal[0];
assign ieu_c_RdMReg_internal[1] = ieu_c_RdMReg_raw_internal[1];
assign ieu_c_RdMReg_internal[2] = ieu_c_RdMReg_raw_internal[2];
assign ieu_c_RdMReg_internal[3] = ieu_c_RdMReg_raw_internal[3];
assign ieu_c_RdMReg_internal[4] = ieu_c_RdMReg_raw_internal[4];

// ---- ieu_c_RdMReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ieu_c_RdMReg_pin_internal[0] = dut.chip.soc_core_ieu_c_RdMReg_q_reg_0_.QN;
assign ieu_c_RdMReg_pin_internal[1] = dut.chip.soc_core_ieu_c_RdMReg_q_reg_1_.QN;
assign ieu_c_RdMReg_pin_internal[2] = dut.chip.soc_core_ieu_c_RdMReg_q_reg_2_.QN;
assign ieu_c_RdMReg_pin_internal[3] = dut.chip.soc_core_ieu_c_RdMReg_q_reg_3_.QN;
assign ieu_c_RdMReg_pin_internal[4] = dut.chip.soc_core_ieu_c_RdMReg_q_reg_4_.QN;

// ---- ieu_c_RdMReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ieu_c_RdMReg_raw_internal_available[0] = 1'b1;
assign ieu_c_RdMReg_raw_internal_available[1] = 1'b1;
assign ieu_c_RdMReg_raw_internal_available[2] = 1'b1;
assign ieu_c_RdMReg_raw_internal_available[3] = 1'b1;
assign ieu_c_RdMReg_raw_internal_available[4] = 1'b1;

// ============================================================================
// Register ieu_c_RdWReg: 5 mapped bits, width 5
// ============================================================================

// Bus declarations
wire [4:0] ieu_c_RdWReg_internal;
wire [4:0] ieu_c_RdWReg_raw_internal;
wire [4:0] ieu_c_RdWReg_pin_internal;
wire [4:0] ieu_c_RdWReg_raw_internal_available;

// ---- ieu_c_RdWReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ieu_c_RdWReg_raw_internal[0] = ~dut.chip.soc_core_ieu_c_RdWReg_q_reg_0_.QN; // c0[14]
assign ieu_c_RdWReg_raw_internal[1] = ~dut.chip.soc_core_ieu_c_RdWReg_q_reg_1_.QN; // c0[15]
assign ieu_c_RdWReg_raw_internal[2] = ~dut.chip.soc_core_ieu_c_RdWReg_q_reg_2_.QN; // c0[16]
assign ieu_c_RdWReg_raw_internal[3] = ~dut.chip.soc_core_ieu_c_RdWReg_q_reg_3_.QN; // c0[17]
assign ieu_c_RdWReg_raw_internal[4] = ~dut.chip.soc_core_ieu_c_RdWReg_q_reg_4_.QN; // c0[18]

// ---- ieu_c_RdWReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ieu_c_RdWReg_internal[0] = ieu_c_RdWReg_raw_internal[0];
assign ieu_c_RdWReg_internal[1] = ieu_c_RdWReg_raw_internal[1];
assign ieu_c_RdWReg_internal[2] = ieu_c_RdWReg_raw_internal[2];
assign ieu_c_RdWReg_internal[3] = ieu_c_RdWReg_raw_internal[3];
assign ieu_c_RdWReg_internal[4] = ieu_c_RdWReg_raw_internal[4];

// ---- ieu_c_RdWReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ieu_c_RdWReg_pin_internal[0] = dut.chip.soc_core_ieu_c_RdWReg_q_reg_0_.QN;
assign ieu_c_RdWReg_pin_internal[1] = dut.chip.soc_core_ieu_c_RdWReg_q_reg_1_.QN;
assign ieu_c_RdWReg_pin_internal[2] = dut.chip.soc_core_ieu_c_RdWReg_q_reg_2_.QN;
assign ieu_c_RdWReg_pin_internal[3] = dut.chip.soc_core_ieu_c_RdWReg_q_reg_3_.QN;
assign ieu_c_RdWReg_pin_internal[4] = dut.chip.soc_core_ieu_c_RdWReg_q_reg_4_.QN;

// ---- ieu_c_RdWReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ieu_c_RdWReg_raw_internal_available[0] = 1'b1;
assign ieu_c_RdWReg_raw_internal_available[1] = 1'b1;
assign ieu_c_RdWReg_raw_internal_available[2] = 1'b1;
assign ieu_c_RdWReg_raw_internal_available[3] = 1'b1;
assign ieu_c_RdWReg_raw_internal_available[4] = 1'b1;

// ============================================================================
// Register ieu_c_Rs1EReg: 5 mapped bits, width 5
// ============================================================================

// Bus declarations
wire [4:0] ieu_c_Rs1EReg_internal;
wire [4:0] ieu_c_Rs1EReg_raw_internal;
wire [4:0] ieu_c_Rs1EReg_pin_internal;
wire [4:0] ieu_c_Rs1EReg_raw_internal_available;

// ---- ieu_c_Rs1EReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ieu_c_Rs1EReg_raw_internal[0] = ~dut.chip.soc_core_ieu_c_Rs1EReg_q_reg_0_.QN; // c0[19]
assign ieu_c_Rs1EReg_raw_internal[1] = dut.chip.soc_core_ieu_c_Rs1EReg_q_reg_1_.Q; // c0[20]
assign ieu_c_Rs1EReg_raw_internal[2] = dut.chip.soc_core_ieu_c_Rs1EReg_q_reg_2_.Q; // c0[21]
assign ieu_c_Rs1EReg_raw_internal[3] = dut.chip.soc_core_ieu_c_Rs1EReg_q_reg_3_.Q; // c0[22]
assign ieu_c_Rs1EReg_raw_internal[4] = ~dut.chip.soc_core_ieu_c_Rs1EReg_q_reg_4_.QN; // c0[23]

// ---- ieu_c_Rs1EReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ieu_c_Rs1EReg_internal[0] = ieu_c_Rs1EReg_raw_internal[0];
assign ieu_c_Rs1EReg_internal[1] = ieu_c_Rs1EReg_raw_internal[1];
assign ieu_c_Rs1EReg_internal[2] = ieu_c_Rs1EReg_raw_internal[2];
assign ieu_c_Rs1EReg_internal[3] = ieu_c_Rs1EReg_raw_internal[3];
assign ieu_c_Rs1EReg_internal[4] = ieu_c_Rs1EReg_raw_internal[4];

// ---- ieu_c_Rs1EReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ieu_c_Rs1EReg_pin_internal[0] = dut.chip.soc_core_ieu_c_Rs1EReg_q_reg_0_.QN;
assign ieu_c_Rs1EReg_pin_internal[1] = dut.chip.soc_core_ieu_c_Rs1EReg_q_reg_1_.Q;
assign ieu_c_Rs1EReg_pin_internal[2] = dut.chip.soc_core_ieu_c_Rs1EReg_q_reg_2_.Q;
assign ieu_c_Rs1EReg_pin_internal[3] = dut.chip.soc_core_ieu_c_Rs1EReg_q_reg_3_.Q;
assign ieu_c_Rs1EReg_pin_internal[4] = dut.chip.soc_core_ieu_c_Rs1EReg_q_reg_4_.QN;

// ---- ieu_c_Rs1EReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ieu_c_Rs1EReg_raw_internal_available[0] = 1'b1;
assign ieu_c_Rs1EReg_raw_internal_available[1] = 1'b1;
assign ieu_c_Rs1EReg_raw_internal_available[2] = 1'b1;
assign ieu_c_Rs1EReg_raw_internal_available[3] = 1'b1;
assign ieu_c_Rs1EReg_raw_internal_available[4] = 1'b1;

// ============================================================================
// Register ieu_c_Rs2EReg: 5 mapped bits, width 5
// ============================================================================

// Bus declarations
wire [4:0] ieu_c_Rs2EReg_internal;
wire [4:0] ieu_c_Rs2EReg_raw_internal;
wire [4:0] ieu_c_Rs2EReg_pin_internal;
wire [4:0] ieu_c_Rs2EReg_raw_internal_available;

// ---- ieu_c_Rs2EReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ieu_c_Rs2EReg_raw_internal[0] = ~dut.chip.soc_core_ieu_c_Rs2EReg_q_reg_0_.QN; // c0[24]
assign ieu_c_Rs2EReg_raw_internal[1] = dut.chip.soc_core_ieu_c_Rs2EReg_q_reg_1_.Q; // c0[25]
assign ieu_c_Rs2EReg_raw_internal[2] = dut.chip.soc_core_ieu_c_Rs2EReg_q_reg_2_.Q; // c0[26]
assign ieu_c_Rs2EReg_raw_internal[3] = dut.chip.soc_core_ieu_c_Rs2EReg_q_reg_3_.Q; // c0[27]
assign ieu_c_Rs2EReg_raw_internal[4] = ~dut.chip.soc_core_ieu_c_Rs2EReg_q_reg_4_.QN; // c0[28]

// ---- ieu_c_Rs2EReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ieu_c_Rs2EReg_internal[0] = ieu_c_Rs2EReg_raw_internal[0];
assign ieu_c_Rs2EReg_internal[1] = ieu_c_Rs2EReg_raw_internal[1];
assign ieu_c_Rs2EReg_internal[2] = ieu_c_Rs2EReg_raw_internal[2];
assign ieu_c_Rs2EReg_internal[3] = ieu_c_Rs2EReg_raw_internal[3];
assign ieu_c_Rs2EReg_internal[4] = ieu_c_Rs2EReg_raw_internal[4];

// ---- ieu_c_Rs2EReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ieu_c_Rs2EReg_pin_internal[0] = dut.chip.soc_core_ieu_c_Rs2EReg_q_reg_0_.QN;
assign ieu_c_Rs2EReg_pin_internal[1] = dut.chip.soc_core_ieu_c_Rs2EReg_q_reg_1_.Q;
assign ieu_c_Rs2EReg_pin_internal[2] = dut.chip.soc_core_ieu_c_Rs2EReg_q_reg_2_.Q;
assign ieu_c_Rs2EReg_pin_internal[3] = dut.chip.soc_core_ieu_c_Rs2EReg_q_reg_3_.Q;
assign ieu_c_Rs2EReg_pin_internal[4] = dut.chip.soc_core_ieu_c_Rs2EReg_q_reg_4_.QN;

// ---- ieu_c_Rs2EReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ieu_c_Rs2EReg_raw_internal_available[0] = 1'b1;
assign ieu_c_Rs2EReg_raw_internal_available[1] = 1'b1;
assign ieu_c_Rs2EReg_raw_internal_available[2] = 1'b1;
assign ieu_c_Rs2EReg_raw_internal_available[3] = 1'b1;
assign ieu_c_Rs2EReg_raw_internal_available[4] = 1'b1;

// ============================================================================
// Register ieu_c_controlregD: 1 mapped bits, width 1
// ============================================================================

// Bus declarations
wire [0:0] ieu_c_controlregD_internal;
wire [0:0] ieu_c_controlregD_raw_internal;
wire [0:0] ieu_c_controlregD_pin_internal;
wire [0:0] ieu_c_controlregD_raw_internal_available;

// ---- ieu_c_controlregD_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ieu_c_controlregD_raw_internal[0] = dut.chip.soc_core_ieu_c_controlregD_q_reg_0_.Q; // c0[29]

// ---- ieu_c_controlregD_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ieu_c_controlregD_internal[0] = ieu_c_controlregD_raw_internal[0];

// ---- ieu_c_controlregD_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ieu_c_controlregD_pin_internal[0] = dut.chip.soc_core_ieu_c_controlregD_q_reg_0_.Q;

// ---- ieu_c_controlregD_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ieu_c_controlregD_raw_internal_available[0] = 1'b1;

// ============================================================================
// Register ieu_c_controlregE: 29 mapped bits, width 47
// ============================================================================

// Bus declarations
wire [46:0] ieu_c_controlregE_internal;
wire [46:0] ieu_c_controlregE_raw_internal;
wire [46:0] ieu_c_controlregE_pin_internal;
wire [46:0] ieu_c_controlregE_raw_internal_available;

// ---- ieu_c_controlregE_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ieu_c_controlregE_raw_internal[0] = 1'bz; // unavailable physical Q
assign ieu_c_controlregE_raw_internal[1] = dut.chip.soc_core_ieu_c_controlregE_q_reg_1_.Q; // c0[30]
assign ieu_c_controlregE_raw_internal[2] = dut.chip.soc_core_ieu_c_controlregE_q_reg_2_.Q; // c0[31]
assign ieu_c_controlregE_raw_internal[3] = 1'bz; // unavailable physical Q
assign ieu_c_controlregE_raw_internal[4] = 1'bz; // unavailable physical Q
assign ieu_c_controlregE_raw_internal[5] = 1'bz; // unavailable physical Q
assign ieu_c_controlregE_raw_internal[6] = 1'bz; // unavailable physical Q
assign ieu_c_controlregE_raw_internal[7] = 1'bz; // unavailable physical Q
assign ieu_c_controlregE_raw_internal[8] = 1'bz; // unavailable physical Q
assign ieu_c_controlregE_raw_internal[9] = 1'bz; // unavailable physical Q
assign ieu_c_controlregE_raw_internal[10] = 1'bz; // unavailable physical Q
assign ieu_c_controlregE_raw_internal[11] = dut.chip.soc_core_ieu_c_controlregE_q_reg_11_.Q; // c0[32]
assign ieu_c_controlregE_raw_internal[12] = dut.chip.soc_core_ieu_c_controlregE_q_reg_12_.Q; // c0[33]
assign ieu_c_controlregE_raw_internal[13] = 1'bz; // unavailable physical Q
assign ieu_c_controlregE_raw_internal[14] = dut.chip.soc_core_ieu_c_controlregE_q_reg_14_.Q; // c0[34]
assign ieu_c_controlregE_raw_internal[15] = dut.chip.soc_core_ieu_c_controlregE_q_reg_15_.Q; // c0[35]
assign ieu_c_controlregE_raw_internal[16] = ~dut.chip.soc_core_ieu_c_controlregE_q_reg_16_.QN; // c0[36]
assign ieu_c_controlregE_raw_internal[17] = dut.chip.soc_core_ieu_c_controlregE_q_reg_17_.Q; // c0[37]
assign ieu_c_controlregE_raw_internal[18] = 1'bz; // unavailable physical Q
assign ieu_c_controlregE_raw_internal[19] = dut.chip.soc_core_ieu_c_controlregE_q_reg_19_.Q; // c0[38]
assign ieu_c_controlregE_raw_internal[20] = 1'bz; // unavailable physical Q
assign ieu_c_controlregE_raw_internal[21] = 1'bz; // unavailable physical Q
assign ieu_c_controlregE_raw_internal[22] = 1'bz; // unavailable physical Q
assign ieu_c_controlregE_raw_internal[23] = 1'bz; // unavailable physical Q
assign ieu_c_controlregE_raw_internal[24] = 1'bz; // unavailable physical Q
assign ieu_c_controlregE_raw_internal[25] = 1'bz; // unavailable physical Q
assign ieu_c_controlregE_raw_internal[26] = 1'bz; // unavailable physical Q
assign ieu_c_controlregE_raw_internal[27] = dut.chip.soc_core_ieu_c_controlregE_q_reg_27_.Q; // c0[39]
assign ieu_c_controlregE_raw_internal[28] = dut.chip.soc_core_ieu_c_controlregE_q_reg_28_.Q; // c0[40]
assign ieu_c_controlregE_raw_internal[29] = dut.chip.soc_core_ieu_c_controlregE_q_reg_29_.Q; // c0[41]
assign ieu_c_controlregE_raw_internal[30] = dut.chip.soc_core_ieu_c_controlregE_q_reg_30_.Q; // c0[42]
assign ieu_c_controlregE_raw_internal[31] = dut.chip.soc_core_ieu_c_controlregE_q_reg_31_.Q; // c0[43]
assign ieu_c_controlregE_raw_internal[32] = dut.chip.soc_core_ieu_c_controlregE_q_reg_32_.Q; // c0[44]
assign ieu_c_controlregE_raw_internal[33] = ~dut.chip.soc_core_ieu_c_controlregE_q_reg_33_.QN; // c0[45]
assign ieu_c_controlregE_raw_internal[34] = ~dut.chip.soc_core_ieu_c_controlregE_q_reg_34_.QN; // c0[46]
assign ieu_c_controlregE_raw_internal[35] = ~dut.chip.soc_core_ieu_c_controlregE_q_reg_35_.QN; // c0[47]
assign ieu_c_controlregE_raw_internal[36] = dut.chip.soc_core_ieu_c_controlregE_q_reg_36_.Q; // c0[48]
assign ieu_c_controlregE_raw_internal[37] = dut.chip.soc_core_ieu_c_controlregE_q_reg_37_.Q; // c0[49]
assign ieu_c_controlregE_raw_internal[38] = dut.chip.soc_core_ieu_c_controlregE_q_reg_38_.Q; // c0[50]
assign ieu_c_controlregE_raw_internal[39] = dut.chip.soc_core_ieu_c_controlregE_q_reg_39_.Q; // c0[51]
assign ieu_c_controlregE_raw_internal[40] = dut.chip.soc_core_ieu_c_controlregE_q_reg_40_.Q; // c0[52]
assign ieu_c_controlregE_raw_internal[41] = dut.chip.soc_core_ieu_c_controlregE_q_reg_41_.Q; // c0[53]
assign ieu_c_controlregE_raw_internal[42] = ~dut.chip.soc_core_ieu_c_controlregE_q_reg_42_.QN; // c0[54]
assign ieu_c_controlregE_raw_internal[43] = dut.chip.soc_core_ieu_c_controlregE_q_reg_43_.Q; // c0[55]
assign ieu_c_controlregE_raw_internal[44] = dut.chip.soc_core_ieu_c_controlregE_q_reg_44_.Q; // c0[56]
assign ieu_c_controlregE_raw_internal[45] = dut.chip.soc_core_ieu_c_controlregE_q_reg_45_.Q; // c0[57]
assign ieu_c_controlregE_raw_internal[46] = dut.chip.soc_core_ieu_c_controlregE_q_reg_46_.Q; // c0[58]

// ---- ieu_c_controlregE_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ieu_c_controlregE_internal[0] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregE_internal[1] = ieu_c_controlregE_raw_internal[1];
assign ieu_c_controlregE_internal[2] = ieu_c_controlregE_raw_internal[2];
assign ieu_c_controlregE_internal[3] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregE_internal[4] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregE_internal[5] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregE_internal[6] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregE_internal[7] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregE_internal[8] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregE_internal[9] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregE_internal[10] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregE_internal[11] = ieu_c_controlregE_raw_internal[11];
assign ieu_c_controlregE_internal[12] = ieu_c_controlregE_raw_internal[12];
assign ieu_c_controlregE_internal[13] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregE_internal[14] = ieu_c_controlregE_raw_internal[14];
assign ieu_c_controlregE_internal[15] = ieu_c_controlregE_raw_internal[15];
assign ieu_c_controlregE_internal[16] = ieu_c_controlregE_raw_internal[16];
assign ieu_c_controlregE_internal[17] = ieu_c_controlregE_raw_internal[17];
assign ieu_c_controlregE_internal[18] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregE_internal[19] = ieu_c_controlregE_raw_internal[19];
assign ieu_c_controlregE_internal[20] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregE_internal[21] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregE_internal[22] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregE_internal[23] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregE_internal[24] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregE_internal[25] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregE_internal[26] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregE_internal[27] = ieu_c_controlregE_raw_internal[27];
assign ieu_c_controlregE_internal[28] = ieu_c_controlregE_raw_internal[28];
assign ieu_c_controlregE_internal[29] = ieu_c_controlregE_raw_internal[29];
assign ieu_c_controlregE_internal[30] = ieu_c_controlregE_raw_internal[30];
assign ieu_c_controlregE_internal[31] = ieu_c_controlregE_raw_internal[31];
assign ieu_c_controlregE_internal[32] = ieu_c_controlregE_raw_internal[32];
assign ieu_c_controlregE_internal[33] = ieu_c_controlregE_raw_internal[33];
assign ieu_c_controlregE_internal[34] = ieu_c_controlregE_raw_internal[34];
assign ieu_c_controlregE_internal[35] = ieu_c_controlregE_raw_internal[35];
assign ieu_c_controlregE_internal[36] = ieu_c_controlregE_raw_internal[36];
assign ieu_c_controlregE_internal[37] = ieu_c_controlregE_raw_internal[37];
assign ieu_c_controlregE_internal[38] = ieu_c_controlregE_raw_internal[38];
assign ieu_c_controlregE_internal[39] = ieu_c_controlregE_raw_internal[39];
assign ieu_c_controlregE_internal[40] = ieu_c_controlregE_raw_internal[40];
assign ieu_c_controlregE_internal[41] = ieu_c_controlregE_raw_internal[41];
assign ieu_c_controlregE_internal[42] = ieu_c_controlregE_raw_internal[42];
assign ieu_c_controlregE_internal[43] = ieu_c_controlregE_raw_internal[43];
assign ieu_c_controlregE_internal[44] = ieu_c_controlregE_raw_internal[44];
assign ieu_c_controlregE_internal[45] = ieu_c_controlregE_raw_internal[45];
assign ieu_c_controlregE_internal[46] = ieu_c_controlregE_raw_internal[46];

// ---- ieu_c_controlregE_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ieu_c_controlregE_pin_internal[0] = 1'bz; // unavailable scan pin
assign ieu_c_controlregE_pin_internal[1] = dut.chip.soc_core_ieu_c_controlregE_q_reg_1_.Q;
assign ieu_c_controlregE_pin_internal[2] = dut.chip.soc_core_ieu_c_controlregE_q_reg_2_.Q;
assign ieu_c_controlregE_pin_internal[3] = 1'bz; // unavailable scan pin
assign ieu_c_controlregE_pin_internal[4] = 1'bz; // unavailable scan pin
assign ieu_c_controlregE_pin_internal[5] = 1'bz; // unavailable scan pin
assign ieu_c_controlregE_pin_internal[6] = 1'bz; // unavailable scan pin
assign ieu_c_controlregE_pin_internal[7] = 1'bz; // unavailable scan pin
assign ieu_c_controlregE_pin_internal[8] = 1'bz; // unavailable scan pin
assign ieu_c_controlregE_pin_internal[9] = 1'bz; // unavailable scan pin
assign ieu_c_controlregE_pin_internal[10] = 1'bz; // unavailable scan pin
assign ieu_c_controlregE_pin_internal[11] = dut.chip.soc_core_ieu_c_controlregE_q_reg_11_.Q;
assign ieu_c_controlregE_pin_internal[12] = dut.chip.soc_core_ieu_c_controlregE_q_reg_12_.Q;
assign ieu_c_controlregE_pin_internal[13] = 1'bz; // unavailable scan pin
assign ieu_c_controlregE_pin_internal[14] = dut.chip.soc_core_ieu_c_controlregE_q_reg_14_.Q;
assign ieu_c_controlregE_pin_internal[15] = dut.chip.soc_core_ieu_c_controlregE_q_reg_15_.Q;
assign ieu_c_controlregE_pin_internal[16] = dut.chip.soc_core_ieu_c_controlregE_q_reg_16_.QN;
assign ieu_c_controlregE_pin_internal[17] = dut.chip.soc_core_ieu_c_controlregE_q_reg_17_.Q;
assign ieu_c_controlregE_pin_internal[18] = 1'bz; // unavailable scan pin
assign ieu_c_controlregE_pin_internal[19] = dut.chip.soc_core_ieu_c_controlregE_q_reg_19_.Q;
assign ieu_c_controlregE_pin_internal[20] = 1'bz; // unavailable scan pin
assign ieu_c_controlregE_pin_internal[21] = 1'bz; // unavailable scan pin
assign ieu_c_controlregE_pin_internal[22] = 1'bz; // unavailable scan pin
assign ieu_c_controlregE_pin_internal[23] = 1'bz; // unavailable scan pin
assign ieu_c_controlregE_pin_internal[24] = 1'bz; // unavailable scan pin
assign ieu_c_controlregE_pin_internal[25] = 1'bz; // unavailable scan pin
assign ieu_c_controlregE_pin_internal[26] = 1'bz; // unavailable scan pin
assign ieu_c_controlregE_pin_internal[27] = dut.chip.soc_core_ieu_c_controlregE_q_reg_27_.Q;
assign ieu_c_controlregE_pin_internal[28] = dut.chip.soc_core_ieu_c_controlregE_q_reg_28_.Q;
assign ieu_c_controlregE_pin_internal[29] = dut.chip.soc_core_ieu_c_controlregE_q_reg_29_.Q;
assign ieu_c_controlregE_pin_internal[30] = dut.chip.soc_core_ieu_c_controlregE_q_reg_30_.Q;
assign ieu_c_controlregE_pin_internal[31] = dut.chip.soc_core_ieu_c_controlregE_q_reg_31_.Q;
assign ieu_c_controlregE_pin_internal[32] = dut.chip.soc_core_ieu_c_controlregE_q_reg_32_.Q;
assign ieu_c_controlregE_pin_internal[33] = dut.chip.soc_core_ieu_c_controlregE_q_reg_33_.QN;
assign ieu_c_controlregE_pin_internal[34] = dut.chip.soc_core_ieu_c_controlregE_q_reg_34_.QN;
assign ieu_c_controlregE_pin_internal[35] = dut.chip.soc_core_ieu_c_controlregE_q_reg_35_.QN;
assign ieu_c_controlregE_pin_internal[36] = dut.chip.soc_core_ieu_c_controlregE_q_reg_36_.Q;
assign ieu_c_controlregE_pin_internal[37] = dut.chip.soc_core_ieu_c_controlregE_q_reg_37_.Q;
assign ieu_c_controlregE_pin_internal[38] = dut.chip.soc_core_ieu_c_controlregE_q_reg_38_.Q;
assign ieu_c_controlregE_pin_internal[39] = dut.chip.soc_core_ieu_c_controlregE_q_reg_39_.Q;
assign ieu_c_controlregE_pin_internal[40] = dut.chip.soc_core_ieu_c_controlregE_q_reg_40_.Q;
assign ieu_c_controlregE_pin_internal[41] = dut.chip.soc_core_ieu_c_controlregE_q_reg_41_.Q;
assign ieu_c_controlregE_pin_internal[42] = dut.chip.soc_core_ieu_c_controlregE_q_reg_42_.QN;
assign ieu_c_controlregE_pin_internal[43] = dut.chip.soc_core_ieu_c_controlregE_q_reg_43_.Q;
assign ieu_c_controlregE_pin_internal[44] = dut.chip.soc_core_ieu_c_controlregE_q_reg_44_.Q;
assign ieu_c_controlregE_pin_internal[45] = dut.chip.soc_core_ieu_c_controlregE_q_reg_45_.Q;
assign ieu_c_controlregE_pin_internal[46] = dut.chip.soc_core_ieu_c_controlregE_q_reg_46_.Q;

// ---- ieu_c_controlregE_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ieu_c_controlregE_raw_internal_available[0] = 1'b0;
assign ieu_c_controlregE_raw_internal_available[1] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[2] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[3] = 1'b0;
assign ieu_c_controlregE_raw_internal_available[4] = 1'b0;
assign ieu_c_controlregE_raw_internal_available[5] = 1'b0;
assign ieu_c_controlregE_raw_internal_available[6] = 1'b0;
assign ieu_c_controlregE_raw_internal_available[7] = 1'b0;
assign ieu_c_controlregE_raw_internal_available[8] = 1'b0;
assign ieu_c_controlregE_raw_internal_available[9] = 1'b0;
assign ieu_c_controlregE_raw_internal_available[10] = 1'b0;
assign ieu_c_controlregE_raw_internal_available[11] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[12] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[13] = 1'b0;
assign ieu_c_controlregE_raw_internal_available[14] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[15] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[16] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[17] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[18] = 1'b0;
assign ieu_c_controlregE_raw_internal_available[19] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[20] = 1'b0;
assign ieu_c_controlregE_raw_internal_available[21] = 1'b0;
assign ieu_c_controlregE_raw_internal_available[22] = 1'b0;
assign ieu_c_controlregE_raw_internal_available[23] = 1'b0;
assign ieu_c_controlregE_raw_internal_available[24] = 1'b0;
assign ieu_c_controlregE_raw_internal_available[25] = 1'b0;
assign ieu_c_controlregE_raw_internal_available[26] = 1'b0;
assign ieu_c_controlregE_raw_internal_available[27] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[28] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[29] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[30] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[31] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[32] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[33] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[34] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[35] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[36] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[37] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[38] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[39] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[40] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[41] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[42] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[43] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[44] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[45] = 1'b1;
assign ieu_c_controlregE_raw_internal_available[46] = 1'b1;

// ============================================================================
// Register ieu_c_controlregM: 18 mapped bits, width 27
// ============================================================================

// Bus declarations
wire [26:0] ieu_c_controlregM_internal;
wire [26:0] ieu_c_controlregM_raw_internal;
wire [26:0] ieu_c_controlregM_pin_internal;
wire [26:0] ieu_c_controlregM_raw_internal_available;

// ---- ieu_c_controlregM_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ieu_c_controlregM_raw_internal[0] = 1'bz; // unavailable physical Q
assign ieu_c_controlregM_raw_internal[1] = dut.chip.soc_core_ieu_c_controlregM_q_reg_1_.Q; // c0[59]
assign ieu_c_controlregM_raw_internal[2] = 1'bz; // unavailable physical Q
assign ieu_c_controlregM_raw_internal[3] = 1'bz; // unavailable physical Q
assign ieu_c_controlregM_raw_internal[4] = 1'bz; // unavailable physical Q
assign ieu_c_controlregM_raw_internal[5] = 1'bz; // unavailable physical Q
assign ieu_c_controlregM_raw_internal[6] = 1'bz; // unavailable physical Q
assign ieu_c_controlregM_raw_internal[7] = 1'bz; // unavailable physical Q
assign ieu_c_controlregM_raw_internal[8] = dut.chip.soc_core_ieu_c_controlregM_q_reg_8_.Q; // c0[60]
assign ieu_c_controlregM_raw_internal[9] = dut.chip.soc_core_ieu_c_controlregM_q_reg_9_.Q; // c0[61]
assign ieu_c_controlregM_raw_internal[10] = dut.chip.soc_core_ieu_c_controlregM_q_reg_10_.Q; // c0[62]
assign ieu_c_controlregM_raw_internal[11] = 1'bz; // unavailable physical Q
assign ieu_c_controlregM_raw_internal[12] = dut.chip.soc_core_ieu_c_controlregM_q_reg_12_.Q; // c0[63]
assign ieu_c_controlregM_raw_internal[13] = dut.chip.soc_core_ieu_c_controlregM_q_reg_13_.Q; // c0[64]
assign ieu_c_controlregM_raw_internal[14] = 1'bz; // unavailable physical Q
assign ieu_c_controlregM_raw_internal[15] = ~dut.chip.soc_core_ieu_c_controlregM_q_reg_15_.QN; // c0[65]
assign ieu_c_controlregM_raw_internal[16] = dut.chip.soc_core_ieu_c_controlregM_q_reg_16_.Q; // c0[66]
assign ieu_c_controlregM_raw_internal[17] = ~dut.chip.soc_core_ieu_c_controlregM_q_reg_17_.QN; // c0[67]
assign ieu_c_controlregM_raw_internal[18] = dut.chip.soc_core_ieu_c_controlregM_q_reg_18_.Q; // c0[68]
assign ieu_c_controlregM_raw_internal[19] = dut.chip.soc_core_ieu_c_controlregM_q_reg_19_.Q; // c0[69]
assign ieu_c_controlregM_raw_internal[20] = dut.chip.soc_core_ieu_c_controlregM_q_reg_20_.Q; // c0[70]
assign ieu_c_controlregM_raw_internal[21] = dut.chip.soc_core_ieu_c_controlregM_q_reg_21_.Q; // c0[71]
assign ieu_c_controlregM_raw_internal[22] = dut.chip.soc_core_ieu_c_controlregM_q_reg_22_.Q; // c0[72]
assign ieu_c_controlregM_raw_internal[23] = dut.chip.soc_core_ieu_c_controlregM_q_reg_23_.Q; // c0[73]
assign ieu_c_controlregM_raw_internal[24] = dut.chip.soc_core_ieu_c_controlregM_q_reg_24_.Q; // c0[74]
assign ieu_c_controlregM_raw_internal[25] = dut.chip.soc_core_ieu_c_controlregM_q_reg_25_.Q; // c0[75]
assign ieu_c_controlregM_raw_internal[26] = dut.chip.soc_core_ieu_c_controlregM_q_reg_26_.Q; // c0[76]

// ---- ieu_c_controlregM_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ieu_c_controlregM_internal[0] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregM_internal[1] = ieu_c_controlregM_raw_internal[1];
assign ieu_c_controlregM_internal[2] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregM_internal[3] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregM_internal[4] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregM_internal[5] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregM_internal[6] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregM_internal[7] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregM_internal[8] = ieu_c_controlregM_raw_internal[8];
assign ieu_c_controlregM_internal[9] = ieu_c_controlregM_raw_internal[9];
assign ieu_c_controlregM_internal[10] = ieu_c_controlregM_raw_internal[10];
assign ieu_c_controlregM_internal[11] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregM_internal[12] = ieu_c_controlregM_raw_internal[12];
assign ieu_c_controlregM_internal[13] = ieu_c_controlregM_raw_internal[13];
assign ieu_c_controlregM_internal[14] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregM_internal[15] = ieu_c_controlregM_raw_internal[15];
assign ieu_c_controlregM_internal[16] = ieu_c_controlregM_raw_internal[16];
assign ieu_c_controlregM_internal[17] = ieu_c_controlregM_raw_internal[17];
assign ieu_c_controlregM_internal[18] = ieu_c_controlregM_raw_internal[18];
assign ieu_c_controlregM_internal[19] = ieu_c_controlregM_raw_internal[19];
assign ieu_c_controlregM_internal[20] = ieu_c_controlregM_raw_internal[20];
assign ieu_c_controlregM_internal[21] = ieu_c_controlregM_raw_internal[21];
assign ieu_c_controlregM_internal[22] = ieu_c_controlregM_raw_internal[22];
assign ieu_c_controlregM_internal[23] = ieu_c_controlregM_raw_internal[23];
assign ieu_c_controlregM_internal[24] = ieu_c_controlregM_raw_internal[24];
assign ieu_c_controlregM_internal[25] = ieu_c_controlregM_raw_internal[25];
assign ieu_c_controlregM_internal[26] = ieu_c_controlregM_raw_internal[26];

// ---- ieu_c_controlregM_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ieu_c_controlregM_pin_internal[0] = 1'bz; // unavailable scan pin
assign ieu_c_controlregM_pin_internal[1] = dut.chip.soc_core_ieu_c_controlregM_q_reg_1_.Q;
assign ieu_c_controlregM_pin_internal[2] = 1'bz; // unavailable scan pin
assign ieu_c_controlregM_pin_internal[3] = 1'bz; // unavailable scan pin
assign ieu_c_controlregM_pin_internal[4] = 1'bz; // unavailable scan pin
assign ieu_c_controlregM_pin_internal[5] = 1'bz; // unavailable scan pin
assign ieu_c_controlregM_pin_internal[6] = 1'bz; // unavailable scan pin
assign ieu_c_controlregM_pin_internal[7] = 1'bz; // unavailable scan pin
assign ieu_c_controlregM_pin_internal[8] = dut.chip.soc_core_ieu_c_controlregM_q_reg_8_.Q;
assign ieu_c_controlregM_pin_internal[9] = dut.chip.soc_core_ieu_c_controlregM_q_reg_9_.Q;
assign ieu_c_controlregM_pin_internal[10] = dut.chip.soc_core_ieu_c_controlregM_q_reg_10_.Q;
assign ieu_c_controlregM_pin_internal[11] = 1'bz; // unavailable scan pin
assign ieu_c_controlregM_pin_internal[12] = dut.chip.soc_core_ieu_c_controlregM_q_reg_12_.Q;
assign ieu_c_controlregM_pin_internal[13] = dut.chip.soc_core_ieu_c_controlregM_q_reg_13_.Q;
assign ieu_c_controlregM_pin_internal[14] = 1'bz; // unavailable scan pin
assign ieu_c_controlregM_pin_internal[15] = dut.chip.soc_core_ieu_c_controlregM_q_reg_15_.QN;
assign ieu_c_controlregM_pin_internal[16] = dut.chip.soc_core_ieu_c_controlregM_q_reg_16_.Q;
assign ieu_c_controlregM_pin_internal[17] = dut.chip.soc_core_ieu_c_controlregM_q_reg_17_.QN;
assign ieu_c_controlregM_pin_internal[18] = dut.chip.soc_core_ieu_c_controlregM_q_reg_18_.Q;
assign ieu_c_controlregM_pin_internal[19] = dut.chip.soc_core_ieu_c_controlregM_q_reg_19_.Q;
assign ieu_c_controlregM_pin_internal[20] = dut.chip.soc_core_ieu_c_controlregM_q_reg_20_.Q;
assign ieu_c_controlregM_pin_internal[21] = dut.chip.soc_core_ieu_c_controlregM_q_reg_21_.Q;
assign ieu_c_controlregM_pin_internal[22] = dut.chip.soc_core_ieu_c_controlregM_q_reg_22_.Q;
assign ieu_c_controlregM_pin_internal[23] = dut.chip.soc_core_ieu_c_controlregM_q_reg_23_.Q;
assign ieu_c_controlregM_pin_internal[24] = dut.chip.soc_core_ieu_c_controlregM_q_reg_24_.Q;
assign ieu_c_controlregM_pin_internal[25] = dut.chip.soc_core_ieu_c_controlregM_q_reg_25_.Q;
assign ieu_c_controlregM_pin_internal[26] = dut.chip.soc_core_ieu_c_controlregM_q_reg_26_.Q;

// ---- ieu_c_controlregM_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ieu_c_controlregM_raw_internal_available[0] = 1'b0;
assign ieu_c_controlregM_raw_internal_available[1] = 1'b1;
assign ieu_c_controlregM_raw_internal_available[2] = 1'b0;
assign ieu_c_controlregM_raw_internal_available[3] = 1'b0;
assign ieu_c_controlregM_raw_internal_available[4] = 1'b0;
assign ieu_c_controlregM_raw_internal_available[5] = 1'b0;
assign ieu_c_controlregM_raw_internal_available[6] = 1'b0;
assign ieu_c_controlregM_raw_internal_available[7] = 1'b0;
assign ieu_c_controlregM_raw_internal_available[8] = 1'b1;
assign ieu_c_controlregM_raw_internal_available[9] = 1'b1;
assign ieu_c_controlregM_raw_internal_available[10] = 1'b1;
assign ieu_c_controlregM_raw_internal_available[11] = 1'b0;
assign ieu_c_controlregM_raw_internal_available[12] = 1'b1;
assign ieu_c_controlregM_raw_internal_available[13] = 1'b1;
assign ieu_c_controlregM_raw_internal_available[14] = 1'b0;
assign ieu_c_controlregM_raw_internal_available[15] = 1'b1;
assign ieu_c_controlregM_raw_internal_available[16] = 1'b1;
assign ieu_c_controlregM_raw_internal_available[17] = 1'b1;
assign ieu_c_controlregM_raw_internal_available[18] = 1'b1;
assign ieu_c_controlregM_raw_internal_available[19] = 1'b1;
assign ieu_c_controlregM_raw_internal_available[20] = 1'b1;
assign ieu_c_controlregM_raw_internal_available[21] = 1'b1;
assign ieu_c_controlregM_raw_internal_available[22] = 1'b1;
assign ieu_c_controlregM_raw_internal_available[23] = 1'b1;
assign ieu_c_controlregM_raw_internal_available[24] = 1'b1;
assign ieu_c_controlregM_raw_internal_available[25] = 1'b1;
assign ieu_c_controlregM_raw_internal_available[26] = 1'b1;

// ============================================================================
// Register ieu_c_controlregW: 5 mapped bits, width 7
// ============================================================================

// Bus declarations
wire [6:0] ieu_c_controlregW_internal;
wire [6:0] ieu_c_controlregW_raw_internal;
wire [6:0] ieu_c_controlregW_pin_internal;
wire [6:0] ieu_c_controlregW_raw_internal_available;

// ---- ieu_c_controlregW_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ieu_c_controlregW_raw_internal[0] = 1'bz; // unavailable physical Q
assign ieu_c_controlregW_raw_internal[1] = dut.chip.soc_core_ieu_c_controlregW_q_reg_1_.Q; // c0[77]
assign ieu_c_controlregW_raw_internal[2] = 1'bz; // unavailable physical Q
assign ieu_c_controlregW_raw_internal[3] = dut.chip.soc_core_ieu_c_controlregW_q_reg_3_.Q; // c0[78]
assign ieu_c_controlregW_raw_internal[4] = dut.chip.soc_core_ieu_c_controlregW_q_reg_4_.Q; // c0[79]
assign ieu_c_controlregW_raw_internal[5] = dut.chip.soc_core_ieu_c_controlregW_q_reg_5_.Q; // c0[80]
assign ieu_c_controlregW_raw_internal[6] = dut.chip.soc_core_ieu_c_controlregW_q_reg_6_.Q; // c0[81]

// ---- ieu_c_controlregW_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ieu_c_controlregW_internal[0] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregW_internal[1] = ieu_c_controlregW_raw_internal[1];
assign ieu_c_controlregW_internal[2] = 1'bz; // unavailable logical estimate
assign ieu_c_controlregW_internal[3] = ieu_c_controlregW_raw_internal[3];
assign ieu_c_controlregW_internal[4] = ieu_c_controlregW_raw_internal[4];
assign ieu_c_controlregW_internal[5] = ieu_c_controlregW_raw_internal[5];
assign ieu_c_controlregW_internal[6] = ieu_c_controlregW_raw_internal[6];

// ---- ieu_c_controlregW_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ieu_c_controlregW_pin_internal[0] = 1'bz; // unavailable scan pin
assign ieu_c_controlregW_pin_internal[1] = dut.chip.soc_core_ieu_c_controlregW_q_reg_1_.Q;
assign ieu_c_controlregW_pin_internal[2] = 1'bz; // unavailable scan pin
assign ieu_c_controlregW_pin_internal[3] = dut.chip.soc_core_ieu_c_controlregW_q_reg_3_.Q;
assign ieu_c_controlregW_pin_internal[4] = dut.chip.soc_core_ieu_c_controlregW_q_reg_4_.Q;
assign ieu_c_controlregW_pin_internal[5] = dut.chip.soc_core_ieu_c_controlregW_q_reg_5_.Q;
assign ieu_c_controlregW_pin_internal[6] = dut.chip.soc_core_ieu_c_controlregW_q_reg_6_.Q;

// ---- ieu_c_controlregW_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ieu_c_controlregW_raw_internal_available[0] = 1'b0;
assign ieu_c_controlregW_raw_internal_available[1] = 1'b1;
assign ieu_c_controlregW_raw_internal_available[2] = 1'b0;
assign ieu_c_controlregW_raw_internal_available[3] = 1'b1;
assign ieu_c_controlregW_raw_internal_available[4] = 1'b1;
assign ieu_c_controlregW_raw_internal_available[5] = 1'b1;
assign ieu_c_controlregW_raw_internal_available[6] = 1'b1;

// ============================================================================
// Register ieu_dp_IEUResultMReg: 72 mapped bits, width 72
// ============================================================================

// Bus declarations
wire [71:0] ieu_dp_IEUResultMReg_internal;
wire [71:0] ieu_dp_IEUResultMReg_raw_internal;
wire [71:0] ieu_dp_IEUResultMReg_pin_internal;
wire [71:0] ieu_dp_IEUResultMReg_raw_internal_available;

// ---- ieu_dp_IEUResultMReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ieu_dp_IEUResultMReg_raw_internal[0] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_0_.Q; // c0[82]
assign ieu_dp_IEUResultMReg_raw_internal[1] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_1_.Q; // c0[83]
assign ieu_dp_IEUResultMReg_raw_internal[2] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_2_.Q; // c0[84]
assign ieu_dp_IEUResultMReg_raw_internal[3] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_3_.Q; // c0[85]
assign ieu_dp_IEUResultMReg_raw_internal[4] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_4_.Q; // c0[86]
assign ieu_dp_IEUResultMReg_raw_internal[5] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_5_.Q; // c0[87]
assign ieu_dp_IEUResultMReg_raw_internal[6] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_6_.Q; // c0[88]
assign ieu_dp_IEUResultMReg_raw_internal[7] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_7_.Q; // c0[89]
assign ieu_dp_IEUResultMReg_raw_internal[8] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_8_.Q; // c0[90]
assign ieu_dp_IEUResultMReg_raw_internal[9] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_9_.Q; // c0[91]
assign ieu_dp_IEUResultMReg_raw_internal[10] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_10_.Q; // c0[92]
assign ieu_dp_IEUResultMReg_raw_internal[11] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_11_.Q; // c0[93]
assign ieu_dp_IEUResultMReg_raw_internal[12] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_12_.Q; // c0[94]
assign ieu_dp_IEUResultMReg_raw_internal[13] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_13_.Q; // c0[95]
assign ieu_dp_IEUResultMReg_raw_internal[14] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_14_.Q; // c0[96]
assign ieu_dp_IEUResultMReg_raw_internal[15] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_15_.Q; // c0[97]
assign ieu_dp_IEUResultMReg_raw_internal[16] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_16_.Q; // c0[98]
assign ieu_dp_IEUResultMReg_raw_internal[17] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_17_.Q; // c0[99]
assign ieu_dp_IEUResultMReg_raw_internal[18] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_18_.Q; // c0[100]
assign ieu_dp_IEUResultMReg_raw_internal[19] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_19_.Q; // c0[101]
assign ieu_dp_IEUResultMReg_raw_internal[20] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_20_.Q; // c0[102]
assign ieu_dp_IEUResultMReg_raw_internal[21] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_21_.Q; // c0[103]
assign ieu_dp_IEUResultMReg_raw_internal[22] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_22_.Q; // c0[104]
assign ieu_dp_IEUResultMReg_raw_internal[23] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_23_.Q; // c0[105]
assign ieu_dp_IEUResultMReg_raw_internal[24] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_24_.Q; // c0[106]
assign ieu_dp_IEUResultMReg_raw_internal[25] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_25_.Q; // c0[107]
assign ieu_dp_IEUResultMReg_raw_internal[26] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_26_.Q; // c0[108]
assign ieu_dp_IEUResultMReg_raw_internal[27] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_27_.Q; // c0[109]
assign ieu_dp_IEUResultMReg_raw_internal[28] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_28_.Q; // c0[110]
assign ieu_dp_IEUResultMReg_raw_internal[29] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_29_.Q; // c0[111]
assign ieu_dp_IEUResultMReg_raw_internal[30] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_30_.Q; // c0[112]
assign ieu_dp_IEUResultMReg_raw_internal[31] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_31_.Q; // c0[113]
assign ieu_dp_IEUResultMReg_raw_internal[32] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_32_.Q; // c0[114]
assign ieu_dp_IEUResultMReg_raw_internal[33] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_33_.Q; // c0[115]
assign ieu_dp_IEUResultMReg_raw_internal[34] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_34_.Q; // c0[116]
assign ieu_dp_IEUResultMReg_raw_internal[35] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_35_.Q; // c0[117]
assign ieu_dp_IEUResultMReg_raw_internal[36] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_36_.Q; // c0[118]
assign ieu_dp_IEUResultMReg_raw_internal[37] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_37_.Q; // c0[119]
assign ieu_dp_IEUResultMReg_raw_internal[38] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_38_.Q; // c0[120]
assign ieu_dp_IEUResultMReg_raw_internal[39] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_39_.Q; // c0[121]
assign ieu_dp_IEUResultMReg_raw_internal[40] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_40_.Q; // c0[122]
assign ieu_dp_IEUResultMReg_raw_internal[41] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_41_.Q; // c0[123]
assign ieu_dp_IEUResultMReg_raw_internal[42] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_42_.Q; // c0[124]
assign ieu_dp_IEUResultMReg_raw_internal[43] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_43_.Q; // c0[125]
assign ieu_dp_IEUResultMReg_raw_internal[44] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_44_.Q; // c0[126]
assign ieu_dp_IEUResultMReg_raw_internal[45] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_45_.Q; // c0[127]
assign ieu_dp_IEUResultMReg_raw_internal[46] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_46_.Q; // c0[128]
assign ieu_dp_IEUResultMReg_raw_internal[47] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_47_.Q; // c0[129]
assign ieu_dp_IEUResultMReg_raw_internal[48] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_48_.Q; // c0[130]
assign ieu_dp_IEUResultMReg_raw_internal[49] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_49_.Q; // c0[131]
assign ieu_dp_IEUResultMReg_raw_internal[50] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_50_.Q; // c0[132]
assign ieu_dp_IEUResultMReg_raw_internal[51] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_51_.Q; // c0[133]
assign ieu_dp_IEUResultMReg_raw_internal[52] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_52_.Q; // c0[134]
assign ieu_dp_IEUResultMReg_raw_internal[53] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_53_.Q; // c0[135]
assign ieu_dp_IEUResultMReg_raw_internal[54] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_54_.Q; // c0[136]
assign ieu_dp_IEUResultMReg_raw_internal[55] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_55_.Q; // c0[137]
assign ieu_dp_IEUResultMReg_raw_internal[56] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_56_.Q; // c0[138]
assign ieu_dp_IEUResultMReg_raw_internal[57] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_57_.Q; // c0[139]
assign ieu_dp_IEUResultMReg_raw_internal[58] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_58_.Q; // c0[140]
assign ieu_dp_IEUResultMReg_raw_internal[59] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_59_.Q; // c0[141]
assign ieu_dp_IEUResultMReg_raw_internal[60] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_60_.Q; // c0[142]
assign ieu_dp_IEUResultMReg_raw_internal[61] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_61_.Q; // c0[143]
assign ieu_dp_IEUResultMReg_raw_internal[62] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_62_.Q; // c0[144]
assign ieu_dp_IEUResultMReg_raw_internal[63] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_63_.Q; // c0[145]
assign ieu_dp_IEUResultMReg_raw_internal[64] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_64_.Q; // c0[146]
assign ieu_dp_IEUResultMReg_raw_internal[65] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_65_.Q; // c0[147]
assign ieu_dp_IEUResultMReg_raw_internal[66] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_66_.Q; // c0[148]
assign ieu_dp_IEUResultMReg_raw_internal[67] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_67_.Q; // c0[149]
assign ieu_dp_IEUResultMReg_raw_internal[68] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_68_.Q; // c0[150]
assign ieu_dp_IEUResultMReg_raw_internal[69] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_69_.Q; // c0[151]
assign ieu_dp_IEUResultMReg_raw_internal[70] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_70_.Q; // c0[152]
assign ieu_dp_IEUResultMReg_raw_internal[71] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_71_.Q; // c0[153]

// ---- ieu_dp_IEUResultMReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ieu_dp_IEUResultMReg_internal[0] = ieu_dp_IEUResultMReg_raw_internal[0];
assign ieu_dp_IEUResultMReg_internal[1] = ieu_dp_IEUResultMReg_raw_internal[1];
assign ieu_dp_IEUResultMReg_internal[2] = ieu_dp_IEUResultMReg_raw_internal[2];
assign ieu_dp_IEUResultMReg_internal[3] = ieu_dp_IEUResultMReg_raw_internal[3];
assign ieu_dp_IEUResultMReg_internal[4] = ieu_dp_IEUResultMReg_raw_internal[4];
assign ieu_dp_IEUResultMReg_internal[5] = ieu_dp_IEUResultMReg_raw_internal[5];
assign ieu_dp_IEUResultMReg_internal[6] = ieu_dp_IEUResultMReg_raw_internal[6];
assign ieu_dp_IEUResultMReg_internal[7] = ieu_dp_IEUResultMReg_raw_internal[7];
assign ieu_dp_IEUResultMReg_internal[8] = ieu_dp_IEUResultMReg_raw_internal[8];
assign ieu_dp_IEUResultMReg_internal[9] = ieu_dp_IEUResultMReg_raw_internal[9];
assign ieu_dp_IEUResultMReg_internal[10] = ieu_dp_IEUResultMReg_raw_internal[10];
assign ieu_dp_IEUResultMReg_internal[11] = ieu_dp_IEUResultMReg_raw_internal[11];
assign ieu_dp_IEUResultMReg_internal[12] = ieu_dp_IEUResultMReg_raw_internal[12];
assign ieu_dp_IEUResultMReg_internal[13] = ieu_dp_IEUResultMReg_raw_internal[13];
assign ieu_dp_IEUResultMReg_internal[14] = ieu_dp_IEUResultMReg_raw_internal[14];
assign ieu_dp_IEUResultMReg_internal[15] = ieu_dp_IEUResultMReg_raw_internal[15];
assign ieu_dp_IEUResultMReg_internal[16] = ieu_dp_IEUResultMReg_raw_internal[16];
assign ieu_dp_IEUResultMReg_internal[17] = ieu_dp_IEUResultMReg_raw_internal[17];
assign ieu_dp_IEUResultMReg_internal[18] = ieu_dp_IEUResultMReg_raw_internal[18];
assign ieu_dp_IEUResultMReg_internal[19] = ieu_dp_IEUResultMReg_raw_internal[19];
assign ieu_dp_IEUResultMReg_internal[20] = ieu_dp_IEUResultMReg_raw_internal[20];
assign ieu_dp_IEUResultMReg_internal[21] = ieu_dp_IEUResultMReg_raw_internal[21];
assign ieu_dp_IEUResultMReg_internal[22] = ieu_dp_IEUResultMReg_raw_internal[22];
assign ieu_dp_IEUResultMReg_internal[23] = ieu_dp_IEUResultMReg_raw_internal[23];
assign ieu_dp_IEUResultMReg_internal[24] = ieu_dp_IEUResultMReg_raw_internal[24];
assign ieu_dp_IEUResultMReg_internal[25] = ieu_dp_IEUResultMReg_raw_internal[25];
assign ieu_dp_IEUResultMReg_internal[26] = ieu_dp_IEUResultMReg_raw_internal[26];
assign ieu_dp_IEUResultMReg_internal[27] = ieu_dp_IEUResultMReg_raw_internal[27];
assign ieu_dp_IEUResultMReg_internal[28] = ieu_dp_IEUResultMReg_raw_internal[28];
assign ieu_dp_IEUResultMReg_internal[29] = ieu_dp_IEUResultMReg_raw_internal[29];
assign ieu_dp_IEUResultMReg_internal[30] = ieu_dp_IEUResultMReg_raw_internal[30];
assign ieu_dp_IEUResultMReg_internal[31] = ieu_dp_IEUResultMReg_raw_internal[31];
assign ieu_dp_IEUResultMReg_internal[32] = ieu_dp_IEUResultMReg_raw_internal[32];
assign ieu_dp_IEUResultMReg_internal[33] = ieu_dp_IEUResultMReg_raw_internal[33];
assign ieu_dp_IEUResultMReg_internal[34] = ieu_dp_IEUResultMReg_raw_internal[34];
assign ieu_dp_IEUResultMReg_internal[35] = ieu_dp_IEUResultMReg_raw_internal[35];
assign ieu_dp_IEUResultMReg_internal[36] = ieu_dp_IEUResultMReg_raw_internal[36];
assign ieu_dp_IEUResultMReg_internal[37] = ieu_dp_IEUResultMReg_raw_internal[37];
assign ieu_dp_IEUResultMReg_internal[38] = ieu_dp_IEUResultMReg_raw_internal[38];
assign ieu_dp_IEUResultMReg_internal[39] = ieu_dp_IEUResultMReg_raw_internal[39];
assign ieu_dp_IEUResultMReg_internal[40] = ieu_dp_IEUResultMReg_raw_internal[40];
assign ieu_dp_IEUResultMReg_internal[41] = ieu_dp_IEUResultMReg_raw_internal[41];
assign ieu_dp_IEUResultMReg_internal[42] = ieu_dp_IEUResultMReg_raw_internal[42];
assign ieu_dp_IEUResultMReg_internal[43] = ieu_dp_IEUResultMReg_raw_internal[43];
assign ieu_dp_IEUResultMReg_internal[44] = ieu_dp_IEUResultMReg_raw_internal[44];
assign ieu_dp_IEUResultMReg_internal[45] = ieu_dp_IEUResultMReg_raw_internal[45];
assign ieu_dp_IEUResultMReg_internal[46] = ieu_dp_IEUResultMReg_raw_internal[46];
assign ieu_dp_IEUResultMReg_internal[47] = ieu_dp_IEUResultMReg_raw_internal[47];
assign ieu_dp_IEUResultMReg_internal[48] = ieu_dp_IEUResultMReg_raw_internal[48];
assign ieu_dp_IEUResultMReg_internal[49] = ieu_dp_IEUResultMReg_raw_internal[49];
assign ieu_dp_IEUResultMReg_internal[50] = ieu_dp_IEUResultMReg_raw_internal[50];
assign ieu_dp_IEUResultMReg_internal[51] = ieu_dp_IEUResultMReg_raw_internal[51];
assign ieu_dp_IEUResultMReg_internal[52] = ieu_dp_IEUResultMReg_raw_internal[52];
assign ieu_dp_IEUResultMReg_internal[53] = ieu_dp_IEUResultMReg_raw_internal[53];
assign ieu_dp_IEUResultMReg_internal[54] = ieu_dp_IEUResultMReg_raw_internal[54];
assign ieu_dp_IEUResultMReg_internal[55] = ieu_dp_IEUResultMReg_raw_internal[55];
assign ieu_dp_IEUResultMReg_internal[56] = ieu_dp_IEUResultMReg_raw_internal[56];
assign ieu_dp_IEUResultMReg_internal[57] = ieu_dp_IEUResultMReg_raw_internal[57];
assign ieu_dp_IEUResultMReg_internal[58] = ieu_dp_IEUResultMReg_raw_internal[58];
assign ieu_dp_IEUResultMReg_internal[59] = ieu_dp_IEUResultMReg_raw_internal[59];
assign ieu_dp_IEUResultMReg_internal[60] = ieu_dp_IEUResultMReg_raw_internal[60];
assign ieu_dp_IEUResultMReg_internal[61] = ieu_dp_IEUResultMReg_raw_internal[61];
assign ieu_dp_IEUResultMReg_internal[62] = ieu_dp_IEUResultMReg_raw_internal[62];
assign ieu_dp_IEUResultMReg_internal[63] = ieu_dp_IEUResultMReg_raw_internal[63];
assign ieu_dp_IEUResultMReg_internal[64] = ieu_dp_IEUResultMReg_raw_internal[64];
assign ieu_dp_IEUResultMReg_internal[65] = ieu_dp_IEUResultMReg_raw_internal[65];
assign ieu_dp_IEUResultMReg_internal[66] = ieu_dp_IEUResultMReg_raw_internal[66];
assign ieu_dp_IEUResultMReg_internal[67] = ieu_dp_IEUResultMReg_raw_internal[67];
assign ieu_dp_IEUResultMReg_internal[68] = ieu_dp_IEUResultMReg_raw_internal[68];
assign ieu_dp_IEUResultMReg_internal[69] = ieu_dp_IEUResultMReg_raw_internal[69];
assign ieu_dp_IEUResultMReg_internal[70] = ieu_dp_IEUResultMReg_raw_internal[70];
assign ieu_dp_IEUResultMReg_internal[71] = ieu_dp_IEUResultMReg_raw_internal[71];

// ---- ieu_dp_IEUResultMReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ieu_dp_IEUResultMReg_pin_internal[0] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_0_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[1] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_1_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[2] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_2_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[3] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_3_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[4] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_4_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[5] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_5_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[6] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_6_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[7] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_7_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[8] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_8_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[9] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_9_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[10] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_10_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[11] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_11_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[12] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_12_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[13] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_13_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[14] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_14_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[15] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_15_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[16] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_16_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[17] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_17_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[18] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_18_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[19] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_19_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[20] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_20_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[21] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_21_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[22] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_22_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[23] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_23_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[24] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_24_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[25] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_25_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[26] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_26_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[27] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_27_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[28] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_28_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[29] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_29_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[30] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_30_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[31] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_31_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[32] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_32_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[33] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_33_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[34] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_34_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[35] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_35_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[36] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_36_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[37] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_37_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[38] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_38_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[39] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_39_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[40] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_40_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[41] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_41_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[42] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_42_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[43] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_43_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[44] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_44_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[45] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_45_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[46] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_46_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[47] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_47_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[48] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_48_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[49] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_49_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[50] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_50_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[51] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_51_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[52] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_52_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[53] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_53_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[54] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_54_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[55] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_55_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[56] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_56_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[57] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_57_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[58] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_58_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[59] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_59_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[60] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_60_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[61] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_61_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[62] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_62_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[63] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_63_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[64] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_64_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[65] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_65_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[66] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_66_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[67] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_67_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[68] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_68_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[69] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_69_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[70] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_70_.Q;
assign ieu_dp_IEUResultMReg_pin_internal[71] = dut.chip.soc_core_ieu_dp_IEUResultMReg_store.cw_stored_reg_71_.Q;

// ---- ieu_dp_IEUResultMReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ieu_dp_IEUResultMReg_raw_internal_available[0] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[1] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[2] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[3] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[4] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[5] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[6] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[7] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[8] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[9] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[10] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[11] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[12] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[13] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[14] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[15] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[16] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[17] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[18] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[19] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[20] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[21] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[22] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[23] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[24] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[25] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[26] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[27] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[28] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[29] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[30] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[31] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[32] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[33] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[34] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[35] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[36] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[37] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[38] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[39] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[40] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[41] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[42] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[43] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[44] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[45] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[46] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[47] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[48] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[49] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[50] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[51] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[52] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[53] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[54] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[55] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[56] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[57] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[58] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[59] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[60] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[61] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[62] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[63] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[64] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[65] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[66] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[67] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[68] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[69] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[70] = 1'b1;
assign ieu_dp_IEUResultMReg_raw_internal_available[71] = 1'b1;

// ============================================================================
// Register ieu_dp_IFResultWReg: 72 mapped bits, width 72
// ============================================================================

// Bus declarations
wire [71:0] ieu_dp_IFResultWReg_internal;
wire [71:0] ieu_dp_IFResultWReg_raw_internal;
wire [71:0] ieu_dp_IFResultWReg_pin_internal;
wire [71:0] ieu_dp_IFResultWReg_raw_internal_available;

// ---- ieu_dp_IFResultWReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ieu_dp_IFResultWReg_raw_internal[0] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_0_.Q; // c0[154]
assign ieu_dp_IFResultWReg_raw_internal[1] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_1_.Q; // c0[155]
assign ieu_dp_IFResultWReg_raw_internal[2] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_2_.Q; // c0[156]
assign ieu_dp_IFResultWReg_raw_internal[3] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_3_.Q; // c0[157]
assign ieu_dp_IFResultWReg_raw_internal[4] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_4_.Q; // c0[158]
assign ieu_dp_IFResultWReg_raw_internal[5] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_5_.Q; // c0[159]
assign ieu_dp_IFResultWReg_raw_internal[6] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_6_.Q; // c0[160]
assign ieu_dp_IFResultWReg_raw_internal[7] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_7_.Q; // c0[161]
assign ieu_dp_IFResultWReg_raw_internal[8] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_8_.Q; // c0[162]
assign ieu_dp_IFResultWReg_raw_internal[9] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_9_.Q; // c0[163]
assign ieu_dp_IFResultWReg_raw_internal[10] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_10_.Q; // c0[164]
assign ieu_dp_IFResultWReg_raw_internal[11] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_11_.Q; // c0[165]
assign ieu_dp_IFResultWReg_raw_internal[12] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_12_.Q; // c0[166]
assign ieu_dp_IFResultWReg_raw_internal[13] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_13_.Q; // c0[167]
assign ieu_dp_IFResultWReg_raw_internal[14] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_14_.Q; // c0[168]
assign ieu_dp_IFResultWReg_raw_internal[15] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_15_.Q; // c0[169]
assign ieu_dp_IFResultWReg_raw_internal[16] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_16_.Q; // c0[170]
assign ieu_dp_IFResultWReg_raw_internal[17] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_17_.Q; // c0[171]
assign ieu_dp_IFResultWReg_raw_internal[18] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_18_.Q; // c0[172]
assign ieu_dp_IFResultWReg_raw_internal[19] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_19_.Q; // c0[173]
assign ieu_dp_IFResultWReg_raw_internal[20] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_20_.Q; // c0[174]
assign ieu_dp_IFResultWReg_raw_internal[21] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_21_.Q; // c0[175]
assign ieu_dp_IFResultWReg_raw_internal[22] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_22_.Q; // c0[176]
assign ieu_dp_IFResultWReg_raw_internal[23] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_23_.Q; // c0[177]
assign ieu_dp_IFResultWReg_raw_internal[24] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_24_.Q; // c0[178]
assign ieu_dp_IFResultWReg_raw_internal[25] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_25_.Q; // c0[179]
assign ieu_dp_IFResultWReg_raw_internal[26] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_26_.Q; // c0[180]
assign ieu_dp_IFResultWReg_raw_internal[27] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_27_.Q; // c0[181]
assign ieu_dp_IFResultWReg_raw_internal[28] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_28_.Q; // c0[182]
assign ieu_dp_IFResultWReg_raw_internal[29] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_29_.Q; // c0[183]
assign ieu_dp_IFResultWReg_raw_internal[30] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_30_.Q; // c0[184]
assign ieu_dp_IFResultWReg_raw_internal[31] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_31_.Q; // c0[185]
assign ieu_dp_IFResultWReg_raw_internal[32] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_32_.Q; // c0[186]
assign ieu_dp_IFResultWReg_raw_internal[33] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_33_.Q; // c1[1]
assign ieu_dp_IFResultWReg_raw_internal[34] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_34_.Q; // c1[2]
assign ieu_dp_IFResultWReg_raw_internal[35] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_35_.Q; // c1[3]
assign ieu_dp_IFResultWReg_raw_internal[36] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_36_.Q; // c1[4]
assign ieu_dp_IFResultWReg_raw_internal[37] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_37_.Q; // c1[5]
assign ieu_dp_IFResultWReg_raw_internal[38] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_38_.Q; // c1[6]
assign ieu_dp_IFResultWReg_raw_internal[39] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_39_.Q; // c1[7]
assign ieu_dp_IFResultWReg_raw_internal[40] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_40_.Q; // c1[8]
assign ieu_dp_IFResultWReg_raw_internal[41] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_41_.Q; // c1[9]
assign ieu_dp_IFResultWReg_raw_internal[42] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_42_.Q; // c1[10]
assign ieu_dp_IFResultWReg_raw_internal[43] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_43_.Q; // c1[11]
assign ieu_dp_IFResultWReg_raw_internal[44] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_44_.Q; // c1[12]
assign ieu_dp_IFResultWReg_raw_internal[45] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_45_.Q; // c1[13]
assign ieu_dp_IFResultWReg_raw_internal[46] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_46_.Q; // c1[14]
assign ieu_dp_IFResultWReg_raw_internal[47] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_47_.Q; // c1[15]
assign ieu_dp_IFResultWReg_raw_internal[48] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_48_.Q; // c1[16]
assign ieu_dp_IFResultWReg_raw_internal[49] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_49_.Q; // c1[17]
assign ieu_dp_IFResultWReg_raw_internal[50] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_50_.Q; // c1[18]
assign ieu_dp_IFResultWReg_raw_internal[51] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_51_.Q; // c1[19]
assign ieu_dp_IFResultWReg_raw_internal[52] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_52_.Q; // c1[20]
assign ieu_dp_IFResultWReg_raw_internal[53] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_53_.Q; // c1[21]
assign ieu_dp_IFResultWReg_raw_internal[54] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_54_.Q; // c1[22]
assign ieu_dp_IFResultWReg_raw_internal[55] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_55_.Q; // c1[23]
assign ieu_dp_IFResultWReg_raw_internal[56] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_56_.Q; // c1[24]
assign ieu_dp_IFResultWReg_raw_internal[57] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_57_.Q; // c1[25]
assign ieu_dp_IFResultWReg_raw_internal[58] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_58_.Q; // c1[26]
assign ieu_dp_IFResultWReg_raw_internal[59] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_59_.Q; // c1[27]
assign ieu_dp_IFResultWReg_raw_internal[60] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_60_.Q; // c1[28]
assign ieu_dp_IFResultWReg_raw_internal[61] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_61_.Q; // c1[29]
assign ieu_dp_IFResultWReg_raw_internal[62] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_62_.Q; // c1[30]
assign ieu_dp_IFResultWReg_raw_internal[63] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_63_.Q; // c1[31]
assign ieu_dp_IFResultWReg_raw_internal[64] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_64_.Q; // c1[32]
assign ieu_dp_IFResultWReg_raw_internal[65] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_65_.Q; // c1[33]
assign ieu_dp_IFResultWReg_raw_internal[66] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_66_.Q; // c1[34]
assign ieu_dp_IFResultWReg_raw_internal[67] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_67_.Q; // c1[35]
assign ieu_dp_IFResultWReg_raw_internal[68] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_68_.Q; // c1[36]
assign ieu_dp_IFResultWReg_raw_internal[69] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_69_.Q; // c1[37]
assign ieu_dp_IFResultWReg_raw_internal[70] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_70_.Q; // c1[38]
assign ieu_dp_IFResultWReg_raw_internal[71] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_71_.Q; // c1[39]

// ---- ieu_dp_IFResultWReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ieu_dp_IFResultWReg_internal[0] = ieu_dp_IFResultWReg_raw_internal[0];
assign ieu_dp_IFResultWReg_internal[1] = ieu_dp_IFResultWReg_raw_internal[1];
assign ieu_dp_IFResultWReg_internal[2] = ieu_dp_IFResultWReg_raw_internal[2];
assign ieu_dp_IFResultWReg_internal[3] = ieu_dp_IFResultWReg_raw_internal[3];
assign ieu_dp_IFResultWReg_internal[4] = ieu_dp_IFResultWReg_raw_internal[4];
assign ieu_dp_IFResultWReg_internal[5] = ieu_dp_IFResultWReg_raw_internal[5];
assign ieu_dp_IFResultWReg_internal[6] = ieu_dp_IFResultWReg_raw_internal[6];
assign ieu_dp_IFResultWReg_internal[7] = ieu_dp_IFResultWReg_raw_internal[7];
assign ieu_dp_IFResultWReg_internal[8] = ieu_dp_IFResultWReg_raw_internal[8];
assign ieu_dp_IFResultWReg_internal[9] = ieu_dp_IFResultWReg_raw_internal[9];
assign ieu_dp_IFResultWReg_internal[10] = ieu_dp_IFResultWReg_raw_internal[10];
assign ieu_dp_IFResultWReg_internal[11] = ieu_dp_IFResultWReg_raw_internal[11];
assign ieu_dp_IFResultWReg_internal[12] = ieu_dp_IFResultWReg_raw_internal[12];
assign ieu_dp_IFResultWReg_internal[13] = ieu_dp_IFResultWReg_raw_internal[13];
assign ieu_dp_IFResultWReg_internal[14] = ieu_dp_IFResultWReg_raw_internal[14];
assign ieu_dp_IFResultWReg_internal[15] = ieu_dp_IFResultWReg_raw_internal[15];
assign ieu_dp_IFResultWReg_internal[16] = ieu_dp_IFResultWReg_raw_internal[16];
assign ieu_dp_IFResultWReg_internal[17] = ieu_dp_IFResultWReg_raw_internal[17];
assign ieu_dp_IFResultWReg_internal[18] = ieu_dp_IFResultWReg_raw_internal[18];
assign ieu_dp_IFResultWReg_internal[19] = ieu_dp_IFResultWReg_raw_internal[19];
assign ieu_dp_IFResultWReg_internal[20] = ieu_dp_IFResultWReg_raw_internal[20];
assign ieu_dp_IFResultWReg_internal[21] = ieu_dp_IFResultWReg_raw_internal[21];
assign ieu_dp_IFResultWReg_internal[22] = ieu_dp_IFResultWReg_raw_internal[22];
assign ieu_dp_IFResultWReg_internal[23] = ieu_dp_IFResultWReg_raw_internal[23];
assign ieu_dp_IFResultWReg_internal[24] = ieu_dp_IFResultWReg_raw_internal[24];
assign ieu_dp_IFResultWReg_internal[25] = ieu_dp_IFResultWReg_raw_internal[25];
assign ieu_dp_IFResultWReg_internal[26] = ieu_dp_IFResultWReg_raw_internal[26];
assign ieu_dp_IFResultWReg_internal[27] = ieu_dp_IFResultWReg_raw_internal[27];
assign ieu_dp_IFResultWReg_internal[28] = ieu_dp_IFResultWReg_raw_internal[28];
assign ieu_dp_IFResultWReg_internal[29] = ieu_dp_IFResultWReg_raw_internal[29];
assign ieu_dp_IFResultWReg_internal[30] = ieu_dp_IFResultWReg_raw_internal[30];
assign ieu_dp_IFResultWReg_internal[31] = ieu_dp_IFResultWReg_raw_internal[31];
assign ieu_dp_IFResultWReg_internal[32] = ieu_dp_IFResultWReg_raw_internal[32];
assign ieu_dp_IFResultWReg_internal[33] = ieu_dp_IFResultWReg_raw_internal[33];
assign ieu_dp_IFResultWReg_internal[34] = ieu_dp_IFResultWReg_raw_internal[34];
assign ieu_dp_IFResultWReg_internal[35] = ieu_dp_IFResultWReg_raw_internal[35];
assign ieu_dp_IFResultWReg_internal[36] = ieu_dp_IFResultWReg_raw_internal[36];
assign ieu_dp_IFResultWReg_internal[37] = ieu_dp_IFResultWReg_raw_internal[37];
assign ieu_dp_IFResultWReg_internal[38] = ieu_dp_IFResultWReg_raw_internal[38];
assign ieu_dp_IFResultWReg_internal[39] = ieu_dp_IFResultWReg_raw_internal[39];
assign ieu_dp_IFResultWReg_internal[40] = ieu_dp_IFResultWReg_raw_internal[40];
assign ieu_dp_IFResultWReg_internal[41] = ieu_dp_IFResultWReg_raw_internal[41];
assign ieu_dp_IFResultWReg_internal[42] = ieu_dp_IFResultWReg_raw_internal[42];
assign ieu_dp_IFResultWReg_internal[43] = ieu_dp_IFResultWReg_raw_internal[43];
assign ieu_dp_IFResultWReg_internal[44] = ieu_dp_IFResultWReg_raw_internal[44];
assign ieu_dp_IFResultWReg_internal[45] = ieu_dp_IFResultWReg_raw_internal[45];
assign ieu_dp_IFResultWReg_internal[46] = ieu_dp_IFResultWReg_raw_internal[46];
assign ieu_dp_IFResultWReg_internal[47] = ieu_dp_IFResultWReg_raw_internal[47];
assign ieu_dp_IFResultWReg_internal[48] = ieu_dp_IFResultWReg_raw_internal[48];
assign ieu_dp_IFResultWReg_internal[49] = ieu_dp_IFResultWReg_raw_internal[49];
assign ieu_dp_IFResultWReg_internal[50] = ieu_dp_IFResultWReg_raw_internal[50];
assign ieu_dp_IFResultWReg_internal[51] = ieu_dp_IFResultWReg_raw_internal[51];
assign ieu_dp_IFResultWReg_internal[52] = ieu_dp_IFResultWReg_raw_internal[52];
assign ieu_dp_IFResultWReg_internal[53] = ieu_dp_IFResultWReg_raw_internal[53];
assign ieu_dp_IFResultWReg_internal[54] = ieu_dp_IFResultWReg_raw_internal[54];
assign ieu_dp_IFResultWReg_internal[55] = ieu_dp_IFResultWReg_raw_internal[55];
assign ieu_dp_IFResultWReg_internal[56] = ieu_dp_IFResultWReg_raw_internal[56];
assign ieu_dp_IFResultWReg_internal[57] = ieu_dp_IFResultWReg_raw_internal[57];
assign ieu_dp_IFResultWReg_internal[58] = ieu_dp_IFResultWReg_raw_internal[58];
assign ieu_dp_IFResultWReg_internal[59] = ieu_dp_IFResultWReg_raw_internal[59];
assign ieu_dp_IFResultWReg_internal[60] = ieu_dp_IFResultWReg_raw_internal[60];
assign ieu_dp_IFResultWReg_internal[61] = ieu_dp_IFResultWReg_raw_internal[61];
assign ieu_dp_IFResultWReg_internal[62] = ieu_dp_IFResultWReg_raw_internal[62];
assign ieu_dp_IFResultWReg_internal[63] = ieu_dp_IFResultWReg_raw_internal[63];
assign ieu_dp_IFResultWReg_internal[64] = ieu_dp_IFResultWReg_raw_internal[64];
assign ieu_dp_IFResultWReg_internal[65] = ieu_dp_IFResultWReg_raw_internal[65];
assign ieu_dp_IFResultWReg_internal[66] = ieu_dp_IFResultWReg_raw_internal[66];
assign ieu_dp_IFResultWReg_internal[67] = ieu_dp_IFResultWReg_raw_internal[67];
assign ieu_dp_IFResultWReg_internal[68] = ieu_dp_IFResultWReg_raw_internal[68];
assign ieu_dp_IFResultWReg_internal[69] = ieu_dp_IFResultWReg_raw_internal[69];
assign ieu_dp_IFResultWReg_internal[70] = ieu_dp_IFResultWReg_raw_internal[70];
assign ieu_dp_IFResultWReg_internal[71] = ieu_dp_IFResultWReg_raw_internal[71];

// ---- ieu_dp_IFResultWReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ieu_dp_IFResultWReg_pin_internal[0] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_0_.Q;
assign ieu_dp_IFResultWReg_pin_internal[1] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_1_.Q;
assign ieu_dp_IFResultWReg_pin_internal[2] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_2_.Q;
assign ieu_dp_IFResultWReg_pin_internal[3] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_3_.Q;
assign ieu_dp_IFResultWReg_pin_internal[4] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_4_.Q;
assign ieu_dp_IFResultWReg_pin_internal[5] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_5_.Q;
assign ieu_dp_IFResultWReg_pin_internal[6] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_6_.Q;
assign ieu_dp_IFResultWReg_pin_internal[7] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_7_.Q;
assign ieu_dp_IFResultWReg_pin_internal[8] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_8_.Q;
assign ieu_dp_IFResultWReg_pin_internal[9] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_9_.Q;
assign ieu_dp_IFResultWReg_pin_internal[10] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_10_.Q;
assign ieu_dp_IFResultWReg_pin_internal[11] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_11_.Q;
assign ieu_dp_IFResultWReg_pin_internal[12] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_12_.Q;
assign ieu_dp_IFResultWReg_pin_internal[13] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_13_.Q;
assign ieu_dp_IFResultWReg_pin_internal[14] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_14_.Q;
assign ieu_dp_IFResultWReg_pin_internal[15] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_15_.Q;
assign ieu_dp_IFResultWReg_pin_internal[16] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_16_.Q;
assign ieu_dp_IFResultWReg_pin_internal[17] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_17_.Q;
assign ieu_dp_IFResultWReg_pin_internal[18] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_18_.Q;
assign ieu_dp_IFResultWReg_pin_internal[19] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_19_.Q;
assign ieu_dp_IFResultWReg_pin_internal[20] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_20_.Q;
assign ieu_dp_IFResultWReg_pin_internal[21] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_21_.Q;
assign ieu_dp_IFResultWReg_pin_internal[22] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_22_.Q;
assign ieu_dp_IFResultWReg_pin_internal[23] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_23_.Q;
assign ieu_dp_IFResultWReg_pin_internal[24] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_24_.Q;
assign ieu_dp_IFResultWReg_pin_internal[25] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_25_.Q;
assign ieu_dp_IFResultWReg_pin_internal[26] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_26_.Q;
assign ieu_dp_IFResultWReg_pin_internal[27] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_27_.Q;
assign ieu_dp_IFResultWReg_pin_internal[28] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_28_.Q;
assign ieu_dp_IFResultWReg_pin_internal[29] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_29_.Q;
assign ieu_dp_IFResultWReg_pin_internal[30] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_30_.Q;
assign ieu_dp_IFResultWReg_pin_internal[31] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_31_.Q;
assign ieu_dp_IFResultWReg_pin_internal[32] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_32_.Q;
assign ieu_dp_IFResultWReg_pin_internal[33] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_33_.Q;
assign ieu_dp_IFResultWReg_pin_internal[34] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_34_.Q;
assign ieu_dp_IFResultWReg_pin_internal[35] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_35_.Q;
assign ieu_dp_IFResultWReg_pin_internal[36] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_36_.Q;
assign ieu_dp_IFResultWReg_pin_internal[37] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_37_.Q;
assign ieu_dp_IFResultWReg_pin_internal[38] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_38_.Q;
assign ieu_dp_IFResultWReg_pin_internal[39] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_39_.Q;
assign ieu_dp_IFResultWReg_pin_internal[40] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_40_.Q;
assign ieu_dp_IFResultWReg_pin_internal[41] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_41_.Q;
assign ieu_dp_IFResultWReg_pin_internal[42] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_42_.Q;
assign ieu_dp_IFResultWReg_pin_internal[43] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_43_.Q;
assign ieu_dp_IFResultWReg_pin_internal[44] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_44_.Q;
assign ieu_dp_IFResultWReg_pin_internal[45] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_45_.Q;
assign ieu_dp_IFResultWReg_pin_internal[46] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_46_.Q;
assign ieu_dp_IFResultWReg_pin_internal[47] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_47_.Q;
assign ieu_dp_IFResultWReg_pin_internal[48] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_48_.Q;
assign ieu_dp_IFResultWReg_pin_internal[49] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_49_.Q;
assign ieu_dp_IFResultWReg_pin_internal[50] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_50_.Q;
assign ieu_dp_IFResultWReg_pin_internal[51] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_51_.Q;
assign ieu_dp_IFResultWReg_pin_internal[52] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_52_.Q;
assign ieu_dp_IFResultWReg_pin_internal[53] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_53_.Q;
assign ieu_dp_IFResultWReg_pin_internal[54] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_54_.Q;
assign ieu_dp_IFResultWReg_pin_internal[55] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_55_.Q;
assign ieu_dp_IFResultWReg_pin_internal[56] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_56_.Q;
assign ieu_dp_IFResultWReg_pin_internal[57] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_57_.Q;
assign ieu_dp_IFResultWReg_pin_internal[58] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_58_.Q;
assign ieu_dp_IFResultWReg_pin_internal[59] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_59_.Q;
assign ieu_dp_IFResultWReg_pin_internal[60] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_60_.Q;
assign ieu_dp_IFResultWReg_pin_internal[61] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_61_.Q;
assign ieu_dp_IFResultWReg_pin_internal[62] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_62_.Q;
assign ieu_dp_IFResultWReg_pin_internal[63] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_63_.Q;
assign ieu_dp_IFResultWReg_pin_internal[64] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_64_.Q;
assign ieu_dp_IFResultWReg_pin_internal[65] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_65_.Q;
assign ieu_dp_IFResultWReg_pin_internal[66] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_66_.Q;
assign ieu_dp_IFResultWReg_pin_internal[67] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_67_.Q;
assign ieu_dp_IFResultWReg_pin_internal[68] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_68_.Q;
assign ieu_dp_IFResultWReg_pin_internal[69] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_69_.Q;
assign ieu_dp_IFResultWReg_pin_internal[70] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_70_.Q;
assign ieu_dp_IFResultWReg_pin_internal[71] = dut.chip.soc_core_ieu_dp_IFResultWReg_store.cw_stored_reg_71_.Q;

// ---- ieu_dp_IFResultWReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ieu_dp_IFResultWReg_raw_internal_available[0] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[1] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[2] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[3] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[4] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[5] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[6] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[7] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[8] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[9] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[10] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[11] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[12] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[13] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[14] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[15] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[16] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[17] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[18] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[19] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[20] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[21] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[22] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[23] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[24] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[25] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[26] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[27] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[28] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[29] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[30] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[31] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[32] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[33] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[34] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[35] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[36] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[37] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[38] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[39] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[40] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[41] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[42] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[43] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[44] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[45] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[46] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[47] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[48] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[49] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[50] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[51] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[52] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[53] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[54] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[55] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[56] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[57] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[58] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[59] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[60] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[61] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[62] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[63] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[64] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[65] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[66] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[67] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[68] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[69] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[70] = 1'b1;
assign ieu_dp_IFResultWReg_raw_internal_available[71] = 1'b1;

// ============================================================================
// Register ieu_dp_ImmExtEReg: 72 mapped bits, width 72
// ============================================================================

// Bus declarations
wire [71:0] ieu_dp_ImmExtEReg_internal;
wire [71:0] ieu_dp_ImmExtEReg_raw_internal;
wire [71:0] ieu_dp_ImmExtEReg_pin_internal;
wire [71:0] ieu_dp_ImmExtEReg_raw_internal_available;

// ---- ieu_dp_ImmExtEReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ieu_dp_ImmExtEReg_raw_internal[0] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_0_.Q; // c1[40]
assign ieu_dp_ImmExtEReg_raw_internal[1] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_1_.Q; // c1[41]
assign ieu_dp_ImmExtEReg_raw_internal[2] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_2_.Q; // c1[42]
assign ieu_dp_ImmExtEReg_raw_internal[3] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_3_.Q; // c1[43]
assign ieu_dp_ImmExtEReg_raw_internal[4] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_4_.Q; // c1[44]
assign ieu_dp_ImmExtEReg_raw_internal[5] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_5_.Q; // c1[45]
assign ieu_dp_ImmExtEReg_raw_internal[6] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_6_.Q; // c1[46]
assign ieu_dp_ImmExtEReg_raw_internal[7] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_7_.Q; // c1[47]
assign ieu_dp_ImmExtEReg_raw_internal[8] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_8_.Q; // c1[48]
assign ieu_dp_ImmExtEReg_raw_internal[9] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_9_.Q; // c1[49]
assign ieu_dp_ImmExtEReg_raw_internal[10] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_10_.Q; // c1[50]
assign ieu_dp_ImmExtEReg_raw_internal[11] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_11_.Q; // c1[51]
assign ieu_dp_ImmExtEReg_raw_internal[12] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_12_.Q; // c1[52]
assign ieu_dp_ImmExtEReg_raw_internal[13] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_13_.Q; // c1[53]
assign ieu_dp_ImmExtEReg_raw_internal[14] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_14_.Q; // c1[54]
assign ieu_dp_ImmExtEReg_raw_internal[15] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_15_.Q; // c1[55]
assign ieu_dp_ImmExtEReg_raw_internal[16] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_16_.Q; // c1[56]
assign ieu_dp_ImmExtEReg_raw_internal[17] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_17_.Q; // c1[57]
assign ieu_dp_ImmExtEReg_raw_internal[18] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_18_.Q; // c1[58]
assign ieu_dp_ImmExtEReg_raw_internal[19] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_19_.Q; // c1[59]
assign ieu_dp_ImmExtEReg_raw_internal[20] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_20_.Q; // c1[60]
assign ieu_dp_ImmExtEReg_raw_internal[21] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_21_.Q; // c1[61]
assign ieu_dp_ImmExtEReg_raw_internal[22] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_22_.Q; // c1[62]
assign ieu_dp_ImmExtEReg_raw_internal[23] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_23_.Q; // c1[63]
assign ieu_dp_ImmExtEReg_raw_internal[24] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_24_.Q; // c1[64]
assign ieu_dp_ImmExtEReg_raw_internal[25] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_25_.Q; // c1[65]
assign ieu_dp_ImmExtEReg_raw_internal[26] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_26_.Q; // c1[66]
assign ieu_dp_ImmExtEReg_raw_internal[27] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_27_.Q; // c1[67]
assign ieu_dp_ImmExtEReg_raw_internal[28] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_28_.Q; // c1[68]
assign ieu_dp_ImmExtEReg_raw_internal[29] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_29_.Q; // c1[69]
assign ieu_dp_ImmExtEReg_raw_internal[30] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_30_.Q; // c1[70]
assign ieu_dp_ImmExtEReg_raw_internal[31] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_31_.Q; // c1[71]
assign ieu_dp_ImmExtEReg_raw_internal[32] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_32_.Q; // c1[72]
assign ieu_dp_ImmExtEReg_raw_internal[33] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_33_.Q; // c1[73]
assign ieu_dp_ImmExtEReg_raw_internal[34] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_34_.Q; // c1[74]
assign ieu_dp_ImmExtEReg_raw_internal[35] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_35_.Q; // c1[75]
assign ieu_dp_ImmExtEReg_raw_internal[36] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_36_.Q; // c1[76]
assign ieu_dp_ImmExtEReg_raw_internal[37] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_37_.Q; // c1[77]
assign ieu_dp_ImmExtEReg_raw_internal[38] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_38_.Q; // c1[78]
assign ieu_dp_ImmExtEReg_raw_internal[39] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_39_.Q; // c1[79]
assign ieu_dp_ImmExtEReg_raw_internal[40] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_40_.Q; // c1[80]
assign ieu_dp_ImmExtEReg_raw_internal[41] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_41_.Q; // c1[81]
assign ieu_dp_ImmExtEReg_raw_internal[42] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_42_.Q; // c1[82]
assign ieu_dp_ImmExtEReg_raw_internal[43] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_43_.Q; // c1[83]
assign ieu_dp_ImmExtEReg_raw_internal[44] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_44_.Q; // c1[84]
assign ieu_dp_ImmExtEReg_raw_internal[45] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_45_.Q; // c1[85]
assign ieu_dp_ImmExtEReg_raw_internal[46] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_46_.Q; // c1[86]
assign ieu_dp_ImmExtEReg_raw_internal[47] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_47_.Q; // c1[87]
assign ieu_dp_ImmExtEReg_raw_internal[48] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_48_.Q; // c1[88]
assign ieu_dp_ImmExtEReg_raw_internal[49] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_49_.Q; // c1[89]
assign ieu_dp_ImmExtEReg_raw_internal[50] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_50_.Q; // c1[90]
assign ieu_dp_ImmExtEReg_raw_internal[51] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_51_.Q; // c1[91]
assign ieu_dp_ImmExtEReg_raw_internal[52] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_52_.Q; // c1[92]
assign ieu_dp_ImmExtEReg_raw_internal[53] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_53_.Q; // c1[93]
assign ieu_dp_ImmExtEReg_raw_internal[54] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_54_.Q; // c1[94]
assign ieu_dp_ImmExtEReg_raw_internal[55] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_55_.Q; // c1[95]
assign ieu_dp_ImmExtEReg_raw_internal[56] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_56_.Q; // c1[96]
assign ieu_dp_ImmExtEReg_raw_internal[57] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_57_.Q; // c1[97]
assign ieu_dp_ImmExtEReg_raw_internal[58] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_58_.Q; // c1[98]
assign ieu_dp_ImmExtEReg_raw_internal[59] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_59_.Q; // c1[99]
assign ieu_dp_ImmExtEReg_raw_internal[60] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_60_.Q; // c1[100]
assign ieu_dp_ImmExtEReg_raw_internal[61] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_61_.Q; // c1[101]
assign ieu_dp_ImmExtEReg_raw_internal[62] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_62_.Q; // c1[102]
assign ieu_dp_ImmExtEReg_raw_internal[63] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_63_.Q; // c1[103]
assign ieu_dp_ImmExtEReg_raw_internal[64] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_64_.Q; // c1[104]
assign ieu_dp_ImmExtEReg_raw_internal[65] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_65_.Q; // c1[105]
assign ieu_dp_ImmExtEReg_raw_internal[66] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_66_.Q; // c1[106]
assign ieu_dp_ImmExtEReg_raw_internal[67] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_67_.Q; // c1[107]
assign ieu_dp_ImmExtEReg_raw_internal[68] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_68_.Q; // c1[108]
assign ieu_dp_ImmExtEReg_raw_internal[69] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_69_.Q; // c1[109]
assign ieu_dp_ImmExtEReg_raw_internal[70] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_70_.Q; // c1[110]
assign ieu_dp_ImmExtEReg_raw_internal[71] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_71_.Q; // c1[111]

// ---- ieu_dp_ImmExtEReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ieu_dp_ImmExtEReg_internal[0] = ieu_dp_ImmExtEReg_raw_internal[0];
assign ieu_dp_ImmExtEReg_internal[1] = ieu_dp_ImmExtEReg_raw_internal[1];
assign ieu_dp_ImmExtEReg_internal[2] = ieu_dp_ImmExtEReg_raw_internal[2];
assign ieu_dp_ImmExtEReg_internal[3] = ieu_dp_ImmExtEReg_raw_internal[3];
assign ieu_dp_ImmExtEReg_internal[4] = ieu_dp_ImmExtEReg_raw_internal[4];
assign ieu_dp_ImmExtEReg_internal[5] = ieu_dp_ImmExtEReg_raw_internal[5];
assign ieu_dp_ImmExtEReg_internal[6] = ieu_dp_ImmExtEReg_raw_internal[6];
assign ieu_dp_ImmExtEReg_internal[7] = ieu_dp_ImmExtEReg_raw_internal[7];
assign ieu_dp_ImmExtEReg_internal[8] = ieu_dp_ImmExtEReg_raw_internal[8];
assign ieu_dp_ImmExtEReg_internal[9] = ieu_dp_ImmExtEReg_raw_internal[9];
assign ieu_dp_ImmExtEReg_internal[10] = ieu_dp_ImmExtEReg_raw_internal[10];
assign ieu_dp_ImmExtEReg_internal[11] = ieu_dp_ImmExtEReg_raw_internal[11];
assign ieu_dp_ImmExtEReg_internal[12] = ieu_dp_ImmExtEReg_raw_internal[12];
assign ieu_dp_ImmExtEReg_internal[13] = ieu_dp_ImmExtEReg_raw_internal[13];
assign ieu_dp_ImmExtEReg_internal[14] = ieu_dp_ImmExtEReg_raw_internal[14];
assign ieu_dp_ImmExtEReg_internal[15] = ieu_dp_ImmExtEReg_raw_internal[15];
assign ieu_dp_ImmExtEReg_internal[16] = ieu_dp_ImmExtEReg_raw_internal[16];
assign ieu_dp_ImmExtEReg_internal[17] = ieu_dp_ImmExtEReg_raw_internal[17];
assign ieu_dp_ImmExtEReg_internal[18] = ieu_dp_ImmExtEReg_raw_internal[18];
assign ieu_dp_ImmExtEReg_internal[19] = ieu_dp_ImmExtEReg_raw_internal[19];
assign ieu_dp_ImmExtEReg_internal[20] = ieu_dp_ImmExtEReg_raw_internal[20];
assign ieu_dp_ImmExtEReg_internal[21] = ieu_dp_ImmExtEReg_raw_internal[21];
assign ieu_dp_ImmExtEReg_internal[22] = ieu_dp_ImmExtEReg_raw_internal[22];
assign ieu_dp_ImmExtEReg_internal[23] = ieu_dp_ImmExtEReg_raw_internal[23];
assign ieu_dp_ImmExtEReg_internal[24] = ieu_dp_ImmExtEReg_raw_internal[24];
assign ieu_dp_ImmExtEReg_internal[25] = ieu_dp_ImmExtEReg_raw_internal[25];
assign ieu_dp_ImmExtEReg_internal[26] = ieu_dp_ImmExtEReg_raw_internal[26];
assign ieu_dp_ImmExtEReg_internal[27] = ieu_dp_ImmExtEReg_raw_internal[27];
assign ieu_dp_ImmExtEReg_internal[28] = ieu_dp_ImmExtEReg_raw_internal[28];
assign ieu_dp_ImmExtEReg_internal[29] = ieu_dp_ImmExtEReg_raw_internal[29];
assign ieu_dp_ImmExtEReg_internal[30] = ieu_dp_ImmExtEReg_raw_internal[30];
assign ieu_dp_ImmExtEReg_internal[31] = ieu_dp_ImmExtEReg_raw_internal[31];
assign ieu_dp_ImmExtEReg_internal[32] = ieu_dp_ImmExtEReg_raw_internal[32];
assign ieu_dp_ImmExtEReg_internal[33] = ieu_dp_ImmExtEReg_raw_internal[33];
assign ieu_dp_ImmExtEReg_internal[34] = ieu_dp_ImmExtEReg_raw_internal[34];
assign ieu_dp_ImmExtEReg_internal[35] = ieu_dp_ImmExtEReg_raw_internal[35];
assign ieu_dp_ImmExtEReg_internal[36] = ieu_dp_ImmExtEReg_raw_internal[36];
assign ieu_dp_ImmExtEReg_internal[37] = ieu_dp_ImmExtEReg_raw_internal[37];
assign ieu_dp_ImmExtEReg_internal[38] = ieu_dp_ImmExtEReg_raw_internal[38];
assign ieu_dp_ImmExtEReg_internal[39] = ieu_dp_ImmExtEReg_raw_internal[39];
assign ieu_dp_ImmExtEReg_internal[40] = ieu_dp_ImmExtEReg_raw_internal[40];
assign ieu_dp_ImmExtEReg_internal[41] = ieu_dp_ImmExtEReg_raw_internal[41];
assign ieu_dp_ImmExtEReg_internal[42] = ieu_dp_ImmExtEReg_raw_internal[42];
assign ieu_dp_ImmExtEReg_internal[43] = ieu_dp_ImmExtEReg_raw_internal[43];
assign ieu_dp_ImmExtEReg_internal[44] = ieu_dp_ImmExtEReg_raw_internal[44];
assign ieu_dp_ImmExtEReg_internal[45] = ieu_dp_ImmExtEReg_raw_internal[45];
assign ieu_dp_ImmExtEReg_internal[46] = ieu_dp_ImmExtEReg_raw_internal[46];
assign ieu_dp_ImmExtEReg_internal[47] = ieu_dp_ImmExtEReg_raw_internal[47];
assign ieu_dp_ImmExtEReg_internal[48] = ieu_dp_ImmExtEReg_raw_internal[48];
assign ieu_dp_ImmExtEReg_internal[49] = ieu_dp_ImmExtEReg_raw_internal[49];
assign ieu_dp_ImmExtEReg_internal[50] = ieu_dp_ImmExtEReg_raw_internal[50];
assign ieu_dp_ImmExtEReg_internal[51] = ieu_dp_ImmExtEReg_raw_internal[51];
assign ieu_dp_ImmExtEReg_internal[52] = ieu_dp_ImmExtEReg_raw_internal[52];
assign ieu_dp_ImmExtEReg_internal[53] = ieu_dp_ImmExtEReg_raw_internal[53];
assign ieu_dp_ImmExtEReg_internal[54] = ieu_dp_ImmExtEReg_raw_internal[54];
assign ieu_dp_ImmExtEReg_internal[55] = ieu_dp_ImmExtEReg_raw_internal[55];
assign ieu_dp_ImmExtEReg_internal[56] = ieu_dp_ImmExtEReg_raw_internal[56];
assign ieu_dp_ImmExtEReg_internal[57] = ieu_dp_ImmExtEReg_raw_internal[57];
assign ieu_dp_ImmExtEReg_internal[58] = ieu_dp_ImmExtEReg_raw_internal[58];
assign ieu_dp_ImmExtEReg_internal[59] = ieu_dp_ImmExtEReg_raw_internal[59];
assign ieu_dp_ImmExtEReg_internal[60] = ieu_dp_ImmExtEReg_raw_internal[60];
assign ieu_dp_ImmExtEReg_internal[61] = ieu_dp_ImmExtEReg_raw_internal[61];
assign ieu_dp_ImmExtEReg_internal[62] = ieu_dp_ImmExtEReg_raw_internal[62];
assign ieu_dp_ImmExtEReg_internal[63] = ieu_dp_ImmExtEReg_raw_internal[63];
assign ieu_dp_ImmExtEReg_internal[64] = ieu_dp_ImmExtEReg_raw_internal[64];
assign ieu_dp_ImmExtEReg_internal[65] = ieu_dp_ImmExtEReg_raw_internal[65];
assign ieu_dp_ImmExtEReg_internal[66] = ieu_dp_ImmExtEReg_raw_internal[66];
assign ieu_dp_ImmExtEReg_internal[67] = ieu_dp_ImmExtEReg_raw_internal[67];
assign ieu_dp_ImmExtEReg_internal[68] = ieu_dp_ImmExtEReg_raw_internal[68];
assign ieu_dp_ImmExtEReg_internal[69] = ieu_dp_ImmExtEReg_raw_internal[69];
assign ieu_dp_ImmExtEReg_internal[70] = ieu_dp_ImmExtEReg_raw_internal[70];
assign ieu_dp_ImmExtEReg_internal[71] = ieu_dp_ImmExtEReg_raw_internal[71];

// ---- ieu_dp_ImmExtEReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ieu_dp_ImmExtEReg_pin_internal[0] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_0_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[1] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_1_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[2] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_2_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[3] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_3_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[4] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_4_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[5] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_5_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[6] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_6_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[7] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_7_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[8] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_8_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[9] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_9_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[10] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_10_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[11] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_11_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[12] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_12_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[13] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_13_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[14] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_14_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[15] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_15_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[16] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_16_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[17] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_17_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[18] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_18_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[19] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_19_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[20] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_20_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[21] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_21_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[22] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_22_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[23] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_23_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[24] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_24_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[25] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_25_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[26] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_26_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[27] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_27_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[28] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_28_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[29] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_29_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[30] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_30_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[31] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_31_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[32] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_32_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[33] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_33_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[34] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_34_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[35] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_35_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[36] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_36_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[37] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_37_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[38] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_38_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[39] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_39_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[40] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_40_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[41] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_41_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[42] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_42_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[43] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_43_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[44] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_44_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[45] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_45_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[46] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_46_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[47] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_47_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[48] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_48_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[49] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_49_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[50] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_50_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[51] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_51_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[52] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_52_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[53] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_53_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[54] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_54_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[55] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_55_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[56] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_56_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[57] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_57_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[58] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_58_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[59] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_59_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[60] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_60_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[61] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_61_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[62] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_62_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[63] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_63_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[64] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_64_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[65] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_65_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[66] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_66_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[67] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_67_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[68] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_68_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[69] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_69_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[70] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_70_.Q;
assign ieu_dp_ImmExtEReg_pin_internal[71] = dut.chip.soc_core_ieu_dp_ImmExtEReg_store.cw_stored_reg_71_.Q;

// ---- ieu_dp_ImmExtEReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ieu_dp_ImmExtEReg_raw_internal_available[0] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[1] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[2] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[3] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[4] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[5] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[6] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[7] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[8] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[9] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[10] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[11] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[12] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[13] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[14] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[15] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[16] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[17] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[18] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[19] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[20] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[21] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[22] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[23] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[24] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[25] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[26] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[27] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[28] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[29] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[30] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[31] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[32] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[33] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[34] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[35] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[36] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[37] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[38] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[39] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[40] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[41] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[42] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[43] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[44] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[45] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[46] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[47] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[48] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[49] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[50] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[51] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[52] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[53] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[54] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[55] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[56] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[57] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[58] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[59] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[60] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[61] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[62] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[63] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[64] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[65] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[66] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[67] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[68] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[69] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[70] = 1'b1;
assign ieu_dp_ImmExtEReg_raw_internal_available[71] = 1'b1;

// ============================================================================
// Register ieu_dp_RD1EReg: 72 mapped bits, width 72
// ============================================================================

// Bus declarations
wire [71:0] ieu_dp_RD1EReg_internal;
wire [71:0] ieu_dp_RD1EReg_raw_internal;
wire [71:0] ieu_dp_RD1EReg_pin_internal;
wire [71:0] ieu_dp_RD1EReg_raw_internal_available;

// ---- ieu_dp_RD1EReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ieu_dp_RD1EReg_raw_internal[0] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_0_.Q; // c1[112]
assign ieu_dp_RD1EReg_raw_internal[1] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_1_.Q; // c1[113]
assign ieu_dp_RD1EReg_raw_internal[2] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_2_.QN; // c1[114]
assign ieu_dp_RD1EReg_raw_internal[3] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_3_.QN; // c1[115]
assign ieu_dp_RD1EReg_raw_internal[4] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_4_.Q; // c1[116]
assign ieu_dp_RD1EReg_raw_internal[5] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_5_.Q; // c1[117]
assign ieu_dp_RD1EReg_raw_internal[6] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_6_.Q; // c1[118]
assign ieu_dp_RD1EReg_raw_internal[7] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_7_.Q; // c1[119]
assign ieu_dp_RD1EReg_raw_internal[8] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_8_.Q; // c1[120]
assign ieu_dp_RD1EReg_raw_internal[9] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_9_.QN; // c1[121]
assign ieu_dp_RD1EReg_raw_internal[10] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_10_.QN; // c1[122]
assign ieu_dp_RD1EReg_raw_internal[11] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_11_.QN; // c1[123]
assign ieu_dp_RD1EReg_raw_internal[12] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_12_.QN; // c1[124]
assign ieu_dp_RD1EReg_raw_internal[13] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_13_.QN; // c1[125]
assign ieu_dp_RD1EReg_raw_internal[14] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_14_.QN; // c1[126]
assign ieu_dp_RD1EReg_raw_internal[15] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_15_.Q; // c1[127]
assign ieu_dp_RD1EReg_raw_internal[16] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_16_.QN; // c1[128]
assign ieu_dp_RD1EReg_raw_internal[17] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_17_.QN; // c1[129]
assign ieu_dp_RD1EReg_raw_internal[18] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_18_.QN; // c1[130]
assign ieu_dp_RD1EReg_raw_internal[19] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_19_.QN; // c1[131]
assign ieu_dp_RD1EReg_raw_internal[20] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_20_.QN; // c1[132]
assign ieu_dp_RD1EReg_raw_internal[21] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_21_.QN; // c1[133]
assign ieu_dp_RD1EReg_raw_internal[22] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_22_.QN; // c1[134]
assign ieu_dp_RD1EReg_raw_internal[23] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_23_.QN; // c1[135]
assign ieu_dp_RD1EReg_raw_internal[24] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_24_.QN; // c1[136]
assign ieu_dp_RD1EReg_raw_internal[25] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_25_.QN; // c1[137]
assign ieu_dp_RD1EReg_raw_internal[26] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_26_.Q; // c1[138]
assign ieu_dp_RD1EReg_raw_internal[27] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_27_.QN; // c1[139]
assign ieu_dp_RD1EReg_raw_internal[28] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_28_.QN; // c1[140]
assign ieu_dp_RD1EReg_raw_internal[29] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_29_.QN; // c1[141]
assign ieu_dp_RD1EReg_raw_internal[30] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_30_.QN; // c1[142]
assign ieu_dp_RD1EReg_raw_internal[31] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_31_.QN; // c1[143]
assign ieu_dp_RD1EReg_raw_internal[32] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_32_.QN; // c1[144]
assign ieu_dp_RD1EReg_raw_internal[33] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_33_.QN; // c1[145]
assign ieu_dp_RD1EReg_raw_internal[34] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_34_.Q; // c1[146]
assign ieu_dp_RD1EReg_raw_internal[35] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_35_.QN; // c1[147]
assign ieu_dp_RD1EReg_raw_internal[36] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_36_.QN; // c1[148]
assign ieu_dp_RD1EReg_raw_internal[37] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_37_.QN; // c1[149]
assign ieu_dp_RD1EReg_raw_internal[38] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_38_.QN; // c1[150]
assign ieu_dp_RD1EReg_raw_internal[39] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_39_.QN; // c1[151]
assign ieu_dp_RD1EReg_raw_internal[40] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_40_.QN; // c1[152]
assign ieu_dp_RD1EReg_raw_internal[41] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_41_.QN; // c1[153]
assign ieu_dp_RD1EReg_raw_internal[42] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_42_.QN; // c1[154]
assign ieu_dp_RD1EReg_raw_internal[43] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_43_.QN; // c1[155]
assign ieu_dp_RD1EReg_raw_internal[44] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_44_.QN; // c1[156]
assign ieu_dp_RD1EReg_raw_internal[45] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_45_.QN; // c1[157]
assign ieu_dp_RD1EReg_raw_internal[46] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_46_.QN; // c1[158]
assign ieu_dp_RD1EReg_raw_internal[47] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_47_.QN; // c1[159]
assign ieu_dp_RD1EReg_raw_internal[48] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_48_.QN; // c1[160]
assign ieu_dp_RD1EReg_raw_internal[49] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_49_.QN; // c1[161]
assign ieu_dp_RD1EReg_raw_internal[50] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_50_.QN; // c1[162]
assign ieu_dp_RD1EReg_raw_internal[51] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_51_.Q; // c1[163]
assign ieu_dp_RD1EReg_raw_internal[52] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_52_.QN; // c1[164]
assign ieu_dp_RD1EReg_raw_internal[53] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_53_.QN; // c1[165]
assign ieu_dp_RD1EReg_raw_internal[54] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_54_.QN; // c1[166]
assign ieu_dp_RD1EReg_raw_internal[55] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_55_.QN; // c1[167]
assign ieu_dp_RD1EReg_raw_internal[56] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_56_.QN; // c1[168]
assign ieu_dp_RD1EReg_raw_internal[57] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_57_.QN; // c1[169]
assign ieu_dp_RD1EReg_raw_internal[58] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_58_.QN; // c1[170]
assign ieu_dp_RD1EReg_raw_internal[59] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_59_.QN; // c1[171]
assign ieu_dp_RD1EReg_raw_internal[60] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_60_.QN; // c1[172]
assign ieu_dp_RD1EReg_raw_internal[61] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_61_.QN; // c1[173]
assign ieu_dp_RD1EReg_raw_internal[62] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_62_.QN; // c1[174]
assign ieu_dp_RD1EReg_raw_internal[63] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_63_.QN; // c1[175]
assign ieu_dp_RD1EReg_raw_internal[64] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_64_.QN; // c1[176]
assign ieu_dp_RD1EReg_raw_internal[65] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_65_.QN; // c1[177]
assign ieu_dp_RD1EReg_raw_internal[66] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_66_.Q; // c1[178]
assign ieu_dp_RD1EReg_raw_internal[67] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_67_.Q; // c1[179]
assign ieu_dp_RD1EReg_raw_internal[68] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_68_.QN; // c1[180]
assign ieu_dp_RD1EReg_raw_internal[69] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_69_.QN; // c1[181]
assign ieu_dp_RD1EReg_raw_internal[70] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_70_.QN; // c1[182]
assign ieu_dp_RD1EReg_raw_internal[71] = ~dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_71_.QN; // c1[183]

// ---- ieu_dp_RD1EReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ieu_dp_RD1EReg_internal[0] = ieu_dp_RD1EReg_raw_internal[0];
assign ieu_dp_RD1EReg_internal[1] = ieu_dp_RD1EReg_raw_internal[1];
assign ieu_dp_RD1EReg_internal[2] = ieu_dp_RD1EReg_raw_internal[2];
assign ieu_dp_RD1EReg_internal[3] = ieu_dp_RD1EReg_raw_internal[3];
assign ieu_dp_RD1EReg_internal[4] = ieu_dp_RD1EReg_raw_internal[4];
assign ieu_dp_RD1EReg_internal[5] = ieu_dp_RD1EReg_raw_internal[5];
assign ieu_dp_RD1EReg_internal[6] = ieu_dp_RD1EReg_raw_internal[6];
assign ieu_dp_RD1EReg_internal[7] = ieu_dp_RD1EReg_raw_internal[7];
assign ieu_dp_RD1EReg_internal[8] = ieu_dp_RD1EReg_raw_internal[8];
assign ieu_dp_RD1EReg_internal[9] = ieu_dp_RD1EReg_raw_internal[9];
assign ieu_dp_RD1EReg_internal[10] = ieu_dp_RD1EReg_raw_internal[10];
assign ieu_dp_RD1EReg_internal[11] = ieu_dp_RD1EReg_raw_internal[11];
assign ieu_dp_RD1EReg_internal[12] = ieu_dp_RD1EReg_raw_internal[12];
assign ieu_dp_RD1EReg_internal[13] = ieu_dp_RD1EReg_raw_internal[13];
assign ieu_dp_RD1EReg_internal[14] = ieu_dp_RD1EReg_raw_internal[14];
assign ieu_dp_RD1EReg_internal[15] = ieu_dp_RD1EReg_raw_internal[15];
assign ieu_dp_RD1EReg_internal[16] = ieu_dp_RD1EReg_raw_internal[16];
assign ieu_dp_RD1EReg_internal[17] = ieu_dp_RD1EReg_raw_internal[17];
assign ieu_dp_RD1EReg_internal[18] = ieu_dp_RD1EReg_raw_internal[18];
assign ieu_dp_RD1EReg_internal[19] = ieu_dp_RD1EReg_raw_internal[19];
assign ieu_dp_RD1EReg_internal[20] = ieu_dp_RD1EReg_raw_internal[20];
assign ieu_dp_RD1EReg_internal[21] = ieu_dp_RD1EReg_raw_internal[21];
assign ieu_dp_RD1EReg_internal[22] = ieu_dp_RD1EReg_raw_internal[22];
assign ieu_dp_RD1EReg_internal[23] = ieu_dp_RD1EReg_raw_internal[23];
assign ieu_dp_RD1EReg_internal[24] = ieu_dp_RD1EReg_raw_internal[24];
assign ieu_dp_RD1EReg_internal[25] = ieu_dp_RD1EReg_raw_internal[25];
assign ieu_dp_RD1EReg_internal[26] = ieu_dp_RD1EReg_raw_internal[26];
assign ieu_dp_RD1EReg_internal[27] = ieu_dp_RD1EReg_raw_internal[27];
assign ieu_dp_RD1EReg_internal[28] = ieu_dp_RD1EReg_raw_internal[28];
assign ieu_dp_RD1EReg_internal[29] = ieu_dp_RD1EReg_raw_internal[29];
assign ieu_dp_RD1EReg_internal[30] = ieu_dp_RD1EReg_raw_internal[30];
assign ieu_dp_RD1EReg_internal[31] = ieu_dp_RD1EReg_raw_internal[31];
assign ieu_dp_RD1EReg_internal[32] = ieu_dp_RD1EReg_raw_internal[32];
assign ieu_dp_RD1EReg_internal[33] = ieu_dp_RD1EReg_raw_internal[33];
assign ieu_dp_RD1EReg_internal[34] = ieu_dp_RD1EReg_raw_internal[34];
assign ieu_dp_RD1EReg_internal[35] = ieu_dp_RD1EReg_raw_internal[35];
assign ieu_dp_RD1EReg_internal[36] = ieu_dp_RD1EReg_raw_internal[36];
assign ieu_dp_RD1EReg_internal[37] = ieu_dp_RD1EReg_raw_internal[37];
assign ieu_dp_RD1EReg_internal[38] = ieu_dp_RD1EReg_raw_internal[38];
assign ieu_dp_RD1EReg_internal[39] = ieu_dp_RD1EReg_raw_internal[39];
assign ieu_dp_RD1EReg_internal[40] = ieu_dp_RD1EReg_raw_internal[40];
assign ieu_dp_RD1EReg_internal[41] = ieu_dp_RD1EReg_raw_internal[41];
assign ieu_dp_RD1EReg_internal[42] = ieu_dp_RD1EReg_raw_internal[42];
assign ieu_dp_RD1EReg_internal[43] = ieu_dp_RD1EReg_raw_internal[43];
assign ieu_dp_RD1EReg_internal[44] = ieu_dp_RD1EReg_raw_internal[44];
assign ieu_dp_RD1EReg_internal[45] = ieu_dp_RD1EReg_raw_internal[45];
assign ieu_dp_RD1EReg_internal[46] = ieu_dp_RD1EReg_raw_internal[46];
assign ieu_dp_RD1EReg_internal[47] = ieu_dp_RD1EReg_raw_internal[47];
assign ieu_dp_RD1EReg_internal[48] = ieu_dp_RD1EReg_raw_internal[48];
assign ieu_dp_RD1EReg_internal[49] = ieu_dp_RD1EReg_raw_internal[49];
assign ieu_dp_RD1EReg_internal[50] = ieu_dp_RD1EReg_raw_internal[50];
assign ieu_dp_RD1EReg_internal[51] = ieu_dp_RD1EReg_raw_internal[51];
assign ieu_dp_RD1EReg_internal[52] = ieu_dp_RD1EReg_raw_internal[52];
assign ieu_dp_RD1EReg_internal[53] = ieu_dp_RD1EReg_raw_internal[53];
assign ieu_dp_RD1EReg_internal[54] = ieu_dp_RD1EReg_raw_internal[54];
assign ieu_dp_RD1EReg_internal[55] = ieu_dp_RD1EReg_raw_internal[55];
assign ieu_dp_RD1EReg_internal[56] = ieu_dp_RD1EReg_raw_internal[56];
assign ieu_dp_RD1EReg_internal[57] = ieu_dp_RD1EReg_raw_internal[57];
assign ieu_dp_RD1EReg_internal[58] = ieu_dp_RD1EReg_raw_internal[58];
assign ieu_dp_RD1EReg_internal[59] = ieu_dp_RD1EReg_raw_internal[59];
assign ieu_dp_RD1EReg_internal[60] = ieu_dp_RD1EReg_raw_internal[60];
assign ieu_dp_RD1EReg_internal[61] = ieu_dp_RD1EReg_raw_internal[61];
assign ieu_dp_RD1EReg_internal[62] = ieu_dp_RD1EReg_raw_internal[62];
assign ieu_dp_RD1EReg_internal[63] = ieu_dp_RD1EReg_raw_internal[63];
assign ieu_dp_RD1EReg_internal[64] = ieu_dp_RD1EReg_raw_internal[64];
assign ieu_dp_RD1EReg_internal[65] = ieu_dp_RD1EReg_raw_internal[65];
assign ieu_dp_RD1EReg_internal[66] = ieu_dp_RD1EReg_raw_internal[66];
assign ieu_dp_RD1EReg_internal[67] = ieu_dp_RD1EReg_raw_internal[67];
assign ieu_dp_RD1EReg_internal[68] = ieu_dp_RD1EReg_raw_internal[68];
assign ieu_dp_RD1EReg_internal[69] = ieu_dp_RD1EReg_raw_internal[69];
assign ieu_dp_RD1EReg_internal[70] = ieu_dp_RD1EReg_raw_internal[70];
assign ieu_dp_RD1EReg_internal[71] = ieu_dp_RD1EReg_raw_internal[71];

// ---- ieu_dp_RD1EReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ieu_dp_RD1EReg_pin_internal[0] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_0_.Q;
assign ieu_dp_RD1EReg_pin_internal[1] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_1_.Q;
assign ieu_dp_RD1EReg_pin_internal[2] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_2_.QN;
assign ieu_dp_RD1EReg_pin_internal[3] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_3_.QN;
assign ieu_dp_RD1EReg_pin_internal[4] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_4_.Q;
assign ieu_dp_RD1EReg_pin_internal[5] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_5_.Q;
assign ieu_dp_RD1EReg_pin_internal[6] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_6_.Q;
assign ieu_dp_RD1EReg_pin_internal[7] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_7_.Q;
assign ieu_dp_RD1EReg_pin_internal[8] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_8_.Q;
assign ieu_dp_RD1EReg_pin_internal[9] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_9_.QN;
assign ieu_dp_RD1EReg_pin_internal[10] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_10_.QN;
assign ieu_dp_RD1EReg_pin_internal[11] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_11_.QN;
assign ieu_dp_RD1EReg_pin_internal[12] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_12_.QN;
assign ieu_dp_RD1EReg_pin_internal[13] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_13_.QN;
assign ieu_dp_RD1EReg_pin_internal[14] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_14_.QN;
assign ieu_dp_RD1EReg_pin_internal[15] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_15_.Q;
assign ieu_dp_RD1EReg_pin_internal[16] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_16_.QN;
assign ieu_dp_RD1EReg_pin_internal[17] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_17_.QN;
assign ieu_dp_RD1EReg_pin_internal[18] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_18_.QN;
assign ieu_dp_RD1EReg_pin_internal[19] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_19_.QN;
assign ieu_dp_RD1EReg_pin_internal[20] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_20_.QN;
assign ieu_dp_RD1EReg_pin_internal[21] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_21_.QN;
assign ieu_dp_RD1EReg_pin_internal[22] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_22_.QN;
assign ieu_dp_RD1EReg_pin_internal[23] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_23_.QN;
assign ieu_dp_RD1EReg_pin_internal[24] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_24_.QN;
assign ieu_dp_RD1EReg_pin_internal[25] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_25_.QN;
assign ieu_dp_RD1EReg_pin_internal[26] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_26_.Q;
assign ieu_dp_RD1EReg_pin_internal[27] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_27_.QN;
assign ieu_dp_RD1EReg_pin_internal[28] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_28_.QN;
assign ieu_dp_RD1EReg_pin_internal[29] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_29_.QN;
assign ieu_dp_RD1EReg_pin_internal[30] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_30_.QN;
assign ieu_dp_RD1EReg_pin_internal[31] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_31_.QN;
assign ieu_dp_RD1EReg_pin_internal[32] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_32_.QN;
assign ieu_dp_RD1EReg_pin_internal[33] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_33_.QN;
assign ieu_dp_RD1EReg_pin_internal[34] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_34_.Q;
assign ieu_dp_RD1EReg_pin_internal[35] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_35_.QN;
assign ieu_dp_RD1EReg_pin_internal[36] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_36_.QN;
assign ieu_dp_RD1EReg_pin_internal[37] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_37_.QN;
assign ieu_dp_RD1EReg_pin_internal[38] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_38_.QN;
assign ieu_dp_RD1EReg_pin_internal[39] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_39_.QN;
assign ieu_dp_RD1EReg_pin_internal[40] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_40_.QN;
assign ieu_dp_RD1EReg_pin_internal[41] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_41_.QN;
assign ieu_dp_RD1EReg_pin_internal[42] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_42_.QN;
assign ieu_dp_RD1EReg_pin_internal[43] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_43_.QN;
assign ieu_dp_RD1EReg_pin_internal[44] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_44_.QN;
assign ieu_dp_RD1EReg_pin_internal[45] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_45_.QN;
assign ieu_dp_RD1EReg_pin_internal[46] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_46_.QN;
assign ieu_dp_RD1EReg_pin_internal[47] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_47_.QN;
assign ieu_dp_RD1EReg_pin_internal[48] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_48_.QN;
assign ieu_dp_RD1EReg_pin_internal[49] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_49_.QN;
assign ieu_dp_RD1EReg_pin_internal[50] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_50_.QN;
assign ieu_dp_RD1EReg_pin_internal[51] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_51_.Q;
assign ieu_dp_RD1EReg_pin_internal[52] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_52_.QN;
assign ieu_dp_RD1EReg_pin_internal[53] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_53_.QN;
assign ieu_dp_RD1EReg_pin_internal[54] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_54_.QN;
assign ieu_dp_RD1EReg_pin_internal[55] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_55_.QN;
assign ieu_dp_RD1EReg_pin_internal[56] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_56_.QN;
assign ieu_dp_RD1EReg_pin_internal[57] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_57_.QN;
assign ieu_dp_RD1EReg_pin_internal[58] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_58_.QN;
assign ieu_dp_RD1EReg_pin_internal[59] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_59_.QN;
assign ieu_dp_RD1EReg_pin_internal[60] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_60_.QN;
assign ieu_dp_RD1EReg_pin_internal[61] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_61_.QN;
assign ieu_dp_RD1EReg_pin_internal[62] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_62_.QN;
assign ieu_dp_RD1EReg_pin_internal[63] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_63_.QN;
assign ieu_dp_RD1EReg_pin_internal[64] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_64_.QN;
assign ieu_dp_RD1EReg_pin_internal[65] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_65_.QN;
assign ieu_dp_RD1EReg_pin_internal[66] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_66_.Q;
assign ieu_dp_RD1EReg_pin_internal[67] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_67_.Q;
assign ieu_dp_RD1EReg_pin_internal[68] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_68_.QN;
assign ieu_dp_RD1EReg_pin_internal[69] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_69_.QN;
assign ieu_dp_RD1EReg_pin_internal[70] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_70_.QN;
assign ieu_dp_RD1EReg_pin_internal[71] = dut.chip.soc_core_ieu_dp_RD1EReg_cw_stored_reg_71_.QN;

// ---- ieu_dp_RD1EReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ieu_dp_RD1EReg_raw_internal_available[0] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[1] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[2] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[3] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[4] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[5] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[6] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[7] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[8] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[9] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[10] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[11] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[12] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[13] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[14] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[15] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[16] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[17] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[18] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[19] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[20] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[21] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[22] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[23] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[24] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[25] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[26] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[27] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[28] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[29] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[30] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[31] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[32] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[33] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[34] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[35] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[36] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[37] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[38] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[39] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[40] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[41] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[42] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[43] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[44] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[45] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[46] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[47] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[48] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[49] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[50] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[51] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[52] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[53] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[54] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[55] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[56] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[57] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[58] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[59] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[60] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[61] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[62] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[63] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[64] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[65] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[66] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[67] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[68] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[69] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[70] = 1'b1;
assign ieu_dp_RD1EReg_raw_internal_available[71] = 1'b1;

// ============================================================================
// Register ieu_dp_RD2EReg: 72 mapped bits, width 72
// ============================================================================

// Bus declarations
wire [71:0] ieu_dp_RD2EReg_internal;
wire [71:0] ieu_dp_RD2EReg_raw_internal;
wire [71:0] ieu_dp_RD2EReg_pin_internal;
wire [71:0] ieu_dp_RD2EReg_raw_internal_available;

// ---- ieu_dp_RD2EReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ieu_dp_RD2EReg_raw_internal[0] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_0_.Q; // c1[184]
assign ieu_dp_RD2EReg_raw_internal[1] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_1_.Q; // c1[185]
assign ieu_dp_RD2EReg_raw_internal[2] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_2_.Q; // c1[186]
assign ieu_dp_RD2EReg_raw_internal[3] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_3_.Q; // c2[1]
assign ieu_dp_RD2EReg_raw_internal[4] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_4_.Q; // c2[2]
assign ieu_dp_RD2EReg_raw_internal[5] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_5_.Q; // c2[3]
assign ieu_dp_RD2EReg_raw_internal[6] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_6_.Q; // c2[4]
assign ieu_dp_RD2EReg_raw_internal[7] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_7_.Q; // c2[5]
assign ieu_dp_RD2EReg_raw_internal[8] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_8_.Q; // c2[6]
assign ieu_dp_RD2EReg_raw_internal[9] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_9_.QN; // c2[7]
assign ieu_dp_RD2EReg_raw_internal[10] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_10_.QN; // c2[8]
assign ieu_dp_RD2EReg_raw_internal[11] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_11_.QN; // c2[9]
assign ieu_dp_RD2EReg_raw_internal[12] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_12_.QN; // c2[10]
assign ieu_dp_RD2EReg_raw_internal[13] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_13_.QN; // c2[11]
assign ieu_dp_RD2EReg_raw_internal[14] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_14_.QN; // c2[12]
assign ieu_dp_RD2EReg_raw_internal[15] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_15_.Q; // c2[13]
assign ieu_dp_RD2EReg_raw_internal[16] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_16_.QN; // c2[14]
assign ieu_dp_RD2EReg_raw_internal[17] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_17_.QN; // c2[15]
assign ieu_dp_RD2EReg_raw_internal[18] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_18_.QN; // c2[16]
assign ieu_dp_RD2EReg_raw_internal[19] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_19_.QN; // c2[17]
assign ieu_dp_RD2EReg_raw_internal[20] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_20_.QN; // c2[18]
assign ieu_dp_RD2EReg_raw_internal[21] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_21_.QN; // c2[19]
assign ieu_dp_RD2EReg_raw_internal[22] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_22_.QN; // c2[20]
assign ieu_dp_RD2EReg_raw_internal[23] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_23_.QN; // c2[21]
assign ieu_dp_RD2EReg_raw_internal[24] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_24_.QN; // c2[22]
assign ieu_dp_RD2EReg_raw_internal[25] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_25_.QN; // c2[23]
assign ieu_dp_RD2EReg_raw_internal[26] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_26_.Q; // c2[24]
assign ieu_dp_RD2EReg_raw_internal[27] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_27_.QN; // c2[25]
assign ieu_dp_RD2EReg_raw_internal[28] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_28_.QN; // c2[26]
assign ieu_dp_RD2EReg_raw_internal[29] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_29_.QN; // c2[27]
assign ieu_dp_RD2EReg_raw_internal[30] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_30_.QN; // c2[28]
assign ieu_dp_RD2EReg_raw_internal[31] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_31_.QN; // c2[29]
assign ieu_dp_RD2EReg_raw_internal[32] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_32_.QN; // c2[30]
assign ieu_dp_RD2EReg_raw_internal[33] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_33_.QN; // c2[31]
assign ieu_dp_RD2EReg_raw_internal[34] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_34_.Q; // c2[32]
assign ieu_dp_RD2EReg_raw_internal[35] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_35_.QN; // c2[33]
assign ieu_dp_RD2EReg_raw_internal[36] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_36_.QN; // c2[34]
assign ieu_dp_RD2EReg_raw_internal[37] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_37_.QN; // c2[35]
assign ieu_dp_RD2EReg_raw_internal[38] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_38_.QN; // c2[36]
assign ieu_dp_RD2EReg_raw_internal[39] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_39_.QN; // c2[37]
assign ieu_dp_RD2EReg_raw_internal[40] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_40_.QN; // c2[38]
assign ieu_dp_RD2EReg_raw_internal[41] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_41_.QN; // c2[39]
assign ieu_dp_RD2EReg_raw_internal[42] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_42_.QN; // c2[40]
assign ieu_dp_RD2EReg_raw_internal[43] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_43_.QN; // c2[41]
assign ieu_dp_RD2EReg_raw_internal[44] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_44_.QN; // c2[42]
assign ieu_dp_RD2EReg_raw_internal[45] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_45_.QN; // c2[43]
assign ieu_dp_RD2EReg_raw_internal[46] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_46_.QN; // c2[44]
assign ieu_dp_RD2EReg_raw_internal[47] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_47_.QN; // c2[45]
assign ieu_dp_RD2EReg_raw_internal[48] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_48_.QN; // c2[46]
assign ieu_dp_RD2EReg_raw_internal[49] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_49_.QN; // c2[47]
assign ieu_dp_RD2EReg_raw_internal[50] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_50_.QN; // c2[48]
assign ieu_dp_RD2EReg_raw_internal[51] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_51_.Q; // c2[49]
assign ieu_dp_RD2EReg_raw_internal[52] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_52_.QN; // c2[50]
assign ieu_dp_RD2EReg_raw_internal[53] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_53_.QN; // c2[51]
assign ieu_dp_RD2EReg_raw_internal[54] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_54_.QN; // c2[52]
assign ieu_dp_RD2EReg_raw_internal[55] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_55_.QN; // c2[53]
assign ieu_dp_RD2EReg_raw_internal[56] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_56_.QN; // c2[54]
assign ieu_dp_RD2EReg_raw_internal[57] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_57_.QN; // c2[55]
assign ieu_dp_RD2EReg_raw_internal[58] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_58_.QN; // c2[56]
assign ieu_dp_RD2EReg_raw_internal[59] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_59_.QN; // c2[57]
assign ieu_dp_RD2EReg_raw_internal[60] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_60_.QN; // c2[58]
assign ieu_dp_RD2EReg_raw_internal[61] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_61_.QN; // c2[59]
assign ieu_dp_RD2EReg_raw_internal[62] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_62_.QN; // c2[60]
assign ieu_dp_RD2EReg_raw_internal[63] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_63_.QN; // c2[61]
assign ieu_dp_RD2EReg_raw_internal[64] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_64_.QN; // c2[62]
assign ieu_dp_RD2EReg_raw_internal[65] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_65_.QN; // c2[63]
assign ieu_dp_RD2EReg_raw_internal[66] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_66_.Q; // c2[64]
assign ieu_dp_RD2EReg_raw_internal[67] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_67_.Q; // c2[65]
assign ieu_dp_RD2EReg_raw_internal[68] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_68_.QN; // c2[66]
assign ieu_dp_RD2EReg_raw_internal[69] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_69_.QN; // c2[67]
assign ieu_dp_RD2EReg_raw_internal[70] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_70_.QN; // c2[68]
assign ieu_dp_RD2EReg_raw_internal[71] = ~dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_71_.QN; // c2[69]

// ---- ieu_dp_RD2EReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ieu_dp_RD2EReg_internal[0] = ieu_dp_RD2EReg_raw_internal[0];
assign ieu_dp_RD2EReg_internal[1] = ieu_dp_RD2EReg_raw_internal[1];
assign ieu_dp_RD2EReg_internal[2] = ieu_dp_RD2EReg_raw_internal[2];
assign ieu_dp_RD2EReg_internal[3] = ieu_dp_RD2EReg_raw_internal[3];
assign ieu_dp_RD2EReg_internal[4] = ieu_dp_RD2EReg_raw_internal[4];
assign ieu_dp_RD2EReg_internal[5] = ieu_dp_RD2EReg_raw_internal[5];
assign ieu_dp_RD2EReg_internal[6] = ieu_dp_RD2EReg_raw_internal[6];
assign ieu_dp_RD2EReg_internal[7] = ieu_dp_RD2EReg_raw_internal[7];
assign ieu_dp_RD2EReg_internal[8] = ieu_dp_RD2EReg_raw_internal[8];
assign ieu_dp_RD2EReg_internal[9] = ieu_dp_RD2EReg_raw_internal[9];
assign ieu_dp_RD2EReg_internal[10] = ieu_dp_RD2EReg_raw_internal[10];
assign ieu_dp_RD2EReg_internal[11] = ieu_dp_RD2EReg_raw_internal[11];
assign ieu_dp_RD2EReg_internal[12] = ieu_dp_RD2EReg_raw_internal[12];
assign ieu_dp_RD2EReg_internal[13] = ieu_dp_RD2EReg_raw_internal[13];
assign ieu_dp_RD2EReg_internal[14] = ieu_dp_RD2EReg_raw_internal[14];
assign ieu_dp_RD2EReg_internal[15] = ieu_dp_RD2EReg_raw_internal[15];
assign ieu_dp_RD2EReg_internal[16] = ieu_dp_RD2EReg_raw_internal[16];
assign ieu_dp_RD2EReg_internal[17] = ieu_dp_RD2EReg_raw_internal[17];
assign ieu_dp_RD2EReg_internal[18] = ieu_dp_RD2EReg_raw_internal[18];
assign ieu_dp_RD2EReg_internal[19] = ieu_dp_RD2EReg_raw_internal[19];
assign ieu_dp_RD2EReg_internal[20] = ieu_dp_RD2EReg_raw_internal[20];
assign ieu_dp_RD2EReg_internal[21] = ieu_dp_RD2EReg_raw_internal[21];
assign ieu_dp_RD2EReg_internal[22] = ieu_dp_RD2EReg_raw_internal[22];
assign ieu_dp_RD2EReg_internal[23] = ieu_dp_RD2EReg_raw_internal[23];
assign ieu_dp_RD2EReg_internal[24] = ieu_dp_RD2EReg_raw_internal[24];
assign ieu_dp_RD2EReg_internal[25] = ieu_dp_RD2EReg_raw_internal[25];
assign ieu_dp_RD2EReg_internal[26] = ieu_dp_RD2EReg_raw_internal[26];
assign ieu_dp_RD2EReg_internal[27] = ieu_dp_RD2EReg_raw_internal[27];
assign ieu_dp_RD2EReg_internal[28] = ieu_dp_RD2EReg_raw_internal[28];
assign ieu_dp_RD2EReg_internal[29] = ieu_dp_RD2EReg_raw_internal[29];
assign ieu_dp_RD2EReg_internal[30] = ieu_dp_RD2EReg_raw_internal[30];
assign ieu_dp_RD2EReg_internal[31] = ieu_dp_RD2EReg_raw_internal[31];
assign ieu_dp_RD2EReg_internal[32] = ieu_dp_RD2EReg_raw_internal[32];
assign ieu_dp_RD2EReg_internal[33] = ieu_dp_RD2EReg_raw_internal[33];
assign ieu_dp_RD2EReg_internal[34] = ieu_dp_RD2EReg_raw_internal[34];
assign ieu_dp_RD2EReg_internal[35] = ieu_dp_RD2EReg_raw_internal[35];
assign ieu_dp_RD2EReg_internal[36] = ieu_dp_RD2EReg_raw_internal[36];
assign ieu_dp_RD2EReg_internal[37] = ieu_dp_RD2EReg_raw_internal[37];
assign ieu_dp_RD2EReg_internal[38] = ieu_dp_RD2EReg_raw_internal[38];
assign ieu_dp_RD2EReg_internal[39] = ieu_dp_RD2EReg_raw_internal[39];
assign ieu_dp_RD2EReg_internal[40] = ieu_dp_RD2EReg_raw_internal[40];
assign ieu_dp_RD2EReg_internal[41] = ieu_dp_RD2EReg_raw_internal[41];
assign ieu_dp_RD2EReg_internal[42] = ieu_dp_RD2EReg_raw_internal[42];
assign ieu_dp_RD2EReg_internal[43] = ieu_dp_RD2EReg_raw_internal[43];
assign ieu_dp_RD2EReg_internal[44] = ieu_dp_RD2EReg_raw_internal[44];
assign ieu_dp_RD2EReg_internal[45] = ieu_dp_RD2EReg_raw_internal[45];
assign ieu_dp_RD2EReg_internal[46] = ieu_dp_RD2EReg_raw_internal[46];
assign ieu_dp_RD2EReg_internal[47] = ieu_dp_RD2EReg_raw_internal[47];
assign ieu_dp_RD2EReg_internal[48] = ieu_dp_RD2EReg_raw_internal[48];
assign ieu_dp_RD2EReg_internal[49] = ieu_dp_RD2EReg_raw_internal[49];
assign ieu_dp_RD2EReg_internal[50] = ieu_dp_RD2EReg_raw_internal[50];
assign ieu_dp_RD2EReg_internal[51] = ieu_dp_RD2EReg_raw_internal[51];
assign ieu_dp_RD2EReg_internal[52] = ieu_dp_RD2EReg_raw_internal[52];
assign ieu_dp_RD2EReg_internal[53] = ieu_dp_RD2EReg_raw_internal[53];
assign ieu_dp_RD2EReg_internal[54] = ieu_dp_RD2EReg_raw_internal[54];
assign ieu_dp_RD2EReg_internal[55] = ieu_dp_RD2EReg_raw_internal[55];
assign ieu_dp_RD2EReg_internal[56] = ieu_dp_RD2EReg_raw_internal[56];
assign ieu_dp_RD2EReg_internal[57] = ieu_dp_RD2EReg_raw_internal[57];
assign ieu_dp_RD2EReg_internal[58] = ieu_dp_RD2EReg_raw_internal[58];
assign ieu_dp_RD2EReg_internal[59] = ieu_dp_RD2EReg_raw_internal[59];
assign ieu_dp_RD2EReg_internal[60] = ieu_dp_RD2EReg_raw_internal[60];
assign ieu_dp_RD2EReg_internal[61] = ieu_dp_RD2EReg_raw_internal[61];
assign ieu_dp_RD2EReg_internal[62] = ieu_dp_RD2EReg_raw_internal[62];
assign ieu_dp_RD2EReg_internal[63] = ieu_dp_RD2EReg_raw_internal[63];
assign ieu_dp_RD2EReg_internal[64] = ieu_dp_RD2EReg_raw_internal[64];
assign ieu_dp_RD2EReg_internal[65] = ieu_dp_RD2EReg_raw_internal[65];
assign ieu_dp_RD2EReg_internal[66] = ieu_dp_RD2EReg_raw_internal[66];
assign ieu_dp_RD2EReg_internal[67] = ieu_dp_RD2EReg_raw_internal[67];
assign ieu_dp_RD2EReg_internal[68] = ieu_dp_RD2EReg_raw_internal[68];
assign ieu_dp_RD2EReg_internal[69] = ieu_dp_RD2EReg_raw_internal[69];
assign ieu_dp_RD2EReg_internal[70] = ieu_dp_RD2EReg_raw_internal[70];
assign ieu_dp_RD2EReg_internal[71] = ieu_dp_RD2EReg_raw_internal[71];

// ---- ieu_dp_RD2EReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ieu_dp_RD2EReg_pin_internal[0] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_0_.Q;
assign ieu_dp_RD2EReg_pin_internal[1] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_1_.Q;
assign ieu_dp_RD2EReg_pin_internal[2] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_2_.Q;
assign ieu_dp_RD2EReg_pin_internal[3] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_3_.Q;
assign ieu_dp_RD2EReg_pin_internal[4] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_4_.Q;
assign ieu_dp_RD2EReg_pin_internal[5] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_5_.Q;
assign ieu_dp_RD2EReg_pin_internal[6] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_6_.Q;
assign ieu_dp_RD2EReg_pin_internal[7] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_7_.Q;
assign ieu_dp_RD2EReg_pin_internal[8] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_8_.Q;
assign ieu_dp_RD2EReg_pin_internal[9] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_9_.QN;
assign ieu_dp_RD2EReg_pin_internal[10] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_10_.QN;
assign ieu_dp_RD2EReg_pin_internal[11] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_11_.QN;
assign ieu_dp_RD2EReg_pin_internal[12] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_12_.QN;
assign ieu_dp_RD2EReg_pin_internal[13] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_13_.QN;
assign ieu_dp_RD2EReg_pin_internal[14] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_14_.QN;
assign ieu_dp_RD2EReg_pin_internal[15] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_15_.Q;
assign ieu_dp_RD2EReg_pin_internal[16] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_16_.QN;
assign ieu_dp_RD2EReg_pin_internal[17] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_17_.QN;
assign ieu_dp_RD2EReg_pin_internal[18] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_18_.QN;
assign ieu_dp_RD2EReg_pin_internal[19] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_19_.QN;
assign ieu_dp_RD2EReg_pin_internal[20] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_20_.QN;
assign ieu_dp_RD2EReg_pin_internal[21] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_21_.QN;
assign ieu_dp_RD2EReg_pin_internal[22] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_22_.QN;
assign ieu_dp_RD2EReg_pin_internal[23] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_23_.QN;
assign ieu_dp_RD2EReg_pin_internal[24] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_24_.QN;
assign ieu_dp_RD2EReg_pin_internal[25] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_25_.QN;
assign ieu_dp_RD2EReg_pin_internal[26] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_26_.Q;
assign ieu_dp_RD2EReg_pin_internal[27] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_27_.QN;
assign ieu_dp_RD2EReg_pin_internal[28] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_28_.QN;
assign ieu_dp_RD2EReg_pin_internal[29] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_29_.QN;
assign ieu_dp_RD2EReg_pin_internal[30] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_30_.QN;
assign ieu_dp_RD2EReg_pin_internal[31] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_31_.QN;
assign ieu_dp_RD2EReg_pin_internal[32] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_32_.QN;
assign ieu_dp_RD2EReg_pin_internal[33] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_33_.QN;
assign ieu_dp_RD2EReg_pin_internal[34] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_34_.Q;
assign ieu_dp_RD2EReg_pin_internal[35] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_35_.QN;
assign ieu_dp_RD2EReg_pin_internal[36] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_36_.QN;
assign ieu_dp_RD2EReg_pin_internal[37] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_37_.QN;
assign ieu_dp_RD2EReg_pin_internal[38] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_38_.QN;
assign ieu_dp_RD2EReg_pin_internal[39] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_39_.QN;
assign ieu_dp_RD2EReg_pin_internal[40] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_40_.QN;
assign ieu_dp_RD2EReg_pin_internal[41] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_41_.QN;
assign ieu_dp_RD2EReg_pin_internal[42] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_42_.QN;
assign ieu_dp_RD2EReg_pin_internal[43] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_43_.QN;
assign ieu_dp_RD2EReg_pin_internal[44] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_44_.QN;
assign ieu_dp_RD2EReg_pin_internal[45] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_45_.QN;
assign ieu_dp_RD2EReg_pin_internal[46] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_46_.QN;
assign ieu_dp_RD2EReg_pin_internal[47] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_47_.QN;
assign ieu_dp_RD2EReg_pin_internal[48] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_48_.QN;
assign ieu_dp_RD2EReg_pin_internal[49] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_49_.QN;
assign ieu_dp_RD2EReg_pin_internal[50] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_50_.QN;
assign ieu_dp_RD2EReg_pin_internal[51] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_51_.Q;
assign ieu_dp_RD2EReg_pin_internal[52] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_52_.QN;
assign ieu_dp_RD2EReg_pin_internal[53] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_53_.QN;
assign ieu_dp_RD2EReg_pin_internal[54] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_54_.QN;
assign ieu_dp_RD2EReg_pin_internal[55] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_55_.QN;
assign ieu_dp_RD2EReg_pin_internal[56] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_56_.QN;
assign ieu_dp_RD2EReg_pin_internal[57] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_57_.QN;
assign ieu_dp_RD2EReg_pin_internal[58] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_58_.QN;
assign ieu_dp_RD2EReg_pin_internal[59] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_59_.QN;
assign ieu_dp_RD2EReg_pin_internal[60] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_60_.QN;
assign ieu_dp_RD2EReg_pin_internal[61] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_61_.QN;
assign ieu_dp_RD2EReg_pin_internal[62] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_62_.QN;
assign ieu_dp_RD2EReg_pin_internal[63] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_63_.QN;
assign ieu_dp_RD2EReg_pin_internal[64] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_64_.QN;
assign ieu_dp_RD2EReg_pin_internal[65] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_65_.QN;
assign ieu_dp_RD2EReg_pin_internal[66] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_66_.Q;
assign ieu_dp_RD2EReg_pin_internal[67] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_67_.Q;
assign ieu_dp_RD2EReg_pin_internal[68] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_68_.QN;
assign ieu_dp_RD2EReg_pin_internal[69] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_69_.QN;
assign ieu_dp_RD2EReg_pin_internal[70] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_70_.QN;
assign ieu_dp_RD2EReg_pin_internal[71] = dut.chip.soc_core_ieu_dp_RD2EReg_cw_stored_reg_71_.QN;

// ---- ieu_dp_RD2EReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ieu_dp_RD2EReg_raw_internal_available[0] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[1] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[2] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[3] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[4] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[5] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[6] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[7] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[8] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[9] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[10] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[11] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[12] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[13] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[14] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[15] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[16] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[17] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[18] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[19] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[20] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[21] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[22] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[23] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[24] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[25] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[26] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[27] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[28] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[29] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[30] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[31] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[32] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[33] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[34] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[35] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[36] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[37] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[38] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[39] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[40] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[41] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[42] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[43] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[44] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[45] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[46] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[47] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[48] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[49] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[50] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[51] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[52] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[53] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[54] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[55] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[56] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[57] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[58] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[59] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[60] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[61] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[62] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[63] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[64] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[65] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[66] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[67] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[68] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[69] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[70] = 1'b1;
assign ieu_dp_RD2EReg_raw_internal_available[71] = 1'b1;

// ============================================================================
// Register ieu_dp_SrcAMReg: 72 mapped bits, width 72
// ============================================================================

// Bus declarations
wire [71:0] ieu_dp_SrcAMReg_internal;
wire [71:0] ieu_dp_SrcAMReg_raw_internal;
wire [71:0] ieu_dp_SrcAMReg_pin_internal;
wire [71:0] ieu_dp_SrcAMReg_raw_internal_available;

// ---- ieu_dp_SrcAMReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ieu_dp_SrcAMReg_raw_internal[0] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_0_.Q; // c2[70]
assign ieu_dp_SrcAMReg_raw_internal[1] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_1_.Q; // c2[71]
assign ieu_dp_SrcAMReg_raw_internal[2] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_2_.Q; // c2[72]
assign ieu_dp_SrcAMReg_raw_internal[3] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_3_.Q; // c2[73]
assign ieu_dp_SrcAMReg_raw_internal[4] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_4_.Q; // c2[74]
assign ieu_dp_SrcAMReg_raw_internal[5] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_5_.Q; // c2[75]
assign ieu_dp_SrcAMReg_raw_internal[6] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_6_.Q; // c2[76]
assign ieu_dp_SrcAMReg_raw_internal[7] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_7_.Q; // c2[77]
assign ieu_dp_SrcAMReg_raw_internal[8] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_8_.Q; // c2[78]
assign ieu_dp_SrcAMReg_raw_internal[9] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_9_.Q; // c2[79]
assign ieu_dp_SrcAMReg_raw_internal[10] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_10_.Q; // c2[80]
assign ieu_dp_SrcAMReg_raw_internal[11] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_11_.Q; // c2[81]
assign ieu_dp_SrcAMReg_raw_internal[12] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_12_.Q; // c2[82]
assign ieu_dp_SrcAMReg_raw_internal[13] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_13_.Q; // c2[83]
assign ieu_dp_SrcAMReg_raw_internal[14] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_14_.Q; // c2[84]
assign ieu_dp_SrcAMReg_raw_internal[15] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_15_.Q; // c2[85]
assign ieu_dp_SrcAMReg_raw_internal[16] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_16_.Q; // c2[86]
assign ieu_dp_SrcAMReg_raw_internal[17] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_17_.Q; // c2[87]
assign ieu_dp_SrcAMReg_raw_internal[18] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_18_.Q; // c2[88]
assign ieu_dp_SrcAMReg_raw_internal[19] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_19_.Q; // c2[89]
assign ieu_dp_SrcAMReg_raw_internal[20] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_20_.Q; // c2[90]
assign ieu_dp_SrcAMReg_raw_internal[21] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_21_.Q; // c2[91]
assign ieu_dp_SrcAMReg_raw_internal[22] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_22_.Q; // c2[92]
assign ieu_dp_SrcAMReg_raw_internal[23] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_23_.Q; // c2[93]
assign ieu_dp_SrcAMReg_raw_internal[24] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_24_.Q; // c2[94]
assign ieu_dp_SrcAMReg_raw_internal[25] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_25_.Q; // c2[95]
assign ieu_dp_SrcAMReg_raw_internal[26] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_26_.Q; // c2[96]
assign ieu_dp_SrcAMReg_raw_internal[27] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_27_.Q; // c2[97]
assign ieu_dp_SrcAMReg_raw_internal[28] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_28_.Q; // c2[98]
assign ieu_dp_SrcAMReg_raw_internal[29] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_29_.Q; // c2[99]
assign ieu_dp_SrcAMReg_raw_internal[30] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_30_.Q; // c2[100]
assign ieu_dp_SrcAMReg_raw_internal[31] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_31_.Q; // c2[101]
assign ieu_dp_SrcAMReg_raw_internal[32] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_32_.Q; // c2[102]
assign ieu_dp_SrcAMReg_raw_internal[33] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_33_.Q; // c2[103]
assign ieu_dp_SrcAMReg_raw_internal[34] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_34_.Q; // c2[104]
assign ieu_dp_SrcAMReg_raw_internal[35] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_35_.Q; // c2[105]
assign ieu_dp_SrcAMReg_raw_internal[36] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_36_.Q; // c2[106]
assign ieu_dp_SrcAMReg_raw_internal[37] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_37_.Q; // c2[107]
assign ieu_dp_SrcAMReg_raw_internal[38] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_38_.Q; // c2[108]
assign ieu_dp_SrcAMReg_raw_internal[39] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_39_.Q; // c2[109]
assign ieu_dp_SrcAMReg_raw_internal[40] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_40_.Q; // c2[110]
assign ieu_dp_SrcAMReg_raw_internal[41] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_41_.Q; // c2[111]
assign ieu_dp_SrcAMReg_raw_internal[42] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_42_.Q; // c2[112]
assign ieu_dp_SrcAMReg_raw_internal[43] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_43_.Q; // c2[113]
assign ieu_dp_SrcAMReg_raw_internal[44] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_44_.Q; // c2[114]
assign ieu_dp_SrcAMReg_raw_internal[45] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_45_.Q; // c2[115]
assign ieu_dp_SrcAMReg_raw_internal[46] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_46_.Q; // c2[116]
assign ieu_dp_SrcAMReg_raw_internal[47] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_47_.Q; // c2[117]
assign ieu_dp_SrcAMReg_raw_internal[48] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_48_.Q; // c2[118]
assign ieu_dp_SrcAMReg_raw_internal[49] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_49_.Q; // c2[119]
assign ieu_dp_SrcAMReg_raw_internal[50] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_50_.Q; // c2[120]
assign ieu_dp_SrcAMReg_raw_internal[51] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_51_.Q; // c2[121]
assign ieu_dp_SrcAMReg_raw_internal[52] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_52_.Q; // c2[122]
assign ieu_dp_SrcAMReg_raw_internal[53] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_53_.Q; // c2[123]
assign ieu_dp_SrcAMReg_raw_internal[54] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_54_.Q; // c2[124]
assign ieu_dp_SrcAMReg_raw_internal[55] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_55_.Q; // c2[125]
assign ieu_dp_SrcAMReg_raw_internal[56] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_56_.Q; // c2[126]
assign ieu_dp_SrcAMReg_raw_internal[57] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_57_.Q; // c2[127]
assign ieu_dp_SrcAMReg_raw_internal[58] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_58_.Q; // c2[128]
assign ieu_dp_SrcAMReg_raw_internal[59] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_59_.Q; // c2[129]
assign ieu_dp_SrcAMReg_raw_internal[60] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_60_.Q; // c2[130]
assign ieu_dp_SrcAMReg_raw_internal[61] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_61_.Q; // c2[131]
assign ieu_dp_SrcAMReg_raw_internal[62] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_62_.Q; // c2[132]
assign ieu_dp_SrcAMReg_raw_internal[63] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_63_.Q; // c2[133]
assign ieu_dp_SrcAMReg_raw_internal[64] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_64_.Q; // c2[134]
assign ieu_dp_SrcAMReg_raw_internal[65] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_65_.Q; // c2[135]
assign ieu_dp_SrcAMReg_raw_internal[66] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_66_.Q; // c2[136]
assign ieu_dp_SrcAMReg_raw_internal[67] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_67_.Q; // c2[137]
assign ieu_dp_SrcAMReg_raw_internal[68] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_68_.Q; // c2[138]
assign ieu_dp_SrcAMReg_raw_internal[69] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_69_.Q; // c2[139]
assign ieu_dp_SrcAMReg_raw_internal[70] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_70_.Q; // c2[140]
assign ieu_dp_SrcAMReg_raw_internal[71] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_71_.Q; // c2[141]

// ---- ieu_dp_SrcAMReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ieu_dp_SrcAMReg_internal[0] = ieu_dp_SrcAMReg_raw_internal[0];
assign ieu_dp_SrcAMReg_internal[1] = ieu_dp_SrcAMReg_raw_internal[1];
assign ieu_dp_SrcAMReg_internal[2] = ieu_dp_SrcAMReg_raw_internal[2];
assign ieu_dp_SrcAMReg_internal[3] = ieu_dp_SrcAMReg_raw_internal[3];
assign ieu_dp_SrcAMReg_internal[4] = ieu_dp_SrcAMReg_raw_internal[4];
assign ieu_dp_SrcAMReg_internal[5] = ieu_dp_SrcAMReg_raw_internal[5];
assign ieu_dp_SrcAMReg_internal[6] = ieu_dp_SrcAMReg_raw_internal[6];
assign ieu_dp_SrcAMReg_internal[7] = ieu_dp_SrcAMReg_raw_internal[7];
assign ieu_dp_SrcAMReg_internal[8] = ieu_dp_SrcAMReg_raw_internal[8];
assign ieu_dp_SrcAMReg_internal[9] = ieu_dp_SrcAMReg_raw_internal[9];
assign ieu_dp_SrcAMReg_internal[10] = ieu_dp_SrcAMReg_raw_internal[10];
assign ieu_dp_SrcAMReg_internal[11] = ieu_dp_SrcAMReg_raw_internal[11];
assign ieu_dp_SrcAMReg_internal[12] = ieu_dp_SrcAMReg_raw_internal[12];
assign ieu_dp_SrcAMReg_internal[13] = ieu_dp_SrcAMReg_raw_internal[13];
assign ieu_dp_SrcAMReg_internal[14] = ieu_dp_SrcAMReg_raw_internal[14];
assign ieu_dp_SrcAMReg_internal[15] = ieu_dp_SrcAMReg_raw_internal[15];
assign ieu_dp_SrcAMReg_internal[16] = ieu_dp_SrcAMReg_raw_internal[16];
assign ieu_dp_SrcAMReg_internal[17] = ieu_dp_SrcAMReg_raw_internal[17];
assign ieu_dp_SrcAMReg_internal[18] = ieu_dp_SrcAMReg_raw_internal[18];
assign ieu_dp_SrcAMReg_internal[19] = ieu_dp_SrcAMReg_raw_internal[19];
assign ieu_dp_SrcAMReg_internal[20] = ieu_dp_SrcAMReg_raw_internal[20];
assign ieu_dp_SrcAMReg_internal[21] = ieu_dp_SrcAMReg_raw_internal[21];
assign ieu_dp_SrcAMReg_internal[22] = ieu_dp_SrcAMReg_raw_internal[22];
assign ieu_dp_SrcAMReg_internal[23] = ieu_dp_SrcAMReg_raw_internal[23];
assign ieu_dp_SrcAMReg_internal[24] = ieu_dp_SrcAMReg_raw_internal[24];
assign ieu_dp_SrcAMReg_internal[25] = ieu_dp_SrcAMReg_raw_internal[25];
assign ieu_dp_SrcAMReg_internal[26] = ieu_dp_SrcAMReg_raw_internal[26];
assign ieu_dp_SrcAMReg_internal[27] = ieu_dp_SrcAMReg_raw_internal[27];
assign ieu_dp_SrcAMReg_internal[28] = ieu_dp_SrcAMReg_raw_internal[28];
assign ieu_dp_SrcAMReg_internal[29] = ieu_dp_SrcAMReg_raw_internal[29];
assign ieu_dp_SrcAMReg_internal[30] = ieu_dp_SrcAMReg_raw_internal[30];
assign ieu_dp_SrcAMReg_internal[31] = ieu_dp_SrcAMReg_raw_internal[31];
assign ieu_dp_SrcAMReg_internal[32] = ieu_dp_SrcAMReg_raw_internal[32];
assign ieu_dp_SrcAMReg_internal[33] = ieu_dp_SrcAMReg_raw_internal[33];
assign ieu_dp_SrcAMReg_internal[34] = ieu_dp_SrcAMReg_raw_internal[34];
assign ieu_dp_SrcAMReg_internal[35] = ieu_dp_SrcAMReg_raw_internal[35];
assign ieu_dp_SrcAMReg_internal[36] = ieu_dp_SrcAMReg_raw_internal[36];
assign ieu_dp_SrcAMReg_internal[37] = ieu_dp_SrcAMReg_raw_internal[37];
assign ieu_dp_SrcAMReg_internal[38] = ieu_dp_SrcAMReg_raw_internal[38];
assign ieu_dp_SrcAMReg_internal[39] = ieu_dp_SrcAMReg_raw_internal[39];
assign ieu_dp_SrcAMReg_internal[40] = ieu_dp_SrcAMReg_raw_internal[40];
assign ieu_dp_SrcAMReg_internal[41] = ieu_dp_SrcAMReg_raw_internal[41];
assign ieu_dp_SrcAMReg_internal[42] = ieu_dp_SrcAMReg_raw_internal[42];
assign ieu_dp_SrcAMReg_internal[43] = ieu_dp_SrcAMReg_raw_internal[43];
assign ieu_dp_SrcAMReg_internal[44] = ieu_dp_SrcAMReg_raw_internal[44];
assign ieu_dp_SrcAMReg_internal[45] = ieu_dp_SrcAMReg_raw_internal[45];
assign ieu_dp_SrcAMReg_internal[46] = ieu_dp_SrcAMReg_raw_internal[46];
assign ieu_dp_SrcAMReg_internal[47] = ieu_dp_SrcAMReg_raw_internal[47];
assign ieu_dp_SrcAMReg_internal[48] = ieu_dp_SrcAMReg_raw_internal[48];
assign ieu_dp_SrcAMReg_internal[49] = ieu_dp_SrcAMReg_raw_internal[49];
assign ieu_dp_SrcAMReg_internal[50] = ieu_dp_SrcAMReg_raw_internal[50];
assign ieu_dp_SrcAMReg_internal[51] = ieu_dp_SrcAMReg_raw_internal[51];
assign ieu_dp_SrcAMReg_internal[52] = ieu_dp_SrcAMReg_raw_internal[52];
assign ieu_dp_SrcAMReg_internal[53] = ieu_dp_SrcAMReg_raw_internal[53];
assign ieu_dp_SrcAMReg_internal[54] = ieu_dp_SrcAMReg_raw_internal[54];
assign ieu_dp_SrcAMReg_internal[55] = ieu_dp_SrcAMReg_raw_internal[55];
assign ieu_dp_SrcAMReg_internal[56] = ieu_dp_SrcAMReg_raw_internal[56];
assign ieu_dp_SrcAMReg_internal[57] = ieu_dp_SrcAMReg_raw_internal[57];
assign ieu_dp_SrcAMReg_internal[58] = ieu_dp_SrcAMReg_raw_internal[58];
assign ieu_dp_SrcAMReg_internal[59] = ieu_dp_SrcAMReg_raw_internal[59];
assign ieu_dp_SrcAMReg_internal[60] = ieu_dp_SrcAMReg_raw_internal[60];
assign ieu_dp_SrcAMReg_internal[61] = ieu_dp_SrcAMReg_raw_internal[61];
assign ieu_dp_SrcAMReg_internal[62] = ieu_dp_SrcAMReg_raw_internal[62];
assign ieu_dp_SrcAMReg_internal[63] = ieu_dp_SrcAMReg_raw_internal[63];
assign ieu_dp_SrcAMReg_internal[64] = ieu_dp_SrcAMReg_raw_internal[64];
assign ieu_dp_SrcAMReg_internal[65] = ieu_dp_SrcAMReg_raw_internal[65];
assign ieu_dp_SrcAMReg_internal[66] = ieu_dp_SrcAMReg_raw_internal[66];
assign ieu_dp_SrcAMReg_internal[67] = ieu_dp_SrcAMReg_raw_internal[67];
assign ieu_dp_SrcAMReg_internal[68] = ieu_dp_SrcAMReg_raw_internal[68];
assign ieu_dp_SrcAMReg_internal[69] = ieu_dp_SrcAMReg_raw_internal[69];
assign ieu_dp_SrcAMReg_internal[70] = ieu_dp_SrcAMReg_raw_internal[70];
assign ieu_dp_SrcAMReg_internal[71] = ieu_dp_SrcAMReg_raw_internal[71];

// ---- ieu_dp_SrcAMReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ieu_dp_SrcAMReg_pin_internal[0] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_0_.Q;
assign ieu_dp_SrcAMReg_pin_internal[1] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_1_.Q;
assign ieu_dp_SrcAMReg_pin_internal[2] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_2_.Q;
assign ieu_dp_SrcAMReg_pin_internal[3] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_3_.Q;
assign ieu_dp_SrcAMReg_pin_internal[4] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_4_.Q;
assign ieu_dp_SrcAMReg_pin_internal[5] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_5_.Q;
assign ieu_dp_SrcAMReg_pin_internal[6] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_6_.Q;
assign ieu_dp_SrcAMReg_pin_internal[7] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_7_.Q;
assign ieu_dp_SrcAMReg_pin_internal[8] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_8_.Q;
assign ieu_dp_SrcAMReg_pin_internal[9] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_9_.Q;
assign ieu_dp_SrcAMReg_pin_internal[10] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_10_.Q;
assign ieu_dp_SrcAMReg_pin_internal[11] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_11_.Q;
assign ieu_dp_SrcAMReg_pin_internal[12] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_12_.Q;
assign ieu_dp_SrcAMReg_pin_internal[13] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_13_.Q;
assign ieu_dp_SrcAMReg_pin_internal[14] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_14_.Q;
assign ieu_dp_SrcAMReg_pin_internal[15] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_15_.Q;
assign ieu_dp_SrcAMReg_pin_internal[16] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_16_.Q;
assign ieu_dp_SrcAMReg_pin_internal[17] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_17_.Q;
assign ieu_dp_SrcAMReg_pin_internal[18] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_18_.Q;
assign ieu_dp_SrcAMReg_pin_internal[19] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_19_.Q;
assign ieu_dp_SrcAMReg_pin_internal[20] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_20_.Q;
assign ieu_dp_SrcAMReg_pin_internal[21] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_21_.Q;
assign ieu_dp_SrcAMReg_pin_internal[22] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_22_.Q;
assign ieu_dp_SrcAMReg_pin_internal[23] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_23_.Q;
assign ieu_dp_SrcAMReg_pin_internal[24] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_24_.Q;
assign ieu_dp_SrcAMReg_pin_internal[25] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_25_.Q;
assign ieu_dp_SrcAMReg_pin_internal[26] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_26_.Q;
assign ieu_dp_SrcAMReg_pin_internal[27] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_27_.Q;
assign ieu_dp_SrcAMReg_pin_internal[28] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_28_.Q;
assign ieu_dp_SrcAMReg_pin_internal[29] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_29_.Q;
assign ieu_dp_SrcAMReg_pin_internal[30] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_30_.Q;
assign ieu_dp_SrcAMReg_pin_internal[31] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_31_.Q;
assign ieu_dp_SrcAMReg_pin_internal[32] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_32_.Q;
assign ieu_dp_SrcAMReg_pin_internal[33] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_33_.Q;
assign ieu_dp_SrcAMReg_pin_internal[34] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_34_.Q;
assign ieu_dp_SrcAMReg_pin_internal[35] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_35_.Q;
assign ieu_dp_SrcAMReg_pin_internal[36] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_36_.Q;
assign ieu_dp_SrcAMReg_pin_internal[37] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_37_.Q;
assign ieu_dp_SrcAMReg_pin_internal[38] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_38_.Q;
assign ieu_dp_SrcAMReg_pin_internal[39] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_39_.Q;
assign ieu_dp_SrcAMReg_pin_internal[40] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_40_.Q;
assign ieu_dp_SrcAMReg_pin_internal[41] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_41_.Q;
assign ieu_dp_SrcAMReg_pin_internal[42] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_42_.Q;
assign ieu_dp_SrcAMReg_pin_internal[43] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_43_.Q;
assign ieu_dp_SrcAMReg_pin_internal[44] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_44_.Q;
assign ieu_dp_SrcAMReg_pin_internal[45] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_45_.Q;
assign ieu_dp_SrcAMReg_pin_internal[46] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_46_.Q;
assign ieu_dp_SrcAMReg_pin_internal[47] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_47_.Q;
assign ieu_dp_SrcAMReg_pin_internal[48] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_48_.Q;
assign ieu_dp_SrcAMReg_pin_internal[49] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_49_.Q;
assign ieu_dp_SrcAMReg_pin_internal[50] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_50_.Q;
assign ieu_dp_SrcAMReg_pin_internal[51] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_51_.Q;
assign ieu_dp_SrcAMReg_pin_internal[52] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_52_.Q;
assign ieu_dp_SrcAMReg_pin_internal[53] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_53_.Q;
assign ieu_dp_SrcAMReg_pin_internal[54] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_54_.Q;
assign ieu_dp_SrcAMReg_pin_internal[55] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_55_.Q;
assign ieu_dp_SrcAMReg_pin_internal[56] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_56_.Q;
assign ieu_dp_SrcAMReg_pin_internal[57] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_57_.Q;
assign ieu_dp_SrcAMReg_pin_internal[58] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_58_.Q;
assign ieu_dp_SrcAMReg_pin_internal[59] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_59_.Q;
assign ieu_dp_SrcAMReg_pin_internal[60] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_60_.Q;
assign ieu_dp_SrcAMReg_pin_internal[61] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_61_.Q;
assign ieu_dp_SrcAMReg_pin_internal[62] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_62_.Q;
assign ieu_dp_SrcAMReg_pin_internal[63] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_63_.Q;
assign ieu_dp_SrcAMReg_pin_internal[64] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_64_.Q;
assign ieu_dp_SrcAMReg_pin_internal[65] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_65_.Q;
assign ieu_dp_SrcAMReg_pin_internal[66] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_66_.Q;
assign ieu_dp_SrcAMReg_pin_internal[67] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_67_.Q;
assign ieu_dp_SrcAMReg_pin_internal[68] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_68_.Q;
assign ieu_dp_SrcAMReg_pin_internal[69] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_69_.Q;
assign ieu_dp_SrcAMReg_pin_internal[70] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_70_.Q;
assign ieu_dp_SrcAMReg_pin_internal[71] = dut.chip.soc_core_ieu_dp_SrcAMReg_store.cw_stored_reg_71_.Q;

// ---- ieu_dp_SrcAMReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ieu_dp_SrcAMReg_raw_internal_available[0] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[1] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[2] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[3] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[4] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[5] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[6] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[7] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[8] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[9] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[10] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[11] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[12] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[13] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[14] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[15] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[16] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[17] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[18] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[19] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[20] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[21] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[22] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[23] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[24] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[25] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[26] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[27] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[28] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[29] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[30] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[31] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[32] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[33] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[34] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[35] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[36] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[37] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[38] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[39] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[40] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[41] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[42] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[43] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[44] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[45] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[46] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[47] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[48] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[49] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[50] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[51] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[52] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[53] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[54] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[55] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[56] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[57] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[58] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[59] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[60] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[61] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[62] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[63] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[64] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[65] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[66] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[67] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[68] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[69] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[70] = 1'b1;
assign ieu_dp_SrcAMReg_raw_internal_available[71] = 1'b1;

// ============================================================================
// Register ieu_dp_WriteDataMReg: 72 mapped bits, width 72
// ============================================================================

// Bus declarations
wire [71:0] ieu_dp_WriteDataMReg_internal;
wire [71:0] ieu_dp_WriteDataMReg_raw_internal;
wire [71:0] ieu_dp_WriteDataMReg_pin_internal;
wire [71:0] ieu_dp_WriteDataMReg_raw_internal_available;

// ---- ieu_dp_WriteDataMReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ieu_dp_WriteDataMReg_raw_internal[0] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_0_.Q; // c2[142]
assign ieu_dp_WriteDataMReg_raw_internal[1] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_1_.Q; // c2[143]
assign ieu_dp_WriteDataMReg_raw_internal[2] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_2_.Q; // c2[144]
assign ieu_dp_WriteDataMReg_raw_internal[3] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_3_.Q; // c2[145]
assign ieu_dp_WriteDataMReg_raw_internal[4] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_4_.Q; // c2[146]
assign ieu_dp_WriteDataMReg_raw_internal[5] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_5_.Q; // c2[147]
assign ieu_dp_WriteDataMReg_raw_internal[6] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_6_.Q; // c2[148]
assign ieu_dp_WriteDataMReg_raw_internal[7] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_7_.Q; // c2[149]
assign ieu_dp_WriteDataMReg_raw_internal[8] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_8_.Q; // c2[150]
assign ieu_dp_WriteDataMReg_raw_internal[9] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_9_.Q; // c2[151]
assign ieu_dp_WriteDataMReg_raw_internal[10] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_10_.Q; // c2[152]
assign ieu_dp_WriteDataMReg_raw_internal[11] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_11_.Q; // c2[153]
assign ieu_dp_WriteDataMReg_raw_internal[12] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_12_.Q; // c2[154]
assign ieu_dp_WriteDataMReg_raw_internal[13] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_13_.Q; // c2[155]
assign ieu_dp_WriteDataMReg_raw_internal[14] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_14_.Q; // c2[156]
assign ieu_dp_WriteDataMReg_raw_internal[15] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_15_.Q; // c2[157]
assign ieu_dp_WriteDataMReg_raw_internal[16] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_16_.Q; // c2[158]
assign ieu_dp_WriteDataMReg_raw_internal[17] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_17_.Q; // c2[159]
assign ieu_dp_WriteDataMReg_raw_internal[18] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_18_.Q; // c2[160]
assign ieu_dp_WriteDataMReg_raw_internal[19] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_19_.Q; // c2[161]
assign ieu_dp_WriteDataMReg_raw_internal[20] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_20_.Q; // c2[162]
assign ieu_dp_WriteDataMReg_raw_internal[21] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_21_.Q; // c2[163]
assign ieu_dp_WriteDataMReg_raw_internal[22] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_22_.Q; // c2[164]
assign ieu_dp_WriteDataMReg_raw_internal[23] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_23_.Q; // c2[165]
assign ieu_dp_WriteDataMReg_raw_internal[24] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_24_.Q; // c2[166]
assign ieu_dp_WriteDataMReg_raw_internal[25] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_25_.Q; // c2[167]
assign ieu_dp_WriteDataMReg_raw_internal[26] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_26_.Q; // c2[168]
assign ieu_dp_WriteDataMReg_raw_internal[27] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_27_.Q; // c2[169]
assign ieu_dp_WriteDataMReg_raw_internal[28] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_28_.Q; // c2[170]
assign ieu_dp_WriteDataMReg_raw_internal[29] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_29_.Q; // c2[171]
assign ieu_dp_WriteDataMReg_raw_internal[30] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_30_.Q; // c2[172]
assign ieu_dp_WriteDataMReg_raw_internal[31] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_31_.Q; // c2[173]
assign ieu_dp_WriteDataMReg_raw_internal[32] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_32_.Q; // c2[174]
assign ieu_dp_WriteDataMReg_raw_internal[33] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_33_.Q; // c2[175]
assign ieu_dp_WriteDataMReg_raw_internal[34] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_34_.Q; // c2[176]
assign ieu_dp_WriteDataMReg_raw_internal[35] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_35_.Q; // c2[177]
assign ieu_dp_WriteDataMReg_raw_internal[36] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_36_.Q; // c2[178]
assign ieu_dp_WriteDataMReg_raw_internal[37] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_37_.Q; // c2[179]
assign ieu_dp_WriteDataMReg_raw_internal[38] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_38_.Q; // c2[180]
assign ieu_dp_WriteDataMReg_raw_internal[39] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_39_.Q; // c2[181]
assign ieu_dp_WriteDataMReg_raw_internal[40] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_40_.Q; // c2[182]
assign ieu_dp_WriteDataMReg_raw_internal[41] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_41_.Q; // c2[183]
assign ieu_dp_WriteDataMReg_raw_internal[42] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_42_.Q; // c2[184]
assign ieu_dp_WriteDataMReg_raw_internal[43] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_43_.Q; // c2[185]
assign ieu_dp_WriteDataMReg_raw_internal[44] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_44_.Q; // c2[186]
assign ieu_dp_WriteDataMReg_raw_internal[45] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_45_.Q; // c3[1]
assign ieu_dp_WriteDataMReg_raw_internal[46] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_46_.Q; // c3[2]
assign ieu_dp_WriteDataMReg_raw_internal[47] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_47_.Q; // c3[3]
assign ieu_dp_WriteDataMReg_raw_internal[48] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_48_.Q; // c3[4]
assign ieu_dp_WriteDataMReg_raw_internal[49] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_49_.Q; // c3[5]
assign ieu_dp_WriteDataMReg_raw_internal[50] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_50_.Q; // c3[6]
assign ieu_dp_WriteDataMReg_raw_internal[51] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_51_.Q; // c3[7]
assign ieu_dp_WriteDataMReg_raw_internal[52] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_52_.Q; // c3[8]
assign ieu_dp_WriteDataMReg_raw_internal[53] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_53_.Q; // c3[9]
assign ieu_dp_WriteDataMReg_raw_internal[54] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_54_.Q; // c3[10]
assign ieu_dp_WriteDataMReg_raw_internal[55] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_55_.Q; // c3[11]
assign ieu_dp_WriteDataMReg_raw_internal[56] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_56_.Q; // c3[12]
assign ieu_dp_WriteDataMReg_raw_internal[57] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_57_.Q; // c3[13]
assign ieu_dp_WriteDataMReg_raw_internal[58] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_58_.Q; // c3[14]
assign ieu_dp_WriteDataMReg_raw_internal[59] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_59_.Q; // c3[15]
assign ieu_dp_WriteDataMReg_raw_internal[60] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_60_.Q; // c3[16]
assign ieu_dp_WriteDataMReg_raw_internal[61] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_61_.Q; // c3[17]
assign ieu_dp_WriteDataMReg_raw_internal[62] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_62_.Q; // c3[18]
assign ieu_dp_WriteDataMReg_raw_internal[63] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_63_.Q; // c3[19]
assign ieu_dp_WriteDataMReg_raw_internal[64] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_64_.Q; // c3[20]
assign ieu_dp_WriteDataMReg_raw_internal[65] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_65_.Q; // c3[21]
assign ieu_dp_WriteDataMReg_raw_internal[66] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_66_.Q; // c3[22]
assign ieu_dp_WriteDataMReg_raw_internal[67] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_67_.Q; // c3[23]
assign ieu_dp_WriteDataMReg_raw_internal[68] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_68_.Q; // c3[24]
assign ieu_dp_WriteDataMReg_raw_internal[69] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_69_.Q; // c3[25]
assign ieu_dp_WriteDataMReg_raw_internal[70] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_70_.Q; // c3[26]
assign ieu_dp_WriteDataMReg_raw_internal[71] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_71_.Q; // c3[27]

// ---- ieu_dp_WriteDataMReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ieu_dp_WriteDataMReg_internal[0] = ieu_dp_WriteDataMReg_raw_internal[0];
assign ieu_dp_WriteDataMReg_internal[1] = ieu_dp_WriteDataMReg_raw_internal[1];
assign ieu_dp_WriteDataMReg_internal[2] = ieu_dp_WriteDataMReg_raw_internal[2];
assign ieu_dp_WriteDataMReg_internal[3] = ieu_dp_WriteDataMReg_raw_internal[3];
assign ieu_dp_WriteDataMReg_internal[4] = ieu_dp_WriteDataMReg_raw_internal[4];
assign ieu_dp_WriteDataMReg_internal[5] = ieu_dp_WriteDataMReg_raw_internal[5];
assign ieu_dp_WriteDataMReg_internal[6] = ieu_dp_WriteDataMReg_raw_internal[6];
assign ieu_dp_WriteDataMReg_internal[7] = ieu_dp_WriteDataMReg_raw_internal[7];
assign ieu_dp_WriteDataMReg_internal[8] = ieu_dp_WriteDataMReg_raw_internal[8];
assign ieu_dp_WriteDataMReg_internal[9] = ieu_dp_WriteDataMReg_raw_internal[9];
assign ieu_dp_WriteDataMReg_internal[10] = ieu_dp_WriteDataMReg_raw_internal[10];
assign ieu_dp_WriteDataMReg_internal[11] = ieu_dp_WriteDataMReg_raw_internal[11];
assign ieu_dp_WriteDataMReg_internal[12] = ieu_dp_WriteDataMReg_raw_internal[12];
assign ieu_dp_WriteDataMReg_internal[13] = ieu_dp_WriteDataMReg_raw_internal[13];
assign ieu_dp_WriteDataMReg_internal[14] = ieu_dp_WriteDataMReg_raw_internal[14];
assign ieu_dp_WriteDataMReg_internal[15] = ieu_dp_WriteDataMReg_raw_internal[15];
assign ieu_dp_WriteDataMReg_internal[16] = ieu_dp_WriteDataMReg_raw_internal[16];
assign ieu_dp_WriteDataMReg_internal[17] = ieu_dp_WriteDataMReg_raw_internal[17];
assign ieu_dp_WriteDataMReg_internal[18] = ieu_dp_WriteDataMReg_raw_internal[18];
assign ieu_dp_WriteDataMReg_internal[19] = ieu_dp_WriteDataMReg_raw_internal[19];
assign ieu_dp_WriteDataMReg_internal[20] = ieu_dp_WriteDataMReg_raw_internal[20];
assign ieu_dp_WriteDataMReg_internal[21] = ieu_dp_WriteDataMReg_raw_internal[21];
assign ieu_dp_WriteDataMReg_internal[22] = ieu_dp_WriteDataMReg_raw_internal[22];
assign ieu_dp_WriteDataMReg_internal[23] = ieu_dp_WriteDataMReg_raw_internal[23];
assign ieu_dp_WriteDataMReg_internal[24] = ieu_dp_WriteDataMReg_raw_internal[24];
assign ieu_dp_WriteDataMReg_internal[25] = ieu_dp_WriteDataMReg_raw_internal[25];
assign ieu_dp_WriteDataMReg_internal[26] = ieu_dp_WriteDataMReg_raw_internal[26];
assign ieu_dp_WriteDataMReg_internal[27] = ieu_dp_WriteDataMReg_raw_internal[27];
assign ieu_dp_WriteDataMReg_internal[28] = ieu_dp_WriteDataMReg_raw_internal[28];
assign ieu_dp_WriteDataMReg_internal[29] = ieu_dp_WriteDataMReg_raw_internal[29];
assign ieu_dp_WriteDataMReg_internal[30] = ieu_dp_WriteDataMReg_raw_internal[30];
assign ieu_dp_WriteDataMReg_internal[31] = ieu_dp_WriteDataMReg_raw_internal[31];
assign ieu_dp_WriteDataMReg_internal[32] = ieu_dp_WriteDataMReg_raw_internal[32];
assign ieu_dp_WriteDataMReg_internal[33] = ieu_dp_WriteDataMReg_raw_internal[33];
assign ieu_dp_WriteDataMReg_internal[34] = ieu_dp_WriteDataMReg_raw_internal[34];
assign ieu_dp_WriteDataMReg_internal[35] = ieu_dp_WriteDataMReg_raw_internal[35];
assign ieu_dp_WriteDataMReg_internal[36] = ieu_dp_WriteDataMReg_raw_internal[36];
assign ieu_dp_WriteDataMReg_internal[37] = ieu_dp_WriteDataMReg_raw_internal[37];
assign ieu_dp_WriteDataMReg_internal[38] = ieu_dp_WriteDataMReg_raw_internal[38];
assign ieu_dp_WriteDataMReg_internal[39] = ieu_dp_WriteDataMReg_raw_internal[39];
assign ieu_dp_WriteDataMReg_internal[40] = ieu_dp_WriteDataMReg_raw_internal[40];
assign ieu_dp_WriteDataMReg_internal[41] = ieu_dp_WriteDataMReg_raw_internal[41];
assign ieu_dp_WriteDataMReg_internal[42] = ieu_dp_WriteDataMReg_raw_internal[42];
assign ieu_dp_WriteDataMReg_internal[43] = ieu_dp_WriteDataMReg_raw_internal[43];
assign ieu_dp_WriteDataMReg_internal[44] = ieu_dp_WriteDataMReg_raw_internal[44];
assign ieu_dp_WriteDataMReg_internal[45] = ieu_dp_WriteDataMReg_raw_internal[45];
assign ieu_dp_WriteDataMReg_internal[46] = ieu_dp_WriteDataMReg_raw_internal[46];
assign ieu_dp_WriteDataMReg_internal[47] = ieu_dp_WriteDataMReg_raw_internal[47];
assign ieu_dp_WriteDataMReg_internal[48] = ieu_dp_WriteDataMReg_raw_internal[48];
assign ieu_dp_WriteDataMReg_internal[49] = ieu_dp_WriteDataMReg_raw_internal[49];
assign ieu_dp_WriteDataMReg_internal[50] = ieu_dp_WriteDataMReg_raw_internal[50];
assign ieu_dp_WriteDataMReg_internal[51] = ieu_dp_WriteDataMReg_raw_internal[51];
assign ieu_dp_WriteDataMReg_internal[52] = ieu_dp_WriteDataMReg_raw_internal[52];
assign ieu_dp_WriteDataMReg_internal[53] = ieu_dp_WriteDataMReg_raw_internal[53];
assign ieu_dp_WriteDataMReg_internal[54] = ieu_dp_WriteDataMReg_raw_internal[54];
assign ieu_dp_WriteDataMReg_internal[55] = ieu_dp_WriteDataMReg_raw_internal[55];
assign ieu_dp_WriteDataMReg_internal[56] = ieu_dp_WriteDataMReg_raw_internal[56];
assign ieu_dp_WriteDataMReg_internal[57] = ieu_dp_WriteDataMReg_raw_internal[57];
assign ieu_dp_WriteDataMReg_internal[58] = ieu_dp_WriteDataMReg_raw_internal[58];
assign ieu_dp_WriteDataMReg_internal[59] = ieu_dp_WriteDataMReg_raw_internal[59];
assign ieu_dp_WriteDataMReg_internal[60] = ieu_dp_WriteDataMReg_raw_internal[60];
assign ieu_dp_WriteDataMReg_internal[61] = ieu_dp_WriteDataMReg_raw_internal[61];
assign ieu_dp_WriteDataMReg_internal[62] = ieu_dp_WriteDataMReg_raw_internal[62];
assign ieu_dp_WriteDataMReg_internal[63] = ieu_dp_WriteDataMReg_raw_internal[63];
assign ieu_dp_WriteDataMReg_internal[64] = ieu_dp_WriteDataMReg_raw_internal[64];
assign ieu_dp_WriteDataMReg_internal[65] = ieu_dp_WriteDataMReg_raw_internal[65];
assign ieu_dp_WriteDataMReg_internal[66] = ieu_dp_WriteDataMReg_raw_internal[66];
assign ieu_dp_WriteDataMReg_internal[67] = ieu_dp_WriteDataMReg_raw_internal[67];
assign ieu_dp_WriteDataMReg_internal[68] = ieu_dp_WriteDataMReg_raw_internal[68];
assign ieu_dp_WriteDataMReg_internal[69] = ieu_dp_WriteDataMReg_raw_internal[69];
assign ieu_dp_WriteDataMReg_internal[70] = ieu_dp_WriteDataMReg_raw_internal[70];
assign ieu_dp_WriteDataMReg_internal[71] = ieu_dp_WriteDataMReg_raw_internal[71];

// ---- ieu_dp_WriteDataMReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ieu_dp_WriteDataMReg_pin_internal[0] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_0_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[1] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_1_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[2] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_2_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[3] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_3_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[4] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_4_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[5] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_5_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[6] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_6_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[7] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_7_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[8] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_8_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[9] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_9_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[10] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_10_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[11] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_11_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[12] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_12_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[13] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_13_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[14] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_14_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[15] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_15_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[16] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_16_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[17] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_17_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[18] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_18_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[19] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_19_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[20] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_20_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[21] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_21_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[22] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_22_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[23] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_23_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[24] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_24_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[25] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_25_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[26] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_26_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[27] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_27_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[28] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_28_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[29] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_29_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[30] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_30_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[31] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_31_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[32] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_32_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[33] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_33_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[34] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_34_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[35] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_35_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[36] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_36_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[37] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_37_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[38] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_38_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[39] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_39_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[40] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_40_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[41] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_41_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[42] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_42_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[43] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_43_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[44] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_44_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[45] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_45_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[46] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_46_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[47] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_47_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[48] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_48_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[49] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_49_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[50] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_50_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[51] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_51_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[52] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_52_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[53] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_53_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[54] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_54_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[55] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_55_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[56] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_56_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[57] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_57_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[58] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_58_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[59] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_59_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[60] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_60_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[61] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_61_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[62] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_62_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[63] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_63_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[64] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_64_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[65] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_65_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[66] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_66_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[67] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_67_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[68] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_68_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[69] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_69_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[70] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_70_.Q;
assign ieu_dp_WriteDataMReg_pin_internal[71] = dut.chip.soc_core_ieu_dp_WriteDataMReg_store.cw_stored_reg_71_.Q;

// ---- ieu_dp_WriteDataMReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ieu_dp_WriteDataMReg_raw_internal_available[0] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[1] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[2] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[3] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[4] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[5] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[6] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[7] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[8] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[9] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[10] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[11] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[12] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[13] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[14] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[15] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[16] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[17] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[18] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[19] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[20] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[21] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[22] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[23] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[24] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[25] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[26] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[27] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[28] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[29] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[30] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[31] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[32] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[33] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[34] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[35] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[36] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[37] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[38] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[39] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[40] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[41] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[42] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[43] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[44] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[45] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[46] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[47] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[48] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[49] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[50] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[51] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[52] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[53] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[54] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[55] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[56] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[57] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[58] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[59] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[60] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[61] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[62] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[63] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[64] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[65] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[66] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[67] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[68] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[69] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[70] = 1'b1;
assign ieu_dp_WriteDataMReg_raw_internal_available[71] = 1'b1;

// ============================================================================
// Register ifu_AlignedInstrRawDFlop: 32 mapped bits, width 32
// ============================================================================

// Bus declarations
wire [31:0] ifu_AlignedInstrRawDFlop_internal;
wire [31:0] ifu_AlignedInstrRawDFlop_raw_internal;
wire [31:0] ifu_AlignedInstrRawDFlop_pin_internal;
wire [31:0] ifu_AlignedInstrRawDFlop_raw_internal_available;

// ---- ifu_AlignedInstrRawDFlop_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ifu_AlignedInstrRawDFlop_raw_internal[0] = ~dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_0_.QN; // c3[28]
assign ifu_AlignedInstrRawDFlop_raw_internal[1] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_1_.Q; // c3[29]
assign ifu_AlignedInstrRawDFlop_raw_internal[2] = ~dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_2_.QN; // c3[30]
assign ifu_AlignedInstrRawDFlop_raw_internal[3] = ~dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_3_.QN; // c3[31]
assign ifu_AlignedInstrRawDFlop_raw_internal[4] = ~dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_4_.QN; // c3[32]
assign ifu_AlignedInstrRawDFlop_raw_internal[5] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_5_.Q; // c3[33]
assign ifu_AlignedInstrRawDFlop_raw_internal[6] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_6_.Q; // c3[34]
assign ifu_AlignedInstrRawDFlop_raw_internal[7] = ~dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_7_.QN; // c3[35]
assign ifu_AlignedInstrRawDFlop_raw_internal[8] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_8_.Q; // c3[36]
assign ifu_AlignedInstrRawDFlop_raw_internal[9] = ~dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_9_.QN; // c3[37]
assign ifu_AlignedInstrRawDFlop_raw_internal[10] = ~dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_10_.QN; // c3[38]
assign ifu_AlignedInstrRawDFlop_raw_internal[11] = ~dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_11_.QN; // c3[39]
assign ifu_AlignedInstrRawDFlop_raw_internal[12] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_12_.Q; // c3[40]
assign ifu_AlignedInstrRawDFlop_raw_internal[13] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_13_.Q; // c3[41]
assign ifu_AlignedInstrRawDFlop_raw_internal[14] = ~dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_14_.QN; // c3[42]
assign ifu_AlignedInstrRawDFlop_raw_internal[15] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_15_.Q; // c3[43]
assign ifu_AlignedInstrRawDFlop_raw_internal[16] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_16_.Q; // c3[44]
assign ifu_AlignedInstrRawDFlop_raw_internal[17] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_17_.Q; // c3[45]
assign ifu_AlignedInstrRawDFlop_raw_internal[18] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_18_.Q; // c3[46]
assign ifu_AlignedInstrRawDFlop_raw_internal[19] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_19_.Q; // c3[47]
assign ifu_AlignedInstrRawDFlop_raw_internal[20] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_20_.Q; // c3[48]
assign ifu_AlignedInstrRawDFlop_raw_internal[21] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_21_.Q; // c3[49]
assign ifu_AlignedInstrRawDFlop_raw_internal[22] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_22_.Q; // c3[50]
assign ifu_AlignedInstrRawDFlop_raw_internal[23] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_23_.Q; // c3[51]
assign ifu_AlignedInstrRawDFlop_raw_internal[24] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_24_.Q; // c3[52]
assign ifu_AlignedInstrRawDFlop_raw_internal[25] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_25_.Q; // c3[53]
assign ifu_AlignedInstrRawDFlop_raw_internal[26] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_26_.Q; // c3[54]
assign ifu_AlignedInstrRawDFlop_raw_internal[27] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_27_.Q; // c3[55]
assign ifu_AlignedInstrRawDFlop_raw_internal[28] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_28_.Q; // c3[56]
assign ifu_AlignedInstrRawDFlop_raw_internal[29] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_29_.Q; // c3[57]
assign ifu_AlignedInstrRawDFlop_raw_internal[30] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_30_.Q; // c3[58]
assign ifu_AlignedInstrRawDFlop_raw_internal[31] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_31_.Q; // c3[59]

// ---- ifu_AlignedInstrRawDFlop_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ifu_AlignedInstrRawDFlop_internal[0] = ifu_AlignedInstrRawDFlop_raw_internal[0];
assign ifu_AlignedInstrRawDFlop_internal[1] = ifu_AlignedInstrRawDFlop_raw_internal[1];
assign ifu_AlignedInstrRawDFlop_internal[2] = ifu_AlignedInstrRawDFlop_raw_internal[2];
assign ifu_AlignedInstrRawDFlop_internal[3] = ifu_AlignedInstrRawDFlop_raw_internal[3];
assign ifu_AlignedInstrRawDFlop_internal[4] = ifu_AlignedInstrRawDFlop_raw_internal[4];
assign ifu_AlignedInstrRawDFlop_internal[5] = ifu_AlignedInstrRawDFlop_raw_internal[5];
assign ifu_AlignedInstrRawDFlop_internal[6] = ifu_AlignedInstrRawDFlop_raw_internal[6];
assign ifu_AlignedInstrRawDFlop_internal[7] = ifu_AlignedInstrRawDFlop_raw_internal[7];
assign ifu_AlignedInstrRawDFlop_internal[8] = ifu_AlignedInstrRawDFlop_raw_internal[8];
assign ifu_AlignedInstrRawDFlop_internal[9] = ifu_AlignedInstrRawDFlop_raw_internal[9];
assign ifu_AlignedInstrRawDFlop_internal[10] = ifu_AlignedInstrRawDFlop_raw_internal[10];
assign ifu_AlignedInstrRawDFlop_internal[11] = ifu_AlignedInstrRawDFlop_raw_internal[11];
assign ifu_AlignedInstrRawDFlop_internal[12] = ifu_AlignedInstrRawDFlop_raw_internal[12];
assign ifu_AlignedInstrRawDFlop_internal[13] = ifu_AlignedInstrRawDFlop_raw_internal[13];
assign ifu_AlignedInstrRawDFlop_internal[14] = ifu_AlignedInstrRawDFlop_raw_internal[14];
assign ifu_AlignedInstrRawDFlop_internal[15] = ifu_AlignedInstrRawDFlop_raw_internal[15];
assign ifu_AlignedInstrRawDFlop_internal[16] = ifu_AlignedInstrRawDFlop_raw_internal[16];
assign ifu_AlignedInstrRawDFlop_internal[17] = ifu_AlignedInstrRawDFlop_raw_internal[17];
assign ifu_AlignedInstrRawDFlop_internal[18] = ifu_AlignedInstrRawDFlop_raw_internal[18];
assign ifu_AlignedInstrRawDFlop_internal[19] = ifu_AlignedInstrRawDFlop_raw_internal[19];
assign ifu_AlignedInstrRawDFlop_internal[20] = ifu_AlignedInstrRawDFlop_raw_internal[20];
assign ifu_AlignedInstrRawDFlop_internal[21] = ifu_AlignedInstrRawDFlop_raw_internal[21];
assign ifu_AlignedInstrRawDFlop_internal[22] = ifu_AlignedInstrRawDFlop_raw_internal[22];
assign ifu_AlignedInstrRawDFlop_internal[23] = ifu_AlignedInstrRawDFlop_raw_internal[23];
assign ifu_AlignedInstrRawDFlop_internal[24] = ifu_AlignedInstrRawDFlop_raw_internal[24];
assign ifu_AlignedInstrRawDFlop_internal[25] = ifu_AlignedInstrRawDFlop_raw_internal[25];
assign ifu_AlignedInstrRawDFlop_internal[26] = ifu_AlignedInstrRawDFlop_raw_internal[26];
assign ifu_AlignedInstrRawDFlop_internal[27] = ifu_AlignedInstrRawDFlop_raw_internal[27];
assign ifu_AlignedInstrRawDFlop_internal[28] = ifu_AlignedInstrRawDFlop_raw_internal[28];
assign ifu_AlignedInstrRawDFlop_internal[29] = ifu_AlignedInstrRawDFlop_raw_internal[29];
assign ifu_AlignedInstrRawDFlop_internal[30] = ifu_AlignedInstrRawDFlop_raw_internal[30];
assign ifu_AlignedInstrRawDFlop_internal[31] = ifu_AlignedInstrRawDFlop_raw_internal[31];

// ---- ifu_AlignedInstrRawDFlop_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ifu_AlignedInstrRawDFlop_pin_internal[0] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_0_.QN;
assign ifu_AlignedInstrRawDFlop_pin_internal[1] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_1_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[2] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_2_.QN;
assign ifu_AlignedInstrRawDFlop_pin_internal[3] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_3_.QN;
assign ifu_AlignedInstrRawDFlop_pin_internal[4] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_4_.QN;
assign ifu_AlignedInstrRawDFlop_pin_internal[5] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_5_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[6] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_6_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[7] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_7_.QN;
assign ifu_AlignedInstrRawDFlop_pin_internal[8] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_8_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[9] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_9_.QN;
assign ifu_AlignedInstrRawDFlop_pin_internal[10] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_10_.QN;
assign ifu_AlignedInstrRawDFlop_pin_internal[11] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_11_.QN;
assign ifu_AlignedInstrRawDFlop_pin_internal[12] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_12_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[13] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_13_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[14] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_14_.QN;
assign ifu_AlignedInstrRawDFlop_pin_internal[15] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_15_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[16] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_16_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[17] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_17_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[18] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_18_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[19] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_19_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[20] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_20_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[21] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_21_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[22] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_22_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[23] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_23_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[24] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_24_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[25] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_25_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[26] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_26_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[27] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_27_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[28] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_28_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[29] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_29_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[30] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_30_.Q;
assign ifu_AlignedInstrRawDFlop_pin_internal[31] = dut.chip.soc_core_ifu_AlignedInstrRawDFlop_q_reg_31_.Q;

// ---- ifu_AlignedInstrRawDFlop_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ifu_AlignedInstrRawDFlop_raw_internal_available[0] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[1] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[2] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[3] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[4] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[5] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[6] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[7] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[8] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[9] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[10] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[11] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[12] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[13] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[14] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[15] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[16] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[17] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[18] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[19] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[20] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[21] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[22] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[23] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[24] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[25] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[26] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[27] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[28] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[29] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[30] = 1'b1;
assign ifu_AlignedInstrRawDFlop_raw_internal_available[31] = 1'b1;

// ============================================================================
// Register ifu_InstrEReg: 32 mapped bits, width 32
// ============================================================================

// Bus declarations
wire [31:0] ifu_InstrEReg_internal;
wire [31:0] ifu_InstrEReg_raw_internal;
wire [31:0] ifu_InstrEReg_pin_internal;
wire [31:0] ifu_InstrEReg_raw_internal_available;

// ---- ifu_InstrEReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ifu_InstrEReg_raw_internal[0] = dut.chip.soc_core_ifu_InstrEReg_q_reg_0_.Q; // c3[60]
assign ifu_InstrEReg_raw_internal[1] = dut.chip.soc_core_ifu_InstrEReg_q_reg_1_.Q; // c3[61]
assign ifu_InstrEReg_raw_internal[2] = dut.chip.soc_core_ifu_InstrEReg_q_reg_2_.Q; // c3[62]
assign ifu_InstrEReg_raw_internal[3] = dut.chip.soc_core_ifu_InstrEReg_q_reg_3_.Q; // c3[63]
assign ifu_InstrEReg_raw_internal[4] = dut.chip.soc_core_ifu_InstrEReg_q_reg_4_.Q; // c3[64]
assign ifu_InstrEReg_raw_internal[5] = dut.chip.soc_core_ifu_InstrEReg_q_reg_5_.Q; // c3[65]
assign ifu_InstrEReg_raw_internal[6] = dut.chip.soc_core_ifu_InstrEReg_q_reg_6_.Q; // c3[66]
assign ifu_InstrEReg_raw_internal[7] = dut.chip.soc_core_ifu_InstrEReg_q_reg_7_.Q; // c3[67]
assign ifu_InstrEReg_raw_internal[8] = dut.chip.soc_core_ifu_InstrEReg_q_reg_8_.Q; // c3[68]
assign ifu_InstrEReg_raw_internal[9] = dut.chip.soc_core_ifu_InstrEReg_q_reg_9_.Q; // c3[69]
assign ifu_InstrEReg_raw_internal[10] = dut.chip.soc_core_ifu_InstrEReg_q_reg_10_.Q; // c3[70]
assign ifu_InstrEReg_raw_internal[11] = dut.chip.soc_core_ifu_InstrEReg_q_reg_11_.Q; // c3[71]
assign ifu_InstrEReg_raw_internal[12] = dut.chip.soc_core_ifu_InstrEReg_q_reg_12_.Q; // c3[72]
assign ifu_InstrEReg_raw_internal[13] = dut.chip.soc_core_ifu_InstrEReg_q_reg_13_.Q; // c3[73]
assign ifu_InstrEReg_raw_internal[14] = dut.chip.soc_core_ifu_InstrEReg_q_reg_14_.Q; // c3[74]
assign ifu_InstrEReg_raw_internal[15] = dut.chip.soc_core_ifu_InstrEReg_q_reg_15_.Q; // c3[75]
assign ifu_InstrEReg_raw_internal[16] = dut.chip.soc_core_ifu_InstrEReg_q_reg_16_.Q; // c3[76]
assign ifu_InstrEReg_raw_internal[17] = dut.chip.soc_core_ifu_InstrEReg_q_reg_17_.Q; // c3[77]
assign ifu_InstrEReg_raw_internal[18] = dut.chip.soc_core_ifu_InstrEReg_q_reg_18_.Q; // c3[78]
assign ifu_InstrEReg_raw_internal[19] = dut.chip.soc_core_ifu_InstrEReg_q_reg_19_.Q; // c3[79]
assign ifu_InstrEReg_raw_internal[20] = dut.chip.soc_core_ifu_InstrEReg_q_reg_20_.Q; // c3[80]
assign ifu_InstrEReg_raw_internal[21] = dut.chip.soc_core_ifu_InstrEReg_q_reg_21_.Q; // c3[81]
assign ifu_InstrEReg_raw_internal[22] = dut.chip.soc_core_ifu_InstrEReg_q_reg_22_.Q; // c3[82]
assign ifu_InstrEReg_raw_internal[23] = dut.chip.soc_core_ifu_InstrEReg_q_reg_23_.Q; // c3[83]
assign ifu_InstrEReg_raw_internal[24] = dut.chip.soc_core_ifu_InstrEReg_q_reg_24_.Q; // c3[84]
assign ifu_InstrEReg_raw_internal[25] = dut.chip.soc_core_ifu_InstrEReg_q_reg_25_.Q; // c3[85]
assign ifu_InstrEReg_raw_internal[26] = dut.chip.soc_core_ifu_InstrEReg_q_reg_26_.Q; // c3[86]
assign ifu_InstrEReg_raw_internal[27] = dut.chip.soc_core_ifu_InstrEReg_q_reg_27_.Q; // c3[87]
assign ifu_InstrEReg_raw_internal[28] = dut.chip.soc_core_ifu_InstrEReg_q_reg_28_.Q; // c3[88]
assign ifu_InstrEReg_raw_internal[29] = dut.chip.soc_core_ifu_InstrEReg_q_reg_29_.Q; // c3[89]
assign ifu_InstrEReg_raw_internal[30] = dut.chip.soc_core_ifu_InstrEReg_q_reg_30_.Q; // c3[90]
assign ifu_InstrEReg_raw_internal[31] = dut.chip.soc_core_ifu_InstrEReg_q_reg_31_.Q; // c3[91]

// ---- ifu_InstrEReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ifu_InstrEReg_internal[0] = ifu_InstrEReg_raw_internal[0];
assign ifu_InstrEReg_internal[1] = ifu_InstrEReg_raw_internal[1];
assign ifu_InstrEReg_internal[2] = ifu_InstrEReg_raw_internal[2];
assign ifu_InstrEReg_internal[3] = ifu_InstrEReg_raw_internal[3];
assign ifu_InstrEReg_internal[4] = ifu_InstrEReg_raw_internal[4];
assign ifu_InstrEReg_internal[5] = ifu_InstrEReg_raw_internal[5];
assign ifu_InstrEReg_internal[6] = ifu_InstrEReg_raw_internal[6];
assign ifu_InstrEReg_internal[7] = ifu_InstrEReg_raw_internal[7];
assign ifu_InstrEReg_internal[8] = ifu_InstrEReg_raw_internal[8];
assign ifu_InstrEReg_internal[9] = ifu_InstrEReg_raw_internal[9];
assign ifu_InstrEReg_internal[10] = ifu_InstrEReg_raw_internal[10];
assign ifu_InstrEReg_internal[11] = ifu_InstrEReg_raw_internal[11];
assign ifu_InstrEReg_internal[12] = ifu_InstrEReg_raw_internal[12];
assign ifu_InstrEReg_internal[13] = ifu_InstrEReg_raw_internal[13];
assign ifu_InstrEReg_internal[14] = ifu_InstrEReg_raw_internal[14];
assign ifu_InstrEReg_internal[15] = ifu_InstrEReg_raw_internal[15];
assign ifu_InstrEReg_internal[16] = ifu_InstrEReg_raw_internal[16];
assign ifu_InstrEReg_internal[17] = ifu_InstrEReg_raw_internal[17];
assign ifu_InstrEReg_internal[18] = ifu_InstrEReg_raw_internal[18];
assign ifu_InstrEReg_internal[19] = ifu_InstrEReg_raw_internal[19];
assign ifu_InstrEReg_internal[20] = ifu_InstrEReg_raw_internal[20];
assign ifu_InstrEReg_internal[21] = ifu_InstrEReg_raw_internal[21];
assign ifu_InstrEReg_internal[22] = ifu_InstrEReg_raw_internal[22];
assign ifu_InstrEReg_internal[23] = ifu_InstrEReg_raw_internal[23];
assign ifu_InstrEReg_internal[24] = ifu_InstrEReg_raw_internal[24];
assign ifu_InstrEReg_internal[25] = ifu_InstrEReg_raw_internal[25];
assign ifu_InstrEReg_internal[26] = ifu_InstrEReg_raw_internal[26];
assign ifu_InstrEReg_internal[27] = ifu_InstrEReg_raw_internal[27];
assign ifu_InstrEReg_internal[28] = ifu_InstrEReg_raw_internal[28];
assign ifu_InstrEReg_internal[29] = ifu_InstrEReg_raw_internal[29];
assign ifu_InstrEReg_internal[30] = ifu_InstrEReg_raw_internal[30];
assign ifu_InstrEReg_internal[31] = ifu_InstrEReg_raw_internal[31];

// ---- ifu_InstrEReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ifu_InstrEReg_pin_internal[0] = dut.chip.soc_core_ifu_InstrEReg_q_reg_0_.Q;
assign ifu_InstrEReg_pin_internal[1] = dut.chip.soc_core_ifu_InstrEReg_q_reg_1_.Q;
assign ifu_InstrEReg_pin_internal[2] = dut.chip.soc_core_ifu_InstrEReg_q_reg_2_.Q;
assign ifu_InstrEReg_pin_internal[3] = dut.chip.soc_core_ifu_InstrEReg_q_reg_3_.Q;
assign ifu_InstrEReg_pin_internal[4] = dut.chip.soc_core_ifu_InstrEReg_q_reg_4_.Q;
assign ifu_InstrEReg_pin_internal[5] = dut.chip.soc_core_ifu_InstrEReg_q_reg_5_.Q;
assign ifu_InstrEReg_pin_internal[6] = dut.chip.soc_core_ifu_InstrEReg_q_reg_6_.Q;
assign ifu_InstrEReg_pin_internal[7] = dut.chip.soc_core_ifu_InstrEReg_q_reg_7_.Q;
assign ifu_InstrEReg_pin_internal[8] = dut.chip.soc_core_ifu_InstrEReg_q_reg_8_.Q;
assign ifu_InstrEReg_pin_internal[9] = dut.chip.soc_core_ifu_InstrEReg_q_reg_9_.Q;
assign ifu_InstrEReg_pin_internal[10] = dut.chip.soc_core_ifu_InstrEReg_q_reg_10_.Q;
assign ifu_InstrEReg_pin_internal[11] = dut.chip.soc_core_ifu_InstrEReg_q_reg_11_.Q;
assign ifu_InstrEReg_pin_internal[12] = dut.chip.soc_core_ifu_InstrEReg_q_reg_12_.Q;
assign ifu_InstrEReg_pin_internal[13] = dut.chip.soc_core_ifu_InstrEReg_q_reg_13_.Q;
assign ifu_InstrEReg_pin_internal[14] = dut.chip.soc_core_ifu_InstrEReg_q_reg_14_.Q;
assign ifu_InstrEReg_pin_internal[15] = dut.chip.soc_core_ifu_InstrEReg_q_reg_15_.Q;
assign ifu_InstrEReg_pin_internal[16] = dut.chip.soc_core_ifu_InstrEReg_q_reg_16_.Q;
assign ifu_InstrEReg_pin_internal[17] = dut.chip.soc_core_ifu_InstrEReg_q_reg_17_.Q;
assign ifu_InstrEReg_pin_internal[18] = dut.chip.soc_core_ifu_InstrEReg_q_reg_18_.Q;
assign ifu_InstrEReg_pin_internal[19] = dut.chip.soc_core_ifu_InstrEReg_q_reg_19_.Q;
assign ifu_InstrEReg_pin_internal[20] = dut.chip.soc_core_ifu_InstrEReg_q_reg_20_.Q;
assign ifu_InstrEReg_pin_internal[21] = dut.chip.soc_core_ifu_InstrEReg_q_reg_21_.Q;
assign ifu_InstrEReg_pin_internal[22] = dut.chip.soc_core_ifu_InstrEReg_q_reg_22_.Q;
assign ifu_InstrEReg_pin_internal[23] = dut.chip.soc_core_ifu_InstrEReg_q_reg_23_.Q;
assign ifu_InstrEReg_pin_internal[24] = dut.chip.soc_core_ifu_InstrEReg_q_reg_24_.Q;
assign ifu_InstrEReg_pin_internal[25] = dut.chip.soc_core_ifu_InstrEReg_q_reg_25_.Q;
assign ifu_InstrEReg_pin_internal[26] = dut.chip.soc_core_ifu_InstrEReg_q_reg_26_.Q;
assign ifu_InstrEReg_pin_internal[27] = dut.chip.soc_core_ifu_InstrEReg_q_reg_27_.Q;
assign ifu_InstrEReg_pin_internal[28] = dut.chip.soc_core_ifu_InstrEReg_q_reg_28_.Q;
assign ifu_InstrEReg_pin_internal[29] = dut.chip.soc_core_ifu_InstrEReg_q_reg_29_.Q;
assign ifu_InstrEReg_pin_internal[30] = dut.chip.soc_core_ifu_InstrEReg_q_reg_30_.Q;
assign ifu_InstrEReg_pin_internal[31] = dut.chip.soc_core_ifu_InstrEReg_q_reg_31_.Q;

// ---- ifu_InstrEReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ifu_InstrEReg_raw_internal_available[0] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[1] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[2] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[3] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[4] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[5] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[6] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[7] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[8] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[9] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[10] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[11] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[12] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[13] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[14] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[15] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[16] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[17] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[18] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[19] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[20] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[21] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[22] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[23] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[24] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[25] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[26] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[27] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[28] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[29] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[30] = 1'b1;
assign ifu_InstrEReg_raw_internal_available[31] = 1'b1;

// ============================================================================
// Register ifu_PCDReg: 63 mapped bits, width 64
// ============================================================================

// Bus declarations
wire [63:0] ifu_PCDReg_internal;
wire [63:0] ifu_PCDReg_raw_internal;
wire [63:0] ifu_PCDReg_pin_internal;
wire [63:0] ifu_PCDReg_raw_internal_available;

// ---- ifu_PCDReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ifu_PCDReg_raw_internal[0] = 1'bz; // unavailable physical Q
assign ifu_PCDReg_raw_internal[1] = dut.chip.soc_core_ifu_PCDReg_q_reg_1_.Q; // c3[92]
assign ifu_PCDReg_raw_internal[2] = dut.chip.soc_core_ifu_PCDReg_q_reg_2_.Q; // c3[93]
assign ifu_PCDReg_raw_internal[3] = dut.chip.soc_core_ifu_PCDReg_q_reg_3_.Q; // c3[94]
assign ifu_PCDReg_raw_internal[4] = dut.chip.soc_core_ifu_PCDReg_q_reg_4_.Q; // c3[95]
assign ifu_PCDReg_raw_internal[5] = dut.chip.soc_core_ifu_PCDReg_q_reg_5_.Q; // c3[96]
assign ifu_PCDReg_raw_internal[6] = dut.chip.soc_core_ifu_PCDReg_q_reg_6_.Q; // c3[97]
assign ifu_PCDReg_raw_internal[7] = dut.chip.soc_core_ifu_PCDReg_q_reg_7_.Q; // c3[98]
assign ifu_PCDReg_raw_internal[8] = dut.chip.soc_core_ifu_PCDReg_q_reg_8_.Q; // c3[99]
assign ifu_PCDReg_raw_internal[9] = dut.chip.soc_core_ifu_PCDReg_q_reg_9_.Q; // c3[100]
assign ifu_PCDReg_raw_internal[10] = dut.chip.soc_core_ifu_PCDReg_q_reg_10_.Q; // c3[101]
assign ifu_PCDReg_raw_internal[11] = dut.chip.soc_core_ifu_PCDReg_q_reg_11_.Q; // c3[102]
assign ifu_PCDReg_raw_internal[12] = dut.chip.soc_core_ifu_PCDReg_q_reg_12_.Q; // c3[103]
assign ifu_PCDReg_raw_internal[13] = dut.chip.soc_core_ifu_PCDReg_q_reg_13_.Q; // c3[104]
assign ifu_PCDReg_raw_internal[14] = dut.chip.soc_core_ifu_PCDReg_q_reg_14_.Q; // c3[105]
assign ifu_PCDReg_raw_internal[15] = dut.chip.soc_core_ifu_PCDReg_q_reg_15_.Q; // c3[106]
assign ifu_PCDReg_raw_internal[16] = dut.chip.soc_core_ifu_PCDReg_q_reg_16_.Q; // c3[107]
assign ifu_PCDReg_raw_internal[17] = dut.chip.soc_core_ifu_PCDReg_q_reg_17_.Q; // c3[108]
assign ifu_PCDReg_raw_internal[18] = dut.chip.soc_core_ifu_PCDReg_q_reg_18_.Q; // c3[109]
assign ifu_PCDReg_raw_internal[19] = dut.chip.soc_core_ifu_PCDReg_q_reg_19_.Q; // c3[110]
assign ifu_PCDReg_raw_internal[20] = dut.chip.soc_core_ifu_PCDReg_q_reg_20_.Q; // c3[111]
assign ifu_PCDReg_raw_internal[21] = dut.chip.soc_core_ifu_PCDReg_q_reg_21_.Q; // c3[112]
assign ifu_PCDReg_raw_internal[22] = dut.chip.soc_core_ifu_PCDReg_q_reg_22_.Q; // c3[113]
assign ifu_PCDReg_raw_internal[23] = dut.chip.soc_core_ifu_PCDReg_q_reg_23_.Q; // c3[114]
assign ifu_PCDReg_raw_internal[24] = dut.chip.soc_core_ifu_PCDReg_q_reg_24_.Q; // c3[115]
assign ifu_PCDReg_raw_internal[25] = dut.chip.soc_core_ifu_PCDReg_q_reg_25_.Q; // c3[116]
assign ifu_PCDReg_raw_internal[26] = dut.chip.soc_core_ifu_PCDReg_q_reg_26_.Q; // c3[117]
assign ifu_PCDReg_raw_internal[27] = dut.chip.soc_core_ifu_PCDReg_q_reg_27_.Q; // c3[118]
assign ifu_PCDReg_raw_internal[28] = dut.chip.soc_core_ifu_PCDReg_q_reg_28_.Q; // c3[119]
assign ifu_PCDReg_raw_internal[29] = dut.chip.soc_core_ifu_PCDReg_q_reg_29_.Q; // c3[120]
assign ifu_PCDReg_raw_internal[30] = dut.chip.soc_core_ifu_PCDReg_q_reg_30_.Q; // c3[121]
assign ifu_PCDReg_raw_internal[31] = dut.chip.soc_core_ifu_PCDReg_q_reg_31_.Q; // c3[122]
assign ifu_PCDReg_raw_internal[32] = dut.chip.soc_core_ifu_PCDReg_q_reg_32_.Q; // c3[123]
assign ifu_PCDReg_raw_internal[33] = dut.chip.soc_core_ifu_PCDReg_q_reg_33_.Q; // c3[124]
assign ifu_PCDReg_raw_internal[34] = dut.chip.soc_core_ifu_PCDReg_q_reg_34_.Q; // c3[125]
assign ifu_PCDReg_raw_internal[35] = dut.chip.soc_core_ifu_PCDReg_q_reg_35_.Q; // c3[126]
assign ifu_PCDReg_raw_internal[36] = dut.chip.soc_core_ifu_PCDReg_q_reg_36_.Q; // c3[127]
assign ifu_PCDReg_raw_internal[37] = dut.chip.soc_core_ifu_PCDReg_q_reg_37_.Q; // c3[128]
assign ifu_PCDReg_raw_internal[38] = dut.chip.soc_core_ifu_PCDReg_q_reg_38_.Q; // c3[129]
assign ifu_PCDReg_raw_internal[39] = dut.chip.soc_core_ifu_PCDReg_q_reg_39_.Q; // c3[130]
assign ifu_PCDReg_raw_internal[40] = dut.chip.soc_core_ifu_PCDReg_q_reg_40_.Q; // c3[131]
assign ifu_PCDReg_raw_internal[41] = dut.chip.soc_core_ifu_PCDReg_q_reg_41_.Q; // c3[132]
assign ifu_PCDReg_raw_internal[42] = dut.chip.soc_core_ifu_PCDReg_q_reg_42_.Q; // c3[133]
assign ifu_PCDReg_raw_internal[43] = dut.chip.soc_core_ifu_PCDReg_q_reg_43_.Q; // c3[134]
assign ifu_PCDReg_raw_internal[44] = dut.chip.soc_core_ifu_PCDReg_q_reg_44_.Q; // c3[135]
assign ifu_PCDReg_raw_internal[45] = dut.chip.soc_core_ifu_PCDReg_q_reg_45_.Q; // c3[136]
assign ifu_PCDReg_raw_internal[46] = dut.chip.soc_core_ifu_PCDReg_q_reg_46_.Q; // c3[137]
assign ifu_PCDReg_raw_internal[47] = dut.chip.soc_core_ifu_PCDReg_q_reg_47_.Q; // c3[138]
assign ifu_PCDReg_raw_internal[48] = dut.chip.soc_core_ifu_PCDReg_q_reg_48_.Q; // c3[139]
assign ifu_PCDReg_raw_internal[49] = dut.chip.soc_core_ifu_PCDReg_q_reg_49_.Q; // c3[140]
assign ifu_PCDReg_raw_internal[50] = dut.chip.soc_core_ifu_PCDReg_q_reg_50_.Q; // c3[141]
assign ifu_PCDReg_raw_internal[51] = dut.chip.soc_core_ifu_PCDReg_q_reg_51_.Q; // c3[142]
assign ifu_PCDReg_raw_internal[52] = dut.chip.soc_core_ifu_PCDReg_q_reg_52_.Q; // c3[143]
assign ifu_PCDReg_raw_internal[53] = dut.chip.soc_core_ifu_PCDReg_q_reg_53_.Q; // c3[144]
assign ifu_PCDReg_raw_internal[54] = dut.chip.soc_core_ifu_PCDReg_q_reg_54_.Q; // c3[145]
assign ifu_PCDReg_raw_internal[55] = dut.chip.soc_core_ifu_PCDReg_q_reg_55_.Q; // c3[146]
assign ifu_PCDReg_raw_internal[56] = dut.chip.soc_core_ifu_PCDReg_q_reg_56_.Q; // c3[147]
assign ifu_PCDReg_raw_internal[57] = dut.chip.soc_core_ifu_PCDReg_q_reg_57_.Q; // c3[148]
assign ifu_PCDReg_raw_internal[58] = dut.chip.soc_core_ifu_PCDReg_q_reg_58_.Q; // c3[149]
assign ifu_PCDReg_raw_internal[59] = dut.chip.soc_core_ifu_PCDReg_q_reg_59_.Q; // c3[150]
assign ifu_PCDReg_raw_internal[60] = dut.chip.soc_core_ifu_PCDReg_q_reg_60_.Q; // c3[151]
assign ifu_PCDReg_raw_internal[61] = dut.chip.soc_core_ifu_PCDReg_q_reg_61_.Q; // c3[152]
assign ifu_PCDReg_raw_internal[62] = dut.chip.soc_core_ifu_PCDReg_q_reg_62_.Q; // c3[153]
assign ifu_PCDReg_raw_internal[63] = dut.chip.soc_core_ifu_PCDReg_q_reg_63_.Q; // c3[154]

// ---- ifu_PCDReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ifu_PCDReg_internal[0] = 1'bz; // unavailable logical estimate
assign ifu_PCDReg_internal[1] = ifu_PCDReg_raw_internal[1];
assign ifu_PCDReg_internal[2] = ifu_PCDReg_raw_internal[2];
assign ifu_PCDReg_internal[3] = ifu_PCDReg_raw_internal[3];
assign ifu_PCDReg_internal[4] = ifu_PCDReg_raw_internal[4];
assign ifu_PCDReg_internal[5] = ifu_PCDReg_raw_internal[5];
assign ifu_PCDReg_internal[6] = ifu_PCDReg_raw_internal[6];
assign ifu_PCDReg_internal[7] = ifu_PCDReg_raw_internal[7];
assign ifu_PCDReg_internal[8] = ifu_PCDReg_raw_internal[8];
assign ifu_PCDReg_internal[9] = ifu_PCDReg_raw_internal[9];
assign ifu_PCDReg_internal[10] = ifu_PCDReg_raw_internal[10];
assign ifu_PCDReg_internal[11] = ifu_PCDReg_raw_internal[11];
assign ifu_PCDReg_internal[12] = ifu_PCDReg_raw_internal[12];
assign ifu_PCDReg_internal[13] = ifu_PCDReg_raw_internal[13];
assign ifu_PCDReg_internal[14] = ifu_PCDReg_raw_internal[14];
assign ifu_PCDReg_internal[15] = ifu_PCDReg_raw_internal[15];
assign ifu_PCDReg_internal[16] = ifu_PCDReg_raw_internal[16];
assign ifu_PCDReg_internal[17] = ifu_PCDReg_raw_internal[17];
assign ifu_PCDReg_internal[18] = ifu_PCDReg_raw_internal[18];
assign ifu_PCDReg_internal[19] = ifu_PCDReg_raw_internal[19];
assign ifu_PCDReg_internal[20] = ifu_PCDReg_raw_internal[20];
assign ifu_PCDReg_internal[21] = ifu_PCDReg_raw_internal[21];
assign ifu_PCDReg_internal[22] = ifu_PCDReg_raw_internal[22];
assign ifu_PCDReg_internal[23] = ifu_PCDReg_raw_internal[23];
assign ifu_PCDReg_internal[24] = ifu_PCDReg_raw_internal[24];
assign ifu_PCDReg_internal[25] = ifu_PCDReg_raw_internal[25];
assign ifu_PCDReg_internal[26] = ifu_PCDReg_raw_internal[26];
assign ifu_PCDReg_internal[27] = ifu_PCDReg_raw_internal[27];
assign ifu_PCDReg_internal[28] = ifu_PCDReg_raw_internal[28];
assign ifu_PCDReg_internal[29] = ifu_PCDReg_raw_internal[29];
assign ifu_PCDReg_internal[30] = ifu_PCDReg_raw_internal[30];
assign ifu_PCDReg_internal[31] = ifu_PCDReg_raw_internal[31];
assign ifu_PCDReg_internal[32] = ifu_PCDReg_raw_internal[32];
assign ifu_PCDReg_internal[33] = ifu_PCDReg_raw_internal[33];
assign ifu_PCDReg_internal[34] = ifu_PCDReg_raw_internal[34];
assign ifu_PCDReg_internal[35] = ifu_PCDReg_raw_internal[35];
assign ifu_PCDReg_internal[36] = ifu_PCDReg_raw_internal[36];
assign ifu_PCDReg_internal[37] = ifu_PCDReg_raw_internal[37];
assign ifu_PCDReg_internal[38] = ifu_PCDReg_raw_internal[38];
assign ifu_PCDReg_internal[39] = ifu_PCDReg_raw_internal[39];
assign ifu_PCDReg_internal[40] = ifu_PCDReg_raw_internal[40];
assign ifu_PCDReg_internal[41] = ifu_PCDReg_raw_internal[41];
assign ifu_PCDReg_internal[42] = ifu_PCDReg_raw_internal[42];
assign ifu_PCDReg_internal[43] = ifu_PCDReg_raw_internal[43];
assign ifu_PCDReg_internal[44] = ifu_PCDReg_raw_internal[44];
assign ifu_PCDReg_internal[45] = ifu_PCDReg_raw_internal[45];
assign ifu_PCDReg_internal[46] = ifu_PCDReg_raw_internal[46];
assign ifu_PCDReg_internal[47] = ifu_PCDReg_raw_internal[47];
assign ifu_PCDReg_internal[48] = ifu_PCDReg_raw_internal[48];
assign ifu_PCDReg_internal[49] = ifu_PCDReg_raw_internal[49];
assign ifu_PCDReg_internal[50] = ifu_PCDReg_raw_internal[50];
assign ifu_PCDReg_internal[51] = ifu_PCDReg_raw_internal[51];
assign ifu_PCDReg_internal[52] = ifu_PCDReg_raw_internal[52];
assign ifu_PCDReg_internal[53] = ifu_PCDReg_raw_internal[53];
assign ifu_PCDReg_internal[54] = ifu_PCDReg_raw_internal[54];
assign ifu_PCDReg_internal[55] = ifu_PCDReg_raw_internal[55];
assign ifu_PCDReg_internal[56] = ifu_PCDReg_raw_internal[56];
assign ifu_PCDReg_internal[57] = ifu_PCDReg_raw_internal[57];
assign ifu_PCDReg_internal[58] = ifu_PCDReg_raw_internal[58];
assign ifu_PCDReg_internal[59] = ifu_PCDReg_raw_internal[59];
assign ifu_PCDReg_internal[60] = ifu_PCDReg_raw_internal[60];
assign ifu_PCDReg_internal[61] = ifu_PCDReg_raw_internal[61];
assign ifu_PCDReg_internal[62] = ifu_PCDReg_raw_internal[62];
assign ifu_PCDReg_internal[63] = ifu_PCDReg_raw_internal[63];

// ---- ifu_PCDReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ifu_PCDReg_pin_internal[0] = 1'bz; // unavailable scan pin
assign ifu_PCDReg_pin_internal[1] = dut.chip.soc_core_ifu_PCDReg_q_reg_1_.Q;
assign ifu_PCDReg_pin_internal[2] = dut.chip.soc_core_ifu_PCDReg_q_reg_2_.Q;
assign ifu_PCDReg_pin_internal[3] = dut.chip.soc_core_ifu_PCDReg_q_reg_3_.Q;
assign ifu_PCDReg_pin_internal[4] = dut.chip.soc_core_ifu_PCDReg_q_reg_4_.Q;
assign ifu_PCDReg_pin_internal[5] = dut.chip.soc_core_ifu_PCDReg_q_reg_5_.Q;
assign ifu_PCDReg_pin_internal[6] = dut.chip.soc_core_ifu_PCDReg_q_reg_6_.Q;
assign ifu_PCDReg_pin_internal[7] = dut.chip.soc_core_ifu_PCDReg_q_reg_7_.Q;
assign ifu_PCDReg_pin_internal[8] = dut.chip.soc_core_ifu_PCDReg_q_reg_8_.Q;
assign ifu_PCDReg_pin_internal[9] = dut.chip.soc_core_ifu_PCDReg_q_reg_9_.Q;
assign ifu_PCDReg_pin_internal[10] = dut.chip.soc_core_ifu_PCDReg_q_reg_10_.Q;
assign ifu_PCDReg_pin_internal[11] = dut.chip.soc_core_ifu_PCDReg_q_reg_11_.Q;
assign ifu_PCDReg_pin_internal[12] = dut.chip.soc_core_ifu_PCDReg_q_reg_12_.Q;
assign ifu_PCDReg_pin_internal[13] = dut.chip.soc_core_ifu_PCDReg_q_reg_13_.Q;
assign ifu_PCDReg_pin_internal[14] = dut.chip.soc_core_ifu_PCDReg_q_reg_14_.Q;
assign ifu_PCDReg_pin_internal[15] = dut.chip.soc_core_ifu_PCDReg_q_reg_15_.Q;
assign ifu_PCDReg_pin_internal[16] = dut.chip.soc_core_ifu_PCDReg_q_reg_16_.Q;
assign ifu_PCDReg_pin_internal[17] = dut.chip.soc_core_ifu_PCDReg_q_reg_17_.Q;
assign ifu_PCDReg_pin_internal[18] = dut.chip.soc_core_ifu_PCDReg_q_reg_18_.Q;
assign ifu_PCDReg_pin_internal[19] = dut.chip.soc_core_ifu_PCDReg_q_reg_19_.Q;
assign ifu_PCDReg_pin_internal[20] = dut.chip.soc_core_ifu_PCDReg_q_reg_20_.Q;
assign ifu_PCDReg_pin_internal[21] = dut.chip.soc_core_ifu_PCDReg_q_reg_21_.Q;
assign ifu_PCDReg_pin_internal[22] = dut.chip.soc_core_ifu_PCDReg_q_reg_22_.Q;
assign ifu_PCDReg_pin_internal[23] = dut.chip.soc_core_ifu_PCDReg_q_reg_23_.Q;
assign ifu_PCDReg_pin_internal[24] = dut.chip.soc_core_ifu_PCDReg_q_reg_24_.Q;
assign ifu_PCDReg_pin_internal[25] = dut.chip.soc_core_ifu_PCDReg_q_reg_25_.Q;
assign ifu_PCDReg_pin_internal[26] = dut.chip.soc_core_ifu_PCDReg_q_reg_26_.Q;
assign ifu_PCDReg_pin_internal[27] = dut.chip.soc_core_ifu_PCDReg_q_reg_27_.Q;
assign ifu_PCDReg_pin_internal[28] = dut.chip.soc_core_ifu_PCDReg_q_reg_28_.Q;
assign ifu_PCDReg_pin_internal[29] = dut.chip.soc_core_ifu_PCDReg_q_reg_29_.Q;
assign ifu_PCDReg_pin_internal[30] = dut.chip.soc_core_ifu_PCDReg_q_reg_30_.Q;
assign ifu_PCDReg_pin_internal[31] = dut.chip.soc_core_ifu_PCDReg_q_reg_31_.Q;
assign ifu_PCDReg_pin_internal[32] = dut.chip.soc_core_ifu_PCDReg_q_reg_32_.Q;
assign ifu_PCDReg_pin_internal[33] = dut.chip.soc_core_ifu_PCDReg_q_reg_33_.Q;
assign ifu_PCDReg_pin_internal[34] = dut.chip.soc_core_ifu_PCDReg_q_reg_34_.Q;
assign ifu_PCDReg_pin_internal[35] = dut.chip.soc_core_ifu_PCDReg_q_reg_35_.Q;
assign ifu_PCDReg_pin_internal[36] = dut.chip.soc_core_ifu_PCDReg_q_reg_36_.Q;
assign ifu_PCDReg_pin_internal[37] = dut.chip.soc_core_ifu_PCDReg_q_reg_37_.Q;
assign ifu_PCDReg_pin_internal[38] = dut.chip.soc_core_ifu_PCDReg_q_reg_38_.Q;
assign ifu_PCDReg_pin_internal[39] = dut.chip.soc_core_ifu_PCDReg_q_reg_39_.Q;
assign ifu_PCDReg_pin_internal[40] = dut.chip.soc_core_ifu_PCDReg_q_reg_40_.Q;
assign ifu_PCDReg_pin_internal[41] = dut.chip.soc_core_ifu_PCDReg_q_reg_41_.Q;
assign ifu_PCDReg_pin_internal[42] = dut.chip.soc_core_ifu_PCDReg_q_reg_42_.Q;
assign ifu_PCDReg_pin_internal[43] = dut.chip.soc_core_ifu_PCDReg_q_reg_43_.Q;
assign ifu_PCDReg_pin_internal[44] = dut.chip.soc_core_ifu_PCDReg_q_reg_44_.Q;
assign ifu_PCDReg_pin_internal[45] = dut.chip.soc_core_ifu_PCDReg_q_reg_45_.Q;
assign ifu_PCDReg_pin_internal[46] = dut.chip.soc_core_ifu_PCDReg_q_reg_46_.Q;
assign ifu_PCDReg_pin_internal[47] = dut.chip.soc_core_ifu_PCDReg_q_reg_47_.Q;
assign ifu_PCDReg_pin_internal[48] = dut.chip.soc_core_ifu_PCDReg_q_reg_48_.Q;
assign ifu_PCDReg_pin_internal[49] = dut.chip.soc_core_ifu_PCDReg_q_reg_49_.Q;
assign ifu_PCDReg_pin_internal[50] = dut.chip.soc_core_ifu_PCDReg_q_reg_50_.Q;
assign ifu_PCDReg_pin_internal[51] = dut.chip.soc_core_ifu_PCDReg_q_reg_51_.Q;
assign ifu_PCDReg_pin_internal[52] = dut.chip.soc_core_ifu_PCDReg_q_reg_52_.Q;
assign ifu_PCDReg_pin_internal[53] = dut.chip.soc_core_ifu_PCDReg_q_reg_53_.Q;
assign ifu_PCDReg_pin_internal[54] = dut.chip.soc_core_ifu_PCDReg_q_reg_54_.Q;
assign ifu_PCDReg_pin_internal[55] = dut.chip.soc_core_ifu_PCDReg_q_reg_55_.Q;
assign ifu_PCDReg_pin_internal[56] = dut.chip.soc_core_ifu_PCDReg_q_reg_56_.Q;
assign ifu_PCDReg_pin_internal[57] = dut.chip.soc_core_ifu_PCDReg_q_reg_57_.Q;
assign ifu_PCDReg_pin_internal[58] = dut.chip.soc_core_ifu_PCDReg_q_reg_58_.Q;
assign ifu_PCDReg_pin_internal[59] = dut.chip.soc_core_ifu_PCDReg_q_reg_59_.Q;
assign ifu_PCDReg_pin_internal[60] = dut.chip.soc_core_ifu_PCDReg_q_reg_60_.Q;
assign ifu_PCDReg_pin_internal[61] = dut.chip.soc_core_ifu_PCDReg_q_reg_61_.Q;
assign ifu_PCDReg_pin_internal[62] = dut.chip.soc_core_ifu_PCDReg_q_reg_62_.Q;
assign ifu_PCDReg_pin_internal[63] = dut.chip.soc_core_ifu_PCDReg_q_reg_63_.Q;

// ---- ifu_PCDReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ifu_PCDReg_raw_internal_available[0] = 1'b0;
assign ifu_PCDReg_raw_internal_available[1] = 1'b1;
assign ifu_PCDReg_raw_internal_available[2] = 1'b1;
assign ifu_PCDReg_raw_internal_available[3] = 1'b1;
assign ifu_PCDReg_raw_internal_available[4] = 1'b1;
assign ifu_PCDReg_raw_internal_available[5] = 1'b1;
assign ifu_PCDReg_raw_internal_available[6] = 1'b1;
assign ifu_PCDReg_raw_internal_available[7] = 1'b1;
assign ifu_PCDReg_raw_internal_available[8] = 1'b1;
assign ifu_PCDReg_raw_internal_available[9] = 1'b1;
assign ifu_PCDReg_raw_internal_available[10] = 1'b1;
assign ifu_PCDReg_raw_internal_available[11] = 1'b1;
assign ifu_PCDReg_raw_internal_available[12] = 1'b1;
assign ifu_PCDReg_raw_internal_available[13] = 1'b1;
assign ifu_PCDReg_raw_internal_available[14] = 1'b1;
assign ifu_PCDReg_raw_internal_available[15] = 1'b1;
assign ifu_PCDReg_raw_internal_available[16] = 1'b1;
assign ifu_PCDReg_raw_internal_available[17] = 1'b1;
assign ifu_PCDReg_raw_internal_available[18] = 1'b1;
assign ifu_PCDReg_raw_internal_available[19] = 1'b1;
assign ifu_PCDReg_raw_internal_available[20] = 1'b1;
assign ifu_PCDReg_raw_internal_available[21] = 1'b1;
assign ifu_PCDReg_raw_internal_available[22] = 1'b1;
assign ifu_PCDReg_raw_internal_available[23] = 1'b1;
assign ifu_PCDReg_raw_internal_available[24] = 1'b1;
assign ifu_PCDReg_raw_internal_available[25] = 1'b1;
assign ifu_PCDReg_raw_internal_available[26] = 1'b1;
assign ifu_PCDReg_raw_internal_available[27] = 1'b1;
assign ifu_PCDReg_raw_internal_available[28] = 1'b1;
assign ifu_PCDReg_raw_internal_available[29] = 1'b1;
assign ifu_PCDReg_raw_internal_available[30] = 1'b1;
assign ifu_PCDReg_raw_internal_available[31] = 1'b1;
assign ifu_PCDReg_raw_internal_available[32] = 1'b1;
assign ifu_PCDReg_raw_internal_available[33] = 1'b1;
assign ifu_PCDReg_raw_internal_available[34] = 1'b1;
assign ifu_PCDReg_raw_internal_available[35] = 1'b1;
assign ifu_PCDReg_raw_internal_available[36] = 1'b1;
assign ifu_PCDReg_raw_internal_available[37] = 1'b1;
assign ifu_PCDReg_raw_internal_available[38] = 1'b1;
assign ifu_PCDReg_raw_internal_available[39] = 1'b1;
assign ifu_PCDReg_raw_internal_available[40] = 1'b1;
assign ifu_PCDReg_raw_internal_available[41] = 1'b1;
assign ifu_PCDReg_raw_internal_available[42] = 1'b1;
assign ifu_PCDReg_raw_internal_available[43] = 1'b1;
assign ifu_PCDReg_raw_internal_available[44] = 1'b1;
assign ifu_PCDReg_raw_internal_available[45] = 1'b1;
assign ifu_PCDReg_raw_internal_available[46] = 1'b1;
assign ifu_PCDReg_raw_internal_available[47] = 1'b1;
assign ifu_PCDReg_raw_internal_available[48] = 1'b1;
assign ifu_PCDReg_raw_internal_available[49] = 1'b1;
assign ifu_PCDReg_raw_internal_available[50] = 1'b1;
assign ifu_PCDReg_raw_internal_available[51] = 1'b1;
assign ifu_PCDReg_raw_internal_available[52] = 1'b1;
assign ifu_PCDReg_raw_internal_available[53] = 1'b1;
assign ifu_PCDReg_raw_internal_available[54] = 1'b1;
assign ifu_PCDReg_raw_internal_available[55] = 1'b1;
assign ifu_PCDReg_raw_internal_available[56] = 1'b1;
assign ifu_PCDReg_raw_internal_available[57] = 1'b1;
assign ifu_PCDReg_raw_internal_available[58] = 1'b1;
assign ifu_PCDReg_raw_internal_available[59] = 1'b1;
assign ifu_PCDReg_raw_internal_available[60] = 1'b1;
assign ifu_PCDReg_raw_internal_available[61] = 1'b1;
assign ifu_PCDReg_raw_internal_available[62] = 1'b1;
assign ifu_PCDReg_raw_internal_available[63] = 1'b1;

// ============================================================================
// Register ifu_PCEReg: 63 mapped bits, width 64
// ============================================================================

// Bus declarations
wire [63:0] ifu_PCEReg_internal;
wire [63:0] ifu_PCEReg_raw_internal;
wire [63:0] ifu_PCEReg_pin_internal;
wire [63:0] ifu_PCEReg_raw_internal_available;

// ---- ifu_PCEReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ifu_PCEReg_raw_internal[0] = 1'bz; // unavailable physical Q
assign ifu_PCEReg_raw_internal[1] = dut.chip.soc_core_ifu_PCEReg_q_reg_1_.Q; // c3[155]
assign ifu_PCEReg_raw_internal[2] = dut.chip.soc_core_ifu_PCEReg_q_reg_2_.Q; // c3[156]
assign ifu_PCEReg_raw_internal[3] = dut.chip.soc_core_ifu_PCEReg_q_reg_3_.Q; // c3[157]
assign ifu_PCEReg_raw_internal[4] = dut.chip.soc_core_ifu_PCEReg_q_reg_4_.Q; // c3[158]
assign ifu_PCEReg_raw_internal[5] = dut.chip.soc_core_ifu_PCEReg_q_reg_5_.Q; // c3[159]
assign ifu_PCEReg_raw_internal[6] = dut.chip.soc_core_ifu_PCEReg_q_reg_6_.Q; // c3[160]
assign ifu_PCEReg_raw_internal[7] = dut.chip.soc_core_ifu_PCEReg_q_reg_7_.Q; // c3[161]
assign ifu_PCEReg_raw_internal[8] = dut.chip.soc_core_ifu_PCEReg_q_reg_8_.Q; // c3[162]
assign ifu_PCEReg_raw_internal[9] = dut.chip.soc_core_ifu_PCEReg_q_reg_9_.Q; // c3[163]
assign ifu_PCEReg_raw_internal[10] = dut.chip.soc_core_ifu_PCEReg_q_reg_10_.Q; // c3[164]
assign ifu_PCEReg_raw_internal[11] = dut.chip.soc_core_ifu_PCEReg_q_reg_11_.Q; // c3[165]
assign ifu_PCEReg_raw_internal[12] = dut.chip.soc_core_ifu_PCEReg_q_reg_12_.Q; // c3[166]
assign ifu_PCEReg_raw_internal[13] = dut.chip.soc_core_ifu_PCEReg_q_reg_13_.Q; // c3[167]
assign ifu_PCEReg_raw_internal[14] = dut.chip.soc_core_ifu_PCEReg_q_reg_14_.Q; // c3[168]
assign ifu_PCEReg_raw_internal[15] = dut.chip.soc_core_ifu_PCEReg_q_reg_15_.Q; // c3[169]
assign ifu_PCEReg_raw_internal[16] = dut.chip.soc_core_ifu_PCEReg_q_reg_16_.Q; // c3[170]
assign ifu_PCEReg_raw_internal[17] = dut.chip.soc_core_ifu_PCEReg_q_reg_17_.Q; // c3[171]
assign ifu_PCEReg_raw_internal[18] = dut.chip.soc_core_ifu_PCEReg_q_reg_18_.Q; // c3[172]
assign ifu_PCEReg_raw_internal[19] = dut.chip.soc_core_ifu_PCEReg_q_reg_19_.Q; // c3[173]
assign ifu_PCEReg_raw_internal[20] = dut.chip.soc_core_ifu_PCEReg_q_reg_20_.Q; // c3[174]
assign ifu_PCEReg_raw_internal[21] = dut.chip.soc_core_ifu_PCEReg_q_reg_21_.Q; // c3[175]
assign ifu_PCEReg_raw_internal[22] = dut.chip.soc_core_ifu_PCEReg_q_reg_22_.Q; // c3[176]
assign ifu_PCEReg_raw_internal[23] = dut.chip.soc_core_ifu_PCEReg_q_reg_23_.Q; // c3[177]
assign ifu_PCEReg_raw_internal[24] = dut.chip.soc_core_ifu_PCEReg_q_reg_24_.Q; // c3[178]
assign ifu_PCEReg_raw_internal[25] = dut.chip.soc_core_ifu_PCEReg_q_reg_25_.Q; // c3[179]
assign ifu_PCEReg_raw_internal[26] = dut.chip.soc_core_ifu_PCEReg_q_reg_26_.Q; // c3[180]
assign ifu_PCEReg_raw_internal[27] = dut.chip.soc_core_ifu_PCEReg_q_reg_27_.Q; // c3[181]
assign ifu_PCEReg_raw_internal[28] = dut.chip.soc_core_ifu_PCEReg_q_reg_28_.Q; // c3[182]
assign ifu_PCEReg_raw_internal[29] = dut.chip.soc_core_ifu_PCEReg_q_reg_29_.Q; // c3[183]
assign ifu_PCEReg_raw_internal[30] = dut.chip.soc_core_ifu_PCEReg_q_reg_30_.Q; // c3[184]
assign ifu_PCEReg_raw_internal[31] = dut.chip.soc_core_ifu_PCEReg_q_reg_31_.Q; // c3[185]
assign ifu_PCEReg_raw_internal[32] = dut.chip.soc_core_ifu_PCEReg_q_reg_32_.Q; // c3[186]
assign ifu_PCEReg_raw_internal[33] = dut.chip.soc_core_ifu_PCEReg_q_reg_33_.Q; // c4[1]
assign ifu_PCEReg_raw_internal[34] = dut.chip.soc_core_ifu_PCEReg_q_reg_34_.Q; // c4[2]
assign ifu_PCEReg_raw_internal[35] = dut.chip.soc_core_ifu_PCEReg_q_reg_35_.Q; // c4[3]
assign ifu_PCEReg_raw_internal[36] = dut.chip.soc_core_ifu_PCEReg_q_reg_36_.Q; // c4[4]
assign ifu_PCEReg_raw_internal[37] = dut.chip.soc_core_ifu_PCEReg_q_reg_37_.Q; // c4[5]
assign ifu_PCEReg_raw_internal[38] = dut.chip.soc_core_ifu_PCEReg_q_reg_38_.Q; // c4[6]
assign ifu_PCEReg_raw_internal[39] = dut.chip.soc_core_ifu_PCEReg_q_reg_39_.Q; // c4[7]
assign ifu_PCEReg_raw_internal[40] = dut.chip.soc_core_ifu_PCEReg_q_reg_40_.Q; // c4[8]
assign ifu_PCEReg_raw_internal[41] = dut.chip.soc_core_ifu_PCEReg_q_reg_41_.Q; // c4[9]
assign ifu_PCEReg_raw_internal[42] = dut.chip.soc_core_ifu_PCEReg_q_reg_42_.Q; // c4[10]
assign ifu_PCEReg_raw_internal[43] = dut.chip.soc_core_ifu_PCEReg_q_reg_43_.Q; // c4[11]
assign ifu_PCEReg_raw_internal[44] = dut.chip.soc_core_ifu_PCEReg_q_reg_44_.Q; // c4[12]
assign ifu_PCEReg_raw_internal[45] = dut.chip.soc_core_ifu_PCEReg_q_reg_45_.Q; // c4[13]
assign ifu_PCEReg_raw_internal[46] = dut.chip.soc_core_ifu_PCEReg_q_reg_46_.Q; // c4[14]
assign ifu_PCEReg_raw_internal[47] = dut.chip.soc_core_ifu_PCEReg_q_reg_47_.Q; // c4[15]
assign ifu_PCEReg_raw_internal[48] = dut.chip.soc_core_ifu_PCEReg_q_reg_48_.Q; // c4[16]
assign ifu_PCEReg_raw_internal[49] = dut.chip.soc_core_ifu_PCEReg_q_reg_49_.Q; // c4[17]
assign ifu_PCEReg_raw_internal[50] = dut.chip.soc_core_ifu_PCEReg_q_reg_50_.Q; // c4[18]
assign ifu_PCEReg_raw_internal[51] = dut.chip.soc_core_ifu_PCEReg_q_reg_51_.Q; // c4[19]
assign ifu_PCEReg_raw_internal[52] = dut.chip.soc_core_ifu_PCEReg_q_reg_52_.Q; // c4[20]
assign ifu_PCEReg_raw_internal[53] = dut.chip.soc_core_ifu_PCEReg_q_reg_53_.Q; // c4[21]
assign ifu_PCEReg_raw_internal[54] = dut.chip.soc_core_ifu_PCEReg_q_reg_54_.Q; // c4[22]
assign ifu_PCEReg_raw_internal[55] = dut.chip.soc_core_ifu_PCEReg_q_reg_55_.Q; // c4[23]
assign ifu_PCEReg_raw_internal[56] = dut.chip.soc_core_ifu_PCEReg_q_reg_56_.Q; // c4[24]
assign ifu_PCEReg_raw_internal[57] = dut.chip.soc_core_ifu_PCEReg_q_reg_57_.Q; // c4[25]
assign ifu_PCEReg_raw_internal[58] = dut.chip.soc_core_ifu_PCEReg_q_reg_58_.Q; // c4[26]
assign ifu_PCEReg_raw_internal[59] = dut.chip.soc_core_ifu_PCEReg_q_reg_59_.Q; // c4[27]
assign ifu_PCEReg_raw_internal[60] = dut.chip.soc_core_ifu_PCEReg_q_reg_60_.Q; // c4[28]
assign ifu_PCEReg_raw_internal[61] = dut.chip.soc_core_ifu_PCEReg_q_reg_61_.Q; // c4[29]
assign ifu_PCEReg_raw_internal[62] = dut.chip.soc_core_ifu_PCEReg_q_reg_62_.Q; // c4[30]
assign ifu_PCEReg_raw_internal[63] = dut.chip.soc_core_ifu_PCEReg_q_reg_63_.Q; // c4[31]

// ---- ifu_PCEReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ifu_PCEReg_internal[0] = 1'bz; // unavailable logical estimate
assign ifu_PCEReg_internal[1] = ifu_PCEReg_raw_internal[1];
assign ifu_PCEReg_internal[2] = ifu_PCEReg_raw_internal[2];
assign ifu_PCEReg_internal[3] = ifu_PCEReg_raw_internal[3];
assign ifu_PCEReg_internal[4] = ifu_PCEReg_raw_internal[4];
assign ifu_PCEReg_internal[5] = ifu_PCEReg_raw_internal[5];
assign ifu_PCEReg_internal[6] = ifu_PCEReg_raw_internal[6];
assign ifu_PCEReg_internal[7] = ifu_PCEReg_raw_internal[7];
assign ifu_PCEReg_internal[8] = ifu_PCEReg_raw_internal[8];
assign ifu_PCEReg_internal[9] = ifu_PCEReg_raw_internal[9];
assign ifu_PCEReg_internal[10] = ifu_PCEReg_raw_internal[10];
assign ifu_PCEReg_internal[11] = ifu_PCEReg_raw_internal[11];
assign ifu_PCEReg_internal[12] = ifu_PCEReg_raw_internal[12];
assign ifu_PCEReg_internal[13] = ifu_PCEReg_raw_internal[13];
assign ifu_PCEReg_internal[14] = ifu_PCEReg_raw_internal[14];
assign ifu_PCEReg_internal[15] = ifu_PCEReg_raw_internal[15];
assign ifu_PCEReg_internal[16] = ifu_PCEReg_raw_internal[16];
assign ifu_PCEReg_internal[17] = ifu_PCEReg_raw_internal[17];
assign ifu_PCEReg_internal[18] = ifu_PCEReg_raw_internal[18];
assign ifu_PCEReg_internal[19] = ifu_PCEReg_raw_internal[19];
assign ifu_PCEReg_internal[20] = ifu_PCEReg_raw_internal[20];
assign ifu_PCEReg_internal[21] = ifu_PCEReg_raw_internal[21];
assign ifu_PCEReg_internal[22] = ifu_PCEReg_raw_internal[22];
assign ifu_PCEReg_internal[23] = ifu_PCEReg_raw_internal[23];
assign ifu_PCEReg_internal[24] = ifu_PCEReg_raw_internal[24];
assign ifu_PCEReg_internal[25] = ifu_PCEReg_raw_internal[25];
assign ifu_PCEReg_internal[26] = ifu_PCEReg_raw_internal[26];
assign ifu_PCEReg_internal[27] = ifu_PCEReg_raw_internal[27];
assign ifu_PCEReg_internal[28] = ifu_PCEReg_raw_internal[28];
assign ifu_PCEReg_internal[29] = ifu_PCEReg_raw_internal[29];
assign ifu_PCEReg_internal[30] = ifu_PCEReg_raw_internal[30];
assign ifu_PCEReg_internal[31] = ifu_PCEReg_raw_internal[31];
assign ifu_PCEReg_internal[32] = ifu_PCEReg_raw_internal[32];
assign ifu_PCEReg_internal[33] = ifu_PCEReg_raw_internal[33];
assign ifu_PCEReg_internal[34] = ifu_PCEReg_raw_internal[34];
assign ifu_PCEReg_internal[35] = ifu_PCEReg_raw_internal[35];
assign ifu_PCEReg_internal[36] = ifu_PCEReg_raw_internal[36];
assign ifu_PCEReg_internal[37] = ifu_PCEReg_raw_internal[37];
assign ifu_PCEReg_internal[38] = ifu_PCEReg_raw_internal[38];
assign ifu_PCEReg_internal[39] = ifu_PCEReg_raw_internal[39];
assign ifu_PCEReg_internal[40] = ifu_PCEReg_raw_internal[40];
assign ifu_PCEReg_internal[41] = ifu_PCEReg_raw_internal[41];
assign ifu_PCEReg_internal[42] = ifu_PCEReg_raw_internal[42];
assign ifu_PCEReg_internal[43] = ifu_PCEReg_raw_internal[43];
assign ifu_PCEReg_internal[44] = ifu_PCEReg_raw_internal[44];
assign ifu_PCEReg_internal[45] = ifu_PCEReg_raw_internal[45];
assign ifu_PCEReg_internal[46] = ifu_PCEReg_raw_internal[46];
assign ifu_PCEReg_internal[47] = ifu_PCEReg_raw_internal[47];
assign ifu_PCEReg_internal[48] = ifu_PCEReg_raw_internal[48];
assign ifu_PCEReg_internal[49] = ifu_PCEReg_raw_internal[49];
assign ifu_PCEReg_internal[50] = ifu_PCEReg_raw_internal[50];
assign ifu_PCEReg_internal[51] = ifu_PCEReg_raw_internal[51];
assign ifu_PCEReg_internal[52] = ifu_PCEReg_raw_internal[52];
assign ifu_PCEReg_internal[53] = ifu_PCEReg_raw_internal[53];
assign ifu_PCEReg_internal[54] = ifu_PCEReg_raw_internal[54];
assign ifu_PCEReg_internal[55] = ifu_PCEReg_raw_internal[55];
assign ifu_PCEReg_internal[56] = ifu_PCEReg_raw_internal[56];
assign ifu_PCEReg_internal[57] = ifu_PCEReg_raw_internal[57];
assign ifu_PCEReg_internal[58] = ifu_PCEReg_raw_internal[58];
assign ifu_PCEReg_internal[59] = ifu_PCEReg_raw_internal[59];
assign ifu_PCEReg_internal[60] = ifu_PCEReg_raw_internal[60];
assign ifu_PCEReg_internal[61] = ifu_PCEReg_raw_internal[61];
assign ifu_PCEReg_internal[62] = ifu_PCEReg_raw_internal[62];
assign ifu_PCEReg_internal[63] = ifu_PCEReg_raw_internal[63];

// ---- ifu_PCEReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ifu_PCEReg_pin_internal[0] = 1'bz; // unavailable scan pin
assign ifu_PCEReg_pin_internal[1] = dut.chip.soc_core_ifu_PCEReg_q_reg_1_.Q;
assign ifu_PCEReg_pin_internal[2] = dut.chip.soc_core_ifu_PCEReg_q_reg_2_.Q;
assign ifu_PCEReg_pin_internal[3] = dut.chip.soc_core_ifu_PCEReg_q_reg_3_.Q;
assign ifu_PCEReg_pin_internal[4] = dut.chip.soc_core_ifu_PCEReg_q_reg_4_.Q;
assign ifu_PCEReg_pin_internal[5] = dut.chip.soc_core_ifu_PCEReg_q_reg_5_.Q;
assign ifu_PCEReg_pin_internal[6] = dut.chip.soc_core_ifu_PCEReg_q_reg_6_.Q;
assign ifu_PCEReg_pin_internal[7] = dut.chip.soc_core_ifu_PCEReg_q_reg_7_.Q;
assign ifu_PCEReg_pin_internal[8] = dut.chip.soc_core_ifu_PCEReg_q_reg_8_.Q;
assign ifu_PCEReg_pin_internal[9] = dut.chip.soc_core_ifu_PCEReg_q_reg_9_.Q;
assign ifu_PCEReg_pin_internal[10] = dut.chip.soc_core_ifu_PCEReg_q_reg_10_.Q;
assign ifu_PCEReg_pin_internal[11] = dut.chip.soc_core_ifu_PCEReg_q_reg_11_.Q;
assign ifu_PCEReg_pin_internal[12] = dut.chip.soc_core_ifu_PCEReg_q_reg_12_.Q;
assign ifu_PCEReg_pin_internal[13] = dut.chip.soc_core_ifu_PCEReg_q_reg_13_.Q;
assign ifu_PCEReg_pin_internal[14] = dut.chip.soc_core_ifu_PCEReg_q_reg_14_.Q;
assign ifu_PCEReg_pin_internal[15] = dut.chip.soc_core_ifu_PCEReg_q_reg_15_.Q;
assign ifu_PCEReg_pin_internal[16] = dut.chip.soc_core_ifu_PCEReg_q_reg_16_.Q;
assign ifu_PCEReg_pin_internal[17] = dut.chip.soc_core_ifu_PCEReg_q_reg_17_.Q;
assign ifu_PCEReg_pin_internal[18] = dut.chip.soc_core_ifu_PCEReg_q_reg_18_.Q;
assign ifu_PCEReg_pin_internal[19] = dut.chip.soc_core_ifu_PCEReg_q_reg_19_.Q;
assign ifu_PCEReg_pin_internal[20] = dut.chip.soc_core_ifu_PCEReg_q_reg_20_.Q;
assign ifu_PCEReg_pin_internal[21] = dut.chip.soc_core_ifu_PCEReg_q_reg_21_.Q;
assign ifu_PCEReg_pin_internal[22] = dut.chip.soc_core_ifu_PCEReg_q_reg_22_.Q;
assign ifu_PCEReg_pin_internal[23] = dut.chip.soc_core_ifu_PCEReg_q_reg_23_.Q;
assign ifu_PCEReg_pin_internal[24] = dut.chip.soc_core_ifu_PCEReg_q_reg_24_.Q;
assign ifu_PCEReg_pin_internal[25] = dut.chip.soc_core_ifu_PCEReg_q_reg_25_.Q;
assign ifu_PCEReg_pin_internal[26] = dut.chip.soc_core_ifu_PCEReg_q_reg_26_.Q;
assign ifu_PCEReg_pin_internal[27] = dut.chip.soc_core_ifu_PCEReg_q_reg_27_.Q;
assign ifu_PCEReg_pin_internal[28] = dut.chip.soc_core_ifu_PCEReg_q_reg_28_.Q;
assign ifu_PCEReg_pin_internal[29] = dut.chip.soc_core_ifu_PCEReg_q_reg_29_.Q;
assign ifu_PCEReg_pin_internal[30] = dut.chip.soc_core_ifu_PCEReg_q_reg_30_.Q;
assign ifu_PCEReg_pin_internal[31] = dut.chip.soc_core_ifu_PCEReg_q_reg_31_.Q;
assign ifu_PCEReg_pin_internal[32] = dut.chip.soc_core_ifu_PCEReg_q_reg_32_.Q;
assign ifu_PCEReg_pin_internal[33] = dut.chip.soc_core_ifu_PCEReg_q_reg_33_.Q;
assign ifu_PCEReg_pin_internal[34] = dut.chip.soc_core_ifu_PCEReg_q_reg_34_.Q;
assign ifu_PCEReg_pin_internal[35] = dut.chip.soc_core_ifu_PCEReg_q_reg_35_.Q;
assign ifu_PCEReg_pin_internal[36] = dut.chip.soc_core_ifu_PCEReg_q_reg_36_.Q;
assign ifu_PCEReg_pin_internal[37] = dut.chip.soc_core_ifu_PCEReg_q_reg_37_.Q;
assign ifu_PCEReg_pin_internal[38] = dut.chip.soc_core_ifu_PCEReg_q_reg_38_.Q;
assign ifu_PCEReg_pin_internal[39] = dut.chip.soc_core_ifu_PCEReg_q_reg_39_.Q;
assign ifu_PCEReg_pin_internal[40] = dut.chip.soc_core_ifu_PCEReg_q_reg_40_.Q;
assign ifu_PCEReg_pin_internal[41] = dut.chip.soc_core_ifu_PCEReg_q_reg_41_.Q;
assign ifu_PCEReg_pin_internal[42] = dut.chip.soc_core_ifu_PCEReg_q_reg_42_.Q;
assign ifu_PCEReg_pin_internal[43] = dut.chip.soc_core_ifu_PCEReg_q_reg_43_.Q;
assign ifu_PCEReg_pin_internal[44] = dut.chip.soc_core_ifu_PCEReg_q_reg_44_.Q;
assign ifu_PCEReg_pin_internal[45] = dut.chip.soc_core_ifu_PCEReg_q_reg_45_.Q;
assign ifu_PCEReg_pin_internal[46] = dut.chip.soc_core_ifu_PCEReg_q_reg_46_.Q;
assign ifu_PCEReg_pin_internal[47] = dut.chip.soc_core_ifu_PCEReg_q_reg_47_.Q;
assign ifu_PCEReg_pin_internal[48] = dut.chip.soc_core_ifu_PCEReg_q_reg_48_.Q;
assign ifu_PCEReg_pin_internal[49] = dut.chip.soc_core_ifu_PCEReg_q_reg_49_.Q;
assign ifu_PCEReg_pin_internal[50] = dut.chip.soc_core_ifu_PCEReg_q_reg_50_.Q;
assign ifu_PCEReg_pin_internal[51] = dut.chip.soc_core_ifu_PCEReg_q_reg_51_.Q;
assign ifu_PCEReg_pin_internal[52] = dut.chip.soc_core_ifu_PCEReg_q_reg_52_.Q;
assign ifu_PCEReg_pin_internal[53] = dut.chip.soc_core_ifu_PCEReg_q_reg_53_.Q;
assign ifu_PCEReg_pin_internal[54] = dut.chip.soc_core_ifu_PCEReg_q_reg_54_.Q;
assign ifu_PCEReg_pin_internal[55] = dut.chip.soc_core_ifu_PCEReg_q_reg_55_.Q;
assign ifu_PCEReg_pin_internal[56] = dut.chip.soc_core_ifu_PCEReg_q_reg_56_.Q;
assign ifu_PCEReg_pin_internal[57] = dut.chip.soc_core_ifu_PCEReg_q_reg_57_.Q;
assign ifu_PCEReg_pin_internal[58] = dut.chip.soc_core_ifu_PCEReg_q_reg_58_.Q;
assign ifu_PCEReg_pin_internal[59] = dut.chip.soc_core_ifu_PCEReg_q_reg_59_.Q;
assign ifu_PCEReg_pin_internal[60] = dut.chip.soc_core_ifu_PCEReg_q_reg_60_.Q;
assign ifu_PCEReg_pin_internal[61] = dut.chip.soc_core_ifu_PCEReg_q_reg_61_.Q;
assign ifu_PCEReg_pin_internal[62] = dut.chip.soc_core_ifu_PCEReg_q_reg_62_.Q;
assign ifu_PCEReg_pin_internal[63] = dut.chip.soc_core_ifu_PCEReg_q_reg_63_.Q;

// ---- ifu_PCEReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ifu_PCEReg_raw_internal_available[0] = 1'b0;
assign ifu_PCEReg_raw_internal_available[1] = 1'b1;
assign ifu_PCEReg_raw_internal_available[2] = 1'b1;
assign ifu_PCEReg_raw_internal_available[3] = 1'b1;
assign ifu_PCEReg_raw_internal_available[4] = 1'b1;
assign ifu_PCEReg_raw_internal_available[5] = 1'b1;
assign ifu_PCEReg_raw_internal_available[6] = 1'b1;
assign ifu_PCEReg_raw_internal_available[7] = 1'b1;
assign ifu_PCEReg_raw_internal_available[8] = 1'b1;
assign ifu_PCEReg_raw_internal_available[9] = 1'b1;
assign ifu_PCEReg_raw_internal_available[10] = 1'b1;
assign ifu_PCEReg_raw_internal_available[11] = 1'b1;
assign ifu_PCEReg_raw_internal_available[12] = 1'b1;
assign ifu_PCEReg_raw_internal_available[13] = 1'b1;
assign ifu_PCEReg_raw_internal_available[14] = 1'b1;
assign ifu_PCEReg_raw_internal_available[15] = 1'b1;
assign ifu_PCEReg_raw_internal_available[16] = 1'b1;
assign ifu_PCEReg_raw_internal_available[17] = 1'b1;
assign ifu_PCEReg_raw_internal_available[18] = 1'b1;
assign ifu_PCEReg_raw_internal_available[19] = 1'b1;
assign ifu_PCEReg_raw_internal_available[20] = 1'b1;
assign ifu_PCEReg_raw_internal_available[21] = 1'b1;
assign ifu_PCEReg_raw_internal_available[22] = 1'b1;
assign ifu_PCEReg_raw_internal_available[23] = 1'b1;
assign ifu_PCEReg_raw_internal_available[24] = 1'b1;
assign ifu_PCEReg_raw_internal_available[25] = 1'b1;
assign ifu_PCEReg_raw_internal_available[26] = 1'b1;
assign ifu_PCEReg_raw_internal_available[27] = 1'b1;
assign ifu_PCEReg_raw_internal_available[28] = 1'b1;
assign ifu_PCEReg_raw_internal_available[29] = 1'b1;
assign ifu_PCEReg_raw_internal_available[30] = 1'b1;
assign ifu_PCEReg_raw_internal_available[31] = 1'b1;
assign ifu_PCEReg_raw_internal_available[32] = 1'b1;
assign ifu_PCEReg_raw_internal_available[33] = 1'b1;
assign ifu_PCEReg_raw_internal_available[34] = 1'b1;
assign ifu_PCEReg_raw_internal_available[35] = 1'b1;
assign ifu_PCEReg_raw_internal_available[36] = 1'b1;
assign ifu_PCEReg_raw_internal_available[37] = 1'b1;
assign ifu_PCEReg_raw_internal_available[38] = 1'b1;
assign ifu_PCEReg_raw_internal_available[39] = 1'b1;
assign ifu_PCEReg_raw_internal_available[40] = 1'b1;
assign ifu_PCEReg_raw_internal_available[41] = 1'b1;
assign ifu_PCEReg_raw_internal_available[42] = 1'b1;
assign ifu_PCEReg_raw_internal_available[43] = 1'b1;
assign ifu_PCEReg_raw_internal_available[44] = 1'b1;
assign ifu_PCEReg_raw_internal_available[45] = 1'b1;
assign ifu_PCEReg_raw_internal_available[46] = 1'b1;
assign ifu_PCEReg_raw_internal_available[47] = 1'b1;
assign ifu_PCEReg_raw_internal_available[48] = 1'b1;
assign ifu_PCEReg_raw_internal_available[49] = 1'b1;
assign ifu_PCEReg_raw_internal_available[50] = 1'b1;
assign ifu_PCEReg_raw_internal_available[51] = 1'b1;
assign ifu_PCEReg_raw_internal_available[52] = 1'b1;
assign ifu_PCEReg_raw_internal_available[53] = 1'b1;
assign ifu_PCEReg_raw_internal_available[54] = 1'b1;
assign ifu_PCEReg_raw_internal_available[55] = 1'b1;
assign ifu_PCEReg_raw_internal_available[56] = 1'b1;
assign ifu_PCEReg_raw_internal_available[57] = 1'b1;
assign ifu_PCEReg_raw_internal_available[58] = 1'b1;
assign ifu_PCEReg_raw_internal_available[59] = 1'b1;
assign ifu_PCEReg_raw_internal_available[60] = 1'b1;
assign ifu_PCEReg_raw_internal_available[61] = 1'b1;
assign ifu_PCEReg_raw_internal_available[62] = 1'b1;
assign ifu_PCEReg_raw_internal_available[63] = 1'b1;

// ============================================================================
// Register ifu_Spill_SpillDReg: 1 mapped bits, width 1
// ============================================================================

// Bus declarations
wire [0:0] ifu_Spill_SpillDReg_internal;
wire [0:0] ifu_Spill_SpillDReg_raw_internal;
wire [0:0] ifu_Spill_SpillDReg_pin_internal;
wire [0:0] ifu_Spill_SpillDReg_raw_internal_available;

// ---- ifu_Spill_SpillDReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ifu_Spill_SpillDReg_raw_internal[0] = dut.chip.soc_core_ifu_Spill_SpillDReg_q_reg_0_.Q; // c4[32]

// ---- ifu_Spill_SpillDReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ifu_Spill_SpillDReg_internal[0] = ifu_Spill_SpillDReg_raw_internal[0];

// ---- ifu_Spill_SpillDReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ifu_Spill_SpillDReg_pin_internal[0] = dut.chip.soc_core_ifu_Spill_SpillDReg_q_reg_0_.Q;

// ---- ifu_Spill_SpillDReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ifu_Spill_SpillDReg_raw_internal_available[0] = 1'b1;

// ============================================================================
// Register ifu_Spill_SpillEReg: 1 mapped bits, width 1
// ============================================================================

// Bus declarations
wire [0:0] ifu_Spill_SpillEReg_internal;
wire [0:0] ifu_Spill_SpillEReg_raw_internal;
wire [0:0] ifu_Spill_SpillEReg_pin_internal;
wire [0:0] ifu_Spill_SpillEReg_raw_internal_available;

// ---- ifu_Spill_SpillEReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ifu_Spill_SpillEReg_raw_internal[0] = dut.chip.soc_core_ifu_Spill_SpillEReg_q_reg_0_.Q; // c4[33]

// ---- ifu_Spill_SpillEReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ifu_Spill_SpillEReg_internal[0] = ifu_Spill_SpillEReg_raw_internal[0];

// ---- ifu_Spill_SpillEReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ifu_Spill_SpillEReg_pin_internal[0] = dut.chip.soc_core_ifu_Spill_SpillEReg_q_reg_0_.Q;

// ---- ifu_Spill_SpillEReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ifu_Spill_SpillEReg_raw_internal_available[0] = 1'b1;

// ============================================================================
// Register ifu_Spill_SpillMReg: 1 mapped bits, width 1
// ============================================================================

// Bus declarations
wire [0:0] ifu_Spill_SpillMReg_internal;
wire [0:0] ifu_Spill_SpillMReg_raw_internal;
wire [0:0] ifu_Spill_SpillMReg_pin_internal;
wire [0:0] ifu_Spill_SpillMReg_raw_internal_available;

// ---- ifu_Spill_SpillMReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ifu_Spill_SpillMReg_raw_internal[0] = dut.chip.soc_core_ifu_Spill_SpillMReg_q_reg_0_.Q; // c4[34]

// ---- ifu_Spill_SpillMReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ifu_Spill_SpillMReg_internal[0] = ifu_Spill_SpillMReg_raw_internal[0];

// ---- ifu_Spill_SpillMReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ifu_Spill_SpillMReg_pin_internal[0] = dut.chip.soc_core_ifu_Spill_SpillMReg_q_reg_0_.Q;

// ---- ifu_Spill_SpillMReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ifu_Spill_SpillMReg_raw_internal_available[0] = 1'b1;

// ============================================================================
// Register ifu_genblk9_InstrMReg: 32 mapped bits, width 32
// ============================================================================

// Bus declarations
wire [31:0] ifu_genblk9_InstrMReg_internal;
wire [31:0] ifu_genblk9_InstrMReg_raw_internal;
wire [31:0] ifu_genblk9_InstrMReg_pin_internal;
wire [31:0] ifu_genblk9_InstrMReg_raw_internal_available;

// ---- ifu_genblk9_InstrMReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ifu_genblk9_InstrMReg_raw_internal[0] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_0_.Q; // c4[35]
assign ifu_genblk9_InstrMReg_raw_internal[1] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_1_.Q; // c4[36]
assign ifu_genblk9_InstrMReg_raw_internal[2] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_2_.Q; // c4[37]
assign ifu_genblk9_InstrMReg_raw_internal[3] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_3_.Q; // c4[38]
assign ifu_genblk9_InstrMReg_raw_internal[4] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_4_.Q; // c4[39]
assign ifu_genblk9_InstrMReg_raw_internal[5] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_5_.Q; // c4[40]
assign ifu_genblk9_InstrMReg_raw_internal[6] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_6_.Q; // c4[41]
assign ifu_genblk9_InstrMReg_raw_internal[7] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_7_.Q; // c4[42]
assign ifu_genblk9_InstrMReg_raw_internal[8] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_8_.Q; // c4[43]
assign ifu_genblk9_InstrMReg_raw_internal[9] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_9_.Q; // c4[44]
assign ifu_genblk9_InstrMReg_raw_internal[10] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_10_.Q; // c4[45]
assign ifu_genblk9_InstrMReg_raw_internal[11] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_11_.Q; // c4[46]
assign ifu_genblk9_InstrMReg_raw_internal[12] = ~dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_12_.QN; // c4[47]
assign ifu_genblk9_InstrMReg_raw_internal[13] = ~dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_13_.QN; // c4[48]
assign ifu_genblk9_InstrMReg_raw_internal[14] = ~dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_14_.QN; // c4[49]
assign ifu_genblk9_InstrMReg_raw_internal[15] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_15_.Q; // c4[50]
assign ifu_genblk9_InstrMReg_raw_internal[16] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_16_.Q; // c4[51]
assign ifu_genblk9_InstrMReg_raw_internal[17] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_17_.Q; // c4[52]
assign ifu_genblk9_InstrMReg_raw_internal[18] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_18_.Q; // c4[53]
assign ifu_genblk9_InstrMReg_raw_internal[19] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_19_.Q; // c4[54]
assign ifu_genblk9_InstrMReg_raw_internal[20] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_20_.Q; // c4[55]
assign ifu_genblk9_InstrMReg_raw_internal[21] = ~dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_21_.QN; // c4[56]
assign ifu_genblk9_InstrMReg_raw_internal[22] = ~dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_22_.QN; // c4[57]
assign ifu_genblk9_InstrMReg_raw_internal[23] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_23_.Q; // c4[58]
assign ifu_genblk9_InstrMReg_raw_internal[24] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_24_.Q; // c4[59]
assign ifu_genblk9_InstrMReg_raw_internal[25] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_25_.Q; // c4[60]
assign ifu_genblk9_InstrMReg_raw_internal[26] = ~dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_26_.QN; // c4[61]
assign ifu_genblk9_InstrMReg_raw_internal[27] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_27_.Q; // c4[62]
assign ifu_genblk9_InstrMReg_raw_internal[28] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_28_.Q; // c4[63]
assign ifu_genblk9_InstrMReg_raw_internal[29] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_29_.Q; // c4[64]
assign ifu_genblk9_InstrMReg_raw_internal[30] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_30_.Q; // c4[65]
assign ifu_genblk9_InstrMReg_raw_internal[31] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_31_.Q; // c4[66]

// ---- ifu_genblk9_InstrMReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ifu_genblk9_InstrMReg_internal[0] = ifu_genblk9_InstrMReg_raw_internal[0];
assign ifu_genblk9_InstrMReg_internal[1] = ifu_genblk9_InstrMReg_raw_internal[1];
assign ifu_genblk9_InstrMReg_internal[2] = ifu_genblk9_InstrMReg_raw_internal[2];
assign ifu_genblk9_InstrMReg_internal[3] = ifu_genblk9_InstrMReg_raw_internal[3];
assign ifu_genblk9_InstrMReg_internal[4] = ifu_genblk9_InstrMReg_raw_internal[4];
assign ifu_genblk9_InstrMReg_internal[5] = ifu_genblk9_InstrMReg_raw_internal[5];
assign ifu_genblk9_InstrMReg_internal[6] = ifu_genblk9_InstrMReg_raw_internal[6];
assign ifu_genblk9_InstrMReg_internal[7] = ifu_genblk9_InstrMReg_raw_internal[7];
assign ifu_genblk9_InstrMReg_internal[8] = ifu_genblk9_InstrMReg_raw_internal[8];
assign ifu_genblk9_InstrMReg_internal[9] = ifu_genblk9_InstrMReg_raw_internal[9];
assign ifu_genblk9_InstrMReg_internal[10] = ifu_genblk9_InstrMReg_raw_internal[10];
assign ifu_genblk9_InstrMReg_internal[11] = ifu_genblk9_InstrMReg_raw_internal[11];
assign ifu_genblk9_InstrMReg_internal[12] = ifu_genblk9_InstrMReg_raw_internal[12];
assign ifu_genblk9_InstrMReg_internal[13] = ifu_genblk9_InstrMReg_raw_internal[13];
assign ifu_genblk9_InstrMReg_internal[14] = ifu_genblk9_InstrMReg_raw_internal[14];
assign ifu_genblk9_InstrMReg_internal[15] = ifu_genblk9_InstrMReg_raw_internal[15];
assign ifu_genblk9_InstrMReg_internal[16] = ifu_genblk9_InstrMReg_raw_internal[16];
assign ifu_genblk9_InstrMReg_internal[17] = ifu_genblk9_InstrMReg_raw_internal[17];
assign ifu_genblk9_InstrMReg_internal[18] = ifu_genblk9_InstrMReg_raw_internal[18];
assign ifu_genblk9_InstrMReg_internal[19] = ifu_genblk9_InstrMReg_raw_internal[19];
assign ifu_genblk9_InstrMReg_internal[20] = ifu_genblk9_InstrMReg_raw_internal[20];
assign ifu_genblk9_InstrMReg_internal[21] = ifu_genblk9_InstrMReg_raw_internal[21];
assign ifu_genblk9_InstrMReg_internal[22] = ifu_genblk9_InstrMReg_raw_internal[22];
assign ifu_genblk9_InstrMReg_internal[23] = ifu_genblk9_InstrMReg_raw_internal[23];
assign ifu_genblk9_InstrMReg_internal[24] = ifu_genblk9_InstrMReg_raw_internal[24];
assign ifu_genblk9_InstrMReg_internal[25] = ifu_genblk9_InstrMReg_raw_internal[25];
assign ifu_genblk9_InstrMReg_internal[26] = ifu_genblk9_InstrMReg_raw_internal[26];
assign ifu_genblk9_InstrMReg_internal[27] = ifu_genblk9_InstrMReg_raw_internal[27];
assign ifu_genblk9_InstrMReg_internal[28] = ifu_genblk9_InstrMReg_raw_internal[28];
assign ifu_genblk9_InstrMReg_internal[29] = ifu_genblk9_InstrMReg_raw_internal[29];
assign ifu_genblk9_InstrMReg_internal[30] = ifu_genblk9_InstrMReg_raw_internal[30];
assign ifu_genblk9_InstrMReg_internal[31] = ifu_genblk9_InstrMReg_raw_internal[31];

// ---- ifu_genblk9_InstrMReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ifu_genblk9_InstrMReg_pin_internal[0] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_0_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[1] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_1_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[2] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_2_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[3] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_3_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[4] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_4_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[5] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_5_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[6] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_6_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[7] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_7_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[8] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_8_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[9] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_9_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[10] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_10_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[11] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_11_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[12] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_12_.QN;
assign ifu_genblk9_InstrMReg_pin_internal[13] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_13_.QN;
assign ifu_genblk9_InstrMReg_pin_internal[14] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_14_.QN;
assign ifu_genblk9_InstrMReg_pin_internal[15] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_15_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[16] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_16_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[17] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_17_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[18] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_18_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[19] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_19_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[20] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_20_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[21] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_21_.QN;
assign ifu_genblk9_InstrMReg_pin_internal[22] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_22_.QN;
assign ifu_genblk9_InstrMReg_pin_internal[23] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_23_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[24] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_24_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[25] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_25_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[26] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_26_.QN;
assign ifu_genblk9_InstrMReg_pin_internal[27] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_27_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[28] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_28_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[29] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_29_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[30] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_30_.Q;
assign ifu_genblk9_InstrMReg_pin_internal[31] = dut.chip.soc_core_ifu_genblk9_InstrMReg_q_reg_31_.Q;

// ---- ifu_genblk9_InstrMReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ifu_genblk9_InstrMReg_raw_internal_available[0] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[1] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[2] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[3] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[4] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[5] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[6] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[7] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[8] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[9] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[10] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[11] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[12] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[13] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[14] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[15] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[16] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[17] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[18] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[19] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[20] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[21] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[22] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[23] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[24] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[25] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[26] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[27] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[28] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[29] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[30] = 1'b1;
assign ifu_genblk9_InstrMReg_raw_internal_available[31] = 1'b1;

// ============================================================================
// Register ifu_genblk10_PCMReg: 63 mapped bits, width 64
// ============================================================================

// Bus declarations
wire [63:0] ifu_genblk10_PCMReg_internal;
wire [63:0] ifu_genblk10_PCMReg_raw_internal;
wire [63:0] ifu_genblk10_PCMReg_pin_internal;
wire [63:0] ifu_genblk10_PCMReg_raw_internal_available;

// ---- ifu_genblk10_PCMReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ifu_genblk10_PCMReg_raw_internal[0] = 1'bz; // unavailable physical Q
assign ifu_genblk10_PCMReg_raw_internal[1] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_1_.Q; // c4[67]
assign ifu_genblk10_PCMReg_raw_internal[2] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_2_.Q; // c4[68]
assign ifu_genblk10_PCMReg_raw_internal[3] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_3_.Q; // c4[69]
assign ifu_genblk10_PCMReg_raw_internal[4] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_4_.Q; // c4[70]
assign ifu_genblk10_PCMReg_raw_internal[5] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_5_.Q; // c4[71]
assign ifu_genblk10_PCMReg_raw_internal[6] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_6_.Q; // c4[72]
assign ifu_genblk10_PCMReg_raw_internal[7] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_7_.Q; // c4[73]
assign ifu_genblk10_PCMReg_raw_internal[8] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_8_.Q; // c4[74]
assign ifu_genblk10_PCMReg_raw_internal[9] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_9_.Q; // c4[75]
assign ifu_genblk10_PCMReg_raw_internal[10] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_10_.Q; // c4[76]
assign ifu_genblk10_PCMReg_raw_internal[11] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_11_.Q; // c4[77]
assign ifu_genblk10_PCMReg_raw_internal[12] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_12_.Q; // c4[78]
assign ifu_genblk10_PCMReg_raw_internal[13] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_13_.Q; // c4[79]
assign ifu_genblk10_PCMReg_raw_internal[14] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_14_.Q; // c4[80]
assign ifu_genblk10_PCMReg_raw_internal[15] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_15_.Q; // c4[81]
assign ifu_genblk10_PCMReg_raw_internal[16] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_16_.Q; // c4[82]
assign ifu_genblk10_PCMReg_raw_internal[17] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_17_.Q; // c4[83]
assign ifu_genblk10_PCMReg_raw_internal[18] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_18_.Q; // c4[84]
assign ifu_genblk10_PCMReg_raw_internal[19] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_19_.Q; // c4[85]
assign ifu_genblk10_PCMReg_raw_internal[20] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_20_.Q; // c4[86]
assign ifu_genblk10_PCMReg_raw_internal[21] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_21_.Q; // c4[87]
assign ifu_genblk10_PCMReg_raw_internal[22] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_22_.Q; // c4[88]
assign ifu_genblk10_PCMReg_raw_internal[23] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_23_.Q; // c4[89]
assign ifu_genblk10_PCMReg_raw_internal[24] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_24_.Q; // c4[90]
assign ifu_genblk10_PCMReg_raw_internal[25] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_25_.Q; // c4[91]
assign ifu_genblk10_PCMReg_raw_internal[26] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_26_.Q; // c4[92]
assign ifu_genblk10_PCMReg_raw_internal[27] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_27_.Q; // c4[93]
assign ifu_genblk10_PCMReg_raw_internal[28] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_28_.Q; // c4[94]
assign ifu_genblk10_PCMReg_raw_internal[29] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_29_.Q; // c4[95]
assign ifu_genblk10_PCMReg_raw_internal[30] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_30_.Q; // c4[96]
assign ifu_genblk10_PCMReg_raw_internal[31] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_31_.Q; // c4[97]
assign ifu_genblk10_PCMReg_raw_internal[32] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_32_.Q; // c4[98]
assign ifu_genblk10_PCMReg_raw_internal[33] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_33_.Q; // c4[99]
assign ifu_genblk10_PCMReg_raw_internal[34] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_34_.Q; // c4[100]
assign ifu_genblk10_PCMReg_raw_internal[35] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_35_.Q; // c4[101]
assign ifu_genblk10_PCMReg_raw_internal[36] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_36_.Q; // c4[102]
assign ifu_genblk10_PCMReg_raw_internal[37] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_37_.Q; // c4[103]
assign ifu_genblk10_PCMReg_raw_internal[38] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_38_.Q; // c4[104]
assign ifu_genblk10_PCMReg_raw_internal[39] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_39_.Q; // c4[105]
assign ifu_genblk10_PCMReg_raw_internal[40] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_40_.Q; // c4[106]
assign ifu_genblk10_PCMReg_raw_internal[41] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_41_.Q; // c4[107]
assign ifu_genblk10_PCMReg_raw_internal[42] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_42_.Q; // c4[108]
assign ifu_genblk10_PCMReg_raw_internal[43] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_43_.Q; // c4[109]
assign ifu_genblk10_PCMReg_raw_internal[44] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_44_.Q; // c4[110]
assign ifu_genblk10_PCMReg_raw_internal[45] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_45_.Q; // c4[111]
assign ifu_genblk10_PCMReg_raw_internal[46] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_46_.Q; // c4[112]
assign ifu_genblk10_PCMReg_raw_internal[47] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_47_.Q; // c4[113]
assign ifu_genblk10_PCMReg_raw_internal[48] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_48_.Q; // c4[114]
assign ifu_genblk10_PCMReg_raw_internal[49] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_49_.Q; // c4[115]
assign ifu_genblk10_PCMReg_raw_internal[50] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_50_.Q; // c4[116]
assign ifu_genblk10_PCMReg_raw_internal[51] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_51_.Q; // c4[117]
assign ifu_genblk10_PCMReg_raw_internal[52] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_52_.Q; // c4[118]
assign ifu_genblk10_PCMReg_raw_internal[53] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_53_.Q; // c4[119]
assign ifu_genblk10_PCMReg_raw_internal[54] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_54_.Q; // c4[120]
assign ifu_genblk10_PCMReg_raw_internal[55] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_55_.Q; // c4[121]
assign ifu_genblk10_PCMReg_raw_internal[56] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_56_.Q; // c4[122]
assign ifu_genblk10_PCMReg_raw_internal[57] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_57_.Q; // c4[123]
assign ifu_genblk10_PCMReg_raw_internal[58] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_58_.Q; // c4[124]
assign ifu_genblk10_PCMReg_raw_internal[59] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_59_.Q; // c4[125]
assign ifu_genblk10_PCMReg_raw_internal[60] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_60_.Q; // c4[126]
assign ifu_genblk10_PCMReg_raw_internal[61] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_61_.Q; // c4[127]
assign ifu_genblk10_PCMReg_raw_internal[62] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_62_.Q; // c4[128]
assign ifu_genblk10_PCMReg_raw_internal[63] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_63_.Q; // c4[129]

// ---- ifu_genblk10_PCMReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ifu_genblk10_PCMReg_internal[0] = 1'bz; // unavailable logical estimate
assign ifu_genblk10_PCMReg_internal[1] = ifu_genblk10_PCMReg_raw_internal[1];
assign ifu_genblk10_PCMReg_internal[2] = ifu_genblk10_PCMReg_raw_internal[2];
assign ifu_genblk10_PCMReg_internal[3] = ifu_genblk10_PCMReg_raw_internal[3];
assign ifu_genblk10_PCMReg_internal[4] = ifu_genblk10_PCMReg_raw_internal[4];
assign ifu_genblk10_PCMReg_internal[5] = ifu_genblk10_PCMReg_raw_internal[5];
assign ifu_genblk10_PCMReg_internal[6] = ifu_genblk10_PCMReg_raw_internal[6];
assign ifu_genblk10_PCMReg_internal[7] = ifu_genblk10_PCMReg_raw_internal[7];
assign ifu_genblk10_PCMReg_internal[8] = ifu_genblk10_PCMReg_raw_internal[8];
assign ifu_genblk10_PCMReg_internal[9] = ifu_genblk10_PCMReg_raw_internal[9];
assign ifu_genblk10_PCMReg_internal[10] = ifu_genblk10_PCMReg_raw_internal[10];
assign ifu_genblk10_PCMReg_internal[11] = ifu_genblk10_PCMReg_raw_internal[11];
assign ifu_genblk10_PCMReg_internal[12] = ifu_genblk10_PCMReg_raw_internal[12];
assign ifu_genblk10_PCMReg_internal[13] = ifu_genblk10_PCMReg_raw_internal[13];
assign ifu_genblk10_PCMReg_internal[14] = ifu_genblk10_PCMReg_raw_internal[14];
assign ifu_genblk10_PCMReg_internal[15] = ifu_genblk10_PCMReg_raw_internal[15];
assign ifu_genblk10_PCMReg_internal[16] = ifu_genblk10_PCMReg_raw_internal[16];
assign ifu_genblk10_PCMReg_internal[17] = ifu_genblk10_PCMReg_raw_internal[17];
assign ifu_genblk10_PCMReg_internal[18] = ifu_genblk10_PCMReg_raw_internal[18];
assign ifu_genblk10_PCMReg_internal[19] = ifu_genblk10_PCMReg_raw_internal[19];
assign ifu_genblk10_PCMReg_internal[20] = ifu_genblk10_PCMReg_raw_internal[20];
assign ifu_genblk10_PCMReg_internal[21] = ifu_genblk10_PCMReg_raw_internal[21];
assign ifu_genblk10_PCMReg_internal[22] = ifu_genblk10_PCMReg_raw_internal[22];
assign ifu_genblk10_PCMReg_internal[23] = ifu_genblk10_PCMReg_raw_internal[23];
assign ifu_genblk10_PCMReg_internal[24] = ifu_genblk10_PCMReg_raw_internal[24];
assign ifu_genblk10_PCMReg_internal[25] = ifu_genblk10_PCMReg_raw_internal[25];
assign ifu_genblk10_PCMReg_internal[26] = ifu_genblk10_PCMReg_raw_internal[26];
assign ifu_genblk10_PCMReg_internal[27] = ifu_genblk10_PCMReg_raw_internal[27];
assign ifu_genblk10_PCMReg_internal[28] = ifu_genblk10_PCMReg_raw_internal[28];
assign ifu_genblk10_PCMReg_internal[29] = ifu_genblk10_PCMReg_raw_internal[29];
assign ifu_genblk10_PCMReg_internal[30] = ifu_genblk10_PCMReg_raw_internal[30];
assign ifu_genblk10_PCMReg_internal[31] = ifu_genblk10_PCMReg_raw_internal[31];
assign ifu_genblk10_PCMReg_internal[32] = ifu_genblk10_PCMReg_raw_internal[32];
assign ifu_genblk10_PCMReg_internal[33] = ifu_genblk10_PCMReg_raw_internal[33];
assign ifu_genblk10_PCMReg_internal[34] = ifu_genblk10_PCMReg_raw_internal[34];
assign ifu_genblk10_PCMReg_internal[35] = ifu_genblk10_PCMReg_raw_internal[35];
assign ifu_genblk10_PCMReg_internal[36] = ifu_genblk10_PCMReg_raw_internal[36];
assign ifu_genblk10_PCMReg_internal[37] = ifu_genblk10_PCMReg_raw_internal[37];
assign ifu_genblk10_PCMReg_internal[38] = ifu_genblk10_PCMReg_raw_internal[38];
assign ifu_genblk10_PCMReg_internal[39] = ifu_genblk10_PCMReg_raw_internal[39];
assign ifu_genblk10_PCMReg_internal[40] = ifu_genblk10_PCMReg_raw_internal[40];
assign ifu_genblk10_PCMReg_internal[41] = ifu_genblk10_PCMReg_raw_internal[41];
assign ifu_genblk10_PCMReg_internal[42] = ifu_genblk10_PCMReg_raw_internal[42];
assign ifu_genblk10_PCMReg_internal[43] = ifu_genblk10_PCMReg_raw_internal[43];
assign ifu_genblk10_PCMReg_internal[44] = ifu_genblk10_PCMReg_raw_internal[44];
assign ifu_genblk10_PCMReg_internal[45] = ifu_genblk10_PCMReg_raw_internal[45];
assign ifu_genblk10_PCMReg_internal[46] = ifu_genblk10_PCMReg_raw_internal[46];
assign ifu_genblk10_PCMReg_internal[47] = ifu_genblk10_PCMReg_raw_internal[47];
assign ifu_genblk10_PCMReg_internal[48] = ifu_genblk10_PCMReg_raw_internal[48];
assign ifu_genblk10_PCMReg_internal[49] = ifu_genblk10_PCMReg_raw_internal[49];
assign ifu_genblk10_PCMReg_internal[50] = ifu_genblk10_PCMReg_raw_internal[50];
assign ifu_genblk10_PCMReg_internal[51] = ifu_genblk10_PCMReg_raw_internal[51];
assign ifu_genblk10_PCMReg_internal[52] = ifu_genblk10_PCMReg_raw_internal[52];
assign ifu_genblk10_PCMReg_internal[53] = ifu_genblk10_PCMReg_raw_internal[53];
assign ifu_genblk10_PCMReg_internal[54] = ifu_genblk10_PCMReg_raw_internal[54];
assign ifu_genblk10_PCMReg_internal[55] = ifu_genblk10_PCMReg_raw_internal[55];
assign ifu_genblk10_PCMReg_internal[56] = ifu_genblk10_PCMReg_raw_internal[56];
assign ifu_genblk10_PCMReg_internal[57] = ifu_genblk10_PCMReg_raw_internal[57];
assign ifu_genblk10_PCMReg_internal[58] = ifu_genblk10_PCMReg_raw_internal[58];
assign ifu_genblk10_PCMReg_internal[59] = ifu_genblk10_PCMReg_raw_internal[59];
assign ifu_genblk10_PCMReg_internal[60] = ifu_genblk10_PCMReg_raw_internal[60];
assign ifu_genblk10_PCMReg_internal[61] = ifu_genblk10_PCMReg_raw_internal[61];
assign ifu_genblk10_PCMReg_internal[62] = ifu_genblk10_PCMReg_raw_internal[62];
assign ifu_genblk10_PCMReg_internal[63] = ifu_genblk10_PCMReg_raw_internal[63];

// ---- ifu_genblk10_PCMReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ifu_genblk10_PCMReg_pin_internal[0] = 1'bz; // unavailable scan pin
assign ifu_genblk10_PCMReg_pin_internal[1] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_1_.Q;
assign ifu_genblk10_PCMReg_pin_internal[2] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_2_.Q;
assign ifu_genblk10_PCMReg_pin_internal[3] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_3_.Q;
assign ifu_genblk10_PCMReg_pin_internal[4] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_4_.Q;
assign ifu_genblk10_PCMReg_pin_internal[5] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_5_.Q;
assign ifu_genblk10_PCMReg_pin_internal[6] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_6_.Q;
assign ifu_genblk10_PCMReg_pin_internal[7] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_7_.Q;
assign ifu_genblk10_PCMReg_pin_internal[8] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_8_.Q;
assign ifu_genblk10_PCMReg_pin_internal[9] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_9_.Q;
assign ifu_genblk10_PCMReg_pin_internal[10] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_10_.Q;
assign ifu_genblk10_PCMReg_pin_internal[11] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_11_.Q;
assign ifu_genblk10_PCMReg_pin_internal[12] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_12_.Q;
assign ifu_genblk10_PCMReg_pin_internal[13] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_13_.Q;
assign ifu_genblk10_PCMReg_pin_internal[14] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_14_.Q;
assign ifu_genblk10_PCMReg_pin_internal[15] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_15_.Q;
assign ifu_genblk10_PCMReg_pin_internal[16] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_16_.Q;
assign ifu_genblk10_PCMReg_pin_internal[17] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_17_.Q;
assign ifu_genblk10_PCMReg_pin_internal[18] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_18_.Q;
assign ifu_genblk10_PCMReg_pin_internal[19] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_19_.Q;
assign ifu_genblk10_PCMReg_pin_internal[20] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_20_.Q;
assign ifu_genblk10_PCMReg_pin_internal[21] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_21_.Q;
assign ifu_genblk10_PCMReg_pin_internal[22] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_22_.Q;
assign ifu_genblk10_PCMReg_pin_internal[23] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_23_.Q;
assign ifu_genblk10_PCMReg_pin_internal[24] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_24_.Q;
assign ifu_genblk10_PCMReg_pin_internal[25] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_25_.Q;
assign ifu_genblk10_PCMReg_pin_internal[26] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_26_.Q;
assign ifu_genblk10_PCMReg_pin_internal[27] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_27_.Q;
assign ifu_genblk10_PCMReg_pin_internal[28] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_28_.Q;
assign ifu_genblk10_PCMReg_pin_internal[29] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_29_.Q;
assign ifu_genblk10_PCMReg_pin_internal[30] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_30_.Q;
assign ifu_genblk10_PCMReg_pin_internal[31] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_31_.Q;
assign ifu_genblk10_PCMReg_pin_internal[32] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_32_.Q;
assign ifu_genblk10_PCMReg_pin_internal[33] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_33_.Q;
assign ifu_genblk10_PCMReg_pin_internal[34] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_34_.Q;
assign ifu_genblk10_PCMReg_pin_internal[35] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_35_.Q;
assign ifu_genblk10_PCMReg_pin_internal[36] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_36_.Q;
assign ifu_genblk10_PCMReg_pin_internal[37] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_37_.Q;
assign ifu_genblk10_PCMReg_pin_internal[38] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_38_.Q;
assign ifu_genblk10_PCMReg_pin_internal[39] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_39_.Q;
assign ifu_genblk10_PCMReg_pin_internal[40] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_40_.Q;
assign ifu_genblk10_PCMReg_pin_internal[41] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_41_.Q;
assign ifu_genblk10_PCMReg_pin_internal[42] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_42_.Q;
assign ifu_genblk10_PCMReg_pin_internal[43] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_43_.Q;
assign ifu_genblk10_PCMReg_pin_internal[44] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_44_.Q;
assign ifu_genblk10_PCMReg_pin_internal[45] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_45_.Q;
assign ifu_genblk10_PCMReg_pin_internal[46] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_46_.Q;
assign ifu_genblk10_PCMReg_pin_internal[47] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_47_.Q;
assign ifu_genblk10_PCMReg_pin_internal[48] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_48_.Q;
assign ifu_genblk10_PCMReg_pin_internal[49] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_49_.Q;
assign ifu_genblk10_PCMReg_pin_internal[50] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_50_.Q;
assign ifu_genblk10_PCMReg_pin_internal[51] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_51_.Q;
assign ifu_genblk10_PCMReg_pin_internal[52] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_52_.Q;
assign ifu_genblk10_PCMReg_pin_internal[53] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_53_.Q;
assign ifu_genblk10_PCMReg_pin_internal[54] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_54_.Q;
assign ifu_genblk10_PCMReg_pin_internal[55] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_55_.Q;
assign ifu_genblk10_PCMReg_pin_internal[56] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_56_.Q;
assign ifu_genblk10_PCMReg_pin_internal[57] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_57_.Q;
assign ifu_genblk10_PCMReg_pin_internal[58] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_58_.Q;
assign ifu_genblk10_PCMReg_pin_internal[59] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_59_.Q;
assign ifu_genblk10_PCMReg_pin_internal[60] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_60_.Q;
assign ifu_genblk10_PCMReg_pin_internal[61] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_61_.Q;
assign ifu_genblk10_PCMReg_pin_internal[62] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_62_.Q;
assign ifu_genblk10_PCMReg_pin_internal[63] = dut.chip.soc_core_ifu_genblk10_PCMReg_q_reg_63_.Q;

// ---- ifu_genblk10_PCMReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ifu_genblk10_PCMReg_raw_internal_available[0] = 1'b0;
assign ifu_genblk10_PCMReg_raw_internal_available[1] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[2] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[3] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[4] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[5] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[6] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[7] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[8] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[9] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[10] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[11] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[12] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[13] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[14] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[15] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[16] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[17] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[18] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[19] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[20] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[21] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[22] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[23] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[24] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[25] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[26] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[27] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[28] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[29] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[30] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[31] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[32] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[33] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[34] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[35] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[36] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[37] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[38] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[39] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[40] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[41] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[42] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[43] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[44] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[45] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[46] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[47] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[48] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[49] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[50] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[51] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[52] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[53] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[54] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[55] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[56] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[57] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[58] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[59] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[60] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[61] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[62] = 1'b1;
assign ifu_genblk10_PCMReg_raw_internal_available[63] = 1'b1;

// ============================================================================
// Register ifu_genblk11_CompressedDReg: 1 mapped bits, width 1
// ============================================================================

// Bus declarations
wire [0:0] ifu_genblk11_CompressedDReg_internal;
wire [0:0] ifu_genblk11_CompressedDReg_raw_internal;
wire [0:0] ifu_genblk11_CompressedDReg_pin_internal;
wire [0:0] ifu_genblk11_CompressedDReg_raw_internal_available;

// ---- ifu_genblk11_CompressedDReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ifu_genblk11_CompressedDReg_raw_internal[0] = dut.chip.soc_core_ifu_genblk11_CompressedDReg_q_reg_0_.Q; // c4[130]

// ---- ifu_genblk11_CompressedDReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ifu_genblk11_CompressedDReg_internal[0] = ifu_genblk11_CompressedDReg_raw_internal[0];

// ---- ifu_genblk11_CompressedDReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ifu_genblk11_CompressedDReg_pin_internal[0] = dut.chip.soc_core_ifu_genblk11_CompressedDReg_q_reg_0_.Q;

// ---- ifu_genblk11_CompressedDReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ifu_genblk11_CompressedDReg_raw_internal_available[0] = 1'b1;

// ============================================================================
// Register ifu_genblk11_CompressedEReg: 1 mapped bits, width 1
// ============================================================================

// Bus declarations
wire [0:0] ifu_genblk11_CompressedEReg_internal;
wire [0:0] ifu_genblk11_CompressedEReg_raw_internal;
wire [0:0] ifu_genblk11_CompressedEReg_pin_internal;
wire [0:0] ifu_genblk11_CompressedEReg_raw_internal_available;

// ---- ifu_genblk11_CompressedEReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ifu_genblk11_CompressedEReg_raw_internal[0] = dut.chip.soc_core_ifu_genblk11_CompressedEReg_q_reg_0_.Q; // c4[131]

// ---- ifu_genblk11_CompressedEReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ifu_genblk11_CompressedEReg_internal[0] = ifu_genblk11_CompressedEReg_raw_internal[0];

// ---- ifu_genblk11_CompressedEReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ifu_genblk11_CompressedEReg_pin_internal[0] = dut.chip.soc_core_ifu_genblk11_CompressedEReg_q_reg_0_.Q;

// ---- ifu_genblk11_CompressedEReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ifu_genblk11_CompressedEReg_raw_internal_available[0] = 1'b1;

// ============================================================================
// Register ifu_genblk12_CompressedMReg: 1 mapped bits, width 1
// ============================================================================

// Bus declarations
wire [0:0] ifu_genblk12_CompressedMReg_internal;
wire [0:0] ifu_genblk12_CompressedMReg_raw_internal;
wire [0:0] ifu_genblk12_CompressedMReg_pin_internal;
wire [0:0] ifu_genblk12_CompressedMReg_raw_internal_available;

// ---- ifu_genblk12_CompressedMReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ifu_genblk12_CompressedMReg_raw_internal[0] = dut.chip.soc_core_ifu_genblk12_CompressedMReg_q_reg_0_.Q; // c4[132]

// ---- ifu_genblk12_CompressedMReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ifu_genblk12_CompressedMReg_internal[0] = ifu_genblk12_CompressedMReg_raw_internal[0];

// ---- ifu_genblk12_CompressedMReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ifu_genblk12_CompressedMReg_pin_internal[0] = dut.chip.soc_core_ifu_genblk12_CompressedMReg_q_reg_0_.Q;

// ---- ifu_genblk12_CompressedMReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ifu_genblk12_CompressedMReg_raw_internal_available[0] = 1'b1;

// ============================================================================
// Register ifu_genblk12_InstrRawEReg: 16 mapped bits, width 16
// ============================================================================

// Bus declarations
wire [15:0] ifu_genblk12_InstrRawEReg_internal;
wire [15:0] ifu_genblk12_InstrRawEReg_raw_internal;
wire [15:0] ifu_genblk12_InstrRawEReg_pin_internal;
wire [15:0] ifu_genblk12_InstrRawEReg_raw_internal_available;

// ---- ifu_genblk12_InstrRawEReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ifu_genblk12_InstrRawEReg_raw_internal[0] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_0_.Q; // c4[133]
assign ifu_genblk12_InstrRawEReg_raw_internal[1] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_1_.Q; // c4[134]
assign ifu_genblk12_InstrRawEReg_raw_internal[2] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_2_.Q; // c4[135]
assign ifu_genblk12_InstrRawEReg_raw_internal[3] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_3_.Q; // c4[136]
assign ifu_genblk12_InstrRawEReg_raw_internal[4] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_4_.Q; // c4[137]
assign ifu_genblk12_InstrRawEReg_raw_internal[5] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_5_.Q; // c4[138]
assign ifu_genblk12_InstrRawEReg_raw_internal[6] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_6_.Q; // c4[139]
assign ifu_genblk12_InstrRawEReg_raw_internal[7] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_7_.Q; // c4[140]
assign ifu_genblk12_InstrRawEReg_raw_internal[8] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_8_.Q; // c4[141]
assign ifu_genblk12_InstrRawEReg_raw_internal[9] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_9_.Q; // c4[142]
assign ifu_genblk12_InstrRawEReg_raw_internal[10] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_10_.Q; // c4[143]
assign ifu_genblk12_InstrRawEReg_raw_internal[11] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_11_.Q; // c4[144]
assign ifu_genblk12_InstrRawEReg_raw_internal[12] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_12_.Q; // c4[145]
assign ifu_genblk12_InstrRawEReg_raw_internal[13] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_13_.Q; // c4[146]
assign ifu_genblk12_InstrRawEReg_raw_internal[14] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_14_.Q; // c4[147]
assign ifu_genblk12_InstrRawEReg_raw_internal[15] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_15_.Q; // c4[148]

// ---- ifu_genblk12_InstrRawEReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ifu_genblk12_InstrRawEReg_internal[0] = ifu_genblk12_InstrRawEReg_raw_internal[0];
assign ifu_genblk12_InstrRawEReg_internal[1] = ifu_genblk12_InstrRawEReg_raw_internal[1];
assign ifu_genblk12_InstrRawEReg_internal[2] = ifu_genblk12_InstrRawEReg_raw_internal[2];
assign ifu_genblk12_InstrRawEReg_internal[3] = ifu_genblk12_InstrRawEReg_raw_internal[3];
assign ifu_genblk12_InstrRawEReg_internal[4] = ifu_genblk12_InstrRawEReg_raw_internal[4];
assign ifu_genblk12_InstrRawEReg_internal[5] = ifu_genblk12_InstrRawEReg_raw_internal[5];
assign ifu_genblk12_InstrRawEReg_internal[6] = ifu_genblk12_InstrRawEReg_raw_internal[6];
assign ifu_genblk12_InstrRawEReg_internal[7] = ifu_genblk12_InstrRawEReg_raw_internal[7];
assign ifu_genblk12_InstrRawEReg_internal[8] = ifu_genblk12_InstrRawEReg_raw_internal[8];
assign ifu_genblk12_InstrRawEReg_internal[9] = ifu_genblk12_InstrRawEReg_raw_internal[9];
assign ifu_genblk12_InstrRawEReg_internal[10] = ifu_genblk12_InstrRawEReg_raw_internal[10];
assign ifu_genblk12_InstrRawEReg_internal[11] = ifu_genblk12_InstrRawEReg_raw_internal[11];
assign ifu_genblk12_InstrRawEReg_internal[12] = ifu_genblk12_InstrRawEReg_raw_internal[12];
assign ifu_genblk12_InstrRawEReg_internal[13] = ifu_genblk12_InstrRawEReg_raw_internal[13];
assign ifu_genblk12_InstrRawEReg_internal[14] = ifu_genblk12_InstrRawEReg_raw_internal[14];
assign ifu_genblk12_InstrRawEReg_internal[15] = ifu_genblk12_InstrRawEReg_raw_internal[15];

// ---- ifu_genblk12_InstrRawEReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ifu_genblk12_InstrRawEReg_pin_internal[0] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_0_.Q;
assign ifu_genblk12_InstrRawEReg_pin_internal[1] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_1_.Q;
assign ifu_genblk12_InstrRawEReg_pin_internal[2] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_2_.Q;
assign ifu_genblk12_InstrRawEReg_pin_internal[3] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_3_.Q;
assign ifu_genblk12_InstrRawEReg_pin_internal[4] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_4_.Q;
assign ifu_genblk12_InstrRawEReg_pin_internal[5] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_5_.Q;
assign ifu_genblk12_InstrRawEReg_pin_internal[6] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_6_.Q;
assign ifu_genblk12_InstrRawEReg_pin_internal[7] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_7_.Q;
assign ifu_genblk12_InstrRawEReg_pin_internal[8] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_8_.Q;
assign ifu_genblk12_InstrRawEReg_pin_internal[9] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_9_.Q;
assign ifu_genblk12_InstrRawEReg_pin_internal[10] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_10_.Q;
assign ifu_genblk12_InstrRawEReg_pin_internal[11] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_11_.Q;
assign ifu_genblk12_InstrRawEReg_pin_internal[12] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_12_.Q;
assign ifu_genblk12_InstrRawEReg_pin_internal[13] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_13_.Q;
assign ifu_genblk12_InstrRawEReg_pin_internal[14] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_14_.Q;
assign ifu_genblk12_InstrRawEReg_pin_internal[15] = dut.chip.soc_core_ifu_genblk12_InstrRawEReg_q_reg_15_.Q;

// ---- ifu_genblk12_InstrRawEReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ifu_genblk12_InstrRawEReg_raw_internal_available[0] = 1'b1;
assign ifu_genblk12_InstrRawEReg_raw_internal_available[1] = 1'b1;
assign ifu_genblk12_InstrRawEReg_raw_internal_available[2] = 1'b1;
assign ifu_genblk12_InstrRawEReg_raw_internal_available[3] = 1'b1;
assign ifu_genblk12_InstrRawEReg_raw_internal_available[4] = 1'b1;
assign ifu_genblk12_InstrRawEReg_raw_internal_available[5] = 1'b1;
assign ifu_genblk12_InstrRawEReg_raw_internal_available[6] = 1'b1;
assign ifu_genblk12_InstrRawEReg_raw_internal_available[7] = 1'b1;
assign ifu_genblk12_InstrRawEReg_raw_internal_available[8] = 1'b1;
assign ifu_genblk12_InstrRawEReg_raw_internal_available[9] = 1'b1;
assign ifu_genblk12_InstrRawEReg_raw_internal_available[10] = 1'b1;
assign ifu_genblk12_InstrRawEReg_raw_internal_available[11] = 1'b1;
assign ifu_genblk12_InstrRawEReg_raw_internal_available[12] = 1'b1;
assign ifu_genblk12_InstrRawEReg_raw_internal_available[13] = 1'b1;
assign ifu_genblk12_InstrRawEReg_raw_internal_available[14] = 1'b1;
assign ifu_genblk12_InstrRawEReg_raw_internal_available[15] = 1'b1;

// ============================================================================
// Register ifu_genblk12_InstrRawMReg: 16 mapped bits, width 16
// ============================================================================

// Bus declarations
wire [15:0] ifu_genblk12_InstrRawMReg_internal;
wire [15:0] ifu_genblk12_InstrRawMReg_raw_internal;
wire [15:0] ifu_genblk12_InstrRawMReg_pin_internal;
wire [15:0] ifu_genblk12_InstrRawMReg_raw_internal_available;

// ---- ifu_genblk12_InstrRawMReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign ifu_genblk12_InstrRawMReg_raw_internal[0] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_0_.Q; // c4[149]
assign ifu_genblk12_InstrRawMReg_raw_internal[1] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_1_.Q; // c4[150]
assign ifu_genblk12_InstrRawMReg_raw_internal[2] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_2_.Q; // c4[151]
assign ifu_genblk12_InstrRawMReg_raw_internal[3] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_3_.Q; // c4[152]
assign ifu_genblk12_InstrRawMReg_raw_internal[4] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_4_.Q; // c4[153]
assign ifu_genblk12_InstrRawMReg_raw_internal[5] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_5_.Q; // c4[154]
assign ifu_genblk12_InstrRawMReg_raw_internal[6] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_6_.Q; // c4[155]
assign ifu_genblk12_InstrRawMReg_raw_internal[7] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_7_.Q; // c4[156]
assign ifu_genblk12_InstrRawMReg_raw_internal[8] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_8_.Q; // c4[157]
assign ifu_genblk12_InstrRawMReg_raw_internal[9] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_9_.Q; // c4[158]
assign ifu_genblk12_InstrRawMReg_raw_internal[10] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_10_.Q; // c4[159]
assign ifu_genblk12_InstrRawMReg_raw_internal[11] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_11_.Q; // c4[160]
assign ifu_genblk12_InstrRawMReg_raw_internal[12] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_12_.Q; // c4[161]
assign ifu_genblk12_InstrRawMReg_raw_internal[13] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_13_.Q; // c4[162]
assign ifu_genblk12_InstrRawMReg_raw_internal[14] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_14_.Q; // c4[163]
assign ifu_genblk12_InstrRawMReg_raw_internal[15] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_15_.Q; // c4[164]

// ---- ifu_genblk12_InstrRawMReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign ifu_genblk12_InstrRawMReg_internal[0] = ifu_genblk12_InstrRawMReg_raw_internal[0];
assign ifu_genblk12_InstrRawMReg_internal[1] = ifu_genblk12_InstrRawMReg_raw_internal[1];
assign ifu_genblk12_InstrRawMReg_internal[2] = ifu_genblk12_InstrRawMReg_raw_internal[2];
assign ifu_genblk12_InstrRawMReg_internal[3] = ifu_genblk12_InstrRawMReg_raw_internal[3];
assign ifu_genblk12_InstrRawMReg_internal[4] = ifu_genblk12_InstrRawMReg_raw_internal[4];
assign ifu_genblk12_InstrRawMReg_internal[5] = ifu_genblk12_InstrRawMReg_raw_internal[5];
assign ifu_genblk12_InstrRawMReg_internal[6] = ifu_genblk12_InstrRawMReg_raw_internal[6];
assign ifu_genblk12_InstrRawMReg_internal[7] = ifu_genblk12_InstrRawMReg_raw_internal[7];
assign ifu_genblk12_InstrRawMReg_internal[8] = ifu_genblk12_InstrRawMReg_raw_internal[8];
assign ifu_genblk12_InstrRawMReg_internal[9] = ifu_genblk12_InstrRawMReg_raw_internal[9];
assign ifu_genblk12_InstrRawMReg_internal[10] = ifu_genblk12_InstrRawMReg_raw_internal[10];
assign ifu_genblk12_InstrRawMReg_internal[11] = ifu_genblk12_InstrRawMReg_raw_internal[11];
assign ifu_genblk12_InstrRawMReg_internal[12] = ifu_genblk12_InstrRawMReg_raw_internal[12];
assign ifu_genblk12_InstrRawMReg_internal[13] = ifu_genblk12_InstrRawMReg_raw_internal[13];
assign ifu_genblk12_InstrRawMReg_internal[14] = ifu_genblk12_InstrRawMReg_raw_internal[14];
assign ifu_genblk12_InstrRawMReg_internal[15] = ifu_genblk12_InstrRawMReg_raw_internal[15];

// ---- ifu_genblk12_InstrRawMReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign ifu_genblk12_InstrRawMReg_pin_internal[0] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_0_.Q;
assign ifu_genblk12_InstrRawMReg_pin_internal[1] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_1_.Q;
assign ifu_genblk12_InstrRawMReg_pin_internal[2] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_2_.Q;
assign ifu_genblk12_InstrRawMReg_pin_internal[3] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_3_.Q;
assign ifu_genblk12_InstrRawMReg_pin_internal[4] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_4_.Q;
assign ifu_genblk12_InstrRawMReg_pin_internal[5] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_5_.Q;
assign ifu_genblk12_InstrRawMReg_pin_internal[6] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_6_.Q;
assign ifu_genblk12_InstrRawMReg_pin_internal[7] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_7_.Q;
assign ifu_genblk12_InstrRawMReg_pin_internal[8] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_8_.Q;
assign ifu_genblk12_InstrRawMReg_pin_internal[9] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_9_.Q;
assign ifu_genblk12_InstrRawMReg_pin_internal[10] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_10_.Q;
assign ifu_genblk12_InstrRawMReg_pin_internal[11] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_11_.Q;
assign ifu_genblk12_InstrRawMReg_pin_internal[12] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_12_.Q;
assign ifu_genblk12_InstrRawMReg_pin_internal[13] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_13_.Q;
assign ifu_genblk12_InstrRawMReg_pin_internal[14] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_14_.Q;
assign ifu_genblk12_InstrRawMReg_pin_internal[15] = dut.chip.soc_core_ifu_genblk12_InstrRawMReg_q_reg_15_.Q;

// ---- ifu_genblk12_InstrRawMReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign ifu_genblk12_InstrRawMReg_raw_internal_available[0] = 1'b1;
assign ifu_genblk12_InstrRawMReg_raw_internal_available[1] = 1'b1;
assign ifu_genblk12_InstrRawMReg_raw_internal_available[2] = 1'b1;
assign ifu_genblk12_InstrRawMReg_raw_internal_available[3] = 1'b1;
assign ifu_genblk12_InstrRawMReg_raw_internal_available[4] = 1'b1;
assign ifu_genblk12_InstrRawMReg_raw_internal_available[5] = 1'b1;
assign ifu_genblk12_InstrRawMReg_raw_internal_available[6] = 1'b1;
assign ifu_genblk12_InstrRawMReg_raw_internal_available[7] = 1'b1;
assign ifu_genblk12_InstrRawMReg_raw_internal_available[8] = 1'b1;
assign ifu_genblk12_InstrRawMReg_raw_internal_available[9] = 1'b1;
assign ifu_genblk12_InstrRawMReg_raw_internal_available[10] = 1'b1;
assign ifu_genblk12_InstrRawMReg_raw_internal_available[11] = 1'b1;
assign ifu_genblk12_InstrRawMReg_raw_internal_available[12] = 1'b1;
assign ifu_genblk12_InstrRawMReg_raw_internal_available[13] = 1'b1;
assign ifu_genblk12_InstrRawMReg_raw_internal_available[14] = 1'b1;
assign ifu_genblk12_InstrRawMReg_raw_internal_available[15] = 1'b1;

// ============================================================================
// Register ifu_pcreg: 63 mapped bits, width 64
// ============================================================================

// Bus declarations
wire [63:0] pc_internal;
wire [63:0] pc_raw_internal;
wire [63:0] pc_pin_internal;
wire [63:0] pc_raw_internal_available;

// ---- pc_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign pc_raw_internal[0] = 1'bz; // unavailable physical Q
assign pc_raw_internal[1] = ~dut.chip.soc_core_ifu_pcreg_q_reg_1_.QN; // c4[165]
assign pc_raw_internal[2] = dut.chip.soc_core_ifu_pcreg_q_reg_2_.Q; // c4[166]
assign pc_raw_internal[3] = dut.chip.soc_core_ifu_pcreg_q_reg_3_.Q; // c4[167]
assign pc_raw_internal[4] = dut.chip.soc_core_ifu_pcreg_q_reg_4_.Q; // c4[168]
assign pc_raw_internal[5] = dut.chip.soc_core_ifu_pcreg_q_reg_5_.Q; // c4[169]
assign pc_raw_internal[6] = dut.chip.soc_core_ifu_pcreg_q_reg_6_.Q; // c4[170]
assign pc_raw_internal[7] = dut.chip.soc_core_ifu_pcreg_q_reg_7_.Q; // c4[171]
assign pc_raw_internal[8] = dut.chip.soc_core_ifu_pcreg_q_reg_8_.Q; // c4[172]
assign pc_raw_internal[9] = dut.chip.soc_core_ifu_pcreg_q_reg_9_.Q; // c4[173]
assign pc_raw_internal[10] = dut.chip.soc_core_ifu_pcreg_q_reg_10_.Q; // c4[174]
assign pc_raw_internal[11] = dut.chip.soc_core_ifu_pcreg_q_reg_11_.Q; // c4[175]
assign pc_raw_internal[12] = dut.chip.soc_core_ifu_pcreg_q_reg_12_.Q; // c4[176]
assign pc_raw_internal[13] = dut.chip.soc_core_ifu_pcreg_q_reg_13_.Q; // c4[177]
assign pc_raw_internal[14] = dut.chip.soc_core_ifu_pcreg_q_reg_14_.Q; // c4[178]
assign pc_raw_internal[15] = dut.chip.soc_core_ifu_pcreg_q_reg_15_.Q; // c4[179]
assign pc_raw_internal[16] = dut.chip.soc_core_ifu_pcreg_q_reg_16_.Q; // c4[180]
assign pc_raw_internal[17] = dut.chip.soc_core_ifu_pcreg_q_reg_17_.Q; // c4[181]
assign pc_raw_internal[18] = dut.chip.soc_core_ifu_pcreg_q_reg_18_.Q; // c4[182]
assign pc_raw_internal[19] = dut.chip.soc_core_ifu_pcreg_q_reg_19_.Q; // c4[183]
assign pc_raw_internal[20] = dut.chip.soc_core_ifu_pcreg_q_reg_20_.Q; // c4[184]
assign pc_raw_internal[21] = dut.chip.soc_core_ifu_pcreg_q_reg_21_.Q; // c4[185]
assign pc_raw_internal[22] = dut.chip.soc_core_ifu_pcreg_q_reg_22_.Q; // c4[186]
assign pc_raw_internal[23] = dut.chip.soc_core_ifu_pcreg_q_reg_23_.Q; // c5[1]
assign pc_raw_internal[24] = dut.chip.soc_core_ifu_pcreg_q_reg_24_.Q; // c5[2]
assign pc_raw_internal[25] = dut.chip.soc_core_ifu_pcreg_q_reg_25_.Q; // c5[3]
assign pc_raw_internal[26] = dut.chip.soc_core_ifu_pcreg_q_reg_26_.Q; // c5[4]
assign pc_raw_internal[27] = dut.chip.soc_core_ifu_pcreg_q_reg_27_.Q; // c5[5]
assign pc_raw_internal[28] = dut.chip.soc_core_ifu_pcreg_q_reg_28_.Q; // c5[6]
assign pc_raw_internal[29] = dut.chip.soc_core_ifu_pcreg_q_reg_29_.Q; // c5[7]
assign pc_raw_internal[30] = dut.chip.soc_core_ifu_pcreg_q_reg_30_.Q; // c5[8]
assign pc_raw_internal[31] = dut.chip.soc_core_ifu_pcreg_q_reg_31_.Q; // c5[9]
assign pc_raw_internal[32] = dut.chip.soc_core_ifu_pcreg_q_reg_32_.Q; // c5[10]
assign pc_raw_internal[33] = dut.chip.soc_core_ifu_pcreg_q_reg_33_.Q; // c5[11]
assign pc_raw_internal[34] = dut.chip.soc_core_ifu_pcreg_q_reg_34_.Q; // c5[12]
assign pc_raw_internal[35] = dut.chip.soc_core_ifu_pcreg_q_reg_35_.Q; // c5[13]
assign pc_raw_internal[36] = dut.chip.soc_core_ifu_pcreg_q_reg_36_.Q; // c5[14]
assign pc_raw_internal[37] = dut.chip.soc_core_ifu_pcreg_q_reg_37_.Q; // c5[15]
assign pc_raw_internal[38] = dut.chip.soc_core_ifu_pcreg_q_reg_38_.Q; // c5[16]
assign pc_raw_internal[39] = dut.chip.soc_core_ifu_pcreg_q_reg_39_.Q; // c5[17]
assign pc_raw_internal[40] = dut.chip.soc_core_ifu_pcreg_q_reg_40_.Q; // c5[18]
assign pc_raw_internal[41] = dut.chip.soc_core_ifu_pcreg_q_reg_41_.Q; // c5[19]
assign pc_raw_internal[42] = dut.chip.soc_core_ifu_pcreg_q_reg_42_.Q; // c5[20]
assign pc_raw_internal[43] = dut.chip.soc_core_ifu_pcreg_q_reg_43_.Q; // c5[21]
assign pc_raw_internal[44] = dut.chip.soc_core_ifu_pcreg_q_reg_44_.Q; // c5[22]
assign pc_raw_internal[45] = dut.chip.soc_core_ifu_pcreg_q_reg_45_.Q; // c5[23]
assign pc_raw_internal[46] = dut.chip.soc_core_ifu_pcreg_q_reg_46_.Q; // c5[24]
assign pc_raw_internal[47] = dut.chip.soc_core_ifu_pcreg_q_reg_47_.Q; // c5[25]
assign pc_raw_internal[48] = dut.chip.soc_core_ifu_pcreg_q_reg_48_.Q; // c5[26]
assign pc_raw_internal[49] = dut.chip.soc_core_ifu_pcreg_q_reg_49_.Q; // c5[27]
assign pc_raw_internal[50] = dut.chip.soc_core_ifu_pcreg_q_reg_50_.Q; // c5[28]
assign pc_raw_internal[51] = dut.chip.soc_core_ifu_pcreg_q_reg_51_.Q; // c5[29]
assign pc_raw_internal[52] = dut.chip.soc_core_ifu_pcreg_q_reg_52_.Q; // c5[30]
assign pc_raw_internal[53] = dut.chip.soc_core_ifu_pcreg_q_reg_53_.Q; // c5[31]
assign pc_raw_internal[54] = dut.chip.soc_core_ifu_pcreg_q_reg_54_.Q; // c5[32]
assign pc_raw_internal[55] = dut.chip.soc_core_ifu_pcreg_q_reg_55_.Q; // c5[33]
assign pc_raw_internal[56] = dut.chip.soc_core_ifu_pcreg_q_reg_56_.Q; // c5[34]
assign pc_raw_internal[57] = ~dut.chip.soc_core_ifu_pcreg_q_reg_57_.QN; // c5[35]
assign pc_raw_internal[58] = ~dut.chip.soc_core_ifu_pcreg_q_reg_58_.QN; // c5[36]
assign pc_raw_internal[59] = ~dut.chip.soc_core_ifu_pcreg_q_reg_59_.QN; // c5[37]
assign pc_raw_internal[60] = ~dut.chip.soc_core_ifu_pcreg_q_reg_60_.QN; // c5[38]
assign pc_raw_internal[61] = ~dut.chip.soc_core_ifu_pcreg_q_reg_61_.QN; // c5[39]
assign pc_raw_internal[62] = ~dut.chip.soc_core_ifu_pcreg_q_reg_62_.QN; // c5[40]
assign pc_raw_internal[63] = ~dut.chip.soc_core_ifu_pcreg_q_reg_63_.QN; // c5[41]

// ---- pc_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign pc_internal[0] = 1'bz; // unavailable logical estimate
assign pc_internal[1] = pc_raw_internal[1];
assign pc_internal[2] = pc_raw_internal[2];
assign pc_internal[3] = pc_raw_internal[3];
assign pc_internal[4] = pc_raw_internal[4];
assign pc_internal[5] = pc_raw_internal[5];
assign pc_internal[6] = pc_raw_internal[6];
assign pc_internal[7] = pc_raw_internal[7];
assign pc_internal[8] = pc_raw_internal[8];
assign pc_internal[9] = pc_raw_internal[9];
assign pc_internal[10] = pc_raw_internal[10];
assign pc_internal[11] = pc_raw_internal[11];
assign pc_internal[12] = pc_raw_internal[12];
assign pc_internal[13] = pc_raw_internal[13];
assign pc_internal[14] = pc_raw_internal[14];
assign pc_internal[15] = pc_raw_internal[15];
assign pc_internal[16] = pc_raw_internal[16];
assign pc_internal[17] = pc_raw_internal[17];
assign pc_internal[18] = pc_raw_internal[18];
assign pc_internal[19] = pc_raw_internal[19];
assign pc_internal[20] = pc_raw_internal[20];
assign pc_internal[21] = pc_raw_internal[21];
assign pc_internal[22] = pc_raw_internal[22];
assign pc_internal[23] = pc_raw_internal[23];
assign pc_internal[24] = pc_raw_internal[24];
assign pc_internal[25] = pc_raw_internal[25];
assign pc_internal[26] = pc_raw_internal[26];
assign pc_internal[27] = pc_raw_internal[27];
assign pc_internal[28] = pc_raw_internal[28];
assign pc_internal[29] = pc_raw_internal[29];
assign pc_internal[30] = pc_raw_internal[30];
assign pc_internal[31] = pc_raw_internal[31];
assign pc_internal[32] = pc_raw_internal[32];
assign pc_internal[33] = pc_raw_internal[33];
assign pc_internal[34] = pc_raw_internal[34];
assign pc_internal[35] = pc_raw_internal[35];
assign pc_internal[36] = pc_raw_internal[36];
assign pc_internal[37] = pc_raw_internal[37];
assign pc_internal[38] = pc_raw_internal[38];
assign pc_internal[39] = pc_raw_internal[39];
assign pc_internal[40] = pc_raw_internal[40];
assign pc_internal[41] = pc_raw_internal[41];
assign pc_internal[42] = pc_raw_internal[42];
assign pc_internal[43] = pc_raw_internal[43];
assign pc_internal[44] = pc_raw_internal[44];
assign pc_internal[45] = pc_raw_internal[45];
assign pc_internal[46] = pc_raw_internal[46];
assign pc_internal[47] = pc_raw_internal[47];
assign pc_internal[48] = pc_raw_internal[48];
assign pc_internal[49] = pc_raw_internal[49];
assign pc_internal[50] = pc_raw_internal[50];
assign pc_internal[51] = pc_raw_internal[51];
assign pc_internal[52] = pc_raw_internal[52];
assign pc_internal[53] = pc_raw_internal[53];
assign pc_internal[54] = pc_raw_internal[54];
assign pc_internal[55] = pc_raw_internal[55];
assign pc_internal[56] = pc_raw_internal[56];
assign pc_internal[57] = pc_raw_internal[57];
assign pc_internal[58] = pc_raw_internal[58];
assign pc_internal[59] = pc_raw_internal[59];
assign pc_internal[60] = pc_raw_internal[60];
assign pc_internal[61] = pc_raw_internal[61];
assign pc_internal[62] = pc_raw_internal[62];
assign pc_internal[63] = pc_raw_internal[63];

// ---- pc_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign pc_pin_internal[0] = 1'bz; // unavailable scan pin
assign pc_pin_internal[1] = dut.chip.soc_core_ifu_pcreg_q_reg_1_.QN;
assign pc_pin_internal[2] = dut.chip.soc_core_ifu_pcreg_q_reg_2_.Q;
assign pc_pin_internal[3] = dut.chip.soc_core_ifu_pcreg_q_reg_3_.Q;
assign pc_pin_internal[4] = dut.chip.soc_core_ifu_pcreg_q_reg_4_.Q;
assign pc_pin_internal[5] = dut.chip.soc_core_ifu_pcreg_q_reg_5_.Q;
assign pc_pin_internal[6] = dut.chip.soc_core_ifu_pcreg_q_reg_6_.Q;
assign pc_pin_internal[7] = dut.chip.soc_core_ifu_pcreg_q_reg_7_.Q;
assign pc_pin_internal[8] = dut.chip.soc_core_ifu_pcreg_q_reg_8_.Q;
assign pc_pin_internal[9] = dut.chip.soc_core_ifu_pcreg_q_reg_9_.Q;
assign pc_pin_internal[10] = dut.chip.soc_core_ifu_pcreg_q_reg_10_.Q;
assign pc_pin_internal[11] = dut.chip.soc_core_ifu_pcreg_q_reg_11_.Q;
assign pc_pin_internal[12] = dut.chip.soc_core_ifu_pcreg_q_reg_12_.Q;
assign pc_pin_internal[13] = dut.chip.soc_core_ifu_pcreg_q_reg_13_.Q;
assign pc_pin_internal[14] = dut.chip.soc_core_ifu_pcreg_q_reg_14_.Q;
assign pc_pin_internal[15] = dut.chip.soc_core_ifu_pcreg_q_reg_15_.Q;
assign pc_pin_internal[16] = dut.chip.soc_core_ifu_pcreg_q_reg_16_.Q;
assign pc_pin_internal[17] = dut.chip.soc_core_ifu_pcreg_q_reg_17_.Q;
assign pc_pin_internal[18] = dut.chip.soc_core_ifu_pcreg_q_reg_18_.Q;
assign pc_pin_internal[19] = dut.chip.soc_core_ifu_pcreg_q_reg_19_.Q;
assign pc_pin_internal[20] = dut.chip.soc_core_ifu_pcreg_q_reg_20_.Q;
assign pc_pin_internal[21] = dut.chip.soc_core_ifu_pcreg_q_reg_21_.Q;
assign pc_pin_internal[22] = dut.chip.soc_core_ifu_pcreg_q_reg_22_.Q;
assign pc_pin_internal[23] = dut.chip.soc_core_ifu_pcreg_q_reg_23_.Q;
assign pc_pin_internal[24] = dut.chip.soc_core_ifu_pcreg_q_reg_24_.Q;
assign pc_pin_internal[25] = dut.chip.soc_core_ifu_pcreg_q_reg_25_.Q;
assign pc_pin_internal[26] = dut.chip.soc_core_ifu_pcreg_q_reg_26_.Q;
assign pc_pin_internal[27] = dut.chip.soc_core_ifu_pcreg_q_reg_27_.Q;
assign pc_pin_internal[28] = dut.chip.soc_core_ifu_pcreg_q_reg_28_.Q;
assign pc_pin_internal[29] = dut.chip.soc_core_ifu_pcreg_q_reg_29_.Q;
assign pc_pin_internal[30] = dut.chip.soc_core_ifu_pcreg_q_reg_30_.Q;
assign pc_pin_internal[31] = dut.chip.soc_core_ifu_pcreg_q_reg_31_.Q;
assign pc_pin_internal[32] = dut.chip.soc_core_ifu_pcreg_q_reg_32_.Q;
assign pc_pin_internal[33] = dut.chip.soc_core_ifu_pcreg_q_reg_33_.Q;
assign pc_pin_internal[34] = dut.chip.soc_core_ifu_pcreg_q_reg_34_.Q;
assign pc_pin_internal[35] = dut.chip.soc_core_ifu_pcreg_q_reg_35_.Q;
assign pc_pin_internal[36] = dut.chip.soc_core_ifu_pcreg_q_reg_36_.Q;
assign pc_pin_internal[37] = dut.chip.soc_core_ifu_pcreg_q_reg_37_.Q;
assign pc_pin_internal[38] = dut.chip.soc_core_ifu_pcreg_q_reg_38_.Q;
assign pc_pin_internal[39] = dut.chip.soc_core_ifu_pcreg_q_reg_39_.Q;
assign pc_pin_internal[40] = dut.chip.soc_core_ifu_pcreg_q_reg_40_.Q;
assign pc_pin_internal[41] = dut.chip.soc_core_ifu_pcreg_q_reg_41_.Q;
assign pc_pin_internal[42] = dut.chip.soc_core_ifu_pcreg_q_reg_42_.Q;
assign pc_pin_internal[43] = dut.chip.soc_core_ifu_pcreg_q_reg_43_.Q;
assign pc_pin_internal[44] = dut.chip.soc_core_ifu_pcreg_q_reg_44_.Q;
assign pc_pin_internal[45] = dut.chip.soc_core_ifu_pcreg_q_reg_45_.Q;
assign pc_pin_internal[46] = dut.chip.soc_core_ifu_pcreg_q_reg_46_.Q;
assign pc_pin_internal[47] = dut.chip.soc_core_ifu_pcreg_q_reg_47_.Q;
assign pc_pin_internal[48] = dut.chip.soc_core_ifu_pcreg_q_reg_48_.Q;
assign pc_pin_internal[49] = dut.chip.soc_core_ifu_pcreg_q_reg_49_.Q;
assign pc_pin_internal[50] = dut.chip.soc_core_ifu_pcreg_q_reg_50_.Q;
assign pc_pin_internal[51] = dut.chip.soc_core_ifu_pcreg_q_reg_51_.Q;
assign pc_pin_internal[52] = dut.chip.soc_core_ifu_pcreg_q_reg_52_.Q;
assign pc_pin_internal[53] = dut.chip.soc_core_ifu_pcreg_q_reg_53_.Q;
assign pc_pin_internal[54] = dut.chip.soc_core_ifu_pcreg_q_reg_54_.Q;
assign pc_pin_internal[55] = dut.chip.soc_core_ifu_pcreg_q_reg_55_.Q;
assign pc_pin_internal[56] = dut.chip.soc_core_ifu_pcreg_q_reg_56_.Q;
assign pc_pin_internal[57] = dut.chip.soc_core_ifu_pcreg_q_reg_57_.QN;
assign pc_pin_internal[58] = dut.chip.soc_core_ifu_pcreg_q_reg_58_.QN;
assign pc_pin_internal[59] = dut.chip.soc_core_ifu_pcreg_q_reg_59_.QN;
assign pc_pin_internal[60] = dut.chip.soc_core_ifu_pcreg_q_reg_60_.QN;
assign pc_pin_internal[61] = dut.chip.soc_core_ifu_pcreg_q_reg_61_.QN;
assign pc_pin_internal[62] = dut.chip.soc_core_ifu_pcreg_q_reg_62_.QN;
assign pc_pin_internal[63] = dut.chip.soc_core_ifu_pcreg_q_reg_63_.QN;

// ---- pc_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign pc_raw_internal_available[0] = 1'b0;
assign pc_raw_internal_available[1] = 1'b1;
assign pc_raw_internal_available[2] = 1'b1;
assign pc_raw_internal_available[3] = 1'b1;
assign pc_raw_internal_available[4] = 1'b1;
assign pc_raw_internal_available[5] = 1'b1;
assign pc_raw_internal_available[6] = 1'b1;
assign pc_raw_internal_available[7] = 1'b1;
assign pc_raw_internal_available[8] = 1'b1;
assign pc_raw_internal_available[9] = 1'b1;
assign pc_raw_internal_available[10] = 1'b1;
assign pc_raw_internal_available[11] = 1'b1;
assign pc_raw_internal_available[12] = 1'b1;
assign pc_raw_internal_available[13] = 1'b1;
assign pc_raw_internal_available[14] = 1'b1;
assign pc_raw_internal_available[15] = 1'b1;
assign pc_raw_internal_available[16] = 1'b1;
assign pc_raw_internal_available[17] = 1'b1;
assign pc_raw_internal_available[18] = 1'b1;
assign pc_raw_internal_available[19] = 1'b1;
assign pc_raw_internal_available[20] = 1'b1;
assign pc_raw_internal_available[21] = 1'b1;
assign pc_raw_internal_available[22] = 1'b1;
assign pc_raw_internal_available[23] = 1'b1;
assign pc_raw_internal_available[24] = 1'b1;
assign pc_raw_internal_available[25] = 1'b1;
assign pc_raw_internal_available[26] = 1'b1;
assign pc_raw_internal_available[27] = 1'b1;
assign pc_raw_internal_available[28] = 1'b1;
assign pc_raw_internal_available[29] = 1'b1;
assign pc_raw_internal_available[30] = 1'b1;
assign pc_raw_internal_available[31] = 1'b1;
assign pc_raw_internal_available[32] = 1'b1;
assign pc_raw_internal_available[33] = 1'b1;
assign pc_raw_internal_available[34] = 1'b1;
assign pc_raw_internal_available[35] = 1'b1;
assign pc_raw_internal_available[36] = 1'b1;
assign pc_raw_internal_available[37] = 1'b1;
assign pc_raw_internal_available[38] = 1'b1;
assign pc_raw_internal_available[39] = 1'b1;
assign pc_raw_internal_available[40] = 1'b1;
assign pc_raw_internal_available[41] = 1'b1;
assign pc_raw_internal_available[42] = 1'b1;
assign pc_raw_internal_available[43] = 1'b1;
assign pc_raw_internal_available[44] = 1'b1;
assign pc_raw_internal_available[45] = 1'b1;
assign pc_raw_internal_available[46] = 1'b1;
assign pc_raw_internal_available[47] = 1'b1;
assign pc_raw_internal_available[48] = 1'b1;
assign pc_raw_internal_available[49] = 1'b1;
assign pc_raw_internal_available[50] = 1'b1;
assign pc_raw_internal_available[51] = 1'b1;
assign pc_raw_internal_available[52] = 1'b1;
assign pc_raw_internal_available[53] = 1'b1;
assign pc_raw_internal_available[54] = 1'b1;
assign pc_raw_internal_available[55] = 1'b1;
assign pc_raw_internal_available[56] = 1'b1;
assign pc_raw_internal_available[57] = 1'b1;
assign pc_raw_internal_available[58] = 1'b1;
assign pc_raw_internal_available[59] = 1'b1;
assign pc_raw_internal_available[60] = 1'b1;
assign pc_raw_internal_available[61] = 1'b1;
assign pc_raw_internal_available[62] = 1'b1;
assign pc_raw_internal_available[63] = 1'b1;

// ============================================================================
// Register lsu_AddressMReg: 64 mapped bits, width 64
// ============================================================================

// Bus declarations
wire [63:0] lsu_AddressMReg_internal;
wire [63:0] lsu_AddressMReg_raw_internal;
wire [63:0] lsu_AddressMReg_pin_internal;
wire [63:0] lsu_AddressMReg_raw_internal_available;

// ---- lsu_AddressMReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign lsu_AddressMReg_raw_internal[0] = dut.chip.soc_core_lsu_AddressMReg_q_reg_0_.Q; // c5[42]
assign lsu_AddressMReg_raw_internal[1] = ~dut.chip.soc_core_lsu_AddressMReg_q_reg_1_.QN; // c5[43]
assign lsu_AddressMReg_raw_internal[2] = ~dut.chip.soc_core_lsu_AddressMReg_q_reg_2_.QN; // c5[44]
assign lsu_AddressMReg_raw_internal[3] = ~dut.chip.soc_core_lsu_AddressMReg_q_reg_3_.QN; // c5[45]
assign lsu_AddressMReg_raw_internal[4] = ~dut.chip.soc_core_lsu_AddressMReg_q_reg_4_.QN; // c5[46]
assign lsu_AddressMReg_raw_internal[5] = ~dut.chip.soc_core_lsu_AddressMReg_q_reg_5_.QN; // c5[47]
assign lsu_AddressMReg_raw_internal[6] = ~dut.chip.soc_core_lsu_AddressMReg_q_reg_6_.QN; // c5[48]
assign lsu_AddressMReg_raw_internal[7] = ~dut.chip.soc_core_lsu_AddressMReg_q_reg_7_.QN; // c5[49]
assign lsu_AddressMReg_raw_internal[8] = ~dut.chip.soc_core_lsu_AddressMReg_q_reg_8_.QN; // c5[50]
assign lsu_AddressMReg_raw_internal[9] = ~dut.chip.soc_core_lsu_AddressMReg_q_reg_9_.QN; // c5[51]
assign lsu_AddressMReg_raw_internal[10] = ~dut.chip.soc_core_lsu_AddressMReg_q_reg_10_.QN; // c5[52]
assign lsu_AddressMReg_raw_internal[11] = ~dut.chip.soc_core_lsu_AddressMReg_q_reg_11_.QN; // c5[53]
assign lsu_AddressMReg_raw_internal[12] = dut.chip.soc_core_lsu_AddressMReg_q_reg_12_.Q; // c5[54]
assign lsu_AddressMReg_raw_internal[13] = dut.chip.soc_core_lsu_AddressMReg_q_reg_13_.Q; // c5[55]
assign lsu_AddressMReg_raw_internal[14] = dut.chip.soc_core_lsu_AddressMReg_q_reg_14_.Q; // c5[56]
assign lsu_AddressMReg_raw_internal[15] = dut.chip.soc_core_lsu_AddressMReg_q_reg_15_.Q; // c5[57]
assign lsu_AddressMReg_raw_internal[16] = dut.chip.soc_core_lsu_AddressMReg_q_reg_16_.Q; // c5[58]
assign lsu_AddressMReg_raw_internal[17] = dut.chip.soc_core_lsu_AddressMReg_q_reg_17_.Q; // c5[59]
assign lsu_AddressMReg_raw_internal[18] = dut.chip.soc_core_lsu_AddressMReg_q_reg_18_.Q; // c5[60]
assign lsu_AddressMReg_raw_internal[19] = dut.chip.soc_core_lsu_AddressMReg_q_reg_19_.Q; // c5[61]
assign lsu_AddressMReg_raw_internal[20] = dut.chip.soc_core_lsu_AddressMReg_q_reg_20_.Q; // c5[62]
assign lsu_AddressMReg_raw_internal[21] = dut.chip.soc_core_lsu_AddressMReg_q_reg_21_.Q; // c5[63]
assign lsu_AddressMReg_raw_internal[22] = dut.chip.soc_core_lsu_AddressMReg_q_reg_22_.Q; // c5[64]
assign lsu_AddressMReg_raw_internal[23] = dut.chip.soc_core_lsu_AddressMReg_q_reg_23_.Q; // c5[65]
assign lsu_AddressMReg_raw_internal[24] = dut.chip.soc_core_lsu_AddressMReg_q_reg_24_.Q; // c5[66]
assign lsu_AddressMReg_raw_internal[25] = dut.chip.soc_core_lsu_AddressMReg_q_reg_25_.Q; // c5[67]
assign lsu_AddressMReg_raw_internal[26] = dut.chip.soc_core_lsu_AddressMReg_q_reg_26_.Q; // c5[68]
assign lsu_AddressMReg_raw_internal[27] = dut.chip.soc_core_lsu_AddressMReg_q_reg_27_.Q; // c5[69]
assign lsu_AddressMReg_raw_internal[28] = dut.chip.soc_core_lsu_AddressMReg_q_reg_28_.Q; // c5[70]
assign lsu_AddressMReg_raw_internal[29] = dut.chip.soc_core_lsu_AddressMReg_q_reg_29_.Q; // c5[71]
assign lsu_AddressMReg_raw_internal[30] = dut.chip.soc_core_lsu_AddressMReg_q_reg_30_.Q; // c5[72]
assign lsu_AddressMReg_raw_internal[31] = dut.chip.soc_core_lsu_AddressMReg_q_reg_31_.Q; // c5[73]
assign lsu_AddressMReg_raw_internal[32] = dut.chip.soc_core_lsu_AddressMReg_q_reg_32_.Q; // c5[74]
assign lsu_AddressMReg_raw_internal[33] = dut.chip.soc_core_lsu_AddressMReg_q_reg_33_.Q; // c5[75]
assign lsu_AddressMReg_raw_internal[34] = dut.chip.soc_core_lsu_AddressMReg_q_reg_34_.Q; // c5[76]
assign lsu_AddressMReg_raw_internal[35] = dut.chip.soc_core_lsu_AddressMReg_q_reg_35_.Q; // c5[77]
assign lsu_AddressMReg_raw_internal[36] = dut.chip.soc_core_lsu_AddressMReg_q_reg_36_.Q; // c5[78]
assign lsu_AddressMReg_raw_internal[37] = dut.chip.soc_core_lsu_AddressMReg_q_reg_37_.Q; // c5[79]
assign lsu_AddressMReg_raw_internal[38] = dut.chip.soc_core_lsu_AddressMReg_q_reg_38_.Q; // c5[80]
assign lsu_AddressMReg_raw_internal[39] = dut.chip.soc_core_lsu_AddressMReg_q_reg_39_.Q; // c5[81]
assign lsu_AddressMReg_raw_internal[40] = dut.chip.soc_core_lsu_AddressMReg_q_reg_40_.Q; // c5[82]
assign lsu_AddressMReg_raw_internal[41] = dut.chip.soc_core_lsu_AddressMReg_q_reg_41_.Q; // c5[83]
assign lsu_AddressMReg_raw_internal[42] = dut.chip.soc_core_lsu_AddressMReg_q_reg_42_.Q; // c5[84]
assign lsu_AddressMReg_raw_internal[43] = dut.chip.soc_core_lsu_AddressMReg_q_reg_43_.Q; // c5[85]
assign lsu_AddressMReg_raw_internal[44] = dut.chip.soc_core_lsu_AddressMReg_q_reg_44_.Q; // c5[86]
assign lsu_AddressMReg_raw_internal[45] = dut.chip.soc_core_lsu_AddressMReg_q_reg_45_.Q; // c5[87]
assign lsu_AddressMReg_raw_internal[46] = dut.chip.soc_core_lsu_AddressMReg_q_reg_46_.Q; // c5[88]
assign lsu_AddressMReg_raw_internal[47] = dut.chip.soc_core_lsu_AddressMReg_q_reg_47_.Q; // c5[89]
assign lsu_AddressMReg_raw_internal[48] = dut.chip.soc_core_lsu_AddressMReg_q_reg_48_.Q; // c5[90]
assign lsu_AddressMReg_raw_internal[49] = dut.chip.soc_core_lsu_AddressMReg_q_reg_49_.Q; // c5[91]
assign lsu_AddressMReg_raw_internal[50] = dut.chip.soc_core_lsu_AddressMReg_q_reg_50_.Q; // c5[92]
assign lsu_AddressMReg_raw_internal[51] = dut.chip.soc_core_lsu_AddressMReg_q_reg_51_.Q; // c5[93]
assign lsu_AddressMReg_raw_internal[52] = dut.chip.soc_core_lsu_AddressMReg_q_reg_52_.Q; // c5[94]
assign lsu_AddressMReg_raw_internal[53] = dut.chip.soc_core_lsu_AddressMReg_q_reg_53_.Q; // c5[95]
assign lsu_AddressMReg_raw_internal[54] = dut.chip.soc_core_lsu_AddressMReg_q_reg_54_.Q; // c5[96]
assign lsu_AddressMReg_raw_internal[55] = dut.chip.soc_core_lsu_AddressMReg_q_reg_55_.Q; // c5[97]
assign lsu_AddressMReg_raw_internal[56] = dut.chip.soc_core_lsu_AddressMReg_q_reg_56_.Q; // c5[98]
assign lsu_AddressMReg_raw_internal[57] = dut.chip.soc_core_lsu_AddressMReg_q_reg_57_.Q; // c5[99]
assign lsu_AddressMReg_raw_internal[58] = dut.chip.soc_core_lsu_AddressMReg_q_reg_58_.Q; // c5[100]
assign lsu_AddressMReg_raw_internal[59] = dut.chip.soc_core_lsu_AddressMReg_q_reg_59_.Q; // c5[101]
assign lsu_AddressMReg_raw_internal[60] = dut.chip.soc_core_lsu_AddressMReg_q_reg_60_.Q; // c5[102]
assign lsu_AddressMReg_raw_internal[61] = dut.chip.soc_core_lsu_AddressMReg_q_reg_61_.Q; // c5[103]
assign lsu_AddressMReg_raw_internal[62] = dut.chip.soc_core_lsu_AddressMReg_q_reg_62_.Q; // c5[104]
assign lsu_AddressMReg_raw_internal[63] = dut.chip.soc_core_lsu_AddressMReg_q_reg_63_.Q; // c5[105]

// ---- lsu_AddressMReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign lsu_AddressMReg_internal[0] = lsu_AddressMReg_raw_internal[0];
assign lsu_AddressMReg_internal[1] = lsu_AddressMReg_raw_internal[1];
assign lsu_AddressMReg_internal[2] = lsu_AddressMReg_raw_internal[2];
assign lsu_AddressMReg_internal[3] = lsu_AddressMReg_raw_internal[3];
assign lsu_AddressMReg_internal[4] = lsu_AddressMReg_raw_internal[4];
assign lsu_AddressMReg_internal[5] = lsu_AddressMReg_raw_internal[5];
assign lsu_AddressMReg_internal[6] = lsu_AddressMReg_raw_internal[6];
assign lsu_AddressMReg_internal[7] = lsu_AddressMReg_raw_internal[7];
assign lsu_AddressMReg_internal[8] = lsu_AddressMReg_raw_internal[8];
assign lsu_AddressMReg_internal[9] = lsu_AddressMReg_raw_internal[9];
assign lsu_AddressMReg_internal[10] = lsu_AddressMReg_raw_internal[10];
assign lsu_AddressMReg_internal[11] = lsu_AddressMReg_raw_internal[11];
assign lsu_AddressMReg_internal[12] = lsu_AddressMReg_raw_internal[12];
assign lsu_AddressMReg_internal[13] = lsu_AddressMReg_raw_internal[13];
assign lsu_AddressMReg_internal[14] = lsu_AddressMReg_raw_internal[14];
assign lsu_AddressMReg_internal[15] = lsu_AddressMReg_raw_internal[15];
assign lsu_AddressMReg_internal[16] = lsu_AddressMReg_raw_internal[16];
assign lsu_AddressMReg_internal[17] = lsu_AddressMReg_raw_internal[17];
assign lsu_AddressMReg_internal[18] = lsu_AddressMReg_raw_internal[18];
assign lsu_AddressMReg_internal[19] = lsu_AddressMReg_raw_internal[19];
assign lsu_AddressMReg_internal[20] = lsu_AddressMReg_raw_internal[20];
assign lsu_AddressMReg_internal[21] = lsu_AddressMReg_raw_internal[21];
assign lsu_AddressMReg_internal[22] = lsu_AddressMReg_raw_internal[22];
assign lsu_AddressMReg_internal[23] = lsu_AddressMReg_raw_internal[23];
assign lsu_AddressMReg_internal[24] = lsu_AddressMReg_raw_internal[24];
assign lsu_AddressMReg_internal[25] = lsu_AddressMReg_raw_internal[25];
assign lsu_AddressMReg_internal[26] = lsu_AddressMReg_raw_internal[26];
assign lsu_AddressMReg_internal[27] = lsu_AddressMReg_raw_internal[27];
assign lsu_AddressMReg_internal[28] = lsu_AddressMReg_raw_internal[28];
assign lsu_AddressMReg_internal[29] = lsu_AddressMReg_raw_internal[29];
assign lsu_AddressMReg_internal[30] = lsu_AddressMReg_raw_internal[30];
assign lsu_AddressMReg_internal[31] = lsu_AddressMReg_raw_internal[31];
assign lsu_AddressMReg_internal[32] = lsu_AddressMReg_raw_internal[32];
assign lsu_AddressMReg_internal[33] = lsu_AddressMReg_raw_internal[33];
assign lsu_AddressMReg_internal[34] = lsu_AddressMReg_raw_internal[34];
assign lsu_AddressMReg_internal[35] = lsu_AddressMReg_raw_internal[35];
assign lsu_AddressMReg_internal[36] = lsu_AddressMReg_raw_internal[36];
assign lsu_AddressMReg_internal[37] = lsu_AddressMReg_raw_internal[37];
assign lsu_AddressMReg_internal[38] = lsu_AddressMReg_raw_internal[38];
assign lsu_AddressMReg_internal[39] = lsu_AddressMReg_raw_internal[39];
assign lsu_AddressMReg_internal[40] = lsu_AddressMReg_raw_internal[40];
assign lsu_AddressMReg_internal[41] = lsu_AddressMReg_raw_internal[41];
assign lsu_AddressMReg_internal[42] = lsu_AddressMReg_raw_internal[42];
assign lsu_AddressMReg_internal[43] = lsu_AddressMReg_raw_internal[43];
assign lsu_AddressMReg_internal[44] = lsu_AddressMReg_raw_internal[44];
assign lsu_AddressMReg_internal[45] = lsu_AddressMReg_raw_internal[45];
assign lsu_AddressMReg_internal[46] = lsu_AddressMReg_raw_internal[46];
assign lsu_AddressMReg_internal[47] = lsu_AddressMReg_raw_internal[47];
assign lsu_AddressMReg_internal[48] = lsu_AddressMReg_raw_internal[48];
assign lsu_AddressMReg_internal[49] = lsu_AddressMReg_raw_internal[49];
assign lsu_AddressMReg_internal[50] = lsu_AddressMReg_raw_internal[50];
assign lsu_AddressMReg_internal[51] = lsu_AddressMReg_raw_internal[51];
assign lsu_AddressMReg_internal[52] = lsu_AddressMReg_raw_internal[52];
assign lsu_AddressMReg_internal[53] = lsu_AddressMReg_raw_internal[53];
assign lsu_AddressMReg_internal[54] = lsu_AddressMReg_raw_internal[54];
assign lsu_AddressMReg_internal[55] = lsu_AddressMReg_raw_internal[55];
assign lsu_AddressMReg_internal[56] = lsu_AddressMReg_raw_internal[56];
assign lsu_AddressMReg_internal[57] = lsu_AddressMReg_raw_internal[57];
assign lsu_AddressMReg_internal[58] = lsu_AddressMReg_raw_internal[58];
assign lsu_AddressMReg_internal[59] = lsu_AddressMReg_raw_internal[59];
assign lsu_AddressMReg_internal[60] = lsu_AddressMReg_raw_internal[60];
assign lsu_AddressMReg_internal[61] = lsu_AddressMReg_raw_internal[61];
assign lsu_AddressMReg_internal[62] = lsu_AddressMReg_raw_internal[62];
assign lsu_AddressMReg_internal[63] = lsu_AddressMReg_raw_internal[63];

// ---- lsu_AddressMReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign lsu_AddressMReg_pin_internal[0] = dut.chip.soc_core_lsu_AddressMReg_q_reg_0_.Q;
assign lsu_AddressMReg_pin_internal[1] = dut.chip.soc_core_lsu_AddressMReg_q_reg_1_.QN;
assign lsu_AddressMReg_pin_internal[2] = dut.chip.soc_core_lsu_AddressMReg_q_reg_2_.QN;
assign lsu_AddressMReg_pin_internal[3] = dut.chip.soc_core_lsu_AddressMReg_q_reg_3_.QN;
assign lsu_AddressMReg_pin_internal[4] = dut.chip.soc_core_lsu_AddressMReg_q_reg_4_.QN;
assign lsu_AddressMReg_pin_internal[5] = dut.chip.soc_core_lsu_AddressMReg_q_reg_5_.QN;
assign lsu_AddressMReg_pin_internal[6] = dut.chip.soc_core_lsu_AddressMReg_q_reg_6_.QN;
assign lsu_AddressMReg_pin_internal[7] = dut.chip.soc_core_lsu_AddressMReg_q_reg_7_.QN;
assign lsu_AddressMReg_pin_internal[8] = dut.chip.soc_core_lsu_AddressMReg_q_reg_8_.QN;
assign lsu_AddressMReg_pin_internal[9] = dut.chip.soc_core_lsu_AddressMReg_q_reg_9_.QN;
assign lsu_AddressMReg_pin_internal[10] = dut.chip.soc_core_lsu_AddressMReg_q_reg_10_.QN;
assign lsu_AddressMReg_pin_internal[11] = dut.chip.soc_core_lsu_AddressMReg_q_reg_11_.QN;
assign lsu_AddressMReg_pin_internal[12] = dut.chip.soc_core_lsu_AddressMReg_q_reg_12_.Q;
assign lsu_AddressMReg_pin_internal[13] = dut.chip.soc_core_lsu_AddressMReg_q_reg_13_.Q;
assign lsu_AddressMReg_pin_internal[14] = dut.chip.soc_core_lsu_AddressMReg_q_reg_14_.Q;
assign lsu_AddressMReg_pin_internal[15] = dut.chip.soc_core_lsu_AddressMReg_q_reg_15_.Q;
assign lsu_AddressMReg_pin_internal[16] = dut.chip.soc_core_lsu_AddressMReg_q_reg_16_.Q;
assign lsu_AddressMReg_pin_internal[17] = dut.chip.soc_core_lsu_AddressMReg_q_reg_17_.Q;
assign lsu_AddressMReg_pin_internal[18] = dut.chip.soc_core_lsu_AddressMReg_q_reg_18_.Q;
assign lsu_AddressMReg_pin_internal[19] = dut.chip.soc_core_lsu_AddressMReg_q_reg_19_.Q;
assign lsu_AddressMReg_pin_internal[20] = dut.chip.soc_core_lsu_AddressMReg_q_reg_20_.Q;
assign lsu_AddressMReg_pin_internal[21] = dut.chip.soc_core_lsu_AddressMReg_q_reg_21_.Q;
assign lsu_AddressMReg_pin_internal[22] = dut.chip.soc_core_lsu_AddressMReg_q_reg_22_.Q;
assign lsu_AddressMReg_pin_internal[23] = dut.chip.soc_core_lsu_AddressMReg_q_reg_23_.Q;
assign lsu_AddressMReg_pin_internal[24] = dut.chip.soc_core_lsu_AddressMReg_q_reg_24_.Q;
assign lsu_AddressMReg_pin_internal[25] = dut.chip.soc_core_lsu_AddressMReg_q_reg_25_.Q;
assign lsu_AddressMReg_pin_internal[26] = dut.chip.soc_core_lsu_AddressMReg_q_reg_26_.Q;
assign lsu_AddressMReg_pin_internal[27] = dut.chip.soc_core_lsu_AddressMReg_q_reg_27_.Q;
assign lsu_AddressMReg_pin_internal[28] = dut.chip.soc_core_lsu_AddressMReg_q_reg_28_.Q;
assign lsu_AddressMReg_pin_internal[29] = dut.chip.soc_core_lsu_AddressMReg_q_reg_29_.Q;
assign lsu_AddressMReg_pin_internal[30] = dut.chip.soc_core_lsu_AddressMReg_q_reg_30_.Q;
assign lsu_AddressMReg_pin_internal[31] = dut.chip.soc_core_lsu_AddressMReg_q_reg_31_.Q;
assign lsu_AddressMReg_pin_internal[32] = dut.chip.soc_core_lsu_AddressMReg_q_reg_32_.Q;
assign lsu_AddressMReg_pin_internal[33] = dut.chip.soc_core_lsu_AddressMReg_q_reg_33_.Q;
assign lsu_AddressMReg_pin_internal[34] = dut.chip.soc_core_lsu_AddressMReg_q_reg_34_.Q;
assign lsu_AddressMReg_pin_internal[35] = dut.chip.soc_core_lsu_AddressMReg_q_reg_35_.Q;
assign lsu_AddressMReg_pin_internal[36] = dut.chip.soc_core_lsu_AddressMReg_q_reg_36_.Q;
assign lsu_AddressMReg_pin_internal[37] = dut.chip.soc_core_lsu_AddressMReg_q_reg_37_.Q;
assign lsu_AddressMReg_pin_internal[38] = dut.chip.soc_core_lsu_AddressMReg_q_reg_38_.Q;
assign lsu_AddressMReg_pin_internal[39] = dut.chip.soc_core_lsu_AddressMReg_q_reg_39_.Q;
assign lsu_AddressMReg_pin_internal[40] = dut.chip.soc_core_lsu_AddressMReg_q_reg_40_.Q;
assign lsu_AddressMReg_pin_internal[41] = dut.chip.soc_core_lsu_AddressMReg_q_reg_41_.Q;
assign lsu_AddressMReg_pin_internal[42] = dut.chip.soc_core_lsu_AddressMReg_q_reg_42_.Q;
assign lsu_AddressMReg_pin_internal[43] = dut.chip.soc_core_lsu_AddressMReg_q_reg_43_.Q;
assign lsu_AddressMReg_pin_internal[44] = dut.chip.soc_core_lsu_AddressMReg_q_reg_44_.Q;
assign lsu_AddressMReg_pin_internal[45] = dut.chip.soc_core_lsu_AddressMReg_q_reg_45_.Q;
assign lsu_AddressMReg_pin_internal[46] = dut.chip.soc_core_lsu_AddressMReg_q_reg_46_.Q;
assign lsu_AddressMReg_pin_internal[47] = dut.chip.soc_core_lsu_AddressMReg_q_reg_47_.Q;
assign lsu_AddressMReg_pin_internal[48] = dut.chip.soc_core_lsu_AddressMReg_q_reg_48_.Q;
assign lsu_AddressMReg_pin_internal[49] = dut.chip.soc_core_lsu_AddressMReg_q_reg_49_.Q;
assign lsu_AddressMReg_pin_internal[50] = dut.chip.soc_core_lsu_AddressMReg_q_reg_50_.Q;
assign lsu_AddressMReg_pin_internal[51] = dut.chip.soc_core_lsu_AddressMReg_q_reg_51_.Q;
assign lsu_AddressMReg_pin_internal[52] = dut.chip.soc_core_lsu_AddressMReg_q_reg_52_.Q;
assign lsu_AddressMReg_pin_internal[53] = dut.chip.soc_core_lsu_AddressMReg_q_reg_53_.Q;
assign lsu_AddressMReg_pin_internal[54] = dut.chip.soc_core_lsu_AddressMReg_q_reg_54_.Q;
assign lsu_AddressMReg_pin_internal[55] = dut.chip.soc_core_lsu_AddressMReg_q_reg_55_.Q;
assign lsu_AddressMReg_pin_internal[56] = dut.chip.soc_core_lsu_AddressMReg_q_reg_56_.Q;
assign lsu_AddressMReg_pin_internal[57] = dut.chip.soc_core_lsu_AddressMReg_q_reg_57_.Q;
assign lsu_AddressMReg_pin_internal[58] = dut.chip.soc_core_lsu_AddressMReg_q_reg_58_.Q;
assign lsu_AddressMReg_pin_internal[59] = dut.chip.soc_core_lsu_AddressMReg_q_reg_59_.Q;
assign lsu_AddressMReg_pin_internal[60] = dut.chip.soc_core_lsu_AddressMReg_q_reg_60_.Q;
assign lsu_AddressMReg_pin_internal[61] = dut.chip.soc_core_lsu_AddressMReg_q_reg_61_.Q;
assign lsu_AddressMReg_pin_internal[62] = dut.chip.soc_core_lsu_AddressMReg_q_reg_62_.Q;
assign lsu_AddressMReg_pin_internal[63] = dut.chip.soc_core_lsu_AddressMReg_q_reg_63_.Q;

// ---- lsu_AddressMReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign lsu_AddressMReg_raw_internal_available[0] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[1] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[2] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[3] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[4] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[5] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[6] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[7] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[8] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[9] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[10] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[11] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[12] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[13] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[14] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[15] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[16] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[17] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[18] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[19] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[20] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[21] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[22] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[23] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[24] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[25] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[26] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[27] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[28] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[29] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[30] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[31] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[32] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[33] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[34] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[35] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[36] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[37] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[38] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[39] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[40] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[41] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[42] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[43] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[44] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[45] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[46] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[47] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[48] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[49] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[50] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[51] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[52] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[53] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[54] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[55] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[56] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[57] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[58] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[59] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[60] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[61] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[62] = 1'b1;
assign lsu_AddressMReg_raw_internal_available[63] = 1'b1;

// ============================================================================
// Register lsu_ReadDataMWReg: 64 mapped bits, width 64
// ============================================================================

// Bus declarations
wire [63:0] lsu_ReadDataMWReg_internal;
wire [63:0] lsu_ReadDataMWReg_raw_internal;
wire [63:0] lsu_ReadDataMWReg_pin_internal;
wire [63:0] lsu_ReadDataMWReg_raw_internal_available;

// ---- lsu_ReadDataMWReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign lsu_ReadDataMWReg_raw_internal[0] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_0_.Q; // c5[106]
assign lsu_ReadDataMWReg_raw_internal[1] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_1_.Q; // c5[107]
assign lsu_ReadDataMWReg_raw_internal[2] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_2_.Q; // c5[108]
assign lsu_ReadDataMWReg_raw_internal[3] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_3_.Q; // c5[109]
assign lsu_ReadDataMWReg_raw_internal[4] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_4_.Q; // c5[110]
assign lsu_ReadDataMWReg_raw_internal[5] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_5_.Q; // c5[111]
assign lsu_ReadDataMWReg_raw_internal[6] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_6_.Q; // c5[112]
assign lsu_ReadDataMWReg_raw_internal[7] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_7_.Q; // c5[113]
assign lsu_ReadDataMWReg_raw_internal[8] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_8_.Q; // c5[114]
assign lsu_ReadDataMWReg_raw_internal[9] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_9_.Q; // c5[115]
assign lsu_ReadDataMWReg_raw_internal[10] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_10_.Q; // c5[116]
assign lsu_ReadDataMWReg_raw_internal[11] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_11_.Q; // c5[117]
assign lsu_ReadDataMWReg_raw_internal[12] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_12_.Q; // c5[118]
assign lsu_ReadDataMWReg_raw_internal[13] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_13_.Q; // c5[119]
assign lsu_ReadDataMWReg_raw_internal[14] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_14_.Q; // c5[120]
assign lsu_ReadDataMWReg_raw_internal[15] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_15_.Q; // c5[121]
assign lsu_ReadDataMWReg_raw_internal[16] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_16_.Q; // c5[122]
assign lsu_ReadDataMWReg_raw_internal[17] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_17_.Q; // c5[123]
assign lsu_ReadDataMWReg_raw_internal[18] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_18_.Q; // c5[124]
assign lsu_ReadDataMWReg_raw_internal[19] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_19_.Q; // c5[125]
assign lsu_ReadDataMWReg_raw_internal[20] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_20_.Q; // c5[126]
assign lsu_ReadDataMWReg_raw_internal[21] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_21_.Q; // c5[127]
assign lsu_ReadDataMWReg_raw_internal[22] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_22_.Q; // c5[128]
assign lsu_ReadDataMWReg_raw_internal[23] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_23_.Q; // c5[129]
assign lsu_ReadDataMWReg_raw_internal[24] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_24_.Q; // c5[130]
assign lsu_ReadDataMWReg_raw_internal[25] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_25_.Q; // c5[131]
assign lsu_ReadDataMWReg_raw_internal[26] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_26_.Q; // c5[132]
assign lsu_ReadDataMWReg_raw_internal[27] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_27_.Q; // c5[133]
assign lsu_ReadDataMWReg_raw_internal[28] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_28_.Q; // c5[134]
assign lsu_ReadDataMWReg_raw_internal[29] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_29_.Q; // c5[135]
assign lsu_ReadDataMWReg_raw_internal[30] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_30_.Q; // c5[136]
assign lsu_ReadDataMWReg_raw_internal[31] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_31_.Q; // c5[137]
assign lsu_ReadDataMWReg_raw_internal[32] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_32_.Q; // c5[138]
assign lsu_ReadDataMWReg_raw_internal[33] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_33_.Q; // c5[139]
assign lsu_ReadDataMWReg_raw_internal[34] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_34_.Q; // c5[140]
assign lsu_ReadDataMWReg_raw_internal[35] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_35_.Q; // c5[141]
assign lsu_ReadDataMWReg_raw_internal[36] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_36_.Q; // c5[142]
assign lsu_ReadDataMWReg_raw_internal[37] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_37_.Q; // c5[143]
assign lsu_ReadDataMWReg_raw_internal[38] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_38_.Q; // c5[144]
assign lsu_ReadDataMWReg_raw_internal[39] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_39_.Q; // c5[145]
assign lsu_ReadDataMWReg_raw_internal[40] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_40_.Q; // c5[146]
assign lsu_ReadDataMWReg_raw_internal[41] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_41_.Q; // c5[147]
assign lsu_ReadDataMWReg_raw_internal[42] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_42_.Q; // c5[148]
assign lsu_ReadDataMWReg_raw_internal[43] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_43_.Q; // c5[149]
assign lsu_ReadDataMWReg_raw_internal[44] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_44_.Q; // c5[150]
assign lsu_ReadDataMWReg_raw_internal[45] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_45_.Q; // c5[151]
assign lsu_ReadDataMWReg_raw_internal[46] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_46_.Q; // c5[152]
assign lsu_ReadDataMWReg_raw_internal[47] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_47_.Q; // c5[153]
assign lsu_ReadDataMWReg_raw_internal[48] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_48_.Q; // c5[154]
assign lsu_ReadDataMWReg_raw_internal[49] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_49_.Q; // c5[155]
assign lsu_ReadDataMWReg_raw_internal[50] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_50_.Q; // c5[156]
assign lsu_ReadDataMWReg_raw_internal[51] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_51_.Q; // c5[157]
assign lsu_ReadDataMWReg_raw_internal[52] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_52_.Q; // c5[158]
assign lsu_ReadDataMWReg_raw_internal[53] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_53_.Q; // c5[159]
assign lsu_ReadDataMWReg_raw_internal[54] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_54_.Q; // c5[160]
assign lsu_ReadDataMWReg_raw_internal[55] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_55_.Q; // c5[161]
assign lsu_ReadDataMWReg_raw_internal[56] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_56_.Q; // c5[162]
assign lsu_ReadDataMWReg_raw_internal[57] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_57_.Q; // c5[163]
assign lsu_ReadDataMWReg_raw_internal[58] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_58_.Q; // c5[164]
assign lsu_ReadDataMWReg_raw_internal[59] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_59_.Q; // c5[165]
assign lsu_ReadDataMWReg_raw_internal[60] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_60_.Q; // c5[166]
assign lsu_ReadDataMWReg_raw_internal[61] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_61_.Q; // c5[167]
assign lsu_ReadDataMWReg_raw_internal[62] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_62_.Q; // c5[168]
assign lsu_ReadDataMWReg_raw_internal[63] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_63_.Q; // c5[169]

// ---- lsu_ReadDataMWReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign lsu_ReadDataMWReg_internal[0] = lsu_ReadDataMWReg_raw_internal[0];
assign lsu_ReadDataMWReg_internal[1] = lsu_ReadDataMWReg_raw_internal[1];
assign lsu_ReadDataMWReg_internal[2] = lsu_ReadDataMWReg_raw_internal[2];
assign lsu_ReadDataMWReg_internal[3] = lsu_ReadDataMWReg_raw_internal[3];
assign lsu_ReadDataMWReg_internal[4] = lsu_ReadDataMWReg_raw_internal[4];
assign lsu_ReadDataMWReg_internal[5] = lsu_ReadDataMWReg_raw_internal[5];
assign lsu_ReadDataMWReg_internal[6] = lsu_ReadDataMWReg_raw_internal[6];
assign lsu_ReadDataMWReg_internal[7] = lsu_ReadDataMWReg_raw_internal[7];
assign lsu_ReadDataMWReg_internal[8] = lsu_ReadDataMWReg_raw_internal[8];
assign lsu_ReadDataMWReg_internal[9] = lsu_ReadDataMWReg_raw_internal[9];
assign lsu_ReadDataMWReg_internal[10] = lsu_ReadDataMWReg_raw_internal[10];
assign lsu_ReadDataMWReg_internal[11] = lsu_ReadDataMWReg_raw_internal[11];
assign lsu_ReadDataMWReg_internal[12] = lsu_ReadDataMWReg_raw_internal[12];
assign lsu_ReadDataMWReg_internal[13] = lsu_ReadDataMWReg_raw_internal[13];
assign lsu_ReadDataMWReg_internal[14] = lsu_ReadDataMWReg_raw_internal[14];
assign lsu_ReadDataMWReg_internal[15] = lsu_ReadDataMWReg_raw_internal[15];
assign lsu_ReadDataMWReg_internal[16] = lsu_ReadDataMWReg_raw_internal[16];
assign lsu_ReadDataMWReg_internal[17] = lsu_ReadDataMWReg_raw_internal[17];
assign lsu_ReadDataMWReg_internal[18] = lsu_ReadDataMWReg_raw_internal[18];
assign lsu_ReadDataMWReg_internal[19] = lsu_ReadDataMWReg_raw_internal[19];
assign lsu_ReadDataMWReg_internal[20] = lsu_ReadDataMWReg_raw_internal[20];
assign lsu_ReadDataMWReg_internal[21] = lsu_ReadDataMWReg_raw_internal[21];
assign lsu_ReadDataMWReg_internal[22] = lsu_ReadDataMWReg_raw_internal[22];
assign lsu_ReadDataMWReg_internal[23] = lsu_ReadDataMWReg_raw_internal[23];
assign lsu_ReadDataMWReg_internal[24] = lsu_ReadDataMWReg_raw_internal[24];
assign lsu_ReadDataMWReg_internal[25] = lsu_ReadDataMWReg_raw_internal[25];
assign lsu_ReadDataMWReg_internal[26] = lsu_ReadDataMWReg_raw_internal[26];
assign lsu_ReadDataMWReg_internal[27] = lsu_ReadDataMWReg_raw_internal[27];
assign lsu_ReadDataMWReg_internal[28] = lsu_ReadDataMWReg_raw_internal[28];
assign lsu_ReadDataMWReg_internal[29] = lsu_ReadDataMWReg_raw_internal[29];
assign lsu_ReadDataMWReg_internal[30] = lsu_ReadDataMWReg_raw_internal[30];
assign lsu_ReadDataMWReg_internal[31] = lsu_ReadDataMWReg_raw_internal[31];
assign lsu_ReadDataMWReg_internal[32] = lsu_ReadDataMWReg_raw_internal[32];
assign lsu_ReadDataMWReg_internal[33] = lsu_ReadDataMWReg_raw_internal[33];
assign lsu_ReadDataMWReg_internal[34] = lsu_ReadDataMWReg_raw_internal[34];
assign lsu_ReadDataMWReg_internal[35] = lsu_ReadDataMWReg_raw_internal[35];
assign lsu_ReadDataMWReg_internal[36] = lsu_ReadDataMWReg_raw_internal[36];
assign lsu_ReadDataMWReg_internal[37] = lsu_ReadDataMWReg_raw_internal[37];
assign lsu_ReadDataMWReg_internal[38] = lsu_ReadDataMWReg_raw_internal[38];
assign lsu_ReadDataMWReg_internal[39] = lsu_ReadDataMWReg_raw_internal[39];
assign lsu_ReadDataMWReg_internal[40] = lsu_ReadDataMWReg_raw_internal[40];
assign lsu_ReadDataMWReg_internal[41] = lsu_ReadDataMWReg_raw_internal[41];
assign lsu_ReadDataMWReg_internal[42] = lsu_ReadDataMWReg_raw_internal[42];
assign lsu_ReadDataMWReg_internal[43] = lsu_ReadDataMWReg_raw_internal[43];
assign lsu_ReadDataMWReg_internal[44] = lsu_ReadDataMWReg_raw_internal[44];
assign lsu_ReadDataMWReg_internal[45] = lsu_ReadDataMWReg_raw_internal[45];
assign lsu_ReadDataMWReg_internal[46] = lsu_ReadDataMWReg_raw_internal[46];
assign lsu_ReadDataMWReg_internal[47] = lsu_ReadDataMWReg_raw_internal[47];
assign lsu_ReadDataMWReg_internal[48] = lsu_ReadDataMWReg_raw_internal[48];
assign lsu_ReadDataMWReg_internal[49] = lsu_ReadDataMWReg_raw_internal[49];
assign lsu_ReadDataMWReg_internal[50] = lsu_ReadDataMWReg_raw_internal[50];
assign lsu_ReadDataMWReg_internal[51] = lsu_ReadDataMWReg_raw_internal[51];
assign lsu_ReadDataMWReg_internal[52] = lsu_ReadDataMWReg_raw_internal[52];
assign lsu_ReadDataMWReg_internal[53] = lsu_ReadDataMWReg_raw_internal[53];
assign lsu_ReadDataMWReg_internal[54] = lsu_ReadDataMWReg_raw_internal[54];
assign lsu_ReadDataMWReg_internal[55] = lsu_ReadDataMWReg_raw_internal[55];
assign lsu_ReadDataMWReg_internal[56] = lsu_ReadDataMWReg_raw_internal[56];
assign lsu_ReadDataMWReg_internal[57] = lsu_ReadDataMWReg_raw_internal[57];
assign lsu_ReadDataMWReg_internal[58] = lsu_ReadDataMWReg_raw_internal[58];
assign lsu_ReadDataMWReg_internal[59] = lsu_ReadDataMWReg_raw_internal[59];
assign lsu_ReadDataMWReg_internal[60] = lsu_ReadDataMWReg_raw_internal[60];
assign lsu_ReadDataMWReg_internal[61] = lsu_ReadDataMWReg_raw_internal[61];
assign lsu_ReadDataMWReg_internal[62] = lsu_ReadDataMWReg_raw_internal[62];
assign lsu_ReadDataMWReg_internal[63] = lsu_ReadDataMWReg_raw_internal[63];

// ---- lsu_ReadDataMWReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign lsu_ReadDataMWReg_pin_internal[0] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_0_.Q;
assign lsu_ReadDataMWReg_pin_internal[1] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_1_.Q;
assign lsu_ReadDataMWReg_pin_internal[2] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_2_.Q;
assign lsu_ReadDataMWReg_pin_internal[3] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_3_.Q;
assign lsu_ReadDataMWReg_pin_internal[4] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_4_.Q;
assign lsu_ReadDataMWReg_pin_internal[5] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_5_.Q;
assign lsu_ReadDataMWReg_pin_internal[6] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_6_.Q;
assign lsu_ReadDataMWReg_pin_internal[7] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_7_.Q;
assign lsu_ReadDataMWReg_pin_internal[8] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_8_.Q;
assign lsu_ReadDataMWReg_pin_internal[9] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_9_.Q;
assign lsu_ReadDataMWReg_pin_internal[10] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_10_.Q;
assign lsu_ReadDataMWReg_pin_internal[11] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_11_.Q;
assign lsu_ReadDataMWReg_pin_internal[12] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_12_.Q;
assign lsu_ReadDataMWReg_pin_internal[13] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_13_.Q;
assign lsu_ReadDataMWReg_pin_internal[14] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_14_.Q;
assign lsu_ReadDataMWReg_pin_internal[15] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_15_.Q;
assign lsu_ReadDataMWReg_pin_internal[16] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_16_.Q;
assign lsu_ReadDataMWReg_pin_internal[17] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_17_.Q;
assign lsu_ReadDataMWReg_pin_internal[18] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_18_.Q;
assign lsu_ReadDataMWReg_pin_internal[19] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_19_.Q;
assign lsu_ReadDataMWReg_pin_internal[20] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_20_.Q;
assign lsu_ReadDataMWReg_pin_internal[21] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_21_.Q;
assign lsu_ReadDataMWReg_pin_internal[22] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_22_.Q;
assign lsu_ReadDataMWReg_pin_internal[23] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_23_.Q;
assign lsu_ReadDataMWReg_pin_internal[24] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_24_.Q;
assign lsu_ReadDataMWReg_pin_internal[25] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_25_.Q;
assign lsu_ReadDataMWReg_pin_internal[26] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_26_.Q;
assign lsu_ReadDataMWReg_pin_internal[27] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_27_.Q;
assign lsu_ReadDataMWReg_pin_internal[28] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_28_.Q;
assign lsu_ReadDataMWReg_pin_internal[29] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_29_.Q;
assign lsu_ReadDataMWReg_pin_internal[30] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_30_.Q;
assign lsu_ReadDataMWReg_pin_internal[31] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_31_.Q;
assign lsu_ReadDataMWReg_pin_internal[32] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_32_.Q;
assign lsu_ReadDataMWReg_pin_internal[33] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_33_.Q;
assign lsu_ReadDataMWReg_pin_internal[34] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_34_.Q;
assign lsu_ReadDataMWReg_pin_internal[35] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_35_.Q;
assign lsu_ReadDataMWReg_pin_internal[36] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_36_.Q;
assign lsu_ReadDataMWReg_pin_internal[37] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_37_.Q;
assign lsu_ReadDataMWReg_pin_internal[38] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_38_.Q;
assign lsu_ReadDataMWReg_pin_internal[39] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_39_.Q;
assign lsu_ReadDataMWReg_pin_internal[40] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_40_.Q;
assign lsu_ReadDataMWReg_pin_internal[41] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_41_.Q;
assign lsu_ReadDataMWReg_pin_internal[42] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_42_.Q;
assign lsu_ReadDataMWReg_pin_internal[43] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_43_.Q;
assign lsu_ReadDataMWReg_pin_internal[44] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_44_.Q;
assign lsu_ReadDataMWReg_pin_internal[45] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_45_.Q;
assign lsu_ReadDataMWReg_pin_internal[46] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_46_.Q;
assign lsu_ReadDataMWReg_pin_internal[47] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_47_.Q;
assign lsu_ReadDataMWReg_pin_internal[48] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_48_.Q;
assign lsu_ReadDataMWReg_pin_internal[49] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_49_.Q;
assign lsu_ReadDataMWReg_pin_internal[50] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_50_.Q;
assign lsu_ReadDataMWReg_pin_internal[51] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_51_.Q;
assign lsu_ReadDataMWReg_pin_internal[52] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_52_.Q;
assign lsu_ReadDataMWReg_pin_internal[53] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_53_.Q;
assign lsu_ReadDataMWReg_pin_internal[54] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_54_.Q;
assign lsu_ReadDataMWReg_pin_internal[55] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_55_.Q;
assign lsu_ReadDataMWReg_pin_internal[56] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_56_.Q;
assign lsu_ReadDataMWReg_pin_internal[57] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_57_.Q;
assign lsu_ReadDataMWReg_pin_internal[58] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_58_.Q;
assign lsu_ReadDataMWReg_pin_internal[59] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_59_.Q;
assign lsu_ReadDataMWReg_pin_internal[60] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_60_.Q;
assign lsu_ReadDataMWReg_pin_internal[61] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_61_.Q;
assign lsu_ReadDataMWReg_pin_internal[62] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_62_.Q;
assign lsu_ReadDataMWReg_pin_internal[63] = dut.chip.soc_core_lsu_ReadDataMWReg_q_reg_63_.Q;

// ---- lsu_ReadDataMWReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign lsu_ReadDataMWReg_raw_internal_available[0] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[1] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[2] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[3] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[4] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[5] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[6] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[7] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[8] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[9] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[10] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[11] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[12] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[13] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[14] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[15] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[16] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[17] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[18] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[19] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[20] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[21] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[22] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[23] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[24] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[25] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[26] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[27] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[28] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[29] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[30] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[31] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[32] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[33] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[34] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[35] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[36] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[37] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[38] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[39] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[40] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[41] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[42] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[43] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[44] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[45] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[46] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[47] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[48] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[49] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[50] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[51] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[52] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[53] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[54] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[55] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[56] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[57] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[58] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[59] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[60] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[61] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[62] = 1'b1;
assign lsu_ReadDataMWReg_raw_internal_available[63] = 1'b1;

// ============================================================================
// Register mdu_mdu_MDUResultWReg: 64 mapped bits, width 64
// ============================================================================

// Bus declarations
wire [63:0] mdu_mdu_MDUResultWReg_internal;
wire [63:0] mdu_mdu_MDUResultWReg_raw_internal;
wire [63:0] mdu_mdu_MDUResultWReg_pin_internal;
wire [63:0] mdu_mdu_MDUResultWReg_raw_internal_available;

// ---- mdu_mdu_MDUResultWReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign mdu_mdu_MDUResultWReg_raw_internal[0] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_0_.Q; // c5[170]
assign mdu_mdu_MDUResultWReg_raw_internal[1] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_1_.Q; // c5[171]
assign mdu_mdu_MDUResultWReg_raw_internal[2] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_2_.Q; // c5[172]
assign mdu_mdu_MDUResultWReg_raw_internal[3] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_3_.Q; // c5[173]
assign mdu_mdu_MDUResultWReg_raw_internal[4] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_4_.Q; // c5[174]
assign mdu_mdu_MDUResultWReg_raw_internal[5] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_5_.Q; // c5[175]
assign mdu_mdu_MDUResultWReg_raw_internal[6] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_6_.Q; // c5[176]
assign mdu_mdu_MDUResultWReg_raw_internal[7] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_7_.Q; // c5[177]
assign mdu_mdu_MDUResultWReg_raw_internal[8] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_8_.Q; // c5[178]
assign mdu_mdu_MDUResultWReg_raw_internal[9] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_9_.Q; // c5[179]
assign mdu_mdu_MDUResultWReg_raw_internal[10] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_10_.Q; // c5[180]
assign mdu_mdu_MDUResultWReg_raw_internal[11] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_11_.Q; // c5[181]
assign mdu_mdu_MDUResultWReg_raw_internal[12] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_12_.Q; // c5[182]
assign mdu_mdu_MDUResultWReg_raw_internal[13] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_13_.Q; // c5[183]
assign mdu_mdu_MDUResultWReg_raw_internal[14] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_14_.Q; // c5[184]
assign mdu_mdu_MDUResultWReg_raw_internal[15] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_15_.Q; // c5[185]
assign mdu_mdu_MDUResultWReg_raw_internal[16] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_16_.Q; // c5[186]
assign mdu_mdu_MDUResultWReg_raw_internal[17] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_17_.Q; // c6[1]
assign mdu_mdu_MDUResultWReg_raw_internal[18] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_18_.Q; // c6[2]
assign mdu_mdu_MDUResultWReg_raw_internal[19] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_19_.Q; // c6[3]
assign mdu_mdu_MDUResultWReg_raw_internal[20] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_20_.Q; // c6[4]
assign mdu_mdu_MDUResultWReg_raw_internal[21] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_21_.Q; // c6[5]
assign mdu_mdu_MDUResultWReg_raw_internal[22] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_22_.Q; // c6[6]
assign mdu_mdu_MDUResultWReg_raw_internal[23] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_23_.Q; // c6[7]
assign mdu_mdu_MDUResultWReg_raw_internal[24] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_24_.Q; // c6[8]
assign mdu_mdu_MDUResultWReg_raw_internal[25] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_25_.Q; // c6[9]
assign mdu_mdu_MDUResultWReg_raw_internal[26] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_26_.Q; // c6[10]
assign mdu_mdu_MDUResultWReg_raw_internal[27] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_27_.Q; // c6[11]
assign mdu_mdu_MDUResultWReg_raw_internal[28] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_28_.Q; // c6[12]
assign mdu_mdu_MDUResultWReg_raw_internal[29] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_29_.Q; // c6[13]
assign mdu_mdu_MDUResultWReg_raw_internal[30] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_30_.Q; // c6[14]
assign mdu_mdu_MDUResultWReg_raw_internal[31] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_31_.Q; // c6[15]
assign mdu_mdu_MDUResultWReg_raw_internal[32] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_32_.Q; // c6[16]
assign mdu_mdu_MDUResultWReg_raw_internal[33] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_33_.Q; // c6[17]
assign mdu_mdu_MDUResultWReg_raw_internal[34] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_34_.Q; // c6[18]
assign mdu_mdu_MDUResultWReg_raw_internal[35] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_35_.Q; // c6[19]
assign mdu_mdu_MDUResultWReg_raw_internal[36] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_36_.Q; // c6[20]
assign mdu_mdu_MDUResultWReg_raw_internal[37] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_37_.Q; // c6[21]
assign mdu_mdu_MDUResultWReg_raw_internal[38] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_38_.Q; // c6[22]
assign mdu_mdu_MDUResultWReg_raw_internal[39] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_39_.Q; // c6[23]
assign mdu_mdu_MDUResultWReg_raw_internal[40] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_40_.Q; // c6[24]
assign mdu_mdu_MDUResultWReg_raw_internal[41] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_41_.Q; // c6[25]
assign mdu_mdu_MDUResultWReg_raw_internal[42] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_42_.Q; // c6[26]
assign mdu_mdu_MDUResultWReg_raw_internal[43] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_43_.Q; // c6[27]
assign mdu_mdu_MDUResultWReg_raw_internal[44] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_44_.Q; // c6[28]
assign mdu_mdu_MDUResultWReg_raw_internal[45] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_45_.Q; // c6[29]
assign mdu_mdu_MDUResultWReg_raw_internal[46] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_46_.Q; // c6[30]
assign mdu_mdu_MDUResultWReg_raw_internal[47] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_47_.Q; // c6[31]
assign mdu_mdu_MDUResultWReg_raw_internal[48] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_48_.Q; // c6[32]
assign mdu_mdu_MDUResultWReg_raw_internal[49] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_49_.Q; // c6[33]
assign mdu_mdu_MDUResultWReg_raw_internal[50] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_50_.Q; // c6[34]
assign mdu_mdu_MDUResultWReg_raw_internal[51] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_51_.Q; // c6[35]
assign mdu_mdu_MDUResultWReg_raw_internal[52] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_52_.Q; // c6[36]
assign mdu_mdu_MDUResultWReg_raw_internal[53] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_53_.Q; // c6[37]
assign mdu_mdu_MDUResultWReg_raw_internal[54] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_54_.Q; // c6[38]
assign mdu_mdu_MDUResultWReg_raw_internal[55] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_55_.Q; // c6[39]
assign mdu_mdu_MDUResultWReg_raw_internal[56] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_56_.Q; // c6[40]
assign mdu_mdu_MDUResultWReg_raw_internal[57] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_57_.Q; // c6[41]
assign mdu_mdu_MDUResultWReg_raw_internal[58] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_58_.Q; // c6[42]
assign mdu_mdu_MDUResultWReg_raw_internal[59] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_59_.Q; // c6[43]
assign mdu_mdu_MDUResultWReg_raw_internal[60] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_60_.Q; // c6[44]
assign mdu_mdu_MDUResultWReg_raw_internal[61] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_61_.Q; // c6[45]
assign mdu_mdu_MDUResultWReg_raw_internal[62] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_62_.Q; // c6[46]
assign mdu_mdu_MDUResultWReg_raw_internal[63] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_63_.Q; // c6[47]

// ---- mdu_mdu_MDUResultWReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign mdu_mdu_MDUResultWReg_internal[0] = mdu_mdu_MDUResultWReg_raw_internal[0];
assign mdu_mdu_MDUResultWReg_internal[1] = mdu_mdu_MDUResultWReg_raw_internal[1];
assign mdu_mdu_MDUResultWReg_internal[2] = mdu_mdu_MDUResultWReg_raw_internal[2];
assign mdu_mdu_MDUResultWReg_internal[3] = mdu_mdu_MDUResultWReg_raw_internal[3];
assign mdu_mdu_MDUResultWReg_internal[4] = mdu_mdu_MDUResultWReg_raw_internal[4];
assign mdu_mdu_MDUResultWReg_internal[5] = mdu_mdu_MDUResultWReg_raw_internal[5];
assign mdu_mdu_MDUResultWReg_internal[6] = mdu_mdu_MDUResultWReg_raw_internal[6];
assign mdu_mdu_MDUResultWReg_internal[7] = mdu_mdu_MDUResultWReg_raw_internal[7];
assign mdu_mdu_MDUResultWReg_internal[8] = mdu_mdu_MDUResultWReg_raw_internal[8];
assign mdu_mdu_MDUResultWReg_internal[9] = mdu_mdu_MDUResultWReg_raw_internal[9];
assign mdu_mdu_MDUResultWReg_internal[10] = mdu_mdu_MDUResultWReg_raw_internal[10];
assign mdu_mdu_MDUResultWReg_internal[11] = mdu_mdu_MDUResultWReg_raw_internal[11];
assign mdu_mdu_MDUResultWReg_internal[12] = mdu_mdu_MDUResultWReg_raw_internal[12];
assign mdu_mdu_MDUResultWReg_internal[13] = mdu_mdu_MDUResultWReg_raw_internal[13];
assign mdu_mdu_MDUResultWReg_internal[14] = mdu_mdu_MDUResultWReg_raw_internal[14];
assign mdu_mdu_MDUResultWReg_internal[15] = mdu_mdu_MDUResultWReg_raw_internal[15];
assign mdu_mdu_MDUResultWReg_internal[16] = mdu_mdu_MDUResultWReg_raw_internal[16];
assign mdu_mdu_MDUResultWReg_internal[17] = mdu_mdu_MDUResultWReg_raw_internal[17];
assign mdu_mdu_MDUResultWReg_internal[18] = mdu_mdu_MDUResultWReg_raw_internal[18];
assign mdu_mdu_MDUResultWReg_internal[19] = mdu_mdu_MDUResultWReg_raw_internal[19];
assign mdu_mdu_MDUResultWReg_internal[20] = mdu_mdu_MDUResultWReg_raw_internal[20];
assign mdu_mdu_MDUResultWReg_internal[21] = mdu_mdu_MDUResultWReg_raw_internal[21];
assign mdu_mdu_MDUResultWReg_internal[22] = mdu_mdu_MDUResultWReg_raw_internal[22];
assign mdu_mdu_MDUResultWReg_internal[23] = mdu_mdu_MDUResultWReg_raw_internal[23];
assign mdu_mdu_MDUResultWReg_internal[24] = mdu_mdu_MDUResultWReg_raw_internal[24];
assign mdu_mdu_MDUResultWReg_internal[25] = mdu_mdu_MDUResultWReg_raw_internal[25];
assign mdu_mdu_MDUResultWReg_internal[26] = mdu_mdu_MDUResultWReg_raw_internal[26];
assign mdu_mdu_MDUResultWReg_internal[27] = mdu_mdu_MDUResultWReg_raw_internal[27];
assign mdu_mdu_MDUResultWReg_internal[28] = mdu_mdu_MDUResultWReg_raw_internal[28];
assign mdu_mdu_MDUResultWReg_internal[29] = mdu_mdu_MDUResultWReg_raw_internal[29];
assign mdu_mdu_MDUResultWReg_internal[30] = mdu_mdu_MDUResultWReg_raw_internal[30];
assign mdu_mdu_MDUResultWReg_internal[31] = mdu_mdu_MDUResultWReg_raw_internal[31];
assign mdu_mdu_MDUResultWReg_internal[32] = mdu_mdu_MDUResultWReg_raw_internal[32];
assign mdu_mdu_MDUResultWReg_internal[33] = mdu_mdu_MDUResultWReg_raw_internal[33];
assign mdu_mdu_MDUResultWReg_internal[34] = mdu_mdu_MDUResultWReg_raw_internal[34];
assign mdu_mdu_MDUResultWReg_internal[35] = mdu_mdu_MDUResultWReg_raw_internal[35];
assign mdu_mdu_MDUResultWReg_internal[36] = mdu_mdu_MDUResultWReg_raw_internal[36];
assign mdu_mdu_MDUResultWReg_internal[37] = mdu_mdu_MDUResultWReg_raw_internal[37];
assign mdu_mdu_MDUResultWReg_internal[38] = mdu_mdu_MDUResultWReg_raw_internal[38];
assign mdu_mdu_MDUResultWReg_internal[39] = mdu_mdu_MDUResultWReg_raw_internal[39];
assign mdu_mdu_MDUResultWReg_internal[40] = mdu_mdu_MDUResultWReg_raw_internal[40];
assign mdu_mdu_MDUResultWReg_internal[41] = mdu_mdu_MDUResultWReg_raw_internal[41];
assign mdu_mdu_MDUResultWReg_internal[42] = mdu_mdu_MDUResultWReg_raw_internal[42];
assign mdu_mdu_MDUResultWReg_internal[43] = mdu_mdu_MDUResultWReg_raw_internal[43];
assign mdu_mdu_MDUResultWReg_internal[44] = mdu_mdu_MDUResultWReg_raw_internal[44];
assign mdu_mdu_MDUResultWReg_internal[45] = mdu_mdu_MDUResultWReg_raw_internal[45];
assign mdu_mdu_MDUResultWReg_internal[46] = mdu_mdu_MDUResultWReg_raw_internal[46];
assign mdu_mdu_MDUResultWReg_internal[47] = mdu_mdu_MDUResultWReg_raw_internal[47];
assign mdu_mdu_MDUResultWReg_internal[48] = mdu_mdu_MDUResultWReg_raw_internal[48];
assign mdu_mdu_MDUResultWReg_internal[49] = mdu_mdu_MDUResultWReg_raw_internal[49];
assign mdu_mdu_MDUResultWReg_internal[50] = mdu_mdu_MDUResultWReg_raw_internal[50];
assign mdu_mdu_MDUResultWReg_internal[51] = mdu_mdu_MDUResultWReg_raw_internal[51];
assign mdu_mdu_MDUResultWReg_internal[52] = mdu_mdu_MDUResultWReg_raw_internal[52];
assign mdu_mdu_MDUResultWReg_internal[53] = mdu_mdu_MDUResultWReg_raw_internal[53];
assign mdu_mdu_MDUResultWReg_internal[54] = mdu_mdu_MDUResultWReg_raw_internal[54];
assign mdu_mdu_MDUResultWReg_internal[55] = mdu_mdu_MDUResultWReg_raw_internal[55];
assign mdu_mdu_MDUResultWReg_internal[56] = mdu_mdu_MDUResultWReg_raw_internal[56];
assign mdu_mdu_MDUResultWReg_internal[57] = mdu_mdu_MDUResultWReg_raw_internal[57];
assign mdu_mdu_MDUResultWReg_internal[58] = mdu_mdu_MDUResultWReg_raw_internal[58];
assign mdu_mdu_MDUResultWReg_internal[59] = mdu_mdu_MDUResultWReg_raw_internal[59];
assign mdu_mdu_MDUResultWReg_internal[60] = mdu_mdu_MDUResultWReg_raw_internal[60];
assign mdu_mdu_MDUResultWReg_internal[61] = mdu_mdu_MDUResultWReg_raw_internal[61];
assign mdu_mdu_MDUResultWReg_internal[62] = mdu_mdu_MDUResultWReg_raw_internal[62];
assign mdu_mdu_MDUResultWReg_internal[63] = mdu_mdu_MDUResultWReg_raw_internal[63];

// ---- mdu_mdu_MDUResultWReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign mdu_mdu_MDUResultWReg_pin_internal[0] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_0_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[1] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_1_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[2] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_2_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[3] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_3_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[4] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_4_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[5] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_5_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[6] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_6_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[7] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_7_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[8] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_8_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[9] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_9_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[10] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_10_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[11] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_11_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[12] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_12_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[13] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_13_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[14] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_14_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[15] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_15_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[16] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_16_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[17] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_17_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[18] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_18_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[19] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_19_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[20] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_20_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[21] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_21_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[22] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_22_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[23] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_23_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[24] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_24_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[25] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_25_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[26] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_26_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[27] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_27_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[28] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_28_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[29] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_29_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[30] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_30_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[31] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_31_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[32] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_32_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[33] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_33_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[34] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_34_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[35] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_35_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[36] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_36_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[37] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_37_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[38] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_38_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[39] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_39_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[40] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_40_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[41] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_41_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[42] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_42_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[43] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_43_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[44] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_44_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[45] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_45_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[46] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_46_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[47] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_47_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[48] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_48_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[49] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_49_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[50] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_50_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[51] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_51_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[52] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_52_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[53] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_53_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[54] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_54_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[55] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_55_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[56] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_56_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[57] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_57_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[58] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_58_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[59] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_59_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[60] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_60_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[61] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_61_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[62] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_62_.Q;
assign mdu_mdu_MDUResultWReg_pin_internal[63] = dut.chip.soc_core_mdu_mdu_MDUResultWReg_q_reg_63_.Q;

// ---- mdu_mdu_MDUResultWReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign mdu_mdu_MDUResultWReg_raw_internal_available[0] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[1] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[2] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[3] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[4] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[5] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[6] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[7] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[8] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[9] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[10] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[11] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[12] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[13] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[14] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[15] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[16] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[17] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[18] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[19] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[20] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[21] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[22] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[23] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[24] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[25] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[26] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[27] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[28] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[29] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[30] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[31] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[32] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[33] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[34] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[35] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[36] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[37] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[38] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[39] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[40] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[41] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[42] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[43] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[44] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[45] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[46] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[47] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[48] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[49] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[50] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[51] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[52] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[53] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[54] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[55] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[56] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[57] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[58] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[59] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[60] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[61] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[62] = 1'b1;
assign mdu_mdu_MDUResultWReg_raw_internal_available[63] = 1'b1;

// ============================================================================
// Register mdu_mdu_W64MReg: 1 mapped bits, width 1
// ============================================================================

// Bus declarations
wire [0:0] mdu_mdu_W64MReg_internal;
wire [0:0] mdu_mdu_W64MReg_raw_internal;
wire [0:0] mdu_mdu_W64MReg_pin_internal;
wire [0:0] mdu_mdu_W64MReg_raw_internal_available;

// ---- mdu_mdu_W64MReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign mdu_mdu_W64MReg_raw_internal[0] = dut.chip.soc_core_mdu_mdu_W64MReg_q_reg_0_.Q; // c6[48]

// ---- mdu_mdu_W64MReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign mdu_mdu_W64MReg_internal[0] = mdu_mdu_W64MReg_raw_internal[0];

// ---- mdu_mdu_W64MReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign mdu_mdu_W64MReg_pin_internal[0] = dut.chip.soc_core_mdu_mdu_W64MReg_q_reg_0_.Q;

// ---- mdu_mdu_W64MReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign mdu_mdu_W64MReg_raw_internal_available[0] = 1'b1;

// ============================================================================
// Register mdu_mdu_div_divfaultreg: 1 mapped bits, width 1
// ============================================================================

// Bus declarations
wire [0:0] mdu_mdu_div_divfaultreg_internal;
wire [0:0] mdu_mdu_div_divfaultreg_raw_internal;
wire [0:0] mdu_mdu_div_divfaultreg_pin_internal;
wire [0:0] mdu_mdu_div_divfaultreg_raw_internal_available;

// ---- mdu_mdu_div_divfaultreg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign mdu_mdu_div_divfaultreg_raw_internal[0] = dut.chip.soc_core_mdu_mdu_div_divfaultreg_q_reg_0_.Q; // c6[49]

// ---- mdu_mdu_div_divfaultreg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign mdu_mdu_div_divfaultreg_internal[0] = mdu_mdu_div_divfaultreg_raw_internal[0];

// ---- mdu_mdu_div_divfaultreg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign mdu_mdu_div_divfaultreg_pin_internal[0] = dut.chip.soc_core_mdu_mdu_div_divfaultreg_q_reg_0_.Q;

// ---- mdu_mdu_div_divfaultreg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign mdu_mdu_div_divfaultreg_raw_internal_available[0] = 1'b1;

// ============================================================================
// Register mdu_mdu_ftmul_primary_PP1Reg: 127 mapped bits, width 127
// ============================================================================

// Bus declarations
wire [126:0] mdu_mdu_ftmul_primary_PP1Reg_internal;
wire [126:0] mdu_mdu_ftmul_primary_PP1Reg_raw_internal;
wire [126:0] mdu_mdu_ftmul_primary_PP1Reg_pin_internal;
wire [126:0] mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available;

// ---- mdu_mdu_ftmul_primary_PP1Reg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[0] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_0_.Q; // c6[50]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[1] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_1_.Q; // c6[51]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[2] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_2_.Q; // c6[52]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[3] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_3_.Q; // c6[53]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[4] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_4_.Q; // c6[54]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[5] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_5_.Q; // c6[55]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[6] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_6_.Q; // c6[56]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[7] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_7_.Q; // c6[57]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[8] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_8_.Q; // c6[58]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[9] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_9_.Q; // c6[59]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[10] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_10_.Q; // c6[60]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[11] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_11_.Q; // c6[61]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[12] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_12_.Q; // c6[62]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[13] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_13_.Q; // c6[63]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[14] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_14_.Q; // c6[64]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[15] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_15_.Q; // c6[65]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[16] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_16_.Q; // c6[66]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[17] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_17_.Q; // c6[67]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[18] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_18_.Q; // c6[68]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[19] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_19_.Q; // c6[69]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[20] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_20_.Q; // c6[70]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[21] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_21_.Q; // c6[71]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[22] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_22_.Q; // c6[72]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[23] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_23_.Q; // c6[73]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[24] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_24_.Q; // c6[74]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[25] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_25_.Q; // c6[75]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[26] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_26_.Q; // c6[76]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[27] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_27_.Q; // c6[77]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[28] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_28_.Q; // c6[78]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[29] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_29_.Q; // c6[79]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[30] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_30_.Q; // c6[80]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[31] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_31_.Q; // c6[81]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[32] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_32_.Q; // c6[82]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[33] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_33_.Q; // c6[83]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[34] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_34_.Q; // c6[84]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[35] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_35_.Q; // c6[85]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[36] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_36_.Q; // c6[86]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[37] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_37_.Q; // c6[87]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[38] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_38_.Q; // c6[88]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[39] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_39_.Q; // c6[89]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[40] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_40_.Q; // c6[90]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[41] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_41_.Q; // c6[91]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[42] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_42_.Q; // c6[92]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[43] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_43_.Q; // c6[93]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[44] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_44_.Q; // c6[94]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[45] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_45_.Q; // c6[95]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[46] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_46_.Q; // c6[96]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[47] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_47_.Q; // c6[97]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[48] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_48_.Q; // c6[98]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[49] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_49_.Q; // c6[99]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[50] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_50_.Q; // c6[100]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[51] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_51_.Q; // c6[101]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[52] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_52_.Q; // c6[102]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[53] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_53_.Q; // c6[103]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[54] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_54_.Q; // c6[104]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[55] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_55_.Q; // c6[105]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[56] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_56_.Q; // c6[106]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[57] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_57_.Q; // c6[107]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[58] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_58_.Q; // c6[108]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[59] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_59_.Q; // c6[109]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[60] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_60_.Q; // c6[110]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[61] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_61_.Q; // c6[111]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[62] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_62_.Q; // c6[112]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[63] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_63_.Q; // c6[113]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[64] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_64_.Q; // c6[114]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[65] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_65_.Q; // c6[115]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[66] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_66_.Q; // c6[116]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[67] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_67_.Q; // c6[117]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[68] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_68_.Q; // c6[118]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[69] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_69_.Q; // c6[119]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[70] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_70_.Q; // c6[120]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[71] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_71_.Q; // c6[121]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[72] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_72_.Q; // c6[122]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[73] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_73_.Q; // c6[123]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[74] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_74_.Q; // c6[124]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[75] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_75_.Q; // c6[125]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[76] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_76_.Q; // c6[126]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[77] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_77_.Q; // c6[127]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[78] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_78_.Q; // c6[128]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[79] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_79_.Q; // c6[129]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[80] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_80_.Q; // c6[130]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[81] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_81_.Q; // c6[131]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[82] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_82_.Q; // c6[132]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[83] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_83_.Q; // c6[133]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[84] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_84_.Q; // c6[134]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[85] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_85_.Q; // c6[135]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[86] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_86_.Q; // c6[136]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[87] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_87_.Q; // c6[137]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[88] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_88_.Q; // c6[138]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[89] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_89_.Q; // c6[139]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[90] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_90_.Q; // c6[140]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[91] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_91_.Q; // c6[141]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[92] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_92_.Q; // c6[142]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[93] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_93_.Q; // c6[143]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[94] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_94_.Q; // c6[144]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[95] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_95_.Q; // c6[145]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[96] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_96_.Q; // c6[146]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[97] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_97_.Q; // c6[147]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[98] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_98_.Q; // c6[148]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[99] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_99_.Q; // c6[149]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[100] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_100_.Q; // c6[150]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[101] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_101_.Q; // c6[151]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[102] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_102_.Q; // c6[152]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[103] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_103_.Q; // c6[153]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[104] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_104_.Q; // c6[154]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[105] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_105_.Q; // c6[155]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[106] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_106_.Q; // c6[156]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[107] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_107_.Q; // c6[157]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[108] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_108_.Q; // c6[158]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[109] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_109_.Q; // c6[159]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[110] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_110_.Q; // c6[160]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[111] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_111_.Q; // c6[161]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[112] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_112_.Q; // c6[162]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[113] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_113_.Q; // c6[163]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[114] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_114_.Q; // c6[164]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[115] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_115_.Q; // c6[165]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[116] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_116_.Q; // c6[166]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[117] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_117_.Q; // c6[167]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[118] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_118_.Q; // c6[168]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[119] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_119_.Q; // c6[169]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[120] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_120_.Q; // c6[170]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[121] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_121_.Q; // c6[171]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[122] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_122_.Q; // c6[172]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[123] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_123_.Q; // c6[173]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[124] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_124_.Q; // c6[174]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[125] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_125_.Q; // c6[175]
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal[126] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_126_.Q; // c6[176]

// ---- mdu_mdu_ftmul_primary_PP1Reg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign mdu_mdu_ftmul_primary_PP1Reg_internal[0] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[0];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[1] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[1];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[2] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[2];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[3] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[3];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[4] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[4];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[5] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[5];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[6] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[6];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[7] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[7];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[8] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[8];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[9] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[9];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[10] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[10];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[11] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[11];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[12] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[12];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[13] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[13];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[14] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[14];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[15] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[15];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[16] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[16];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[17] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[17];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[18] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[18];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[19] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[19];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[20] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[20];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[21] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[21];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[22] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[22];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[23] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[23];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[24] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[24];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[25] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[25];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[26] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[26];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[27] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[27];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[28] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[28];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[29] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[29];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[30] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[30];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[31] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[31];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[32] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[32];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[33] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[33];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[34] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[34];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[35] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[35];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[36] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[36];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[37] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[37];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[38] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[38];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[39] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[39];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[40] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[40];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[41] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[41];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[42] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[42];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[43] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[43];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[44] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[44];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[45] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[45];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[46] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[46];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[47] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[47];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[48] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[48];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[49] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[49];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[50] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[50];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[51] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[51];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[52] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[52];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[53] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[53];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[54] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[54];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[55] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[55];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[56] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[56];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[57] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[57];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[58] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[58];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[59] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[59];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[60] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[60];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[61] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[61];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[62] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[62];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[63] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[63];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[64] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[64];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[65] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[65];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[66] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[66];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[67] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[67];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[68] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[68];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[69] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[69];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[70] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[70];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[71] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[71];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[72] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[72];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[73] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[73];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[74] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[74];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[75] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[75];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[76] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[76];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[77] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[77];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[78] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[78];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[79] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[79];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[80] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[80];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[81] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[81];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[82] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[82];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[83] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[83];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[84] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[84];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[85] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[85];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[86] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[86];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[87] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[87];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[88] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[88];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[89] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[89];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[90] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[90];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[91] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[91];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[92] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[92];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[93] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[93];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[94] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[94];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[95] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[95];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[96] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[96];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[97] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[97];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[98] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[98];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[99] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[99];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[100] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[100];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[101] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[101];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[102] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[102];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[103] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[103];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[104] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[104];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[105] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[105];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[106] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[106];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[107] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[107];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[108] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[108];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[109] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[109];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[110] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[110];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[111] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[111];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[112] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[112];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[113] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[113];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[114] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[114];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[115] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[115];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[116] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[116];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[117] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[117];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[118] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[118];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[119] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[119];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[120] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[120];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[121] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[121];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[122] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[122];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[123] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[123];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[124] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[124];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[125] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[125];
assign mdu_mdu_ftmul_primary_PP1Reg_internal[126] = mdu_mdu_ftmul_primary_PP1Reg_raw_internal[126];

// ---- mdu_mdu_ftmul_primary_PP1Reg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[0] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_0_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[1] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_1_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[2] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_2_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[3] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_3_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[4] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_4_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[5] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_5_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[6] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_6_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[7] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_7_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[8] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_8_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[9] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_9_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[10] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_10_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[11] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_11_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[12] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_12_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[13] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_13_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[14] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_14_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[15] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_15_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[16] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_16_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[17] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_17_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[18] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_18_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[19] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_19_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[20] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_20_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[21] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_21_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[22] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_22_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[23] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_23_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[24] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_24_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[25] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_25_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[26] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_26_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[27] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_27_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[28] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_28_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[29] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_29_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[30] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_30_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[31] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_31_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[32] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_32_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[33] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_33_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[34] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_34_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[35] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_35_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[36] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_36_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[37] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_37_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[38] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_38_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[39] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_39_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[40] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_40_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[41] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_41_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[42] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_42_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[43] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_43_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[44] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_44_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[45] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_45_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[46] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_46_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[47] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_47_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[48] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_48_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[49] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_49_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[50] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_50_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[51] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_51_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[52] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_52_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[53] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_53_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[54] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_54_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[55] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_55_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[56] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_56_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[57] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_57_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[58] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_58_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[59] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_59_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[60] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_60_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[61] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_61_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[62] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_62_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[63] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_63_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[64] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_64_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[65] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_65_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[66] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_66_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[67] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_67_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[68] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_68_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[69] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_69_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[70] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_70_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[71] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_71_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[72] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_72_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[73] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_73_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[74] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_74_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[75] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_75_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[76] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_76_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[77] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_77_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[78] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_78_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[79] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_79_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[80] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_80_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[81] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_81_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[82] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_82_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[83] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_83_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[84] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_84_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[85] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_85_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[86] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_86_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[87] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_87_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[88] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_88_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[89] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_89_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[90] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_90_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[91] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_91_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[92] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_92_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[93] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_93_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[94] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_94_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[95] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_95_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[96] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_96_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[97] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_97_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[98] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_98_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[99] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_99_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[100] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_100_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[101] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_101_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[102] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_102_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[103] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_103_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[104] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_104_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[105] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_105_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[106] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_106_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[107] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_107_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[108] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_108_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[109] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_109_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[110] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_110_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[111] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_111_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[112] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_112_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[113] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_113_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[114] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_114_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[115] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_115_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[116] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_116_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[117] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_117_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[118] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_118_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[119] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_119_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[120] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_120_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[121] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_121_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[122] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_122_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[123] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_123_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[124] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_124_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[125] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_125_.Q;
assign mdu_mdu_ftmul_primary_PP1Reg_pin_internal[126] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP1Reg_q_reg_126_.Q;

// ---- mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[0] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[1] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[2] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[3] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[4] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[5] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[6] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[7] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[8] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[9] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[10] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[11] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[12] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[13] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[14] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[15] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[16] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[17] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[18] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[19] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[20] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[21] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[22] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[23] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[24] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[25] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[26] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[27] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[28] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[29] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[30] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[31] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[32] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[33] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[34] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[35] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[36] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[37] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[38] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[39] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[40] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[41] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[42] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[43] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[44] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[45] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[46] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[47] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[48] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[49] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[50] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[51] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[52] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[53] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[54] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[55] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[56] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[57] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[58] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[59] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[60] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[61] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[62] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[63] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[64] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[65] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[66] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[67] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[68] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[69] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[70] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[71] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[72] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[73] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[74] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[75] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[76] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[77] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[78] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[79] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[80] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[81] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[82] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[83] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[84] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[85] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[86] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[87] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[88] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[89] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[90] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[91] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[92] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[93] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[94] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[95] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[96] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[97] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[98] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[99] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[100] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[101] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[102] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[103] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[104] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[105] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[106] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[107] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[108] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[109] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[110] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[111] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[112] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[113] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[114] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[115] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[116] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[117] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[118] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[119] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[120] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[121] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[122] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[123] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[124] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[125] = 1'b1;
assign mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available[126] = 1'b1;

// ============================================================================
// Register mdu_mdu_ftmul_primary_PP2Reg: 63 mapped bits, width 126
// ============================================================================

// Bus declarations
wire [125:0] mdu_mdu_ftmul_primary_PP2Reg_internal;
wire [125:0] mdu_mdu_ftmul_primary_PP2Reg_raw_internal;
wire [125:0] mdu_mdu_ftmul_primary_PP2Reg_pin_internal;
wire [125:0] mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available;

// ---- mdu_mdu_ftmul_primary_PP2Reg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[0] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[1] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[2] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[3] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[4] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[5] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[6] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[7] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[8] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[9] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[10] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[11] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[12] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[13] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[14] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[15] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[16] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[17] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[18] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[19] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[20] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[21] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[22] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[23] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[24] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[25] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[26] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[27] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[28] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[29] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[30] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[31] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[32] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[33] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[34] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[35] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[36] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[37] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[38] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[39] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[40] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[41] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[42] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[43] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[44] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[45] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[46] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[47] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[48] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[49] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[50] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[51] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[52] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[53] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[54] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[55] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[56] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[57] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[58] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[59] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[60] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[61] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[62] = 1'bz; // unavailable physical Q
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[63] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_63_.Q; // c6[177]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[64] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_64_.Q; // c6[178]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[65] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_65_.Q; // c6[179]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[66] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_66_.Q; // c6[180]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[67] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_67_.Q; // c6[181]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[68] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_68_.Q; // c6[182]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[69] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_69_.Q; // c6[183]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[70] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_70_.Q; // c6[184]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[71] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_71_.Q; // c6[185]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[72] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_72_.Q; // c6[186]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[73] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_73_.Q; // c7[1]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[74] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_74_.Q; // c7[2]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[75] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_75_.Q; // c7[3]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[76] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_76_.Q; // c7[4]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[77] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_77_.Q; // c7[5]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[78] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_78_.Q; // c7[6]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[79] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_79_.Q; // c7[7]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[80] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_80_.Q; // c7[8]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[81] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_81_.Q; // c7[9]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[82] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_82_.Q; // c7[10]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[83] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_83_.Q; // c7[11]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[84] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_84_.Q; // c7[12]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[85] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_85_.Q; // c7[13]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[86] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_86_.Q; // c7[14]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[87] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_87_.Q; // c7[15]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[88] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_88_.Q; // c7[16]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[89] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_89_.Q; // c7[17]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[90] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_90_.Q; // c7[18]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[91] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_91_.Q; // c7[19]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[92] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_92_.Q; // c7[20]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[93] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_93_.Q; // c7[21]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[94] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_94_.Q; // c7[22]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[95] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_95_.Q; // c7[23]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[96] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_96_.Q; // c7[24]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[97] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_97_.Q; // c7[25]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[98] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_98_.Q; // c7[26]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[99] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_99_.Q; // c7[27]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[100] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_100_.Q; // c7[28]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[101] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_101_.Q; // c7[29]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[102] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_102_.Q; // c7[30]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[103] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_103_.Q; // c7[31]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[104] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_104_.Q; // c7[32]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[105] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_105_.Q; // c7[33]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[106] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_106_.Q; // c7[34]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[107] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_107_.Q; // c7[35]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[108] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_108_.Q; // c7[36]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[109] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_109_.Q; // c7[37]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[110] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_110_.Q; // c7[38]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[111] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_111_.Q; // c7[39]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[112] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_112_.Q; // c7[40]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[113] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_113_.Q; // c7[41]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[114] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_114_.Q; // c7[42]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[115] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_115_.Q; // c7[43]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[116] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_116_.Q; // c7[44]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[117] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_117_.Q; // c7[45]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[118] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_118_.Q; // c7[46]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[119] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_119_.Q; // c7[47]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[120] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_120_.Q; // c7[48]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[121] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_121_.Q; // c7[49]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[122] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_122_.Q; // c7[50]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[123] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_123_.Q; // c7[51]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[124] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_124_.Q; // c7[52]
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal[125] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_125_.Q; // c7[53]

// ---- mdu_mdu_ftmul_primary_PP2Reg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign mdu_mdu_ftmul_primary_PP2Reg_internal[0] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[1] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[2] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[3] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[4] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[5] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[6] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[7] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[8] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[9] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[10] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[11] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[12] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[13] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[14] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[15] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[16] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[17] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[18] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[19] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[20] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[21] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[22] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[23] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[24] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[25] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[26] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[27] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[28] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[29] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[30] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[31] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[32] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[33] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[34] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[35] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[36] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[37] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[38] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[39] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[40] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[41] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[42] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[43] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[44] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[45] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[46] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[47] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[48] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[49] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[50] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[51] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[52] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[53] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[54] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[55] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[56] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[57] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[58] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[59] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[60] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[61] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[62] = 1'bz; // unavailable logical estimate
assign mdu_mdu_ftmul_primary_PP2Reg_internal[63] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[63];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[64] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[64];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[65] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[65];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[66] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[66];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[67] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[67];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[68] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[68];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[69] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[69];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[70] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[70];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[71] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[71];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[72] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[72];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[73] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[73];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[74] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[74];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[75] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[75];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[76] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[76];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[77] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[77];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[78] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[78];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[79] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[79];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[80] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[80];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[81] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[81];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[82] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[82];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[83] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[83];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[84] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[84];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[85] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[85];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[86] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[86];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[87] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[87];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[88] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[88];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[89] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[89];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[90] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[90];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[91] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[91];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[92] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[92];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[93] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[93];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[94] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[94];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[95] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[95];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[96] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[96];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[97] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[97];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[98] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[98];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[99] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[99];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[100] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[100];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[101] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[101];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[102] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[102];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[103] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[103];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[104] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[104];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[105] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[105];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[106] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[106];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[107] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[107];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[108] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[108];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[109] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[109];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[110] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[110];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[111] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[111];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[112] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[112];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[113] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[113];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[114] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[114];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[115] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[115];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[116] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[116];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[117] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[117];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[118] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[118];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[119] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[119];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[120] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[120];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[121] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[121];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[122] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[122];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[123] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[123];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[124] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[124];
assign mdu_mdu_ftmul_primary_PP2Reg_internal[125] = mdu_mdu_ftmul_primary_PP2Reg_raw_internal[125];

// ---- mdu_mdu_ftmul_primary_PP2Reg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[0] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[1] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[2] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[3] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[4] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[5] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[6] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[7] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[8] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[9] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[10] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[11] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[12] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[13] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[14] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[15] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[16] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[17] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[18] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[19] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[20] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[21] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[22] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[23] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[24] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[25] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[26] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[27] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[28] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[29] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[30] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[31] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[32] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[33] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[34] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[35] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[36] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[37] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[38] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[39] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[40] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[41] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[42] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[43] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[44] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[45] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[46] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[47] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[48] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[49] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[50] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[51] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[52] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[53] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[54] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[55] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[56] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[57] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[58] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[59] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[60] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[61] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[62] = 1'bz; // unavailable scan pin
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[63] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_63_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[64] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_64_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[65] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_65_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[66] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_66_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[67] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_67_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[68] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_68_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[69] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_69_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[70] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_70_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[71] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_71_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[72] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_72_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[73] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_73_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[74] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_74_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[75] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_75_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[76] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_76_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[77] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_77_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[78] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_78_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[79] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_79_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[80] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_80_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[81] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_81_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[82] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_82_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[83] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_83_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[84] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_84_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[85] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_85_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[86] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_86_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[87] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_87_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[88] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_88_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[89] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_89_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[90] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_90_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[91] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_91_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[92] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_92_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[93] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_93_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[94] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_94_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[95] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_95_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[96] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_96_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[97] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_97_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[98] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_98_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[99] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_99_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[100] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_100_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[101] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_101_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[102] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_102_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[103] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_103_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[104] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_104_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[105] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_105_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[106] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_106_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[107] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_107_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[108] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_108_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[109] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_109_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[110] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_110_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[111] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_111_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[112] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_112_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[113] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_113_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[114] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_114_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[115] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_115_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[116] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_116_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[117] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_117_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[118] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_118_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[119] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_119_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[120] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_120_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[121] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_121_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[122] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_122_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[123] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_123_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[124] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_124_.Q;
assign mdu_mdu_ftmul_primary_PP2Reg_pin_internal[125] = dut.chip.soc_core_mdu_mdu_ftmul_primary_PP2Reg_q_reg_125_.Q;

// ---- mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[0] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[1] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[2] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[3] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[4] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[5] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[6] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[7] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[8] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[9] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[10] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[11] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[12] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[13] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[14] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[15] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[16] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[17] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[18] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[19] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[20] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[21] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[22] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[23] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[24] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[25] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[26] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[27] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[28] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[29] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[30] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[31] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[32] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[33] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[34] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[35] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[36] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[37] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[38] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[39] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[40] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[41] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[42] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[43] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[44] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[45] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[46] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[47] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[48] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[49] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[50] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[51] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[52] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[53] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[54] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[55] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[56] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[57] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[58] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[59] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[60] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[61] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[62] = 1'b0;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[63] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[64] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[65] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[66] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[67] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[68] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[69] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[70] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[71] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[72] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[73] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[74] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[75] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[76] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[77] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[78] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[79] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[80] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[81] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[82] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[83] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[84] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[85] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[86] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[87] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[88] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[89] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[90] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[91] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[92] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[93] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[94] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[95] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[96] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[97] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[98] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[99] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[100] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[101] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[102] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[103] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[104] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[105] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[106] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[107] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[108] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[109] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[110] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[111] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[112] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[113] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[114] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[115] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[116] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[117] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[118] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[119] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[120] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[121] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[122] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[123] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[124] = 1'b1;
assign mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available[125] = 1'b1;

// ============================================================================
// Register priv_priv_csr_CSRValWReg: 64 mapped bits, width 64
// ============================================================================

// Bus declarations
wire [63:0] priv_priv_csr_CSRValWReg_internal;
wire [63:0] priv_priv_csr_CSRValWReg_raw_internal;
wire [63:0] priv_priv_csr_CSRValWReg_pin_internal;
wire [63:0] priv_priv_csr_CSRValWReg_raw_internal_available;

// ---- priv_priv_csr_CSRValWReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign priv_priv_csr_CSRValWReg_raw_internal[0] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_0_.Q; // c7[54]
assign priv_priv_csr_CSRValWReg_raw_internal[1] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_1_.Q; // c7[55]
assign priv_priv_csr_CSRValWReg_raw_internal[2] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_2_.Q; // c7[56]
assign priv_priv_csr_CSRValWReg_raw_internal[3] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_3_.Q; // c7[57]
assign priv_priv_csr_CSRValWReg_raw_internal[4] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_4_.Q; // c7[58]
assign priv_priv_csr_CSRValWReg_raw_internal[5] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_5_.Q; // c7[59]
assign priv_priv_csr_CSRValWReg_raw_internal[6] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_6_.Q; // c7[60]
assign priv_priv_csr_CSRValWReg_raw_internal[7] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_7_.Q; // c7[61]
assign priv_priv_csr_CSRValWReg_raw_internal[8] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_8_.Q; // c7[62]
assign priv_priv_csr_CSRValWReg_raw_internal[9] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_9_.Q; // c7[63]
assign priv_priv_csr_CSRValWReg_raw_internal[10] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_10_.Q; // c7[64]
assign priv_priv_csr_CSRValWReg_raw_internal[11] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_11_.Q; // c7[65]
assign priv_priv_csr_CSRValWReg_raw_internal[12] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_12_.Q; // c7[66]
assign priv_priv_csr_CSRValWReg_raw_internal[13] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_13_.Q; // c7[67]
assign priv_priv_csr_CSRValWReg_raw_internal[14] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_14_.Q; // c7[68]
assign priv_priv_csr_CSRValWReg_raw_internal[15] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_15_.Q; // c7[69]
assign priv_priv_csr_CSRValWReg_raw_internal[16] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_16_.Q; // c7[70]
assign priv_priv_csr_CSRValWReg_raw_internal[17] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_17_.Q; // c7[71]
assign priv_priv_csr_CSRValWReg_raw_internal[18] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_18_.Q; // c7[72]
assign priv_priv_csr_CSRValWReg_raw_internal[19] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_19_.Q; // c7[73]
assign priv_priv_csr_CSRValWReg_raw_internal[20] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_20_.Q; // c7[74]
assign priv_priv_csr_CSRValWReg_raw_internal[21] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_21_.Q; // c7[75]
assign priv_priv_csr_CSRValWReg_raw_internal[22] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_22_.Q; // c7[76]
assign priv_priv_csr_CSRValWReg_raw_internal[23] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_23_.Q; // c7[77]
assign priv_priv_csr_CSRValWReg_raw_internal[24] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_24_.Q; // c7[78]
assign priv_priv_csr_CSRValWReg_raw_internal[25] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_25_.Q; // c7[79]
assign priv_priv_csr_CSRValWReg_raw_internal[26] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_26_.Q; // c7[80]
assign priv_priv_csr_CSRValWReg_raw_internal[27] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_27_.Q; // c7[81]
assign priv_priv_csr_CSRValWReg_raw_internal[28] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_28_.Q; // c7[82]
assign priv_priv_csr_CSRValWReg_raw_internal[29] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_29_.Q; // c7[83]
assign priv_priv_csr_CSRValWReg_raw_internal[30] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_30_.Q; // c7[84]
assign priv_priv_csr_CSRValWReg_raw_internal[31] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_31_.Q; // c7[85]
assign priv_priv_csr_CSRValWReg_raw_internal[32] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_32_.Q; // c7[86]
assign priv_priv_csr_CSRValWReg_raw_internal[33] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_33_.Q; // c7[87]
assign priv_priv_csr_CSRValWReg_raw_internal[34] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_34_.Q; // c7[88]
assign priv_priv_csr_CSRValWReg_raw_internal[35] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_35_.Q; // c7[89]
assign priv_priv_csr_CSRValWReg_raw_internal[36] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_36_.Q; // c7[90]
assign priv_priv_csr_CSRValWReg_raw_internal[37] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_37_.Q; // c7[91]
assign priv_priv_csr_CSRValWReg_raw_internal[38] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_38_.Q; // c7[92]
assign priv_priv_csr_CSRValWReg_raw_internal[39] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_39_.Q; // c7[93]
assign priv_priv_csr_CSRValWReg_raw_internal[40] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_40_.Q; // c7[94]
assign priv_priv_csr_CSRValWReg_raw_internal[41] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_41_.Q; // c7[95]
assign priv_priv_csr_CSRValWReg_raw_internal[42] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_42_.Q; // c7[96]
assign priv_priv_csr_CSRValWReg_raw_internal[43] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_43_.Q; // c7[97]
assign priv_priv_csr_CSRValWReg_raw_internal[44] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_44_.Q; // c7[98]
assign priv_priv_csr_CSRValWReg_raw_internal[45] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_45_.Q; // c7[99]
assign priv_priv_csr_CSRValWReg_raw_internal[46] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_46_.Q; // c7[100]
assign priv_priv_csr_CSRValWReg_raw_internal[47] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_47_.Q; // c7[101]
assign priv_priv_csr_CSRValWReg_raw_internal[48] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_48_.Q; // c7[102]
assign priv_priv_csr_CSRValWReg_raw_internal[49] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_49_.Q; // c7[103]
assign priv_priv_csr_CSRValWReg_raw_internal[50] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_50_.Q; // c7[104]
assign priv_priv_csr_CSRValWReg_raw_internal[51] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_51_.Q; // c7[105]
assign priv_priv_csr_CSRValWReg_raw_internal[52] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_52_.Q; // c7[106]
assign priv_priv_csr_CSRValWReg_raw_internal[53] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_53_.Q; // c7[107]
assign priv_priv_csr_CSRValWReg_raw_internal[54] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_54_.Q; // c7[108]
assign priv_priv_csr_CSRValWReg_raw_internal[55] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_55_.Q; // c7[109]
assign priv_priv_csr_CSRValWReg_raw_internal[56] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_56_.Q; // c7[110]
assign priv_priv_csr_CSRValWReg_raw_internal[57] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_57_.Q; // c7[111]
assign priv_priv_csr_CSRValWReg_raw_internal[58] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_58_.Q; // c7[112]
assign priv_priv_csr_CSRValWReg_raw_internal[59] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_59_.Q; // c7[113]
assign priv_priv_csr_CSRValWReg_raw_internal[60] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_60_.Q; // c7[114]
assign priv_priv_csr_CSRValWReg_raw_internal[61] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_61_.Q; // c7[115]
assign priv_priv_csr_CSRValWReg_raw_internal[62] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_62_.Q; // c7[116]
assign priv_priv_csr_CSRValWReg_raw_internal[63] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_63_.Q; // c7[117]

// ---- priv_priv_csr_CSRValWReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign priv_priv_csr_CSRValWReg_internal[0] = priv_priv_csr_CSRValWReg_raw_internal[0];
assign priv_priv_csr_CSRValWReg_internal[1] = priv_priv_csr_CSRValWReg_raw_internal[1];
assign priv_priv_csr_CSRValWReg_internal[2] = priv_priv_csr_CSRValWReg_raw_internal[2];
assign priv_priv_csr_CSRValWReg_internal[3] = priv_priv_csr_CSRValWReg_raw_internal[3];
assign priv_priv_csr_CSRValWReg_internal[4] = priv_priv_csr_CSRValWReg_raw_internal[4];
assign priv_priv_csr_CSRValWReg_internal[5] = priv_priv_csr_CSRValWReg_raw_internal[5];
assign priv_priv_csr_CSRValWReg_internal[6] = priv_priv_csr_CSRValWReg_raw_internal[6];
assign priv_priv_csr_CSRValWReg_internal[7] = priv_priv_csr_CSRValWReg_raw_internal[7];
assign priv_priv_csr_CSRValWReg_internal[8] = priv_priv_csr_CSRValWReg_raw_internal[8];
assign priv_priv_csr_CSRValWReg_internal[9] = priv_priv_csr_CSRValWReg_raw_internal[9];
assign priv_priv_csr_CSRValWReg_internal[10] = priv_priv_csr_CSRValWReg_raw_internal[10];
assign priv_priv_csr_CSRValWReg_internal[11] = priv_priv_csr_CSRValWReg_raw_internal[11];
assign priv_priv_csr_CSRValWReg_internal[12] = priv_priv_csr_CSRValWReg_raw_internal[12];
assign priv_priv_csr_CSRValWReg_internal[13] = priv_priv_csr_CSRValWReg_raw_internal[13];
assign priv_priv_csr_CSRValWReg_internal[14] = priv_priv_csr_CSRValWReg_raw_internal[14];
assign priv_priv_csr_CSRValWReg_internal[15] = priv_priv_csr_CSRValWReg_raw_internal[15];
assign priv_priv_csr_CSRValWReg_internal[16] = priv_priv_csr_CSRValWReg_raw_internal[16];
assign priv_priv_csr_CSRValWReg_internal[17] = priv_priv_csr_CSRValWReg_raw_internal[17];
assign priv_priv_csr_CSRValWReg_internal[18] = priv_priv_csr_CSRValWReg_raw_internal[18];
assign priv_priv_csr_CSRValWReg_internal[19] = priv_priv_csr_CSRValWReg_raw_internal[19];
assign priv_priv_csr_CSRValWReg_internal[20] = priv_priv_csr_CSRValWReg_raw_internal[20];
assign priv_priv_csr_CSRValWReg_internal[21] = priv_priv_csr_CSRValWReg_raw_internal[21];
assign priv_priv_csr_CSRValWReg_internal[22] = priv_priv_csr_CSRValWReg_raw_internal[22];
assign priv_priv_csr_CSRValWReg_internal[23] = priv_priv_csr_CSRValWReg_raw_internal[23];
assign priv_priv_csr_CSRValWReg_internal[24] = priv_priv_csr_CSRValWReg_raw_internal[24];
assign priv_priv_csr_CSRValWReg_internal[25] = priv_priv_csr_CSRValWReg_raw_internal[25];
assign priv_priv_csr_CSRValWReg_internal[26] = priv_priv_csr_CSRValWReg_raw_internal[26];
assign priv_priv_csr_CSRValWReg_internal[27] = priv_priv_csr_CSRValWReg_raw_internal[27];
assign priv_priv_csr_CSRValWReg_internal[28] = priv_priv_csr_CSRValWReg_raw_internal[28];
assign priv_priv_csr_CSRValWReg_internal[29] = priv_priv_csr_CSRValWReg_raw_internal[29];
assign priv_priv_csr_CSRValWReg_internal[30] = priv_priv_csr_CSRValWReg_raw_internal[30];
assign priv_priv_csr_CSRValWReg_internal[31] = priv_priv_csr_CSRValWReg_raw_internal[31];
assign priv_priv_csr_CSRValWReg_internal[32] = priv_priv_csr_CSRValWReg_raw_internal[32];
assign priv_priv_csr_CSRValWReg_internal[33] = priv_priv_csr_CSRValWReg_raw_internal[33];
assign priv_priv_csr_CSRValWReg_internal[34] = priv_priv_csr_CSRValWReg_raw_internal[34];
assign priv_priv_csr_CSRValWReg_internal[35] = priv_priv_csr_CSRValWReg_raw_internal[35];
assign priv_priv_csr_CSRValWReg_internal[36] = priv_priv_csr_CSRValWReg_raw_internal[36];
assign priv_priv_csr_CSRValWReg_internal[37] = priv_priv_csr_CSRValWReg_raw_internal[37];
assign priv_priv_csr_CSRValWReg_internal[38] = priv_priv_csr_CSRValWReg_raw_internal[38];
assign priv_priv_csr_CSRValWReg_internal[39] = priv_priv_csr_CSRValWReg_raw_internal[39];
assign priv_priv_csr_CSRValWReg_internal[40] = priv_priv_csr_CSRValWReg_raw_internal[40];
assign priv_priv_csr_CSRValWReg_internal[41] = priv_priv_csr_CSRValWReg_raw_internal[41];
assign priv_priv_csr_CSRValWReg_internal[42] = priv_priv_csr_CSRValWReg_raw_internal[42];
assign priv_priv_csr_CSRValWReg_internal[43] = priv_priv_csr_CSRValWReg_raw_internal[43];
assign priv_priv_csr_CSRValWReg_internal[44] = priv_priv_csr_CSRValWReg_raw_internal[44];
assign priv_priv_csr_CSRValWReg_internal[45] = priv_priv_csr_CSRValWReg_raw_internal[45];
assign priv_priv_csr_CSRValWReg_internal[46] = priv_priv_csr_CSRValWReg_raw_internal[46];
assign priv_priv_csr_CSRValWReg_internal[47] = priv_priv_csr_CSRValWReg_raw_internal[47];
assign priv_priv_csr_CSRValWReg_internal[48] = priv_priv_csr_CSRValWReg_raw_internal[48];
assign priv_priv_csr_CSRValWReg_internal[49] = priv_priv_csr_CSRValWReg_raw_internal[49];
assign priv_priv_csr_CSRValWReg_internal[50] = priv_priv_csr_CSRValWReg_raw_internal[50];
assign priv_priv_csr_CSRValWReg_internal[51] = priv_priv_csr_CSRValWReg_raw_internal[51];
assign priv_priv_csr_CSRValWReg_internal[52] = priv_priv_csr_CSRValWReg_raw_internal[52];
assign priv_priv_csr_CSRValWReg_internal[53] = priv_priv_csr_CSRValWReg_raw_internal[53];
assign priv_priv_csr_CSRValWReg_internal[54] = priv_priv_csr_CSRValWReg_raw_internal[54];
assign priv_priv_csr_CSRValWReg_internal[55] = priv_priv_csr_CSRValWReg_raw_internal[55];
assign priv_priv_csr_CSRValWReg_internal[56] = priv_priv_csr_CSRValWReg_raw_internal[56];
assign priv_priv_csr_CSRValWReg_internal[57] = priv_priv_csr_CSRValWReg_raw_internal[57];
assign priv_priv_csr_CSRValWReg_internal[58] = priv_priv_csr_CSRValWReg_raw_internal[58];
assign priv_priv_csr_CSRValWReg_internal[59] = priv_priv_csr_CSRValWReg_raw_internal[59];
assign priv_priv_csr_CSRValWReg_internal[60] = priv_priv_csr_CSRValWReg_raw_internal[60];
assign priv_priv_csr_CSRValWReg_internal[61] = priv_priv_csr_CSRValWReg_raw_internal[61];
assign priv_priv_csr_CSRValWReg_internal[62] = priv_priv_csr_CSRValWReg_raw_internal[62];
assign priv_priv_csr_CSRValWReg_internal[63] = priv_priv_csr_CSRValWReg_raw_internal[63];

// ---- priv_priv_csr_CSRValWReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign priv_priv_csr_CSRValWReg_pin_internal[0] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_0_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[1] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_1_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[2] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_2_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[3] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_3_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[4] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_4_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[5] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_5_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[6] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_6_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[7] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_7_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[8] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_8_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[9] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_9_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[10] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_10_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[11] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_11_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[12] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_12_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[13] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_13_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[14] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_14_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[15] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_15_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[16] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_16_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[17] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_17_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[18] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_18_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[19] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_19_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[20] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_20_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[21] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_21_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[22] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_22_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[23] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_23_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[24] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_24_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[25] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_25_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[26] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_26_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[27] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_27_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[28] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_28_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[29] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_29_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[30] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_30_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[31] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_31_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[32] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_32_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[33] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_33_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[34] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_34_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[35] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_35_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[36] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_36_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[37] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_37_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[38] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_38_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[39] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_39_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[40] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_40_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[41] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_41_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[42] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_42_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[43] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_43_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[44] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_44_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[45] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_45_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[46] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_46_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[47] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_47_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[48] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_48_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[49] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_49_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[50] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_50_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[51] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_51_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[52] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_52_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[53] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_53_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[54] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_54_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[55] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_55_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[56] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_56_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[57] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_57_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[58] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_58_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[59] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_59_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[60] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_60_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[61] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_61_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[62] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_62_.Q;
assign priv_priv_csr_CSRValWReg_pin_internal[63] = dut.chip.soc_core_priv_priv_csr_CSRValWReg_q_reg_63_.Q;

// ---- priv_priv_csr_CSRValWReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign priv_priv_csr_CSRValWReg_raw_internal_available[0] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[1] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[2] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[3] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[4] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[5] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[6] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[7] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[8] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[9] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[10] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[11] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[12] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[13] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[14] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[15] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[16] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[17] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[18] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[19] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[20] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[21] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[22] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[23] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[24] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[25] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[26] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[27] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[28] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[29] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[30] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[31] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[32] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[33] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[34] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[35] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[36] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[37] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[38] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[39] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[40] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[41] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[42] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[43] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[44] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[45] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[46] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[47] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[48] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[49] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[50] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[51] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[52] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[53] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[54] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[55] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[56] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[57] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[58] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[59] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[60] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[61] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[62] = 1'b1;
assign priv_priv_csr_CSRValWReg_raw_internal_available[63] = 1'b1;

// ============================================================================
// Register priv_priv_csr_csrm/MSECFAULT_REGW: 7 mapped bits, width 7
// ============================================================================

// Bus declarations
wire [6:0] priv_priv_csr_csrm_MSECFAULT_REGW_internal;
wire [6:0] priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal;
wire [6:0] priv_priv_csr_csrm_MSECFAULT_REGW_pin_internal;
wire [6:0] priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal_available;

// ---- priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal[0] = dut.chip.soc_core_priv_priv_csr_csrm.MSECFAULT_REGW_reg_0_.Q; // c7[118]
assign priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal[1] = dut.chip.soc_core_priv_priv_csr_csrm.MSECFAULT_REGW_reg_1_.Q; // c7[119]
assign priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal[2] = dut.chip.soc_core_priv_priv_csr_csrm.MSECFAULT_REGW_reg_2_.Q; // c7[120]
assign priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal[3] = dut.chip.soc_core_priv_priv_csr_csrm.MSECFAULT_REGW_reg_3_.Q; // c7[121]
assign priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal[4] = dut.chip.soc_core_priv_priv_csr_csrm.MSECFAULT_REGW_reg_4_.Q; // c7[122]
assign priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal[5] = dut.chip.soc_core_priv_priv_csr_csrm.MSECFAULT_REGW_reg_5_.Q; // c7[123]
assign priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal[6] = dut.chip.soc_core_priv_priv_csr_csrm.MSECFAULT_REGW_reg_6_.Q; // c7[124]

// ---- priv_priv_csr_csrm_MSECFAULT_REGW_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign priv_priv_csr_csrm_MSECFAULT_REGW_internal[0] = priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal[0];
assign priv_priv_csr_csrm_MSECFAULT_REGW_internal[1] = priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal[1];
assign priv_priv_csr_csrm_MSECFAULT_REGW_internal[2] = priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal[2];
assign priv_priv_csr_csrm_MSECFAULT_REGW_internal[3] = priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal[3];
assign priv_priv_csr_csrm_MSECFAULT_REGW_internal[4] = priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal[4];
assign priv_priv_csr_csrm_MSECFAULT_REGW_internal[5] = priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal[5];
assign priv_priv_csr_csrm_MSECFAULT_REGW_internal[6] = priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal[6];

// ---- priv_priv_csr_csrm_MSECFAULT_REGW_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign priv_priv_csr_csrm_MSECFAULT_REGW_pin_internal[0] = dut.chip.soc_core_priv_priv_csr_csrm.MSECFAULT_REGW_reg_0_.Q;
assign priv_priv_csr_csrm_MSECFAULT_REGW_pin_internal[1] = dut.chip.soc_core_priv_priv_csr_csrm.MSECFAULT_REGW_reg_1_.Q;
assign priv_priv_csr_csrm_MSECFAULT_REGW_pin_internal[2] = dut.chip.soc_core_priv_priv_csr_csrm.MSECFAULT_REGW_reg_2_.Q;
assign priv_priv_csr_csrm_MSECFAULT_REGW_pin_internal[3] = dut.chip.soc_core_priv_priv_csr_csrm.MSECFAULT_REGW_reg_3_.Q;
assign priv_priv_csr_csrm_MSECFAULT_REGW_pin_internal[4] = dut.chip.soc_core_priv_priv_csr_csrm.MSECFAULT_REGW_reg_4_.Q;
assign priv_priv_csr_csrm_MSECFAULT_REGW_pin_internal[5] = dut.chip.soc_core_priv_priv_csr_csrm.MSECFAULT_REGW_reg_5_.Q;
assign priv_priv_csr_csrm_MSECFAULT_REGW_pin_internal[6] = dut.chip.soc_core_priv_priv_csr_csrm.MSECFAULT_REGW_reg_6_.Q;

// ---- priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal_available[0] = 1'b1;
assign priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal_available[1] = 1'b1;
assign priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal_available[2] = 1'b1;
assign priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal_available[3] = 1'b1;
assign priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal_available[4] = 1'b1;
assign priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal_available[5] = 1'b1;
assign priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal_available[6] = 1'b1;

// ============================================================================
// Register priv_priv_csr_csrm/RANDINSTRFREQreg: 32 mapped bits, width 32
// ============================================================================

// Bus declarations
wire [31:0] priv_priv_csr_csrm_RANDINSTRFREQreg_internal;
wire [31:0] priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal;
wire [31:0] priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal;
wire [31:0] priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available;

// ---- priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[0] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_0_.Q; // c7[125]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[1] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_1_.Q; // c7[126]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[2] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_2_.Q; // c7[127]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[3] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_3_.Q; // c7[128]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[4] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_4_.Q; // c7[129]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[5] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_5_.Q; // c7[130]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[6] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_6_.Q; // c7[131]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[7] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_7_.Q; // c7[132]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[8] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_8_.Q; // c7[133]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[9] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_9_.Q; // c7[134]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[10] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_10_.Q; // c7[135]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[11] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_11_.Q; // c7[136]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[12] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_12_.Q; // c7[137]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[13] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_13_.Q; // c7[138]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[14] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_14_.Q; // c7[139]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[15] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_15_.Q; // c7[140]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[16] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_16_.Q; // c7[141]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[17] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_17_.Q; // c7[142]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[18] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_18_.Q; // c7[143]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[19] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_19_.Q; // c7[144]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[20] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_20_.Q; // c7[145]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[21] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_21_.Q; // c7[146]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[22] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_22_.Q; // c7[147]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[23] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_23_.Q; // c7[148]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[24] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_24_.Q; // c7[149]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[25] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_25_.Q; // c7[150]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[26] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_26_.Q; // c7[151]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[27] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_27_.Q; // c7[152]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[28] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_28_.Q; // c7[153]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[29] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_29_.Q; // c7[154]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[30] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_30_.Q; // c7[155]
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[31] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_31_.Q; // c7[156]

// ---- priv_priv_csr_csrm_RANDINSTRFREQreg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[0] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[0];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[1] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[1];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[2] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[2];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[3] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[3];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[4] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[4];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[5] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[5];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[6] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[6];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[7] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[7];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[8] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[8];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[9] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[9];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[10] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[10];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[11] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[11];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[12] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[12];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[13] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[13];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[14] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[14];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[15] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[15];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[16] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[16];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[17] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[17];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[18] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[18];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[19] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[19];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[20] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[20];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[21] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[21];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[22] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[22];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[23] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[23];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[24] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[24];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[25] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[25];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[26] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[26];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[27] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[27];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[28] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[28];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[29] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[29];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[30] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[30];
assign priv_priv_csr_csrm_RANDINSTRFREQreg_internal[31] = priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal[31];

// ---- priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[0] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_0_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[1] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_1_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[2] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_2_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[3] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_3_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[4] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_4_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[5] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_5_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[6] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_6_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[7] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_7_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[8] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_8_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[9] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_9_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[10] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_10_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[11] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_11_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[12] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_12_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[13] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_13_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[14] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_14_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[15] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_15_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[16] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_16_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[17] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_17_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[18] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_18_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[19] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_19_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[20] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_20_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[21] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_21_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[22] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_22_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[23] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_23_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[24] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_24_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[25] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_25_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[26] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_26_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[27] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_27_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[28] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_28_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[29] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_29_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[30] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_30_.Q;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_pin_internal[31] = dut.chip.soc_core_priv_priv_csr_csrm.RANDINSTRFREQreg_q_reg_31_.Q;

// ---- priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[0] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[1] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[2] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[3] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[4] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[5] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[6] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[7] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[8] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[9] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[10] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[11] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[12] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[13] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[14] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[15] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[16] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[17] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[18] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[19] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[20] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[21] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[22] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[23] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[24] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[25] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[26] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[27] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[28] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[29] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[30] = 1'b1;
assign priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available[31] = 1'b1;

// ============================================================================
// Register priv_priv_csr_csrsr_STATUS_MPP: 2 mapped bits, width 2
// ============================================================================

// Bus declarations
wire [1:0] priv_priv_csr_csrsr_STATUS_MPP_internal;
wire [1:0] priv_priv_csr_csrsr_STATUS_MPP_raw_internal;
wire [1:0] priv_priv_csr_csrsr_STATUS_MPP_pin_internal;
wire [1:0] priv_priv_csr_csrsr_STATUS_MPP_raw_internal_available;

// ---- priv_priv_csr_csrsr_STATUS_MPP_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign priv_priv_csr_csrsr_STATUS_MPP_raw_internal[0] = dut.chip.soc_core_priv_priv_csr_csrsr_STATUS_MPP_reg_0_.Q; // c7[157]
assign priv_priv_csr_csrsr_STATUS_MPP_raw_internal[1] = ~dut.chip.soc_core_priv_priv_csr_csrsr_STATUS_MPP_reg_1_.QN; // c7[158]

// ---- priv_priv_csr_csrsr_STATUS_MPP_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign priv_priv_csr_csrsr_STATUS_MPP_internal[0] = priv_priv_csr_csrsr_STATUS_MPP_raw_internal[0];
assign priv_priv_csr_csrsr_STATUS_MPP_internal[1] = priv_priv_csr_csrsr_STATUS_MPP_raw_internal[1];

// ---- priv_priv_csr_csrsr_STATUS_MPP_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign priv_priv_csr_csrsr_STATUS_MPP_pin_internal[0] = dut.chip.soc_core_priv_priv_csr_csrsr_STATUS_MPP_reg_0_.Q;
assign priv_priv_csr_csrsr_STATUS_MPP_pin_internal[1] = dut.chip.soc_core_priv_priv_csr_csrsr_STATUS_MPP_reg_1_.QN;

// ---- priv_priv_csr_csrsr_STATUS_MPP_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign priv_priv_csr_csrsr_STATUS_MPP_raw_internal_available[0] = 1'b1;
assign priv_priv_csr_csrsr_STATUS_MPP_raw_internal_available[1] = 1'b1;

// ============================================================================
// Register priv_priv_pmd_wfiWReg: 1 mapped bits, width 1
// ============================================================================

// Bus declarations
wire [0:0] priv_priv_pmd_wfiWReg_internal;
wire [0:0] priv_priv_pmd_wfiWReg_raw_internal;
wire [0:0] priv_priv_pmd_wfiWReg_pin_internal;
wire [0:0] priv_priv_pmd_wfiWReg_raw_internal_available;

// ---- priv_priv_pmd_wfiWReg_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign priv_priv_pmd_wfiWReg_raw_internal[0] = dut.chip.soc_core_priv_priv_pmd_wfiWReg_q_reg_0_.Q; // c7[159]

// ---- priv_priv_pmd_wfiWReg_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign priv_priv_pmd_wfiWReg_internal[0] = priv_priv_pmd_wfiWReg_raw_internal[0];

// ---- priv_priv_pmd_wfiWReg_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign priv_priv_pmd_wfiWReg_pin_internal[0] = dut.chip.soc_core_priv_priv_pmd_wfiWReg_q_reg_0_.Q;

// ---- priv_priv_pmd_wfiWReg_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign priv_priv_pmd_wfiWReg_raw_internal_available[0] = 1'b1;

// ============================================================================
// Register priv_priv_ppr_faultregD: 4 mapped bits, width 4
// ============================================================================

// Bus declarations
wire [3:0] priv_priv_ppr_faultregD_internal;
wire [3:0] priv_priv_ppr_faultregD_raw_internal;
wire [3:0] priv_priv_ppr_faultregD_pin_internal;
wire [3:0] priv_priv_ppr_faultregD_raw_internal_available;

// ---- priv_priv_ppr_faultregD_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign priv_priv_ppr_faultregD_raw_internal[0] = dut.chip.soc_core_priv_priv_ppr_faultregD_q_reg_0_.Q; // c7[160]
assign priv_priv_ppr_faultregD_raw_internal[1] = dut.chip.soc_core_priv_priv_ppr_faultregD_q_reg_1_.Q; // c7[161]
assign priv_priv_ppr_faultregD_raw_internal[2] = dut.chip.soc_core_priv_priv_ppr_faultregD_q_reg_2_.Q; // c7[162]
assign priv_priv_ppr_faultregD_raw_internal[3] = dut.chip.soc_core_priv_priv_ppr_faultregD_q_reg_3_.Q; // c7[163]

// ---- priv_priv_ppr_faultregD_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign priv_priv_ppr_faultregD_internal[0] = priv_priv_ppr_faultregD_raw_internal[0];
assign priv_priv_ppr_faultregD_internal[1] = priv_priv_ppr_faultregD_raw_internal[1];
assign priv_priv_ppr_faultregD_internal[2] = priv_priv_ppr_faultregD_raw_internal[2];
assign priv_priv_ppr_faultregD_internal[3] = priv_priv_ppr_faultregD_raw_internal[3];

// ---- priv_priv_ppr_faultregD_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign priv_priv_ppr_faultregD_pin_internal[0] = dut.chip.soc_core_priv_priv_ppr_faultregD_q_reg_0_.Q;
assign priv_priv_ppr_faultregD_pin_internal[1] = dut.chip.soc_core_priv_priv_ppr_faultregD_q_reg_1_.Q;
assign priv_priv_ppr_faultregD_pin_internal[2] = dut.chip.soc_core_priv_priv_ppr_faultregD_q_reg_2_.Q;
assign priv_priv_ppr_faultregD_pin_internal[3] = dut.chip.soc_core_priv_priv_ppr_faultregD_q_reg_3_.Q;

// ---- priv_priv_ppr_faultregD_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign priv_priv_ppr_faultregD_raw_internal_available[0] = 1'b1;
assign priv_priv_ppr_faultregD_raw_internal_available[1] = 1'b1;
assign priv_priv_ppr_faultregD_raw_internal_available[2] = 1'b1;
assign priv_priv_ppr_faultregD_raw_internal_available[3] = 1'b1;

// ============================================================================
// Register priv_priv_ppr_faultregE: 5 mapped bits, width 5
// ============================================================================

// Bus declarations
wire [4:0] priv_priv_ppr_faultregE_internal;
wire [4:0] priv_priv_ppr_faultregE_raw_internal;
wire [4:0] priv_priv_ppr_faultregE_pin_internal;
wire [4:0] priv_priv_ppr_faultregE_raw_internal_available;

// ---- priv_priv_ppr_faultregE_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign priv_priv_ppr_faultregE_raw_internal[0] = dut.chip.soc_core_priv_priv_ppr_faultregE_q_reg_0_.Q; // c7[164]
assign priv_priv_ppr_faultregE_raw_internal[1] = dut.chip.soc_core_priv_priv_ppr_faultregE_q_reg_1_.Q; // c7[165]
assign priv_priv_ppr_faultregE_raw_internal[2] = dut.chip.soc_core_priv_priv_ppr_faultregE_q_reg_2_.Q; // c7[166]
assign priv_priv_ppr_faultregE_raw_internal[3] = dut.chip.soc_core_priv_priv_ppr_faultregE_q_reg_3_.Q; // c7[167]
assign priv_priv_ppr_faultregE_raw_internal[4] = dut.chip.soc_core_priv_priv_ppr_faultregE_q_reg_4_.Q; // c7[168]

// ---- priv_priv_ppr_faultregE_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign priv_priv_ppr_faultregE_internal[0] = priv_priv_ppr_faultregE_raw_internal[0];
assign priv_priv_ppr_faultregE_internal[1] = priv_priv_ppr_faultregE_raw_internal[1];
assign priv_priv_ppr_faultregE_internal[2] = priv_priv_ppr_faultregE_raw_internal[2];
assign priv_priv_ppr_faultregE_internal[3] = priv_priv_ppr_faultregE_raw_internal[3];
assign priv_priv_ppr_faultregE_internal[4] = priv_priv_ppr_faultregE_raw_internal[4];

// ---- priv_priv_ppr_faultregE_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign priv_priv_ppr_faultregE_pin_internal[0] = dut.chip.soc_core_priv_priv_ppr_faultregE_q_reg_0_.Q;
assign priv_priv_ppr_faultregE_pin_internal[1] = dut.chip.soc_core_priv_priv_ppr_faultregE_q_reg_1_.Q;
assign priv_priv_ppr_faultregE_pin_internal[2] = dut.chip.soc_core_priv_priv_ppr_faultregE_q_reg_2_.Q;
assign priv_priv_ppr_faultregE_pin_internal[3] = dut.chip.soc_core_priv_priv_ppr_faultregE_q_reg_3_.Q;
assign priv_priv_ppr_faultregE_pin_internal[4] = dut.chip.soc_core_priv_priv_ppr_faultregE_q_reg_4_.Q;

// ---- priv_priv_ppr_faultregE_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign priv_priv_ppr_faultregE_raw_internal_available[0] = 1'b1;
assign priv_priv_ppr_faultregE_raw_internal_available[1] = 1'b1;
assign priv_priv_ppr_faultregE_raw_internal_available[2] = 1'b1;
assign priv_priv_ppr_faultregE_raw_internal_available[3] = 1'b1;
assign priv_priv_ppr_faultregE_raw_internal_available[4] = 1'b1;

// ============================================================================
// Register priv_priv_ppr_faultregM: 5 mapped bits, width 5
// ============================================================================

// Bus declarations
wire [4:0] priv_priv_ppr_faultregM_internal;
wire [4:0] priv_priv_ppr_faultregM_raw_internal;
wire [4:0] priv_priv_ppr_faultregM_pin_internal;
wire [4:0] priv_priv_ppr_faultregM_raw_internal_available;

// ---- priv_priv_ppr_faultregM_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign priv_priv_ppr_faultregM_raw_internal[0] = dut.chip.soc_core_priv_priv_ppr_faultregM_q_reg_0_.Q; // c7[169]
assign priv_priv_ppr_faultregM_raw_internal[1] = dut.chip.soc_core_priv_priv_ppr_faultregM_q_reg_1_.Q; // c7[170]
assign priv_priv_ppr_faultregM_raw_internal[2] = dut.chip.soc_core_priv_priv_ppr_faultregM_q_reg_2_.Q; // c7[171]
assign priv_priv_ppr_faultregM_raw_internal[3] = dut.chip.soc_core_priv_priv_ppr_faultregM_q_reg_3_.Q; // c7[172]
assign priv_priv_ppr_faultregM_raw_internal[4] = dut.chip.soc_core_priv_priv_ppr_faultregM_q_reg_4_.Q; // c7[173]

// ---- priv_priv_ppr_faultregM_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign priv_priv_ppr_faultregM_internal[0] = priv_priv_ppr_faultregM_raw_internal[0];
assign priv_priv_ppr_faultregM_internal[1] = priv_priv_ppr_faultregM_raw_internal[1];
assign priv_priv_ppr_faultregM_internal[2] = priv_priv_ppr_faultregM_raw_internal[2];
assign priv_priv_ppr_faultregM_internal[3] = priv_priv_ppr_faultregM_raw_internal[3];
assign priv_priv_ppr_faultregM_internal[4] = priv_priv_ppr_faultregM_raw_internal[4];

// ---- priv_priv_ppr_faultregM_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign priv_priv_ppr_faultregM_pin_internal[0] = dut.chip.soc_core_priv_priv_ppr_faultregM_q_reg_0_.Q;
assign priv_priv_ppr_faultregM_pin_internal[1] = dut.chip.soc_core_priv_priv_ppr_faultregM_q_reg_1_.Q;
assign priv_priv_ppr_faultregM_pin_internal[2] = dut.chip.soc_core_priv_priv_ppr_faultregM_q_reg_2_.Q;
assign priv_priv_ppr_faultregM_pin_internal[3] = dut.chip.soc_core_priv_priv_ppr_faultregM_q_reg_3_.Q;
assign priv_priv_ppr_faultregM_pin_internal[4] = dut.chip.soc_core_priv_priv_ppr_faultregM_q_reg_4_.Q;

// ---- priv_priv_ppr_faultregM_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign priv_priv_ppr_faultregM_raw_internal_available[0] = 1'b1;
assign priv_priv_ppr_faultregM_raw_internal_available[1] = 1'b1;
assign priv_priv_ppr_faultregM_raw_internal_available[2] = 1'b1;
assign priv_priv_ppr_faultregM_raw_internal_available[3] = 1'b1;
assign priv_priv_ppr_faultregM_raw_internal_available[4] = 1'b1;

// ============================================================================
// Register priv_priv_privmode_privmode_privchkreg_a: 2 mapped bits, width 2
// ============================================================================

// Bus declarations
wire [1:0] priv_priv_privmode_privmode_privchkreg_a_internal;
wire [1:0] priv_priv_privmode_privmode_privchkreg_a_raw_internal;
wire [1:0] priv_priv_privmode_privmode_privchkreg_a_pin_internal;
wire [1:0] priv_priv_privmode_privmode_privchkreg_a_raw_internal_available;

// ---- priv_priv_privmode_privmode_privchkreg_a_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign priv_priv_privmode_privmode_privchkreg_a_raw_internal[0] = ~dut.chip.soc_core_priv_priv_privmode_privmode_privchkreg_a.q_reg_0_.QN; // c7[174]
assign priv_priv_privmode_privmode_privchkreg_a_raw_internal[1] = ~dut.chip.soc_core_priv_priv_privmode_privmode_privchkreg_a.q_reg_1_.QN; // c7[175]

// ---- priv_priv_privmode_privmode_privchkreg_a_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign priv_priv_privmode_privmode_privchkreg_a_internal[0] = priv_priv_privmode_privmode_privchkreg_a_raw_internal[0] ^ 1'b1;
assign priv_priv_privmode_privmode_privchkreg_a_internal[1] = priv_priv_privmode_privmode_privchkreg_a_raw_internal[1] ^ 1'b1;

// ---- priv_priv_privmode_privmode_privchkreg_a_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign priv_priv_privmode_privmode_privchkreg_a_pin_internal[0] = dut.chip.soc_core_priv_priv_privmode_privmode_privchkreg_a.q_reg_0_.QN;
assign priv_priv_privmode_privmode_privchkreg_a_pin_internal[1] = dut.chip.soc_core_priv_priv_privmode_privmode_privchkreg_a.q_reg_1_.QN;

// ---- priv_priv_privmode_privmode_privchkreg_a_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign priv_priv_privmode_privmode_privchkreg_a_raw_internal_available[0] = 1'b1;
assign priv_priv_privmode_privmode_privchkreg_a_raw_internal_available[1] = 1'b1;

// ============================================================================
// Register priv_priv_privmode_privmode_privchkreg_b: 2 mapped bits, width 2
// ============================================================================

// Bus declarations
wire [1:0] priv_priv_privmode_privmode_privchkreg_b_internal;
wire [1:0] priv_priv_privmode_privmode_privchkreg_b_raw_internal;
wire [1:0] priv_priv_privmode_privmode_privchkreg_b_pin_internal;
wire [1:0] priv_priv_privmode_privmode_privchkreg_b_raw_internal_available;

// ---- priv_priv_privmode_privmode_privchkreg_b_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign priv_priv_privmode_privmode_privchkreg_b_raw_internal[0] = ~dut.chip.soc_core_priv_priv_privmode_privmode_privchkreg_b.q_reg_0_.QN; // c7[176]
assign priv_priv_privmode_privmode_privchkreg_b_raw_internal[1] = ~dut.chip.soc_core_priv_priv_privmode_privmode_privchkreg_b.q_reg_1_.QN; // c7[177]

// ---- priv_priv_privmode_privmode_privchkreg_b_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign priv_priv_privmode_privmode_privchkreg_b_internal[0] = priv_priv_privmode_privmode_privchkreg_b_raw_internal[0] ^ 1'b1;
assign priv_priv_privmode_privmode_privchkreg_b_internal[1] = priv_priv_privmode_privmode_privchkreg_b_raw_internal[1] ^ 1'b1;

// ---- priv_priv_privmode_privmode_privchkreg_b_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign priv_priv_privmode_privmode_privchkreg_b_pin_internal[0] = dut.chip.soc_core_priv_priv_privmode_privmode_privchkreg_b.q_reg_0_.QN;
assign priv_priv_privmode_privmode_privchkreg_b_pin_internal[1] = dut.chip.soc_core_priv_priv_privmode_privmode_privchkreg_b.q_reg_1_.QN;

// ---- priv_priv_privmode_privmode_privchkreg_b_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign priv_priv_privmode_privmode_privchkreg_b_raw_internal_available[0] = 1'b1;
assign priv_priv_privmode_privmode_privchkreg_b_raw_internal_available[1] = 1'b1;

// ============================================================================
// Register priv_priv_privmode_privmode_privchkreg_c: 2 mapped bits, width 2
// ============================================================================

// Bus declarations
wire [1:0] priv_priv_privmode_privmode_privchkreg_c_internal;
wire [1:0] priv_priv_privmode_privmode_privchkreg_c_raw_internal;
wire [1:0] priv_priv_privmode_privmode_privchkreg_c_pin_internal;
wire [1:0] priv_priv_privmode_privmode_privchkreg_c_raw_internal_available;

// ---- priv_priv_privmode_privmode_privchkreg_c_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign priv_priv_privmode_privmode_privchkreg_c_raw_internal[0] = dut.chip.soc_core_priv_priv_privmode_privmode_privchkreg_c.q_reg_0_.Q; // c7[178]
assign priv_priv_privmode_privmode_privchkreg_c_raw_internal[1] = ~dut.chip.soc_core_priv_priv_privmode_privmode_privchkreg_c.q_reg_1_.QN; // c7[179]

// ---- priv_priv_privmode_privmode_privchkreg_c_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign priv_priv_privmode_privmode_privchkreg_c_internal[0] = priv_priv_privmode_privmode_privchkreg_c_raw_internal[0];
assign priv_priv_privmode_privmode_privchkreg_c_internal[1] = priv_priv_privmode_privmode_privchkreg_c_raw_internal[1] ^ 1'b1;

// ---- priv_priv_privmode_privmode_privchkreg_c_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign priv_priv_privmode_privmode_privchkreg_c_pin_internal[0] = dut.chip.soc_core_priv_priv_privmode_privmode_privchkreg_c.q_reg_0_.Q;
assign priv_priv_privmode_privmode_privchkreg_c_pin_internal[1] = dut.chip.soc_core_priv_priv_privmode_privmode_privchkreg_c.q_reg_1_.QN;

// ---- priv_priv_privmode_privmode_privchkreg_c_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign priv_priv_privmode_privmode_privchkreg_c_raw_internal_available[0] = 1'b1;
assign priv_priv_privmode_privmode_privchkreg_c_raw_internal_available[1] = 1'b1;

// ============================================================================
// Register priv_priv_privmode_privmode_privmodereg_a: 2 mapped bits, width 2
// ============================================================================

// Bus declarations
wire [1:0] priv_priv_privmode_privmode_privmodereg_a_internal;
wire [1:0] priv_priv_privmode_privmode_privmodereg_a_raw_internal;
wire [1:0] priv_priv_privmode_privmode_privmodereg_a_pin_internal;
wire [1:0] priv_priv_privmode_privmode_privmodereg_a_raw_internal_available;

// ---- priv_priv_privmode_privmode_privmodereg_a_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign priv_priv_privmode_privmode_privmodereg_a_raw_internal[0] = ~dut.chip.soc_core_priv_priv_privmode_privmode_privmodereg_a.q_reg_0_.QN; // c7[180]
assign priv_priv_privmode_privmode_privmodereg_a_raw_internal[1] = ~dut.chip.soc_core_priv_priv_privmode_privmode_privmodereg_a.q_reg_1_.QN; // c7[181]

// ---- priv_priv_privmode_privmode_privmodereg_a_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign priv_priv_privmode_privmode_privmodereg_a_internal[0] = priv_priv_privmode_privmode_privmodereg_a_raw_internal[0] ^ 1'b1;
assign priv_priv_privmode_privmode_privmodereg_a_internal[1] = priv_priv_privmode_privmode_privmodereg_a_raw_internal[1] ^ 1'b1;

// ---- priv_priv_privmode_privmode_privmodereg_a_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign priv_priv_privmode_privmode_privmodereg_a_pin_internal[0] = dut.chip.soc_core_priv_priv_privmode_privmode_privmodereg_a.q_reg_0_.QN;
assign priv_priv_privmode_privmode_privmodereg_a_pin_internal[1] = dut.chip.soc_core_priv_priv_privmode_privmode_privmodereg_a.q_reg_1_.QN;

// ---- priv_priv_privmode_privmode_privmodereg_a_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign priv_priv_privmode_privmode_privmodereg_a_raw_internal_available[0] = 1'b1;
assign priv_priv_privmode_privmode_privmodereg_a_raw_internal_available[1] = 1'b1;

// ============================================================================
// Register priv_priv_privmode_privmode_privmodereg_b: 2 mapped bits, width 2
// ============================================================================

// Bus declarations
wire [1:0] priv_priv_privmode_privmode_privmodereg_b_internal;
wire [1:0] priv_priv_privmode_privmode_privmodereg_b_raw_internal;
wire [1:0] priv_priv_privmode_privmode_privmodereg_b_pin_internal;
wire [1:0] priv_priv_privmode_privmode_privmodereg_b_raw_internal_available;

// ---- priv_priv_privmode_privmode_privmodereg_b_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign priv_priv_privmode_privmode_privmodereg_b_raw_internal[0] = ~dut.chip.soc_core_priv_priv_privmode_privmode_privmodereg_b.q_reg_0_.QN; // c7[182]
assign priv_priv_privmode_privmode_privmodereg_b_raw_internal[1] = ~dut.chip.soc_core_priv_priv_privmode_privmode_privmodereg_b.q_reg_1_.QN; // c7[183]

// ---- priv_priv_privmode_privmode_privmodereg_b_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign priv_priv_privmode_privmode_privmodereg_b_internal[0] = priv_priv_privmode_privmode_privmodereg_b_raw_internal[0] ^ 1'b1;
assign priv_priv_privmode_privmode_privmodereg_b_internal[1] = priv_priv_privmode_privmode_privmodereg_b_raw_internal[1] ^ 1'b1;

// ---- priv_priv_privmode_privmode_privmodereg_b_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign priv_priv_privmode_privmode_privmodereg_b_pin_internal[0] = dut.chip.soc_core_priv_priv_privmode_privmode_privmodereg_b.q_reg_0_.QN;
assign priv_priv_privmode_privmode_privmodereg_b_pin_internal[1] = dut.chip.soc_core_priv_priv_privmode_privmode_privmodereg_b.q_reg_1_.QN;

// ---- priv_priv_privmode_privmode_privmodereg_b_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign priv_priv_privmode_privmode_privmodereg_b_raw_internal_available[0] = 1'b1;
assign priv_priv_privmode_privmode_privmodereg_b_raw_internal_available[1] = 1'b1;

// ============================================================================
// Register priv_priv_privmode_privmode_privmodereg_c: 2 mapped bits, width 2
// ============================================================================

// Bus declarations
wire [1:0] priv_priv_privmode_privmode_privmodereg_c_internal;
wire [1:0] priv_priv_privmode_privmode_privmodereg_c_raw_internal;
wire [1:0] priv_priv_privmode_privmode_privmodereg_c_pin_internal;
wire [1:0] priv_priv_privmode_privmode_privmodereg_c_raw_internal_available;

// ---- priv_priv_privmode_privmode_privmodereg_c_raw_internal ----
// Physical Q: .Q or ~.QN; no logical polarity correction.
assign priv_priv_privmode_privmode_privmodereg_c_raw_internal[0] = ~dut.chip.soc_core_priv_priv_privmode_privmode_privmodereg_c.q_reg_0_.QN; // c7[184]
assign priv_priv_privmode_privmode_privmodereg_c_raw_internal[1] = ~dut.chip.soc_core_priv_priv_privmode_privmode_privmodereg_c.q_reg_1_.QN; // c7[185]

// ---- priv_priv_privmode_privmode_privmodereg_c_internal ----
// Logical estimate: physical Q XOR map_ph; unavailable bits stay Z.
assign priv_priv_privmode_privmode_privmodereg_c_internal[0] = priv_priv_privmode_privmode_privmodereg_c_raw_internal[0] ^ 1'b1;
assign priv_priv_privmode_privmode_privmodereg_c_internal[1] = priv_priv_privmode_privmode_privmodereg_c_raw_internal[1] ^ 1'b1;

// ---- priv_priv_privmode_privmode_privmodereg_c_pin_internal ----
// Scan output pin: scandef Q/QN selection; STOP uses an available output.
assign priv_priv_privmode_privmode_privmodereg_c_pin_internal[0] = dut.chip.soc_core_priv_priv_privmode_privmode_privmodereg_c.q_reg_0_.QN;
assign priv_priv_privmode_privmode_privmodereg_c_pin_internal[1] = dut.chip.soc_core_priv_priv_privmode_privmode_privmodereg_c.q_reg_1_.QN;

// ---- priv_priv_privmode_privmode_privmodereg_c_raw_internal_available ----
// Availability mask: 1 = physical Q can be probed; 0 = unavailable.
assign priv_priv_privmode_privmode_privmodereg_c_raw_internal_available[0] = 1'b1;
assign priv_priv_privmode_privmode_privmodereg_c_raw_internal_available[1] = 1'b1;

// ============================================================================
// Name-indexed register arrays
// ============================================================================
// Keys match scan_map.svh reg_name[].
// Values are LIVE. Snapshot before scan unload.
// Value arrays are padded to MAX_W with Z; masks are padded with 0.

// Physical Q (.Q or ~.QN), without map_ph correction; unavailable bits are Z.
val_t internal_raw_by_name[string];

// Logical estimate (physical Q XOR map_ph); unavailable bits remain Z.
val_t internal_est_by_name[string];

// Availability mask: 1 = physical output can be probed; 0 = unavailable.
val_t internal_available_by_name[string];

// Compatibility alias of internal_est_by_name; not an independent observation.
val_t internal_by_name[string];

always_comb begin
  // ---- internal_raw_by_name ----
  // Physical Q (.Q or ~.QN), without map_ph correction; unavailable bits are Z.
  internal_raw_by_name["FTStatusSticky"] = {{(MAX_W-7){1'bz}}, FTStatusSticky_raw_internal};
  internal_raw_by_name["ieu_c_RdEReg"] = {{(MAX_W-5){1'bz}}, ieu_c_RdEReg_raw_internal};
  internal_raw_by_name["ieu_c_RdMReg"] = {{(MAX_W-5){1'bz}}, ieu_c_RdMReg_raw_internal};
  internal_raw_by_name["ieu_c_RdWReg"] = {{(MAX_W-5){1'bz}}, ieu_c_RdWReg_raw_internal};
  internal_raw_by_name["ieu_c_Rs1EReg"] = {{(MAX_W-5){1'bz}}, ieu_c_Rs1EReg_raw_internal};
  internal_raw_by_name["ieu_c_Rs2EReg"] = {{(MAX_W-5){1'bz}}, ieu_c_Rs2EReg_raw_internal};
  internal_raw_by_name["ieu_c_controlregD"] = {{(MAX_W-1){1'bz}}, ieu_c_controlregD_raw_internal};
  internal_raw_by_name["ieu_c_controlregE"] = {{(MAX_W-47){1'bz}}, ieu_c_controlregE_raw_internal};
  internal_raw_by_name["ieu_c_controlregM"] = {{(MAX_W-27){1'bz}}, ieu_c_controlregM_raw_internal};
  internal_raw_by_name["ieu_c_controlregW"] = {{(MAX_W-7){1'bz}}, ieu_c_controlregW_raw_internal};
  internal_raw_by_name["ieu_dp_IEUResultMReg"] = {{(MAX_W-72){1'bz}}, ieu_dp_IEUResultMReg_raw_internal};
  internal_raw_by_name["ieu_dp_IFResultWReg"] = {{(MAX_W-72){1'bz}}, ieu_dp_IFResultWReg_raw_internal};
  internal_raw_by_name["ieu_dp_ImmExtEReg"] = {{(MAX_W-72){1'bz}}, ieu_dp_ImmExtEReg_raw_internal};
  internal_raw_by_name["ieu_dp_RD1EReg"] = {{(MAX_W-72){1'bz}}, ieu_dp_RD1EReg_raw_internal};
  internal_raw_by_name["ieu_dp_RD2EReg"] = {{(MAX_W-72){1'bz}}, ieu_dp_RD2EReg_raw_internal};
  internal_raw_by_name["ieu_dp_SrcAMReg"] = {{(MAX_W-72){1'bz}}, ieu_dp_SrcAMReg_raw_internal};
  internal_raw_by_name["ieu_dp_WriteDataMReg"] = {{(MAX_W-72){1'bz}}, ieu_dp_WriteDataMReg_raw_internal};
  internal_raw_by_name["ifu_AlignedInstrRawDFlop"] = {{(MAX_W-32){1'bz}}, ifu_AlignedInstrRawDFlop_raw_internal};
  internal_raw_by_name["ifu_InstrEReg"] = {{(MAX_W-32){1'bz}}, ifu_InstrEReg_raw_internal};
  internal_raw_by_name["ifu_PCDReg"] = {{(MAX_W-64){1'bz}}, ifu_PCDReg_raw_internal};
  internal_raw_by_name["ifu_PCEReg"] = {{(MAX_W-64){1'bz}}, ifu_PCEReg_raw_internal};
  internal_raw_by_name["ifu_Spill_SpillDReg"] = {{(MAX_W-1){1'bz}}, ifu_Spill_SpillDReg_raw_internal};
  internal_raw_by_name["ifu_Spill_SpillEReg"] = {{(MAX_W-1){1'bz}}, ifu_Spill_SpillEReg_raw_internal};
  internal_raw_by_name["ifu_Spill_SpillMReg"] = {{(MAX_W-1){1'bz}}, ifu_Spill_SpillMReg_raw_internal};
  internal_raw_by_name["ifu_genblk9_InstrMReg"] = {{(MAX_W-32){1'bz}}, ifu_genblk9_InstrMReg_raw_internal};
  internal_raw_by_name["ifu_genblk10_PCMReg"] = {{(MAX_W-64){1'bz}}, ifu_genblk10_PCMReg_raw_internal};
  internal_raw_by_name["ifu_genblk11_CompressedDReg"] = {{(MAX_W-1){1'bz}}, ifu_genblk11_CompressedDReg_raw_internal};
  internal_raw_by_name["ifu_genblk11_CompressedEReg"] = {{(MAX_W-1){1'bz}}, ifu_genblk11_CompressedEReg_raw_internal};
  internal_raw_by_name["ifu_genblk12_CompressedMReg"] = {{(MAX_W-1){1'bz}}, ifu_genblk12_CompressedMReg_raw_internal};
  internal_raw_by_name["ifu_genblk12_InstrRawEReg"] = {{(MAX_W-16){1'bz}}, ifu_genblk12_InstrRawEReg_raw_internal};
  internal_raw_by_name["ifu_genblk12_InstrRawMReg"] = {{(MAX_W-16){1'bz}}, ifu_genblk12_InstrRawMReg_raw_internal};
  internal_raw_by_name["ifu_pcreg"] = {{(MAX_W-64){1'bz}}, pc_raw_internal};
  internal_raw_by_name["lsu_AddressMReg"] = {{(MAX_W-64){1'bz}}, lsu_AddressMReg_raw_internal};
  internal_raw_by_name["lsu_ReadDataMWReg"] = {{(MAX_W-64){1'bz}}, lsu_ReadDataMWReg_raw_internal};
  internal_raw_by_name["mdu_mdu_MDUResultWReg"] = {{(MAX_W-64){1'bz}}, mdu_mdu_MDUResultWReg_raw_internal};
  internal_raw_by_name["mdu_mdu_W64MReg"] = {{(MAX_W-1){1'bz}}, mdu_mdu_W64MReg_raw_internal};
  internal_raw_by_name["mdu_mdu_div_divfaultreg"] = {{(MAX_W-1){1'bz}}, mdu_mdu_div_divfaultreg_raw_internal};
  internal_raw_by_name["mdu_mdu_ftmul_primary_PP1Reg"] = {{(MAX_W-127){1'bz}}, mdu_mdu_ftmul_primary_PP1Reg_raw_internal};
  internal_raw_by_name["mdu_mdu_ftmul_primary_PP2Reg"] = {{(MAX_W-126){1'bz}}, mdu_mdu_ftmul_primary_PP2Reg_raw_internal};
  internal_raw_by_name["priv_priv_csr_CSRValWReg"] = {{(MAX_W-64){1'bz}}, priv_priv_csr_CSRValWReg_raw_internal};
  internal_raw_by_name["priv_priv_csr_csrm/MSECFAULT_REGW"] = {{(MAX_W-7){1'bz}}, priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal};
  internal_raw_by_name["priv_priv_csr_csrm/RANDINSTRFREQreg"] = {{(MAX_W-32){1'bz}}, priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal};
  internal_raw_by_name["priv_priv_csr_csrsr_STATUS_MPP"] = {{(MAX_W-2){1'bz}}, priv_priv_csr_csrsr_STATUS_MPP_raw_internal};
  internal_raw_by_name["priv_priv_pmd_wfiWReg"] = {{(MAX_W-1){1'bz}}, priv_priv_pmd_wfiWReg_raw_internal};
  internal_raw_by_name["priv_priv_ppr_faultregD"] = {{(MAX_W-4){1'bz}}, priv_priv_ppr_faultregD_raw_internal};
  internal_raw_by_name["priv_priv_ppr_faultregE"] = {{(MAX_W-5){1'bz}}, priv_priv_ppr_faultregE_raw_internal};
  internal_raw_by_name["priv_priv_ppr_faultregM"] = {{(MAX_W-5){1'bz}}, priv_priv_ppr_faultregM_raw_internal};
  internal_raw_by_name["priv_priv_privmode_privmode_privchkreg_a"] = {{(MAX_W-2){1'bz}}, priv_priv_privmode_privmode_privchkreg_a_raw_internal};
  internal_raw_by_name["priv_priv_privmode_privmode_privchkreg_b"] = {{(MAX_W-2){1'bz}}, priv_priv_privmode_privmode_privchkreg_b_raw_internal};
  internal_raw_by_name["priv_priv_privmode_privmode_privchkreg_c"] = {{(MAX_W-2){1'bz}}, priv_priv_privmode_privmode_privchkreg_c_raw_internal};
  internal_raw_by_name["priv_priv_privmode_privmode_privmodereg_a"] = {{(MAX_W-2){1'bz}}, priv_priv_privmode_privmode_privmodereg_a_raw_internal};
  internal_raw_by_name["priv_priv_privmode_privmode_privmodereg_b"] = {{(MAX_W-2){1'bz}}, priv_priv_privmode_privmode_privmodereg_b_raw_internal};
  internal_raw_by_name["priv_priv_privmode_privmode_privmodereg_c"] = {{(MAX_W-2){1'bz}}, priv_priv_privmode_privmode_privmodereg_c_raw_internal};

  // ---- internal_est_by_name ----
  // Logical estimate (physical Q XOR map_ph); unavailable bits remain Z.
  internal_est_by_name["FTStatusSticky"] = {{(MAX_W-7){1'bz}}, FTStatusSticky_internal};
  internal_est_by_name["ieu_c_RdEReg"] = {{(MAX_W-5){1'bz}}, ieu_c_RdEReg_internal};
  internal_est_by_name["ieu_c_RdMReg"] = {{(MAX_W-5){1'bz}}, ieu_c_RdMReg_internal};
  internal_est_by_name["ieu_c_RdWReg"] = {{(MAX_W-5){1'bz}}, ieu_c_RdWReg_internal};
  internal_est_by_name["ieu_c_Rs1EReg"] = {{(MAX_W-5){1'bz}}, ieu_c_Rs1EReg_internal};
  internal_est_by_name["ieu_c_Rs2EReg"] = {{(MAX_W-5){1'bz}}, ieu_c_Rs2EReg_internal};
  internal_est_by_name["ieu_c_controlregD"] = {{(MAX_W-1){1'bz}}, ieu_c_controlregD_internal};
  internal_est_by_name["ieu_c_controlregE"] = {{(MAX_W-47){1'bz}}, ieu_c_controlregE_internal};
  internal_est_by_name["ieu_c_controlregM"] = {{(MAX_W-27){1'bz}}, ieu_c_controlregM_internal};
  internal_est_by_name["ieu_c_controlregW"] = {{(MAX_W-7){1'bz}}, ieu_c_controlregW_internal};
  internal_est_by_name["ieu_dp_IEUResultMReg"] = {{(MAX_W-72){1'bz}}, ieu_dp_IEUResultMReg_internal};
  internal_est_by_name["ieu_dp_IFResultWReg"] = {{(MAX_W-72){1'bz}}, ieu_dp_IFResultWReg_internal};
  internal_est_by_name["ieu_dp_ImmExtEReg"] = {{(MAX_W-72){1'bz}}, ieu_dp_ImmExtEReg_internal};
  internal_est_by_name["ieu_dp_RD1EReg"] = {{(MAX_W-72){1'bz}}, ieu_dp_RD1EReg_internal};
  internal_est_by_name["ieu_dp_RD2EReg"] = {{(MAX_W-72){1'bz}}, ieu_dp_RD2EReg_internal};
  internal_est_by_name["ieu_dp_SrcAMReg"] = {{(MAX_W-72){1'bz}}, ieu_dp_SrcAMReg_internal};
  internal_est_by_name["ieu_dp_WriteDataMReg"] = {{(MAX_W-72){1'bz}}, ieu_dp_WriteDataMReg_internal};
  internal_est_by_name["ifu_AlignedInstrRawDFlop"] = {{(MAX_W-32){1'bz}}, ifu_AlignedInstrRawDFlop_internal};
  internal_est_by_name["ifu_InstrEReg"] = {{(MAX_W-32){1'bz}}, ifu_InstrEReg_internal};
  internal_est_by_name["ifu_PCDReg"] = {{(MAX_W-64){1'bz}}, ifu_PCDReg_internal};
  internal_est_by_name["ifu_PCEReg"] = {{(MAX_W-64){1'bz}}, ifu_PCEReg_internal};
  internal_est_by_name["ifu_Spill_SpillDReg"] = {{(MAX_W-1){1'bz}}, ifu_Spill_SpillDReg_internal};
  internal_est_by_name["ifu_Spill_SpillEReg"] = {{(MAX_W-1){1'bz}}, ifu_Spill_SpillEReg_internal};
  internal_est_by_name["ifu_Spill_SpillMReg"] = {{(MAX_W-1){1'bz}}, ifu_Spill_SpillMReg_internal};
  internal_est_by_name["ifu_genblk9_InstrMReg"] = {{(MAX_W-32){1'bz}}, ifu_genblk9_InstrMReg_internal};
  internal_est_by_name["ifu_genblk10_PCMReg"] = {{(MAX_W-64){1'bz}}, ifu_genblk10_PCMReg_internal};
  internal_est_by_name["ifu_genblk11_CompressedDReg"] = {{(MAX_W-1){1'bz}}, ifu_genblk11_CompressedDReg_internal};
  internal_est_by_name["ifu_genblk11_CompressedEReg"] = {{(MAX_W-1){1'bz}}, ifu_genblk11_CompressedEReg_internal};
  internal_est_by_name["ifu_genblk12_CompressedMReg"] = {{(MAX_W-1){1'bz}}, ifu_genblk12_CompressedMReg_internal};
  internal_est_by_name["ifu_genblk12_InstrRawEReg"] = {{(MAX_W-16){1'bz}}, ifu_genblk12_InstrRawEReg_internal};
  internal_est_by_name["ifu_genblk12_InstrRawMReg"] = {{(MAX_W-16){1'bz}}, ifu_genblk12_InstrRawMReg_internal};
  internal_est_by_name["ifu_pcreg"] = {{(MAX_W-64){1'bz}}, pc_internal};
  internal_est_by_name["lsu_AddressMReg"] = {{(MAX_W-64){1'bz}}, lsu_AddressMReg_internal};
  internal_est_by_name["lsu_ReadDataMWReg"] = {{(MAX_W-64){1'bz}}, lsu_ReadDataMWReg_internal};
  internal_est_by_name["mdu_mdu_MDUResultWReg"] = {{(MAX_W-64){1'bz}}, mdu_mdu_MDUResultWReg_internal};
  internal_est_by_name["mdu_mdu_W64MReg"] = {{(MAX_W-1){1'bz}}, mdu_mdu_W64MReg_internal};
  internal_est_by_name["mdu_mdu_div_divfaultreg"] = {{(MAX_W-1){1'bz}}, mdu_mdu_div_divfaultreg_internal};
  internal_est_by_name["mdu_mdu_ftmul_primary_PP1Reg"] = {{(MAX_W-127){1'bz}}, mdu_mdu_ftmul_primary_PP1Reg_internal};
  internal_est_by_name["mdu_mdu_ftmul_primary_PP2Reg"] = {{(MAX_W-126){1'bz}}, mdu_mdu_ftmul_primary_PP2Reg_internal};
  internal_est_by_name["priv_priv_csr_CSRValWReg"] = {{(MAX_W-64){1'bz}}, priv_priv_csr_CSRValWReg_internal};
  internal_est_by_name["priv_priv_csr_csrm/MSECFAULT_REGW"] = {{(MAX_W-7){1'bz}}, priv_priv_csr_csrm_MSECFAULT_REGW_internal};
  internal_est_by_name["priv_priv_csr_csrm/RANDINSTRFREQreg"] = {{(MAX_W-32){1'bz}}, priv_priv_csr_csrm_RANDINSTRFREQreg_internal};
  internal_est_by_name["priv_priv_csr_csrsr_STATUS_MPP"] = {{(MAX_W-2){1'bz}}, priv_priv_csr_csrsr_STATUS_MPP_internal};
  internal_est_by_name["priv_priv_pmd_wfiWReg"] = {{(MAX_W-1){1'bz}}, priv_priv_pmd_wfiWReg_internal};
  internal_est_by_name["priv_priv_ppr_faultregD"] = {{(MAX_W-4){1'bz}}, priv_priv_ppr_faultregD_internal};
  internal_est_by_name["priv_priv_ppr_faultregE"] = {{(MAX_W-5){1'bz}}, priv_priv_ppr_faultregE_internal};
  internal_est_by_name["priv_priv_ppr_faultregM"] = {{(MAX_W-5){1'bz}}, priv_priv_ppr_faultregM_internal};
  internal_est_by_name["priv_priv_privmode_privmode_privchkreg_a"] = {{(MAX_W-2){1'bz}}, priv_priv_privmode_privmode_privchkreg_a_internal};
  internal_est_by_name["priv_priv_privmode_privmode_privchkreg_b"] = {{(MAX_W-2){1'bz}}, priv_priv_privmode_privmode_privchkreg_b_internal};
  internal_est_by_name["priv_priv_privmode_privmode_privchkreg_c"] = {{(MAX_W-2){1'bz}}, priv_priv_privmode_privmode_privchkreg_c_internal};
  internal_est_by_name["priv_priv_privmode_privmode_privmodereg_a"] = {{(MAX_W-2){1'bz}}, priv_priv_privmode_privmode_privmodereg_a_internal};
  internal_est_by_name["priv_priv_privmode_privmode_privmodereg_b"] = {{(MAX_W-2){1'bz}}, priv_priv_privmode_privmode_privmodereg_b_internal};
  internal_est_by_name["priv_priv_privmode_privmode_privmodereg_c"] = {{(MAX_W-2){1'bz}}, priv_priv_privmode_privmode_privmodereg_c_internal};

  // ---- internal_available_by_name ----
  // Availability mask: 1 = physical output can be probed; 0 = unavailable.
  internal_available_by_name["FTStatusSticky"] = val_t'(FTStatusSticky_raw_internal_available);
  internal_available_by_name["ieu_c_RdEReg"] = val_t'(ieu_c_RdEReg_raw_internal_available);
  internal_available_by_name["ieu_c_RdMReg"] = val_t'(ieu_c_RdMReg_raw_internal_available);
  internal_available_by_name["ieu_c_RdWReg"] = val_t'(ieu_c_RdWReg_raw_internal_available);
  internal_available_by_name["ieu_c_Rs1EReg"] = val_t'(ieu_c_Rs1EReg_raw_internal_available);
  internal_available_by_name["ieu_c_Rs2EReg"] = val_t'(ieu_c_Rs2EReg_raw_internal_available);
  internal_available_by_name["ieu_c_controlregD"] = val_t'(ieu_c_controlregD_raw_internal_available);
  internal_available_by_name["ieu_c_controlregE"] = val_t'(ieu_c_controlregE_raw_internal_available);
  internal_available_by_name["ieu_c_controlregM"] = val_t'(ieu_c_controlregM_raw_internal_available);
  internal_available_by_name["ieu_c_controlregW"] = val_t'(ieu_c_controlregW_raw_internal_available);
  internal_available_by_name["ieu_dp_IEUResultMReg"] = val_t'(ieu_dp_IEUResultMReg_raw_internal_available);
  internal_available_by_name["ieu_dp_IFResultWReg"] = val_t'(ieu_dp_IFResultWReg_raw_internal_available);
  internal_available_by_name["ieu_dp_ImmExtEReg"] = val_t'(ieu_dp_ImmExtEReg_raw_internal_available);
  internal_available_by_name["ieu_dp_RD1EReg"] = val_t'(ieu_dp_RD1EReg_raw_internal_available);
  internal_available_by_name["ieu_dp_RD2EReg"] = val_t'(ieu_dp_RD2EReg_raw_internal_available);
  internal_available_by_name["ieu_dp_SrcAMReg"] = val_t'(ieu_dp_SrcAMReg_raw_internal_available);
  internal_available_by_name["ieu_dp_WriteDataMReg"] = val_t'(ieu_dp_WriteDataMReg_raw_internal_available);
  internal_available_by_name["ifu_AlignedInstrRawDFlop"] = val_t'(ifu_AlignedInstrRawDFlop_raw_internal_available);
  internal_available_by_name["ifu_InstrEReg"] = val_t'(ifu_InstrEReg_raw_internal_available);
  internal_available_by_name["ifu_PCDReg"] = val_t'(ifu_PCDReg_raw_internal_available);
  internal_available_by_name["ifu_PCEReg"] = val_t'(ifu_PCEReg_raw_internal_available);
  internal_available_by_name["ifu_Spill_SpillDReg"] = val_t'(ifu_Spill_SpillDReg_raw_internal_available);
  internal_available_by_name["ifu_Spill_SpillEReg"] = val_t'(ifu_Spill_SpillEReg_raw_internal_available);
  internal_available_by_name["ifu_Spill_SpillMReg"] = val_t'(ifu_Spill_SpillMReg_raw_internal_available);
  internal_available_by_name["ifu_genblk9_InstrMReg"] = val_t'(ifu_genblk9_InstrMReg_raw_internal_available);
  internal_available_by_name["ifu_genblk10_PCMReg"] = val_t'(ifu_genblk10_PCMReg_raw_internal_available);
  internal_available_by_name["ifu_genblk11_CompressedDReg"] = val_t'(ifu_genblk11_CompressedDReg_raw_internal_available);
  internal_available_by_name["ifu_genblk11_CompressedEReg"] = val_t'(ifu_genblk11_CompressedEReg_raw_internal_available);
  internal_available_by_name["ifu_genblk12_CompressedMReg"] = val_t'(ifu_genblk12_CompressedMReg_raw_internal_available);
  internal_available_by_name["ifu_genblk12_InstrRawEReg"] = val_t'(ifu_genblk12_InstrRawEReg_raw_internal_available);
  internal_available_by_name["ifu_genblk12_InstrRawMReg"] = val_t'(ifu_genblk12_InstrRawMReg_raw_internal_available);
  internal_available_by_name["ifu_pcreg"] = val_t'(pc_raw_internal_available);
  internal_available_by_name["lsu_AddressMReg"] = val_t'(lsu_AddressMReg_raw_internal_available);
  internal_available_by_name["lsu_ReadDataMWReg"] = val_t'(lsu_ReadDataMWReg_raw_internal_available);
  internal_available_by_name["mdu_mdu_MDUResultWReg"] = val_t'(mdu_mdu_MDUResultWReg_raw_internal_available);
  internal_available_by_name["mdu_mdu_W64MReg"] = val_t'(mdu_mdu_W64MReg_raw_internal_available);
  internal_available_by_name["mdu_mdu_div_divfaultreg"] = val_t'(mdu_mdu_div_divfaultreg_raw_internal_available);
  internal_available_by_name["mdu_mdu_ftmul_primary_PP1Reg"] = val_t'(mdu_mdu_ftmul_primary_PP1Reg_raw_internal_available);
  internal_available_by_name["mdu_mdu_ftmul_primary_PP2Reg"] = val_t'(mdu_mdu_ftmul_primary_PP2Reg_raw_internal_available);
  internal_available_by_name["priv_priv_csr_CSRValWReg"] = val_t'(priv_priv_csr_CSRValWReg_raw_internal_available);
  internal_available_by_name["priv_priv_csr_csrm/MSECFAULT_REGW"] = val_t'(priv_priv_csr_csrm_MSECFAULT_REGW_raw_internal_available);
  internal_available_by_name["priv_priv_csr_csrm/RANDINSTRFREQreg"] = val_t'(priv_priv_csr_csrm_RANDINSTRFREQreg_raw_internal_available);
  internal_available_by_name["priv_priv_csr_csrsr_STATUS_MPP"] = val_t'(priv_priv_csr_csrsr_STATUS_MPP_raw_internal_available);
  internal_available_by_name["priv_priv_pmd_wfiWReg"] = val_t'(priv_priv_pmd_wfiWReg_raw_internal_available);
  internal_available_by_name["priv_priv_ppr_faultregD"] = val_t'(priv_priv_ppr_faultregD_raw_internal_available);
  internal_available_by_name["priv_priv_ppr_faultregE"] = val_t'(priv_priv_ppr_faultregE_raw_internal_available);
  internal_available_by_name["priv_priv_ppr_faultregM"] = val_t'(priv_priv_ppr_faultregM_raw_internal_available);
  internal_available_by_name["priv_priv_privmode_privmode_privchkreg_a"] = val_t'(priv_priv_privmode_privmode_privchkreg_a_raw_internal_available);
  internal_available_by_name["priv_priv_privmode_privmode_privchkreg_b"] = val_t'(priv_priv_privmode_privmode_privchkreg_b_raw_internal_available);
  internal_available_by_name["priv_priv_privmode_privmode_privchkreg_c"] = val_t'(priv_priv_privmode_privmode_privchkreg_c_raw_internal_available);
  internal_available_by_name["priv_priv_privmode_privmode_privmodereg_a"] = val_t'(priv_priv_privmode_privmode_privmodereg_a_raw_internal_available);
  internal_available_by_name["priv_priv_privmode_privmode_privmodereg_b"] = val_t'(priv_priv_privmode_privmode_privmodereg_b_raw_internal_available);
  internal_available_by_name["priv_priv_privmode_privmode_privmodereg_c"] = val_t'(priv_priv_privmode_privmode_privmodereg_c_raw_internal_available);

  // ---- internal_by_name ----
  // Compatibility alias of internal_est_by_name; not an independent observation.
  internal_by_name["FTStatusSticky"] = internal_est_by_name["FTStatusSticky"];
  internal_by_name["ieu_c_RdEReg"] = internal_est_by_name["ieu_c_RdEReg"];
  internal_by_name["ieu_c_RdMReg"] = internal_est_by_name["ieu_c_RdMReg"];
  internal_by_name["ieu_c_RdWReg"] = internal_est_by_name["ieu_c_RdWReg"];
  internal_by_name["ieu_c_Rs1EReg"] = internal_est_by_name["ieu_c_Rs1EReg"];
  internal_by_name["ieu_c_Rs2EReg"] = internal_est_by_name["ieu_c_Rs2EReg"];
  internal_by_name["ieu_c_controlregD"] = internal_est_by_name["ieu_c_controlregD"];
  internal_by_name["ieu_c_controlregE"] = internal_est_by_name["ieu_c_controlregE"];
  internal_by_name["ieu_c_controlregM"] = internal_est_by_name["ieu_c_controlregM"];
  internal_by_name["ieu_c_controlregW"] = internal_est_by_name["ieu_c_controlregW"];
  internal_by_name["ieu_dp_IEUResultMReg"] = internal_est_by_name["ieu_dp_IEUResultMReg"];
  internal_by_name["ieu_dp_IFResultWReg"] = internal_est_by_name["ieu_dp_IFResultWReg"];
  internal_by_name["ieu_dp_ImmExtEReg"] = internal_est_by_name["ieu_dp_ImmExtEReg"];
  internal_by_name["ieu_dp_RD1EReg"] = internal_est_by_name["ieu_dp_RD1EReg"];
  internal_by_name["ieu_dp_RD2EReg"] = internal_est_by_name["ieu_dp_RD2EReg"];
  internal_by_name["ieu_dp_SrcAMReg"] = internal_est_by_name["ieu_dp_SrcAMReg"];
  internal_by_name["ieu_dp_WriteDataMReg"] = internal_est_by_name["ieu_dp_WriteDataMReg"];
  internal_by_name["ifu_AlignedInstrRawDFlop"] = internal_est_by_name["ifu_AlignedInstrRawDFlop"];
  internal_by_name["ifu_InstrEReg"] = internal_est_by_name["ifu_InstrEReg"];
  internal_by_name["ifu_PCDReg"] = internal_est_by_name["ifu_PCDReg"];
  internal_by_name["ifu_PCEReg"] = internal_est_by_name["ifu_PCEReg"];
  internal_by_name["ifu_Spill_SpillDReg"] = internal_est_by_name["ifu_Spill_SpillDReg"];
  internal_by_name["ifu_Spill_SpillEReg"] = internal_est_by_name["ifu_Spill_SpillEReg"];
  internal_by_name["ifu_Spill_SpillMReg"] = internal_est_by_name["ifu_Spill_SpillMReg"];
  internal_by_name["ifu_genblk9_InstrMReg"] = internal_est_by_name["ifu_genblk9_InstrMReg"];
  internal_by_name["ifu_genblk10_PCMReg"] = internal_est_by_name["ifu_genblk10_PCMReg"];
  internal_by_name["ifu_genblk11_CompressedDReg"] = internal_est_by_name["ifu_genblk11_CompressedDReg"];
  internal_by_name["ifu_genblk11_CompressedEReg"] = internal_est_by_name["ifu_genblk11_CompressedEReg"];
  internal_by_name["ifu_genblk12_CompressedMReg"] = internal_est_by_name["ifu_genblk12_CompressedMReg"];
  internal_by_name["ifu_genblk12_InstrRawEReg"] = internal_est_by_name["ifu_genblk12_InstrRawEReg"];
  internal_by_name["ifu_genblk12_InstrRawMReg"] = internal_est_by_name["ifu_genblk12_InstrRawMReg"];
  internal_by_name["ifu_pcreg"] = internal_est_by_name["ifu_pcreg"];
  internal_by_name["lsu_AddressMReg"] = internal_est_by_name["lsu_AddressMReg"];
  internal_by_name["lsu_ReadDataMWReg"] = internal_est_by_name["lsu_ReadDataMWReg"];
  internal_by_name["mdu_mdu_MDUResultWReg"] = internal_est_by_name["mdu_mdu_MDUResultWReg"];
  internal_by_name["mdu_mdu_W64MReg"] = internal_est_by_name["mdu_mdu_W64MReg"];
  internal_by_name["mdu_mdu_div_divfaultreg"] = internal_est_by_name["mdu_mdu_div_divfaultreg"];
  internal_by_name["mdu_mdu_ftmul_primary_PP1Reg"] = internal_est_by_name["mdu_mdu_ftmul_primary_PP1Reg"];
  internal_by_name["mdu_mdu_ftmul_primary_PP2Reg"] = internal_est_by_name["mdu_mdu_ftmul_primary_PP2Reg"];
  internal_by_name["priv_priv_csr_CSRValWReg"] = internal_est_by_name["priv_priv_csr_CSRValWReg"];
  internal_by_name["priv_priv_csr_csrm/MSECFAULT_REGW"] = internal_est_by_name["priv_priv_csr_csrm/MSECFAULT_REGW"];
  internal_by_name["priv_priv_csr_csrm/RANDINSTRFREQreg"] = internal_est_by_name["priv_priv_csr_csrm/RANDINSTRFREQreg"];
  internal_by_name["priv_priv_csr_csrsr_STATUS_MPP"] = internal_est_by_name["priv_priv_csr_csrsr_STATUS_MPP"];
  internal_by_name["priv_priv_pmd_wfiWReg"] = internal_est_by_name["priv_priv_pmd_wfiWReg"];
  internal_by_name["priv_priv_ppr_faultregD"] = internal_est_by_name["priv_priv_ppr_faultregD"];
  internal_by_name["priv_priv_ppr_faultregE"] = internal_est_by_name["priv_priv_ppr_faultregE"];
  internal_by_name["priv_priv_ppr_faultregM"] = internal_est_by_name["priv_priv_ppr_faultregM"];
  internal_by_name["priv_priv_privmode_privmode_privchkreg_a"] = internal_est_by_name["priv_priv_privmode_privmode_privchkreg_a"];
  internal_by_name["priv_priv_privmode_privmode_privchkreg_b"] = internal_est_by_name["priv_priv_privmode_privmode_privchkreg_b"];
  internal_by_name["priv_priv_privmode_privmode_privchkreg_c"] = internal_est_by_name["priv_priv_privmode_privmode_privchkreg_c"];
  internal_by_name["priv_priv_privmode_privmode_privmodereg_a"] = internal_est_by_name["priv_priv_privmode_privmode_privmodereg_a"];
  internal_by_name["priv_priv_privmode_privmode_privmodereg_b"] = internal_est_by_name["priv_priv_privmode_privmode_privmodereg_b"];
  internal_by_name["priv_priv_privmode_privmode_privmodereg_c"] = internal_est_by_name["priv_priv_privmode_privmode_privmodereg_c"];

end

// ============================================================================
// Static hookup limitations
// ============================================================================
// Unavailable hookup sources; distinct from runtime X/Z on connected pins.

initial begin
  $display("%s", "INTERNAL UNAVAILABLE: FTStatusSticky[2] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: FTStatusSticky[3] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: FTStatusSticky[4] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: FTStatusSticky[5] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregE[0] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregE[3] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregE[4] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregE[5] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregE[6] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregE[7] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregE[8] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregE[9] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregE[10] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregE[13] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregE[18] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregE[20] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregE[21] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregE[22] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregE[23] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregE[24] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregE[25] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregE[26] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregM[0] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregM[2] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregM[3] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregM[4] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregM[5] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregM[6] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregM[7] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregM[11] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregM[14] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregW[0] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ieu_c_controlregW[2] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ifu_PCDReg[0] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ifu_PCEReg[0] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ifu_genblk10_PCMReg[0] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: ifu_pcreg[0] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[0] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[1] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[2] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[3] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[4] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[5] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[6] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[7] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[8] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[9] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[10] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[11] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[12] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[13] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[14] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[15] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[16] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[17] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[18] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[19] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[20] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[21] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[22] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[23] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[24] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[25] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[26] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[27] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[28] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[29] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[30] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[31] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[32] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[33] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[34] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[35] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[36] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[37] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[38] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[39] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[40] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[41] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[42] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[43] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[44] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[45] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[46] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[47] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[48] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[49] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[50] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[51] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[52] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[53] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[54] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[55] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[56] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[57] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[58] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[59] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[60] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[61] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
  $display("%s", "INTERNAL UNAVAILABLE: mdu_mdu_ftmul_primary_PP2Reg[62] instance=<unmapped> reason=no_scan_map_entry; constant/merged/optimized status is unproven");
end

