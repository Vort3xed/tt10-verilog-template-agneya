`default_nettype none
`timescale 1ns / 1ps

/* This testbench instantiates the UART matrix multiplier module and provides
   signals for cocotb to drive/monitor the UART interface.
*/
module tb ();

    // Dump the signals to a VCD file. You can view it with gtkwave or surfer.
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
        #1;
    end

    // --- Testbench Signals ---
    reg clk;
    reg rst_n;
    reg ena;

    // Signals driven/monitored by cocotb test.py
    reg tb_rx; // Testbench drives this -> DUT ui_in[0]
    wire tb_tx; // Testbench monitors this <- DUT uo_out[0]

    // --- DUT Connections ---
    // We only need ui_in[0] for RX and uo_out[0] for TX
    wire [7:0] dut_ui_in;
    wire [7:0] dut_uo_out;
    // Tie unused uio inputs to 0
    wire [7:0] dut_uio_in = 8'b0;
    wire [7:0] dut_uio_out;
    wire [7:0] dut_uio_oe;

    // Connect testbench UART signals to DUT pins
    assign dut_ui_in[0] = tb_rx;
    assign dut_ui_in[7:1] = 7'b0; // Tie unused ui_in bits low
    assign tb_tx = dut_uo_out[0];

`ifdef GL_TEST
    wire VPWR = 1'b1;
    wire VGND = 1'b0;
`endif

    // Instantiate the DUT (the new top-level wrapper)
    tt_um_2x2MatrixMult_Vort3xed user_project (
`ifdef GL_TEST
        .VPWR(VPWR),
        .VGND(VGND),
`endif
        .ui_in  (dut_ui_in),    // Connect UART RX here
        .uo_out (dut_uo_out),   // Connect UART TX here
        .uio_in (dut_uio_in),   // Tied low
        .uio_out(dut_uio_out),  // Unused output
        .uio_oe (dut_uio_oe),   // Unused output
        .ena    (ena),          // Design enable
        .clk    (clk),          // Clock
        .rst_n  (rst_n)         // Reset
    );

    // --- Clock Generation ---
    initial begin
        clk = 0;
        forever #5000 clk = ~clk; // 10us period = 100kHz clock
    end

    // --- Initialization ---
    initial begin
        rst_n = 1'b0; // Assert reset
        ena = 1'b0;   // Keep disabled during reset
        tb_rx = 1'b1; // UART idle state
        #20000;       // Wait for a bit
        rst_n = 1'b1; // Deassert reset
        #10000;
        ena = 1'b1;   // Enable the design
    end

endmodule