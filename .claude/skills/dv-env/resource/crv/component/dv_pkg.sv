/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    dv_pkg.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       design verification package
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

package dv_pkg;

    //=============================================================
    //                          TYPE DEFINE
    //=============================================================
    
    typedef struct packed {
        bit sign;
        bit [7:0] exp;
        bit [22:0] frac;
    } fp32_t;

    typedef int unsigned uint;

    // Matrix layout of PATTERN, row = token, column = dim
    typedef real mat16x4_t [16][4];
    typedef real mat4x4_t [4][4];

    //=============================================================
    //                          PARAMETER
    //=============================================================
    
    localparam bit [7:0] EXP_0P5 = 8'b01111110;
    localparam bit [7:0] EXP_255 = 8'b10000110;

    localparam bit [22:0] FRAC_0P5 = 23'b00000000000000000000000;
    localparam bit [22:0] FRAC_255 = 23'b11111110000000000000000;

    localparam bit [7:0] EXP_MIN = 8'd103;

    localparam uint TIMEOUT = 1000;

    localparam real ERR_TOL = 1e-6;

    //=============================================================
    //                            FUNCTION
    //=============================================================

    function automatic shortreal fp2r(fp32_t x);
        return $bitstoshortreal(x);
    endfunction

    // in_valid cycle i carries token i / 4, dim i % 4, same as the PATTERN driver
    function automatic mat16x4_t pack_16x4(logic [31:0] a[64]);
        mat16x4_t m;
        for(int i = 0; i < 64; i++) m[i/4][i%4] = $bitstoshortreal(a[i]);
        return m;
    endfunction

    // out_weight of the first 16 in_valid cycles
    function automatic mat4x4_t pack_4x4(logic [31:0] a[16]);
        mat4x4_t m;
        for(int i = 0; i < 16; i++) m[i/4][i%4] = $bitstoshortreal(a[i]);
        return m;
    endfunction

endpackage