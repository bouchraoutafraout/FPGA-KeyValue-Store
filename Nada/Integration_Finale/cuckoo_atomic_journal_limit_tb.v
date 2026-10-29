`timescale 1ns/1ps
// Boundary test: artificially sets log_count to LOG_DEPTH.
// Does NOT claim to fill the journal with 16 real Cuckoo evictions.
module cuckoo_atomic_journal_limit_tb;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;
  reg [7:0] cmd = 0;
  reg [31:0] key = 0;
  reg [15:0] value_in = 0;
  reg start = 0, txn_begin = 0, txn_commit = 0, txn_rollback = 0;
  wire rollback_done, overflow, busy, done, found, error;
  wire [15:0] value_out;
  integer i;

  cuckoo_top_atomic dut (
    .clk(clk), .rst(rst), .cmd(cmd), .key(key), .value_in(value_in), .start(start),
    .txn_begin(txn_begin), .txn_commit(txn_commit), .txn_rollback(txn_rollback),
    .txn_rollback_done(rollback_done), .txn_journal_overflow(overflow),
    .busy(busy), .done(done), .found(found), .value_out(value_out), .error(error)
  );

  task command;
    input [7:0] c;
    input [31:0] k;
    input [15:0] v;
    begin
      // Request on falling edge so DUT captures it at next rising edge.
      @(negedge clk); cmd = c; key = k; value_in = v; start = 1;
      @(negedge clk); start = 0;
      begin : wait_response
        for (i=0; i<300; i=i+1) begin
          @(negedge clk);
          if (done) disable wait_response;
        end
        $display("FAIL: KVS timeout for cmd %h", c);
        $finish;
      end
    end
  endtask

  initial begin
    $dumpfile("cuckoo_atomic_journal_limit.vcd");
    $dumpvars(0, cuckoo_atomic_journal_limit_tb);
    repeat (5) @(negedge clk);
    rst = 0;

    // First create a known, committed key.
    @(negedge clk); txn_begin=1;
    @(negedge clk); txn_begin=0;
    command(8'h01, 32'h12345678, 16'h00AA);
    if (error) begin $display("FAIL: initial CREATE"); $finish; end
    @(negedge clk); txn_commit=1;
    @(negedge clk); txn_commit=0;

    // Begin a second transaction and simulate full journal counter.
    @(negedge clk); txn_begin=1;
    @(negedge clk); txn_begin=0;
    force dut.log_count = 5'd16;
    command(8'h03, 32'h12345678, 16'h00BB);
    if (overflow !== 1'b1) begin
      $display("FAIL: expected txn_journal_overflow=1"); $finish;
    end
    $display("PASS: journal limit detected (simulated log_count=16)");
    // This test must not initiate rollback: simulated log entries are uninitialized.
    // Release forced counter, reset DUT bookkeeping, retain physical RAM contents.
    release dut.log_count;
    @(negedge clk); rst=1;
    repeat (3) @(negedge clk);
    rst=0;
    command(8'h02, 32'h12345678, 16'h0000);
    if (found !== 1'b1 || value_out !== 16'h00AA) begin
      $display("FAIL: old key mutated while journal was full: found=%b value=%h",found,value_out);
      $finish;
    end
    $display("PASS: physical write blocked at journal boundary");
    $display("WARNING: global controller overflow handling and real 16-write saturation NOT validated");
    $finish;
  end
endmodule
