
`timescale 1ns/1ps

module canfd_rx_tb_crc_error;

    // ==========================================
    // CONFIGURATION
    // ==========================================

    localparam integer CLK_FREQ = 100_000_000;
    localparam integer BIT_RATE = 1_000_000;

    // Meme trame que le test DLC 8 valide.
    localparam integer PAYLOAD_BITS = 86;
    localparam integer FRAME_BITS = 124;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg start = 1'b0;

    reg [10:0] can_id = 11'h123;
    reg [63:0] data = 64'h123456789ABCDEF0;
    reg [3:0] dlc = 4'd8;

    always #5 clk = ~clk;

    // ==========================================
    // SIGNAUX TX
    // ==========================================

    wire can_tx;
    wire tx_busy;
    wire tx_done;
    wire ack_error;

    // ==========================================
    // SIGNAUX RX
    // ==========================================

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
    // INJECTION D'UNE ERREUR
    // ==========================================

    reg inject_error = 1'b0;

    // Bus normal :
    //   TX AND NOT(ACK)
    //
    // Pendant l'injection :
    //   inversion du bit TX sur le bus.

    wire can_bus =
        inject_error
        ? ~can_tx
        : (can_tx & ~ack_drive_low);

    // ==========================================
    // TRANSMETTEUR
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
    // RECEPTEUR
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
    // LOCALISATION DU CHAMP CRC
    // ==========================================

    reg seen_payload_done = 1'b0;
    reg seen_crc_done = 1'b0;
    reg seen_tx_done = 1'b0;

    integer crc_sample_count = 0;
    integer injections = 0;

    // Un bit est inverse dans le champ CRC.
    // On compte les echantillons apres payload_done.
    //
    // Les premiers bits correspondent notamment
    // au SBC et aux bits fixes de stuffing.
    //
    // Le 12e echantillon est cible pour toucher
    // un bit CRC plutot que le SBC.

    always @(negedge clk) begin
        if (rst) begin
            seen_payload_done = 1'b0;
            seen_crc_done = 1'b0;
            seen_tx_done = 1'b0;
            crc_sample_count = 0;
            inject_error = 1'b0;
            injections = 0;
        end
        else begin
            if (payload_done)
                seen_payload_done = 1'b1;

            if (crc_done)
                seen_crc_done = 1'b1;

            if (tx_done)
                seen_tx_done = 1'b1;

            if (seen_payload_done &&
                !seen_crc_done &&
                sample_valid) begin

                crc_sample_count = crc_sample_count + 1;

            end

            // Maintient le bit inverse entre
            // deux instants d'echantillonnage.
            //
            // Le numero de bit devra etre confirme
            // sur le VCD si le RX est desynchronise.

            if (seen_payload_done &&
                !seen_crc_done &&
                crc_sample_count == 11 &&
                !inject_error &&
                injections == 0) begin

                inject_error = 1'b1;
                injections = 1;

                $display(
                    "INJECTION CRC activee : t=%0t",
                    $time
                );
            end

            if (inject_error &&
                crc_sample_count >= 12) begin

                inject_error = 1'b0;

                $display(
                    "INJECTION CRC terminee : t=%0t",
                    $time
                );
            end
        end
    end

    // ==========================================
    // SCENARIO PRINCIPAL
    // ==========================================

    initial begin

        $dumpfile("canfd_crc_error.vcd");
        $dumpvars(0, canfd_rx_tb_crc_error);

        repeat (5) @(negedge clk);
        rst = 1'b0;

        repeat (5) @(negedge clk);

        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        // Attendre le diagnostic CRC du recepteur.
        wait (seen_crc_done);

        repeat (4) @(negedge clk);

        $display("");
        $display("======================================");
        $display("TEST INJECTION ERREUR CRC - DLC 8");
        $display("======================================");

        $display("ID recu         : 0x%03h", rx_id);
        $display("DLC recu        : %0d", rx_dlc);
        $display("DATA recue      : 0x%016h", rx_data);

        $display("");
        $display("Injection       : %0d", injections);
        $display("CRC TX original : 0x%05h", tx.crc_final);
        $display("CRC calcule RX  : 0x%05h", crc_calc);
        $display("CRC recu RX     : 0x%05h", crc_recu);

        $display("crc_done        : %b", crc_done);
        $display("crc_ok          : %b", crc_ok);
        $display("fsb_error       : %b", fsb_error);
        $display("stuff_error     : %b", stuff_error);
        $display("frame_valid     : %b", frame_valid);

        $display("");
        $display("======================================");
        $display("RESULTAT");
        $display("======================================");

        if (injections == 1 &&
            crc_calc !== crc_recu &&
            crc_ok === 1'b0 &&
            fsb_error === 1'b0) begin

            $display("PASS : ERREUR CRC DETECTEE");

        end
        else begin

            $display("FAIL : VERIFICATION CRC");
            $display("Analyser le fichier VCD.");
        end

        $finish;
    end

    // ==========================================
    // TIMEOUT
    // ==========================================

    initial begin
        #250000;

        $display("");
        $display("FAIL : TIMEOUT CRC ERROR");
        $display("Injection      : %0d", injections);
        $display("Echantillons   : %0d", crc_sample_count);
        $display("Payload termine: %b", seen_payload_done);
        $display("CRC termine    : %b", seen_crc_done);
        $display("TX termine     : %b", seen_tx_done);

        $finish;
    end

endmodule
