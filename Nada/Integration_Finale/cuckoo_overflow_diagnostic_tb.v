`timescale 1ns/1ps

module cuckoo_overflow_diagnostic_tb;

reg clk = 0;
reg rst = 1;
reg [7:0] cmd = 0;
reg [31:0] key = 0;
reg [15:0] value_in = 0;
reg start = 0;
reg txn_begin = 0;
reg txn_commit = 0;
reg txn_rollback = 0;

wire busy, done, found, error;
wire [15:0] value_out;
wire txn_rollback_done;
wire txn_journal_overflow;

always #5 clk = ~clk;

cuckoo_top_atomic dut (
    .clk(clk), .rst(rst),
    .cmd(cmd), .key(key),
    .value_in(value_in), .start(start),
    .txn_begin(txn_begin),
    .txn_commit(txn_commit),
    .txn_rollback(txn_rollback),
    .txn_rollback_done(txn_rollback_done),
    .txn_journal_overflow(txn_journal_overflow),
    .busy(busy), .done(done),
    .found(found), .value_out(value_out),
    .error(error)
);

initial begin
    #100000;
    $display("FAIL: timeout");
    $finish;
end

initial begin
    repeat (5) @(negedge clk);
    rst = 0;

    @(negedge clk);
    txn_begin = 1;
    @(negedge clk);
    txn_begin = 0;

    // Simulation artificielle d'un journal plein.
    dut.log_count = 5'd16;

    cmd = 8'h01;
    key = 32'h12345678;
    value_in = 16'h00AA;
    start = 1;

    @(negedge clk);
    start = 0;

    @(posedge done);
    #1;

    $display("Journal overflow = %b", txn_journal_overflow);
    $display("KVS error        = %b", error);
    $display("KVS done         = %b", done);
    $display("Writes logged    = %0d", dut.log_count);

    if (txn_journal_overflow === 1'b1 &&
        error === 1'b0)
        $display("BUG CONFIRMED: insertion annoncee reussie malgre journal plein");
    else if (txn_journal_overflow === 1'b1 &&
             error === 1'b1)
        $display("PASS: overflow signale comme erreur KVS");
    else
        $display("CHECK: comportement inattendu, analyser les signaux");

    $finish;
end

endmodule
