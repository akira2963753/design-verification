/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    monitor.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       monitor
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

import dv_pkg::*;

class monitor;

    //=============================================================
    //                          CONSTRUCTOR
    //=============================================================

    virtual vif.mon vif;
    mailbox #(mon_txn) mon2scb;

    function new(
        virtual vif.mon vif,
        mailbox #(mon_txn) mon2scb
    );
        this.vif = vif;
        this.mon2scb = mon2scb;
    endfunction

    //=============================================================
    //                         COLLECT TASK
    //=============================================================

    // Called at the 1st sample with in_valid high, leaves at the 1st sample with in_valid low
    task collect_in(mon_txn t);
        for(int i = 0; i < 64; i++) begin
            t.q[i] = vif.mon_cb.Q;
            t.k[i] = vif.mon_cb.K;
            t.v[i] = vif.mon_cb.V;
            if(i < 16) t.w[i] = vif.mon_cb.out_weight;
            @(vif.mon_cb);
        end
    endtask

    // Leaves at the 1st negedge after out_valid pulled down
    task collect_out(mon_txn t);
        // mon_cb samples 1 cycle after the negedge pulling in_valid down, so lat starts at 1
        t.lat = 1;
        while(vif.mon_cb.out_valid !== 1'b1) begin
            @(vif.mon_cb);
            t.lat++;
        end

        for(int i = 0; i < 64; i++) begin
            t.out[i] = vif.mon_cb.out;
            @(vif.mon_cb);
        end
    endtask

    //=============================================================
    //                           MAIN FLOW
    //=============================================================

    // Passive: one mon_txn per pattern, the env stops it at the end
    task run();
        mon_txn t;
        forever begin
            @(vif.mon_cb iff (vif.mon_cb.in_valid === 1'b1));
            t = new();
            collect_in(t);
            collect_out(t);
            mon2scb.put(t);
        end
    endtask

endclass
