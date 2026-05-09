/* verilator lint_off TIMESCALEMOD */
/*
 * Copyright (c) 2026 Roshan Tripathy
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`timescale 1ns / 1ps

// =============================================================================
// Tiny Tapeout Top
// =============================================================================

module tt_um_ross_systolic (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,

    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,

    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    wire rst = ~rst_n;

    wire wren  = uio_in[0];
    wire start = uio_in[1];
    wire debug = uio_in[2];

    wire start_gated;

    // =========================================================================
    // Matrix storage
    // =========================================================================

    reg [7:0] mat_reg [0:7];
    reg [2:0] byte_addr;

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            byte_addr <= 3'd0;

            for (i = 0; i < 8; i = i + 1)
                mat_reg[i] <= 8'd0;

        end else if (wren) begin
            mat_reg[byte_addr] <= ui_in;
            byte_addr <= byte_addr + 3'd1;
        end
    end

    // =========================================================================
    // Unpack A
    // =========================================================================

    wire [1:0] a00 = mat_reg[0][1:0];
    wire [1:0] a01 = mat_reg[0][3:2];
    wire [1:0] a02 = mat_reg[0][5:4];
    wire [1:0] a03 = mat_reg[0][7:6];

    wire [1:0] a10 = mat_reg[1][1:0];
    wire [1:0] a11 = mat_reg[1][3:2];
    wire [1:0] a12 = mat_reg[1][5:4];
    wire [1:0] a13 = mat_reg[1][7:6];

    wire [1:0] a20 = mat_reg[2][1:0];
    wire [1:0] a21 = mat_reg[2][3:2];
    wire [1:0] a22 = mat_reg[2][5:4];
    wire [1:0] a23 = mat_reg[2][7:6];

    wire [1:0] a30 = mat_reg[3][1:0];
    wire [1:0] a31 = mat_reg[3][3:2];
    wire [1:0] a32 = mat_reg[3][5:4];
    wire [1:0] a33 = mat_reg[3][7:6];

    // =========================================================================
    // Unpack B
    // =========================================================================

    wire [1:0] b00 = mat_reg[4][1:0];
    wire [1:0] b01 = mat_reg[4][3:2];
    wire [1:0] b02 = mat_reg[4][5:4];
    wire [1:0] b03 = mat_reg[4][7:6];

    wire [1:0] b10 = mat_reg[5][1:0];
    wire [1:0] b11 = mat_reg[5][3:2];
    wire [1:0] b12 = mat_reg[5][5:4];
    wire [1:0] b13 = mat_reg[5][7:6];

    wire [1:0] b20 = mat_reg[6][1:0];
    wire [1:0] b21 = mat_reg[6][3:2];
    wire [1:0] b22 = mat_reg[6][5:4];
    wire [1:0] b23 = mat_reg[6][7:6];

    wire [1:0] b30 = mat_reg[7][1:0];
    wire [1:0] b31 = mat_reg[7][3:2];
    wire [1:0] b32 = mat_reg[7][5:4];
    wire [1:0] b33 = mat_reg[7][7:6];

    // =========================================================================
    // Core
    // =========================================================================

    wire [5:0] acc00, acc01, acc02, acc03;
    wire [5:0] acc10, acc11, acc12, acc13;
    wire [5:0] acc20, acc21, acc22, acc23;
    wire [5:0] acc30, acc31, acc32, acc33;

    wire done_pulse;
    wire busy_core;

    systolic_4x4 core (
        .clk    (clk),
        .rst    (rst),
        .clk_en (1'b1),
        .start  (start_gated),

        .a00(a00), .a01(a01), .a02(a02), .a03(a03),
        .a10(a10), .a11(a11), .a12(a12), .a13(a13),
        .a20(a20), .a21(a21), .a22(a22), .a23(a23),
        .a30(a30), .a31(a31), .a32(a32), .a33(a33),

        .b00(b00), .b01(b01), .b02(b02), .b03(b03),
        .b10(b10), .b11(b11), .b12(b12), .b13(b13),
        .b20(b20), .b21(b21), .b22(b22), .b23(b23),
        .b30(b30), .b31(b31), .b32(b32), .b33(b33),

        .acc00(acc00), .acc01(acc01), .acc02(acc02), .acc03(acc03),
        .acc10(acc10), .acc11(acc11), .acc12(acc12), .acc13(acc13),
        .acc20(acc20), .acc21(acc21), .acc22(acc22), .acc23(acc23),
        .acc30(acc30), .acc31(acc31), .acc32(acc32), .acc33(acc33),

        .done   (done_pulse),
        .busy   (busy_core)
    );

    // =========================================================================
    // Output serializer (direct accumulator mux — no result_mem to save area)
    // =========================================================================

    reg [3:0] out_idx;
    reg       out_valid;
    reg       out_busy;

    always @(posedge clk) begin
        if (rst) begin
            out_valid <= 1'b0;
            out_busy  <= 1'b0;
            out_idx   <= 4'd0;
        end else begin
            if (done_pulse) begin
                out_valid <= 1'b1;
                out_busy  <= 1'b1;
                out_idx   <= 4'd0;
            end else if (out_valid) begin
                if (out_idx == 4'd15) begin
                    out_valid <= 1'b0;
                    out_busy  <= 1'b0;
                end else begin
                    out_idx <= out_idx + 4'd1;
                end
            end else if (busy_core) begin
                out_busy <= 1'b1;
            end else begin
                out_busy <= 1'b0;
            end
        end
    end

    wire [5:0] result_data;
    assign result_data =
        (out_idx == 4'd0)  ? acc00 :
        (out_idx == 4'd1)  ? acc01 :
        (out_idx == 4'd2)  ? acc02 :
        (out_idx == 4'd3)  ? acc03 :
        (out_idx == 4'd4)  ? acc10 :
        (out_idx == 4'd5)  ? acc11 :
        (out_idx == 4'd6)  ? acc12 :
        (out_idx == 4'd7)  ? acc13 :
        (out_idx == 4'd8)  ? acc20 :
        (out_idx == 4'd9)  ? acc21 :
        (out_idx == 4'd10) ? acc22 :
        (out_idx == 4'd11) ? acc23 :
        (out_idx == 4'd12) ? acc30 :
        (out_idx == 4'd13) ? acc31 :
        (out_idx == 4'd14) ? acc32 :
        (out_idx == 4'd15) ? acc33 : 6'd0;

    assign start_gated = start && !out_busy;

    assign uo_out[5:0] = result_data;
    assign uo_out[6]   = out_valid;
    assign uo_out[7]   = out_busy || busy_core;

    assign uio_out[3:0] = debug ? out_idx[3:0] : 4'b0000;
    assign uio_out[7:4] = 4'b0000;

    assign uio_oe = debug ? 8'h0F : 8'h00;

    wire _unused = &{ena, uio_in[7:3], 1'b0};

endmodule

`default_nettype wire