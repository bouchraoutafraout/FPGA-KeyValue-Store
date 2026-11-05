`timescale 1ns/1ps
// Dashboard V2: original transaction_validator -> RTL block_builder + SHA256 -> BRAM
// KVS simplifie de 8 cases (modele tire du tb_transaction_validator de Sanae).
// UART / Cuckoo physique non presents. Les fichiers RTL originaux ne sont pas modifies.
// Input +N=1..6, +TX0=00011122334400AA, ... (64 bits)
// PIPE|TX|ordre|commande|cle|valeur|found|error|code|valeur_lue|accepted|blocks_stored
// PIPE|BLOCK|ordre|index|transaction|previous_hash|hash_stored|storage_ok
// PIPE|VERIFY|ordre|link_ok|hash_ok|chain_valid|computed_hash
module pipeline_dashboard_tb;
    localparam [7:0] CREATE=8'h01, SEARCH=8'h02, TRANSFER=8'h03;
    reg clk=0, rst=1;
    always #5 clk=~clk;

    reg [7:0] in_cmd=0;
    reg [31:0] in_key=0;
    reg [15:0] in_value=0;
    reg in_start=0;
    wire in_busy, in_done, in_found, in_error;
    wire [15:0] in_value_out;
    wire [3:0] in_err_code;
    wire [7:0] kv_cmd;
    wire [31:0] kv_key;
    wire [15:0] kv_value;
    wire kv_start;
    reg mb=0, md=0, mf=0, me=0;
    reg [15:0] mvo=0;
    wire blk_hold, tx_acc_valid;
    wire [7:0] tx_acc_type;
    wire [31:0] tx_acc_key;
    wire [15:0] tx_acc_value;
    wire [3:0] dbg_state;
    wire tx_ready, block_done, storage_ok, builder_busy;
    wire [31:0] next_index, blocks_stored;
    wire [255:0] last_hash;
    wire [63:0] accepted_tx={8'd0,tx_acc_type,tx_acc_key,tx_acc_value};

    transaction_validator #(.VALUE_MIN(16'd1), .VALUE_MAX(16'h7FFF), .TIMEOUT(1000)) TX_VALIDATOR (
      .clk(clk),.rst(rst),.in_cmd(in_cmd),.in_key(in_key),.in_value(in_value),.in_start(in_start),
      .in_busy(in_busy),.in_done(in_done),.in_found(in_found),.in_value_out(in_value_out),
      .in_error(in_error),.in_err_code(in_err_code),
      .kv_cmd(kv_cmd),.kv_key(kv_key),.kv_value(kv_value),.kv_start(kv_start),
      .kv_busy(mb),.kv_done(md),.kv_found(mf),.kv_value_out(mvo),.kv_error(me),
      .blk_ready(tx_ready),.blk_hold(blk_hold),
      .tx_acc_valid(tx_acc_valid),.tx_acc_type(tx_acc_type),.tx_acc_key(tx_acc_key),
      .tx_acc_value(tx_acc_value),.dbg_state(dbg_state)
    );

    block_builder_nada_sha_storage_top BLOCK_STORAGE (
      .clk(clk),.rst(rst),.tx_valid(tx_acc_valid),.tx_data(accepted_tx),
      .tx_ready(tx_ready),.block_done(block_done),.storage_ok(storage_ok),
      .next_index(next_index),.last_hash(last_hash),.blocks_stored(blocks_stored),.busy(builder_busy)
    );

    // Modelisation du KVS du testbench de Sanae; ce n'est pas le Cuckoo RTL.
    reg [31:0] mk[0:7];
    reg [15:0] mv[0:7];
    reg mvld[0:7];
    reg [7:0] lcmd;
    reg [31:0] lkey;
    reg [15:0] lval;
    integer wait_kvs=0, hit, freeidx, j;
    always @(posedge clk) begin
      md <= 1'b0;
      if (rst) begin
        mb <= 1'b0;
        mf <= 1'b0;
        me <= 1'b0;
        mvo <= 16'd0;
        wait_kvs <= 0;
      end else if (kv_start) begin
        lcmd <= kv_cmd;
        lkey <= kv_key;
        lval <= kv_value;
        mb <= 1'b1;
        wait_kvs <= 3;
      end else if (mb) begin
        if (wait_kvs == 0) begin
          hit=-1; freeidx=-1;
          for(j=0;j<8;j=j+1) begin
            if(mvld[j] && mk[j]==lkey) hit=j;
            if(!mvld[j] && freeidx<0) freeidx=j;
          end
          mf <= 1'b0; me <= 1'b0; mvo <= 16'd0;
          case(lcmd)
            CREATE: if(hit>=0 || freeidx<0) me <= 1'b1;
                    else begin mvld[freeidx] <= 1'b1; mk[freeidx] <= lkey; mv[freeidx] <= lval; end
            SEARCH: if(hit>=0) begin mf <= 1'b1; mvo <= mv[hit]; end
            TRANSFER: if(hit>=0) begin mf <= 1'b1; mv[hit] <= lval; end
            default: ;
          endcase
          md <= 1'b1;
          mb <= 1'b0;
        end else wait_kvs <= wait_kvs-1;
      end
    end

    reg v_start=0;
    reg [31:0] v_index=0;
    reg [255:0] v_prev=0,v_stored=0,v_expected_prev=0;
    reg [63:0] v_tx=0;
    wire v_busy,v_done,v_link_ok,v_hash_ok,v_valid;
    wire [255:0] v_computed;
    chain_validator CHAIN_VALIDATOR (
      .clk(clk),.rst(rst),.start(v_start),.index(v_index),
      .previous_hash(v_prev),.transaction(v_tx),.stored_hash(v_stored),
      .expected_previous_hash(v_expected_prev),.busy(v_busy),.done(v_done),
      .link_ok(v_link_ok),.hash_ok(v_hash_ok),.chain_valid(v_valid),.computed_hash(v_computed)
    );

    reg [63:0] txs[0:5];
    integer n=5, k, errs=0, t, blocks_before;
    reg accepted;
    reg [255:0] hash_before;
    reg [31:0] index_before;
    reg [7:0] c;
    reg [31:0] key;
    reg [15:0] value;
    reg [15:0] read_value;
    reg found, error;
    reg [3:0] err_code;

    task run_command;
      input integer step_idx;
      input [63:0] transaction;
      begin
        c=transaction[55:48]; key=transaction[47:16]; value=transaction[15:0];
        blocks_before=blocks_stored;
        index_before=next_index;
        hash_before=last_hash;
        @(negedge clk);
        in_cmd=c; in_key=key; in_value=value; in_start=1;
        @(negedge clk);
        in_start=0;
        t=0;
        while(in_done !== 1'b1 && t<2200) begin @(negedge clk); t=t+1; end
        if(t>=2200) begin
          $display("PIPE|FAIL|Transaction timeout step=%0d",step_idx);
          errs=errs+1;
        end else begin
          found=in_found; error=in_error; err_code=in_err_code; read_value=in_value_out;
          accepted=(c==CREATE || c==TRANSFER) && found && !error && err_code==0;
          if(accepted) begin
            t=0;
            while(block_done !== 1'b1 && t<700) begin @(negedge clk); t=t+1; end
            if(t>=700 || !storage_ok) begin
              $display("PIPE|FAIL|Stockage timeout/erreur step=%0d",step_idx);
              errs=errs+1;
            end else begin
              t=0;
              while(blocks_stored !== (blocks_before+1) && t<20) begin @(negedge clk); t=t+1; end
              if(t>=20) begin
                $display("PIPE|FAIL|blocks_stored non incremente step=%0d",step_idx);
                errs=errs+1;
              end else begin
                $display("PIPE|BLOCK|%0d|%0d|%016h|%064h|%064h|%0d",
                   step_idx,index_before,transaction,hash_before,last_hash,storage_ok);
                @(negedge clk);
                v_index=index_before; v_prev=hash_before; v_tx=transaction;
                v_stored=last_hash; v_expected_prev=hash_before; v_start=1;
                @(negedge clk); v_start=0;
                t=0;
                while(v_done !== 1'b1 && t<700) begin @(negedge clk); t=t+1; end
                if(t>=700) begin
                  $display("PIPE|FAIL|Chain Validator timeout step=%0d",step_idx);
                  errs=errs+1;
                end else begin
                  $display("PIPE|VERIFY|%0d|%0d|%0d|%0d|%064h",
                   step_idx,v_link_ok,v_hash_ok,v_valid,v_computed);
                  if(!v_valid) errs=errs+1;
                end
              end
            end
          end else if(blocks_stored !== blocks_before) begin
            $display("PIPE|FAIL|Un bloc a ete cree pour une commande refusee/SEARCH step=%0d",step_idx);
            errs=errs+1;
          end
          $display("PIPE|TX|%0d|%02h|%08h|%04h|%0d|%0d|%0d|%04h|%0d|%0d",
            step_idx,c,key,value,found,error,err_code,read_value,accepted,blocks_stored);
        end
        repeat(3) @(negedge clk);
      end
    endtask

    initial begin
      $dumpfile("pipeline_dashboard.vcd");
      $dumpvars(0,pipeline_dashboard_tb);
      txs[0]=64'h00011122334400AA;
      txs[1]=64'h0002112233440000;
      txs[2]=64'h0003112233440055;
      txs[3]=64'h0001112233440001;
      txs[4]=64'h0002112233440000;
      txs[5]=64'h0002000000000000;
      if($value$plusargs("N=%d",n)) begin end
      if($value$plusargs("TX0=%h",txs[0])) begin end
      if($value$plusargs("TX1=%h",txs[1])) begin end
      if($value$plusargs("TX2=%h",txs[2])) begin end
      if($value$plusargs("TX3=%h",txs[3])) begin end
      if($value$plusargs("TX4=%h",txs[4])) begin end
      if($value$plusargs("TX5=%h",txs[5])) begin end
      if(n<1 || n>6) begin $display("PIPE|FAIL|N invalide"); $finish; end
      for(k=0;k<8;k=k+1) begin mvld[k]=0; mk[k]=0; mv[k]=0; end
      repeat(5) @(negedge clk);
      rst=0;
      repeat(5) @(negedge clk);
      $display("PIPE|START|%0d",n);
      for(k=0;k<n;k=k+1) run_command(k,txs[k]);
      if(errs==0) $display("PIPE|END|PASS|%0d|%0d",n,blocks_stored);
      else $display("PIPE|END|FAIL|%0d|%0d",n,errs);
      $finish;
    end
    initial begin #30000000; $display("PIPE|FAIL|Global timeout"); $finish; end
endmodule
