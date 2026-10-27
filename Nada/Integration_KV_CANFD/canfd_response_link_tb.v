`timescale 1ns/1ps

// Test de liaison reelle : response encoder -> CAN-FD TX -> bus -> CAN-FD RX.
// Ne remplace aucun module du projet.
module canfd_response_link_tb;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg resp_valid = 1'b0;
    reg [7:0] resp_cmd = 8'h00;
    reg [7:0] resp_status = 8'h00;
    reg [15:0] resp_value = 16'h0000;
    always #5 clk = ~clk;

    wire resp_ready;
    wire encoder_busy;
    wire tx_start;
    wire [63:0] tx_data;
    wire [3:0] tx_dlc;
    wire tx_busy, tx_done, tx_ack_error, can_tx;
    wire ack_drive_low;
    wire can_bus = can_tx & ~ack_drive_low;

    wire [63:0] rx_data;
    wire [3:0] rx_dlc;
    wire [10:0] rx_id;
    wire rx_frame_done, rx_frame_valid, rx_crc_ok;
    wire rx_stuff_error, rx_fsb_error;

    canfd_response_encoder ENC (
        .clk(clk), .rst(rst),
        .resp_valid(resp_valid), .resp_ready(resp_ready),
        .resp_cmd(resp_cmd), .resp_status(resp_status),
        .resp_value(resp_value), .tx_busy(tx_busy),
        .tx_start(tx_start), .tx_data(tx_data),
        .tx_dlc(tx_dlc), .encoder_busy(encoder_busy)
    );

    canfd_tx #(.CLK_FREQ(100_000_000)) TX (
        .clk(clk), .rst(rst), .start(tx_start),
        .can_id(11'h124), .data(tx_data), .dlc(tx_dlc),
        .can_rx(can_bus), .can_tx(can_tx), .busy(tx_busy),
        .done(tx_done), .ack_error(tx_ack_error)
    );

    // Version du RX d'integration avec arret sur frame_done.
    canfd_rx #(
        .CLK_FREQ(100_000_000), .BIT_RATE(1_000_000),
        .PAYLOAD_BITS(86), .FRAME_BITS(200)
    ) RX (
        .clk(clk), .rst(rst), .can_rx(can_bus),
        .rx_id(rx_id), .rx_dlc(rx_dlc), .rx_data(rx_data),
        .crc_ok(rx_crc_ok), .stuff_error(rx_stuff_error),
        .fsb_error(rx_fsb_error), .ack_drive_low(ack_drive_low),
        .frame_done(rx_frame_done), .frame_valid(rx_frame_valid)
    );

    integer errors = 0;
    reg seen_rx = 1'b0, seen_tx = 1'b0;
    reg [63:0] saved_rx_data = 0;
    reg [3:0] saved_rx_dlc = 0;
    reg saved_rx_valid = 0;
    reg saved_crc_ok = 0;
    reg saved_tx_ack_error = 0;
    reg [10:0] saved_rx_id = 0;

    always @(posedge clk) begin
        if (!rst) begin
            if (rx_frame_done) begin
                seen_rx <= 1'b1;
                saved_rx_data <= rx_data;
                saved_rx_dlc <= rx_dlc;
                saved_rx_valid <= rx_frame_valid;
                saved_crc_ok <= rx_crc_ok;
                saved_rx_id <= rx_id;
                $display("[RX] frame_valid=%b crc_ok=%b data=%016h", rx_frame_valid, rx_crc_ok, rx_data);
            end
            if (tx_done) begin
                seen_tx <= 1'b1;
                saved_tx_ack_error <= tx_ack_error;
                $display("[TX] done ACK error=%b", tx_ack_error);
            end
        end
    end

    initial begin
        $dumpfile("canfd_response_link.vcd");
        $dumpvars(0, canfd_response_link_tb);
        repeat (20) @(negedge clk);
        rst = 1'b0;
        repeat (20) @(negedge clk);

        // SEARCH reussi : cmd=02, statut=00, valeur=00AA.
        if (!resp_ready) begin
            $display("FAIL: encodeur non disponible");
            errors = errors + 1;
        end
        resp_cmd = 8'h02;
        resp_status = 8'h00;
        resp_value = 16'h00AA;
        resp_valid = 1'b1;
        @(negedge clk);
        resp_valid = 1'b0;

        wait (seen_rx && seen_tx);
        @(negedge clk);

        if (saved_rx_data !== 64'h04020000AA000000) begin
            $display("FAIL: donnees RX : %016h", saved_rx_data);
            errors = errors + 1;
        end
        if (saved_rx_dlc !== 4'd8 || saved_rx_id !== 11'h124) begin
            $display("FAIL: DLC=%0d ID=%03h", saved_rx_dlc, saved_rx_id);
            errors = errors + 1;
        end
        if (!saved_rx_valid || !saved_crc_ok || saved_tx_ack_error) begin
            $display("FAIL: frame=%b crc=%b ack_error=%b", saved_rx_valid, saved_crc_ok, saved_tx_ack_error);
            errors = errors + 1;
        end
        if (errors == 0)
            $display("PASS : RESPONSE ENCODER -> CAN-FD TX -> RX");
        else
            $display("FAIL : %0d erreur(s)", errors);
        $finish;
    end

    initial begin
        #300000;
        $display("FAIL : TIMEOUT (TX=%b RX=%b)", seen_tx, seen_rx);
        $finish;
    end
endmodule
