
`timescale 1ns/1ps

module canfd_multiframe_tb;

    reg clk = 0;
    reg rst = 1;
    reg start = 0;

    reg [10:0] can_id = 0;
    reg [63:0] data = 0;
    reg [3:0] dlc = 0;

    wire can_tx;
    wire busy;
    wire done;
    wire ack_error;

    // Modele simplifie d'un recepteur CAN :
    // acquittement dominant durant la fenetre ACK.
    wire can_rx;

    assign can_rx =
        (dut.state == 4'd7 &&
         (dut.tail_index == 4'd1 ||
          dut.tail_index == 4'd2))
        ? 1'b0 : can_tx;

    integer errors = 0;
    integer frames_ok = 0;
    integer ticks;
    integer done_count = 0;

    // Horloge 100 MHz : periode de 10 ns
    always #5 clk = ~clk;

    // =====================================
    // MODULE CAN FD A TESTER
    // =====================================

    canfd_tx #(
        .CLK_FREQ(100_000_000)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .can_id(can_id),
        .data(data),
        .dlc(dlc),
        .can_rx(can_rx),
        .can_tx(can_tx),
        .busy(busy),
        .done(done),
        .ack_error(ack_error)
    );

    // =====================================
    // COMPTEUR DES TRANSMISSIONS TERMINEES
    // =====================================

    always @(posedge clk) begin
        if (rst)
            done_count <= 0;
        else if (done)
            done_count <= done_count + 1;
    end

    // =====================================
    // TEST D'UNE TRAME
    // =====================================

    task test_frame;

        input [10:0] test_id;
        input [63:0] test_data;
        input [3:0] test_dlc;
        input check_crc;

        integer previous_done;
        integer start_done_count;

        begin

            $display("");
            $display("================================");
            $display("TEST ID=%h DLC=%0d DATA=%h",
                     test_id, test_dlc, test_data);

            // Attendre que le TX soit disponible
            wait(busy == 1'b0);

            @(negedge clk);

            can_id = test_id;
            data = test_data;
            dlc = test_dlc;

            start_done_count = done_count;

            // Demander une transmission
            start = 1'b1;

            @(negedge clk);
            start = 1'b0;

            // =====================================
            // VERIFIER BUSY
            // =====================================

            if (busy !== 1'b1) begin

                $display("FAIL : busy absent au depart");
                errors = errors + 1;

            end
            else begin

                $display("PASS : busy actif");

            end

            // =====================================
            // TEST START PENDANT BUSY
            // =====================================

            repeat (10) @(negedge clk);

            start = 1'b1;

            @(negedge clk);
            start = 1'b0;

            // =====================================
            // ATTENDRE LA FIN DE TRANSMISSION
            // =====================================

            ticks = 0;

            while (busy === 1'b1 && ticks < 25000) begin

                @(negedge clk);
                ticks = ticks + 1;

            end

            if (ticks >= 25000) begin

                $display("FAIL : timeout transmission");
                errors = errors + 1;

            end
            else if (done !== 1'b1) begin

                $display("FAIL : done absent");
                errors = errors + 1;

            end
            else begin

                $display("PASS : transmission terminee");
                frames_ok = frames_ok + 1;

            end

            // =====================================
            // VERIFIER L'ETAT FINAL DU BUS
            // =====================================

            if (can_tx !== 1'b1) begin

                $display("FAIL : can_tx non recessif en fin");
                errors = errors + 1;

            end
            else begin

                $display("PASS : can_tx recessif en fin");

            end

            // =====================================
            // VERIFICATION CRC DE REFERENCE
            // =====================================

            // Reference interne pour :
            // ID = 0x123
            // DLC = 2
            // DATA = A5C3
            //
            // CRC apres traitement SBC = 0x1BBF9
            // Valeur a confronter ensuite a un
            // modele independant conforme CAN-FD.

            $display("CRC-17 calcule = %05h", dut.crc_final);

            if (check_crc) begin

                if (dut.crc_final !== 17'h1BBF9) begin

                    $display(
                        "FAIL : CRC attendu 1BBF9, obtenu %h",
                        dut.crc_final
                    );

                    errors = errors + 1;

                end
                else begin

                    $display("PASS : CRC-17 = 1BBF9");

                end

            end

            // =====================================
            // VERIFICATION ACK
            // =====================================

            if (ack_error !== 1'b0) begin

                $display("FAIL : ACK non recu");
                errors = errors + 1;

            end
            else begin

                $display("PASS : ACK recu");

            end

            // =====================================
            // ATTENDRE LA FIN DE L'IMPULSION DONE
            // =====================================

            wait(done == 1'b0);

            @(negedge clk);

            // Verifier une seule transmission terminee
            if (done_count != start_done_count + 1) begin

                $display(
                    "FAIL : nombre de done incorrect (%0d -> %0d)",
                    start_done_count, done_count
                );

                errors = errors + 1;

            end
            else begin

                $display("PASS : une seule impulsion done");

            end

            previous_done = done_count;

            // =====================================
            // VERIFIER QU'AUCUNE NOUVELLE
            // TRANSMISSION N'EST DECLENCHEE
            // =====================================

            repeat (150) @(negedge clk);

            if (busy !== 1'b0) begin

                $display("FAIL : busy reste actif");
                errors = errors + 1;

            end
            else begin

                $display("PASS : busy reste a 0");

            end

            if (done_count != previous_done) begin

                $display("FAIL : transmission supplementaire");
                errors = errors + 1;

            end
            else begin

                $display("PASS : aucune transmission supplementaire");

            end

        end

    endtask

    // =====================================
    // SCENARIO DE TEST
    // =====================================

    initial begin

        $dumpfile("canfd_multiframe.vcd");
        $dumpvars(0, canfd_multiframe_tb);

        rst = 1'b1;
        start = 1'b0;

        repeat (5) @(negedge clk);

        rst = 1'b0;

        // ---------------------------------
        // TEST 1 : 0 OCTET
        // ---------------------------------

        test_frame(
            11'h100,
            64'h0000000000000000,
            4'd0,
            1'b0
        );

        // ---------------------------------
        // TEST 2 : 2 OCTETS
        // ---------------------------------

        test_frame(
            11'h123,
            64'hA5C3000000000000,
            4'd2,
            1'b1
        );

        // ---------------------------------
        // TEST 3 : 8 OCTETS
        // ---------------------------------

        test_frame(
            11'h456,
            64'h123456789ABCDEF0,
            4'd8,
            1'b0
        );

        // =====================================
        // RESULTATS
        // =====================================

        $display("");
        $display("================================");
        $display("Trames terminees : %0d/3", frames_ok);
        $display("Erreurs           : %0d", errors);
        $display("================================");

        if (errors == 0 && frames_ok == 3) begin

            $display("=== TEST MULTIFRAME REUSSI ===");

        end
        else begin

            $display("=== TEST MULTIFRAME ECHEC ===");

        end

        $finish;

    end

    // =====================================
    // TIMEOUT GLOBAL
    // =====================================

    initial begin

        #1000000;

        $display("FAIL : TIMEOUT GLOBAL");
        $finish;

    end

endmodule
