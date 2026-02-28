# SPDX-FileCopyrightText: © 2024 Dr. Sriram Anbalagan, SASTRA Deemed University
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge, Timer

async def send_spi_frame(dut, x_val, y_val, z_val):
    """Send 48-bit SPI frame: X(16bit) + Y(16bit) + Z(16bit)"""
    # Pack into 48-bit frame
    x = x_val & 0xFFFF
    y = y_val & 0xFFFF
    z = z_val & 0xFFFF
    frame = (x << 32) | (y << 16) | z

    # CS low — start frame
    dut.ui_in.value = 0b00000000  # CS=0, CLK=0, MOSI=0
    await Timer(100, units="us")

    # Send 48 bits MSB first
    for i in range(47, -1, -1):
        bit = (frame >> i) & 1
        # CLK low, set MOSI
        dut.ui_in.val
cat > test/test.py << 'ENDOFFILE'
# SPDX-FileCopyrightText: © 2024 Dr. Sriram Anbalagan, SASTRA Deemed University
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge, Timer

async def send_spi_frame(dut, x_val, y_val, z_val):
    """Send 48-bit SPI frame: X(16bit) + Y(16bit) + Z(16bit)"""
    # Pack into 48-bit frame
    x = x_val & 0xFFFF
    y = y_val & 0xFFFF
    z = z_val & 0xFFFF
    frame = (x << 32) | (y << 16) | z

    # CS low — start frame
    dut.ui_in.value = 0b00000000  # CS=0, CLK=0, MOSI=0
    await Timer(100, units="us")

    # Send 48 bits MSB first
    for i in range(47, -1, -1):
        bit = (frame >> i) & 1
        # CLK low, set MOSI
        dut.ui_in.value = (bit << 1) | 0b00000000  # MOSI=bit, CLK=0, CS=0
        await Timer(60, units="us")
        # CLK high — sample
        dut.ui_in.value = (bit << 1) | 0b00000001  # CLK=1
        await Timer(60, units="us")

    # CLK low
    dut.ui_in.value = 0b00000000
    await Timer(100, units="us")
    # CS high — end frame, latch data
    dut.ui_in.value = 0b00000100  # CS=1
    await Timer(500, units="us")

async def read_step_count(dut):
    """Read 16-bit step count via byte_sel"""
    # Read low byte
    dut.ui_in.value = 0b00000100  # byte_sel=0, CS=1
    await Timer(100, units="us")
    low = dut.uo_out.value.integer

    # Read high byte
    dut.ui_in.value = 0b00001100  # byte_sel=1, CS=1
    await Timer(100, units="us")
    high = dut.uo_out.value.integer

    return (high << 8) | low

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start — Ultra Low Power Pedometer ASIC")
    dut._log.info("Dr. Sriram Anbalagan, SASTRA Deemed University")

    # 32.768 kHz clock
    clock = Clock(dut.clk, 30517, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.ena.value = 1
    dut.ui_in.value = 0b00000100  # CS high
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    dut._log.info("Reset released")

    # TEST 1: Normal Walking — 5 steps
    dut._log.info("TEST 1: Normal Walking")
    for step in range(5):
        # Send 8 peak frames
        for _ in range(8):
            await send_spi_frame(dut, 100, 150, 350)
        await ClockCycles(dut.clk, 500)
        # Send 8 rest frames
        for _ in range(8):
            await send_spi_frame(dut, 10, 10, 20)
        await ClockCycles(dut.clk, 200)

    count = await read_step_count(dut)
    dut._log.info(f"Step count = {count}")
    assert count > 0, f"Expected steps > 0, got {count}"
    dut._log.info(f"TEST 1 PASSED — {count} steps detected")

    # TEST 2: IO Enable Check
    dut._log.info("TEST 2: IO Enable Check")
    assert dut.uio_oe.value == 0x03, f"Expected uio_oe=0x03, got {dut.uio_oe.value}"
    dut._log.info("TEST 2 PASSED — uio_oe = 0x03")

    dut._log.info("ALL TESTS PASSED ✅")
