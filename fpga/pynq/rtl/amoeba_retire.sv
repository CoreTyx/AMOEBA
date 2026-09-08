///////////////////////////////////////////////////////////////////////////////
// amoeba_retire.sv
//
// The retired-instruction and trap counters, as a module of their own so that
// they exist in EVERY build.
//
// WHY THIS WAS SPLIT OUT.  These counters used to live inside amoeba_trace,
// whose own comment called them "always-on ... they run in every mode
// including OFF".  That was true of the trace MODES and false of the trace
// PARAMETER: amoeba_trace is only instantiated when TRACE=1, so in a TRACE=0
// build the top tied retired and traps to zero.  Every TRACE=0 run therefore
// reported "0 retired, 0 traps" no matter what the core was doing -- including
// a FreeRTOS build that was demonstrably alive and printing heartbeats on the
// console at the time.  Two of the three headline counters were constants, and
// they read exactly the same on a healthy machine as on a wedged one.
//
// ~100 flops.  There is no build in which that is worth the ambiguity.
///////////////////////////////////////////////////////////////////////////////

module amoeba_retire #(
    parameter int XLEN = 64
)(
    input  logic            clk,
    input  logic            rst,            // PL reset, active high
    input  logic            clear,          // CTRL monitor clear
    input  logic            core_reset,     // counters restart with the core

    // M-stage taps and the pipeline controls needed to walk them to W.  These
    // are the same nets hdl/rv64_core_wrapper.sv uses for its RVFI monitor, so
    // "retired" means the same thing here, in simulation, and in the trace.
    input  logic            StallW,
    input  logic            FlushW,
    input  logic [XLEN-1:0] PCM,
    input  logic            InstrValidM,
    input  logic            TrapM,

    output logic [63:0]     retired,
    output logic [31:0]     traps
);

    // Same reset term amoeba_trace uses, so the two agree on where a count
    // starts: PL reset, an explicit monitor clear, or the core being held.
    logic tap_rst;
    assign tap_rst = rst | clear | core_reset;

    logic [XLEN-1:0] PCW;
    logic            InstrValidW;
    logic            TrapW;

    flopenrc #(XLEN) pc_w   (clk, tap_rst, FlushW, ~StallW, PCM,         PCW);
    flopenrc #(1)    iv_w   (clk, tap_rst, FlushW, ~StallW, InstrValidM, InstrValidW);
    // NOT walked to W like the others.  A trap FLUSHES W in the very cycle
    // TrapM asserts, so a TrapM value enabled through a FlushW-cleared flop
    // can never be observed, and a trapped instruction never satisfies the
    // retire condition either -- the old form made traps structurally
    // uncountable (a FreeRTOS run full of timer interrupts reported 0).
    // Edge-detect at M instead: the flush empties M behind a trap, so
    // consecutive trap events are always at least two cycles apart.
    logic TrapM_q;
    flopr #(1) trap_q (clk, tap_rst, TrapM, TrapM_q);
    assign TrapW = TrapM & ~TrapM_q;

    // Same retire condition hdl/rv64_core_wrapper.sv uses for monitor_valid.
    // The (|PCW) term suppresses the bubble that walks out of the pipeline
    // after reset, which would otherwise count as a retired instruction.
    logic retire;
    assign retire = InstrValidW & ~StallW & (|PCW);

    always_ff @(posedge clk) begin
        if (tap_rst) begin
            retired <= '0;
            traps   <= '0;
        end else begin
            if (retire) retired <= retired + 1'b1;
            if (TrapW)  traps   <= traps   + 1'b1;
        end
    end

endmodule
