
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
    wire ack_error;

    // Simulation du bus CAN :
    // Un recepteur acquitte pendant le ACK slot.
    wire can_rx;

    assign can_rx =
    (dut.state == 4'd7 &&
     (dut.tail_index == 4'd1 ||
      dut.tail_index == 4'd2))
    ? 1'b0 : can_tx;

    integer errors = 0;
    integer useful_bits = 0;
    integer dynamic_stuff = 0;
    integer crc_bits = 0;
    integer tail_bits = 0;

    // CRC attendu pour ce vecteur, apres traitement du SBC 0011
    reg [16:0] expected_crc = 17'h1BBF9;

    // Horloge 100 MHz : periode 10 ns
    always #5 clk = ~clk;

    // =====================================
    // MODULE CAN FD TX
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
    // COMPTEURS STUFFING ET CRC
    // =====================================

    always @(negedge clk) begin

        if (!rst) begin

            if (dut.out_valid &&
                (dut.state == 4'd2 ||
                 dut.state == 4'd3)) begin

                if (dut.out_is_stuff)
                    dynamic_stuff = dynamic_stuff + 1;
                else
                    useful_bits = useful_bits + 1;

            end

            // CRC_SEND = 4'd6
            if (dut.crc_valid &&
                dut.state == 4'd6) begin

                crc_bits = crc_bits + 1;

            end

        end
    end

    // =====================================
    // VERIFICATION DE LA FIN DE TRAME
    // =====================================

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

        rst = 1;
        start = 0;

        repeat (5) @(negedge clk);

        rst = 0;

        repeat (3) @(negedge clk);

        // Demarrage de la transmission
        start = 1;

        @(negedge clk);
        start = 0;

        // Attendre la fin de la trame
        wait(done == 1'b1);

        @(negedge clk);

        // =====================================
        // RESULTATS
        // =====================================

        $display("--------------------------------");
        $display("Bits utiles       : %0d", useful_bits);
        $display("Stuff dynamiques  : %0d", dynamic_stuff);
        $display("Bits CRC field    : %0d", crc_bits);
        $display("Bits fin de trame : %0d", tail_bits);
        $display("CRC-17            : %h", dut.crc_final);
        $display("ACK error         : %b", ack_error);
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

        // Verification du CRC-17
        if (dut.crc_final !== expected_crc) begin
            $display("FAIL : CRC-17 incorrect");
            errors = errors + 1;
        end

        // Verification de l'ACK
        if (ack_error !== 1'b0) begin
            $display("FAIL : ACK non recu");
            errors = errors + 1;
        end else begin
            $display("PASS : ACK recu");
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

    // Diagnostic du moment d'echantillonnage ACK
    always @(negedge clk) begin
        if (!rst &&
            dut.ack_sampling &&
            dut.ack_counter == dut.HALF_BIT_CLKS - 1) begin

            $display(
                "DEBUG ACK : can_rx=%b, can_rx_sync=%b, tail_index=%0d",
                can_rx, dut.can_rx_sync, dut.tail_index
            );
        end
    end
always @(negedge clk) begin
    if (!rst && dut.crc_en) begin
        $display(
            "DEBUG CRC : state=%0d | bit=%b | crc=%h",
            dut.state,
            dut.crc_din,
            dut.crc_value
        );
    end
end
always @(negedge clk) begin
    if (!rst && dut.state == 4'd4) begin
        $display(
            "DEBUG SBC : index=%0d | sbc=%b | bit=%b",
            dut.sbc_index,
            dut.sbc_final,
            dut.crc_din
        );
    end
end
endmodule
