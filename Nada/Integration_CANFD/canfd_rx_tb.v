
`timescale 1ns/1ps

module canfd_rx_tb;

    // ==========================================
    // 1. SIGNAUX DE SIMULATION
    // ==========================================

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg start = 1'b0;

    reg [10:0] can_id = 11'h123;
    reg [63:0] data = 64'hA51F000000000000;
    reg [3:0] dlc = 4'd2;

    wire can_tx, tx_busy, tx_done, ack_error;

    wire sample_bit, sample_valid, rx_busy;
    wire [6:0] bit_index;

    wire payload_bit, payload_valid, payload_done;
    wire [6:0] payload_count;
    wire [7:0] stuff_count;
    wire stuff_error;

    wire [10:0] rx_id;
    wire [3:0] rx_dlc;
    wire [63:0] rx_data;
    wire decode_done;

    wire [16:0] crc_calc, crc_recu;
    wire [3:0] sbc_recu;
    wire fsb_error, crc_done, crc_ok;

    wire ack_drive_low, ack_sent;
    wire tail_error, frame_done, frame_valid;

    // Bus CAN logique : dominant = 0
    wire can_bus = can_tx & ~ack_drive_low;

    integer ack_low_cycles = 0;
    integer errors = 0;

    // ==========================================
    // 2. HORLOGE 100 MHz
    // ==========================================

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst && ack_drive_low)
            ack_low_cycles = ack_low_cycles + 1;
    end

    // ==========================================
    // 3. TRANSMETTEUR DE NADA
    // ==========================================

    canfd_tx #(
        .CLK_FREQ(100_000_000)
    ) tx (
        .clk(clk),
        .rst(rst),
        .start(start),
        .can_id(can_id),
        .data(data),
        .dlc(dlc),
        .can_rx(can_bus),
        .can_tx(can_tx),
        .busy(tx_busy),
        .done(tx_done),
        .ack_error(ack_error)
    );

    // ==========================================
    // 4. RECEPTEUR DE BOUCHRA
    // ==========================================

    canfd_rx #(
        .CLK_FREQ(100_000_000),
        .BIT_RATE(1_000_000),
        .FRAME_BITS(77),
        .PAYLOAD_BITS(38)
    ) rx (
        .clk(clk),
        .rst(rst),
        .can_rx(can_bus),

        .sample_bit(sample_bit),
        .sample_valid(sample_valid),
        .busy(rx_busy),
        .bit_index(bit_index),

        .payload_bit(payload_bit),
        .payload_valid(payload_valid),
        .payload_count(payload_count),
        .stuff_count(stuff_count),
        .stuff_error(stuff_error),
        .payload_done(payload_done),

        .rx_id(rx_id),
        .rx_dlc(rx_dlc),
        .rx_data(rx_data),
        .decode_done(decode_done),

        .crc_calc(crc_calc),
        .crc_recu(crc_recu),
        .sbc_recu(sbc_recu),
        .fsb_error(fsb_error),
        .crc_done(crc_done),
        .crc_ok(crc_ok),

        .ack_drive_low(ack_drive_low),
        .ack_sent(ack_sent),
        .tail_error(tail_error),
        .frame_done(frame_done),
        .frame_valid(frame_valid)
    );

    // ==========================================
    // 5. COLLECTE DES DONNEES UTILES
    // ==========================================

    reg [37:0] bits_recus = 38'd0;
    integer nb_bits = 0;

    localparam [37:0] BITS_ATTENDUS = {
        1'b0,
        11'h123,
        6'b101000,
        4'd2,
        16'hA51F
    };

    always @(negedge clk) begin
        if (rst) begin
            bits_recus = 38'd0;
            nb_bits = 0;
        end
        else if (payload_valid) begin
            bits_recus = {bits_recus[36:0], payload_bit};
            nb_bits = nb_bits + 1;
        end
    end

    // ==========================================
    // 6. ENREGISTREMENT DES EVENEMENTS
    // ==========================================

    // Memoriser les impulsions pour ne pas les manquer.
    reg seen_decode_done = 0;
    reg seen_crc_done = 0;
    reg seen_frame_done = 0;
    reg seen_tx_done = 0;

    always @(posedge clk) begin
        if (rst) begin
            seen_decode_done <= 0;
            seen_crc_done <= 0;
            seen_frame_done <= 0;
            seen_tx_done <= 0;
        end
        else begin
            if (decode_done)
                seen_decode_done <= 1;

            if (crc_done)
                seen_crc_done <= 1;

            if (frame_done)
                seen_frame_done <= 1;

            if (tx_done)
                seen_tx_done <= 1;
        end
    end

    // ==========================================
    // 7. SCENARIO PRINCIPAL
    // ==========================================

    initial begin

        $dumpfile("canfd_rx.vcd");
        $dumpvars(0, canfd_rx_tb);

        repeat (5) @(negedge clk);
        rst = 1'b0;

        repeat (5) @(negedge clk);

        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        // Attendre la fin TX et RX avec indicateurs memorises.
        wait (seen_frame_done && seen_tx_done);

        @(negedge clk);
        #1;

        // ======================================
        // TEST 1 : DESTUFFING
        // ======================================

        $display("");
        $display("==================================");
        $display("TEST DESTUFFING NADA -> BOUCHRA");
        $display("==================================");

        $display("Bits utiles recus   : %0d", nb_bits);
        $display("Bits utiles attendus: 38");

        $display("Stuffing retire     : %0d", stuff_count);
        $display("Stuffing attendu    : 2");

        $display("Erreur stuffing     : %b", stuff_error);

        $display("Payload recu        : %038b", bits_recus);
        $display("Payload attendu     : %038b", BITS_ATTENDUS);

        if (nb_bits == 38 &&
            payload_count == 38 &&
            stuff_count == 2 &&
            stuff_error === 1'b0 &&
            bits_recus === BITS_ATTENDUS)
            $display("PASS : destuffing et payload");
        else begin
            $display("FAIL : destuffing ou payload");
            errors = errors + 1;
        end

        // ======================================
        // TEST 2 : DECODAGE
        // ======================================

        $display("");
        $display("==================================");
        $display("TEST DECODAGE ID / DLC / DATA");
        $display("==================================");

        $display("ID recu   : 0x%03h", rx_id);
        $display("DLC recu  : %0d", rx_dlc);
        $display("DATA recue: 0x%016h", rx_data);

        if (seen_decode_done &&
            rx_id === 11'h123 &&
            rx_dlc === 4'd2 &&
            rx_data === 64'h000000000000A51F)
            $display("PASS : decodage ID, DLC et DATA");
        else begin
            $display("FAIL : decodage ID, DLC ou DATA");
            errors = errors + 1;
        end

        // ======================================
        // TEST 3 : CRC-17
        // ======================================

        $display("");
        $display("==================================");
        $display("TEST CRC-17 ET SBC");
        $display("==================================");

        $display("SBC recu    : %04b", sbc_recu);
        $display("SBC attendu : 0110");

        $display("CRC calcule : 0x%05h", crc_calc);
        $display("CRC recu    : 0x%05h", crc_recu);
        $display("CRC attendu : 0x1D72F");

        $display("Erreur FSB  : %b", fsb_error);
        $display("CRC valide  : %b", crc_ok);

        if (seen_crc_done &&
            sbc_recu === 4'b0110 &&
            crc_calc === 17'h1D72F &&
            crc_recu === 17'h1D72F &&
            fsb_error === 1'b0 &&
            crc_ok === 1'b1)
            $display("PASS : CRC-17, SBC et FSB");
        else begin
            $display("FAIL : CRC-17, SBC ou FSB");
            errors = errors + 1;
        end

        // ======================================
        // TEST 4 : ACK ET FIN DE TRAME
        // ======================================

        $display("");
        $display("==================================");
        $display("TEST ACK ET FIN DE TRAME");
        $display("==================================");

        $display("ACK envoye      : %b", ack_sent);
        $display("ACK erreur TX   : %b", ack_error);
        $display("Duree ACK (clk) : %0d", ack_low_cycles);
        $display("Erreur fin trame: %b", tail_error);
        $display("Trame valide    : %b", frame_valid);

        if (ack_sent === 1'b1 &&
            ack_error === 1'b0 &&
            ack_low_cycles == 100 &&
            tail_error === 1'b0 &&
            frame_valid === 1'b1 &&
            seen_frame_done &&
            seen_tx_done)
            $display("PASS : ACK et fin de trame");
        else begin
            $display("FAIL : ACK ou fin de trame");
            errors = errors + 1;
        end

        // ======================================
        // 8. RESULTAT GLOBAL
        // ======================================

        $display("");
        $display("==================================");
        $display("RESULTAT GLOBAL INTEGRATION CANFD");
        $display("==================================");

        $display("Erreurs : %0d", errors);

        if (errors == 0)
            $display("=== TEST TX -> RX REUSSI ===");
        else
            $display("=== TEST TX -> RX ECHEC ===");

        $finish;

    end

    // ==========================================
    // 9. TIMEOUT DE SECURITE
    // ==========================================

    initial begin
        #150000;

        $display("");
        $display("FAIL : TIMEOUT TX -> RX");

        $display("decode_done vu : %b", seen_decode_done);
        $display("crc_done vu    : %b", seen_crc_done);
        $display("frame_done vu  : %b", seen_frame_done);
        $display("tx_done vu     : %b", seen_tx_done);

        $display("CRC valide     : %b", crc_ok);
        $display("Trame valide   : %b", frame_valid);

        $finish;
    end

endmodule
