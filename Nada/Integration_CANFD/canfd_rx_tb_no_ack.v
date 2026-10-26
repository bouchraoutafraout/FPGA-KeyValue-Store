`timescale 1ns/1ps

module canfd_rx_tb_no_ack;

    reg clk = 0;
    reg rst = 1;
    reg start = 0;

    wire can_tx;
    wire busy;
    wire done;
    wire ack_error;

    // Aucun recepteur ne force le bus a 0.
    // Le TX voit donc un bit recessif pendant l'ACK.
    wire can_bus = can_tx;

    always #5 clk = ~clk;

    canfd_tx #(
        .CLK_FREQ(100_000_000)
    ) tx (
        .clk(clk),
        .rst(rst),
        .start(start),
        .can_id(11'h123),
        .data(64'h123456789ABCDEF0),
        .dlc(4'd8),
        .can_rx(can_bus),
        .can_tx(can_tx),
        .busy(busy),
        .done(done),
        .ack_error(ack_error)
    );

    initial begin
        $dumpfile("canfd_no_ack.vcd");
        $dumpvars(0, canfd_rx_tb_no_ack);

        repeat (5) @(negedge clk);
        rst = 0;

        repeat (5) @(negedge clk);
        start = 1;

        @(negedge clk);
        start = 0;

        wait (done === 1'b1);
        @(negedge clk);
        #1;

        $display("");
        $display("==================================");
        $display("TEST ABSENCE ACK - DLC 8");
        $display("==================================");
        $display("TX done   : %b", done);
        $display("ACK error : %b", ack_error);

        if (ack_error === 1'b1)
            $display("PASS : ABSENCE ACK DETECTEE");
        else
            $display("FAIL : ABSENCE ACK NON DETECTEE");

        $finish;
    end

    initial begin
        #200000;
        $display("FAIL : TIMEOUT NO ACK");
        $display("busy=%b done=%b ack_error=%b",
                 busy, done, ack_error);
        $finish;
    end

endmodule
