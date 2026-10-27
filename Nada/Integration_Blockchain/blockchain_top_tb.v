`timescale 1ns/1ps
// TEST ONLY: handshake mocks; no real SHA-256, validation policy, BRAM or CAN-FD.
module blockchain_top_tb;
    reg clk=0, rst=1, tx_valid=0, result_ready=1;
    reg [63:0] tx_data=0;
    always #5 clk=~clk;

    wire tx_ready, validator_start, builder_start, sha_start, storage_start;
    wire [63:0] validator_tx, builder_tx;
    wire [31:0] builder_index, storage_index, result_index, next_index;
    wire [255:0] builder_prev_hash, storage_hash, result_hash, previous_hash;
    wire [351:0] sha_message, storage_header;
    wire result_valid, result_ok, busy;
    wire [7:0] result_status;
    reg validator_done=0, validator_accept=0;
    reg builder_done=0;
    reg [351:0] builder_header=0;
    reg sha_done=0;
    reg [255:0] sha_hash=0;
    reg storage_done=0, storage_ok=0;

    blockchain_top DUT (
       .clk(clk),.rst(rst),.tx_valid(tx_valid),.tx_ready(tx_ready),.tx_data(tx_data),
       .validator_start(validator_start),.validator_tx(validator_tx),
       .validator_done(validator_done),.validator_accept(validator_accept),
       .builder_start(builder_start),.builder_index(builder_index),
       .builder_prev_hash(builder_prev_hash),.builder_tx(builder_tx),
       .builder_done(builder_done),.builder_header(builder_header),
       .sha_start(sha_start),.sha_message(sha_message),
       .sha_done(sha_done),.sha_hash(sha_hash),
       .storage_start(storage_start),.storage_index(storage_index),
       .storage_header(storage_header),.storage_hash(storage_hash),
       .storage_done(storage_done),.storage_ok(storage_ok),
       .result_valid(result_valid),.result_ready(result_ready),
       .result_ok(result_ok),.result_status(result_status),
       .result_index(result_index),.result_hash(result_hash),
       .busy(busy),.next_index(next_index),.previous_hash(previous_hash)
    );

    // Simulate each team member's future module responding one cycle after start.
    reg reject_next=0, fail_store_next=0;
    reg [255:0] mock_hash=256'h100;
    always @(posedge clk) begin
       if (rst) begin
          validator_done<=0;validator_accept<=0;
          builder_done<=0;builder_header<=0;
          sha_done<=0;sha_hash<=0;
          storage_done<=0;storage_ok<=0;
       end else begin
          validator_done<=validator_start;
          if (validator_start) validator_accept<=!reject_next;
          builder_done<=builder_start;
          if (builder_start)
             builder_header<={builder_index,builder_prev_hash,builder_tx};
          sha_done<=sha_start;
          if (sha_start) begin
             sha_hash<=mock_hash; // Mock ONLY, NOT a cryptographic hash.
             mock_hash<=mock_hash+1;
          end
          storage_done<=storage_start;
          if (storage_start) storage_ok<=!fail_store_next;
       end
    end

    integer errors=0;
    task send_and_check;
      input [63:0] value;
      input [7:0] exp_status;
      input [31:0] exp_index_after;
      begin
        @(negedge clk);
        while (!tx_ready) @(negedge clk);
        tx_data=value;tx_valid=1;
        @(negedge clk);tx_valid=0;
        wait(result_valid);
        #1;
        $display("TX=%h status=%h index=%0d next=%0d",value,result_status,result_index,next_index);
        if (result_status !== exp_status || next_index !== exp_index_after) begin
          $display("FAIL transaction");errors=errors+1;
        end
        @(negedge clk);
      end
    endtask

    initial begin
      repeat(4) @(negedge clk);rst=0;
      send_and_check(64'h07011234567800aa,8'h00,32'd1);
      send_and_check(64'h0502123456780000,8'h00,32'd2);
      @(negedge clk);reject_next=1;
      send_and_check(64'hffff000000000000,8'h01,32'd2);
      @(negedge clk);reject_next=0;fail_store_next=1;
      send_and_check(64'h0703123456780055,8'h02,32'd2);
      @(negedge clk);fail_store_next=0;
      send_and_check(64'h0703123456780055,8'h00,32'd3);
      if(errors==0) $display("PASS : BLOCKCHAIN CONTROLLER FSM (MOCKS ONLY)");
      else $display("FAIL : %0d ERRORS",errors);
      $finish;
    end
    initial begin #100000; $display("FAIL : TIMEOUT");$finish;end
endmodule
