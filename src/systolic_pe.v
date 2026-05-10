// =============================================================================
// FILE        : systolic_pe.v
// DESCRIPTION : Processing Element for 2×2 Systolic Array (4-bit elements)
//
//   Each PE performs one MAC per active clock cycle:
//     acc = clear ? product : acc + product
//
//   a_in flows RIGHT to a_out  (forwarded to PE on the right)
//   b_in flows DOWN  to b_out  (forwarded to PE below)
//
//   ACC_WIDTH = 9 covers max sum of 2 products (2 × 225 = 450).
// =============================================================================

`default_nettype none

module systolic_pe (
    input  wire       clk,
    input  wire       rst,
    input  wire       clk_en,
    input  wire       clear,
    input  wire [3:0] a_in,
    input  wire [3:0] b_in,
    output reg  [3:0] a_out,
    output reg  [3:0] b_out,
    output reg  [8:0] acc
);

    // -------------------------------------------------------------------------
    // 4×4 multiplier
    // -------------------------------------------------------------------------
    wire [7:0] product;

    mult_4x4 u_mult (
        .a(a_in),
        .b(b_in),
        .p(product)
    );

    // -------------------------------------------------------------------------
    // Accumulator (load-clear or accumulate)
    // -------------------------------------------------------------------------
    wire [8:0] product_ext = {1'b0, product};
    wire [8:0] next_acc    = clear ? product_ext : (acc + product_ext);

    always @(posedge clk) begin
        if (rst) begin
            a_out <= 4'b0000;
            b_out <= 4'b0000;
            acc   <= 9'd0;
        end else if (clk_en) begin
            a_out <= a_in;
            b_out <= b_in;
            acc   <= next_acc;
        end
    end

endmodule

`default_nettype wire