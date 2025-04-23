`default_nettype none
`timescale 1ns / 1ps

/* This testbench instantiates the UART-enabled wrapper */
module tb ();

    // --- Parameters ---
    localparam CLOCK_FREQ = 100_000; // Must match wrapper and test.py
    localparam BAUD_RATE = 5_000;    // Must match wrapper and test.py
    localparam CLK_PERIOD_NS = 1_000_000_000 / CLOCK_FREQ;

    // --- Testbench Signals ---
    reg clk = 0;
    reg rst_n = 0; // Start in reset

    // --- DUT Connections ---
    reg [7:0] ui_in = 8'hFF; // Default UART RX idle state (high)
    wire [7:0] uo_out;
    wire [7:0] uio_inout; // Unused by DUT in this config

    // --- Instantiate the Wrapper ---
    tt_generic_wrapper #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_inout(uio_inout), // Connect but unused
        .clk(clk),
        .rst_n(rst_n)
    );

    // --- Clock Generation ---
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    // --- Reset Sequence ---
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
        #1; // Short delay
        rst_n = 0; // Assert reset
        #(CLK_PERIOD_NS * 10); // Hold reset for 10 cycles
        rst_n = 1; // Deassert reset
    end

    // --- Cocotb Interface ---
    // Cocotb will drive ui_in[0] for UART TX simulation
    // Cocotb will monitor uo_out[0] for UART RX simulation

    // Tie off unused inputs (optional, good practice)
    // ui_in[7:1] are not used by the wrapper FSM
    // uio_inout is set to Z by the wrapper, tb doesn't need to drive

endmodule