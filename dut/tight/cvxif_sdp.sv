// Custom-0 operations for the fixed nv_small 1x1x8 INT8 SDP workload:
//   funct3=0  relu8 rd, rs1(src AXI address), rs2(dst AXI address)
//             Program and launch NVDLA; rd=0 on success, 1 on bad address.
//   funct3=1  wait rd
//             Poll SDP D_OP_ENABLE until it clears; rd=0 or 2 on timeout.
//   funct3=2  conv rd
//             Launch the fixed 13x15x64 x 5x3x64x16 INT8 convolution.
// CSB is used only inside this unit. Software sees a task, not registers.
module cvxif_sdp #(
    parameter type cvxif_req_t = logic,
    parameter type cvxif_resp_t = logic
) (
    input  logic clk_i, rst_ni,
    input  cvxif_req_t cvxif_req_i,
    output cvxif_resp_t cvxif_resp_o,
    output logic csb_valid,
    input  logic csb_ready,
    output logic [15:0] csb_addr,
    output logic [31:0] csb_wdata,
    output logic csb_write, csb_nposted,
    input  logic csb_resp_valid,
    input  logic [31:0] csb_resp_data
);
    typedef enum logic [2:0] {
        IDLE, WAIT_COMMIT, CONFIG_REQ, POLL_REQ, POLL_RESP, RESULT,
        FLUSH_REQ, FLUSH_RESP
    } state_t;
    typedef struct packed {
        logic [15:0] byte_offset;
        logic [31:0] value;
    } csb_command_t;

    localparam logic [5:0] LAST_CONFIG = 6'd32;
    `include "conv_commands.svh"
    localparam logic [19:0] MAX_POLLS = 20'hfffff;
    state_t state;
    logic [7:0] config_index_q;
    logic [19:0] poll_count_q;
    logic [31:0] src_q, dst_q, result_q;
    logic invalid_addr_q, wait_q, conv_q;
    logic [$bits(cvxif_req_i.issue_req.id)-1:0] id_q;
    logic [$bits(cvxif_req_i.issue_req.hartid)-1:0] hartid_q;
    logic [4:0] rd_q;
    logic match_instr, operands_valid, accept_issue, commit_matches;
    csb_command_t command;

    // The same SDP setup used by the loose firmware, now in the instruction
    // unit. Addresses are captured from GPRs at issue, not compiled into RTL.
    function automatic csb_command_t config_command(
        input logic [5:0] index, input logic [31:0] src, dst
    );
        case (index)
            // Select configuration bank 0 for SDP and its input RDMA.
            6'd0:  config_command = {16'h9004, 32'd0};
            6'd1:  config_command = {16'h8004, 32'd0};
            // Output cube and destination address/strides.
            6'd2:  config_command = {16'h903c, 32'd0};
            6'd3:  config_command = {16'h9040, 32'd0};
            6'd4:  config_command = {16'h9044, 32'd7};
            6'd5:  config_command = {16'h9048, dst};
            6'd6:  config_command = {16'h904c, 32'd0};
            6'd7:  config_command = {16'h9050, 32'd8};
            6'd8:  config_command = {16'h9054, 32'd8};
            // BS MAX(operand, 0); bypass the other arithmetic stages.
            6'd9:  config_command = {16'h9058, 32'h10}; // BS ALU MAX zero
            6'd10: config_command = {16'h905c, 32'd0};
            6'd11: config_command = {16'h9060, 32'd0};
            6'd12: config_command = {16'h906c, 32'd1};
            6'd13: config_command = {16'h9080, 32'd1};
            6'd14: config_command = {16'h90b0, 32'd0};
            6'd15: config_command = {16'h90b4, 32'd1};
            6'd16: config_command = {16'h90c0, 32'd0};
            6'd17: config_command = {16'h90c4, 32'd1};
            6'd18: config_command = {16'h90c8, 32'd0};
            // Input cube, source address/strides, and input DMA bypasses.
            6'd19: config_command = {16'h800c, 32'd0};
            6'd20: config_command = {16'h8010, 32'd0};
            6'd21: config_command = {16'h8014, 32'd7};
            6'd22: config_command = {16'h8018, src};
            6'd23: config_command = {16'h801c, 32'd0};
            6'd24: config_command = {16'h8020, 32'd8};
            6'd25: config_command = {16'h8024, 32'd8};
            6'd26: config_command = {16'h8028, 32'd1};
            6'd27: config_command = {16'h8040, 32'd1};
            6'd28: config_command = {16'h8058, 32'd1};
            6'd29: config_command = {16'h8070, 32'd0};
            6'd30: config_command = {16'h8074, 32'd1};
            // Start input DMA before enabling SDP processing.
            6'd31: config_command = {16'h8008, 32'd1}; // start RDMA
            6'd32: config_command = {16'h9038, 32'd1}; // start SDP last
            default: config_command = '0;
        endcase
    endfunction

    assign match_instr = cvxif_req_i.issue_req.instr[6:0] == 7'h0b &&
                         cvxif_req_i.issue_req.instr[31:25] == 7'b0 &&
                         cvxif_req_i.issue_req.instr[14:12] <= 3'd2;
    assign operands_valid = cvxif_req_i.issue_req.instr[14:12] != 3'd0 ||
                            (&cvxif_req_i.register.rs_valid[1:0]);
    assign accept_issue = state == IDLE && cvxif_req_i.issue_valid &&
                          match_instr && operands_valid;
    assign commit_matches = cvxif_req_i.commit_valid &&
                            cvxif_req_i.commit.id == id_q &&
                            cvxif_req_i.commit.hartid == hartid_q;
    assign command = conv_q ? conv_command(config_index_q) :
                            config_command(config_index_q[5:0], src_q, dst_q);
    assign csb_valid = state == CONFIG_REQ || state == POLL_REQ || state == FLUSH_REQ;
    assign csb_addr = state == CONFIG_REQ ? (command.byte_offset >> 2) :
                      state == FLUSH_REQ ? 16'h0c03 : 16'h240e;
    assign csb_wdata = command.value;
    assign csb_write = state == CONFIG_REQ;
    assign csb_nposted = 1'b0;

    always_comb begin
        cvxif_resp_o = '0;
        cvxif_resp_o.compressed_ready = 1'b1;
        cvxif_resp_o.issue_ready = !match_instr || (state == IDLE && operands_valid);
        cvxif_resp_o.register_ready = cvxif_resp_o.issue_ready;
        cvxif_resp_o.issue_resp.accept = match_instr;
        cvxif_resp_o.issue_resp.writeback = match_instr;
        cvxif_resp_o.issue_resp.register_read =
            cvxif_req_i.issue_req.instr[14:12] == 3'd0 ? 2'b11 : 2'b00;
        cvxif_resp_o.result_valid = state == RESULT;
        cvxif_resp_o.result.hartid = hartid_q;
        cvxif_resp_o.result.id = id_q;
        cvxif_resp_o.result.rd = rd_q;
        cvxif_resp_o.result.data = {{($bits(cvxif_resp_o.result.data)-32){1'b0}}, result_q};
        cvxif_resp_o.result.we = 1'b1;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= IDLE;
            config_index_q <= '0;
            poll_count_q <= '0;
            src_q <= '0;
            dst_q <= '0;
            result_q <= '0;
            invalid_addr_q <= '0;
            wait_q <= '0;
            conv_q <= '0;
            id_q <= '0;
            hartid_q <= '0;
            rd_q <= '0;
        end else begin
            case (state)
                IDLE: if (accept_issue) begin
                    src_q <= cvxif_req_i.register.rs[0][31:0];
                    dst_q <= cvxif_req_i.register.rs[1][31:0];
                    invalid_addr_q <= (|cvxif_req_i.register.rs[0][63:32]) ||
                                      (|cvxif_req_i.register.rs[1][63:32]) ||
                                      (|cvxif_req_i.register.rs[0][2:0]) ||
                                      (|cvxif_req_i.register.rs[1][2:0]);
                    wait_q <= cvxif_req_i.issue_req.instr[14:12] == 3'd1;
                    conv_q <= cvxif_req_i.issue_req.instr[14:12] == 3'd2;
                    id_q <= cvxif_req_i.issue_req.id;
                    hartid_q <= cvxif_req_i.issue_req.hartid;
                    rd_q <= cvxif_req_i.issue_req.instr[11:7];
                    result_q <= '0;
                    config_index_q <= '0;
                    poll_count_q <= '0;
                    // CVA6 commits in the issue cycle. WAIT_COMMIT also
                    // covers cores that commit the accepted issue later.
                    if (cvxif_req_i.commit_valid &&
                        cvxif_req_i.commit.id == cvxif_req_i.issue_req.id &&
                        cvxif_req_i.commit.hartid == cvxif_req_i.issue_req.hartid) begin
                        if (cvxif_req_i.commit.commit_kill) state <= IDLE;
                        else if (cvxif_req_i.issue_req.instr[14:12] == 3'd1)
                            state <= POLL_REQ;
                        else if (cvxif_req_i.issue_req.instr[14:12] == 3'd2)
                            state <= CONFIG_REQ;
                        else if ((|cvxif_req_i.register.rs[0][63:32]) ||
                                 (|cvxif_req_i.register.rs[1][63:32]) ||
                                 (|cvxif_req_i.register.rs[0][2:0]) ||
                                 (|cvxif_req_i.register.rs[1][2:0])) begin
                            result_q <= 32'd1;
                            state <= RESULT;
                        end else state <= CONFIG_REQ;
                    end else state <= WAIT_COMMIT;
                end
                WAIT_COMMIT: if (commit_matches) begin
                    if (cvxif_req_i.commit.commit_kill) state <= IDLE;
                    else if (wait_q) state <= POLL_REQ;
                    else if (conv_q) state <= CONFIG_REQ;
                    else if (invalid_addr_q) begin
                        result_q <= 32'd1;
                        state <= RESULT;
                    end else state <= CONFIG_REQ;
                end
                CONFIG_REQ: if (csb_ready) begin
                    if (conv_q && config_index_q == CONV_COMMAND_COUNT-1)
                        state <= RESULT;
                    else if (!conv_q && config_index_q == LAST_CONFIG)
                        state <= RESULT;
                    else if (conv_q && config_index_q == CONV_CONFIG_COUNT-1) begin
                        config_index_q <= config_index_q + 8'd1;
                        state <= FLUSH_REQ;
                    end else config_index_q <= config_index_q + 8'd1;
                end
                FLUSH_REQ: if (csb_ready) state <= FLUSH_RESP;
                FLUSH_RESP: if (csb_resp_valid) begin
                    if (csb_resp_data[0]) state <= CONFIG_REQ;
                    else if (poll_count_q == MAX_POLLS) begin
                        result_q <= 32'd2;
                        state <= RESULT;
                    end else begin
                        poll_count_q <= poll_count_q + 20'd1;
                        state <= FLUSH_REQ;
                    end
                end
                POLL_REQ: if (csb_ready) state <= POLL_RESP;
                POLL_RESP: if (csb_resp_valid) begin
                    if (!csb_resp_data[0]) state <= RESULT;
                    else if (poll_count_q == MAX_POLLS) begin
                        result_q <= 32'd2;
                        state <= RESULT;
                    end else begin
                        poll_count_q <= poll_count_q + 20'd1;
                        state <= POLL_REQ;
                    end
                end
                RESULT: if (cvxif_req_i.result_ready) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
