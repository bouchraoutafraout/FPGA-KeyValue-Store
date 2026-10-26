// cmd_decoder.v : decodeur de commandes (Personne 4), version adaptee au plan CAN-FD du 19 octobre.
//
// Chaine : CAN-FD RX (P2) -> cmd_decoder -> Cuckoo/BRAM (P3) -> reponse -> CAN-FD TX (P1)
//
// Format d'un paquet (a confirmer avec l'equipe) :
//   octet 0      : LEN = nombre d'octets utiles qui suivent (5 pour SEARCH, 7 pour CREATE et TRANSFER)
//   octet 1      : code de commande (0x01 CREATE, 0x02 SEARCH, 0x03 TRANSFER)
//   octets 2-5   : cle 32 bits, octet de poids fort en premier
//   octets 6-7   : valeur 16 bits, octet de poids fort en premier (CREATE et TRANSFER)
//   octets suivants : bourrage eventuel (trame CAN-FD completee), ignores
// La fin du paquet est donnee par rx_frame_done (de P2). Le decodeur n'agit qu'a la fin de la trame,
// une fois que P2 n'a signale aucune erreur (rx_error).
//
// Hypotheses d'interface (a confirmer avec P2 et P3) :
//   - rx_frame_done : impulsion d'un cycle apres le dernier octet (ou dans le meme cycle).
//   - rx_error      : au plus tard 1 cycle apres rx_frame_done pour une trame invalide.
//   - ck_done       : impulsion d'un cycle, apres le cycle ou ck_start vaut 1.
//   - pour TRANSFER, P3 renseigne ck_found (0 = cle absente).
//
// Erreurs de paquet (err_valid, impulsion d'un cycle, avec err_code) :
//   1 = longueur annoncee incorrecte, 2 = paquet trop court, 3 = commande inconnue.
// Une seule operation Cuckoo a la fois ; une trame recue pendant ce temps est ignoree (dbg_overrun).

