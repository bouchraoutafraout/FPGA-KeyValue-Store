`timescale 1ns/1ps

module blockchain_storage_adapter (
    input wire clk,
    input wire rst,
    input wire storage_start,
    input wire [31:0] storage_index,
    input wire [351:0] storage_header,
    input wire [255:0] storage_hash,
    output wire storage_done,
    output reg storage_ok
);

    localparam S_IDLE = 2'd0;
    localparam S_WRITE = 2'd1;
    localparam S_VERIFY = 2'd2;
    localparam S_RESULT = 2'd3;

    reg [1:0] state;
    reg [3:0] saved_index;
    reg [607:0] saved_data;

    wire [607:0] read_data;
    wire write_enable = (state == S_WRITE);

    assign storage_done = (state == S_RESULT);

    blockchain_storage #(
        .ADDR_WIDTH(4),
        .DATA_WIDTH(608)
    ) STORAGE (
        .clk(clk),
        .rst(rst),
        .wr_en(write_enable),
        .block_index(saved_index),
        .block_data_in(saved_data),
        .block_data_out(read_data)
    );

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            saved_index <= 0;
            saved_data <= 0;
            storage_ok <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (storage_start) begin
                        if (storage_index >= 32'd16) begin
                            storage_ok <= 0;
                            state <= S_RESULT;
                        end else begin
                            saved_index <= storage_index[3:0];
                            saved_data <= {storage_header, storage_hash};
                            storage_ok <= 0;
                            state <= S_WRITE;
                        end
                    end
                end

                S_WRITE: state <= S_VERIFY;

                S_VERIFY: begin
                    storage_ok <= (read_data === saved_data);
                    state <= S_RESULT;
                end

                S_RESULT: state <= S_IDLE;

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
