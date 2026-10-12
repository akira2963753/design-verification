/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    scoreboard.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       scoreboard
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

class scoreboard extends uvm_scoreboard;

    `uvm_component_utils(scoreboard)

    // ap.write(t) in the monitor calls write(t) below directly, no mailbox and no run loop
    uvm_analysis_imp #(mon_txn, scoreboard) imp;

    uint pat_num;           // expected patterns, from uvm_config_db

    // Same layout as PATTERN, row = token, column = dim
    mat16x4_t q;
    mat16x4_t k;
    mat16x4_t v;
    mat4x4_t w;
    real golden [64];

    // Statistics
    uint pat_cnt;
    uint fail_cnt;
    uint total_lat;
    uint max_lat;
    real max_err;

    //=============================================================
    //                          CONSTRUCTOR
    //=============================================================

    function new(string name, uvm_component parent);
        super.new(name, parent);
        pat_cnt = 0;
        fail_cnt = 0;
        total_lat = 0;
        max_lat = 0;
        max_err = 0.0;
    endfunction

    //=============================================================
    //                             PHASE
    //=============================================================

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        imp = new("imp", this);
        if(!uvm_config_db #(uint)::get(this, "", "pat_num", pat_num))
            `uvm_fatal("SCB", "Cannot get pat_num from uvm_config_db")
    endfunction

    // Runs after the run phase, catches patterns lost between the driver and the scoreboard
    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if(pat_cnt != pat_num)
            `uvm_error("SCB", $sformatf("Scoreboard checked %0d patterns, expected %0d", pat_cnt, pat_num))
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCB", $sformatf("\n%s\n%s\n%s\nPass patterns = %0d, fail patterns = %0d\nLatency: total = %0d, max = %0d, avg = %.2f cycles\nMax error = %.3e (tolerance %.0e)\n%s",
            "=============================================================",
            "                     Scoreboard Summary",
            "=============================================================",
            pat_cnt - fail_cnt, fail_cnt,
            total_lat, max_lat, (pat_cnt == 0)? 0.0 : real'(total_lat) / pat_cnt,
            max_err, ERR_TOL,
            "============================================================="), UVM_NONE)
    endfunction

    //=============================================================
    //                         WRITE FUNCTION
    //=============================================================

    // Called by the analysis port in zero time, so it is a function, not a task
    virtual function void write(mon_txn t);
        q = pack_16x4(t.q);
        k = pack_16x4(t.k);
        v = pack_16x4(t.v);
        w = pack_4x4(t.w);
        ref_model();

        if(check_out(t)) begin
            `uvm_info("SCB", $sformatf("[PATTERN %0d] PASS, latency = %0d", pat_cnt, t.lat), UVM_MEDIUM)
        end
        else begin
            // Dump the 1st failed pattern only, it is usually the root cause
            if(fail_cnt == 0) begin
                dump_pattern(t);
                `uvm_info("SCB", "Pattern written to fail_input.txt (TA input.txt format)", UVM_NONE)
            end
            fail_cnt++;
        end

        // Statistics
        total_lat += t.lat;
        if(t.lat > max_lat) max_lat = t.lat;
        pat_cnt++;
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

    // 64 outputs in raster order, reports the 1st mismatch of the pattern, 1 = pass
    // Not named check(), uvm_component keeps a deprecated check() for OVM
    function bit check_out(mon_txn t);
        real dut, err;

        for(int i = 0; i < 64; i++) begin

            if($isunknown(t.out[i])) begin
                `uvm_error("SCB", $sformatf("[SPEC-2 FAILED] Your output data is unknown, Pattern NO.%0d, Output NO.%0d (token %0d, dim %0d)",
                    pat_cnt, i, i / 4, i % 4))
                return 1'b0;
            end

            dut = $bitstoshortreal(t.out[i]);
            err = dut - golden[i];
            if(err < 0) err = -err; // turn to positive

            if(err >= ERR_TOL) begin
                `uvm_error("SCB", $sformatf("[SPEC-2 FAILED] Pattern NO.%0d, Output NO.%0d (token %0d, dim %0d)\n    Golden: %.10e\n    Yours : %.10e (32'h%08h)\n    Error : %.3e (tolerance %.0e)",
                    pat_cnt, i, i / 4, i % 4, golden[i], dut, t.out[i], err, ERR_TOL))
                return 1'b0;
            end

            if(err > max_err) max_err = err;
        end

        return 1'b1;
    endfunction

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

endclass
