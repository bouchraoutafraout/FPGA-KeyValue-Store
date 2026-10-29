`timescale 1ns/1ps
module canfd_blockchain_guarded_timeout_tb;
    reg clk=0, rst=1, start=0;
    reg [63:0] request_data=0;
    always #5 clk=~clk;
    wire tx_wire, tx_busy, tx_done, tx_ack_error;
    wire req_ack, request_done, request_valid;
    wire request_bus=tx_wire & ~req_ack;
    wire response_tx_wire, response_tx_done, response_ack_error, response_tx_busy;
    wire resp_ack;
    wire response_bus=response_tx_wire & ~resp_ack;
    wire response_done, response_valid, resp_crc_ok;
    wire [63:0] response_data;
    wire [3:0] response_dlc;
    wire [31:0] next_index;
    wire [255:0] last_hash;
    reg verify_start=0;
    reg [3:0] verify_index=0;
    wire verify_ready, verify_done, verify_valid, verify_link_ok, verify_hash_ok, verify_error;
    integer errors=0;
    integer responses=0;
    reg [63:0] last_response=0;
    canfd_tx #(.CLK_FREQ(100_000_000)) REQUEST_TX (
        .clk(clk),.rst(rst),.start(start),.can_id(11'h123),
        .data(request_data),.dlc(4'd8),.can_rx(request_bus),
        .can_tx(tx_wire),.busy(tx_busy),.done(tx_done),.ack_error(tx_ack_error)
    );
    canfd_blockchain_chain_guarded_top DUT (
        .clk(clk),.rst(rst),.request_can_rx(request_bus),
        .request_ack_drive_low(req_ack),.response_can_tx(response_tx_wire),
        .response_can_rx(response_bus),.response_tx_done(response_tx_done),
        .response_ack_error(response_ack_error),.response_tx_busy(response_tx_busy),
        .request_frame_done(request_done),.request_frame_valid(request_valid),
        .blockchain_next_index(next_index),.blockchain_last_hash(last_hash),
        .verify_start(verify_start), .verify_index(verify_index),
        .verify_ready(verify_ready), .verify_done(verify_done),
        .verify_valid(verify_valid), .verify_link_ok(verify_link_ok),
        .verify_hash_ok(verify_hash_ok), .verify_error(verify_error)
    );
    canfd_rx #(.CLK_FREQ(100_000_000), .BIT_RATE(1_000_000),
               .PAYLOAD_BITS(86),.FRAME_BITS(127)) RESPONSE_RX (
        .clk(clk),.rst(rst),.can_rx(response_bus),
        .ack_drive_low(resp_ack),.frame_done(response_done),
        .frame_valid(response_valid),.rx_data(response_data),.rx_dlc(response_dlc),
        .crc_ok(resp_crc_ok)
    );
    always @(posedge clk) if (!rst && response_done) begin
        if (!response_valid || !resp_crc_ok) begin
            $display("FAIL: CAN-FD response CRC/frame"); errors=errors+1;
        end
        last_response=response_data;
        responses=responses+1;
    end
    task run_request;
        input [63:0] req;
        input [63:0] expected_resp;
        input [31:0] expected_index;
        integer old_count;
        integer guard;
        begin
            old_count=responses;
            @(negedge clk); request_data=req; start=1;
            @(negedge clk); start=0;
            guard=0;
            while (responses==old_count && guard<300000) begin
                @(negedge clk); guard=guard+1;
            end
            if (responses==old_count) begin
                $display("FAIL: timeout req=%h",req); errors=errors+1;
            end else if (last_response !== expected_resp || next_index !== expected_index) begin
                $display("FAIL: req=%h reply=%h expected=%h next=%0d expected=%0d",req,last_response,expected_resp,next_index,expected_index);
                errors=errors+1;
            end else $display("PASS: req=%h response=%h blocks=%0d",req,last_response,next_index);
            repeat(30) @(negedge clk);
        end
    endtask
    task check_chain;
        input [3:0] idx;
        input expected_valid;
        input expected_error;
        integer guard;
        begin
            guard=0;
            while (!verify_ready && guard<100000) begin
                @(negedge clk); guard=guard+1;
            end
            if (!verify_ready) begin
                $display("FAIL: verify not ready"); errors=errors+1;
            end else begin
                @(negedge clk); verify_index=idx; verify_start=1;
                @(negedge clk); verify_start=0;
                guard=0;
                while (!verify_done && guard<100000) begin
                    @(negedge clk); guard=guard+1;
                end
                if (!verify_done || verify_valid !== expected_valid ||
                    verify_error !== expected_error ||
                    (expected_valid && (!verify_link_ok || !verify_hash_ok))) begin
                    $display("FAIL VERIFY index=%0d valid=%b link=%b hash=%b error=%b",idx,verify_valid,verify_link_ok,verify_hash_ok,verify_error);
                    errors=errors+1;
                end else $display("PASS VERIFY BRAM index=%0d valid=%b err=%b",idx,verify_valid,verify_error);
                repeat (4) @(negedge clk);
            end
        end
    endtask
    // Diagnostic: force the controller's timeout decision while holding
    // completion signals low. This is not a real BRAM failure/recovery test.
    integer guard;
    integer replies_before;
    initial begin
        $dumpfile("canfd_blockchain_timeout.vcd");
        $dumpvars(0,canfd_blockchain_guarded_timeout_tb);
        repeat(10) @(negedge clk); rst=0;
        repeat(10) @(negedge clk);

        @(negedge clk); request_data=64'h07011234567800AA; start=1;
        @(negedge clk); start=0;
        guard=0;
        while (DUT.BLOCKCHAIN.state !== 3'd2 && guard < 150000) begin
            @(negedge clk); guard=guard+1;
        end
        if (DUT.BLOCKCHAIN.state !== 3'd2) begin
            $display("FAIL: never reached WAIT_STORE");
            errors=errors+1;
        end else begin
            // Simulate an unresolved storage operation. Hold handshakes
            // while the timer is moved to its last count.
            force DUT.BLOCKCHAIN.block_done = 1'b0;
            force DUT.BLOCKCHAIN.block_failed = 1'b0;
            force DUT.BLOCKCHAIN.store_timer = 20'hfffff;
            @(negedge clk);
            release DUT.BLOCKCHAIN.store_timer;
            release DUT.BLOCKCHAIN.block_done;
            release DUT.BLOCKCHAIN.block_failed;
            if (DUT.BLOCKCHAIN.fault_latched !== 1'b1 ||
                DUT.BLOCKCHAIN.result_error !== 4'hf) begin
                $display("FAIL: timeout did not latch fault/error F: latched=%b err=%h state=%0d",
                    DUT.BLOCKCHAIN.fault_latched, DUT.BLOCKCHAIN.result_error, DUT.BLOCKCHAIN.state);
                errors=errors+1;
            end else $display("PASS: forced WAIT_STORE timeout latched error F");

            guard=0;
            while (DUT.BLOCKCHAIN.state !== 3'd7 && guard<150000) begin
                @(negedge clk); guard=guard+1;
            end
            if (DUT.BLOCKCHAIN.state !== 3'd7) begin
                $display("FAIL: FAULT_LOCK not reached state=%0d",DUT.BLOCKCHAIN.state);
                errors=errors+1;
            end else $display("PASS: FAULT_LOCK entered after response");
            if (DUT.BLOCKCHAIN.tx_ready !== 1'b0 ||
                DUT.BLOCKCHAIN.search_ready !== 1'b0 ||
                DUT.BLOCKCHAIN.verify_ready !== 1'b0) begin
                $display("FAIL: inputs not disabled in FAULT_LOCK");
                errors=errors+1;
            end else $display("PASS: tx/search/verify ready all low");
            replies_before=responses;
            // Wait for any already scheduled CAN-FD transmission to end.
            repeat(1000) @(negedge clk);
            @(negedge clk); request_data=64'h07011234567800CC; start=1;
            @(negedge clk); start=0;
            repeat(35000) @(negedge clk);
            if (DUT.BLOCKCHAIN.state !== 3'd7 || next_index > 32'd1) begin
                $display("FAIL: lock state lost or unexpected index=%0d",next_index);
                errors=errors+1;
            end else $display("PASS: subsequent CREATE cannot exit FAULT_LOCK");
        end
        if (errors==0) $display("PASS: FORCED TIMEOUT FAIL-STOP DIAGNOSTIC");
        else $display("FAIL: %0d timeout diagnostic errors",errors);
        $finish;
    end
endmodule
