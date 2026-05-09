// =============================================================================
// FILE        : systolic_4x4.v
// DESCRIPTION : 4×4 Systolic Array Matrix Multiplier
//
//   Computes C = A × B where A and B are 4×4 matrices with 2-bit elements.
//   Results are 6-bit accumulators (max 4 × 3×3 = 36).
//
//   Controller uses a cycle counter (0-9) with skewed feeding.
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module systolic_4x4 (
    input  wire       clk,
    input  wire       rst,
    input  wire       clk_en,
    input  wire       start,

    // Matrix A elements (2-bit each, row-major)
    input  wire [1:0] a00, a01, a02, a03,
    input  wire [1:0] a10, a11, a12, a13,
    input  wire [1:0] a20, a21, a22, a23,
    input  wire [1:0] a30, a31, a32, a33,

    // Matrix B elements (2-bit each, row-major)
    input  wire [1:0] b00, b01, b02, b03,
    input  wire [1:0] b10, b11, b12, b13,
    input  wire [1:0] b20, b21, b22, b23,
    input  wire [1:0] b30, b31, b32, b33,

    // Live accumulator outputs
    output wire [5:0] acc00, acc01, acc02, acc03,
    output wire [5:0] acc10, acc11, acc12, acc13,
    output wire [5:0] acc20, acc21, acc22, acc23,
    output wire [5:0] acc30, acc31, acc32, acc33,

    // Status
    output reg        done,
    output reg        busy
);

    // -------------------------------------------------------------------------
    // Controller: cycle counter and status
    // -------------------------------------------------------------------------
    localparam CYCLES_TOTAL = 4'd10;

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
    wire [1:0] feed_a0 = (t < 4)           ? (t==0?a00:(t==1?a01:(t==2?a02:a03))) : 2'd0;
    wire [1:0] feed_a1 = (t >= 1 && t < 5) ? (t==1?a10:(t==2?a11:(t==3?a12:a13))) : 2'd0;
    wire [1:0] feed_a2 = (t >= 2 && t < 6) ? (t==2?a20:(t==3?a21:(t==4?a22:a23))) : 2'd0;
    wire [1:0] feed_a3 = (t >= 3 && t < 7) ? (t==3?a30:(t==4?a31:(t==5?a32:a33))) : 2'd0;

    wire [1:0] feed_b0 = (t < 4)           ? (t==0?b00:(t==1?b10:(t==2?b20:b30))) : 2'd0;
    wire [1:0] feed_b1 = (t >= 1 && t < 5) ? (t==1?b01:(t==2?b11:(t==3?b21:b31))) : 2'd0;
    wire [1:0] feed_b2 = (t >= 2 && t < 6) ? (t==2?b02:(t==3?b12:(t==4?b22:b32))) : 2'd0;
    wire [1:0] feed_b3 = (t >= 3 && t < 7) ? (t==3?b03:(t==4?b13:(t==5?b23:b33))) : 2'd0;

    // -------------------------------------------------------------------------
    // PE grid interconnection wires
    // -------------------------------------------------------------------------
    wire [1:0] a_h00, a_h01, a_h02, a_h03;
    wire [1:0] a_h10, a_h11, a_h12, a_h13;
    wire [1:0] a_h20, a_h21, a_h22, a_h23;
    wire [1:0] a_h30, a_h31, a_h32, a_h33;

    wire [1:0] b_v00, b_v01, b_v02, b_v03;
    wire [1:0] b_v10, b_v11, b_v12, b_v13;
    wire [1:0] b_v20, b_v21, b_v22, b_v23;
    wire [1:0] b_v30, b_v31, b_v32, b_v33;

    // -------------------------------------------------------------------------
    // Row 0
    // -------------------------------------------------------------------------
    systolic_pe pe00 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(feed_a0),  .b_in(feed_b0),  .a_out(a_h00), .b_out(b_v00), .acc(acc00));
    systolic_pe pe01 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h00),    .b_in(feed_b1),  .a_out(a_h01), .b_out(b_v01), .acc(acc01));
    systolic_pe pe02 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h01),    .b_in(feed_b2),  .a_out(a_h02), .b_out(b_v02), .acc(acc02));
    systolic_pe pe03 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h02),    .b_in(feed_b3),  .a_out(a_h03), .b_out(b_v03), .acc(acc03));

    // -------------------------------------------------------------------------
    // Row 1
    // -------------------------------------------------------------------------
    systolic_pe pe10 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(feed_a1),  .b_in(b_v00),    .a_out(a_h10), .b_out(b_v10), .acc(acc10));
    systolic_pe pe11 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h10),    .b_in(b_v01),    .a_out(a_h11), .b_out(b_v11), .acc(acc11));
    systolic_pe pe12 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h11),    .b_in(b_v02),    .a_out(a_h12), .b_out(b_v12), .acc(acc12));
    systolic_pe pe13 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h12),    .b_in(b_v03),    .a_out(a_h13), .b_out(b_v13), .acc(acc13));

    // -------------------------------------------------------------------------
    // Row 2
    // -------------------------------------------------------------------------
    systolic_pe pe20 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(feed_a2),  .b_in(b_v10),    .a_out(a_h20), .b_out(b_v20), .acc(acc20));
    systolic_pe pe21 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h20),    .b_in(b_v11),    .a_out(a_h21), .b_out(b_v21), .acc(acc21));
    systolic_pe pe22 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h21),    .b_in(b_v12),    .a_out(a_h22), .b_out(b_v22), .acc(acc22));
    systolic_pe pe23 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h22),    .b_in(b_v13),    .a_out(a_h23), .b_out(b_v23), .acc(acc23));

    // -------------------------------------------------------------------------
    // Row 3
    // -------------------------------------------------------------------------
    systolic_pe pe30 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(feed_a3),  .b_in(b_v20),    .a_out(a_h30), .b_out(b_v30), .acc(acc30));
    systolic_pe pe31 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h30),    .b_in(b_v21),    .a_out(a_h31), .b_out(b_v31), .acc(acc31));
    systolic_pe pe32 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h31),    .b_in(b_v22),    .a_out(a_h32), .b_out(b_v32), .acc(acc32));
    systolic_pe pe33 (.clk(clk), .rst(rst), .clk_en(run_en), .clear(clear_pe), .a_in(a_h32),    .b_in(b_v23),    .a_out(a_h33), .b_out(b_v33), .acc(acc33));

endmodule

`default_nettype wire
