///////////////////////////////////////////////////////////////////////////////
// amoeba_uart_xcvr.sv
//
// The PL end of the DUT's serial line: a deserializer on the 16550's SOUT and
// a serializer into its SIN, both behind FIFOs the PS reads and writes through
// amoeba_ctl.  This is how characters get INTO the guest -- the console snoop
// in amoeba_bus_mon only ever listened -- and it is the console the silicon
// bring-up board will have to use, where there is no bus to snoop.  See
// docs/impl_plan_shell.md.
//
// TIMEBASE.  Wally's 16550 runs its 16x baud clock at one pulse every
// {DLM,DLL} << UART_PRESCALE PCLK cycles (uartPC16550D.sv, baudpulseComb), so
// a bit is 16 of those.  `tick` is that pulse period in PCLK cycles, and the
// top supplies it either from amoeba_bus_mon's shadow of the guest's divisor
// (exact, whatever the guest programs -- FreeRTOS leaves the reset value 1,
// Linux writes what its DTS clock-frequency implies) or from a register the
// host programs, for the platform where the divisor cannot be seen.  A tick
// of 0 is treated as 1 rather than stopping the line.
//
// RX.  Two flops of synchronizer (the same net in-fabric; a pad later), a
// falling edge starts the receiver, half a bit later the start bit is
// confirmed still low (a glitch returns to idle), then eight data bits and the
// stop bit are sampled one bit apart -- each sample at the centre of its bit.
// 8N1 only.  A stop bit read as 0 is a framing error: counted, and the byte is
// pushed anyway, so a wrong divisor shows up as garbage AND a count rather
// than as silence.  The receiver returns to idle right after the stop sample,
// so a start edge in the second half of the stop bit is not missed.
//
// TX.  Start, eight data bits LSB first, stop; one bit per 16 ticks; idle is
// mark.  The FIFO in front is small: the PS paces itself on `tx_full`, and a
// 16550 with FIFOs reads faster than any rate here.
///////////////////////////////////////////////////////////////////////////////

