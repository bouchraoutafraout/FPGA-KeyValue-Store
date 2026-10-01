module uart_tx #(
    parameter CLK_FREQ  = 50000000,   // fréquence horloge FPGA (50 MHz par ex.)
    parameter BAUD_RATE = 9600
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       start_tx,       // signal pour lancer l'envoi
    input  wire [7:0] data_in,        // octet à envoyer
    output reg        tx,             // ligne série de sortie
    output reg        busy            // 1 = transmission en cours
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    reg [12:0] clk_count = 0;
    reg [2:0]  bit_index = 0;
    reg [7:0]  data_reg  = 0;

    localparam IDLE  = 0, START = 1, DATA = 2, STOP = 3;
    reg [1:0] state = IDLE;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state     <= IDLE;
            tx        <= 1'b1;   // ligne au repos = 1
            busy      <= 0;
            clk_count <= 0;
            bit_index <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1'b1;
                    if (start_tx) begin
                        data_reg  <= data_in;
                        busy      <= 1;
                        state     <= START;
                        clk_count <= 0;
                    end
                end

                START: begin
                    tx <= 1'b0;  // start bit
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        state     <= DATA;
                        bit_index <= 0;
                    end
                end

                DATA: begin
                    tx <= data_reg[bit_index];
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            state <= STOP;
                        end
                    end
                end

                STOP: begin
                    tx <= 1'b1;  // stop bit
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        busy      <= 0;
                        state     <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule