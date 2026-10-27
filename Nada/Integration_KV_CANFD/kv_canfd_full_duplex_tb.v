`timescale 1ns/1ps
module kv_canfd_full_duplex_tb;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg request_start = 1'b0;
    reg [63:0] request_data = 64'd0;
    always #5 clk = ~clk;

    wire request_tx_pin, request_tx_busy, request_tx_done, request_tx_ack_error;
    wire request_ack_drive_low;
    wire request_bus = request_tx_pin & ~request_ack_drive_low;

    canfd_tx #(.CLK_FREQ(100_000_000)) REQUEST_TX (
        .clk(clk), .rst(rst), .start(request_start),
        .can_id(11'h123), .data(request_data), .dlc(4'd8),
        .can_rx(request_bus), .can_tx(request_tx_pin),
        .busy(request_tx_busy), .done(request_tx_done),
        .ack_error(request_tx_ack_error)
    );

    wire response_tx_pin, response_tx_done, response_tx_busy, response_ack_error;
    wire response_ack_drive_low;
    wire response_bus = response_tx_pin & ~response_ack_drive_low;
    wire request_frame_done, request_frame_valid, response_encoder_busy, storage_done;

    kv_canfd_full_duplex_top DUT (
        .clk(clk), .rst(rst),
        .request_can_rx(request_bus),
        .request_ack_drive_low(request_ack_drive_low),
        .response_can_tx(response_tx_pin),
        .response_can_rx(response_bus),
        .response_tx_done(response_tx_done),
        .response_ack_error(response_ack_error),
        .response_tx_busy(response_tx_busy),
        .request_frame_done(request_frame_done),
        .request_frame_valid(request_frame_valid),
        .response_encoder_busy(response_encoder_busy),
        .storage_done(storage_done)
    );

    wire response_frame_done, response_frame_valid, response_crc_ok;
    wire [10:0] response_id;
    wire [3:0] response_dlc;
    wire [63:0] response_data;

    canfd_rx #(
        .CLK_FREQ(100_000_000), .BIT_RATE(1_000_000),
        .PAYLOAD_BITS(86), .FRAME_BITS(127)
    ) RESPONSE_RX (
        .clk(clk), .rst(rst), .can_rx(response_bus),
        .rx_id(response_id), .rx_dlc(response_dlc),
        .rx_data(response_data),
        .crc_ok(response_crc_ok),
        .ack_drive_low(response_ack_drive_low),
        .frame_done(response_frame_done),
        .frame_valid(response_frame_valid)
    );

    integer errors = 0;
    integer responses = 0;
    reg [63:0] received_response = 64'd0;
    reg [10:0] received_id = 11'd0;
    reg received_valid = 1'b0;
    reg received_crc_ok = 1'b0;
    integer request_done_count = 0;
    integer response_tx_done_count = 0;

    always @(posedge clk) if (!rst) begin
        if (response_frame_done) begin
            responses = responses + 1;
            received_response = response_data;
            received_id = response_id;
            received_valid = response_frame_valid;
            received_crc_ok = response_crc_ok;
            $display("[RESPONSE RX] id=%03h valid=%b crc_ok=%b data=%016h",
                     response_id, response_frame_valid, response_crc_ok, response_data);
        end
        if (request_tx_done) begin
            request_done_count = request_done_count + 1;
            $display("[REQUEST TX] done ack_error=%b", request_tx_ack_error);
            if (request_tx_ack_error) errors = errors + 1;
        end
        if (response_tx_done) begin
            response_tx_done_count = response_tx_done_count + 1;
            $display("[RESPONSE TX] done ack_error=%b", response_ack_error);
            if (response_ack_error) errors = errors + 1;
        end
    end

    task send_and_check;
        input [63:0] packet;
        input [63:0] expected_response;
        integer old_responses;
        integer cycles;
        begin
            old_responses = responses;
            @(negedge clk);
            request_data = packet;
            request_start = 1'b1;
            @(negedge clk);
            request_start = 1'b0;
            cycles = 0;
            while (responses == old_responses && cycles < 35000) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (responses == old_responses) begin
                $display("FAIL: timeout response for %016h", packet);
                errors = errors + 1;
            end else begin
                if (received_response !== expected_response ||
                    received_id !== 11'h124 ||
                    !received_valid || !received_crc_ok) begin
                    $display("FAIL: expected %016h got %016h", expected_response, received_response);
                    errors = errors + 1;
                end else begin
                    $display("PASS: request %016h -> response %016h", packet, received_response);
                end
            end
            // Keep all transactions apart by at least the bus intermission.
            #20000;
        end
    endtask

    initial begin
        $dumpfile("kv_canfd_full_duplex.vcd");
        $dumpvars(0, kv_canfd_full_duplex_tb);
        repeat (20) @(negedge clk);
        rst = 1'b0;
        repeat (20) @(negedge clk);
        // CREATE key=12345678 value=00AA
        send_and_check(64'h07011234567800AA, 64'h0401000000000000);
        // SEARCH key=12345678 => 00AA
        send_and_check(64'h0502123456780000, 64'h04020000AA000000);
        // TRANSFER key=12345678 value=0055
        send_and_check(64'h0703123456780055, 64'h0403000000000000);
        // SEARCH => 0055
        send_and_check(64'h0502123456780000, 64'h0402000055000000);
        $display("TOTAL responses=%0d request_tx_done=%0d response_tx_done=%0d errors=%0d",
                 responses, request_done_count, response_tx_done_count, errors);
        if (errors == 0 && responses == 4 && request_done_count == 4 && response_tx_done_count == 4)
            $display("PASS : CAN-FD REQUEST -> CUCKOO -> CAN-FD RESPONSE (4 transactions)");
        else
            $display("FAIL : FULL DUPLEX INTEGRATION");
        $finish;
    end
    initial begin
        #2500000;
        $display("FAIL : GLOBAL TIMEOUT");
        $finish;
    end
endmodule
