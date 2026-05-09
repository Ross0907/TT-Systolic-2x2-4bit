// =============================================================================
// FILE        : tt_um_systolic_2x2.v
// DESCRIPTION : Tiny Tapeout wrapper for the 2×2 Systolic Array Multiplier
//
//   Computes  C = A × B  where A and B are 2×2 matrices with 2-bit elements
//   (values 0-3).  Results are 5-bit accumulators (values 0-18).
//
// ──────────────────────────────────────────────────────────────────────────────
// PIN MAP
// ──────────────────────────────────────────────────────────────────────────────
//   ui_in  [7:0]  — Matrix A  (dedicated inputs, all stable before rst_n high)
//     ui_in[1:0]  = a00   (row 0, col 0)
//     ui_in[3:2]  = a01   (row 0, col 1)
//     ui_in[5:4]  = a10   (row 1, col 0)
//     ui_in[7:6]  = a11   (row 1, col 1)
//
//   uio_in [7:0]  — Matrix B  (bidir used as pure inputs; uio_oe = 0)
//     uio_in[1:0] = b00   (row 0, col 0)
//     uio_in[3:2] = b01   (row 0, col 1)
//     uio_in[5:4] = b10   (row 1, col 0)
//     uio_in[7:6] = b11   (row 1, col 1)
//
//   uo_out [7:0]  — Serial result output
//     uo_out[4:0] = acc_out  — 5-bit result currently on display
//     uo_out[6:5] = sel[1:0] — which result: 00=C[0][0], 01=C[0][1],
//                                             10=C[1][0], 11=C[1][1]
//     uo_out[7]   = done     — HIGH for all 4 result-output cycles
//
//   clk            — System clock (the TT RP2040-generated clock)
//   rst_n          — Active-LOW reset.  Hold low, set matrices, then release.
//                    Computation starts automatically 1 cycle after rst_n=1.
//
// ──────────────────────────────────────────────────────────────────────────────
// OPERATION
// ──────────────────────────────────────────────────────────────────────────────
//   The systolic array runs free-running (clk_en = 1, start = 1).
//   One computation takes exactly 5 clock cycles.  On every 5th cycle,
//   `done` pulses and the four 5-bit results are latched.  Over the next
//   4 clock cycles, uo_out[6:5] steps through 00→01→10→11, presenting
//   each result on uo_out[4:0] in turn, and uo_out[7]=1 throughout.
//
//   To read all four results:
//     1. Hold rst_n=0, set ui_in (Matrix A) and uio_in (Matrix B).
//     2. Assert rst_n=1.
//     3. Wait until uo_out[7]=1 (first result: C[0][0] on uo_out[4:0]).
//     4. Sample uo_out[4:0] — that is C[0][0].
//     5. Next rising edge: uo_out[6:5]=01, uo_out[4:0] = C[0][1].
//     6. Next: uo_out[6:5]=10, C[1][0].
//     7. Next: uo_out[6:5]=11, C[1][1].
//
//   After step 7 the next computation result is available on the following
//   done pulse (inputs are re-sampled each run, so you can update them
//   between runs for a streaming multiplier).
//
// SPDX-License-Identifier: Apache-2.0
// =============================================================================

`default_nettype none

module tt_um_systolic_2x2 (
    input  wire [7:0] ui_in,    // Matrix A: {a11, a10, a01, a00} (2-bit each)
    output wire [7:0] uo_out,   // {done, sel[1:0], acc_out[4:0]}
    input  wire [7:0] uio_in,   // Matrix B: {b11, b10, b01, b00} (2-bit each)
    output wire [7:0] uio_out,  // unused – tied low
    output wire [7:0] uio_oe,   // all inputs (0 = input direction)
    input  wire       ena,      // always high when design is selected
    input  wire       clk,
    input  wire       rst_n
);

    // ─────────────────────────────────────────────────────────────
    // 1. Unpack matrix elements from IO pins
    // ─────────────────────────────────────────────────────────────
    wire [1:0] a00 = ui_in[1:0];
    wire [1:0] a01 = ui_in[3:2];
    wire [1:0] a10 = ui_in[5:4];
    wire [1:0] a11 = ui_in[7:6];

    wire [1:0] b00 = uio_in[1:0];
    wire [1:0] b01 = uio_in[3:2];
    wire [1:0] b10 = uio_in[5:4];
    wire [1:0] b11 = uio_in[7:6];

    // ─────────────────────────────────────────────────────────────
    // 2. Systolic array core
    //    clk_en = 1  →  free-running (no manual step button)
    //    start  = 1  →  auto-restart after each DONE (continuous)
    //    rst    = ~rst_n  (active-high internally)
    // ─────────────────────────────────────────────────────────────
    wire [4:0] acc00, acc01, acc10, acc11;
    wire       done_pulse, busy;

    systolic_2x2 u_sys (
        .clk    (clk),
        .rst    (~rst_n),
        .clk_en (1'b1),
        .start  (1'b1),
        .a00(a00), .a01(a01),
        .a10(a10), .a11(a11),
        .b00(b00), .b01(b01),
        .b10(b10), .b11(b11),
        .acc00(acc00), .acc01(acc01),
        .acc10(acc10), .acc11(acc11),
        .done(done_pulse),
        .busy(busy)
    );

    // ─────────────────────────────────────────────────────────────
    // 3. Result register + 4-cycle serial output
    //
    //    On every done_pulse: latch all four results and begin
    //    cycling sel 0→1→2→3 over the next four clock edges,
    //    holding done_reg=1 throughout.
    // ─────────────────────────────────────────────────────────────
    reg [4:0] r00, r01, r10, r11;
    reg [1:0] sel;
    reg       done_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            r00      <= 5'd0;
            r01      <= 5'd0;
            r10      <= 5'd0;
            r11      <= 5'd0;
            sel      <= 2'd0;
            done_reg <= 1'b0;
        end else if (done_pulse) begin
            // Latch the just-completed results and start display
            r00      <= acc00;
            r01      <= acc01;
            r10      <= acc10;
            r11      <= acc11;
            sel      <= 2'd0;
            done_reg <= 1'b1;
        end else if (done_reg) begin
            // Step through sel 0→1→2→3, then clear done_reg
            if (sel == 2'd3)
                done_reg <= 1'b0;
            sel <= sel + 2'd1;
        end
    end

    // ─────────────────────────────────────────────────────────────
    // 4. Output multiplexer
    // ─────────────────────────────────────────────────────────────
    reg [4:0] acc_out;
    always @(*) begin
        case (sel)
            2'd0:    acc_out = r00;
            2'd1:    acc_out = r01;
            2'd2:    acc_out = r10;
            2'd3:    acc_out = r11;
            default: acc_out = r00;
        endcase
    end

    // ─────────────────────────────────────────────────────────────
    // 5. IO assignments
    // ─────────────────────────────────────────────────────────────
    assign uo_out  = {done_reg, sel, acc_out};   // [7]=done [6:5]=sel [4:0]=value
    assign uio_out = 8'b0000_0000;
    assign uio_oe  = 8'b0000_0000;               // all bidir pins are inputs

    // Suppress unused signal warning from synthesis tools
    wire _unused_ok = &{ena, busy, 1'b0};

endmodule

`default_nettype wire
