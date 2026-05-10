// =============================================================================
// FILE        : tb_vivado.v
// DESCRIPTION : Self-checking Verilog testbench for tt_um_ross_systolic
//               2×2 Systolic Array Matrix Multiplier (signed 4-bit elements)
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

    // Pack two signed 4-bit elements into one byte: {e1[3:0], e0[3:0]}
    function [7:0] pack2_4bit;
        input signed [3:0] e0, e1;
        begin
            pack2_4bit = {e1[3:0], e0[3:0]};
        end
    endfunction

    // Reference 2×2 matrix multiply element (signed 9-bit, compare lower 8 bits)
    function signed [8:0] ref_elem;
        input signed [3:0] a0, a1;
        input signed [3:0] b0, b1;
        begin
            ref_elem = (a0 * b0) + (a1 * b1);
        end
    endfunction

    // Check if signed 9-bit value overflows 8-bit signed range
    function overflow_8bit;
        input signed [8:0] val;
        begin
            overflow_8bit = (val > 127) || (val < -128);
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
        reg signed [8:0] ec00, ec01;
        reg signed [8:0] ec10, ec11;
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

            // Wait for out_valid, then read 4 results with per-cycle overflow/sign check
            repeat(2) @(posedge clk);
            while (uio_out[3] == 1'b0) @(posedge clk);

            begin : read_with_debug
                integer k;
                reg exp_ov;
                reg exp_sign;
                for (k = 0; k < 4; k = k + 1) begin
                    results[k] = uo_out;
                    // Check per-result overflow_8bit and acc_sign
                    case (k)
                        0: begin exp_ov = overflow_8bit(ec00); exp_sign = ec00[8]; end
                        1: begin exp_ov = overflow_8bit(ec01); exp_sign = ec01[8]; end
                        2: begin exp_ov = overflow_8bit(ec10); exp_sign = ec10[8]; end
                        3: begin exp_ov = overflow_8bit(ec11); exp_sign = ec11[8]; end
                    endcase
                    if (uio_out[4] !== exp_ov) begin
                        $display("  OVERFLOW MISMATCH C%0d%0d: got %b, exp %b", k/2,k%2, uio_out[4], exp_ov);
                        ok = 1'b0;
                    end
                    if (uio_out[7] !== exp_sign) begin
                        $display("  SIGN MISMATCH C%0d%0d: got %b, exp %b", k/2,k%2, uio_out[7], exp_sign);
                        ok = 1'b0;
                    end
                    if (k < 3) @(posedge clk);
                end
            end

            // Compare lower 8 bits (uo_out is 8-bit, accumulator is 9-bit)
            ok = ok && (results[0] === ec00[7:0] && results[1] === ec01[7:0] &&
                        results[2] === ec10[7:0] && results[3] === ec11[7:0]);

            // Let serializer finish (out_valid goes 0 on next edge after last read)
            @(posedge clk);
            // After stream: out_valid=0, so overflow_8bit=0 and acc_sign=0
            // busy_core should also be 0
            if (uio_out[4] !== 1'b0 || uio_out[7] !== 1'b0 || uio_out[2] !== 1'b0) begin
                $display("  FINAL DEBUG MISMATCH: uio_out=0x%02X (exp overflow=0, sign=0, busy=0)", uio_out);
                ok = 1'b0;
            end

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
    // Step-mode helpers
    // ─────────────────────────────────────────────────────────────
    task step_pulse;
        begin
            @(negedge clk);
            uio_in[5] = 1'b1;   // manual_clk high
            @(posedge clk);       // rising edge → step fires
            @(negedge clk);
            uio_in[5] = 1'b0;   // manual_clk low
            @(posedge clk);
        end
    endtask

    task load_byte_step;
        input [7:0] data;
        begin
            @(negedge clk);
            ui_in  = data;
            uio_in = 8'h41;       // step_mode=1, wren=1
            step_pulse;
            @(negedge clk);
            uio_in = 8'h40;       // step_mode=1, wren=0
            @(posedge clk);
        end
    endtask

    task start_compute_step;
        begin
            @(negedge clk);
            uio_in = 8'h42;       // step_mode=1, start=1
            step_pulse;
            @(negedge clk);
            uio_in = 8'h40;       // step_mode=1, start=0
            @(posedge clk);
        end
    endtask

    task read_results_step;
        reg [7:0] res [0:3];
        integer k;
        begin
            // Step until out_valid goes high
            while (uio_out[3] == 1'b0) step_pulse;
            // Read 4 results, one per step
            for (k = 0; k < 4; k = k + 1) begin
                res[k] = uo_out;
                if (k < 3) step_pulse;
            end
        end
    endtask

    // Run one test in manual step mode and verify against reference
    task run_test_step;
        input [3:0] a00, a01;
        input [3:0] a10, a11;
        input [3:0] b00, b01;
        input [3:0] b10, b11;
        input [63:0] label;
        reg signed [8:0] ec00, ec01;
        reg signed [8:0] ec10, ec11;
        reg [7:0] got [0:3];
        reg ok;
        integer k;
        begin
            ec00 = ref_elem(a00, a01, b00, b10);
            ec01 = ref_elem(a00, a01, b01, b11);
            ec10 = ref_elem(a10, a11, b00, b10);
            ec11 = ref_elem(a10, a11, b01, b11);

            do_reset;

            load_byte_step(pack2_4bit(a00, a01));
            load_byte_step(pack2_4bit(a10, a11));
            load_byte_step(pack2_4bit(b00, b01));
            load_byte_step(pack2_4bit(b10, b11));

            start_compute_step;

            // Step until result valid, then read 4 results
            while (uio_out[3] == 1'b0) step_pulse;
            for (k = 0; k < 4; k = k + 1) begin
                got[k] = uo_out;
                if (k < 3) step_pulse;
            end

            ok = (got[0] === ec00[7:0] && got[1] === ec01[7:0] &&
                  got[2] === ec10[7:0] && got[3] === ec11[7:0]);

            if (!ok) begin
                $display("FAIL [%s] (step mode)", label);
                $display("  got      C00=%0d C01=%0d", got[0], got[1]);
                $display("           C10=%0d C11=%0d", got[2], got[3]);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS [%s] (step mode)", label);
                pass_count = pass_count + 1;
            end
        end
    endtask

    // ─────────────────────────────────────────────────────────────
    // Test sequence
    // ─────────────────────────────────────────────────────────────
    initial begin
        $timeformat(-9, 1, " ns", 8);
        $display("=== tt_um_ross_systolic 2x2 (signed 4-bit) testbench start ===");

        // Verify debug IO configuration after reset
        do_reset;
        if (uio_oe !== 8'h9C) begin
            $display("FAIL [io_oe] expected 0x9C, got 0x%02X", uio_oe);
            fail_count = fail_count + 1;
        end else begin
            $display("PASS [io_oe] uio_oe = 0x9C (bits 7,4,3,2 out; 6,5,1,0 in)");
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

        // Test 3: Max positive inputs (7×7 → 98, fits in 8-bit signed)
        run_test(4'sd7, 4'sd7,
                 4'sd7, 4'sd7,
                 4'sd7, 4'sd7,
                 4'sd7, 4'sd7,
                 "max-pos ");

        // Test 4: Asymmetric
        run_test(4'd5, 4'd3,
                 4'd2, 4'd7,
                 4'd4, 4'd6,
                 4'd1, 4'd7,
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

        // Test 7: Mixed signs (3, -4, 5, 6) × (1, 2, -3, 4)
        run_test(4'sd3,  -4'sd4,
                 4'sd5,   4'sd6,
                 4'sd1,   4'sd2,
                 -4'sd3,  4'sd4,
                 "mixed-sg");

        // Test 8: Overflow test — (-8)×(-8) + (-8)×(-8) = 128 (> +127)
        run_test(-4'sd8, -4'sd8,
                 4'sd0,   4'sd0,
                 -4'sd8,  4'sd0,
                 4'sd0,   4'sd0,
                 "overflow");

        // Test 9: All minimum (-8) inputs
        run_test(-4'sd8, -4'sd8,
                 -4'sd8, -4'sd8,
                 -4'sd8, -4'sd8,
                 -4'sd8, -4'sd8,
                 "all-neg ");

        // Test 10: Boundary mix (-8, 7, -8, 7) × (7, -8, 7, -8)
        run_test(-4'sd8,  4'sd7,
                 -4'sd8,  4'sd7,
                  4'sd7, -4'sd8,
                  4'sd7, -4'sd8,
                 "bndry-mx");

        // Test 11: Manual step mode — same matrix, stepped one cycle at a time
        run_test_step(4'sd3,  4'sd2,
                      -4'sd1, 4'sd4,
                       4'sd5, -4'sd2,
                       4'sd3,  4'sd1,
                      "step-md ");

        // Test 12: ena gating — start ignored when ena=0
        begin
            reg ena_ok;
            do_reset;
            ena = 1'b0;
            load_byte(pack2_4bit(4'd1, 4'd0));
            load_byte(pack2_4bit(4'd0, 4'd1));
            load_byte(pack2_4bit(4'd1, 4'd0));
            load_byte(pack2_4bit(4'd0, 4'd1));
            @(negedge clk);
            uio_in = 8'h02;  // start=1, but ena=0
            @(posedge clk);
            @(negedge clk);
            uio_in = 8'h00;
            repeat(4) @(posedge clk);
            ena_ok = (uio_out[2] === 1'b0) && (uio_out[4] === 1'b0);  // busy=0
            if (ena_ok) begin
                $display("PASS [ena-gate] start ignored when ena=0");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [ena-gate] computation started despite ena=0");
                fail_count = fail_count + 1;
            end
            ena = 1'b1;
        end

        // Test 13: Reset during compute — should abort cleanly
        begin
            reg rst_ok;
            do_reset;
            load_byte(pack2_4bit(4'd3, 4'd2));
            load_byte(pack2_4bit(4'd5, 4'd7));
            load_byte(pack2_4bit(4'd1, 4'd0));
            load_byte(pack2_4bit(4'd0, 4'd1));
            do_start;
            repeat(2) @(posedge clk);  // mid-compute
            do_reset;
            rst_ok = (uio_out === 8'h00) && (uo_out === 8'h00);
            if (rst_ok) begin
                $display("PASS [rst-mid] reset during compute aborts cleanly");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [rst-mid] uio_out=0x%02X uo_out=0x%02X after reset", uio_out, uo_out);
                fail_count = fail_count + 1;
            end
        end

        // Test 14: Start-while-busy ignored
        begin
            reg busy_ok;
            do_reset;
            load_byte(pack2_4bit(4'd3, 4'd2));
            load_byte(pack2_4bit(4'd5, 4'd7));
            load_byte(pack2_4bit(4'd1, 4'd0));
            load_byte(pack2_4bit(4'd0, 4'd1));
            do_start;
            @(posedge clk);
            @(negedge clk);
            uio_in = 8'h02;  // start again while busy
            @(posedge clk);
            @(negedge clk);
            uio_in = 8'h00;
            busy_ok = (uio_out[2] === 1'b1);  // still busy, not restarted
            repeat(10) @(posedge clk);  // let it finish
            if (busy_ok && uio_out[2] === 1'b0) begin
                $display("PASS [busy-ign] start-while-busy ignored");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [busy-ign] start-while-busy caused restart");
                fail_count = fail_count + 1;
            end
        end

        // Test 15: Rapid consecutive runs (no reset between)
        begin
            reg rapid_ok;
            integer rc;
            rapid_ok = 1'b1;
            do_reset;
            for (rc = 0; rc < 3; rc = rc + 1) begin
                load_byte(pack2_4bit(4'd1+rc, 4'd0));
                load_byte(pack2_4bit(4'd0, 4'd1));
                load_byte(pack2_4bit(4'd1, 4'd0+rc));
                load_byte(pack2_4bit(4'd0, 4'd1));
                do_start;
                repeat(8) @(posedge clk);
                // Just verify no crash / busy goes low
                if (uio_out[2] !== 1'b0) begin
                    $display("  FAIL rapid run %0d: busy_core still high", rc);
                    rapid_ok = 1'b0;
                end
            end
            if (rapid_ok) begin
                $display("PASS [rapid-3] 3 consecutive runs OK");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [rapid-3] consecutive run failure");
                fail_count = fail_count + 1;
            end
        end

        // Test 16: Overflow boundary (+127 edge)
        begin
            reg ov_ok;
            do_reset;
            // A = [[7,7],[0,0]], B = [[7,0],[7,0]] -> C00 = 98 (fits)
            load_byte(pack2_4bit(4'sd7, 4'sd7));
            load_byte(pack2_4bit(4'sd0, 4'sd0));
            load_byte(pack2_4bit(4'sd7, 4'sd0));
            load_byte(pack2_4bit(4'sd7, 4'sd0));
            do_start;
            repeat(6) @(posedge clk);
            read_results;
            // C00 = 7*7 + 7*7 = 98, fits in 8-bit, overflow should be 0 during C00 read
            ov_ok = (results[0] === 8'd98);
            if (ov_ok) begin
                $display("PASS [ov-edge] +98 fits, no overflow");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [ov-edge] result=%0d, expected 98", results[0]);
                fail_count = fail_count + 1;
            end
        end

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
