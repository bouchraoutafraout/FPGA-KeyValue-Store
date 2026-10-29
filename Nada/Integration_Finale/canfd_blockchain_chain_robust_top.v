`timescale 1ns/1ps
// Functional two-bus integration: CAN-FD request -> real KVS/blockchain -> CAN-FD reply.
// It is NOT a shared physical CAN bus implementation.
module canfd_blockchain_chain_robust_top (
    input wire clk, rst,
    input wire request_can_rx,
    output wire request_ack_drive_low,
    output wire response_can_tx,
    input wire response_can_rx,
    output wire response_tx_done,
    output wire response_ack_error,
    output wire response_tx_busy,
    output wire request_frame_done,
    output wire request_frame_valid,
    output wire [31:0] blockchain_next_index,
    output wire [255:0] blockchain_last_hash,
    input wire verify_start,
    input wire [3:0] verify_index,
    output wire verify_ready, verify_done, verify_valid,
    output wire verify_link_ok, verify_hash_ok, verify_error
);
    wire [63:0] rx_payload;
    wire [3:0] rx_dlc;
    wire rx_crc_ok, rx_stuff_error, rx_fsb_error;
    canfd_rx #(.CLK_FREQ(100_000_000), .BIT_RATE(1_000_000),
               .PAYLOAD_BITS(86), .FRAME_BITS(127)) REQUEST_RX (
        .clk(clk), .rst(rst), .can_rx(request_can_rx),
        .rx_data(rx_payload), .rx_dlc(rx_dlc),
        .ack_drive_low(request_ack_drive_low),
        .frame_done(request_frame_done), .frame_valid(request_frame_valid),
        .crc_ok(rx_crc_ok), .stuff_error(rx_stuff_error), .fsb_error(rx_fsb_error)
    );
    wire [7:0] rx_byte;
    wire rx_byte_valid, rx_byte_done, rx_byte_error;
    canfd_rx_adapter ADAPT (
        .clk(clk), .rst(rst), .can_data(rx_payload), .can_dlc(rx_dlc),
        .can_frame_done(request_frame_done), .can_frame_valid(request_frame_valid),
        .rx_data(rx_byte), .rx_valid(rx_byte_valid),
        .rx_frame_done(rx_byte_done), .rx_error(rx_byte_error)
    );
    wire [7:0] ck_cmd;
    wire [31:0] ck_key;
    wire [15:0] ck_value;
    wire ck_start;
    wire ck_busy, ck_done, ck_found, ck_error;
    wire [15:0] ck_value_out;
    wire resp_valid, resp_ready;
    wire [7:0] resp_cmd, resp_status;
    wire [15:0] resp_value;
    cmd_decoder #(.TIMEOUT(65535)) DEC (
        .clk(clk), .rst(rst),
        .rx_data(rx_byte), .rx_valid(rx_byte_valid),
        .rx_frame_done(rx_byte_done), .rx_error(rx_byte_error),
        .ck_cmd(ck_cmd), .ck_key(ck_key), .ck_value(ck_value),
        .ck_start(ck_start), .ck_busy(ck_busy), .ck_done(ck_done),
        .ck_found(ck_found), .ck_error(ck_error), .ck_value_out(ck_value_out),
        .resp_valid(resp_valid), .resp_ready(resp_ready),
        .resp_cmd(resp_cmd), .resp_status(resp_status), .resp_value(resp_value)
    );
    // Bridge from decoder's KVS protocol to blockchain transactions or SEARCH.
    localparam [2:0] B_IDLE=0, B_TX_SEND=1, B_TX_WAIT=2,
                     B_SEARCH_SEND=3, B_SEARCH_WAIT=4, B_RESP=5;
    reg [2:0] bs;
    reg [7:0] command_saved;
    reg [31:0] key_saved;
    reg [15:0] value_saved;
    reg ck_done_r, ck_found_r, ck_error_r;
    reg [15:0] ck_value_out_r;
    wire bc_tx_ready, bc_result_valid, bc_result_ok;
    wire [3:0] bc_result_error;
    wire [31:0] bc_result_index;
    wire bc_search_ready, bc_search_done, bc_search_found, bc_search_error;
    wire [15:0] bc_search_value;
    wire bc_busy;
    assign ck_busy = (bs != B_IDLE);
    assign ck_done = ck_done_r;
    assign ck_found = ck_found_r;
    assign ck_error = ck_error_r;
    assign ck_value_out = ck_value_out_r;
    blockchain_kvs_search_chain_robust_top BLOCKCHAIN (
        .clk(clk), .rst(rst),
        .tx_valid(bs == B_TX_SEND), .tx_ready(bc_tx_ready),
        .tx_data({8'd0, command_saved, key_saved, value_saved}),
        .result_valid(bc_result_valid), .result_ready(bs == B_TX_WAIT),
        .result_ok(bc_result_ok), .result_error(bc_result_error),
        .result_index(bc_result_index),
        .search_start(bs == B_SEARCH_SEND), .search_key(key_saved),
        .search_ready(bc_search_ready), .search_done(bc_search_done),
        .search_found(bc_search_found), .search_value(bc_search_value),
        .search_error(bc_search_error),
        .next_index(blockchain_next_index), .last_hash(blockchain_last_hash),
        .busy(bc_busy),
        .verify_start(verify_start), .verify_index(verify_index),
        .verify_ready(verify_ready), .verify_done(verify_done),
        .verify_valid(verify_valid), .verify_link_ok(verify_link_ok),
        .verify_hash_ok(verify_hash_ok), .verify_error(verify_error)
    );
    always @(posedge clk) begin
        if (rst) begin
            bs <= B_IDLE;
            command_saved <= 0; key_saved <= 0; value_saved <= 0;
            ck_done_r <= 0; ck_found_r <= 0; ck_error_r <= 0;
            ck_value_out_r <= 0;
        end else begin
            ck_done_r <= 1'b0;
            case (bs)
                B_IDLE: if (ck_start) begin
                    command_saved <= ck_cmd;
                    key_saved <= ck_key;
                    value_saved <= ck_value;
                    if (ck_cmd == 8'h02) bs <= B_SEARCH_SEND;
                    else bs <= B_TX_SEND;
                end
                B_TX_SEND: begin
                    if (blockchain_next_index >= 32'd15) begin
                        // Full blockchain: refuse without running KVS validator.
                        // Return ck_done to avoid waiting forever in cmd_decoder.
                        ck_found_r <= 1'b0;
                        ck_error_r <= 1'b1;
                        ck_value_out_r <= 16'd0;
                        ck_done_r <= 1'b1;
                        bs <= B_RESP;
                    end else if (bc_tx_ready)
                        bs <= B_TX_WAIT;
                end
                B_TX_WAIT: if (bc_result_valid) begin
                    ck_found_r <= bc_result_ok;
                    ck_error_r <= !bc_result_ok;
                    ck_value_out_r <= 16'd0;
                    ck_done_r <= 1'b1;
                    bs <= B_RESP;
                end
                B_SEARCH_SEND: if (bc_search_ready) bs <= B_SEARCH_WAIT;
                B_SEARCH_WAIT: if (bc_search_done) begin
                    ck_found_r <= bc_search_found;
                    ck_error_r <= bc_search_error;
                    ck_value_out_r <= bc_search_value;
                    ck_done_r <= 1'b1;
                    bs <= B_RESP;
                end
                B_RESP: bs <= B_IDLE;
                default: bs <= B_IDLE;
            endcase
        end
    end
    wire [63:0] response_data;
    wire [3:0] response_dlc;
    wire response_start, response_encoder_busy;
    canfd_response_encoder ENC (
        .clk(clk), .rst(rst), .resp_valid(resp_valid), .resp_ready(resp_ready),
        .resp_cmd(resp_cmd), .resp_status(resp_status), .resp_value(resp_value),
        .tx_busy(response_tx_busy), .tx_start(response_start),
        .tx_data(response_data), .tx_dlc(response_dlc),
        .encoder_busy(response_encoder_busy)
    );
    canfd_tx #(.CLK_FREQ(100_000_000)) RESPONSE_TX (
        .clk(clk), .rst(rst), .start(response_start), .can_id(11'h124),
        .data(response_data), .dlc(response_dlc), .can_rx(response_can_rx),
        .can_tx(response_can_tx), .busy(response_tx_busy),
        .done(response_tx_done), .ack_error(response_ack_error)
    );
endmodule
