// ============================================================
// canfd_crc.v  -  Moteur CRC bit par bit pour CAN FD
// Un bit est pris en compte a chaque cycle ou en = 1.
//
//   CRC-17 (donnees <= 16 octets) : WIDTH=17, POLY=21'h1685B, INIT=21'h10000
//   CRC-21 (donnees  > 16 octets) : WIDTH=21, POLY=21'h102899, INIT=21'h100000
//
// POLY s'ecrit sans le terme de plus haut degre.
//   CRC-17 : x17 + x16 + x14 + x13 + x11 + x6 + x4 + x3 + x1 + 1
//   CRC-21 : x21 + x20 + x13 + x11 + x7 + x4 + x3 + 1
// INIT = "1 suivi de zeros" (bit de poids fort a 1) pour CAN FD.
// ============================================================
module canfd_crc #(
    parameter             WIDTH = 17,
    parameter [20:0]      POLY  = 21'h1685B,
    parameter [20:0]      INIT  = 21'h10000
)(
    input  wire             clk,
    input  wire             rst,        // reinitialise (asynchrone au domaine clk : synchrone ici)
    input  wire             load_init,  // recharge INIT (a mettre a 1 au debut de chaque trame)
    input  wire             en,         // 1 = din est pris en compte a ce cycle
    input  wire             din,        // bit transmis (bits de bourrage dynamiques inclus)
    output reg  [WIDTH-1:0] crc
);
    wire [WIDTH-1:0] poly_w = POLY[WIDTH-1:0];
    wire [WIDTH-1:0] init_w = INIT[WIDTH-1:0];
    wire             fb     = crc[WIDTH-1] ^ din;

    always @(posedge clk) begin
        if (rst || load_init)
            crc <= init_w;
        else if (en)
            crc <= {crc[WIDTH-2:0], 1'b0} ^ (fb ? poly_w : {WIDTH{1'b0}});
    end
endmodule
