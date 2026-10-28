module blockchain_storage #(
    parameter ADDR_WIDTH = 4,   // Permet de stocker jusqu'à 16 blocs
    parameter DATA_WIDTH = 128  // Largeur des données du bloc (ou hash/transactions)
)(
    input wire clk,
    input wire rst,
    input wire wr_en,
    input wire [ADDR_WIDTH-1:0] block_index,
    input wire [DATA_WIDTH-1:0] block_data_in,
    output reg [DATA_WIDTH-1:0] block_data_out
);

    // Déclaration de la mémoire BRAM (Tableaux de registres)
    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    integer i;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Initialisation au Reset : Création du Bloc Genesis (Index 0)
            mem[0] <= 128'h00000000000000000000000000000001; // Valeur par défaut du Genesis
            for (i = 1; i < (1<<ADDR_WIDTH); i = i + 1) begin
                mem[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            // Écriture d'un nouveau bloc validé
            if (wr_en) begin
                mem[block_index] <= block_data_in;
            end
        end
    end

    // Lecture synchrone ou asynchrone du bloc demandé
    always @(*) begin
        block_data_out = mem[block_index];
    end

endmodule