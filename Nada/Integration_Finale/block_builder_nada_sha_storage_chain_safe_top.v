`timescale 1ns/1ps
// Intermediate integration: Sanae's REAL block_builder orchestrates hashing and storage.
// Bouchra's REAL SHA-256 and Khadija/Nada's Genesis-protected BRAM adapter.
// Not the final CAN-FD/KVS/controller integration.
module block_builder_nada_sha_storage_chain_safe_top (
    input wire clk,
    input wire rst,
    input wire tx_valid,
    input wire [63:0] tx_data,
    output wire tx_ready,
    output wire block_done,
    output wire block_failed,
    output wire storage_ok,
    output wire [31:0] next_index,
    output wire [255:0] last_hash,
    output wire [31:0] blocks_stored,
    output wire busy,
    input wire verify_start,
    input wire [3:0] verify_index,
    output wire verify_ready, verify_done, verify_valid,
    output wire verify_link_ok, verify_hash_ok, verify_error
);
    wire builder_ready;
    wire builder_busy;
    wire sha_start, sha_done, sha_busy;
    wire [351:0] header;
    wire [255:0] sha_hash;
    wire store_start, store_done;
    wire [31:0] store_index;
    wire [255:0] store_hash;
    wire [3:0] dbg_state;
    reg seal_delayed;
    wire full = (next_index >= 32'd15);

    wire mem_verify_ready;
    assign verify_ready = mem_verify_ready && !builder_busy && !seal_delayed;
    assign tx_ready = builder_ready && !full && verify_ready && !verify_start;
    assign busy = builder_busy;
    assign block_done = store_done && storage_ok;

    // Transaction must be latched BEFORE seal, otherwise it can be lost.
    always @(posedge clk) begin
        if (rst)
            seal_delayed <= 1'b0;
        else
            seal_delayed <= tx_valid && tx_ready;
    end

    // AUTO_GENESIS=0: Nada's logical block index starts at 0,
    // physical Genesis is already reserved by Khadija's memory at address 0.
    // First user block links to previous_hash=0 (same as blockchain_top convention).
    block_builder_safe #(.AUTO_GENESIS(0)) BUILDER_SANAE (
        .clk(clk), .rst(rst),
        .tx_valid(tx_valid && tx_ready),
        .tx_type(tx_data[55:48]),
        .tx_key(tx_data[47:16]),
        .tx_value(tx_data[15:0]),
        .ready(builder_ready), .hold(1'b0), .seal(seal_delayed),
        .init_valid(1'b1), .init_index(32'd0), .init_hash(256'd0),
        .hash_start(sha_start), .blk_data(header),
        .hash_done(sha_done), .hash_value(sha_hash),
        .store_start(store_start), .blk_index(store_index),
        .blk_hash(store_hash), .store_done(store_done),
        .store_ok(storage_ok), .store_failed(block_failed), .st_full(full),
        .next_index(next_index), .last_hash(last_hash),
        .blocks_stored(blocks_stored), .busy(builder_busy),
        .dbg_state(dbg_state)
    );

    sha256_core #(.MSG_BITS(352)) SHA_BOUCHRA (
        .clk(clk), .rst(rst), .start(sha_start), .message(header),
        .busy(sha_busy), .done(sha_done), .hash(sha_hash)
    );

    blockchain_storage_adapter_chain STORAGE_KHADIJA (
        .clk(clk), .rst(rst), .storage_start(store_start),
        .storage_index(store_index), .storage_header(header),
        .storage_hash(store_hash), .storage_done(store_done),
        .storage_ok(storage_ok),
        .verify_start(verify_start && verify_ready), .verify_index(verify_index),
        .verify_ready(mem_verify_ready), .verify_done(verify_done),
        .verify_valid(verify_valid), .verify_link_ok(verify_link_ok),
        .verify_hash_ok(verify_hash_ok), .verify_error(verify_error)
    );
endmodule
