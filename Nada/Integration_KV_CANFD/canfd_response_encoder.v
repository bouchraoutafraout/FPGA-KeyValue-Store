`timescale 1ns/1ps
module canfd_response_encoder (
    input wire clk,
    input wire rst,
    input wire resp_valid,
    output wire resp_ready,
    input wire [7:0] resp_cmd,
    input wire [7:0] resp_status,
    input wire [15:0] resp_value,
    input wire tx_busy,
    output wire tx_start,
    output reg [63:0] tx_data,
    output wire [3:0] tx_dlc,
    output wire encoder_busy
);
    localparam [1:0] S_IDLE=2'd0, S_START=2'd1,
                     S_WAIT_BUSY=2'd2, S_WAIT_END=2'd3;
    reg [1:0] state;
    assign resp_ready = (state == S_IDLE);
    assign tx_start = (state == S_START);
    assign tx_dlc = 4'd8;
    assign encoder_busy = (state != S_IDLE);
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            tx_data <= 64'd0;
        end else begin
            case (state)
                S_IDLE: if (resp_valid && !tx_busy) begin
                    // [LEN=4, CMD, STATUS, VALUE_HI, VALUE_LO, 0, 0, 0]
                    tx_data <= {8'h04,resp_cmd,resp_status,resp_value,24'h000000};
                    state <= S_START;
                end
                S_START: state <= S_WAIT_BUSY;
                S_WAIT_BUSY: if (tx_busy) state <= S_WAIT_END;
                S_WAIT_END: if (!tx_busy) state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
