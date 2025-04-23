# README.md

# tt10 Verilog Matrix Multiplication Project

This project implements a Verilog module for multiplying two 2x2 matrices and communicates with a host computer via UART. The design is intended to be synthesized for the Arty A7 35T FPGA board.

## Project Structure

The project consists of the following files:

- **src/project.v**: Contains the Verilog module `tt_um_2x2MatrixMult_Vort3xed`, which performs the multiplication of two 2x2 matrices. It includes input ports for the matrices, a clock, a reset signal, and UART communication ports for sending and receiving data.

- **src/tt_generic_wrapper.v**: A wrapper for the `tt_um_2x2MatrixMult_Vort3xed` module. It handles the clock signal and bidirectional I/O for the Arty A7 board, as well as UART communication.

- **test/Makefile**: Contains the build instructions for the simulation environment using Cocotb. It specifies the simulator, source directories, and includes the necessary make rules for running the tests.

- **test/test.py**: The Cocotb testbench for evaluating the functionality of the matrix multiplication module. It includes tests for sending matrices over UART and verifying the output.

- **test/tb.v**: The testbench that instantiates the matrix multiplication module and connects the signals. It is updated to include the UART interface.

## Setup Instructions

1. **Install Dependencies**: Ensure you have the necessary tools installed, including a simulator compatible with Cocotb (e.g., Icarus Verilog) and Python with the Cocotb library.

2. **Clone the Repository**: Clone this repository to your local machine.

3. **Build the Project**: Navigate to the `test` directory and run the following command to build the project:
   ```
   make
   ```

4. **Run the Tests**: Execute the tests using the following command:
   ```
   make sim
   ```

## Usage Guidelines

- Connect the Arty A7 board to your computer via USB.
- Use a serial monitor to send the two 2x2 matrices to the FPGA over UART.
- The FPGA will compute the product of the matrices and send the results back to the computer.

## Notes

- Ensure that the UART settings (baud rate, data bits, stop bits) match between the host computer and the FPGA.
- The design has been tested in simulation using Cocotb, and it is expected to work on the physical hardware as well.

## License

This project is licensed under the Apache-2.0 License. See the LICENSE file for more details.