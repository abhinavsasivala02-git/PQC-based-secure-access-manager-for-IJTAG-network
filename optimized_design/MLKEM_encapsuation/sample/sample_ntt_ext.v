//============================================================================
// SampleNTT — Algorithm 7 of FIPS 203
// MODIFIED: uses EXTERNAL hash engine interface instead of internal SHAKE-128
// The caller configures the hash engine for SHAKE-128 before starting.
//============================================================================
module sample_ntt_ext (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [255:0] seed,
    input  wire [7:0]  idx_i,
    input  wire [7:0]  idx_j,
    output reg         done,
    output reg         busy,

    // Output polynomial RAM
    output reg         poly_wen,
    output reg  [7:0]  poly_addr,
    output reg  [11:0] poly_wdata,

    // External hash engine interface
    output reg         hash_init,
    output reg         hash_absorb_valid,
    output reg  [7:0]  hash_absorb_data,
    input  wire        hash_absorb_ready,
    output reg         hash_absorb_last,
    input  wire        hash_squeeze_valid,
    input  wire [7:0]  hash_squeeze_data,
    output reg         hash_squeeze_next,
    input  wire        hash_busy
);

    `include "mlkem_params.vh"

    localparam S_IDLE        = 4'd0;
    localparam S_INIT_HASH   = 4'd1;
    localparam S_ABSORB_SEED = 4'd2;
    localparam S_ABSORB_IDX  = 4'd3;
    localparam S_WAIT_PERM   = 4'd4;
    localparam S_SQUEEZE_B0  = 4'd5;
    localparam S_SQUEEZE_B1  = 4'd6;
    localparam S_SQUEEZE_B2  = 4'd7;
    localparam S_CHECK       = 4'd8;
    localparam S_DONE        = 4'd9;
    localparam S_W0A         = 4'd10;   // engine advance wait (n=1 from B0)
    localparam S_W0B         = 4'd11;   // engine data settle wait (n=0)
    localparam S_W1A         = 4'd12;   // engine advance wait (n=1 from B1)
    localparam S_W1B         = 4'd13;   // engine data settle wait (n=0)

    reg [3:0] state;
    reg [5:0] seed_byte_cnt;
    reg [7:0] b0, b1, b2;
    wire [11:0] d1, d2;
    assign d1 = {b1[3:0], b0};
    assign d2 = {b2, b1[7:4]};
    reg [8:0] coeff_cnt;
    reg check_d2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= S_IDLE;
            done               <= 1'b0;
            busy               <= 1'b0;
            poly_wen           <= 1'b0;
            poly_addr          <= 8'd0;
            poly_wdata         <= 12'd0;
            hash_init          <= 1'b0;
            hash_absorb_valid  <= 1'b0;
            hash_absorb_data   <= 8'd0;
            hash_absorb_last   <= 1'b0;
            hash_squeeze_next  <= 1'b0;
            seed_byte_cnt      <= 6'd0;
            b0 <= 8'd0; b1 <= 8'd0; b2 <= 8'd0;
            coeff_cnt          <= 9'd0;
            check_d2           <= 1'b0;
        end else begin
            hash_init          <= 1'b0;
            hash_absorb_valid  <= 1'b0;
            hash_absorb_last   <= 1'b0;
            hash_squeeze_next  <= 1'b0;
            poly_wen           <= 1'b0;
            done               <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy          <= 1'b1;
                        hash_init     <= 1'b1;  // Caller already set cfg_rate/domain
                        seed_byte_cnt <= 6'd0;
                        coeff_cnt     <= 9'd0;
                        state         <= S_INIT_HASH;
                    end
                end

                S_INIT_HASH: begin
                    // Wait one cycle for hash engine to reset
                    state <= S_ABSORB_SEED;
                end

                S_ABSORB_SEED: begin
                    if (hash_absorb_ready) begin
                        hash_absorb_valid <= 1'b1;
                        hash_absorb_data  <= seed[seed_byte_cnt*8 +: 8];
                        if (seed_byte_cnt == 6'd31) begin
                            state         <= S_ABSORB_IDX;
                            seed_byte_cnt <= 6'd0;
                        end else begin
                            seed_byte_cnt <= seed_byte_cnt + 6'd1;
                        end
                    end
                end

                S_ABSORB_IDX: begin
                    if (hash_absorb_ready) begin
                        hash_absorb_valid <= 1'b1;
                        if (seed_byte_cnt == 6'd0) begin
                            hash_absorb_data <= idx_j;
                            seed_byte_cnt    <= 6'd1;
                        end else begin
                            hash_absorb_data <= idx_i;
                            hash_absorb_last <= 1'b1;
                            state            <= S_WAIT_PERM;
                        end
                    end
                end

                S_WAIT_PERM: begin
                    if (hash_squeeze_valid)
                        state <= S_SQUEEZE_B0;
                end

                S_SQUEEZE_B0: begin
                    if (hash_squeeze_valid) begin
                        b0                <= hash_squeeze_data;
                        hash_squeeze_next <= 1'b1;
                        state             <= S_W0A;
                    end
                end

                S_W0A: begin
                    // Engine advances spos on this edge (n=1 from B0); the
                    // squeeze_data register is still the old byte here.
                    state <= S_W0B;
                end

                S_W0B: begin
                    // Fresh byte (kst[spos]) is now presented; sample at B1.
                    state <= S_SQUEEZE_B1;
                end

                S_SQUEEZE_B1: begin
                    if (hash_squeeze_valid) begin
                        b1                <= hash_squeeze_data;
                        hash_squeeze_next <= 1'b1;
                        state             <= S_W1A;
                    end
                end

                S_W1A: begin
                    state <= S_W1B;
                end

                S_W1B: begin
                    state <= S_SQUEEZE_B2;
                end

                S_SQUEEZE_B2: begin
                    if (hash_squeeze_valid) begin
                        b2                <= hash_squeeze_data;
                        hash_squeeze_next <= 1'b1;
                        check_d2          <= 1'b0;
                        state             <= S_CHECK;
                    end
                end

                S_CHECK: begin
                    if (!check_d2) begin
                        if (d1 < MLKEM_Q[11:0] && coeff_cnt < 9'd256) begin
                            poly_wen   <= 1'b1;
                            poly_addr  <= coeff_cnt[7:0];
                            poly_wdata <= d1;
                            coeff_cnt  <= coeff_cnt + 9'd1;
                        end
                        check_d2 <= 1'b1;
                    end else begin
                        if (d2 < MLKEM_Q[11:0] && coeff_cnt < 9'd256) begin
                            poly_wen   <= 1'b1;
                            poly_addr  <= coeff_cnt[7:0];
                            poly_wdata <= d2;
                            coeff_cnt  <= coeff_cnt + 9'd1;
                        end
                        if (coeff_cnt >= 9'd256 || (coeff_cnt == 9'd255 && d2 < MLKEM_Q[11:0]))
                            state <= S_DONE;
                        else
                            state <= S_SQUEEZE_B0;
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
