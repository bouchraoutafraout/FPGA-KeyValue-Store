`timescale 1ns / 1ps

module blockchain_storage_tb;

    parameter ADDR_WIDTH = 4;
    parameter DATA_WIDTH = 512;
    parameter CLK_PERIOD = 10;
    parameter DEPTH = 1 << ADDR_WIDTH;
    parameter [DATA_WIDTH-1:0] GENESIS = {{(DATA_WIDTH-1){1'b0}}, 1'b1};

    reg clk;
    reg rst;
    reg wr_en;
    reg [DATA_WIDTH-1:0] block_data_in;
    reg rd_en;
    reg [ADDR_WIDTH-1:0] block_index;

    wire wr_ready;
    wire wr_err;
    wire [DATA_WIDTH-1:0] block_data_out;
    wire rd_valid;
    wire rd_err;
    wire [ADDR_WIDTH:0] block_count;
    wire full;

    integer errors;
    integer k;

    blockchain_storage #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .GENESIS_DATA(GENESIS)
    ) uut (
        .clk(clk),
        .rst(rst),
        .wr_en(wr_en),
        .block_data_in(block_data_in),
        .wr_ready(wr_ready),
        .wr_err(wr_err),
        .rd_en(rd_en),
        .block_index(block_index),
        .block_data_out(block_data_out),
        .rd_valid(rd_valid),
        .rd_err(rd_err),
        .block_count(block_count),
        .full(full)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    task write_block(input [DATA_WIDTH-1:0] data);
        begin
            @(negedge clk);
            block_data_in = data;
            wr_en = 1;
            @(negedge clk);
            wr_en = 0;
        end
    endtask

    task read_block(input [ADDR_WIDTH-1:0] idx);
        begin
            @(negedge clk);
            block_index = idx;
            rd_en = 1;
            @(negedge clk);
            rd_en = 0;
            #1;
        end
    endtask

    task check(input cond, input [511:0] name);
        begin
            if (cond) $display("-> OK : %0s", name);
            else begin
                $display("-> ERREUR : %0s", name);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        wr_en = 0;
        rd_en = 0;
        block_index = 0;
        block_data_in = 0;
        errors = 0;

        $display("--------------------------------------------------");
        $display("[Khadija] DEBUT DU TESTBENCH : BRAM BLOCKCHAIN STORAGE");
        $display("--------------------------------------------------");

        #(CLK_PERIOD * 2);
        rst = 0;
        #(CLK_PERIOD);

        $display("\n[TEST 1] Bloc Genesis (index 0) et compteur initial");
        check(block_count == 1, "block_count = 1 apres reset");
        read_block(0);
        check(rd_valid && block_data_out == GENESIS, "Genesis lu correctement");

        $display("\n[TEST 2] Ajout et relecture des blocs 1 et 2");
        write_block({4{128'hA1B2C3D4_E5F60718_99887766_55443322}});
        check(block_count == 2, "block_count = 2");
        read_block(1);
        check(rd_valid && block_data_out == {4{128'hA1B2C3D4_E5F60718_99887766_55443322}}, "Bloc 1 relu");
        write_block({4{128'hFEDCBA98_76543210_11223344_55667788}});
        check(block_count == 3, "block_count = 3");
        read_block(2);
        check(rd_valid && block_data_out == {4{128'hFEDCBA98_76543210_11223344_55667788}}, "Bloc 2 relu");

        $display("\n[TEST 3] Relecture croisee : le Genesis n'a pas change");
        read_block(0);
        check(rd_valid && block_data_out == GENESIS, "Genesis intact");
        read_block(1);
        check(rd_valid && block_data_out == {4{128'hA1B2C3D4_E5F60718_99887766_55443322}}, "Bloc 1 intact");

        $display("\n[TEST 4] Lecture d'un index non ecrit");
        read_block(10);
        check(rd_err && !rd_valid, "rd_err leve pour index >= block_count");

        $display("\n[TEST 5] Remplissage jusqu'a la capacite");
        for (k = 3; k < DEPTH; k = k + 1) begin
            write_block(k);
        end
        check(full, "full leve a 16 blocs");
        check(!wr_ready, "wr_ready bas quand plein");
        check(block_count == DEPTH, "block_count = capacite");
        read_block(DEPTH - 1);
        check(rd_valid && block_data_out == DEPTH - 1, "dernier bloc relu");

        $display("\n[TEST 6] Ecriture au-dela de la capacite");
        @(negedge clk);
        block_data_in = {DATA_WIDTH{1'b1}};
        wr_en = 1;
        @(posedge clk);
        #1;
        check(wr_err, "wr_err leve quand plein");
        wr_en = 0;
        check(block_count == DEPTH, "block_count inchange");
        read_block(0);
        check(block_data_out == GENESIS, "Genesis non ecrase");
        read_block(DEPTH - 1);
        check(block_data_out == DEPTH - 1, "dernier bloc non ecrase");

        $display("\n[TEST 7] Reset : retour au Genesis seul");
        rst = 1;
        #(CLK_PERIOD);
        rst = 0;
        #(CLK_PERIOD);
        check(block_count == 1 && !full, "block_count = 1 et full bas");
        read_block(0);
        check(rd_valid && block_data_out == GENESIS, "Genesis conserve");

        $display("\n--------------------------------------------------");
        if (errors == 0) $display("[Khadija] FIN DU TESTBENCH : BRAM VALIDEE (PASS)");
        else $display("[Khadija] FIN DU TESTBENCH : %0d ERREUR(S) (FAIL)", errors);
        $display("--------------------------------------------------");
        $finish;
    end

endmodule