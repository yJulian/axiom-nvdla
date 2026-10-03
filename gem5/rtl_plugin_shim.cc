// rtl_plugin_shim.cc
//
// Generic shim implementing axion_rtl_* (src/axi/axi4_plugin_abi.h) against
// whatever Verilator top module plugin/rtl_plugin.mk was invoked with.
// Compiled once per DUT by that Makefile, parameterized purely via -D /
// -include compiler flags (AXION_TOP_CLASS, AXION_PLUGIN_HAS_SLAVE,
// AXION_PLUGIN_HAS_MASTER) -- there is nothing in this file to hand-edit
// per model. Field access mirrors examples/fifo_pio_accel/fifo_pio_device.cc
// one-for-one, written once generically instead of once per DUT.

#include "axi/axi4_plugin_abi.h"

#include <cstring>
#include <memory>

#include <verilated.h>

#ifndef AXION_TOP_CLASS
#error "AXION_TOP_CLASS must be defined, e.g. -DAXION_TOP_CLASS=Vfifo_pio_top"
#endif

#ifndef AXION_PLUGIN_HAS_SLAVE
#define AXION_PLUGIN_HAS_SLAVE 1
#endif
#ifndef AXION_PLUGIN_HAS_MASTER
#define AXION_PLUGIN_HAS_MASTER 0
#endif

struct AxionRtlInstance
{
    std::unique_ptr<VerilatedContext> context;
    std::unique_ptr<AXION_TOP_CLASS> top;

    explicit AxionRtlInstance(const char *name)
        : context(new VerilatedContext),
          top(new AXION_TOP_CLASS(context.get(), name))
    {
        // CVA6's reset-time plusargs require argv to be initialized on the
        // same VerilatedContext that owns this model instance.
        const char *argv[] = {"axiom-nvdla"};
        context->commandArgs(1, argv);
    }
};

