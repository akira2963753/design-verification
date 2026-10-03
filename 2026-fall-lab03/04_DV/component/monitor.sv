/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    monitor.sv
* Project:      2026 FALL NYCU IC LAB, LAB03
* Module:       monitor
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

class monitor;

    //=============================================================
    //                          Variable
    //=============================================================

    virtual vif.mon vif;
    mailbox #(mon_txn) mon2scb;

    //=============================================================
    //                         Constructor
    //=============================================================

    function new(
        virtual vif.mon vif,
        mailbox #(mon_txn) mon2scb
    );
        this.vif = vif;
        this.mon2scb = mon2scb;
    endfunction

    //=============================================================
    //                            Task
    //=============================================================

    // Called at the 1st sample with in_valid high
    task collect_load(mon_txn t);
        t.kind = MON_LOAD;
        t.ring_len = vif.mon_cb.ring_len;
        while(vif.mon_cb.in_valid === 1'b1) begin
            t.ring.push_back(vif.mon_cb.in_color);
            @(vif.mon_cb);
        end
    endtask

    // Called at the sample with shot_valid high, returns after the whole out_valid burst
    task collect_shot(mon_txn t);
        t.kind = MON_SHOT;
        t.shot_color = vif.mon_cb.shot_color;
        t.shot_pos = vif.mon_cb.shot_pos;
        t.lat = 0;

        // This negedge already shows the output of the posedge taking shot_valid
        while(vif.mon_cb.out_valid !== 1'b1) begin
            @(vif.mon_cb);
            t.lat++;
        end

        // Sample dut output, one level per cycle
        while(vif.mon_cb.out_valid === 1'b1) begin
            t.chain_num.push_back(vif.mon_cb.chain_num);
            t.elim_color.push_back(vif.mon_cb.elim_color);
            t.elim_cnt.push_back(vif.mon_cb.elim_cnt);
            @(vif.mon_cb);
            t.lat++;
        end
    endtask

    //=============================================================
    //                           Main Run
    //=============================================================

    // Passive: one mon_txn per loading phase and per shot, the env stops it at the end
    task run();
        mon_txn t;
        forever begin
            @(vif.mon_cb iff (vif.mon_cb.in_valid === 1'b1 || vif.mon_cb.shot_valid === 1'b1));
            t = new();
            if(vif.mon_cb.in_valid === 1'b1) collect_load(t);
            else collect_shot(t);
            mon2scb.put(t);
        end
    endtask

endclass
