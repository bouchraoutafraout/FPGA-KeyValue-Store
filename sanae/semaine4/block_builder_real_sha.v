
`timescale 1ns/1ps

// Wrapper d'integration : Block Builder + SHA-256 reel
// Les modules existants restent inchanges.

module block_builder_real_sha #(
    parameter AUTO_GENESIS = 1,
    parameter [255:0] GENESIS_HASH = 256'd0
) (
    input wire clk,
    input wire rst,

    // Entree transaction
    input wire tx_valid,
    input wire [7:0] tx_type,
    input wire [31:0] tx_key,
    input wire [15:0] tx_value,
    output wire ready,

    // Commandes du Block Builder
    input wire hold,
    input wire seal,

    // Initialisation optionnelle
    input wire init_valid,
    input wire [31:0] init_index,
    input wire [255:0] init_hash,

    // Interface avec le stockage
    output wire store_start,
    output wire [31:0] blk_index,
    output wire [255:0] blk_hash,
    input wire store_done,
    input wire st_full,

    // Informations d'etat
    output wire [31:0] next_index,
    output wire [255:0] last_hash,
    output wire [31:0] blocks_stored,
    output wire busy,
    output wire [3:0] dbg_state
);

    // Signaux entre le Block Builder et le moteur SHA
    wire hash_start;
    wire [351:0] blk_data;
    wire hash_done;
    wire [255:0] hash_value;

    wire sha_busy;
    wire sha_done;
    wire [255:0] sha_hash;

    // ------------------------------------------------
    // 1. Ton module : construction des blocs
    // ------------------------------------------------
    block_builder #(
        .AUTO_GENESIS(AUTO_GENESIS),
        .GENESIS_HASH(GENESIS_HASH)
    ) u_block_builder (
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
        .st_full(st_full),

        .next_index(next_index),
        .last_hash(last_hash),
        .blocks_stored(blocks_stored),
        .busy(busy),
        .dbg_state(dbg_state)
    );

    // ------------------------------------------------
    // 2. Module de Bouchra : calcul du vrai SHA-256
    // ------------------------------------------------
    block_hash u_block_hash (
        .clk(clk),
        .rst(rst),
        .start(hash_start),

        .index(blk_data[351:320]),
        .previous_hash(blk_data[319:64]),
        .transaction(blk_data[63:0]),

        .busy(sha_busy),
        .done(sha_done),
        .hash(sha_hash)
    );

    // ------------------------------------------------
    // 3. Retour du resultat SHA au Block Builder
    // ------------------------------------------------
    assign hash_done  = sha_done;
    assign hash_value = sha_hash;

endmodule
