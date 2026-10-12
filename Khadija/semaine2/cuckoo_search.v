module search #(
    parameter KEY_W  = 32,
    parameter VAL_W  = 16,
    parameter ADDR_W = 8
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     start,
    input  wire [KEY_W-1:0]         key,
    output reg                      busy,
    output reg                      done,
    output reg                      found,
    output reg  [VAL_W-1:0]         value,
    output reg                      table_sel,
    output reg  [ADDR_W-1:0]        addr_found,
    output wire [ADDR_W-1:0]        addr1,
    output wire [ADDR_W-1:0]        addr2,
    input  wire [1+KEY_W+VAL_W-1:0] data1,
    input  wire [1+KEY_W+VAL_W-1:0] data2
);

    localparam IDLE    = 2'd0;
    localparam READ    = 2'd1;
    localparam COMPARE = 2'd2;
    localparam DONE    = 2'd3;

    reg [1:0]       state;
    reg [KEY_W-1:0] key_reg;

    wire [31:0] hash_key = key_reg;
    wire [7:0]  hash_index1;
    wire [7:0]  hash_index2;

    hash_function1 u_hash_function1 (.key(hash_key), .index(hash_index1));
    hash_function2 u_hash_function2 (.key(hash_key), .index(hash_index2));

    assign addr1 = hash_index1[ADDR_W-1:0];
    assign addr2 = hash_index2[ADDR_W-1:0];

    wire             valid1 = data1[1+KEY_W+VAL_W-1];
    wire [KEY_W-1:0] key1   = data1[VAL_W +: KEY_W];
    wire [VAL_W-1:0] val1   = data1[VAL_W-1:0];

    wire             valid2 = data2[1+KEY_W+VAL_W-1];
    wire [KEY_W-1:0] key2   = data2[VAL_W +: KEY_W];
    wire [VAL_W-1:0] val2   = data2[VAL_W-1:0];

    wire hit1 = valid1 && (key1 == key_reg);
    wire hit2 = valid2 && (key2 == key_reg);

    always @(posedge clk) begin
        if (rst) begin
            state      <= IDLE;
            key_reg    <= {KEY_W{1'b0}};
            busy       <= 1'b0;
            done       <= 1'b0;
            found      <= 1'b0;
            value      <= {VAL_W{1'b0}};
            table_sel  <= 1'b0;
            addr_found <= {ADDR_W{1'b0}};
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: begin
                    if (start) begin
                        key_reg <= key;
                        busy    <= 1'b1;
                        state   <= READ;
                    end
                end
                READ: begin
                    state <= COMPARE;
                end
                COMPARE: begin
                    if (hit1) begin
                        found      <= 1'b1;
                        value      <= val1;
                        table_sel  <= 1'b0;
                        addr_found <= addr1;
                    end else if (hit2) begin
                        found      <= 1'b1;
                        value      <= val2;
                        table_sel  <= 1'b1;
                        addr_found <= addr2;
                    end else begin
                        found      <= 1'b0;
                        value      <= {VAL_W{1'b0}};
                        table_sel  <= 1'b0;
                        addr_found <= {ADDR_W{1'b0}};
                    end
                    state <= DONE;
                end
                DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule