// ============================================================
// canfd_stuffer.v  -  Bits de bourrage DYNAMIQUES de CAN FD
// Regle : apres 5 bits identiques consecutifs, on insere un bit de valeur
// opposee. Le bit de bourrage compte comme premier bit de la serie suivante.
// S'applique du SOF a la fin du champ de donnees (le champ CRC utilise des
// bits de bourrage FIXES : module a part).
//
// Fonctionnement : a chaque impulsion de tick (un bit sur le bus),
//   - soit un bit de bourrage est emis (in_take = 0),
//   - soit le bit utile in_bit est emis (in_take = 1).
// ============================================================
module canfd_stuffer (
    input  wire       clk,
    input  wire       rst,
    input  wire       clear,         // debut de trame : remet tout a zero
    input  wire       tick,          // 1 impulsion par bit emis
    input  wire       in_valid,      // 1 = in_bit est disponible
    input  wire       in_bit,
    output wire       in_take,       // 1 = in_bit est consomme a ce tick
    output reg        out_valid,     // 1 = out_bit est un bit emis sur le bus
    output reg        out_bit,
    output reg        out_is_stuff,  // 1 = c'est un bit de bourrage
    output reg  [7:0] stuff_cnt      // nombre de bits de bourrage depuis clear
);
    reg       last;                  // valeur du dernier bit emis
    reg [2:0] run;                   // longueur de la serie courante (0 a 5)

    wire need_stuff = (run == 3'd5);
    assign in_take  = tick & in_valid & ~need_stuff;

    always @(posedge clk) begin
        if (rst || clear) begin
            last         <= 1'b0;
            run          <= 3'd0;
            out_valid    <= 1'b0;
            out_bit      <= 1'b0;
            out_is_stuff <= 1'b0;
            stuff_cnt    <= 8'd0;
        end else begin
            out_valid <= 1'b0;
            if (tick) begin
                if (need_stuff) begin
                    out_valid    <= 1'b1;
                    out_bit      <= ~last;
                    out_is_stuff <= 1'b1;
                    last         <= ~last;
                    run          <= 3'd1;
                    stuff_cnt    <= stuff_cnt + 8'd1;
                end else if (in_valid) begin
                    out_valid    <= 1'b1;
                    out_bit      <= in_bit;
                    out_is_stuff <= 1'b0;
                    if (run != 3'd0 && in_bit == last) run <= run + 3'd1;
                    else                               run <= 3'd1;
                    last         <= in_bit;
                end
            end
        end
    end
endmodule
