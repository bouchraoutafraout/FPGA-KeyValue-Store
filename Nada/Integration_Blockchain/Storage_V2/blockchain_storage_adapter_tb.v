`timescale 1ns/1ps
module blockchain_storage_adapter_tb;
reg clk=0, rst=1, storage_start=0;
reg [31:0] storage_index=0;
reg [351:0] storage_header=0;
reg [255:0] storage_hash=0;
wire storage_done, storage_ok;
integer errors=0;
always #5 clk=~clk;
blockchain_storage_adapter DUT (
 .clk(clk),.rst(rst),.storage_start(storage_start),.storage_index(storage_index),
 .storage_header(storage_header),.storage_hash(storage_hash),
 .storage_done(storage_done),.storage_ok(storage_ok));
task write_test;
 input [31:0] idx; input [351:0] hdr; input [255:0] hash;
 input expected;
 integer count;
 begin
  @(negedge clk);
  storage_index=idx; storage_header=hdr; storage_hash=hash;storage_start=1;
  @(negedge clk);storage_start=0;
  count=0;
  while (!storage_done && count<30) begin @(negedge clk);count=count+1; end
  if (count>=30 || storage_ok !== expected) begin
   $display("FAIL : write idx=%0d success=%b expected=%b", idx,storage_ok,expected);
   errors=errors+1;
  end else $display("PASS : write idx=%0d success=%b", idx,storage_ok);
  @(negedge clk);
 end
endtask
initial begin
 repeat(4) @(negedge clk);rst=0;
 // Genesis is reserved in slot 0; controller logical blocks use slots 1,2,...
 if (DUT.STORAGE.mem[0] !== 608'd1) begin $display("FAIL : GENESIS");errors=errors+1; end
 else $display("PASS : GENESIS RESERVED");
 write_test(0,352'h1234,256'hABCD,1);
 write_test(1,352'h5678,256'hEF01,1);
 if (DUT.STORAGE.mem[1] !== {352'h1234,256'hABCD}) begin
   $display("FAIL : PHYSICAL SLOT 1");errors=errors+1;
 end else $display("PASS : PHYSICAL SLOT 1");
 if (DUT.STORAGE.mem[2] !== {352'h5678,256'hEF01}) begin
   $display("FAIL : PHYSICAL SLOT 2");errors=errors+1;
 end else $display("PASS : PHYSICAL SLOT 2");
 write_test(1,352'hAAAA,256'hBBBB,0); // overwrite prohibited
 if (DUT.STORAGE.block_count !== 5'd3) begin
   $display("FAIL : COUNT %0d",DUT.STORAGE.block_count);errors=errors+1;
 end else $display("PASS : COUNT=3 including Genesis");
 if (errors==0) $display("PASS : NEW KHADIJA STORAGE ADAPTER");
 else $display("FAIL : %0d ERRORS",errors);
 $finish;
end
initial begin #10000;$display("FAIL : GLOBAL TIMEOUT");$finish;end
endmodule
