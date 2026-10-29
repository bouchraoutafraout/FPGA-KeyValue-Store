`timescale 1ns/1ps
module block_builder_nada_sha_storage_tb;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, tx_valid=0;
    reg [63:0] tx_data=0;
    wire tx_ready, block_done, storage_ok, busy;
    wire [31:0] next_index, blocks_stored;
    wire [255:0] last_hash;
    integer errors=0;
    integer timeout;

    block_builder_nada_sha_storage_top DUT (
       .clk(clk),.rst(rst),.tx_valid(tx_valid),.tx_data(tx_data),
       .tx_ready(tx_ready),.block_done(block_done),.storage_ok(storage_ok),
       .next_index(next_index),.last_hash(last_hash),
       .blocks_stored(blocks_stored),.busy(busy)
    );

    task send_tx;
       input [63:0] tx;
       begin
          timeout=0;
          while (!tx_ready && timeout<30) begin @(negedge clk); timeout=timeout+1; end
          if (!tx_ready) begin $display("FAIL: builder not ready"); $finish; end
          tx_data=tx;
          tx_valid=1;
          @(negedge clk);
          tx_valid=0;
       end
    endtask

    task wait_block;
       input [31:0] expected_index;
       input [255:0] expected_hash;
       begin
          timeout=0;
          while (!block_done && timeout<500) begin @(negedge clk); timeout=timeout+1; end
          if (!block_done) begin $display("FAIL: no stored block"); $finish; end
          @(negedge clk);
          if (next_index !== expected_index || last_hash !== expected_hash) begin
             $display("FAIL: index=%0d hash=%064h", next_index, last_hash);
             errors=errors+1;
          end else $display("PASS: block %0d sha256=%064h", expected_index-1, last_hash);
       end
    endtask
    initial begin
       repeat (3) @(negedge clk);
       rst=0;
       send_tx(64'h00011122334400AA);
       wait_block(32'd1,256'h0325b114dcefab9e94fcd2fd751adf9c21a8338f439272fa3cc087f1d666eb84);
       send_tx(64'h0003556677880055);
       wait_block(32'd2,256'hccf27749657c6b571174834a346f288318e6bc5b1ccc07320a7b1e46559734e9);
       if (errors==0) $display("PASS: SANAE BUILDER + BOUCHRA SHA + KHADIJA BRAM");
       else $display("FAIL: %0d errors", errors);
       $finish;
    end
endmodule
