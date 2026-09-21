//============================================================================
// NTT Zeta ROM — Precomputed twiddle factors for ML-KEM NTT
// 128 entries of zeta^{BitRev7(i)} mod q = 3329, PLAIN (NOT Montgomery)
// zeta = 17 (primitive 256th root of unity mod q)
//
// Values match Go crypto/internal/fips140/mlkem zetas[] (FIPS 203 plain
// convention: no R factor). Basemul reads 64..127 for the pair gammas.
//
// SYNTHESIS-SAFE: No initial block. Uses combinational case + registered
// output so Cadence Genus infers BRAM or DFF-bank automatically.
//============================================================================
module ntt_rom (
    input  wire              clk,
    input  wire [6:0]        addr,    // 0..127
    output reg  signed [15:0] zeta
);

    // Combinational ROM — pure case statement, synthesis-safe
    reg signed [15:0] zeta_comb;

    always @(*) begin
        case (addr)
            7'd0: zeta_comb = 16'sd1;
            7'd1: zeta_comb = 16'sd1729;
            7'd2: zeta_comb = 16'sd2580;
            7'd3: zeta_comb = 16'sd3289;
            7'd4: zeta_comb = 16'sd2642;
            7'd5: zeta_comb = 16'sd630;
            7'd6: zeta_comb = 16'sd1897;
            7'd7: zeta_comb = 16'sd848;
            7'd8: zeta_comb = 16'sd1062;
            7'd9: zeta_comb = 16'sd1919;
            7'd10: zeta_comb = 16'sd193;
            7'd11: zeta_comb = 16'sd797;
            7'd12: zeta_comb = 16'sd2786;
            7'd13: zeta_comb = 16'sd3260;
            7'd14: zeta_comb = 16'sd569;
            7'd15: zeta_comb = 16'sd1746;
            7'd16: zeta_comb = 16'sd296;
            7'd17: zeta_comb = 16'sd2447;
            7'd18: zeta_comb = 16'sd1339;
            7'd19: zeta_comb = 16'sd1476;
            7'd20: zeta_comb = 16'sd3046;
            7'd21: zeta_comb = 16'sd56;
            7'd22: zeta_comb = 16'sd2240;
            7'd23: zeta_comb = 16'sd1333;
            7'd24: zeta_comb = 16'sd1426;
            7'd25: zeta_comb = 16'sd2094;
            7'd26: zeta_comb = 16'sd535;
            7'd27: zeta_comb = 16'sd2882;
            7'd28: zeta_comb = 16'sd2393;
            7'd29: zeta_comb = 16'sd2879;
            7'd30: zeta_comb = 16'sd1974;
            7'd31: zeta_comb = 16'sd821;
            7'd32: zeta_comb = 16'sd289;
            7'd33: zeta_comb = 16'sd331;
            7'd34: zeta_comb = 16'sd3253;
            7'd35: zeta_comb = 16'sd1756;
            7'd36: zeta_comb = 16'sd1197;
            7'd37: zeta_comb = 16'sd2304;
            7'd38: zeta_comb = 16'sd2277;
            7'd39: zeta_comb = 16'sd2055;
            7'd40: zeta_comb = 16'sd650;
            7'd41: zeta_comb = 16'sd1977;
            7'd42: zeta_comb = 16'sd2513;
            7'd43: zeta_comb = 16'sd632;
            7'd44: zeta_comb = 16'sd2865;
            7'd45: zeta_comb = 16'sd33;
            7'd46: zeta_comb = 16'sd1320;
            7'd47: zeta_comb = 16'sd1915;
            7'd48: zeta_comb = 16'sd2319;
            7'd49: zeta_comb = 16'sd1435;
            7'd50: zeta_comb = 16'sd807;
            7'd51: zeta_comb = 16'sd452;
            7'd52: zeta_comb = 16'sd1438;
            7'd53: zeta_comb = 16'sd2868;
            7'd54: zeta_comb = 16'sd1534;
            7'd55: zeta_comb = 16'sd2402;
            7'd56: zeta_comb = 16'sd2647;
            7'd57: zeta_comb = 16'sd2617;
            7'd58: zeta_comb = 16'sd1481;
            7'd59: zeta_comb = 16'sd648;
            7'd60: zeta_comb = 16'sd2474;
            7'd61: zeta_comb = 16'sd3110;
            7'd62: zeta_comb = 16'sd1227;
            7'd63: zeta_comb = 16'sd910;
            7'd64: zeta_comb = 16'sd17;
            7'd65: zeta_comb = 16'sd2761;
            7'd66: zeta_comb = 16'sd583;
            7'd67: zeta_comb = 16'sd2649;
            7'd68: zeta_comb = 16'sd1637;
            7'd69: zeta_comb = 16'sd723;
            7'd70: zeta_comb = 16'sd2288;
            7'd71: zeta_comb = 16'sd1100;
            7'd72: zeta_comb = 16'sd1409;
            7'd73: zeta_comb = 16'sd2662;
            7'd74: zeta_comb = 16'sd3281;
            7'd75: zeta_comb = 16'sd233;
            7'd76: zeta_comb = 16'sd756;
            7'd77: zeta_comb = 16'sd2156;
            7'd78: zeta_comb = 16'sd3015;
            7'd79: zeta_comb = 16'sd3050;
            7'd80: zeta_comb = 16'sd1703;
            7'd81: zeta_comb = 16'sd1651;
            7'd82: zeta_comb = 16'sd2789;
            7'd83: zeta_comb = 16'sd1789;
            7'd84: zeta_comb = 16'sd1847;
            7'd85: zeta_comb = 16'sd952;
            7'd86: zeta_comb = 16'sd1461;
            7'd87: zeta_comb = 16'sd2687;
            7'd88: zeta_comb = 16'sd939;
            7'd89: zeta_comb = 16'sd2308;
            7'd90: zeta_comb = 16'sd2437;
            7'd91: zeta_comb = 16'sd2388;
            7'd92: zeta_comb = 16'sd733;
            7'd93: zeta_comb = 16'sd2337;
            7'd94: zeta_comb = 16'sd268;
            7'd95: zeta_comb = 16'sd641;
            7'd96: zeta_comb = 16'sd1584;
            7'd97: zeta_comb = 16'sd2298;
            7'd98: zeta_comb = 16'sd2037;
            7'd99: zeta_comb = 16'sd3220;
            7'd100: zeta_comb = 16'sd375;
            7'd101: zeta_comb = 16'sd2549;
            7'd102: zeta_comb = 16'sd2090;
            7'd103: zeta_comb = 16'sd1645;
            7'd104: zeta_comb = 16'sd1063;
            7'd105: zeta_comb = 16'sd319;
            7'd106: zeta_comb = 16'sd2773;
            7'd107: zeta_comb = 16'sd757;
            7'd108: zeta_comb = 16'sd2099;
            7'd109: zeta_comb = 16'sd561;
            7'd110: zeta_comb = 16'sd2466;
            7'd111: zeta_comb = 16'sd2594;
            7'd112: zeta_comb = 16'sd2804;
            7'd113: zeta_comb = 16'sd1092;
            7'd114: zeta_comb = 16'sd403;
            7'd115: zeta_comb = 16'sd1026;
            7'd116: zeta_comb = 16'sd1143;
            7'd117: zeta_comb = 16'sd2150;
            7'd118: zeta_comb = 16'sd2775;
            7'd119: zeta_comb = 16'sd886;
            7'd120: zeta_comb = 16'sd1722;
            7'd121: zeta_comb = 16'sd1212;
            7'd122: zeta_comb = 16'sd1874;
            7'd123: zeta_comb = 16'sd1029;
            7'd124: zeta_comb = 16'sd2110;
            7'd125: zeta_comb = 16'sd2935;
            7'd126: zeta_comb = 16'sd885;
            7'd127: zeta_comb = 16'sd2154;
            default: zeta_comb = 16'sd0;
        endcase
    end

    // Synchronous registered output — Genus/ASIC infers BRAM or DFF-bank
    always @(posedge clk) begin
        zeta <= zeta_comb;
    end

endmodule