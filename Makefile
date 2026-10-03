RISCV_PREFIX ?= riscv64-linux-gnu-
NVDLA_RTL := ext/nvdla/outdir/nv_small/vmod/nvdla/top/NV_nvdla.v
FIRMWARE_FLAGS := -nostdlib -static -no-pie -ffreestanding -fno-pic -mcmodel=medany -O2 -march=rv64imac -mabi=lp64 -Wl,--build-id=none -Wl,-T,sw/link.ld
CONV_FLAGS := -nostdlib -static -no-pie -ffreestanding -fno-pic -mcmodel=medany -O2 -march=rv64imac -mabi=lp64 -Wl,--build-id=none -Wl,-T,sw/conv_link.ld

.PHONY: nvdla-rtl cocotb-env tb-nvdla tb-loose tb-tight lint-loose lint-tight diagrams
nvdla-rtl: $(NVDLA_RTL)

diagrams: dut/loose/architecture.svg dut/tight/architecture.svg

dut/%/architecture.svg: dut/%/architecture.d2
	d2 --layout tala --theme 1 --pad 24 $< $@

$(NVDLA_RTL):
	@test -f ext/nvdla/Makefile || { echo 'Run git submodule update --init --recursive'; exit 1; }
	nix-shell -p perl perlPackages.YAML perlPackages.CaptureTiny perlPackages.XMLSimple jdk21 --run 'make -C ext/nvdla USE_VM_ENV=1 VM_PROJ=nv_small VM_USE_DESIGNWARE=0 VM_PYTHON=python3 VM_JAVA=java VM_PERL=perl VM_CPP=cpp VM_GCC=gcc VM_CXX=g++ VM_VERILATOR=verilator VM_CLANG=gcc && cd ext/nvdla && ./tools/bin/tmake -build vmod -projects nv_small'

build/loose/relu.bin: dut/loose/relu.c sw/link.ld Makefile
	mkdir -p build/loose
	$(RISCV_PREFIX)gcc $(FIRMWARE_FLAGS) -o build/loose/relu.elf dut/loose/relu.c
	$(RISCV_PREFIX)objcopy -O binary build/loose/relu.elf $@

build/tight/relu.bin: dut/tight/relu.c sw/link.ld Makefile
	mkdir -p build/tight
	$(RISCV_PREFIX)gcc $(FIRMWARE_FLAGS) -o build/tight/relu.elf dut/tight/relu.c
	$(RISCV_PREFIX)objcopy -O binary build/tight/relu.elf $@

CONV_TRACE := ext/nvdla/verif/tests/trace_tests/nv_small/dc_13x15x64_5x3x64x16_int8_0
CONV_GENERATED := dut/loose/conv_commands.h dut/tight/conv_commands.svh dut/loose/conv_input.h dut/loose/conv_weight.h dut/tight/conv_input.h dut/tight/conv_weight.h
$(CONV_GENERATED) &: tools/gen_conv.py $(CONV_TRACE)/dc_13x15x64_5x3x64x16_int8_0.cfg $(CONV_TRACE)/dc_13x15x64_5x3x64x16_int8_0_in_feature.dat $(CONV_TRACE)/dc_13x15x64_5x3x64x16_int8_0_in_wt.dat
	python3 tools/gen_conv.py

build/%/conv.bin: dut/%/conv.c dut/%/conv_input.h dut/%/conv_weight.h sw/conv_link.ld Makefile
	mkdir -p build/$*
	$(RISCV_PREFIX)gcc $(CONV_FLAGS) -o build/$*/conv.elf $<
	$(RISCV_PREFIX)objcopy -O binary build/$*/conv.elf $@

build/loose/conv.bin: dut/loose/conv_commands.h

.venv/bin/cocotb-config: ext/axiom/requirements-cocotb.txt
	python3 -m venv .venv
	.venv/bin/pip install -r ext/axiom/requirements-cocotb.txt

cocotb-env: .venv/bin/cocotb-config

tb-nvdla: nvdla-rtl cocotb-env
	PATH=$(CURDIR)/.venv/bin:$$PATH $(MAKE) -C dut/common sim

build/system_loose.f: $(NVDLA_RTL) dut/common/cva6_build.mk dut/loose/build.mk dut/loose/system_top.sv dut/loose/cva6_axi_top.sv dut/loose/axi_csb.sv
	$(MAKE) -C ext/cva6 -f Makefile -f ../../dut/common/cva6_build.mk -f ../../dut/loose/build.mk system-filelist RISCV=/usr

build/system_tight.f: $(NVDLA_RTL) dut/common/cva6_build.mk dut/tight/build.mk dut/tight/system_top.sv dut/tight/cva6_axi_top.sv dut/tight/cvxif_sdp.sv dut/tight/conv_commands.svh dut/tight/ariane_nvdla.sv
	$(MAKE) -C ext/cva6 -f Makefile -f ../../dut/common/cva6_build.mk -f ../../dut/tight/build.mk system-filelist RISCV=/usr

