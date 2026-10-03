# Loose coupling

`relu.c` uses normal volatile loads and stores at `0x10000000 + CSB offset`.
`cva6_axi_top.sv` wraps upstream CVA6 and resolves AXI atomics. In
`system_top.sv`, the CPU AXI port and NVDLA DMA port enter the crossbar.
Its first target is shared RAM; the second is `axi_csb.sv`, which translates
MMIO transactions to NVDLA's CSB request and response signals.

`test_loose.py` loads firmware and input into an external AXI RAM model,
checks that the CPU completed a CSB read, and verifies all eight ReLU output
bytes after NVDLA's DMA writeback. `build.mk` lists this variant's RTL;
`sim.mk` selects its Cocotb test. Run `make tb-loose` from the repository root.

`conv.c` shows the full convolution setup separately from the ReLU example.
It writes the trace-derived configuration for CDMA, CSC, both CMACs, CACC and
SDP through the same MMIO bridge, waits for CBUF flush, enables consumers
before the producer, and polls for completion. `test_conv.py` checks the
upstream CRC32 over the 0x1500-byte destination region. Run
`make tb-conv-loose` from the repository root. `tools/gen_conv.py` generates
the register table and input/weight arrays from NVDLA's `nv_small` trace.
