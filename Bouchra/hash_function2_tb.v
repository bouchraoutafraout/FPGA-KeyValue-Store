`timescale 1ns/1ps

module hash_function2_tb;

    reg [31:0] key;
    wire [7:0] index;

    hash_function2 uut (
        .key(key),
        .index(index)
    );

    initial begin

        $dumpfile("hash_function2.vcd");
        $dumpvars(0, hash_function2_tb);

        $display("Key (hex) | Hash2 Index");

        key = 32'h00000001;
        #10;
        $display("%h | %h", key, index);

        key = 32'h12345678;
        #10;
        $display("%h | %h", key, index);

        key = 32'hFFFFFFFF;
        #10;
        $display("%h | %h", key, index);

        key = 32'hAABBCCDD;
        #10;
        $display("%h | %h", key, index);

        $finish;

    end

endmodule