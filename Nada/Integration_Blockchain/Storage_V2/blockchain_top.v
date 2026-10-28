`timescale 1ns/1ps
// Integration controller only. External modules implement real validation,
// block building, SHA-256 and storage. No cryptographic logic is faked here.
module blockchain_top (
    input  wire         clk,
    input  wire         rst,
    // Transaction ingress (one transaction = 64 bits)
    input  wire         tx_valid,
    output wire         tx_ready,
    input  wire [63:0]  tx_data,
    // Transaction validator (Sanae)
    output wire         validator_start,
    output wire [63:0]  validator_tx,
    input  wire         validator_done,
    input  wire         validator_accept,
    // Block builder (Sanae)
    output wire         builder_start,
    output wire [31:0]  builder_index,
    output wire [255:0] builder_prev_hash,
    output wire [63:0]  builder_tx,
    input  wire         builder_done,
    input  wire [351:0] builder_header,
    // SHA-256 core + input padding (Bouchra)
    output wire         sha_start,
    output wire [351:0] sha_message,
    input  wire         sha_done,
    input  wire [255:0] sha_hash,
    // Blockchain storage (Khadija)
    output wire         storage_start,
    output wire [31:0]  storage_index,
    output wire [351:0] storage_header,
    output wire [255:0] storage_hash,
    input  wire         storage_done,
    input  wire         storage_ok,
    // Result to CAN-FD response path (Nada)
    output wire         result_valid,
    input  wire         result_ready,
    output reg          result_ok,
    output reg [7:0]    result_status,
    output reg [31:0]   result_index,
    output reg [255:0]  result_hash,
    output wire         busy,
    output reg [31:0]   next_index,
    output reg [255:0]  previous_hash
);
    // Status: 00 success; 01 rejected; 02 storage failure.
    localparam [3:0] IDLE=4'd0, VAL_START=4'd1, VAL_WAIT=4'd2,
        BUILD_START=4'd3, BUILD_WAIT=4'd4,
        HASH_START=4'd5, HASH_WAIT=4'd6,
        STORE_START=4'd7, STORE_WAIT=4'd8, RESP=4'd9;

    reg [3:0] state;
    reg [63:0] saved_tx;
    reg [351:0] saved_header;
    reg [255:0] saved_hash;

    assign tx_ready = (state == IDLE);
    assign busy = (state != IDLE);
    assign validator_start = (state == VAL_START);
    assign validator_tx = saved_tx;
    assign builder_start = (state == BUILD_START);
    assign builder_index = next_index;
    assign builder_prev_hash = previous_hash;
    assign builder_tx = saved_tx;
    assign sha_start = (state == HASH_START);
    assign sha_message = saved_header;
    assign storage_start = (state == STORE_START);
    assign storage_index = next_index;
    assign storage_header = saved_header;
    assign storage_hash = saved_hash;
    assign result_valid = (state == RESP);

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            saved_tx <= 64'd0;
            saved_header <= 352'd0;
            saved_hash <= 256'd0;
            next_index <= 32'd0;
            previous_hash <= 256'd0; // Genesis predecessor convention
            result_ok <= 1'b0;
            result_status <= 8'd0;
            result_index <= 32'd0;
            result_hash <= 256'd0;
        end else begin
            case (state)
                IDLE: if (tx_valid) begin
                    saved_tx <= tx_data;
                    state <= VAL_START;
                end
                VAL_START: state <= VAL_WAIT;
                VAL_WAIT: if (validator_done) begin
                    if (validator_accept) state <= BUILD_START;
                    else begin
                        result_ok <= 1'b0;
                        result_status <= 8'h01;
                        result_index <= next_index;
                        result_hash <= previous_hash;
                        state <= RESP;
                    end
                end
                BUILD_START: state <= BUILD_WAIT;
                BUILD_WAIT: if (builder_done) begin
                    saved_header <= builder_header;
                    state <= HASH_START;
                end
                HASH_START: state <= HASH_WAIT;
                HASH_WAIT: if (sha_done) begin
                    saved_hash <= sha_hash;
                    state <= STORE_START;
                end
                STORE_START: state <= STORE_WAIT;
                STORE_WAIT: if (storage_done) begin
                    result_ok <= storage_ok;
                    result_status <= storage_ok ? 8'h00 : 8'h02;
                    result_index <= next_index;
                    result_hash <= saved_hash;
                    if (storage_ok) begin
                        previous_hash <= saved_hash;
                        next_index <= next_index + 32'd1;
                    end
                    state <= RESP;
                end
                RESP: if (result_ready) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
