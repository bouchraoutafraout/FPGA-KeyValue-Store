`timescale 1ns/1ps
module block_builder_storage_failure_tb;
  reg clk=0, rst=1;
  always #5 clk=~clk;
  reg tx_valid=0,seal=0,hash_done=0,store_done=0;
  wire ready,hash_start,store_start,busy;
  wire [351:0] blk_data;
  wire [31:0] blk_index,next_index,blocks_stored;
  wire [255:0] blk_hash,last_hash;
  wire [3:0] dbg_state;
  integer cycles=0;
  block_builder #(.AUTO_GENESIS(0)) dut(
    .clk(clk),.rst(rst),.tx_valid(tx_valid),.tx_type(8'h01),
    .tx_key(32'h12345678),.tx_value(16'h00AA),.ready(ready),
    .hold(1'b0),.seal(seal),.init_valid(1'b1),
    .init_index(32'd0),.init_hash(256'd0),
    .hash_start(hash_start),.blk_data(blk_data),
    .hash_done(hash_done),.hash_value(256'hCAFE),
    .store_start(store_start),.blk_index(blk_index),
    .blk_hash(blk_hash),.store_done(store_done),.st_full(1'b0),
    .next_index(next_index),.last_hash(last_hash),
    .blocks_stored(blocks_stored),.busy(busy),.dbg_state(dbg_state)
  );
  initial begin
    repeat(3) @(negedge clk); rst=0;
    wait(ready); @(negedge clk); tx_valid=1;
    @(negedge clk); tx_valid=0; seal=1;
    @(negedge clk); seal=0;
    wait(hash_start); wait(dbg_state == 4);
    @(negedge clk); hash_done=1;
    @(negedge clk); hash_done=0;
    wait(store_start);
    @(negedge clk); // simulate adapter completion AFTER FAILED BRAM write
    store_done=1;
    @(negedge clk); store_done=0;
    repeat(2) @(negedge clk);
    $display("INJECTION: storage operation finished, write FAILED (no storage_ok port)");
    $display("next_index=%0d blocks_stored=%0d last_hash=%h",next_index,blocks_stored,last_hash);
    if (next_index!=0 || blocks_stored!=0 || last_hash!=0)
      $display("BUG REPRODUCED: builder commits a failed storage operation");
    else $display("PASS: no false commit");
    $finish;
  end
  initial begin
    #200000;
    $display("FAIL: timeout (state=%0d)",dbg_state);
    $finish;
  end
endmodule

