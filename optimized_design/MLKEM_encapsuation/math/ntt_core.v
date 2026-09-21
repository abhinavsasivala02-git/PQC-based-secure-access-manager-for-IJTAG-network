//============================================================================
// Unified NTT Core — Forward NTT + Inverse NTT with inline butterfly
// Eliminates separate ntt_butterfly.v module entirely.
//
// mode = 0: Forward NTT (Cooley-Tukey)
// mode = 1: Inverse NTT (Gentleman-Sande) with final f=3303 scaling
// PLAIN arithmetic (FIPS 203 / Go convention, no Montgomery)
//============================================================================
module mlkem_ntt_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        mode,       // 0=forward NTT, 1=inverse NTT
    output reg         done,
    output reg         busy,

    // Polynomial RAM interface - Port A (read/write)
    output reg         ram_wen,
    output reg  [7:0]  ram_addr_a,
    output reg  [11:0] ram_wdata_a,
    input  wire [11:0] ram_rdata_a,

    // Polynomial RAM interface - Port B (read-only)
    output reg  [7:0]  ram_addr_b,
    input  wire [11:0] ram_rdata_b
);

    localparam MLKEM_N      = 9'd256;
    localparam MLKEM_INTT_F = 16'd3303;   // 128^-1 mod q (plain INTT scale)
    localparam MLKEM_Q      = 13'd3329;

    // FSM states
    localparam S_IDLE      = 4'd0;
    localparam S_SETUP     = 4'd1;
    localparam S_READ      = 4'd2;
    localparam S_WAIT      = 4'd3;
    localparam S_BFLY      = 4'd4;
    localparam S_BFLY_WAIT = 4'd5;
    localparam S_WRITE     = 4'd6;
    localparam S_WRITE2    = 4'd7;
    localparam S_NEXT      = 4'd8;
    localparam S_SCALE_RD  = 4'd9;
    localparam S_SCALE_WT  = 4'd10;
    localparam S_SCALE_WB  = 4'd11;
    localparam S_SCALE_NX  = 4'd12;
    localparam S_DONE      = 4'd13;

    reg [3:0] state, next_state;
    reg       mode_reg;

    // Layer and position counters
    reg [2:0]  layer;
    reg [7:0]  j;
    reg [7:0]  start_idx;
    reg [7:0]  len;
    reg [7:0]  k;
    reg [8:0]  scale_idx;

    // Zeta ROM
    wire signed [15:0] zeta_val;

    ntt_rom u_zeta_rom (
        .clk  (clk),
        .addr (k[6:0]),
        .zeta (zeta_val)
    );

    // Address computation
    wire [7:0] addr_lo, addr_hi;
    assign addr_lo = start_idx + j;
    assign addr_hi = start_idx + j + len;

    // ==================================================================
    // Inline Butterfly — CT and GS with plain mod-q reduction
    // ==================================================================
    reg               bfly_valid_in;
    reg  signed [15:0] bfly_a_in, bfly_b_in;
    reg  signed [15:0] bfly_a_out, bfly_b_out;
    reg               bfly_valid_out;

    // --- CT path: t = (zeta * b) mod q; a' = a+t; b' = a-t ---
    (* use_dsp = "no" *) wire signed [31:0] ct_product;
    wire [11:0] ct_red;
    wire signed [15:0] ct_t;
    assign ct_product = zeta_val * bfly_b_in;             // both < q
    fq_reduce u_fq_ct (.a(ct_product[24:0]), .result(ct_red));
    assign ct_t = $signed({1'b0, ct_red});

    // --- GS path: d = b-a+q in [0,2q); t = (zeta*d) mod q; a' = a+b ---
    wire signed [15:0] gs_diff;
    assign gs_diff = bfly_b_in - bfly_a_in;               // (-q, q)
    wire signed [16:0] gs_d;
    assign gs_d = gs_diff + $signed({1'b0, MLKEM_Q[12:0]});
    (* use_dsp = "no" *) wire signed [31:0] gs_product;
    wire [11:0] gs_red;
    assign gs_product = zeta_val * gs_d;                  // < 2q^2 < 2^25
    fq_reduce u_fq_gs (.a(gs_product[24:0]), .result(gs_red));

    // --- Reduction of butterfly add/sub outputs to keep coeffs in [0,q) ---
    wire signed [15:0] ct_a_sum, ct_b_diff, gs_a_sum;
    wire [11:0] ct_a_red, ct_b_red, gs_a_red;

    assign ct_a_sum  = bfly_a_in + ct_t;        // [0,2q)
    assign ct_b_diff = bfly_a_in - ct_t;        // (-q,q)
    assign gs_a_sum  = bfly_a_in + bfly_b_in;   // [0,2q)

    barrett_reduce u_bar_ct_a (.a(ct_a_sum),  .result(ct_a_red));
    barrett_reduce u_bar_gs_a (.a(gs_a_sum),  .result(gs_a_red));

    wire signed [15:0] ct_b_adj;
    assign ct_b_adj = (ct_b_diff < 16'sd0) ? (ct_b_diff + $signed({1'b0, MLKEM_Q[12:0]})) : ct_b_diff;
    assign ct_b_red = ct_b_adj[11:0];

    // Registered butterfly output (1-cycle pipeline)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bfly_a_out     <= 16'sd0;
            bfly_b_out     <= 16'sd0;
            bfly_valid_out <= 1'b0;
        end else begin
            bfly_valid_out <= bfly_valid_in;
            if (bfly_valid_in) begin
                if (mode_reg == 1'b0) begin
                    // Cooley-Tukey (forward), reduced to [0,q)
                    bfly_a_out <= $signed({1'b0, ct_a_red});
                    bfly_b_out <= $signed({1'b0, ct_b_red});
                end else begin
                    // Gentleman-Sande (inverse), reduced to [0,q)
                    bfly_a_out <= $signed({1'b0, gs_a_red});
                    bfly_b_out <= $signed({1'b0, gs_red});
                end
            end
        end
    end

    // --- INTT final scaling by f = 3303 ---
    (* use_dsp = "no" *) wire signed [31:0] scale_product;
    wire [11:0] scale_result;
    assign scale_product = $signed({4'b0, ram_rdata_a}) * $signed(MLKEM_INTT_F);
    fq_reduce u_fq_scale (.a(scale_product[24:0]), .result(scale_result));

    // ==================================================================
    // FSM
    // ==================================================================

    // Sequential
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // Combinational next-state
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:      if (start) next_state = S_SETUP;
            S_SETUP:     next_state = S_READ;
            S_READ:      next_state = S_WAIT;
            S_WAIT:      next_state = S_BFLY;
            S_BFLY:      next_state = S_BFLY_WAIT;
            S_BFLY_WAIT: next_state = S_WRITE;
            S_WRITE:     next_state = S_WRITE2;
            S_WRITE2:    next_state = S_NEXT;
            S_NEXT: begin
                if (j + 1 < len)
                    next_state = S_READ;
                else if (start_idx + (len << 1) < MLKEM_N)
                    next_state = S_READ;
                else if (layer < 3'd6)
                    next_state = S_SETUP;
                else if (mode_reg)
                    next_state = S_SCALE_RD;
                else
                    next_state = S_DONE;
            end
            S_SCALE_RD:  next_state = S_SCALE_WT;
            S_SCALE_WT:  next_state = S_SCALE_WB;
            S_SCALE_WB:  next_state = S_SCALE_NX;
            S_SCALE_NX:  next_state = (scale_idx < 9'd255) ? S_SCALE_RD : S_DONE;
            S_DONE:      next_state = S_IDLE;
            default:     next_state = S_IDLE;
        endcase
    end

    // Datapath
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done          <= 1'b0;
            busy          <= 1'b0;
            ram_wen       <= 1'b0;
            ram_addr_a    <= 8'd0;
            ram_addr_b    <= 8'd0;
            ram_wdata_a   <= 12'd0;
            bfly_valid_in <= 1'b0;
            bfly_a_in     <= 16'sd0;
            bfly_b_in     <= 16'sd0;
            mode_reg      <= 1'b0;
            layer         <= 3'd0;
            j             <= 8'd0;
            start_idx     <= 8'd0;
            len           <= 8'd128;
            k             <= 7'd0;
            scale_idx     <= 9'd0;
        end else begin
            ram_wen       <= 1'b0;
            bfly_valid_in <= 1'b0;
            done          <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy     <= 1'b1;
                        mode_reg <= mode;
                        layer    <= 3'd0;
                        if (mode == 1'b0) begin
                            len <= 8'd128;
                            k   <= 7'd0;
                        end else begin
                            len <= 8'd2;
                            k   <= 8'd128;
                        end
                    end
                end

                S_SETUP: begin
                    start_idx <= 8'd0;
                    j         <= 8'd0;
                    if (mode_reg == 1'b0)
                        k <= k + 7'd1;
                    else
                        k <= k - 7'd1;
                end

                S_READ: begin
                    ram_addr_a <= addr_lo;
                    ram_addr_b <= addr_hi;
                end

                S_WAIT: begin
                    // RAM read latency
                end

                S_BFLY: begin
                    bfly_a_in     <= $signed({4'b0, ram_rdata_a});
                    bfly_b_in     <= $signed({4'b0, ram_rdata_b});
                    bfly_valid_in <= 1'b1;
                end

                S_BFLY_WAIT: begin
                    // Wait for butterfly registered output pipeline
                end

                S_WRITE: begin
                    ram_wen     <= 1'b1;
                    ram_addr_a  <= addr_lo;
                    ram_wdata_a <= bfly_a_out[11:0];
                end

                S_WRITE2: begin
                    ram_wen     <= 1'b1;
                    ram_addr_a  <= addr_hi;
                    ram_wdata_a <= bfly_b_out[11:0];
                end

                S_NEXT: begin
                    if (j + 1 < len) begin
                        j <= j + 8'd1;
                    end else if (start_idx + (len << 1) < MLKEM_N) begin
                        start_idx <= start_idx + (len << 1);
                        j         <= 8'd0;
                        if (mode_reg == 1'b0)
                            k <= k + 7'd1;
                        else
                            k <= k - 7'd1;
                    end else begin
                        layer <= layer + 3'd1;
                        if (mode_reg == 1'b0)
                            len <= len >> 1;
                        else begin
                            len       <= len << 1;
                            scale_idx <= 9'd0;
                        end
                    end
                end

                S_SCALE_RD: ram_addr_a <= scale_idx[7:0];
                S_SCALE_WT: begin /* read latency */ end
                S_SCALE_WB: begin
                    ram_wen     <= 1'b1;
                    ram_addr_a  <= scale_idx[7:0];
                    ram_wdata_a <= scale_result;
                end
                S_SCALE_NX: scale_idx <= scale_idx + 9'd1;

                S_DONE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                end
            endcase
        end
    end

endmodule
