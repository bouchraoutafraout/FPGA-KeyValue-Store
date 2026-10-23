
`timescale 1ns/1ps

module canfd_tx #(
    parameter CLK_FREQ = 100_000_000
)(
    input wire clk,
    input wire rst,
    input wire start,
    input wire [10:0] can_id,
    input wire [63:0] data,
    input wire [3:0] dlc,
    output reg can_tx,
    output reg busy,
    output reg done
);

    // ==============================
    // ETATS DE LA MACHINE
    // ==============================

    localparam IDLE      = 3'd0;
    localparam PREP      = 3'd1;
    localparam SEND      = 3'd2;
    localparam WAIT_LAST = 3'd3;
    localparam CRC_LOAD  = 3'd4;
    localparam CRC_SEND  = 3'd5;
    localparam TAIL      = 3'd6;
    localparam FINISH    = 3'd7;

    reg [2:0] state;

    // ==============================
    // REGISTRES DE TRANSMISSION
    // ==============================

    reg [85:0] payload;
    reg [6:0] total_bits;
    reg [6:0] bit_index;

    reg [16:0] crc_final;
    reg [7:0] stuff_final;
    reg prev_final;

    reg [3:0] tail_index;
    reg tail_valid;

    reg timer_run;
    wire tick;

    // ==============================
    // BIT TIMER
    // ==============================

    canfd_bit_timer #(
        .CLK_FREQ(CLK_FREQ),
        .NOM_RATE(1_000_000),
        .DATA_RATE(2_000_000)
    ) timer (
        .clk(clk),
        .rst(rst),
        .run(timer_run),
        .next_mode(2'd0),
        .tick(tick)
    );

    // ==============================
    // DYNAMIC BIT STUFFING
    // ==============================

    wire clear_stuff = (state == PREP);

    wire in_valid =
        (state == SEND) && (bit_index < total_bits);

    wire in_bit = payload[85-bit_index];

    wire in_take;
    wire out_valid;
    wire out_bit;
    wire out_is_stuff;
    wire [7:0] stuff_count;

    canfd_stuffer stuffer (
        .clk(clk),
        .rst(rst),
        .clear(clear_stuff),
        .tick(tick),
        .in_valid(in_valid),
        .in_bit(in_bit),
        .in_take(in_take),
        .out_valid(out_valid),
        .out_bit(out_bit),
        .out_is_stuff(out_is_stuff),
        .stuff_cnt(stuff_count)
    );

    // ==============================
    // CRC-17
    // ==============================

    wire [16:0] crc_value;

    wire crc_init = (state == PREP);

    wire crc_en =
        out_valid &&
        ((state == SEND) || (state == WAIT_LAST));

    canfd_crc #(
        .WIDTH(17),
        .POLY(21'h1685B),
        .INIT(21'h10000)
    ) crc_unit (
        .clk(clk),
        .rst(rst),
        .load_init(crc_init),
        .en(crc_en),
        .din(out_bit),
        .crc(crc_value)
    );

    // ==============================
    // CRC FIELD
    // ==============================

    reg crc_load;

    wire crc_valid;
    wire crc_bit;
    wire crc_fsb;
    wire crc_done;
    wire crc_active;

    canfd_crcfield crc_field (
        .clk(clk),
        .rst(rst),
        .load(crc_load),
        .prev_bit(prev_final),
        .stuff_mod8(stuff_final[2:0]),
        .crc({4'd0, crc_final}),
        .is21(1'b0),
        .tick(tick),
        .out_valid(crc_valid),
        .out_bit(crc_bit),
        .out_is_fsb(crc_fsb),
        .done(crc_done),
        .active(crc_active)
    );

    // ==============================
    // MACHINE PRINCIPALE
    // ==============================

    always @(posedge clk) begin

        if (rst) begin

            state <= IDLE;

            payload <= 0;
            total_bits <= 0;
            bit_index <= 0;

            crc_final <= 0;
            stuff_final <= 0;
            prev_final <= 1;

            tail_index <= 0;
            tail_valid <= 0;

            timer_run <= 0;
            crc_load <= 0;

            can_tx <= 1;
            busy <= 0;
            done <= 0;

        end else begin

            done <= 0;
            crc_load <= 0;
            tail_valid <= 0;

            // Sortie du stuffer
            if (out_valid &&
                (state == SEND || state == WAIT_LAST))
                can_tx <= out_bit;

            // Sortie du champ CRC
            if (crc_valid && state == CRC_SEND)
                can_tx <= crc_bit;

            case (state)

                // ----------------------
                // IDLE
                // ----------------------

                IDLE: begin

                    timer_run <= 0;
                    can_tx <= 1;
                    busy <= 0;

                    if (start) begin

                        payload <= {
                            1'b0,       // SOF
                            can_id,     // ID 11 bits
                            1'b1,       // RRS
                            1'b0,       // IDE
                            1'b1,       // FDF
                            1'b0,       // res
                            1'b0,       // BRS
                            1'b0,       // ESI
                            dlc,        // DLC
                            data        // DATA
                        };

                        total_bits <=
                            7'd22 + ({3'd0, dlc} << 3);

                        bit_index <= 0;
                        tail_index <= 0;

                        busy <= 1;
                        state <= PREP;

                    end
                end

                // ----------------------
                // PREPARATION
                // ----------------------

                PREP: begin

                    timer_run <= 0;
                    state <= SEND;

                end

                // ----------------------
                // EN-TETE + DATA
                // ----------------------

                SEND: begin

                    timer_run <= 1;

                    if (in_take) begin

                        bit_index <= bit_index + 1'b1;

                        if (bit_index == total_bits - 1)
                            state <= WAIT_LAST;

                    end
                end

                // ----------------------
                // DERNIER BIT
                // ----------------------

                WAIT_LAST: begin

                    if (out_valid) begin

                        prev_final <= out_bit;
                        stuff_final <= stuff_count;

                        state <= CRC_LOAD;

                    end
                end

                // ----------------------
                // CHARGEMENT CRC
                // ----------------------

                CRC_LOAD: begin

                    crc_final <= crc_value;
                    crc_load <= 1;

                    state <= CRC_SEND;

                end

                // ----------------------
                // TRANSMISSION CRC
                // ----------------------

                CRC_SEND: begin

                    if (crc_done) begin

                        tail_index <= 0;
                        state <= TAIL;

                    end
                end

                // ----------------------
                // FIN DE TRAME
                // CRC DELIMITER + ACK + EOF
                // ----------------------

                TAIL: begin

                    if (tick) begin

                        tail_valid <= 1'b1;

                        if (tail_index == 4'd9) begin
                            state <= FINISH;
                        end else begin
                            tail_index <= tail_index + 1'b1;
                        end

                    end

                    // CORRECTION :
                    // Meme latence enregistree
                    // que la sortie du CRC
                    if (tail_valid)
                        can_tx <= 1'b1;

                end

                // ----------------------
                // FIN TRANSMISSION
                // ----------------------

                FINISH: begin

                    if (tick) begin

                        timer_run <= 0;
                        busy <= 0;
                        done <= 1;

                        state <= IDLE;

                    end
                end

                default: begin

                    state <= IDLE;
                    timer_run <= 0;

                end

            endcase

        end
    end

endmodule
