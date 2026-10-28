`timescale 1ns/1ps

module canfd_rx_adapter_tb;

    reg clk = 0;
    reg rst = 1;

    reg [63:0] can_data = 0;
    reg [3:0] can_dlc = 0;
    reg can_frame_done = 0;
    reg can_frame_valid = 0;

    wire [7:0] rx_data;
    wire rx_valid;
    wire rx_frame_done;
    wire rx_error;
    wire busy;

    integer count = 0;
    integer errors = 0;

    reg [7:0] expected [0:7];

    always #5 clk = ~clk;

    canfd_rx_adapter dut (
        .clk(clk),
        .rst(rst),
        .can_data(can_data),
        .can_dlc(can_dlc),
        .can_frame_done(can_frame_done),
        .can_frame_valid(can_frame_valid),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .rx_frame_done(rx_frame_done),
        .rx_error(rx_error),
        .busy(busy)
    );

    always @(negedge clk) begin
        if (!rst && rx_valid) begin
            $display("Octet %0d : 0x%02h", count, rx_data);

            if (count >= 8 || rx_data !== expected[count])
                errors = errors + 1;

            count = count + 1;
        end
    end

    initial begin
        expected[0] = 8'h07;  // LEN
        expected[1] = 8'h01;  // CREATE
        expected[2] = 8'h12;
        expected[3] = 8'h34;
        expected[4] = 8'h56;
        expected[5] = 8'h78;
        expected[6] = 8'h00;
        expected[7] = 8'hAA;

        $dumpfile("canfd_rx_adapter_tb.vcd");
        $dumpvars(0, canfd_rx_adapter_tb);

        repeat (4) @(negedge clk);
        rst = 0;

        repeat (3) @(negedge clk);

        can_data = 64'h07011234567800AA;
        can_dlc = 4'd8;
        can_frame_valid = 1;
        can_frame_done = 1;

        @(negedge clk);
        can_frame_done = 0;

        wait (rx_frame_done);
        @(negedge clk);
        #1;

        $display("");
        $display("Octets recus : %0d", count);
        $display("Erreurs      : %0d", errors);

        if (count == 8 && errors == 0 && rx_error == 0)
            $display("PASS : ADAPTATEUR CAN-FD -> OCTETS");
        else
            $display("FAIL : ADAPTATEUR");

        $finish;
    end

    initial begin
        #10000;
        $display("FAIL : TIMEOUT ADAPTATEUR");
        $finish;
    end

endmodule
