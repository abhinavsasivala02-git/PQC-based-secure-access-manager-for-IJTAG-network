//============================================================================
// Polynomial Base Multiplication in NTT Domain - Algorithm 11 of FIPS 203
// Multiplies two NTT-domain polynomials coefficient-pair-wise
//
// In the NTT domain, a 256-coeff polynomial becomes 128 pairs (a0,a1).
// BaseMul for pair i:
//   c0 = a0*b0 + a1*b1*gamma_i
//   c1 = a0*b1 + a1*b0
// where gamma_i = zeta^(2*BitRev7(i)+1) is the pair twiddle factor
// (gamma_i = zetas[64 + i/2] for even i, q - zetas[64 + i/2] for odd i).
//
// All multiplications are plain mod-q (FIPS 203 / Go convention).
//============================================================================
module poly_basemul (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output reg         done,
    output reg         busy,

    // RAM for polynomial A (NTT domain) - read-only
    output reg  [7:0]  a_addr,
    input  wire [11:0] a_rdata,

    // RAM for polynomial B (NTT domain) - read-only
    output reg  [7:0]  b_addr,
    input  wire [11:0] b_rdata,

    // RAM for result C - write-only
    output reg         c_wen,
    output reg  [7:0]  c_addr,
    output reg  [11:0] c_wdata
);

    // FSM states
    localparam S_IDLE   = 4'd0;
    localparam S_RD_A0B0 = 4'd1;
    localparam S_WAIT_AB0 = 4'd2;
    localparam S_WT_A0B0 = 4'd3;
    localparam S_RD_A1B1 = 4'd4;
    localparam S_WAIT_AB1 = 4'd5;
    localparam S_WT_A1B1 = 4'd6;
    localparam S_COMP_C0 = 4'd7;
    localparam S_COMP_C1 = 4'd8;
    localparam S_WR_C0   = 4'd9;
    localparam S_WR_C1   = 4'd10;
    localparam S_NEXT    = 4'd11;
    localparam S_DONE    = 4'd12;

    reg [3:0] state, next_state;

    // Pair index (0..127)
    reg [6:0] pair_idx;

    // Latched coefficient values
    reg signed [15:0] a0, a1, b0, b1;

    // Zeta value for gamma (pair twiddle)
    wire signed [15:0] gamma_val;
    reg  [6:0] gamma_addr;

    // gamma_i = (i odd) ? q - zetas[64 + i/2] : zetas[64 + i/2]
    localparam MLKEM_Q = 13'd3329;
    wire [11:0] gamma_s;
    assign gamma_s = (pair_idx[0]) ? (MLKEM_Q[11:0] - gamma_val[11:0]) : gamma_val[11:0];

    // Plain products (all reduced to [0,q) by fq_reduce)
    (* use_dsp = "no" *) wire signed [31:0] prod_a0b0, prod_a1b1, prod_a0b1, prod_a1b0;
    wire [23:0] prod_a1b1g;
    wire [11:0] m_a0b0, m_a1b1g, m_a0b1, m_a1b0;
    wire [11:0] m_a1b1;

    // Result accumulators
    reg signed [15:0] c0_val, c1_val;

    // Gamma ROM - uses the same zeta ROM with offset addressing
    // gamma base = zetas[64 + i/2] for the basemul twiddles (synchronous BRAM)
    ntt_rom u_gamma_rom (
        .clk  (clk),
        .addr (gamma_addr),
        .zeta (gamma_val)
    );

    // Plain multiplication instances
    assign prod_a0b0 = a0 * b0;
    assign prod_a1b1 = a1 * b1;
    assign prod_a0b1 = a0 * b1;
    assign prod_a1b0 = a1 * b0;
    assign prod_a1b1g = m_a1b1 * gamma_s;

    fq_reduce u_fq_a0b0  (.a(prod_a0b0[24:0]),  .result(m_a0b0));
    fq_reduce u_fq_a1b1  (.a(prod_a1b1[24:0]),  .result(m_a1b1));
    fq_reduce u_fq_a1b1g (.a({1'b0, prod_a1b1g}), .result(m_a1b1g));
    fq_reduce u_fq_a0b1  (.a(prod_a0b1[24:0]),  .result(m_a0b1));
    fq_reduce u_fq_a1b0  (.a(prod_a1b0[24:0]),  .result(m_a1b0));

    // Reduction of the pair sums to [0,q) so 12-bit output never overflows
    wire signed [15:0] c0_sum, c1_sum;
    wire [11:0] c0_red, c1_red;
    assign c0_sum = $signed({1'b0, m_a0b0}) + $signed({1'b0, m_a1b1g});
    assign c1_sum = $signed({1'b0, m_a0b1}) + $signed({1'b0, m_a1b0});
    barrett_reduce u_bar_c0 (.a(c0_sum), .result(c0_red));
    barrett_reduce u_bar_c1 (.a(c1_sum), .result(c1_red));

    // FSM sequential
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // FSM combinational
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:      if (start) next_state = S_RD_A0B0;
            S_RD_A0B0:   next_state = S_WAIT_AB0;
            S_WAIT_AB0:  next_state = S_WT_A0B0;
            S_WT_A0B0:   next_state = S_RD_A1B1;
            S_RD_A1B1:   next_state = S_WAIT_AB1;
            S_WAIT_AB1:  next_state = S_WT_A1B1;
            S_WT_A1B1:   next_state = S_COMP_C0;
            S_COMP_C0:   next_state = S_COMP_C1;
            S_COMP_C1:   next_state = S_WR_C0;
            S_WR_C0:     next_state = S_WR_C1;
            S_WR_C1:     next_state = S_NEXT;
            S_NEXT:      next_state = (pair_idx < 7'd127) ? S_RD_A0B0 : S_DONE;
            S_DONE:      next_state = S_IDLE;
            default:     next_state = S_IDLE;
        endcase
    end

    // Datapath
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done       <= 1'b0;
            busy       <= 1'b0;
            c_wen      <= 1'b0;
            a_addr     <= 8'd0;
            b_addr     <= 8'd0;
            c_addr     <= 8'd0;
            c_wdata    <= 12'd0;
            pair_idx   <= 7'd0;
            a0 <= 16'sd0; a1 <= 16'sd0;
            b0 <= 16'sd0; b1 <= 16'sd0;
            c0_val <= 16'sd0; c1_val <= 16'sd0;
            gamma_addr <= 7'd0;
        end else begin
            c_wen <= 1'b0;
            done  <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy     <= 1'b1;
                        pair_idx <= 7'd0;
                    end
                end

                S_RD_A0B0: begin
                    a_addr <= {pair_idx, 1'b0};  // even index
                    b_addr <= {pair_idx, 1'b0};
                    gamma_addr <= 7'd64 + {1'b0, pair_idx[6:1]};
                end

                S_WT_A0B0: begin
                    a0 <= $signed({4'b0, a_rdata});
                    b0 <= $signed({4'b0, b_rdata});
                end

                S_RD_A1B1: begin
                    a_addr <= {pair_idx, 1'b1};  // odd index
                    b_addr <= {pair_idx, 1'b1};
                end

                S_WT_A1B1: begin
                    a1 <= $signed({4'b0, a_rdata});
                    b1 <= $signed({4'b0, b_rdata});
                end

                S_COMP_C0: begin
                    // c0 = (a0*b0 + gamma*(a1*b1)) mod q, plain
                    c0_val <= $signed({1'b0, c0_red});
                end

                S_COMP_C1: begin
                    // c1 = (a0*b1 + a1*b0) mod q, plain
                    c1_val <= $signed({1'b0, c1_red});
                end

                S_WR_C0: begin
                    c_wen   <= 1'b1;
                    c_addr  <= {pair_idx, 1'b0};
                    c_wdata <= c0_val[11:0];
                end

                S_WR_C1: begin
                    c_wen   <= 1'b1;
                    c_addr  <= {pair_idx, 1'b1};
                    c_wdata <= c1_val[11:0];
                end

                S_NEXT: begin
                    pair_idx <= pair_idx + 7'd1;
                end

                S_DONE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                end
            endcase
        end
    end

endmodule
