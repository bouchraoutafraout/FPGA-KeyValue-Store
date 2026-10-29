`timescale 1ns/1ps

module blockchain_storage_full_tb;

reg clk = 0;
reg rst = 1;
reg wr_en = 0;
reg rd_en = 0;
reg [3:0] block_index = 0;
reg [607:0] block_data_in = 0;

wire wr_ready, wr_err;
wire [607:0] block_data_out;
wire rd_valid, rd_err;
wire [4:0] block_count;
wire full;

integer i;
integer errors = 0;

always #5 clk = ~clk;

blockchain_storage #(
    .ADDR_WIDTH(4),
    .DATA_WIDTH(608)
) DUT (
    .clk(clk),
    .rst(rst),
    .wr_en(wr_en),
    .block_data_in(block_data_in),
    .wr_ready(wr_ready),
    .wr_err(wr_err),
    .rd_en(rd_en),
    .block_index(block_index),
    .block_data_out(block_data_out),
    .rd_valid(rd_valid),
    .rd_err(rd_err),
    .block_count(block_count),
    .full(full)
);

initial begin
    repeat (4) @(negedge clk);
    rst = 0;

    #1;
    if (block_count !== 5'd1) begin
        $display("FAIL: Genesis non reserve");
        errors = errors + 1;
    end

    for (i = 0; i < 15; i = i + 1) begin
        @(negedge clk);
        wr_en = 1;
        block_data_in = i + 1;

        @(posedge clk);
        #1;

        if (block_count !== (i + 2)) begin
            $display("FAIL: bloc %0d count=%0d", i, block_count);
            errors = errors + 1;
        end
    end

    @(negedge clk);
    wr_en = 0;
    #1;

    if (full === 1'b1 &&
        wr_ready === 1'b0 &&
        block_count === 5'd16)
        $display("PASS: BRAM pleine apres 15 blocs");
    else begin
        $display("FAIL: saturation BRAM");
        errors = errors + 1;
    end

    // Tentative d'ecriture supplementaire
    @(negedge clk);
    wr_en = 1;
    block_data_in = 608'hDEADBEEF;

    @(posedge clk);
    #1;

    if (wr_err === 1'b1 &&
        block_count === 5'd16)
        $display("PASS: ecriture supplementaire refusee");
    else begin
        $display("FAIL: depassement BRAM");
        errors = errors + 1;
    end

    @(negedge clk);
    wr_en = 0;

    if (errors == 0)
        $display("PASS: ROBUSTESSE BRAM PLEINE");
    else
        $display("FAIL: %0d erreurs", errors);

    $finish;
end

endmodule
