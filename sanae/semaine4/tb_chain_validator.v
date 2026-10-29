`timescale 1ns/1ps

module tb_chain_validator;
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;
    reg start = 0;
    reg [31:0] index = 0;
    reg [255:0] previous_hash = 0;
    reg [63:0] transaction = 0;
    reg [255:0] stored_hash = 0;
    reg [255:0] expected_previous_hash = 0;

    wire busy, done, link_ok, hash_ok, chain_valid;
    wire [255:0] computed_hash;

    chain_validator dut (
        .clk(clk), .rst(rst), .start(start),
        .index(index),
        .previous_hash(previous_hash),
        .transaction(transaction),
        .stored_hash(stored_hash),
        .expected_previous_hash(expected_previous_hash),
        .busy(busy), .done(done),
        .link_ok(link_ok), .hash_ok(hash_ok),
        .chain_valid(chain_valid),
        .computed_hash(computed_hash)
    );

    task validate_block;
        begin
            @(negedge clk);
            start = 1;
            @(negedge clk);
            start = 0;
            wait(done);
            @(negedge clk);
        end
    endtask

    initial begin
        $dumpfile("chain_validator.vcd");
        $dumpvars(0, tb_chain_validator);

        repeat (2) @(negedge clk);
        rst = 0;

        // Premier passage : calculer le hash de reference.
        index = 1;
        previous_hash = 256'h1234;
        expected_previous_hash = 256'h1234;
        transaction = 64'h01000000000000AA;
        stored_hash = 0;

        validate_block();
        stored_hash = computed_hash;

        // Cas 1 : bloc valide.
        validate_block();
        if (chain_valid && link_ok && hash_ok)
            $display("OK : bloc valide accepte");
        else
            $fatal(1, "ECHEC : bloc valide refuse");

        // Cas 2 : hash stocke incorrect.
        stored_hash = computed_hash ^ 256'h1;
        validate_block();
        if (!chain_valid && link_ok && !hash_ok)
            $display("OK : hash incorrect detecte");
        else
            $fatal(1, "ECHEC : hash incorrect non detecte");

        // Cas 3 : lien avec le bloc precedent incorrect.
        stored_hash = computed_hash;
        expected_previous_hash = 256'h5678;
        validate_block();
        if (!chain_valid && !link_ok && hash_ok)
            $display("OK : lien incorrect detecte");
        else
            $fatal(1, "ECHEC : lien incorrect non detecte");

        $display("TOUS LES TESTS CHAIN_VALIDATOR PASSENT");
        $finish;
    end
endmodule
