/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    monitor.sv
* Project:      2026 FALL NYCU IC LAB, LAB01
* Module:       OISS Monitor
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

class monitor;
    virtual vif.monitor_mp mon_if;
    mailbox #(mon_txn) mon2scb;
    coverage cov;
    int unsigned pattern_num;
    int unsigned sampled_num;

    //=============================================================
    //                         Constructor
    //=============================================================

    function new(
        input virtual vif.monitor_mp mon_if,
        input mailbox #(mon_txn) mon2scb,
        input int unsigned pattern_num
    );

        this.mon_if = mon_if;
        this.mon2scb = mon2scb;
        this.pattern_num = pattern_num;
        this.sampled_num = 0;
        cov = new();
    endfunction

    //=============================================================
    //                           Main Run
    //=============================================================

    // Start concurrently with the driver, before its first clocking event.
    // Use an unbounded mailbox so scoreboard work cannot stall sampling.
    task run();
        mon_txn tr;
        int unsigned received_num;

        received_num = 0;
        while(received_num < pattern_num) begin
            @(mon_if.monitor_cb);

            if($isunknown(mon_if.monitor_cb.sample_valid)) $fatal(1,
                {"================================================================\n",
                "                 Monitor Valid is X/Z ! ! !\n",
                "================================================================"});

            if(mon_if.monitor_cb.sample_valid === 1'b1) begin
                // All fields are the same pre-edge snapshot, including X/Z.
                tr = new();
                tr.testcase = sampled_num;
                tr.inst_seq = mon_if.monitor_cb.Inst_seq_I;
                tr.inst_lat = mon_if.monitor_cb.Inst_latency_I;
                tr.inst_order = mon_if.monitor_cb.Inst_order_O;
                tr.ex_cycle = mon_if.monitor_cb.Ex_cycle;

                // Count observed stimulus independently of scoreboard PASS/FAIL.
                // Direct calls leave the scoreboard mailbox's contents intact.
                cov.write(tr);

                // 這裡使用 try_put() 而非 put() 是因為怕漏掉 sample 而沒發現
                if(mon2scb.try_put(tr) == 0) $fatal(1,
                    {"================================================================\n",
                    "             Monitor Mailbox is Full ! ! !\n",
                    "================================================================"});

                sampled_num++;
                received_num++;
            end
        end
    endtask
endclass
