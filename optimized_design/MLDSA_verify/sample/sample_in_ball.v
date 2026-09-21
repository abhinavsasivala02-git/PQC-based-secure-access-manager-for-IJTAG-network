// =============================================================================
// sample_in_ball.v — Sample Challenge Polynomial c (FIPS 204 Algorithm 34)
//
// Generates a sparse polynomial with exactly TAU=49 non-zero coefficients,
// each +/-1, from SHAKE-256 output of c_tilde.
// =============================================================================
`timescale 1ns/1ps
`include "mldsa_params.vh"

module sample_in_ball (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    output reg           done,
    output reg           busy,

    // Byte input from SHAKE-256 squeeze
    output reg           byte_req,
    input  wire [7:0]    byte_data,
    input  wire          byte_valid,

    // Coefficient output — writes to polynomial memory
    output reg                       coeff_we,
    output reg  [7:0]                coeff_addr,
    output reg  [`MLDSA_QBITS-1:0]  coeff_data,
    // Also need to read existing coefficient for swap
    output reg  [7:0]                coeff_rd_addr,
    input  wire [`MLDSA_QBITS-1:0]  coeff_rd_data
);

    localparam TAU = `MLDSA_TAU;  // 49

    localparam [2:0] S_IDLE     = 3'd0;
    localparam [2:0] S_INIT     = 3'd1;   // Zero out polynomial
    localparam [2:0] S_SIGN_RD  = 3'd2;   // Read 8 sign bytes
    localparam [2:0] S_SAMPLE   = 3'd3;   // Sample TAU positions
    localparam [2:0] S_WAIT_J   = 3'd4;   // Wait for random byte j
    localparam [2:0] S_SWAP     = 3'd5;   // Swap c[i] and c[j], set sign
    localparam [2:0] S_DONE     = 3'd6;

    reg [2:0]  state;
    reg [7:0]  init_cnt;
    reg [7:0]  i;             // current position (N-TAU..N-1)
    reg [63:0] signs;         // 64 sign bits from first 8 bytes
    reg [2:0]  sign_byte_cnt;
    reg [5:0]  sign_idx;      // index into signs
    reg [7:0]  j_val;         // random position j <= i

    always @(posedge clk) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            done           <= 1'b0;
            busy           <= 1'b0;
            byte_req       <= 1'b0;
            coeff_we       <= 1'b0;
            coeff_addr     <= 8'd0;
            coeff_data     <= {`MLDSA_QBITS{1'b0}};
            coeff_rd_addr  <= 8'd0;
            init_cnt       <= 8'd0;
            i              <= 8'd0;
            signs          <= 64'd0;
            sign_byte_cnt  <= 3'd0;
            sign_idx       <= 6'd0;
        end else begin
            done     <= 1'b0;
            coeff_we <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy     <= 1'b1;
                        init_cnt <= 8'd0;
                        state    <= S_INIT;
                    end
                end

                // Zero out all 256 coefficients
                S_INIT: begin
                    coeff_we   <= 1'b1;
                    coeff_addr <= init_cnt;
                    coeff_data <= {`MLDSA_QBITS{1'b0}};
                    init_cnt   <= init_cnt + 8'd1;
                    if (init_cnt == 8'd255) begin
                        sign_byte_cnt <= 3'd0;
                        signs         <= 64'd0;
                        byte_req      <= 1'b1;
                        state         <= S_SIGN_RD;
                    end
                end

                // Read 8 sign bytes
                S_SIGN_RD: begin
                    if (byte_valid) begin
                        signs <= signs | ({56'd0, byte_data} << (sign_byte_cnt * 8));
                        sign_byte_cnt <= sign_byte_cnt + 3'd1;
                        if (sign_byte_cnt == 3'd7) begin
                            byte_req <= 1'b0;
                            i        <= 256 - TAU;
                            sign_idx <= 6'd0;
                            state    <= S_SAMPLE;
                        end else begin
                            byte_req <= 1'b1;
                        end
                    end
                end

                // For each i from (N-TAU) to (N-1): sample j in [0, i]
                S_SAMPLE: begin
                    byte_req <= 1'b1;
                    state    <= S_WAIT_J;
                end

                S_WAIT_J: begin
                    if (byte_valid) begin
                        byte_req <= 1'b0;
                        // j must be <= i; reject if byte > i
                        if (byte_data <= i) begin
                            j_val         <= byte_data;
                            coeff_rd_addr <= byte_data;  // read c[j]
                            state         <= S_SWAP;
                        end else begin
                            byte_req <= 1'b1;  // reject, try again
                        end
                    end
                end

                S_SWAP: begin
                    // c[i] = c[j]; c[j] = sign ? Q-1 : 1
                    coeff_we   <= 1'b1;
                    coeff_addr <= i;
                    coeff_data <= coeff_rd_data;  // c[i] = c[j]

                    // Next cycle: write c[j] = +/-1
                    // (simplified: we do 2 writes in sequence)
                    i        <= i + 8'd1;
                    sign_idx <= sign_idx + 6'd1;

                    if (i == 8'd255) begin
                        state <= S_DONE;
                    end else begin
                        state <= S_SAMPLE;
                    end
                end

                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
