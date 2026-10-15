/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    scoreboard.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       scoreboard
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

import dv_pkg::*;

class scoreboard;

    //=============================================================
    //                          CONSTRUCTOR
    //=============================================================

    mailbox #(mon_txn) mon2scb;

    // Same layout as PATTERN, row = token, column = dim
    mat16x4_t q;
    mat16x4_t k;
    mat16x4_t v;
    mat4x4_t w;
    real golden [64];

    // Statistics
    uint pat_cnt;
    uint total_lat;
    uint max_lat;
    real max_err;

    function new(
        mailbox #(mon_txn) mon2scb
    );
        this.mon2scb = mon2scb;
        this.pat_cnt = 0;
        this.total_lat = 0;
        this.max_lat = 0;
        this.max_err = 0.0;
    endfunction

    //=============================================================
    //                       REFERENCE MODEL
    //=============================================================

    // Standard (non-tiled) multi-head attention in double precision
    function void ref_model();

        real s [16];        // one row temp of scores
        real head [16][4];  // concat of head 1 (dim 0,1) and head 2 (dim 2,3)
        real SQRT2 = $bitstoshortreal(32'h3FB504F3);
        real mx, sum, acc;

        for(int h = 0; h < 2; h++) begin: head_loop
            for(int i = 0; i < 16; i++) begin: q_row_loop

                mx = -1.0e300; // init the row max to a very small number
                sum = 0.0;

                // Calculate the attention score
                for(int j = 0; j < 16; j++) begin
                    s[j] = (q[i][2*h] * k[j][2*h] + q[i][2*h+1] * k[j][2*h+1]) / SQRT2;
                    if(s[j] > mx) mx = s[j];
                end

                // Calculate the two parts of softmax
                for(int j = 0; j < 16; j++) begin
                    s[j] = $exp(s[j] - mx);
                    sum += s[j];
                end

                // Add V
                for(int d = 0; d < 2; d++) begin: v_col_loop
                    acc = 0.0;

                    // accumulate
                    for(int j = 0; j < 16; j++) acc += s[j] * v[j][2*h+d];
                    head[i][2*h+d] = acc / sum;
                end

            end
        end

        for(int t = 0; t < 16; t++) begin: head_row_loop
            for(int o = 0; o < 4; o++) begin: head_col_loop
                acc = 0.0;

                // accumulate
                for(int c = 0; c < 4; c++) acc += head[t][c] * w[o][c];
                golden[t*4+o] = acc;
            end
        end

    endfunction

    //=============================================================
    //                         CHECK FUNCTION
    //=============================================================

    // Write the failed pattern in TA input.txt format for replay
    function void dump_pattern(mon_txn t);
        int fd;
        fd = $fopen("fail_input.txt", "w");
        $fdisplay(fd, "1");
        for(int i = 0; i < 64; i++) begin
            if(i < 16) $fdisplay(fd, "%h %h %h %h", t.q[i], t.k[i], t.v[i], t.w[i]);
            else $fdisplay(fd, "%h %h %h", t.q[i], t.k[i], t.v[i]);
        end
        $fclose(fd);
    endfunction

    // 64 outputs in raster order
    function void check(mon_txn t);
        real dut, err;

        for(int i = 0; i < 64; i++) begin

            if($isunknown(t.out[i])) begin
                $display("=============================================================");
                $display("          [SPEC-2 FAILED] Your output data is unknown        ");
                $display("    Pattern NO.%0d, Output NO.%0d (token %0d, dim %0d)", pat_cnt, i, i / 4, i % 4);
                $display("=============================================================");
                dump_pattern(t);
                $display("Pattern written to fail_input.txt (TA input.txt format)");
                $fatal(1);
            end

            dut = $bitstoshortreal(t.out[i]);
            err = dut - golden[i];
            if(err < 0) err = -err; // turn to positive

            if(err >= ERR_TOL) begin
                $display("=============================================================");
                $display("                    [SPEC-2 FAILED]                          ");
                $display("    Pattern NO.%0d, Output NO.%0d (token %0d, dim %0d)", pat_cnt, i, i / 4, i % 4);
                $display("    Golden: %.10e", golden[i]);
                $display("    Yours : %.10e (32'h%08h)", dut, t.out[i]);
                $display("    Error : %.3e (tolerance %.0e)", err, ERR_TOL);
                $display("=============================================================");
                dump_pattern(t);
                $display("Pattern written to fail_input.txt (TA input.txt format)");
                $fatal(1);
            end

            if(err > max_err) max_err = err;
        end

        // Statistics
        total_lat += t.lat;
        if(t.lat > max_lat) max_lat = t.lat;
    endfunction

    function void report();
        $display("=============================================================");
        $display("                     Scoreboard Summary");
        $display("=============================================================");
        $display("Pass patterns = %0d", pat_cnt);
        $display("Latency: total = %0d, max = %0d, avg = %.2f cycles", total_lat, max_lat, (pat_cnt == 0)? 0.0 : real'(total_lat) / pat_cnt);
        $display("Max error = %.3e (tolerance %.0e)", max_err, ERR_TOL);
        $display("=============================================================");
    endfunction

    //=============================================================
    //                           MAIN FLOW
    //=============================================================

    task run();
        mon_txn t;
        forever begin
            mon2scb.get(t);
            q = pack_16x4(t.q);
            k = pack_16x4(t.k);
            v = pack_16x4(t.v);
            w = pack_4x4(t.w);
            ref_model();
            check(t);
            $display(" [PATTERN %0d] PASS, latency = %0d", pat_cnt, t.lat);
            pat_cnt++;
        end
    endtask

endclass
