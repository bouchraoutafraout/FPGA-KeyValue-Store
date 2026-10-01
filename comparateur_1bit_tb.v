module comparateur_1bit_tb;
    reg A, B;
    wire sup, egal, inf;
    comparateur_1bit uut (
        .A(A), .B(B),
        .sup(sup), .egal(egal), .inf(inf)
    );
    initial begin
        $display("A B | sup egal inf");
        A=0; B=0; #10 $display("%b %b |  %b   %b   %b", A, B, sup, egal, inf);
        A=0; B=1; #10 $display("%b %b |  %b   %b   %b", A, B, sup, egal, inf);
        A=1; B=0; #10 $display("%b %b |  %b   %b   %b", A, B, sup, egal, inf);
        A=1; B=1; #10 $display("%b %b |  %b   %b   %b", A, B, sup, egal, inf);
        $finish;
    end
endmodule