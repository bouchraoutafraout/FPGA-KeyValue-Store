`timescale 1ns/1ps
module cuckoo_overflow_safe_tb;
  reg clk=0, rst=1;
  always #5 clk=~clk;
  reg [7:0] cmd=0;
  reg [31:0] key=0;
  reg [15:0] value_in=0;
  reg start=0, txn_begin=0, txn_commit=0, txn_rollback=0;
  wire txn_rollback_done, txn_journal_overflow;
  wire busy, done, found, error;
  wire [15:0] value_out;
  integer tick=0;
  cuckoo_top_atomic DUT (
    .clk(clk), .rst(rst), .cmd(cmd), .key(key), .value_in(value_in),
    .start(start), .txn_begin(txn_begin), .txn_commit(txn_commit),
    .txn_rollback(txn_rollback), .txn_rollback_done(txn_rollback_done),
    .txn_journal_overflow(txn_journal_overflow),
    .busy(busy), .done(done), .found(found), .value_out(value_out), .error(error)
  );
  initial begin
    #200000;
    $display("FAIL: timeout waiting for Cuckoo completion");
    $finish;
  end
  initial begin
    repeat(4) @(negedge clk);
    rst=0;
    @(negedge clk); txn_begin=1;
    @(negedge clk); txn_begin=0;
    if (!DUT.txn_active) begin
      $display("FAIL: transaction not active"); $finish;
    end
    // Fault injection: emulate 16 existing logged writes.
    // This isolates saturation logic; it does not generate 16 actual evictions.
    DUT.log_count=5'd16;
    @(negedge clk);
    cmd=8'h01; key=32'h12345678; value_in=16'h00AA; start=1;
    @(negedge clk); start=0;
    wait (DUT.live_write);
    #1;
    if (DUT.physical_live_write !== 1'b0) begin
      $display("FAIL: unlogged physical write enabled"); $finish;
    end
    $display("PASS: physical write blocked at journal capacity");
    wait (done);
    #1;
    $display("OBSERVED: journal_overflow=%b cuckoo_error=%b cuckoo_done=%b",txn_journal_overflow,error,done);
    if (txn_journal_overflow !== 1'b1) begin
      $display("FAIL: overflow flag missing"); $finish;
    end
    if (error !== 1'b1) begin
      $display("FAIL: Cuckoo reported success despite a blocked write");
      $fatal(1);
    end else begin
      $display("PASS: journal overflow propagates to KVS error");
    end
    $display("TEST COMPLETE: forced-full journal diagnostic only");
    $finish;
  end
endmodule
