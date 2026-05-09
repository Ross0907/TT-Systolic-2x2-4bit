/* verilator lint_off TIMESCALEMOD */
/*
 * Copyright (c) 2026 Roshan Tripathy
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`timescale 1ns / 1ps

// =============================================================================
// Tiny Tapeout Top — 3×3 Systolic Array with 3-bit elements
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

    wire start_gated;

    // =========================================================================
    // Matrix storage (10 bytes: 5 for A, 5 for B)
    // =========================================================================

    reg [7:0] mat_reg [0:9];
    reg [3:0] byte_addr;

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            byte_addr <= 4'd0;

            for (i = 0; i < 10; i = i + 1)
                mat_reg[i] <= 8'd0;

        end else if (wren) begin
            mat_reg[byte_addr] <= ui_in;
            byte_addr <= byte_addr + 4'd1;
        end
    end

    // =========================================================================
    // Unpack A (3-bit elements from 5 bytes)
    // Byte 0: {a01[2:0], a00[2:0]}
    // Byte 1: {a10[2:0], a02[2:0]}
    // Byte 2: {a12[2:0], a11[2:0]}
    // Byte 3: {a21[2:0], a20[2:0]}
    // Byte 4: {5'b0, a22[2:0]}
    // =========================================================================

    wire [2:0] a00 = mat_reg[0][2:0];
    wire [2:0] a01 = mat_reg[0][5:3];
    wire [2:0] a02 = mat_reg[1][2:0];
    wire [2:0] a10 = mat_reg[1][5:3];
    wire [2:0] a11 = mat_reg[2][2:0];
    wire [2:0] a12 = mat_reg[2][5:3];
    wire [2:0] a20 = mat_reg[3][2:0];
    wire [2:0] a21 = mat_reg[3][5:3];
    wire [2:0] a22 = mat_reg[4][2:0];

    // =========================================================================
    // Unpack B (3-bit elements from 5 bytes)
    // Byte 5: {b01[2:0], b00[2:0]}
    // Byte 6: {b10[2:0], b02[2:0]}
    // Byte 7: {b12[2:0], b11[2:0]}
    // Byte 8: {b21[2:0], b20[2:0]}
    // Byte 9: {5'b0, b22[2:0]}
    // =========================================================================

    wire [2:0] b00 = mat_reg[5][2:0];
    wire [2:0] b01 = mat_reg[5][5:3];
    wire [2:0] b02 = mat_reg[6][2:0];
    wire [2:0] b10 = mat_reg[6][5:3];
    wire [2:0] b11 = mat_reg[7][2:0];
    wire [2:0] b12 = mat_reg[7][5:3];
    wire [2:0] b20 = mat_reg[8][2:0];
    wire [2:0] b21 = mat_reg[8][5:3];
    wire [2:0] b22 = mat_reg[9][2:0];

    // =========================================================================
    // Core
    // =========================================================================

    wire [7:0] acc00, acc01, acc02;
    wire [7:0] acc10, acc11, acc12;
    wire [7:0] acc20, acc21, acc22;

    wire done_pulse;
    wire busy_core;

    systolic_3x3 core (
        .clk    (clk),
        .rst    (rst),
        .clk_en (1'b1),
        .start  (start_gated),

        .a00(a00), .a01(a01), .a02(a02),
        .a10(a10), .a11(a11), .a12(a12),
        .a20(a20), .a21(a21), .a22(a22),

        .b00(b00), .b01(b01), .b02(b02),
        .b10(b10), .b11(b11), .b12(b12),
        .b20(b20), .b21(b21), .b22(b22),

        .acc00(acc00), .acc01(acc01), .acc02(acc02),
        .acc10(acc10), .acc11(acc11), .acc12(acc12),
        .acc20(acc20), .acc21(acc21), .acc22(acc22),

        .done   (done_pulse),
        .busy   (busy_core)
    );

    // =========================================================================
    // Output serializer (9 results, 8-bit each)
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
                if (out_idx == 4'd8) begin
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

    wire [7:0] result_data;
    assign result_data =
        (out_idx == 4'd0) ? acc00 :
        (out_idx == 4'd1) ? acc01 :
        (out_idx == 4'd2) ? acc02 :
        (out_idx == 4'd3) ? acc10 :
        (out_idx == 4'd4) ? acc11 :
        (out_idx == 4'd5) ? acc12 :
        (out_idx == 4'd6) ? acc20 :
        (out_idx == 4'd7) ? acc21 :
        (out_idx == 4'd8) ? acc22 : 8'd0;

    assign start_gated = start && !out_busy;

    assign uo_out = result_data;

    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

    wire _unused = &{ena, uio_in[7:3], 1'b0};

endmodule

`default_nettype wire