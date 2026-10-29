
`timescale 1ns/1ps

// block_builder.v
// Construction de blocs de 352 bits pour la mini-blockchain.
//
// FORMAT DU MESSAGE :
//   index (32 bits) | hash precedent (256 bits) | transaction (64 bits)
//
// FORMAT DE LA TRANSACTION :
//   reserve (8 bits) | type (8 bits) | cle (32 bits) | valeur (16 bits)
//
// Une seule transaction par bloc.
// Le hash est calcule par le module de Bouchra.
// Le stockage est gere par le module de Khadija.

module block_builder_safe #(
    parameter AUTO_GENESIS = 1,
    // A ADAPTER : hash Genesis du nouveau format de 352 bits.
    parameter [255:0] GENESIS_HASH =
        256'h85759b3811ff7dc47b03792ac85317be51431a3f9e01dcafce317ed736a391b0
)(
    input  wire         clk,
    input  wire         rst,

    // Transaction acceptee
    input  wire         tx_valid,
    input  wire [7:0]   tx_type,
    input  wire [31:0]  tx_key,
    input  wire [15:0]  tx_value,
    output wire         ready,
    input  wire         hold,
    input  wire         seal,

    // Genesis externe si AUTO_GENESIS = 0
    input  wire         init_valid,
    input  wire [31:0]  init_index,
    input  wire [255:0] init_hash,

    // Interface de hachage
    output wire         hash_start,
    output wire [351:0] blk_data,
    input  wire         hash_done,
    input  wire [255:0] hash_value,

    // Interface de stockage
    output wire         store_start,
    output wire [31:0]  blk_index,
    output wire [255:0] blk_hash,
    input  wire         store_done,
    input  wire         store_ok,
    output reg          store_failed,
    input  wire         st_full,

    // Etat
    output wire [31:0]  next_index,
    output wire [255:0] last_hash,
    output reg  [31:0]  blocks_stored,
    output wire         busy,
    output wire [3:0]   dbg_state
);

    localparam [3:0]
        S_INIT       = 4'd0,
        S_IDLE       = 4'd1,
        S_BUILD      = 4'd2,
        S_HASH_REQ   = 4'd3,
        S_HASH_WAIT  = 4'd4,
        S_STORE_REQ  = 4'd5,
        S_STORE_WAIT = 4'd6;

    reg [3:0] state;

    reg        tx_pending;
    reg [63:0] tx_reg;

    reg        seal_pending;

    reg [31:0]  next_index_r;
    reg [255:0] last_hash_r;

    reg [351:0] blk_reg;
    reg [31:0]  cur_index;
    reg [255:0] cur_hash;

    wire manual_seal_ready =
        seal_pending && tx_pending && !hold && !st_full;

    assign ready =
        (state == S_IDLE) &&
        !tx_pending &&
        !seal_pending &&
        !st_full;

    assign hash_start  = (state == S_HASH_REQ);
    assign store_start = (state == S_STORE_REQ);

    assign blk_data   = blk_reg;
    assign blk_index  = cur_index;
    assign blk_hash   = cur_hash;

    assign next_index = next_index_r;
    assign last_hash  = last_hash_r;

    assign busy      = (state != S_IDLE);
    assign dbg_state = state;

    wire tx_take = tx_valid && ready;

    always @(posedge clk) begin
        if (rst) begin
            state         <= S_INIT;
            tx_pending    <= 1'b0;
            tx_reg        <= 64'd0;
            seal_pending  <= 1'b0;

            next_index_r  <= 32'd0;
            last_hash_r   <= 256'd0;

            blk_reg       <= 352'd0;
            cur_index     <= 32'd0;
            cur_hash      <= 256'd0;

            blocks_stored <= 32'd0;
            store_failed <= 1'b0;
        end else begin
            store_failed <= 1'b0;

            if (seal && tx_pending)
                seal_pending <= 1'b1;

            case (state)

                // Genesis
                S_INIT: begin
                    if (AUTO_GENESIS == 1) begin
                        // Message Genesis : 352 bits a zero
                        blk_reg   <= 352'd0;
                        cur_index <= 32'd0;
                        state     <= S_HASH_REQ;
                    end else if (AUTO_GENESIS == 2) begin
                        // Genesis deja present dans le stockage
                        next_index_r  <= 32'd1;
                        last_hash_r   <= GENESIS_HASH;
                        blocks_stored <= 32'd1;
                        state         <= S_IDLE;
                    end else if (init_valid) begin
                        next_index_r  <= init_index;
                        last_hash_r   <= init_hash;
                        blocks_stored <= init_index;
                        state         <= S_IDLE;
                    end
                end

                // Attente d'une transaction
                S_IDLE: begin
                    if (tx_take) begin
                        // 8 bits reserves + type + cle + valeur
                        tx_reg      <= {8'd0, tx_type, tx_key, tx_value};
                        tx_pending  <= 1'b1;
                        seal_pending <= 1'b0;
                    end else if (manual_seal_ready) begin
                        state <= S_BUILD;
                    end
                end

                // Construction du message de 352 bits
                S_BUILD: begin
                    blk_reg <= {
                        next_index_r,
                        last_hash_r,
                        tx_reg
                    };

                    cur_index    <= next_index_r;
                    seal_pending <= 1'b0;
                    state        <= S_HASH_REQ;
                end

                // Demande de calcul SHA-256
                S_HASH_REQ: begin
                    state <= S_HASH_WAIT;
                end

                // Attente du resultat du hash
                S_HASH_WAIT: begin
                    if (hash_done) begin
                        cur_hash <= hash_value;
                        state    <= S_STORE_REQ;
                    end
                end

                // Demande d'ecriture en stockage
                S_STORE_REQ: begin
                    if (!st_full)
                        state <= S_STORE_WAIT;
                end

                // Attente de confirmation du stockage
                S_STORE_WAIT: begin
                    if (store_done) begin
                        if (store_ok) begin
                            last_hash_r   <= cur_hash;
                            next_index_r  <= cur_index + 32'd1;
                            blocks_stored <= blocks_stored + 32'd1;
                        end else begin
                            store_failed <= 1'b1;
                        end

                        tx_pending   <= 1'b0;
                        tx_reg       <= 64'd0;
                        seal_pending <= 1'b0;
                        state <= S_IDLE;
                    end
                end

                default: begin
                    state <= S_INIT;
                end
            endcase
        end
    end

endmodule
