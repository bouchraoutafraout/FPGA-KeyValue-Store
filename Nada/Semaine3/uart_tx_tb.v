module uart_tx_tb;

    reg clk = 0;
    reg reset = 1;
    reg start_tx = 0;
    reg [7:0] data_in = 8'h00;
    wire tx, busy;

    // Instance avec un baud rate rapide pour la simulation
    uart_tx #(
        .CLK_FREQ(1000),
        .BAUD_RATE(100)
    ) uut (
        .clk(clk), .reset(reset),
        .start_tx(start_tx), .data_in(data_in),
        .tx(tx), .busy(busy)
    );

    // Horloge
    always #5 clk = ~clk;

    initial begin
        $display("Debut simulation UART TX");
        #20 reset = 0;

        // Envoyer l'octet 0x41 ('A')
        #10 data_in = 8'h41;
            start_tx = 1;
        #10 start_tx = 0;

        // Attendre la fin de la transmission
        wait (busy == 0);
        #50;

        $display("Transmission terminee");
        $finish;
    end

    // Affiche l'état de la ligne tx à chaque changement
    initial begin
        $monitor("Temps=%0t | tx=%b | busy=%b", $time, tx, busy);
    end

endmodule