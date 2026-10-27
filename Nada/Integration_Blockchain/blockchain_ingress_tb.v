`timescale 1ns/1ps
module blockchain_ingress_tb;
    reg clk=0, rst=1, frame_done=0, frame_valid=0, tx_ready=0;
    reg [3:0] frame_dlc=8;
    reg [63:0] frame_data=0;
    wire tx_valid, overflow;
    wire [63:0] tx_data;
    always #5 clk=~clk;
    blockchain_ingress DUT (.*);
    integer errors=0;
    initial begin
        repeat(3) @(negedge clk);
        rst=0;
        @(negedge clk);
        frame_data=64'h07011234567800AA;
        frame_done=1; frame_valid=1;
        @(negedge clk);
        frame_done=0;
        repeat(3) @(negedge clk);
        if(tx_valid !== 1 || tx_data !== 64'h07011234567800AA) begin
            $display("FAIL : stored transaction not held"); errors=errors+1;
        end
        tx_ready=1;
        @(negedge clk);
        tx_ready=0;
        if(tx_valid !== 0) begin
            $display("FAIL : valid was not cleared on handshake"); errors=errors+1;
        end
        frame_data=64'h0000000000000001;
        frame_valid=0; frame_done=1;
        @(negedge clk); frame_done=0;
        if(tx_valid !== 0) begin
            $display("FAIL : invalid frame accepted"); errors=errors+1;
        end
        if(errors==0 && overflow==0) $display("PASS : BLOCKCHAIN INGRESS FIFO");
        else $display("FAIL : BLOCKCHAIN INGRESS FIFO errors=%0d",errors);
        $finish;
    end
endmodule
