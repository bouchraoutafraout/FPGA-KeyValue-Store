
`timescale 1ns/1ps

module canfd_rx_tb_sbc_error;

    localparam integer CLK_FREQ = 100_000_000;
    localparam integer BIT_RATE = 1_000_000;
    localparam integer PAYLOAD_BITS = 86;
    localparam integer FRAME_BITS = 124;

    reg clk = 0;
    reg rst = 1;
    reg start = 0;

    reg [10:0] can_id = 11'h123;
    reg [63:0] data = 64'h123456789ABCDEF0;
    reg [3:0] dlc = 4'd8;

    always #5 clk = ~clk;

    // TX
    wire can_tx, tx_busy, tx_done, ack_error;

    // RX
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

    // ==========================================
    // INJECTION ERREUR FSB
    // ==========================================

    reg inject_error = 0;
    reg injected = 0;

    wire normal_bus = can_tx & ~ack_drive_low;

    // Un FSB doit etre oppose au bit precedent.
    // On impose au contraire le meme bit.
    wire can_bus = inject_error
                 ? rx.prev_wire_bit
                 : normal_bus;

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
    // MEMORISATION DES EVENEMENTS
    // ==========================================

    reg seen_crc_done = 0;
    reg seen_frame_done = 0;
    reg seen_fsb_error = 0;

    always @(posedge clk) begin
        if (rst) begin
            seen_crc_done <= 0;
            seen_frame_done <= 0;
            seen_fsb_error <= 0;
        end else begin
            if (crc_done)
                seen_crc_done <= 1;

            if (frame_done)
                seen_frame_done <= 1;

            if (fsb_error)
                seen_fsb_error <= 1;
        end
    end

    // ==========================================
    // INJECTION AU FSB D'INDICE 5
    // ==========================================

    initial begin

        wait (rst == 0);

        // Attendre le champ CRC.
        // L'indice 5 correspond a un FSB.
        wait (payload_done &&
              rx.crc_field_index == 5'd5 &&
              !crc_done);

        @(negedge clk);

        $display("");
        $display("==================================");
        $display("INJECTION ERREUR FSB");
        $display("==================================");

        $display("Temps : %0t", $time);
        $display("Index CRC : %0d",
                 rx.crc_field_index);
        $display("Bit precedent : %b",
                 rx.prev_wire_bit);

        // Forcer un bit interdit.
        inject_error = 1;
        injected = 1;

        $display("Injection activee");

        // Attendre l'echantillonnage FSB.
        wait (sample_valid &&
              rx.crc_field_index == 5'd5);

        repeat (2) @(negedge clk);

        inject_error = 0;

        $display("Injection terminee");
    end

    // ==========================================
    // SCENARIO PRINCIPAL
    // ==========================================

    initial begin

        $dumpfile("canfd_fsb_error.vcd");
        $dumpvars(0, canfd_rx_tb_sbc_error);

        repeat (5) @(negedge clk);
        rst = 0;

        repeat (5) @(negedge clk);
        start = 1;

        @(negedge clk);
        start = 0;

        wait (seen_frame_done);

        @(negedge clk);
        #1;

        $display("");
        $display("==================================");
        $display("TEST ERREUR FSB - DLC 8");
        $display("==================================");

        $display("Injection       : %b", injected);
        $display("ID              : 0x%03h", rx_id);
        $display("DLC             : %0d", rx_dlc);

        $display("SBC recu        : %04b", sbc_recu);
        $display("FSB error       : %b", fsb_error);
        $display("FSB error vu    : %b", seen_fsb_error);

        $display("CRC calcule     : 0x%05h", crc_calc);
        $display("CRC recu        : 0x%05h", crc_recu);
        $display("CRC OK          : %b", crc_ok);

        $display("Stuff error     : %b", stuff_error);
        $display("ACK sent        : %b", ack_sent);
        $display("Frame valid     : %b", frame_valid);

        $display("");
        $display("==================================");
        $display("RESULTAT TEST FSB");
        $display("==================================");

        if (injected === 1'b1 &&
            seen_fsb_error === 1'b1 &&
            fsb_error === 1'b1 &&
            seen_crc_done === 1'b1 &&
            crc_ok === 1'b0 &&
            frame_valid === 1'b0 &&
            ack_sent === 1'b0) begin

            $display("PASS : ERREUR FSB DETECTEE");

        end else begin

            $display("FAIL : TEST FSB");

        end

        $finish;
    end

    // ==========================================
    // TIMEOUT
    // ==========================================

    initial begin
        #250000;

        $display("");
        $display("FAIL : TIMEOUT FSB");
        $display("Injection    : %b", injected);
        $display("FSB error    : %b", fsb_error);
        $display("CRC done     : %b", seen_crc_done);
        $display("Frame done   : %b", seen_frame_done);

        $finish;
    end

endmodule
