// cuckoo_insert.v : logique INSERT du Cuckoo Hashing (eviction)
// Hypotheses : la cle n'existe pas deja (le decodeur appelle SEARCH avant),
//              lecture memoire synchrone (donnee valide 1 cycle apres l'adresse).
// Format d'une case memoire : {valid, key, value}

module cuckoo_insert #(
    parameter KEY_W     = 16,
    parameter VAL_W     = 16,
    parameter IDX_W     = 2,     // taille table = 2^IDX_W cases
    parameter MAX_KICKS = 8      // limite d'evictions avant echec
)(
    input  wire                 clk,
    input  wire                 rst,

    // commande
    input  wire                 start,
    input  wire [KEY_W-1:0]     key_in,
    input  wire [VAL_W-1:0]     val_in,
    output wire                 busy,
    output wire                 done,      // impulsion 1 cycle : insertion reussie
    output wire                 fail,      // impulsion 1 cycle : trop d'evictions
    output reg  [7:0]           kick_count,// nb d'evictions (debug)

    // fonctions de hachage (combinatoires, branchees de l'exterieur)
    output wire [KEY_W-1:0]     hash_key,
    input  wire [IDX_W-1:0]     h1_idx,
    input  wire [IDX_W-1:0]     h2_idx,

    // memoire (2 tables)
    output wire                 mem_tbl,   // 0 = table 1, 1 = table 2
    output wire [IDX_W-1:0]     mem_addr,
    output wire                 mem_we,
    output wire [KEY_W+VAL_W:0] mem_wdata,
    input  wire [KEY_W+VAL_W:0] mem_rdata
);

    localparam IDLE = 3'd0, READ = 3'd1, CHECK = 3'd2,
               WRITE = 3'd3, DONE = 3'd4, FAIL = 3'd5;

    reg [2:0]       state;
    reg             tbl;                 // table courante
    reg             evict;               // la case etait occupee
    reg [KEY_W-1:0] cur_key, old_key;    // cle en main / cle expulsee
    reg [VAL_W-1:0] cur_val, old_val;

    assign hash_key  = cur_key;
    assign mem_tbl   = tbl;
    assign mem_addr  = tbl ? h2_idx : h1_idx;
    assign mem_we    = (state == WRITE);
    assign mem_wdata = {1'b1, cur_key, cur_val};

    assign busy = (state != IDLE);
    assign done = (state == DONE);
    assign fail = (state == FAIL);

    always @(posedge clk) begin
        if (rst) begin
            state      <= IDLE;
            tbl        <= 1'b0;
            evict      <= 1'b0;
            kick_count <= 8'd0;
            cur_key    <= {KEY_W{1'b0}};
            cur_val    <= {VAL_W{1'b0}};
            old_key    <= {KEY_W{1'b0}};
            old_val    <= {VAL_W{1'b0}};
        end else begin
            case (state)
                IDLE: if (start) begin
                    cur_key    <= key_in;
                    cur_val    <= val_in;
                    tbl        <= 1'b0;
                    kick_count <= 8'd0;
                    state      <= READ;
                end

                READ:  state <= CHECK;       // attente latence memoire

                CHECK: begin
                    if (!mem_rdata[KEY_W+VAL_W]) begin      // case vide
                        evict <= 1'b0;
                        state <= WRITE;
                    end else if (kick_count == MAX_KICKS) begin
                        state <= FAIL;                      // trop d'evictions
                    end else begin                          // case occupee
                        old_key <= mem_rdata[KEY_W+VAL_W-1:VAL_W];
                        old_val <= mem_rdata[VAL_W-1:0];
                        evict   <= 1'b1;
                        state   <= WRITE;
                    end
                end

                WRITE: begin                 // on ecrit cur dans la case
                    if (evict) begin         // puis l'ancien occupant repart
                        cur_key    <= old_key;
                        cur_val    <= old_val;
                        tbl        <= ~tbl;
                        kick_count <= kick_count + 8'd1;
                        state      <= READ;
                    end else begin
                        state <= DONE;
                    end
                end

                DONE: state <= IDLE;
                FAIL: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
