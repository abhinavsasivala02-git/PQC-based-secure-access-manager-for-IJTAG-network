//============================================================================
// Dual-Port Polynomial Coefficient RAM
// 256 entries × 12 bits per coefficient
// Port A: read/write
// Port B: read-only
// Synchronous read with 1-cycle latency
//============================================================================
module mlkem_poly_ram #(
    parameter DEPTH = 256,
    parameter WIDTH = 12,
    parameter ADDR_W = 8
)(
    input  wire              clk,

    // Port A: Read/Write
    input  wire              a_wen,
    input  wire [ADDR_W-1:0] a_addr,
    input  wire [WIDTH-1:0]  a_wdata,
    output reg  [WIDTH-1:0]  a_rdata,

    // Port B: Read-Only
    input  wire [ADDR_W-1:0] b_addr,
    output reg  [WIDTH-1:0]  b_rdata
);

    // Memory array
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    // Port A: synchronous read/write
    always @(posedge clk) begin
        if (a_wen)
            mem[a_addr] <= a_wdata;
        a_rdata <= mem[a_addr];
    end

    // Port B: synchronous read
    always @(posedge clk) begin
        b_rdata <= mem[b_addr];
    end

endmodule
