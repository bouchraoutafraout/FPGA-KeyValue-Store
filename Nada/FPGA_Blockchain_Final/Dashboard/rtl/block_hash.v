`timescale 1ns/1ps

// Calcule le SHA-256 d'un bloc blockchain de 352 bits :
// index (32) || previous_hash (256) || transaction (64).
// start : impulsion d'un cycle ; done : impulsion de fin.
// Ce module reutilise le sha256_core valide, sans le modifier.
module block_hash (
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire [31:0]  index,
    input  wire [255:0] previous_hash,
    input  wire [63:0]  transaction,
    output wire         busy,
    output wire         done,
    output wire [255:0] hash
);
    wire [351:0] block_message = {index, previous_hash, transaction};

    sha256_core #(.MSG_BITS(352)) sha (
        .clk(clk),
        .rst(rst),
        .start(start),
        .message(block_message),
        .busy(busy),
        .done(done),
        .hash(hash)
    );
endmodule
