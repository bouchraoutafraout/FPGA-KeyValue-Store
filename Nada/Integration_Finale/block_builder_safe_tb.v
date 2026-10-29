`timescale 1ns/1ps
module block_builder_safe_tb;
  reg clk=0, rst=1;
  always #5 clk=~clk;
  reg tx_valid=0, seal=0, hash_done=0, store_done=0, store_ok=0;
  wire ready, hash_start, store_start, busy, store_failed;
  wire [351:0] blk_data;
  wire [31:0] blk_index, next_index, blocks_stored;
  wire [255:0] blk_hash, last_hash;
  wire [3:0] dbg_state;
  integer errors=0;
  block_builder_safe #(.AUTO_GENESIS(0)) dut (
    .clk(clk), .rst(rst), .tx_valid(tx_valid), .tx_type(8'h01),
    .tx_key(32'h12345678), .tx_value(16'h00AA), .ready(ready),
    .hold(1'b0), .seal(seal), .init_valid(1'b1),
    .init_index(32'd0), .init_hash(256'd0),
    .hash_start(hash_start), .blk_data(blk_data),
    .hash_done(hash_done), .hash_value(256'hCAFE),
    .store_start(store_start), .blk_index(blk_index),
    .blk_hash(blk_hash), .store_done(store_done),
    .store_ok(store_ok), .store_failed(store_failed), .st_full(1'b0),
    .next_index(next_index), .last_hash(last_hash),
    .blocks_stored(blocks_stored), .busy(busy), .dbg_state(dbg_state)
  );
  task run_transaction;
    input success;
    begin
      wait(ready === 1'b1);
      @(negedge clk); tx_valid=1;
      @(negedge clk); tx_valid=0; seal=1;
      @(negedge clk); seal=0;
      wait(hash_start === 1'b1);
      wait(dbg_state == 4'd4);
      @(negedge clk); hash_done=1;
      @(negedge clk); hash_done=0;
      wait(store_start === 1'b1);
      wait(dbg_state == 4'd6);
      @(negedge clk); store_ok=success; store_done=1;
      @(posedge clk); #1;
      if (success === 1'b0 && store_failed !== 1'b1) begin
        $display("FAIL: store_failed missing"); errors=errors+1;
      end
      if (success === 1'b1 && store_failed !== 1'b0) begin
        $display("FAIL: unexpected store_failed"); errors=errors+1;
      end
      @(negedge clk); store_done=0; store_ok=0;
      repeat(2) @(negedge clk);
    end
  endtask
  initial begin
    repeat(3) @(negedge clk); rst=0;
    run_transaction(1'b0);
    if (next_index !== 0 || blocks_stored !== 0 || last_hash !== 0) begin
      $display("FAIL: failed store modified chain state"); errors=errors+1;
    end else $display("PASS: failed storage does not commit block");
    run_transaction(1'b1);
    if (next_index !== 1 || blocks_stored !== 1 || last_hash !== 256'hCAFE) begin
      $display("FAIL: successful store not committed"); errors=errors+1;
    end else $display("PASS: successful storage commits block");
    if (errors == 0) $display("PASS: BLOCK BUILDER SAFE STORAGE");
    else $display("FAIL: %0d errors", errors);
    $finish;
  end
  initial begin
    #200000;
    $display("FAIL: timeout state=%0d", dbg_state);
    $finish;
  end
endmodule
