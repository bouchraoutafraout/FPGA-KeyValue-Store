`timescale 1ns/1ps
module sha256_core_tb;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg start = 1'b0;
    wire busy_abc, done_abc, busy_block, done_block;
    wire [255:0] hash_abc, hash_block;
    always #5 clk = ~clk; // 100 MHz

    // Vecteur SHA-256 standard : SHA256("abc").
    sha256_core #(.MSG_BITS(24)) test_abc (
        .clk(clk), .rst(rst), .start(start),
        .message(24'h616263),
        .busy(busy_abc), .done(done_abc), .hash(hash_abc)
    );

    // Format prevu dans INTERFACES.md : index || previous_hash || transaction.
    sha256_core #(.MSG_BITS(352)) test_block (
        .clk(clk), .rst(rst), .start(start),
        .message({32'd1, 256'd0, 64'h00000000A51FB6C7}),
        .busy(busy_block), .done(done_block), .hash(hash_block)
    );

    initial begin
        repeat (5) @(negedge clk);
        rst = 1'b0;
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait (done_abc && done_block);
        #1;
        $display("=== TEST SHA-256 STANDARD abc ===");
        $display("Obtenu  : %064h", hash_abc);
        $display("Attendu : ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
        if (hash_abc === 256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad)
            $display("PASS : SHA-256 abc");
        else
            $display("FAIL : SHA-256 abc");
        $display("=== TEST SHA-256 BLOC 352 BITS ===");
        $display("Obtenu  : %064h", hash_block);
        $display("Attendu : 32fa9e86898cde0f5f5526ffbbb27fdc128abe4889ffa7da08c3530926ae8168");
        if (hash_block === 256'h32fa9e86898cde0f5f5526ffbbb27fdc128abe4889ffa7da08c3530926ae8168)
            $display("PASS : SHA-256 bloc 352 bits");
        else
            $display("FAIL : SHA-256 bloc 352 bits");
        $finish;
    end
    initial begin
        #2000;
        $display("FAIL : TIMEOUT SHA-256");
        $finish;
    end
endmodule
