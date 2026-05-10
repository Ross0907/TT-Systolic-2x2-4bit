// =============================================================================
// FILE        : tb_vivado.v
// DESCRIPTION : Self-checking Verilog testbench for tt_um_ross_systolic
//               2×2 Systolic Array Matrix Multiplier (4-bit elements)
//
// HOW TO USE IN VIVADO
// ────────────────────
//  1. File → Add Sources → Add or create simulation sources
//     Add ALL of:
//       src/mult_4x4.v
//       src/systolic_pe.v
//       src/systolic_2x2.v
//       src/project.v
//       test/tb_vivado.v   (set as top)
//  2. In the Flow Navigator, click "Run Simulation" → "Run Behavioral Simulation"
//  3. In Tcl console:   run 5000ns
//  4. Check transcript for PASS/FAIL messages.
//
// =============================================================================
`default_nettype none

module tb_vivado;

    // ─────────────────────────────────────────────────────────────
    // DUT signals
    // ─────────────────────────────────────────────────────────────
    reg        clk    = 0;
    reg        rst_n  = 0;
    reg        ena    = 1;
    reg  [7:0] ui_in  = 0;
    reg  [7:0] uio_in = 0;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    // ─────────────────────────────────────────────────────────────
    // Clock: 10 ns period (100 MHz)
    // ─────────────────────────────────────────────────────────────
    always #5 clk = ~clk;

    // ─────────────────────────────────────────────────────────────
    // DUT instantiation
    // ─────────────────────────────────────────────────────────────
    tt_um_ross_systolic dut (
        .ui_in  (ui_in),
        .uo_out (uo_out),
        .uio_in (uio_in),
        .uio_out(uio_out),
        .uio_oe (uio_oe),
        .ena    (ena),
        .clk    (clk),
        .rst_n  (rst_n)
    );

    // ─────────────────────────────────────────────────────────────
    // Control decode
    // ─────────────────────────────────────────────────────────────
    wire       busy  = uo_out[7];  // not used directly
    wire       valid = 1'b1;      // full byte always valid when read
    wire [7:0] rdata = uo_out[7:0];

    // ─────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────
    integer pass_count = 0;
    integer fail_count = 0;

    // Pack two 4-bit elements into one byte: {e1[3:0], e0[3:0]}
    function [7:0] pack2_4bit;
        input [3:0] e0, e1;
        begin
            pack2_4bit = {e1, e0};
        end
    endfunction

    // Reference 2×2 matrix multiply element (9-bit internal, compare lower 8 bits)
    function [8:0] ref_elem;
        input [3:0] a0, a1;
        input [3:0] b0, b1;
        begin
            ref_elem = ({4'b0, a0} * {4'b0, b0}) +
                       ({4'b0, a1} * {4'b0, b1});
        end
    endfunction

    // Apply reset
    task do_reset;
        begin
            @(negedge clk);
            rst_n = 0;
            ui_in  = 8'd0;
            uio_in = 8'd0;
            repeat(4) @(posedge clk);
            @(negedge clk);
            rst_n = 1;
        end
    endtask

    // Load one byte into the matrix register
    task load_byte;
        input [7:0] data;
        begin
            @(negedge clk);
            ui_in  = data;
            uio_in = 8'h01;  // wren=1
            @(posedge clk);
            @(negedge clk);
            uio_in = 8'h00;
        end
    endtask

    // Start computation
    task do_start;
        begin
            @(negedge clk);
            uio_in = 8'h02;  // start=1
            @(posedge clk);
            @(negedge clk);
            uio_in = 8'h00;
        end
    endtask

    // Read 4 serial results
    reg [7:0] results [0:3];
    task read_results;
        integer j;
        begin
            for (j = 0; j < 4; j = j + 1) begin
                results[j] = uo_out;
                @(posedge clk);
            end
        end
    endtask

    // Run one complete 2×2 test case
    task run_test;
        input [3:0] a00, a01;
        input [3:0] a10, a11;
        input [3:0] b00, b01;
        input [3:0] b10, b11;
        input [63:0] label;
        reg [8:0] ec00, ec01;
        reg [8:0] ec10, ec11;
        reg ok;
        begin
            // Expected results (9-bit)
            ec00 = ref_elem(a00, a01, b00, b10);
            ec01 = ref_elem(a00, a01, b01, b11);
            ec10 = ref_elem(a10, a11, b00, b10);
            ec11 = ref_elem(a10, a11, b01, b11);

            do_reset;

            // Load 4 bytes: A (2 bytes), then B (2 bytes)
            // Perfect 4-bit packing: byte={e1,e0}
            load_byte(pack2_4bit(a00, a01));
            load_byte(pack2_4bit(a10, a11));
            load_byte(pack2_4bit(b00, b01));
            load_byte(pack2_4bit(b10, b11));

            // Start computation
            do_start;

            // Wait for systolic array to finish (~6 cycles) then read 4 outputs
            repeat(6) @(posedge clk);
            read_results;

            // Compare lower 8 bits (uo_out is 8-bit, accumulator is 9-bit)
            ok = (results[0] === ec00[7:0] && results[1] === ec01[7:0] &&
                  results[2] === ec10[7:0] && results[3] === ec11[7:0]);

            if (!ok) begin
                $display("FAIL [%s]", label);
                $display("  got      C00=%0d C01=%0d", results[0], results[1]);
                $display("           C10=%0d C11=%0d", results[2], results[3]);
                $display("  expected C00=%0d C01=%0d", ec00[7:0], ec01[7:0]);
                $display("           C10=%0d C11=%0d", ec10[7:0], ec11[7:0]);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS [%s]", label);
                pass_count = pass_count + 1;
            end
        end
    endtask

    // ─────────────────────────────────────────────────────────────
    // Test sequence
    // ─────────────────────────────────────────────────────────────
    initial begin
        $timeformat(-9, 1, " ns", 8);
        $display("=== tt_um_ross_systolic 2x2 (4-bit) testbench start ===");

        // Verify debug IO configuration after reset
        do_reset;
        if (uio_oe !== 8'hFC) begin
            $display("FAIL [io_oe] expected 0xFC, got 0x%02X", uio_oe);
            fail_count = fail_count + 1;
        end else begin
            $display("PASS [io_oe] uio_oe = 0xFC (debug outputs enabled)");
            pass_count = pass_count + 1;
        end
        if (uio_out !== 8'h00) begin
            $display("FAIL [io_out] expected 0x00 after reset, got 0x%02X", uio_out);
            fail_count = fail_count + 1;
        end else begin
            $display("PASS [io_out] uio_out = 0x00 after reset");
            pass_count = pass_count + 1;
        end

        // Test 1: Identity × Identity = Identity
        run_test(4'd1, 4'd0,
                 4'd0, 4'd1,
                 4'd1, 4'd0,
                 4'd0, 4'd1,
                 "I*I     ");

        // Test 2: All-ones × All-ones (result = 2, fits in 8 bits)
        run_test(4'd1, 4'd1,
                 4'd1, 4'd1,
                 4'd1, 4'd1,
                 4'd1, 4'd1,
                 "1s*1s   ");

        // Test 3: Near-max inputs that fit in 8 bits (11×11 → 242)
        run_test(4'd11, 4'd11,
                 4'd11, 4'd11,
                 4'd11, 4'd11,
                 4'd11, 4'd11,
                 "near-max");

        // Test 4: Asymmetric
        run_test(4'd5, 4'd3,
                 4'd2, 4'd7,
                 4'd4, 4'd6,
                 4'd1, 4'd8,
                 "asym    ");

        // Test 5: Zero matrix
        run_test(4'd0, 4'd0,
                 4'd0, 4'd0,
                 4'd9, 4'd12,
                 4'd3, 4'd7,
                 "0*B     ");

        // Test 6: Diagonal scaling
        run_test(4'd4, 4'd0,
                 4'd0, 4'd4,
                 4'd2, 4'd5,
                 4'd6, 4'd3,
                 "diag    ");

        // Test 7: Sparse
        run_test(4'd8, 4'd0,
                 4'd0, 4'd0,
                 4'd5, 4'd3,
                 4'd0, 4'd0,
                 "sparse  ");

        // Summary
        $display("===========================================");
        $display("Results: %0d PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("*** SOME TESTS FAILED ***");
        $display("===========================================");

        $finish;
    end

    // Watchdog
    initial begin
        #5000;
        $display("ERROR: Watchdog timeout");
        $finish;
    end

endmodule

`default_nettype wire
