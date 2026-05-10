/*
 * Copyright (c) 2026 Roshan Tripathy
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// =============================================================================
// Tiny Tapeout Top — 2×2 Systolic Array with signed 4-bit elements
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

    wire manual_clk = uio_in[5];
    wire step_mode  = uio_in[6];

    // Manual step logic: rising-edge detect on manual_clk when step_mode=1
    reg manual_clk_prev;
    always @(posedge clk) begin
        if (rst)
            manual_clk_prev <= 1'b0;
        else
            manual_clk_prev <= manual_clk;
    end

    wire step_pulse = step_mode & manual_clk & ~manual_clk_prev;
    wire step_en    = step_mode ? step_pulse : 1'b1;

    wire start_gated;

    // =========================================================================
    // Matrix storage (4 bytes: 2 for A, 2 for B)
    // =========================================================================

    reg [7:0] mat_reg [0:3];
    reg [1:0] byte_addr;

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            byte_addr <= 2'd0;

            for (i = 0; i < 4; i = i + 1)
                mat_reg[i] <= 8'd0;

        end else if (step_en) begin
            if (wren) begin
                mat_reg[byte_addr] <= ui_in;
                byte_addr <= byte_addr + 2'd1;
            end else if (start) begin
                byte_addr <= 2'd0;
            end
        end
    end

    // =========================================================================
    // Unpack A (4-bit elements from 2 bytes, perfect packing)
    // Byte 0: {a01[3:0], a00[3:0]}
    // Byte 1: {a11[3:0], a10[3:0]}
    // =========================================================================

    wire [3:0] a00 = mat_reg[0][3:0];
    wire [3:0] a01 = mat_reg[0][7:4];
    wire [3:0] a10 = mat_reg[1][3:0];
    wire [3:0] a11 = mat_reg[1][7:4];

    // =========================================================================
    // Unpack B (4-bit elements from 2 bytes, perfect packing)
    // Byte 2: {b01[3:0], b00[3:0]}
    // Byte 3: {b11[3:0], b10[3:0]}
    // =========================================================================

    wire [3:0] b00 = mat_reg[2][3:0];
    wire [3:0] b01 = mat_reg[2][7:4];
    wire [3:0] b10 = mat_reg[3][3:0];
    wire [3:0] b11 = mat_reg[3][7:4];

    // =========================================================================
    // Core
    // =========================================================================

    wire signed [8:0] acc00, acc01;
    wire signed [8:0] acc10, acc11;

    wire done_pulse;
    wire busy_core;

    systolic_2x2 core (
        .clk    (clk),
        .rst    (rst),
        .clk_en (step_en),
        .start  (start_gated),

        .a00(a00), .a01(a01),
        .a10(a10), .a11(a11),

        .b00(b00), .b01(b01),
        .b10(b10), .b11(b11),

        .acc00(acc00), .acc01(acc01),
        .acc10(acc10), .acc11(acc11),

        .done   (done_pulse),
        .busy   (busy_core)
    );

    // =========================================================================
    // Output serializer (4 results, lower 8 bits of 9-bit accumulators)
    // Note: max theoretical result = 98 (0x62) for all +7 inputs.
    //       Output is lower 8 bits (two's complement for negative results).
    //       MSB (bit 8) is available via debug if needed.
    // =========================================================================

    reg [3:0] out_idx;
    reg       out_valid;
    reg       out_busy;

    always @(posedge clk) begin
        if (rst) begin
            out_valid <= 1'b0;
            out_busy  <= 1'b0;
            out_idx   <= 4'd0;
        end else if (step_en) begin
            if (done_pulse) begin
                out_valid <= 1'b1;
                out_busy  <= 1'b1;
                out_idx   <= 4'd0;
            end else if (out_valid) begin
                if (out_idx == 4'd3) begin
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
        (out_idx == 4'd0) ? acc00[7:0] :
        (out_idx == 4'd1) ? acc01[7:0] :
        (out_idx == 4'd2) ? acc10[7:0] :
        (out_idx == 4'd3) ? acc11[7:0] : 8'd0;

    assign start_gated = start && !out_busy && ena;

    assign uo_out = result_data;

    // Debug/status outputs on uio_out[7,4:2] (bits 6,5 are manual-step INPUTS)
    //   [2] = busy_core      – systolic array is computing
    //   [3] = out_valid        – result data on uo_out is valid
    //   [4] = overflow_8bit    – acc[8] ^ acc[7] for CURRENT result (1 = truncated)
    //   [7] = acc_sign         – acc[8] (sign bit) for CURRENT result
    // Bits [6:5] are INPUTS for manual step mode:
    //   [5] = manual_clk       – rising edge advances one step when step_mode=1
    //   [6] = step_mode        – 1 = manual step, 0 = free-running
    // Together {acc_sign, uo_out[7:0]} gives the full 9-bit signed value.
    wire acc_sign = out_valid ?
        ((out_idx == 4'd0) ? acc00[8] :
         (out_idx == 4'd1) ? acc01[8] :
         (out_idx == 4'd2) ? acc10[8] :
         (out_idx == 4'd3) ? acc11[8] : 1'b0) : 1'b0;

    wire overflow_8bit = out_valid ?
        ((out_idx == 4'd0) ? (acc00[8] ^ acc00[7]) :
         (out_idx == 4'd1) ? (acc01[8] ^ acc01[7]) :
         (out_idx == 4'd2) ? (acc10[8] ^ acc10[7]) :
         (out_idx == 4'd3) ? (acc11[8] ^ acc11[7]) : 1'b0) : 1'b0;

    assign uio_out = {acc_sign, 2'b00, overflow_8bit, out_valid, busy_core, 2'b00};
    assign uio_oe  = 8'h9C;  // bits 7,4,3,2 = output; bits 6,5,1,0 = input

    wire _unused = &{uio_in[7], uio_in[4:2], 1'b0};

endmodule

`default_nettype wire