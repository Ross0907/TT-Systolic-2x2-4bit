// =============================================================================
// FILE        : systolic_2x2.v
// DESCRIPTION : 2×2 Systolic Array Matrix Multiplier
//
//   Computes C = A × B where A and B are 2×2 matrices with 4-bit elements.
//   Results are 9-bit accumulators (max 2 × 15×15 = 450).
//
//   Controller uses a cycle counter (0-3) with skewed feeding.
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module systolic_2x2 (
    input  wire       clk,
    input  wire       rst,
    input  wire       clk_en,
    input  wire       start,

    // Matrix A elements (4-bit each, row-major)
    input  wire [3:0] a00, a01,
    input  wire [3:0] a10, a11,

    // Matrix B elements (4-bit each, row-major)
    input  wire [3:0] b00, b01,
    input  wire [3:0] b10, b11,

    // Live accumulator outputs (9-bit each)
    output wire [8:0] acc00, acc01,
    output wire [8:0] acc10, acc11,

    // Status
    output reg        done,
    output reg        busy
);

    // -------------------------------------------------------------------------
    // Controller: cycle counter and status
    // -------------------------------------------------------------------------
    localparam CYCLES_TOTAL = 4'd4;

    reg [3:0] cycle_cnt;
    reg       active;

    always @(posedge clk) begin
        if (rst) begin
            active    <= 1'b0;
            cycle_cnt <= 4'd0;
            busy      <= 1'b0;
            done      <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start && !active) begin
                active    <= 1'b1;
                cycle_cnt <= 4'd0;
                busy      <= 1'b1;
            end else if (active) begin
                if (cycle_cnt == CYCLES_TOTAL - 1) begin
                    active <= 1'b0;
                    busy   <= 1'b0;
                    done   <= 1'b1;
                end else begin
                    cycle_cnt <= cycle_cnt + 4'd1;
                end
            end
        end
    end

    wire [3:0] t = cycle_cnt;
    wire       clear_pe = (t == 4'd0);
    wire       run_en   = active && clk_en;

    // -------------------------------------------------------------------------
    // Skewed feed generation (combinatorial)
    // -------------------------------------------------------------------------
    wire [3:0] feed_a0 = (t < 2)           ? (t==0 ? a00 : a01) : 4'd0;
    wire [3:0] feed_a1 = (t >= 1 && t < 3) ? (t==1 ? a10 : a11) : 4'd0;

    wire [3:0] feed_b0 = (t < 2)           ? (t==0 ? b00 : b10) : 4'd0;
    wire [3:0] feed_b1 = (t >= 1 && t < 3) ? (t==1 ? b01 : b11) : 4'd0;

    // -------------------------------------------------------------------------
    // PE grid interconnection wires
    // -------------------------------------------------------------------------
    wire [3:0] a_h00, a_h10;
    wire [3:0] b_v00, b_v01;

    // Dummy wires for unused edge outputs (prevents PINCONNECTEMPTY warnings)
    wire [3:0] a_unused;
    wire [3:0] b_unused;

    // -------------------------------------------------------------------------
    // Row 0
    // -------------------------------------------------------------------------
    systolic_pe pe00 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(feed_a0), .b_in(feed_b0), .a_out(a_h00), .b_out(b_v00), .acc(acc00));
    systolic_pe pe01 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h00),   .b_in(feed_b1), .a_out(a_unused), .b_out(b_v01), .acc(acc01));

    // -------------------------------------------------------------------------
    // Row 1
    // -------------------------------------------------------------------------
    systolic_pe pe10 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(feed_a1), .b_in(b_v00), .a_out(a_h10), .b_out(b_unused), .acc(acc10));
    systolic_pe pe11 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h10),   .b_in(b_v01), .a_out(a_unused), .b_out(b_unused), .acc(acc11));

endmodule

`default_nettype wire
