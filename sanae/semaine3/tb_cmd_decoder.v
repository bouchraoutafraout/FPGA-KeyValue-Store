`timescale 1ns/1ps
// Testbench du decodeur de commandes.
// Joue le role de P2 (RX CAN-FD), de P3 (Cuckoo, modele simplifie) et de P1 (TX).
module tb_cmd_decoder;

    localparam [7:0] CREATE = 8'h01, SEARCH = 8'h02, TRANSFER = 8'h03;
    localparam [7:0] ST_OK = 8'h00, ST_NOTFOUND = 8'h01, ST_CKERR = 8'h02,
                     ST_UNKNOWN = 8'h03, ST_BADLEN = 8'h04, ST_TIMEOUT = 8'h05;

    reg clk = 0, rst = 1;
    reg [7:0] rx_data = 0;
    reg rx_valid = 0, rx_frame_done = 0, rx_error = 0;

    wire [7:0]  ck_cmd;
    wire [31:0] ck_key;
    wire [15:0] ck_value;
    wire        ck_start;
    reg         mb = 0, md = 0, mf = 0, me = 0;     // sorties du modele Cuckoo
    reg  [15:0] mvo = 0;

    wire        resp_valid;
    reg         resp_ready = 1;
    wire [7:0]  resp_cmd, resp_status;
    wire [15:0] resp_value;
    wire        dbg_overrun, dbg_rejected;
    wire [2:0]  dbg_state;

    cmd_decoder #(.TIMEOUT(60)) dut (
        .clk(clk), .rst(rst),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .rx_frame_done(rx_frame_done), .rx_error(rx_error),
        .ck_cmd(ck_cmd), .ck_key(ck_key), .ck_value(ck_value), .ck_start(ck_start),
        .ck_busy(mb), .ck_done(md), .ck_found(mf), .ck_value_out(mvo), .ck_error(me),
        .resp_valid(resp_valid), .resp_ready(resp_ready),
        .resp_cmd(resp_cmd), .resp_status(resp_status), .resp_value(resp_value),
        .dbg_overrun(dbg_overrun), .dbg_rejected(dbg_rejected), .dbg_state(dbg_state)
    );

    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // Modele simplifie du Cuckoo (P3) : 8 cases, recherche lineaire
    // ------------------------------------------------------------------
    reg [31:0] mk   [0:7];
    reg [15:0] mv   [0:7];
    reg        mvld [0:7];
    reg [7:0]  lcmd;
    reg [31:0] lkey;
    reg [15:0] lval;
    integer    lat = 3, delay = 0, starts = 0, hit, freeidx, i;
    reg        hang = 0;

    always @(posedge clk) begin
        md <= 1'b0;
        if (ck_start) begin
            starts = starts + 1;
            lcmd <= ck_cmd; lkey <= ck_key; lval <= ck_value;
            mb <= 1'b1; delay = lat;
        end else if (mb && !hang) begin
            if (delay == 0) begin
                hit = -1; freeidx = -1;
                for (i = 0; i < 8; i = i + 1) begin
                    if (mvld[i] && mk[i] == lkey) hit = i;
                    if (!mvld[i] && freeidx < 0) freeidx = i;
                end
                mf <= 1'b0; me <= 1'b0; mvo <= 16'd0;
                case (lcmd)
                    8'h01: if (hit >= 0 || freeidx < 0) me <= 1'b1;
                           else begin mvld[freeidx] <= 1'b1; mk[freeidx] <= lkey; mv[freeidx] <= lval; end
                    8'h02: if (hit >= 0) begin mf <= 1'b1; mvo <= mv[hit]; end
                    8'h03: if (hit >= 0) begin mf <= 1'b1; mv[hit] <= lval; end
                    default: ;
                endcase
                md <= 1'b1; mb <= 1'b0;
            end else delay = delay - 1;
        end
    end

    // ------------------------------------------------------------------
    // Surveillance des reponses vers P1 et des drapeaux de debug
    // ------------------------------------------------------------------
    integer    resp_n = 0, overruns = 0, rejects = 0;
    reg [7:0]  last_cmd, last_status;
    reg [15:0] last_value;
    always @(posedge clk) begin
        if (resp_valid && resp_ready) begin
            resp_n = resp_n + 1;
            last_cmd = resp_cmd; last_status = resp_status; last_value = resp_value;
        end
        if (dbg_overrun)  overruns = overruns + 1;
        if (dbg_rejected) rejects  = rejects  + 1;
    end

    // ------------------------------------------------------------------
    // Outils de test
    // ------------------------------------------------------------------
    integer errors = 0;
    reg [7:0] fb [0:15];

    task check(input cond, input [511:0] msg);
        begin
            if (!cond) begin $display("ERREUR : %0s", msg); errors = errors + 1; end
        end
    endtask

    task set_cmd(input [7:0] c, input [31:0] k, input [15:0] v);
        begin
            fb[0] = (c == SEARCH) ? 8'd5 : 8'd7;          // LEN : octets utiles qui suivent
            fb[1] = c;
            fb[2] = k[31:24]; fb[3] = k[23:16]; fb[4] = k[15:8]; fb[5] = k[7:0];
            fb[6] = v[15:8];  fb[7] = v[7:0];
        end
    endtask

    // err : 0 = trame valide, 1 = rx_error en meme temps que frame_done,
    //       2 = rx_error un cycle apres frame_done
    // coinc : 1 = frame_done dans le meme cycle que le dernier octet
    // gap   : 1 = un cycle vide entre les octets
    task send_frame(input integer n, input integer err, input integer coinc, input integer gap);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(negedge clk);
                rx_data = fb[k]; rx_valid = 1;
                if (coinc != 0 && k == n - 1) begin
                    rx_frame_done = 1; rx_error = (err == 1);
                end
                if (gap != 0 && k < n - 1) begin @(negedge clk); rx_valid = 0; end
            end
            @(negedge clk);
            rx_valid = 0; rx_frame_done = 0; rx_error = 0;
            if (coinc == 0) begin
                rx_frame_done = 1; rx_error = (err == 1);
                @(negedge clk);
                rx_frame_done = 0; rx_error = 0;
            end
            if (err == 2) begin
                rx_error = 1; @(negedge clk); rx_error = 0;
            end
        end
    endtask

    // attend une reponse et la compare
    task expect_resp(input integer n0, input [7:0] c, input [7:0] s, input [15:0] v, input [511:0] name);
        integer t;
        begin
            t = 0;
            while (resp_n == n0 && t < 300) begin @(negedge clk); t = t + 1; end
            if (resp_n == n0) begin
                $display("ERREUR : %0s : aucune reponse", name); errors = errors + 1;
            end else begin
                if (last_cmd !== c || last_status !== s || last_value !== v) begin
                    $display("ERREUR : %0s : recu cmd=%h statut=%h valeur=%h, attendu cmd=%h statut=%h valeur=%h",
                             name, last_cmd, last_status, last_value, c, s, v);
                    errors = errors + 1;
                end else $display("OK      : %0s", name);
            end
            repeat (5) @(negedge clk);
        end
    endtask

    // verifie qu'aucune reponse ne vient
    task expect_none(input integer n0, input [511:0] name);
        begin
            repeat (80) @(negedge clk);
            if (resp_n != n0) begin $display("ERREUR : %0s : reponse inattendue", name); errors = errors + 1; end
            else $display("OK      : %0s", name);
        end
    endtask

    integer n0, s0, ov0, rj0;
    reg [7:0]  h_cmd, h_status;
    reg [15:0] h_value;

    initial begin
        $dumpfile("cmd_decoder.vcd");
        $dumpvars(0, tb_cmd_decoder);
        for (i = 0; i < 8; i = i + 1) mvld[i] = 0;
        repeat (4) @(negedge clk);
        rst = 0;
        repeat (3) @(negedge clk);

        // ---- Scenario du guide : CREATE, SEARCH, TRANSFER, SEARCH ----
        n0 = resp_n; set_cmd(CREATE, 32'h12345678, 16'h00AA);
        send_frame(8, 0, 0, 1);
        expect_resp(n0, CREATE, ST_OK, 16'h0000, "CREATE 12345678 = 00AA");

        n0 = resp_n; set_cmd(SEARCH, 32'h12345678, 16'h0000);
        send_frame(6, 0, 0, 1);
        expect_resp(n0, SEARCH, ST_OK, 16'h00AA, "SEARCH 12345678 -> 00AA");

        n0 = resp_n; set_cmd(TRANSFER, 32'h12345678, 16'h0055);
        send_frame(8, 0, 0, 1);
        expect_resp(n0, TRANSFER, ST_OK, 16'h0000, "TRANSFER 12345678 = 0055");

        n0 = resp_n; set_cmd(SEARCH, 32'h12345678, 16'h0000);
        send_frame(6, 0, 0, 1);
        expect_resp(n0, SEARCH, ST_OK, 16'h0055, "SEARCH apres TRANSFER -> 0055");

        // ---- cle absente ----
        n0 = resp_n; set_cmd(SEARCH, 32'hDEADBEEF, 16'h0000);
        send_frame(6, 0, 0, 1);
        expect_resp(n0, SEARCH, ST_NOTFOUND, 16'h0000, "SEARCH cle absente");

        n0 = resp_n; set_cmd(TRANSFER, 32'hDEADBEEF, 16'h0001);
        send_frame(8, 0, 0, 1);
        expect_resp(n0, TRANSFER, ST_NOTFOUND, 16'h0000, "TRANSFER cle absente");

        // ---- erreur renvoyee par le Cuckoo (CREATE sur une cle deja presente) ----
        n0 = resp_n; set_cmd(CREATE, 32'h12345678, 16'h0001);
        send_frame(8, 0, 0, 1);
        expect_resp(n0, CREATE, ST_CKERR, 16'h0000, "CREATE doublon -> erreur Cuckoo");

        // ---- commande inconnue : aucune operation Cuckoo ----
        n0 = resp_n; s0 = starts; set_cmd(8'h7F, 32'h11111111, 16'h0000);
        send_frame(8, 0, 0, 1);
        expect_resp(n0, 8'h7F, ST_UNKNOWN, 16'h0000, "commande inconnue");
        check(starts == s0, "commande inconnue : le Cuckoo ne doit pas etre lance");

        // ---- trame trop courte ----
        n0 = resp_n; s0 = starts; set_cmd(SEARCH, 32'h12345678, 16'h0000);
        send_frame(4, 0, 0, 1);
        expect_resp(n0, SEARCH, ST_BADLEN, 16'h0000, "SEARCH trop court");
        check(starts == s0, "trame trop courte : le Cuckoo ne doit pas etre lance");

        // ---- octet LEN incoherent avec la commande (CREATE annonce 5 au lieu de 7) ----
        n0 = resp_n; s0 = starts; set_cmd(CREATE, 32'h12345678, 16'h0001);
        fb[0] = 8'd5;
        send_frame(8, 0, 0, 1);
        expect_resp(n0, CREATE, ST_BADLEN, 16'h0000, "LEN incoherent");
        check(starts == s0, "LEN incoherent : le Cuckoo ne doit pas etre lance");

        // ---- trame qui s'arrete juste apres l'octet LEN ----
        n0 = resp_n; s0 = starts; fb[0] = 8'd7;
        send_frame(1, 0, 0, 1);
        expect_resp(n0, 8'h00, ST_BADLEN, 16'h0000, "trame reduite a l'octet LEN");
        check(starts == s0, "trame reduite a LEN : le Cuckoo ne doit pas etre lance");

        // ---- trame invalide (rx_error) : rien ne doit s'executer ----
        n0 = resp_n; s0 = starts; rj0 = rejects; set_cmd(CREATE, 32'hAAAA0001, 16'h0BAD);
        send_frame(8, 1, 0, 1);
        expect_none(n0, "trame rx_error : aucune reponse");
        check(starts == s0, "rx_error : le Cuckoo ne doit pas etre lance");
        check(rejects > rj0, "rx_error : dbg_rejected attendu");
        n0 = resp_n; set_cmd(SEARCH, 32'hAAAA0001, 16'h0000);
        send_frame(6, 0, 0, 1);
        expect_resp(n0, SEARCH, ST_NOTFOUND, 16'h0000, "la trame rejetee n'a rien ecrit");

        // ---- rx_error un cycle apres frame_done ----
        n0 = resp_n; s0 = starts; set_cmd(CREATE, 32'hAAAA0002, 16'h0BAD);
        send_frame(8, 2, 0, 1);
        expect_none(n0, "rx_error tardif : aucune reponse");
        check(starts == s0, "rx_error tardif : le Cuckoo ne doit pas etre lance");

        // ---- frame_done dans le meme cycle que le dernier octet, octets sans pause ----
        n0 = resp_n; set_cmd(CREATE, 32'h00000042, 16'h4242);
        send_frame(8, 0, 1, 0);
        expect_resp(n0, CREATE, ST_OK, 16'h0000, "CREATE frame_done simultane, sans pause");
        n0 = resp_n; set_cmd(SEARCH, 32'h00000042, 16'h0000);
        send_frame(6, 0, 1, 0);
        expect_resp(n0, SEARCH, ST_OK, 16'h4242, "SEARCH frame_done simultane");

        // ---- octets de bourrage apres la commande ----
        n0 = resp_n; set_cmd(SEARCH, 32'h00000042, 16'h0000);
        fb[6] = 8'h00; fb[7] = 8'h00; fb[8] = 8'hFF;
        send_frame(9, 0, 0, 0);
        expect_resp(n0, SEARCH, ST_OK, 16'h4242, "SEARCH avec bourrage");

        // ---- plusieurs commandes consecutives, plusieurs cles ----
        n0 = resp_n; set_cmd(CREATE, 32'h000000A1, 16'h1111); send_frame(8, 0, 0, 1);
        expect_resp(n0, CREATE, ST_OK, 16'h0000, "CREATE A1");
        n0 = resp_n; set_cmd(CREATE, 32'h000000A2, 16'h2222); send_frame(8, 0, 0, 1);
        expect_resp(n0, CREATE, ST_OK, 16'h0000, "CREATE A2");
        n0 = resp_n; set_cmd(CREATE, 32'h000000A3, 16'h3333); send_frame(8, 0, 0, 1);
        expect_resp(n0, CREATE, ST_OK, 16'h0000, "CREATE A3");
        n0 = resp_n; set_cmd(SEARCH, 32'h000000A2, 16'h0000); send_frame(6, 0, 0, 1);
        expect_resp(n0, SEARCH, ST_OK, 16'h2222, "SEARCH A2 -> 2222");
        n0 = resp_n; set_cmd(SEARCH, 32'h000000A3, 16'h0000); send_frame(6, 0, 0, 1);
        expect_resp(n0, SEARCH, ST_OK, 16'h3333, "SEARCH A3 -> 3333");
        n0 = resp_n; set_cmd(SEARCH, 32'h000000A1, 16'h0000); send_frame(6, 0, 0, 1);
        expect_resp(n0, SEARCH, ST_OK, 16'h1111, "SEARCH A1 -> 1111");

        // ---- trame recue pendant qu'une operation est en cours (busy) ----
        lat = 25;
        n0 = resp_n; ov0 = overruns; s0 = starts;
        set_cmd(CREATE, 32'h000000B1, 16'h0B01); send_frame(8, 0, 0, 0);
        set_cmd(CREATE, 32'h000000B2, 16'h0B02); send_frame(8, 0, 0, 0);   // arrive pendant l'attente
        expect_resp(n0, CREATE, ST_OK, 16'h0000, "operation en cours : la premiere commande aboutit");
        check(overruns > ov0, "busy : dbg_overrun attendu");
        check(resp_n == n0 + 1, "busy : la trame recue pendant l'operation doit etre ignoree");
        check(starts == s0 + 1, "busy : une seule operation Cuckoo attendue");
        lat = 3;
        n0 = resp_n; set_cmd(SEARCH, 32'h000000B2, 16'h0000); send_frame(6, 0, 0, 1);
        expect_resp(n0, SEARCH, ST_NOTFOUND, 16'h0000, "la trame ignoree n'a rien ecrit");

        // ---- reponse retenue par le TX (resp_ready = 0) ----
        resp_ready = 0;
        n0 = resp_n; set_cmd(SEARCH, 32'h000000A1, 16'h0000); send_frame(6, 0, 0, 1);
        repeat (40) @(negedge clk);
        check(resp_valid === 1'b1, "backpressure : resp_valid doit rester a 1");
        h_cmd = resp_cmd; h_status = resp_status; h_value = resp_value;
        repeat (10) @(negedge clk);
        check(resp_cmd === h_cmd && resp_status === h_status && resp_value === h_value,
              "backpressure : la reponse doit rester stable");
        resp_ready = 1;
        expect_resp(n0, SEARCH, ST_OK, 16'h1111, "reponse livree apres attente du TX");

        // ---- le Cuckoo ne repond jamais : temporisation ----
        hang = 1;
        n0 = resp_n; set_cmd(SEARCH, 32'h000000A1, 16'h0000); send_frame(6, 0, 0, 1);
        expect_resp(n0, SEARCH, ST_TIMEOUT, 16'h0000, "Cuckoo bloque : temporisation");
        hang = 0;
        repeat (20) @(negedge clk);
        n0 = resp_n; set_cmd(SEARCH, 32'h000000A1, 16'h0000); send_frame(6, 0, 0, 1);
        expect_resp(n0, SEARCH, ST_OK, 16'h1111, "retour a un etat connu apres temporisation");

        if (errors == 0) $display("TOUS LES TESTS PASSENT");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end
endmodule
