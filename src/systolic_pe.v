// =============================================================================
// FILE        : systolic_pe.v
// DESCRIPTION : Processing Element for 3×3 Systolic Array
//
//   Each PE performs one MAC per active clock cycle:
//     acc = clear ? product : acc + product
//
//   a_in flows RIGHT to a_out  (forwarded to PE on the right)
//   b_in flows DOWN  to b_out  (forwarded to PE below)
//
//   ACC_WIDTH = 8 covers max sum of 3 products (3 × 49 = 147).
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module systolic_pe (
    input  wire       clk,
    input  wire       rst,
    input  wire       clk_en,
    input  wire       clear,
    input  wire [2:0] a_in,
    input  wire [2:0] b_in,
    output reg  [2:0] a_out,
    output reg  [2:0] b_out,
    output reg  [7:0] acc
);

    // -------------------------------------------------------------------------
    // 3×3 multiplier
    // -------------------------------------------------------------------------
    wire [5:0] product;

    mult_3x3 u_mult (
        .a(a_in),
        .b(b_in),
        .p(product)
    );

    // -------------------------------------------------------------------------
    // Accumulator (load-clear or accumulate)
    // -------------------------------------------------------------------------
    wire [7:0] product_ext = {2'b00, product};
    wire [7:0] next_acc    = clear ? product_ext : (acc + product_ext);

    always @(posedge clk) begin
        if (rst) begin
            a_out <= 3'b000;
            b_out <= 3'b000;
            acc   <= 8'd0;
        end else if (clk_en) begin
            a_out <= a_in;
            b_out <= b_in;
            acc   <= next_acc;
        end
    end

endmodule

`default_nettype wire