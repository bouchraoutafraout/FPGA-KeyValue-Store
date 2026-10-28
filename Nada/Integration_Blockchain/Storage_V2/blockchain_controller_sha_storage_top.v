`timescale 1ns/1ps
// Integration RTL: controller Nada + real SHA-256 Bouchra + storage V2 Khadija.
// Transaction validator and block builder remain external interfaces.
module blockchain_controller_sha_storage_top (
    input wire clk, rst,
    input wire tx_valid,
    output wire tx_ready,
    input wire [63:0] tx_data,
    output wire validator_start,
    output wire [63:0] validator_tx,
    input wire validator_done, validator_accept,
    output wire builder_start,
    output wire [31:0] builder_index,
    output wire [255:0] builder_prev_hash,
    output wire [63:0] builder_tx,
    input wire builder_done,
    input wire [351:0] builder_header,
    output wire result_valid,
    input wire result_ready,
    output wire result_ok,
    output wire [7:0] result_status,
    output wire [31:0] result_index,
    output wire [255:0] result_hash,
    output wire busy,
    output wire [31:0] next_index,
    output wire [255:0] previous_hash
);
    wire sha_start, sha_done, sha_busy;
    wire [351:0] sha_message;
    wire [255:0] sha_hash;

    blockchain_controller_storage_top SYSTEM (
        .clk(clk), .rst(rst),
        .tx_valid(tx_valid), .tx_ready(tx_ready), .tx_data(tx_data),
        .validator_start(validator_start), .validator_tx(validator_tx),
        .validator_done(validator_done), .validator_accept(validator_accept),
        .builder_start(builder_start), .builder_index(builder_index),
        .builder_prev_hash(builder_prev_hash), .builder_tx(builder_tx),
        .builder_done(builder_done), .builder_header(builder_header),
        .sha_start(sha_start), .sha_message(sha_message),
        .sha_done(sha_done), .sha_hash(sha_hash),
        .result_valid(result_valid), .result_ready(result_ready),
        .result_ok(result_ok), .result_status(result_status),
        .result_index(result_index), .result_hash(result_hash),
        .busy(busy), .next_index(next_index), .previous_hash(previous_hash)
    );

    sha256_core #(.MSG_BITS(352)) SHA_BOUCHRA (
        .clk(clk), .rst(rst), .start(sha_start),
        .message(sha_message), .busy(sha_busy),
        .done(sha_done), .hash(sha_hash)
    );
endmodule
