`timescale 1ns/1ps
// Testbench du moteur CRC CAN FD.
// Test 1 et 2 : vecteurs de controle du catalogue CRC (message "123456789", init a 0)
//               CRC-17/CAN-FD = 0x04F03   CRC-21/CAN-FD = 0x0ED841
// Test 3 et 4 : init CAN FD (bit de poids fort a 1), motif 0123456789ABCDEF
//               valeurs calculees avec le modele Python (canfd_model.py)
module canfd_crc_tb;
    reg clk = 0, rst = 1, load_init = 0, en = 0, din = 0;
    wire [16:0] c17z, c17;
    wire [20:0] c21z, c21;

    canfd_crc #(.WIDTH(17), .POLY(21'h1685B),  .INIT(21'h0))      u17z (.clk(clk), .rst(rst), .load_init(load_init), .en(en), .din(din), .crc(c17z));
    canfd_crc #(.WIDTH(21), .POLY(21'h102899), .INIT(21'h0))      u21z (.clk(clk), .rst(rst), .load_init(load_init), .en(en), .din(din), .crc(c21z));
    canfd_crc #(.WIDTH(17), .POLY(21'h1685B),  .INIT(21'h10000))  u17  (.clk(clk), .rst(rst), .load_init(load_init), .en(en), .din(din), .crc(c17));
    canfd_crc #(.WIDTH(21), .POLY(21'h102899), .INIT(21'h100000)) u21  (.clk(clk), .rst(rst), .load_init(load_init), .en(en), .din(din), .crc(c21));

    always #5 clk = ~clk;

    integer errors = 0;
    integer i;

    task send_bit(input b);
        begin
            @(negedge clk); din = b; en = 1;
            @(negedge clk); en = 0;
        end
    endtask

    task send_byte(input [7:0] x);
        integer k;
        begin
            for (k = 7; k >= 0; k = k - 1) send_bit(x[k]);
        end
    endtask

    task check17(input [16:0] got, input [16:0] exp, input [255:0] name);
        begin
            if (got === exp) $display("PASS  %0s : 0x%05h", name, got);
            else begin $display("FAIL  %0s : obtenu 0x%05h, attendu 0x%05h", name, got, exp); errors = errors + 1; end
        end
    endtask

    task check21(input [20:0] got, input [20:0] exp, input [255:0] name);
        begin
            if (got === exp) $display("PASS  %0s : 0x%06h", name, got);
            else begin $display("FAIL  %0s : obtenu 0x%06h, attendu 0x%06h", name, got, exp); errors = errors + 1; end
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst = 0;

        // message "123456789"
        send_byte("1"); send_byte("2"); send_byte("3"); send_byte("4"); send_byte("5");
        send_byte("6"); send_byte("7"); send_byte("8"); send_byte("9");
        check17(c17z, 17'h04F03, "CRC-17 init 0  ('123456789')");
        check21(c21z, 21'h0ED841, "CRC-21 init 0  ('123456789')");

        // recharge l'init CAN FD puis envoie 0123456789ABCDEF
        @(negedge clk); load_init = 1;
        @(negedge clk); load_init = 0;
        send_byte(8'h01); send_byte(8'h23); send_byte(8'h45); send_byte(8'h67);
        send_byte(8'h89); send_byte(8'hAB); send_byte(8'hCD); send_byte(8'hEF);
        check17(c17, 17'h1E7E1, "CRC-17 init CAN FD (motif)");
        check21(c21, 21'h1FB023, "CRC-21 init CAN FD (motif)");

        if (errors == 0) $display("=== TOUS LES TESTS CRC REUSSIS ===");
        else             $display("=== %0d ERREUR(S) ===", errors);
        $finish;
    end
endmodule
