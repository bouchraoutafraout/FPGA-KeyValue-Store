`timescale 1ns/1ps

module hashtables_switch_tb;

    localparam KEY_W   = 32;
    localparam VAL_W   = 16;
    localparam IDX_W   = 8;
    localparam ENTRY_W = 1 + KEY_W + VAL_W;

    localparam [ENTRY_W-1:0] DATA_A = {1'b1, 32'h0000_00AA, 16'h1111};
    localparam [ENTRY_W-1:0] DATA_B = {1'b1, 32'h0000_00BB, 16'h2222};

    reg                 clk = 1'b0;
    reg                 search_busy = 1'b0;
    reg  [IDX_W-1:0]    s_addr1 = {IDX_W{1'b0}};
    reg  [IDX_W-1:0]    s_addr2 = {IDX_W{1'b0}};
    wire [ENTRY_W-1:0]  s_rdata1;
    wire [ENTRY_W-1:0]  s_rdata2;
    reg                 ins_tbl = 1'b0;
    reg  [IDX_W-1:0]    ins_addr = {IDX_W{1'b0}};
    reg                 ins_we = 1'b0;
    reg  [ENTRY_W-1:0]  ins_wdata = {ENTRY_W{1'b0}};
    wire [ENTRY_W-1:0]  ins_rdata;

    integer errors = 0;

    hashtables #(.KEY_W(KEY_W), .VAL_W(VAL_W), .IDX_W(IDX_W)) dut (
        .clk(clk),
        .search_busy(search_busy),
        .s_addr1(s_addr1), .s_addr2(s_addr2),
        .s_rdata1(s_rdata1), .s_rdata2(s_rdata2),
        .ins_tbl(ins_tbl), .ins_addr(ins_addr), .ins_we(ins_we),
        .ins_wdata(ins_wdata), .ins_rdata(ins_rdata)
    );

    always #5 clk = ~clk;

    task wr;
        input             tbl;
        input [IDX_W-1:0] a;
        input [ENTRY_W-1:0] d;
        begin
            @(negedge clk);
            ins_tbl   = tbl;
            ins_addr  = a;
            ins_wdata = d;
            ins_we    = 1'b1;
            @(negedge clk);
            ins_we    = 1'b0;
        end
    endtask

    task check;
        input [ENTRY_W-1:0] got;
        input [ENTRY_W-1:0] exp;
        input [639:0]       name;
        begin
            if (got !== exp) begin
                errors = errors + 1;
                $display("ECHEC  %0s : lu=%h attendu=%h", name, got, exp);
            end else begin
                $display("OK     %0s", name);
            end
        end
    endtask

    initial begin
        wr(1'b0, 8'd1, DATA_A);
        wr(1'b1, 8'd2, DATA_B);

        @(negedge clk);
        search_busy = 1'b0;
        ins_tbl     = 1'b0;
        ins_addr    = 8'd1;
        @(negedge clk);
        ins_tbl     = 1'b1;
        ins_addr    = 8'd2;
        #1;
        check(ins_rdata, DATA_A, "bascule de table : donnee de la lecture precedente (table 1)");
        @(negedge clk);
        check(ins_rdata, DATA_B, "bascule de table : donnee de la nouvelle lecture (table 2)");

        @(negedge clk);
        ins_tbl     = 1'b0;
        ins_addr    = 8'd1;
        @(negedge clk);
        ins_tbl     = 1'b1;
        ins_addr    = 8'd2;
        @(negedge clk);
        ins_tbl     = 1'b0;
        ins_addr    = 8'd1;
        #1;
        check(ins_rdata, DATA_B, "alternance rapide : lecture table 2");
        @(negedge clk);
        check(ins_rdata, DATA_A, "alternance rapide : lecture table 1");

        #20;
        if (errors == 0) $display("TOUS LES TESTS PASSENT");
        else             $display("%0d TEST(S) EN ECHEC", errors);
        $finish;
    end

endmodule
