
`timescale 1ns/1ps

module canfd_timing_tb;

    reg clk = 0;
    reg rst = 1;
    reg start = 0;

    reg [10:0] can_id = 11'h123;
    reg [63:0] data = 64'hA5C3000000000000;
    reg [3:0] dlc = 4'd2;

    wire can_tx, busy, done;

    integer errors = 0;
    integer ticks = 0;
    integer changes = 0;

    time last_tick_time = 0;
    time current_tick_time;
    time bit_period;

    reg first_tick = 1;

    // Horloge FPGA : 100 MHz
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

    // Verification de la periode du Bit Timer
    always @(negedge clk) begin
        if (!rst && dut.tick && busy) begin

            current_tick_time = $time;

            if (!first_tick) begin
                bit_period =
                    current_tick_time - last_tick_time;

                if (bit_period != 1000) begin
                    $display(
                        "FAIL tick : periode=%0t ns",
                        bit_period
                    );
                    errors = errors + 1;
                end
            end

            last_tick_time = current_tick_time;
            first_tick = 0;
            ticks = ticks + 1;
        end
    end

    // Surveillance des transitions de can_tx
    always @(can_tx) begin
        if (!rst && busy) begin
            changes = changes + 1;
            $display(
                "Transition can_tx=%b a %0t ns",
                can_tx, $time
            );
        end
    end

    initial begin

        $dumpfile("canfd_timing.vcd");
        $dumpvars(0, canfd_timing_tb);

        repeat (4) @(negedge clk);
        rst = 0;

        @(negedge clk);
        start = 1;

        @(negedge clk);
        start = 0;

        wait(done);

        @(negedge clk);

        $display("--------------------------------");
        $display("Ticks observes      : %0d", ticks);
        $display("Transitions can_tx  : %0d", changes);
        $display("Erreurs temporelles : %0d", errors);
        $display("--------------------------------");

        if (errors == 0)
            $display("=== TEST PERIODE BIT TIMER REUSSI ===");
        else
            $display("=== TEST TEMPOREL ECHOUE ===");

        $finish;
    end

    // Protection contre une simulation bloquee
    initial begin
        #120000;
        $display("FAIL : timeout");
        $finish;
    end

endmodule
