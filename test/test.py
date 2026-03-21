# SPDX-FileCopyrightText: 2024 Dr. Sriram Anbalagan, SASTRA Deemed University
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer

async def send_spi_frame(dut, x_val, y_val, z_val):
    x = x_val & 0xFFFF
    y = y_val & 0xFFFF
    z = z_val & 0xFFFF
    frame = (x << 32) | (y << 16) | z
    dut.ui_in.value = 0b00000000
    await Timer(100, units="us")
    for i in range(47, -1, -1):
        bit = (frame >> i) & 1
        dut.ui_in.value = (bit << 1)
        await Timer(60, units="us")
        dut.ui_in.value = (bit << 1) | 0b00000001
        await Timer(60, units="us")
    dut.ui_in.value = 0b00000000
    await Timer(100, units="us")
    dut.ui_in.value = 0b00000100
    await Timer(500, units="us")

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start Pedometer Test")
    clock = Clock(dut.clk, 30517, units="ns")
    cocotb.start_soon(clock.start())
    dut.ena.value = 1
    dut.ui_in.value = 0b00000100
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    dut._log.info("Reset released")
    for step in range(3):
        for _ in range(8):
            await send_spi_frame(dut, 100, 150, 350)
        await ClockCycles(dut.clk, 500)
        for _ in range(8):
            await send_spi_frame(dut, 10, 10, 20)
        await ClockCycles(dut.clk, 200)
    assert dut.uio_oe.value == 0x03
    dut._log.info("ALL TESTS PASSED")
