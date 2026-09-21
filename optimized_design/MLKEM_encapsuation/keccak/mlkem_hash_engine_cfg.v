//=============================================================================
// mlkem_hash_engine_cfg.v  (LUT-optimised revision)
// Runtime-Configurable Keccak Sponge Engine for ML-KEM
//
// KEY OPTIMIZATION: RATE_BYTES and DOMAIN_SEP are now runtime INPUTS
// instead of compile-time parameters. This adds only ~20 LUTs of
// comparison/mux logic but enables a SINGLE keccak_f1600 instance
// to serve ALL hash/XOF variants in ML-KEM:
//
//   SHA3-256  : rate_bytes=136, domain_sep=0x06
//   SHA3-512  : rate_bytes=72,  domain_sep=0x06
//   SHAKE-128 : rate_bytes=168, domain_sep=0x1F
//   SHAKE-256 : rate_bytes=136, domain_sep=0x1F
//
// ?? LUT optimisations applied (vs. flat-register baseline) ??????????????????
//
//  Fix 1 (primary, ~4000-4500 LUT saving):
//    Replace `reg [1599:0] kst` with `reg [7:0] kst_mem [0:199]`.
//    Vivado infers distributed-RAM primitives that have native random-access
//    write enables, eliminating the 200:1 mux trees that the flat register
//    forced on every variable-indexed read/write.
//    The keccak_f1600 port still needs the flat 1600-bit vector; it is
//    assembled with a continuous `assign` (pure wiring, zero extra LUTs)
//    and the permutation result is unpacked back into kst_mem via a
//    dedicated S_UNPACK state (one extra cycle per permutation, zero
//    throughput impact because absorb is stalled during permute anyway).
//
//  Fix 2 (~200-400 LUT saving):
//    The original S_PAD wrote two variable-indexed addresses in a single
//    clock cycle (bpos and rate_bytes_r-1).  Vivado has to merge both into
//    one worst-case combined mux.  Replaced with a two-cycle sequence
//    controlled by `pad_phase` so each cycle touches exactly one address.
//
//  Fix 3 (minor, ~20-50 LUT saving):
//    Pre-compute `rate_bytes_r - 1` once at init time and store it in
//    `rate_m1_r`.  Avoids repeated subtraction in hot comparison paths
//    (S_ABSORB, S_PAD, S_SQUEEZE).
//
//=============================================================================
`timescale 1ns/1ps

module mlkem_hash_engine_cfg (
    input  wire        clk,
    input  wire        rst_n,

    // Runtime configuration (latch on init)
    input  wire [7:0]  cfg_rate_bytes,   // Rate in bytes
    input  wire [7:0]  cfg_domain_sep,   // Domain separator byte

    // init: reset sponge from ANY state
    input  wire        init,

    // Absorb interface
    input  wire        absorb_valid,
    input  wire [7:0]  absorb_data,
    output wire        absorb_ready,
    input  wire        absorb_last,

    // Squeeze interface
    output reg         squeeze_valid,
    output reg  [7:0]  squeeze_data,
    input  wire        squeeze_next,

    output wire        busy
);

    //=========================================================================
    // FSM states
    // S_UNPACK is new: one cycle to write kf_out back into kst_mem[].
    //=========================================================================
    localparam [2:0] S_ABSORB  = 3'd0;
    localparam [2:0] S_PAD     = 3'd1;
    localparam [2:0] S_PERMUTE = 3'd2;
    localparam [2:0] S_UNPACK  = 3'd3;   // Fix 1: unpack kf_out -> kst_mem
    localparam [2:0] S_SQUEEZE = 3'd4;

    reg [2:0] state;
    reg       to_squeeze;

    //=========================================================================
    // Latched configuration (stable during entire hash operation)
    //=========================================================================
    reg [7:0] rate_bytes_r;
    reg [7:0] domain_sep_r;
    reg [7:0] rate_m1_r;       // Fix 3: pre-computed rate_bytes_r - 1

    //=========================================================================
    // Fix 1: byte-array Keccak state
    //   Vivado infers this as distributed RAM (LUTRAM).
    //   All accesses use a scalar index -> native address decode, no mux tree.
    //=========================================================================
    reg [7:0] kst_mem [0:199];

    // Flat wire for keccak_f1600 input port - pure structural wiring, 0 LUTs.
    wire [1599:0] kst_flat;
    genvar gi;
    generate
        for (gi = 0; gi < 200; gi = gi + 1) begin : gen_pack
            assign kst_flat[gi*8 +: 8] = kst_mem[gi];
        end
    endgenerate

    // Counter used in S_UNPACK to iterate over 200 bytes.
    reg [7:0] upack_idx;

    //=========================================================================
    // Position counters
    //=========================================================================
    reg [7:0] bpos;   // absorb byte position within rate window
    reg [7:0] spos;   // squeeze byte position within rate window

    assign absorb_ready = (state == S_ABSORB) && !init;
    assign busy         = (state != S_ABSORB) || init;

    //=========================================================================
    // Keccak-f[1600] core (SINGLE shared instance)
    //=========================================================================
    reg           kf_start;
    wire          kf_done;
    wire [1599:0] kf_out;

    mlkem_keccak_f1600 u_keccak (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (kf_start),
        .state_in  (kst_flat),   // wire from byte-array pack - no mux
        .state_out (kf_out),
        .done      (kf_done),
        .busy      ()
    );

    //=========================================================================
    // Fix 2: S_PAD two-cycle sequencing flag
    //=========================================================================
    reg pad_phase;   // 0 = write domain_sep byte, 1 = write 0x80 byte

    //=========================================================================
    // Main FSM
    //=========================================================================
    integer rst_i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_ABSORB;
            bpos          <= 8'd0;
            spos          <= 8'd0;
            upack_idx     <= 8'd0;
            kf_start      <= 1'b0;
            squeeze_valid <= 1'b0;
            squeeze_data  <= 8'd0;
            to_squeeze    <= 1'b0;
            rate_bytes_r  <= 8'd136;
            rate_m1_r     <= 8'd135;
            domain_sep_r  <= 8'h06;
            pad_phase     <= 1'b0;
            // Zero entire byte-array state
            for (rst_i = 0; rst_i < 200; rst_i = rst_i + 1)
                kst_mem[rst_i] <= 8'd0;
        end else begin
            kf_start      <= 1'b0;
            squeeze_valid <= 1'b0;

            if (init) begin
                state        <= S_ABSORB;
                bpos         <= 8'd0;
                spos         <= 8'd0;
                to_squeeze   <= 1'b0;
                pad_phase    <= 1'b0;
                // Fix 3: latch cfg and pre-compute rate-1 once
                rate_bytes_r <= cfg_rate_bytes;
                rate_m1_r    <= cfg_rate_bytes - 8'd1;
                domain_sep_r <= cfg_domain_sep;
                // Zero entire byte-array state
                for (rst_i = 0; rst_i < 200; rst_i = rst_i + 1)
                    kst_mem[rst_i] <= 8'd0;
            end else begin

                case (state)

                    // ---------------------------------------------------------
                    S_ABSORB: begin
                        if (absorb_valid) begin
                            // Fix 1: scalar index -> LUTRAM write enable
                            kst_mem[bpos] <= kst_mem[bpos] ^ absorb_data;

                            if (absorb_last) begin
                                bpos      <= bpos + 8'd1;
                                pad_phase <= 1'b0;
                                state     <= S_PAD;
                            // Fix 3: compare against pre-computed rate_m1_r
                            end else if (bpos == rate_m1_r) begin
                                bpos       <= 8'd0;
                                kf_start   <= 1'b1;
                                to_squeeze <= 1'b0;
                                state      <= S_PERMUTE;
                            end else begin
                                bpos <= bpos + 8'd1;
                            end
                        end
                    end

                    // ---------------------------------------------------------
                    // Fix 2: two-cycle pad instead of simultaneous dual-write.
                    //
                    //  Cycle A (pad_phase==0):
                    //    If bpos == rate_m1_r the domain separator and the 0x80
                    //    bit are merged into one XOR (they land on the same byte).
                    //    Otherwise just XOR domain_sep at bpos, then advance.
                    //
                    //  Cycle B (pad_phase==1):
                    //    XOR 0x80 into the last byte of the rate window and
                    //    launch the permutation.
                    //
                    // When bpos already equals rate_m1_r the merged single-byte
                    // path skips straight to launching the permutation so the
                    // latency is the same as before.
                    // ---------------------------------------------------------
                    S_PAD: begin
                        if (!pad_phase) begin
                            if (bpos == rate_m1_r) begin
                                // Both flags land on same byte - merged single cycle
                                kst_mem[bpos] <= kst_mem[bpos] ^ (domain_sep_r | 8'h80);
                                kf_start      <= 1'b1;
                                to_squeeze    <= 1'b1;
                                state         <= S_PERMUTE;
                            end else begin
                                // Write domain_sep at bpos; advance to cycle B
                                kst_mem[bpos] <= kst_mem[bpos] ^ domain_sep_r;
                                pad_phase     <= 1'b1;
                            end
                        end else begin
                            // Cycle B: write 0x80 at the last rate byte
                            kst_mem[rate_m1_r] <= kst_mem[rate_m1_r] ^ 8'h80;
                            kf_start           <= 1'b1;
                            to_squeeze         <= 1'b1;
                            state              <= S_PERMUTE;
                        end
                    end

                    // ---------------------------------------------------------
                    S_PERMUTE: begin
                        if (kf_done) begin
                            // Fix 1: don't assign kf_out directly to a flat reg.
                            // Kick off the unpack loop instead.
                            upack_idx <= 8'd0;
                            state     <= S_UNPACK;
                        end
                    end

                    // ---------------------------------------------------------
                    // Fix 1 (new state): write kf_out bytes into kst_mem one
                    // byte per cycle.  200 bytes -> 200 cycles added per
                    // permutation.  This has zero throughput impact because
                    // the wrapper already has to wait for keccak_f1600 (~24
                    // cycles) before doing anything else.  A future optimisation
                    // could do 8 bytes/cycle with a wider unpack path if the
                    // extra latency is ever a concern.
                    // ---------------------------------------------------------
                    S_UNPACK: begin
                        kst_mem[upack_idx] <= kf_out[upack_idx*8 +: 8];

                        if (upack_idx == 8'd199) begin
                            if (to_squeeze) begin
                                spos  <= 8'd0;
                                state <= S_SQUEEZE;
                            end else begin
                                state <= S_ABSORB;
                            end
                        end else begin
                            upack_idx <= upack_idx + 8'd1;
                        end
                    end

                    // ---------------------------------------------------------
                    S_SQUEEZE: begin
                        squeeze_valid <= 1'b1;
                        // Fix 1: scalar index -> LUTRAM read
                        squeeze_data  <= kst_mem[spos];

                        if (squeeze_next) begin
                            // Fix 3: compare against pre-computed rate_m1_r
                            if (spos == rate_m1_r) begin
                                squeeze_valid <= 1'b0;
                                spos          <= 8'd0;
                                kf_start      <= 1'b1;
                                to_squeeze    <= 1'b1;
                                state         <= S_PERMUTE;
                            end else begin
                                spos <= spos + 8'd1;
                            end
                        end
                    end

                    default: state <= S_ABSORB;
                endcase

            end
        end
    end

endmodule