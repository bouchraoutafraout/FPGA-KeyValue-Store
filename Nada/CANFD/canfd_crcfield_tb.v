`timescale 1ns/1ps
// Testbench du serialiseur du champ CRC.
// Test 1 et 2 : sequences derivees a la main (voir commentaires).
// Test 3 : CRC-21 (modele Python canfd_model.py).
module canfd_crcfield_tb;
    reg clk = 0, rst = 1, load = 0, prev_bit = 0, is21 = 0, tick = 0;
    reg [2:0]  stuff_mod8 = 0;
    reg [20:0] crc = 0;
    wire out_valid, out_bit, out_is_fsb, done, active;

    canfd_crcfield dut (.clk(clk), .rst(rst), .load(load), .prev_bit(prev_bit),
                        .stuff_mod8(stuff_mod8), .crc(crc), .is21(is21), .tick(tick),
                        .out_valid(out_valid), .out_bit(out_bit), .out_is_fsb(out_is_fsb),
                        .done(done), .active(active));

    always #5 clk = ~clk;

    reg [8*40-1:0] got;       // bits recus, sous forme de caracteres '0' / '1'
    integer n_got, n_fsb, errors = 0;

    always @(posedge clk) begin
        if (out_valid) begin
            got   = (got << 8) | (out_bit ? 8'h31 : 8'h30);
            n_got = n_got + 1;
            if (out_is_fsb) n_fsb = n_fsb + 1;
        end
    end

    task run(input p, input [2:0] sc, input [20:0] c, input w21,
             input [8*40-1:0] exp, input integer exp_n, input integer exp_fsb, input [255:0] name);
        integer t;
        begin
            got = 0; n_got = 0; n_fsb = 0;
            @(negedge clk); prev_bit = p; stuff_mod8 = sc; crc = c; is21 = w21; load = 1;
            @(negedge clk); load = 0; tick = 1;                     // un tick a chaque cycle
            $display("DEBUG TB: p=%b sc=%0d is21=%b", p, sc, w21);
$display("DEBUG DUT: len=%0d active=%b seq=%b fsb=%b",
         dut.len, dut.active, dut.seq, dut.fsb);
            for (t = 0; t < exp_n + 6; t = t + 1) @(negedge clk);
            tick = 0; @(negedge clk);
            if (got === exp && n_got == exp_n && n_fsb == exp_fsb)
                $display("PASS  %0s : %0d bits dont %0d de bourrage fixe", name, n_got, n_fsb);
            else begin
                $display("FAIL  %0s : %0d bits (attendu %0d), FSB %0d (attendu %0d)", name, n_got, exp_n, n_fsb, exp_fsb);
                $display("      obtenu  %0s", got);
                $display("      attendu %0s", exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst = 0;
        // Test 1 : bit precedent 0, compteur 0 (Gray 000, parite 0), CRC-17 = 0
        //   1 | 0000 | 1 | 0000 | 1 | 0000 | 1 | 0000 | 1 | 0000 | 1 | 0
        run(1'b0, 3'd0, 21'h00000, 1'b0, "100001000010000100001000010", 27, 6, "CRC-17, tout a zero");
        // Test 2 : bit precedent 1, compteur 3 (Gray 010, parite 1), CRC-17 = tous les bits a 1
        //   0 | 0101 | 0 | 1111 | 0 | 1111 | 0 | 1111 | 0 | 1111 | 0 | 1
        run(1'b1, 3'd3, 21'h1FFFF, 1'b0, "001010111101111011110111101", 27, 6, "CRC-17, compteur 3");
        // Test 3 : CRC-21 (donnees > 16 octets), compteur 7, motif 0x155555
        run(1'b0, 3'd7, 21'h155555, 1'b1, "11001010101101011010110101101011", 32, 7, "CRC-21, compteur 7");

        if (errors == 0) $display("=== TOUS LES TESTS DU CHAMP CRC REUSSIS ===");
        else             $display("=== %0d ERREUR(S) ===", errors);
        $finish;
    end
endmodule
