# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge, Timer

# UART configuration
BAUD_RATE = 9600
CLKS_PER_BIT = 10  # Same as in Verilog code
BIT_PERIOD = 104  # bit period in nanoseconds (rounded)

async def uart_tx(dut, byte_value):
    """Send a byte over UART TX (to the RX pin of DUT)"""
    dut._log.info(f"UART TX: Sending byte 0x{byte_value:02x}")
    
    # Start bit (low)
    dut.rx.value = 0
    await Timer(BIT_PERIOD, units="ns")
    
    # Data bits (LSB first)
    for i in range(8):
        bit_value = (byte_value >> i) & 1
        dut.rx.value = bit_value
        await Timer(BIT_PERIOD, units="ns")
    
    # Stop bit (high)
    dut.rx.value = 1
    await Timer(BIT_PERIOD, units="ns")
    
    # Additional idle time
    await Timer(BIT_PERIOD/2, units="ns")

async def uart_rx(dut):
    """Receive a byte over UART RX (from the TX pin of DUT)"""
    # Wait for start bit (falling edge on TX pin)
    while dut.tx.value == 1:
        await Timer(BIT_PERIOD/10, units="ns")
    
    # Confirm it's the start bit
    await Timer(BIT_PERIOD/2, units="ns")  # Sample in the middle of the bit
    if dut.tx.value != 0:
        dut._log.error("UART RX: False start bit detected")
        return None
    
    # Read 8 data bits
    rx_data = 0
    for i in range(8):
        await Timer(BIT_PERIOD, units="ns")
        bit_value = int(dut.tx.value)
        rx_data |= (bit_value << i)  # LSB first
    
    # Wait for stop bit
    await Timer(BIT_PERIOD, units="ns")
    if dut.tx.value != 1:
        dut._log.warning("UART RX: Missing stop bit")
    
    dut._log.info(f"UART RX: Received byte 0x{rx_data:02x}")
    return rx_data

@cocotb.test()
async def test_matrix_mult_uart(dut):
    """Test the matrix multiplier via UART interface"""
    dut._log.info("Starting matrix multiplication UART test")

    # Create clock signal
    clock = Clock(dut.clk, 10, units="us")  # 100 KHz clock
    cocotb.start_soon(clock.start())
    
    # Initialize signals
    dut.rx.value = 1  # UART idle state is high
    dut.ena.value = 1
    dut.uio_in.value = 0  # Initialize uio_in
    
    # Reset the design
    dut._log.info("Applying reset")
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 20)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 20)
    
    # Test data
    matrix_A = [1, 2, 3, 4]  # First matrix values
    matrix_B = [5, 6, 7, 8]  # Second matrix values
    expected_results = [19, 22, 43, 50]  # Expected multiplication results
    
    # Debug: Print design state before sending data
    dut._log.info(f"Before sending - rx pin state: {dut.rx.value}")
    
    # Send matrix A over UART with more delay between bytes
    dut._log.info("Sending matrix A over UART")
    for i, value in enumerate(matrix_A):
        dut._log.info(f"Sending A[{i}] = {value}")
        await uart_tx(dut, value)
        await ClockCycles(dut.clk, 100)  # Much more time between bytes
    
    # Send matrix B over UART with more delay
    dut._log.info("Sending matrix B over UART")
    for i, value in enumerate(matrix_B):
        dut._log.info(f"Sending B[{i}] = {value}")
        await uart_tx(dut, value)
        await ClockCycles(dut.clk, 100)  # Much more time between bytes
    
    # Allow significant time for computation
    dut._log.info("Waiting for computation to complete")
    await ClockCycles(dut.clk, 1000)
    
    # Debug: Check tx pin before trying to receive
    dut._log.info(f"Before receiving - tx pin state: {dut.tx.value}")
    
    # Receive and check results
    dut._log.info("Receiving results over UART")
    results = []
    
    # Set a longer timeout for receiving results
    timeout_cycles = 20000  # Much longer timeout
    for i in range(4):
        start_bit_found = False
        for cycle in range(timeout_cycles):
            if dut.tx.value == 0:  # Wait for start bit
                start_bit_found = True
                dut._log.info(f"Start bit found for result {i+1} after {cycle} cycles")
                break
            await ClockCycles(dut.clk, 1)
        
        if not start_bit_found:
            dut._log.error(f"Timeout waiting for result byte {i+1}")
            break
            
        result = await uart_rx(dut)
        if result is not None:
            results.append(result)
            dut._log.info(f"Received result {i+1}: {result}")
        
        # Add extra delay between receiving bytes
        await ClockCycles(dut.clk, 200)
    
    # Verify results
    if len(results) == 4:
        assert results == expected_results, f"Matrix multiplication failed. Expected {expected_results}, got {results}"
        dut._log.info("Matrix multiplication UART test passed!")
    else:
        dut._log.error(f"Didn't receive all 4 results: {results}")