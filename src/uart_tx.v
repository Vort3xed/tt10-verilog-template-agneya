`default_nettype none
`timescale 1ns / 1ps

module uart_tx #(
    parameter CLOCK_FREQ = 100_000, // Hz
    parameter BAUD_RATE = 5_000,    // Baud
    parameter CLKS_PER_BIT = CLOCK_FREQ / BAUD_RATE // Should be integer
) (
    input wire clk,
    input wire rst_n,
    input wire tx_start,      // Pulse high to start transmission
    input wire [7:0] tx_data, // Data to transmit
    output reg tx_busy,       // High while transmitting
    output reg tx_out = 1'b1  // UART TX line, idle high
);

    localparam IDLE         = 0;
    localparam START_BIT    = 1;
    localparam DATA_BITS    = 2;
    localparam STOP_BIT     = 3;

    reg [$clog2(CLKS_PER_BIT)-1:0] clk_count = 0;
    reg [3:0] bit_index = 0; // 0=start, 1-8=data, 9=stop
    reg [1:0] state = IDLE;
    reg [8:0] tx_buffer = 0; // Holds data + start/stop bits

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            clk_count <= 0;
            bit_index <= 0;
            tx_busy <= 0;
            tx_out <= 1'b1; // Idle high
        end else begin
            case (state)
                IDLE: begin
                    tx_out <= 1'b1;
                    tx_busy <= 0;
                    clk_count <= 0;
                    bit_index <= 0;
                    if (tx_start) begin
                        state <= START_BIT;
                        tx_buffer <= {tx_data, 1'b0}; // LSB is start bit
                        tx_busy <= 1;
                        tx_out <= 0; // Start bit
                        clk_count <= 1; // Start counting
                        bit_index <= 0; // Index for start bit
                    end
                end

                START_BIT: begin
                    if (clk_count == CLKS_PER_BIT -1) begin
                        clk_count <= 0;
                        state <= DATA_BITS;
                        bit_index <= 1; // Index for first data bit (LSB)
                        tx_out <= tx_buffer[0]; // Send LSB
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                DATA_BITS: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        if (bit_index == 8) begin // Last data bit sent
                            state <= STOP_BIT;
                            tx_out <= 1'b1; // Stop bit
                            bit_index <= 9; // Index for stop bit
                        end else begin
                            tx_out <= tx_buffer[bit_index]; // Send next data bit
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                STOP_BIT: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        state <= IDLE; // Transmission complete
                        // tx_busy will be deasserted in IDLE state next cycle
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule