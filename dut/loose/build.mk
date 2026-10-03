# Include after ext/cva6/Makefile and dut/common/cva6_build.mk.
# The only control target is AXI MMIO -> axi_csb -> NVDLA CSB.
SYSTEM_RTL := $(ROOT)/dut/loose/cva6_axi_top.sv \
	$(ROOT)/dut/loose/system_top.sv $(ROOT)/dut/loose/axi_csb.sv \
	$(ROOT)/dut/common/nvdla_shell.sv
SYSTEM_FLAGS := $(CVA6_FLAGS) $(NV_FLAGS) $(NV_LIBS) \
	$(NV_MOD)/nvdla/top/NV_nvdla.v $(SYSTEM_RTL) \
	-DNO_PLI_OR_EMU -DPRAND_OFF

.PHONY: lint-system system-filelist
lint-system:
	@verilator --lint-only --timing --top-module system_top $(SYSTEM_FLAGS)

system-filelist:
	@mkdir -p $(ROOT)/build
	@printf '%s\n' $(SYSTEM_FLAGS) > $(ROOT)/build/system_loose.f
