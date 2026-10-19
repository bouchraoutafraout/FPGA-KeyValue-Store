`timescale 1ns/1ps

module bram_tb;

    localparam KEY_W   = 8;
    localparam VAL_W   = 8;
    localparam IDX_W   = 4;
    localparam ENTRY_W = 1 + KEY_W + VAL_W;
    localparam LAST    = (1 << IDX_W) - 1;

    reg clk = 0;
    always #5 clk = ~clk;

    reg search_busy;
    reg [IDX_W-1:0] s_addr1, s_addr2;
    wire [ENTRY_W-1:0] s_rdata1, s_rdata2;
    reg ins_tbl, ins_we;
    reg [IDX_W-1:0] ins_addr;
    reg [ENTRY_W-1:0] ins_wdata;
    wire [ENTRY_W-1:0] ins_rdata;

    integer errors = 0;

    hashtables #(.IDX_W(IDX_W), .KEY_W(KEY_W), .VAL_W(VAL_W)) dut (
        .clk(clk),
        .search_busy(search_busy),
        .s_addr1(s_addr1), .s_addr2(s_addr2),
        .s_rdata1(s_rdata1), .s_rdata2(s_rdata2),
        .ins_tbl(ins_tbl), .ins_addr(ins_addr), .ins_we(ins_we),
        .ins_wdata(ins_wdata), .ins_rdata(ins_rdata)
    );

    task write_entry;
        input tbl;
        input [IDX_W-1:0] a;
        input [ENTRY_W-1:0] d;
        begin
            @(negedge clk);
            ins_tbl = tbl;
            ins_addr = a;
            ins_wdata = d;
            ins_we = 1;
            @(negedge clk);
            ins_we = 0;
        end
    endtask

    task read_entries;
        input [IDX_W-1:0] a1;
        input [IDX_W-1:0] a2;
        begin
            @(negedge clk);
            search_busy = 1;
            s_addr1 = a1;
            s_addr2 = a2;
            @(negedge clk);
        end
    endtask

    task expect_entry;
        input [ENTRY_W-1:0] got;
        input [ENTRY_W-1:0] expected;
        input [255:0] name;
        begin
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s : got=%h expected=%h", name, got, expected);
            end else begin
                $display("PASS %0s", name);
            end
        end
    endtask

    initial begin
        search_busy = 0;
        s_addr1 = 0;
        s_addr2 = 0;
        ins_tbl = 0;
        ins_we = 0;
        ins_addr = 0;
        ins_wdata = 0;

        write_entry(1'b0, 4'd3, {1'b1, 8'hA5, 8'h11});
        write_entry(1'b1, 4'd3, {1'b1, 8'h5A, 8'h22});
        write_entry(1'b0, LAST, {1'b1, 8'hFE, 8'h0B});
        read_entries(4'd3, 4'd3);
        expect_entry(s_rdata1, {1'b1, 8'hA5, 8'h11}, "table 1");
        expect_entry(s_rdata2, {1'b1, 8'h5A, 8'h22}, "table 2");

        read_entries(LAST, 4'd0);
        expect_entry(s_rdata1, {1'b1, 8'hFE, 8'h0B}, "derniere adresse");
        expect_entry(s_rdata2, {ENTRY_W{1'b0}}, "case vide");

        if (errors == 0)
            $display("PASS : tous les tests sont OK");
        else
            $display("FAIL : %0d erreur(s)", errors);
        $finish;
    end

endmodule
