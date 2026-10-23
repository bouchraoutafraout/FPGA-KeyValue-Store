
`timescale 1ns/1ps

module canfd_tx_tb;

    reg clk = 0;
    reg rst = 1;
    reg start = 0;

    reg [10:0] can_id = 11'h123;
    reg [63:0] data = 64'hA5C3000000000000;
    reg [3:0] dlc = 4'd2;

    wire can_tx;
    wire busy;
    wire done;

    integer errors = 0;
    integer useful_bits = 0;
    integer dynamic_stuff = 0;
    integer crc_bits = 0;
    integer tail_bits = 0;

    reg [16:0] expected_crc = 17'h14E0A;

    // Horloge 100 MHz : periode de 10 ns
    always #5 clk = ~clk;

    // Module CAN FD a tester
    canfd_tx #(
        .CLK_FREQ(100_000_000)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .can_id(can_id),
        .data(data),
        .dlc(dlc),
        .can_tx(can_tx),
        .busy(busy),
        .done(done)
    );

    // =====================================
    // COMPTEURS DU STUFFING ET DU CRC
    // =====================================

    always @(negedge clk) begin

        if (!rst) begin

            if (dut.out_valid &&
                (dut.state == 3'd2 ||
                 dut.state == 3'd3)) begin

                if (dut.out_is_stuff)
                    dynamic_stuff = dynamic_stuff + 1;
                else
                    useful_bits = useful_bits + 1;

            end

            if (dut.crc_valid &&
                dut.state == 3'd5) begin

                crc_bits = crc_bits + 1;

            end

        end

    end

    // =====================================
    // VERIFICATION DE LA FIN DE TRAME
    // =====================================

    // tail_valid est une impulsion enregistree.
    // can_tx est mis a jour au front suivant.
    // On attend ce front, puis 1 ns pour observer
    // la nouvelle valeur de can_tx.

    always @(posedge clk) begin

        if (!rst && dut.tail_valid) begin

            #1;

            if (can_tx !== 1'b1) begin

                $display(
                    "FAIL TAIL bit %0d = %b",
                    tail_bits, can_tx
                );

                errors = errors + 1;

            end else begin

                $display(
                    "PASS TAIL bit %0d = 1",
                    tail_bits
                );

            end

            tail_bits = tail_bits + 1;

        end

    end

    // =====================================
    // SCENARIO DE TEST
    // =====================================

    initial begin

        $dumpfile("canfd_tx.vcd");
        $dumpvars(0, canfd_tx_tb);

        // Initialisation
        rst = 1;
        start = 0;

        repeat (5) @(negedge clk);

        rst = 0;

        repeat (3) @(negedge clk);

        // Demarrage transmission
        start = 1;

        @(negedge clk);
        start = 0;

        // Attendre fin de transmission
        wait(done == 1'b1);

        @(negedge clk);

        // =====================================
        // AFFICHAGE DES RESULTATS
        // =====================================

        $display("--------------------------------");
        $display("Bits utiles       : %0d", useful_bits);
        $display("Stuff dynamiques  : %0d", dynamic_stuff);
        $display("Bits CRC field    : %0d", crc_bits);
        $display("Bits fin de trame : %0d", tail_bits);
        $display("CRC-17            : %h", dut.crc_final);
        $display("--------------------------------");

        // Verification du nombre de bits utiles
        if (useful_bits != 38) begin
            $display("FAIL : nombre de bits utiles");
            errors = errors + 1;
        end

        // Verification du stuffing dynamique
        if (dynamic_stuff != 1) begin
            $display("FAIL : stuffing dynamique");
            errors = errors + 1;
        end

        // Verification du champ CRC
        if (crc_bits != 27) begin
            $display("FAIL : nombre de bits CRC");
            errors = errors + 1;
        end

        // Verification de la fin de trame
        if (tail_bits != 10) begin
            $display("FAIL : nombre de bits TAIL");
            errors = errors + 1;
        end

        // Verification CRC-17
        if (dut.crc_final !== expected_crc) begin
            $display("FAIL : CRC-17 incorrect");
            errors = errors + 1;
        end

        $display("--------------------------------");

        if (errors == 0)
            $display("=== TEST CAN FD REUSSI ===");
        else
            $display("=== %0d ERREUR(S) ===", errors);

        $finish;

    end

    // =====================================
    // TIMEOUT DE SECURITE
    // =====================================

    initial begin

        #200000;

        $display("FAIL : TIMEOUT SIMULATION");
        $finish;

    end

endmodule
