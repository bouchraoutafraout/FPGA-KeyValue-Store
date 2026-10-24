module uart_rx #(
    parameter CLK_FREQ  = 50000000,
    parameter BAUD_RATE = 9600
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       rx,
    output reg [7:0]  data_out,
    output reg        data_valid,
    output reg        busy
);

    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam integer HALF_CLKS    = CLKS_PER_BIT / 2;

    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0] state;
    reg [12:0] clk_count;
    reg [2:0] bit_index;
    reg [7:0] data_reg;

    reg rx_sync1;
    reg rx_sync2;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state      <= IDLE;
            clk_count  <= 0;
            bit_index  <= 0;
            data_reg   <= 0;
            data_out   <= 0;
            data_valid <= 0;
            busy       <= 0;
        end else begin

            data_valid <= 1'b0;

            case (state)

                IDLE: begin
                    busy      <= 1'b0;
                    clk_count <= 0;
                    bit_index <= 0;

                    if (rx_sync2 == 1'b0) begin
                        busy      <= 1'b1;
                        state     <= START;
                        clk_count <= 0;
                    end
                end

                START: begin
                    if (clk_count < HALF_CLKS - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;

                        if (rx_sync2 == 1'b0) begin
                            state     <= DATA;
                            bit_index <= 0;
                        end else begin
                            state <= IDLE;
                            busy  <= 1'b0;
                        end
                    end
                end

                DATA: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        data_reg[bit_index] <= rx_sync2;

                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            state <= STOP;
                        end
                    end
                end

                STOP: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count  <= 0;
                        state      <= IDLE;
                        busy       <= 1'b0;
                        data_out   <= data_reg;
                        data_valid <= 1'b1;
                    end
                end

                default: begin
                    state <= IDLE;
                    busy  <= 1'b0;
                end

            endcase
        end
    end

endmodule
