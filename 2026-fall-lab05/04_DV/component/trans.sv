/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    trans.sv
* Project:      2026 FALL NYCU IC LAB, LAB05
* Module:       transaction
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

import dv_pkg::*;

class txn;

    //=============================================================
    //                       RANDOM VARIABLE
    //=============================================================

    rand img_e kind;
    rand bit [7:0] base;    // background level (IMG_SMOOTH / IMG_SPARSE)
    rand int gx, gy;        // gradient step per pixel (IMG_SMOOTH)
    rand int noise;         // noise amplitude (IMG_SMOOTH)

    bit [7:0] pix [16384];  // raster order, filled in post_randomize()
                            // IMG_SPARSE draws its basis pattern with dv_pkg::C_TAB

    //=============================================================
    //                         CONSTRAINT
    //=============================================================

    // SMOOTH 40% : most common case, like a real photo
    // NOISE  30% : longest bitstream and latency, no EOB in many blocks
    // SPARSE 20% : ZRL and long runs, rare in the other types
    // EXTREME 10%: DC corner cases, a few images are enough
    constraint c_kind {
        kind dist {
            IMG_SMOOTH  := 4,
            IMG_NOISE   := 3,
            IMG_SPARSE  := 2,
            IMG_EXTREME := 1
        };
    }

    constraint c_param {
        gx inside {[-2 : 2]};
        gy inside {[-2 : 2]};
        noise inside {[1 : 16]};
    }

    //=============================================================
    //                        PIXEL GENERATE
    //=============================================================

    // pixels are built here instead of by the solver, 16384 rand elements are slow to solve
    function void post_randomize();
        int u, v, amp;

        case(kind)
            IMG_NOISE: begin
                foreach(pix[i]) pix[i] = $urandom_range(0, 255);
            end
            IMG_SMOOTH: begin
                foreach(pix[i]) pix[i] = clip(base + gx * (i % 128) + gy * (i / 128) + int'($urandom_range(0, 2 * noise)) - noise);
            end
            IMG_SPARSE: begin
                for(int b = 0; b < 256; b++) begin
                    u = $urandom_range(0, 7);
                    v = $urandom_range(0, 7);
                    amp = $urandom_range(16, 80);
                    for(int y = 0; y < 8; y++) begin
                        for(int x = 0; x < 8; x++) begin
                            pix[idx(b, x, y)] = clip(base + amp * C_TAB[u][x] * C_TAB[v][y] / (251 * 251));
                        end
                    end
                end
            end
            IMG_EXTREME: begin
                for(int b = 0; b < 256; b++) begin
                    amp = ($urandom_range(0, 1))? 255 : 0;
                    for(int y = 0; y < 8; y++) begin
                        for(int x = 0; x < 8; x++) pix[idx(b, x, y)] = amp;
                    end
                end
            end
        endcase
    endfunction

    // raster index of pixel (x, y) in block b, b = 16 * by + bx
    function int idx(int b, int x, int y);
        return 128 * (8 * (b / 16) + y) + 8 * (b % 16) + x;
    endfunction

    function bit [7:0] clip(int v);
        return (v < 0)? 8'd0 : (v > 255)? 8'd255 : v[7:0];
    endfunction

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
        t.kind = kind;
        t.base = base;
        t.gx = gx;
        t.gy = gy;
        t.noise = noise;
        t.pix = pix;
        return t;
    endfunction

endclass

//=============================================================
//                    DIRECTED TRANSACTION
//=============================================================

// Fixes the image type, the other knobs stay random
class kind_txn extends txn;
    img_e want;

    constraint c_want {
        kind == want;
    }

    function new(img_e want = IMG_NOISE);
        this.want = want;
    endfunction

    virtual function txn create();
        kind_txn t = new(want);
        return t;
    endfunction

endclass

// Reads one image per randomize() from input.txt (16384 hex pixels), the test opens the file
class file_txn extends txn;
    static int fd;      // shared by every copy, each pattern continues from the last one

    function new();
        rand_mode(0);           // close the randomization
        constraint_mode(0);     // close the constraint checks, file data may be outside them
    endfunction

    function void post_randomize();
        for(int i = 0; i < 16384; i++) begin
            if($fscanf(fd, "%h", pix[i]) != 1) begin
                $display("=============================================================");
                $display("      [GEN] Input file format mismatch / EOF at pixel %0d", i);
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

// Base type of the monitor to scoreboard stream, one mailbox keeps images and bytes in time order
class mon_txn;
endclass

// One whole image, put at the sample of the last pixel (the negedge pulling in_valid down)
class img_txn extends mon_txn;
    logic [7:0] pix [16384];    // in_data, raster order
endclass

// One output byte, put at every sample with out_valid high
class byte_txn extends mon_txn;
    logic [7:0] data;
    uint lat;                   // SPEC-3 latency of this byte, in_valid falling edge counted as cycle 1
endclass
