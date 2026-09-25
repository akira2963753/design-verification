/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    scoreboard.sv
* Project:      2026 FALL NYCU IC LAB, LAB02
* Module:       scoreboard
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

class scoreboard;
    mailbox #(mon_txn) mon2scb;
    ref_model rm;

    uint pattern_num;
    uint checked_num;
    uint max_latency;

    // Statistics: [mode][iterations 1..8, 9 = warn]
    uint iter_hist[2][10];
    uint total_latency;

    //=============================================================
    //                         Constructor
    //=============================================================

    function new(
        input mailbox #(mon_txn) mon2scb,
        input uint pattern_num
    );
        this.mon2scb = mon2scb;
        this.pattern_num = pattern_num;
        this.checked_num = 0;
        this.max_latency = 0;
        this.total_latency = 0;
        this.rm = new();
    endfunction

    //=============================================================
    //                       Diagnostic Output
    //=============================================================

    // Write the pattern in TA input.txt / output.txt format for replay
    local function void dump_pattern(
        input mon_txn tr,
        input bit signed [7:0] exp_app[128],
        input bit exp_warn
    );
        int fi, fo;

        fi = $fopen("fail_input.txt", "w");
        fo = $fopen("fail_output.txt", "w");
        $fdisplay(fi, "%0d", tr.mode);
        foreach(tr.lch[i]) $fwrite(fi, "%0d ", tr.lch[i]);
        $fdisplay(fi, "");
        $fdisplay(fo, "%0d", exp_warn);
        foreach(exp_app[i]) $fwrite(fo, "%0d ", exp_app[i]);
        $fdisplay(fo, "");
        $fclose(fi);
        $fclose(fo);
    endfunction

    local function void report_failure(
        input string reason,
        input mon_txn tr,
        input bit signed [7:0] exp_app[128],
        input bit exp_warn
    );
        int shown;

        $display("================================================================");
        $display("                  Scoreboard Check Failed ! ! !");
        $display("================================================================");
        $display("Reason: %s", reason);
        $display("TEST PATTERN [%0d], mode = %0d, latency = %0d", tr.testcase, tr.mode, tr.latency);
        $display("Golden warn = %0d, iterations = %0d, DUT warn = %0d", exp_warn, rm.iters, tr.warn[0]);
        shown = 0;
        foreach(exp_app[i]) begin
            if(tr.app[i] !== exp_app[i] && shown < 16) begin
                $display("    Lv[%3d]: golden = %4d, DUT = %4d", i, exp_app[i], tr.app[i]);
                shown++;
            end
        end
        dump_pattern(tr, exp_app, exp_warn);
        $display("Pattern written to fail_input.txt / fail_output.txt (TA format)");
        $fatal(1, "================================================================");
    endfunction

    //=============================================================
    //                       Transaction Check
    //=============================================================

    function void check_one(input mon_txn tr);
        bit signed [7:0] exp_app[128];
        bit signed [5:0] lch_in[128];
        bit exp_warn;

        // Protocol, length, latency and X/Z rules are SVA in PATTERN.sv
        // Bit-exact compare with the reference model
        foreach(lch_in[i]) lch_in[i] = tr.lch[i];
        rm.decode(tr.mode, lch_in, exp_app, exp_warn);
        if(tr.warn[0] !== exp_warn) report_failure("out_warn does not match the reference model", tr, exp_app, exp_warn);
        foreach(exp_app[i]) if(tr.app[i] !== exp_app[i]) report_failure("out_data does not match the reference model", tr, exp_app, exp_warn);

        iter_hist[tr.mode][(exp_warn)? 9 : rm.iters]++;
        total_latency += tr.latency;
        if(tr.latency > max_latency) max_latency = tr.latency;
    endfunction

    //=============================================================
    //                           Summary
    //=============================================================

    function void report();
        $display("================================================================");
        $display("                  Scoreboard Summary");
        $display("================================================================");
        $display("Checked patterns = %0d / %0d", checked_num, pattern_num);
        $display("Latency: max = %0d, avg = %.2f cycles", max_latency, (checked_num == 0)? 0.0 : real'(total_latency) / checked_num);
        for(int m = 0; m < 2; m++) begin
            $display("Mode %0d iterations 1..8 = %0d %0d %0d %0d %0d %0d %0d %0d | warn = %0d", m,
                iter_hist[m][1], iter_hist[m][2], iter_hist[m][3], iter_hist[m][4],
                iter_hist[m][5], iter_hist[m][6], iter_hist[m][7], iter_hist[m][8], iter_hist[m][9]);
        end
        $display("================================================================");
    endfunction

    //=============================================================
    //                           Main Run
    //=============================================================

    task run();
        mon_txn tr;

        checked_num = 0;
        repeat(pattern_num) begin
            mon2scb.get(tr);
            check_one(tr);
            checked_num++;
        end
    endtask
endclass