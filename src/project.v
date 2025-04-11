/*
 * Copyright (c) 2024 Agneya Tharun 
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_2x2MatrixMult_Vort3xed (
    input  wire [7:0] ui_in,    // Input for data (UART RX connects to ui_in[0])
    output wire [7:0] uo_out,   // Output for data (UART TX connects to uo_out[0])
    input  wire [7:0] uio_in,   // Input for additional data if needed
    output wire [7:0] uio_out,  // (Unused)
    output wire [7:0] uio_oe,   // (Unused)
    input  wire       ena,      // always 1 when design powered
    input  wire       clk,      // clock
    input  wire       rst_n     // active-low reset
);

  // Unused outputs fixed to 0.
  assign uio_out = 0;
  assign uio_oe  = 0;

  // UART Parameters - CRITICAL: Match these to your test.py settings!
  parameter CLOCK_RATE = 10_000_000;  // 10 MHz for simulation
  parameter BAUD_RATE = 115200;       // Higher baud rate for simulation
  parameter CLOCKS_PER_BIT = CLOCK_RATE / BAUD_RATE;

  // Internal state definitions for the main state machine
  localparam IDLE = 0,
             RECV_A0 = 1,
             RECV_A1 = 2,
             RECV_A2 = 3,
             RECV_A3 = 4,
             RECV_B0 = 5,
             RECV_B1 = 6,
             RECV_B2 = 7,
             RECV_B3 = 8,
             COMPUTE = 9,
             SEND_C00 = 10,
             WAIT_C00 = 11,
             SEND_C01 = 12,
             WAIT_C01 = 13,
             SEND_C10 = 14,
             WAIT_C10 = 15,
             SEND_C11 = 16,
             WAIT_C11 = 17,
             DONE = 18;

  reg [4:0] state;
  reg [7:0] A0, A1, A2, A3;    // Elements for matrix A (rowwise order)
  reg [7:0] B0, B1, B2, B3;    // Elements for matrix B (rowwise order)
  
  // Use 16-bit registers for intermediate calculations to prevent overflow
  reg [15:0] calc_temp;
  reg [7:0] C00, C01, C10, C11; // Result matrix
  
  // UART signals
  wire       rx_data_valid;
  wire [7:0] rx_byte;
  reg        tx_start;
  reg  [7:0] tx_byte;
  wire       tx_busy;
  wire       tx_done;
  
  // Debug counter to ensure we wait enough cycles
  reg [7:0] wait_counter;
  
  // UART Receive module
  uart_rx #(
    .CLOCKS_PER_BIT(CLOCKS_PER_BIT)
  ) uart_rx_inst (
    .i_Clock(clk),
    .i_Rx_Serial(ui_in[0]),
    .o_Rx_DV(rx_data_valid),
    .o_Rx_Byte(rx_byte),
    .i_Rst_L(rst_n)
  );
  
  // UART Transmit module
  uart_tx #(
    .CLOCKS_PER_BIT(CLOCKS_PER_BIT)
  ) uart_tx_inst (
    .i_Clock(clk),
    .i_Tx_DV(tx_start),
    .i_Tx_Byte(tx_byte),
    .o_Tx_Active(tx_busy),
    .o_Tx_Serial(uo_out[0]),
    .o_Tx_Done(tx_done),
    .i_Rst_L(rst_n)
  );
  
  // Drive remaining output bits to 0
  assign uo_out[7:1] = 7'b0;

  // Matrix multiplication state machine
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      A0 <= 0; A1 <= 0; A2 <= 0; A3 <= 0;
      B0 <= 0; B1 <= 0; B2 <= 0; B3 <= 0;
      C00 <= 0; C01 <= 0; C10 <= 0; C11 <= 0;
      tx_start <= 0;
      tx_byte <= 0;
      calc_temp <= 0;
      wait_counter <= 0;
    end else begin
      // Default: tx_start is one-cycle pulse
      tx_start <= 0;
      
      case (state)
        IDLE: begin
          if (rx_data_valid) begin
            // Start byte received, transition to receiving matrix A
            state <= RECV_A0;
          end
        end
        
        RECV_A0: begin
          if (rx_data_valid) begin
            A0 <= rx_byte;
            state <= RECV_A1;
          end
        end
        
        RECV_A1: begin
          if (rx_data_valid) begin
            A1 <= rx_byte;
            state <= RECV_A2;
          end
        end
        
        RECV_A2: begin
          if (rx_data_valid) begin
            A2 <= rx_byte;
            state <= RECV_A3;
          end
        end
        
        RECV_A3: begin
          if (rx_data_valid) begin
            A3 <= rx_byte;
            state <= RECV_B0;
          end
        end
        
        RECV_B0: begin
          if (rx_data_valid) begin
            B0 <= rx_byte;
            state <= RECV_B1;
          end
        end
        
        RECV_B1: begin
          if (rx_data_valid) begin
            B1 <= rx_byte;
            state <= RECV_B2;
          end
        end
        
        RECV_B2: begin
          if (rx_data_valid) begin
            B2 <= rx_byte;
            state <= RECV_B3;
          end
        end
        
        RECV_B3: begin
          if (rx_data_valid) begin
            B3 <= rx_byte;
            state <= COMPUTE;
          end
        end
        
        COMPUTE: begin
          // Matrix multiplication with careful calculations:
          // C00 = A0*B0 + A1*B2
          calc_temp <= A0 * B0;
          C00 <= (A0 * B0 + A1 * B2);
          
          // C01 = A0*B1 + A1*B3
          C01 <= (A0 * B1 + A1 * B3);
          
          // C10 = A2*B0 + A3*B2
          C10 <= (A2 * B0 + A3 * B2);
          
          // C11 = A2*B1 + A3*B3
          C11 <= (A2 * B1 + A3 * B3);
          
          state <= SEND_C00;
          wait_counter <= 0;
        end
        
        SEND_C00: begin
          if (!tx_busy) begin
            tx_byte <= C00;
            tx_start <= 1;  // Set tx_start high for one cycle
            state <= WAIT_C00;
            wait_counter <= 0;
          end
        end
        
        WAIT_C00: begin
          // Wait for transmission to complete
          if (wait_counter < 200) begin
            wait_counter <= wait_counter + 1;
          end else begin
            state <= SEND_C01;
            wait_counter <= 0;
          end
        end
        
        SEND_C01: begin
          if (!tx_busy) begin
            tx_byte <= C01;
            tx_start <= 1;
            state <= WAIT_C01;
            wait_counter <= 0;
          end
        end
        
        WAIT_C01: begin
          if (wait_counter < 200) begin
            wait_counter <= wait_counter + 1;
          end else begin
            state <= SEND_C10;
            wait_counter <= 0;
          end
        end
        
        SEND_C10: begin
          if (!tx_busy) begin
            tx_byte <= C10;
            tx_start <= 1;
            state <= WAIT_C10;
            wait_counter <= 0;
          end
        end
        
        WAIT_C10: begin
          if (wait_counter < 200) begin
            wait_counter <= wait_counter + 1;
          end else begin
            state <= SEND_C11;
            wait_counter <= 0;
          end
        end
        
        SEND_C11: begin
          if (!tx_busy) begin
            tx_byte <= C11;
            tx_start <= 1;
            state <= WAIT_C11;
            wait_counter <= 0;
          end
        end
        
        WAIT_C11: begin
          if (wait_counter < 200) begin
            wait_counter <= wait_counter + 1;
          end else begin
            state <= DONE;
          end
        end
        
        DONE: begin
          state <= IDLE;  // Return to IDLE to process another matrix if needed
        end
        
        default: state <= IDLE;
      endcase
    end
  end

  // List all unused input signals to prevent warnings
  wire _unused = &{ena, uio_in, ui_in[7:1]};

endmodule

// UART Receiver Module
module uart_rx #(
  parameter CLOCKS_PER_BIT = 87  // 10MHz/115200 baud
) (
  input        i_Clock,
  input        i_Rx_Serial,
  output reg   o_Rx_DV,
  output reg [7:0] o_Rx_Byte,
  input        i_Rst_L
);

  localparam IDLE = 0,
             START_BIT = 1,
             DATA_BITS = 2,
             STOP_BIT = 3,
             CLEANUP = 4;
  
  reg [2:0] state;
  reg [$clog2(CLOCKS_PER_BIT):0] clock_count;
  reg [2:0] bit_index;
  reg rx_data;
  
  // Double-register the serial input for metastability
  reg rx_data1;
  
  always @(posedge i_Clock or negedge i_Rst_L) begin
    if (!i_Rst_L) begin
      state <= IDLE;
      clock_count <= 0;
      bit_index <= 0;
      o_Rx_Byte <= 0;
      o_Rx_DV <= 0;
      rx_data <= 1;
      rx_data1 <= 1;
    end else begin
      // Always synchronize input
      rx_data1 <= i_Rx_Serial;
      rx_data <= rx_data1;
      
      // Default state for data valid (one-cycle pulse)
      o_Rx_DV <= 0;
      
      case (state)
        IDLE: begin
          bit_index <= 0;
          clock_count <= 0;
          
          if (rx_data == 0) begin  // Start bit detected
            state <= START_BIT;
          end
        end
        
        START_BIT: begin
          // Wait half of one bit time to sample in the middle
          if (clock_count == (CLOCKS_PER_BIT-1)/2) begin
            if (rx_data == 0) begin  // Confirm start bit is still low
              clock_count <= 0;
              state <= DATA_BITS;
            end else begin
              state <= IDLE;  // False start
            end
          end else begin
            clock_count <= clock_count + 1;
          end
        end
        
        DATA_BITS: begin
          if (clock_count < CLOCKS_PER_BIT-1) begin
            clock_count <= clock_count + 1;
          end else begin
            clock_count <= 0;
            o_Rx_Byte[bit_index] <= rx_data;  // Sample bit
            
            if (bit_index < 7) begin
              bit_index <= bit_index + 1;
            end else begin
              bit_index <= 0;
              state <= STOP_BIT;
            end
          end
        end
        
        STOP_BIT: begin
          if (clock_count < CLOCKS_PER_BIT-1) begin
            clock_count <= clock_count + 1;
          end else begin
            o_Rx_DV <= 1;  // Byte received successfully
            clock_count <= 0;
            state <= CLEANUP;
          end
        end
        
        CLEANUP: begin
          state <= IDLE;
        end
        
        default: state <= IDLE;
      endcase
    end
  end
  
endmodule

// UART Transmitter Module
module uart_tx #(
  parameter CLOCKS_PER_BIT = 87  // 10MHz/115200 baud
) (
  input      i_Clock,
  input      i_Tx_DV,
  input [7:0] i_Tx_Byte, 
  output     o_Tx_Active,
  output reg o_Tx_Serial,
  output     o_Tx_Done,
  input      i_Rst_L
);
  
  localparam IDLE = 0,
             START_BIT = 1,
             DATA_BITS = 2,
             STOP_BIT = 3,
             CLEANUP = 4;
  
  reg [2:0] state;
  reg [$clog2(CLOCKS_PER_BIT):0] clock_count;
  reg [2:0] bit_index;
  reg [7:0] tx_data;
  reg tx_active;
  reg tx_done;
    
  always @(posedge i_Clock or negedge i_Rst_L) begin
    if (!i_Rst_L) begin
      state <= IDLE;
      clock_count <= 0;
      bit_index <= 0;
      tx_data <= 0;
      tx_done <= 0;
      tx_active <= 0;
      o_Tx_Serial <= 1;  // Line high when idle
    end else begin
      case (state)
        IDLE: begin
          o_Tx_Serial <= 1;  // Line high when idle
          tx_done <= 0;
          clock_count <= 0;
          bit_index <= 0;
          
          if (i_Tx_DV) begin
            tx_active <= 1;
            tx_data <= i_Tx_Byte;
            state <= START_BIT;
          end
        end
        
        START_BIT: begin
          o_Tx_Serial <= 0;  // Start bit (low)
          
          if (clock_count < CLOCKS_PER_BIT-1) begin
            clock_count <= clock_count + 1;
          end else begin
            clock_count <= 0;
            state <= DATA_BITS;
          end
        end
        
        DATA_BITS: begin
          o_Tx_Serial <= tx_data[bit_index];  // Output bit
          
          if (clock_count < CLOCKS_PER_BIT-1) begin
            clock_count <= clock_count + 1;
          end else begin
            clock_count <= 0;
            
            if (bit_index < 7) begin
              bit_index <= bit_index + 1;
            end else begin
              bit_index <= 0;
              state <= STOP_BIT;
            end
          end
        end
        
        STOP_BIT: begin
          o_Tx_Serial <= 1;  // Stop bit (high)
          
          if (clock_count < CLOCKS_PER_BIT-1) begin
            clock_count <= clock_count + 1;
          end else begin
            tx_done <= 1;
            clock_count <= 0;
            state <= CLEANUP;
            tx_active <= 0;
          end
        end
        
        CLEANUP: begin
          tx_done <= 0;
          state <= IDLE;
        end
        
        default: state <= IDLE;
      endcase
    end
  end
  
  assign o_Tx_Active = tx_active;
  assign o_Tx_Done = tx_done;
endmodule