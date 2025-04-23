import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer, RisingEdge, FallingEdge, First
import random

# --- UART Helper Functions ---

CLOCK_FREQ = 100_000 # Hz (Must match Verilog)
BAUD_RATE = 5_000    # Baud (Must match Verilog)
# Ensure integer division for CLKS_PER_BIT
CLKS_PER_BIT = CLOCK_FREQ // BAUD_RATE
# Check if CLKS_PER_BIT is reasonable
if CLKS_PER_BIT < 10:
    cocotb.log.warning(f"CLKS_PER_BIT ({CLKS_PER_BIT}) is low. UART timing might be inaccurate.")
CLK_PERIOD_NS = int(1_000_000_000 / CLOCK_FREQ)

async def uart_write_byte(dut, byte_val):
    """Writes a byte serially to dut.ui_in[0]"""
    dut._log.debug(f"UART TX: Sending byte {byte_val} (0x{byte_val:02X})")
    # Idle high
    dut.ui_in[0].value = 1
    await ClockCycles(dut.clk, 2) # Ensure idle state

    # Start bit (low)
    dut.ui_in[0].value = 0
    await ClockCycles(dut.clk, CLKS_PER_BIT)

    # Data bits (LSB first)
    for i in range(8):
        bit = (byte_val >> i) & 1
        dut.ui_in[0].value = bit
        await ClockCycles(dut.clk, CLKS_PER_BIT)

    # Stop bit (high)
    dut.ui_in[0].value = 1
    await ClockCycles(dut.clk, CLKS_PER_BIT)
    dut._log.debug(f"UART TX: Byte {byte_val} sent")


async def uart_read_byte(dut):
    """Reads a byte serially from dut.uo_out[0]"""
    dut._log.debug("UART RX: Waiting for start bit...")
    # Wait for start bit (falling edge on uo_out[0])
    await FallingEdge(dut.uo_out[0])
    dut._log.debug("UART RX: Start bit detected (Falling Edge)")

    # Wait half a bit period to sample middle of start bit
    await Timer(CLK_PERIOD_NS * CLKS_PER_BIT / 2, units="ns")
    if int(dut.uo_out[0].value) != 0:
         # Use assert for failure
         assert False, "UART RX Error: Start bit not low after falling edge and half bit delay"

    # Wait until the middle of the first data bit (another full bit period)
    await Timer(CLK_PERIOD_NS * CLKS_PER_BIT, units="ns")

    byte_val = 0
    # Read data bits (LSB first)
    for i in range(8):
        bit = int(dut.uo_out[0].value)
        byte_val |= (bit << i)
        dut._log.debug(f"UART RX: Read data bit {i}: {bit}")
        # Wait for the middle of the next bit
        await Timer(CLK_PERIOD_NS * CLKS_PER_BIT, units="ns")


    # At this point, we should be in the middle of the stop bit period
    stop_bit = int(dut.uo_out[0].value)
    dut._log.debug(f"UART RX: Read stop bit: {stop_bit}")
    if stop_bit != 1:
        # Use assert for failure
        assert False, f"UART RX Error: Stop bit not high (got {stop_bit})"

    dut._log.info(f"UART RX: Received byte {byte_val} (0x{byte_val:02X})")

    # Wait for the rest of the stop bit period to finish before returning
    await Timer(CLK_PERIOD_NS * CLKS_PER_BIT / 2, units="ns")
    return byte_val

# --- Test ---

@cocotb.test()
async def test_matrix_mult_uart(dut):
    dut._log.info("Starting UART matrix multiplication test")

    # Clock matches Verilog tb parameter
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())

    # Reset is handled by Verilog tb
    dut._log.info("Waiting for reset release")
    await RisingEdge(dut.rst_n)
    # Initialize UART input to idle high after reset
    dut.ui_in[0].value = 1
    await ClockCycles(dut.clk, 5) # Allow things to settle

    # --- Input Data ---
    matrix_a = [1, 2, 3, 4]
    matrix_b = [5, 6, 7, 8]
    # C = A * B
    # C00 = A0*B0 + A1*B2 = 1*5 + 2*7 = 5 + 14 = 19
    # C01 = A0*B1 + A1*B3 = 1*6 + 2*8 = 6 + 16 = 22
    # C10 = A2*B0 + A3*B2 = 3*5 + 4*7 = 15 + 28 = 43
    # C11 = A2*B1 + A3*B3 = 3*6 + 4*8 = 18 + 32 = 50
    expected_c = [19, 22, 43, 50] # Expected results (8-bit truncated)

    # --- Send Matrices via UART ---
    dut._log.info("Sending Matrix A via UART")
    for val in matrix_a:
        await uart_write_byte(dut, val)

    dut._log.info("Sending Matrix B via UART")
    for val in matrix_b:
        await uart_write_byte(dut, val)

    # --- Receive Result Matrix via UART ---
    dut._log.info("Waiting to receive Matrix C via UART")
    results_c = []
    try:
        # Define the timeout duration (e.g., time for ~20 bytes)
        timeout_duration_ns = CLK_PERIOD_NS * CLKS_PER_BIT * 10 * 20 # 1 start + 8 data + 1 stop = 10 bits
        timeout_timer = Timer(timeout_duration_ns, units="ns")

        for i in range(4): # Expecting 4 bytes for matrix C
            dut._log.info(f"Waiting for result byte {i+1}...")
            # Start the read operation
            read_task = cocotb.start_soon(uart_read_byte(dut))
            # Wait for either the read task or the timeout timer
            trigger = await First(read_task, timeout_timer)

            if trigger is timeout_timer:
                # Timeout occurred
                assert False, f"Timeout waiting for UART RX byte {i+1}"
            elif trigger is read_task:
                # Task completed successfully
                results_c.append(read_task.result())
            else:
                 # Should not happen with First
                 assert False, "Unexpected trigger result from First"

    except Exception as e:
         dut._log.error(f"Error during UART read: {e}")
         # Use assert False for failure
         assert False, f"UART Read failed: {e}"

    # --- Verification ---
    dut._log.info(f"Received Matrix C: {results_c}")
    assert results_c == expected_c, f"Matrix multiplication failed. Expected {expected_c}, got {results_c}"

    dut._log.info("UART Matrix multiplication test passed!")

    # Add a small delay at the end
    await ClockCycles(dut.clk, 20)