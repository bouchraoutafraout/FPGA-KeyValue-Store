`timescale 1ns/1ps
// Integration V1: transaction validator + real Cuckoo KVS +
// real block builder + SHA-256 + Genesis-protected storage.
// No CAN-FD / chain verifier yet. Existing modules remain unchanged.
module blockchain_kvs_real_top (
    input wire clk,
    input wire rst,
    input wire tx_valid,
    output wire tx_ready,
    input wire [63:0] tx_data,
    output wire result_valid,
    input wire result_ready,
    output reg result_ok,
    output reg [3:0] result_error,
    output reg [31:0] result_index,
    output wire [31:0] next_index,
    output wire [255:0] last_hash,
    output wire busy
);
    localparam [1:0] IDLE=2'd0, WAIT_VALID=2'd1,
                     WAIT_STORE=2'd2, RESP=2'd3;
    reg [1:0] state;
    reg [63:0] tx_saved;
    reg start_validator;
    // Remember acceptance pulse until validator_done (one cycle later).
    reg tx_accepted_seen;
    reg [19:0] store_timer;

    wire v_busy, v_done, v_found, v_error, blk_hold;
    wire [3:0] v_err_code, v_dbg;
    wire [15:0] v_value_out;
    wire [7:0] kv_cmd, acc_type;
    wire [31:0] kv_key, acc_key;
    wire [15:0] kv_value, kv_value_out, acc_value;
    wire kv_start, kv_busy, kv_done, kv_found, kv_error;
    wire tx_acc_valid, builder_tx_ready, builder_busy;
    wire block_done, storage_ok;
    wire [31:0] blocks_stored;
    wire [63:0] accepted_tx = {8'd0, acc_type, acc_key, acc_value};

    assign tx_ready = (state == IDLE) && builder_tx_ready;
    assign result_valid = (state == RESP);
    assign busy = (state != IDLE) || builder_busy;

    transaction_validator V_SANAE (
        .clk(clk), .rst(rst),
        .in_cmd(tx_saved[55:48]), .in_key(tx_saved[47:16]),
        .in_value(tx_saved[15:0]), .in_start(start_validator),
        .in_busy(v_busy), .in_done(v_done), .in_found(v_found),
        .in_value_out(v_value_out), .in_error(v_error),
        .in_err_code(v_err_code),
        .kv_cmd(kv_cmd), .kv_key(kv_key), .kv_value(kv_value),
        .kv_start(kv_start), .kv_busy(kv_busy), .kv_done(kv_done),
        .kv_found(kv_found), .kv_value_out(kv_value_out),
        .kv_error(kv_error),
        .blk_ready(builder_tx_ready), .blk_hold(blk_hold),
        .tx_acc_valid(tx_acc_valid), .tx_acc_type(acc_type),
        .tx_acc_key(acc_key), .tx_acc_value(acc_value),
        .dbg_state(v_dbg)
    );

    cuckoo_top KV_REAL (
        .clk(clk), .rst(rst), .cmd(kv_cmd), .key(kv_key),
        .value_in(kv_value), .start(kv_start),
        .busy(kv_busy), .done(kv_done), .found(kv_found),
        .value_out(kv_value_out), .error(kv_error)
    );

    block_builder_nada_sha_storage_top BLOCKS_REAL (
        .clk(clk), .rst(rst),
        .tx_valid(tx_acc_valid), .tx_data(accepted_tx),
        .tx_ready(builder_tx_ready), .block_done(block_done),
        .storage_ok(storage_ok), .next_index(next_index),
        .last_hash(last_hash), .blocks_stored(blocks_stored),
        .busy(builder_busy)
    );

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            tx_saved <= 64'd0;
            start_validator <= 1'b0;
            tx_accepted_seen <= 1'b0;
            store_timer <= 20'd0;
            result_ok <= 1'b0;
            result_error <= 4'd0;
            result_index <= 32'd0;
        end else begin
            start_validator <= 1'b0;
            if (tx_acc_valid) tx_accepted_seen <= 1'b1;
            case (state)
                IDLE: if (tx_valid && tx_ready) begin
                    tx_saved <= tx_data;
                    start_validator <= 1'b1;
                    tx_accepted_seen <= 1'b0;
                    state <= WAIT_VALID;
                end
                WAIT_VALID: if (v_done) begin
                    if (v_err_code == 4'd0 && !v_error && (tx_accepted_seen || tx_acc_valid)) begin
                        // transaction sent to builder on same rising edge
                        store_timer <= 20'd0;
                        state <= WAIT_STORE;
                    end else begin
                        result_ok <= 1'b0;
                        result_error <= v_err_code;
                        result_index <= next_index;
                        state <= RESP;
                    end
                end
                WAIT_STORE: begin
                    store_timer <= store_timer + 1'b1;
                    if (block_done) begin
                        result_ok <= 1'b1;
                        result_error <= 4'd0;
                        result_index <= next_index - 32'd1;
                        state <= RESP;
                    end else if (&store_timer) begin
                        // Timed out waiting for storage. KVS may have been modified;
                        // no rollback is provided by this integration prototype.
                        result_ok <= 1'b0;
                        result_error <= 4'hF;
                        result_index <= next_index;
                        state <= RESP;
                    end
                end
                RESP: if (result_ready) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
