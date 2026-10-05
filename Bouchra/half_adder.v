module half_adder (
    input  wire A,
    input  wire B,
    output wire S,
    output wire Cout
);

    assign S = A ^ B;
    assign Cout = A & B;

endmodule