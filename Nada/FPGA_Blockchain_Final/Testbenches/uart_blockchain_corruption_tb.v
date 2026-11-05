`timescale 1ns/1ps

// Simulation only: CREATE -> VERIFY VALID -> corrupt stored hash -> VERIFY INVALID.
// This does not alter the programmed FPGA or the source memory RTL.
module uart_blockchain_corruption_tb;
    reg sysclk_p = 1'b0;
    wire sysclk_n = ~sysclk_p;
    reg uart_rx_pin = 1'b1;
    wire uart_tx_pin, led_ok;

    // AC701 differential reference clock: 200 MHz.
    always #2.5 sysclk_p = ~sysclk_p;

    uart_blockchain_top dut (
        .sysclk_p(sysclk_p), .sysclk_n(sysclk_n),
        .uart_rx_pin(uart_rx_pin), .uart_tx_pin(uart_tx_pin),
        .led_ok(led_ok)
    );

    localparam integer BIT_NS = 8681; // ~115200 baud
    reg [127:0] last_response;
    integer last_length;
    reg [7:0] rx_char;
    integer j;

    task send_uart_byte;
        input [7:0] c;
        integer b;
        begin
            uart_rx_pin = 1'b0;  // Start bit
            #(BIT_NS);
            for (b = 0; b < 8; b = b + 1) begin
                uart_rx_pin = c[b]; // LSB first
                #(BIT_NS);
            end
            uart_rx_pin = 1'b1;  // Stop bit
            #(BIT_NS);
        end
    endtask

    task send_create;
        begin
            // C + key(00000001) + value(0064) + CR
            send_uart_byte("C");
            send_uart_byte("0"); send_uart_byte("0");
            send_uart_byte("0"); send_uart_byte("0");
            send_uart_byte("0"); send_uart_byte("0");
            send_uart_byte("0"); send_uart_byte("1");
            send_uart_byte("0"); send_uart_byte("0");
            send_uart_byte("6"); send_uart_byte("4");
            send_uart_byte(8'h0D);
        end
    endtask

    task send_verify;
        begin
            // V0000 + CR: request verification at index 0
            send_uart_byte("V");
            send_uart_byte("0"); send_uart_byte("0");
            send_uart_byte("0"); send_uart_byte("0");
            send_uart_byte(8'h0D);
        end
    endtask

    task receive_uart_byte;
        output [7:0] c;
        integer b;
        begin
            @(negedge uart_tx_pin);
            #(BIT_NS + BIT_NS/2); // Center of data bit 0
            for (b = 0; b < 8; b = b + 1) begin
                c[b] = uart_tx_pin;
                #(BIT_NS);
            end
            if (uart_tx_pin !== 1'b1)
                $display("WARNING: UART stop bit not high");
            #(BIT_NS/2);
        end
    endtask

    task receive_line;
        integer n;
        reg done;
        begin
            last_response = 128'd0;
            last_length = 0;
            done = 1'b0;
            for (n = 0; n < 16 && !done; n = n + 1) begin
                receive_uart_byte(rx_char);
                if (rx_char == 8'h0D || rx_char == 8'h0A) begin
                    done = 1'b1;
                end else begin
                    last_response = (last_response << 8) | rx_char;
                    last_length = last_length + 1;
                end
            end
        end
    endtask

    // Deadlock protection: a missing FPGA reply fails the simulation.
    initial begin
        #50000000; // 50 ms
        $display("FAIL TIMEOUT: FPGA did not finish integrity test");
        $finish;
    end

    initial begin
        // Allow MMCM lock and 16-bit reset counter to settle.
        #2000000;
        $display("TEST 1: CREATE key=1 value=100");
        fork
            send_create();
            receive_line();
        join
        $display("CREATE reply: %0s", last_response);
        if (last_response !== "OK") begin
            $display("FAIL CREATE: expected OK");
            $finish;
        end
        $display("PASS CREATE");

        // Remaining CRLF LF will be transmitted while the next command starts;
        // delay for a clean turnaround.
        #1000000;
        $display("TEST 2: VERIFY index=0 (V0000)");
        fork
            send_verify();
            receive_line();
        join
        $display("VERIFY reply: %0s", last_response);

        if (last_response !== "VALID") begin
            $display("FAIL: intact block must return VALID");
            $fatal(1);
        end
        $display("PASS: intact block VALID");

        // The first user block is stored at physical slot 1 (slot 0 is Genesis).
        // Corrupt the least-significant bit of the stored 256-bit hash.
        // Full hierarchy: top -> blockchain -> block subsystem -> adapter -> BRAM.
        #1000000;
        $display("Stored hash bit before: %b",
                 dut.BLOCKCHAIN.BLOCKS_REAL.STORAGE_KHADIJA.STORAGE.mem[1][0]);
        dut.BLOCKCHAIN.BLOCKS_REAL.STORAGE_KHADIJA.STORAGE.mem[1][0] =
            ~dut.BLOCKCHAIN.BLOCKS_REAL.STORAGE_KHADIJA.STORAGE.mem[1][0];
        $display("Stored hash bit after : %b",
                 dut.BLOCKCHAIN.BLOCKS_REAL.STORAGE_KHADIJA.STORAGE.mem[1][0]);

        #1000000;
        $display("TEST 3: VERIFY corrupted block index=0 (V0000)");
        fork
            send_verify();
            receive_line();
        join
        $display("Corrupted VERIFY reply: %0s", last_response);
        if (last_response !== "INVALID") begin
            $display("FAIL: corrupted stored hash was not rejected");
            $fatal(1);
        end
        $display("PASS: CORRUPTION DETECTED (INVALID)");
        $display("ALL INTEGRITY TESTS PASSED");
        $finish;
    end
endmodule
