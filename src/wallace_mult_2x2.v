`default_nettype none

module wallace_mult_2x2 (
    input  wire [1:0] a,
    input  wire [1:0] b,
    output wire [3:0] p
);

    wire pp00 = a[0] & b[0];
    wire pp01 = a[0] & b[1];
    wire pp10 = a[1] & b[0];
    wire pp11 = a[1] & b[1];

    wire s1;
    wire c1;

    assign s1 = pp01 ^ pp10;
    assign c1 = pp01 & pp10;

    wire s2;
    wire c2;

    assign s2 = pp11 ^ c1;
    assign c2 = pp11 & c1;

    assign p[0] = pp00;
    assign p[1] = s1;
    assign p[2] = s2;
    assign p[3] = c2;

endmodule

`default_nettype wire