`timescale 1ns/1ps
// One-entry elastic buffer for complete and valid DLC8 CAN-FD requests.
// This module does NOT validate financial transactions or modify KVS.
module blockchain_ingress (
    input wire clk,
    input wire rst,
    input wire frame_done,
    input wire frame_valid,
    input wire [3:0] frame_dlc,
    input wire [63:0] frame_data,
    output wire tx_valid,
    input wire tx_ready,
    output wire [63:0] tx_data,
    output reg overflow
);
    reg pending;
    reg [63:0] saved_data;
    wire incoming = frame_done && frame_valid && (frame_dlc == 4'd8);
    assign tx_valid = pending;
    assign tx_data = saved_data;

    always @(posedge clk) begin
        if (rst) begin
            pending <= 1'b0;
            saved_data <= 64'd0;
            overflow <= 1'b0;
        end else begin
            if (incoming) begin
                if (!pending || tx_ready) begin
                    saved_data <= frame_data;
                    pending <= 1'b1;
                end else begin
                    overflow <= 1'b1;
                end
            end else if (pending && tx_ready) begin
                pending <= 1'b0;
            end
        end
    end
endmodule
