// =============================================================================
// shake_unified.v - Unified SHAKE-128/256 with shared Keccak-f[1600]
//
// AREA-OPTIMIZED: Single active state register.
// The two channels NEVER overlap in ML-DSA (keygen completes before
// sign/verify starts). So we use ONE state register and simply track
// which channel is active. Context save/restore for channel switch.
//
// Channel A = SHAKE-256 (keygen/sign/verify main hash)
// Channel B = SHAKE-128 (keygen ExpandA)
// =============================================================================
`timescale 1ns/1ps

module shake_unified (
    input  wire          clk,
    input  wire          rst_n,

    // ---- Channel A (SHAKE-256) ----
    input  wire          a_init,
    input  wire          a_wr_en,
    input  wire [4:0]    a_wr_lane_idx,
    input  wire [63:0]   a_wr_lane_data,
    input  wire          a_pad_and_permute,
    input  wire          a_permute,
    input  wire [4:0]    a_rd_lane_idx,
    output wire [63:0]   a_rd_lane_data,
    output wire          a_busy,
    output wire          a_rdy,

    // ---- Channel B (SHAKE-128) ----
    input  wire          b_init,
    input  wire          b_wr_en,
    input  wire [4:0]    b_wr_lane_idx,
    input  wire [63:0]   b_wr_lane_data,
    input  wire          b_pad_and_permute,
    input  wire          b_permute,
    input  wire [4:0]    b_rd_lane_idx,
    output wire [63:0]   b_rd_lane_data,
    output wire          b_busy,
    output wire          b_rdy
);

    // --- Shared Keccak-f[1600] core ---
    reg           kf_start;
    wire          kf_busy, kf_done;
    reg  [1599:0] kf_state_in;
    wire [1599:0] kf_state_out;

    keccak_f1600 u_keccak (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (kf_start),
        .state_in  (kf_state_in),
        .state_out (kf_state_out),
        .busy      (kf_busy),
        .done      (kf_done)
    );

    // =========================================================================
    // Single state register + save buffer for inactive channel
    // =========================================================================
    reg [1599:0] state;        // active working state
    reg [1599:0] save_buf;     // inactive channel's saved state
    reg          active_ch;    // 0=A active, 1=B active

    // --- Muxed write port ---
    wire        wr_en       = (active_ch == 1'b0) ? a_wr_en : b_wr_en;
    wire [4:0]  wr_lane_idx = (active_ch == 1'b0) ? a_wr_lane_idx : b_wr_lane_idx;
    wire [63:0] wr_lane_data= (active_ch == 1'b0) ? a_wr_lane_data : b_wr_lane_data;

    // --- Read ports (both read from active state) ---
    assign a_rd_lane_data = state[a_rd_lane_idx * 64 +: 64];
    assign b_rd_lane_data = state[b_rd_lane_idx * 64 +: 64];

    // --- FSM per channel ---
    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_PAD  = 2'd1;
    localparam [1:0] S_WAIT = 2'd2;

    reg [1:0] fsm_a, fsm_b;
    reg       owner;

    // --- Status ---
    assign a_busy = kf_busy | (fsm_a != S_IDLE);
    assign a_rdy  = (fsm_a == S_IDLE) & ~kf_busy & ~a_pad_and_permute & ~a_permute;
    assign b_busy = kf_busy | (fsm_b != S_IDLE);
    assign b_rdy  = (fsm_b == S_IDLE) & ~kf_busy & ~b_pad_and_permute & ~b_permute;

    // --- Channel A FSM ---
    always @(posedge clk) begin
        if (!rst_n) begin
            fsm_a <= S_IDLE;
        end else begin
            case (fsm_a)
                S_IDLE: begin
                    if (a_pad_and_permute && !kf_busy)
                        fsm_a <= S_PAD;
                    else if (a_permute && !kf_busy)
                        fsm_a <= S_WAIT;
                end
                S_PAD:  fsm_a <= S_WAIT;
                S_WAIT: begin
                    if (kf_done && owner == 1'b0) fsm_a <= S_IDLE;
                end
                default: fsm_a <= S_IDLE;
            endcase
        end
    end

    // --- Channel B FSM ---
    always @(posedge clk) begin
        if (!rst_n) begin
            fsm_b <= S_IDLE;
        end else begin
            case (fsm_b)
                S_IDLE: begin
                    if (b_pad_and_permute && !kf_busy)
                        fsm_b <= S_PAD;
                    else if (b_permute && !kf_busy)
                        fsm_b <= S_WAIT;
                end
                S_PAD:  fsm_b <= S_WAIT;
                S_WAIT: begin
                    if (kf_done && owner == 1'b1) fsm_b <= S_IDLE;
                end
                default: fsm_b <= S_IDLE;
            endcase
        end
    end

    // --- State register: init, write, swap, keccak done ---
    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= {1600{1'b0}};
            save_buf  <= {1600{1'b0}};
            active_ch <= 1'b0;
        end else begin
            // --- Channel switch on init ---
            if (a_init && active_ch == 1'b1) begin
                save_buf  <= state;
                state     <= {1600{1'b0}};
                active_ch <= 1'b0;
            end
            else if (b_init && active_ch == 1'b0) begin
                save_buf  <= state;
                state     <= {1600{1'b0}};
                active_ch <= 1'b1;
            end
            else if (a_init && active_ch == 1'b0) begin
                state <= {1600{1'b0}};
            end
            else if (b_init && active_ch == 1'b1) begin
                state <= {1600{1'b0}};
            end

            // --- XOR-write into active state ---
            if (wr_en && !kf_busy)
                state[wr_lane_idx*64 +: 64] <=
                    state[wr_lane_idx*64 +: 64] ^ wr_lane_data;

            // --- Keccak done: capture result ---
            if (kf_done)
                state <= kf_state_out;
        end
    end

    // --- Shared Keccak arbiter ---
    always @(posedge clk) begin
        if (!rst_n) begin
            kf_start    <= 1'b0;
            kf_state_in <= {1600{1'b0}};
            owner       <= 1'b0;
        end else begin
            kf_start <= 1'b0;

            if (!kf_busy) begin
                if (fsm_a == S_PAD || (a_permute && fsm_a == S_IDLE)) begin
                    kf_start    <= 1'b1;
                    kf_state_in <= state;
                    owner       <= 1'b0;
                end
                else if (fsm_b == S_PAD || (b_permute && fsm_b == S_IDLE)) begin
                    kf_start    <= 1'b1;
                    kf_state_in <= state;
                    owner       <= 1'b1;
                end
            end
        end
    end

endmodule
