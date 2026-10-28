`timescale 1ns/1ps
// SHA-256 reel, version pedagogique iterative (64 tours).
// Un seul bloc SHA-256 de 512 bits est traite par message.
// MSG_BITS <= 447 : le padding SHA-256 est fait automatiquement.
// Pour le projet : MSG_BITS = 352 = 32 index + 256 previous_hash + 64 transaction.
// Interface : start (1 cycle), busy, done (1 cycle), hash sur 256 bits.
module sha256_core #(
    parameter integer MSG_BITS = 352
)(
    input  wire                clk,
    input  wire                rst,
    input  wire                start,
    input  wire [MSG_BITS-1:0] message,
    output reg                 busy,
    output reg                 done,
    output reg [255:0]         hash
);
    localparam [63:0] LENGTH_BITS = MSG_BITS;
    // Message original || '1' || zeros || longueur (64 bits), format FIPS 180-4.
    wire [511:0] padded_block = {
        message, 1'b1, {(447-MSG_BITS){1'b0}}, LENGTH_BITS
    };

    // 16 mots de travail stockes dans une memoire circulaire.
    reg [31:0] words [0:15];
    reg [5:0] round_no;
    reg [31:0] a, b, c, d, e, f, g, h;
    integer i;

    function [31:0] rotr;
        input [31:0] x;
        input integer n;
        begin rotr = (x >> n) | (x << (32-n)); end
    endfunction

    function [31:0] small_s0;
        input [31:0] x;
        begin small_s0 = rotr(x,7) ^ rotr(x,18) ^ (x >> 3); end
    endfunction
    function [31:0] small_s1;
        input [31:0] x;
        begin small_s1 = rotr(x,17) ^ rotr(x,19) ^ (x >> 10); end
    endfunction
    function [31:0] big_s0;
        input [31:0] x;
        begin big_s0 = rotr(x,2) ^ rotr(x,13) ^ rotr(x,22); end
    endfunction
    function [31:0] big_s1;
        input [31:0] x;
        begin big_s1 = rotr(x,6) ^ rotr(x,11) ^ rotr(x,25); end
    endfunction

    function [31:0] round_constant;
        input [5:0] n;
        begin
            case (n)
            6'd0: round_constant = 32'h428a2f98;
            6'd1: round_constant = 32'h71374491;
            6'd2: round_constant = 32'hb5c0fbcf;
            6'd3: round_constant = 32'he9b5dba5;
            6'd4: round_constant = 32'h3956c25b;
            6'd5: round_constant = 32'h59f111f1;
            6'd6: round_constant = 32'h923f82a4;
            6'd7: round_constant = 32'hab1c5ed5;
            6'd8: round_constant = 32'hd807aa98;
            6'd9: round_constant = 32'h12835b01;
            6'd10: round_constant = 32'h243185be;
            6'd11: round_constant = 32'h550c7dc3;
            6'd12: round_constant = 32'h72be5d74;
            6'd13: round_constant = 32'h80deb1fe;
            6'd14: round_constant = 32'h9bdc06a7;
            6'd15: round_constant = 32'hc19bf174;
            6'd16: round_constant = 32'he49b69c1;
            6'd17: round_constant = 32'hefbe4786;
            6'd18: round_constant = 32'h0fc19dc6;
            6'd19: round_constant = 32'h240ca1cc;
            6'd20: round_constant = 32'h2de92c6f;
            6'd21: round_constant = 32'h4a7484aa;
            6'd22: round_constant = 32'h5cb0a9dc;
            6'd23: round_constant = 32'h76f988da;
            6'd24: round_constant = 32'h983e5152;
            6'd25: round_constant = 32'ha831c66d;
            6'd26: round_constant = 32'hb00327c8;
            6'd27: round_constant = 32'hbf597fc7;
            6'd28: round_constant = 32'hc6e00bf3;
            6'd29: round_constant = 32'hd5a79147;
            6'd30: round_constant = 32'h06ca6351;
            6'd31: round_constant = 32'h14292967;
            6'd32: round_constant = 32'h27b70a85;
            6'd33: round_constant = 32'h2e1b2138;
            6'd34: round_constant = 32'h4d2c6dfc;
            6'd35: round_constant = 32'h53380d13;
            6'd36: round_constant = 32'h650a7354;
            6'd37: round_constant = 32'h766a0abb;
            6'd38: round_constant = 32'h81c2c92e;
            6'd39: round_constant = 32'h92722c85;
            6'd40: round_constant = 32'ha2bfe8a1;
            6'd41: round_constant = 32'ha81a664b;
            6'd42: round_constant = 32'hc24b8b70;
            6'd43: round_constant = 32'hc76c51a3;
            6'd44: round_constant = 32'hd192e819;
            6'd45: round_constant = 32'hd6990624;
            6'd46: round_constant = 32'hf40e3585;
            6'd47: round_constant = 32'h106aa070;
            6'd48: round_constant = 32'h19a4c116;
            6'd49: round_constant = 32'h1e376c08;
            6'd50: round_constant = 32'h2748774c;
            6'd51: round_constant = 32'h34b0bcb5;
            6'd52: round_constant = 32'h391c0cb3;
            6'd53: round_constant = 32'h4ed8aa4a;
            6'd54: round_constant = 32'h5b9cca4f;
            6'd55: round_constant = 32'h682e6ff3;
            6'd56: round_constant = 32'h748f82ee;
            6'd57: round_constant = 32'h78a5636f;
            6'd58: round_constant = 32'h84c87814;
            6'd59: round_constant = 32'h8cc70208;
            6'd60: round_constant = 32'h90befffa;
            6'd61: round_constant = 32'ha4506ceb;
            6'd62: round_constant = 32'hbef9a3f7;
            6'd63: round_constant = 32'hc67178f2;
                default: round_constant = 32'd0;
            endcase
        end
    endfunction

    wire [3:0] idx_0  = round_no[3:0];
    wire [3:0] idx_15 = idx_0 - 4'd15;
    wire [3:0] idx_7  = idx_0 - 4'd7;
    wire [3:0] idx_2  = idx_0 - 4'd2;

    wire [31:0] next_word = small_s1(words[idx_2]) + words[idx_7]
                           + small_s0(words[idx_15]) + words[idx_0];
    wire [31:0] wt = (round_no < 6'd16) ? words[idx_0] : next_word;

    wire [31:0] t1 = h + big_s1(e) + ((e & f) ^ (~e & g))
                   + round_constant(round_no) + wt;
    wire [31:0] t2 = big_s0(a) + ((a & b) ^ (a & c) ^ (b & c));

    wire [31:0] new_a = t1 + t2;
    wire [31:0] new_b = a;
    wire [31:0] new_c = b;
    wire [31:0] new_d = c;
    wire [31:0] new_e = d + t1;
    wire [31:0] new_f = e;
    wire [31:0] new_g = f;
    wire [31:0] new_h = g;

    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            done <= 1'b0;
            hash <= 256'd0;
            round_no <= 6'd0;
            a <= 0; b <= 0; c <= 0; d <= 0;
            e <= 0; f <= 0; g <= 0; h <= 0;
            for (i=0; i<16; i=i+1)
                words[i] <= 32'd0;
        end else begin
            done <= 1'b0;
            if (!busy) begin
                if (start) begin
                    busy <= 1'b1;
                    round_no <= 6'd0;
                    // Les constantes initiales officielles du SHA-256.
                    a <= 32'h6a09e667; b <= 32'hbb67ae85;
                    c <= 32'h3c6ef372; d <= 32'ha54ff53a;
                    e <= 32'h510e527f; f <= 32'h9b05688c;
                    g <= 32'h1f83d9ab; h <= 32'h5be0cd19;
                    for (i=0; i<16; i=i+1)
                        words[i] <= padded_block[511 - (32*i) -: 32];
                end
            end else begin
                if (round_no >= 6'd16)
                    words[idx_0] <= next_word;
                a <= new_a; b <= new_b; c <= new_c; d <= new_d;
                e <= new_e; f <= new_f; g <= new_g; h <= new_h;
                if (round_no == 6'd63) begin
                    hash <= {
                        32'h6a09e667 + new_a, 32'hbb67ae85 + new_b,
                        32'h3c6ef372 + new_c, 32'ha54ff53a + new_d,
                        32'h510e527f + new_e, 32'h9b05688c + new_f,
                        32'h1f83d9ab + new_g, 32'h5be0cd19 + new_h
                    };
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    round_no <= round_no + 6'd1;
                end
            end
        end
    end
endmodule
