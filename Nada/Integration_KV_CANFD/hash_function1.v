module hash_function1(
    input  wire [31:0] key,
    output wire [7:0]  index
);
    assign index = key[7:0] ^ key[15:8] ^ key[23:16] ^ key[31:24];
endmodule