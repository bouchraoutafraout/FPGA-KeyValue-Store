module comparateur_8bits_tb;
    reg [7:0] A, B;
    wire sup, egal, inf;
    comparateur_8bits uut (
        .A(A), .B(B),
        .sup(sup), .egal(egal), .inf(inf)
    );
    initial begin
        $display("   A    B  | sup egal inf");
        A=5;   B=10;  #10 $display("%3d  %3d |  %b   %b   %b", A, B, sup, egal, inf);
        A=200; B=200; #10 $display("%3d  %3d |  %b   %b   %b", A, B, sup, egal, inf);
        A=255; B=0;   #10 $display("%3d  %3d |  %b   %b   %b", A, B, sup, egal, inf);
        A=0;   B=255; #10 $display("%3d  %3d |  %b   %b   %b", A, B, sup, egal, inf);
        $finish;
    end
endmodule