// =============================================================================
// FILE        : tb_vivado.v
// DESCRIPTION : Self-checking Verilog testbench for tt_um_ross_systolic
//               3×3 Systolic Array Matrix Multiplier (3-bit elements)
//
// HOW TO USE IN VIVADO
// ────────────────────
//  1. File → Add Sources → Add or create simulation sources
//     Add ALL of:
//       src/mult_3x3.v
//       src/systolic_pe.v
//       src/systolic_3x3.v
//       src/project.v
//       test/tb_vivado.v   (set as top)
//  2. In the Flow Navigator, click "Run Simulation" → "Run Behavioral Simulation"
//  3. In Tcl console:   run 5000ns
//  4. Check transcript for PASS/FAIL messages.
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
    wire       busy  = uo_out[7];  // not used directly
    wire       valid = 1'b1;      // full byte always valid when read
    wire [7:0] rdata = uo_out[7:0];

    // ─────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────
    integer pass_count = 0;
    integer fail_count = 0;

    // Pack two 3-bit elements into one byte: {2'b0, e1[2:0], e0[2:0]}
    function [7:0] pack2_3bit;
        input [2:0] e0, e1;
        begin
            pack2_3bit = {2'b00, e1, e0};
        end
    endfunction

    // Reference 3×3 matrix multiply element
    function [7:0] ref_elem;
        input [2:0] a0, a1, a2;
        input [2:0] b0, b1, b2;
        begin
            ref_elem = ({5'b0, a0} * {5'b0, b0}) +
                       ({5'b0, a1} * {5'b0, b1}) +
                       ({5'b0, a2} * {5'b0, b2});
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

    // Read 9 serial results after fixed delay
    reg [7:0] results [0:8];
    task read_results;
        integer j;
        begin
            for (j = 0; j < 9; j = j + 1) begin
                results[j] = uo_out;
                @(posedge clk);
            end
        end
    endtask

    // Run one complete 3×3 test case
    task run_test;
        input [2:0] a00, a01, a02;
        input [2:0] a10, a11, a12;
        input [2:0] a20, a21, a22;
        input [2:0] b00, b01, b02;
        input [2:0] b10, b11, b12;
        input [2:0] b20, b21, b22;
        input [63:0] label;
        reg [7:0] ec00, ec01, ec02;
        reg [7:0] ec10, ec11, ec12;
        reg [7:0] ec20, ec21, ec22;
        reg ok;
        begin
            // Expected results
            ec00 = ref_elem(a00, a01, a02, b00, b10, b20);
            ec01 = ref_elem(a00, a01, a02, b01, b11, b21);
            ec02 = ref_elem(a00, a01, a02, b02, b12, b22);
            ec10 = ref_elem(a10, a11, a12, b00, b10, b20);
            ec11 = ref_elem(a10, a11, a12, b01, b11, b21);
            ec12 = ref_elem(a10, a11, a12, b02, b12, b22);
            ec20 = ref_elem(a20, a21, a22, b00, b10, b20);
            ec21 = ref_elem(a20, a21, a22, b01, b11, b21);
            ec22 = ref_elem(a20, a21, a22, b02, b12, b22);

            do_reset;

            // Load 10 bytes: A (5 bytes), then B (5 bytes)
            // A packing: byte0={a01,a00}, byte1={a10,a02}, byte2={a12,a11}, byte3={a21,a20}, byte4={5'b0,a22}
            load_byte(pack2_3bit(a00, a01));
            load_byte(pack2_3bit(a02, a10));
            load_byte(pack2_3bit(a11, a12));
            load_byte(pack2_3bit(a20, a21));
            load_byte({5'b0, a22});
            // B packing: byte5={b01,b00}, byte6={b10,b02}, byte7={b12,b11}, byte8={b21,b20}, byte9={5'b0,b22}
            load_byte(pack2_3bit(b00, b01));
            load_byte(pack2_3bit(b02, b10));
            load_byte(pack2_3bit(b11, b12));
            load_byte(pack2_3bit(b20, b21));
            load_byte({5'b0, b22});

            // Start computation
            do_start;

            // Wait for systolic array to finish (~10 cycles) then read 9 outputs
            repeat(10) @(posedge clk);
            read_results;

            ok = (results[0] === ec00 && results[1] === ec01 && results[2] === ec02 &&
                  results[3] === ec10 && results[4] === ec11 && results[5] === ec12 &&
                  results[6] === ec20 && results[7] === ec21 && results[8] === ec22);

            if (!ok) begin
                $display("FAIL [%s]", label);
                $display("  got      C00=%0d C01=%0d C02=%0d", results[0], results[1], results[2]);
                $display("           C10=%0d C11=%0d C12=%0d", results[3], results[4], results[5]);
                $display("           C20=%0d C21=%0d C22=%0d", results[6], results[7], results[8]);
                $display("  expected C00=%0d C01=%0d C02=%0d", ec00, ec01, ec02);
                $display("           C10=%0d C11=%0d C12=%0d", ec10, ec11, ec12);
                $display("           C20=%0d C21=%0d C22=%0d", ec20, ec21, ec22);
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
        $display("=== tt_um_ross_systolic 3x3 testbench start ===");

        // Test 1: Identity × Identity = Identity
        run_test(3'd1, 3'd0, 3'd0,
                 3'd0, 3'd1, 3'd0,
                 3'd0, 3'd0, 3'd1,
                 3'd1, 3'd0, 3'd0,
                 3'd0, 3'd1, 3'd0,
                 3'd0, 3'd0, 3'd1,
                 "I*I     ");

        // Test 2: All-ones × All-ones
        run_test(3'd1, 3'd1, 3'd1,
                 3'd1, 3'd1, 3'd1,
                 3'd1, 3'd1, 3'd1,
                 3'd1, 3'd1, 3'd1,
                 3'd1, 3'd1, 3'd1,
                 3'd1, 3'd1, 3'd1,
                 "1s*1s   ");

        // Test 3: Maximum inputs (7×7)
        run_test(3'd7, 3'd7, 3'd7,
                 3'd7, 3'd7, 3'd7,
                 3'd7, 3'd7, 3'd7,
                 3'd7, 3'd7, 3'd7,
                 3'd7, 3'd7, 3'd7,
                 3'd7, 3'd7, 3'd7,
                 "max     ");

        // Test 4: Asymmetric
        run_test(3'd2, 3'd1, 3'd0,
                 3'd0, 3'd2, 3'd1,
                 3'd3, 3'd0, 3'd2,
                 3'd1, 3'd2, 3'd3,
                 3'd0, 3'd1, 3'd2,
                 3'd3, 3'd0, 3'd1,
                 "asym    ");

        // Test 5: Zero matrix
        run_test(3'd0, 3'd0, 3'd0,
                 3'd0, 3'd0, 3'd0,
                 3'd0, 3'd0, 3'd0,
                 3'd3, 3'd2, 3'd1,
                 3'd1, 3'd2, 3'd3,
                 3'd0, 3'd1, 3'd2,
                 "0*B     ");

        // Test 6: Diagonal scaling
        run_test(3'd2, 3'd0, 3'd0,
                 3'd0, 3'd2, 3'd0,
                 3'd0, 3'd0, 3'd2,
                 3'd1, 3'd3, 3'd2,
                 3'd3, 3'd1, 3'd3,
                 3'd2, 3'd3, 3'd1,
                 "diag    ");

        // Test 7: Sparse
        run_test(3'd3, 3'd0, 3'd0,
                 3'd0, 3'd0, 3'd0,
                 3'd0, 3'd0, 3'd0,
                 3'd2, 3'd1, 3'd0,
                 3'd0, 3'd0, 3'd0,
                 3'd0, 3'd0, 3'd0,
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
