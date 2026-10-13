// ============================================================
// canfd_bit_timer.v  -  Generateur de temps de bit pour l'emetteur CAN FD
//
// Produit "tick" : une impulsion d'un cycle d'horloge a chaque frontiere de bit.
// Convention (la meme que canfd_stuffer.v) :
//   - au cycle ou tick = 1, le sequenceur choisit le bit suivant et presente
//     dans next_mode la longueur de CE bit suivant ;
//   - le temporisateur recharge son compteur avec cette longueur au meme front d'horloge.
//
//   next_mode = 0 : bit au debit nominal              (ex. 1 Mbit/s)
//   next_mode = 1 : bit au debit de donnees           (ex. 2 Mbit/s)
//   next_mode = 2 : bit BRS  = nominal jusqu'au point d'echantillonnage nominal,
//                   puis fin du bit au debit de donnees   (A VALIDER avec la norme)
//   next_mode = 3 : delimiteur de CRC = debit de donnees jusqu'au point d'echantillonnage,
//                   puis fin du bit au debit nominal      (A VALIDER avec la norme)
//
// Avec CLK_FREQ = 100 MHz, 1 Mbit/s et 2 Mbit/s, points d'echantillonnage a 75 % :
//   nominal = 100 cycles, donnees = 50, BRS = 88, delimiteur CRC = 62.
// Adapter CLK_FREQ a l'horloge reelle de la carte.
// ============================================================
module canfd_bit_timer #(
    parameter CLK_FREQ  = 100_000_000,
    parameter NOM_RATE  = 1_000_000,
    parameter DATA_RATE = 2_000_000,
    parameter SP_NOM    = 75,          // point d'echantillonnage, debit nominal (%)
    parameter SP_DATA   = 75           // point d'echantillonnage, debit de donnees (%)
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       run,             // 1 = le temporisateur tourne (0 = repos, compteur a zero)
    input  wire [1:0] next_mode,       // longueur du bit qui commence au prochain front
    output wire       tick             // 1 cycle par frontiere de bit
);
    localparam NOM_CYC  = CLK_FREQ / NOM_RATE;
    localparam DAT_CYC  = CLK_FREQ / DATA_RATE;
    localparam NOM_S    = NOM_CYC * SP_NOM  / 100;   // cycles jusqu'au point d'echantillonnage nominal
    localparam DAT_S    = DAT_CYC * SP_DATA / 100;   // cycles jusqu'au point d'echantillonnage donnees
    localparam LEN_NOM  = NOM_CYC;
    localparam LEN_DATA = DAT_CYC;
    localparam LEN_BRS  = NOM_S + (DAT_CYC - DAT_S);
    localparam LEN_CRCD = DAT_S + (NOM_CYC - NOM_S);

    function [15:0] len_of(input [1:0] m);
        case (m)
            2'd0:    len_of = LEN_NOM;
            2'd1:    len_of = LEN_DATA;
            2'd2:    len_of = LEN_BRS;
            default: len_of = LEN_CRCD;
        endcase
    endfunction

    reg [15:0] cnt;
    assign tick = run & (cnt == 16'd0);

    always @(posedge clk) begin
        if (rst || !run)
            cnt <= 16'd0;
        else if (cnt == 16'd0)
            cnt <= len_of(next_mode) - 16'd1;
        else
            cnt <= cnt - 16'd1;
    end
endmodule
