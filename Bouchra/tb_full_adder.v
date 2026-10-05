`timescale 1ns/1ps

module tb_full_adder;

    reg A;
    reg B;
    reg Cin;

    wire S;
    wire Cout;

    integer i;

    full_adder uut (
        .A(A),
        .B(B),
        .Cin(Cin),
        .S(S),
        .Cout(Cout)
    );

    initial begin

        $dumpfile("full_adder.vcd");
        $dumpvars(0, tb_full_adder);

        $display("A B Cin | S Cout");
        $display("----------------");

        for (i = 0; i < 8; i = i + 1) begin

            {A, B, Cin} = i;

            #10;

            $display("%b %b  %b  | %b %b",
                     A, B, Cin, S, Cout);

        end

        $finish;

    end

endmodule