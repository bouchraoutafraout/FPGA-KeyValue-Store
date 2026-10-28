`timescale 1ns/1ps
// Adapter for Khadija's append-only storage (Genesis at physical slot 0).
// Controller logical index 0 is stored at physical slot 1.
module blockchain_storage_adapter (
    input wire clk,
    input wire rst,
    input wire storage_start,
    input wire [31:0] storage_index,
    input wire [351:0] storage_header,
    input wire [255:0] storage_hash,
    output wire storage_done,
    output reg storage_ok
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
    wire rd_en = (state == READ_REQ);

    assign storage_done = (state == RESULT);

    blockchain_storage #(.ADDR_WIDTH(4), .DATA_WIDTH(608)) STORAGE (
        .clk(clk), .rst(rst),
        .wr_en(wr_en), .block_data_in(saved_data),
        .wr_ready(wr_ready), .wr_err(wr_err),
        .rd_en(rd_en), .block_index(saved_addr),
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
                IDLE: if (storage_start) begin
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
endmodule
