/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    monitor.sv
* Project:      2026 FALL NYCU IC LAB, LAB02
* Module:       monitor
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

class monitor;
    virtual vif.MON mon_if;

    mailbox #(mon_txn) mon2scb;

    uint pattern_num;
    uint sampled_num;

    //=============================================================
    //                         Constructor
    //=============================================================

    function new(
        input virtual vif.MON mon_if,
        input mailbox #(mon_txn) mon2scb,
        input uint pattern_num
    );
        this.mon_if = mon_if;
        this.mon2scb = mon2scb;
        this.pattern_num = pattern_num;
        this.sampled_num = 0;
    endfunction

    //=============================================================
    //                      Pattern Collector
    //=============================================================

    // in_mode_valid -> 128 in_data_valid -> latency -> out_valid period
    task collect(output mon_txn tr);
        int k;

        tr = new();
        tr.testcase = sampled_num;

        do @(mon_if.mon_cb); while(mon_if.mon_cb.in_mode_valid !== 1'b1);
        tr.mode = mon_if.mon_cb.in_mode;

        k = 0;
        while(k < 128) begin
            @(mon_if.mon_cb);
            if(mon_if.mon_cb.in_data_valid === 1'b1) begin
                tr.lch[k] = mon_if.mon_cb.in_data;
                k++;
            end
        end

        // Latency is kept for statistics, the spec limit is SVA in PATTERN
        tr.latency = 0;
        do begin
            @(mon_if.mon_cb);
            tr.latency++;
        end while(mon_if.mon_cb.out_valid !== 1'b1);

        // 128 cycles from the first out_valid, the length rule is SVA in PATTERN
        for(int i = 0; i < 128; i++) begin
            tr.app[i] = mon_if.mon_cb.out_data;
            tr.warn[i] = mon_if.mon_cb.out_warn;
            @(mon_if.mon_cb);
        end
    endtask

    //=============================================================
    //                           Main Run
    //=============================================================

    task run();
        mon_txn tr;

        while(sampled_num < pattern_num) begin
            collect(tr);
            mon2scb.put(tr);
            sampled_num++;
        end
    endtask
endclass
