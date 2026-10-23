
`timescale 1ns/1ps

module canfd_wire_tb;

    // ==========================================
    // 1. SIGNAUX DE SIMULATION
    // ==========================================

    reg clk = 0;
    reg rst = 1;
    reg start = 0;

    reg [10:0] can_id = 11'h123;

    // Test particulier : les 5 derniers bits
    // du deuxieme octet sont 11111
    reg [63:0] data = 64'hA51F000000000000;

    reg [3:0] dlc = 4'd2;

    wire can_tx;
    wire busy;
    wire done;

    integer file_out;
    integer bit_count = 0;

    // Horloge 100 MHz : periode 10 ns
    always #5 clk = ~clk;

    // ==========================================
    // 2. MODULE CAN FD A TESTER
    // ==========================================

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

    // ==========================================
    // 3. CAPTURE DES BITS SUR CAN_TX
    // ==========================================

    // Echantillonnage 30 ns apres chaque tick
    // pour tenir compte de la latence du TX actuel.

    always @(posedge dut.tick) begin

        #30;

        if (busy) begin

            $fdisplay(
                file_out,
                "%0d,%0t,%b",
                bit_count,
                $time,
                can_tx
            );

            bit_count = bit_count + 1;

        end

    end

    // ==========================================
    // 4. SCENARIO DE SIMULATION
    // ==========================================

    initial begin

        $dumpfile("canfd_wire.vcd");
        $dumpvars(0, canfd_wire_tb);

        file_out = $fopen("canfd_wire_bits.csv", "w");

        if (file_out == 0) begin

            $display(
                "ERREUR : impossible de creer le CSV"
            );

            $finish;

        end

        $fdisplay(
            file_out,
            "bit_index,time_ps,can_tx"
        );

        // Initialisation
        rst = 1'b1;
        start = 1'b0;

        repeat (5) @(negedge clk);

        rst = 1'b0;

        repeat (3) @(negedge clk);

        // Debut de transmission
        start = 1'b1;

        @(negedge clk);
        start = 1'b0;

        // Attendre la fin
        wait(done == 1'b1);

        @(negedge clk);

        // ======================================
        // 5. RESULTATS
        // ======================================

        $display("--------------------------------");
        $display("TEST STUFFING FINAL SUR CAN_TX");
        $display("--------------------------------");

        $display("ID = %h", can_id);
        $display("DLC = %0d", dlc);
        $display("DATA = %h", data);

        $display(
            "Bits echantillonnes = %0d",
            bit_count
        );

        $display(
            "Stuffing dynamique = %0d",
            dut.stuff_count
        );

        $display(
            "CRC-17 = %05h",
            dut.crc_final
        );

        $display(
            "Fichier : canfd_wire_bits.csv"
        );

        $display("--------------------------------");

        $fclose(file_out);

        $finish;

    end

    // ==========================================
    // 6. TIMEOUT DE SECURITE
    // ==========================================

    initial begin

        #200000;

        $display("ERREUR : TIMEOUT");

        $fclose(file_out);

        $finish;

    end

endmodule