tb-loose: build/loose/relu.bin build/system_loose.f cocotb-env
	PATH=$(CURDIR)/.venv/bin:$$PATH $(MAKE) -C ext/cva6 -f ../../dut/loose/sim.mk

tb-tight: build/tight/relu.bin build/system_tight.f cocotb-env
	PATH=$(CURDIR)/.venv/bin:$$PATH $(MAKE) -C ext/cva6 -f ../../dut/tight/sim.mk

.PHONY: tb-conv-loose tb-conv-tight
tb-conv-loose: build/loose/conv.bin build/system_loose.f cocotb-env
	PATH=$(CURDIR)/.venv/bin:$$PATH $(MAKE) -C ext/cva6 -f ../../dut/loose/sim.mk MODULE=test_conv FIRMWARE=$(CURDIR)/build/loose/conv.bin

tb-conv-tight: build/tight/conv.bin build/system_tight.f cocotb-env
	PATH=$(CURDIR)/.venv/bin:$$PATH $(MAKE) -C ext/cva6 -f ../../dut/tight/sim.mk MODULE=test_conv FIRMWARE=$(CURDIR)/build/tight/conv.bin

lint-loose: nvdla-rtl
	$(MAKE) -C ext/cva6 -f Makefile -f ../../dut/common/cva6_build.mk -f ../../dut/loose/build.mk lint-system RISCV=/usr

lint-tight: nvdla-rtl
	$(MAKE) -C ext/cva6 -f Makefile -f ../../dut/common/cva6_build.mk -f ../../dut/tight/build.mk lint-system RISCV=/usr

build/gem5/driver.elf: gem5/driver.c Makefile
	mkdir -p build/gem5
	$(RISCV_PREFIX)gcc -nostdlib -static -no-pie -ffreestanding -fno-pic -mcmodel=medany -O2 -march=rv64imac -mabi=lp64 -Wl,--no-relax -Wl,-e,_start -o $@ $<

build/gem5/conv_driver.elf: gem5/conv_driver.c Makefile
	mkdir -p build/gem5
	$(RISCV_PREFIX)gcc -nostdlib -static -no-pie -ffreestanding -fno-pic -mcmodel=medany -O2 -march=rv64imac -mabi=lp64 -Wl,--no-relax -Wl,-e,_start -o $@ $<

build/gem5/loose/libnvdla_loose.so: build/system_loose.f dut/loose/gem5_top.sv gem5/build_plugin.sh gem5/rtl_plugin_shim.cc
	bash gem5/build_plugin.sh loose

build/gem5/tight/libnvdla_tight.so: build/system_tight.f dut/tight/gem5_top.sv gem5/build_plugin.sh gem5/rtl_plugin_shim.cc
	bash gem5/build_plugin.sh tight

.PHONY: gem5-loose gem5-tight gem5-sweep
gem5-loose: build/loose/relu.bin build/gem5/driver.elf build/gem5/loose/libnvdla_loose.so
	$(MAKE) -C gem5 run MODE=loose LATENCY=$(or $(LATENCY),10ns)

gem5-tight: build/tight/relu.bin build/gem5/driver.elf build/gem5/tight/libnvdla_tight.so
	$(MAKE) -C gem5 run MODE=tight LATENCY=$(or $(LATENCY),10ns)

gem5-sweep: build/loose/relu.bin build/tight/relu.bin build/gem5/driver.elf build/gem5/loose/libnvdla_loose.so build/gem5/tight/libnvdla_tight.so
	@for latency in 10ns 50ns 100ns; do \
	  $(MAKE) -C gem5 run MODE=loose LATENCY=$$latency || exit $$?; \
	  $(MAKE) -C gem5 run MODE=tight LATENCY=$$latency || exit $$?; \
	done
	python3 gem5/plot.py gem5/results.csv gem5/results.svg

.PHONY: gem5-conv-loose gem5-conv-tight gem5-conv-sweep
gem5-conv-loose: build/loose/conv.bin build/gem5/conv_driver.elf build/gem5/loose/libnvdla_loose.so
	$(MAKE) -C gem5 run MODE=loose WORKLOAD=conv LATENCY=$(or $(LATENCY),10ns)

gem5-conv-tight: build/tight/conv.bin build/gem5/conv_driver.elf build/gem5/tight/libnvdla_tight.so
	$(MAKE) -C gem5 run MODE=tight WORKLOAD=conv LATENCY=$(or $(LATENCY),10ns)

gem5-conv-sweep: build/loose/conv.bin build/tight/conv.bin build/gem5/conv_driver.elf build/gem5/loose/libnvdla_loose.so build/gem5/tight/libnvdla_tight.so
	@for latency in 10ns 50ns 100ns; do \
	  $(MAKE) -C gem5 run MODE=loose WORKLOAD=conv LATENCY=$$latency || exit $$?; \
	  $(MAKE) -C gem5 run MODE=tight WORKLOAD=conv LATENCY=$$latency || exit $$?; \
	done
	python3 gem5/plot.py gem5/conv_results.csv gem5/conv_results.svg
