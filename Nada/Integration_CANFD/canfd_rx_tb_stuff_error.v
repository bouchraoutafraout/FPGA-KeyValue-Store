
`timescale 1ns/1ps

module canfd_rx_tb_stuff_error;

    // ==========================================
    // 1. PARAMETRES
    // ==========================================

    localparam integer CLK_FREQ = 100_000_000;
    localparam integer BIT_RATE = 1_000_000;

    // DLC = 8 : 22 bits d'en-tete + 64 bits DATA
    localparam integer PAYLOAD_BITS = 86;

    // Configuration validee dans le test DLC 8
    localparam integer FRAME_BITS = 124;

    // ==========================================
    // 2. SIGNAUX
    // ==========================================

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg start = 1'b0;

    reg [10:0] can_id = 11'h123;
    reg [63:0] data = 64'h123456789ABCDEF0;
    reg [3:0] dlc = 4'd8;

    always #5 clk = ~clk;

    // TX
    wire can_tx;
    wire tx_busy;
    wire tx_done;
    wire ack_error;

    // RX
    wire sample_bit;
    wire sample_valid;
    wire rx_busy;
    wire [6:0] bit_index;

    wire payload_bit;
    wire payload_valid;
    wire payload_done;
    wire [6:0] payload_count;
    wire [7:0] stuff_count;
    wire stuff_error;

    wire [10:0] rx_id;
    wire [3:0] rx_dlc;
    wire [63:0] rx_data;
    wire decode_done;

    wire [16:0] crc_calc;
    wire [16:0] crc_recu;
    wire [3:0] sbc_recu;
    wire fsb_error;
    wire crc_done;
    wire crc_ok;

    wire ack_drive_low;
    wire ack_sent;
    wire tail_error;
    wire frame_done;
    wire frame_valid;

    // ==========================================
    // 3. BUS CAN AVEC INJECTION
    // ==========================================

    reg inject_error = 1'b0;
    reg injected = 1'b0;

    wire normal_bus = can_tx & ~ack_drive_low;

    // Le bit de stuffing devrait etre oppose
    // aux cinq bits identiques precedents.
    //
    // Pendant l'injection, nous forc ons le bus
    // a conserver la meme valeur que le dernier bit.
    //
    // Cela cree une violation de bit stuffing.

    wire can_bus = inject_error ?
                   rx.last_bit :
                   normal_bus;

    // ==========================================
    // 4. INSTANCE TRANSMETTEUR
    // ==========================================

    canfd_tx #(
        .CLK_FREQ(CLK_FREQ)
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
    // 5. INSTANCE RECEPTEUR
    // ==========================================

    canfd_rx #(
        .CLK_FREQ(CLK_FREQ),
        .BIT_RATE(BIT_RATE),
        .FRAME_BITS(FRAME_BITS),
        .PAYLOAD_BITS(PAYLOAD_BITS)
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
    // 6. MEMORISATION DES EVENEMENTS
    // ==========================================

    reg seen_crc_done = 1'b0;
    reg seen_frame_done = 1'b0;
    reg seen_tx_done = 1'b0;
    reg seen_stuff_error = 1'b0;

    always @(posedge clk) begin
        if (rst) begin
            seen_crc_done <= 1'b0;
            seen_frame_done <= 1'b0;
            seen_tx_done <= 1'b0;
            seen_stuff_error <= 1'b0;
        end
        else begin
            if (crc_done)
                seen_crc_done <= 1'b1;

            if (frame_done)
                seen_frame_done <= 1'b1;

            if (tx_done)
                seen_tx_done <= 1'b1;

            if (stuff_error)
                seen_stuff_error <= 1'b1;
        end
    end

    // ==========================================
    // 7. INJECTION D'ERREUR STUFFING
    // ==========================================

    initial begin

        // Attendre la fin du reset
        wait (rst == 1'b0);

        // Attendre exactement cinq bits
        // identiques consecutifs dans le RX.
        //
        // Le bit suivant devra etre un
        // bit de stuffing de valeur opposee.

        wait (rx.run_count == 3'd5 &&
              payload_done == 1'b0 &&
              rx.busy == 1'b1);

        @(negedge clk);

        $display("");
        $display("==================================");
        $display("INJECTION ERREUR STUFFING");
        $display("==================================");

        $display("Temps injection : %0t", $time);
        $display("Run count       : %0d", rx.run_count);
        $display("Dernier bit     : %b", rx.last_bit);
        $display("Stuff count     : %0d", stuff_count);

        // Injection : forcer un sixieme bit
        // identique aux cinq precedents.

        inject_error = 1'b1;
        injected = 1'b1;

        $display("Injection activee");

        // Attendre le prochain echantillon
        // du RX, puis laisser le temps au
        // detecteur de traiter ce bit.

        @(posedge sample_valid);

        repeat (2) @(negedge clk);

        inject_error = 1'b0;

        $display("Injection terminee");
        $display("Temps fin       : %0t", $time);

    end

    // ==========================================
    // 8. SCENARIO PRINCIPAL
    // ==========================================

    initial begin

        $dumpfile("canfd_stuff_error.vcd");
        $dumpvars(0, canfd_rx_tb_stuff_error);

        // RESET
        repeat (5) @(negedge clk);
        rst = 1'b0;

        // ATTENTE
        repeat (5) @(negedge clk);

        // DEMARRER TRANSMISSION
        start = 1'b1;

        @(negedge clk);
        start = 1'b0;

        // Attendre la fin de trame cote RX
        wait (seen_frame_done);

        @(negedge clk);
        #1;

        // ======================================
        // RESULTATS
        // ======================================

        $display("");
        $display("==================================");
        $display("TEST ERREUR STUFFING - DLC 8");
        $display("==================================");

        $display("Injection effectuee : %b", injected);

        $display("ID recu             : 0x%03h", rx_id);
        $display("DLC recu            : %0d", rx_dlc);

        $display("DATA recue          : 0x%016h", rx_data);

        $display("");
        $display("Stuff count         : %0d", stuff_count);
        $display("Stuff error         : %b", stuff_error);
        $display("Stuff error vu      : %b", seen_stuff_error);

        $display("");
        $display("CRC calcule         : 0x%05h", crc_calc);
        $display("CRC recu            : 0x%05h", crc_recu);
        $display("CRC OK              : %b", crc_ok);

        $display("");
        $display("FSB error           : %b", fsb_error);
        $display("ACK sent            : %b", ack_sent);

        $display("Frame valid         : %b", frame_valid);

        // ======================================
        // VERIFICATION
        // ======================================

        $display("");
        $display("==================================");
        $display("RESULTAT TEST STUFFING");
        $display("==================================");

        if (injected == 1'b1 &&
            seen_stuff_error == 1'b1 &&
            stuff_error === 1'b1 &&
            seen_crc_done == 1'b1 &&
            crc_ok === 1'b0 &&
            frame_valid === 1'b0) begin

            $display("PASS : ERREUR STUFFING DETECTEE");

        end
        else begin

            $display("FAIL : TEST STUFFING");
        end

        $finish;
    end

    // ==========================================
    // 9. TIMEOUT DE SECURITE
    // ==========================================

    initial begin

        #250000;

        $display("");
        $display("==================================");
        $display("FAIL : TIMEOUT STUFF ERROR");
        $display("==================================");

        $display("Injection       : %b", injected);
        $display("Stuff error     : %b", stuff_error);
        $display("Stuff count     : %0d", stuff_count);
        $display("Payload count   : %0d", payload_count);
        $display("CRC done vu     : %b", seen_crc_done);
        $display("Frame done vu   : %b", seen_frame_done);
        $display("TX done vu      : %b", seen_tx_done);

        $finish;
    end

endmodule
