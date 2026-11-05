`timescale 1ns/1ps

// Test du chainage avec les deux vrais blocs de l'integration Nada/Khadija.
// Empreintes attendues calculees independamment avec Python hashlib.sha256.
module chain_validator_tb;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg start = 1'b0;
    reg [31:0] index = 0;
    reg [255:0] previous_hash = 0;
    reg [255:0] expected_previous_hash = 0;
    reg [63:0] transaction = 0;
    reg [255:0] stored_hash = 0;

    wire busy, done, link_ok, hash_ok, chain_valid;
    wire [255:0] computed_hash;
    integer errors = 0;

    localparam [255:0] HASH_BLOC0 =
        256'h5340d663384c25c0bff9964af0d47b3abb746752ba4af91408e641f59a2cbc7d;
    localparam [255:0] HASH_BLOC1 =
        256'haf02679bbe0c555e390d2f41ccf0eb55d9e7ba3867542ea3ce3c802268eb835f;
    localparam [255:0] HASH_TX_MODIFIEE =
        256'h29c7476f0bf3c77bfa54bc252a67b8c60c3167130c1db6b41d88d43cde3d308e;
    localparam [255:0] HASH_MAUVAIS_PREV =
        256'hfbe5863a789659c94ea4de357d61a93a3c9bd6a3e73ae74687b60ecb85b2a203;

    always #5 clk = ~clk;

    chain_validator dut (
        .clk(clk), .rst(rst), .start(start),
        .index(index), .previous_hash(previous_hash),
        .transaction(transaction), .stored_hash(stored_hash),
        .expected_previous_hash(expected_previous_hash),
        .busy(busy), .done(done), .link_ok(link_ok),
        .hash_ok(hash_ok), .chain_valid(chain_valid),
        .computed_hash(computed_hash)
    );

    task check_block;
        input [31:0]  t_index;
        input [255:0] t_prev, t_expected_prev;
        input [63:0]  t_tx;
        input [255:0] t_stored, t_expected_hash;
        input         t_link_ok, t_hash_ok, t_valid;
        input [8*50-1:0] test_name;
        begin
            @(negedge clk);
            index                  = t_index;
            previous_hash          = t_prev;
            expected_previous_hash = t_expected_prev;
            transaction            = t_tx;
            stored_hash            = t_stored;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait (done === 1'b1);
            @(negedge clk);
            if (link_ok === t_link_ok && hash_ok === t_hash_ok &&
                chain_valid === t_valid && computed_hash === t_expected_hash) begin
                $display("PASS : %0s", test_name);
            end else begin
                $display("FAIL : %0s", test_name);
                $display(" link=%b hash_ok=%b valid=%b", link_ok, hash_ok, chain_valid);
                $display(" hash calcule = %064h", computed_hash);
                $display(" hash attendu = %064h", t_expected_hash);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("chain_validator.vcd");
        $dumpvars(0, chain_validator_tb);
        repeat (5) @(negedge clk);
        rst = 1'b0;

        // Bloc logique 0 : premier bloc apres Genesis.
        check_block(32'd0, 256'd0, 256'd0,
                    64'h07011234567800AA, HASH_BLOC0, HASH_BLOC0,
                    1'b1, 1'b1, 1'b1, "Bloc 0 valide");

        // Bloc logique 1 : reference exactement le hash du bloc logique 0.
        check_block(32'd1, HASH_BLOC0, HASH_BLOC0,
                    64'h0703123456780055, HASH_BLOC1, HASH_BLOC1,
                    1'b1, 1'b1, 1'b1, "Bloc 1 chaine correctement");

        // Transaction modifiee dans le stockage, hash conserve : refus.
        check_block(32'd1, HASH_BLOC0, HASH_BLOC0,
                    64'h0703123456780054, HASH_BLOC1, HASH_TX_MODIFIEE,
                    1'b1, 1'b0, 1'b0, "Transaction modifiee detectee");

        // Previous_hash modifie, hash recalcule pour isoler l'erreur de lien.
        check_block(32'd1, HASH_BLOC0 ^ 256'd1, HASH_BLOC0,
                    64'h0703123456780055, HASH_MAUVAIS_PREV, HASH_MAUVAIS_PREV,
                    1'b0, 1'b1, 1'b0, "Mauvais lien precedent detecte");

        // Hash stocke corrompu, contenu et lien inchanges : refus.
        check_block(32'd1, HASH_BLOC0, HASH_BLOC0,
                    64'h0703123456780055, HASH_BLOC1 ^ 256'd1, HASH_BLOC1,
                    1'b1, 1'b0, 1'b0, "Hash stocke corrompu detecte");

        if (errors == 0)
            $display("PASS : CHAIN VALIDATOR - TOUS LES TESTS REUSSIS");
        else
            $display("FAIL : %0d test(s) en erreur", errors);
        $finish;
    end

    initial begin
        #15000;
        $display("FAIL : TIMEOUT chain_validator");
        $finish;
    end
endmodule
