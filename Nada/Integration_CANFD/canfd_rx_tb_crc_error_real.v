`timescale 1ns/1ps
// Independent CRC-17 corruption test, DLC=8.
// Flips a single transmitted CRC bit (CRC field index 7), not a fixed stuff bit.
module canfd_rx_tb_crc_error_real;
    localparam CLK_FREQ = 100_000_000;
    reg clk = 0, rst = 1, start = 0;
    always #5 clk = ~clk;
    reg [10:0] can_id = 11'h123;
    reg [63:0] data = 64'h123456789abcdef0;
    reg [3:0] dlc = 4'd8;
    wire tx_line, tx_busy, tx_done, tx_ack_error;
    wire ack_drive_low, ack_sent, tail_error, frame_done, frame_valid;
    reg inject_error = 0, injected = 0;
    // Normal wire-AND with ACK; corrupt exactly one sampled CRC bit.
    wire can_bus = (tx_line & ~ack_drive_low) ^ inject_error;
    canfd_tx #(.CLK_FREQ(CLK_FREQ)) tx (
        .clk(clk), .rst(rst), .start(start), .can_id(can_id),
        .data(data), .dlc(dlc), .can_rx(can_bus),
        .can_tx(tx_line), .busy(tx_busy), .done(tx_done),
        .ack_error(tx_ack_error)
    );
    wire sample_bit, sample_valid, rx_busy;
    wire [6:0] bit_index, payload_count;
    wire payload_bit, payload_valid, payload_done, stuff_error;
    wire [7:0] stuff_count;
    wire [10:0] rx_id;
    wire [3:0] rx_dlc, sbc_recu;
    wire [63:0] rx_data;
    wire decode_done, fsb_error, crc_done, crc_ok;
    wire [16:0] crc_calc, crc_recu;
    canfd_rx #(
        .CLK_FREQ(CLK_FREQ), .BIT_RATE(1_000_000),
        .FRAME_BITS(127), .PAYLOAD_BITS(86)
    ) rx (
        .clk(clk), .rst(rst), .can_rx(can_bus),
        .sample_bit(sample_bit), .sample_valid(sample_valid),
        .busy(rx_busy), .bit_index(bit_index),
        .payload_bit(payload_bit), .payload_valid(payload_valid),
        .payload_count(payload_count), .stuff_count(stuff_count),
        .stuff_error(stuff_error), .payload_done(payload_done),
        .rx_id(rx_id), .rx_dlc(rx_dlc), .rx_data(rx_data),
        .decode_done(decode_done), .crc_calc(crc_calc),
        .crc_recu(crc_recu), .sbc_recu(sbc_recu),
        .fsb_error(fsb_error), .crc_done(crc_done), .crc_ok(crc_ok),
        .ack_drive_low(ack_drive_low), .ack_sent(ack_sent),
        .tail_error(tail_error), .frame_done(frame_done),
        .frame_valid(frame_valid)
    );
    // Flip CRC bit at index 7, safely separated from fixed-stuff indices
    // 0,5,10,15,20,25. Hold inversion across its sample point.
    initial begin
        wait (!rst);
        wait (payload_done && rx.crc_field_index == 5'd7 && !crc_done);
        @(negedge clk);
        inject_error = 1;
        injected = 1;
        $display("INJECTION CRC : index=%0d", rx.crc_field_index);
        wait (sample_valid && rx.crc_field_index == 5'd7);
        repeat (2) @(negedge clk);
        inject_error = 0;
    end
    initial begin
        $dumpfile("canfd_crc_error_real.vcd");
        $dumpvars(0, canfd_rx_tb_crc_error_real);
        repeat (5) @(negedge clk); rst = 0;
        repeat (5) @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        wait (frame_done);
        @(negedge clk); #1;
        $display("Injection=%b stuffing=%b FSB=%b CRC_OK=%b frame_valid=%b", injected, stuff_error, fsb_error, crc_ok, frame_valid);
        $display("CRC calcule=0x%05h recu=0x%05h", crc_calc, crc_recu);
        if (injected && !stuff_error && !fsb_error && !crc_ok && !frame_valid && (crc_calc != crc_recu))
            $display("PASS : ERREUR CRC-17 DETECTEE INDEPENDAMMENT");
        else
            $display("FAIL : TEST CRC-17");
        $finish;
    end
    initial begin
        #200000000;
        $display("FAIL : TIMEOUT TEST CRC-17");
        $finish;
    end
endmodule
