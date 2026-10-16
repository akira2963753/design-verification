//v33: v30 + no block counters pb / cblk (end of image from fb_fin / fev and a block-255-complete flag)
// Lab05 JPEGLENC (Verilog-2001)
//  SRAM SUMA180_1488X64X1BM1, one port, 64-bit words
//    0..127    line buffer: one block row, word = 8 pixels of one block row segment, in place:
//              raster word k = {yl, bx} of block row r is at rotr7(k, 3r mod 7)
//    128..1487 bitstream words j < 1360 at 128 + j; j >= 1360 at rotr7(j - 1360, 6) (slots of block row 15 already read)
//  port priority: input write > output read > bitstream write > engine read
//  SRAM read data is registered (dout_q, no enable): data of a read granted in cycle t is used in cycle t+2
//  engine reads are scheduled so that the row arrives in P1 and goes straight into x (no row slots)
//  a block of 64 equal pixels skips the DCT: Q(0,0) only (flat shortcut), its line-buffer words are read once

`include "../01_RTL/SUMA180_1488X64X1BM1.v"

module JPEGLENC (
    input            clk,
    input            rst_n,
    input            in_valid,
    input      [7:0] in_data,
    output reg       out_valid,
    output reg [7:0] out_data
);

// ---------------------------------------------------------------------------------------------- helpers
function [6:0] rotr7;
    input [6:0] k;
    input [2:0] n;
    begin
        case (n)
            3'd1:    rotr7 = {k[0],   k[6:1]};
            3'd2:    rotr7 = {k[1:0], k[6:2]};
            3'd3:    rotr7 = {k[2:0], k[6:3]};
            3'd4:    rotr7 = {k[3:0], k[6:4]};
            3'd5:    rotr7 = {k[4:0], k[6:5]};
            3'd6:    rotr7 = {k[5:0], k[6]};
            default: rotr7 = k;
        endcase
    end
endfunction

// 3r mod 7 for block row r
function [2:0] rot_of;
    input [3:0] r;
    begin
        case (r)
            4'd0, 4'd7, 4'd14: rot_of = 3'd0;
            4'd1, 4'd8, 4'd15: rot_of = 3'd3;
            4'd2, 4'd9:        rot_of = 3'd6;
            4'd3, 4'd10:       rot_of = 3'd2;
            4'd4, 4'd11:       rot_of = 3'd5;
            4'd5, 4'd12:       rot_of = 3'd1;
            default:           rot_of = 3'd4;     // 6, 13
        endcase
    end
endfunction

// SRAM address of bitstream word j
function [10:0] bs_addr;
    input [10:0] j;
    reg   [10:0] m;
    begin
        m = j - 11'd1360;
        if (j < 11'd1360) bs_addr = j + 11'd128;
        else              bs_addr = {4'd0, rotr7(m[6:0], 3'd6)};
    end
endfunction

// fused round_s(round_s(A, 18), S): V = Q for A >= 0, Q - 1 for A < 0 (8 bit) (reference form, frs below is used)
function [7:0] fround;
    input [28:0] a;
    input [2:0]  s;
    reg   [13:0] hi, kk, sm, sh;
    reg          sg;
    begin
        sg = a[28];
        hi = {{2{a[28]}}, a[28:17]};
        kk = 14'd1 + (14'd1 << s);
        if (sg) kk = ~kk;
        sm = hi + kk + {13'd0, sg & (|a[16:0])};
        sh = $signed(sm) >>> ({1'b0, s} + 4'd1);
        fround = sh[7:0];
    end
endfunction

// fround with S in 3..7 (lane 0) / 4..7 (lanes 1..3, s4 = S - 4): constant kk, output slice sm[S+8:S+1]
function [7:0] frs;
    input [28:0] a;
    input [2:0]  s;
    reg   [13:0] hi, kk, sm;
    reg          sg;
    begin
        sg = a[28];
        hi = {{2{a[28]}}, a[28:17]};
        case (s)
            3'd3:    kk = 14'd9;
            3'd4:    kk = 14'd17;
            3'd5:    kk = 14'd33;
            3'd6:    kk = 14'd65;
            default: kk = 14'd129;
        endcase
        if (sg) kk = ~kk;
        sm = hi + kk + {13'd0, sg & (|a[16:0])};
        case (s)
            3'd3:    frs = sm[11:4];
            3'd4:    frs = sm[12:5];
            3'd5:    frs = sm[13:6];
            3'd6:    frs = {sm[13], sm[13:7]};
            default: frs = {{2{sm[13]}}, sm[13:8]};
        endcase
    end
endfunction
function [7:0] frs4;
    input [28:0] a;
    input [1:0]  s4;
    begin
        frs4 = frs(a, {1'b1, s4});
    end
endfunction

// S(u, v) for v = 0..7 of column u, lane v at bits [3v+2:3v]
function [23:0] shrow;
    input [2:0] u;
    begin
        case (u)
        3'd0: shrow = 24'b110110101100100100100100;
        3'd1: shrow = 24'b111110101100100100100011;
        3'd2: shrow = 24'b111110110101100100100011;
        3'd3: shrow = 24'b111110110110101101100100;
        3'd4: shrow = 24'b111111110110110101101101;
        3'd5: shrow = 24'b111111111111110110110101;
        3'd6: shrow = 24'b111111111111110110110110;
        3'd7: shrow = 24'b111111111110110110110110;
            default: shrow = 24'd0;
        endcase
    end
endfunction

// AC Huffman: {length, code right aligned}, only symbols that can occur (EOB, ZRL, RUN 0..15 x SIZE 1..7)
function [20:0] aclut;
    input [7:0] sym;
    begin
        case (sym)
        8'h00: aclut = {5'd4, 16'h000A};
        8'h01: aclut = {5'd2, 16'h0000};
        8'h02: aclut = {5'd2, 16'h0001};
        8'h03: aclut = {5'd3, 16'h0004};
        8'h04: aclut = {5'd4, 16'h000B};
        8'h05: aclut = {5'd5, 16'h001A};
        8'h06: aclut = {5'd7, 16'h0078};
        8'h07: aclut = {5'd8, 16'h00F8};
        8'h11: aclut = {5'd4, 16'h000C};
        8'h12: aclut = {5'd5, 16'h001B};
        8'h13: aclut = {5'd7, 16'h0079};
        8'h14: aclut = {5'd9, 16'h01F6};
        8'h15: aclut = {5'd11, 16'h07F6};
        8'h16: aclut = {5'd16, 16'hFF84};
        8'h17: aclut = {5'd16, 16'hFF85};
        8'h21: aclut = {5'd5, 16'h001C};
        8'h22: aclut = {5'd8, 16'h00F9};
        8'h23: aclut = {5'd10, 16'h03F7};
        8'h24: aclut = {5'd12, 16'h0FF4};
        8'h25: aclut = {5'd16, 16'hFF89};
        8'h26: aclut = {5'd16, 16'hFF8A};
        8'h27: aclut = {5'd16, 16'hFF8B};
        8'h31: aclut = {5'd6, 16'h003A};
        8'h32: aclut = {5'd9, 16'h01F7};
        8'h33: aclut = {5'd12, 16'h0FF5};
        8'h34: aclut = {5'd16, 16'hFF8F};
        8'h35: aclut = {5'd16, 16'hFF90};
        8'h36: aclut = {5'd16, 16'hFF91};
        8'h37: aclut = {5'd16, 16'hFF92};
        8'h41: aclut = {5'd6, 16'h003B};
        8'h42: aclut = {5'd10, 16'h03F8};
        8'h43: aclut = {5'd16, 16'hFF96};
        8'h44: aclut = {5'd16, 16'hFF97};
        8'h45: aclut = {5'd16, 16'hFF98};
        8'h46: aclut = {5'd16, 16'hFF99};
        8'h47: aclut = {5'd16, 16'hFF9A};
        8'h51: aclut = {5'd7, 16'h007A};
        8'h52: aclut = {5'd11, 16'h07F7};
        8'h53: aclut = {5'd16, 16'hFF9E};
        8'h54: aclut = {5'd16, 16'hFF9F};
        8'h55: aclut = {5'd16, 16'hFFA0};
        8'h56: aclut = {5'd16, 16'hFFA1};
        8'h57: aclut = {5'd16, 16'hFFA2};
        8'h61: aclut = {5'd7, 16'h007B};
        8'h62: aclut = {5'd12, 16'h0FF6};
        8'h63: aclut = {5'd16, 16'hFFA6};
        8'h64: aclut = {5'd16, 16'hFFA7};
        8'h65: aclut = {5'd16, 16'hFFA8};
        8'h66: aclut = {5'd16, 16'hFFA9};
        8'h67: aclut = {5'd16, 16'hFFAA};
        8'h71: aclut = {5'd8, 16'h00FA};
        8'h72: aclut = {5'd12, 16'h0FF7};
        8'h73: aclut = {5'd16, 16'hFFAE};
        8'h74: aclut = {5'd16, 16'hFFAF};
        8'h75: aclut = {5'd16, 16'hFFB0};
        8'h76: aclut = {5'd16, 16'hFFB1};
        8'h77: aclut = {5'd16, 16'hFFB2};
        8'h81: aclut = {5'd9, 16'h01F8};
        8'h82: aclut = {5'd15, 16'h7FC0};
        8'h83: aclut = {5'd16, 16'hFFB6};
        8'h84: aclut = {5'd16, 16'hFFB7};
        8'h85: aclut = {5'd16, 16'hFFB8};
        8'h86: aclut = {5'd16, 16'hFFB9};
        8'h87: aclut = {5'd16, 16'hFFBA};
        8'h91: aclut = {5'd9, 16'h01F9};
        8'h92: aclut = {5'd16, 16'hFFBE};
        8'h93: aclut = {5'd16, 16'hFFBF};
        8'h94: aclut = {5'd16, 16'hFFC0};
        8'h95: aclut = {5'd16, 16'hFFC1};
        8'h96: aclut = {5'd16, 16'hFFC2};
        8'h97: aclut = {5'd16, 16'hFFC3};
        8'hA1: aclut = {5'd9, 16'h01FA};
        8'hA2: aclut = {5'd16, 16'hFFC7};
        8'hA3: aclut = {5'd16, 16'hFFC8};
        8'hA4: aclut = {5'd16, 16'hFFC9};
        8'hA5: aclut = {5'd16, 16'hFFCA};
        8'hA6: aclut = {5'd16, 16'hFFCB};
        8'hA7: aclut = {5'd16, 16'hFFCC};
        8'hB1: aclut = {5'd10, 16'h03F9};
        8'hB2: aclut = {5'd16, 16'hFFD0};
        8'hB3: aclut = {5'd16, 16'hFFD1};
        8'hB4: aclut = {5'd16, 16'hFFD2};
        8'hB5: aclut = {5'd16, 16'hFFD3};
        8'hB6: aclut = {5'd16, 16'hFFD4};
        8'hB7: aclut = {5'd16, 16'hFFD5};
        8'hC1: aclut = {5'd10, 16'h03FA};
        8'hC2: aclut = {5'd16, 16'hFFD9};
        8'hC3: aclut = {5'd16, 16'hFFDA};
        8'hC4: aclut = {5'd16, 16'hFFDB};
        8'hC5: aclut = {5'd16, 16'hFFDC};
        8'hC6: aclut = {5'd16, 16'hFFDD};
        8'hC7: aclut = {5'd16, 16'hFFDE};
        8'hD1: aclut = {5'd11, 16'h07F8};
        8'hD2: aclut = {5'd16, 16'hFFE2};
        8'hD3: aclut = {5'd16, 16'hFFE3};
        8'hD4: aclut = {5'd16, 16'hFFE4};
        8'hD5: aclut = {5'd16, 16'hFFE5};
        8'hD6: aclut = {5'd16, 16'hFFE6};
        8'hD7: aclut = {5'd16, 16'hFFE7};
        8'hE1: aclut = {5'd16, 16'hFFEB};
        8'hE2: aclut = {5'd16, 16'hFFEC};
        8'hE3: aclut = {5'd16, 16'hFFED};
        8'hE4: aclut = {5'd16, 16'hFFEE};
        8'hE5: aclut = {5'd16, 16'hFFEF};
        8'hE6: aclut = {5'd16, 16'hFFF0};
        8'hE7: aclut = {5'd16, 16'hFFF1};
        8'hF0: aclut = {5'd11, 16'h07F9};
        8'hF1: aclut = {5'd16, 16'hFFF5};
        8'hF2: aclut = {5'd16, 16'hFFF6};
        8'hF3: aclut = {5'd16, 16'hFFF7};
        8'hF4: aclut = {5'd16, 16'hFFF8};
        8'hF5: aclut = {5'd16, 16'hFFF9};
        8'hF6: aclut = {5'd16, 16'hFFFA};
        8'hF7: aclut = {5'd16, 16'hFFFB};
        default: aclut = 21'd0;
        endcase
    end
endfunction

function [20:0] dclut;
    input [3:0] sz;
    begin
        case (sz)
        4'd0: dclut = {5'd2, 16'h0000};
        4'd1: dclut = {5'd3, 16'h0002};
        4'd2: dclut = {5'd3, 16'h0003};
        4'd3: dclut = {5'd3, 16'h0004};
        4'd4: dclut = {5'd3, 16'h0005};
        4'd5: dclut = {5'd3, 16'h0006};
        4'd6: dclut = {5'd4, 16'h000E};
        4'd7: dclut = {5'd5, 16'h001E};
        4'd8: dclut = {5'd6, 16'h003E};
        default: dclut = 21'd0;
        endcase
    end
endfunction

// Huffman code already shifted left by the amplitude size, and the total field length:
// index {DC, run, size}; EOB = AC run 0 size 0, ZRL = AC run 15 size 0; only reachable symbols are listed
function [27:0] hlut;
    input [8:0] k;
    begin
        case (k)
        9'h000: hlut = {5'd4, 23'h00000A};
        9'h001: hlut = {5'd3, 23'h000000};
        9'h002: hlut = {5'd4, 23'h000004};
        9'h003: hlut = {5'd6, 23'h000020};
        9'h004: hlut = {5'd8, 23'h0000B0};
        9'h005: hlut = {5'd10, 23'h000340};
        9'h006: hlut = {5'd13, 23'h001E00};
        9'h007: hlut = {5'd15, 23'h007C00};
        9'h011: hlut = {5'd5, 23'h000018};
        9'h012: hlut = {5'd7, 23'h00006C};
        9'h013: hlut = {5'd10, 23'h0003C8};
        9'h014: hlut = {5'd13, 23'h001F60};
        9'h015: hlut = {5'd16, 23'h00FEC0};
        9'h016: hlut = {5'd22, 23'h3FE100};
        9'h017: hlut = {5'd23, 23'h7FC280};
        9'h021: hlut = {5'd6, 23'h000038};
        9'h022: hlut = {5'd10, 23'h0003E4};
        9'h023: hlut = {5'd13, 23'h001FB8};
        9'h024: hlut = {5'd16, 23'h00FF40};
        9'h025: hlut = {5'd21, 23'h1FF120};
        9'h026: hlut = {5'd22, 23'h3FE280};
        9'h027: hlut = {5'd23, 23'h7FC580};
        9'h031: hlut = {5'd7, 23'h000074};
        9'h032: hlut = {5'd11, 23'h0007DC};
        9'h033: hlut = {5'd15, 23'h007FA8};
        9'h034: hlut = {5'd20, 23'h0FF8F0};
        9'h035: hlut = {5'd21, 23'h1FF200};
        9'h036: hlut = {5'd22, 23'h3FE440};
        9'h037: hlut = {5'd23, 23'h7FC900};
        9'h041: hlut = {5'd7, 23'h000076};
        9'h042: hlut = {5'd12, 23'h000FE0};
        9'h043: hlut = {5'd19, 23'h07FCB0};
        9'h044: hlut = {5'd20, 23'h0FF970};
        9'h045: hlut = {5'd21, 23'h1FF300};
        9'h046: hlut = {5'd22, 23'h3FE640};
        9'h047: hlut = {5'd23, 23'h7FCD00};
        9'h051: hlut = {5'd8, 23'h0000F4};
        9'h052: hlut = {5'd13, 23'h001FDC};
        9'h053: hlut = {5'd19, 23'h07FCF0};
        9'h054: hlut = {5'd20, 23'h0FF9F0};
        9'h055: hlut = {5'd21, 23'h1FF400};
        9'h056: hlut = {5'd22, 23'h3FE840};
        9'h057: hlut = {5'd23, 23'h7FD100};
        9'h061: hlut = {5'd8, 23'h0000F6};
        9'h062: hlut = {5'd14, 23'h003FD8};
        9'h063: hlut = {5'd19, 23'h07FD30};
        9'h064: hlut = {5'd20, 23'h0FFA70};
        9'h065: hlut = {5'd21, 23'h1FF500};
        9'h066: hlut = {5'd22, 23'h3FEA40};
        9'h067: hlut = {5'd23, 23'h7FD500};
        9'h071: hlut = {5'd9, 23'h0001F4};
        9'h072: hlut = {5'd14, 23'h003FDC};
        9'h073: hlut = {5'd19, 23'h07FD70};
        9'h074: hlut = {5'd20, 23'h0FFAF0};
        9'h075: hlut = {5'd21, 23'h1FF600};
        9'h076: hlut = {5'd22, 23'h3FEC40};
        9'h077: hlut = {5'd23, 23'h7FD900};
        9'h081: hlut = {5'd10, 23'h0003F0};
        9'h082: hlut = {5'd17, 23'h01FF00};
        9'h083: hlut = {5'd19, 23'h07FDB0};
        9'h084: hlut = {5'd20, 23'h0FFB70};
        9'h085: hlut = {5'd21, 23'h1FF700};
        9'h086: hlut = {5'd22, 23'h3FEE40};
        9'h087: hlut = {5'd23, 23'h7FDD00};
        9'h091: hlut = {5'd10, 23'h0003F2};
        9'h092: hlut = {5'd18, 23'h03FEF8};
        9'h093: hlut = {5'd19, 23'h07FDF8};
        9'h094: hlut = {5'd20, 23'h0FFC00};
        9'h095: hlut = {5'd21, 23'h1FF820};
        9'h096: hlut = {5'd22, 23'h3FF080};
        9'h097: hlut = {5'd23, 23'h7FE180};
        9'h0A1: hlut = {5'd10, 23'h0003F4};
        9'h0A2: hlut = {5'd18, 23'h03FF1C};
        9'h0A3: hlut = {5'd19, 23'h07FE40};
        9'h0A4: hlut = {5'd20, 23'h0FFC90};
        9'h0A5: hlut = {5'd21, 23'h1FF940};
        9'h0A6: hlut = {5'd22, 23'h3FF2C0};
        9'h0A7: hlut = {5'd23, 23'h7FE600};
        9'h0B1: hlut = {5'd11, 23'h0007F2};
        9'h0B2: hlut = {5'd18, 23'h03FF40};
        9'h0B3: hlut = {5'd19, 23'h07FE88};
        9'h0B4: hlut = {5'd20, 23'h0FFD20};
        9'h0B5: hlut = {5'd21, 23'h1FFA60};
        9'h0B6: hlut = {5'd22, 23'h3FF500};
        9'h0B7: hlut = {5'd23, 23'h7FEA80};
        9'h0C1: hlut = {5'd11, 23'h0007F4};
        9'h0C2: hlut = {5'd18, 23'h03FF64};
        9'h0C3: hlut = {5'd19, 23'h07FED0};
        9'h0C4: hlut = {5'd20, 23'h0FFDB0};
        9'h0C5: hlut = {5'd21, 23'h1FFB80};
        9'h0C6: hlut = {5'd22, 23'h3FF740};
        9'h0C7: hlut = {5'd23, 23'h7FEF00};
        9'h0D1: hlut = {5'd12, 23'h000FF0};
        9'h0D2: hlut = {5'd18, 23'h03FF88};
        9'h0D3: hlut = {5'd19, 23'h07FF18};
        9'h0D4: hlut = {5'd20, 23'h0FFE40};
        9'h0D5: hlut = {5'd21, 23'h1FFCA0};
        9'h0D6: hlut = {5'd22, 23'h3FF980};
        9'h0D7: hlut = {5'd23, 23'h7FF380};
        9'h0E1: hlut = {5'd17, 23'h01FFD6};
        9'h0E2: hlut = {5'd18, 23'h03FFB0};
        9'h0E3: hlut = {5'd19, 23'h07FF68};
        9'h0E4: hlut = {5'd20, 23'h0FFEE0};
        9'h0E5: hlut = {5'd21, 23'h1FFDE0};
        9'h0E6: hlut = {5'd22, 23'h3FFC00};
        9'h0E7: hlut = {5'd23, 23'h7FF880};
        9'h0F0: hlut = {5'd11, 23'h0007F9};
        9'h0F1: hlut = {5'd17, 23'h01FFEA};
        9'h0F2: hlut = {5'd18, 23'h03FFD8};
        9'h0F3: hlut = {5'd19, 23'h07FFB8};
        9'h0F4: hlut = {5'd20, 23'h0FFF80};
        9'h0F5: hlut = {5'd21, 23'h1FFF20};
        9'h0F6: hlut = {5'd22, 23'h3FFE80};
        9'h0F7: hlut = {5'd23, 23'h7FFD80};
        9'h100: hlut = {5'd2, 23'h000000};
        9'h101: hlut = {5'd4, 23'h000004};
        9'h102: hlut = {5'd5, 23'h00000C};
        9'h103: hlut = {5'd6, 23'h000020};
        9'h104: hlut = {5'd7, 23'h000050};
        9'h105: hlut = {5'd8, 23'h0000C0};
        9'h106: hlut = {5'd10, 23'h000380};
        9'h107: hlut = {5'd12, 23'h000F00};
        9'h108: hlut = {5'd14, 23'h003E00};
        default: hlut = 28'd0;
        endcase
    end
endfunction
function [3:0] bitlen9;
    input [8:0] x;
    begin
        if      (x[8]) bitlen9 = 4'd9;
        else if (x[7]) bitlen9 = 4'd8;
        else if (x[6]) bitlen9 = 4'd7;
        else if (x[5]) bitlen9 = 4'd6;
        else if (x[4]) bitlen9 = 4'd5;
        else if (x[3]) bitlen9 = 4'd4;
        else if (x[2]) bitlen9 = 4'd3;
        else if (x[1]) bitlen9 = 4'd2;
        else if (x[0]) bitlen9 = 4'd1;
        else           bitlen9 = 4'd0;
    end
endfunction

// zigzag index of coefficient (u, v)
function [5:0] zzpos;
    input [2:0] u, v;
    begin
        case ({u, v})
        6'd0: zzpos = 6'd0;
        6'd1: zzpos = 6'd2;
        6'd2: zzpos = 6'd3;
        6'd3: zzpos = 6'd9;
        6'd4: zzpos = 6'd10;
        6'd5: zzpos = 6'd20;
        6'd6: zzpos = 6'd21;
        6'd7: zzpos = 6'd35;
        6'd8: zzpos = 6'd1;
        6'd9: zzpos = 6'd4;
        6'd10: zzpos = 6'd8;
        6'd11: zzpos = 6'd11;
        6'd12: zzpos = 6'd19;
        6'd13: zzpos = 6'd22;
        6'd14: zzpos = 6'd34;
        6'd15: zzpos = 6'd36;
        6'd16: zzpos = 6'd5;
        6'd17: zzpos = 6'd7;
        6'd18: zzpos = 6'd12;
        6'd19: zzpos = 6'd18;
        6'd20: zzpos = 6'd23;
        6'd21: zzpos = 6'd33;
        6'd22: zzpos = 6'd37;
        6'd23: zzpos = 6'd48;
        6'd24: zzpos = 6'd6;
        6'd25: zzpos = 6'd13;
        6'd26: zzpos = 6'd17;
        6'd27: zzpos = 6'd24;
        6'd28: zzpos = 6'd32;
        6'd29: zzpos = 6'd38;
        6'd30: zzpos = 6'd47;
        6'd31: zzpos = 6'd49;
        6'd32: zzpos = 6'd14;
        6'd33: zzpos = 6'd16;
        6'd34: zzpos = 6'd25;
        6'd35: zzpos = 6'd31;
        6'd36: zzpos = 6'd39;
        6'd37: zzpos = 6'd46;
        6'd38: zzpos = 6'd50;
        6'd39: zzpos = 6'd57;
        6'd40: zzpos = 6'd15;
        6'd41: zzpos = 6'd26;
        6'd42: zzpos = 6'd30;
        6'd43: zzpos = 6'd40;
        6'd44: zzpos = 6'd45;
        6'd45: zzpos = 6'd51;
        6'd46: zzpos = 6'd56;
        6'd47: zzpos = 6'd58;
        6'd48: zzpos = 6'd27;
        6'd49: zzpos = 6'd29;
        6'd50: zzpos = 6'd41;
        6'd51: zzpos = 6'd44;
        6'd52: zzpos = 6'd52;
        6'd53: zzpos = 6'd55;
        6'd54: zzpos = 6'd59;
        6'd55: zzpos = 6'd62;
        6'd56: zzpos = 6'd28;
        6'd57: zzpos = 6'd42;
        6'd58: zzpos = 6'd43;
        6'd59: zzpos = 6'd53;
        6'd60: zzpos = 6'd54;
        6'd61: zzpos = 6'd60;
        6'd62: zzpos = 6'd61;
        6'd63: zzpos = 6'd63;
            default: zzpos = 6'd0;
        endcase
    end
endfunction

// ---------------------------------------------------------------------------------------------- SRAM
wire        g_in, g_out, g_str, g_eng;
wire [10:0] sram_a;
wire [63:0] sram_di, sram_do;
wire        sram_cs  = g_in | g_out | g_str | g_eng;
wire        sram_web = ~(g_in | g_str);

SUMA180_1488X64X1BM1 u_sram (
    .A0(sram_a[0]), .A1(sram_a[1]), .A2(sram_a[2]), .A3(sram_a[3]), .A4(sram_a[4]), .A5(sram_a[5]),
    .A6(sram_a[6]), .A7(sram_a[7]), .A8(sram_a[8]), .A9(sram_a[9]), .A10(sram_a[10]),
    .DO0(sram_do[0]),   .DO1(sram_do[1]),   .DO2(sram_do[2]),   .DO3(sram_do[3]),
    .DO4(sram_do[4]),   .DO5(sram_do[5]),   .DO6(sram_do[6]),   .DO7(sram_do[7]),
    .DO8(sram_do[8]),   .DO9(sram_do[9]),   .DO10(sram_do[10]), .DO11(sram_do[11]),
    .DO12(sram_do[12]), .DO13(sram_do[13]), .DO14(sram_do[14]), .DO15(sram_do[15]),
    .DO16(sram_do[16]), .DO17(sram_do[17]), .DO18(sram_do[18]), .DO19(sram_do[19]),
    .DO20(sram_do[20]), .DO21(sram_do[21]), .DO22(sram_do[22]), .DO23(sram_do[23]),
    .DO24(sram_do[24]), .DO25(sram_do[25]), .DO26(sram_do[26]), .DO27(sram_do[27]),
    .DO28(sram_do[28]), .DO29(sram_do[29]), .DO30(sram_do[30]), .DO31(sram_do[31]),
    .DO32(sram_do[32]), .DO33(sram_do[33]), .DO34(sram_do[34]), .DO35(sram_do[35]),
    .DO36(sram_do[36]), .DO37(sram_do[37]), .DO38(sram_do[38]), .DO39(sram_do[39]),
    .DO40(sram_do[40]), .DO41(sram_do[41]), .DO42(sram_do[42]), .DO43(sram_do[43]),
    .DO44(sram_do[44]), .DO45(sram_do[45]), .DO46(sram_do[46]), .DO47(sram_do[47]),
    .DO48(sram_do[48]), .DO49(sram_do[49]), .DO50(sram_do[50]), .DO51(sram_do[51]),
    .DO52(sram_do[52]), .DO53(sram_do[53]), .DO54(sram_do[54]), .DO55(sram_do[55]),
    .DO56(sram_do[56]), .DO57(sram_do[57]), .DO58(sram_do[58]), .DO59(sram_do[59]),
    .DO60(sram_do[60]), .DO61(sram_do[61]), .DO62(sram_do[62]), .DO63(sram_do[63]),
    .DI0(sram_di[0]),   .DI1(sram_di[1]),   .DI2(sram_di[2]),   .DI3(sram_di[3]),
    .DI4(sram_di[4]),   .DI5(sram_di[5]),   .DI6(sram_di[6]),   .DI7(sram_di[7]),
    .DI8(sram_di[8]),   .DI9(sram_di[9]),   .DI10(sram_di[10]), .DI11(sram_di[11]),
    .DI12(sram_di[12]), .DI13(sram_di[13]), .DI14(sram_di[14]), .DI15(sram_di[15]),
    .DI16(sram_di[16]), .DI17(sram_di[17]), .DI18(sram_di[18]), .DI19(sram_di[19]),
    .DI20(sram_di[20]), .DI21(sram_di[21]), .DI22(sram_di[22]), .DI23(sram_di[23]),
    .DI24(sram_di[24]), .DI25(sram_di[25]), .DI26(sram_di[26]), .DI27(sram_di[27]),
    .DI28(sram_di[28]), .DI29(sram_di[29]), .DI30(sram_di[30]), .DI31(sram_di[31]),
    .DI32(sram_di[32]), .DI33(sram_di[33]), .DI34(sram_di[34]), .DI35(sram_di[35]),
    .DI36(sram_di[36]), .DI37(sram_di[37]), .DI38(sram_di[38]), .DI39(sram_di[39]),
    .DI40(sram_di[40]), .DI41(sram_di[41]), .DI42(sram_di[42]), .DI43(sram_di[43]),
    .DI44(sram_di[44]), .DI45(sram_di[45]), .DI46(sram_di[46]), .DI47(sram_di[47]),
    .DI48(sram_di[48]), .DI49(sram_di[49]), .DI50(sram_di[50]), .DI51(sram_di[51]),
    .DI52(sram_di[52]), .DI53(sram_di[53]), .DI54(sram_di[54]), .DI55(sram_di[55]),
    .DI56(sram_di[56]), .DI57(sram_di[57]), .DI58(sram_di[58]), .DI59(sram_di[59]),
    .DI60(sram_di[60]), .DI61(sram_di[61]), .DI62(sram_di[62]), .DI63(sram_di[63]),
    .CK(clk), .WEB(sram_web), .OE(1'b1), .CS(sram_cs)
);

reg [63:0] dout_q;
always @(posedge clk) dout_q <= sram_do;

// next bitstream address: 128 + j up to 1487, then rotr7(m, 6) for m = j - 1360 (m + 1 -> rotl7(rotr7(a, 1) + 1, 1))
function [10:0] bs_next;
    input [10:0] a;
    reg   [6:0]  m;
    begin
        m = {a[0], a[6:1]} + 7'd1;
        if (a[10:7] == 4'd0)       bs_next = {4'd0, m[5:0], m[6]};
        else if (a == 11'd1487)    bs_next = 11'd0;
        else                       bs_next = a + 11'd1;
    end
endfunction

// image end: one-cycle clear of every per-image state
reg img_end;

// ---------------------------------------------------------------------------------------------- input
reg  [6:0]  in_x, in_y;
reg  [63:0] io_r;                       // input: last 8 pixels (written the cycle after the 8th);
                                        // output: the word being sent (input and output never overlap)
reg         in_wpend, in_wlast, in_done;
reg  [6:0]  in_waddr;
reg  [7:0]  blkdone;                    // blocks whose 8 words are in the SRAM
wire [7:0]  pixl = {~in_data[7], in_data[6:0]};   // P - 128

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        in_x <= 7'd0; in_y <= 7'd0; in_wpend <= 1'b0; in_wlast <= 1'b0; in_done <= 1'b0;
    end else begin
        if (in_valid) begin
            in_x <= in_x + 7'd1;
            if (in_x == 7'd127) in_y <= in_y + 7'd1;
            if (in_x == 7'd127 && in_y == 7'd127) in_done <= 1'b1;
        end else if (img_end) begin
            in_done <= 1'b0;
        end
        if (in_valid && in_x[2:0] == 3'd7) begin
            in_wpend <= 1'b1;
            in_wlast <= (in_y[2:0] == 3'd7);
        end else if (g_in) begin
            in_wpend <= 1'b0;
        end
    end
end

always @(posedge clk) begin
    if (in_valid && in_x[2:0] == 3'd7) begin
        in_waddr <= rotr7({in_y[2:0], in_x[6:3]}, rot_of(in_y[6:3]));
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)                  blkdone <= 8'd0;
    else if (img_end)            blkdone <= 8'd0;
    else if (g_in && in_wlast)   blkdone <= blkdone + 8'd1;
end

// ---------------------------------------------------------------------------------------------- engine fetch
localparam E_P1 = 2'd0, E_WT = 2'd1, E_P2 = 2'd2, E_FIN = 2'd3;
reg  [1:0]  est;
reg  [2:0]  ecnt;
reg         ehalf;                      // engine half (1: u 4..7 first, 0: u 0..3)
reg  [7:0]  fb;                         // block being fetched
reg         fb_fin;
reg         fhalf;                      // fetch half (0: u 0..3, 1: u 4..7)
reg  [2:0]  fy;                         // row being fetched
// read now: P1 of the half being fetched (fhalf != ehalf: fetch and engine on the same half);
// prefetch: P2 cycles ecnt = 6 / 7 for rows 0 / 1 of the next half (fhalf == ehalf: fetch already moved on)
wire        r_now = (est == E_P1) && (fhalf != ehalf);
wire        r_pre = (est == E_P2) && (fhalf == ehalf) && (ecnt[2:1] == 2'b11) && (fy <= {2'b00, ecnt[0]});
wire        r_eng = !fb_fin && (blkdone != fb) && (r_now || r_pre);
wire [6:0]  eng_a = rotr7({fy, fb[3:0]}, rot_of(fb[7:4]));

// read tags: stage 1 at the SRAM edge, stage 2 with dout_q
reg        rt1_out, rt1_eng, rt2_out, rt2_eng;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rt1_out <= 1'b0; rt1_eng <= 1'b0; rt2_out <= 1'b0; rt2_eng <= 1'b0;
    end else begin
        rt1_out <= g_out; rt1_eng <= g_eng;
        rt2_out <= rt1_out; rt2_eng <= rt1_eng;
    end
end

// engine unit control
reg  [1:0]  wt;
reg  [1:0]  q_full;
reg         lo_hold, lo_own;            // low half (u <= 3) holds data of block parity lo_own
reg         hw_full, hr_busy;           // H half: A holds a complete half / B holds a block not yet coded
reg         qw, qr;
reg  [7:0]  fpx;                        // first pixel of the block (P - 128)
reg         fflat, fdc;                 // rows so far all equal to fpx / block found flat, waiting for the low half
reg  [1:0]  qflat;                      // Q buffer parity holds a flat block (no H half)
wire [7:0]  fref  = (ecnt == 3'd0) ? dout_q[63:56] : fpx;
wire        frow  = (dout_q == {8{fref}});
wire        fev   = (est == E_WT) && fdc && !lo_hold;     // flat block: write Q(0,0) now
// V(0,0) of a flat block: (P'+1)>>1 for P' >= 0, ~((-P'+1)>>1) for P' < 0 (V = Q - 1)
wire [8:0]  fdm   = fpx[7] ? ({1'b0, ~fpx} + 9'd2) : ({1'b0, fpx} + 9'd1);
wire [7:0]  fdcv  = fpx[7] ? ~fdm[8:1] : fdm[8:1];
wire        ld1 = rt2_eng;                  // a row arrives only in P1 (read scheduling)
wire        ld2 = (est == E_P2) && (ecnt != 3'd0 || (ehalf ? !hw_full : !lo_hold));

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fb <= 8'd0; fb_fin <= 1'b0; fhalf <= 1'b0; fy <= 3'd0;
    end else if (img_end) begin
        fb <= 8'd0; fb_fin <= 1'b0; fhalf <= 1'b0; fy <= 3'd0;
    end else begin
        if (g_eng) begin
            fy <= fy + 3'd1;
            if (fy == 3'd7) begin
                fhalf <= ~fhalf;
                if (fhalf) begin
                    fb <= fb + 8'd1;
                    if (fb == 8'd255) fb_fin <= 1'b1;
                end
            end
        end else if (fev) begin                         // no reads in E_WT: skip the second fetch of a flat block
            fhalf <= 1'b0;
            fb <= fb + 8'd1;
            if (fb == 8'd255) fb_fin <= 1'b1;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        est <= E_P1; ecnt <= 3'd0; wt <= 2'd0; ehalf <= 1'b1; fdc <= 1'b0;
    end else if (img_end) begin
        est <= E_P1; ecnt <= 3'd0; wt <= 2'd0; ehalf <= 1'b1; fdc <= 1'b0;
    end else begin
        case (est)
            E_P1: if (ld1) begin
                      ecnt <= ecnt + 3'd1;
                      if (ecnt == 3'd7) begin
                          est <= E_WT; wt <= 2'd0;
                          fdc <= ehalf && fflat && frow;          // first fetch: all 64 pixels equal
                      end
                  end
            E_WT: if (fdc) begin
                      if (!lo_hold) begin                         // fev: Q(0,0) written, block done
                          fdc <= 1'b0;
                          est <= (fb == 8'd255) ? E_FIN : E_P1;    // fev: fb is still this block
                      end
                  end else begin
                      wt <= wt + 2'd1;
                      if (wt == 2'd3) est <= E_P2;
                  end
            E_P2: if (ld2) begin
                      ecnt <= ecnt + 3'd1;
                      if (ecnt == 3'd7) begin                // 4 columns x 2 phases
                          ecnt  <= 3'd0;
                          ehalf <= ~ehalf;
                          if (!ehalf) begin
                              est <= fb_fin ? E_FIN : E_P1;        // fb = this block + 1 here
                          end else
                              est <= E_P1;
                      end
                  end
            default: est <= E_FIN;
        endcase
    end
end

// flat check on the rows of the first fetch (ehalf = 1); fflat holds "rows 0 .. ecnt-1 all equal to fpx"
always @(posedge clk) begin
    if (ld1 && ecnt == 3'd0) fpx <= dout_q[63:56];
    if (ld1) fflat <= ((ecnt == 3'd0) || fflat) && frow;
end

// ---------------------------------------------------------------------------------------------- DCT unit
// row stage: x_i = P'(i, y) -> R(u, y) ; column stage: x_i = R(u, i) -> A(u, v)
// two halves per block: half h keeps u = 4h + j (j = 0..3) of each row, then runs those 4 columns
reg  [18:0] tp [0:31];                  // tp[y*4+j] = R(4*ehalf + j, y)
reg  signed [18:0] x0, x1, x2, x3, x4, x5, x6, x7;
reg         t0_v, t0_c, t1_v, t1_c, t2_v, t2_c, t3_v, t3_c;   // valid, column stage
reg  [2:0]  t0_idx, t1_idx, t2_idx, t3_idx;
reg         t0_ph, t1_ph, t2_ph, t3_ph;   // phase: row stage = ehalf, column stage = ecnt[0]
// x loads every cycle (no hold): the column stage from tp, otherwise the row in dout_q (used when ld1)
always @(posedge clk) begin
    if (ld2) begin
        x0 <= tp[{3'd0, ecnt[2:1]}]; x1 <= tp[{3'd1, ecnt[2:1]}]; x2 <= tp[{3'd2, ecnt[2:1]}]; x3 <= tp[{3'd3, ecnt[2:1]}];
        x4 <= tp[{3'd4, ecnt[2:1]}]; x5 <= tp[{3'd5, ecnt[2:1]}]; x6 <= tp[{3'd6, ecnt[2:1]}]; x7 <= tp[{3'd7, ecnt[2:1]}];
    end else begin
        x0 <= {{11{dout_q[63]}}, dout_q[63:56]}; x1 <= {{11{dout_q[55]}}, dout_q[55:48]};
        x2 <= {{11{dout_q[47]}}, dout_q[47:40]}; x3 <= {{11{dout_q[39]}}, dout_q[39:32]};
        x4 <= {{11{dout_q[31]}}, dout_q[31:24]}; x5 <= {{11{dout_q[23]}}, dout_q[23:16]};
        x6 <= {{11{dout_q[15]}}, dout_q[15:8]};  x7 <= {{11{dout_q[7]}},  dout_q[7:0]};
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        t0_v <= 1'b0; t1_v <= 1'b0; t2_v <= 1'b0; t3_v <= 1'b0;
    end else begin
        t0_v <= ld1 | ld2; t1_v <= t0_v; t2_v <= t1_v; t3_v <= t2_v;
    end
end
// stage tags travel with the data; only the valid bits need a reset
always @(posedge clk) begin
    t0_c <= ld2; t0_idx <= ld2 ? {ehalf, ecnt[2:1]} : ecnt; t0_ph <= ld2 ? ecnt[0] : ehalf;
    t1_c <= t0_c; t1_idx <= t0_idx; t1_ph <= t0_ph;
    t2_c <= t1_c; t2_idx <= t1_idx; t2_ph <= t1_ph;
    t3_c <= t2_c; t3_idx <= t2_idx; t3_ph <= t2_ph;
end

// stage 1: butterfly and signed operand permutation for phase t0_ph (4 lanes, half the constant products)
//   phase 0 -> X0, X2, X1, X3 ; phase 1 -> X4, X6, X5, X7
//   lane l0 : 181 * (e0 +- e1)                 lane l1 : 237 * a + 98 * b, (a, b) = (e2, e3) or (-e3, e2)
//   lane m0 / m1 : 251 * a0 + 213 * a1 + 142 * a2 + 50 * a3, a = signed permutation of d (m1: r0 = -a0, r2 = -a2)
//            X1 = (d0, d1, d2, d3)  X3 = (-d2, d0, -d3, -d1)  X5 = (-d1, d3, d0, d2)  X7 = (-d3, d2, -d1, d0)
wire signed [19:0] s0 = x0 + x7, s1 = x1 + x6, s2 = x2 + x5, s3 = x3 + x4;
wire signed [19:0] d0w = x0 - x7, d1w = x1 - x6, d2w = x2 - x5, d3w = x3 - x4;
wire signed [20:0] e0 = s0 + s3, e1 = s1 + s2, e2w = s0 - s3, e3w = s1 - s2;
reg  signed [21:0] f;
reg  signed [20:0] ea, eb;
reg  signed [19:0] p0, p1, p2, p3, r0, r1, r2, r3;
always @(posedge clk) begin
    f  <= t0_ph ? e0 - e1 : e0 + e1;
    ea <= t0_ph ? -e3w : e2w;
    eb <= t0_ph ? e2w  : e3w;
    p0 <= t0_ph ? -d1w : d0w;   p1 <= t0_ph ? d3w : d1w;   p2 <= t0_ph ? d0w  : d2w;   p3 <= t0_ph ? d2w : d3w;
    r0 <= t0_ph ? d3w : d2w;    r1 <= t0_ph ? d2w : d0w;   r2 <= t0_ph ? d1w : d3w;    r3 <= t0_ph ? d0w : -d1w;
end

// stage 2: constant products, pair sums
reg signed [28:0] l0, l1, m0a, m0b, m1a, m1b;
always @(posedge clk) begin
    l0  <= f  * 9'sd181;
    l1  <= ea * 9'sd237 + eb * 9'sd98;
    m0a <= p0 * 9'sd251 + p1 * 9'sd213;
    m0b <= p2 * 9'sd142 + p3 * 9'sd50;
    m1a <= r1 * 9'sd213 - r0 * 9'sd251;      // r0, r2 hold -a0, -a2 of lane m1
    m1b <= r3 * 9'sd50  - r2 * 9'sd142;
end

// stage 3: odd lanes X(4ph+1) = m0a + m0b, X(4ph+3) = m1a + m1b; the even lanes X(4ph), X(4ph+2) are l0, l1 one stage earlier
// zm keeps the round inputs only: A[28:17] and the sticky |A[16:0]
wire signed [28:0] am0 = m0a + m0b, am1 = m1a + m1b;
reg  [12:0] zm0, zm1;
always @(posedge clk) begin
    zm0 <= {am0[28:17], |am0[16:0]}; zm1 <= {am1[28:17], |am1[16:0]};
end

// row stage result -> transpose row (the row phase is ehalf, so lane j holds u = 4*ehalf + j directly):
// all lanes at t2: j = 0, 2 from l0, l1, j = 1, 3 from the sums m0a + m0b, m1a + m1b
always @(posedge clk) begin
    if (t2_v && !t2_c) begin
        tp[{t2_idx, 2'd0}] <= l0[18:0]; tp[{t2_idx, 2'd2}] <= l1[18:0];
        tp[{t2_idx, 2'd1}] <= am0[18:0]; tp[{t2_idx, 2'd3}] <= am1[18:0];
    end
end

// column stage result -> fused round -> register -> Q buffer (zigzag order, V format)
// lane k (v = 4 * ph + k): k = 0, 2 round l0, l1 at t2 (shift row of t2_idx), k = 1, 3 round zm0, zm1 at t3
wire [23:0] sr  = shrow(t3_idx);
wire [23:0] sre = shrow(t2_idx);
wire [7:0]  vl [0:3];
assign vl[0] = frs (l0,  t2_ph ? sre[14:12] : sre[2:0]);   // S 3..7
assign vl[1] = frs4({zm0[12:1], 16'd0, zm0[0]}, t3_ph ? sr[16:15]  : sr[4:3]);    // S 4..7
assign vl[2] = frs4(l1,  t2_ph ? sre[19:18] : sre[7:6]);
assign vl[3] = frs4({zm1[12:1], 16'd0, zm1[0]}, t3_ph ? sr[22:21]  : sr[10:9]);

// one register stage after the fused round
reg         t4_v, t4_c, t4_ph;
reg  [2:0]  t4_idx;
reg  [7:0]  v4l [0:3];
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) t4_v <= 1'b0;
    else        t4_v <= t3_v;
end
always @(posedge clk) begin
    t4_c <= t3_c; t4_ph <= t3_ph; t4_idx <= t3_idx;
end
always @(posedge clk) begin
    v4l[0] <= vl[0]; v4l[1] <= vl[1]; v4l[2] <= vl[2]; v4l[3] <= vl[3];
end

// Q buffers: entry p (zigzag index) keeps V in bitlen(max |Q|) + 1 bits; u >= 4: two copies qa / qb (153 bits each),
// u <= 3 (p <= 49): one copy qs (198 bits), free once the coder of its block has moved past p49
reg  [7:0] qs0;
reg  [7:0] qs1;
reg  [6:0] qs2;
reg  [6:0] qs3;
reg  [6:0] qs4;
reg  [7:0] qs5;
reg  [6:0] qs6;
reg  [6:0] qs7;
reg  [6:0] qs8;
reg  [6:0] qs9;
reg  [7:0] qs10;
reg  [6:0] qs11;
reg  [6:0] qs12;
reg  [6:0] qs13;
reg  [6:0] qa14, qb14;
reg  [5:0] qa15, qb15;
reg  [5:0] qa16, qb16;
reg  [5:0] qs17;
reg  [6:0] qs18;
reg  [6:0] qs19;
reg  [5:0] qs20;
reg  [4:0] qs21;
reg  [5:0] qs22;
reg  [5:0] qs23;
reg  [5:0] qs24;
reg  [5:0] qa25, qb25;
reg  [4:0] qa26, qb26;
reg  [4:0] qa27, qb27;
reg  [4:0] qa28, qb28;
reg  [4:0] qa29, qb29;
reg  [4:0] qa30, qb30;
reg  [4:0] qa31, qb31;
reg  [4:0] qs32;
reg  [4:0] qs33;
reg  [4:0] qs34;
reg  [4:0] qs35;
reg  [3:0] qs36;
reg  [4:0] qs37;
reg  [4:0] qs38;
reg  [5:0] qa39, qb39;
reg  [4:0] qa40, qb40;
reg  [4:0] qa41, qb41;
reg  [4:0] qa42, qb42;
reg  [4:0] qa43, qb43;
reg  [4:0] qa44, qb44;
reg  [3:0] qa45, qb45;
reg  [4:0] qa46, qb46;
reg  [4:0] qs47;
reg  [3:0] qs48;
reg  [3:0] qs49;
reg  [3:0] qa50, qb50;
reg  [3:0] qa51, qb51;
reg  [3:0] qa52, qb52;
reg  [4:0] qa53, qb53;
reg  [4:0] qa54, qb54;
reg  [3:0] qa55, qb55;
reg  [3:0] qa56, qb56;
reg  [3:0] qa57, qb57;
reg  [3:0] qa58, qb58;
reg  [3:0] qa59, qb59;
reg  [3:0] qa60, qb60;
reg  [3:0] qa61, qb61;
reg  [3:0] qa62, qb62;
reg  [3:0] qa63, qb63;
// even lanes (v = 0, 2, 4, 6) arrive one stage earlier
always @(posedge clk) begin
    if (t3_v && t3_c) begin
        if (t3_idx == 3'd1 && t3_ph == 1'b0) qs1 <= v4l[0][7:0];
        if (t3_idx == 3'd0 && t3_ph == 1'b0) qs3 <= v4l[2][6:0];
        if (t3_idx == 3'd2 && t3_ph == 1'b0) qs5 <= v4l[0][7:0];
        if (t3_idx == 3'd3 && t3_ph == 1'b0) qs6 <= v4l[0][6:0];
        if (t3_idx == 3'd1 && t3_ph == 1'b0) qs8 <= v4l[2][6:0];
        if (t3_idx == 3'd0 && t3_ph == 1'b1) qs10 <= v4l[0][7:0];
        if (t3_idx == 3'd2 && t3_ph == 1'b0) qs12 <= v4l[2][6:0];
        if (t3_idx == 3'd4 && t3_ph == 1'b0) qa14 <= v4l[0][6:0];
        if (t3_idx == 3'd5 && t3_ph == 1'b0) qa15 <= v4l[0][5:0];
        if (t3_idx == 3'd3 && t3_ph == 1'b0) qs17 <= v4l[2][5:0];
        if (t3_idx == 3'd1 && t3_ph == 1'b1) qs19 <= v4l[0][6:0];
        if (t3_idx == 3'd0 && t3_ph == 1'b1) qs21 <= v4l[2][4:0];
        if (t3_idx == 3'd2 && t3_ph == 1'b1) qs23 <= v4l[0][5:0];
        if (t3_idx == 3'd4 && t3_ph == 1'b0) qa25 <= v4l[2][5:0];
        if (t3_idx == 3'd6 && t3_ph == 1'b0) qa27 <= v4l[0][4:0];
        if (t3_idx == 3'd7 && t3_ph == 1'b0) qa28 <= v4l[0][4:0];
        if (t3_idx == 3'd5 && t3_ph == 1'b0) qa30 <= v4l[2][4:0];
        if (t3_idx == 3'd3 && t3_ph == 1'b1) qs32 <= v4l[0][4:0];
        if (t3_idx == 3'd1 && t3_ph == 1'b1) qs34 <= v4l[2][4:0];
        if (t3_idx == 3'd2 && t3_ph == 1'b1) qs37 <= v4l[2][4:0];
        if (t3_idx == 3'd4 && t3_ph == 1'b1) qa39 <= v4l[0][5:0];
        if (t3_idx == 3'd6 && t3_ph == 1'b0) qa41 <= v4l[2][4:0];
        if (t3_idx == 3'd7 && t3_ph == 1'b0) qa43 <= v4l[2][4:0];
        if (t3_idx == 3'd5 && t3_ph == 1'b1) qa45 <= v4l[0][3:0];
        if (t3_idx == 3'd3 && t3_ph == 1'b1) qs47 <= v4l[2][4:0];
        if (t3_idx == 3'd4 && t3_ph == 1'b1) qa50 <= v4l[2][3:0];
        if (t3_idx == 3'd6 && t3_ph == 1'b1) qa52 <= v4l[0][3:0];
        if (t3_idx == 3'd7 && t3_ph == 1'b1) qa54 <= v4l[0][4:0];
        if (t3_idx == 3'd5 && t3_ph == 1'b1) qa56 <= v4l[2][3:0];
        if (t3_idx == 3'd6 && t3_ph == 1'b1) qa59 <= v4l[2][3:0];
        if (t3_idx == 3'd7 && t3_ph == 1'b1) qa61 <= v4l[2][3:0];
    end
end
always @(posedge clk) begin
    if (t4_v && t4_c) begin
        if (t4_idx == 3'd0 && t4_ph == 1'b0) qs2 <= v4l[1][6:0];
        if (t4_idx == 3'd1 && t4_ph == 1'b0) qs4 <= v4l[1][6:0];
        if (t4_idx == 3'd2 && t4_ph == 1'b0) qs7 <= v4l[1][6:0];
        if (t4_idx == 3'd0 && t4_ph == 1'b0) qs9 <= v4l[3][6:0];
        if (t4_idx == 3'd1 && t4_ph == 1'b0) qs11 <= v4l[3][6:0];
        if (t4_idx == 3'd3 && t4_ph == 1'b0) qs13 <= v4l[1][6:0];
        if (t4_idx == 3'd4 && t4_ph == 1'b0) qa16 <= v4l[1][5:0];
        if (t4_idx == 3'd2 && t4_ph == 1'b0) qs18 <= v4l[3][6:0];
        if (t4_idx == 3'd0 && t4_ph == 1'b1) qs20 <= v4l[1][5:0];
        if (t4_idx == 3'd1 && t4_ph == 1'b1) qs22 <= v4l[1][5:0];
        if (t4_idx == 3'd3 && t4_ph == 1'b0) qs24 <= v4l[3][5:0];
        if (t4_idx == 3'd5 && t4_ph == 1'b0) qa26 <= v4l[1][4:0];
        if (t4_idx == 3'd6 && t4_ph == 1'b0) qa29 <= v4l[1][4:0];
        if (t4_idx == 3'd4 && t4_ph == 1'b0) qa31 <= v4l[3][4:0];
        if (t4_idx == 3'd2 && t4_ph == 1'b1) qs33 <= v4l[1][4:0];
        if (t4_idx == 3'd0 && t4_ph == 1'b1) qs35 <= v4l[3][4:0];
        if (t4_idx == 3'd1 && t4_ph == 1'b1) qs36 <= v4l[3][3:0];
        if (t4_idx == 3'd3 && t4_ph == 1'b1) qs38 <= v4l[1][4:0];
        if (t4_idx == 3'd5 && t4_ph == 1'b0) qa40 <= v4l[3][4:0];
        if (t4_idx == 3'd7 && t4_ph == 1'b0) qa42 <= v4l[1][4:0];
        if (t4_idx == 3'd6 && t4_ph == 1'b0) qa44 <= v4l[3][4:0];
        if (t4_idx == 3'd4 && t4_ph == 1'b1) qa46 <= v4l[1][4:0];
        if (t4_idx == 3'd2 && t4_ph == 1'b1) qs48 <= v4l[3][3:0];
        if (t4_idx == 3'd3 && t4_ph == 1'b1) qs49 <= v4l[3][3:0];
        if (t4_idx == 3'd5 && t4_ph == 1'b1) qa51 <= v4l[1][3:0];
        if (t4_idx == 3'd7 && t4_ph == 1'b0) qa53 <= v4l[3][4:0];
        if (t4_idx == 3'd6 && t4_ph == 1'b1) qa55 <= v4l[1][3:0];
        if (t4_idx == 3'd4 && t4_ph == 1'b1) qa57 <= v4l[3][3:0];
        if (t4_idx == 3'd5 && t4_ph == 1'b1) qa58 <= v4l[3][3:0];
        if (t4_idx == 3'd7 && t4_ph == 1'b1) qa60 <= v4l[1][3:0];
        if (t4_idx == 3'd6 && t4_ph == 1'b1) qa62 <= v4l[3][3:0];
        if (t4_idx == 3'd7 && t4_ph == 1'b1) qa63 <= v4l[3][3:0];
    end
end
wire [7:0]  qv0 = {qs0};
wire [7:0]  qv1 = {qs1};
wire [7:0]  qv2 = {{1{qs2[6]}}, qs2};
wire [7:0]  qv3 = {{1{qs3[6]}}, qs3};
wire [7:0]  qv4 = {{1{qs4[6]}}, qs4};
wire [7:0]  qv5 = {qs5};
wire [7:0]  qv6 = {{1{qs6[6]}}, qs6};
wire [7:0]  qv7 = {{1{qs7[6]}}, qs7};
wire [7:0]  qv8 = {{1{qs8[6]}}, qs8};
wire [7:0]  qv9 = {{1{qs9[6]}}, qs9};
wire [7:0]  qv10 = {qs10};
wire [7:0]  qv11 = {{1{qs11[6]}}, qs11};
wire [7:0]  qv12 = {{1{qs12[6]}}, qs12};
wire [7:0]  qv13 = {{1{qs13[6]}}, qs13};
wire [7:0]  qv14 = {{1{qb14[6]}}, qb14};
wire [7:0]  qv15 = {{2{qb15[5]}}, qb15};
wire [7:0]  qv16 = {{2{qb16[5]}}, qb16};
wire [7:0]  qv17 = {{2{qs17[5]}}, qs17};
wire [7:0]  qv18 = {{1{qs18[6]}}, qs18};
wire [7:0]  qv19 = {{1{qs19[6]}}, qs19};
wire [7:0]  qv20 = {{2{qs20[5]}}, qs20};
wire [7:0]  qv21 = {{3{qs21[4]}}, qs21};
wire [7:0]  qv22 = {{2{qs22[5]}}, qs22};
wire [7:0]  qv23 = {{2{qs23[5]}}, qs23};
wire [7:0]  qv24 = {{2{qs24[5]}}, qs24};
wire [7:0]  qv25 = {{2{qb25[5]}}, qb25};
wire [7:0]  qv26 = {{3{qb26[4]}}, qb26};
wire [7:0]  qv27 = {{3{qb27[4]}}, qb27};
wire [7:0]  qv28 = {{3{qb28[4]}}, qb28};
wire [7:0]  qv29 = {{3{qb29[4]}}, qb29};
wire [7:0]  qv30 = {{3{qb30[4]}}, qb30};
wire [7:0]  qv31 = {{3{qb31[4]}}, qb31};
wire [7:0]  qv32 = {{3{qs32[4]}}, qs32};
wire [7:0]  qv33 = {{3{qs33[4]}}, qs33};
wire [7:0]  qv34 = {{3{qs34[4]}}, qs34};
wire [7:0]  qv35 = {{3{qs35[4]}}, qs35};
wire [7:0]  qv36 = {{4{qs36[3]}}, qs36};
wire [7:0]  qv37 = {{3{qs37[4]}}, qs37};
wire [7:0]  qv38 = {{3{qs38[4]}}, qs38};
wire [7:0]  qv39 = {{2{qb39[5]}}, qb39};
wire [7:0]  qv40 = {{3{qb40[4]}}, qb40};
wire [7:0]  qv41 = {{3{qb41[4]}}, qb41};
wire [7:0]  qv42 = {{3{qb42[4]}}, qb42};
wire [7:0]  qv43 = {{3{qb43[4]}}, qb43};
wire [7:0]  qv44 = {{3{qb44[4]}}, qb44};
wire [7:0]  qv45 = {{4{qb45[3]}}, qb45};
wire [7:0]  qv46 = {{3{qb46[4]}}, qb46};
wire [7:0]  qv47 = {{3{qs47[4]}}, qs47};
wire [7:0]  qv48 = {{4{qs48[3]}}, qs48};
wire [7:0]  qv49 = {{4{qs49[3]}}, qs49};
wire [7:0]  qv50 = {{4{qb50[3]}}, qb50};
wire [7:0]  qv51 = {{4{qb51[3]}}, qb51};
wire [7:0]  qv52 = {{4{qb52[3]}}, qb52};
wire [7:0]  qv53 = {{3{qb53[4]}}, qb53};
wire [7:0]  qv54 = {{3{qb54[4]}}, qb54};
wire [7:0]  qv55 = {{4{qb55[3]}}, qb55};
wire [7:0]  qv56 = {{4{qb56[3]}}, qb56};
wire [7:0]  qv57 = {{4{qb57[3]}}, qb57};
wire [7:0]  qv58 = {{4{qb58[3]}}, qb58};
wire [7:0]  qv59 = {{4{qb59[3]}}, qb59};
wire [7:0]  qv60 = {{4{qb60[3]}}, qb60};
wire [7:0]  qv61 = {{4{qb61[3]}}, qb61};
wire [7:0]  qv62 = {{4{qb62[3]}}, qb62};
wire [7:0]  qv63 = {{4{qb63[3]}}, qb63};

// ---------------------------------------------------------------------------------------------- coder
// C1: symbol select (one zigzag position per cycle)  C2a: size / amplitude  C2b: Huffman field  C3: packer
wire        cstall;
reg         c_act;
reg  [5:0]  cur;                        // 1..63 while the coder is active
reg         lastq;                      // block 255 is complete in the Q buffer
reg         c1v, c1last;
reg  [1:0]  c1t;                        // 0 DC, 1 AC, 2 ZRL, 3 EOB
reg  [3:0]  c1run;
reg  [7:0]  c1val;
reg  [5:0]  lnz0, lnz1;                 // last nonzero AC position per Q buffer parity

wire        q_rdy = q_full[qr];
reg  [3:0]  crun;                       // zero AC coefficients since the last symbol
wire [5:0]  c_last = qr ? lnz1 : lnz0;  // last nonzero AC position of the block (0 = none)
wire        c_eob  = (cur > c_last);
wire [7:0]  v0    = qv0;
reg  [7:0]  qsel;
always @(*) begin
    case (cur[5:0])
        6'd0: qsel = qv0;
        6'd1: qsel = qv1;
        6'd2: qsel = qv2;
        6'd3: qsel = qv3;
        6'd4: qsel = qv4;
        6'd5: qsel = qv5;
        6'd6: qsel = qv6;
        6'd7: qsel = qv7;
        6'd8: qsel = qv8;
        6'd9: qsel = qv9;
        6'd10: qsel = qv10;
        6'd11: qsel = qv11;
        6'd12: qsel = qv12;
        6'd13: qsel = qv13;
        6'd14: qsel = qv14;
        6'd15: qsel = qv15;
        6'd16: qsel = qv16;
        6'd17: qsel = qv17;
        6'd18: qsel = qv18;
        6'd19: qsel = qv19;
        6'd20: qsel = qv20;
        6'd21: qsel = qv21;
        6'd22: qsel = qv22;
        6'd23: qsel = qv23;
        6'd24: qsel = qv24;
        6'd25: qsel = qv25;
        6'd26: qsel = qv26;
        6'd27: qsel = qv27;
        6'd28: qsel = qv28;
        6'd29: qsel = qv29;
        6'd30: qsel = qv30;
        6'd31: qsel = qv31;
        6'd32: qsel = qv32;
        6'd33: qsel = qv33;
        6'd34: qsel = qv34;
        6'd35: qsel = qv35;
        6'd36: qsel = qv36;
        6'd37: qsel = qv37;
        6'd38: qsel = qv38;
        6'd39: qsel = qv39;
        6'd40: qsel = qv40;
        6'd41: qsel = qv41;
        6'd42: qsel = qv42;
        6'd43: qsel = qv43;
        6'd44: qsel = qv44;
        6'd45: qsel = qv45;
        6'd46: qsel = qv46;
        6'd47: qsel = qv47;
        6'd48: qsel = qv48;
        6'd49: qsel = qv49;
        6'd50: qsel = qv50;
        6'd51: qsel = qv51;
        6'd52: qsel = qv52;
        6'd53: qsel = qv53;
        6'd54: qsel = qv54;
        6'd55: qsel = qv55;
        6'd56: qsel = qv56;
        6'd57: qsel = qv57;
        6'd58: qsel = qv58;
        6'd59: qsel = qv59;
        6'd60: qsel = qv60;
        6'd61: qsel = qv61;
        6'd62: qsel = qv62;
        6'd63: qsel = qv63;
        default: qsel = 8'd0;
    endcase
end
wire        c_zero = (qsel == 8'h00) || (qsel == 8'hFF);   // V = 0 / -1 is Q = 0
// done after the EOB, or after a nonzero coefficient at position 63 (no EOB then)
wire        c_dn   = c_act && !cstall && (c_eob || cur == 6'd63);   // cur = 63 and not EOB: p63 is the last nonzero

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        c_act <= 1'b0; cur <= 6'd1; c1v <= 1'b0; c1last <= 1'b0;
        c1t <= 2'd0; c1run <= 4'd0; c1val <= 8'd0; crun <= 4'd0;
    end else if (img_end) begin
        c_act <= 1'b0; cur <= 6'd1; c1v <= 1'b0; c1last <= 1'b0;
    end else if (!cstall) begin
        c1v <= 1'b0; c1last <= 1'b0;
        if (!c_act) begin
            if (q_rdy) begin
                c_act <= 1'b1; cur <= 6'd1; crun <= 4'd0;
                c1v <= 1'b1; c1t <= 2'd0; c1run <= 4'd0;
                c1val <= v0 + {7'd0, v0[7]};               // Q(0,0)
            end
        end else begin
            if (c_eob) begin
                c1v <= 1'b1; c1t <= 2'd3; c1run <= 4'd0;
            end else if (c_zero) begin
                // a zero before the last nonzero: count it; the 16th one in a row is a ZRL
                cur <= cur + 6'd1; crun <= crun + 4'd1;
                if (crun == 4'd15) begin
                    c1v <= 1'b1; c1t <= 2'd2; c1run <= 4'd15;
                end
            end else begin
                c1v <= 1'b1; c1t <= 2'd1; c1run <= crun; c1val <= qsel; crun <= 4'd0; cur <= cur + 6'd1;
            end
            if (c_dn) begin
                c_act <= 1'b0;
                c1last <= lastq && !q_full[~qr];   // block 255 is in, the other parity holds no later block
            end
        end
    end
end

// p0 (u = 0, v = 0): column stage, or Q(0,0) of a flat block
always @(posedge clk) begin
    if (fev)                                              qs0 <= fdcv;
    else if (t3_v && t3_c && t3_idx == 3'd0 && !t3_ph)    qs0 <= v4l[0][7:0];
end

// H half: the coder reads copy B; the engine writes copy A, which moves to B when B is free
wire        bdone = (t4_v && t4_c && t4_ph && t4_idx == 3'd3) || fev;   // block complete in the Q buffer
// block 255 complete: its last column at t4 (the engine is in E_FIN since its P2 ended) or its flat fev
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)                                                    lastq <= 1'b0;
    else if (img_end)                                              lastq <= 1'b0;
    else if (bdone && (est == E_FIN || (fev && fb == 8'd255)))     lastq <= 1'b1;
end
wire        hfree = c_dn && !qflat[qr];              // the coded block used copy B
wire        hcopy = hw_full && (!hr_busy || hfree);
always @(posedge clk) begin
    if (hcopy) begin
        qb14 <= qa14;
        qb15 <= qa15;
        qb16 <= qa16;
        qb25 <= qa25;
        qb26 <= qa26;
        qb27 <= qa27;
        qb28 <= qa28;
        qb29 <= qa29;
        qb30 <= qa30;
        qb31 <= qa31;
        qb39 <= qa39;
        qb40 <= qa40;
        qb41 <= qa41;
        qb42 <= qa42;
        qb43 <= qa43;
        qb44 <= qa44;
        qb45 <= qa45;
        qb46 <= qa46;
        qb50 <= qa50;
        qb51 <= qa51;
        qb52 <= qa52;
        qb53 <= qa53;
        qb54 <= qa54;
        qb55 <= qa55;
        qb56 <= qa56;
        qb57 <= qa57;
        qb58 <= qa58;
        qb59 <= qa59;
        qb60 <= qa60;
        qb61 <= qa61;
        qb62 <= qa62;
        qb63 <= qa63;
    end
end
// Q buffer flags: column 3 phase 1 (the last one) fills buffer qw; the coder frees buffer qr when a block is done
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        q_full <= 2'd0; qw <= 1'b0; qr <= 1'b0; qflat <= 2'd0;
    end else if (img_end) begin
        q_full <= 2'd0; qw <= 1'b0; qr <= 1'b0; qflat <= 2'd0;
    end else begin
        q_full <= (q_full | ({1'b0, bdone} << qw)) & ~({1'b0, c_dn} << qr);
        if (bdone) qw <= ~qw;
        if (c_dn) qr <= ~qr;
        if (bdone) qflat[qw] <= fev;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        hw_full <= 1'b0; hr_busy <= 1'b0;
    end else if (img_end) begin
        hw_full <= 1'b0; hr_busy <= 1'b0;
    end else begin
        if (t4_v && t4_c && t4_ph && t4_idx == 3'd7) hw_full <= 1'b1; else if (hcopy) hw_full <= 1'b0;
        if (hcopy) hr_busy <= 1'b1; else if (hfree) hr_busy <= 1'b0;
    end
end

// low half: set when a block's last column is written, cleared once the coder of that block has moved past p49
// (positions >= cur are the only ones it still reads) or finished it
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        lo_hold <= 1'b0; lo_own <= 1'b0;
    end else if (img_end) begin
        lo_hold <= 1'b0; lo_own <= 1'b0;
    end else if (bdone) begin
        lo_hold <= 1'b1; lo_own <= qw;
    end else if (c_act && qr == lo_own && (cur > 6'd49 || c_dn)) begin
        lo_hold <= 1'b0;
    end
end

// last nonzero AC position per Q buffer parity, collected while the column stage writes the buffer: even lanes
// (k = 0, 2) are written at t3, odd lanes at t4; the first write of a block (column u = 4, phase 0, t3) restarts it
wire [5:0]  zc0 = (t3_v && t3_c && v4l[0] != 8'h00 && v4l[0] != 8'hFF) ? zzpos(t3_idx, {t3_ph, 2'd0}) : 6'd0;
wire [5:0]  zc2 = (t3_v && t3_c && v4l[2] != 8'h00 && v4l[2] != 8'hFF) ? zzpos(t3_idx, {t3_ph, 2'd2}) : 6'd0;
wire [5:0]  zc1 = (t4_v && t4_c && v4l[1] != 8'h00 && v4l[1] != 8'hFF) ? zzpos(t4_idx, {t4_ph, 2'd1}) : 6'd0;
wire [5:0]  zc3 = (t4_v && t4_c && v4l[3] != 8'h00 && v4l[3] != 8'hFF) ? zzpos(t4_idx, {t4_ph, 2'd3}) : 6'd0;
wire [5:0]  zma = (zc2 != 6'd0) ? zc2 : zc0;   // same column: p(u, v+2) > p(u, v)
wire [5:0]  zmb = (zc3 != 6'd0) ? zc3 : zc1;
wire [5:0]  zmc = (zma > zmb) ? zma : zmb;
wire [5:0]  zold = (t3_v && t3_c && t3_idx == 3'd4 && !t3_ph) ? 6'd0 : (qw ? lnz1 : lnz0);
wire [5:0]  lnzn = (zmc > zold) ? zmc : zold;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        lnz0 <= 6'd0; lnz1 <= 6'd0;
    end else if (qw) begin
        lnz1 <= fev ? 6'd0 : lnzn;
    end else begin
        lnz0 <= fev ? 6'd0 : lnzn;
    end
end

// C2a: DC difference, size and amplitude bits   C2b: Huffman code, field = code followed by the amplitude bits
reg  signed [7:0] prev_dc;
reg         cav, calast;
reg  [1:0]  cat;
reg  [3:0]  carun, casz;
reg  [7:0]  caamp;
reg         c2v, c2last;
reg  [22:0] c2f;
reg  [4:0]  c2len;
wire signed [8:0] dlt  = {c1val[7], c1val} - {prev_dc[7], prev_dc};
wire        [8:0] vd   = dlt - {8'd0, dlt[8]};                 // amplitude form of the DC difference
wire        [8:0] vdm  = vd ^ {9{vd[8]}};
wire        [7:0] vam  = c1val ^ {8{c1val[7]}};
wire        [3:0] sz   = (c1t == 2'd0) ? bitlen9({1'b0, vdm[7:0]}) : (c1t == 2'd1) ? bitlen9({2'd0, vam[6:0]}) : 4'd0;
wire        [8:0] ampv = (c1t == 2'd0) ? vd : {1'b0, c1val};
wire        [8:0] amp  = ampv & ~({9{1'b1}} << sz);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        prev_dc <= 8'd0; cav <= 1'b0; calast <= 1'b0; cat <= 2'd0; carun <= 4'd0; casz <= 4'd0; caamp <= 8'd0;
    end else if (img_end) begin
        prev_dc <= 8'd0; cav <= 1'b0; calast <= 1'b0;
    end else if (!cstall) begin
        cav <= c1v; calast <= c1last;
        if (c1v) begin
            cat <= c1t; carun <= c1run; casz <= sz; caamp <= amp[7:0];
            if (c1t == 2'd0) prev_dc <= c1val;
        end
    end
end

wire       [27:0] hl   = hlut({cat == 2'd0, carun, casz});
reg               c2pad;                                       // c2f / c2len hold the 7-bit pad of ones

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        c2v <= 1'b0; c2last <= 1'b0; c2pad <= 1'b0; c2f <= 23'd0; c2len <= 5'd0;
    end else if (img_end) begin
        c2v <= 1'b0; c2last <= 1'b0; c2pad <= 1'b0;
    end else if (!cstall) begin
        // the cycle C3 takes the last symbol, C2b loads the pad (no symbol follows it)
        c2v <= cav || (c2v && c2last); c2last <= calast; c2pad <= c2v && c2last;
        if (cav) begin
            c2f   <= hl[22:0] | {15'd0, caamp};
            c2len <= hl[27:23];
        end else if (c2v && c2last) begin
            c2f   <= 23'h00007F;
            c2len <= 5'd7;
        end
    end
end

// C3: packer, acc[85:86-pc] hold pc bits (MSB first); every 64 bits go to the word FIFO
reg  [85:0] acc;
reg  [6:0]  pc;
reg         fcnt;
reg  [63:0] fw0;
reg         bs_done;
reg  [10:0] wcount;                     // SRAM address of the next bitstream word
reg  [3:0]  lastb;
wire [6:0]  pcn  = pc + {2'd0, c2len};
wire [108:0] insw = {c2f, 86'd0} >> pcn;   // field bit j lands at 86 + j - pc - len
wire [85:0] ins  = insw[85:0];
wire [85:0] accn = acc | ins;
wire        wfull = (pcn >= 7'd64);
// a word goes out when 64 bits are full, or at the pad when data is left (pad of ones fills its last byte)
wire        push_r = c2pad ? (pc != 7'd0) : wfull;
assign      cstall = c2v && push_r && fcnt;
wire        push   = c2v && push_r && !fcnt;
wire [63:0] pword  = accn[85:22];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        acc <= 86'd0; pc <= 7'd0; bs_done <= 1'b0;
        lastb <= 4'd8;
    end else if (img_end) begin
        acc <= 86'd0; pc <= 7'd0; bs_done <= 1'b0;
        lastb <= 4'd8;
    end else if (c2v && !cstall && c2pad) begin
        // last word: pc data bits + pad; bytes up to (pc + 7) / 8 are sent (8 when the pad reaches the word end)
        bs_done <= 1'b1; acc <= 86'd0; pc <= 7'd0;
        lastb <= (pc == 7'd0 || pcn[6]) ? 4'd8 : {1'b0, pcn[5:3]};
    end else if (c2v && !cstall) begin
        if (wfull) begin
            acc <= {accn[21:0], 64'd0};
            pc <= pcn - 7'd64;
        end else begin
            acc <= accn;
            pc <= pcn;
        end
    end
end

// word FIFO (1 entry) -> SRAM bitstream area; a push only happens while it is empty (cstall), so push and g_str
// never meet
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fcnt <= 1'b0; wcount <= 11'd128;
    end else if (img_end) begin
        fcnt <= 1'b0; wcount <= 11'd128;
    end else begin
        if (g_str) wcount <= bs_next(wcount);
        if (push) fcnt <= 1'b1; else if (g_str) fcnt <= 1'b0;
    end
end
always @(posedge clk) if (push) fw0 <= pword;

// ---------------------------------------------------------------------------------------------- output
reg  [10:0] rptr;                       // SRAM address of the next word to read
reg         ocnt, oinf;                 // word in the output buffer / read in flight
reg  [2:0]  bi;
// the next word is read 2 cycles before the current one ends (bi = 5), so it arrives with the word end
wire        r_out = in_done && (rptr != wcount) && !oinf && (!ocnt || bi >= 3'd5);
// the word in ob0 is the last one: all words pushed and written, all read, no read in flight
wire        o_last = bs_done && !fcnt && !oinf && (rptr == wcount);
wire        o_emit = in_done && (ocnt != 2'd0);
wire        o_wend = o_emit && (bi == 3'd7 || (o_last && {1'b0, bi} == lastb - 4'd1));
wire [7:0]  obyte  = io_r[63:56];           // io_r shifts one byte per output cycle

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rptr <= 11'd128; ocnt <= 1'b0; oinf <= 1'b0; bi <= 3'd0;
        out_valid <= 1'b0; out_data <= 8'd0; img_end <= 1'b0;
    end else begin
        out_valid <= o_emit && !img_end;
        out_data  <= (o_emit && !img_end) ? obyte : 8'd0;
        img_end   <= o_emit && !img_end && o_wend && o_last;
        if (img_end) begin
            rptr <= 11'd128; ocnt <= 1'b0; oinf <= 1'b0; bi <= 3'd0;
        end else begin
            if (g_out) rptr <= bs_next(rptr);
            if (g_out) oinf <= 1'b1; else if (rt2_out) oinf <= 1'b0;
            if (rt2_out) ocnt <= 1'b1; else if (o_wend) ocnt <= 1'b0;
            if (o_emit) begin
                bi <= o_wend ? 3'd0 : bi + 3'd1;
            end
        end
    end
end
always @(posedge clk) begin
    if (rt2_out) io_r <= dout_q;                 // never during the input (output reads start after in_done)
    else         io_r <= {io_r[55:0], pixl};     // input: pixel shift; output: next byte to the top
end

// ---------------------------------------------------------------------------------------------- SRAM port
assign g_in  = in_wpend;
assign g_out = !g_in && r_out;
assign g_str = !g_in && !r_out && fcnt;
assign g_eng = !g_in && !r_out && !fcnt && r_eng;
assign sram_a  = g_in  ? {4'd0, in_waddr} :
                 g_out ? rptr :
                 g_str ? wcount : {4'd0, eng_a};
assign sram_di = g_in ? io_r : fw0;

endmodule