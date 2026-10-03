# Include after ext/cva6/Makefile and dut/common/cva6_build.mk.
# CV-X-IF connects Custom-0 instructions to CSB; AXI is RAM-only.
SYSTEM_RTL := $(ROOT)/dut/tight/cva6_axi_top.sv \
	$(ROOT)/dut/tight/ariane_nvdla.sv $(ROOT)/dut/tight/cvxif_sdp.sv \
	$(ROOT)/dut/tight/system_top.sv $(ROOT)/dut/common/nvdla_shell.sv
SYSTEM_FLAGS := $(CVA6_FLAGS) $(NV_FLAGS) $(NV_LIBS) -I$(ROOT)/dut/tight \
	$(NV_MOD)/nvdla/top/NV_nvdla.v $(SYSTEM_RTL) \
	-DNO_PLI_OR_EMU -DPRAND_OFF

.PHONY: lint-system system-filelist
lint-system:
	@verilator --lint-only --timing --top-module system_top $(SYSTEM_FLAGS)

system-filelist:
	@mkdir -p $(ROOT)/build
	@printf '%s\n' $(SYSTEM_FLAGS) > $(ROOT)/build/system_tight.f
