`timescale 1ns/1ps

// Etape 6 : CRC-17 + ACK dominant + controle des delimiteurs et EOF.
// Configuration de test : ID=0x123, DLC=2, soit 38 bits utiles.
// Test cible : meme format que le TX actuel de Nada (DLC=2).
module canfd_rx #(
    parameter integer CLK_FREQ     = 100_000_000,
    parameter integer BIT_RATE     = 1_000_000,
    parameter integer FRAME_BITS   = 76,
    parameter integer PAYLOAD_BITS = 38
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       can_rx,

    output reg        sample_bit,
    output reg        sample_valid,
    output reg        busy,
    output reg [6:0]  bit_index,

    output reg        payload_bit,
    output reg        payload_valid,
    output reg [6:0]  payload_count,
    output reg [7:0]  stuff_count,
    output reg        stuff_error,
    output reg        payload_done,

    // Champs decodes apres le destuffing (trame de test DLC=2).
    output reg [10:0] rx_id,
    output reg [3:0]  rx_dlc,
    output reg [63:0] rx_data,
    output reg        decode_done,

    // Verification CRC-17 (etape 5 du travail pratique)
    output reg [16:0] crc_calc,
    output reg [16:0] crc_recu,
    output reg [3:0]  sbc_recu,
    output reg        fsb_error,
    output reg        crc_done,
    output reg        crc_ok,

    // Sortie a relier a un transceiver CAN (dominant=0).
    // Dans le TB : can_bus = tx_can_tx & ~ack_drive_low.
    output reg        ack_drive_low,
    output reg        ack_sent,
    output reg        tail_error,
    output reg        frame_done,
    output reg        frame_valid
);

    localparam integer BIT_CLKS    = CLK_FREQ / BIT_RATE;
    localparam integer SAMPLE_CLKS = (BIT_CLKS * 75) / 100;

    reg rx_meta;
    reg rx_sync;
    reg rx_prev;
    reg [15:0] timer;

    reg last_bit;
    reg [2:0] run_count;
    reg pending_last_stuff;

    wire start_frame = rx_prev && !rx_sync;

    // Synchronisation du bus CAN vers l'horloge FPGA.
    always @(posedge clk) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            rx_prev <= 1'b1;
        end else begin
            rx_meta <= can_rx;
            rx_sync <= rx_meta;
            rx_prev <= rx_sync;
        end
    end

    // Echantillonneur, conserve le fonctionnement de l'etape 1.
    always @(posedge clk) begin
        if (rst) begin
            timer        <= 0;
            busy         <= 0;
            bit_index    <= 0;
            sample_bit   <= 1'b1;
            sample_valid <= 1'b0;
        end else begin
            sample_valid <= 1'b0;

            if (!busy) begin
                timer <= 0;
                if (start_frame) begin
                    busy      <= 1'b1;
                    bit_index <= 0;
                end
            end else if (timer == ((bit_index == 0)
                        ? SAMPLE_CLKS - 1 : BIT_CLKS - 1)) begin
                timer        <= 0;
                sample_bit   <= rx_sync;
                sample_valid <= 1'b1;

                if (bit_index == FRAME_BITS - 1)
                    busy <= 1'b0;
                else
                    bit_index <= bit_index + 1'b1;
            end else begin
                timer <= timer + 1'b1;
            end
        end
    end

    // Suppression du stuffing DYNAMIQUE dans le payload uniquement.
    // Apres cinq bits identiques, le bit suivant doit etre oppose.
    always @(posedge clk) begin
        if (rst) begin
            payload_bit       <= 1'b0;
            payload_valid     <= 1'b0;
            payload_count     <= 0;
            stuff_count       <= 0;
            stuff_error       <= 1'b0;
            payload_done      <= 1'b0;
            last_bit          <= 1'b0;
            run_count         <= 0;
            pending_last_stuff <= 1'b0;
        end else begin
            payload_valid <= 1'b0;

            if (start_frame && !busy) begin
                payload_count      <= 0;
                stuff_count        <= 0;
                stuff_error        <= 1'b0;
                payload_done       <= 1'b0;
                run_count          <= 0;
                last_bit           <= 1'b0;
                pending_last_stuff <= 1'b0;
            end else if (sample_valid && !payload_done) begin
                if (run_count == 3'd5) begin
                    // Bit insere par l'emetteur : verifier puis ignorer.
                    if (sample_bit == last_bit)
                        stuff_error <= 1'b1;

                    stuff_count <= stuff_count + 1'b1;
                    last_bit    <= sample_bit;
                    run_count   <= 3'd1;

                    if (pending_last_stuff) begin
                        payload_done       <= 1'b1;
                        pending_last_stuff <= 1'b0;
                    end
                end else begin
                    // Bit original conserve pour le decodage suivant.
                    payload_bit   <= sample_bit;
                    payload_valid <= 1'b1;
                    payload_count <= payload_count + 1'b1;

                    if (sample_bit == last_bit && run_count != 0)
                        run_count <= run_count + 1'b1;
                    else
                        run_count <= 3'd1;
                    last_bit <= sample_bit;

                    // Le TX de Nada passe au champ CRC apres
                    // le dernier bit utile sans stuffing dynamique final.
                    
if (payload_count == PAYLOAD_BITS - 1) begin

    // Si le dernier bit utile complete une suite
    // de cinq bits identiques, attendre le stuffing final.
    if (run_count == 3'd4 && sample_bit == last_bit) begin
        pending_last_stuff <= 1'b1;
    end
    else begin
        payload_done <= 1'b1;
    end

end

                end
            end
        end
    end
    // Decodage des 38 bits utiles :
    // 1 SOF + 11 ID + 6 controle + 4 DLC + 16 DATA.
    // Le bloc ci-dessous lit les valeurs deja destuffees.
    // Attention : payload_valid est lu au cycle suivant sa mise a 1.
    // Ainsi payload_count vaut 2..12 pour l'ID, 19..22 pour le DLC,
    // et 23..38 pour les deux octets de donnees.
    always @(posedge clk) begin
        if (rst) begin
            rx_id       <= 11'd0;
            rx_dlc      <= 4'd0;
            rx_data     <= 64'd0;
            decode_done <= 1'b0;
        end else begin
            decode_done <= 1'b0;

            if (start_frame && !busy) begin
                rx_id   <= 11'd0;
                rx_dlc  <= 4'd0;
                rx_data <= 64'd0;
            end else if (payload_valid) begin
                if (payload_count >= 7'd2 && payload_count <= 7'd12)
                    rx_id <= {rx_id[9:0], payload_bit};

                if (payload_count >= 7'd19 && payload_count <= 7'd22)
                    rx_dlc <= {rx_dlc[2:0], payload_bit};

                if (payload_count >= 7'd23 && payload_count <= 7'd38)
                    rx_data <= {rx_data[62:0], payload_bit};

                if (payload_count == PAYLOAD_BITS)
                    decode_done <= 1'b1;
            end
        end
    end

    // ---------------------------------------------------------
    // VERIFICATION CRC-17 (polynome et INIT du TX de Nada)
    // La valeur du CRC porte sur les bits physiques du payload
    // (stuffing dynamique compris), puis sur les 4 bits SBC.
    // Le champ CRC contient 27 bits :
    // FSB, SBC[3:0], FSB, CRC[16:13], FSB, CRC[12:9],
    // FSB, CRC[8:5], FSB, CRC[4:1], FSB, CRC[0].
    // Les six FSB ne contribuent PAS au CRC.
    // ---------------------------------------------------------
    function [16:0] crc17_step;
        input [16:0] current_crc;
        input         bit_in;
        reg           feedback;
        begin
            feedback = current_crc[16] ^ bit_in;
            crc17_step = {current_crc[15:0], 1'b0} ^
                         (feedback ? 17'h1685B : 17'h00000);
        end
    endfunction

    reg [4:0] crc_field_index;
    reg       prev_wire_bit;

    wire [2:0] gray_attendu = stuff_count[2:0] ^
                             (stuff_count[2:0] >> 1);
    wire [3:0] sbc_attendu  = {gray_attendu, ^gray_attendu};

    // Indices des bits de stuffing fixes dans les 27 bits du champ.
    wire est_fsb = (crc_field_index == 5'd0)  ||
                   (crc_field_index == 5'd5)  ||
                   (crc_field_index == 5'd10) ||
                   (crc_field_index == 5'd15) ||
                   (crc_field_index == 5'd20) ||
                   (crc_field_index == 5'd25);

    always @(posedge clk) begin
        if (rst) begin
            crc_calc        <= 17'h10000;
            crc_recu        <= 17'd0;
            sbc_recu        <= 4'd0;
            crc_field_index <= 5'd0;
            prev_wire_bit   <= 1'b1;
            fsb_error       <= 1'b0;
            crc_done        <= 1'b0;
            crc_ok          <= 1'b0;
        end else if (start_frame && !busy) begin
            crc_calc        <= 17'h10000;
            crc_recu        <= 17'd0;
            sbc_recu        <= 4'd0;
            crc_field_index <= 5'd0;
            prev_wire_bit   <= 1'b1;
            fsb_error       <= 1'b0;
            crc_done        <= 1'b0;
            crc_ok          <= 1'b0;
        end else if (sample_valid && !crc_done) begin
            if (!payload_done) begin
                // Flux brut : contient aussi les bits de stuffing dynamique.
                crc_calc      <= crc17_step(crc_calc, sample_bit);
                prev_wire_bit <= sample_bit;
            end else if (crc_field_index < 5'd27) begin
                // Apres les 38 bits utiles, traiter le champ CRC transmis.
                prev_wire_bit <= sample_bit;
                crc_field_index <= crc_field_index + 5'd1;

                if (est_fsb) begin
                    // Chaque FSB doit etre l'inverse du bit precedent.
                    if (sample_bit == prev_wire_bit)
                        fsb_error <= 1'b1;
                end else if (crc_field_index >= 5'd1 &&
                             crc_field_index <= 5'd4) begin
                    // SBC (code Gray et bit de parite), inclus dans le CRC.
                    sbc_recu <= {sbc_recu[2:0], sample_bit};
                    crc_calc <= crc17_step(crc_calc, sample_bit);
                end else begin
                    // 17 bits CRC recus, sans leurs bits FSB.
                    crc_recu <= {crc_recu[15:0], sample_bit};
                    if (crc_field_index == 5'd26) begin
                        crc_done <= 1'b1;
                        crc_ok <=
                            ({crc_recu[15:0], sample_bit} == crc_calc) &&
                            (sbc_recu == sbc_attendu) &&
                            !fsb_error && !stuff_error;
                    end
                end
            end
        end
    end

    // ---------------------------------------------------------
    // Etape 6 : ACK et verification de la fin de trame.
    // Apres le dernier bit CRC, le TX de Nada envoie :
    // 0: CRC delimiter, 1: ACK slot, 2: ACK delimiter, 3..9: EOF.
    // Le RX echantillonne a 75 % du bit. Apres avoir echantillonne
    // le CRC delimiter, il reste 25 % d'un bit avant l'ACK slot.
    // On force 0 pendant exactement un temps-bit (100 clocks).
    // ---------------------------------------------------------
    localparam [1:0] ACK_IDLE = 2'd0,
                     ACK_WAIT = 2'd1,
                     ACK_DRIVE = 2'd2;
    localparam integer ACK_DELAY_CLKS = BIT_CLKS - SAMPLE_CLKS;

    reg [1:0] ack_state;
    reg [15:0] ack_timer;
    reg [3:0] tail_rx_index;

    always @(posedge clk) begin
        if (rst || (start_frame && !busy)) begin
            ack_drive_low <= 1'b0;
            ack_sent <= 1'b0;
            ack_state <= ACK_IDLE;
            ack_timer <= 0;
            tail_rx_index <= 0;
            tail_error <= 1'b0;
            frame_done <= 1'b0;
            frame_valid <= 1'b0;
        end else begin
            frame_done <= 1'b0;

            // Timer independant du decodage, pour ne pas modifier
            // l'echantillonnage qui a deja ete valide.
            case (ack_state)
                ACK_WAIT: begin
                    if (ack_timer == ACK_DELAY_CLKS - 2) begin
                        ack_drive_low <= 1'b1;
                        ack_timer <= 0;
                        ack_state <= ACK_DRIVE;
                    end else
                        ack_timer <= ack_timer + 1'b1;
                end
                ACK_DRIVE: begin
                    if (ack_timer == BIT_CLKS - 1) begin
                        ack_drive_low <= 1'b0;
                        ack_sent <= 1'b1;
                        ack_timer <= 0;
                        ack_state <= ACK_IDLE;
                    end else
                        ack_timer <= ack_timer + 1'b1;
                end
                default: begin
                    ack_drive_low <= 1'b0;
                end
            endcase

            // crc_done passe a 1 apres la reception du 27e bit du
            // champ CRC. Le sample_valid suivant est le delimiter.
            if (crc_done && sample_valid && tail_rx_index < 4'd10) begin
                tail_rx_index <= tail_rx_index + 1'b1;
                if (tail_rx_index == 4'd0) begin
                    // CRC delimiter : toujours recessif.
                    if (sample_bit !== 1'b1)
                        tail_error <= 1'b1;
                    else if (crc_ok && !stuff_error && !fsb_error) begin
                        // Echantillonnage a 75 %. Attendre environ
                        // 25 clocks puis activer l'ACK dominant.
                        ack_timer <= 0;
                        ack_state <= ACK_WAIT;
                    end
                end else if (tail_rx_index >= 4'd2) begin
                    // ACK delimiter (2) et les 7 bits EOF (3..9) : 1
                    if (sample_bit !== 1'b1)
                        tail_error <= 1'b1;
                end

                if (tail_rx_index == 4'd9) begin
                    frame_done <= 1'b1;
                    frame_valid <= crc_ok && !stuff_error &&
                                  !fsb_error && !tail_error &&
                                  (sample_bit === 1'b1);
                end
            end
        end
    end
endmodule
