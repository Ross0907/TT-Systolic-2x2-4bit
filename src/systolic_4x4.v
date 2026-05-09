`default_nettype none

module systolic_4x4 (

    input wire clk,
    input wire rst,
    input wire start,

    input wire [1:0] a00, a01, a02, a03,
    input wire [1:0] a10, a11, a12, a13,
    input wire [1:0] a20, a21, a22, a23,
    input wire [1:0] a30, a31, a32, a33,

    input wire [1:0] b00, b01, b02, b03,
    input wire [1:0] b10, b11, b12, b13,
    input wire [1:0] b20, b21, b22, b23,
    input wire [1:0] b30, b31, b32, b33,

    output wire [5:0] acc00, acc01, acc02, acc03,
    output wire [5:0] acc10, acc11, acc12, acc13,
    output wire [5:0] acc20, acc21, acc22, acc23,
    output wire [5:0] acc30, acc31, acc32, acc33,

    output reg done,
    output reg busy
);

    localparam TOTAL_CYCLES = 4'd8;

    reg [3:0] t;
    reg active;

    always @(posedge clk) begin

        if (rst) begin
            t      <= 4'd0;
            active <= 1'b0;
            busy   <= 1'b0;
            done   <= 1'b0;

        end else begin

            done <= 1'b0;

            if (start && !active) begin
                active <= 1'b1;
                busy   <= 1'b1;
                t      <= 4'd0;

            end else if (active) begin

                if (t == TOTAL_CYCLES-1) begin
                    active <= 1'b0;
                    busy   <= 1'b0;
                    done   <= 1'b1;
                end

                t <= t + 4'd1;
            end
        end
    end

    wire clear = start;

    // =========================================================================
    // A feed
    // =========================================================================

    wire [1:0] feed_a0 =
        (t==0) ? a00 :
        (t==1) ? a01 :
        (t==2) ? a02 :
        (t==3) ? a03 : 2'd0;

    wire [1:0] feed_a1 =
        (t==1) ? a10 :
        (t==2) ? a11 :
        (t==3) ? a12 :
        (t==4) ? a13 : 2'd0;

    wire [1:0] feed_a2 =
        (t==2) ? a20 :
        (t==3) ? a21 :
        (t==4) ? a22 :
        (t==5) ? a23 : 2'd0;

    wire [1:0] feed_a3 =
        (t==3) ? a30 :
        (t==4) ? a31 :
        (t==5) ? a32 :
        (t==6) ? a33 : 2'd0;

    // =========================================================================
    // B feed
    // =========================================================================

    wire [1:0] feed_b0 =
        (t==0) ? b00 :
        (t==1) ? b10 :
        (t==2) ? b20 :
        (t==3) ? b30 : 2'd0;

    wire [1:0] feed_b1 =
        (t==0) ? b01 :
        (t==1) ? b11 :
        (t==2) ? b21 :
        (t==3) ? b31 : 2'd0;

    wire [1:0] feed_b2 =
        (t==0) ? b02 :
        (t==1) ? b12 :
        (t==2) ? b22 :
        (t==3) ? b32 : 2'd0;

    wire [1:0] feed_b3 =
        (t==0) ? b03 :
        (t==1) ? b13 :
        (t==2) ? b23 :
        (t==3) ? b33 : 2'd0;

    // =========================================================================
    // Interconnect
    // =========================================================================

    wire [1:0] a01w, a02w, a03w;
    wire [1:0] a11w, a12w, a13w;
    wire [1:0] a21w, a22w, a23w;
    wire [1:0] a31w, a32w, a33w;

    wire [1:0] b10w, b11w, b12w, b13w;
    wire [1:0] b20w, b21w, b22w, b23w;
    wire [1:0] b30w, b31w, b32w, b33w;

    // =========================================================================
    // PE grid
    // =========================================================================

    systolic_pe pe00(clk,rst,active,clear,feed_a0,feed_b0,a01w,b10w,acc00);
    systolic_pe pe01(clk,rst,active,clear,a01w,feed_b1,a02w,b11w,acc01);
    systolic_pe pe02(clk,rst,active,clear,a02w,feed_b2,a03w,b12w,acc02);
    systolic_pe pe03(clk,rst,active,clear,a03w,feed_b3,,b13w,acc03);

    systolic_pe pe10(clk,rst,active,clear,feed_a1,b10w,a11w,b20w,acc10);
    systolic_pe pe11(clk,rst,active,clear,a11w,b11w,a12w,b21w,acc11);
    systolic_pe pe12(clk,rst,active,clear,a12w,b12w,a13w,b22w,acc12);
    systolic_pe pe13(clk,rst,active,clear,a13w,b13w,,b23w,acc13);

    systolic_pe pe20(clk,rst,active,clear,feed_a2,b20w,a21w,b30w,acc20);
    systolic_pe pe21(clk,rst,active,clear,a21w,b21w,a22w,b31w,acc21);
    systolic_pe pe22(clk,rst,active,clear,a22w,b22w,a23w,b32w,acc22);
    systolic_pe pe23(clk,rst,active,clear,a23w,b23w,,b33w,acc23);

    systolic_pe pe30(clk,rst,active,clear,feed_a3,b30w,a31w,,acc30);
    systolic_pe pe31(clk,rst,active,clear,a31w,b31w,a32w,,acc31);
    systolic_pe pe32(clk,rst,active,clear,a32w,b32w,a33w,,acc32);
    systolic_pe pe33(clk,rst,active,clear,a33w,b33w,,,acc33);

endmodule

`default_nettype wire