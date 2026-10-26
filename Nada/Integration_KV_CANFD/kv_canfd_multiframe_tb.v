
`timescale 1ns/1ps

module kv_canfd_multiframe_tb;

    // ========================================
    // 1. CLOCK ET RESET
    // ========================================

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg start = 1'b0;

    always #5 clk = ~clk;

    // ========================================
    // 2. CAN-FD TRANSMITTER
    // ========================================

    reg [63:0] tx_data = 64'd0;

    wire can_tx;
    wire tx_busy;
    wire tx_done;
    wire tx_ack_error;

    wire ack_drive_low;
    wire can_bus;

    assign can_bus = can_tx & ~ack_drive_low;

    canfd_tx #(
        .CLK_FREQ(100_000_000)
    ) TX (
        .clk(clk),
        .rst(rst),
        .start(start),
        .can_id(11'h123),
        .data(tx_data),
        .dlc(4'd8),
        .can_rx(can_bus),
        .can_tx(can_tx),
        .busy(tx_busy),
        .done(tx_done),
        .ack_error(tx_ack_error)
    );

    // ========================================
    // 3. KEY-VALUE CAN-FD TOP
    // ========================================

    wire resp_valid;
    wire [7:0] resp_cmd;
    wire [7:0] resp_status;
    wire [15:0] resp_value;

    wire rx_frame_done;
    wire rx_frame_valid;
    wire rx_crc_ok;
    wire rx_stuff_error;
    wire rx_fsb_error;

    wire adapter_busy;

    wire ck_busy;
    wire ck_done;
    wire ck_found;
    wire ck_error;

    kv_canfd_top DUT (
        .clk(clk),
        .rst(rst),

        .can_rx(can_bus),
        .ack_drive_low(ack_drive_low),

        .resp_valid(resp_valid),
        .resp_ready(1'b1),
        .resp_cmd(resp_cmd),
        .resp_status(resp_status),
        .resp_value(resp_value),

        .rx_frame_done(rx_frame_done),
        .rx_frame_valid(rx_frame_valid),
        .rx_crc_ok(rx_crc_ok),
        .rx_stuff_error(rx_stuff_error),
        .rx_fsb_error(rx_fsb_error),

        .adapter_busy(adapter_busy),

        .ck_busy(ck_busy),
        .ck_done(ck_done),
        .ck_found(ck_found),
        .ck_error(ck_error)
    );

    // ========================================
    // 4. MONITEUR DES EVENEMENTS
    // ========================================

    integer tx_count = 0;
    integer rx_count = 0;
    integer response_count = 0;
    integer storage_count = 0;
    integer errors = 0;

    reg old_tx_done = 1'b0;
    reg old_rx_done = 1'b0;
    reg old_response = 1'b0;
    reg old_storage_done = 1'b0;

    reg [7:0] last_cmd = 0;
    reg [7:0] last_status = 0;
    reg [15:0] last_value = 0;
    reg last_rx_valid = 0;
    reg last_ack_error = 0;

    always @(posedge clk) begin
        if (rst) begin
            tx_count <= 0;
            rx_count <= 0;
            response_count <= 0;
            storage_count <= 0;

            old_tx_done <= 0;
            old_rx_done <= 0;
            old_response <= 0;
            old_storage_done <= 0;

            last_cmd <= 0;
            last_status <= 0;
            last_value <= 0;
            last_rx_valid <= 0;
            last_ack_error <= 0;

        end else begin
            old_tx_done <= tx_done;
            old_rx_done <= rx_frame_done;
            old_response <= resp_valid;
            old_storage_done <= ck_done;

            if (tx_done && !old_tx_done) begin
                tx_count <= tx_count + 1;
                last_ack_error <= tx_ack_error;

                $display("[TX] Trame terminee, ACK error=%b",
                         tx_ack_error);
            end

            if (rx_frame_done && !old_rx_done) begin
                rx_count <= rx_count + 1;
                last_rx_valid <= rx_frame_valid;

                $display("[RX] Trame terminee, valid=%b, CRC=%b",
                         rx_frame_valid, rx_crc_ok);
            end

            if (ck_done && !old_storage_done) begin
                storage_count <= storage_count + 1;

                $display("[CUCKOO] Done, found=%b, error=%b",
                         ck_found, ck_error);
            end

            if (resp_valid && !old_response) begin
                response_count <= response_count + 1;

                last_cmd <= resp_cmd;
                last_status <= resp_status;
                last_value <= resp_value;

                $display(
                    "[RESPONSE] CMD=%02h STATUS=%02h VALUE=%04h",
                    resp_cmd, resp_status, resp_value
                );
            end
        end
    end

    // ========================================
    // 5. ENVOYER UNE COMMANDE
    // ========================================

    task send_command;
        input [63:0] packet;
        input [7:0] expected_cmd;
        input check_value;
        input [15:0] expected_value;

        integer old_tx_count;
        integer old_rx_count;
        integer old_resp_count;
        integer cycles;

        begin
            // Attendre que la transmission precedente
            // soit terminee.
            while (tx_busy || DUT.rx_busy || adapter_busy)
                @(negedge clk);

            old_tx_count = tx_count;
            old_rx_count = rx_count;
            old_resp_count = response_count;

            $display("");
            $display("----------------------------------------");
            $display("ENVOI CAN-FD : %016h", packet);
            $display("----------------------------------------");

            // Impulsion START d'un cycle.
            @(negedge clk);
            tx_data = packet;
            start = 1'b1;

            @(negedge clk);
            start = 1'b0;

            // Attendre TX + RX + reponse,
            // avec un timeout de securite.
            cycles = 0;

            while (
                ((tx_count == old_tx_count) ||
                 (rx_count == old_rx_count) ||
                 (response_count == old_resp_count))
                && cycles < 40000
            ) begin
                @(negedge clk);
                cycles = cycles + 1;
            end

            if (cycles >= 40000) begin
                errors = errors + 1;
                $display("FAIL : TIMEOUT");
                $display("TX count=%0d RX count=%0d RESP count=%0d",
                         tx_count, rx_count, response_count);
            end else begin
                if (!last_rx_valid) begin
                    errors = errors + 1;
                    $display("FAIL : RX FRAME INVALIDE");
                end

                if (last_ack_error) begin
                    errors = errors + 1;
                    $display("FAIL : ACK ERROR");
                end

                if (last_cmd !== expected_cmd) begin
                    errors = errors + 1;
                    $display(
                        "FAIL : CMD attendue=%02h recue=%02h",
                        expected_cmd, last_cmd
                    );
                end

                if (last_status !== 8'h00) begin
                    errors = errors + 1;
                    $display(
                        "FAIL : STATUS=%02h",
                        last_status
                    );
                end

                if (check_value &&
                    last_value !== expected_value) begin
                    errors = errors + 1;
                    $display(
                        "FAIL : VALUE attendue=%04h recue=%04h",
                        expected_value, last_value
                    );
                end

                $display("Transaction terminee.");
            end

            // Intervalle entre deux trames.
            #20000;
        end
    endtask

    // ========================================
    // 6. SEQUENCE MULTITRAMES
    // ========================================

    initial begin
        $dumpfile("kv_canfd_multiframe.vcd");
        $dumpvars(0, kv_canfd_multiframe_tb);

        $display("");
        $display("========================================");
        $display("TEST CAN-FD -> KEY VALUE MULTIFRAME");
        $display("========================================");

        repeat (20) @(negedge clk);
        rst = 1'b0;

        repeat (20) @(negedge clk);

        // CREATE
        // LEN=07, CMD=01
        // KEY=12345678, VALUE=00AA
        send_command(
            64'h07011234567800AA,
            8'h01,
            1'b0,
            16'h0000
        );

        // SEARCH
        // LEN=05, CMD=02
        // KEY=12345678
        // Deux octets de padding pour DLC=8
        send_command(
            64'h0502123456780000,
            8'h02,
            1'b1,
            16'h00AA
        );

        // TRANSFER
        // LEN=07, CMD=03
        // KEY=12345678, VALUE=0055
        send_command(
            64'h0703123456780055,
            8'h03,
            1'b0,
            16'h0000
        );

        // SEARCH APRES TRANSFER
        send_command(
            64'h0502123456780000,
            8'h02,
            1'b1,
            16'h0055
        );

        $display("");
        $display("========================================");
        $display("RESULTAT FINAL MULTIFRAME");
        $display("========================================");

        $display("TX frames     : %0d", tx_count);
        $display("RX frames     : %0d", rx_count);
        $display("Cuckoo done   : %0d", storage_count);
        $display("Responses     : %0d", response_count);
        $display("Errors        : %0d", errors);

        if (
            errors == 0 &&
            tx_count == 4 &&
            rx_count == 4 &&
            response_count == 4
        )
            $display("PASS : MULTIFRAME CAN-FD -> CUCKOO");
        else
            $display("FAIL : MULTIFRAME");

        $finish;
    end

    // Timeout global de protection
    initial begin
        #2000000;
        $display("FAIL : TIMEOUT GLOBAL");
        $finish;
    end

endmodule
