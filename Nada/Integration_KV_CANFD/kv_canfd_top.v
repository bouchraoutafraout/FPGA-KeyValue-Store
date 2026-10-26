`timescale 1ns/1ps

module kv_canfd_top (
    input  wire        clk,
    input  wire        rst,

    // Bus CAN-FD entrant
    input  wire        can_rx,
    output wire        ack_drive_low,

    // Reponse du Key-Value Store
    output wire        resp_valid,
    input  wire        resp_ready,
    output wire [7:0]  resp_cmd,
    output wire [7:0]  resp_status,
    output wire [15:0] resp_value,

    // Diagnostic
    output wire        rx_frame_done,
    output wire        rx_frame_valid,
    output wire        rx_crc_ok,
    output wire        rx_stuff_error,
    output wire        rx_fsb_error,

    output wire        adapter_busy,
    output wire        ck_busy,
    output wire        ck_done,
    output wire        ck_found,
    output wire        ck_error
);

    // ==========================================
    // 1. CAN-FD RX
    // ==========================================

    wire [63:0] can_data;
    wire [3:0]  can_dlc;
    wire [10:0] can_id;

    wire sample_bit;
    wire sample_valid;
    wire rx_busy;
    wire [6:0] bit_index;

    wire payload_bit;
    wire payload_valid;
    wire payload_done;
    wire [6:0] payload_count;
    wire [7:0] stuff_count;

    wire decode_done;
    wire [16:0] crc_calc;
    wire [16:0] crc_recu;
    wire [3:0] sbc_recu;
    wire crc_done;

    wire ack_sent;
    wire tail_error;

    canfd_rx #(
        .CLK_FREQ(100_000_000),
        .BIT_RATE(1_000_000),
        .PAYLOAD_BITS(86),
        .FRAME_BITS(127)
    ) RX (
        .clk(clk),
        .rst(rst),
        .can_rx(can_rx),

        .sample_bit(sample_bit),
        .sample_valid(sample_valid),
        .busy(rx_busy),
        .bit_index(bit_index),

        .payload_bit(payload_bit),
        .payload_valid(payload_valid),
        .payload_count(payload_count),
        .stuff_count(stuff_count),
        .stuff_error(rx_stuff_error),
        .payload_done(payload_done),

        .rx_id(can_id),
        .rx_dlc(can_dlc),
        .rx_data(can_data),
        .decode_done(decode_done),

        .crc_calc(crc_calc),
        .crc_recu(crc_recu),
        .sbc_recu(sbc_recu),
        .fsb_error(rx_fsb_error),
        .crc_done(crc_done),
        .crc_ok(rx_crc_ok),

        .ack_drive_low(ack_drive_low),
        .ack_sent(ack_sent),
        .tail_error(tail_error),
        .frame_done(rx_frame_done),
        .frame_valid(rx_frame_valid)
    );

    // ==========================================
    // 2. ADAPTATEUR CAN-FD -> OCTETS
    // ==========================================

    wire [7:0] dec_rx_data;
    wire dec_rx_valid;
    wire dec_rx_frame_done;
    wire dec_rx_error;

    canfd_rx_adapter ADAPTER (
        .clk(clk),
        .rst(rst),

        .can_data(can_data),
        .can_dlc(can_dlc),
        .can_frame_done(rx_frame_done),
        .can_frame_valid(rx_frame_valid),

        .rx_data(dec_rx_data),
        .rx_valid(dec_rx_valid),
        .rx_frame_done(dec_rx_frame_done),
        .rx_error(dec_rx_error),

        .busy(adapter_busy)
    );

    // ==========================================
    // 3. DECODEUR DE COMMANDES
    // ==========================================

    wire [7:0] ck_cmd;
    wire [31:0] ck_key;
    wire [15:0] ck_value;
    wire ck_start;
    wire [15:0] ck_value_out;

    wire err_valid;
    wire [1:0] err_code;
    wire dbg_overrun;
    wire dbg_rejected;
    wire [2:0] dbg_state;

    cmd_decoder #(
        .TIMEOUT(2000)
    ) DEC (
        .clk(clk),
        .rst(rst),

        .rx_data(dec_rx_data),
        .rx_valid(dec_rx_valid),
        .rx_frame_done(dec_rx_frame_done),
        .rx_error(dec_rx_error),

        .ck_cmd(ck_cmd),
        .ck_key(ck_key),
        .ck_value(ck_value),
        .ck_start(ck_start),

        .ck_busy(ck_busy),
        .ck_done(ck_done),
        .ck_found(ck_found),
        .ck_value_out(ck_value_out),
        .ck_error(ck_error),

        .resp_valid(resp_valid),
        .resp_ready(resp_ready),
        .resp_cmd(resp_cmd),
        .resp_status(resp_status),
        .resp_value(resp_value),

        .err_valid(err_valid),
        .err_code(err_code),
        .dbg_overrun(dbg_overrun),
        .dbg_rejected(dbg_rejected),
        .dbg_state(dbg_state)
    );

    // ==========================================
    // 4. VERITABLE KEY-VALUE STORE
    // ==========================================

    cuckoo_top #(
        .KEY_W(32),
        .VAL_W(16),
        .IDX_W(8)
    ) CK (
        .clk(clk),
        .rst(rst),

        .cmd(ck_cmd),
        .key(ck_key),
        .value_in(ck_value),
        .start(ck_start),

        .busy(ck_busy),
        .done(ck_done),
        .found(ck_found),
        .value_out(ck_value_out),
        .error(ck_error)
    );

endmodule
