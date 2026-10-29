`timescale 1ns/1ps
// Test de bout en bout de la mini-blockchain a un noeud (simulation) :
//   trames d'octets -> cmd_decoder -> transaction_validator -> cuckoo_top (KVS en BRAM)
//                                          |-> block_builder -> SHA-256 (modele) -> stockage (modele)
// Les empreintes de reference ont ete calculees avec hashlib (Python).
module tb_blockchain_e2e;

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
    wire [407:0] blk_data;
    reg          hash_done = 0, store_done = 0;
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

    block_builder #(.AUTO_GENESIS(1)) BB (
        .clk(clk), .rst(rst),
        .tx_valid(tx_acc_valid), .tx_type(tx_acc_type), .tx_key(tx_acc_key), .tx_value(tx_acc_value),
        .ready(blk_ready), .hold(blk_hold), .seal(seal),
        .init_valid(1'b0), .init_index(32'd0), .init_hash(256'd0),
        .hash_start(hash_start), .blk_data(blk_data), .hash_done(hash_done), .hash_value(hash_value),
        .store_start(store_start), .blk_index(blk_index), .blk_hash(blk_hash), .store_done(store_done), .st_full(1'b0),
        .next_index(next_index), .last_hash(last_hash), .blocks_stored(blocks_stored),
        .busy(bb_busy), .dbg_state(bb_state)
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

    // message de 51 octets -> bloc complete (octet 0x80, zeros, longueur 408 bits)
    function [511:0] pad51(input [407:0] msg);
        begin pad51 = {msg, 8'h80, 32'h0, 64'd408}; end
    endfunction


    // ------------------------------------------------------------------
    // Moteur de hachage (latence 40 cycles) et stockage (latence 5 cycles) simules
    // ------------------------------------------------------------------
    reg [407:0] st_data [0:7];
    reg [255:0] st_hash [0:7];
    reg [31:0]  st_idx  [0:7];
    integer     n_stored = 0, hcnt = 0, scnt = 0;

    always @(posedge clk) begin
        hash_done  <= 1'b0;
        store_done <= 1'b0;
        if (hash_start) begin
            sha256_block(pad51(blk_data));
            hcnt = 40;
        end else if (hcnt > 0) begin
            hcnt = hcnt - 1;
            if (hcnt == 0) begin hash_value <= sha_out; hash_done <= 1'b1; end
        end
        if (store_start) begin
            st_data[n_stored] = blk_data;
            st_hash[n_stored] = blk_hash;
            st_idx[n_stored]  = blk_index;
            n_stored = n_stored + 1;
            scnt = 5;
        end else if (scnt > 0) begin
            scnt = scnt - 1;
            if (scnt == 0) store_done <= 1'b1;
        end
    end

    // reponses recues
    integer    resp_n = 0;
    reg [7:0]  r_cmd, r_status;
    reg [15:0] r_value;
    always @(posedge clk)
        if (resp_valid) begin
            resp_n = resp_n + 1;
            r_cmd = resp_cmd; r_status = resp_status; r_value = resp_value;
        end

    initial begin
        #60000000;
        $display("ERREUR : delai global depasse, la simulation est arretee");
        $finish;
    end

    // ------------------------------------------------------------------
    // Outils de test
    // ------------------------------------------------------------------
    integer errors = 0, i, t;
    reg [7:0] fb [0:15];

    task check(input cond, input [1023:0] msg);
        begin
            if (!cond) begin $display("ERREUR : %0s", msg); errors = errors + 1; end
            else       $display("OK      : %0s", msg);
        end
    endtask

    // envoie une commande (octet LEN, code, cle, valeur) comme le fera le RX CAN-FD, attend la reponse
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
            while (resp_n == n0 && tt < 5000) begin @(negedge clk); tt = tt + 1; end
            if (resp_n == n0) begin $display("ERREUR : pas de reponse (cmd %h cle %h)", c, k); errors = errors + 1; end
            repeat (4) @(negedge clk);
        end
    endtask

    integer tt_wait;

    task wait_stored(input integer n);
        begin
            tt_wait = 0;
            while ((n_stored < n || bb_busy) && tt_wait < 3000) begin @(negedge clk); tt_wait = tt_wait + 1; end
        end
    endtask

    localparam [255:0] EXP_H0 = 256'h8e8fe47e4a33b178bf0433d8050cb0ad7ec323fbdeeab3ecfd857b4ce1805b7a;
    localparam [255:0] EXP_H1 = 256'h57b61e1308e553f7ad0bd4701b4546f10ba0e01ebc77a050619f5cbf7afc7abf;
    localparam [255:0] EXP_H2 = 256'h4c7220d23eb3109616103d99d2ec3dc2027e4ebdafc6eb99e904eebb8a9bef37;
    localparam [407:0] EXP_B1 = 408'h000000018e8fe47e4a33b178bf0433d8050cb0ad7ec323fbdeeab3ecfd857b4ce1805b7a02011111111100aa012222222200bb;
    localparam [407:0] EXP_B2 = 408'h0000000257b61e1308e553f7ad0bd4701b4546f10ba0e01ebc77a050619f5cbf7afc7abf010311111111005500000000000000;


    integer nb0;

    initial begin
        $dumpfile("blockchain_e2e.vcd");
        $dumpvars(0, tb_blockchain_e2e);
        repeat (4) @(negedge clk); rst = 0;

        // ---- bloc Genesis ----
        wait_stored(1);
        check(n_stored == 1 && st_hash[0] == EXP_H0, "Genesis cree et stocke apres le reset (empreinte conforme a hashlib)");

        // ---- bloc 1 : deux transactions valides recues sous forme de trames ----
        run_cmd(CREATE, 32'h11111111, 16'h00AA);
        check(r_status == ST_OK, "trame CREATE 11111111 = 00AA : reponse OK");
        run_cmd(CREATE, 32'h22222222, 16'h00BB);
        check(r_status == ST_OK, "trame CREATE 22222222 = 00BB : reponse OK");
        wait_stored(2);
        check(n_stored == 2 && st_data[1] == EXP_B1, "bloc 1 : les deux transactions sont dans le bloc (contenu conforme)");
        check(st_hash[1] == EXP_H1, "bloc 1 : empreinte SHA-256 conforme a hashlib, chainee au Genesis");

        // ---- transactions invalides : refusees, rien dans le bloc ----
        nb0 = BB.count;
        run_cmd(CREATE, 32'h11111111, 16'h0001);
        check(r_status == ST_CKERR, "CREATE d'une cle existante : refuse");
        run_cmd(TRANSFER, 32'h99999999, 16'h0001);
        check(r_status == ST_NOTFOUND, "TRANSFER d'une cle absente : refuse (cle absente)");
        run_cmd(CREATE, 32'h00000000, 16'h0001);
        check(r_status == ST_CKERR, "CREATE avec cle nulle : refuse");
        run_cmd(CREATE, 32'h33333333, 16'h0000);
        check(r_status == ST_CKERR, "CREATE avec valeur nulle : refuse");
        run_cmd(8'h7F, 32'h44444444, 16'h0001);
        check(r_status == ST_UNKNOWN, "type de commande inconnu : refuse par le decodeur");
        check(BB.count == nb0 && n_stored == 2, "aucune transaction refusee n'est entree dans un bloc");

        // ---- etat du KVS coherent avec les transactions validees ----
        run_cmd(SEARCH, 32'h11111111, 16'h0000);
        check(r_status == ST_OK && r_value == 16'h00AA, "SEARCH : 11111111 = 00AA (etat du KVS conforme)");
        run_cmd(SEARCH, 32'h33333333, 16'h0000);
        check(r_status == ST_NOTFOUND, "SEARCH : la cle d'une transaction refusee n'existe pas");

        // ---- bloc 2 : TRANSFER + scellement manuel ----
        run_cmd(TRANSFER, 32'h11111111, 16'h0055);
        check(r_status == ST_OK, "TRANSFER 11111111 = 0055 : reponse OK");
        @(negedge clk); seal = 1; @(negedge clk); seal = 0;
        wait_stored(3);
        check(n_stored == 3 && st_data[2] == EXP_B2, "bloc 2 : une transaction, contenu conforme");
        check(st_hash[2] == EXP_H2, "bloc 2 : empreinte SHA-256 conforme a hashlib, chainee au bloc 1");
        run_cmd(SEARCH, 32'h11111111, 16'h0000);
        check(r_status == ST_OK && r_value == 16'h0055, "SEARCH apres TRANSFER : 0055");

        // ---- integrite de la chaine ----
        check(st_data[1][375:120] == st_hash[0] && st_data[2][375:120] == st_hash[1], "chainage : chaque bloc contient l'empreinte du precedent");
        sha256_block(pad51(st_data[1] ^ 408'h1));
        check(sha_out != st_hash[1] && sha_out != st_data[2][375:120], "alteration du bloc 1 detectee : empreinte differente, chaine brisee");

        if (errors == 0) $display("MINI-BLOCKCHAIN DE BOUT EN BOUT : OK");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end
endmodule
