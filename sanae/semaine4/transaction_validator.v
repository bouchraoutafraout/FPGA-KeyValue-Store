// transaction_validator.v : validation des transactions (Sanae)
//
// Place entre le decodeur de commandes et le Cuckoo / KVS. Les deux cotes utilisent la meme interface
// (cmd, key, value, start / busy, done, found, value_out, error), donc le decodeur ne change pas :
// il se branche sur les ports in_* au lieu du KVS, et le KVS se branche sur les ports kv_*.
//
// TRANSACTION (7 octets) : type (1) | cle (4) | valeur (2). Types : 0x01 CREATE, 0x03 TRANSFER (= modifier la valeur
// d'une cle, pas un transfert atomique entre deux comptes). 0x02 SEARCH n'est pas une transaction : elle traverse
// le validateur sans controle et n'entre pas dans les blocs.
//
// REGLES (dans l'ordre) :
//   R1 type CREATE ou TRANSFER                                      -> sinon code 1
//   R2 cle non nulle                                                -> sinon code 2
//   R3 valeur entre VALUE_MIN et VALUE_MAX                          -> sinon code 3
//   R4 CREATE : la cle ne doit pas exister (SEARCH dans le KVS)     -> sinon code 4
//   R5 TRANSFER : la cle doit exister                               -> sinon code 5 (in_found = 0, pas d'erreur)
//   R6 l'execution dans le KVS doit reussir                         -> sinon code 6
//   R7 le bloc doit pouvoir accepter la transaction (blk_ready)     -> sinon attente, puis code 7 au bout de TIMEOUT
//   Seule une transaction qui passe toutes les regles est executee dans le KVS ET envoyee au constructeur de bloc,
//   donc l'etat du KVS reste coherent avec le contenu des blocs.
//
// Codes d'erreur (in_err_code) : 0 aucun, 1 type interdit, 2 cle nulle, 3 valeur hors plage, 4 cle deja existante,
//   5 cle absente, 6 erreur du KVS, 7 temporisation (KVS ou bloc ne repond pas).
// in_error = 1 pour tous les codes sauf 5.
//
// Hypotheses (a confirmer avec P3 et Nada) : kv_done est une impulsion ; kv_found, kv_value_out et kv_error
// restent stables apres kv_done jusqu'a la prochaine kv_start.

module transaction_validator #(
    parameter [7:0]  CMD_CREATE   = 8'h01,
    parameter [7:0]  CMD_SEARCH   = 8'h02,
    parameter [7:0]  CMD_TRANSFER = 8'h03,
    parameter [15:0] VALUE_MIN    = 16'd1,
    parameter [15:0] VALUE_MAX    = 16'hFFFF,
    parameter        TIMEOUT      = 1000        // cycles max d'attente (KVS ou bloc)
)(
    input  wire        clk,
    input  wire        rst,

    // ---- cote decodeur (le validateur est l'esclave) ----
    input  wire [7:0]  in_cmd,
    input  wire [31:0] in_key,
    input  wire [15:0] in_value,
    input  wire        in_start,
    output wire        in_busy,
    output reg         in_done,
    output reg         in_found,
    output reg  [15:0] in_value_out,
    output reg         in_error,
    output reg  [3:0]  in_err_code,

    // ---- cote KVS / Cuckoo (le validateur est le maitre) ----
    output reg  [7:0]  kv_cmd,
    output reg  [31:0] kv_key,
    output reg  [15:0] kv_value,
    output reg         kv_start,
    input  wire        kv_busy,
    input  wire        kv_done,
    input  wire        kv_found,
    input  wire [15:0] kv_value_out,
    input  wire        kv_error,

    // ---- vers block_builder ----
    input  wire        blk_ready,
    output wire        blk_hold,
    output wire        tx_acc_valid,            // impulsion : transaction acceptee
    output reg  [7:0]  tx_acc_type,
    output reg  [31:0] tx_acc_key,
    output reg  [15:0] tx_acc_value,

    // ---- debug ----
    output wire [3:0]  dbg_state
);

    localparam [3:0] V_IDLE       = 4'd0,
                     V_CHECK      = 4'd1,
                     V_WAIT_BLK   = 4'd2,
                     V_SRCH_START = 4'd3,
                     V_SRCH_WAIT  = 4'd4,
                     V_EXEC_START = 4'd5,
                     V_EXEC_WAIT  = 4'd6,
                     V_PASS_START = 4'd7,
                     V_PASS_WAIT  = 4'd8,
                     V_DONE       = 4'd9;

    reg [3:0]  state;
    reg [7:0]  cmd_r;
    reg [31:0] key_r;
    reg [15:0] val_r;
    reg        acc_flag;
    reg [15:0] tmo;

    assign in_busy      = (state != V_IDLE);
    assign tx_acc_valid = (state == V_DONE) && acc_flag;
    assign blk_hold     = (state == V_WAIT_BLK)   || (state == V_SRCH_START) || (state == V_SRCH_WAIT) ||
                          (state == V_EXEC_START) || (state == V_EXEC_WAIT)  || (state == V_DONE);
    assign dbg_state    = state;

    wire is_create   = (cmd_r == CMD_CREATE);
    wire is_transfer = (cmd_r == CMD_TRANSFER);
    wire is_search   = (cmd_r == CMD_SEARCH);

    // refus d'une transaction : code d'erreur, puis fin
    task reject(input [3:0] code);
        begin
            in_err_code <= code;
            in_error    <= (code != 4'd5);
            in_found    <= 1'b0;
            acc_flag    <= 1'b0;
            state       <= V_DONE;
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            state        <= V_IDLE;
            cmd_r        <= 8'd0;
            key_r        <= 32'd0;
            val_r        <= 16'd0;
            acc_flag     <= 1'b0;
            tmo          <= 16'd0;
            in_done      <= 1'b0;
            in_found     <= 1'b0;
            in_value_out <= 16'd0;
            in_error     <= 1'b0;
            in_err_code  <= 4'd0;
            kv_cmd       <= 8'd0;
            kv_key       <= 32'd0;
            kv_value     <= 16'd0;
            kv_start     <= 1'b0;
            tx_acc_type  <= 8'd0;
            tx_acc_key   <= 32'd0;
            tx_acc_value <= 16'd0;
        end else begin
            in_done  <= 1'b0;
            kv_start <= 1'b0;

            case (state)

                V_IDLE: if (in_start) begin
                    cmd_r        <= in_cmd;
                    key_r        <= in_key;
                    val_r        <= in_value;
                    acc_flag     <= 1'b0;
                    in_found     <= 1'b0;
                    in_value_out <= 16'd0;
                    in_error     <= 1'b0;
                    in_err_code  <= 4'd0;
                    tmo          <= 16'd0;
                    state        <= V_CHECK;
                end

                // ---------- regles sans acces au KVS (R1 a R3) ----------
                V_CHECK: begin
                    if (is_search)
                        state <= V_PASS_START;
                    else if (!(is_create || is_transfer))
                        reject(4'd1);
                    else if (key_r == 32'd0)
                        reject(4'd2);
                    else if (val_r < VALUE_MIN || val_r > VALUE_MAX)
                        reject(4'd3);
                    else begin
                        tmo   <= 16'd0;
                        state <= V_WAIT_BLK;
                    end
                end

                // ---------- R7 : le bloc peut-il accepter ? ----------
                V_WAIT_BLK: begin
                    tmo <= tmo + 16'd1;
                    if (blk_ready) begin
                        tmo   <= 16'd0;
                        state <= V_SRCH_START;
                    end else if (tmo == TIMEOUT)
                        reject(4'd7);
                end

                // ---------- R4 / R5 : la cle existe-t-elle ? ----------
                V_SRCH_START: if (!kv_busy) begin
                    kv_cmd   <= CMD_SEARCH;
                    kv_key   <= key_r;
                    kv_value <= 16'd0;
                    kv_start <= 1'b1;
                    tmo      <= 16'd0;
                    state    <= V_SRCH_WAIT;
                end

                V_SRCH_WAIT: begin
                    tmo <= tmo + 16'd1;
                    if (kv_done) begin
                        if (kv_error)                       reject(4'd6);
                        else if (is_create && kv_found)     reject(4'd4);
                        else if (is_transfer && !kv_found)  reject(4'd5);
                        else                                state <= V_EXEC_START;
                    end else if (tmo == TIMEOUT)
                        reject(4'd7);
                end

                // ---------- execution dans le KVS (R6) ----------
                V_EXEC_START: if (!kv_busy) begin
                    kv_cmd   <= cmd_r;
                    kv_key   <= key_r;
                    kv_value <= val_r;
                    kv_start <= 1'b1;
                    tmo      <= 16'd0;
                    state    <= V_EXEC_WAIT;
                end

                V_EXEC_WAIT: begin
                    tmo <= tmo + 16'd1;
                    if (kv_done) begin
                        if (kv_error)                           reject(4'd6);
                        else if (is_transfer && !kv_found)      reject(4'd5);
                        else begin                              // transaction acceptee
                            tx_acc_type  <= cmd_r;
                            tx_acc_key   <= key_r;
                            tx_acc_value <= val_r;
                            acc_flag     <= 1'b1;
                            in_found     <= 1'b1;
                            in_error     <= 1'b0;
                            in_err_code  <= 4'd0;
                            state        <= V_DONE;
                        end
                    end else if (tmo == TIMEOUT)
                        reject(4'd7);
                end

                // ---------- SEARCH : simple passage vers le KVS ----------
                V_PASS_START: if (!kv_busy) begin
                    kv_cmd   <= cmd_r;
                    kv_key   <= key_r;
                    kv_value <= 16'd0;
                    kv_start <= 1'b1;
                    tmo      <= 16'd0;
                    state    <= V_PASS_WAIT;
                end

                V_PASS_WAIT: begin
                    tmo <= tmo + 16'd1;
                    if (kv_done) begin
                        in_found     <= kv_found;
                        in_value_out <= kv_value_out;
                        in_error     <= kv_error;
                        in_err_code  <= kv_error ? 4'd6 : 4'd0;
                        acc_flag     <= 1'b0;
                        state        <= V_DONE;
                    end else if (tmo == TIMEOUT) begin
                        reject(4'd7);
                    end
                end

                // ---------- Fin de transaction ----------
                V_DONE: begin
                    in_done <= 1'b1;
                    state   <= V_IDLE;
                end

                default: begin
                    state <= V_IDLE;
                end
            endcase
        end
    end

endmodule
