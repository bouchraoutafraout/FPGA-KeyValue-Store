module uart_blockchain_top (
    input  wire sysclk_p,
    input  wire sysclk_n,
    input  wire uart_rx_pin,
    output wire uart_tx_pin,
    output wire led_ok
);
    // AC701: 200 MHz differential clock -> 50 MHz system clock.
    wire clk_in, clk_fb, clk_fb_buf;
    wire clk_mmcm, clk, locked;

    IBUFDS #(.DIFF_TERM("TRUE")) INPUT_CLK (
        .I(sysclk_p), .IB(sysclk_n), .O(clk_in)
    );

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(5.0),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(5.0),
        .CLKOUT0_DIVIDE_F(20.0)
    ) MMCM (
        .CLKIN1(clk_in),
        .CLKFBIN(clk_fb_buf),
        .CLKFBOUT(clk_fb),
        .CLKOUT0(clk_mmcm),
        .LOCKED(locked),
        .PWRDWN(1'b0),
        .RST(1'b0)
    );

    BUFG FB_BUF (.I(clk_fb), .O(clk_fb_buf));
    BUFG CLK_BUF (.I(clk_mmcm), .O(clk));

    reg [15:0] reset_counter = 16'd0;
    always @(posedge clk) begin
        if (!locked)
            reset_counter <= 16'd0;
        else if (!(&reset_counter))
            reset_counter <= reset_counter + 1'b1;
    end
    wire rst = !locked || !(&reset_counter);

    // UART: 115200 baud, 8N1.
    wire [7:0] rx_byte;
    wire rx_valid, rx_busy, tx_busy;
    wire [7:0] tx_byte;
    wire tx_start;

    uart_rx #(
        .CLK_FREQ(50000000),
        .BAUD_RATE(115200)
    ) UART_RX (
        .clk(clk), .reset(rst),
        .rx(uart_rx_pin),
        .data_out(rx_byte),
        .data_valid(rx_valid),
        .busy(rx_busy)
    );

    uart_tx #(
        .CLK_FREQ(50000000),
        .BAUD_RATE(115200)
    ) UART_TX (
        .clk(clk), .reset(rst),
        .start_tx(tx_start),
        .data_in(tx_byte),
        .tx(uart_tx_pin),
        .busy(tx_busy)
    );

    // Blockchain interface.
    reg [7:0] pending_cmd;
    reg [31:0] pending_key;
    reg [15:0] pending_value;
    reg [3:0] pending_verify_index;

    wire bc_tx_ready, bc_result_valid;
    wire bc_result_ok;
    wire [3:0] bc_result_error;
    wire [31:0] bc_result_index;
    wire bc_search_ready, bc_search_done;
    wire bc_search_found, bc_search_error;
    wire [15:0] bc_search_value;
    wire [31:0] bc_next_index;
    wire [255:0] bc_last_hash;
    wire bc_busy;
    wire bc_verify_ready, bc_verify_done;
    wire bc_verify_valid, bc_verify_link_ok;
    wire bc_verify_hash_ok, bc_verify_error;

    reg [3:0] state;
    localparam ST_INPUT        = 4'd0,
               ST_TX_READY     = 4'd1,
               ST_TX_RESULT    = 4'd2,
               ST_SEARCH_READY = 4'd3,
               ST_SEARCH_DONE  = 4'd4,
               ST_SEND_START   = 4'd5,
               ST_SEND_BUSY    = 4'd6,
               ST_SEND_DONE    = 4'd7,
               ST_VERIFY_READY = 4'd8,
               ST_VERIFY_DONE  = 4'd9;

    wire bc_tx_valid = (state == ST_TX_READY);
    wire bc_search_start = (state == ST_SEARCH_READY);
    wire bc_result_ready =
        (state == ST_TX_RESULT) && bc_result_valid;
    wire bc_verify_start = (state == ST_VERIFY_READY);
    blockchain_kvs_search_chain_guarded_top BLOCKCHAIN (
        .clk(clk), .rst(rst),

        .search_start(bc_search_start),
        .search_key(pending_key),
        .search_ready(bc_search_ready),
        .search_done(bc_search_done),
        .search_found(bc_search_found),
        .search_value(bc_search_value),
        .search_error(bc_search_error),

        .tx_valid(bc_tx_valid),
        .tx_ready(bc_tx_ready),
        .tx_data({8'h00, pending_cmd, pending_key, pending_value}),

        .result_valid(bc_result_valid),
        .result_ready(bc_result_ready),
        .result_ok(bc_result_ok),
        .result_error(bc_result_error),
        .result_index(bc_result_index),

        .next_index(bc_next_index),
        .last_hash(bc_last_hash),
        .busy(bc_busy),

        // New UART-controlled integrity verification.
        .verify_start(bc_verify_start),
        .verify_index(pending_verify_index),
        .verify_ready(bc_verify_ready),
        .verify_done(bc_verify_done),
        .verify_valid(bc_verify_valid),
        .verify_link_ok(bc_verify_link_ok),
        .verify_hash_ok(bc_verify_hash_ok),
        .verify_error(bc_verify_error)
    );

    // Retain existing ILA configuration (5 probes).
    ila_0 ila_blockchain_debug (
        .clk(clk),
        .probe0(bc_last_hash),
        .probe1(bc_busy),
        .probe2(bc_search_done),
        .probe3(bc_result_valid),
        .probe4({bc_result_ok, bc_result_error, bc_verify_done})
    );

    // ASCII hexadecimal conversion.
    function [4:0] decode_hex;
        input [7:0] c;
        reg [3:0] nibble;
        reg valid;
        begin
            valid = 1'b1;
            nibble = 4'd0;
            if (c >= "0" && c <= "9")
                nibble = c - "0";
            else if (c >= "A" && c <= "F")
                nibble = c - "A" + 8'd10;
            else if (c >= "a" && c <= "f")
                nibble = c - "a" + 8'd10;
            else
                valid = 1'b0;
            decode_hex = {valid, nibble};
        end
    endfunction

    function [7:0] hex_ascii;
        input [3:0] n;
        begin
            if (n < 10)
                hex_ascii = "0" + {4'd0,n};
            else
                hex_ascii = "A" + {4'd0,n} - 8'd10;
        end
    endfunction

    // Protocol (CR-terminated):
    // PING          -> PONG
    // Cxxxxxxxxvvvv -> OK / ERRn
    // Txxxxxxxxvvvv -> OK / ERRn
    // Sxxxxxxxx     -> FOUND=vvvv / MISS / ERRSEARCH
    // V000n         -> VALID / INVALID / ERRVERIFY, n in [0..F]
    reg [4:0] line_len;
    reg [7:0] operation;
    reg [47:0] hex_acc;
    reg [31:0] word_shift;
    reg invalid_hex;
    wire [4:0] decoded = decode_hex(rx_byte);

    // Left-aligned UART response, up to 16 bytes.
    reg [127:0] response;
    reg [4:0] send_len;
    reg led_received;

    assign led_ok = led_received;
    assign tx_byte = response[127:120];
    assign tx_start = (state == ST_SEND_START) && !tx_busy;

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_INPUT;
            line_len <= 0;
            operation <= 0;
            hex_acc <= 0;
            word_shift <= 0;
            invalid_hex <= 0;
            pending_cmd <= 0;
            pending_key <= 0;
            pending_value <= 0;
            pending_verify_index <= 4'd0;
            response <= 0;
            send_len <= 0;
            led_received <= 0;
        end else begin
            case (state)
                ST_INPUT: if (rx_valid) begin
                    if (rx_byte == 8'h0A) begin
                        // Ignore LF.
                    end else if (rx_byte == 8'h0D) begin
                        line_len <= 0;

                        if (line_len == 4 &&
                            word_shift == 32'h50494E47) begin
                            response <= {"PONG",8'h0D,8'h0A,80'd0};
                            send_len <= 6;
                            state <= ST_SEND_START;

                        end else if (line_len == 13 &&
                                     !invalid_hex &&
                                     (operation == "C" ||
                                      operation == "T")) begin
                            pending_cmd <=
                                (operation == "C") ? 8'h01 : 8'h03;
                            pending_key <= hex_acc[47:16];
                            pending_value <= hex_acc[15:0];
                            state <= ST_TX_READY;

                        end else if (line_len == 9 &&
                                     !invalid_hex &&
                                     operation == "S") begin
                            pending_key <= hex_acc[31:0];
                            state <= ST_SEARCH_READY;

                        end else if (line_len == 5 &&
                                     !invalid_hex &&
                                     operation == "V" &&
                                     hex_acc[15:4] == 12'd0) begin
                            pending_verify_index <= hex_acc[3:0];
                            state <= ST_VERIFY_READY;

                        end else if (line_len != 0) begin
                            response <= {"ERRFMT",8'h0D,8'h0A,64'd0};
                            send_len <= 8;
                            state <= ST_SEND_START;
                        end
                    end else if (line_len < 14) begin
                        word_shift <= {word_shift[23:0],rx_byte};
                        line_len <= line_len + 1'b1;

                        if (line_len == 0) begin
                            operation <= rx_byte;
                            hex_acc <= 0;
                            invalid_hex <= 0;
                        end else begin
                            hex_acc <= {hex_acc[43:0],decoded[3:0]};
                            if (!decoded[4])
                                invalid_hex <= 1'b1;
                        end
                    end
                end

                ST_TX_READY: begin
                    if (bc_tx_ready)
                        state <= ST_TX_RESULT;
                end

                ST_TX_RESULT: if (bc_result_valid) begin
                    if (bc_result_ok) begin
                        response <= {"OK",8'h0D,8'h0A,96'd0};
                        send_len <= 4;
                        led_received <= 1'b1;
                    end else begin
                        response <= {
                            "ERR",
                            hex_ascii(bc_result_error),
                            8'h0D,8'h0A,80'd0
                        };
                        send_len <= 6;
                    end
                    state <= ST_SEND_START;
                end

                ST_SEARCH_READY: if (bc_search_ready)
                    state <= ST_SEARCH_DONE;

                ST_SEARCH_DONE: if (bc_search_done) begin
                    if (bc_search_error) begin
                        response <= {"ERRSEARCH",8'h0D,8'h0A,40'd0};
                        send_len <= 11;
                    end else if (bc_search_found) begin
                        response <= {
                            "FOUND=",
                            hex_ascii(bc_search_value[15:12]),
                            hex_ascii(bc_search_value[11:8]),
                            hex_ascii(bc_search_value[7:4]),
                            hex_ascii(bc_search_value[3:0]),
                            8'h0D,8'h0A,32'd0
                        };
                        send_len <= 12;
                        led_received <= 1'b1;
                    end else begin
                        response <= {"MISS",8'h0D,8'h0A,80'd0};
                        send_len <= 6;
                    end
                    state <= ST_SEND_START;
                end

                ST_VERIFY_READY: begin
                    if (bc_verify_ready)
                        state <= ST_VERIFY_DONE;
                end

                ST_VERIFY_DONE: if (bc_verify_done) begin
                    if (bc_verify_error) begin
                        response <= {"ERRVERIFY",8'h0D,8'h0A,40'd0};
                        send_len <= 11;
                    end else if (bc_verify_valid &&
                                 bc_verify_link_ok &&
                                 bc_verify_hash_ok) begin
                        response <= {"VALID",8'h0D,8'h0A,72'd0};
                        send_len <= 7;
                        led_received <= 1'b1;
                    end else begin
                        response <= {"INVALID",8'h0D,8'h0A,56'd0};
                        send_len <= 9;
                    end
                    state <= ST_SEND_START;
                end

                ST_SEND_START: if (!tx_busy)
                    state <= ST_SEND_BUSY;

                ST_SEND_BUSY: if (tx_busy)
                    state <= ST_SEND_DONE;

                ST_SEND_DONE: if (!tx_busy) begin
                    if (send_len == 1) begin
                        send_len <= 0;
                        state <= ST_INPUT;
                    end else begin
                        response <= response << 8;
                        send_len <= send_len - 1'b1;
                        state <= ST_SEND_START;
                    end
                end

                default: state <= ST_INPUT;
            endcase
        end
    end
endmodule
