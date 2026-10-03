"""Custom relu8/wait instructions drive real NVDLA; DMA shares AXI RAM."""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, with_timeout
from cocotbext.axi import AxiBus, AxiRam

VALUES = bytes([0x80, 0xFF, 0, 1, 2, 127, 0xD6, 42])
EXPECTED = bytes(max(int.from_bytes(bytes([x]), "little", signed=True), 0) for x in VALUES)
RAM_SIZE = 1 << 20


@cocotb.test()
async def cva6_cvxif_sdp_relu(dut):
    dut.rst_ni.value = 0
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    ram = AxiRam(AxiBus.from_prefix(dut, "m_axi"), dut.clk_i, dut.rst_ni,
                 reset_active_level=False, size=RAM_SIZE)
    firmware = Path(os.environ["FIRMWARE"]).read_bytes()
    assert len(firmware) < 0x10000
    ram.write(0, firmware)
    ram.write(0x10000, VALUES)
    ram.write(0x20000, b"\xA5" * len(VALUES))
    ram.write(0x30000, b"\xA5" * 4)
    for _ in range(20):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    await with_timeout(RisingEdge(dut.cpu_done), 1, "ms")
    assert not int(dut.illegal_instr.value), "CVA6 reported illegal instruction"
    status = int.from_bytes(ram.read(0x30000, 4), "little")
    assert status == 0, f"relu8/wait returned status 0x{status:08x}"
    got = ram.read(0x20000, len(VALUES))
    assert got == EXPECTED, f"SDP ReLU output {got.hex()} != {EXPECTED.hex()}"
