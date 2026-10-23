
`timescale 1ns/1ps

module canfd_stuffer (
    input  wire       clk,
    input  wire       rst,
    input  wire       clear,
    input  wire       tick,
    input  wire       in_valid,
    input  wire       in_bit,

    output wire       in_take,
    output reg        out_valid,
    output reg        out_bit,
    output reg        out_is_stuff,
    output reg [7:0]  stuff_cnt
);

    reg last;
    reg [2:0] run;

    wire need_stuff = (run == 3'd5);

    assign in_take =
        tick && in_valid && !need_stuff;

    always @(posedge clk) begin

        if (rst || clear) begin
            last         <= 1'b0;
            run          <= 3'd0;
            out_valid    <= 1'b0;
            out_bit      <= 1'b0;
            out_is_stuff <= 1'b0;
            stuff_cnt    <= 8'd0;
        end
        else begin

            out_valid <= 1'b0;

            if (tick && in_valid) begin

                if (need_stuff) begin

                    out_valid    <= 1'b1;
                    out_bit      <= ~last;
                    out_is_stuff <= 1'b1;

                    last      <= ~last;
                    run       <= 3'd1;
                    stuff_cnt <= stuff_cnt + 8'd1;

                end
                else begin

                    out_valid    <= 1'b1;
                    out_bit      <= in_bit;
                    out_is_stuff <= 1'b0;

                    if (run != 0 && in_bit == last)
                        run <= run + 3'd1;
                    else
                        run <= 3'd1;

                    last <= in_bit;

                end
            end
        end
    end

endmodule
