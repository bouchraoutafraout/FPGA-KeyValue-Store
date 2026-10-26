`timescale 1ns/1ps

module canfd_tx #(
    parameter CLK_FREQ = 100_000_000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,

    input  wire [10:0] can_id,
    input  wire [63:0] data,
    input  wire [3:0]  dlc,

    input  wire        can_rx,

    output reg         can_tx,
    output reg         busy,
    output reg         done,
    output reg         ack_error
);

    localparam [3:0]
        IDLE      = 4'd0,
        PREP      = 4'd1,
        SEND      = 4'd2,
        WAIT_LAST = 4'd3,
        CRC_SBC   = 4'd4,
        CRC_LOAD  = 4'd5,
        CRC_SEND  = 4'd6,
        TAIL      = 4'd7,
        FINISH    = 4'd8;

    reg [3:0] state;

    reg [85:0] payload;
    reg [6:0] total_bits;
    reg [6:0] bit_index;

    reg [16:0] crc_final;
    reg [7:0] stuff_final;
    reg prev_final;

    reg [3:0] sbc_final;
    reg [1:0] sbc_index;

    reg [3:0] tail_index;
    reg tail_valid;

    reg timer_run;
    wire tick;

    // ==========================================
    // BIT TIMER
    // ==========================================

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

    // ==========================================
    // DYNAMIC STUFFING
    // ==========================================

    wire clear_stuff = (state == PREP);

    wire in_valid =
    ((state == SEND) &&
     (bit_index < total_bits))
    ||
    ((state == WAIT_LAST) &&
     stuffer.need_stuff);
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

    // ==========================================
    // STUFF BIT COUNT
    // ==========================================

    function [3:0] make_sbc;
        input [2:0] count;
        reg [2:0] gray;
        begin
            gray = count ^ (count >> 1);
            make_sbc = {gray, ^gray};
        end
    endfunction

    // ==========================================
    // CRC-17
    // ==========================================

    wire [16:0] crc_value;

    wire crc_init = (state == PREP);

    wire crc_payload_en =
        out_valid &&
        ((state == SEND) ||
         (state == WAIT_LAST));

    wire crc_sbc_en = (state == CRC_SBC);
    wire crc_en = crc_payload_en || crc_sbc_en;

    wire crc_din =
        crc_sbc_en ?
        sbc_final[3 - sbc_index] :
        out_bit;

    canfd_crc #(
        .WIDTH(17),
        .POLY(21'h1685B),
        .INIT(21'h10000)
    ) crc_unit (
        .clk(clk),
        .rst(rst),
        .load_init(crc_init),
        .en(crc_en),
        .din(crc_din),
        .crc(crc_value)
    );

    // ==========================================
    // CRC FIELD
    // ==========================================

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

    // ==========================================
    // ACK : ECHANTILLONNAGE DU BUS
    // ==========================================

    // Cette version utilise 1 Mbit/s.
    // Echantillonnage au milieu du bit ACK.
    localparam integer HALF_BIT_CLKS =
        CLK_FREQ / (2 * 1_000_000);

    reg [31:0] ack_counter;
    reg ack_sampling;

    // Synchronisation de can_rx sur clk.
    reg can_rx_meta;
    reg can_rx_sync;

    always @(posedge clk) begin
        if (rst) begin
            can_rx_meta <= 1'b1;
            can_rx_sync <= 1'b1;
        end else begin
            can_rx_meta <= can_rx;
            can_rx_sync <= can_rx_meta;
        end
    end

    // ==========================================
    // MACHINE PRINCIPALE
    // ==========================================

    always @(posedge clk) begin

        if (rst) begin

            state <= IDLE;

            payload <= 0;
            total_bits <= 0;
            bit_index <= 0;

            crc_final <= 0;
            stuff_final <= 0;
            prev_final <= 1'b1;

            sbc_final <= 0;
            sbc_index <= 0;

            tail_index <= 0;
            tail_valid <= 0;

            timer_run <= 0;
            crc_load <= 0;

            ack_counter <= 0;
            ack_sampling <= 0;
            ack_error <= 0;

            can_tx <= 1'b1;
            busy <= 0;
            done <= 0;

        end else begin

            done <= 1'b0;
            crc_load <= 1'b0;
            tail_valid <= 1'b0;

            if (out_valid &&
                (state == SEND ||
                 state == WAIT_LAST))
                can_tx <= out_bit;

            if (crc_valid && state == CRC_SEND)
                can_tx <= crc_bit;

            // Mesurer can_rx au milieu de l'ACK slot.
            if (ack_sampling) begin
                if (ack_counter == HALF_BIT_CLKS - 1) begin
                    ack_error <= (can_rx_sync !== 1'b0);
                    ack_sampling <= 1'b0;
                end else begin
                    ack_counter <= ack_counter + 1;
                end
            end

            case (state)

                IDLE: begin
                    timer_run <= 0;
                    can_tx <= 1;
                    busy <= 0;

                    if (start) begin

                        payload <= {
                            1'b0,
                            can_id,
                            1'b1,
                            1'b0,
                            1'b1,
                            1'b0,
                            1'b0,
                            1'b0,
                            dlc,
                            data
                        };

                        total_bits <=
                            7'd22 + ({3'd0, dlc} << 3);

                        bit_index <= 0;
                        tail_index <= 0;

                        ack_counter <= 0;
                        ack_sampling <= 0;
                        ack_error <= 1'b1;

                        busy <= 1;
                        state <= PREP;
                    end
                end

                PREP: begin
                    timer_run <= 0;
                    state <= SEND;
                end

                SEND: begin
                    timer_run <= 1;

                    if (in_take) begin
                        bit_index <= bit_index + 1'b1;

                        if (bit_index == total_bits - 1)
                            state <= WAIT_LAST;
                    end
                end

                WAIT_LAST: begin
                    // Le dernier bit utile a deja ete accepte.
                    // Si cinq bits identiques viennent d'etre emis,
                    // attendre le stuffing final avant le champ CRC.
                    if (out_valid && !stuffer.need_stuff) begin
                        prev_final <= out_bit;
                        stuff_final <= stuff_count;

                        sbc_final <=
                            make_sbc(stuff_count[2:0]);

                        sbc_index <= 0;
                        state <= CRC_SBC;
                    end
                end

                CRC_SBC: begin
                    if (sbc_index == 2'd3)
                        state <= CRC_LOAD;
                    else
                        sbc_index <= sbc_index + 1'b1;
                end

                CRC_LOAD: begin
                    crc_final <= crc_value;
                    crc_load <= 1;
                    state <= CRC_SEND;
                end

                CRC_SEND: begin
                    if (crc_done) begin
                        tail_index <= 0;
                        state <= TAIL;
                    end
                end

                TAIL: begin

                    if (tick) begin

                        tail_valid <= 1;

                        // tail_index 0 : CRC delimiter
                        // tail_index 1 : ACK slot
                        // tail_index 2 : ACK delimiter
                        // tail_index 3..9 : EOF

                        if (tail_index == 4'd1) begin
                            ack_counter <= 0;
                            ack_sampling <= 1;
                        end

                        if (tail_index == 4'd9)
                            state <= FINISH;
                        else
                            tail_index <= tail_index + 1'b1;
                    end

                    // Le transmetteur reste recessif
                    // pendant delimiter, ACK et EOF.
                    if (tail_valid)
                        can_tx <= 1'b1;

                end

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
