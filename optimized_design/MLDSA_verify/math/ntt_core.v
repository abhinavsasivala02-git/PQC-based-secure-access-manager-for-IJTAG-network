// =============================================================================
// ntt_core.v — Iterative in-place NTT / INTT for FIPS 204 ML-DSA
//
// Forward NTT  (intt_mode=0): Cooley-Tukey DIT, 8 stages, len 128->1
// Inverse INTT (intt_mode=1): Gentleman-Sande DIF, 8 stages, len 1->128
//                              + final scaling by N^{-1} (Montgomery form)
//
// Performance: ~6400 clock cycles per NTT @ 100 MHz = ~64 us
// Memory: poly_ram_tdp (256 x 23-bit) for in-place computation
// Reset: synchronous active-low
// =============================================================================
`timescale 1ns/1ps
`include "mldsa_params.vh"

module ntt_core (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      start,
    input  wire                      intt_mode,
    output reg                       busy,
    output reg                       done,

    // External coefficient load/read bus (when not busy)
    input  wire                      ext_we,
    input  wire [7:0]                ext_addr,
    input  wire [`MLDSA_QBITS-1:0]  ext_din,
    output wire [`MLDSA_QBITS-1:0]  ext_dout
);

    // =========================================================================
    // State encoding
    // =========================================================================
    localparam [3:0] S_IDLE     = 4'd0;
    localparam [3:0] S_INIT     = 4'd1;
    localparam [3:0] S_BLK_INIT = 4'd2;
    localparam [3:0] S_READ     = 4'd3;
    localparam [3:0] S_WAIT     = 4'd4;
    localparam [3:0] S_BF0      = 4'd5;
    localparam [3:0] S_BF1      = 4'd6;
    localparam [3:0] S_BF2      = 4'd7;
    localparam [3:0] S_BF3      = 4'd8;
    localparam [3:0] S_WRITE    = 4'd9;
    localparam [3:0] S_SCALE    = 4'd10;
    localparam [3:0] S_SCALE_W  = 4'd11;
    localparam [3:0] S_DONE     = 4'd12;
    localparam [3:0] S_ZETA_WAIT = 4'd13; // Wait for BRAM zeta read latency

    reg [3:0] state;

    // =========================================================================
    // Counters
    // =========================================================================
    reg [2:0] stage;
    reg [7:0] blk_start;
    reg [7:0] len;
    reg [6:0] j_cnt;
    reg [7:0] k_idx;

    // =========================================================================
    // Butterfly unit signals
    // =========================================================================
    reg                       bf_vld_in;
    wire                      bf_vld_out;
    reg  [`MLDSA_QBITS-1:0]  bf_a_in, bf_b_in, bf_zeta;
    wire [`MLDSA_QBITS-1:0]  bf_a_out, bf_b_out;

    // Write-back address pipeline (5-deep)
    reg [7:0] wa_dly_0, wa_dly_1, wa_dly_2, wa_dly_3, wa_dly_4;
    reg [7:0] wb_dly_0, wb_dly_1, wb_dly_2, wb_dly_3, wb_dly_4;

    // =========================================================================
    // SRAM signals — FSM-driven and external-muxed
    // =========================================================================
    reg                       fsm_wea, fsm_web;
    reg  [7:0]                fsm_addra, fsm_addrb;
    reg  [`MLDSA_QBITS-1:0]  fsm_dina, fsm_dinb;

    wire                      sram_wea, sram_web;
    wire [7:0]                sram_addra, sram_addrb;
    wire [`MLDSA_QBITS-1:0]  sram_dina, sram_dinb;
    wire [`MLDSA_QBITS-1:0]  sram_douta, sram_doutb;

    // External / Internal mux
    assign sram_wea   = busy ? fsm_wea   : ext_we;
    assign sram_addra = busy ? fsm_addra : ext_addr;
    assign sram_dina  = busy ? fsm_dina  : ext_din;
    assign sram_web   = busy ? fsm_web   : 1'b0;
    assign sram_addrb = busy ? fsm_addrb : 8'd0;
    assign sram_dinb  = busy ? fsm_dinb  : {`MLDSA_QBITS{1'b0}};
    assign ext_dout   = busy ? {`MLDSA_QBITS{1'b0}} : sram_douta;

    // =========================================================================
    // SRAM instance
    // =========================================================================
    poly_ram_tdp #(.DEPTH(256), .WIDTH(`MLDSA_QBITS)) u_ram (
        .clk   (clk),
        .wea   (sram_wea),   .addra (sram_addra), .dina (sram_dina),  .douta (sram_douta),
        .web   (sram_web),   .addrb (sram_addrb), .dinb (sram_dinb),  .doutb (sram_doutb)
    );

    // =========================================================================
    // Butterfly unit
    // =========================================================================
    butterfly_unit u_bf (
        .clk       (clk),
        .rst_n     (rst_n),
        .vld_in    (bf_vld_in),
        .intt_mode (intt_mode),
        .a         (bf_a_in),
        .b         (bf_b_in),
        .zeta_mont (bf_zeta),
        .a_out     (bf_a_out),
        .b_out     (bf_b_out),
        .vld_out   (bf_vld_out)
    );

    // =========================================================================
    // Zeta ROM (synchronous BRAM)
    // =========================================================================
    wire [22:0] rom_data;
    zeta_rom u_zeta_rom (
        .clk  (clk),
        .addr (k_idx),
        .data (rom_data)
    );

    // =========================================================================
    // INTT final scaling multiplier
    // =========================================================================
    reg  [7:0]                sc_idx;
    reg                       sc_vld_in;
    wire                      sc_vld_out;
    wire [`MLDSA_QBITS-1:0]  sc_result;
    reg  [`MLDSA_QBITS-1:0]  sc_coeff;

    montgomery_mult u_sc_mont (
        .clk     (clk),
        .rst_n   (rst_n),
        .vld_in  (sc_vld_in),
        .a       (`MLDSA_NINV_MONT),
        .b       (sc_coeff),
        .result  (sc_result),
        .vld_out (sc_vld_out)
    );

    // =========================================================================
    // Write-address pipeline
    // =========================================================================
    always @(posedge clk) begin
        wa_dly_0 <= fsm_addra;
        wa_dly_1 <= wa_dly_0;
        wa_dly_2 <= wa_dly_1;
        wa_dly_3 <= wa_dly_2;
        wa_dly_4 <= wa_dly_3;
        wb_dly_0 <= fsm_addrb;
        wb_dly_1 <= wb_dly_0;
        wb_dly_2 <= wb_dly_1;
        wb_dly_3 <= wb_dly_2;
        wb_dly_4 <= wb_dly_3;
    end

    // =========================================================================
    // Address helpers
    // =========================================================================
    wire [7:0] addr_j, addr_jlen;
    assign addr_j    = blk_start + {1'b0, j_cnt};
    assign addr_jlen = blk_start + {1'b0, j_cnt} + len;

    // =========================================================================
    // Main FSM
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            busy      <= 1'b0;
            done      <= 1'b0;
            stage     <= 3'd0;
            blk_start <= 8'd0;
            len       <= 7'd0;
            j_cnt     <= 7'd0;
            k_idx     <= 8'd0;
            bf_vld_in <= 1'b0;
            bf_a_in   <= {`MLDSA_QBITS{1'b0}};
            bf_b_in   <= {`MLDSA_QBITS{1'b0}};
            bf_zeta   <= {`MLDSA_QBITS{1'b0}};
            sc_vld_in <= 1'b0;
            sc_idx    <= 8'd0;
            sc_coeff  <= {`MLDSA_QBITS{1'b0}};
            fsm_wea   <= 1'b0;
            fsm_web   <= 1'b0;
            fsm_addra <= 8'd0;
            fsm_addrb <= 8'd0;
            fsm_dina  <= {`MLDSA_QBITS{1'b0}};
            fsm_dinb  <= {`MLDSA_QBITS{1'b0}};
        end else begin
            done      <= 1'b0;
            bf_vld_in <= 1'b0;
            sc_vld_in <= 1'b0;

            case (state)

                S_IDLE: begin
                    busy <= 1'b0;
                    fsm_wea <= 1'b0;
                    fsm_web <= 1'b0;
                    if (start) begin
                        busy  <= 1'b1;
                        state <= S_INIT;
                    end
                end

                S_INIT: begin
                    stage     <= 3'd0;
                    k_idx     <= 8'd1;
                    len       <= intt_mode ? 8'd1 : 8'd128;
                    blk_start <= 8'd0;
                    j_cnt     <= 7'd0;
                    state     <= S_ZETA_WAIT;  // Wait for BRAM to output zeta[1]
                end

                S_ZETA_WAIT: begin
                    // 1-cycle wait for BRAM zeta ROM read latency
                    state <= S_BLK_INIT;
                end

                S_BLK_INIT: begin
                    // Latch zeta for this block (BRAM data now valid)
                    if (intt_mode)
                        bf_zeta <= `MLDSA_Q - rom_data;
                    else
                        bf_zeta <= rom_data;
                    j_cnt <= 7'd0;
                    state <= S_READ;
                end

                S_READ: begin
                    fsm_wea   <= 1'b0;
                    fsm_addra <= addr_j;
                    fsm_web   <= 1'b0;
                    fsm_addrb <= addr_jlen;
                    state     <= S_WAIT;
                end

                S_WAIT: begin
                    bf_a_in   <= sram_douta;
                    bf_b_in   <= sram_doutb;
                    bf_vld_in <= 1'b1;
                    state     <= S_BF0;
                end

                S_BF0: state <= S_BF1;
                S_BF1: state <= S_BF2;
                S_BF2: state <= S_BF3;

                S_BF3: begin
                    if (bf_vld_out) begin
                        fsm_wea   <= 1'b1;
                        fsm_addra <= wa_dly_3;
                        fsm_dina  <= bf_a_out;
                        fsm_web   <= 1'b1;
                        fsm_addrb <= wb_dly_3;
                        fsm_dinb  <= bf_b_out;
                        state     <= S_WRITE;
                    end
                end

                S_WRITE: begin
                    fsm_wea <= 1'b0;
                    fsm_web <= 1'b0;

                    if (j_cnt < len - 7'd1) begin
                        j_cnt <= j_cnt + 7'd1;
                        state <= S_READ;
                    end else begin
                        k_idx     <= k_idx + 8'd1;
                        blk_start <= blk_start + {len, 1'b0};

                        if ({1'b0, blk_start} + {len, 1'b0} < 9'd256) begin
                            j_cnt <= 7'd0;
                            state <= S_ZETA_WAIT;  // Wait for BRAM read
                        end else begin
                            if (stage == 3'd7) begin
                                if (intt_mode) begin
                                    sc_idx <= 8'd0;
                                    state  <= S_SCALE;
                                end else begin
                                    state <= S_DONE;
                                end
                            end else begin
                                stage     <= stage + 3'd1;
                                blk_start <= 8'd0;
                                if (intt_mode)
                                    len <= {len[6:0], 1'b0};  // *2
                                else
                                    len <= {1'b0, len[7:1]};  // /2
                                j_cnt <= 7'd0;
                                state <= S_ZETA_WAIT;  // Wait for BRAM read
                            end
                        end
                    end
                end

                S_SCALE: begin
                    fsm_wea   <= 1'b0;
                    fsm_addra <= sc_idx;
                    sc_coeff  <= sram_douta;
                    sc_vld_in <= 1'b1;
                    sc_idx    <= sc_idx + 8'd1;
                    state     <= S_SCALE_W;
                end

                S_SCALE_W: begin
                    if (sc_vld_out) begin
                        fsm_wea   <= 1'b1;
                        fsm_addra <= sc_idx - 8'd5;
                        fsm_dina  <= sc_result;
                        if (sc_idx == 8'd0) begin
                            state <= S_DONE;
                        end else begin
                            fsm_addra <= sc_idx;
                            sc_coeff  <= sram_douta;
                            sc_vld_in <= 1'b1;
                            sc_idx    <= sc_idx + 8'd1;
                        end
                    end
                end

                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    fsm_wea <= 1'b0;
                    fsm_web <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
