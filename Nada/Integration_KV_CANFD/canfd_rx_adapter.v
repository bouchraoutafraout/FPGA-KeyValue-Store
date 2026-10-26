
`timescale 1ns/1ps

module canfd_rx_adapter (
    input  wire        clk,
    input  wire        rst,

    // Depuis CAN-FD RX
    input  wire [63:0] can_data,
    input  wire [3:0]  can_dlc,
    input  wire        can_frame_done,
    input  wire        can_frame_valid,

    // Vers cmd_decoder de Sanae
    output reg  [7:0]  rx_data,
    output reg         rx_valid,
    output reg         rx_frame_done,
    output reg         rx_error,

    output wire        busy
);

    localparam IDLE = 2'd0;
    localparam SEND = 2'd1;
    localparam GAP  = 2'd2;
    localparam DONE = 2'd3;

    reg [1:0] state;
    reg [63:0] data_reg;
    reg [3:0] byte_index;

    assign busy = (state != IDLE);

    always @(posedge clk) begin

        if (rst) begin
            state <= IDLE;
            data_reg <= 64'd0;
            byte_index <= 0;
            rx_data <= 0;
            rx_valid <= 0;
            rx_frame_done <= 0;
            rx_error <= 0;
        end

        else begin

            rx_valid <= 0;
            rx_frame_done <= 0;
            rx_error <= 0;

            case (state)

                IDLE: begin

                    if (can_frame_done) begin

                        if (can_frame_valid &&
                            can_dlc == 4'd8) begin

                            data_reg <= can_data;
                            byte_index <= 0;
                            state <= SEND;

                        end

                        else begin
                            rx_error <= 1;
                        end

                    end

                end

                SEND: begin

                    rx_data <= data_reg[63:56];
                    rx_valid <= 1;

                    data_reg <= {data_reg[55:0], 8'h00};

                    if (byte_index == 7)
                        state <= DONE;
                    else begin
                        byte_index <= byte_index + 1;
                        state <= GAP;
                    end

                end

                GAP: begin
                    state <= SEND;
                end

                DONE: begin
                    rx_frame_done <= 1;
                    state <= IDLE;
                end

                default: state <= IDLE;

            endcase

        end

    end

endmodule
