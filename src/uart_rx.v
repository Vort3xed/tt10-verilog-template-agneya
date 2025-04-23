`default_nettype none
`timescale 1ns / 1ps

module uart_rx #(
    parameter CLOCK_FREQ = 100_000, // Hz
    parameter BAUD_RATE = 5_000,    // Baud
    parameter CLKS_PER_BIT = CLOCK_FREQ / BAUD_RATE // Should be integer
) (
    input wire clk,
    input wire rst_n,
    input wire rx_in,
    output reg rx_data_valid,
    output reg [7:0] rx_data
);

    localparam IDLE         = 0;
    localparam START_BIT    = 1;
    localparam DATA_BITS    = 2;
    localparam STOP_BIT     = 3;

    reg [$clog2(CLKS_PER_BIT)-1:0] clk_count = 0;
    reg [2:0] bit_index = 0; // 8 data bits
    reg [1:0] state = IDLE;
    reg [7:0] data_buffer = 0;
    reg rx_in_sync1 = 1;
    reg rx_in_sync2 = 1;
    reg rx_in_sync3 = 1;

    // Synchronize rx_in and detect falling edge for start bit
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_in_sync1 <= 1;
            rx_in_sync2 <= 1;
            rx_in_sync3 <= 1;
        end else begin
            rx_in_sync1 <= rx_in;
            rx_in_sync2 <= rx_in_sync1;
            rx_in_sync3 <= rx_in_sync2;
        end
    end
    wire falling_edge = rx_in_sync2 & ~rx_in_sync3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            clk_count <= 0;
            bit_index <= 0;
            rx_data_valid <= 0;
            rx_data <= 0;
            data_buffer <= 0;
        end else begin
            // Default assignments
            rx_data_valid <= 0;

            case (state)
                IDLE: begin
                    clk_count <= 0;
                    bit_index <= 0;
                    if (falling_edge) begin // Start bit detected
                        state <= START_BIT;
                        clk_count <= 1; // Start counting from 1
                    end
                end

                START_BIT: begin
                    if (clk_count == CLKS_PER_BIT / 2) begin // Check middle of start bit
                        if (rx_in_sync3 == 0) begin // Valid start bit
                            state <= DATA_BITS;
                            clk_count <= 0; // Reset for data bits
                            bit_index <= 0;
                        end else begin
                            state <= IDLE; // False start bit
                        end
                    end else if (clk_count == CLKS_PER_BIT - 1) begin
                         // Should have transitioned mid-bit, error if we get here
                         state <= IDLE;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                DATA_BITS: begin
                     if (clk_count == CLKS_PER_BIT -1) begin // End of a bit period
                        clk_count <= 0;
                        data_buffer <= {rx_in_sync3, data_buffer[7:1]}; // Shift in LSB first
                        if (bit_index == 7) begin
                            state <= STOP_BIT;
                        end else begin
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                STOP_BIT: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        if (rx_in_sync3 == 1) begin // Valid stop bit
                            rx_data <= data_buffer;
                            rx_data_valid <= 1;
                        end
                        // Else: Framing error (optional handling)
                        state <= IDLE; // Ready for next byte
                        clk_count <= 0;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule