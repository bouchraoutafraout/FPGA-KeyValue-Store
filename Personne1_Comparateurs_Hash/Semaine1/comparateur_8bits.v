module comparateur_8bits(
    input  wire [7:0] A,
    input  wire [7:0] B,
    output wire sup,
    output wire egal,
    output wire inf
);
    assign egal = (A == B);
    assign sup  = (A > B);
    assign inf  = (A < B);
endmodule