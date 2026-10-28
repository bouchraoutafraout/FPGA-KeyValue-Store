
`timescale 1ns/1ps

module canfd_rx_tb_stuff_error;

    localparam integer CLK_FREQ = 100_000_000;
    localparam integer BIT_RATE = 1_000_000;
    localparam integer PAYLOAD_BITS = 86;
    localparam integer FRAME_BITS = 124;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg start = 1'b0;

    reg [10:0] can_id = 11'h123;
    reg [63:0] data = 64'h123456789ABCDEF0;
    reg [3:0] dlc = 4'd8;

    always #5 clk = ~clk;

    // ========================================
    // TRANSMETTEUR
    // ========================================

    wire can_tx;
    wire tx_busy;
    wire tx_done;
    wire ack_error;

    // ========================================
    // RECEPTEUR
    // ========================================

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

    // ========================================
    // BUS AVEC INJECTION D'ERREUR
    // ========================================

    reg inject_error = 1'b0;
    reg injected = 1'b0;

    wire normal_bus = can_tx & ~ack_drive_low;

    // Pendant l'injection, on impose le meme
    // bit que les cinq bits precedents.
    // Cela viole la regle du stuffing.
    wire can_bus = inject_error ?
                   rx.last_bit :
                   normal_bus;

    // ========================================
    // INSTANCE TX
    // ========================================

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

    // ========================================
    // INSTANCE RX
    // ========================================

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

    // ========================================
    // MEMORISER LES FIN DE TEST
    // ========================================

    reg seen_crc_done = 1'b0;
    reg seen_frame_done = 1'b0;
    reg seen_tx_done = 1'b0;

    always @(posedge clk) begin
        if (rst) begin
            seen_crc_done <= 0;
            seen_frame_done <= 0;
            seen_tx_done <= 0;
        end
        else begin
            if (crc_done)
                seen_crc_done <= 1;

            if (frame_done)
                seen_frame_done <= 1;

            if (tx_done)
                seen_tx_done <= 1;
        end
    end

    // ========================================
    // INJECTION CIBLEE DU STUFFING
    // ========================================

    initial begin

        // Attendre la fin du reset.
        wait (!rst);

        // Le RX vient de recevoir cinq bits
        // identiques et attend un stuffing.
        wait (rx.run_count == 3'd5 &&
              payload_done == 1'b0);

        @(negedge clk);

        $display("");
        $display("=================================");
        $display("INJECTION ERREUR STUFFING");
        $display("=================================");

        $display("Temps : %0t", $time);
        $display("Dernier bit : %b", rx.last_bit);
        $display("Run count : %0d", rx.run_count);
        $display("Stuff count avant : %0d", stuff_count);

        // Remplacer le stuffing par une valeur
        // identique aux cinq bits precedents.
        inject_error = 1'b1;
        injected = 1'b1;

        $display("Injection activee");

        // Attendre l'echantillonnage du
        // prochain bit par le recepteur.
        @(posedge sample_valid);

        // Conserver la corruption jusqu'a
        // ce que le RX traite cet echantillon.
        repeat (2) @(negedge clk);

        inject_error = 1'b0;

        $display("Injection terminee");
        $display("Temps : %0t", $time);

    end

    // ========================================
    // SCENARIO DE SIMULATION
    // ========================================

    initial begin

        $dumpfile("canfd_stuff_error.vcd");
        $dumpvars(0, canfd_rx_tb_stuff_error);

        repeat (5) @(negedge clk);
        rst = 1'b0;

        repeat (5) @(negedge clk);

        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        // Attendre la fin de reception.
        wait (seen_frame_done);

        @(negedge clk);
        #1;

        $display("");
        $display("=================================");
        $display("TEST ERREUR STUFFING - DLC 8");
        $display("=================================");

        $display("Injection       : %b", injected);
        $display("ID recu         : 0x%03h", rx_id);
        $display("DLC recu        : %0d", rx_dlc);
        $display("DATA recue      : 0x%016h", rx_data);

        $display("Stuff count     : %0d", stuff_count);
        $display("Stuff error     : %b", stuff_error);

        $display("CRC calcule     : 0x%05h", crc_calc);
        $display("CRC recu        : 0x%05h", crc_recu);
        $display("CRC OK          : %b", crc_ok);

        $display("Frame done      : %b", frame_done);
        $display("Frame valid     : %b", frame_valid);
        $display("FSB error       : %b", fsb_error);

        $display("");
        $display("=================================");
        $display("RESULTAT TEST STUFFING");
        $display("=================================");

        if (injected == 1'b1 &&
            stuff_error === 1'b1 &&
            seen_crc_done &&
            crc_ok === 1'b0 &&
            frame_valid === 1'b0) begin

            $display(
                "PASS : ERREUR STUFFING DETECTEE"
            );

        end
        else begin

            $display(
                "FAIL : TEST STUFFING"
            );

        end

        $finish;

    end

    // ========================================
    // TIMEOUT DE SECURITE
    // ========================================

    initial begin

        #250000;

        $display("");
        $display("FAIL : TIMEOUT STUFF ERROR");

        $display("Injection      : %b", injected);
        $display("Stuff error    : %b", stuff_error);
        $display("Payload count  : %0d", payload_count);
        $display("Stuff count    : %0d", stuff_count);
        $display("CRC done vu    : %b", seen_crc_done);
        $display("Frame done vu  : %b", seen_frame_done);
        $display("TX done vu     : %b", seen_tx_done);

        $finish;

    end

endmodule
