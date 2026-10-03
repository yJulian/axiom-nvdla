# Source inventory shared by both DUT build files. Include after CVA6's Makefile.
ROOT := ../..
export TARGET_CFG := ../../../../dut/common/cva6
export CVA6_REPO_DIR := $(CURDIR)

CVA6_COMMON := $(filter-out %.vhd,$(ariane_pkg)) \
	$(filter-out core/fpu_wrap.sv %/rvfi_tracer.sv %/SimDTM.sv %/SimJTAG.sv,$(filter-out %.vhd,$(filter-out %_config_pkg.sv,$(src))))
CVA6_FLAGS := -f core/Flist.cva6 core/cva6_rvfi.sv \
	$(CVA6_COMMON) $(list_incdir) +incdir+corev_apu/axi_node \
	+define+$(defines) --unroll-count 256 -Wno-fatal -Wno-PINMISSING \
	-Wno-ASSIGNDLY -Wno-UNOPTFLAT -Wno-BLKANDNBLK
NV_MOD := $(ROOT)/ext/nvdla/outdir/nv_small/vmod
NV_DIRS := $(shell find $(NV_MOD)/nvdla $(NV_MOD)/vlibs $(NV_MOD)/rams/model $(NV_MOD)/rams/fpga/model $(NV_MOD)/fifos $(NV_MOD)/include -type d)
NV_FLAGS := $(foreach dir,$(NV_DIRS),-y $(dir) +incdir+$(dir))
NV_LIBS := $(wildcard $(NV_MOD)/vlibs/*.vlib) $(wildcard $(NV_MOD)/fifos/*.v) \
	$(NV_MOD)/nvdla/nocif/NV_NVDLA_XXIF_libs.v
