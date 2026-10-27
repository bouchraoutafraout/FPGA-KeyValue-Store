`timescale 1ns/1ps

module blockchain_storage_adapter_tb;

    reg clk = 0;
    reg rst = 1;
    reg storage_start = 0;
    reg [31:0] storage_index = 0;
    reg [351:0] storage_header = 0;
    reg [255:0] storage_hash = 0;

    wire storage_done;
    wire storage_ok;

    integer errors = 0;

    always #5 clk = ~clk;

    blockchain_storage_adapter DUT (
        .clk(clk),
        .rst(rst),
        .storage_start(storage_start),
        .storage_index(storage_index),
        .storage_header(storage_header),
        .storage_hash(storage_hash),
        .storage_done(storage_done),
        .storage_ok(storage_ok)
    );

    task test_write;
        input [31:0] idx;
        input [351:0] header;
        input [255:0] hash_value;
        input expected_ok;
        integer cycles;
        begin
            @(negedge clk);
            storage_index = idx;
            storage_header = header;
            storage_hash = hash_value;
            storage_start = 1;

            @(negedge clk);
            storage_start = 0;

            cycles = 0;
            while (!storage_done && cycles < 20) begin
                @(negedge clk);
                cycles = cycles + 1;
            end

            if (cycles == 20) begin
                $display("FAIL : TIMEOUT index=%0d", idx);
                errors = errors + 1;
            end else if (storage_ok !== expected_ok) begin
                $display("FAIL : index=%0d ok=%b", idx, storage_ok);
                errors = errors + 1;
            end else begin
                $display("PASS : index=%0d ok=%b", idx, storage_ok);
            end

            @(negedge clk);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst = 0;

        test_write(0, 352'h1234, 256'hABCD, 1'b1);
        test_write(1, 352'h5678, 256'hEF01, 1'b1);
        test_write(15, 352'h9999, 256'hAAAA, 1'b1);

        // Index hors capacite : doit etre refuse
        test_write(16, 352'h1111, 256'h2222, 1'b0);

        // Verifier que les donnees du bloc 1 sont conservees
        @(negedge clk);
        force DUT.saved_index = 4'd1;
        #1;

        if (DUT.read_data !== {352'h5678,256'hEF01}) begin
            $display("FAIL : RELECTURE BLOC 1");
            errors = errors + 1;
        end else begin
            $display("PASS : RELECTURE BLOC 1");
        end

        release DUT.saved_index;

        if (errors == 0)
            $display("PASS : BLOCKCHAIN STORAGE REAL");
        else
            $display("FAIL : BLOCKCHAIN STORAGE errors=%0d", errors);

        $finish;
    end

endmodule
