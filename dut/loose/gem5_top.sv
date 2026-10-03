// AXIOM plugin wrapper: gem5 owns RAM, while the CVA6/NVDLA system owns
// instruction execution and both AXI masters behind its local crossbar.
module gem5_top (
    input logic clk_i, rst_ni,
    input logic [7:0] s_axi_awid,
    input logic [63:0] s_axi_awaddr,
    input logic [7:0] s_axi_awlen,
    input logic [2:0] s_axi_awsize,
    input logic [1:0] s_axi_awburst,
    input logic s_axi_awlock,
    input logic [3:0] s_axi_awcache,
    input logic [2:0] s_axi_awprot,
    input logic [3:0] s_axi_awqos, s_axi_awregion,
    input logic s_axi_awvalid,
    output logic s_axi_awready,
    input logic [63:0] s_axi_wdata,
    input logic [7:0] s_axi_wstrb,
    input logic s_axi_wlast, s_axi_wvalid,
    output logic s_axi_wready,
    output logic [7:0] s_axi_bid,
    output logic [1:0] s_axi_bresp,
    output logic s_axi_bvalid,
    input logic s_axi_bready,
    input logic [7:0] s_axi_arid,
    input logic [63:0] s_axi_araddr,
    input logic [7:0] s_axi_arlen,
    input logic [2:0] s_axi_arsize,
    input logic [1:0] s_axi_arburst,
    input logic s_axi_arlock,
    input logic [3:0] s_axi_arcache,
    input logic [2:0] s_axi_arprot,
    input logic [3:0] s_axi_arqos, s_axi_arregion,
    input logic s_axi_arvalid,
    output logic s_axi_arready,
    output logic [7:0] s_axi_rid,
    output logic [63:0] s_axi_rdata,
    output logic [1:0] s_axi_rresp,
    output logic s_axi_rlast, s_axi_rvalid,
    input logic s_axi_rready,
    output logic [8:0] m_axi_awid,
    output logic [63:0] m_axi_awaddr,
    output logic [7:0] m_axi_awlen,
    output logic [2:0] m_axi_awsize,
    output logic m_axi_awlock,
    output logic [3:0] m_axi_awcache,
    output logic [2:0] m_axi_awprot,
    output logic [3:0] m_axi_awqos, m_axi_awregion,
    output logic [1:0] m_axi_awburst,
    output logic m_axi_awvalid,
    input logic m_axi_awready,
    output logic [63:0] m_axi_wdata,
    output logic [7:0] m_axi_wstrb,
    output logic m_axi_wlast, m_axi_wvalid,
    input logic m_axi_wready,
    input logic [8:0] m_axi_bid,
    input logic [1:0] m_axi_bresp,
    input logic m_axi_bvalid,
    output logic m_axi_bready,
    output logic [8:0] m_axi_arid,
    output logic [63:0] m_axi_araddr,
    output logic [7:0] m_axi_arlen,
    output logic [1:0] m_axi_arburst,
    output logic [2:0] m_axi_arsize,
    output logic m_axi_arlock,
    output logic [3:0] m_axi_arcache,
    output logic [2:0] m_axi_arprot,
    output logic [3:0] m_axi_arqos, m_axi_arregion,
    output logic m_axi_arvalid,
    input logic m_axi_arready,
    input logic [8:0] m_axi_rid,
    input logic [63:0] m_axi_rdata,
    input logic [1:0] m_axi_rresp,
    input logic m_axi_rlast, m_axi_rvalid,
    output logic m_axi_rready
);
    logic [63:0] program_counter;
    logic illegal_instr, cpu_done, nvdla_irq;
    logic run_q, done_q;
    logic [63:0] cycles_q, done_cycles_q;
    logic aw_pending_q, w_pending_q;
    logic [7:0] aw_id_q;
    logic [63:0] aw_addr_q, w_data_q;
    typedef struct packed {
        logic [8:0] id;
        logic [63:0] data;
        logic [1:0] resp;
        logic last;
    } read_beat_t;
    read_beat_t read_fifo [0:255];
    logic [7:0] read_wr_q, read_rd_q;
    logic [8:0] read_count_q;
    logic [10:0] write_fifo [0:15];
    logic [3:0] write_wr_q, write_rd_q;
    logic [4:0] write_count_q;
    logic [8:0] core_rid, core_bid;
    logic [63:0] core_rdata;
    logic [1:0] core_rresp, core_bresp;
    logic core_rlast, core_rvalid, core_rready;
    logic core_bvalid, core_bready;

    // AXIOM's DMA bridge samples READY after the edge. Keep its response
    // READY asserted and absorb beats here so CVA6 may apply backpressure.
    // Overflow is fatal, never a silently dropped AXI response.
    assign m_axi_rready = 1'b1;
    assign m_axi_bready = 1'b1;
    assign core_rvalid = read_count_q != 0;
    assign {core_rid, core_rdata, core_rresp, core_rlast} = read_fifo[read_rd_q];
    assign core_bvalid = write_count_q != 0;
    assign {core_bid, core_bresp} = write_fifo[write_rd_q];

    // The plugin's PIO port only starts the preloaded bare-metal system and
    // exposes its progress. It is outside the CVA6 control path being tested.
    assign s_axi_awready = !aw_pending_q && !s_axi_bvalid;
    assign s_axi_wready = !w_pending_q && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;
    assign s_axi_bresp = 2'b00;
    assign s_axi_rresp = 2'b00;
    assign s_axi_rlast = 1'b1;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            run_q <= 0;
            done_q <= 0;
            cycles_q <= 0;
            done_cycles_q <= 0;
            aw_pending_q <= 0;
            w_pending_q <= 0;
            s_axi_bvalid <= 0;
            s_axi_bid <= 0;
            s_axi_rvalid <= 0;
            s_axi_rid <= 0;
            s_axi_rdata <= 0;
            read_wr_q <= 0;
            read_rd_q <= 0;
            read_count_q <= 0;
            write_wr_q <= 0;
            write_rd_q <= 0;
            write_count_q <= 0;
        end else begin
            if (m_axi_rvalid) begin
                assert (read_count_q < 256) else $fatal(1, "AXI read buffer overflow");
                read_fifo[read_wr_q] <= '{m_axi_rid, m_axi_rdata, m_axi_rresp, m_axi_rlast};
                read_wr_q <= read_wr_q + 1'b1;
            end
            if (core_rvalid && core_rready) read_rd_q <= read_rd_q + 1'b1;
            case ({m_axi_rvalid, core_rvalid && core_rready})
                2'b10: read_count_q <= read_count_q + 1'b1;
                2'b01: read_count_q <= read_count_q - 1'b1;
                default: ;
            endcase
            if (m_axi_bvalid) begin
                assert (write_count_q < 16) else $fatal(1, "AXI write buffer overflow");
                write_fifo[write_wr_q] <= {m_axi_bid, m_axi_bresp};
                write_wr_q <= write_wr_q + 1'b1;
            end
            if (core_bvalid && core_bready) write_rd_q <= write_rd_q + 1'b1;
            case ({m_axi_bvalid, core_bvalid && core_bready})
                2'b10: write_count_q <= write_count_q + 1'b1;
                2'b01: write_count_q <= write_count_q - 1'b1;
                default: ;
            endcase
            if (run_q && !done_q) cycles_q <= cycles_q + 1;
            if (run_q && cpu_done && !done_q) begin
                done_q <= 1;
                done_cycles_q <= cycles_q;
            end
            if (s_axi_awvalid && s_axi_awready) begin
                aw_pending_q <= 1;
                aw_addr_q <= s_axi_awaddr;
                aw_id_q <= s_axi_awid;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_pending_q <= 1;
                w_data_q <= s_axi_wdata;
            end
            if (aw_pending_q && w_pending_q && !s_axi_bvalid) begin
                if (aw_addr_q[5:0] == 0 && w_data_q[0]) run_q <= 1;
                aw_pending_q <= 0;
                w_pending_q <= 0;
                s_axi_bid <= aw_id_q;
                s_axi_bvalid <= 1;
            end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 0;
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1;
                s_axi_rid <= s_axi_arid;
                case (s_axi_araddr[5:0])
                    0: s_axi_rdata <= {60'b0, nvdla_irq, illegal_instr, done_q, run_q};
                    8: s_axi_rdata <= cycles_q;
                    16: s_axi_rdata <= done_cycles_q;
                    24: s_axi_rdata <= program_counter;
                    default: s_axi_rdata <= 0;
                endcase
            end
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 0;
        end
    end

    assign m_axi_awlock = 0;
    assign m_axi_awcache = 0;
    assign m_axi_awprot = 0;
    assign m_axi_awqos = 0;
    assign m_axi_awregion = 0;
    assign m_axi_arlock = 0;
    assign m_axi_arcache = 0;
    assign m_axi_arprot = 0;
    assign m_axi_arqos = 0;
    assign m_axi_arregion = 0;

    system_top i_system (
        .clk_i(clk_i), .rst_ni(rst_ni && run_q),
        .program_counter(program_counter), .illegal_instr(illegal_instr),
        .cpu_done(cpu_done), .nvdla_irq(nvdla_irq),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_awid(m_axi_awid), .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst), .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready), .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast),
        .m_axi_bvalid(core_bvalid), .m_axi_bready(core_bready),
        .m_axi_bid(core_bid), .m_axi_bresp(core_bresp),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_arid(m_axi_arid), .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_rvalid(core_rvalid), .m_axi_rready(core_rready),
        .m_axi_rid(core_rid), .m_axi_rdata(core_rdata),
        .m_axi_rresp(core_rresp), .m_axi_rlast(core_rlast)
    );
endmodule
