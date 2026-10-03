"""Run the complete CVA6/NVDLA RTL behind AXIOM's DMA plugin bridge.

The gem5 CPU only initializes/checks memory and starts the RTL. The measured
cycles come from the wrapper around the RTL CVA6, not this driver process.
"""
import argparse

import m5
from m5.objects import (AddrRange, Process, RiscvTimingSimpleCPU, Root,
                        RTLDmaDevicePlugin, SEWorkload, SimpleMemory,
                        SrcClockDomain, System, SystemXBar, VoltageDomain)

parser = argparse.ArgumentParser()
parser.add_argument("--driver", required=True)
parser.add_argument("--firmware", required=True)
parser.add_argument("--plugin", required=True)
parser.add_argument("--latency", default="10ns")
parser.add_argument("--max-ticks", type=int, default=100_000_000_000)
parser.add_argument("--driver-output", default="cout")
args = parser.parse_args()

CONTROL = 0x10010000
RAM_BASE = 0x80000000
system = System()
system.clk_domain = SrcClockDomain(clock="1GHz", voltage_domain=VoltageDomain())
system.mem_mode = "timing"
system.mem_ranges = [AddrRange("256MB"), AddrRange(RAM_BASE, size="1MB")]
system.cpu = RiscvTimingSimpleCPU()
system.bus = SystemXBar()
system.cpu.icache_port = system.bus.cpu_side_ports
system.cpu.dcache_port = system.bus.cpu_side_ports
system.accel = RTLDmaDevicePlugin(pio_addr=CONTROL, rtl_library=args.plugin,
                                  idle_gate_cycles=0)
system.accel.pio = system.bus.mem_side_ports
system.accel.dma = system.bus.cpu_side_ports
system.host_mem = SimpleMemory(range=system.mem_ranges[0], latency="10ns")
system.host_mem.port = system.bus.mem_side_ports
system.rtl_mem = SimpleMemory(range=system.mem_ranges[1], latency=args.latency,
                              image_file=args.firmware)
system.rtl_mem.port = system.bus.mem_side_ports
system.cpu.createInterruptController()
system.system_port = system.bus.cpu_side_ports
process = Process(cmd=[args.driver], output=args.driver_output)
system.cpu.workload = process
system.cpu.createThreads()
system.workload = SEWorkload.init_compatible(args.driver)
root = Root(full_system=False, system=system)
m5.instantiate()
process.map(CONTROL, CONTROL, 0x1000)
process.map(RAM_BASE, RAM_BASE, 0x100000)
event = m5.simulate(args.max_ticks)
print("GEM5_EXIT tick=%d cause=%s" % (m5.curTick(), event.getCause()))
