`timescale 1ns/1ps
module blockchain_storage_chain_verify_tb;
 reg clk=0; always #5 clk=~clk;
 reg rst=1,wr_en=0,verify_start=0;
 reg [607:0] block_data_in=0;
 reg [3:0] verify_index=0;
 wire wr_ready,wr_err,full,verify_busy,verify_done,verify_valid,verify_link_ok,verify_hash_ok,verify_error;
 wire [4:0] block_count;
 wire [255:0] verify_computed_hash;
 blockchain_storage_chain_verify dut(.*);
 integer failures=0;
 task write_block(input [607:0] data); begin
   @(negedge clk); if(!wr_ready) begin $display("FAIL: not ready to write");failures=failures+1;end
   block_data_in=data;wr_en=1;
   @(negedge clk);wr_en=0;
 end endtask
 task verify(input [3:0] ix,input expected_valid,input expected_link,input expected_hash,input expected_error); integer n;begin
   @(negedge clk);verify_index=ix;verify_start=1;
   @(negedge clk);verify_start=0;
   n=0;
   while(!verify_done && n<500) begin @(negedge clk);n=n+1;end
   if(!verify_done) begin $display("FAIL: timeout index %0d",ix);failures=failures+1;end
   else if(verify_valid!==expected_valid || verify_link_ok!==expected_link || verify_hash_ok!==expected_hash || verify_error!==expected_error) begin
      $display("FAIL: index=%0d valid=%b link=%b hash=%b err=%b expected=%b%b%b%b",ix,verify_valid,verify_link_ok,verify_hash_ok,verify_error,expected_valid,expected_link,expected_hash,expected_error);
      failures=failures+1;
   end else $display("PASS: index=%0d valid=%b link=%b hash=%b err=%b",ix,verify_valid,verify_link_ok,verify_hash_ok,verify_error);
 end endtask
 initial begin
   repeat(3) @(negedge clk);rst=0;
   if(block_count!==1) begin $display("FAIL: genesis block_count");failures=failures+1;end
   verify(0,0,0,0,1); // not written yet
   write_block({32'd0,256'h0000000000000000000000000000000000000000000000000000000000000000,64'h07011234567800aa,256'h5340d663384c25c0bff9964af0d47b3abb746752ba4af91408e641f59a2cbc7d});
   write_block({32'd1,256'h5340d663384c25c0bff9964af0d47b3abb746752ba4af91408e641f59a2cbc7d,64'h0703123456780055,256'haf02679bbe0c555e390d2f41ccf0eb55d9e7ba3867542ea3ce3c802268eb835f});
   write_block({32'd2,256'habababababababababababababababababababababababababababababababab,64'h0702123456780011,256'h4d71fde821d1c0ec3754ae4613f78698fbfbfdbfa67f0f70039d44a4a1d2f948});
   write_block({32'd3,256'h4d71fde821d1c0ec3754ae4613f78698fbfbfdbfa67f0f70039d44a4a1d2f948,64'h0704123456780022,256'h22d4800e1bf62384fb847828dd4275e2b90b22687e7ca3cb0d0297f10297fbe9});
   if(block_count!==5) begin $display("FAIL: block_count %0d",block_count);failures=failures+1;end
   verify(0,1,1,1,0);
   verify(1,1,1,1,0);
   verify(2,0,0,1,0); // wrong previous hash, correct SHA
   verify(3,0,1,0,0); // correct link, corrupted stored SHA
   verify(4,0,0,0,1); // invalid logical index
   if(failures==0) $display("PASS: BRAM + REAL CHAIN VALIDATOR TESTS");
   else $display("FAIL: %0d tests failed",failures);
   $finish;
 end
 initial begin #200000; $display("FAIL GLOBAL TIMEOUT");$finish;end
endmodule
