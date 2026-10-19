module bram_table #(
    parameter ADDR_W = 8,
    parameter DATA_W = 65
)(
    input clk,
    input we,
    input [ADDR_W-1:0] waddr,
    input [DATA_W-1:0] wdata,
    input [ADDR_W-1:0] raddr,
    output reg [DATA_W-1:0] rdata
);

    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];
    integer i;

    initial begin
        for (i = 0; i < (1<<ADDR_W); i = i + 1)
            mem[i] = {DATA_W{1'b0}};
        rdata = {DATA_W{1'b0}};
    end

    always @(posedge clk) begin
        if (we)
            mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end

endmodule
