module comparateur_1bit(
    input  wire A,
    input  wire B,
    output wire sup,   // A > B
    output wire egal,  // A = B
    output wire inf    // A < B
);
    assign egal = (A == B);
    assign sup  = (A & ~B);   // A=1, B=0
    assign inf  = (~A & B);   // A=0, B=1
endmodule