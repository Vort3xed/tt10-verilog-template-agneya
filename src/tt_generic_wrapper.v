`default_nettype none
`timescale 1ns / 1ps

// Include UART modules (adjust path if needed)
`include "uart_rx.v"
`include "uart_tx.v"
// Include the original project module
// `include "project.v" // Assuming it's included elsewhere or pre-compiled

module tt_generic_wrapper #(
    parameter CLOCK_FREQ = 100_000, // Hz - Match cocotb clock
    parameter BAUD_RATE = 5_000     // Baud - Match cocotb baud rate
) (
    input  wire [7:0] ui_in,    // Dedicated inputs (ui_in[0] used for UART RX)
    output wire [7:0] uo_out,   // Dedicated outputs (uo_out[0] used for UART TX)
    inout  wire [7:0] uio_inout,// Bidirectional input/output (unused in this setup)
    input  wire       clk,      // System clock
    input  wire       rst_n     // Async active-low reset
);

    localparam CLKS_PER_BIT = CLOCK_FREQ / BAUD_RATE;

    // --- UART Signals ---
    wire uart_rx_in = ui_in[0]; // Use ui_in[0] for UART RX
    wire uart_tx_out;           // UART TX output wire
    wire rx_data_valid;
    wire [7:0] rx_data;
    reg tx_start = 0;
    reg [7:0] tx_data = 0;
    wire tx_busy;

    // --- Matrix Core Signals ---
    reg core_rst_n = 0; // Separate synchronous reset for core FSM
    reg [7:0] core_ui_in = 0;
    reg [7:0] core_uio_in = 0;
    wire [7:0] core_uo_out;
    // Core's uio_out and uio_oe are unused by the wrapper

    // --- Internal State and Storage ---
    localparam S_IDLE       = 0;
    localparam S_RECV_A     = 1; // Receiving Matrix A (4 bytes)
    localparam S_RECV_B     = 2; // Receiving Matrix B (4 bytes)
    localparam S_LOAD_A     = 3; // Loading Matrix A into core
    localparam S_LOAD_B     = 4; // Loading Matrix B into core
    localparam S_WAIT_CORE  = 5; // Waiting for core computation (fixed delay)
    localparam S_READ_C     = 6; // Reading result Matrix C from core
    localparam S_SEND_C     = 7; // Sending Matrix C via UART

    reg [2:0] state = S_IDLE;
    reg [1:0] byte_count = 0; // Counts bytes received/sent (0-3)
    reg [1:0] load_count = 0; // Counts cycles for loading core (0-3)
    reg [3:0] wait_count = 0; // Counts cycles waiting for core (~1+4 cycles)
    reg [7:0] matrix_A[0:3];
    reg [7:0] matrix_B[0:3];
    reg [7:0] matrix_C[0:3];

    // --- Instantiate UART Modules ---
    uart_rx #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uart_rx_inst (
        .clk(clk),
        .rst_n(rst_n), // Use async reset for UART RX
        .rx_in(uart_rx_in),
        .rx_data_valid(rx_data_valid),
        .rx_data(rx_data)
    );

    uart_tx #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uart_tx_inst (
        .clk(clk),
        .rst_n(rst_n), // Use async reset for UART TX
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_busy(tx_busy),
        .tx_out(uart_tx_out)
    );

    // --- Instantiate Matrix Core ---
    tt_um_2x2MatrixMult_Vort3xed project (
        .ui_in(core_ui_in),     // Controlled by wrapper FSM
        .uo_out(core_uo_out),   // Read by wrapper FSM
        .uio_in(core_uio_in),   // Controlled by wrapper FSM
        .uio_out(),             // Not used by wrapper
        .uio_oe(),              // Not used by wrapper
        .ena(1'b1),             // Assuming always enabled when powered
        .clk(clk),              // Use main clock
        .rst_n(core_rst_n)      // Use synchronous reset controlled by wrapper
    );

    // --- Assign Outputs ---
    // Assign UART TX to the designated output pin
    assign uo_out[0] = uart_tx_out;
    // Assign other outputs to 0 (or keep floating if appropriate)
    assign uo_out[7:1] = 7'b0;
    // uio_inout is unused, keep it high-Z
    assign uio_inout = 8'hZZ;

    // --- Control FSM ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Async reset for main FSM state
            state <= S_IDLE;
            byte_count <= 0;
            load_count <= 0;
            wait_count <= 0;
            core_rst_n <= 0; // Assert core reset
            tx_start <= 0;
            // Clear stored matrices (optional)
            matrix_A[0] <= 0; matrix_A[1] <= 0; matrix_A[2] <= 0; matrix_A[3] <= 0;
            matrix_B[0] <= 0; matrix_B[1] <= 0; matrix_B[2] <= 0; matrix_B[3] <= 0;
            matrix_C[0] <= 0; matrix_C[1] <= 0; matrix_C[2] <= 0; matrix_C[3] <= 0;
        end else begin
            // Default assignments
            tx_start <= 0; // tx_start is a pulse
            core_rst_n <= 1; // Deassert core reset after main reset

            case (state)
                S_IDLE: begin
                    byte_count <= 0;
                    load_count <= 0;
                    wait_count <= 0;
                    if (rx_data_valid) begin // Received first byte of A
                        matrix_A[0] <= rx_data;
                        byte_count <= 1;
                        state <= S_RECV_A;
                    end
                end

                S_RECV_A: begin // Receive A[1], A[2], A[3]
                    if (rx_data_valid) begin
                        matrix_A[byte_count] <= rx_data;
                        if (byte_count == 3) begin
                            byte_count <= 0; // Reset for matrix B
                            state <= S_RECV_B;
                        end else begin
                            byte_count <= byte_count + 1;
                        end
                    end
                end

                S_RECV_B: begin // Receive B[0]..B[3]
                    if (rx_data_valid) begin
                        matrix_B[byte_count] <= rx_data;
                        if (byte_count == 3) begin
                            byte_count <= 0; // Reset for output count
                            load_count <= 0; // Reset for loading count
                            core_rst_n <= 0; // Reset the core FSM before loading
                            state <= S_LOAD_A;
                        end else begin
                            byte_count <= byte_count + 1;
                        end
                    end
                end

                S_LOAD_A: begin // Load A into core over 4 cycles
                    core_rst_n <= 1; // De-assert core reset
                    core_ui_in <= matrix_A[load_count];
                    if (load_count == 3) begin
                        load_count <= 0; // Reset for loading B
                        state <= S_LOAD_B;
                    end else begin
                        load_count <= load_count + 1;
                    end
                end

                S_LOAD_B: begin // Load B into core over 4 cycles
                    core_uio_in <= matrix_B[load_count];
                    if (load_count == 3) begin
                        load_count <= 0; // Done loading
                        wait_count <= 0; // Start wait counter
                        state <= S_WAIT_CORE;
                    end else begin
                        load_count <= load_count + 1;
                    end
                end

                S_WAIT_CORE: begin // Wait for core (Compute=1 + Output=4 = 5 cycles)
                    // The core starts computing automatically after B is loaded.
                    // It takes 1 cycle to compute and then starts outputting on the next cycle.
                    // The first result is available on uo_out 1 cycle after compute state.
                    // The core's output state takes 4 cycles.
                    // We need to wait until the *first* result is ready.
                    // Core states after Load B: COMPUTE (1 cycle), OUTPUT (cycle 0) -> result C00 ready
                    // So we need to wait 1 cycle after S_LOAD_B finishes.
                    // Let's wait a fixed number of cycles corresponding to the core's compute + output phase.
                    // Core FSM: INPUT_A(4) -> INPUT_B(4) -> COMPUTE(1) -> OUTPUT(4)
                    // After S_LOAD_B, core is at start of COMPUTE.
                    // Wait 1 (COMPUTE) + 4 (OUTPUT) = 5 cycles total.
                    if (wait_count == 4) begin // Wait 5 cycles (0 to 4)
                        wait_count <= 0;
                        byte_count <= 0; // Reset for reading C
                        state <= S_READ_C;
                    end else begin
                        wait_count <= wait_count + 1;
                    end
                end

                S_READ_C: begin // Read C from core over 4 cycles
                    // Core should be in its OUTPUT state, presenting results sequentially.
                    matrix_C[byte_count] <= core_uo_out;
                    if (byte_count == 3) begin
                        byte_count <= 0; // Reset for sending C
                        state <= S_SEND_C;
                    end else begin
                        byte_count <= byte_count + 1;
                    end
                end

                S_SEND_C: begin // Send C[0]..C[3] via UART
                    if (!tx_busy) begin // Ready to send next byte?
                        tx_data <= matrix_C[byte_count];
                        tx_start <= 1; // Pulse start high for one cycle
                        if (byte_count == 3) begin
                            byte_count <= 0;
                            state <= S_IDLE; // Done, wait for next transaction
                        end else begin
                            byte_count <= byte_count + 1;
                            // tx_start will be low next cycle automatically
                        end
                    end
                    // else: wait for tx_busy to go low
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule