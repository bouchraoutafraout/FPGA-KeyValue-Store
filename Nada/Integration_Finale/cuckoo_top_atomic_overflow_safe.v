// cuckoo_top.v : PROPOSITION de bloc "Cuckoo / BRAM" pour tester le decodeur de bout en bout.
// A valider avec la Personne 3, qui reste responsable de ce bloc.
//
// Interface cote decodeur : cmd, key, value_in, start -> busy, done, found, value_out, error
//   CREATE   : SEARCH d'abord (doublon => error), puis INSERT (echec d'insertion => error)
//   SEARCH   : lit les deux tables en parallele ; found et value_out
//   TRANSFER : SEARCH, puis reecriture de la valeur a l'endroit trouve ; found = 0 si cle absente
//
// Contient : cuckoo_insert (P4), hashtables + bram_table (P3), hash_function1 et 2 (P1, P2).
// done est une impulsion d'un cycle.

module cuckoo_top_atomic_overflow_safe #(
    parameter KEY_W = 32,
    parameter VAL_W = 16,
    parameter IDX_W = 8
)(
    input  wire              clk,
    input  wire              rst,

    input  wire [7:0]        cmd,
    input  wire [KEY_W-1:0]  key,
    input  wire [VAL_W-1:0]  value_in,
    input  wire              start,
    input  wire              txn_begin,
    input  wire              txn_commit,
    input  wire              txn_rollback,
    output reg               txn_rollback_done,
    output reg               txn_journal_overflow,

    output wire              busy,
    output reg               done,
    output reg               found,
    output reg  [VAL_W-1:0]  value_out,
    output reg               error
);

    localparam EW = 1 + KEY_W + VAL_W;
    localparam C_CREATE = 8'h01, C_SEARCH = 8'h02, C_TRANSFER = 8'h03;
    localparam T_IDLE = 3'd0, T_SRCH = 3'd1, T_SRCH2 = 3'd2,
               T_INS  = 3'd3, T_UPD  = 3'd4, T_DONE  = 3'd5;

    reg [2:0]       st;
    reg [7:0]       cmd_r;
    reg [KEY_W-1:0] key_r;
    reg [VAL_W-1:0] val_r;
    reg             hit_tbl;
    reg [IDX_W-1:0] hit_idx;
    reg             ins_start;

    // hachages de la cle de la requete (pour SEARCH / TRANSFER)
    wire [IDX_W-1:0] rh1, rh2;
    hash_function1 RH1 (.key(key_r), .index(rh1));
    hash_function2 RH2 (.key(key_r), .index(rh2));

    // hachages demandes par le module INSERT (la cle change a chaque eviction)
    wire [KEY_W-1:0] ins_hash_key;
    wire [IDX_W-1:0] ih1, ih2;
    hash_function1 IH1 (.key(ins_hash_key), .index(ih1));
    hash_function2 IH2 (.key(ins_hash_key), .index(ih2));

    // module INSERT
    wire             ins_busy, ins_done, ins_fail;
    wire [7:0]       ins_kicks;
    wire             i_tbl, i_we;
    wire [IDX_W-1:0] i_addr;
    wire [EW-1:0]    i_wdata, ht_rdata;

    cuckoo_insert #(.KEY_W(KEY_W), .VAL_W(VAL_W), .IDX_W(IDX_W), .MAX_KICKS(8)) INS (
        .clk(clk), .rst(rst), .start(ins_start), .key_in(key_r), .val_in(val_r),
        .busy(ins_busy), .done(ins_done), .fail(ins_fail), .kick_count(ins_kicks),
        .hash_key(ins_hash_key), .h1_idx(ih1), .h2_idx(ih2),
        .mem_tbl(i_tbl), .mem_addr(i_addr), .mem_we(i_we),
        .mem_wdata(i_wdata), .mem_rdata(ht_rdata)
    );

    // Undo log: up to 16 physical writes, including Cuckoo evictions.
    // This is a volatile, synchronous rollback prototype (not power-loss safe).
    localparam LOG_DEPTH = 16;
    reg [4:0] log_count;
    reg [4:0] undo_pos;
    reg txn_active;
    reg undo_active;
    reg log_table [0:LOG_DEPTH-1];
    reg [IDX_W-1:0] log_addr [0:LOG_DEPTH-1];
    reg [EW-1:0] log_old [0:LOG_DEPTH-1];
    wire undo_write = undo_active && (undo_pos != 0);
    wire [4:0] undo_slot = undo_pos - 1'b1;
    wire live_write = upd | i_we;
    wire [EW-1:0] live_old = upd ? (hit_tbl ? r2 : r1) : ht_rdata;
    wire journal_space = log_count < LOG_DEPTH;
    wire physical_live_write = live_write && (!txn_active || journal_space)
                               && !undo_active && !txn_rollback;

    always @(posedge clk) begin
        if (rst) begin
            log_count <= 0;
            undo_pos <= 0;
            txn_active <= 0;
            undo_active <= 0;
            txn_rollback_done <= 0;
            txn_journal_overflow <= 0;
        end else begin
            txn_rollback_done <= 0;
            if (txn_begin && !undo_active) begin
                txn_active <= 1;
                log_count <= 0;
                txn_journal_overflow <= 0;
            end else if (txn_commit && !undo_active) begin
                txn_active <= 0;
                log_count <= 0;
            end else if (txn_rollback && !undo_active) begin
                txn_active <= 0;
                undo_pos <= log_count;
                undo_active <= 1;
            end else if (undo_active) begin
                if (undo_pos != 0)
                    undo_pos <= undo_pos - 1'b1;
                else begin
                    undo_active <= 0;
                    log_count <= 0;
                    txn_rollback_done <= 1;
                end
            end else if (txn_active && live_write) begin
                if (journal_space) begin
                    log_table[log_count] <= upd ? hit_tbl : i_tbl;
                    log_addr[log_count] <= upd ? hit_idx : i_addr;
                    log_old[log_count] <= live_old;
                    log_count <= log_count + 1'b1;
                end else
                    txn_journal_overflow <= 1;
            end
        end
    end

    // tables en BRAM (P3) ; en etat T_UPD, ce bloc prend la main sur le port d'ecriture
    wire upd = (st == T_UPD);
    wire [EW-1:0] r1, r2;

    hashtables #(.KEY_W(KEY_W), .VAL_W(VAL_W), .IDX_W(IDX_W)) HT (
        .clk(clk),
        .search_busy(st == T_SRCH),
        .s_addr1(rh1), .s_addr2(rh2), .s_rdata1(r1), .s_rdata2(r2),
        .ins_tbl(undo_write ? log_table[undo_slot] : (upd ? hit_tbl : i_tbl)),
        .ins_addr(undo_write ? log_addr[undo_slot] : (upd ? hit_idx : i_addr)),
        .ins_we(undo_write || physical_live_write),
        .ins_wdata(undo_write ? log_old[undo_slot] : (upd ? {1'b1, key_r, val_r} : i_wdata)),
        .ins_rdata(ht_rdata)
    );

    wire hit1 = r1[EW-1] && (r1[EW-2:VAL_W] == key_r);
    wire hit2 = r2[EW-1] && (r2[EW-2:VAL_W] == key_r);

    assign busy = (st != T_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            st <= T_IDLE; done <= 1'b0; found <= 1'b0; error <= 1'b0;
            value_out <= {VAL_W{1'b0}}; ins_start <= 1'b0;
            cmd_r <= 8'd0; key_r <= {KEY_W{1'b0}}; val_r <= {VAL_W{1'b0}};
            hit_tbl <= 1'b0; hit_idx <= {IDX_W{1'b0}};
        end else begin
            done <= 1'b0;
            ins_start <= 1'b0;
            case (st)
                T_IDLE: if (start) begin
                    cmd_r <= cmd; key_r <= key; val_r <= value_in;
                    found <= 1'b0; error <= 1'b0; value_out <= {VAL_W{1'b0}};
                    st <= T_SRCH;
                end

                T_SRCH: st <= T_SRCH2;          // attente de la lecture BRAM (1 cycle)

                T_SRCH2: begin
                    found     <= hit1 | hit2;
                    hit_tbl   <= ~hit1 & hit2;
                    hit_idx   <= hit1 ? rh1 : rh2;
                    value_out <= (cmd_r == C_SEARCH && (hit1 | hit2))
                                 ? (hit1 ? r1[VAL_W-1:0] : r2[VAL_W-1:0]) : {VAL_W{1'b0}};
                    case (cmd_r)
                        C_SEARCH:   st <= T_DONE;
                        C_CREATE:   if (hit1 | hit2) begin error <= 1'b1; st <= T_DONE; end
                                    else begin ins_start <= 1'b1; st <= T_INS; end
                        C_TRANSFER: st <= (hit1 | hit2) ? T_UPD : T_DONE;
                        default:    begin error <= 1'b1; st <= T_DONE; end
                    endcase
                end

                T_INS: begin
                    if (ins_done)      st <= T_DONE;
                    else if (ins_fail) begin error <= 1'b1; st <= T_DONE; end
                end

                T_UPD:  st <= T_DONE;           // ecriture de la nouvelle valeur

                T_DONE: begin
                    // An insertion must never report success if a physical
                    // write was suppressed due to a full undo journal.
                    if (txn_journal_overflow)
                        error <= 1'b1;
                    done <= 1'b1;
                    st <= T_IDLE;
                end

                default: st <= T_IDLE;
            endcase
        end
    end
endmodule
