
`timescale 1ns/1ps

module canfd_last_stuff_tb;

    reg clk = 0;
    reg rst = 1;
    reg start = 0;

    reg [10:0] can_id = 11'h123;
    reg [63:0] data = 64'hA51F000000000000;
    reg [3:0] dlc = 4'd2;

    wire can_tx;
    wire busy;
    wire done;

    integer checked = 0;
    integer errors = 0;

    always #5 clk = ~clk;

    canfd_tx #(
        .CLK_FREQ(100_000_000)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .can_id(can_id),
        .data(data),
        .dlc(dlc),
        .can_tx(can_tx),
        .busy(busy),
        .done(done)
    );

    // Tester le passage vers le CRC
    always @(negedge clk) begin
        if (!rst && dut.state == 3'd4 && checked == 0) begin

            checked = 1;

            $display("--------------------------------");
            $display("Verification fin des donnees");
            $display("Dernier bit = %b", dut.stuffer.last);
            $display("Longueur serie = %0d", dut.stuffer.run);
            $display("Stuffing en attente = %b",
                     dut.stuffer.run == 3'd5);

            if (dut.stuffer.run == 3'd5) begin
                $display("FAIL : passage au CRC avant");
                $display("       le stuffing final !");
                errors = errors + 1;
            end
            else begin
                $display("PASS : pas de stuffing en attente");
            end

        end
    end

    initial begin
        $dumpfile("canfd_last_stuff.vcd");
        $dumpvars(0, canfd_last_stuff_tb);

        repeat (5) @(negedge clk);
        rst = 0;

        repeat (3) @(negedge clk);
        start = 1;

        @(negedge clk);
        start = 0;

        wait(done == 1'b1);

        @(negedge clk);

        if (checked == 0) begin
            $display("FAIL : transition CRC non observee");
            errors = errors + 1;
        end

        $display("--------------------------------");
        $display("Erreurs = %0d", errors);

        if (errors == 0)
            $display("=== TEST REUSSI ===");
        else
            $display("=== PROBLEME DETECTE ===");

        $finish;
    end

    initial begin
        #200000;
        $display("FAIL : TIMEOUT");
        $finish;
    end

endmodule
