# CVA6–NVDLA co-simulation demonstrator

This repository pins AXIOM (`ext/axiom`), CVA6 (`ext/cva6`) and upstream
NVDLA (`ext/nvdla`) as Git submodules. Both DUTs use the generated upstream
`nv_small` RTL. The short smoke workload is a single INT8 SDP cube with BS
ALU MAX 0: eight signed bytes are transformed to `max(x, 0)` and written back
to RAM. A second workload runs a full 13×15×64 by 5×3×64×16 INT8 convolution
through CDMA, CSC, CMAC, CACC and SDP.

The loose DUT uses CVA6 AXI transactions to reach NVDLA's CSB register
window at `0x10000000`. The tight DUT exposes task-level Custom-0
instructions through CV-X-IF: `relu8` takes input/output addresses and
launches the SDP job; `conv` starts the fixed reference convolution; `wait`
returns after NVDLA completion. In both DUTs,
CVA6 and NVDLA share the RAM target through a PULP AXI crossbar. The RAM
window is `0x80000000`–`0x800fffff`. The firmware starts at `0x80000000`,
input is at `0x80010000`, and output is at `0x80020000`.
The convolution keeps its input at `0x80010000`, puts weights at
`0x80020000`, and writes the result at `0x80040000`.

The two coarse architecture diagrams are available as D2 sources and rendered
SVGs: [loose](dut/loose/architecture.d2) ([SVG](dut/loose/architecture.svg))
and [tight](dut/tight/architecture.d2) ([SVG](dut/tight/architecture.svg)).
Run `make diagrams` after changing either D2 source. Each DUT is self-contained:
the [loose path](dut/loose/README.md) and [tight path](dut/tight/README.md)
have their own top-level, CPU wrapper, firmware, source list, and Cocotb test.
`dut/common` contains only shared infrastructure: the NVDLA RTL shell, CVA6
configuration, source inventory, and the isolated NVDLA smoke test.
The [tight ISA roadmap](dut/tight/ISA_PLAN.md) proposes a descriptor-based
instruction set for the other NVDLA blocks and documents the limits of the
current `nv_small` build.

Prerequisites: Verilator 5, GNU RISC-V cross tools (`riscv64-linux-gnu-gcc`
and `objcopy`), Python 3 with venv, and Nix with `nix-shell`. Initialize all
submodules before building:

```sh
git submodule update --init --recursive
make nvdla-rtl
make tb-nvdla
make tb-loose
make tb-tight
make tb-conv-loose
make tb-conv-tight
```

`nvdla-rtl` generates `nv_small` into NVDLA's ignored `outdir` using the
upstream generator. The test targets install Cocotb into `.venv`, build
the bare-metal firmware, run Verilator, and check the eight output bytes.
`tb-nvdla` separately validates the SDP register sequence without CVA6.
`lint-loose` and `lint-tight` run system-level Verilator lint.

The convolution tests also check the upstream CRC32 over the complete output.
The Cocotb RAM model is external to the DUT. This keeps the AXI memory
boundary available for AXIOM/gem5 integration and independently checks both
CPU control paths and NVDLA DMA outside gem5.

The [gem5/AXIOM comparison](gem5/README.md) now also runs the complete
CVA6/NVDLA RTL against gem5 memory at three latencies and produces
[cycle counts](gem5/results.svg) and a [relative-speed plot](gem5/speedup.svg).
It tests both the eight-byte ReLU job and the fixed reference convolution;
see [gem5/README.md](gem5/README.md) for separate results and limits.
