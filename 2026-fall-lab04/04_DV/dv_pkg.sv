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
    //                          PARAMETER
    //=============================================================
    
    localparam bit [7:0] EXP_0P5 = 8'b01111110;
    localparam bit [7:0] EXP_255 = 8'b10000110;

    localparam bit [22:0] FRAC_0P5 = 23'b00000000000000000000000;
    localparam bit [22:0] FRAC_255 = 23'b11111110000000000000000;

    localparam bit [7:0] EXP_MIN = 8'd103;

    //=============================================================
    //                          TYPE DEFINE
    //=============================================================
    
    typedef struct packed {
        bit sign;
        bit [7:0] exp;
        bit [22:0] frac;
    } fp32_t;

    type unsigned int uint;


    //=============================================================
    //                            FUNCTION
    //=============================================================

    function automatic shortreal fp2r(fp32_t x);
        return $bitstoshortreal(x);
    endfunction

endpackage