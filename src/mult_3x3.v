// =============================================================================
// FILE        : mult_3x3.v
// DESCRIPTION : 3×3 unsigned multiplier
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module mult_3x3 (
    input  wire [2:0] a,
    input  wire [2:0] b,
    output wire [5:0] p
);

    assign p = a * b;

endmodule

`default_nettype wire
