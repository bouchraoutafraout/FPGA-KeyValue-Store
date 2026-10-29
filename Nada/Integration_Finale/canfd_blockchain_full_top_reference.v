`timescale 1ns/1ps

// Two independent CAN-FD links for functional verification:
// request bus -> KVS -> response bus.
// A single physical CAN bus needs arbitration, self-reception handling,
// and an appropriate CAN transceiver; this module does not implement them.
module canfd_blockchain_full_top_reference (
    input  wire        clk,
    input  wire        rst,
    input  wire        request_can_rx,
    output wire        request_ack_drive_low,
    output wire        response_can_tx,
    input  wire        response_can_rx,
    output wire        response_tx_done,
    output wire        response_ack_error,
    output wire        response_tx_busy,
    output wire        request_frame_done,
    output wire        request_frame_valid,
    output wire        response_encoder_busy,
    output wire storage_done,
    output wire [63:0] blockchain_rx_data,
    output wire [3:0] blockchain_rx_dlc
);
    wire        resp_valid;
    wire        resp_ready;
    wire [7:0]  resp_cmd;
    wire [7:0]  resp_status;
    wire [15:0] resp_value;
    wire        request_crc_ok;
    wire        request_stuff_error;
    wire        request_fsb_error;
    wire        adapter_busy;
    wire        ck_busy;
    wire        ck_found;
    wire        ck_error;

    kv_canfd_top KV (
        .clk(clk),
        .rst(rst),
        .can_rx(request_can_rx),
        .ack_drive_low(request_ack_drive_low),
        .resp_valid(resp_valid),
        .resp_ready(resp_ready),
        .resp_cmd(resp_cmd),
        .resp_status(resp_status),
        .resp_value(resp_value),
        .rx_frame_done(request_frame_done),
        .rx_frame_valid(request_frame_valid),
        .rx_crc_ok(request_crc_ok),
        .rx_stuff_error(request_stuff_error),
        .rx_fsb_error(request_fsb_error),
        .adapter_busy(adapter_busy),
        .ck_busy(ck_busy),
        .ck_done(storage_done),
        .ck_found(ck_found),
        .ck_error(ck_error),
.blockchain_rx_data(blockchain_rx_data),
.blockchain_rx_dlc(blockchain_rx_dlc)
    );

    wire [63:0] response_data;
    wire [3:0] response_dlc;
    wire response_start;

    canfd_response_encoder ENC (
        .clk(clk),
        .rst(rst),
        .resp_valid(resp_valid),
        .resp_ready(resp_ready),
        .resp_cmd(resp_cmd),
        .resp_status(resp_status),
        .resp_value(resp_value),
        .tx_busy(response_tx_busy),
        .tx_start(response_start),
        .tx_data(response_data),
        .tx_dlc(response_dlc),
        .encoder_busy(response_encoder_busy)
    );

    canfd_tx #(.CLK_FREQ(100_000_000)) RESPONSE_TX (
        .clk(clk),
        .rst(rst),
        .start(response_start),
        .can_id(11'h124),
        .data(response_data),
        .dlc(response_dlc),
        .can_rx(response_can_rx),
        .can_tx(response_can_tx),
        .busy(response_tx_busy),
        .done(response_tx_done),
        .ack_error(response_ack_error)
    );
endmodule

