`timescale 1ns/1ps
// Standalone hardware integration prototype: real BRAM + real chain_validator.
// It does NOT replace the controller's existing storage adapter automatically.
// Physical slot 0 = Genesis, logical block N = physical N+1.
// Verify requests must not overlap writes. verify_done pulses once per request.
module blockchain_storage_chain_verify (
    input wire clk, rst,
    input wire wr_en,
    input wire [607:0] block_data_in,
    output wire wr_ready, output wire wr_err,
    output wire [4:0] block_count, output wire full,
    input wire verify_start,
    input wire [3:0] verify_index,
    output wire verify_busy,
    output reg verify_done,
    output reg verify_valid,
    output reg verify_link_ok,
    output reg verify_hash_ok,
    output reg verify_error,
    output reg [255:0] verify_computed_hash
);
    localparam IDLE=3'd0, PREV_REQ=3'd1, PREV_WAIT=3'd2,
               CUR_REQ=3'd3, CUR_WAIT=3'd4, SHA_START=3'd5,
               SHA_WAIT=3'd6, COMPLETE=3'd7;
    reg [2:0] state;
    reg [3:0] logical_index;
    reg [255:0] expected_hash;
    reg [607:0] current_data;
    wire [607:0] rd_data;
    wire rd_valid,rd_err;
    wire [3:0] rd_addr = (state==PREV_REQ || state==PREV_WAIT) ? logical_index : (logical_index + 4'd1);
    wire rd_en = (state==PREV_REQ || state==CUR_REQ);
    // Protect against writes during verification; do not silently lose user writes.
    wire storage_wr_en = wr_en && (state==IDLE) && !verify_start;
    assign wr_ready = storage_ready && (state==IDLE) && !verify_start;
    wire storage_ready;
    assign verify_busy = (state != IDLE);
    blockchain_storage #(.ADDR_WIDTH(4),.DATA_WIDTH(608)) STORAGE (
        .clk(clk),.rst(rst),.wr_en(storage_wr_en),.block_data_in(block_data_in),
        .wr_ready(storage_ready),.wr_err(wr_err),
        .rd_en(rd_en),.block_index(rd_addr),.block_data_out(rd_data),
        .rd_valid(rd_valid),.rd_err(rd_err),.block_count(block_count),.full(full)
    );
    wire v_busy,v_done,v_link_ok,v_hash_ok,v_valid;
    wire [255:0] v_hash;
    chain_validator VALIDATOR (
        .clk(clk),.rst(rst),.start(state==SHA_START),
        .index(current_data[607:576]),
        .previous_hash(current_data[575:320]),
        .transaction(current_data[319:256]),
        .stored_hash(current_data[255:0]),
        .expected_previous_hash(expected_hash),
        .busy(v_busy),.done(v_done),.link_ok(v_link_ok),
        .hash_ok(v_hash_ok),.chain_valid(v_valid),.computed_hash(v_hash)
    );
    always @(posedge clk) begin
        if (rst) begin
            state<=IDLE;logical_index<=0;expected_hash<=0;current_data<=0;
            verify_done<=0;verify_valid<=0;verify_link_ok<=0;
            verify_hash_ok<=0;verify_error<=0;verify_computed_hash<=0;
        end else begin
            verify_done<=0;
            case(state)
                IDLE: if(verify_start) begin
                    logical_index<=verify_index;
                    verify_valid<=0;verify_error<=0;
                    verify_link_ok<=0;verify_hash_ok<=0;
                    if ({1'b0,verify_index}+5'd1 >= block_count) begin
                        verify_error<=1;state<=COMPLETE;
                    end else if(verify_index==0) begin
                        expected_hash<=256'd0;state<=CUR_REQ;
                    end else state<=PREV_REQ;
                end
                PREV_REQ:state<=PREV_WAIT;
                PREV_WAIT:if(rd_valid && !rd_err) begin
                    expected_hash<=rd_data[255:0];state<=CUR_REQ;
                end else if(rd_err) begin verify_error<=1;state<=COMPLETE;end
                CUR_REQ:state<=CUR_WAIT;
                CUR_WAIT:if(rd_valid && !rd_err) begin
                    current_data<=rd_data;state<=SHA_START;
                end else if(rd_err) begin verify_error<=1;state<=COMPLETE;end
                SHA_START:state<=SHA_WAIT;
                SHA_WAIT:if(v_done) begin
                    verify_link_ok<=v_link_ok;
                    verify_hash_ok<=v_hash_ok && (current_data[607:576]=={28'd0,logical_index});
                    verify_valid<=v_valid && (current_data[607:576]=={28'd0,logical_index});
                    verify_computed_hash<=v_hash;
                    state<=COMPLETE;
                end
                COMPLETE:begin verify_done<=1;state<=IDLE;end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
