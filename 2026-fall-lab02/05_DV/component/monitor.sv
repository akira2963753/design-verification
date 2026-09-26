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

    //=============================================================
    //                          Variable
    //=============================================================

    virtual vif.mon vif;
    uint pat_num;
    mailbox #(mon_txn) mon2scb;

    //=============================================================
    //                         Constructor
    //=============================================================

    function new(
        virtual vif.mon vif,
        uint pat_num,
        mailbox #(mon_txn) mon2scb
    );
        this.vif = vif;
        this.pat_num = pat_num;
        this.mon2scb = mon2scb;
    endfunction

    //=============================================================
    //                            Task
    //=============================================================

    task collect(output mon_txn t);
        int lat_cnt = 1;
        
        t = new();
        // @(vif.mon_cb);
        @(vif.mon_cb iff vif.mon_cb.in_mode_valid === 1'b1);
        t.mode = vif.mon_cb.in_mode;
        @(vif.mon_cb iff vif.mon_cb.in_data_valid === 1'b1);

        // Sample dut iuput data
        for(int i = 0; i < 128; i++) begin
            t.lch[i] = vif.mon_cb.in_data;
            @(vif.mon_cb);
        end

        while(vif.mon_cb.out_valid !== 1) begin
            @(vif.mon_cb);
            lat_cnt++;
        end

        // Sample dut ouput data
        t.run_lat = lat_cnt;
        for(int i = 0; i < 128; i++) begin
            t.app[i] = vif.mon_cb.out_data;
            t.warn[i] = vif.mon_cb.out_warn;
            @(vif.mon_cb);            
        end

    endtask

    //=============================================================
    //                           Main Run
    //=============================================================
    
    task run();
        mon_txn t;

        for(int i = 0; i < pat_num; i++) begin
            collect(t);
            mon2scb.put(t);
        end

    endtask

endclass