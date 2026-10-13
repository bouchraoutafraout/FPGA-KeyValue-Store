`timescale 1ns/1ps
// Testbench du generateur de temps de bit.
// On presente une suite de longueurs de bits et on mesure, en cycles d'horloge,
// l'intervalle entre deux ticks. Valeurs attendues (100 MHz, 1 / 2 Mbit/s, 75 %) :
//   nominal = 100, donnees = 50, BRS = 88, delimiteur CRC = 62.
module canfd_bit_timer_tb;
    reg clk = 0, rst = 1, run = 0;
    wire tick;
    integer idx = 0;          // numero du tick courant
    integer cyc = 0;          // cycles depuis le debut
    integer last_tick = 0;
    integer errors = 0;
    integer measured;

    // suite de longueurs : nominal, nominal, BRS, donnees, donnees, delimiteur CRC, nominal
    reg [1:0] seq [0:6];
    integer   expv [0:6];
    wire [1:0] next_mode = seq[idx];

    canfd_bit_timer #(.CLK_FREQ(100_000_000), .NOM_RATE(1_000_000), .DATA_RATE(2_000_000),
                      .SP_NOM(75), .SP_DATA(75))
        dut (.clk(clk), .rst(rst), .run(run), .next_mode(next_mode), .tick(tick));

    always #5 clk = ~clk;

    always @(posedge clk) begin
        cyc = cyc + 1;
        if (tick) begin
            if (idx > 0) begin
                measured = cyc - last_tick;
                if (measured == expv[idx-1])
                    $display("PASS  bit %0d : %0d cycles", idx-1, measured);
                else begin
                    $display("FAIL  bit %0d : %0d cycles (attendu %0d)", idx-1, measured, expv[idx-1]);
                    errors = errors + 1;
                end
            end
            last_tick = cyc;
            idx = idx + 1;
        end
    end

    initial begin
        seq[0] = 0; seq[1] = 0; seq[2] = 2; seq[3] = 1; seq[4] = 1; seq[5] = 3; seq[6] = 0;
        expv[0] = 100; expv[1] = 100; expv[2] = 88; expv[3] = 50; expv[4] = 50; expv[5] = 62; expv[6] = 100;
        repeat (3) @(negedge clk);
        rst = 0; run = 1;
        wait (idx == 8);                 // 7 intervalles mesures
        @(negedge clk);
        if (errors == 0) $display("=== TOUS LES TESTS DU TEMPORISATEUR REUSSIS ===");
        else             $display("=== %0d ERREUR(S) ===", errors);
        $finish;
    end
endmodule
