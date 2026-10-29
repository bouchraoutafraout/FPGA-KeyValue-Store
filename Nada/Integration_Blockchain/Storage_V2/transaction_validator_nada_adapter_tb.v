`timescale 1ns/1ps
module transaction_validator_nada_adapter_tb;
  reg clk=0, rst=1, validator_start=0;
  always #5 clk=~clk;
  reg [63:0] validator_tx=0;
  wire validator_done, validator_accept, blk_hold, kv_start, tx_acc_valid;
  wire [7:0] kv_cmd;
  wire [31:0] kv_key;
  wire [15:0] kv_value;
  wire [63:0] tx_acc_data;
  wire [3:0] validation_error_code;
  reg kv_busy=0, kv_done=0, kv_found=0, kv_error=0;
  reg [15:0] kv_value_out=0;
  reg exists=0;
  reg [31:0] saved_key=0;
  reg [15:0] saved_value=0;
  reg [7:0] pending_cmd=0;
  reg [31:0] pending_key=0;
  reg [15:0] pending_value=0;
  reg [1:0] delay_count=0;
  integer accepted_count=0;
  transaction_validator_nada_adapter DUT (
    .clk(clk), .rst(rst), .validator_start(validator_start), .validator_tx(validator_tx),
    .validator_done(validator_done), .validator_accept(validator_accept),
    .blk_ready(1'b1), .blk_hold(blk_hold),
    .kv_cmd(kv_cmd),.kv_key(kv_key),.kv_value(kv_value),.kv_start(kv_start),
    .kv_busy(kv_busy),.kv_done(kv_done),.kv_found(kv_found),
    .kv_value_out(kv_value_out),.kv_error(kv_error),
    .tx_acc_valid(tx_acc_valid),.tx_acc_data(tx_acc_data),
    .validation_error_code(validation_error_code)
  );
  // Minimal KVS model, not the real KVS RTL.
  always @(posedge clk) begin
    kv_done <= 0;
    if (kv_start && !kv_busy) begin
      kv_busy<=1;
      pending_cmd<=kv_cmd; pending_key<=kv_key; pending_value<=kv_value;
      delay_count<=2;
    end else if (kv_busy) begin
      if (delay_count!=0) delay_count<=delay_count-1'b1;
      else begin
        kv_busy<=0; kv_done<=1; kv_error<=0;
        kv_found<=exists && pending_key==saved_key;
        kv_value_out<=exists && pending_key==saved_key ? saved_value : 16'd0;
        if(pending_cmd==8'h01 && !exists) begin exists<=1; saved_key<=pending_key; saved_value<=pending_value; end
        if(pending_cmd==8'h03 && exists && pending_key==saved_key) saved_value<=pending_value;
      end
    end
    if(tx_acc_valid) accepted_count<=accepted_count+1;
  end
  task run(input [7:0] cmd, input [31:0] key, input [15:0] value, input expected_accept);
    integer cycles;
    begin
      @(negedge clk); validator_tx={8'd0,cmd,key,value}; validator_start=1;
      @(negedge clk); validator_start=0;
      cycles=0;
      while(!validator_done && cycles<250) begin @(negedge clk); cycles=cycles+1; end
      if(cycles>=250) $fatal(1,"Timeout validator_done");
      if(validator_accept !== expected_accept) $fatal(1,"Wrong accept cmd %h expected %b got %b",cmd,expected_accept,validator_accept);
      $display("PASS cmd=%h key=%h accept=%b code=%d",cmd,key,validator_accept,validation_error_code);
      @(negedge clk);
    end
  endtask
  initial begin
    repeat(4) @(negedge clk); rst=0;
    run(8'h01,32'h11223344,16'h00aa,1'b1);
    run(8'h01,32'h11223344,16'h00bb,1'b0);
    run(8'h03,32'h11223344,16'h00bb,1'b1);
    run(8'h03,32'h55667788,16'h00cc,1'b0);
    run(8'h01,32'h00000000,16'h00aa,1'b0);
    if(accepted_count!=2) $fatal(1,"Expected two accepted transactions, got %d",accepted_count);
    $display("PASS NADA + SANAE TRANSACTION VALIDATOR ADAPTER (mock KVS)");
    $finish;
  end
endmodule
