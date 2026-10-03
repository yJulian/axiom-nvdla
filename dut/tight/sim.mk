# Run from ext/cva6. Only this DUT's RTL, firmware and Cocotb test are used.
ROOT := ../..
export CVA6_REPO_DIR := $(CURDIR)
export HPDCACHE_DIR := $(CURDIR)/core/cache_subsystem/hpdcache
export TARGET_CFG := ../../../../dut/common/cva6
SIM ?= verilator
TOPLEVEL_LANG ?= verilog
TOPLEVEL := system_top
MODULE := test_tight
EXTRA_ARGS += --timing -f $(ROOT)/build/system_tight.f
CUSTOM_COMPILE_DEPS += $(ROOT)/build/system_tight.f $(ROOT)/dut/common/dpi_stubs.cpp
COMPILE_ARGS += -j 4
SIM_BUILD := $(abspath $(ROOT)/build/sim_tight)
COCOTB_RESULTS_FILE := $(abspath $(ROOT)/build/results_tight.xml)
export PYTHONPATH := $(abspath $(ROOT)/dut/tight):$(PYTHONPATH)
export FIRMWARE := $(abspath $(ROOT)/build/tight/relu.bin)

include $(shell cocotb-config --makefiles)/Makefile.sim
COMPILE_ARGS := $(filter-out --public-flat-rw,$(COMPILE_ARGS)) --public-depth 1
VERILATOR_CPP += $(abspath $(ROOT)/dut/common/dpi_stubs.cpp)
