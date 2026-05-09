// =============================================================================
// FILE        : wallace_mult_2x2.v
// DESCRIPTION : 2×2 unsigned Wallace Tree Multiplier
//
//   Explicit Wallace tree reduction for educational value and speed.
//   For 2×2 the tree is minimal (just 2 half-adders), but the structure
//   demonstrates the technique used in larger multipliers.
//
//   Partial products:
//     w0: a0·b0
//     w1: a1·b0 , a0·b1
//     w2: a1·b1
//
//   Stage 1 (Wallace reduction):
//     Col 1: 2 pp → 1 HA  → sum bit 1, carry to col 2
//     Col 2: 2 pp → 1 HA  → sum bit 2, carry to col 3
//
//   Stage 2 (Carry-propagate adder): already reduced, just wire through.
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module wallace_mult_2x2 (
    input  wire [1:0] a,
    input  wire [1:0] b,
    output wire [3:0] p
);

    // -------------------------------------------------------------------------
    // Partial products
    // -------------------------------------------------------------------------
    wire pp00 = a[0] & b[0];  // weight 0
    wire pp10 = a[1] & b[0];  // weight 1
    wire pp01 = a[0] & b[1];  // weight 1
    wire pp11 = a[1] & b[1];  // weight 2

    // -------------------------------------------------------------------------
    // Wallace reduction stage 1
    // -------------------------------------------------------------------------
    // Column 1: 2 bits → half adder
    wire s1, c1_to_2;
    assign s1       = pp10 ^ pp01;
    assign c1_to_2  = pp10 & pp01;

    // Column 2: pp11 + carry from col 1 → half adder
    wire s2, c2_to_3;
    assign s2       = pp11 ^ c1_to_2;
    assign c2_to_3  = pp11 & c1_to_2;

    // -------------------------------------------------------------------------
    // Final product
    // -------------------------------------------------------------------------
    assign p[0] = pp00;
    assign p[1] = s1;
    assign p[2] = s2;
    assign p[3] = c2_to_3;

endmodule

`default_nettype wire
