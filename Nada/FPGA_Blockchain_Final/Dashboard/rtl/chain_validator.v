`timescale 1ns/1ps

// Verification d'un bloc de la mini-blockchain.
// Un bloc contient : {index (32), previous_hash (256), transaction (64)}.
// On verifie :
// 1) previous_hash == expected_previous_hash (lien avec le bloc precedent)
// 2) stored_hash == SHA256(contenu du bloc) (integrite du bloc)
// start : impulsion de 1 cycle ; done : impulsion de 1 cycle.
// Le controleur doit fournir les champs lus en memoire et le hash attendu.
module chain_validator (
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire [31:0]  index,
    input  wire [255:0] previous_hash,
    input  wire [63:0]  transaction,
    input  wire [255:0] stored_hash,
    input  wire [255:0] expected_previous_hash,
    output wire         busy,
    output reg          done,
    output reg          link_ok,
    output reg          hash_ok,
    output reg          chain_valid,
    output reg [255:0]  computed_hash
);
    reg active;
    reg link_matches;
    reg [255:0] stored_hash_saved;
    wire sha_busy, sha_done;
    wire [255:0] sha_hash;
    wire sha_start = start && !active && !sha_busy;

    // Le SHA-256 traite le message sur un front montant de start.
    // Les champs doivent etre stables pendant ce front.
    sha256_core #(.MSG_BITS(352)) sha (
        .clk(clk), .rst(rst), .start(sha_start),
        .message({index, previous_hash, transaction}),
        .busy(sha_busy), .done(sha_done), .hash(sha_hash)
    );

    assign busy = active || sha_busy;

    always @(posedge clk) begin
        if (rst) begin
            active                <= 1'b0;
            link_matches          <= 1'b0;
            stored_hash_saved     <= 256'd0;
            done                  <= 1'b0;
            link_ok               <= 1'b0;
            hash_ok               <= 1'b0;
            chain_valid           <= 1'b0;
            computed_hash         <= 256'd0;
        end else begin
            done <= 1'b0;
            if (sha_start) begin
                active            <= 1'b1;
                link_matches      <= (previous_hash == expected_previous_hash);
                stored_hash_saved <= stored_hash;
                link_ok           <= 1'b0;
                hash_ok           <= 1'b0;
                chain_valid       <= 1'b0;
            end else if (active && sha_done) begin
                active            <= 1'b0;
                computed_hash     <= sha_hash;
                link_ok           <= link_matches;
                hash_ok           <= (sha_hash == stored_hash_saved);
                chain_valid       <= link_matches && (sha_hash == stored_hash_saved);
                done              <= 1'b1;
            end
        end
    end
endmodule
