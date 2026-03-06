# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.triggers import RisingEdge, Timer


@cocotb.test()
async def test_project(dut):
    dut._log.info("Waiting for Verilog testbench to complete")

    # The Verilog testbench (tb.v) drives its own clock, reset, and tests.
    # We just monitor pass_o / error_o signals.
    timeout_ns = 50_000_000  # 50ms timeout
    poll_ns = 1000  # check every 1us

    for _ in range(timeout_ns // poll_ns):
        await Timer(poll_ns, unit="ns")
        try:
            pass_o = dut.pass_o.value
            error_o = dut.error_o.value
        except AttributeError:
            continue
        if str(pass_o) == "1":
            dut._log.info("Verilog testbench PASSED")
            return
        if str(error_o) == "1":
            assert False, "Verilog testbench reported FAILURE"

    assert False, "Timeout: Verilog testbench did not complete"
