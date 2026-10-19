module hashtables #(
    parameter KEY_W = 32,
    parameter VAL_W = 16,
    parameter IDX_W = 8
)(
    input  wire                     clk,

    input  wire                     search_busy,

    input  wire [IDX_W-1:0]         s_addr1,
    input  wire [IDX_W-1:0]         s_addr2,
    output wire [KEY_W+VAL_W:0]     s_rdata1,
    output wire [KEY_W+VAL_W:0]     s_rdata2,

    input  wire                     ins_tbl,
    input  wire [IDX_W-1:0]         ins_addr,
    input  wire                     ins_we,
    input  wire [KEY_W+VAL_W:0]     ins_wdata,
    output wire [KEY_W+VAL_W:0]     ins_rdata
);

    localparam ENTRY_W = 1 + KEY_W + VAL_W;

    wire [IDX_W-1:0] raddr1 = search_busy ? s_addr1 : ins_addr;
    wire [IDX_W-1:0] raddr2 = search_busy ? s_addr2 : ins_addr;

    wire we1 = ins_we & ~ins_tbl;
    wire we2 = ins_we &  ins_tbl;

    reg ins_tbl_q;
    always @(posedge clk)
        ins_tbl_q <= ins_tbl;

    bram_table #(.DATA_W(ENTRY_W), .ADDR_W(IDX_W)) hashtable1 (
        .clk(clk),
        .we(we1),
        .waddr(ins_addr),
        .wdata(ins_wdata),
        .raddr(raddr1),
        .rdata(s_rdata1)
    );

    bram_table #(.DATA_W(ENTRY_W), .ADDR_W(IDX_W)) hashtable2 (
        .clk(clk),
        .we(we2),
        .waddr(ins_addr),
        .wdata(ins_wdata),
        .raddr(raddr2),
        .rdata(s_rdata2)
    );

    assign ins_rdata = ins_tbl_q ? s_rdata2 : s_rdata1;

endmodule
