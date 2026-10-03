ROOT := ../..
NVDLA := $(ROOT)/ext/nvdla/outdir/nv_small/vmod
NVDLA_DIRS := $(shell find $(NVDLA)/nvdla $(NVDLA)/vlibs $(NVDLA)/rams/model $(NVDLA)/rams/fpga/model $(NVDLA)/fifos $(NVDLA)/include -type d)
NVDLA_FLAGS := $(foreach dir,$(NVDLA_DIRS),-y $(dir) +incdir+$(dir))
NVDLA_LIBS := $(wildcard $(NVDLA)/vlibs/*.vlib) \
	$(wildcard $(NVDLA)/fifos/*.v) \
	$(NVDLA)/nvdla/nocif/NV_NVDLA_XXIF_libs.v

SIM ?= verilator
TOPLEVEL_LANG ?= verilog
TOPLEVEL := nvdla_shell
MODULE := test_nvdla
COCOTB_RESULTS_FILE := $(abspath ../../build/results_nvdla.xml)
VERILOG_SOURCES := $(abspath nvdla_shell.sv) $(abspath $(NVDLA)/nvdla/top/NV_nvdla.v) $(abspath $(NVDLA_LIBS))
EXTRA_ARGS += --timing -Wno-fatal -Wno-PINMISSING -DNO_PLI_OR_EMU -DPRAND_OFF $(NVDLA_FLAGS)
COMPILE_ARGS += -j 4

.PHONY: lint-nvdla
lint-nvdla:
	@test -f $(NVDLA)/nvdla/top/NV_nvdla.v || { echo 'Generate nv_small RTL first: make nvdla-rtl'; exit 1; }
	@verilator --lint-only -Wno-fatal -Wno-PINMISSING \
		-DNO_PLI_OR_EMU -DPRAND_OFF --top-module nvdla_shell \
		$(NVDLA_FLAGS) $(NVDLA_LIBS) nvdla_shell.sv $(NVDLA)/nvdla/top/NV_nvdla.v

include $(shell cocotb-config --makefiles)/Makefile.sim
