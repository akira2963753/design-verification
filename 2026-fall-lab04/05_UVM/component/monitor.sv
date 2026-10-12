/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    monitor.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       monitor
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

class monitor extends uvm_monitor;

    `uvm_component_utils(monitor)

    virtual vif.mon vif;

    // Broadcast, any number of subscribers (scoreboard, coverage) connect without changing the monitor
    uvm_analysis_port #(mon_txn) ap;

    //=============================================================
    //                          CONSTRUCTOR
    //=============================================================

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    //=============================================================
    //                             PHASE
    //=============================================================

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if(!uvm_config_db #(virtual vif.mon)::get(this, "", "vif", vif))
            `uvm_fatal("MON", "Cannot get virtual vif.mon from uvm_config_db")
    endfunction

    // Passive: one mon_txn per pattern, runs until the run phase ends
    virtual task run_phase(uvm_phase phase);
        mon_txn t;
        forever begin
            @(vif.mon_cb iff (vif.mon_cb.in_valid === 1'b1));
            t = mon_txn::type_id::create("t");
            collect_in(t);
            collect_out(t);
            ap.write(t);                        // replaces mon2scb.put(t)
        end
    endtask

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

endclass
