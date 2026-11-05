`timescale 1ns/1ps
// Testbench de transaction_validator.
// Joue le role du decodeur (cote in_*), du KVS / Cuckoo (cote kv_*, modele simplifie de 8 cases)
// et du constructeur de bloc (blk_ready commande par le test).
module tb_transaction_validator;

    localparam [7:0] CREATE = 8'h01, SEARCH = 8'h02, TRANSFER = 8'h03;

    reg clk = 0, rst = 1;

    // cote decodeur
    reg  [7:0]  in_cmd = 0;
    reg  [31:0] in_key = 0;
    reg  [15:0] in_value = 0;
    reg         in_start = 0;
    wire        in_busy, in_done, in_found, in_error;
    wire [15:0] in_value_out;
    wire [3:0]  in_err_code;

    // cote KVS
    wire [7:0]  kv_cmd;
    wire [31:0] kv_key;
    wire [15:0] kv_value;
    wire        kv_start;
    reg         mb = 0, md = 0, mf = 0, me = 0;
    reg  [15:0] mvo = 0;

    // vers le constructeur de bloc
    reg         blk_ready = 1;
    wire        blk_hold, tx_acc_valid;
    wire [7:0]  tx_acc_type;
    wire [31:0] tx_acc_key;
    wire [15:0] tx_acc_value;
    wire [3:0]  dbg_state;

    transaction_validator #(.VALUE_MIN(16'd1), .VALUE_MAX(16'h7FFF), .TIMEOUT(60)) dut (
        .clk(clk), .rst(rst),
        .in_cmd(in_cmd), .in_key(in_key), .in_value(in_value), .in_start(in_start),
        .in_busy(in_busy), .in_done(in_done), .in_found(in_found), .in_value_out(in_value_out),
        .in_error(in_error), .in_err_code(in_err_code),
        .kv_cmd(kv_cmd), .kv_key(kv_key), .kv_value(kv_value), .kv_start(kv_start),
        .kv_busy(mb), .kv_done(md), .kv_found(mf), .kv_value_out(mvo), .kv_error(me),
        .blk_ready(blk_ready), .blk_hold(blk_hold), .tx_acc_valid(tx_acc_valid),
        .tx_acc_type(tx_acc_type), .tx_acc_key(tx_acc_key), .tx_acc_value(tx_acc_value),
        .dbg_state(dbg_state)
    );

    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // Modele simplifie du KVS (meme comportement que cuckoo_top) : 8 cases
    // ------------------------------------------------------------------
    reg [31:0] mk   [0:7];
    reg [15:0] mv   [0:7];
    reg        mvld [0:7];
    reg [7:0]  lcmd;
    reg [31:0] lkey;
    reg [15:0] lval;
    integer    delay = 0, hit, freeidx, i;
    integer    n_start = 0, n_search = 0, n_create = 0, n_transfer = 0;
    reg        hang = 0;

    always @(posedge clk) begin
        md <= 1'b0;
        if (kv_start) begin
            n_start = n_start + 1;
            case (kv_cmd)
                8'h01: n_create   = n_create + 1;
                8'h02: n_search   = n_search + 1;
                8'h03: n_transfer = n_transfer + 1;
                default: ;
            endcase
            lcmd <= kv_cmd; lkey <= kv_key; lval <= kv_value;
            mb <= 1'b1; delay = 3;
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
    // Surveillance des transactions acceptees
    // ------------------------------------------------------------------
    integer    acc_n = 0, hold_cycles = 0;
    reg [7:0]  acc_type;
    reg [31:0] acc_key;
    reg [15:0] acc_value;
    always @(posedge clk) begin
        if (tx_acc_valid) begin
            acc_n = acc_n + 1;
            acc_type = tx_acc_type; acc_key = tx_acc_key; acc_value = tx_acc_value;
        end
        if (blk_hold) hold_cycles = hold_cycles + 1;
    end

    // garde-fou global
    initial begin
        #20000000;
        $display("ERREUR : delai global depasse, la simulation est arretee");
        $finish;
    end

    // ------------------------------------------------------------------
    // Outils de test
    // ------------------------------------------------------------------
    integer errors = 0;
    reg        r_found, r_error;
    reg [15:0] r_val;
    reg [3:0]  r_code;

    task check(input cond, input [1023:0] msg);
        begin
            if (!cond) begin $display("ERREUR : %0s", msg); errors = errors + 1; end
            else       $display("OK      : %0s", msg);
        end
    endtask

    // lance une commande comme le ferait le decodeur et attend in_done
    task run(input [7:0] c, input [31:0] k, input [15:0] v);
        integer t;
        begin
            @(negedge clk); in_cmd = c; in_key = k; in_value = v; in_start = 1;
            @(negedge clk); in_start = 0;
            t = 0;
            while (!in_done && t < 2000) begin @(negedge clk); t = t + 1; end
            if (t >= 2000) begin $display("ERREUR : pas de in_done"); errors = errors + 1; end
            r_found = in_found; r_val = in_value_out; r_error = in_error; r_code = in_err_code;
            repeat (3) @(negedge clk);
        end
    endtask

    integer s0, c0, t0, a0;

    initial begin
        $dumpfile("transaction_validator.vcd");
        $dumpvars(0, tb_transaction_validator);
        for (i = 0; i < 8; i = i + 1) mvld[i] = 0;
        repeat (4) @(negedge clk); rst = 0; repeat (3) @(negedge clk);

        // ---- transaction valide : CREATE ----
        a0 = acc_n; s0 = n_search; c0 = n_create;
        run(CREATE, 32'h11111111, 16'h00AA);
        check(!r_error && r_found && r_code == 4'd0, "CREATE valide : acceptee, aucune erreur");
        check(acc_n == a0 + 1 && acc_type == CREATE && acc_key == 32'h11111111 && acc_value == 16'h00AA,
              "CREATE valide : transmise au constructeur de bloc avec ses champs");
        check(n_search == s0 + 1 && n_create == c0 + 1, "CREATE valide : un SEARCH de controle puis le CREATE dans le KVS");

        // ---- R4 : CREATE sur une cle existante ----
        a0 = acc_n; c0 = n_create;
        run(CREATE, 32'h11111111, 16'h0001);
        check(r_error && r_code == 4'd4, "R4 : CREATE d'une cle existante refuse, code 4");
        check(acc_n == a0 && n_create == c0, "R4 : rien envoye au bloc, aucun CREATE dans le KVS");
        run(SEARCH, 32'h11111111, 16'h0000);
        check(r_found && r_val == 16'h00AA, "R4 : la valeur existante est intacte");

        // ---- TRANSFER valide ----
        a0 = acc_n; t0 = n_transfer;
        run(TRANSFER, 32'h11111111, 16'h0055);
        check(!r_error && r_found, "TRANSFER valide : acceptee");
        check(acc_n == a0 + 1 && acc_type == TRANSFER && acc_value == 16'h0055, "TRANSFER valide : transmise au bloc");
        check(n_transfer == t0 + 1, "TRANSFER valide : execute dans le KVS");
        run(SEARCH, 32'h11111111, 16'h0000);
        check(r_found && r_val == 16'h0055, "TRANSFER valide : la nouvelle valeur est bien stockee");

        // ---- R5 : TRANSFER sur une cle absente ----
        a0 = acc_n; t0 = n_transfer;
        run(TRANSFER, 32'h99999999, 16'h0001);
        check(!r_found && !r_error && r_code == 4'd5, "R5 : TRANSFER d'une cle absente refuse, code 5, found = 0");
        check(acc_n == a0 && n_transfer == t0, "R5 : rien envoye au bloc, aucun TRANSFER dans le KVS");

        // ---- R1 : type interdit ----
        a0 = acc_n; s0 = n_start;
        run(8'h09, 32'h22222222, 16'h0001);
        check(r_error && r_code == 4'd1, "R1 : type inconnu refuse, code 1");
        check(n_start == s0 && acc_n == a0, "R1 : le KVS n'est pas sollicite");

        // ---- R2 : cle nulle ----
        s0 = n_start;
        run(CREATE, 32'h00000000, 16'h0001);
        check(r_error && r_code == 4'd2, "R2 : cle nulle refusee, code 2");
        check(n_start == s0, "R2 : le KVS n'est pas sollicite");

        // ---- R3 : valeur hors plage ----
        s0 = n_start;
        run(CREATE, 32'h33333333, 16'h0000);
        check(r_error && r_code == 4'd3, "R3 : valeur 0 refusee (minimum 1), code 3");
        run(CREATE, 32'h33333333, 16'h8000);
        check(r_error && r_code == 4'd3, "R3 : valeur 0x8000 refusee (maximum 0x7FFF dans ce test), code 3");
        check(n_start == s0, "R3 : le KVS n'est pas sollicite");

        // ---- SEARCH : simple passage, jamais dans un bloc ----
        a0 = acc_n;
        run(SEARCH, 32'h11111111, 16'h0000);
        check(r_found && r_val == 16'h0055 && !r_error, "SEARCH present : resultat renvoye");
        run(SEARCH, 32'h77777777, 16'h0000);
        check(!r_found && !r_error, "SEARCH absent : found = 0");
        check(acc_n == a0, "SEARCH : aucune transaction envoyee au bloc");

        // ---- R7 : le bloc n'est pas pret ----
        blk_ready = 0;
        s0 = n_start; a0 = acc_n; i = hold_cycles;
        fork
            run(CREATE, 32'h44444444, 16'h0007);
            begin
                repeat (25) @(negedge clk);
                check(n_start == s0, "R7 : bloc non pret, le KVS n'est pas touche pendant l'attente");
                check(hold_cycles > i, "R7 : le validateur reserve le bloc (blk_hold) pendant l'attente");
                blk_ready = 1;
            end
        join
        check(!r_error && acc_n == a0 + 1, "R7 : des que le bloc est pret, la transaction est acceptee");

        // ---- R7 : le bloc ne devient jamais pret ----
        blk_ready = 0; s0 = n_start; a0 = acc_n;
        run(CREATE, 32'h55555555, 16'h0008);
        check(r_error && r_code == 4'd7, "R7 : bloc jamais pret, temporisation, code 7");
        check(n_start == s0 && acc_n == a0, "R7 : rien execute ni envoye au bloc");
        blk_ready = 1;

        // ---- R6 : KVS plein ----
        // 0x11111111 et 0x44444444 sont deja dedans : on remplit les 6 autres cases
        run(CREATE, 32'hA0000001, 16'h0001);
        run(CREATE, 32'hA0000002, 16'h0001);
        run(CREATE, 32'hA0000003, 16'h0001);
        run(CREATE, 32'hA0000004, 16'h0001);
        run(CREATE, 32'hA0000005, 16'h0001);
        run(CREATE, 32'hA0000006, 16'h0001);
        a0 = acc_n;
        run(CREATE, 32'hA0000007, 16'h0001);
        check(r_error && r_code == 4'd6, "R6 : KVS plein, l'execution echoue, code 6");
        check(acc_n == a0, "R6 : la transaction echouee n'est pas envoyee au bloc");

        // ---- le KVS ne repond plus ----
        hang = 1;
        run(SEARCH, 32'h11111111, 16'h0000);
        check(r_error && r_code == 4'd7, "KVS bloque : temporisation, code 7");
        hang = 0;
        repeat (20) @(negedge clk);
        run(SEARCH, 32'h11111111, 16'h0000);
        check(r_found && r_val == 16'h0055 && !r_error, "retour a un etat connu apres la temporisation");

        if (errors == 0) $display("TOUS LES TESTS PASSENT");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end
endmodule
