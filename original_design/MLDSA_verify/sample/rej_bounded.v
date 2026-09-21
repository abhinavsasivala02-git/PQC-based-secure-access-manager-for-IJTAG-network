// =============================================================================
// rej_bounded.v — Rejection Sampling for Bounded Coefficients (eta)
//
// FIPS 204 Algorithm 31 (RejBoundedPoly / CoeffFromHalfByte)
// For ML-DSA-65: eta = 4, reads nibbles from SHAKE-256 output.
// If both nibbles of a byte are <= 2*eta, accept as coeff = eta - nibble.
// Produces 256 coefficients in [-eta, eta] stored as [0, Q-1].
// =============================================================================
`timescale 1ns/1ps
`include "mldsa_params.vh"

module rej_bounded (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    output reg           done,
    output reg           busy,

    // Byte input stream (from SHAKE-256 squeeze)
    output reg           byte_req,
    input  wire [7:0]    byte_data,
    input  wire          byte_valid,

    // Coefficient output
    output reg                       coeff_we,
    output reg  [7:0]                coeff_addr,
    output reg  [`MLDSA_QBITS-1:0]  coeff_data
);

    localparam ETA     = `MLDSA_ETA;        // 4 for ML-DSA-65
    localparam ETA2    = 2 * ETA;           // 8

    localparam [2:0] S_IDLE   = 3'd0;
    localparam [2:0] S_FETCH  = 3'd1;
    localparam [2:0] S_LO     = 3'd2;
    localparam [2:0] S_HI     = 3'd3;
    localparam [2:0] S_DONE   = 3'd4;

    reg [2:0]  state;
    reg [7:0]  cnt;
    reg [7:0]  cur_byte;
    reg [3:0]  lo_nib, hi_nib;

    // Convert nibble to coefficient: eta - nibble
    // Result is in [-eta, eta], stored modulo Q
    function [`MLDSA_QBITS-1:0] nib_to_coeff;
        input [3:0] nib;
        reg signed [31:0] val;
        begin
            val = ETA - nib;
            if (val < 0)
                nib_to_coeff = val + `MLDSA_Q;
            else
                nib_to_coeff = val;
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            done       <= 1'b0;
            busy       <= 1'b0;
            byte_req   <= 1'b0;
            coeff_we   <= 1'b0;
            coeff_addr <= 8'd0;
            coeff_data <= {`MLDSA_QBITS{1'b0}};
            cnt        <= 8'd0;
        end else begin
            done     <= 1'b0;
            coeff_we <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy     <= 1'b1;
                        cnt      <= 8'd0;
                        byte_req <= 1'b1;
                        state    <= S_FETCH;
                    end
                end

                S_FETCH: begin
                    if (byte_valid) begin
                        cur_byte <= byte_data;
                        lo_nib   <= byte_data[3:0];
                        hi_nib   <= byte_data[7:4];
                        byte_req <= 1'b0;
                        state    <= S_LO;
                    end
                end

                S_LO: begin
                    if (lo_nib <= ETA2 && cnt < 8'd255) begin
                        coeff_we   <= 1'b1;
                        coeff_addr <= cnt;
                        coeff_data <= nib_to_coeff(lo_nib);
                        cnt        <= cnt + 8'd1;
                    end
                    state <= S_HI;
                end

                S_HI: begin
                    if (hi_nib <= ETA2 && cnt <= 8'd255) begin
                        coeff_we   <= 1'b1;
                        coeff_addr <= cnt;
                        coeff_data <= nib_to_coeff(hi_nib);
                        cnt        <= cnt + 8'd1;
                    end
                    if (cnt >= 8'd255) begin
                        state <= S_DONE;
                    end else begin
                        byte_req <= 1'b1;
                        state    <= S_FETCH;
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
