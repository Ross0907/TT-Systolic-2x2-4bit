// =============================================================================
// FILE        : tb_vivado.v
// DESCRIPTION : Self-checking Verilog testbench for tt_um_ross_systolic
//               4×4 Systolic Array Matrix Multiplier – Vivado compatible
//
// HOW TO USE IN VIVADO
// ────────────────────
//  1. File → Add Sources → Add or create simulation sources
//     Add ALL of:
//       src/wallace_mult_2x2.v
//       src/systolic_pe.v
//       src/systolic_4x4.v
//       src/tt_um_ross_systolic.v
//       test/tb_vivado.v   (set as top)
//  2. In the Flow Navigator, click "Run Simulation" → "Run Behavioral Simulation"
//  3. In Tcl console:   run 5000ns
//  4. Check transcript for PASS/FAIL messages.
//     No assertion messages = all tests passed.
//
// =============================================================================
`default_nettype none
`timescale 1ns/1ps

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
    wire       wren  = uio_in[0];
    wire       start = uio_in[1];
    wire       busy  = uo_out[7];
    wire       valid = uo_out[6];
    wire [5:0] rdata = uo_out[5:0];

    // ─────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────
    integer pass_count = 0;
    integer fail_count = 0;

    // Pack four 2-bit elements into one byte: {e3, e2, e1, e0}
    function [7:0] pack4;
        input [1:0] e0, e1, e2, e3;
        begin
            pack4 = {e3, e2, e1, e0};
        end
    endfunction

    // Reference 4×4 matrix multiply element
    function [5:0] ref_elem;
        input [1:0] a0, a1, a2, a3;
        input [1:0] b0, b1, b2, b3;
        begin
            ref_elem = ({4'b0, a0} * {4'b0, b0}) +
                       ({4'b0, a1} * {4'b0, b1}) +
                       ({4'b0, a2} * {4'b0, b2}) +
                       ({4'b0, a3} * {4'b0, b3});
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

    // Wait for valid result output
    task wait_valid;
        output reg timed_out;
        integer i;
        begin
            timed_out = 1;
            for (i = 0; i < 50; i = i + 1) begin
                @(posedge clk);
                if (valid) begin
                    timed_out = 0;
                    i = 50; // break
                end
            end
        end
    endtask

    // Read 16 serial results after valid goes high
    reg [5:0] results [0:15];
    task read_results;
        integer j;
        begin
            for (j = 0; j < 16; j = j + 1) begin
                if (!valid) begin
                    $display("ERROR: valid de-asserted before all 16 results read (j=%0d)", j);
                    fail_count = fail_count + 1;
                end
                results[j] = rdata;
                @(posedge clk);
            end
        end
    endtask

    // Run one complete 4×4 test case
    task run_test;
        input [1:0] a00, a01, a02, a03;
        input [1:0] a10, a11, a12, a13;
        input [1:0] a20, a21, a22, a23;
        input [1:0] a30, a31, a32, a33;
        input [1:0] b00, b01, b02, b03;
        input [1:0] b10, b11, b12, b13;
        input [1:0] b20, b21, b22, b23;
        input [1:0] b30, b31, b32, b33;
        input [63:0] label;
        reg [5:0] ec00, ec01, ec02, ec03;
        reg [5:0] ec10, ec11, ec12, ec13;
        reg [5:0] ec20, ec21, ec22, ec23;
        reg [5:0] ec30, ec31, ec32, ec33;
        reg timed_out;
        reg ok;
        begin
            // Expected results
            ec00 = ref_elem(a00, a01, a02, a03, b00, b10, b20, b30);
            ec01 = ref_elem(a00, a01, a02, a03, b01, b11, b21, b31);
            ec02 = ref_elem(a00, a01, a02, a03, b02, b12, b22, b32);
            ec03 = ref_elem(a00, a01, a02, a03, b03, b13, b23, b33);
            ec10 = ref_elem(a10, a11, a12, a13, b00, b10, b20, b30);
            ec11 = ref_elem(a10, a11, a12, a13, b01, b11, b21, b31);
            ec12 = ref_elem(a10, a11, a12, a13, b02, b12, b22, b32);
            ec13 = ref_elem(a10, a11, a12, a13, b03, b13, b23, b33);
            ec20 = ref_elem(a20, a21, a22, a23, b00, b10, b20, b30);
            ec21 = ref_elem(a20, a21, a22, a23, b01, b11, b21, b31);
            ec22 = ref_elem(a20, a21, a22, a23, b02, b12, b22, b32);
            ec23 = ref_elem(a20, a21, a22, a23, b03, b13, b23, b33);
            ec30 = ref_elem(a30, a31, a32, a33, b00, b10, b20, b30);
            ec31 = ref_elem(a30, a31, a32, a33, b01, b11, b21, b31);
            ec32 = ref_elem(a30, a31, a32, a33, b02, b12, b22, b32);
            ec33 = ref_elem(a30, a31, a32, a33, b03, b13, b23, b33);

            do_reset;

            // Load 8 bytes: A rows 0-3, then B rows 0-3
            load_byte(pack4(a00, a01, a02, a03));
            load_byte(pack4(a10, a11, a12, a13));
            load_byte(pack4(a20, a21, a22, a23));
            load_byte(pack4(a30, a31, a32, a33));
            load_byte(pack4(b00, b01, b02, b03));
            load_byte(pack4(b10, b11, b12, b13));
            load_byte(pack4(b20, b21, b22, b23));
            load_byte(pack4(b30, b31, b32, b33));

            // Start computation
            do_start;

            // Wait for output
            wait_valid(timed_out);
            if (timed_out) begin
                $display("FAIL [%s]: TIMEOUT waiting for valid", label);
                fail_count = fail_count + 1;
            end else begin
                read_results;

                ok = (results[0]  === ec00 && results[1]  === ec01 &&
                      results[2]  === ec02 && results[3]  === ec03 &&
                      results[4]  === ec10 && results[5]  === ec11 &&
                      results[6]  === ec12 && results[7]  === ec13 &&
                      results[8]  === ec20 && results[9]  === ec21 &&
                      results[10] === ec22 && results[11] === ec23 &&
                      results[12] === ec30 && results[13] === ec31 &&
                      results[14] === ec32 && results[15] === ec33);

                if (!ok) begin
                    $display("FAIL [%s]", label);
                    $display("  got      C00=%0d C01=%0d C02=%0d C03=%0d", results[0],  results[1],  results[2],  results[3]);
                    $display("           C10=%0d C11=%0d C12=%0d C13=%0d", results[4],  results[5],  results[6],  results[7]);
                    $display("           C20=%0d C21=%0d C22=%0d C23=%0d", results[8],  results[9],  results[10], results[11]);
                    $display("           C30=%0d C31=%0d C32=%0d C33=%0d", results[12], results[13], results[14], results[15]);
                    $display("  expected C00=%0d C01=%0d C02=%0d C03=%0d", ec00, ec01, ec02, ec03);
                    $display("           C10=%0d C11=%0d C12=%0d C13=%0d", ec10, ec11, ec12, ec13);
                    $display("           C20=%0d C21=%0d C22=%0d C23=%0d", ec20, ec21, ec22, ec23);
                    $display("           C30=%0d C31=%0d C32=%0d C33=%0d", ec30, ec31, ec32, ec33);
                    fail_count = fail_count + 1;
                end else begin
                    $display("PASS [%s]", label);
                    pass_count = pass_count + 1;
                end
            end
        end
    endtask

    // ─────────────────────────────────────────────────────────────
    // Test sequence
    // ─────────────────────────────────────────────────────────────
    initial begin
        $timeformat(-9, 1, " ns", 8);
        $display("=== tt_um_ross_systolic 4x4 testbench start ===");

        // Test 1: Identity × Identity = Identity
        run_test(2'd1, 2'd0, 2'd0, 2'd0,
                 2'd0, 2'd1, 2'd0, 2'd0,
                 2'd0, 2'd0, 2'd1, 2'd0,
                 2'd0, 2'd0, 2'd0, 2'd1,
                 2'd1, 2'd0, 2'd0, 2'd0,
                 2'd0, 2'd1, 2'd0, 2'd0,
                 2'd0, 2'd0, 2'd1, 2'd0,
                 2'd0, 2'd0, 2'd0, 2'd1,
                 "I*I     ");

        // Test 2: All-ones × All-ones
        run_test(2'd1, 2'd1, 2'd1, 2'd1,
                 2'd1, 2'd1, 2'd1, 2'd1,
                 2'd1, 2'd1, 2'd1, 2'd1,
                 2'd1, 2'd1, 2'd1, 2'd1,
                 2'd1, 2'd1, 2'd1, 2'd1,
                 2'd1, 2'd1, 2'd1, 2'd1,
                 2'd1, 2'd1, 2'd1, 2'd1,
                 2'd1, 2'd1, 2'd1, 2'd1,
                 "1s*1s   ");

        // Test 3: Maximum inputs
        run_test(2'd3, 2'd3, 2'd3, 2'd3,
                 2'd3, 2'd3, 2'd3, 2'd3,
                 2'd3, 2'd3, 2'd3, 2'd3,
                 2'd3, 2'd3, 2'd3, 2'd3,
                 2'd3, 2'd3, 2'd3, 2'd3,
                 2'd3, 2'd3, 2'd3, 2'd3,
                 2'd3, 2'd3, 2'd3, 2'd3,
                 2'd3, 2'd3, 2'd3, 2'd3,
                 "max     ");

        // Test 4: Asymmetric
        run_test(2'd2, 2'd1, 2'd0, 2'd3,
                 2'd0, 2'd2, 2'd1, 2'd0,
                 2'd3, 2'd0, 2'd2, 2'd1,
                 2'd1, 2'd3, 2'd0, 2'd2,
                 2'd1, 2'd2, 2'd3, 2'd0,
                 2'd0, 2'd1, 2'd2, 2'd3,
                 2'd3, 2'd0, 2'd1, 2'd2,
                 2'd2, 2'd3, 2'd0, 2'd1,
                 "asym    ");

        // Test 5: Zero matrix
        run_test(2'd0, 2'd0, 2'd0, 2'd0,
                 2'd0, 2'd0, 2'd0, 2'd0,
                 2'd0, 2'd0, 2'd0, 2'd0,
                 2'd0, 2'd0, 2'd0, 2'd0,
                 2'd3, 2'd2, 2'd1, 2'd3,
                 2'd1, 2'd2, 2'd3, 2'd0,
                 2'd0, 2'd1, 2'd2, 2'd3,
                 2'd3, 2'd0, 2'd1, 2'd2,
                 "0*B     ");

        // Test 6: Diagonal scaling
        run_test(2'd2, 2'd0, 2'd0, 2'd0,
                 2'd0, 2'd2, 2'd0, 2'd0,
                 2'd0, 2'd0, 2'd2, 2'd0,
                 2'd0, 2'd0, 2'd0, 2'd2,
                 2'd1, 2'd3, 2'd2, 2'd1,
                 2'd3, 2'd1, 2'd3, 2'd2,
                 2'd2, 2'd3, 2'd1, 2'd3,
                 2'd1, 2'd2, 2'd3, 2'd1,
                 "diag    ");

        // Test 7: Sparse
        run_test(2'd3, 2'd0, 2'd0, 2'd0,
                 2'd0, 2'd0, 2'd0, 2'd0,
                 2'd0, 2'd0, 2'd0, 2'd0,
                 2'd0, 2'd0, 2'd0, 2'd0,
                 2'd2, 2'd1, 2'd0, 2'd0,
                 2'd0, 2'd0, 2'd0, 2'd0,
                 2'd0, 2'd0, 2'd0, 2'd0,
                 2'd0, 2'd0, 2'd0, 2'd0,
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
