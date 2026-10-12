/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    trans.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       transcation
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

import dv_pkg::*;

class txn;

    rand fp32_t q [64];
    rand fp32_t k [64];
    rand fp32_t v [64];
    rand fp32_t w [16];

    // K Range = +/- 0.5 ~ 255.0
    constraint c_k {
        foreach(k[i]) {
            k[i].exp dist {
                EXP_0P5 :/ 35,
                [EXP_0P5+1 : EXP_255-1] :/ 30,
                EXP_255 :/ 35
            }; 
            
            if(k[i].exp == EXP_255) k[i].frac inside {[23'd0 : FRAC_255]};

        }
    }

    // Q, V, W Range = +/- 0 ~ 0.5  
    constraint c_qvw {
        foreach(q[i]) {
            q[i].exp inside {8'd0, [EXP_MIN : EXP_0P5]};
            if(q[i].exp == 8'd0) q[i].frac == 23'd0;
            if(q[i].exp == EXP_0P5) q[i].frac == FRAC_0P5;
        }
        foreach(v[i]) {
            v[i].exp inside {8'd0, [EXP_MIN : EXP_0P5]};
            if(v[i].exp == 8'd0) v[i].frac == 23'd0;
            if(v[i].exp == EXP_0P5) v[i].frac == FRAC_0P5;
        }
        foreach(w[i]) {
            w[i].exp inside {8'd0, [EXP_MIN : EXP_0P5]};
            if(w[i].exp == 8'd0) w[i].frac == 23'd0;
            if(w[i].exp == EXP_0P5) w[i].frac == FRAC_0P5;
        }
    }

    //=============================================================
    //                            PRINT
    //=============================================================

    function string mat2str(string name, fp32_t a[], int rows);
        string s;
        s = $sformatf("=========================== %s (%0dx4) ==================================\n", name, rows);

        for(int t = 0; t < rows; t++) begin
            s = {s, $sformatf("[%2d] ", t)};
            for(int d = 0; d < 4; d++) s = {s, $sformatf("%h(%11.4e) ", a[t*4 + d], fp2r(a[t*4 + d]))};
            s = {s, "\n"};
        end
        return s;
    endfunction

    function string convert2string();
        return {mat2str("Q", q, 16),
                mat2str("K", k, 16),
                mat2str("V", v, 16),
                mat2str("W", w, 4)};
    endfunction

endclass