module cmd_decoder #(
    parameter [7:0] CMD_CREATE   = 8'h01,
    parameter [7:0] CMD_SEARCH   = 8'h02,
    parameter [7:0] CMD_TRANSFER = 8'h03,
    parameter       TIMEOUT      = 4096         // cycles max d'attente de ck_done
)(
    input  wire        clk,
    input  wire        rst,                     // reset synchrone, actif a 1

    // ---- P2 : reception CAN-FD ----
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    input  wire        rx_frame_done,
    input  wire        rx_error,

    // ---- P3 : Cuckoo / BRAM ----
    output reg  [7:0]  ck_cmd,
    output reg  [31:0] ck_key,
    output reg  [15:0] ck_value,
    output reg         ck_start,
    input  wire        ck_busy,
    input  wire        ck_done,
    input  wire        ck_found,
    input  wire [15:0] ck_value_out,
    input  wire        ck_error,

    // ---- P1 : reponse a transmettre ----
    output reg         resp_valid,
    input  wire        resp_ready,
    output reg  [7:0]  resp_cmd,
    output reg  [7:0]  resp_status,
    output reg  [15:0] resp_value,

    // ---- erreurs de paquet et debug ----
    output reg         err_valid,
    output reg  [1:0]  err_code,
    output reg         dbg_overrun,
    output reg         dbg_rejected,
    output wire [2:0]  dbg_state
);

    localparam [1:0] E_LEN = 2'd1, E_SHORT = 2'd2, E_CMD = 2'd3;

    localparam [7:0] ST_OK       = 8'h00,
                     ST_NOTFOUND = 8'h01,
                     ST_CKERR    = 8'h02,
                     ST_UNKNOWN  = 8'h03,
                     ST_BADLEN   = 8'h04,
                     ST_TIMEOUT  = 8'h05;

    localparam [2:0] S_LEN   = 3'd0,   // attend l'octet de longueur (debut de trame)
                     S_BODY  = 3'd1,   // recoit les octets utiles puis le bourrage, jusqu'a la fin de trame
                     S_CHECK = 3'd2,   // analyse la trame complete
                     S_EXEC  = 3'd3,   // lance l'operation Cuckoo
                     S_WAIT  = 3'd4,   // attend le resultat
                     S_RESP  = 3'd5;   // presente la reponse a P1

    reg [2:0]  state;
    reg [3:0]  idx;              // octets recus apres l'octet de longueur (sature a 15)
    reg [7:0]  len_r;
    reg [7:0]  cmd_r;
    reg [31:0] key_r;
    reg [15:0] val_r;
    reg        frame_done_q;     // rx_frame_done retarde d'un cycle
    reg [15:0] tmo;

    wire       known   = (cmd_r == CMD_CREATE) || (cmd_r == CMD_SEARCH) || (cmd_r == CMD_TRANSFER);
    wire [7:0] exp_len = (cmd_r == CMD_SEARCH) ? 8'd5 : 8'd7;

    assign dbg_state = state;

    always @(posedge clk) begin
        if (rst) begin
            state        <= S_LEN;
            idx          <= 4'd0;
            len_r        <= 8'd0;
            cmd_r        <= 8'd0;
            key_r        <= 32'd0;
            val_r        <= 16'd0;
            frame_done_q <= 1'b0;
            tmo          <= 16'd0;
            ck_cmd       <= 8'd0;
            ck_key       <= 32'd0;
            ck_value     <= 16'd0;
            ck_start     <= 1'b0;
            resp_valid   <= 1'b0;
            resp_cmd     <= 8'd0;
            resp_status  <= 8'd0;
            resp_value   <= 16'd0;
            err_valid    <= 1'b0;
            err_code     <= 2'd0;
            dbg_overrun  <= 1'b0;
            dbg_rejected <= 1'b0;
        end else begin
            frame_done_q <= rx_frame_done;
            ck_start     <= 1'b0;
            err_valid    <= 1'b0;
            dbg_overrun  <= 1'b0;
            dbg_rejected <= 1'b0;

            // octet recu alors que le decodeur traite deja une commande : ignore
            if (rx_valid && state > S_BODY)
                dbg_overrun <= 1'b1;

            case (state)

                // ---------- debut de trame : octet de longueur ----------
                S_LEN: begin
                    if (rx_error) begin
                        dbg_rejected <= 1'b1;
                    end else if (rx_valid) begin
                        len_r <= rx_data;
                        cmd_r <= 8'd0;
                        key_r <= 32'd0;
                        val_r <= 16'd0;
                        idx   <= 4'd0;
                        state <= S_BODY;
                    end
                end

                // ---------- octets utiles, puis bourrage ----------
                S_BODY: begin
                    if (rx_error) begin                 // trame invalide : on jette tout
                        dbg_rejected <= 1'b1;
                        idx   <= 4'd0;
                        state <= S_LEN;
                    end else if (frame_done_q) begin    // fin de trame
                        state <= S_CHECK;
                        if (rx_valid) dbg_overrun <= 1'b1;
                    end else if (rx_valid) begin
                        if (idx < len_r) begin          // au-dela de LEN : bourrage ignore
                            case (idx)
                                4'd0: cmd_r <= rx_data;
                                4'd1, 4'd2, 4'd3, 4'd4: key_r <= {key_r[23:0], rx_data};
                                4'd5, 4'd6:             val_r <= {val_r[7:0],  rx_data};
                                default: ;
                            endcase
                        end
                        if (idx != 4'd15) idx <= idx + 4'd1;
                    end
                end

                // ---------- analyse de la trame complete ----------
                S_CHECK: begin
                    idx        <= 4'd0;
                    resp_cmd   <= cmd_r;
                    resp_value <= 16'd0;
                    if (idx < len_r) begin                       // moins d'octets que annonce
                        err_valid   <= 1'b1; err_code <= E_SHORT;
                        resp_status <= ST_BADLEN; resp_valid <= 1'b1; state <= S_RESP;
                    end else if (!known) begin                   // commande inconnue
                        err_valid   <= 1'b1; err_code <= E_CMD;
                        resp_status <= ST_UNKNOWN; resp_valid <= 1'b1; state <= S_RESP;
                    end else if (len_r != exp_len) begin         // LEN incoherent avec la commande
                        err_valid   <= 1'b1; err_code <= E_LEN;
                        resp_status <= ST_BADLEN; resp_valid <= 1'b1; state <= S_RESP;
                    end else begin
                        ck_cmd   <= cmd_r;
                        ck_key   <= key_r;
                        ck_value <= val_r;
                        state    <= S_EXEC;
                    end
                end

                // ---------- lancement de l'operation Cuckoo ----------
                S_EXEC: begin
                    if (!ck_busy) begin
                        ck_start <= 1'b1;                        // impulsion d'un cycle
                        tmo      <= 16'd0;
                        state    <= S_WAIT;
                    end
                end

                // ---------- attente du resultat ----------
                S_WAIT: begin
                    tmo <= tmo + 16'd1;
                    if (ck_done) begin
                        if (ck_error)
                            resp_status <= ST_CKERR;
                        else if (cmd_r != CMD_CREATE && !ck_found)
                            resp_status <= ST_NOTFOUND;
                        else
                            resp_status <= ST_OK;
                        resp_value <= (cmd_r == CMD_SEARCH && ck_found) ? ck_value_out : 16'd0;
                        resp_valid <= 1'b1;
                        state      <= S_RESP;
                    end else if (tmo == TIMEOUT) begin
                        resp_status <= ST_TIMEOUT;
                        resp_valid  <= 1'b1;
                        state       <= S_RESP;
                    end
                end

                // ---------- reponse vers P1 ----------
                S_RESP: begin
                    if (resp_ready) begin                        // poignee de main valid/ready
                        resp_valid <= 1'b0;
                        state      <= S_LEN;
                    end
                end

                default: state <= S_LEN;
            endcase
        end
    end
endmodule
