module hash_function1_tb;
    reg  [31:0] key;
    wire [7:0]  index;

    hash_function1 uut (
        .key(key),
        .index(index)
    );

    initial begin
        $display("Key (hex)   | Index (hex)");
        key = 32'h00000001; #10 $display("%h | %h", key, index);
        key = 32'h12345678; #10 $display("%h | %h", key, index);
        key = 32'hFFFFFFFF; #10 $display("%h | %h", key, index);
        key = 32'hAABBCCDD; #10 $display("%h | %h", key, index);
        $finish;
    end
endmodule