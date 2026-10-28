`timescale 1ns/1ps

module canfd_adapter_decoder_tb;

    reg clk = 0;
    reg rst = 1;

    always #5 clk = ~clk;

    // Entree : trame recue du CAN-FD RX
    reg [63:0] can_data = 64'd0;
    reg [3:0] can_dlc = 4'd0;
    reg can_frame_done = 0;
    reg can_frame_valid = 0;

    // Liaison adaptateur -> decodeur
    wire [7:0] rx_data;
    wire rx_valid;
    wire rx_frame_done;
    wire rx_error;
    wire adapter_busy;

    // Commande vers le Key-Value Store
    wire [7:0] ck_cmd;
    wire [31:0] ck_key;
    wire [15:0] ck_value;
    wire ck_start;

    reg ck_busy = 0;
    reg ck_done = 0;
    reg ck_found = 0;
    reg [15:0] ck_value_out = 0;
    reg ck_error = 0;

    // Reponse du decodeur
    wire resp_valid;
    wire [7:0] resp_cmd;
    wire [7:0] resp_status;
    wire [15:0] resp_value;

    wire err_valid;
    wire [1:0] err_code;
    wire dbg_overrun;
    wire dbg_rejected;
    wire [2:0] dbg_state;

    integer errors = 0;
    integer bytes_received = 0;

    reg seen_ck_start = 0;
    reg seen_response = 0;
    reg [7:0] saved_status = 0;

    // =======================================
    // 1. ADAPTATEUR DE NADA
    // =======================================

    canfd_rx_adapter ADAPTER (
        .clk(clk),
        .rst(rst),
        .can_data(can_data),
        .can_dlc(can_dlc),
        .can_frame_done(can_frame_done),
        .can_frame_valid(can_frame_valid),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .rx_frame_done(rx_frame_done),
        .rx_error(rx_error),
        .busy(adapter_busy)
    );

    // =======================================
    // 2. DECODEUR DE SANAE
    // =======================================

    cmd_decoder #(.TIMEOUT(2000)) DEC (
        .clk(clk),
        .rst(rst),

        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .rx_frame_done(rx_frame_done),
        .rx_error(rx_error),

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
        .resp_ready(1'b1),
        .resp_cmd(resp_cmd),
        .resp_status(resp_status),
        .resp_value(resp_value),

        .err_valid(err_valid),
        .err_code(err_code),
        .dbg_overrun(dbg_overrun),
        .dbg_rejected(dbg_rejected),
        .dbg_state(dbg_state)
    );

    // =======================================
    // 3. FAUX KEY-VALUE STORE
    // =======================================

    integer countdown = 0;

    always @(posedge clk) begin
        if (rst) begin
            ck_busy <= 0;
            ck_done <= 0;
            ck_found <= 0;
            ck_value_out <= 0;
            ck_error <= 0;
            countdown <= 0;
        end else begin
            ck_done <= 0;

            if (ck_start && !ck_busy) begin
                ck_busy <= 1;
                countdown <= 3;
            end else if (ck_busy) begin
                if (countdown == 1) begin
                    ck_busy <= 0;
                    ck_done <= 1;
                    ck_found <= 0;
                    ck_error <= 0;
                    countdown <= 0;
                end else begin
                    countdown <= countdown - 1;
                end
            end
        end
    end

    // =======================================
    // 4. SURVEILLANCE
    // =======================================

    always @(posedge clk) begin
        if (rst) begin
            bytes_received <= 0;
            seen_ck_start <= 0;
            seen_response <= 0;
            saved_status <= 0;
        end else begin

            if (rx_valid) begin
                bytes_received <= bytes_received + 1;
                $display("Octet transmis : 0x%02h", rx_data);
            end

            if (ck_start) begin
                seen_ck_start <= 1;

                $display("");
                $display("COMMANDE DECODEE :");
                $display("ck_cmd   = 0x%02h", ck_cmd);
                $display("ck_key   = 0x%08h", ck_key);
                $display("ck_value = 0x%04h", ck_value);
                $display("ck_start = %b", ck_start);

                if (ck_cmd !== 8'h01 ||
                    ck_key !== 32'h12345678 ||
                    ck_value !== 16'h00AA)
                    errors = errors + 1;
            end

            if (resp_valid) begin
                seen_response <= 1;
                saved_status <= resp_status;

                $display("");
                $display("REPONSE DECODEUR :");
                $display("resp_cmd    = 0x%02h", resp_cmd);
                $display("resp_status = 0x%02h", resp_status);

                if (resp_cmd !== 8'h01 ||
                    resp_status !== 8'h00)
                    errors = errors + 1;
            end

            if (err_valid || dbg_rejected)
                errors = errors + 1;
        end
    end

    // =======================================
    // 5. SCENARIO CREATE
    // =======================================

    initial begin
        $dumpfile("adapter_decoder.vcd");
        $dumpvars(0, canfd_adapter_decoder_tb);

        repeat (5) @(negedge clk);
        rst = 0;

        repeat (5) @(negedge clk);

        // LEN=7, CREATE=1, KEY=12345678, VALUE=00AA
        can_data = 64'h07011234567800AA;
        can_dlc = 4'd8;
        can_frame_valid = 1;
        can_frame_done = 1;

        @(negedge clk);
        can_frame_done = 0;

        wait (seen_response);
        repeat (3) @(negedge clk);

        $display("");
        $display("==============================");
        $display("RESULTAT INTEGRATION");
        $display("==============================");

        $display("Octets recus : %0d", bytes_received);
        $display("Commande vue : %b", seen_ck_start);
        $display("Reponse vue  : %b", seen_response);
        $display("Statut      : 0x%02h", saved_status);
        $display("Erreurs     : %0d", errors);

        if (bytes_received == 8 &&
            seen_ck_start &&
            seen_response &&
            saved_status == 8'h00 &&
            errors == 0)
            $display("PASS : ADAPTATEUR -> CMD_DECODER");
        else
            $display("FAIL : ADAPTATEUR -> CMD_DECODER");

        $finish;
    end

    // =======================================
    // 6. TIMEOUT
    // =======================================

    initial begin
        #100000;
        $display("FAIL : TIMEOUT ADAPTER DECODER");
        $display("Etat decodeur : %0d", dbg_state);
        $display("Octets recus  : %0d", bytes_received);
        $display("Commande vue  : %b", seen_ck_start);
        $finish;
    end

endmodule
