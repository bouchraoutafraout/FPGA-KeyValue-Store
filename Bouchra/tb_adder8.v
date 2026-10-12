`timescale 1ns/1ps

module tb_adder8;

    reg [7:0] A;
    reg [7:0] B;
    reg Cin;

    wire [7:0] S;
    wire Cout;

    adder8 uut (
        .A(A),
        .B(B),
        .Cin(Cin),
        .S(S),
        .Cout(Cout)
    );

    initial begin

        $dumpfile("adder8.vcd");
        $dumpvars(0, tb_adder8);

        Cin = 0;

        $display("A + B = Cout S");
        $display("----------------");

        A = 15;
        B = 20;
        #10;
        $display("%d + %d = %b %d", A, B, Cout, S);

        A = 200;
        B = 100;
        #10;
        $display("%d + %d = %b %d", A, B, Cout, S);

        A = 255;
        B = 1;
        #10;
        $display("%d + %d = %b %d", A, B, Cout, S);

        A = 100;
        B = 50;
        #10;
        $display("%d + %d = %b %d", A, B, Cout, S);

        $finish;

    end

endmodule