`timescale 1ns/1ps

module search_tb;

    localparam KEY_W   = 32;
    localparam VAL_W   = 16;
    localparam ADDR_W  = 8;
    localparam ENTRY_W = 1 + KEY_W + VAL_W;

    reg                  clk = 1'b0;
    reg                  rst = 1'b1;
    reg                  start = 1'b0;
    reg  [KEY_W-1:0]     key = {KEY_W{1'b0}};
    wire                 busy;
    wire                 done;
    wire                 found;
    wire [VAL_W-1:0]     value;
    wire                 table_sel;
    wire [ADDR_W-1:0]    addr_found;
    wire [ADDR_W-1:0]    addr1;
    wire [ADDR_W-1:0]    addr2;
    reg  [ENTRY_W-1:0]   data1;
    reg  [ENTRY_W-1:0]   data2;

    reg  [ENTRY_W-1:0]   mem1 [0:(1<<ADDR_W)-1];
    reg  [ENTRY_W-1:0]   mem2 [0:(1<<ADDR_W)-1];

    reg  [KEY_W-1:0]     probe_key = {KEY_W{1'b0}};
    wire [7:0]           probe_h1;
    wire [7:0]           probe_h2;
    wire [31:0]          probe_key_extended = probe_key;
    wire [7:0]           probe_index1;
    wire [7:0]           probe_index2;

    integer i;
    integer errors = 0;

    search #(.KEY_W(KEY_W), .VAL_W(VAL_W), .ADDR_W(ADDR_W)) dut (
        .clk(clk), .rst(rst), .start(start), .key(key),
        .busy(busy), .done(done), .found(found), .value(value),
        .table_sel(table_sel), .addr_found(addr_found),
        .addr1(addr1), .addr2(addr2), .data1(data1), .data2(data2)
    );

    hash_function1 u_probe_h1 (.key(probe_key_extended), .index(probe_index1));
    hash_function2 u_probe_h2 (.key(probe_key_extended), .index(probe_index2));

    assign probe_h1 = probe_index1;
    assign probe_h2 = probe_index2;

    always #5 clk = ~clk;

    always @(posedge clk) begin
        data1 <= mem1[addr1];
        data2 <= mem2[addr2];
    end

    task put1;
        input [KEY_W-1:0] k;
        input [VAL_W-1:0] v;
        input             valid;
        begin
            probe_key = k;
            #1;
            mem1[probe_h1] = {valid, k, v};
        end
    endtask

    task put2;
        input [KEY_W-1:0] k;
        input [VAL_W-1:0] v;
        input             valid;
        begin
            probe_key = k;
            #1;
            mem2[probe_h2] = {valid, k, v};
        end
    endtask

    task verify;
        input             exp_found;
        input [VAL_W-1:0] exp_value;
        input             exp_table;
        input [255:0]     name;
        begin
            if (found !== exp_found ||
                (exp_found && (value !== exp_value || table_sel !== exp_table))) begin
                errors = errors + 1;
                $display("ECHEC  %0s : found=%b value=%h table=%b", name, found, value, table_sel);
            end else begin
                $display("OK     %0s", name);
            end
        end
    endtask

    task search_key;
        input [KEY_W-1:0] k;
        begin
            @(negedge clk);
            key   = k;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait (done === 1'b1);
            #1;
        end
    endtask

    initial begin
        $dumpfile("search.vcd");
        $dumpvars(0, search_tb);

        for (i = 0; i < (1<<ADDR_W); i = i + 1) begin
            mem1[i] = {ENTRY_W{1'b0}};
            mem2[i] = {ENTRY_W{1'b0}};
        end

        #22 rst = 1'b0;

        put1(32'h0000_002A, 16'h0011, 1'b1);
        put2(32'h0000_003C, 16'h0022, 1'b1);
        put1(32'h0000_0055, 16'h0099, 1'b0);
        put1(32'h0000_0001, 16'h3333, 1'b1);
        put2(32'h0000_0100, 16'h4444, 1'b1);
        put1(32'hDEAD_BEEF, 16'h5555, 1'b1);

        search_key(32'h0000_002A);
        verify(1'b1, 16'h0011, 1'b0, "cle dans table 1");

        search_key(32'h0000_003C);
        verify(1'b1, 16'h0022, 1'b1, "cle dans table 2");

        search_key(32'h0000_0077);
        verify(1'b0, 16'h0000, 1'b0, "cle absente");

        search_key(32'h0000_0055);
        verify(1'b0, 16'h0000, 1'b0, "case invalide ignoree");

        search_key(32'h0000_0100);
        verify(1'b1, 16'h4444, 1'b1, "collision : cle en table 2");

        search_key(32'h0001_0000);
        verify(1'b0, 16'h0000, 1'b0, "collision : cle absente");

        search_key(32'hDEAD_BEEF);
        verify(1'b1, 16'h5555, 1'b0, "cle sur 32 bits");

        search_key(32'h0000_002A);
        verify(1'b1, 16'h0011, 1'b0, "recherche consecutive 1");

        search_key(32'h0000_003C);
        verify(1'b1, 16'h0022, 1'b1, "recherche consecutive 2");

        @(negedge clk);
        key   = 32'h0000_002A;
        start = 1'b1;
        @(negedge clk);
        key   = 32'h0000_003C;
        @(negedge clk);
        start = 1'b0;
        wait (done === 1'b1);
        #1;
        verify(1'b1, 16'h0011, 1'b0, "start ignore pendant busy");

        #20;
        if (errors == 0) $display("TOUS LES TESTS PASSENT");
        else             $display("%0d TEST(S) EN ECHEC", errors);
        $finish;
    end

endmodule
