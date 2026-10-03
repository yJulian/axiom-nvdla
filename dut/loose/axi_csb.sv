// Single-outstanding AXI4 register port for NVDLA's 32-bit CSB bus.
// AXI addresses are byte offsets from the NVDLA MMIO base.
module axi_csb #(
    parameter type axi_req_t = logic,
    parameter type axi_resp_t = logic
) (
    input  logic clk_i, rst_ni,
    input  axi_req_t req_i,
    output axi_resp_t resp_o,
    output logic csb_valid,
    input  logic csb_ready,
    output logic [15:0] csb_addr,
    output logic [31:0] csb_wdata,
    output logic csb_write, csb_nposted,
    input  logic csb_resp_valid,
    input  logic [31:0] csb_resp_data
);
    typedef enum logic [2:0] {IDLE, WRITE_DATA, CSB_REQ, CSB_READ, AXI_B, AXI_R} state_t;
    state_t state;
    logic [15:0] addr_q;
    logic [31:0] data_q, read_q;
    logic write_q, upper_q, error_q;
    logic [$bits(req_i.aw.id)-1:0] id_q;

    assign csb_valid = state == CSB_REQ && !error_q;
    assign csb_addr = addr_q;
    assign csb_wdata = data_q;
    assign csb_write = write_q;
    assign csb_nposted = 1'b0;

    always_comb begin
        resp_o = '0;
        resp_o.aw_ready = state == IDLE;
        resp_o.w_ready = state == WRITE_DATA;
        resp_o.ar_ready = state == IDLE && !req_i.aw_valid;
        resp_o.b_valid = state == AXI_B;
        resp_o.b.id = id_q;
        resp_o.b.resp = error_q ? 2'b10 : 2'b00;
        resp_o.r_valid = state == AXI_R;
        resp_o.r.id = id_q;
        resp_o.r.data = upper_q ? {read_q, 32'b0} : {32'b0, read_q};
        resp_o.r.resp = error_q ? 2'b10 : 2'b00;
        resp_o.r.last = 1'b1;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= IDLE;
            addr_q <= '0;
            data_q <= '0;
            read_q <= '0;
            write_q <= 1'b0;
            upper_q <= 1'b0;
            error_q <= 1'b0;
            id_q <= '0;
        end else begin
            case (state)
                IDLE: begin
                    if (req_i.aw_valid) begin
                        addr_q <= req_i.aw.addr[17:2];
                        upper_q <= req_i.aw.addr[2];
                        error_q <= req_i.aw.len != 0 || req_i.aw.size != 3'd2 ||
                                   req_i.aw.addr[1:0] != 0;
                        id_q <= req_i.aw.id;
                        write_q <= 1'b1;
                        state <= WRITE_DATA;
                    end else if (req_i.ar_valid) begin
                        addr_q <= req_i.ar.addr[17:2];
                        upper_q <= req_i.ar.addr[2];
                        error_q <= req_i.ar.len != 0 || req_i.ar.size != 3'd2 ||
                                   req_i.ar.addr[1:0] != 0;
                        id_q <= req_i.ar.id;
                        write_q <= 1'b0;
                        state <= CSB_REQ;
                    end
                end
                WRITE_DATA: if (req_i.w_valid) begin
                    data_q <= upper_q ? req_i.w.data[63:32] : req_i.w.data[31:0];
                    error_q <= error_q || !req_i.w.last ||
                               (upper_q ? req_i.w.strb != 8'hf0 : req_i.w.strb != 8'h0f);
                    state <= CSB_REQ;
                end
                CSB_REQ: if (error_q || csb_ready) begin
                    state <= write_q ? AXI_B : (error_q ? AXI_R : CSB_READ);
                end
                CSB_READ: if (csb_resp_valid) begin
                    read_q <= csb_resp_data;
                    state <= AXI_R;
                end
                AXI_B: if (req_i.b_ready) state <= IDLE;
                AXI_R: if (req_i.r_ready) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
