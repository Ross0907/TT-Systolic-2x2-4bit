/*
 * Copyright (c) 202r Roshan Tripathy
 * SPDX-License-Identifier: Apache-2.0
 */

// =============================================================================
// FILE        : tt_um_ross_systolic.v
// DESCRIPTION : Tiny Tapeout Top Module – 4×4 Systolic Array Matrix Multiplier
//
//   Computes C = A × B where A and B are 4×4 matrices with 2-bit elements.
//   Uses explicit Wallace tree multipliers in each PE for speed.
//
// ─────────────────────────────────────────────────────────────────────────────
// PIN MAP
// ─────────────────────────────────────────────────────────────────────────────
//   ui_in[7:0]  — Data byte input
//
//   uio_in[0]   — wren   (write enable: load ui_in into next matrix byte)
//   uio_in[1]   — start  (pulse high to begin computation)
//   uio_in[2]   — debug  (when high, uio_out[3:0] shows result index)
//   uio_in[7:3] — unused (tied low recommended)
//
//   uo_out[5:0] — result_data  (6-bit matrix element result)
//   uo_out[6]   — valid        (HIGH when result_data is valid)
//   uo_out[7]   — busy         (HIGH during compute + output phases)
//
//   uio_out[3:0]— debug_idx    (current output index when debug=1)
//   uio_out[7:4]— unused       (tied low)
//   uio_oe[7:0] — 8'h0F when debug=1, else 8'h00
//
// ─────────────────────────────────────────────────────────────────────────────
// OPERATION
// ─────────────────────────────────────────────────────────────────────────────
//   1. LOAD PHASE (in IDLE):
//      - Set matrix data byte on ui_in[7:0].
//      - Pulse uio_in[0] (wren) HIGH for one clock cycle.
//      - The byte is stored in an internal 8-byte register at the current
//        address (auto-increments 0→7, wraps to 0 after 8).
//      - Repeat 8 times to load all of A (bytes 0-3) and B (bytes 4-7).
//
//        Byte layout (each byte holds four 2-bit elements):
//          Byte 0: {a03, a02, a01, a00}
//          Byte 1: {a13, a12, a11, a10}
//          Byte 2: {a23, a22, a21, a20}
//          Byte 3: {a33, a32, a31, a30}
//          Byte 4: {b03, b02, b01, b00}
//          Byte 5: {b13, b12, b11, b10}
//          Byte 6: {b23, b22, b21, b20}
//          Byte 7: {b33, b32, b31, b30}
//
//   2. COMPUTE PHASE:
//      - Pulse uio_in[1] (start) HIGH for one clock cycle.
//      - busy (uo_out[7]) goes HIGH.
//      - The 4×4 systolic array runs for 10 clock cycles internally.
//
//   3. OUTPUT PHASE:
//      - After computation, valid (uo_out[6]) goes HIGH.
//      - uo_out[5:0] presents C[0][0], then C[0][1], ... C[3][3]
//        automatically on each subsequent clock cycle.
//      - 16 results are streamed over 16 clock cycles.
//      - busy goes LOW after the last result.
//
//   4. DEBUG MODE:
//      - Hold uio_in[2] HIGH.
//      - uio_out[3:0] shows the current result index (0-15).
//      - uio_oe lower nibble becomes HIGH (output direction).
//
// SPDX-License-Identifier: Apache-2.0
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

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

    // -------------------------------------------------------------------------
    // Internal reset (active-high)
    // -------------------------------------------------------------------------
    wire rst = ~rst_n;

    // -------------------------------------------------------------------------
    // Control inputs
    // -------------------------------------------------------------------------
    wire       wren   = uio_in[0];
    wire       start  = uio_in[1];
    wire       debug  = uio_in[2];

    // -------------------------------------------------------------------------
    // Matrix data registers (8 bytes)
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // Unpack matrix elements from bytes
    // -------------------------------------------------------------------------
    wire [1:0] a00 = mat_reg[0][1:0];   wire [1:0] a01 = mat_reg[0][3:2];
    wire [1:0] a02 = mat_reg[0][5:4];   wire [1:0] a03 = mat_reg[0][7:6];

    wire [1:0] a10 = mat_reg[1][1:0];   wire [1:0] a11 = mat_reg[1][3:2];
    wire [1:0] a12 = mat_reg[1][5:4];   wire [1:0] a13 = mat_reg[1][7:6];

    wire [1:0] a20 = mat_reg[2][1:0];   wire [1:0] a21 = mat_reg[2][3:2];
    wire [1:0] a22 = mat_reg[2][5:4];   wire [1:0] a23 = mat_reg[2][7:6];

    wire [1:0] a30 = mat_reg[3][1:0];   wire [1:0] a31 = mat_reg[3][3:2];
    wire [1:0] a32 = mat_reg[3][5:4];   wire [1:0] a33 = mat_reg[3][7:6];

    wire [1:0] b00 = mat_reg[4][1:0];   wire [1:0] b01 = mat_reg[4][3:2];
    wire [1:0] b02 = mat_reg[4][5:4];   wire [1:0] b03 = mat_reg[4][7:6];

    wire [1:0] b10 = mat_reg[5][1:0];   wire [1:0] b11 = mat_reg[5][3:2];
    wire [1:0] b12 = mat_reg[5][5:4];   wire [1:0] b13 = mat_reg[5][7:6];

    wire [1:0] b20 = mat_reg[6][1:0];   wire [1:0] b21 = mat_reg[6][3:2];
    wire [1:0] b22 = mat_reg[6][5:4];   wire [1:0] b23 = mat_reg[6][7:6];

    wire [1:0] b30 = mat_reg[7][1:0];   wire [1:0] b31 = mat_reg[7][3:2];
    wire [1:0] b32 = mat_reg[7][5:4];   wire [1:0] b33 = mat_reg[7][7:6];

    // -------------------------------------------------------------------------
    // Systolic array core
    // -------------------------------------------------------------------------
    wire [5:0] acc00, acc01, acc02, acc03;
    wire [5:0] acc10, acc11, acc12, acc13;
    wire [5:0] acc20, acc21, acc22, acc23;
    wire [5:0] acc30, acc31, acc32, acc33;
    wire       done_pulse, busy_core;

    systolic_4x4 u_sys (
        .clk    (clk),
        .rst    (rst),
        .clk_en (1'b1),
        .start  (start),
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

    // -------------------------------------------------------------------------
    // Result latch and output serializer
    // -------------------------------------------------------------------------
    reg [5:0] result_mem [0:15];
    reg [4:0] out_idx;
    reg       out_valid;
    reg       out_busy;
    reg       capture_done;   // delayed done_pulse for reliable capture

    always @(posedge clk) begin
        if (rst) begin
            out_valid     <= 1'b0;
            out_busy      <= 1'b0;
            out_idx       <= 5'd0;
            capture_done  <= 1'b0;
        end else begin
            capture_done <= done_pulse;

            if (capture_done) begin
                // Latch all 16 results (one cycle after done_pulse so accs are stable)
                result_mem[0]  <= acc00;  result_mem[1]  <= acc01;
                result_mem[2]  <= acc02;  result_mem[3]  <= acc03;
                result_mem[4]  <= acc10;  result_mem[5]  <= acc11;
                result_mem[6]  <= acc12;  result_mem[7]  <= acc13;
                result_mem[8]  <= acc20;  result_mem[9]  <= acc21;
                result_mem[10] <= acc22;  result_mem[11] <= acc23;
                result_mem[12] <= acc30;  result_mem[13] <= acc31;
                result_mem[14] <= acc32;  result_mem[15] <= acc33;
                out_valid <= 1'b1;
                out_busy  <= 1'b1;
                out_idx   <= 5'd0;
            end else if (out_valid) begin
                if (out_idx == 5'd15) begin
                    out_valid <= 1'b0;
                    out_busy  <= 1'b0;
                end else begin
                    out_idx <= out_idx + 5'd1;
                end
            end else if (busy_core) begin
                out_busy <= 1'b1;
            end else begin
                out_busy <= 1'b0;
            end
        end
    end

    wire [5:0] result_data = out_valid ? result_mem[out_idx] : 6'd0;

    // -------------------------------------------------------------------------
    // Output assignments
    // -------------------------------------------------------------------------
    assign uo_out[5:0] = result_data;
    assign uo_out[6]   = out_valid;
    assign uo_out[7]   = out_busy || busy_core;

    // Debug output on bidir pins
    assign uio_out[3:0] = debug ? out_idx[3:0] : 4'b0000;
    assign uio_out[7:4] = 4'b0000;
    assign uio_oe       = debug ? 8'h0F : 8'h00;

    // Suppress unused-signal warnings
    wire _unused = &{ena, uio_in[7:3], 1'b0};

endmodule

`default_nettype wire
