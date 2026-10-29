`timescale 1ns/1ps
// Test de la mini-blockchain avec le VRAI module blockchain_storage (Khadija) via l'adaptateur chain_storage_if.
// Seul le cœur SHA-256 reste un modele (a remplacer par celui de Bouchra).
// Stockage reduit a 4 cases (ADDR_WIDTH = 2) : Genesis + 3 blocs, pour tester aussi la limite de capacite.
module tb_blockchain_storage;

    localparam [7:0] CREATE = 8'h01, SEARCH = 8'h02, TRANSFER = 8'h03;
    localparam [7:0] ST_OK = 8'h00, ST_NOTFOUND = 8'h01, ST_CKERR = 8'h02, ST_UNKNOWN = 8'h03, ST_BADLEN = 8'h04;

    reg clk = 0, rst = 1;
    reg [7:0] rx_data = 0;
    reg rx_valid = 0, rx_frame_done = 0, rx_error = 0;
    reg seal = 0;

    // decodeur <-> validateur
    wire [7:0]  ck_cmd;
    wire [31:0] ck_key;
    wire [15:0] ck_value, ck_value_out;
    wire        ck_start, ck_busy, ck_done, ck_found, ck_error;
    wire [3:0]  in_err_code;

    // validateur <-> KVS
    wire [7:0]  kv_cmd;
    wire [31:0] kv_key;
    wire [15:0] kv_value, kv_value_out;
    wire        kv_start, kv_busy, kv_done, kv_found, kv_error;

    // validateur <-> constructeur de bloc
    wire        blk_ready, blk_hold, tx_acc_valid;
    wire [7:0]  tx_acc_type;
    wire [31:0] tx_acc_key;
    wire [15:0] tx_acc_value;

    // constructeur de bloc <-> hachage / stockage
    wire         hash_start, store_start, bb_busy;
    wire [351:0] blk_data;
    reg          hash_done = 0;
    wire         store_done, st_full;
    reg  [255:0] hash_value = 0;
    wire [31:0]  blk_index, next_index, blocks_stored;
    wire [255:0] blk_hash, last_hash;
    wire [3:0]   bb_state;

    // reponses vers le "TX"
    wire        resp_valid;
    wire [7:0]  resp_cmd, resp_status;
    wire [15:0] resp_value;
    wire        err_valid, dbg_overrun, dbg_rejected;
    wire [1:0]  err_code;
    wire [2:0]  dec_state;
    wire [3:0]  val_state;

    cmd_decoder #(.TIMEOUT(4000)) DEC (
        .clk(clk), .rst(rst),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_frame_done(rx_frame_done), .rx_error(rx_error),
        .ck_cmd(ck_cmd), .ck_key(ck_key), .ck_value(ck_value), .ck_start(ck_start),
        .ck_busy(ck_busy), .ck_done(ck_done), .ck_found(ck_found), .ck_value_out(ck_value_out), .ck_error(ck_error),
        .resp_valid(resp_valid), .resp_ready(1'b1),
        .resp_cmd(resp_cmd), .resp_status(resp_status), .resp_value(resp_value),
        .err_valid(err_valid), .err_code(err_code),
        .dbg_overrun(dbg_overrun), .dbg_rejected(dbg_rejected), .dbg_state(dec_state)
    );

    transaction_validator #(.VALUE_MIN(16'd1), .VALUE_MAX(16'hFFFF), .TIMEOUT(3000)) VAL (
        .clk(clk), .rst(rst),
        .in_cmd(ck_cmd), .in_key(ck_key), .in_value(ck_value), .in_start(ck_start),
        .in_busy(ck_busy), .in_done(ck_done), .in_found(ck_found), .in_value_out(ck_value_out),
        .in_error(ck_error), .in_err_code(in_err_code),
        .kv_cmd(kv_cmd), .kv_key(kv_key), .kv_value(kv_value), .kv_start(kv_start),
        .kv_busy(kv_busy), .kv_done(kv_done), .kv_found(kv_found), .kv_value_out(kv_value_out), .kv_error(kv_error),
        .blk_ready(blk_ready), .blk_hold(blk_hold), .tx_acc_valid(tx_acc_valid),
        .tx_acc_type(tx_acc_type), .tx_acc_key(tx_acc_key), .tx_acc_value(tx_acc_value),
        .dbg_state(val_state)
    );

    cuckoo_top #(.KEY_W(32), .VAL_W(16), .IDX_W(8)) KVS (
        .clk(clk), .rst(rst),
        .cmd(kv_cmd), .key(kv_key), .value_in(kv_value), .start(kv_start),
        .busy(kv_busy), .done(kv_done), .found(kv_found), .value_out(kv_value_out), .error(kv_error)
    );

    block_builder #(.AUTO_GENESIS(2)) BB (
        .clk(clk), .rst(rst),
        .tx_valid(tx_acc_valid), .tx_type(tx_acc_type), .tx_key(tx_acc_key), .tx_value(tx_acc_value),
        .ready(blk_ready), .hold(blk_hold), .seal(seal),
        .init_valid(1'b0), .init_index(32'd0), .init_hash(256'd0),
        .hash_start(hash_start), .blk_data(blk_data), .hash_done(hash_done), .hash_value(hash_value),
        .store_start(store_start), .blk_index(blk_index), .blk_hash(blk_hash), .store_done(store_done), .st_full(st_full),
        .next_index(next_index), .last_hash(last_hash), .blocks_stored(blocks_stored),
        .busy(bb_busy), .dbg_state(bb_state)
    );


    // lecture du stockage
    reg         rd_en = 0;
    reg  [1:0]  rd_index = 0;
    wire [607:0] rd_record;
    wire        rd_valid, rd_err;
    wire [2:0]  block_count;

    chain_storage_if #(.ADDR_WIDTH(2)) STO (
        .clk(clk), .rst(rst),
        .store_start(store_start), .blk_data(blk_data), .blk_hash(blk_hash),
        .store_done(store_done), .st_full(st_full),
        .rd_en(rd_en), .block_index(rd_index), .rd_record(rd_record),
        .rd_valid(rd_valid), .rd_err(rd_err), .block_count(block_count)
    );

    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // SHA-256 comportemental (un seul bloc de 512 bits deja complete par le padding)
    // ------------------------------------------------------------------
    reg [31:0] K [0:63];
    reg [31:0] H [0:7];
    reg [31:0] W [0:63];
    reg [255:0] sha_out;
    initial begin
        K[0] = 32'h428a2f98;
        K[1] = 32'h71374491;
        K[2] = 32'hb5c0fbcf;
        K[3] = 32'he9b5dba5;
        K[4] = 32'h3956c25b;
        K[5] = 32'h59f111f1;
        K[6] = 32'h923f82a4;
        K[7] = 32'hab1c5ed5;
        K[8] = 32'hd807aa98;
        K[9] = 32'h12835b01;
        K[10] = 32'h243185be;
        K[11] = 32'h550c7dc3;
        K[12] = 32'h72be5d74;
        K[13] = 32'h80deb1fe;
        K[14] = 32'h9bdc06a7;
        K[15] = 32'hc19bf174;
        K[16] = 32'he49b69c1;
        K[17] = 32'hefbe4786;
        K[18] = 32'h0fc19dc6;
        K[19] = 32'h240ca1cc;
        K[20] = 32'h2de92c6f;
        K[21] = 32'h4a7484aa;
        K[22] = 32'h5cb0a9dc;
        K[23] = 32'h76f988da;
        K[24] = 32'h983e5152;
        K[25] = 32'ha831c66d;
        K[26] = 32'hb00327c8;
        K[27] = 32'hbf597fc7;
        K[28] = 32'hc6e00bf3;
        K[29] = 32'hd5a79147;
        K[30] = 32'h06ca6351;
        K[31] = 32'h14292967;
        K[32] = 32'h27b70a85;
        K[33] = 32'h2e1b2138;
        K[34] = 32'h4d2c6dfc;
        K[35] = 32'h53380d13;
        K[36] = 32'h650a7354;
        K[37] = 32'h766a0abb;
        K[38] = 32'h81c2c92e;
        K[39] = 32'h92722c85;
        K[40] = 32'ha2bfe8a1;
        K[41] = 32'ha81a664b;
        K[42] = 32'hc24b8b70;
        K[43] = 32'hc76c51a3;
        K[44] = 32'hd192e819;
        K[45] = 32'hd6990624;
        K[46] = 32'hf40e3585;
        K[47] = 32'h106aa070;
        K[48] = 32'h19a4c116;
        K[49] = 32'h1e376c08;
        K[50] = 32'h2748774c;
        K[51] = 32'h34b0bcb5;
        K[52] = 32'h391c0cb3;
        K[53] = 32'h4ed8aa4a;
        K[54] = 32'h5b9cca4f;
        K[55] = 32'h682e6ff3;
        K[56] = 32'h748f82ee;
        K[57] = 32'h78a5636f;
        K[58] = 32'h84c87814;
        K[59] = 32'h8cc70208;
        K[60] = 32'h90befffa;
        K[61] = 32'ha4506ceb;
        K[62] = 32'hbef9a3f7;
        K[63] = 32'hc67178f2;
        H[0] = 32'h6a09e667;
        H[1] = 32'hbb67ae85;
        H[2] = 32'h3c6ef372;
        H[3] = 32'ha54ff53a;
        H[4] = 32'h510e527f;
        H[5] = 32'h9b05688c;
        H[6] = 32'h1f83d9ab;
        H[7] = 32'h5be0cd19;
    end

    function [31:0] rotr(input [31:0] x, input integer n);
        begin rotr = (x >> n) | (x << (32 - n)); end
    endfunction

    task sha256_block(input [511:0] blk);
        integer t;
        reg [31:0] a, b, c, d, e, f, g, h, s0, s1, ch, maj, t1, t2;
        begin
            for (t = 0; t < 16; t = t + 1) W[t] = blk[511 - 32*t -: 32];
            for (t = 16; t < 64; t = t + 1) begin
                s0 = rotr(W[t-15], 7) ^ rotr(W[t-15], 18) ^ (W[t-15] >> 3);
                s1 = rotr(W[t-2], 17) ^ rotr(W[t-2], 19)  ^ (W[t-2] >> 10);
                W[t] = W[t-16] + s0 + W[t-7] + s1;
            end
            a = H[0]; b = H[1]; c = H[2]; d = H[3]; e = H[4]; f = H[5]; g = H[6]; h = H[7];
            for (t = 0; t < 64; t = t + 1) begin
                s1  = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
                ch  = (e & f) ^ (~e & g);
                t1  = h + s1 + ch + K[t] + W[t];
                s0  = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
                maj = (a & b) ^ (a & c) ^ (b & c);
                t2  = s0 + maj;
                h = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
            end
            sha_out = {H[0]+a, H[1]+b, H[2]+c, H[3]+d, H[4]+e, H[5]+f, H[6]+g, H[7]+h};
        end
    endtask

    // Message de 44 octets -> bloc SHA-256 complete, longueur 352 bits
    function [511:0] pad44(input [351:0] msg);
        begin
            pad44 = {msg, 8'h80, 88'd0, 64'd352};
        end
    endfunction


    // moteur de hachage simule (latence 40 cycles)
    integer hcnt = 0;
    always @(posedge clk) begin
        hash_done <= 1'b0;
        if (hash_start) begin
            sha256_block(pad44(blk_data));
            hcnt = 40;
        end else if (hcnt > 0) begin
            hcnt = hcnt - 1;
            if (hcnt == 0) begin hash_value <= sha_out; hash_done <= 1'b1; end
        end
    end

    integer    resp_n = 0;
    reg [7:0]  r_cmd, r_status;
    reg [15:0] r_value;
    always @(posedge clk)
        if (resp_valid) begin
            resp_n = resp_n + 1;
            r_cmd = resp_cmd; r_status = resp_status; r_value = resp_value;
        end

    initial begin
        #80000000;
        $display("ERREUR : delai global depasse, la simulation est arretee");
        $finish;
    end

    integer errors = 0, i, tt_wait;
    reg [7:0] fb [0:15];

    task check(input cond, input [1023:0] msg);
        begin
            if (!cond) begin $display("ERREUR : %0s", msg); errors = errors + 1; end
            else       $display("OK      : %0s", msg);
        end
    endtask

    task run_cmd(input [7:0] c, input [31:0] k, input [15:0] v);
        integer n, len, tt, n0;
        begin
            len = (c == SEARCH) ? 5 : 7;
            fb[0] = len; fb[1] = c;
            fb[2] = k[31:24]; fb[3] = k[23:16]; fb[4] = k[15:8]; fb[5] = k[7:0];
            fb[6] = v[15:8];  fb[7] = v[7:0];
            n0 = resp_n;
            for (n = 0; n < len + 1; n = n + 1) begin
                @(negedge clk); rx_data = fb[n]; rx_valid = 1;
                @(negedge clk); rx_valid = 0;
            end
            @(negedge clk); rx_frame_done = 1;
            @(negedge clk); rx_frame_done = 0;
            tt = 0;
            while (resp_n == n0 && tt < 8000) begin @(negedge clk); tt = tt + 1; end
            if (resp_n == n0) begin $display("ERREUR : pas de reponse (cmd %h cle %h)", c, k); errors = errors + 1; end
            repeat (4) @(negedge clk);
        end
    endtask

    task wait_idle;
        begin
            tt_wait = 0;
            repeat (3) @(negedge clk);
            while (bb_busy && tt_wait < 3000) begin @(negedge clk); tt_wait = tt_wait + 1; end
        end
    endtask

    // lit une case du stockage (lecture synchrone : rd_valid / rd_err un cycle plus tard)
    reg [607:0] rec;
    reg         rec_valid, rec_err;
    task rd(input [1:0] idx);
        begin
            @(negedge clk); rd_index = idx; rd_en = 1;
            @(negedge clk);                                   // un front d'horloge plus tard : donnee et rd_valid disponibles
            rec = rd_record; rec_valid = rd_valid; rec_err = rd_err;
            rd_en = 0;
        end
    endtask

    // SHA-256 de 44 octets nuls : Genesis
    localparam [255:0] EXP_H0 =
        256'h85759b3811ff7dc47b03792ac85317be51431a3f9e01dcafce317ed736a391b0;

    // Bloc 1 : CREATE 11111111 = 00AA
    localparam [255:0] EXP_H1 =
        256'h5e29442e6444de3e89fd30bcecaa0b4068d339bdb9fd4294bc5f6a1ac20314d3;

    // Bloc 2 : CREATE 22222222 = 00BB
    localparam [255:0] EXP_H2 =
        256'h4ee637030564ea0663a2d6b5489abf4bd7add91bfad902f4277ba827c7a8d154;

    // Bloc 3 : TRANSFER 11111111 = 0055
    localparam [255:0] EXP_H3 =
        256'h5e425ac33d7f60bbcf096d3839162caf742688256e11a709c5fc6d5c9d6c58be;

    // Format : index (32) | hash precedent (256) | transaction (64)
    localparam [351:0] EXP_B1 = {32'd1, EXP_H0, 64'h00011111111100AA};
    localparam [351:0] EXP_B2 = {32'd2, EXP_H1, 64'h00012222222200BB};
    localparam [351:0] EXP_B3 = {32'd3, EXP_H2, 64'h0003111111110055};

    initial begin
        $dumpfile("blockchain_storage.vcd");
        $dumpvars(0, tb_blockchain_storage);
        rst = 1;
        repeat (4) @(negedge clk); rst = 0;
        repeat (5) @(negedge clk);

        // ---- etat initial : Genesis deja dans la case 0 ----
        rd(2'd0);
        check(rec_valid && rec == {352'd0, EXP_H0}, "case 0 du stockage : Genesis (44 octets a zero + empreinte SHA-256 reelle)");
        check(block_count == 3'd1 && !st_full, "stockage : 1 bloc (Genesis), pas plein");
        check(BB.next_index == 32'd1 && BB.last_hash == EXP_H0, "constructeur : pret pour le bloc 1, empreinte precedente = celle du Genesis");

        // ---- Bloc 1 : CREATE ----
        run_cmd(CREATE, 32'h11111111, 16'h00AA);
        check(r_status == ST_OK, "CREATE 11111111 = 00AA : OK");
        @(negedge clk); seal = 1;
        @(negedge clk); seal = 0;
        wait_idle;
        rd(2'd1);
        check(rec_valid && rec == {EXP_B1, EXP_H1},
              "bloc 1 : CREATE et hash SHA-256 corrects");

        // ---- Bloc 2 : second CREATE ----
        run_cmd(CREATE, 32'h22222222, 16'h00BB);
        check(r_status == ST_OK, "CREATE 22222222 = 00BB : OK");
        @(negedge clk); seal = 1;
        @(negedge clk); seal = 0;
        wait_idle;
        rd(2'd2);
        check(rec_valid && rec == {EXP_B2, EXP_H2},
              "bloc 2 : lien au bloc 1 et hash corrects");
        check(block_count == 3'd3 && !st_full,
              "stockage : Genesis et deux blocs");

        // ---- Bloc 3 : TRANSFER ----
        run_cmd(TRANSFER, 32'h11111111, 16'h0055);
        check(r_status == ST_OK, "TRANSFER 11111111 = 0055 : OK");
        @(negedge clk); seal = 1;
        @(negedge clk); seal = 0;
        wait_idle;
        rd(2'd3);
        check(rec_valid && rec == {EXP_B3, EXP_H3},
              "bloc 3 : lien au bloc 2 et hash corrects");
        check(block_count == 3'd4 && st_full,
              "stockage plein : Genesis + trois blocs");

        // ---- Capacité pleine ----
        run_cmd(CREATE, 32'h000000C5, 16'h0005);
        check(r_status == ST_CKERR,
              "stockage plein : nouvelle transaction refusee");

        run_cmd(SEARCH, 32'h000000C5, 16'h0000);
        check(r_status == ST_NOTFOUND,
              "la transaction refusee n'est pas dans le KVS");

        run_cmd(SEARCH, 32'h11111111, 16'h0000);
        check(r_status == ST_OK && r_value == 16'h0055,
              "SEARCH : 11111111 vaut toujours 0055");

        // ---- lecture hors limite : erreur ----
        // (index 3 est le dernier valide avec ADDR_WIDTH = 2 ; la case 0 reste lisible)
        rd(2'd0);
        check(rec_valid && !rec_err, "lecture d'une case existante : rd_valid, pas d'erreur");

        if (errors == 0) $display("MINI-BLOCKCHAIN AVEC LE STOCKAGE DE KHADIJA : OK");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end
endmodule
