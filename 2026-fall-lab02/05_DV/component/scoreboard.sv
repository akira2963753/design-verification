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

    //=============================================================
    //                          Variable
    //=============================================================

    uint pat_num;
    uint pass_num;
    mailbox #(mon_txn) mon2scb;
    ref_model rm;

    // Statistics, iter_hist[mode][1..8], index 9 = warn
    uint iter_hist[2][10];
    uint max_lat;
    uint total_lat;

    //=============================================================
    //                         Constructor
    //=============================================================

    function new(
        uint pat_num,
        mailbox #(mon_txn) mon2scb
    );
        this.pat_num = pat_num;
        this.mon2scb = mon2scb;
        this.pass_num = 0;
        this.max_lat = 0;
        this.total_lat = 0;
        this.rm = new();
    endfunction

    //=============================================================
    //                          Function
    //=============================================================

    // Write the failed pattern in TA input.txt / output.txt format for replay
    function void dump_pattern(mon_txn t, bit signed [7:0] gold_app[128], bit gold_warn);
        int fi, fo;
        fi = $fopen("fail_input.txt", "w");
        fo = $fopen("fail_output.txt", "w");
        $fdisplay(fi, "%0d", t.mode);
        foreach(t.lch[i]) $fwrite(fi, "%0d ", t.lch[i]);
        $fdisplay(fi, "");
        $fdisplay(fo, "%0d", gold_warn);
        foreach(gold_app[i]) $fwrite(fo, "%0d ", gold_app[i]);
        $fdisplay(fo, "");
        $fclose(fi);
        $fclose(fo);
    endfunction

    function void report_fail(uint idx, string reason, mon_txn t, bit signed [7:0] gold_app[128], bit gold_warn);
        int shown = 0;
        $display("=============================================================");
        $display("           [SCB] Pattern [%0d] FAIL: %s", idx, reason);
        $display("=============================================================");
        $display("mode = %0d, latency = %0d, iterations = %0d", t.mode, t.run_lat, rm.iters);
        $display("Golden warn = %0d, DUT warn = %0d", gold_warn, t.warn[0]);
        foreach(gold_app[i]) begin
            if(t.app[i] !== gold_app[i] && shown < 16) begin
                $display("    Lv[%3d]: golden = %4d, DUT = %4d", i, gold_app[i], t.app[i]);
                shown++;
            end
        end
        dump_pattern(t, gold_app, gold_warn);
        $display("Pattern written to fail_input.txt / fail_output.txt (TA format)");
        $display("=============================================================");
        $fatal(1);
    endfunction

    // Bit-exact compare with the reference model
    // Protocol, latency and X/Z rules are checked by SVA
    function void check(uint idx, mon_txn t);
        bit signed [5:0] lch[128];
        bit signed [7:0] gold_app[128];
        bit gold_warn;

        foreach(lch[i]) lch[i] = t.lch[i];
        rm.decode(t.mode, lch, gold_app, gold_warn);

        foreach(t.warn[i]) if(t.warn[i] !== gold_warn) report_fail(idx, "out_warn mismatch", t, gold_app, gold_warn);
        foreach(t.app[i]) if(t.app[i] !== gold_app[i]) report_fail(idx, "out_data mismatch", t, gold_app, gold_warn);

        pass_num++;
        iter_hist[t.mode][(gold_warn)? 9 : rm.iters]++;
        total_lat += t.run_lat;
        if(t.run_lat > max_lat) max_lat = t.run_lat;
        $display("Pattern [%0d] PASS: mode = %0d, warn = %0d, iterations = %0d, latency = %0d", idx, t.mode, gold_warn, rm.iters, t.run_lat);
    endfunction

    function void report();
        $display("=============================================================");
        $display("                     Scoreboard Summary");
        $display("=============================================================");
        $display("Pass patterns = %0d / %0d", pass_num, pat_num);
        $display("Latency: max = %0d, avg = %.2f cycles", max_lat, (pass_num == 0)? 0.0 : real'(total_lat) / pass_num);
        for(int m = 0; m < 2; m++) begin
            $display("Mode %0d iterations 1..8 = %0d %0d %0d %0d %0d %0d %0d %0d | warn = %0d", m,
                iter_hist[m][1], iter_hist[m][2], iter_hist[m][3], iter_hist[m][4],
                iter_hist[m][5], iter_hist[m][6], iter_hist[m][7], iter_hist[m][8], iter_hist[m][9]);
        end
        $display("=============================================================");
    endfunction

    //=============================================================
    //                          Main Run
    //=============================================================

    task run();
        mon_txn t;
        for(int i = 0; i < pat_num; i++) begin
            mon2scb.get(t);
            check(i, t);
        end
    endtask

endclass
