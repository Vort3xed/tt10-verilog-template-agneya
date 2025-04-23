import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer

@cocotb.test()
async def test_matrix_mult(dut):
    dut._log.info("Starting matrix multiplication test")

    # clock with 10us period (100 KHz)
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    # reset
    dut._log.info("Applying reset")
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    # Send matrices over UART
    # Assuming UART communication is implemented
    # For example, sending matrix A
    for value in [1, 2, 3, 4]:
        await send_uart(dut, value)
    dut._log.info("Matrix A sent")

    # Send matrix B
    for value in [5, 6, 7, 8]:
        await send_uart(dut, value)
    dut._log.info("Matrix B sent")

    # Wait for computation or something
    await ClockCycles(dut.clk, 2)

    # Expected outputs: 19, 22, 43, 50 (lower 8 bits of each sum)
    expected = [19, 22, 43, 50]
    results = []

    for i in range(4):
        await ClockCycles(dut.clk, 1)
        result = int(dut.uo_out.value)
        results.append(result)
        dut._log.info(f"Cycle {i} output: {result}")

    assert results == expected, f"Matrix multiplication failed. Expected {expected}, got {results}"

    dut._log.info("Matrix multiplication test passed!")

async def send_uart(dut, value):
    # Implement UART send logic here
    dut.uart_tx.value = value
    await Timer(1, units='us')  # Simulate UART transmission delay