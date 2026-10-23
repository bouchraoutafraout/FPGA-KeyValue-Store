// ============================================================
// canfd_crcfield.v  -  Serialiseur du champ CRC d'une trame CAN FD
//
// Emet, un bit par tick :  [FSB] compteur(4) [FSB] puis le CRC (17 ou 21 bits),
// avec un bit de bourrage FIXE (FSB) avant le premier bit et apres chaque
// groupe de 4 bits du champ. Un FSB vaut l'inverse du bit qui le precede.
//   CRC-17 : 6 FSB, 27 bits emis      CRC-21 : 7 FSB, 32 bits emis
//
// Compteur de bourrage = nombre de bits de bourrage DYNAMIQUES modulo 8,
// en code Gray sur 3 bits, suivi d'un bit de parite paire.
//   0=000 1=001 2=011 3=010 4=110 5=111 6=101 7=100
// Ordre de transmission : bit de poids fort du code Gray en premier (SUPPOSE, a valider
// avec une trame reelle), puis la parite, puis le CRC du bit de poids fort au plus faible.
//
// Utilisation : impulsion "load" (au moins 1 cycle avant le premier tick), puis un tick par bit.
//   prev_bit   = dernier bit emis avant le champ CRC (donnees, y compris bourrage dynamique)
//   stuff_mod8 = stuff_cnt[2:0] du stuffer
//   crc        = valeur finale du CRC (CRC-17 dans les 17 bits de poids faible)
// ============================================================
module canfd_crcfield (
    input  wire        clk,
    input  wire        rst,
    input  wire        load,
    input  wire        prev_bit,
    input  wire [2:0]  stuff_mod8,
    input  wire [20:0] crc,
    input  wire        is21,          // 1 = CRC-21 (donnees > 16 octets)
    input  wire        tick,
    output reg         out_valid,
    output reg         out_bit,
    output reg         out_is_fsb,    // 1 = bit de bourrage fixe
    output reg         done,          // 1 cycle, en meme temps que le dernier bit
    output reg         active
);
    function [3:0] sbc_code(input [2:0] n);
        reg [2:0] g;
        begin
            case (n)
                3'd0:    g = 3'b000;
                3'd1:    g = 3'b001;
                3'd2:    g = 3'b011;
                3'd3:    g = 3'b010;
                3'd4:    g = 3'b110;
                3'd5:    g = 3'b111;
                3'd6:    g = 3'b101;
                default: g = 3'b100;
            endcase
            sbc_code = {g, ^g};       // ^g = 1 si nombre impair de 1 : la parite rend le total pair
        end
    endfunction

    // ---- construction de la sequence complete (combinatoire) ----
    reg [31:0] seq_c, fsb_c;
    reg [5:0]  len_c;
    reg [24:0] fld;
    reg [3:0]  sbc;
    reg        prev;
    integer    i, n, nb;

    always_comb begin
        sbc = sbc_code(stuff_mod8);
        nb  = is21 ? 25 : 21;
        fld = is21 ? {sbc, crc} : {4'b0000, sbc, crc[16:0]};
        seq_c = 32'd0;
        fsb_c = 32'd0;
        n     = 0;
        prev  = prev_bit;
        seq_c[n] = ~prev; fsb_c[n] = 1'b1; prev = ~prev; n = n + 1;      // FSB initial
        for (i = 0; i < 25; i = i + 1) begin
            if (i < nb) begin
                seq_c[n] = fld[nb-1-i]; fsb_c[n] = 1'b0; prev = fld[nb-1-i]; n = n + 1;
                if (((i + 1) % 4) == 0 && (i + 1) < nb) begin             // FSB apres chaque 4e bit
                    seq_c[n] = ~prev; fsb_c[n] = 1'b1; prev = ~prev; n = n + 1;
                end
            end
        end
        len_c = n;
        
    end

    // ---- emission bit par bit ----
    reg [31:0] seq, fsb;
    reg [5:0]  len, idx;

    always @(posedge clk) begin
        if (rst) begin
            active <= 1'b0; out_valid <= 1'b0; done <= 1'b0; out_bit <= 1'b0; out_is_fsb <= 1'b0;
            idx <= 6'd0; len <= 6'd0; seq <= 32'd0; fsb <= 32'd0;
        end else begin
            out_valid <= 1'b0;
            done      <= 1'b0;
            if (load) begin
                seq <= seq_c; fsb <= fsb_c; len <= len_c; idx <= 6'd0; active <= 1'b1;
            end else if (tick && active) begin
                out_valid  <= 1'b1;
                out_bit    <= seq[idx];
                out_is_fsb <= fsb[idx];
                if (idx == len - 6'd1) begin done <= 1'b1; active <= 1'b0; end
                idx <= idx + 6'd1;
            end
        end
    end
endmodule
