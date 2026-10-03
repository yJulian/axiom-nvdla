// Pin-level adapter around the generated nv_small NV_nvdla RTL.
// The DBB interface is AXI4 without response-code pins; NVDLA treats all
// accepted responses as successful.  Keep those pins on the shell so the
// same external memory model can be shared with CVA6.
module nvdla_shell (
    input  logic clk_i, rst_ni,
    input  logic csb_valid,
    output logic csb_ready,
    input  logic [15:0] csb_addr,
    input  logic [31:0] csb_wdata,
    input  logic csb_write, csb_nposted,
    output logic csb_resp_valid,
    output logic [31:0] csb_resp_data,
    output logic csb_wr_complete,
    output logic irq,

    output logic m_axi_awvalid,
    input  logic m_axi_awready,
    output logic [7:0] m_axi_awid,
    output logic [31:0] m_axi_awaddr,
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
    input  logic [7:0] m_axi_bid,
    input  logic [1:0] m_axi_bresp,
    output logic m_axi_arvalid,
    input  logic m_axi_arready,
    output logic [7:0] m_axi_arid,
    output logic [31:0] m_axi_araddr,
    output logic [7:0] m_axi_arlen,
    output logic [2:0] m_axi_arsize,
    output logic [1:0] m_axi_arburst,
    input  logic m_axi_rvalid,
    output logic m_axi_rready,
    input  logic [7:0] m_axi_rid,
    input  logic [63:0] m_axi_rdata,
    input  logic [1:0] m_axi_rresp,
    input  logic m_axi_rlast
);
    logic [3:0] raw_awlen, raw_arlen;

    assign m_axi_awlen = {4'b0, raw_awlen};
    assign m_axi_arlen = {4'b0, raw_arlen};
    assign m_axi_awsize = 3'd3;
    assign m_axi_arsize = 3'd3;
    assign m_axi_awburst = 2'b01;
    assign m_axi_arburst = 2'b01;

    NV_nvdla i_nvdla (
        .dla_core_clk(clk_i),
        .dla_csb_clk(clk_i),
        .global_clk_ovr_on(1'b0),
        .tmc2slcg_disable_clock_gating(1'b0),
        .dla_reset_rstn(rst_ni),
        .direct_reset_(rst_ni),
        .test_mode(1'b0),
        .csb2nvdla_valid(csb_valid),
        .csb2nvdla_ready(csb_ready),
        .csb2nvdla_addr(csb_addr),
        .csb2nvdla_wdat(csb_wdata),
        .csb2nvdla_write(csb_write),
        .csb2nvdla_nposted(csb_nposted),
        .nvdla2csb_valid(csb_resp_valid),
        .nvdla2csb_data(csb_resp_data),
        .nvdla2csb_wr_complete(csb_wr_complete),
        .nvdla_core2dbb_aw_awvalid(m_axi_awvalid),
        .nvdla_core2dbb_aw_awready(m_axi_awready),
        .nvdla_core2dbb_aw_awid(m_axi_awid),
        .nvdla_core2dbb_aw_awlen(raw_awlen),
        .nvdla_core2dbb_aw_awaddr(m_axi_awaddr),
        .nvdla_core2dbb_w_wvalid(m_axi_wvalid),
        .nvdla_core2dbb_w_wready(m_axi_wready),
        .nvdla_core2dbb_w_wdata(m_axi_wdata),
        .nvdla_core2dbb_w_wstrb(m_axi_wstrb),
        .nvdla_core2dbb_w_wlast(m_axi_wlast),
        .nvdla_core2dbb_b_bvalid(m_axi_bvalid),
        .nvdla_core2dbb_b_bready(m_axi_bready),
        .nvdla_core2dbb_b_bid(m_axi_bid),
        .nvdla_core2dbb_ar_arvalid(m_axi_arvalid),
        .nvdla_core2dbb_ar_arready(m_axi_arready),
        .nvdla_core2dbb_ar_arid(m_axi_arid),
        .nvdla_core2dbb_ar_arlen(raw_arlen),
        .nvdla_core2dbb_ar_araddr(m_axi_araddr),
        .nvdla_core2dbb_r_rvalid(m_axi_rvalid),
        .nvdla_core2dbb_r_rready(m_axi_rready),
        .nvdla_core2dbb_r_rid(m_axi_rid),
        .nvdla_core2dbb_r_rdata(m_axi_rdata),
        .nvdla_core2dbb_r_rlast(m_axi_rlast),
        .dla_intr(irq),
        .nvdla_pwrbus_ram_c_pd(32'b0),
        .nvdla_pwrbus_ram_ma_pd(32'b0),
        .nvdla_pwrbus_ram_mb_pd(32'b0),
        .nvdla_pwrbus_ram_p_pd(32'b0),
        .nvdla_pwrbus_ram_o_pd(32'b0),
        .nvdla_pwrbus_ram_a_pd(32'b0)
    );
endmodule
