`timescale 1ns/1ps

module tb_half_adder;

    reg A;
    reg B;

    wire S;
    wire Cout;

    half_adder uut (
        .A(A),
        .B(B),
        .S(S),
        .Cout(Cout)
    );

    initial begin

        $dumpfile("half_adder.vcd");
        $dumpvars(0, tb_half_adder);

        $display("A B | S Cout");
        $display("-------------");

        A = 0; B = 0;
        #10;
        $display("%b %b | %b %b", A, B, S, Cout);

        A = 0; B = 1;
        #10;
        $display("%b %b | %b %b", A, B, S, Cout);

        A = 1; B = 0;
        #10;
        $display("%b %b | %b %b", A, B, S, Cout);

        A = 1; B = 1;
        #10;
        $display("%b %b | %b %b", A, B, S, Cout);

        $finish;

    end

endmodule