module blockchain_storage #(
    parameter ADDR_WIDTH = 4,
    parameter DATA_WIDTH = 608,
    parameter [DATA_WIDTH-1:0] GENESIS_DATA = {{(DATA_WIDTH-1){1'b0}}, 1'b1}
)(
    input wire clk,
    input wire rst,
    input wire wr_en,
    input wire [DATA_WIDTH-1:0] block_data_in,
    output wire wr_ready,
    output reg wr_err,
    input wire rd_en,
    input wire [ADDR_WIDTH-1:0] block_index,
    output reg [DATA_WIDTH-1:0] block_data_out,
    output reg rd_valid,
    output reg rd_err,
    output reg [ADDR_WIDTH:0] block_count,
    output wire full
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    integer i;
    initial begin
        mem[0] = GENESIS_DATA;
        for (i = 1; i < DEPTH; i = i + 1) begin
            mem[i] = {DATA_WIDTH{1'b0}};
        end
    end

    assign full = (block_count == DEPTH);
    assign wr_ready = ~full;

    always @(posedge clk) begin
        if (wr_en && !full) begin
            mem[block_count[ADDR_WIDTH-1:0]] <= block_data_in;
        end
        if (rd_en) begin
            block_data_out <= mem[block_index];
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            block_count <= 1;
            wr_err <= 1'b0;
            rd_valid <= 1'b0;
            rd_err <= 1'b0;
        end else begin
            wr_err <= wr_en && full;
            rd_valid <= rd_en && ({1'b0, block_index} < block_count);
            rd_err <= rd_en && ({1'b0, block_index} >= block_count);
            if (wr_en && !full) begin
                block_count <= block_count + 1'b1;
            end
        end
    end

endmodule
