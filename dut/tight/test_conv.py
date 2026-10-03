"""CVA6 CV-X-IF drives the full NVDLA convolution pipeline."""
import os
from pathlib import Path
import zlib

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, with_timeout
from cocotbext.axi import AxiBus, AxiRam


@cocotb.test()
async def large_int8_convolution(dut):
    dut.rst_ni.value = 0
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    ram = AxiRam(AxiBus.from_prefix(dut, "m_axi"), dut.clk_i, dut.rst_ni,
                 reset_active_level=False, size=1 << 20)
    image = Path(os.environ["FIRMWARE"]).read_bytes()
    assert len(image) <= 0x30000
    ram.write(0, image)
    for _ in range(20):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    await with_timeout(RisingEdge(dut.cpu_done), 20, "ms")
    assert not int(dut.illegal_instr.value)
    status = int.from_bytes(ram.read(0x50000, 4), "little")
    assert status == 0, f"NVDLA status={status}"
    crc = zlib.crc32(ram.read(0x40000, 0x1500))
    assert crc == 0x8C467827, f"convolution output CRC=0x{crc:08x}"
