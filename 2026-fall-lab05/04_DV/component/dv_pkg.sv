/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    dv_pkg.sv
* Project:      2026 FALL NYCU IC LAB, LAB05
* Module:       design verification package
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

package dv_pkg;

    //=============================================================
    //                          TYPE DEFINE
    //=============================================================

    typedef int unsigned uint;

    // image type of the random transaction
    typedef enum int {
        IMG_NOISE,      // every pixel random, most AC non-zero, longest output
        IMG_SMOOTH,     // gradient + small noise, natural-image-like, small delta_dc
        IMG_SPARSE,     // each block = flat + one random DCT basis pattern, long zero runs -> ZRL
        IMG_EXTREME     // each block 0 or 255, D(0,0) = +/-1024, delta_dc SIZE 8, DC + EOB only
    } img_e;

    //=============================================================
    //                          PARAMETER
    //=============================================================

    localparam uint PIX_NUM = 16384;    // 128 x 128 pixels per image

    localparam uint TIMEOUT = 50000;    // SPEC-3 execution latency limit

    // integer DCT matrix, C_TAB[freq][pos]
    localparam int C_TAB [8][8] = '{
        '{ 181,  181,  181,  181,  181,  181,  181,  181},
        '{ 251,  213,  142,   50,  -50, -142, -213, -251},
        '{ 237,   98,  -98, -237, -237,  -98,   98,  237},
        '{ 213,  -50, -251, -142,  142,  251,   50, -213},
        '{ 181, -181, -181,  181,  181, -181, -181,  181},
        '{ 142, -251,   50,  213, -213,  -50,  251, -142},
        '{  98, -237,  237,  -98,  -98,  237, -237,   98},
        '{  50, -142,  213, -251,  251, -213,  142,  -50}
    };

    // quantization shift, row = v (vertical frequency), column = u (horizontal frequency): S(u, v) = S_TAB[v][u]
    localparam int S_TAB [8][8] = '{
        '{ 4, 3, 3, 4, 5, 5, 6, 6},
        '{ 4, 4, 4, 4, 5, 6, 6, 6},
        '{ 4, 4, 4, 5, 5, 6, 6, 6},
        '{ 4, 4, 4, 5, 6, 6, 6, 6},
        '{ 4, 4, 5, 6, 6, 7, 7, 6},
        '{ 5, 5, 6, 6, 6, 7, 7, 7},
        '{ 6, 6, 6, 6, 7, 7, 7, 7},
        '{ 6, 7, 7, 7, 7, 7, 7, 7}
    };

    // zigzag order, Z[k] = Q(ZZ_U[k], ZZ_V[k])
    localparam int ZZ_U [64] = '{
        0, 1, 0, 0, 1, 2, 3, 2, 1, 0, 0, 1, 2, 3, 4, 5,
        4, 3, 2, 1, 0, 0, 1, 2, 3, 4, 5, 6, 7, 6, 5, 4,
        3, 2, 1, 0, 1, 2, 3, 4, 5, 6, 7, 7, 6, 5, 4, 3,
        2, 3, 4, 5, 6, 7, 7, 6, 5, 4, 5, 6, 7, 7, 6, 7
    };

    localparam int ZZ_V [64] = '{
        0, 0, 1, 2, 1, 0, 0, 1, 2, 3, 4, 3, 2, 1, 0, 0,
        1, 2, 3, 4, 5, 6, 5, 4, 3, 2, 1, 0, 0, 1, 2, 3,
        4, 5, 6, 7, 7, 6, 5, 4, 3, 2, 1, 2, 3, 4, 5, 6,
        7, 7, 6, 5, 4, 3, 4, 5, 6, 7, 7, 6, 5, 6, 7, 7
    };

    //=============================================================
    //                            FUNCTION
    //=============================================================

    // symmetric signed rounding of a / 2^n, halfway away from zero
    function automatic int round_s(int a, int n);
        int m;
        m = (a < 0)? -a : a;
        m = (m + (1 << (n - 1))) >> n;
        return (a < 0)? -m : m;
    endfunction

    // bit length of |a|, 0 for a = 0
    function automatic int get_size(int a);
        return $clog2(((a < 0)? -a : a) + 1);
    endfunction

    // a > 0: binary of a, a < 0: (2^size - 1) + a (ones' complement)
    function automatic bit [15:0] get_amp(int a, int size);
        return (a < 0)? ((2**size) - 1 + a) : a;
    endfunction

    // append the lowest len bits of val to the bitstream, MSB first
    function automatic void put_bits(ref bit bs[$], input bit [15:0] val, input int len);
        for(int i = len - 1; i >= 0; i--) bs.push_back(val[i]);
    endfunction

    // DC luminance Huffman table, from dc_huffman_lut.txt (address = SIZE)
    function automatic void DC_HUFF(input int size, output int len, output bit [15:0] code);

        case(size)
             0: begin len =  2; code = 16'b00; end
             1: begin len =  3; code = 16'b010; end
             2: begin len =  3; code = 16'b011; end
             3: begin len =  3; code = 16'b100; end
             4: begin len =  3; code = 16'b101; end
             5: begin len =  3; code = 16'b110; end
             6: begin len =  4; code = 16'b1110; end
             7: begin len =  5; code = 16'b11110; end
             8: begin len =  6; code = 16'b111110; end
             9: begin len =  7; code = 16'b1111110; end
            10: begin len =  8; code = 16'b11111110; end
            11: begin len =  9; code = 16'b111111110; end
            default: begin
                $display("[SCB] DC_HUFF: invalid SIZE %0d", size);
                $fatal(1);
            end
        endcase

    endfunction

    // AC luminance Huffman table, from ac_huffman_lut.txt (address = {RUN, SIZE})
    function automatic void AC_HUFF(input int run, input int size, output int len, output bit [15:0] code);

        case({run[3:0], size[3:0]})
            8'h00: begin len =  4; code = 16'b1010; end
            8'h01: begin len =  2; code = 16'b00; end
            8'h02: begin len =  2; code = 16'b01; end
            8'h03: begin len =  3; code = 16'b100; end
            8'h04: begin len =  4; code = 16'b1011; end
            8'h05: begin len =  5; code = 16'b11010; end
            8'h06: begin len =  7; code = 16'b1111000; end
            8'h07: begin len =  8; code = 16'b11111000; end
            8'h08: begin len = 10; code = 16'b1111110110; end
            8'h09: begin len = 16; code = 16'b1111111110000010; end
            8'h0A: begin len = 16; code = 16'b1111111110000011; end
            8'h11: begin len =  4; code = 16'b1100; end
            8'h12: begin len =  5; code = 16'b11011; end
            8'h13: begin len =  7; code = 16'b1111001; end
            8'h14: begin len =  9; code = 16'b111110110; end
            8'h15: begin len = 11; code = 16'b11111110110; end
            8'h16: begin len = 16; code = 16'b1111111110000100; end
            8'h17: begin len = 16; code = 16'b1111111110000101; end
            8'h18: begin len = 16; code = 16'b1111111110000110; end
            8'h19: begin len = 16; code = 16'b1111111110000111; end
            8'h1A: begin len = 16; code = 16'b1111111110001000; end
            8'h21: begin len =  5; code = 16'b11100; end
            8'h22: begin len =  8; code = 16'b11111001; end
            8'h23: begin len = 10; code = 16'b1111110111; end
            8'h24: begin len = 12; code = 16'b111111110100; end
            8'h25: begin len = 16; code = 16'b1111111110001001; end
            8'h26: begin len = 16; code = 16'b1111111110001010; end
            8'h27: begin len = 16; code = 16'b1111111110001011; end
            8'h28: begin len = 16; code = 16'b1111111110001100; end
            8'h29: begin len = 16; code = 16'b1111111110001101; end
            8'h2A: begin len = 16; code = 16'b1111111110001110; end
            8'h31: begin len =  6; code = 16'b111010; end
            8'h32: begin len =  9; code = 16'b111110111; end
            8'h33: begin len = 12; code = 16'b111111110101; end
            8'h34: begin len = 16; code = 16'b1111111110001111; end
            8'h35: begin len = 16; code = 16'b1111111110010000; end
            8'h36: begin len = 16; code = 16'b1111111110010001; end
            8'h37: begin len = 16; code = 16'b1111111110010010; end
            8'h38: begin len = 16; code = 16'b1111111110010011; end
            8'h39: begin len = 16; code = 16'b1111111110010100; end
            8'h3A: begin len = 16; code = 16'b1111111110010101; end
            8'h41: begin len =  6; code = 16'b111011; end
            8'h42: begin len = 10; code = 16'b1111111000; end
            8'h43: begin len = 16; code = 16'b1111111110010110; end
            8'h44: begin len = 16; code = 16'b1111111110010111; end
            8'h45: begin len = 16; code = 16'b1111111110011000; end
            8'h46: begin len = 16; code = 16'b1111111110011001; end
            8'h47: begin len = 16; code = 16'b1111111110011010; end
            8'h48: begin len = 16; code = 16'b1111111110011011; end
            8'h49: begin len = 16; code = 16'b1111111110011100; end
            8'h4A: begin len = 16; code = 16'b1111111110011101; end
            8'h51: begin len =  7; code = 16'b1111010; end
            8'h52: begin len = 11; code = 16'b11111110111; end
            8'h53: begin len = 16; code = 16'b1111111110011110; end
            8'h54: begin len = 16; code = 16'b1111111110011111; end
            8'h55: begin len = 16; code = 16'b1111111110100000; end
            8'h56: begin len = 16; code = 16'b1111111110100001; end
            8'h57: begin len = 16; code = 16'b1111111110100010; end
            8'h58: begin len = 16; code = 16'b1111111110100011; end
            8'h59: begin len = 16; code = 16'b1111111110100100; end
            8'h5A: begin len = 16; code = 16'b1111111110100101; end
            8'h61: begin len =  7; code = 16'b1111011; end
            8'h62: begin len = 12; code = 16'b111111110110; end
            8'h63: begin len = 16; code = 16'b1111111110100110; end
            8'h64: begin len = 16; code = 16'b1111111110100111; end
            8'h65: begin len = 16; code = 16'b1111111110101000; end
            8'h66: begin len = 16; code = 16'b1111111110101001; end
            8'h67: begin len = 16; code = 16'b1111111110101010; end
            8'h68: begin len = 16; code = 16'b1111111110101011; end
            8'h69: begin len = 16; code = 16'b1111111110101100; end
            8'h6A: begin len = 16; code = 16'b1111111110101101; end
            8'h71: begin len =  8; code = 16'b11111010; end
            8'h72: begin len = 12; code = 16'b111111110111; end
            8'h73: begin len = 16; code = 16'b1111111110101110; end
            8'h74: begin len = 16; code = 16'b1111111110101111; end
            8'h75: begin len = 16; code = 16'b1111111110110000; end
            8'h76: begin len = 16; code = 16'b1111111110110001; end
            8'h77: begin len = 16; code = 16'b1111111110110010; end
            8'h78: begin len = 16; code = 16'b1111111110110011; end
            8'h79: begin len = 16; code = 16'b1111111110110100; end
            8'h7A: begin len = 16; code = 16'b1111111110110101; end
            8'h81: begin len =  9; code = 16'b111111000; end
            8'h82: begin len = 15; code = 16'b111111111000000; end
            8'h83: begin len = 16; code = 16'b1111111110110110; end
            8'h84: begin len = 16; code = 16'b1111111110110111; end
            8'h85: begin len = 16; code = 16'b1111111110111000; end
            8'h86: begin len = 16; code = 16'b1111111110111001; end
            8'h87: begin len = 16; code = 16'b1111111110111010; end
            8'h88: begin len = 16; code = 16'b1111111110111011; end
            8'h89: begin len = 16; code = 16'b1111111110111100; end
            8'h8A: begin len = 16; code = 16'b1111111110111101; end
            8'h91: begin len =  9; code = 16'b111111001; end
            8'h92: begin len = 16; code = 16'b1111111110111110; end
            8'h93: begin len = 16; code = 16'b1111111110111111; end
            8'h94: begin len = 16; code = 16'b1111111111000000; end
            8'h95: begin len = 16; code = 16'b1111111111000001; end
            8'h96: begin len = 16; code = 16'b1111111111000010; end
            8'h97: begin len = 16; code = 16'b1111111111000011; end
            8'h98: begin len = 16; code = 16'b1111111111000100; end
            8'h99: begin len = 16; code = 16'b1111111111000101; end
            8'h9A: begin len = 16; code = 16'b1111111111000110; end
            8'hA1: begin len =  9; code = 16'b111111010; end
            8'hA2: begin len = 16; code = 16'b1111111111000111; end
            8'hA3: begin len = 16; code = 16'b1111111111001000; end
            8'hA4: begin len = 16; code = 16'b1111111111001001; end
            8'hA5: begin len = 16; code = 16'b1111111111001010; end
            8'hA6: begin len = 16; code = 16'b1111111111001011; end
            8'hA7: begin len = 16; code = 16'b1111111111001100; end
            8'hA8: begin len = 16; code = 16'b1111111111001101; end
            8'hA9: begin len = 16; code = 16'b1111111111001110; end
            8'hAA: begin len = 16; code = 16'b1111111111001111; end
            8'hB1: begin len = 10; code = 16'b1111111001; end
            8'hB2: begin len = 16; code = 16'b1111111111010000; end
            8'hB3: begin len = 16; code = 16'b1111111111010001; end
            8'hB4: begin len = 16; code = 16'b1111111111010010; end
            8'hB5: begin len = 16; code = 16'b1111111111010011; end
            8'hB6: begin len = 16; code = 16'b1111111111010100; end
            8'hB7: begin len = 16; code = 16'b1111111111010101; end
            8'hB8: begin len = 16; code = 16'b1111111111010110; end
            8'hB9: begin len = 16; code = 16'b1111111111010111; end
            8'hBA: begin len = 16; code = 16'b1111111111011000; end
            8'hC1: begin len = 10; code = 16'b1111111010; end
            8'hC2: begin len = 16; code = 16'b1111111111011001; end
            8'hC3: begin len = 16; code = 16'b1111111111011010; end
            8'hC4: begin len = 16; code = 16'b1111111111011011; end
            8'hC5: begin len = 16; code = 16'b1111111111011100; end
            8'hC6: begin len = 16; code = 16'b1111111111011101; end
            8'hC7: begin len = 16; code = 16'b1111111111011110; end
            8'hC8: begin len = 16; code = 16'b1111111111011111; end
            8'hC9: begin len = 16; code = 16'b1111111111100000; end
            8'hCA: begin len = 16; code = 16'b1111111111100001; end
            8'hD1: begin len = 11; code = 16'b11111111000; end
            8'hD2: begin len = 16; code = 16'b1111111111100010; end
            8'hD3: begin len = 16; code = 16'b1111111111100011; end
            8'hD4: begin len = 16; code = 16'b1111111111100100; end
            8'hD5: begin len = 16; code = 16'b1111111111100101; end
            8'hD6: begin len = 16; code = 16'b1111111111100110; end
            8'hD7: begin len = 16; code = 16'b1111111111100111; end
            8'hD8: begin len = 16; code = 16'b1111111111101000; end
            8'hD9: begin len = 16; code = 16'b1111111111101001; end
            8'hDA: begin len = 16; code = 16'b1111111111101010; end
            8'hE1: begin len = 16; code = 16'b1111111111101011; end
            8'hE2: begin len = 16; code = 16'b1111111111101100; end
            8'hE3: begin len = 16; code = 16'b1111111111101101; end
            8'hE4: begin len = 16; code = 16'b1111111111101110; end
            8'hE5: begin len = 16; code = 16'b1111111111101111; end
            8'hE6: begin len = 16; code = 16'b1111111111110000; end
            8'hE7: begin len = 16; code = 16'b1111111111110001; end
            8'hE8: begin len = 16; code = 16'b1111111111110010; end
            8'hE9: begin len = 16; code = 16'b1111111111110011; end
            8'hEA: begin len = 16; code = 16'b1111111111110100; end
            8'hF0: begin len = 11; code = 16'b11111111001; end
            8'hF1: begin len = 16; code = 16'b1111111111110101; end
            8'hF2: begin len = 16; code = 16'b1111111111110110; end
            8'hF3: begin len = 16; code = 16'b1111111111110111; end
            8'hF4: begin len = 16; code = 16'b1111111111111000; end
            8'hF5: begin len = 16; code = 16'b1111111111111001; end
            8'hF6: begin len = 16; code = 16'b1111111111111010; end
            8'hF7: begin len = 16; code = 16'b1111111111111011; end
            8'hF8: begin len = 16; code = 16'b1111111111111100; end
            8'hF9: begin len = 16; code = 16'b1111111111111101; end
            8'hFA: begin len = 16; code = 16'b1111111111111110; end
            default: begin
                $display("[SCB] AC_HUFF: invalid RUN %0d / SIZE %0d", run, size);
                $fatal(1);
            end
        endcase

    endfunction

endpackage
