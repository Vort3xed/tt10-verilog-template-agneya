# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer, RisingEdge, FallingEdge, First

# --- UART Configuration ---
# Match the CLKS_PER_BIT_PARAM in project.v for simulation
# For 100kHz clock and 9600 baud, CLKS_PER_BIT = 100_000 / 9600 = 10.4 => Use 10
# Clock period is 10us = 10000 ns
# Bit period = 1 / 9600 s = 104166.67 ns
# Number of clocks per bit = 104166.67 ns / 10000 ns = 10.4 clocks => Use 10
CLKS_PER_BIT = 10
CLK_PERIOD_NS = 10000 # 10us clock
BIT_PERIOD_NS = CLK_PERIOD_NS * CLKS_PER_BIT # ~100us

# --- UART Helper Functions ---

async def uart_send_byte(dut, byte_to_send):
    """Sends a byte over the simulated UART TX line (dut.tb_rx)."""
    dut._log.info(f"UART TX: Sending byte 0x{byte_to_send:02X}")
    dut.tb_rx.value = 1 # Ensure idle state initially

    # Start bit
    dut.tb_rx.value = 0
    await Timer(BIT_PERIOD_NS, units="ns")

    # Data bits (LSB first)
    for i in range(8):
        bit = (byte_to_send >> i) & 1
        dut.tb_rx.value = bit
        await Timer(BIT_PERIOD_NS, units="ns")

    # Stop bit
    dut.tb_rx.value = 1
    await Timer(BIT_PERIOD_NS, units="ns")
    dut._log.info(f"UART TX: Byte 0x{byte_to_send:02X} sent")

async def uart_receive_byte(dut, timeout_ns=BIT_PERIOD_NS * 15):
    """Receives a byte from the simulated UART RX line (dut.tb_tx)."""
    dut._log.info("UART RX: Waiting for byte...")
    received_byte = 0
    start_edge = FallingEdge(dut.tb_tx) # Wait for start bit

    try:
        # Wait for the start bit (falling edge) or timeout
        await First(start_edge, Timer(timeout_ns, units="ns"))

        if dut.tb_tx.value != 0:
             dut._log.error("UART RX: Timeout or glitch waiting for start bit.")
             return None

        # Wait half a bit period to sample in the middle of the start bit
        await Timer(BIT_PERIOD_NS / 2, units="ns")
        if dut.tb_tx.value != 0:
            dut._log.error("UART RX: False start bit detected.")
            return None

        # Wait another half bit period to align with the start of the first data bit
        await Timer(BIT_PERIOD_NS / 2, units="ns")

        # Read data bits (LSB first)
        for i in range(8):
            # Sample in the middle of the bit period
            await Timer(BIT_PERIOD_NS / 2, units="ns")
            bit = int(dut.tb_tx.value)
            received_byte |= (bit << i)
            # Wait remaining half bit period
            await Timer(BIT_PERIOD_NS / 2, units="ns")

        # Wait for stop bit (should be high)
        await Timer(BIT_PERIOD_NS / 2, units="ns") # Sample middle of stop bit
        if dut.tb_tx.value != 1:
            dut._log.warning("UART RX: Stop bit was not high.")
        await Timer(BIT_PERIOD_NS / 2, units="ns") # Finish stop bit period

        dut._log.info(f"UART RX: Received byte 0x{received_byte:02X}")
        return received_byte

    except Exception as e:
        dut._log.error(f"UART RX: Error during reception: {e}")
        # Attempt to read the final value in case of timeout during data/stop bit
        try:
            final_val = int(dut.tb_tx.value)
            dut._log.info(f"UART RX: Final TX value was {final_val}")
        except ValueError:
             dut._log.info(f"UART RX: Final TX value was not an integer (e.g., 'X')")
        return None


# --- Main Test ---

@cocotb.test()
async def test_matrix_mult_uart(dut):
    dut._log.info("Starting UART matrix multiplication test")

    # Note: Clock and Reset are handled by tb.v initial blocks

    # Wait for reset to deassert and ena to assert
    await RisingEdge(dut.rst_n)
    await RisingEdge(dut.ena)
    await ClockCycles(dut.clk, 5) # Give some time after enable

    dut._log.info("Design reset and enabled.")

    # Test data
    matrix_A = [1, 2, 3, 4]  # First matrix values
    matrix_B = [5, 6, 7, 8]  # Second matrix values
    expected_results = [19, 22, 43, 50]  # Expected multiplication results (truncated)

    # Send matrix A over UART
    dut._log.info("Sending matrix A...")
    for byte_val in matrix_A:
        await uart_send_byte(dut, byte_val)
        await ClockCycles(dut.clk, 5) # Small delay between bytes

    # Send matrix B over UART
    dut._log.info("Sending matrix B...")
    for byte_val in matrix_B:
        await uart_send_byte(dut, byte_val)
        await ClockCycles(dut.clk, 5) # Small delay between bytes

    # Receive results
    dut._log.info("Receiving results...")
    results = []
    for i in range(4):
        dut._log.info(f"Waiting for result byte {i+1}...")
        # Increase timeout significantly as computation takes time
        received = await uart_receive_byte(dut, timeout_ns=BIT_PERIOD_NS * 50)
        if received is None:
            dut._log.error(f"Failed to receive result byte {i+1}")
            break
        results.append(received)
        await ClockCycles(dut.clk, 5) # Small delay

    # Verification
    dut._log.info(f"Expected: {expected_results}")
    dut._log.info(f"Received: {results}")
    assert results == expected_results, f"Test failed! Expected {expected_results}, got {results}"

    dut._log.info("UART Matrix multiplication test passed!")
    await ClockCycles(dut.clk, 20) # Finish simulation gracefully