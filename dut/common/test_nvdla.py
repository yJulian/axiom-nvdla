"""Real nv_small SDP smoke test, independent of CVA6 and gem5."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, with_timeout
from cocotbext.axi import AxiBus, AxiRam

INPUT_ADDR = 0x80000400
OUTPUT_ADDR = 0x80000800
RAM_SIZE = 1 << 20
VALUES = bytes([0x80, 0xFF, 0, 1, 2, 127, 0xD6, 42])
EXPECTED = bytes(max(int.from_bytes(bytes([x]), "little", signed=True), 0) for x in VALUES)


async def csb_write(dut, addr, value):
    dut.csb_addr.value = addr >> 2
    dut.csb_wdata.value = value
    dut.csb_write.value = 1
    dut.csb_nposted.value = 0
    dut.csb_valid.value = 1
    while True:
        await RisingEdge(dut.clk_i)
        if int(dut.csb_ready.value):
            break
    dut.csb_valid.value = 0
    await RisingEdge(dut.clk_i)


@cocotb.test()
async def sdp_relu_int8(dut):
    dut.rst_ni.value = 0
    dut.csb_valid.value = 0
    dut.csb_addr.value = 0
    dut.csb_wdata.value = 0
    dut.csb_write.value = 0
    dut.csb_nposted.value = 0
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    ram = AxiRam(AxiBus.from_prefix(dut, "m_axi"), dut.clk_i, dut.rst_ni,
                 reset_active_level=False, size=RAM_SIZE)
    ram.write(INPUT_ADDR % RAM_SIZE, VALUES)
    ram.write(OUTPUT_ADDR % RAM_SIZE, b"\xA5" * len(VALUES))
    for _ in range(16):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    await RisingEdge(dut.clk_i)

    # Offline SDP, one 1x1x8 INT8 cube.  BS ALU is MAX with the constant 0;
    # BS multiplier is bypassed, so it computes ReLU(x) = max(x, 0).
    writes = [
        (0x9004, 0), (0x8004, 0),
        (0x903c, 0), (0x9040, 0), (0x9044, 7),
        (0x9048, OUTPUT_ADDR), (0x904c, 0),
        (0x9050, 8), (0x9054, 8),
        (0x9058, 0x10), (0x905c, 0), (0x9060, 0),
        (0x906c, 1), (0x9080, 1),
        (0x90b0, 0), (0x90b4, 1),
        (0x90c0, 0), (0x90c4, 1), (0x90c8, 0),
        (0x800c, 0), (0x8010, 0), (0x8014, 7),
        (0x8018, INPUT_ADDR), (0x801c, 0),
        (0x8020, 8), (0x8024, 8),
        (0x8028, 1), (0x8040, 1), (0x8058, 1),
        (0x8070, 0), (0x8074, 1),
        (0x8008, 1), (0x9038, 1),
    ]
    for addr, data in writes:
        await with_timeout(csb_write(dut, addr, data), 100, "us")

    await Timer(10, unit="us")
    got = ram.read(OUTPUT_ADDR % RAM_SIZE, len(VALUES))
    assert got == EXPECTED, f"NVDLA ReLU output: {got.hex()} != {EXPECTED.hex()}"
