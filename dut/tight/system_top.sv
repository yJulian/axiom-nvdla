`include "axi/typedef.svh"

// Tight coupling: CVA6 Custom-0 instructions reach NVDLA CSB through
// CV-X-IF. CPU and NVDLA DMA still share RAM through the AXI crossbar.
module system_top (
    input logic clk_i, rst_ni,
    output logic [63:0] program_counter,
    output logic illegal_instr,
    output logic cpu_done,
    output logic nvdla_irq,
    output logic m_axi_awvalid,
    input  logic m_axi_awready,
    output logic [8:0] m_axi_awid,
    output logic [63:0] m_axi_awaddr,
    output logic [7:0] m_axi_awlen,
    output logic [2:0] m_axi_awsize,
    output logic [1:0] m_axi_awburst,
    output logic m_axi_wvalid,
    input  logic m_axi_wready,
    output logic [63:0] m_axi_wdata,
    output logic [7:0] m_axi_wstrb,
    output logic m_axi_wlast,
    input  logic m_axi_bvalid,
    output logic m_axi_bready,
    input  logic [8:0] m_axi_bid,
    input  logic [1:0] m_axi_bresp,
    output logic m_axi_arvalid,
    input  logic m_axi_arready,
    output logic [8:0] m_axi_arid,
    output logic [63:0] m_axi_araddr,
    output logic [7:0] m_axi_arlen,
    output logic [2:0] m_axi_arsize,
    output logic [1:0] m_axi_arburst,
    input  logic m_axi_rvalid,
    output logic m_axi_rready,
    input  logic [8:0] m_axi_rid,
    input  logic [63:0] m_axi_rdata,
    input  logic [1:0] m_axi_rresp,
    input  logic m_axi_rlast
);
    typedef logic [63:0] addr_t;
    typedef logic [63:0] data_t;
    typedef logic [7:0] strb_t;
    typedef logic [0:0] user_t;
    typedef logic [7:0] slv_id_t;
    typedef logic [8:0] mst_id_t;
    `AXI_TYPEDEF_ALL(slv, addr_t, slv_id_t, data_t, strb_t, user_t)
    `AXI_TYPEDEF_ALL(mst, addr_t, mst_id_t, data_t, strb_t, user_t)
    slv_req_t [1:0] slv_req;
    slv_resp_t [1:0] slv_resp;
    mst_req_t [0:0] mst_req;
    mst_resp_t [0:0] mst_resp;
    logic csb_valid, csb_ready, csb_write, csb_nposted;
    logic csb_resp_valid, csb_wr_complete;
    logic [15:0] csb_addr;
    logic [31:0] csb_wdata, csb_resp_data;

    localparam axi_pkg::xbar_cfg_t XBAR_CFG = '{
        NoSlvPorts: 2, NoMstPorts: 1,
        MaxMstTrans: 4, MaxSlvTrans: 4,
        FallThrough: 1'b0, LatencyMode: axi_pkg::NO_LATENCY,
        AxiIdWidthSlvPorts: 8, AxiIdUsedSlvPorts: 8,
        UniqueIds: 1'b0, AxiAddrWidth: 64, AxiDataWidth: 64,
        NoAddrRules: 1
    };
    localparam axi_pkg::xbar_rule_64_t [0:0] ADDR_MAP = '{
        '{idx: 0, start_addr: 64'h80000000, end_addr: 64'h80100000}
    };

    axi_xbar #(
        .Cfg(XBAR_CFG), .ATOPs(1'b0),
        .slv_aw_chan_t(slv_aw_chan_t), .mst_aw_chan_t(mst_aw_chan_t),
        .w_chan_t(slv_w_chan_t), .slv_b_chan_t(slv_b_chan_t),
        .mst_b_chan_t(mst_b_chan_t), .slv_ar_chan_t(slv_ar_chan_t),
        .mst_ar_chan_t(mst_ar_chan_t), .slv_r_chan_t(slv_r_chan_t),
        .mst_r_chan_t(mst_r_chan_t), .slv_req_t(slv_req_t),
        .slv_resp_t(slv_resp_t), .mst_req_t(mst_req_t),
        .mst_resp_t(mst_resp_t), .rule_t(axi_pkg::xbar_rule_64_t)
    ) i_xbar (
        .clk_i(clk_i), .rst_ni(rst_ni), .test_i(1'b0),
        .slv_ports_req_i(slv_req), .slv_ports_resp_o(slv_resp),
        .mst_ports_req_o(mst_req), .mst_ports_resp_i(mst_resp),
        .addr_map_i(ADDR_MAP), .en_default_mst_port_i('0),
        .default_mst_port_i('0)
    );

    // CVA6's AXI atomics adapter resolves atomics before this crossbar.
    cva6_axi_top i_cpu (
        .clk_i(clk_i), .rst_ni(rst_ni), .boot_addr_i(64'h80000000),
        .hart_id_i(64'b0), .irq_i(2'b0), .ipi_i(1'b0),
        .time_irq_i(1'b0), .debug_req_i(1'b0),
        .ebreak_o(cpu_done), .illegal_instr_o(illegal_instr),
        .program_counter(program_counter),
        .noc_req_aw_valid_o(slv_req[0].aw_valid),
        .noc_req_aw_id_o(slv_req[0].aw.id),
        .noc_req_aw_addr_o(slv_req[0].aw.addr),
        .noc_req_aw_len_o(slv_req[0].aw.len),
        .noc_req_aw_size_o(slv_req[0].aw.size),
        .noc_req_aw_cache_o(slv_req[0].aw.cache),
        .noc_resp_aw_ready_i(slv_resp[0].aw_ready),
        .noc_req_w_valid_o(slv_req[0].w_valid),
        .noc_req_w_data_o(slv_req[0].w.data),
        .noc_req_w_strb_o(slv_req[0].w.strb),
        .noc_req_w_last_o(slv_req[0].w.last),
        .noc_resp_w_ready_i(slv_resp[0].w_ready),
        .noc_resp_b_valid_i(slv_resp[0].b_valid),
        .noc_resp_b_id_i(slv_resp[0].b.id[ariane_axi::IdWidth-1:0]),
        .noc_resp_b_resp_i(slv_resp[0].b.resp),
        .noc_req_b_ready_o(slv_req[0].b_ready),
        .noc_req_ar_valid_o(slv_req[0].ar_valid),
        .noc_req_ar_id_o(slv_req[0].ar.id),
        .noc_req_ar_addr_o(slv_req[0].ar.addr),
        .noc_req_ar_len_o(slv_req[0].ar.len),
        .noc_req_ar_size_o(slv_req[0].ar.size),
        .noc_req_ar_prot_o(slv_req[0].ar.prot),
        .noc_req_ar_cache_o(slv_req[0].ar.cache),
        .noc_resp_ar_ready_i(slv_resp[0].ar_ready),
        .noc_resp_r_valid_i(slv_resp[0].r_valid),
        .noc_resp_r_id_i(slv_resp[0].r.id[ariane_axi::IdWidth-1:0]),
        .noc_resp_r_data_i(slv_resp[0].r.data),
        .noc_resp_r_last_i(slv_resp[0].r.last),
        .noc_resp_r_resp_i(slv_resp[0].r.resp),
        .noc_req_r_ready_o(slv_req[0].r_ready)
        ,.csb_valid(csb_valid), .csb_ready(csb_ready),
        .csb_addr(csb_addr), .csb_wdata(csb_wdata),
        .csb_write(csb_write), .csb_nposted(csb_nposted),
        .csb_resp_valid(csb_resp_valid), .csb_resp_data(csb_resp_data)
    );
    assign slv_req[0].aw.burst = 2'b01;
    assign slv_req[0].aw.lock = 1'b0;
    assign slv_req[0].aw.prot = 3'b0;
    assign slv_req[0].aw.qos = 4'b0;
    assign slv_req[0].aw.region = 4'b0;
    assign slv_req[0].aw.atop = 6'b0;
    assign slv_req[0].aw.user = '0;
    assign slv_req[0].w.user = '0;
    assign slv_req[0].ar.burst = 2'b01;
    assign slv_req[0].ar.lock = 1'b0;
    assign slv_req[0].ar.qos = 4'b0;
    assign slv_req[0].ar.region = 4'b0;
    assign slv_req[0].ar.user = '0;

    nvdla_shell i_nvdla (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .csb_valid(csb_valid), .csb_ready(csb_ready),
        .csb_addr(csb_addr), .csb_wdata(csb_wdata),
        .csb_write(csb_write), .csb_nposted(csb_nposted),
        .csb_resp_valid(csb_resp_valid), .csb_resp_data(csb_resp_data),
        .csb_wr_complete(csb_wr_complete), .irq(nvdla_irq),
        .m_axi_awvalid(slv_req[1].aw_valid),
        .m_axi_awready(slv_resp[1].aw_ready),
        .m_axi_awid(slv_req[1].aw.id),
        .m_axi_awaddr(slv_req[1].aw.addr[31:0]),
        .m_axi_awlen(slv_req[1].aw.len),
        .m_axi_awsize(slv_req[1].aw.size),
        .m_axi_awburst(slv_req[1].aw.burst),
        .m_axi_wvalid(slv_req[1].w_valid),
        .m_axi_wready(slv_resp[1].w_ready),
        .m_axi_wdata(slv_req[1].w.data),
        .m_axi_wstrb(slv_req[1].w.strb),
        .m_axi_wlast(slv_req[1].w.last),
        .m_axi_bvalid(slv_resp[1].b_valid),
        .m_axi_bready(slv_req[1].b_ready),
        .m_axi_bid(slv_resp[1].b.id),
        .m_axi_bresp(slv_resp[1].b.resp),
        .m_axi_arvalid(slv_req[1].ar_valid),
        .m_axi_arready(slv_resp[1].ar_ready),
        .m_axi_arid(slv_req[1].ar.id),
        .m_axi_araddr(slv_req[1].ar.addr[31:0]),
        .m_axi_arlen(slv_req[1].ar.len),
        .m_axi_arsize(slv_req[1].ar.size),
        .m_axi_arburst(slv_req[1].ar.burst),
        .m_axi_rvalid(slv_resp[1].r_valid),
        .m_axi_rready(slv_req[1].r_ready),
        .m_axi_rid(slv_resp[1].r.id),
        .m_axi_rdata(slv_resp[1].r.data),
        .m_axi_rresp(slv_resp[1].r.resp),
        .m_axi_rlast(slv_resp[1].r.last)
    );
    assign slv_req[1].aw.addr[63:32] = '0;
    assign slv_req[1].aw.lock = 1'b0;
    assign slv_req[1].aw.cache = 4'b0;
    assign slv_req[1].aw.prot = 3'b0;
    assign slv_req[1].aw.qos = 4'b0;
    assign slv_req[1].aw.region = 4'b0;
    assign slv_req[1].aw.atop = 6'b0;
    assign slv_req[1].aw.user = '0;
    assign slv_req[1].w.user = '0;
    assign slv_req[1].ar.addr[63:32] = '0;
    assign slv_req[1].ar.lock = 1'b0;
    assign slv_req[1].ar.cache = 4'b0;
    assign slv_req[1].ar.prot = 3'b0;
    assign slv_req[1].ar.qos = 4'b0;
    assign slv_req[1].ar.region = 4'b0;
    assign slv_req[1].ar.user = '0;

    assign m_axi_awvalid = mst_req[0].aw_valid;
    assign m_axi_awid = mst_req[0].aw.id;
    assign m_axi_awaddr = mst_req[0].aw.addr;
    assign m_axi_awlen = mst_req[0].aw.len;
    assign m_axi_awsize = mst_req[0].aw.size;
    assign m_axi_awburst = mst_req[0].aw.burst;
    assign mst_resp[0].aw_ready = m_axi_awready;
    assign m_axi_wvalid = mst_req[0].w_valid;
    assign m_axi_wdata = mst_req[0].w.data;
    assign m_axi_wstrb = mst_req[0].w.strb;
    assign m_axi_wlast = mst_req[0].w.last;
    assign mst_resp[0].w_ready = m_axi_wready;
    assign mst_resp[0].b_valid = m_axi_bvalid;
    assign mst_resp[0].b.id = m_axi_bid;
    assign mst_resp[0].b.resp = m_axi_bresp;
    assign mst_resp[0].b.user = '0;
    assign m_axi_bready = mst_req[0].b_ready;
    assign m_axi_arvalid = mst_req[0].ar_valid;
    assign m_axi_arid = mst_req[0].ar.id;
    assign m_axi_araddr = mst_req[0].ar.addr;
    assign m_axi_arlen = mst_req[0].ar.len;
    assign m_axi_arsize = mst_req[0].ar.size;
    assign m_axi_arburst = mst_req[0].ar.burst;
    assign mst_resp[0].ar_ready = m_axi_arready;
    assign mst_resp[0].r_valid = m_axi_rvalid;
    assign mst_resp[0].r.id = m_axi_rid;
    assign mst_resp[0].r.data = m_axi_rdata;
    assign mst_resp[0].r.resp = m_axi_rresp;
    assign mst_resp[0].r.last = m_axi_rlast;
    assign mst_resp[0].r.user = '0;
    assign m_axi_rready = mst_req[0].r_ready;
endmodule
