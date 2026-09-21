//============================================================================
// Compress_d - FIPS 203 Section 4.2.1
// Compress_d(x) = round(2^d / q * x) mod 2^d
//
// Implementation: ((x << d) + q/2) / q
// Division by q approximated using reciprocal multiply:
//   result = ((x << d) + (q >> 1)) * RECIPROCAL >> SHIFT
//
// This avoids expensive hardware dividers.
//============================================================================
module compress #(
    parameter D = 10     // Compression bits (1, 4, 5, 10, 11)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output reg         done,
    output reg         busy,

    // Input polynomial RAM - read
    output reg  [7:0]  in_addr,
    input  wire [11:0] in_rdata,

    // Output polynomial RAM - write
    output reg         out_wen,
    output reg  [7:0]  out_addr,
    output reg  [11:0] out_wdata
);

    `include "mlkem_params.vh"

    // FSM
    localparam S_IDLE  = 3'd0;
    localparam S_READ  = 3'd1;
    localparam S_WAIT  = 3'd2;
    localparam S_COMP  = 3'd3;
    localparam S_WRITE = 3'd4;
    localparam S_NEXT  = 3'd5;
    localparam S_DONE  = 3'd6;

    reg [2:0] state;
    reg [8:0] idx;

    // Compression computation
    // Compress_d(x) = round(x * 2^d / q)
    // = floor((x * 2^d + q/2) / q), with q_half = 1664
    wire [23:0] numerator;
    wire [D-1:0] compressed;

    assign numerator = ({12'd0, in_rdata} << D) + 24'd1664;

    // Exact division by q using reciprocal multiply + correction.
    // For q=3329 we use M = floor(2^26 / q) = 20158, so that
    //   q_est = floor(numerator * M / 2^26) <= floor(numerator / q)
    // always (no overshoot). The estimate can be at most one too small, so
    //   rem = numerator - q_est * q  (>= 0)
    // and if rem >= q we increment q_est once. This matches FIPS 203 exactly:
    //   Compress_d(x) = floor((x*2^d + q/2) / q) mod 2^d
    // (The old constant 20159 was larger than ceil(2^26/q), causing +1 errors.)

    wire [49:0] approx_product;
    assign approx_product = numerator * 24'd20158;

    wire [11:0] q_est;
    assign q_est = approx_product[37:26];       // >> 26 (fits in 12 bits)

    wire [23:0] rem;
    assign rem = numerator - (q_est * 12'd3329);

    wire [11:0] q_adj;
    assign q_adj = (rem >= 12'd3329) ? q_est + 12'd1 : q_est;

    assign compressed = q_adj[D-1:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            done      <= 1'b0;
            busy      <= 1'b0;
            out_wen   <= 1'b0;
            in_addr   <= 8'd0;
            out_addr  <= 8'd0;
            out_wdata <= 12'd0;
            idx       <= 9'd0;
        end else begin
            out_wen <= 1'b0;
            done    <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        idx  <= 9'd0;
                        state <= S_READ;
                    end
                end

                S_READ: begin
                    in_addr <= idx[7:0];
                    state   <= S_WAIT;
                end

                S_WAIT: state <= S_COMP;

                S_COMP: state <= S_WRITE;

                S_WRITE: begin
                    out_wen   <= 1'b1;
                    out_addr  <= idx[7:0];
                    out_wdata <= {{(12-D){1'b0}}, compressed};
                    state     <= S_NEXT;
                end

                S_NEXT: begin
                    if (idx == 9'd255) state <= S_DONE;
                    else begin
                        idx   <= idx + 9'd1;
                        state <= S_READ;
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