module amoeba_uart_xcvr #(
    parameter int RX_FIFO_LOG2 = 10,     // match the snoop's: same stream
    parameter int TX_FIFO_LOG2 = 4
)(
    input  logic                    clk,
    input  logic                    rst,        // synchronous, active high
    input  logic                    clear,      // one-cycle: empty both FIFOs, zero the counters

    input  logic [19:0]             tick,       // PCLK cycles per 16x baud tick

    // ---- the line ----------------------------------------------------------
    input  logic                    sin,        // the DUT's SOUT
    output logic                    sout,       // the DUT's SIN

    // ---- received bytes (DUT -> PS) -----------------------------------------
    output logic [7:0]              rx_data,
    output logic                    rx_valid,
    input  logic                    rx_pop,
    output logic [15:0]             rx_level,
    output logic                    rx_overflow,
    output logic [7:0]              rx_ferr,    // framing errors, saturating

    // ---- bytes to send (PS -> DUT) ------------------------------------------
    input  logic                    tx_push,
    input  logic [7:0]              tx_data,
    output logic                    tx_full,
    output logic [15:0]             tx_level,
    output logic                    tx_busy     // a frame is on the line
);

    // ---- timebase ----------------------------------------------------------
    // A bit is 16 ticks; half a bit is 8.  24 bits covers 16 x 2^20.
    logic [19:0] tick_eff;
    logic [23:0] bit_cycles, half_cycles;
    assign tick_eff    = (tick == 20'd0) ? 20'd1 : tick;
    assign bit_cycles  = {tick_eff, 4'b0000};
    assign half_cycles = {1'b0, tick_eff, 3'b000};

    // ---- RX ------------------------------------------------------------------
    logic sin_m, sin_s, sin_q;              // synchronizer + edge history
    always_ff @(posedge clk) begin
        if (rst) begin
            sin_m <= 1'b1; sin_s <= 1'b1; sin_q <= 1'b1;
        end else begin
            sin_m <= sin; sin_s <= sin_m; sin_q <= sin_s;
        end
    end
    logic start_edge;
    assign start_edge = sin_q & ~sin_s;

    typedef enum logic [1:0] { RX_IDLE, RX_START, RX_DATA, RX_STOP } rx_state_t;
    rx_state_t   rx_st;
    logic [23:0] rx_cnt;                    // cycles until the next sample
    logic [2:0]  rx_bit;
    logic [7:0]  rx_shift;
    logic        rx_push;
    logic [7:0]  rx_byte;
    logic        rx_fifo_full, rx_fifo_empty;
    logic [RX_FIFO_LOG2:0] rx_fifo_level;

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            rx_st    <= RX_IDLE;
            rx_cnt   <= '0;
            rx_bit   <= '0;
            rx_shift <= '0;
            rx_push  <= 1'b0;
            rx_byte  <= '0;
            rx_ferr  <= '0;
        end else begin
            rx_push <= 1'b0;
            case (rx_st)
                RX_IDLE: if (start_edge) begin
                    // The edge was seen on sin_s one cycle ago; the centre of
                    // the start bit is half a bit after the edge.
                    rx_cnt <= half_cycles - 24'd2;
                    rx_st  <= RX_START;
                end
                RX_START: begin
                    if (rx_cnt != 24'd0) rx_cnt <= rx_cnt - 1'b1;
                    else if (!sin_s) begin
                        rx_cnt <= bit_cycles - 24'd1;
                        rx_bit <= 3'd0;
                        rx_st  <= RX_DATA;
                    end else begin
                        rx_st  <= RX_IDLE;        // glitch, not a start bit
                    end
                end
                RX_DATA: begin
                    if (rx_cnt != 24'd0) rx_cnt <= rx_cnt - 1'b1;
                    else begin
                        rx_shift <= {sin_s, rx_shift[7:1]};   // LSB first
                        rx_cnt   <= bit_cycles - 24'd1;
                        rx_bit   <= rx_bit + 1'b1;
                        if (rx_bit == 3'd7) rx_st <= RX_STOP;
                    end
                end
                RX_STOP: begin
                    if (rx_cnt != 24'd0) rx_cnt <= rx_cnt - 1'b1;
                    else begin
                        rx_push <= 1'b1;
                        rx_byte <= rx_shift;
                        if (!sin_s && rx_ferr != 8'hFF) rx_ferr <= rx_ferr + 1'b1;
                        rx_st   <= RX_IDLE;
                    end
                end
                default: rx_st <= RX_IDLE;
            endcase
        end
    end

    amoeba_fifo #(
        .W          (8),
        .DEPTH_LOG2 (RX_FIFO_LOG2)
    ) rx_fifo (
        .clk      (clk),
        .rst      (rst | clear),
        .wr_en    (rx_push),
        .wr_data  (rx_byte),
        .full     (rx_fifo_full),
        .overflow (rx_overflow),
        .rd_en    (rx_pop),
        .rd_data  (rx_data),
        .empty    (rx_fifo_empty),
        .level    (rx_fifo_level)
    );
    assign rx_valid = ~rx_fifo_empty;
    assign rx_level = 16'(rx_fifo_level);

    // ---- TX ------------------------------------------------------------------
    logic [7:0]  tx_fifo_data;
    logic        tx_fifo_empty, tx_pop;
    logic [TX_FIFO_LOG2:0] tx_fifo_level;

    amoeba_fifo #(
        .W          (8),
        .DEPTH_LOG2 (TX_FIFO_LOG2)
    ) tx_fifo (
        .clk      (clk),
        .rst      (rst | clear),
        .wr_en    (tx_push),
        .wr_data  (tx_data),
        .full     (tx_full),
        .overflow (),                       // the PS paces on tx_full
        .rd_en    (tx_pop),
        .rd_data  (tx_fifo_data),
        .empty    (tx_fifo_empty),
        .level    (tx_fifo_level)
    );
    assign tx_level = 16'(tx_fifo_level);

    logic [9:0]  tx_shift;                  // {stop, data[7:0], start}
    logic [3:0]  tx_bits;                   // bits left in the frame
    logic [23:0] tx_cnt;

    // Busy until the stop bit has had its full period, not just until it was
    // driven; otherwise the next start bit would cut it short.
    assign tx_busy = (tx_bits != 4'd0) | (tx_cnt != 24'd0);
    assign tx_pop  = ~tx_fifo_empty & ~tx_busy;

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            tx_shift <= '1;
            tx_bits  <= '0;
            tx_cnt   <= '0;
            sout     <= 1'b1;
        end else if (!tx_busy) begin
            sout <= 1'b1;
            if (tx_pop) begin
                tx_shift <= {1'b1, tx_fifo_data, 1'b0};
                tx_bits  <= 4'd10;
                tx_cnt   <= '0;
            end
        end else if (tx_cnt != 24'd0) begin
            tx_cnt <= tx_cnt - 1'b1;
        end else begin
            sout     <= tx_shift[0];
            tx_shift <= {1'b1, tx_shift[9:1]};
            tx_bits  <= tx_bits - 1'b1;
            tx_cnt   <= bit_cycles - 24'd1;
        end
    end

    logic unused;
    assign unused = rx_fifo_full;

endmodule
