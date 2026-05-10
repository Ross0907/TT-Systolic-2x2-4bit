// =============================================================================
// FILE        : mult_4x4.v
// DESCRIPTION : 4×4 unsigned multiplier (8-bit product)
// =============================================================================

`default_nettype none

module mult_4x4 (
    input  wire [3:0] a,
    input  wire [3:0] b,
    output wire [7:0] p
);

    assign p = a * b;

endmodule

`default_nettype wire
