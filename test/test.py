# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    dut._log.info("Test project behavior")

    # After reset, all PHT entries = WT (2'b10), prediction = 1
    # Test 1: Read prediction for pc_index=0 (no update)
    # ui_in = {2'b00, update=0, outcome=0, pc_index=0000} = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 2)
    # Expected: prediction=1, state=2'b10 -> uo_out[0]=1, uo_out[2:1]=2'b10 -> 0b00000101 = 5
    assert dut.uo_out.value == 5, f"After reset, expected uo_out=5 (WT, predict Taken), got {dut.uo_out.value}"

    # Test 2: Update pc_index=0 with outcome=Taken (should go WT->ST)
    # ui_in = {2'b00, update=1, outcome=1, pc_index=0000} = 0b00110000
    dut.ui_in.value = 0b00110000
    await ClockCycles(dut.clk, 1)
    # Deassert update after 1 cycle to avoid double-update
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 2)
    # ST(11): prediction=1, state=2'b11 -> uo_out = 0b00000111 = 7
    assert dut.uo_out.value == 7, f"After Taken update, expected uo_out=7 (ST), got {dut.uo_out.value}"

    # Test 3: Update pc_index=1 with outcome=Not Taken (should go WT->WNT)
    # ui_in = {2'b00, update=1, outcome=0, pc_index=0001} = 0b00100001
    dut.ui_in.value = 0b00100001
    await ClockCycles(dut.clk, 1)
    # Deassert update after 1 cycle
    dut.ui_in.value = 0b00000001
    await ClockCycles(dut.clk, 2)
    # WNT(01): prediction=0, state=2'b01 -> uo_out = 0b00000010 = 2
    assert dut.uo_out.value == 2, f"After NT update, expected uo_out=2 (WNT), got {dut.uo_out.value}"

    # Test 4: Verify pc_index=0 is still ST (independent entries)
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 2)
    assert dut.uo_out.value == 7, f"pc=0 should still be ST(7), got {dut.uo_out.value}"

    dut._log.info("All tests passed!")
