`timescale 1ns/1ps
// Integration wrapper for CAN-FD -> blockchain FSM -> Khadija's Storage V2.
// WARNING: KVS is still executed independently, and validator/builder/SHA
// remain external. This is not atomic, secure blockchain operation.
module blockchain_system_storage_v2_top (
    input wire clk, rst,
    input wire request_can_rx,
    output wire request_ack_drive_low,
    output wire response_can_tx,
    input wire response_can_rx,
    output wire response_tx_done, response_ack_error,
    output wire request_frame_done, request_frame_valid,
    output wire ingress_overflow,
    output wire validator_start,
    output wire [63:0] validator_tx,
    input wire validator_done, validator_accept,
    output wire builder_start,
    output wire [31:0] builder_index,
    output wire [255:0] builder_prev_hash,
    output wire [63:0] builder_tx,
    input wire builder_done,
    input wire [351:0] builder_header,
    output wire sha_start,
    output wire [351:0] sha_message,
    input wire sha_done,
    input wire [255:0] sha_hash,
    output wire storage_start,
    output wire [31:0] storage_index,
    output wire [351:0] storage_header,
    output wire [255:0] storage_hash,
    output wire chain_result_valid,
    input wire chain_result_ready,
    output wire chain_result_ok,
    output wire [7:0] chain_result_status,
    output wire [31:0] chain_result_index,
    output wire [255:0] chain_result_hash,
    output wire [31:0] next_index,
    output wire [255:0] previous_hash
);
    wire storage_done, storage_ok;

    blockchain_system_top SYSTEM (
        .clk(clk), .rst(rst),
        .request_can_rx(request_can_rx),
        .request_ack_drive_low(request_ack_drive_low),
        .response_can_tx(response_can_tx),
        .response_can_rx(response_can_rx),
        .response_tx_done(response_tx_done),
        .response_ack_error(response_ack_error),
        .request_frame_done(request_frame_done),
        .request_frame_valid(request_frame_valid),
        .ingress_overflow(ingress_overflow),
        .validator_start(validator_start), .validator_tx(validator_tx),
        .validator_done(validator_done), .validator_accept(validator_accept),
        .builder_start(builder_start), .builder_index(builder_index),
        .builder_prev_hash(builder_prev_hash), .builder_tx(builder_tx),
        .builder_done(builder_done), .builder_header(builder_header),
        .sha_start(sha_start), .sha_message(sha_message),
        .sha_done(sha_done), .sha_hash(sha_hash),
        .storage_start(storage_start), .storage_index(storage_index),
        .storage_header(storage_header), .storage_hash(storage_hash),
        .storage_done(storage_done), .storage_ok(storage_ok),
        .chain_result_valid(chain_result_valid),
        .chain_result_ready(chain_result_ready),
        .chain_result_ok(chain_result_ok),
        .chain_result_status(chain_result_status),
        .chain_result_index(chain_result_index),
        .chain_result_hash(chain_result_hash),
        .next_index(next_index), .previous_hash(previous_hash)
    );

    blockchain_storage_adapter STORE (
        .clk(clk), .rst(rst),
        .storage_start(storage_start),
        .storage_index(storage_index),
        .storage_header(storage_header),
        .storage_hash(storage_hash),
        .storage_done(storage_done),
        .storage_ok(storage_ok)
    );
endmodule
