// =============================================================================
// poly_arith.v — Coefficient-wise polynomial arithmetic
//
// Operations (selected by `op`):
//   ADD   (2'b00): out[i] = (a[i] + b[i]) mod Q
//   SUB   (2'b01): out[i] = (a[i] - b[i] + Q) mod Q
//   SCALE (2'b10): out[i] = MONT_MULT(scalar, a[i])
//   NOP   (2'b11): out[i] = a[i]
//
// Processes all 256 coefficients sequentially.
// =============================================================================
`timescale 1ns/1ps
`include "mldsa_params.vh"

module poly_arith (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      start,
    input  wire [1:0]                op,
    input  wire [`MLDSA_QBITS-1:0]  scalar,

    // Operand A memory bus
    output reg  [7:0]                mem_a_addr,
    input  wire [`MLDSA_QBITS-1:0]  mem_a_rdata,

    // Operand B memory bus
    output reg  [7:0]                mem_b_addr,
    input  wire [`MLDSA_QBITS-1:0]  mem_b_rdata,

    // Result memory bus
    output reg                       mem_r_we,
    output reg  [7:0]                mem_r_addr,
    output reg  [`MLDSA_QBITS-1:0]  mem_r_wdata,

    output reg                       busy,
    output reg                       done
);

    localparam [1:0] OP_ADD   = 2'b00;
    localparam [1:0] OP_SUB   = 2'b01;
    localparam [1:0] OP_SCALE = 2'b10;

    // FSM states
    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_PROC = 2'd1;
    localparam [1:0] S_WAIT = 2'd2;
    localparam [1:0] S_DONE = 2'd3;

    reg [1:0] state;
    reg [7:0] idx;
    reg [7:0] wr_idx;

    // Modular adder
    wire [`MLDSA_QBITS-1:0] add_sum, sub_diff;

    mod_add u_add (
        .a    (mem_a_rdata),
        .b    (mem_b_rdata),
        .sum  (add_sum),
        .diff (sub_diff)
    );

    // Montgomery multiplier for SCALE
    reg                       sc_vld_in;
    wire                      sc_vld_out;
    wire [`MLDSA_QBITS-1:0]  sc_result;

    montgomery_mult u_mont (
        .clk     (clk),
        .rst_n   (rst_n),
        .vld_in  (sc_vld_in),
        .a       (scalar),
        .b       (mem_a_rdata),
        .result  (sc_result),
        .vld_out (sc_vld_out)
    );

    // Read address generation
    always @(*) begin
        mem_a_addr = idx;
        mem_b_addr = idx;
    end

    // FSM
    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            busy        <= 1'b0;
            done        <= 1'b0;
            idx         <= 8'd0;
            wr_idx      <= 8'd0;
            mem_r_we    <= 1'b0;
            mem_r_addr  <= 8'd0;
            mem_r_wdata <= {`MLDSA_QBITS{1'b0}};
            sc_vld_in   <= 1'b0;
        end else begin
            done      <= 1'b0;
            mem_r_we  <= 1'b0;
            sc_vld_in <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy   <= 1'b1;
                        idx    <= 8'd0;
                        wr_idx <= 8'd0;
                        state  <= S_PROC;
                    end
                end

                S_PROC: begin
                    idx <= idx + 8'd1;

                    if (op == OP_ADD) begin
                        mem_r_we    <= (idx > 8'd0);
                        mem_r_addr  <= idx - 8'd1;
                        mem_r_wdata <= add_sum;
                    end else if (op == OP_SUB) begin
                        mem_r_we    <= (idx > 8'd0);
                        mem_r_addr  <= idx - 8'd1;
                        mem_r_wdata <= sub_diff;
                    end else if (op == OP_SCALE) begin
                        sc_vld_in <= 1'b1;
                    end

                    if (sc_vld_out && op == OP_SCALE) begin
                        mem_r_we    <= 1'b1;
                        mem_r_addr  <= wr_idx;
                        mem_r_wdata <= sc_result;
                        wr_idx      <= wr_idx + 8'd1;
                    end

                    if (idx == 8'd255) begin
                        state <= S_WAIT;
                        idx   <= 8'd0;
                    end
                end

                S_WAIT: begin
                    if (op == OP_SCALE && sc_vld_out) begin
                        mem_r_we    <= 1'b1;
                        mem_r_addr  <= wr_idx;
                        mem_r_wdata <= sc_result;
                        wr_idx      <= wr_idx + 8'd1;
                    end
                    if (wr_idx == 8'd255) state <= S_DONE;
                    if (op != OP_SCALE)   state <= S_DONE;
                end

                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
