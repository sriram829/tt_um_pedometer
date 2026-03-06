# FPGA Implementation — DE10-Lite Pedometer SPI

## Board
Intel MAX10 DE10-Lite (10M50DAF484C7G)

## Files
| File | Description |
|------|-------------|
| src/top_pedometer.v | Top-level FPGA design |
| src/tt_um_pedometer.v | TT wrapper |
| src/pedometer_core.v | Pedometer RTL core |
| src/my_pll.v | PLL implementation |
| src/my_pll_bb.v | PLL black box |
| constraints/top_pedometer.qsf | Pin assignments |
| constraints/my_pll.qip | PLL IP core |
| constraints/pins.tcl | TCL pin script |

## How to Compile
1. Open Quartus Prime
2. File → Open Project → constraints/top_pedometer.qpf
3. Add all src/*.v files
4. Processing → Start Compilation
5. Program DE10-Lite via USB-Blaster

## Demo Operation
| Signal | Function |
|--------|----------|
| HEX0-1 | Step count decimal |
| LEDR[8] | Step detected LED |
| LEDR[9] | Artifact flag |
| KEY[0] | Reset counter |
| SW[9] | Toggle display mode |
