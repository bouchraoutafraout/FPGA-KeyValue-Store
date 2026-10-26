`timescale 1ns/1ps
// Testbench du stuffer CAN FD (bits de bourrage dynamiques).
// Chaque cycle d'horloge = un bit sur le bus (tick = 1 en permanence).
module canfd_stuffer_tb;
    reg clk = 0, rst = 1, clear = 0;
    reg in_valid = 0, in_bit = 0;
    wire in_take, out_valid, out_bit, out_is_stuff;
    wire [7:0] stuff_cnt;

    canfd_stuffer dut (.clk(clk), .rst(rst), .clear(clear), .tick(1'b1),
                       .in_valid(in_valid), .in_bit(in_bit), .in_take(in_take),
                       .out_valid(out_valid), .out_bit(out_bit),
                       .out_is_stuff(out_is_stuff), .stuff_cnt(stuff_cnt));

    always #5 clk = ~clk;

    reg [63:0] vec;          // flux d'entree (bit 0 = premier bit)
    integer    n_in, idx, n_out;
    reg [127:0] outv;        // flux de sortie (bit 0 = premier bit)
    integer    errors = 0;

    // fournit le bit courant au stuffer
    always @(*) begin
        in_valid = (idx < n_in);
        in_bit   = vec[idx];
    end

    // avance dans le flux d'entree quand le stuffer consomme un bit
    // et memorise les bits emis (lus avant la mise a jour du front d'horloge)
    always @(posedge clk) begin
        if (!rst && !clear) begin
            if (in_take) idx = idx + 1;
            if (out_valid) begin outv[n_out] = out_bit; n_out = n_out + 1; end
        end
    end

    task run(input [63:0] v, input integer n, input [127:0] expv, input integer exp_n,
             input integer exp_cnt, input [255:0] name);
        integer t;
        reg [127:0] mask;
        begin
            @(negedge clk); clear = 1; vec = v; n_in = n; idx = 0; n_out = 0; outv = 0;
            @(negedge clk); clear = 0;
            for (t = 0; t < n + 12; t = t + 1) @(negedge clk);
            mask = (128'd1 << exp_n) - 128'd1;
            if (n_out === exp_n && (outv & mask) === (expv & mask) && stuff_cnt === exp_cnt)
                $display("PASS  %0s : %0d bits, %0d bit(s) de bourrage", name, n_out, stuff_cnt);
            else begin
                $display("FAIL  %0s : %0d bits (attendu %0d), bourrage %0d (attendu %0d), sortie %b",
                         name, n_out, exp_n, stuff_cnt, exp_cnt, outv & mask);
                errors = errors + 1;
            end
        end
    endtask

    // Les flux sont ecrits avec le PREMIER BIT A DROITE (bit 0) : lire les litteraux a l'envers.
    initial begin
        repeat (2) @(negedge clk);
        rst = 0;
        // 6 zeros -> 00000 [1] 0
        run(64'b000000,       6,  128'b0100000,        7, 1, "6 zeros");
        // 10 uns -> 11111 [0] 11111 [0]
        run(64'b1111111111, 10, 128'b11111011111, 11, 1, "10 uns");
        // 0000011111 -> 00000 [1] 1111 [0] 1  (le bit de bourrage compte dans la serie suivante)
        run(64'b1111100000,  10,  128'b101111100000, 12, 2, "bourrage dans la serie suivante");
        // alternance : aucun bourrage
        run(64'b0101010101,  10,  128'b0101010101,    10, 0, "alternance");
        // 00000 puis 1 : le bourrage est insere meme si le bit suivant est different
        run(64'b100000,       6,  128'b1100000,        7, 1, "5 zeros puis un 1");

        if (errors == 0) $display("=== TOUS LES TESTS STUFFER REUSSIS ===");
        else             $display("=== %0d ERREUR(S) ===", errors);
        $finish;
    end
endmodule
