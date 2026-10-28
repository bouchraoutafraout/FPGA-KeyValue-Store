`timescale 1ns/1ps
module blockchain_system_storage_v2_tb;
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

    wire ingress_overflow;
    wire validator_start, builder_start, sha_start, chain_storage_start;
    wire [63:0] validator_tx, builder_tx;
    wire [31:0] builder_index, chain_storage_index, chain_result_index, next_index;
    wire [255:0] builder_prev_hash, chain_storage_hash, chain_result_hash, previous_hash;
    wire [351:0] sha_message, chain_storage_header;
    wire chain_result_valid, chain_result_ok;
    wire [7:0] chain_result_status;
    reg validator_done=0, validator_accept=0;
    reg builder_done=0;
    reg [351:0] builder_header=0;
    reg sha_done=0;
    reg [255:0] sha_hash=0;

    blockchain_system_storage_v2_top DUT (
        .clk(clk), .rst(rst),
        .request_can_rx(request_bus),
        .request_ack_drive_low(request_ack_drive_low),
        .response_can_tx(response_tx_pin),
        .response_can_rx(response_bus),
        .response_tx_done(response_tx_done),
        .response_ack_error(response_ack_error),
        .request_frame_done(request_frame_done),
        .request_frame_valid(request_frame_valid),
        .ingress_overflow(ingress_overflow),
        .validator_start(validator_start), .validator_tx(validator_tx),
        .validator_done(validator_done), .validator_accept(validator_accept),
        .builder_start(builder_start), .builder_index(builder_index),
        .builder_prev_hash(builder_prev_hash), .builder_tx(builder_tx),
        .builder_done(builder_done), .builder_header(builder_header),
        .sha_start(sha_start), .sha_message(sha_message),
        .sha_done(sha_done), .sha_hash(sha_hash),
        .storage_start(chain_storage_start), .storage_index(chain_storage_index),
        .storage_header(chain_storage_header), .storage_hash(chain_storage_hash),
        .chain_result_valid(chain_result_valid), .chain_result_ready(1'b1),
        .chain_result_ok(chain_result_ok),
        .chain_result_status(chain_result_status),
        .chain_result_index(chain_result_index),
        .chain_result_hash(chain_result_hash),
        .next_index(next_index), .previous_hash(previous_hash)
    );

    // Validator/builder/SHA are MOCKS; storage V2 is REAL behavioral memory.
    reg [255:0] dummy_hash=256'h100;
    integer chain_results=0;
    integer incoming_count=0;
    always @(posedge clk) begin
        if (rst) begin
            validator_done <= 0;
            validator_accept <= 0;
            builder_done <= 0;
            builder_header <= 0;
            sha_done <= 0;
            sha_hash <= 0;
        end else begin
            validator_done <= validator_start;
            if (validator_start) begin
                validator_accept <= 1;
                incoming_count = incoming_count+1;
                $display("[BLOCKCHAIN] transaction=%016h", validator_tx);
            end
            builder_done <= builder_start;
            if (builder_start)
                builder_header <= {builder_index,builder_prev_hash,builder_tx};
            sha_done <= sha_start;
            if (sha_start) begin
                sha_hash <= dummy_hash;
                dummy_hash <= dummy_hash+1;
            end
            if (chain_result_valid) begin
                chain_results = chain_results+1;
                $display("[BLOCKCHAIN MOCK] status=%02h index=%0d", chain_result_status, chain_result_index);
            end
        end
    end

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
        $dumpfile("blockchain_system_storage_v2.vcd");
        $dumpvars(0, blockchain_system_storage_v2_tb);
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
        #1000;
        $display("CHAIN results=%0d incoming=%0d index=%0d overflow=%b",chain_results,incoming_count,next_index,ingress_overflow);
        $display("TOTAL responses=%0d request_tx_done=%0d response_tx_done=%0d errors=%0d",
                 responses, request_done_count, response_tx_done_count, errors);
        if (DUT.STORE.STORAGE.block_count !== 5'd5) begin
            $display("FAIL : block_count expected 5 got %0d", DUT.STORE.STORAGE.block_count);
            errors = errors + 1;
        end
        if (DUT.STORE.STORAGE.mem[0] !== 608'd1) begin
            $display("FAIL : Genesis overwritten");
            errors = errors + 1;
        end else $display("PASS : GENESIS RESERVED");
        if (DUT.STORE.STORAGE.mem[1] !== {32'd0,256'd0,64'h07011234567800AA,256'h100} ||
            DUT.STORE.STORAGE.mem[2] !== {32'd1,256'h100,64'h0502123456780000,256'h101} ||
            DUT.STORE.STORAGE.mem[3] !== {32'd2,256'h101,64'h0703123456780055,256'h102} ||
            DUT.STORE.STORAGE.mem[4] !== {32'd3,256'h102,64'h0502123456780000,256'h103}) begin
            $display("FAIL : expected storage data/chain mismatch");
            errors = errors + 1;
        end else $display("PASS : FOUR BLOCKS STORED WITH HASH CHAIN (MOCK HASH)");
        if (errors == 0 && responses == 4 && request_done_count == 4 && response_tx_done_count == 4 && chain_results == 4 && incoming_count == 4 && next_index == 4 && !ingress_overflow)
            $display("PASS : CAN-FD -> INGRESS -> BLOCKCHAIN -> STORAGE V2 + KVS RESPONSES");
        else
            $display("FAIL : FULL DUPLEX V2 INTEGRATION");
        $finish;
    end
    initial begin
        #2500000;
        $display("FAIL : GLOBAL TIMEOUT");
        $finish;
    end
endmodule
