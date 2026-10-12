`timescale 1ns/1ps
// Testbench avec les VRAIES fonctions de hachage (hash_function1 / hash_function2)
// cle 32 bits, index 8 bits (tables de 256 cases)
module tb_cuckoo_insert_real;
    localparam KEY_W = 32, VAL_W = 16, IDX_W = 8, N = 1 << IDX_W;
    localparam EW = KEY_W + VAL_W + 1;     // {valid, key, value}

    reg clk = 0, rst = 1, start = 0;
    reg  [KEY_W-1:0] key_in;
    reg  [VAL_W-1:0] val_in;
    wire busy, done, fail;
    wire [7:0] kick_count;
    wire [KEY_W-1:0] hash_key;
    wire [IDX_W-1:0] h1_idx, h2_idx, mem_addr;
    wire mem_tbl, mem_we;
    wire [EW-1:0] mem_wdata;
    reg  [EW-1:0] mem_rdata;

    // hachages utilises par l'INSERT
    hash_function1 H1 (.key(hash_key), .index(h1_idx));
    hash_function2 H2 (.key(hash_key), .index(h2_idx));

    // hachages utilises par le testbench pour verifier
    reg  [KEY_W-1:0] chk_key;
    wire [IDX_W-1:0] c1, c2;
    hash_function1 C1 (.key(chk_key), .index(c1));
    hash_function2 C2 (.key(chk_key), .index(c2));

    cuckoo_insert #(.KEY_W(KEY_W), .VAL_W(VAL_W), .IDX_W(IDX_W), .MAX_KICKS(8)) dut (
        .clk(clk), .rst(rst), .start(start), .key_in(key_in), .val_in(val_in),
        .busy(busy), .done(done), .fail(fail), .kick_count(kick_count),
        .hash_key(hash_key), .h1_idx(h1_idx), .h2_idx(h2_idx),
        .mem_tbl(mem_tbl), .mem_addr(mem_addr), .mem_we(mem_we),
        .mem_wdata(mem_wdata), .mem_rdata(mem_rdata)
    );

    // memoire simulee : 2 tables, lecture synchrone
    reg [EW-1:0] t1 [0:N-1];
    reg [EW-1:0] t2 [0:N-1];
    always @(posedge clk) begin
        mem_rdata <= mem_tbl ? t2[mem_addr] : t1[mem_addr];
        if (mem_we) begin
            if (mem_tbl) t2[mem_addr] <= mem_wdata;
            else         t1[mem_addr] <= mem_wdata;
        end
    end

    always #5 clk = ~clk;

    integer errors = 0, i, fails, total_kicks, saved;

    task clear_mem;
        begin
            for (i = 0; i < N; i = i + 1) begin t1[i] = 0; t2[i] = 0; end
        end
    endtask

    reg ok;
    task do_insert(input [KEY_W-1:0] k, input [VAL_W-1:0] v);
        integer t;
        begin
            @(negedge clk); key_in = k; val_in = v; start = 1;
            @(negedge clk); start = 0;
            t = 0;
            while (!done && !fail && t < 300) begin @(negedge clk); t = t + 1; end
            ok = done;
            if (t >= 300) begin $display("ERREUR: timeout cle %h", k); errors = errors + 1; end
            @(negedge clk);
        end
    endtask

    // la cle doit etre dans T1[h1] ou T2[h2] avec la bonne valeur
    task check_present(input [KEY_W-1:0] k, input [VAL_W-1:0] v);
        reg [EW-1:0] e1, e2;
        begin
            chk_key = k; #1;
            e1 = t1[c1]; e2 = t2[c2];
            if (!((e1[EW-1] && e1[EW-2:VAL_W] == k && e1[VAL_W-1:0] == v) ||
                  (e2[EW-1] && e2[EW-2:VAL_W] == k && e2[VAL_W-1:0] == v))) begin
                $display("ERREUR: cle %h absente ou valeur fausse", k);
                errors = errors + 1;
            end
        end
    endtask

    reg [KEY_W-1:0] rk [0:99];
    initial begin
        $dumpfile("cuckoo_insert_real.vcd");
        $dumpvars(0, tb_cuckoo_insert_real);
        clear_mem;
        repeat (3) @(negedge clk);
        rst = 0;

        // Test 1 : insertion simple
        do_insert(32'h0000_0005, 16'd100);
        if (!ok || kick_count != 0) begin $display("ERREUR test1"); errors = errors + 1; end
        check_present(32'h0000_0005, 16'd100);

        // Test 2 : 0x104 a le meme h1 (=5) que 0x5 -> 1 eviction
        do_insert(32'h0000_0104, 16'd200);
        if (!ok || kick_count != 1) begin $display("ERREUR test2 (kicks=%0d)", kick_count); errors = errors + 1; end
        check_present(32'h0000_0005, 16'd100);
        check_present(32'h0000_0104, 16'd200);

        // Test 3 : 100 cles aleatoires dans des tables vides
        clear_mem;
        fails = 0; total_kicks = 0;
        for (i = 0; i < 100; i = i + 1) begin
            rk[i] = $urandom;
            do_insert(rk[i], i);
            if (!ok) fails = fails + 1;
            total_kicks = total_kicks + kick_count;
        end
        $display("Test 3 : 100 cles aleatoires -> %0d echec(s), %0d eviction(s) au total", fails, total_kicks);
        // informatif : un echec fait perdre la cle tenue en main (voir note du module)
        saved = errors;
        for (i = 0; i < 100; i = i + 1) check_present(rk[i], i);
        $display("Test 3 : %0d cle(s) perdue(s) sur 100", errors - saved);
        errors = saved;

        // Test 4 : 3 cles avec les memes (h1,h2) -> la 3e doit echouer
        clear_mem;
        do_insert(32'h0000_0003, 16'd1);
        do_insert(32'h0000_0102, 16'd2);
        do_insert(32'h0000_0201, 16'd3);
        if (ok) begin $display("test4: la 3e cle a ete inseree (inattendu)"); errors = errors + 1; end
        else    $display("Test 4 : echec attendu observe (3 cles, memes h1 et h2)");

        if (errors == 0) $display("TOUS LES TESTS PASSENT");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end
endmodule
