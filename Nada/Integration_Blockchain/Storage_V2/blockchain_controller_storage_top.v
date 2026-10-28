`timescale 1ns/1ps
// RTL integration of blockchain controller and 608-bit Genesis-protected storage.
// Validator, builder, and SHA-256 are external RTL interfaces, NOT mocks.
// This is an internal integration top, not an FPGA-pin-level top.
module blockchain_controller_storage_top (
    input  wire         clk,
    input  wire         rst,
    input  wire         tx_valid,
    output wire         tx_ready,
    input  wire [63:0]  tx_data,

    output wire         validator_start,
    output wire [63:0]  validator_tx,
    input  wire         validator_done,
    input  wire         validator_accept,

    output wire         builder_start,
    output wire [31:0]  builder_index,
    output wire [255:0] builder_prev_hash,
    output wire [63:0]  builder_tx,
    input  wire         builder_done,
    input  wire [351:0] builder_header,

    output wire         sha_start,
    output wire [351:0] sha_message,
    input  wire         sha_done,
    input  wire [255:0] sha_hash,

    output wire         result_valid,
    input  wire         result_ready,
    output wire         result_ok,
    output wire [7:0]   result_status,
    output wire [31:0]  result_index,
    output wire [255:0] result_hash,
    output wire         busy,
    output wire [31:0]  next_index,
    output wire [255:0] previous_hash
);
    wire         storage_start;
    wire [31:0]  storage_index;
    wire [351:0] storage_header;
    wire [255:0] storage_hash;
    wire         storage_done;
    wire         storage_ok;

    blockchain_top CONTROLLER (
        .clk(clk), .rst(rst),
        .tx_valid(tx_valid), .tx_ready(tx_ready), .tx_data(tx_data),
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
        .result_valid(result_valid), .result_ready(result_ready),
        .result_ok(result_ok), .result_status(result_status),
        .result_index(result_index), .result_hash(result_hash),
        .busy(busy), .next_index(next_index), .previous_hash(previous_hash)
    );

    blockchain_storage_adapter STORAGE_ADAPTER (
        .clk(clk), .rst(rst),
        .storage_start(storage_start), .storage_index(storage_index),
        .storage_header(storage_header), .storage_hash(storage_hash),
        .storage_done(storage_done), .storage_ok(storage_ok)
    );
endmodule
