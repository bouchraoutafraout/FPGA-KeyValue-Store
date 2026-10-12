`timescale 1ns/1ps

module cuckoo_tb;

    localparam KEY_W   = 32;
    localparam VAL_W   = 16;
    localparam IDX_W   = 8;
    localparam ENTRY_W = 1 + KEY_W + VAL_W;

    reg clk = 1'b0;
    reg rst = 1'b1;

    reg                 ins_start = 1'b0;
    reg  [KEY_W-1:0]    ins_key   = {KEY_W{1'b0}};
    reg  [VAL_W-1:0]    ins_val   = {VAL_W{1'b0}};
    wire                ins_busy;
    wire                ins_done;
    wire                ins_fail;
    wire [7:0]          kick_count;
    wire [KEY_W-1:0]    ins_hash_key;
    wire [IDX_W-1:0]    ins_h1;
    wire [IDX_W-1:0]    ins_h2;
    wire                mem_tbl;
    wire [IDX_W-1:0]    mem_addr;
    wire                mem_we;
    wire [ENTRY_W-1:0]  mem_wdata;
    reg  [ENTRY_W-1:0]  mem_rdata;

    reg                 s_start = 1'b0;
    reg  [KEY_W-1:0]    s_key   = {KEY_W{1'b0}};
    wire                s_busy;
    wire                s_done;
    wire                s_found;
    wire [VAL_W-1:0]    s_value;
    wire                s_table;
    wire [IDX_W-1:0]    s_addr_found;
    wire [KEY_W-1:0]    s_hash_key;
    wire [IDX_W-1:0]    s_h1;
    wire [IDX_W-1:0]    s_h2;
    wire [IDX_W-1:0]    s_addr1;
    wire [IDX_W-1:0]    s_addr2;
    reg  [ENTRY_W-1:0]  s_rdata1;
    reg  [ENTRY_W-1:0]  s_rdata2;

    reg  [ENTRY_W-1:0]  mem1 [0:(1<<IDX_W)-1];
    reg  [ENTRY_W-1:0]  mem2 [0:(1<<IDX_W)-1];

    integer i;
    integer errors = 0;
    integer nfound;
    reg     last_fail;
    reg [7:0] last_kicks;

    cuckoo_insert #(.KEY_W(KEY_W), .VAL_W(VAL_W), .IDX_W(IDX_W), .MAX_KICKS(8)) u_ins (
        .clk(clk), .rst(rst),
        .start(ins_start), .key_in(ins_key), .val_in(ins_val),
        .busy(ins_busy), .done(ins_done), .fail(ins_fail), .kick_count(kick_count),
        .hash_key(ins_hash_key), .h1_idx(ins_h1), .h2_idx(ins_h2),
        .mem_tbl(mem_tbl), .mem_addr(mem_addr), .mem_we(mem_we),
        .mem_wdata(mem_wdata), .mem_rdata(mem_rdata)
    );

    search #(.KEY_W(KEY_W), .VAL_W(VAL_W), .ADDR_W(IDX_W)) u_srch (
        .clk(clk), .rst(rst),
        .start(s_start), .key(s_key),
        .busy(s_busy), .done(s_done), .found(s_found), .value(s_value),
        .table_sel(s_table), .addr_found(s_addr_found),
        .addr1(s_addr1), .addr2(s_addr2),
        .data1(s_rdata1), .data2(s_rdata2)
    );

    hash_function1 u_hi1 (.key(ins_hash_key), .index(ins_h1));
    hash_function2 u_hi2 (.key(ins_hash_key), .index(ins_h2));

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (mem_we) begin
            if (mem_tbl) mem2[mem_addr] <= mem_wdata;
            else         mem1[mem_addr] <= mem_wdata;
        end
        mem_rdata <= mem_tbl ? mem2[mem_addr] : mem1[mem_addr];
        s_rdata1  <= mem1[s_addr1];
        s_rdata2  <= mem2[s_addr2];
    end

    task do_insert;
        input [KEY_W-1:0] k;
        input [VAL_W-1:0] v;
        begin
            @(negedge clk);
            ins_key   = k;
            ins_val   = v;
            ins_start = 1'b1;
            @(negedge clk);
            ins_start = 1'b0;
            while (!(ins_done || ins_fail)) @(posedge clk);
            last_fail  = ins_fail;
            last_kicks = kick_count;
            @(negedge clk);
            @(negedge clk);
        end
    endtask

    task do_search;
        input [KEY_W-1:0] k;
        begin
            @(negedge clk);
            s_key   = k;
            s_start = 1'b1;
            @(negedge clk);
            s_start = 1'b0;
            wait (s_done === 1'b1);
            #1;
        end
    endtask

    task expect_found;
        input [KEY_W-1:0] k;
        input [VAL_W-1:0] v;
        input [255:0]     name;
        begin
            do_search(k);
            if (s_found !== 1'b1 || s_value !== v) begin
                errors = errors + 1;
                $display("ECHEC  %0s : found=%b value=%h (attendu %h)", name, s_found, s_value, v);
            end else begin
                $display("OK     %0s (table %0d, case %0d)", name, s_table + 1, s_addr_found);
            end
        end
    endtask

    task expect_absent;
        input [KEY_W-1:0] k;
        input [255:0]     name;
        begin
            do_search(k);
            if (s_found !== 1'b0) begin
                errors = errors + 1;
                $display("ECHEC  %0s : trouvee alors qu'elle ne devrait pas", name);
            end else begin
                $display("OK     %0s", name);
            end
        end
    endtask

    initial begin
        $dumpfile("cuckoo_joint.vcd");
        $dumpvars(0, cuckoo_tb);
        for (i = 0; i < (1<<IDX_W); i = i + 1) begin
            mem1[i] = {ENTRY_W{1'b0}};
            mem2[i] = {ENTRY_W{1'b0}};
        end

        #22 rst = 1'b0;

        do_insert(32'h000000AA, 16'h1111);
        do_insert(32'h000000BB, 16'h2222);
        do_insert(32'h00001234, 16'h3333);
        do_insert(32'hDEADBEEF, 16'h4444);

        expect_found(32'h000000AA, 16'h1111, "insert/search AA");
        expect_found(32'h000000BB, 16'h2222, "insert/search BB");
        expect_found(32'h00001234, 16'h3333, "insert/search 1234");
        expect_found(32'hDEADBEEF, 16'h4444, "insert/search DEADBEEF");
        expect_absent(32'h00000077, "cle jamais inseree");

        do_insert(32'h00000001, 16'hA001);
        do_insert(32'h00000100, 16'hA002);
        if (last_fail || last_kicks !== 8'd1) begin
            errors = errors + 1;
            $display("ECHEC  eviction : fail=%b kicks=%0d (attendu fail=0 kicks=1)", last_fail, last_kicks);
        end else begin
            $display("OK     eviction : 1 expulsion, insertion reussie");
        end
        expect_found(32'h00000001, 16'hA001, "apres eviction : cle expulsee");
        expect_found(32'h00000100, 16'hA002, "apres eviction : cle inseree");
        expect_found(32'h000000AA, 16'h1111, "apres eviction : AA intacte");

        do_insert(32'h00010000, 16'hA003);
        $display("INFO   3e cle sur les memes cases : fail=%b kicks=%0d", last_fail, last_kicks);
        nfound = 0;
        do_search(32'h00000001); nfound = nfound + s_found;
        do_search(32'h00000100); nfound = nfound + s_found;
        do_search(32'h00010000); nfound = nfound + s_found;
        $display("INFO   apres l'echec : %0d cle(s) sur 3 retrouvable(s)", nfound);

        #20;
        if (errors == 0) $display("TOUS LES TESTS PASSENT");
        else             $display("%0d TEST(S) EN ECHEC", errors);
        $finish;
    end

endmodule