# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge, Timer

async def uart_tx(dut, byte, baud_rate=115200, clk_freq=10_000_000):
    """Send a byte over UART to the design."""
    bit_time = int(clk_freq / baud_rate)
    
    # Start bit (low)
    dut._log.info(f"UART TX: Sending byte 0x{byte:02x}, start bit")
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, bit_time)
    
    # Data bits (LSB first)
    for i in range(8):
        bit = (byte >> i) & 1
        dut._log.info(f"UART TX: Bit {i} = {bit}")
        dut.ui_in.value = bit
        await ClockCycles(dut.clk, bit_time)
    
    # Stop bit (high)
    dut._log.info(f"UART TX: Stop bit")
    dut.ui_in.value = 1
    await ClockCycles(dut.clk, bit_time)
    
    # Additional idle time
    await ClockCycles(dut.clk, bit_time)

async def uart_rx(dut, timeout_ms=500, baud_rate=115200, clk_freq=10_000_000):
    """Receive a byte over UART from the design with improved timeout handling."""
    bit_time = int(clk_freq / baud_rate)
    timeout_cycles = int((timeout_ms * clk_freq) / 1000)  # Convert ms to cycles
    
    # Wait for start bit (falling edge on TX)
    for _ in range(timeout_cycles):
        if dut.uo_out.value & 1 == 0:
            dut._log.info(f"UART RX: Start bit detected")
            break
        await ClockCycles(dut.clk, 1)
    else:
        dut._log.error(f"UART RX: Timeout waiting for start bit after {timeout_ms}ms")
        return None
    
    # Wait one bit time to reach middle of start bit
    await ClockCycles(dut.clk, bit_time)
    
    # Read 8 data bits
    data = 0
    for i in range(8):
        bit = dut.uo_out.value & 1
        dut._log.info(f"UART RX: Bit {i} = {bit}")
        data |= (bit << i)
        await ClockCycles(dut.clk, bit_time)
    
    # Check stop bit
    stop_bit = dut.uo_out.value & 1
    dut._log.info(f"UART RX: Stop bit = {stop_bit}")
    if stop_bit != 1:
        dut._log.warning(f"UART RX: Invalid stop bit: {stop_bit}")
    
    dut._log.info(f"UART RX: Received byte 0x{data:02x}")
    return data

@cocotb.test()
async def test_uart_matrix_mult(dut):
    dut._log.info("Starting UART matrix multiplication test")

    # Use 10MHz clock for simulation
    clock_freq_mhz = 10
    clock_period_ns = 1000/clock_freq_mhz
    baud_rate = 115200
    
    clock = Clock(dut.clk, clock_period_ns, units="ns")
    cocotb.start_soon(clock.start())

    # Enable the design
    dut.ena.value = 1

    # Reset
    dut._log.info("Applying reset")
    dut.rst_n.value = 0
    dut.ui_in.value = 1  # UART idle state is high
    await ClockCycles(dut.clk, 20)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 20)

    # Define test matrices: A = [1,2;3,4] and B = [5,6;7,8]
    matrix_A = [1, 2, 3, 4]
    matrix_B = [5, 6, 7, 8]
    expected_results = [19, 22, 43, 50]

    # Send initial byte to start the process
    dut._log.info("Sending start byte")
    await uart_tx(dut, 0xFF, baud_rate, clock_freq_mhz*1_000_000)
    await ClockCycles(dut.clk, 200)  # Wait longer for processing
    
    # Send matrix A with increased delays
    dut._log.info("Sending matrix A")
    for i, value in enumerate(matrix_A):
        dut._log.info(f"Sending A[{i}] = {value}")
        await uart_tx(dut, value, baud_rate, clock_freq_mhz*1_000_000)
        await ClockCycles(dut.clk, 200)  # Increased delay between transmissions
    
    # Send matrix B with increased delays
    dut._log.info("Sending matrix B")
    for i, value in enumerate(matrix_B):
        dut._log.info(f"Sending B[{i}] = {value}")
        await uart_tx(dut, value, baud_rate, clock_freq_mhz*1_000_000)
        await ClockCycles(dut.clk, 200)  # Increased delay between transmissions
    
    # Wait for computation with longer delay
    dut._log.info("Waiting for computation and transmission to begin")
    await ClockCycles(dut.clk, 2000)
    
    # Receive results with longer timeout
    results = []
    dut._log.info("Receiving results")
    
    for i in range(4):
        dut._log.info(f"Waiting for result {i+1}")
        # Higher timeout (500ms) for receiving results
        result = await uart_rx(dut, timeout_ms=500, baud_rate=baud_rate, clk_freq=clock_freq_mhz*1_000_000)
        
        if result is None:
            dut._log.error(f"Failed to receive result {i+1}")
            break
            
        results.append(result)
        dut._log.info(f"Received result {i+1}: {result}")
        await ClockCycles(dut.clk, 200)  # Increased delay between receptions
    
    # Verify results
    if len(results) == 4:
        for i, (expected, actual) in enumerate(zip(expected_results, results)):
            if expected != actual:
                dut._log.error(f"Result mismatch at position {i}: expected {expected}, got {actual}")
        
        assert results == expected_results, f"Matrix multiplication failed. Expected {expected_results}, got {results}"
        dut._log.info("UART matrix multiplication test passed!")
    else:
        assert False, f"Did not receive all 4 results. Only got: {results}"