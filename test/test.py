import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

def pack_inputs(pc_index, outcome, update):
    return (update << 5) | (outcome << 4) | (pc_index & 0xF)

async def apply_branch(dut, pc_index, outcome):
    """Read prediction then update on rising edge."""
    dut.ui_in.value  = pack_inputs(pc_index, outcome, 0)
    dut.uio_in.value = 0
    await Timer(2, units="ns")
    pred = int(dut.uo_out.value) & 1

    dut.ui_in.value = pack_inputs(pc_index, outcome, 1)
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    dut.ui_in.value = pack_inputs(pc_index, outcome, 0)
    return pred

async def check_pred(dut, pc_index, expected, test_name):
    dut.ui_in.value  = pack_inputs(pc_index, 0, 0)
    dut.uio_in.value = 0
    await Timer(2, units="ns")
    pred = int(dut.uo_out.value) & 1
    assert pred == expected, \
        f"FAIL [{test_name}]: pc={pc_index} expected={expected} got={pred}"
    cocotb.log.info(f"PASS [{test_name}]: pc={pc_index} pred={pred}")

# Software reference model
ref_bht = [0b10] * 16

def ref_update(idx, taken):
    if taken:
        ref_bht[idx] = min(0b11, ref_bht[idx] + 1)
    else:
        ref_bht[idx] = max(0b00, ref_bht[idx] - 1)

def ref_predict(idx):
    return (ref_bht[idx] >> 1) & 1

@cocotb.test()
async def test_branch_predictor(dut):
    global ref_bht
    ref_bht = [0b10] * 16

    # Start clock
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # Reset
    dut.rst_n.value  = 0
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    dut.ena.value    = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # TEST 1: Reset state - all entries WT (10) → predict Taken
    cocotb.log.info("--- TEST 1: Reset state ---")
    for i in range(16):
        await check_pred(dut, i, 1, f"reset pc={i}")

    # TEST 2: Always Taken on pc=0 → WT→ST
    cocotb.log.info("--- TEST 2: Always Taken ---")
    await apply_branch(dut, 0, 1); ref_update(0, 1)  # WT→ST
    await check_pred(dut, 0, 1, "after 1 taken")
    await apply_branch(dut, 0, 1); ref_update(0, 1)  # stays ST
    await check_pred(dut, 0, 1, "after 2 taken")

    # TEST 3: Always Not Taken on pc=1 → WT→WNT→SNT
    cocotb.log.info("--- TEST 3: Always Not Taken ---")
    await apply_branch(dut, 1, 0); ref_update(1, 0)  # WT→WNT
    await check_pred(dut, 1, 0, "after 1 NT")
    await apply_branch(dut, 1, 0); ref_update(1, 0)  # WNT→SNT
    await check_pred(dut, 1, 0, "after 2 NT")
    await apply_branch(dut, 1, 0); ref_update(1, 0)  # stays SNT
    await check_pred(dut, 1, 0, "after 3 NT saturate")

    # TEST 4: Hysteresis - ST needs 2 NTs to flip
    cocotb.log.info("--- TEST 4: Hysteresis ---")
    # pc=0 is at ST after TEST 2
    await apply_branch(dut, 0, 0); ref_update(0, 0)  # ST→WT
    await check_pred(dut, 0, 1, "1 NT from ST still Taken")
    await apply_branch(dut, 0, 0); ref_update(0, 0)  # WT→WNT
    await check_pred(dut, 0, 0, "2 NT from ST now Not Taken")

    # TEST 5: Alternating T/NT on pc=2
    cocotb.log.info("--- TEST 5: Alternating ---")
    for _ in range(4):
        await apply_branch(dut, 2, 1); ref_update(2, 1)
        await apply_branch(dut, 2, 0); ref_update(2, 0)
    await check_pred(dut, 2, ref_predict(2), "alternating stable")

    # TEST 6: PHT independence
    cocotb.log.info("--- TEST 6: Independence ---")
    await apply_branch(dut, 3, 0); ref_update(3, 0)
    await apply_branch(dut, 3, 0); ref_update(3, 0)  # pc=3 → SNT
    await apply_branch(dut, 4, 1); ref_update(4, 1)  # pc=4 → ST
    await check_pred(dut, 3, 0, "pc=3 SNT independent")
    await check_pred(dut, 4, 1, "pc=4 ST independent")
    await check_pred(dut, 5, 1, "pc=5 untouched WT")

    # TEST 7: All 4 states on pc=6
    cocotb.log.info("--- TEST 7: All 4 states ---")
    await check_pred(dut, 6, 1, "WT state")
    await apply_branch(dut, 6, 0); ref_update(6, 0)  # WT→WNT
    await check_pred(dut, 6, 0, "WNT state")
    await apply_branch(dut, 6, 0); ref_update(6, 0)  # WNT→SNT
    await check_pred(dut, 6, 0, "SNT state")
    await apply_branch(dut, 6, 1); ref_update(6, 1)  # SNT→WNT
    await check_pred(dut, 6, 0, "WNT again")
    await apply_branch(dut, 6, 1); ref_update(6, 1)  # WNT→WT
    await check_pred(dut, 6, 1, "WT again")
    await apply_branch(dut, 6, 1); ref_update(6, 1)  # WT→ST
    await check_pred(dut, 6, 1, "ST state")

    # TEST 8: Saturation boundaries on pc=7
    cocotb.log.info("--- TEST 8: Saturation ---")
    for _ in range(5):
        await apply_branch(dut, 7, 0); ref_update(7, 0)
    await check_pred(dut, 7, 0, "SNT saturated")
    for _ in range(5):
        await apply_branch(dut, 7, 1); ref_update(7, 1)
    await check_pred(dut, 7, 1, "ST saturated")

    # TEST 9: Reference model sweep all 16 PCs
    cocotb.log.info("--- TEST 9: Reference sweep ---")
    for i in range(16):
        await check_pred(dut, i, ref_predict(i), f"ref sweep pc={i}")

    cocotb.log.info("ALL TESTS PASSED!")
