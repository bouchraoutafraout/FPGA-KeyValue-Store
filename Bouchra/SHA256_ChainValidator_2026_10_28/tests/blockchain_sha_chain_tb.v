`timescale 1ns/1ps

module blockchain_sha_chain_tb;

reg clk=0, rst=1, tx_valid=0;
reg [63:0] tx_data=0;
always #5 clk=~clk;

wire tx_ready, validator_start, builder_start;
wire sha_start, storage_start;
wire [63:0] validator_tx, builder_tx;
wire [31:0] builder_index, storage_index;
wire [31:0] result_index, next_index;
wire [255:0] builder_prev_hash, storage_hash;
wire [255:0] result_hash, previous_hash;
wire [351:0] sha_message, storage_header;
wire result_valid, result_ok, busy;
wire [7:0] result_status;

reg validator_done=0, validator_accept=0;
reg builder_done=0;
reg [351:0] builder_header=0;
wire sha_done;
wire [255:0] sha_hash;
wire sha_busy;

wire storage_done, storage_ok;

integer errors=0;
reg [607:0] expected_block0;
reg [607:0] expected_block1;

blockchain_top DUT (
    .clk(clk), .rst(rst),
    .tx_valid(tx_valid), .tx_ready(tx_ready),
    .tx_data(tx_data),
    .validator_start(validator_start),
    .validator_tx(validator_tx),
    .validator_done(validator_done),
    .validator_accept(validator_accept),
    .builder_start(builder_start),
    .builder_index(builder_index),
    .builder_prev_hash(builder_prev_hash),
    .builder_tx(builder_tx),
    .builder_done(builder_done),
    .builder_header(builder_header),
    .sha_start(sha_start),
    .sha_message(sha_message),
    .sha_done(sha_done),
    .sha_hash(sha_hash),
    .storage_start(storage_start),
    .storage_index(storage_index),
    .storage_header(storage_header),
    .storage_hash(storage_hash),
    .storage_done(storage_done),
    .storage_ok(storage_ok),
    .result_valid(result_valid),
    .result_ready(1'b1),
    .result_ok(result_ok),
    .result_status(result_status),
    .result_index(result_index),
    .result_hash(result_hash),
    .busy(busy),
    .next_index(next_index),
    .previous_hash(previous_hash)
);

// VRAI STOCKAGE DE KHADIJA + ADAPTATEUR
blockchain_storage_adapter STORE (
    .clk(clk), .rst(rst),
    .storage_start(storage_start),
    .storage_index(storage_index),
    .storage_header(storage_header),
    .storage_hash(storage_hash),
    .storage_done(storage_done),
    .storage_ok(storage_ok)
);

// Le vrai SHA-256 de Bouchra calcule le hash des 352 bits du bloc.
sha256_core #(.MSG_BITS(352)) SHA_BOUCHRA (
    .clk(clk), .rst(rst), .start(sha_start), .message(sha_message),
    .busy(sha_busy), .done(sha_done), .hash(sha_hash)
);

// Validation et construction de bloc simulees uniquement ici.
always @(posedge clk) begin
    if (rst) begin
        validator_done <= 0;
        validator_accept <= 0;
        builder_done <= 0;
        builder_header <= 0;
    end else begin
        validator_done <= validator_start;
        if (validator_start)
            validator_accept <= 1'b1;

        builder_done <= builder_start;
        if (builder_start)
            builder_header <= {
                builder_index,
                builder_prev_hash,
                builder_tx
            };

    end
end

task send_transaction;
    input [63:0] packet;
    input [31:0] expected_next;
    integer cycles;
    begin
        @(negedge clk);
        while (!tx_ready) @(negedge clk);

        tx_data = packet;
        tx_valid = 1'b1;

        @(negedge clk);
        tx_valid = 1'b0;

        cycles = 0;
        while (!result_valid && cycles < 500) begin
            @(negedge clk);
            cycles = cycles + 1;
        end

        if (cycles >= 500) begin
            $display("FAIL : TIMEOUT");
            errors = errors + 1;
        end else begin
            $display(
                "TX=%h STATUS=%h INDEX=%0d NEXT=%0d",
                packet, result_status, result_index, next_index
            );

            if (result_status !== 8'h00 ||
                next_index !== expected_next) begin
                $display("FAIL : CONTROLEUR OU STOCKAGE");
                errors = errors + 1;
            end
        end

        @(negedge clk);
    end
endtask


// === Integration des deux autres modules de Bouchra ===
// Lecture du contenu en BRAM faite dans ce testbench uniquement.
// Les modules reels (controleur, stockage, SHA) restent inchanges.
reg [31:0]  val_index = 0;
reg [255:0] val_prev = 0, val_stored = 0, val_expected_prev = 0;
reg [63:0]  val_tx = 0;
reg val_start = 0;
wire val_busy, val_done, val_link_ok, val_hash_ok, val_valid;
wire [255:0] val_computed_hash;

chain_validator VALIDATEUR_CHAINE (
    .clk(clk), .rst(rst), .start(val_start),
    .index(val_index), .previous_hash(val_prev),
    .transaction(val_tx), .stored_hash(val_stored),
    .expected_previous_hash(val_expected_prev),
    .busy(val_busy), .done(val_done),
    .link_ok(val_link_ok), .hash_ok(val_hash_ok),
    .chain_valid(val_valid), .computed_hash(val_computed_hash)
);

reg [31:0] bh_index = 0;
reg [255:0] bh_prev = 0;
reg [63:0] bh_tx = 0;
reg bh_start = 0;
wire bh_busy, bh_done;
wire [255:0] bh_hash;

block_hash HASH_BLOC_BOUCHRA (
    .clk(clk), .rst(rst), .start(bh_start),
    .index(bh_index), .previous_hash(bh_prev),
    .transaction(bh_tx), .busy(bh_busy),
    .done(bh_done), .hash(bh_hash)
);

reg [607:0] bloc2_sauvegarde;

task tester_hash_bloc;
    input [3:0] adresse;
    integer cycles;
    begin
        @(negedge clk);
        bh_index = STORE.STORAGE.mem[adresse][607:576];
        bh_prev  = STORE.STORAGE.mem[adresse][575:320];
        bh_tx    = STORE.STORAGE.mem[adresse][319:256];
        bh_start = 1'b1;
        @(negedge clk);
        bh_start = 1'b0;
        cycles = 0;
        while (bh_done !== 1'b1 && cycles < 150) begin
            @(negedge clk);
            cycles = cycles + 1;
        end
        if (cycles >= 150 || bh_hash !== STORE.STORAGE.mem[adresse][255:0]) begin
            $display("FAIL : BLOCK_HASH BLOC PHYSIQUE %0d", adresse);
            errors = errors + 1;
        end else begin
            $display("PASS : BLOCK_HASH REEL BLOC PHYSIQUE %0d", adresse);
        end
    end
endtask

task tester_integrite;
    input [3:0] adresse;
    input [255:0] hash_precedent_attendu;
    input lien_attendu;
    input hash_attendu;
    input validite_attendue;
    input [8*48-1:0] libelle;
    integer cycles;
    begin
        @(negedge clk);
        val_index = STORE.STORAGE.mem[adresse][607:576];
        val_prev  = STORE.STORAGE.mem[adresse][575:320];
        val_tx    = STORE.STORAGE.mem[adresse][319:256];
        val_stored = STORE.STORAGE.mem[adresse][255:0];
        val_expected_prev = hash_precedent_attendu;
        val_start = 1'b1;
        @(negedge clk);
        val_start = 1'b0;
        cycles = 0;
        while (val_done !== 1'b1 && cycles < 150) begin
            @(negedge clk);
            cycles = cycles + 1;
        end
        if (cycles >= 150 || val_link_ok !== lien_attendu ||
            val_hash_ok !== hash_attendu || val_valid !== validite_attendue) begin
            $display("FAIL : %0s (link=%b hash=%b valid=%b)",
                     libelle, val_link_ok, val_hash_ok, val_valid);
            errors = errors + 1;
        end else begin
            $display("PASS : %0s", libelle);
        end
    end
endtask

initial begin
    repeat(4) @(negedge clk);
    rst = 0;

    if (STORE.STORAGE.mem[0] !== 608'd1) begin
        $display("FAIL : GENESIS MODIFIE");
        errors = errors + 1;
    end else $display("PASS : GENESIS PRESERVE");

    // Bloc 0 : premier bloc de la chaine
    send_transaction(
        64'h07011234567800AA,
        32'd1
    );

    if (result_hash !== 256'h5340d663384c25c0bff9964af0d47b3abb746752ba4af91408e641f59a2cbc7d) begin
        $display("FAIL : SHA REEL BLOC 0"); errors = errors + 1;
    end else $display("PASS : SHA REEL BLOC 0");

    expected_block0 = {
        32'd0,
        256'd0,
        64'h07011234567800AA,
        256'h5340d663384c25c0bff9964af0d47b3abb746752ba4af91408e641f59a2cbc7d
    };

    if (STORE.STORAGE.mem[1] !== expected_block0) begin
        $display("FAIL : BLOC 0 INCORRECT");
        errors = errors + 1;
    end else begin
        $display("PASS : BLOC 0 STOCKE");
    end

    // Bloc 1 : son previous_hash doit etre 0x100
    send_transaction(
        64'h0703123456780055,
        32'd2
    );

    if (result_hash !== 256'haf02679bbe0c555e390d2f41ccf0eb55d9e7ba3867542ea3ce3c802268eb835f) begin
        $display("FAIL : SHA REEL BLOC 1"); errors = errors + 1;
    end else $display("PASS : SHA REEL BLOC 1");

    expected_block1 = {
        32'd1,
        256'h5340d663384c25c0bff9964af0d47b3abb746752ba4af91408e641f59a2cbc7d,
        64'h0703123456780055,
        256'haf02679bbe0c555e390d2f41ccf0eb55d9e7ba3867542ea3ce3c802268eb835f
    };

    if (STORE.STORAGE.mem[2] !== expected_block1) begin
        $display("FAIL : BLOC 1 INCORRECT");
        errors = errors + 1;
    end else begin
        $display("PASS : BLOC 1 STOCKE");
    end

    if (STORE.STORAGE.mem[0] !== 608'd1 || STORE.STORAGE.block_count !== 5'd3) begin
        $display("FAIL : GENESIS OU NOMBRE DE BLOCS");
        errors = errors + 1;
    end else $display("PASS : GENESIS ET COMPTEUR (3)");

    if (previous_hash !== 256'haf02679bbe0c555e390d2f41ccf0eb55d9e7ba3867542ea3ce3c802268eb835f) begin
        $display("FAIL : PREVIOUS HASH");
        errors = errors + 1;
    end else begin
        $display("PASS : CHAINAGE LOGIQUE");
    end

    // Tester le vrai block_hash sur chaque bloc relu en BRAM.
    tester_hash_bloc(4'd1);
    tester_hash_bloc(4'd2);

    // Verification de l'integrite et du chaînage des deux blocs.
    tester_integrite(4'd1, 256'd0, 1'b1, 1'b1, 1'b1,
                     "BLOC 0 VALIDE EN BRAM");
    tester_integrite(4'd2, expected_block0[255:0], 1'b1, 1'b1, 1'b1,
                     "BLOC 1 CHAINE EN BRAM");

    // Trois corruptions volontaires dans la BRAM de simulation.
    bloc2_sauvegarde = STORE.STORAGE.mem[2];

    STORE.STORAGE.mem[2][256] = ~STORE.STORAGE.mem[2][256]; // Transaction
    tester_integrite(4'd2, expected_block0[255:0], 1'b1, 1'b0, 1'b0,
                     "TRANSACTION MODIFIEE DETECTEE");
    STORE.STORAGE.mem[2] = bloc2_sauvegarde;

    STORE.STORAGE.mem[2][320] = ~STORE.STORAGE.mem[2][320]; // Prev hash
    tester_integrite(4'd2, expected_block0[255:0], 1'b0, 1'b0, 1'b0,
                     "MAUVAIS PREVIOUS HASH DETECTE");
    STORE.STORAGE.mem[2] = bloc2_sauvegarde;

    STORE.STORAGE.mem[2][0] = ~STORE.STORAGE.mem[2][0]; // Hash stocke
    tester_integrite(4'd2, expected_block0[255:0], 1'b1, 1'b0, 1'b0,
                     "HASH STOCKE CORROMPU DETECTE");
    STORE.STORAGE.mem[2] = bloc2_sauvegarde;

    tester_integrite(4'd2, expected_block0[255:0], 1'b1, 1'b1, 1'b1,
                     "BLOC 1 RESTAURE VALIDE");
    if (STORE.STORAGE.mem[0] !== 608'd1) begin
        $display("FAIL : GENESIS APRES TESTS");
        errors = errors + 1;
    end else $display("PASS : GENESIS TOUJOURS PROTEGE");

    if (errors == 0)
        $display("PASS : INTEGRATION SHA + BLOCK_HASH + CHAIN_VALIDATOR + NADA + KHADIJA");
    else
        $display("FAIL : %0d ERRORS", errors);

    $finish;
end

initial begin
    #150000;
    $display("FAIL : TIMEOUT GLOBAL");
    $finish;
end

endmodule
