`timescale 1ns/1ps
// Integration : trames -> cmd_decoder -> cuckoo_top -> hashtables (BRAM) avec les vraies fonctions de hachage.
// Remplace le modele Cuckoo simplifie du testbench du decodeur.
module tb_integration;

    localparam [7:0] CREATE = 8'h01, SEARCH = 8'h02, TRANSFER = 8'h03;
    localparam [7:0] ST_OK = 8'h00, ST_NOTFOUND = 8'h01, ST_CKERR = 8'h02;

    reg clk = 0, rst = 1;
    reg [7:0] rx_data = 0;
    reg rx_valid = 0, rx_frame_done = 0, rx_error = 0;

    wire [7:0]  ck_cmd;
    wire [31:0] ck_key;
    wire [15:0] ck_value, ck_value_out;
    wire        ck_start, ck_busy, ck_done, ck_found, ck_error;

    wire        resp_valid;
    wire [7:0]  resp_cmd, resp_status;
    wire [15:0] resp_value;
    wire        dbg_overrun, dbg_rejected;
    wire [2:0]  dbg_state;

    cmd_decoder #(.TIMEOUT(2000)) DEC (
        .clk(clk), .rst(rst),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_frame_done(rx_frame_done), .rx_error(rx_error),
        .ck_cmd(ck_cmd), .ck_key(ck_key), .ck_value(ck_value), .ck_start(ck_start),
        .ck_busy(ck_busy), .ck_done(ck_done), .ck_found(ck_found),
        .ck_value_out(ck_value_out), .ck_error(ck_error),
        .resp_valid(resp_valid), .resp_ready(1'b1),
        .resp_cmd(resp_cmd), .resp_status(resp_status), .resp_value(resp_value),
        .dbg_overrun(dbg_overrun), .dbg_rejected(dbg_rejected), .dbg_state(dbg_state)
    );

    cuckoo_top #(.KEY_W(32), .VAL_W(16), .IDX_W(8)) CK (
        .clk(clk), .rst(rst),
        .cmd(ck_cmd), .key(ck_key), .value_in(ck_value), .start(ck_start),
        .busy(ck_busy), .done(ck_done), .found(ck_found),
        .value_out(ck_value_out), .error(ck_error)
    );

    always #5 clk = ~clk;

    integer    resp_n = 0, errors = 0, i;
    reg [7:0]  r_cmd, r_status;
    reg [15:0] r_value;
    always @(posedge clk)
        if (resp_valid) begin
            resp_n = resp_n + 1;
            r_cmd = resp_cmd; r_status = resp_status; r_value = resp_value;
        end

    reg [7:0] fb [0:15];

    // envoie une commande sous forme de trame et attend la reponse (r_status, r_value)
    task run_cmd(input [7:0] c, input [31:0] k, input [15:0] v);
        integer n, len, t, n0;
        begin
            len = (c == SEARCH) ? 5 : 7;
            fb[0] = len;                                    // octet LEN
            fb[1] = c;
            fb[2] = k[31:24]; fb[3] = k[23:16]; fb[4] = k[15:8]; fb[5] = k[7:0];
            fb[6] = v[15:8];  fb[7] = v[7:0];
            n0 = resp_n;
            for (n = 0; n < len + 1; n = n + 1) begin
                @(negedge clk); rx_data = fb[n]; rx_valid = 1;
                @(negedge clk); rx_valid = 0;
            end
            @(negedge clk); rx_frame_done = 1;
            @(negedge clk); rx_frame_done = 0;
            t = 0;
            while (resp_n == n0 && t < 3000) begin @(negedge clk); t = t + 1; end
            if (resp_n == n0) begin $display("ERREUR : pas de reponse (cmd %h cle %h)", c, k); errors = errors + 1; end
            repeat (4) @(negedge clk);
        end
    endtask

    task check_resp(input [7:0] s, input [15:0] v, input [511:0] name);
        begin
            if (r_status !== s || r_value !== v) begin
                $display("ERREUR : %0s : recu statut=%h valeur=%h, attendu statut=%h valeur=%h", name, r_status, r_value, s, v);
                errors = errors + 1;
            end else $display("OK      : %0s", name);
        end
    endtask

    integer ok_n, found_n, fail_n;
    reg [31:0] rk [0:59];

    initial begin
        $dumpfile("integration.vcd");
        $dumpvars(0, tb_integration);
        repeat (4) @(negedge clk); rst = 0; repeat (3) @(negedge clk);

        // ---- scenario du guide ----
        run_cmd(CREATE, 32'h12345678, 16'h00AA);   check_resp(ST_OK, 16'h0000, "CREATE 12345678 = 00AA");
        run_cmd(SEARCH, 32'h12345678, 16'h0000);   check_resp(ST_OK, 16'h00AA, "SEARCH -> 00AA");
        run_cmd(TRANSFER, 32'h12345678, 16'h0055); check_resp(ST_OK, 16'h0000, "TRANSFER = 0055");
        run_cmd(SEARCH, 32'h12345678, 16'h0000);   check_resp(ST_OK, 16'h0055, "SEARCH apres TRANSFER -> 0055");
        run_cmd(SEARCH, 32'hDEADBEEF, 16'h0000);   check_resp(ST_NOTFOUND, 16'h0000, "SEARCH cle absente");
        run_cmd(TRANSFER, 32'hDEADBEEF, 16'h0001); check_resp(ST_NOTFOUND, 16'h0000, "TRANSFER cle absente");
        run_cmd(CREATE, 32'h12345678, 16'h0001);   check_resp(ST_CKERR, 16'h0000, "CREATE doublon -> erreur");
        run_cmd(SEARCH, 32'h12345678, 16'h0000);   check_resp(ST_OK, 16'h0055, "le doublon n'a pas ecrase la valeur");

        // ---- collision Cuckoo : 0x5 et 0x104 ont le meme h1, la premiere cle est deplacee ----
        run_cmd(CREATE, 32'h00000005, 16'h0111);   check_resp(ST_OK, 16'h0000, "CREATE 5");
        run_cmd(CREATE, 32'h00000104, 16'h0222);   check_resp(ST_OK, 16'h0000, "CREATE 104 (collision, eviction)");
        run_cmd(SEARCH, 32'h00000005, 16'h0000);   check_resp(ST_OK, 16'h0111, "SEARCH 5 apres eviction");
        run_cmd(SEARCH, 32'h00000104, 16'h0000);   check_resp(ST_OK, 16'h0222, "SEARCH 104");
        run_cmd(TRANSFER, 32'h00000005, 16'h0999); check_resp(ST_OK, 16'h0000, "TRANSFER sur la cle deplacee (table 2)");
        run_cmd(SEARCH, 32'h00000005, 16'h0000);   check_resp(ST_OK, 16'h0999, "SEARCH 5 -> 0999");
        run_cmd(SEARCH, 32'h00000104, 16'h0000);   check_resp(ST_OK, 16'h0222, "104 intacte");

        // ---- echec d'insertion : 3 cles avec les memes (h1,h2) ----
        run_cmd(CREATE, 32'h00000003, 16'h0301);   check_resp(ST_OK, 16'h0000, "CREATE 0003");
        run_cmd(CREATE, 32'h00000102, 16'h0302);   check_resp(ST_OK, 16'h0000, "CREATE 0102");
        run_cmd(CREATE, 32'h00000201, 16'h0303);   check_resp(ST_CKERR, 16'h0000, "CREATE 0201 -> echec d'insertion (3e cle, memes casiers)");

        // ---- 60 cles aleatoires, puis SEARCH de chacune ----
        ok_n = 0; fail_n = 0; found_n = 0;
        for (i = 0; i < 60; i = i + 1) begin
            rk[i] = $urandom;
            run_cmd(CREATE, rk[i], i + 16'h1000);
            if (r_status == ST_OK) ok_n = ok_n + 1; else fail_n = fail_n + 1;
        end
        for (i = 0; i < 60; i = i + 1) begin
            run_cmd(SEARCH, rk[i], 16'h0000);
            if (r_status == ST_OK) begin
                found_n = found_n + 1;
                if (r_value !== i + 16'h1000) begin $display("ERREUR : valeur fausse pour la cle %h", rk[i]); errors = errors + 1; end
            end
        end
        $display("60 cles aleatoires : %0d CREATE reussis, %0d echecs, %0d cles retrouvees par SEARCH", ok_n, fail_n, found_n);
        if (found_n != ok_n) begin $display("ERREUR : retrouvees != reussies"); errors = errors + 1; end

        if (errors == 0) $display("INTEGRATION COMPLETE : OK");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end
endmodule
