`timescale 1ns/1ps
module canfd_blockchain_guarded_collision_tb;
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
    initial begin
        $dumpfile("canfd_blockchain_atomic_collision.vcd");
        $dumpvars(0,canfd_blockchain_guarded_collision_tb);
        repeat(10) @(negedge clk); rst=0;
        repeat(10) @(negedge clk);

        // h1(key)=byte XOR; h2(key)=(b3 XOR b0)+(b2 XOR b1) mod 256.
        // A: h1=1,h2=1. B,C: h1=1,h2=5.
        // After A,B, the table1[1] slot contains B and table2[1] contains A.
        // C forces B out of table1[1] into table2[5] (2 Cuckoo writes).
        $display("COLLISION KEYS: A=00000001 B=00000203 C=00000302");
        run_request(64'h07010000000100A1,64'h0401000000000000,32'd1);
        run_request(64'h07010000020300B2,64'h0401000000000000,32'd2);
        run_request(64'h0502000000010000,64'h04020000A1000000,32'd2);
        run_request(64'h0502000002030000,64'h04020000B2000000,32'd2);

        // Force failure of blockchain write AFTER multiple Cuckoo writes.
        force DUT.BLOCKCHAIN.BLOCKS_REAL.STORAGE_KHADIJA.wr_ready = 1'b0;
        $display("INJECTION: reject BRAM write for colliding CREATE C");
        run_request(64'h07010000030200C3,64'h0401020000000000,32'd2);
        release DUT.BLOCKCHAIN.BLOCKS_REAL.STORAGE_KHADIJA.wr_ready;

        if (DUT.BLOCKCHAIN.BLOCKS_REAL.STORAGE_KHADIJA.STORAGE.block_count !== 5'd3) begin
            $display("FAIL: BRAM count changed after rejection"); errors=errors+1;
        end else $display("PASS: BRAM still has Genesis plus two blocks");
        if (next_index !== 32'd2) begin
            $display("FAIL: next_index=%0d after rejection",next_index); errors=errors+1;
        end else $display("PASS: next_index unchanged");

        // Both displaced and undisplaced originals must be restored.
        run_request(64'h0502000000010000,64'h04020000A1000000,32'd2);
        run_request(64'h0502000002030000,64'h04020000B2000000,32'd2);
        run_request(64'h0502000003020000,64'h0402010000000000,32'd2);
        if (errors==0) $display("PASS: CUCKOO MULTI-WRITE ROLLBACK AFTER BRAM FAILURE");
        else $display("FAIL: %0d collision / storage assertions", errors);
        $finish;
    end
endmodule
