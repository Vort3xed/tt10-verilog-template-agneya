/*
 * Copyright (c) 2024 Agneya Tharun
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

//-----------------------------------------------------------------------------
// UART Receiver Module
//-----------------------------------------------------------------------------
module uart_rx #(
    parameter CLKS_PER_BIT = 10 // Default for 100kHz simulation clock, 9600 baud
) (
    input wire clk,
    input wire rst_n,
    input wire rx,          // Serial data input
    output reg rx_done,     // Goes high for one clock cycle when a byte is received
    output reg [7:0] rx_data // Received data byte
);
    localparam IDLE = 2'b00;
    localparam START = 2'b01;
    localparam DATA = 2'b10;
    localparam STOP = 2'b11;

    reg [1:0] state_reg;
    reg [3:0] bit_idx_reg; // To count 8 data bits
    // Use a fixed-width counter suitable for synthesis and potential CLKS_PER_BIT values
    reg [15:0] clk_count_reg; // Max value for 100MHz/9600baud is ~10417

    // Calculate middle sampling point
    localparam SAMPLE_POINT = (CLKS_PER_BIT / 2) - 1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg <= IDLE;
            clk_count_reg <= 0;
            bit_idx_reg <= 0;
            rx_done <= 1'b0;
            rx_data <= 8'b0;
        end else begin
            // Default assignments
            rx_done <= 1'b0;

            case (state_reg)
                IDLE: begin
                    clk_count_reg <= 0; // Reset counter in idle
                    bit_idx_reg <= 0;
                    if (rx == 1'b0) begin // Start bit detected (falling edge)
                        state_reg <= START;
                    end
                end

                START: begin
                    if (clk_count_reg == SAMPLE_POINT) begin
                        if (rx == 1'b0) begin // Confirm it's still low (valid start bit)
                            clk_count_reg <= 0; // Reset counter for data bits
                            state_reg <= DATA;
                        end else begin
                            state_reg <= IDLE; // Glitch, return to idle
                        end
                    end else begin
                        clk_count_reg <= clk_count_reg + 1;
                    end
                end

                DATA: begin
                    if (clk_count_reg == CLKS_PER_BIT - 1) begin
                        clk_count_reg <= 0; // Reset counter for next bit
                        rx_data[bit_idx_reg] <= rx; // Capture data bit (LSB first)
                        if (bit_idx_reg == 7) begin
                            bit_idx_reg <= 0;
                            state_reg <= STOP;
                        end else begin
                            bit_idx_reg <= bit_idx_reg + 1;
                        end
                    end else begin
                        clk_count_reg <= clk_count_reg + 1;
                    end
                end

                STOP: begin
                    if (clk_count_reg == CLKS_PER_BIT - 1) begin
                        // Check if stop bit is high? Optional, often ignored.
                        rx_done <= 1'b1; // Signal byte received
                        state_reg <= IDLE;
                    end else begin
                        clk_count_reg <= clk_count_reg + 1;
                    end
                end

                default: state_reg <= IDLE;
            endcase
        end
    end
endmodule

//-----------------------------------------------------------------------------
// UART Transmitter Module
//-----------------------------------------------------------------------------
module uart_tx #(
    parameter CLKS_PER_BIT = 10 // Default for 100kHz simulation clock, 9600 baud
) (
    input wire clk,
    input wire rst_n,
    input wire tx_start,    // Pulse high for one clock to start transmission
    input wire [7:0] tx_data, // Data byte to transmit
    output reg tx,          // Serial data output
    output reg tx_busy      // High while transmitting
);
    localparam IDLE = 2'b00;
    localparam START = 2'b01;
    localparam DATA = 2'b10;
    localparam STOP = 2'b11;

    reg [1:0] state_reg;
    reg [3:0] bit_idx_reg; // 0=start, 1-8=data, 9=stop
    reg [15:0] clk_count_reg; // Max value for 100MHz/9600baud is ~10417
    reg [7:0] data_reg; // Internal storage for data byte

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg <= IDLE;
            clk_count_reg <= 0;
            bit_idx_reg <= 0;
            tx <= 1'b1; // Idle line is high
            tx_busy <= 1'b0;
            data_reg <= 8'b0;
        end else begin
            case (state_reg)
                IDLE: begin
                    tx <= 1'b1;
                    tx_busy <= 1'b0;
                    clk_count_reg <= 0; // Keep counter reset
                    bit_idx_reg <= 0;
                    if (tx_start) begin
                        data_reg <= tx_data;
                        tx_busy <= 1'b1;
                        state_reg <= START;
                    end
                end

                START: begin // Send start bit (low)
                    tx <= 1'b0;
                    if (clk_count_reg == CLKS_PER_BIT - 1) begin
                        clk_count_reg <= 0;
                        bit_idx_reg <= 0; // Start counting data bits
                        state_reg <= DATA;
                    end else begin
                        clk_count_reg <= clk_count_reg + 1;
                    end
                end

                DATA: begin // Send data bits (LSB first)
                    tx <= data_reg[bit_idx_reg];
                    if (clk_count_reg == CLKS_PER_BIT - 1) begin
                        clk_count_reg <= 0;
                        if (bit_idx_reg == 7) begin
                            bit_idx_reg <= 0; // Reset for stop bit phase
                            state_reg <= STOP;
                        end else begin
                            bit_idx_reg <= bit_idx_reg + 1;
                        end
                    end else begin
                        clk_count_reg <= clk_count_reg + 1;
                    end
                end

                STOP: begin // Send stop bit (high)
                    tx <= 1'b1;
                    if (clk_count_reg == CLKS_PER_BIT - 1) begin
                        state_reg <= IDLE; // Return to idle, tx_busy will go low next cycle
                    end else begin
                        clk_count_reg <= clk_count_reg + 1;
                    end
                end

                default: state_reg <= IDLE;
            endcase
        end
    end
endmodule

//-----------------------------------------------------------------------------
// Original Matrix Multiplier Core (renamed from tt_um_2x2MatrixMult_Vort3xed)
//-----------------------------------------------------------------------------
module matrix_multiplier_core (
    input  wire [7:0] core_ui_in,    // Input for first matrix values
    output wire [7:0] core_uo_out,   // Sequential output of result cells
    input  wire [7:0] core_uio_in,   // Input for second matrix values
    input  wire       core_ena,      // Enable signal
    input  wire       clk,           // clock
    input  wire       rst_n          // active-low reset
);
    // Internal state definitions
    localparam STATE_INPUT_A = 2'd0,
               STATE_INPUT_B = 2'd1,
               STATE_COMPUTE = 2'd2,
               STATE_OUTPUT  = 2'd3;

    reg [1:0] state;
    reg [1:0] counter;      // used for both input and output counting
    reg [7:0] A0, A1, A2, A3;   // Elements for matrix A (rowwise order)
    reg [7:0] B0, B1, B2, B3;   // Elements for matrix B (rowwise order)
    reg [15:0] C00, C01, C10, C11; // Full-precision intermediate products
    reg [7:0] uo_out_reg;       // Registered output (truncated to 8 bits)

    // Output assignment
    assign core_uo_out = uo_out_reg;

    // Sequential logic with state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= STATE_INPUT_A;
            counter    <= 0;
            A0 <= 0; A1 <= 0; A2 <= 0; A3 <= 0;
            B0 <= 0; B1 <= 0; B2 <= 0; B3 <= 0;
            C00 <= 0; C01 <= 0; C10 <= 0; C11 <= 0;
            uo_out_reg <= 0;
        end else if (core_ena) begin // Only operate when enabled
            case (state)
                // Input first matrix (from core_ui_in)
                STATE_INPUT_A: begin
                    case (counter)
                        2'd0: A0 <= core_ui_in;
                        2'd1: A1 <= core_ui_in;
                        2'd2: A2 <= core_ui_in;
                        2'd3: A3 <= core_ui_in;
                    endcase
                    if (counter == 2'd3) begin
                        state   <= STATE_INPUT_B;
                        counter <= 0;
                    end else begin
                        counter <= counter + 1;
                    end
                end

                // Input second matrix (from core_uio_in)
                STATE_INPUT_B: begin
                    case (counter)
                        2'd0: B0 <= core_uio_in;
                        2'd1: B1 <= core_uio_in;
                        2'd2: B2 <= core_uio_in;
                        2'd3: B3 <= core_uio_in;
                    endcase
                    if (counter == 2'd3) begin
                        state   <= STATE_COMPUTE;
                        counter <= 0;
                    end else begin
                        counter <= counter + 1;
                    end
                end

                // Compute matrix multiplication
                STATE_COMPUTE: begin
                    // Standard 2x2 matrix multiply (results are truncated to 8 bits)
                    C00 <= A0 * B0 + A1 * B2;
                    C01 <= A0 * B1 + A1 * B3;
                    C10 <= A2 * B0 + A3 * B2;
                    C11 <= A2 * B1 + A3 * B3;
                    state <= STATE_OUTPUT;
                    counter <= 0;
                end

                // Output each cell over successive clock cycles
                STATE_OUTPUT: begin
                    case (counter)
                        2'd0: uo_out_reg <= C00[7:0];
                        2'd1: uo_out_reg <= C01[7:0];
                        2'd2: uo_out_reg <= C10[7:0];
                        2'd3: uo_out_reg <= C11[7:0];
                    endcase
                    if (counter == 2'd3) begin
                        // After outputting all cells, return to input state
                        state   <= STATE_INPUT_A;
                        counter <= 0;
                    end else begin
                        counter <= counter + 1;
                    end
                end

                default: state <= STATE_INPUT_A;
            endcase
        end // end if(core_ena)
    end // end always
endmodule

//-----------------------------------------------------------------------------
// Top-Level UART Matrix Multiplier Wrapper
// This is the module that will be synthesized for the FPGA.
//-----------------------------------------------------------------------------
module tt_um_2x2MatrixMult_Vort3xed (
    input  wire [7:0] ui_in,    // ui_in[0] is UART RX
    output wire [7:0] uo_out,   // uo_out[0] is UART TX
    input  wire [7:0] uio_in,   // Unused in this UART wrapper
    output wire [7:0] uio_out,  // Unused
    output wire [7:0] uio_oe,   // Unused
    input  wire       ena,      // Design enable
    input  wire       clk,      // System clock
    input  wire       rst_n     // System reset
);

    // --- Parameters ---
    // Set CLKS_PER_BIT based on target clock frequency and baud rate
    // For 100MHz Arty A7 clock and 9600 baud: 100,000,000 / 9600 = 10416.67
    // For 100kHz simulation clock and 9600 baud: 100,000 / 9600 = 10.4
    // Choose the value appropriate for your simulation or synthesis target.
    // Using 10 for simulation as per original test.py clock.
    // Change to 10417 for synthesis on Arty A7.
    localparam CLKS_PER_BIT_PARAM = 10;

    // localparam CLKS_PER_BIT_PARAM = 10417; // For synthesis on Arty A7

    // --- Unused IO ---
    assign uio_out = 8'b0;
    assign uio_oe = 8'b0; // All uio pins are inputs (oe=0)

    // --- Internal Signals ---
    wire uart_rx_wire = ui_in[0]; // Connect UART RX to the designated pin
    wire uart_tx_wire;            // UART TX output from the TX module
    assign uo_out = {7'b0, uart_tx_wire}; // Connect UART TX to the designated pin

    wire rx_done;
    wire [7:0] rx_data;
    reg tx_start;
    reg [7:0] tx_data_to_send;
    wire tx_busy;

    reg [7:0] matrix_A_bytes [0:3];
    reg [7:0] matrix_B_bytes [0:3];
    reg [7:0] result_bytes [0:3];

    reg [3:0] byte_count; // Counts received/sent bytes (0-7 for input, 0-3 for output)
    reg core_start_computation; // Signal to start the core computation
    reg core_ena_reg; // Enable signal for the core multiplier

    wire [7:0] core_result_out; // Output from the core multiplier

    // --- State Machine ---
    typedef enum logic [2:0] {
        S_IDLE,
        S_RX_A,
        S_RX_B,
        S_LOAD_CORE_A,
        S_LOAD_CORE_B,
        S_WAIT_COMPUTE,
        S_READ_RESULT,
        S_TX_RESULT
    } state_t;

    reg state_reg, next_state;

    // --- Instantiate Modules ---
    uart_rx #( .CLKS_PER_BIT(CLKS_PER_BIT_PARAM) ) rx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_rx_wire),
        .rx_done(rx_done),
        .rx_data(rx_data)
    );

    uart_tx #( .CLKS_PER_BIT(CLKS_PER_BIT_PARAM) ) tx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_data(tx_data_to_send),
        .tx(uart_tx_wire),
        .tx_busy(tx_busy)
    );

    matrix_multiplier_core core_inst (
        .core_ui_in(matrix_A_bytes[byte_count]), // Feed A bytes during LOAD_CORE_A
        .core_uo_out(core_result_out),
        .core_uio_in(matrix_B_bytes[byte_count]), // Feed B bytes during LOAD_CORE_B
        .core_ena(core_ena_reg), // Enable core only when loading/computing/reading
        .clk(clk),
        .rst_n(rst_n)
    );

    // --- State Register ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg <= S_IDLE;
        end else if (ena) begin // Only advance state if top-level enable is high
            state_reg <= next_state;
        end else begin
            state_reg <= S_IDLE; // If disabled, return to IDLE
        end
    end

    // --- Combinational State Logic ---
    always_comb begin
        // Default assignments
        next_state = state_reg;
        tx_start = 1'b0;
        tx_data_to_send = 8'b0;
        core_ena_reg = 1'b0; // Core disabled by default

        case (state_reg)
            S_IDLE: begin
                byte_count = 0; // Reset counter
                if (ena) begin // Wait for enable before starting reception
                   next_state = S_RX_A;
                end
            end

            S_RX_A: begin // Receive 4 bytes for Matrix A
                if (rx_done) begin
                    matrix_A_bytes[byte_count] = rx_data;
                    if (byte_count == 3) begin
                        byte_count = 0; // Reset for Matrix B
                        next_state = S_RX_B;
                    end else begin
                        byte_count = byte_count + 1;
                    end
                end
            end

            S_RX_B: begin // Receive 4 bytes for Matrix B
                if (rx_done) begin
                    matrix_B_bytes[byte_count] = rx_data;
                    if (byte_count == 3) begin
                        byte_count = 0; // Reset for loading core
                        next_state = S_LOAD_CORE_A;
                    end else begin
                        byte_count = byte_count + 1;
                    end
                end
            end

            S_LOAD_CORE_A: begin // Load Matrix A into core (4 cycles)
                core_ena_reg = 1'b1; // Enable core
                // Data is selected by byte_count via core_inst connection
                if (byte_count == 3) begin
                    byte_count = 0; // Reset for loading B
                    next_state = S_LOAD_CORE_B;
                end else begin
                    byte_count = byte_count + 1;
                    next_state = S_LOAD_CORE_A; // Stay here for 4 cycles
                end
            end

            S_LOAD_CORE_B: begin // Load Matrix B into core (4 cycles)
                core_ena_reg = 1'b1; // Enable core
                // Data is selected by byte_count via core_inst connection
                if (byte_count == 3) begin
                    byte_count = 0; // Reset for waiting
                    next_state = S_WAIT_COMPUTE;
                end else begin
                    byte_count = byte_count + 1;
                    next_state = S_LOAD_CORE_B; // Stay here for 4 cycles
                end
            end

            S_WAIT_COMPUTE: begin // Wait 1 cycle for computation state in core
                 core_ena_reg = 1'b1; // Keep core enabled for compute state
                 byte_count = 0; // Reset for reading results
                 next_state = S_READ_RESULT;
            end

            S_READ_RESULT: begin // Read 4 result bytes from core (4 cycles)
                core_ena_reg = 1'b1; // Keep core enabled for output state
                result_bytes[byte_count] = core_result_out; // Capture result
                if (byte_count == 3) begin
                    byte_count = 0; // Reset for TX
                    next_state = S_TX_RESULT;
                end else begin
                    byte_count = byte_count + 1;
                    next_state = S_READ_RESULT; // Stay here for 4 cycles
                end
            end

            S_TX_RESULT: begin // Transmit 4 result bytes
                if (!tx_busy) begin // Only start sending if TX is not busy
                    tx_data_to_send = result_bytes[byte_count];
                    tx_start = 1'b1; // Request transmission
                    if (byte_count == 3) begin
                        byte_count = 0; // Reset counter
                        next_state = S_IDLE; // Done, return to idle
                    end else begin
                        byte_count = byte_count + 1;
                        // Stay in this state, next byte sent when tx_busy goes low again
                    end
                end
                // If tx_busy is high, stay in this state and wait.
            end

            default: next_state = S_IDLE;
        endcase
    end

endmodule