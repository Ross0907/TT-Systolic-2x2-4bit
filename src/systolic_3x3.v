// =============================================================================
// FILE        : systolic_3x3.v
// DESCRIPTION : 3×3 Systolic Array Matrix Multiplier
//
//   Computes C = A × B where A and B are 3×3 matrices with 3-bit elements.
//   Results are 8-bit accumulators (max 3 × 7×7 = 147).
//
//   Controller uses a cycle counter (0-7) with skewed feeding.
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module systolic_3x3 (
    input  wire       clk,
    input  wire       rst,
    input  wire       clk_en,
    input  wire       start,

    // Matrix A elements (3-bit each, row-major)
    input  wire [2:0] a00, a01, a02,
    input  wire [2:0] a10, a11, a12,
    input  wire [2:0] a20, a21, a22,

    // Matrix B elements (3-bit each, row-major)
    input  wire [2:0] b00, b01, b02,
    input  wire [2:0] b10, b11, b12,
    input  wire [2:0] b20, b21, b22,

    // Live accumulator outputs
    output wire [7:0] acc00, acc01, acc02,
    output wire [7:0] acc10, acc11, acc12,
    output wire [7:0] acc20, acc21, acc22,

    // Status
    output reg        done,
    output reg        busy
);

    // -------------------------------------------------------------------------
    // Controller: cycle counter and status
    // -------------------------------------------------------------------------
    localparam CYCLES_TOTAL = 4'd8;

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
    wire [2:0] feed_a0 = (t < 3)           ? (t==0?a00:(t==1?a01:a02)) : 3'd0;
    wire [2:0] feed_a1 = (t >= 1 && t < 4) ? (t==1?a10:(t==2?a11:a12)) : 3'd0;
    wire [2:0] feed_a2 = (t >= 2 && t < 5) ? (t==2?a20:(t==3?a21:a22)) : 3'd0;

    wire [2:0] feed_b0 = (t < 3)           ? (t==0?b00:(t==1?b10:b20)) : 3'd0;
    wire [2:0] feed_b1 = (t >= 1 && t < 4) ? (t==1?b01:(t==2?b11:b21)) : 3'd0;
    wire [2:0] feed_b2 = (t >= 2 && t < 5) ? (t==2?b02:(t==3?b12:b22)) : 3'd0;

    // -------------------------------------------------------------------------
    // PE grid interconnection wires
    // -------------------------------------------------------------------------
    wire [2:0] a_h00, a_h01;
    wire [2:0] a_h10, a_h11;
    wire [2:0] a_h20, a_h21;

    wire [2:0] b_v00, b_v01, b_v02;
    wire [2:0] b_v10, b_v11, b_v12;

    // -------------------------------------------------------------------------
    // Row 0
    // -------------------------------------------------------------------------
    systolic_pe pe00 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(feed_a0),  .b_in(feed_b0),  .a_out(a_h00), .b_out(b_v00), .acc(acc00));
    systolic_pe pe01 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h00),    .b_in(feed_b1),  .a_out(a_h01), .b_out(b_v01), .acc(acc01));
    systolic_pe pe02 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h01),    .b_in(feed_b2),  .a_out(),      .b_out(b_v02), .acc(acc02));

    // -------------------------------------------------------------------------
    // Row 1
    // -------------------------------------------------------------------------
    systolic_pe pe10 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(feed_a1),  .b_in(b_v00),    .a_out(a_h10), .b_out(b_v10), .acc(acc10));
    systolic_pe pe11 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h10),    .b_in(b_v01),    .a_out(a_h11), .b_out(b_v11), .acc(acc11));
    systolic_pe pe12 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h11),    .b_in(b_v02),    .a_out(),      .b_out(b_v12), .acc(acc12));

    // -------------------------------------------------------------------------
    // Row 2
    // -------------------------------------------------------------------------
    systolic_pe pe20 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(feed_a2),  .b_in(b_v10),    .a_out(a_h20), .b_out(),      .acc(acc20));
    systolic_pe pe21 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h20),    .b_in(b_v11),    .a_out(a_h21), .b_out(),      .acc(acc21));
    systolic_pe pe22 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h21),    .b_in(b_v12),    .a_out(),      .b_out(),      .acc(acc22));

endmodule

`default_nettype wire
