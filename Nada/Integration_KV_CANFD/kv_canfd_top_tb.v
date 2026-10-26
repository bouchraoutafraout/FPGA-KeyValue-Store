
`timescale 1ns/1ps

module kv_canfd_top_tb;

    // ============================================
    // 1. HORLOGE ET RESET
    // ============================================

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg start = 1'b0;

    always #5 clk = ~clk;

    // ============================================
    // 2. COMMANDE CREATE
    // ============================================

    // LEN = 07
    // CMD = 01 (CREATE)
    // KEY = 12345678
    // VALUE = 00AA

    localparam [63:0] REQUEST =
        64'h07011234567800AA;

    // ============================================
    // 3. SIGNAUX CAN-FD TX
    // ============================================

    wire can_tx;
    wire tx_busy;
    wire tx_done;
    wire tx_ack_error;

    // ============================================
    // 4. BUS CAN-FD
    // ============================================

    wire ack_drive_low;

    // Bus dominant = 0
    wire can_bus = can_tx & ~ack_drive_low;

    // ============================================
    // 5. SORTIES KEY-VALUE STORE
    // ============================================

    wire resp_valid;
    wire [7:0] resp_cmd;
    wire [7:0] resp_status;
    wire [15:0] resp_value;

    // ============================================
    // 6. DIAGNOSTIC RX
    // ============================================

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

    // ============================================
    // 7. VARIABLES DU TEST
    // ============================================

    integer errors = 0;

    reg seen_rx_done = 0;
    reg seen_tx_done = 0;
    reg seen_response = 0;
    reg seen_ck_done = 0;
    reg seen_crc_done = 0;
    reg seen_ack_sent = 0;

    reg saved_rx_valid = 0;

    reg [7:0] saved_cmd = 0;
    reg [7:0] saved_status = 0;
    reg [15:0] saved_value = 0;

    // ============================================
    // 8. CAN-FD TRANSMITTER : NADA
    // ============================================

    canfd_tx #(
        .CLK_FREQ(100_000_000)
    ) TX (
        .clk(clk),
        .rst(rst),
        .start(start),

        .can_id(11'h123),
        .data(REQUEST),
        .dlc(4'd8),

        .can_rx(can_bus),
        .can_tx(can_tx),

        .busy(tx_busy),
        .done(tx_done),
        .ack_error(tx_ack_error)
    );

    // ============================================
    // 9. INTEGRATION CAN-FD / KV STORE
    // ============================================

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

    // ============================================
    // 10. SURVEILLANCE DES EVENEMENTS
    // ============================================

    always @(posedge clk) begin

        if (rst) begin
            seen_rx_done <= 0;
            seen_tx_done <= 0;
            seen_response <= 0;
            seen_ck_done <= 0;
            seen_crc_done <= 0;
            seen_ack_sent <= 0;

            saved_rx_valid <= 0;
            saved_cmd <= 0;
            saved_status <= 0;
            saved_value <= 0;
        end
        else begin

            // Fin de transmission TX
            if (tx_done && !seen_tx_done) begin
                seen_tx_done <= 1;

                $display("");
                $display("[TX] Transmission terminee");
                $display("[TX] ACK error : %b",
                         tx_ack_error);
            end

            // Reception CRC terminee
            if (DUT.crc_done && !seen_crc_done) begin
                seen_crc_done <= 1;

                $display("");
                $display("[RX] Verification CRC terminee");
                $display("[RX] CRC OK : %b",
                         rx_crc_ok);
                $display("[RX] CRC calcule : 0x%05h",
                         DUT.crc_calc);
                $display("[RX] CRC recu : 0x%05h",
                         DUT.crc_recu);
            end

            // ACK envoye par RX
            if (DUT.ack_sent && !seen_ack_sent) begin
                seen_ack_sent <= 1;

                $display("");
                $display("[RX] ACK envoye");
            end

            // Fin de reception RX
            if (rx_frame_done && !seen_rx_done) begin
                seen_rx_done <= 1;
                saved_rx_valid <= rx_frame_valid;

                $display("");
                $display("[RX] Fin de trame detectee");
                $display("[RX] Frame valid : %b",
                         rx_frame_valid);
            end

            // Fin operation Cuckoo
            if (ck_done && !seen_ck_done) begin
                seen_ck_done <= 1;

                $display("");
                $display("[KV] Operation terminee");
                $display("[KV] Found : %b", ck_found);
                $display("[KV] Error : %b", ck_error);
            end

            // Reponse decodeur
            if (resp_valid && !seen_response) begin
                seen_response <= 1;

                saved_cmd <= resp_cmd;
                saved_status <= resp_status;
                saved_value <= resp_value;

                $display("");
                $display("[DECODER] Reponse disponible");
                $display("Commande : 0x%02h", resp_cmd);
                $display("Statut   : 0x%02h", resp_status);
                $display("Valeur   : 0x%04h", resp_value);
            end

        end
    end

    // ============================================
    // 11. TACHE DIAGNOSTIC
    // ============================================

    task show_diagnostic;
    begin

        $display("");
        $display("====================================");
        $display("DIAGNOSTIC CAN-FD");
        $display("====================================");

        $display("TX done          : %b",
                 seen_tx_done);

        $display("TX busy          : %b",
                 tx_busy);

        $display("TX ACK error     : %b",
                 tx_ack_error);

        $display("");

        $display("RX busy          : %b",
                 DUT.rx_busy);

        $display("RX bit_index     : %0d",
                 DUT.bit_index);

        $display("RX payload_count : %0d",
                 DUT.payload_count);

        $display("RX payload_done  : %b",
                 DUT.payload_done);

        $display("RX stuff_count   : %0d",
                 DUT.stuff_count);

        $display("RX stuff_error   : %b",
                 rx_stuff_error);

        $display("");

        $display("RX crc_done      : %b",
                 DUT.crc_done);

        $display("RX crc_ok        : %b",
                 rx_crc_ok);

        $display("RX crc_index     : %0d",
                 DUT.RX.crc_field_index);

        $display("RX fsb_error     : %b",
                 rx_fsb_error);

        $display("");

        $display("RX tail_index    : %0d",
                 DUT.RX.tail_rx_index);

        $display("RX tail_error    : %b",
                 DUT.tail_error);

        $display("RX ack_sent      : %b",
                 DUT.ack_sent);

        $display("RX frame_done    : %b",
                 rx_frame_done);

        $display("RX frame_valid   : %b",
                 rx_frame_valid);

        $display("RX done vu       : %b",
                 seen_rx_done);

        $display("");

        $display("Adapter busy     : %b",
                 adapter_busy);

        $display("Decoder state    : %0d",
                 DUT.DEC.dbg_state);

        $display("Cuckoo busy      : %b",
                 ck_busy);

        $display("Cuckoo done vu   : %b",
                 seen_ck_done);

        $display("Reponse vue      : %b",
                 seen_response);

        $display("====================================");

    end
    endtask

    // ============================================
    // 12. SCENARIO PRINCIPAL
    // ============================================

    initial begin

        $dumpfile("kv_canfd_debug.vcd");
        $dumpvars(0, kv_canfd_top_tb);

        // RESET
        repeat (5) @(negedge clk);
        rst = 0;

        repeat (5) @(negedge clk);

        // DEMARRER LE TX
        start = 1;

        @(negedge clk);
        start = 0;

        $display("");
        $display("====================================");
        $display("DEBUT : CAN-FD -> KEY-VALUE STORE");
        $display("====================================");

        $display("ID   : 0x123");
        $display("DLC  : 8");
        $display("DATA : 0x%016h", REQUEST);

        // Attendre la reponse et fin TX
        wait (seen_response && seen_tx_done);

        repeat (3) @(negedge clk);

        show_diagnostic();

        $display("");
        $display("====================================");
        $display("RESULTAT INTEGRATION");
        $display("====================================");

        if (!seen_rx_done)
            errors = errors + 1;

        if (!saved_rx_valid)
            errors = errors + 1;

        if (!seen_tx_done)
            errors = errors + 1;

        if (tx_ack_error !== 1'b0)
            errors = errors + 1;

        if (!seen_ck_done)
            errors = errors + 1;

        if (!seen_response)
            errors = errors + 1;

        if (saved_cmd !== 8'h01)
            errors = errors + 1;

        if (saved_status !== 8'h00)
            errors = errors + 1;

        if (saved_value !== 16'h0000)
            errors = errors + 1;

        $display("Erreurs : %0d", errors);

        if (errors == 0)
            $display(
                "PASS : CAN-FD -> CREATE -> CUCKOO"
            );
        else
            $display(
                "FAIL : INTEGRATION CAN-FD / CUCKOO"
            );

        $finish;
    end

    // ============================================
    // 13. TIMEOUT DE SECURITE
    // ============================================

    initial begin

        #250000;

        $display("");
        $display("====================================");
        $display("FAIL : TIMEOUT INTEGRATION");
        $display("====================================");

        show_diagnostic();

        $finish;
    end

endmodule