extern "C" {

AxionRtlInstance *
axion_rtl_create(const char *instance_name)
{
    return new AxionRtlInstance(instance_name);
}

void
axion_rtl_destroy(AxionRtlInstance *inst)
{
    if (!inst)
        return;
    inst->top->final();
    delete inst;
}

void
axion_rtl_set_clk(AxionRtlInstance *inst, uint8_t val)
{
    inst->top->clk_i = val;
}

void
axion_rtl_set_rst_n(AxionRtlInstance *inst, uint8_t val)
{
    inst->top->rst_ni = val;
}

void
axion_rtl_eval(AxionRtlInstance *inst)
{
    inst->top->eval();
}

int
axion_rtl_has_slave_port(void)
{
    return AXION_PLUGIN_HAS_SLAVE;
}

int
axion_rtl_has_master_port(void)
{
    return AXION_PLUGIN_HAS_MASTER;
}

#if AXION_PLUGIN_HAS_SLAVE

void
axion_rtl_slave_drive(AxionRtlInstance *inst, const AxionAxi4SlaveInputs *in)
{
    auto *top = inst->top.get();

    top->s_axi_awid = in->awid;
    top->s_axi_awaddr = in->awaddr;
    top->s_axi_awlen = in->awlen;
    top->s_axi_awsize = in->awsize;
    top->s_axi_awburst = in->awburst;
    top->s_axi_awlock = in->awlock;
    top->s_axi_awcache = in->awcache;
    top->s_axi_awprot = in->awprot;
    top->s_axi_awqos = in->awqos;
    top->s_axi_awregion = in->awregion;
    top->s_axi_awvalid = in->awvalid;

    top->s_axi_wdata = in->wdata;
    top->s_axi_wstrb = in->wstrb;
    top->s_axi_wlast = in->wlast;
    top->s_axi_wvalid = in->wvalid;

    top->s_axi_bready = in->bready;

    top->s_axi_arid = in->arid;
    top->s_axi_araddr = in->araddr;
    top->s_axi_arlen = in->arlen;
    top->s_axi_arsize = in->arsize;
    top->s_axi_arburst = in->arburst;
    top->s_axi_arlock = in->arlock;
    top->s_axi_arcache = in->arcache;
    top->s_axi_arprot = in->arprot;
    top->s_axi_arqos = in->arqos;
    top->s_axi_arregion = in->arregion;
    top->s_axi_arvalid = in->arvalid;

    top->s_axi_rready = in->rready;
}

void
axion_rtl_slave_sample(AxionRtlInstance *inst, AxionAxi4SlaveOutputs *out)
{
    auto *top = inst->top.get();

    out->awready = top->s_axi_awready;
    out->wready = top->s_axi_wready;
    out->bid = top->s_axi_bid;
    out->bresp = top->s_axi_bresp;
    out->bvalid = top->s_axi_bvalid;
    out->arready = top->s_axi_arready;
    out->rid = top->s_axi_rid;
    out->rdata = top->s_axi_rdata;
    out->rresp = top->s_axi_rresp;
    out->rlast = top->s_axi_rlast;
    out->rvalid = top->s_axi_rvalid;
}

#else // !AXION_PLUGIN_HAS_SLAVE

void
axion_rtl_slave_drive(AxionRtlInstance *, const AxionAxi4SlaveInputs *)
{}

void
axion_rtl_slave_sample(AxionRtlInstance *, AxionAxi4SlaveOutputs *out)
{
    std::memset(out, 0, sizeof(*out));
}

#endif // AXION_PLUGIN_HAS_SLAVE

#if AXION_PLUGIN_HAS_MASTER

void
axion_rtl_master_drive(AxionRtlInstance *inst,
                        const AxionAxi4MasterInputs *in)
{
    auto *top = inst->top.get();

    top->m_axi_awready = in->awready;
    top->m_axi_wready = in->wready;
    top->m_axi_bid = in->bid;
    top->m_axi_bresp = in->bresp;
    top->m_axi_bvalid = in->bvalid;
    top->m_axi_arready = in->arready;
    top->m_axi_rid = in->rid;
    top->m_axi_rdata = in->rdata;
    top->m_axi_rresp = in->rresp;
    top->m_axi_rlast = in->rlast;
    top->m_axi_rvalid = in->rvalid;
}

void
axion_rtl_master_sample(AxionRtlInstance *inst, AxionAxi4MasterOutputs *out)
{
    auto *top = inst->top.get();

    out->awid = top->m_axi_awid;
    out->awaddr = top->m_axi_awaddr;
    out->awlen = top->m_axi_awlen;
    out->awsize = top->m_axi_awsize;
    out->awburst = top->m_axi_awburst;
    out->awlock = top->m_axi_awlock;
    out->awcache = top->m_axi_awcache;
    out->awprot = top->m_axi_awprot;
    out->awqos = top->m_axi_awqos;
    out->awregion = top->m_axi_awregion;
    out->awvalid = top->m_axi_awvalid;

    out->wdata = top->m_axi_wdata;
    out->wstrb = top->m_axi_wstrb;
    out->wlast = top->m_axi_wlast;
    out->wvalid = top->m_axi_wvalid;

    out->bready = top->m_axi_bready;

    out->arid = top->m_axi_arid;
    out->araddr = top->m_axi_araddr;
    out->arlen = top->m_axi_arlen;
    out->arsize = top->m_axi_arsize;
    out->arburst = top->m_axi_arburst;
    out->arlock = top->m_axi_arlock;
    out->arcache = top->m_axi_arcache;
    out->arprot = top->m_axi_arprot;
    out->arqos = top->m_axi_arqos;
    out->arregion = top->m_axi_arregion;
    out->arvalid = top->m_axi_arvalid;

    out->rready = top->m_axi_rready;
}

#else // !AXION_PLUGIN_HAS_MASTER

void
axion_rtl_master_drive(AxionRtlInstance *, const AxionAxi4MasterInputs *)
{}

void
axion_rtl_master_sample(AxionRtlInstance *, AxionAxi4MasterOutputs *out)
{
    std::memset(out, 0, sizeof(*out));
}

#endif // AXION_PLUGIN_HAS_MASTER

unsigned
axion_rtl_abi_version(void)
{
    return AXION_RTL_PLUGIN_ABI_VERSION;
}

} // extern "C"
