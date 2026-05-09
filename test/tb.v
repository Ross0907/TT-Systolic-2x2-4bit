// Standard Tiny Tapeout testbench
// Instantiates the DUT and exposes all pins for cocotb to drive/read.
// Do NOT edit the port list; cocotb identifies signals by name.

`default_nettype none
`timescale 1ns/1ps

module tb ();

    // Clock & reset
    reg clk;
    reg rst_n;
    reg ena;

    // Dedicated inputs/outputs
    reg  [7:0] ui_in;
    wire [7:0] uo_out;

    // Bidirectional IOs
    reg  [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

`ifdef GL_TEST
    wire VPWR = 1'b1;
    wire VGND = 1'b0;
`endif

    // DUT
    tt_um_ross_systolic user_project (
`ifdef GL_TEST
        .VPWR   (VPWR),
        .VGND   (VGND),
`endif
        .ui_in  (ui_in),
        .uo_out (uo_out),
        .uio_in (uio_in),
        .uio_out(uio_out),
        .uio_oe (uio_oe),
        .ena    (ena),
        .clk    (clk),
        .rst_n  (rst_n)
    );

    // Dump VCD for GTKWave / Vivado
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
        #1;
    end

endmodule
