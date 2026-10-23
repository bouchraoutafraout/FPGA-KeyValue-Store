
`timescale 1ns/1ps

module canfd_ack_tb;

    reg clk = 0;
    reg rst = 1;
    reg start = 0;
    reg ack_enable = 0;

    reg [10:0] can_id = 11'h123;
    reg [63:0] data = 64'hA51F000000000000;
    reg [3:0] dlc = 4'd2;

    wire can_tx;
    wire can_rx;
    wire busy;
    wire done;
    wire ack_error;

    integer errors = 0;

    always #5 clk = ~clk;

    // Modele simplifie du recepteur de Bouchra.
    // Le bus devient dominant uniquement
    // pendant l'ACK slot lorsque ack_enable=1.
    assign can_rx =
        (ack_enable &&
         dut.state == 4'd7 &&
         dut.tail_index == 4'd2)
        ? 1'b0 : 1'b1;

    canfd_tx #(
        .CLK_FREQ(100_000_000)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .can_id(can_id),
        .data(data),
        .dlc(dlc),
        .can_rx(can_rx),
        .can_tx(can_tx),
        .busy(busy),
        .done(done),
        .ack_error(ack_error)
    );

    task test_ack;
        input provide_ack;
        input expected_error;

        begin
            wait(busy == 0);
            @(negedge clk);

            ack_enable = provide_ack;
            start = 1;

            @(negedge clk);
            start = 0;

            wait(done == 1);

            @(negedge clk);

            $display("------------------------------");
            $display("ACK fourni : %b", provide_ack);
            $display("ACK error  : %b", ack_error);

            if (ack_error !== expected_error) begin
                $display("FAIL : resultat ACK incorrect");
                errors = errors + 1;
            end else begin
                $display("PASS : resultat ACK correct");
            end

            repeat (5) @(negedge clk);
        end
    endtask

    initial begin

        $dumpfile("canfd_ack.vcd");
        $dumpvars(0, canfd_ack_tb);

        repeat (5) @(negedge clk);
        rst = 0;

        $display("=== TEST ACK RECU ===");
        test_ack(1'b1, 1'b0);

        $display("=== TEST ACK ABSENT ===");
        test_ack(1'b0, 1'b1);

        $display("------------------------------");
        $display("Erreurs = %0d", errors);

        if (errors == 0)
            $display("=== TEST ACK REUSSI ===");
        else
            $display("=== TEST ACK ECHEC ===");

        $finish;
    end

    initial begin
        #300000;
        $display("FAIL : TIMEOUT");
        $finish;
    end

endmodule
