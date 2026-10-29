`timescale 1ns/1ps
// Bridge: Nada blockchain_top validator handshake <-> Sanae transaction_validator.
// Transaction format: {reserved[7:0], type[7:0], key[31:0], value[15:0]}.
// The KVS port MUST be connected to an actual KVS for a functional integration.
module transaction_validator_nada_adapter (
  input wire clk, rst,
  input wire validator_start,
  input wire [63:0] validator_tx,
  output wire validator_done,
  output wire validator_accept,
  input wire blk_ready,
  output wire blk_hold,
  output wire [7:0] kv_cmd,
  output wire [31:0] kv_key,
  output wire [15:0] kv_value,
  output wire kv_start,
  input wire kv_busy, kv_done, kv_found, kv_error,
  input wire [15:0] kv_value_out,
  output wire tx_acc_valid,
  output wire [63:0] tx_acc_data,
  output wire [3:0] validation_error_code
);
  wire in_busy, in_done, in_found, in_error;
  wire [15:0] in_value_out;
  wire [3:0] in_err_code;
  wire [7:0] tx_acc_type;
  wire [31:0] tx_acc_key;
  wire [15:0] tx_acc_value;
  wire [3:0] dbg_state;
  reg seen_acc;
  always @(posedge clk) begin
    if (rst) seen_acc <= 1'b0;
    else if (validator_start) seen_acc <= 1'b0;
    else if (tx_acc_valid) seen_acc <= 1'b1;
  end
  assign validator_done = in_done;
  assign validator_accept = in_done && (seen_acc || tx_acc_valid) && !in_error;
  assign tx_acc_data = {8'd0, tx_acc_type, tx_acc_key, tx_acc_value};
  assign validation_error_code = in_err_code;
  transaction_validator SANAe_VALIDATOR (
    .clk(clk), .rst(rst),
    .in_cmd(validator_tx[55:48]), .in_key(validator_tx[47:16]),
    .in_value(validator_tx[15:0]), .in_start(validator_start),
    .in_busy(in_busy), .in_done(in_done), .in_found(in_found),
    .in_value_out(in_value_out), .in_error(in_error), .in_err_code(in_err_code),
    .kv_cmd(kv_cmd), .kv_key(kv_key), .kv_value(kv_value), .kv_start(kv_start),
    .kv_busy(kv_busy), .kv_done(kv_done), .kv_found(kv_found),
    .kv_value_out(kv_value_out), .kv_error(kv_error),
    .blk_ready(blk_ready), .blk_hold(blk_hold),
    .tx_acc_valid(tx_acc_valid), .tx_acc_type(tx_acc_type),
    .tx_acc_key(tx_acc_key), .tx_acc_value(tx_acc_value),
    .dbg_state(dbg_state)
  );
endmodule
