`default_nettype none

module systolic_pe (

    input wire clk,
    input wire rst,
    input wire clk_en,
    input wire clear,

    input wire [1:0] a_in,
    input wire [1:0] b_in,

    output reg [1:0] a_out,
    output reg [1:0] b_out,

    output reg [5:0] acc
);

    wire [3:0] product;

    wallace_mult_2x2 mult (
        .a(a_in),
        .b(b_in),
        .p(product)
    );

    always @(posedge clk) begin

        if (rst) begin
            a_out <= 2'd0;
            b_out <= 2'd0;
            acc   <= 6'd0;

        end else if (clk_en) begin

            a_out <= a_in;
            b_out <= b_in;

            if (clear)
                acc <= {2'b00, product};
            else
                acc <= acc + {2'b00, product};
        end
    end

endmodule

`default_nettype wire