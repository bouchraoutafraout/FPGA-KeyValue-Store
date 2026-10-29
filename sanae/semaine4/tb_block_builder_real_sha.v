`timescale 1ns/1ps

module tb_block_builder_real_sha;

    reg clk = 0;
    reg rst = 1;

    reg tx_valid = 0;
    reg [7:0] tx_type = 0;
    reg [31:0] tx_key = 0;
    reg [15:0] tx_value = 0;

    wire ready;
    reg hold = 0;
    reg seal = 0;

    reg init_valid = 0;
    reg [31:0] init_index = 0;
    reg [255:0] init_hash = 0;

    wire store_start;
    wire [31:0] blk_index;
    wire [255:0] blk_hash;
    reg store_done = 0;
    reg st_full = 0;

    wire [31:0] next_index;
    wire [255:0] last_hash;
    wire [31:0] blocks_stored;
    wire busy;
    wire [3:0] dbg_state;

    integer store_count = 0;
    reg [31:0] saved_index [0:1];
    reg [255:0] saved_hash [0:1];

    localparam [255:0] EXPECTED_GENESIS =
        256'h85759b3811ff7dc47b03792ac85317be51431a3f9e01dcafce317ed736a391b0;

    localparam [255:0] EXPECTED_BLOCK1 =
        256'h4a94ba54d7af29a02ac41ee273055ab9251cf29d350c26b0af7817fa4a543bad;

    // Module a tester : ton Block Builder + SHA-256 reel
    block_builder_real_sha dut (
        .clk(clk),
        .rst(rst),

        .tx_valid(tx_valid),
        .tx_type(tx_type),
        .tx_key(tx_key),
        .tx_value(tx_value),
        .ready(ready),

        .hold(hold),
        .seal(seal),

        .init_valid(init_valid),
        .init_index(init_index),
        .init_hash(init_hash),

        .store_start(store_start),
        .blk_index(blk_index),
        .blk_hash(blk_hash),
        .store_done(store_done),
        .st_full(st_full),

        .next_index(next_index),
        .last_hash(last_hash),
        .blocks_stored(blocks_stored),
        .busy(busy),
        .dbg_state(dbg_state)
    );

    // Horloge : periode de 10 ns
    always #5 clk = ~clk;

    // Modele simple de stockage pour le testbench.
    // Il enregistre le bloc et renvoie un acquittement.
    always @(posedge clk) begin
        if (rst) begin
            store_done <= 0;
            store_count = 0;
        end else begin
            store_done <= 0;

            if (store_start && !st_full) begin
                if (store_count < 2) begin
                    saved_index[store_count] = blk_index;
                    saved_hash[store_count] = blk_hash;
                end

                store_count = store_count + 1;
                store_done <= 1;
            end
        end
    end

    initial begin
        $dumpfile("tb_block_builder_real_sha.vcd");
        $dumpvars(0, tb_block_builder_real_sha);

        // Reset
        repeat (3) @(negedge clk);
        rst = 0;

        // Test 1 : Genesis calcule avec le vrai SHA-256
        wait (store_count >= 1);
        repeat (2) @(negedge clk);

        if (saved_index[0] !== 32'd0) begin
            $display("ECHEC : index Genesis incorrect");
            $fatal(1);
        end

        if (saved_hash[0] !== EXPECTED_GENESIS) begin
            $display("ECHEC : hash Genesis incorrect");
            $display("Obtenu  : %064h", saved_hash[0]);
            $display("Attendu : %064h", EXPECTED_GENESIS);
            $fatal(1);
        end

        $display("OK : Genesis et SHA-256 reel");

        // Test 2 : envoyer une transaction
        wait (ready == 1'b1);
        @(negedge clk);

        tx_type  = 8'h01;
        tx_key   = 32'h12345678;
        tx_value = 16'hABCD;
        tx_valid = 1;

        @(negedge clk);
        tx_valid = 0;

        // Demander la construction du bloc
        @(negedge clk);
        seal = 1;

        @(negedge clk);
        seal = 0;

        // Attendre l'ecriture du bloc 1
        wait (store_count >= 2);
        repeat (2) @(negedge clk);

        if (saved_index[1] !== 32'd1) begin
            $display("ECHEC : index du bloc 1 incorrect");
            $fatal(1);
        end

        if (saved_hash[1] !== EXPECTED_BLOCK1) begin
            $display("ECHEC : hash du bloc 1 incorrect");
            $display("Obtenu  : %064h", saved_hash[1]);
            $display("Attendu : %064h", EXPECTED_BLOCK1);
            $fatal(1);
        end

        $display("OK : transaction et hash SHA-256 reel");
        $display("OK : index et stockage");
        $display("Hash Genesis : %064h", saved_hash[0]);
        $display("Hash bloc 1 : %064h", saved_hash[1]);
        $display("TOUS LES TESTS D'INTEGRATION PASSENT");

        $finish;
    end

    // Timeout pour detecter un blocage de la simulation
    initial begin
        #200000;
        $display("ECHEC : timeout, le traitement ne se termine pas");
        $fatal(1);
    end

endmodule
