`timescale 1ns/1ps
module blockchain_kvs_real_tb;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, tx_valid=0, result_ready=1;
    reg [63:0] tx_data=0;
    wire tx_ready, result_valid, result_ok, busy;
    wire [3:0] result_error;
    wire [31:0] result_index, next_index;
    wire [255:0] last_hash;
    integer errors=0;

    blockchain_kvs_real_top dut (
        .clk(clk), .rst(rst), .tx_valid(tx_valid), .tx_ready(tx_ready),
        .tx_data(tx_data), .result_valid(result_valid),
        .result_ready(result_ready), .result_ok(result_ok),
        .result_error(result_error), .result_index(result_index),
        .next_index(next_index), .last_hash(last_hash), .busy(busy)
    );

    task send_tx;
        input [7:0] cmd;
        input [31:0] key;
        input [15:0] val;
        input expect_ok;
        input [31:0] expect_next;
        integer i;
        reg reached;
        begin
            reached=0;
            for(i=0;i<10000 && !tx_ready;i=i+1) @(negedge clk);
            if (!tx_ready) begin
                $display("FAIL: ready timeout"); errors=errors+1;
            end else begin
                @(negedge clk);
                tx_data={8'd0,cmd,key,val};
                tx_valid=1;
                @(negedge clk);
                tx_valid=0;
                for(i=0;i<100000 && !reached;i=i+1) begin
                    if(result_valid) reached=1;
                    else @(negedge clk);
                end
                if(!reached) begin
                    $display("FAIL: response timeout cmd=%h",cmd);
                    errors=errors+1;
                end else if(result_ok !== expect_ok || next_index !== expect_next) begin
                    $display("FAIL: cmd=%h key=%h ok=%b next=%0d err=%h (expected ok=%b next=%0d)",
                        cmd,key,result_ok,next_index,result_error,expect_ok,expect_next);
                    errors=errors+1;
                end else begin
                    $display("PASS: cmd=%h key=%h ok=%b next_index=%0d err=%h",
                        cmd,key,result_ok,next_index,result_error);
                end
                @(negedge clk);
            end
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);
        rst=0;
        repeat(5) @(negedge clk);
        send_tx(8'h01,32'h11223344,16'h00AA,1'b1,32'd1);
        send_tx(8'h01,32'h11223344,16'h00BB,1'b0,32'd1);
        send_tx(8'h03,32'h11223344,16'h0055,1'b1,32'd2);
        send_tx(8'h03,32'h55667788,16'h0055,1'b0,32'd2);
        send_tx(8'h01,32'h00000000,16'h0011,1'b0,32'd2);
        if(errors==0) $display("PASS: REAL KVS + SANAE VALIDATOR + BUILDER + SHA256 + BRAM");
        else $display("FAIL: %0d errors",errors);
        $finish;
    end
endmodule
