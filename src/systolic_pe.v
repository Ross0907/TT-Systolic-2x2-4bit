`default_nettype none
`timescale 1ns / 1ps

module systolic_pe (
    input  wire       clk,
    input  wire       rst,
    input  wire       clk_en,
    input  wire       clear,
    input  wire [1:0] a_in,
    input  wire [1:0] b_in,

    output wire [1:0] a_out,
    output wire [1:0] b_out,

    output reg  [5:0] acc
);

    // combinational forwarding
    assign a_out = a_in;
    assign b_out = b_in;

    // Wallace multiplier
    wire [3:0] product;

    wallace_mult_2x2 u_mult (
        .a(a_in),
        .b(b_in),
        .p(product)
    );

    wire [5:0] product_ext = {2'b00, product};

    always @(posedge clk) begin
        if (rst) begin
            acc <= 6'd0;
        end else if (clk_en) begin
            if (clear)
                acc <= product_ext;
            else
                acc <= acc + product_ext;
        end
    end

endmodule

`default_nettype wire