`timescale 1ns/1ps
// Dashboard: testbench seulement. Les trois modules RTL d'origine restent inchanges.
// Format des traces: DASH|BLOCK|index|tx|prev|stored|computed|expected_prev|link|hash_ok|valid|cycles
module dashboard_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk; // Simulation a 100 MHz
    reg rst = 1'b1;

    reg h_start = 1'b0;
    reg [31:0] h_index = 0;
    reg [255:0] h_prev = 0;
    reg [63:0] h_tx = 0;
    wire h_busy, h_done;
    wire [255:0] h_hash;
    block_hash hash_dut (
        .clk(clk), .rst(rst), .start(h_start),
        .index(h_index), .previous_hash(h_prev), .transaction(h_tx),
        .busy(h_busy), .done(h_done), .hash(h_hash)
    );

    reg v_start = 1'b0;
    reg [31:0] v_index = 0;
    reg [255:0] v_prev = 0;
    reg [63:0] v_tx = 0;
    reg [255:0] v_stored = 0;
    reg [255:0] v_expected_prev = 0;
    wire v_busy, v_done, v_link_ok, v_hash_ok, v_valid;
    wire [255:0] v_computed;
    chain_validator validator_dut (
        .clk(clk), .rst(rst), .start(v_start),
        .index(v_index), .previous_hash(v_prev), .transaction(v_tx),
        .stored_hash(v_stored), .expected_previous_hash(v_expected_prev),
        .busy(v_busy), .done(v_done), .link_ok(v_link_ok),
        .hash_ok(v_hash_ok), .chain_valid(v_valid), .computed_hash(v_computed)
    );

    reg [63:0] transactions [0:2];
    reg [255:0] hashes [0:2];
    reg [255:0] predecessors [0:2];
    reg [255:0] hash_tmp, hash_wrong_prev;
    reg [255:0] current_prev, current_stored, current_expected;
    reg [63:0] current_tx;
    integer scenario = 0, target = 1, i;
    integer checks = 0;
    integer checks_valid = 0;

    task calculate_hash;
        input [31:0] idx;
        input [255:0] prev;
        input [63:0] tx;
        output [255:0] result;
        begin
            @(negedge clk);
            h_index = idx;
            h_prev = prev;
            h_tx = tx;
            h_start = 1'b1;
            @(negedge clk);
            h_start = 1'b0;
            wait (h_done === 1'b1);
            result = h_hash;
            @(negedge clk);
        end
    endtask

    task validate_and_emit;
        input [31:0] idx;
        input [255:0] prev;
        input [63:0] tx;
        input [255:0] stored;
        input [255:0] expected_prev;
        integer start_cycle, elapsed_cycles;
        begin
            @(negedge clk);
            v_index = idx;
            v_prev = prev;
            v_tx = tx;
            v_stored = stored;
            v_expected_prev = expected_prev;
            v_start = 1'b1;
            start_cycle = $time / 10;
            @(negedge clk);
            v_start = 1'b0;
            wait (v_done === 1'b1);
            @(negedge clk);
            elapsed_cycles = ($time / 10) - start_cycle;
            $display("DASH|BLOCK|%0d|%016h|%064h|%064h|%064h|%064h|%0d|%0d|%0d|%0d",
                idx, tx, prev, stored, v_computed, expected_prev,
                v_link_ok, v_hash_ok, v_valid, elapsed_cycles);
            checks = checks + 1;
            if (v_valid) checks_valid = checks_valid + 1;
        end
    endtask

    initial begin
        $dumpfile("blockchain_dashboard.vcd");
        $dumpvars(0, dashboard_tb);
        transactions[0] = 64'h07011234567800AA;
        transactions[1] = 64'h0703123456780055;
        transactions[2] = 64'h1122334455667788;
        if ($value$plusargs("TX0=%h", transactions[0])) begin end
        if ($value$plusargs("TX1=%h", transactions[1])) begin end
        if ($value$plusargs("TX2=%h", transactions[2])) begin end
        if ($value$plusargs("SCENARIO=%d", scenario)) begin end
        if ($value$plusargs("TARGET=%d", target)) begin end
        if (target < 0 || target > 2 || scenario < 0 || scenario > 3) begin
            $display("DASH|ERROR|Arguments de simulation invalides");
            $finish;
        end
        $display("DASH|START|scenario=%0d|target=%0d", scenario, target);
        repeat (5) @(negedge clk);
        rst = 1'b0;

        // Construire 3 vrais blocs avec le module block_hash (SHA-256 RTL).
        for (i = 0; i < 3; i = i + 1) begin
            if (i == 0)
                predecessors[i] = 256'd0; // convention du bloc initial
            else
                predecessors[i] = hashes[i - 1];
            calculate_hash(i, predecessors[i], transactions[i], hash_tmp);
            hashes[i] = hash_tmp;
        end

        // Scenario 2: produire un hash coherent pour un mauvais parent.
        // Cela isole une erreur de lien: link_ok=0 mais hash_ok=1.
        if (scenario == 2) begin
            calculate_hash(target, predecessors[target] ^ 256'd1,
                           transactions[target], hash_wrong_prev);
        end

        for (i = 0; i < 3; i = i + 1) begin
            current_tx = transactions[i];
            current_prev = predecessors[i];
            current_stored = hashes[i];
            if (i == 0)
                current_expected = 256'd0;
            else
                current_expected = hashes[i - 1];

            if (i == target) begin
                case (scenario)
                    1: current_tx = current_tx ^ 64'd1; // donnees modifiees
                    2: begin
                        current_prev = current_prev ^ 256'd1;
                        current_stored = hash_wrong_prev;
                    end
                    3: current_stored = current_stored ^ 256'd1; // hash stocke corrompu
                    default: begin end
                endcase
            end
            validate_and_emit(i, current_prev, current_tx,
                              current_stored, current_expected);
        end
        $display("DASH|END|%0d|%0d", checks, checks_valid);
        $finish;
    end

    initial begin
        #120000;
        $display("DASH|ERROR|TIMEOUT");
        $finish;
    end
endmodule
