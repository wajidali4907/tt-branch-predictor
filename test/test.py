# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer


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
    # Wait extra cycles for gate-level reset propagation
    await ClockCycles(dut.clk, 10)

    dut._log.info("Test project behavior")

    # After reset, all PHT entries = WT (2'b10), prediction = 1
    # Test 1: Read prediction for pc_index=0 (no update)
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 5)
    # Expected: prediction=1, state=2'b10 -> uo_out[2:0] = 0b101 = 5
    dut._log.info(f"Test 1: uo_out = {dut.uo_out.value}")
    assert dut.uo_out.value == 5, f"After reset, expected uo_out=5 (WT, predict Taken), got {dut.uo_out.value}"

    # Test 2: Update pc_index=0 with outcome=Taken (should go WT->ST)
    # Set update=1, outcome=1, pc_index=0 for exactly 1 clock edge
    dut.ui_in.value = 0b00110000
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 5)
    # ST(11): prediction=1, state=2'b11 -> uo_out[2:0] = 0b111 = 7
    dut._log.info(f"Test 2: uo_out = {dut.uo_out.value}")
    assert dut.uo_out.value == 7, f"After Taken update, expected uo_out=7 (ST), got {dut.uo_out.value}"

    # Test 3: Update pc_index=1 with outcome=Not Taken (should go WT->WNT)
    dut.ui_in.value = 0b00100001
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = 0b00000001
    await ClockCycles(dut.clk, 5)
    # WNT(01): prediction=0, state=2'b01 -> uo_out[2:0] = 0b010 = 2
    dut._log.info(f"Test 3: uo_out = {dut.uo_out.value}")
    assert dut.uo_out.value == 2, f"After NT update, expected uo_out=2 (WNT), got {dut.uo_out.value}"

    # Test 4: Verify pc_index=0 is still ST (independent entries)
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut._log.info(f"Test 4: uo_out = {dut.uo_out.value}")
    assert dut.uo_out.value == 7, f"pc=0 should still be ST(7), got {dut.uo_out.value}"

    dut._log.info("All tests passed!")
