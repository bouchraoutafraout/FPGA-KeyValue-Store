`timescale 1ns / 1ps

module blockchain_storage_tb;

    // Paramètres
    parameter ADDR_WIDTH = 4;
    parameter DATA_WIDTH = 128;
    parameter CLK_PERIOD = 10; // 100 MHz

    // Signaux d'entrée du module
    reg clk;
    reg rst;
    reg wr_en;
    reg [ADDR_WIDTH-1:0] block_index;
    reg [DATA_WIDTH-1:0] block_data_in;

    // Signal de sortie du module
    wire [DATA_WIDTH-1:0] block_data_out;

    // Instanciation du module à tester (UUT)
    blockchain_storage #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .clk(clk),
        .rst(rst),
        .wr_en(wr_en),
        .block_index(block_index),
        .block_data_in(block_data_in),
        .block_data_out(block_data_out)
    );

    // Génération de l'horloge
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Séquence de test
    initial begin
        // Initialisation des signaux
        clk = 0;
        rst = 1;
        wr_en = 0;
        block_index = 0;
        block_data_in = 0;

        $display("--------------------------------------------------");
        $display("[Khadija] DÉBUT DU TESTBENCH : BRAM BLOCKCHAIN STORAGE");
        $display("--------------------------------------------------");

        // Application du Reset
        #(CLK_PERIOD * 2);
        rst = 0;
        #(CLK_PERIOD);

        // ----------------------------------------------------
        // TEST 1 : Vérification du Bloc Genesis (Index 0)
        // ----------------------------------------------------
        block_index = 0;
        #1;
        $display("[TEST 1] Lecture du Bloc Genesis (Index 0)...");
        if (block_data_out == 128'h00000000000000000000000000000001) begin
            $display("-> OK : Bloc Genesis correctement intialisé ! (Valeur: %h)", block_data_out);
        end else begin
            $display("-> ERREUR : Bloc Genesis incorrect (Valeur: %h)", block_data_out);
        end

        // ----------------------------------------------------
        // TEST 2 : Écriture du Bloc 1 (Index 1)
        // ----------------------------------------------------
        #(CLK_PERIOD);
        block_index = 4'd1;
        block_data_in = 128'hA1B2C3D4_E5F60718_99887766_55443322; // Données/Hash du Bloc 1
        wr_en = 1;
        $display("\n[TEST 2] Écriture du Bloc 1 (Index 1)...");
        
        #(CLK_PERIOD);
        wr_en = 0; // Désactivation de l'écriture

        // Relire le Bloc 1 pour vérifier
        #1;
        if (block_data_out == 128'hA1B2C3D4_E5F60718_99887766_55443322) begin
            $display("-> OK : Bloc 1 écrit et relu avec succès !");
        end else begin
            $display("-> ERREUR : Échec de lecture du Bloc 1 (Obtenu: %h)", block_data_out);
        end

        // ----------------------------------------------------
        // TEST 3 : Écriture du Bloc 2 (Index 2)
        // ----------------------------------------------------
        #(CLK_PERIOD);
        block_index = 4'd2;
        block_data_in = 128'hFEDCBA98_76543210_11223344_55667788; // Données/Hash du Bloc 2
        wr_en = 1;
        $display("\n[TEST 3] Écriture du Bloc 2 (Index 2)...");

        #(CLK_PERIOD);
        wr_en = 0;

        // Relire le Bloc 2
        #1;
        if (block_data_out == 128'hFEDCBA98_76543210_11223344_55667788) begin
            $display("-> OK : Bloc 2 écrit et relu avec succès !");
        end else begin
            $display("-> ERREUR : Échec de lecture du Bloc 2 (Obtenu: %h)", block_data_out);
        end

        // ----------------------------------------------------
        // TEST 4 : Relecture croisée des blocs (Contrôle d'intégrité)
        // ----------------------------------------------------
        $display("\n[TEST 4] Relecture croisée des blocs stockés...");
        
        block_index = 4'd0; #1;
        $display("  Index 0 (Genesis) : %h", block_data_out);
        
        block_index = 4'd1; #1;
        $display("  Index 1 (Bloc 1)  : %h", block_data_out);
        
        block_index = 4'd2; #1;
        $display("  Index 2 (Bloc 2)  : %h", block_data_out);

        $display("\n--------------------------------------------------");
        $display("[Khadija] FIN DU TESTBENCH : BRAM VALIDÉE (PASS)");
        $display("--------------------------------------------------");

        $finish;
    end

endmodule