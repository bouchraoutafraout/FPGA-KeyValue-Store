
`timescale 1ns/1ps

module canfd_bits_tb;

    reg clk = 0;
    reg rst = 1;
    reg start = 0;

    reg [10:0] can_id = 0;
    reg [63:0] data = 0;
    reg [3:0] dlc = 0;

    wire can_tx;
    wire busy;
    wire done;

    integer errors = 0;
    integer useful_bits = 0;
    integer stuff_bits = 0;
    integer total_bits_expected = 0;
    integer cycles = 0;
    integer run_length = 0;

    reg [85:0] expected_payload;
    reg monitor_enable = 0;
    reg last_bit = 1'b1;
    reg expected_bit;

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

    // Observer les sorties du stuffer
    // apres les mises a jour du front montant.
    always @(negedge clk) begin

        if (!rst && monitor_enable &&
            dut.out_valid &&
            ((dut.state == 3'd2) ||
             (dut.state == 3'd3))) begin

            if (dut.out_is_stuff) begin

                stuff_bits = stuff_bits + 1;

                if (run_length != 5 ||
                    dut.out_bit !== ~last_bit) begin

                    $display(
                        "FAIL STUFF : bit=%b, run=%0d",
                        dut.out_bit, run_length
                    );

                    errors = errors + 1;

                end

            end
            else begin

                if (useful_bits >= total_bits_expected) begin

                    $display("FAIL : bit utile supplementaire");
                    errors = errors + 1;

                end
                else begin

                    expected_bit =
                        expected_payload[85-useful_bits];

                    if (dut.out_bit !== expected_bit) begin

                        $display(
                            "FAIL BIT %0d : attendu=%b obtenu=%b",
                            useful_bits,
                            expected_bit,
                            dut.out_bit
                        );

                        errors = errors + 1;

                    end

                end

                if (run_length == 5) begin
                    $display(
                        "FAIL : stuffing manquant avant bit %0d",
                        useful_bits
                    );
                    errors = errors + 1;
                end

                useful_bits = useful_bits + 1;

            end

            if (run_length == 0 ||
                dut.out_bit !== last_bit)
                run_length = 1;
            else
                run_length = run_length + 1;

            last_bit = dut.out_bit;

        end

    end

    task test_frame;

        input [10:0] test_id;
        input [63:0] test_data;
        input [3:0] test_dlc;

        integer old_errors;

        begin

            $display("");
            $display("==============================");
            $display(
                "TEST ID=%h DLC=%0d DATA=%h",
                test_id, test_dlc, test_data
            );

            wait(busy === 1'b0);
            @(negedge clk);

            can_id = test_id;
            data = test_data;
            dlc = test_dlc;

            // Meme disposition des champs que
            // l'implementation TX actuelle.
            expected_payload = {
                1'b0,
                test_id,
                1'b1,
                1'b0,
                1'b1,
                1'b0,
                1'b0,
                1'b0,
                test_dlc,
                test_data
            };

            total_bits_expected = 22 + (test_dlc * 8);

            useful_bits = 0;
            stuff_bits = 0;
            run_length = 0;
            last_bit = 1'b1;
            cycles = 0;
            old_errors = errors;

            monitor_enable = 1;

            start = 1;
            @(negedge clk);
            start = 0;

            while (busy === 1'b1 && cycles < 25000) begin
                @(negedge clk);
                cycles = cycles + 1;
            end

            monitor_enable = 0;

            if (cycles >= 25000) begin
                $display("FAIL : timeout");
                errors = errors + 1;
            end

            if (useful_bits != total_bits_expected) begin
                $display(
                    "FAIL : %0d bits utiles, %0d attendus",
                    useful_bits,
                    total_bits_expected
                );
                errors = errors + 1;
            end

            $display("Bits utiles : %0d", useful_bits);
            $display("Bits stuffing : %0d", stuff_bits);

            if (errors == old_errors)
                $display("PASS : bits utiles et stuffing");
            else
                $display("FAIL : erreurs detectees");

            repeat (3) @(negedge clk);

        end

    endtask

    initial begin

        $dumpfile("canfd_bits.vcd");
        $dumpvars(0, canfd_bits_tb);

        repeat (5) @(negedge clk);
        rst = 0;

        test_frame(
            11'h100,
            64'h0000000000000000,
            4'd0
        );

        test_frame(
            11'h123,
            64'hA5C3000000000000,
            4'd2
        );

        test_frame(
            11'h456,
            64'h123456789ABCDEF0,
            4'd8
        );

        $display("");
        $display("==============================");
        $display("TOTAL ERREURS : %0d", errors);

        if (errors == 0)
            $display("=== TEST BITS REUSSI ===");
        else
            $display("=== TEST BITS ECHEC ===");

        $finish;
    end

    initial begin
        #1000000;
        $display("FAIL : timeout global");
        $finish;
    end

endmodule

