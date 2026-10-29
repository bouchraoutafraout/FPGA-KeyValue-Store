
module chain_storage_if #(
    parameter ADDR_WIDTH = 4,
    parameter [255:0] GENESIS_HASH =
        256'h85759b3811ff7dc47b03792ac85317be51431a3f9e01dcafce317ed736a391b0
)(
    input wire clk,
    input wire rst,

    input wire store_start,
    input wire [351:0] blk_data,
    input wire [255:0] blk_hash,
    output reg store_done,

    output wire st_full,

    input wire rd_en,
    input wire [ADDR_WIDTH-1:0] block_index,
    output wire [607:0] rd_record,
    output wire rd_valid,
    output wire rd_err,
    output wire [ADDR_WIDTH:0] block_count
);

    wire wr_ready;
    wire wr_err;

    blockchain_storage #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(608),
        .GENESIS_DATA({352'd0, GENESIS_HASH})
    ) ST (
        .clk(clk),
        .rst(rst),

        .wr_en(store_start),
        .block_data_in({blk_data, blk_hash}),
        .wr_ready(wr_ready),
        .wr_err(wr_err),

        .rd_en(rd_en),
        .block_index(block_index),
        .block_data_out(rd_record),
        .rd_valid(rd_valid),
        .rd_err(rd_err),

        .block_count(block_count),
        .full(st_full)
    );

    always @(posedge clk) begin
        if (rst)
            store_done <= 1'b0;
        else
            store_done <= store_start && wr_ready;
    end

endmodule
