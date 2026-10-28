`timescale 1ns/1ps

// Test de deux blocs chaines, avec references SHA-256 calculees
// independamment (hashlib Python sur les 44 octets de chaque bloc).
module block_hash_tb;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg start = 1'b0;
    reg [31:0] index = 32'd0;
    reg [255:0] previous_hash = 256'd0;
    reg [63:0] transaction = 64'd0;
    wire busy, done;
    wire [255:0] hash;
    integer erreurs = 0;

    localparam [255:0] HASH_BLOC1 =
        256'h32fa9e86898cde0f5f5526ffbbb27fdc128abe4889ffa7da08c3530926ae8168;
    localparam [255:0] HASH_BLOC2 =
        256'hee0e74567e6ccdbedaac5744d8302ff9dc90a9e904fcb9865405c648b72f9824;

    always #5 clk = ~clk; // 100 MHz

    block_hash dut (
        .clk(clk), .rst(rst), .start(start),
        .index(index), .previous_hash(previous_hash),
        .transaction(transaction),
        .busy(busy), .done(done), .hash(hash)
    );

    initial begin
        $dumpfile("block_hash.vcd");
        $dumpvars(0, block_hash_tb);
        repeat (5) @(negedge clk);
        rst = 1'b0;

        // Bloc 1 : previous_hash = 0 (convention de ce test).
        @(negedge clk);
        index = 32'd1;
        previous_hash = 256'd0;
        transaction = 64'h00000000A51FB6C7;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait (done === 1'b1);
        @(negedge clk);
        $display("=== TEST BLOCK HASH : BLOC 1 ===");
        $display("Obtenu  : %064h", hash);
        $display("Attendu : %064h", HASH_BLOC1);
        if (hash === HASH_BLOC1)
            $display("PASS : hash du bloc 1 correct");
        else begin
            $display("FAIL : hash du bloc 1 incorrect");
            erreurs = erreurs + 1;
        end

        // Bloc 2 : son previous_hash est le hash du bloc 1.
        @(negedge clk);
        index = 32'd2;
        previous_hash = HASH_BLOC1;
        transaction = 64'h1122334455667788;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait (done === 1'b1);
        @(negedge clk);
        $display("=== TEST BLOCK HASH : BLOC 2 ===");
        $display("Obtenu  : %064h", hash);
        $display("Attendu : %064h", HASH_BLOC2);
        if (hash === HASH_BLOC2)
            $display("PASS : hash du bloc 2 correct");
        else begin
            $display("FAIL : hash du bloc 2 incorrect");
            erreurs = erreurs + 1;
        end

        if (erreurs == 0)
            $display("PASS : deux blocs hashes avec SHA-256");
        else
            $display("FAIL : %0d erreur(s)", erreurs);
        $finish;
    end

    initial begin
        #3000;
        $display("FAIL : TIMEOUT block_hash");
        $finish;
    end
endmodule
