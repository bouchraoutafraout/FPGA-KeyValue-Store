`timescale 1ns/1ps
module canfd_response_encoder_tb;
    reg clk=0, rst=1, resp_valid=0, tx_busy=0;
    reg [7:0] resp_cmd=0, resp_status=0;
    reg [15:0] resp_value=0;
    wire resp_ready, tx_start, encoder_busy;
    wire [63:0] tx_data;
    wire [3:0] tx_dlc;
    integer errors=0;
    always #5 clk=~clk;
    canfd_response_encoder dut (
        .clk(clk), .rst(rst),
        .resp_valid(resp_valid), .resp_ready(resp_ready),
        .resp_cmd(resp_cmd), .resp_status(resp_status),
        .resp_value(resp_value), .tx_busy(tx_busy),
        .tx_start(tx_start), .tx_data(tx_data),
        .tx_dlc(tx_dlc), .encoder_busy(encoder_busy)
    );
    initial begin
        repeat(3) @(negedge clk);
        rst=0;
        @(negedge clk);
        if (!resp_ready) errors=errors+1;
        resp_valid=1;
        resp_cmd=8'h02;
        resp_status=8'h00;
        resp_value=16'h00AA;
        @(negedge clk);
        resp_valid=0;
        if (tx_start !== 1 || tx_data !== 64'h04020000AA000000 || tx_dlc !== 8) begin
            $display("FAIL: packet/start DATA=%h START=%b DLC=%d",tx_data,tx_start,tx_dlc);
            errors=errors+1;
        end
        @(negedge clk);
        tx_busy=1;
        @(negedge clk);
        if (!encoder_busy) errors=errors+1;
        repeat(3) @(negedge clk);
        tx_busy=0;
        repeat(2) @(negedge clk);
        if (!resp_ready) begin
            $display("FAIL: ready not restored");
            errors=errors+1;
        end
        if (errors==0) $display("PASS : CAN-FD RESPONSE ENCODER");
        else $display("FAIL : %0d errors",errors);
        $finish;
    end
    initial begin #10000; $display("FAIL: TIMEOUT"); $finish; end
endmodule
