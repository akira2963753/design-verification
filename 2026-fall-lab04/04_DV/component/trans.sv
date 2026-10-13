/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    trans.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       transaction
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
    //                         CREATE & COPY
    //=============================================================

    // Every subclass overrides create() to build its own type, like the UVM factory
    virtual function txn create();
        txn t = new();
        return t;
    endfunction

    // create() picks the real type, so a copy of a subclass keeps its constraints
    function txn copy();
        txn t = create();
        t.q = q;
        t.k = k;
        t.v = v;
        t.w = w;
        return t;
    endfunction
    
endclass

//=============================================================
//                    DIRECTED TRANSACTION
//=============================================================

// Reads one pattern per randomize() from the TA input.txt format, the test opens the file
class file_txn extends txn;
    static int fd;      // shared by every copy, each pattern continues from the last one

    function new();
        rand_mode(0);           // close the randomization
        constraint_mode(0);     // close the constraint checks, file data may be outside them
    endfunction

    function void post_randomize();
        int n;
        for(int i = 0; i < 64; i++) begin
            if(i < 16) n = $fscanf(fd, "%h %h %h %h", q[i], k[i], v[i], w[i]);
            else n = $fscanf(fd, "%h %h %h", q[i], k[i], v[i]);

            if(n != ((i < 16)? 4 : 3)) begin
                $display("=============================================================");
                $display("      [GEN] Input file format mismatch / EOF at line %0d", i);
                $display("=============================================================");
                $fatal(1);
            end
        end
    endfunction

    virtual function txn create();
        file_txn t = new();
        return t;
    endfunction

endclass

//=============================================================
//                    MONITOR TRANSACTION
//=============================================================

class mon_txn;
    logic [31:0] q[64];     
    logic [31:0] k[64];
    logic [31:0] v[64];
    logic [31:0] w[16];    
    logic [31:0] out[64];   
    uint lat;
endclass