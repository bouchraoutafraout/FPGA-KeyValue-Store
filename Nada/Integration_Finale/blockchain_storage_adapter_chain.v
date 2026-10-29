`timescale 1ns/1ps
// Adapter for Khadija's append-only storage (Genesis at physical slot 0).
// Controller logical index 0 is stored at physical slot 1.
module blockchain_storage_adapter_chain (
    input wire clk,
    input wire rst,
    input wire storage_start,
    input wire [31:0] storage_index,
    input wire [351:0] storage_header,
    input wire [255:0] storage_hash,
    output wire storage_done,
    output reg storage_ok,
    input wire verify_start,
    input wire [3:0] verify_index,
    output wire verify_ready,
    output reg verify_done,
    output reg verify_valid,
    output reg verify_link_ok,
    output reg verify_hash_ok,
    output reg verify_error
);
    localparam [2:0] IDLE=3'd0, WRITE=3'd1, READ_REQ=3'd2,
                     READ_WAIT=3'd3, CHECK=3'd4, RESULT=3'd5;
    reg [2:0] state;
    reg [607:0] saved_data;
    reg [3:0] saved_addr;
    reg accepted_write;

    wire wr_ready, wr_err, rd_valid, rd_err, full;
    wire [4:0] block_count;
    wire [607:0] read_data;
    wire wr_en = (state == WRITE);
    wire rd_en = (state == READ_REQ) || (vstate == V_PREV_REQ) || (vstate == V_CUR_REQ);
    wire [3:0] mux_addr = (state == READ_REQ) ? saved_addr :
        (vstate == V_PREV_REQ || vstate == V_PREV_WAIT) ? v_index : v_index + 4'd1;
    localparam [2:0] V_IDLE=0, V_PREV_REQ=1, V_PREV_WAIT=2,
                     V_CUR_REQ=3, V_CUR_WAIT=4, V_SHA_START=5,
                     V_SHA_WAIT=6, V_RESULT=7;
    reg [2:0] vstate;
    reg [3:0] v_index;
    reg [255:0] expected_prev_hash;
    reg [607:0] verify_block;
    wire v_done, v_busy, v_link, v_hash_ok, v_valid;
    wire [255:0] v_computed;
    assign verify_ready = (state == IDLE) && (vstate == V_IDLE) && !storage_start;
    chain_validator VERIFY_CHAIN (
        .clk(clk), .rst(rst), .start(vstate == V_SHA_START),
        .index(verify_block[607:576]),
        .previous_hash(verify_block[575:320]),
        .transaction(verify_block[319:256]),
        .stored_hash(verify_block[255:0]),
        .expected_previous_hash(expected_prev_hash),
        .busy(v_busy), .done(v_done), .link_ok(v_link),
        .hash_ok(v_hash_ok), .chain_valid(v_valid), .computed_hash(v_computed)
    );

    assign storage_done = (state == RESULT);

    blockchain_storage #(.ADDR_WIDTH(4), .DATA_WIDTH(608)) STORAGE (
        .clk(clk), .rst(rst),
        .wr_en(wr_en), .block_data_in(saved_data),
        .wr_ready(wr_ready), .wr_err(wr_err),
        .rd_en(rd_en), .block_index(mux_addr),
        .block_data_out(read_data), .rd_valid(rd_valid), .rd_err(rd_err),
        .block_count(block_count), .full(full)
    );

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            saved_data <= 608'd0;
            saved_addr <= 4'd0;
            accepted_write <= 1'b0;
            storage_ok <= 1'b0;
        end else begin
            case (state)
                IDLE: if (storage_start && vstate == V_IDLE && !verify_start) begin
                    storage_ok <= 1'b0;
                    // Strict append-only, never overwrite Genesis.
                    // Physical address = logical controller index + 1.
                    if (storage_index >= 32'd15 ||
                        {27'd0, block_count} != storage_index + 32'd1 ||
                        !wr_ready || full) begin
                        state <= RESULT;
                    end else begin
                        saved_data <= {storage_header, storage_hash};
                        saved_addr <= storage_index[3:0] + 4'd1;
                        state <= WRITE;
                    end
                end
                WRITE: state <= READ_REQ; // write happens at this clock edge
                READ_REQ: state <= READ_WAIT; // synchronous memory read edge
                READ_WAIT: begin
                    if (rd_valid && !rd_err && !wr_err)
                        state <= CHECK;
                    else if (rd_err || wr_err)
                        state <= RESULT;
                end
                CHECK: begin
                    storage_ok <= (read_data === saved_data);
                    state <= RESULT;
                end
                RESULT: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
    // Verification is read-only and shares the SAME physical BRAM.
    // Requests are only accepted while no store is in progress.
    always @(posedge clk) begin
        if (rst) begin
            vstate <= V_IDLE;
            v_index <= 0;
            expected_prev_hash <= 0;
            verify_block <= 0;
            verify_done <= 0;
            verify_valid <= 0;
            verify_link_ok <= 0;
            verify_hash_ok <= 0;
            verify_error <= 0;
        end else begin
            verify_done <= 0;
            case (vstate)
                V_IDLE: if (verify_start && verify_ready) begin
                    v_index <= verify_index;
                    verify_valid <= 0;
                    verify_link_ok <= 0;
                    verify_hash_ok <= 0;
                    verify_error <= 0;
                    if ({1'b0,verify_index} + 5'd1 >= block_count) begin
                        verify_error <= 1;
                        vstate <= V_RESULT;
                    end else if (verify_index == 0) begin
                        expected_prev_hash <= 256'd0;
                        vstate <= V_CUR_REQ;
                    end else vstate <= V_PREV_REQ;
                end
                V_PREV_REQ: vstate <= V_PREV_WAIT;
                V_PREV_WAIT: if (rd_valid && !rd_err) begin
                    expected_prev_hash <= read_data[255:0];
                    vstate <= V_CUR_REQ;
                end else if (rd_err) begin
                    verify_error <= 1;
                    vstate <= V_RESULT;
                end
                V_CUR_REQ: vstate <= V_CUR_WAIT;
                V_CUR_WAIT: if (rd_valid && !rd_err) begin
                    verify_block <= read_data;
                    vstate <= V_SHA_START;
                end else if (rd_err) begin
                    verify_error <= 1;
                    vstate <= V_RESULT;
                end
                V_SHA_START: vstate <= V_SHA_WAIT;
                V_SHA_WAIT: if (v_done) begin
                    verify_link_ok <= v_link;
                    verify_hash_ok <= v_hash_ok &&
                        (verify_block[607:576] == {28'd0,v_index});
                    verify_valid <= v_valid &&
                        (verify_block[607:576] == {28'd0,v_index});
                    vstate <= V_RESULT;
                end
                V_RESULT: begin
                    verify_done <= 1;
                    vstate <= V_IDLE;
                end
                default: vstate <= V_IDLE;
            endcase
        end
    end
endmodule
