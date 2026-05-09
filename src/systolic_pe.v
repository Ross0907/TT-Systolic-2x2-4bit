// =============================================================================
// FILE        : systolic_pe.v
// DESCRIPTION : Processing Element for N×N Systolic Array
//
//   Each PE performs one MAC per active clock cycle:
//     acc = clear ? product : acc + product
//
//   a_in flows RIGHT to a_out  (forwarded to PE on the right)
//   b_in flows DOWN  to b_out  (forwarded to PE below)
//
//   Uses explicit 2×2 Wallace tree multiplier for speed.
//   ACC_WIDTH = 6 covers max sum of 4 products (4 × 9 = 36).
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module systolic_pe (
    input  wire       clk,
    input  wire       rst,
    input  wire       clk_en,
    input  wire       clear,
    input  wire [1:0] a_in,
    input  wire [1:0] b_in,
    output reg  [1:0] a_out,
    output reg  [1:0] b_out,
    output reg  [5:0] acc
);

    // -------------------------------------------------------------------------
    // 2×2 Wallace tree multiplier
    // -------------------------------------------------------------------------
    wire [3:0] product;

    wallace_mult_2x2 u_mult (
        .a(a_in),
        .b(b_in),
        .p(product)
    );

    // -------------------------------------------------------------------------
    // Accumulator (load-clear or accumulate)
    // -------------------------------------------------------------------------
    wire [5:0] product_ext = {2'b00, product};
    wire [5:0] next_acc    = clear ? product_ext : (acc + product_ext);

    always @(posedge clk) begin
        if (rst) begin
            a_out <= 2'b00;
            b_out <= 2'b00;
            acc   <= 6'd0;
        end else if (clk_en) begin
            a_out <= a_in;
            b_out <= b_in;
            acc   <= next_acc;
        end
    end

endmodule

`default_nettype wire
