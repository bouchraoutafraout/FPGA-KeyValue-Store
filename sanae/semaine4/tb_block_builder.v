
`timescale 1ns/1ps

module tb_block_builder;

    reg clk = 0, rst = 1;
    reg tx_valid = 0, hold = 0, seal = 0, init_valid = 0;
    reg [7:0] tx_type = 0;
    reg [31:0] tx_key = 0, init_index = 0;
    reg [15:0] tx_value = 0;
    reg [255:0] init_hash = 0;

    wire ready, hash_start, store_start, busy;
    wire [351:0] blk_data;

    reg hash_done = 0, store_done = 0;
    reg [255:0] hash_value = 0;

    wire [31:0] blk_index, next_index, blocks_stored;
    wire [255:0] blk_hash, last_hash;
    wire [3:0] dbg_state;

    block_builder #(.AUTO_GENESIS(1)) dut (
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
        .hash_start(hash_start),
        .blk_data(blk_data),
        .hash_done(hash_done),
        .hash_value(hash_value),
        .store_start(store_start),
        .blk_index(blk_index),
        .blk_hash(blk_hash),
        .store_done(store_done),
        .st_full(1'b0),
        .next_index(next_index),
        .last_hash(last_hash),
        .blocks_stored(blocks_stored),
        .busy(busy),
        .dbg_state(dbg_state)
    );

    always #5 clk = ~clk;

    // ============================================================
    // Moteur SHA-256 comportemental
    // ============================================================

    reg [31:0] K [0:63];
    reg [31:0] H [0:7];
    reg [31:0] W [0:63];
    reg [255:0] sha_out;

    initial begin
        K[0]=32'h428a2f98; K[1]=32'h71374491;
        K[2]=32'hb5c0fbcf; K[3]=32'he9b5dba5;
        K[4]=32'h3956c25b; K[5]=32'h59f111f1;
        K[6]=32'h923f82a4; K[7]=32'hab1c5ed5;
        K[8]=32'hd807aa98; K[9]=32'h12835b01;
        K[10]=32'h243185be; K[11]=32'h550c7dc3;
        K[12]=32'h72be5d74; K[13]=32'h80deb1fe;
        K[14]=32'h9bdc06a7; K[15]=32'hc19bf174;
        K[16]=32'he49b69c1; K[17]=32'hefbe4786;
        K[18]=32'h0fc19dc6; K[19]=32'h240ca1cc;
        K[20]=32'h2de92c6f; K[21]=32'h4a7484aa;
        K[22]=32'h5cb0a9dc; K[23]=32'h76f988da;
        K[24]=32'h983e5152; K[25]=32'ha831c66d;
        K[26]=32'hb00327c8; K[27]=32'hbf597fc7;
        K[28]=32'hc6e00bf3; K[29]=32'hd5a79147;
        K[30]=32'h06ca6351; K[31]=32'h14292967;
        K[32]=32'h27b70a85; K[33]=32'h2e1b2138;
        K[34]=32'h4d2c6dfc; K[35]=32'h53380d13;
        K[36]=32'h650a7354; K[37]=32'h766a0abb;
        K[38]=32'h81c2c92e; K[39]=32'h92722c85;
        K[40]=32'ha2bfe8a1; K[41]=32'ha81a664b;
        K[42]=32'hc24b8b70; K[43]=32'hc76c51a3;
        K[44]=32'hd192e819; K[45]=32'hd6990624;
        K[46]=32'hf40e3585; K[47]=32'h106aa070;
        K[48]=32'h19a4c116; K[49]=32'h1e376c08;
        K[50]=32'h2748774c; K[51]=32'h34b0bcb5;
        K[52]=32'h391c0cb3; K[53]=32'h4ed8aa4a;
        K[54]=32'h5b9cca4f; K[55]=32'h682e6ff3;
        K[56]=32'h748f82ee; K[57]=32'h78a5636f;
        K[58]=32'h84c87814; K[59]=32'h8cc70208;
        K[60]=32'h90befffa; K[61]=32'ha4506ceb;
        K[62]=32'hbef9a3f7; K[63]=32'hc67178f2;

        H[0]=32'h6a09e667;
        H[1]=32'hbb67ae85;
        H[2]=32'h3c6ef372;
        H[3]=32'ha54ff53a;
        H[4]=32'h510e527f;
        H[5]=32'h9b05688c;
        H[6]=32'h1f83d9ab;
        H[7]=32'h5be0cd19;
    end

    function [31:0] rotr(input [31:0] x, input integer n);
        begin
            rotr = (x >> n) | (x << (32-n));
        end
    endfunction

    task sha256_block(input [511:0] blk);
        integer t;
        reg [31:0] a,b,c,d,e,f,g,h;
        reg [31:0] s0,s1,ch,maj,t1,t2;
        begin
            for (t=0; t<16; t=t+1)
                W[t] = blk[511-32*t -: 32];

            for (t=16; t<64; t=t+1) begin
                s0 = rotr(W[t-15],7)
                   ^ rotr(W[t-15],18)
                   ^ (W[t-15] >> 3);
                s1 = rotr(W[t-2],17)
                   ^ rotr(W[t-2],19)
                   ^ (W[t-2] >> 10);

                W[t] = W[t-16] + s0 + W[t-7] + s1;
            end

            a=H[0]; b=H[1]; c=H[2]; d=H[3];
            e=H[4]; f=H[5]; g=H[6]; h=H[7];

            for (t=0; t<64; t=t+1) begin
                s1 = rotr(e,6) ^ rotr(e,11) ^ rotr(e,25);
                ch = (e & f) ^ (~e & g);
                t1 = h + s1 + ch + K[t] + W[t];

                s0 = rotr(a,2) ^ rotr(a,13) ^ rotr(a,22);
                maj = (a & b) ^ (a & c) ^ (b & c);
                t2 = s0 + maj;

                h=g; g=f; f=e; e=d+t1;
                d=c; c=b; b=a; a=t1+t2;
            end

            sha_out = {
                H[0]+a, H[1]+b, H[2]+c, H[3]+d,
                H[4]+e, H[5]+f, H[6]+g, H[7]+h
            };
        end
    endtask

    // ============================================================
    // Padding SHA-256 : message de 352 bits = 44 octets
    // 352 + 8 + 88 + 64 = 512 bits
    // ============================================================

    function [511:0] pad44(input [351:0] msg);
        begin
            pad44 = {msg, 8'h80, 88'd0, 64'd352};
        end
    endfunction

    // ============================================================
    // Stockage simulé et moteur de hash
    // ============================================================

    reg [351:0] st_data [0:7];
    reg [255:0] st_hash [0:7];
    reg [31:0] st_idx [0:7];

    integer n_stored = 0;
    integer hash_calls = 0;
    integer hcnt = 0;
    integer scnt = 0;

    always @(posedge clk) begin
        hash_done <= 1'b0;
        store_done <= 1'b0;

        if (hash_start) begin
            hash_calls = hash_calls + 1;
            sha256_block(pad44(blk_data));
            hcnt = 40;
        end
        else if (hcnt > 0) begin
            hcnt = hcnt - 1;
            if (hcnt == 0) begin
                hash_value <= sha_out;
                hash_done <= 1'b1;
            end
        end

        if (store_start) begin
            if (n_stored < 8) begin
                st_data[n_stored] = blk_data;
                st_hash[n_stored] = blk_hash;
                st_idx[n_stored] = blk_index;
                n_stored = n_stored + 1;
                scnt = 5;
            end
        end
        else if (scnt > 0) begin
            scnt = scnt - 1;
            if (scnt == 0)
                store_done <= 1'b1;
        end
    end

    // ============================================================
    // Outils de test
    // ============================================================

    integer errors = 0;
    integer i, t;

    task check(input cond, input [1023:0] msg);
        begin
            if (!cond) begin
                $display("ERREUR : %0s", msg);
                errors = errors + 1;
            end
            else begin
                $display("OK      : %0s", msg);
            end
        end
    endtask

    task send_tx(
        input [7:0] ty,
        input [31:0] k,
        input [15:0] v
    );
        begin
            t = 0;
            @(negedge clk);

            while (!ready && t < 3000) begin
                @(negedge clk);
                t = t + 1;
            end

            if (!ready) begin
                $display("ERREUR : ready reste a 0 avant transaction");
                errors = errors + 1;
            end
            else begin
                tx_type = ty;
                tx_key = k;
                tx_value = v;
                tx_valid = 1'b1;

                @(negedge clk);
                tx_valid = 1'b0;
            end
        end
    endtask

    task wait_stored(input integer n);
        begin
            t = 0;
            while ((n_stored < n || busy) && t < 3000) begin
                @(negedge clk);
                t = t + 1;
            end

            if (n_stored < n || busy) begin
                $display("ERREUR : timeout pendant attente stockage");
                errors = errors + 1;
            end
        end
    endtask

    // Références calculées sur des messages de 44 octets.
    localparam [255:0] EXP_H0 =
        256'h85759b3811ff7dc47b03792ac85317be51431a3f9e01dcafce317ed736a391b0;

    localparam [255:0] EXP_H1 =
        256'h5e29442e6444de3e89fd30bcecaa0b4068d339bdb9fd4294bc5f6a1ac20314d3;

    localparam [255:0] EXP_H2 =
        256'h37ee332a97a2e14f70e638148a9bcf4f59cface720e61d82659d97448107d911;

    localparam [351:0] EXP_B1 =
        352'h0000000185759b3811ff7dc47b03792ac85317be51431a3f9e01dcafce317ed736a391b000011111111100aa;

    localparam [351:0] EXP_B2 =
        352'h000000025e29442e6444de3e89fd30bcecaa0b4068d339bdb9fd4294bc5f6a1ac20314d30003111111110055;

    // ============================================================
    // Scénario principal
    // ============================================================

    initial begin
        $dumpfile("block_builder.vcd");
        $dumpvars(0, tb_block_builder);

        repeat (4) @(negedge clk);
        rst = 0;

        // Test standard SHA-256 : "abc"
        sha256_block({24'h616263, 8'h80, 416'd0, 64'd24});

        check(
            sha_out == 256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad,
            "SHA-256('abc') conforme au vecteur standard"
        );

        // Genesis automatique
        wait_stored(1);

        check(n_stored == 1,
              "Genesis stocke automatiquement");

        check(st_idx[0] == 0 && st_data[0] == 352'd0,
              "Genesis : index 0 et message nul");

        check(st_hash[0] == EXP_H0,
              "Genesis : hash de reference");

        check(next_index == 1 && last_hash == EXP_H0,
              "Index suivant et hash precedent corrects");

        check(ready == 1'b1,
              "Constructeur pret apres Genesis");

        // Bloc 1 : une transaction et scellement manuel
        send_tx(8'h01, 32'h11111111, 16'h00AA);

        @(negedge clk);
        seal = 1'b1;
        @(negedge clk);
        seal = 1'b0;

        wait_stored(2);

        check(n_stored == 2,
              "Bloc 1 stocke");

        check(st_data[1] == EXP_B1,
              "Bloc 1 : contenu de 352 bits correct");

        check(st_hash[1] == EXP_H1,
              "Bloc 1 : hash correct");

        check(st_idx[1] == 1,
              "Bloc 1 : index correct");

        check(st_data[1][319:64] == st_hash[0],
              "Bloc 1 : hash precedent egal au hash Genesis");

        // Bloc 2 : une transaction et scellement manuel
        send_tx(8'h03, 32'h11111111, 16'h0055);

        @(negedge clk);
        seal = 1'b1;
        @(negedge clk);
        seal = 1'b0;

        wait_stored(3);

        check(n_stored == 3,
              "Bloc 2 stocke");

        check(st_data[2] == EXP_B2,
              "Bloc 2 : contenu de 352 bits correct");

        check(st_hash[2] == EXP_H2,
              "Bloc 2 : hash correct");

        check(st_idx[2] == 2,
              "Bloc 2 : index correct");

        check(st_data[2][319:64] == st_hash[1],
              "Bloc 2 : hash precedent egal au hash du bloc 1");

        // Vérification du chaînage de tous les blocs
        for (i = 1; i < n_stored; i = i + 1) begin
            check(
                st_data[i][319:64] == st_hash[i-1],
                "Chainage entre blocs successifs"
            );
        end

        // Modification d'un bit du bloc 1 et recalcul de son hash
        sha256_block(pad44(st_data[1] ^ 352'h1));

        check(sha_out != st_hash[1],
              "Une alteration modifie le hash recalcule");

        check(sha_out != st_data[2][319:64],
              "L'alteration casse la coherence de la chaine");

        if (errors == 0)
            $display("TOUS LES TESTS PASSENT");
        else
            $display("%0d ERREUR(S)", errors);

        $finish;
    end

    // Protection contre un blocage de la simulation
    initial begin
        #20000000;
        $display("ERREUR : delai global depasse");
        $finish;
    end

endmodule
