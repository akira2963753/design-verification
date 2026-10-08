/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    driver.sv
* Project:      2026 FALL NYCU IC LAB, LAB02
* Module:       driver
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/


class driver;

    //=============================================================
    //                          Variable
    //=============================================================

    virtual vif.drv vif;
    uint pat_num;
    uint time_out;
    mailbox #(txn) gen2drv;

    //=============================================================
    //                         Constructor
    //=============================================================

    function new (
        virtual vif.drv vif,
        uint pat_num,
        uint time_out,
        mailbox #(txn) gen2drv
    );
        this.vif = vif;
        this.pat_num = pat_num;
        this.time_out = time_out;
        this.gen2drv = gen2drv;
    endfunction

    //=============================================================
    //                           Task
    //=============================================================
    task drive_idle();
        vif.drv_cb.in_mode_valid <= 1'b0;
        vif.drv_cb.in_mode <= 1'b0;
        vif.drv_cb.in_data_valid <= 1'b0;
        vif.drv_cb.in_data <= 'd0;
    endtask

    task drive_input(txn t);
        vif.drv_cb.in_mode_valid <= 1'b1;
        vif.drv_cb.in_mode <= t.mode;
        @(vif.drv_cb);
        drive_idle();
        repeat(t.in_lat) @(vif.drv_cb);
        vif.drv_cb.in_data_valid <= 1'b1;
        foreach(t.lch[i]) begin 
            vif.drv_cb.in_data <= t.lch[i];
            @(vif.drv_cb);
        end
        drive_idle();
    endtask

    task wait_output(txn t, uint idx);
        uint cnt = 0;
        while(!vif.drv_cb.out_valid) begin
            if(cnt >= time_out) begin
                $display("=============================================================");
                $display("[DRV] Pattern [%0d] no out_valid assertion after %0d cycles", idx, time_out);
                $display("=============================================================");
                $fatal(1);
            end
            cnt++;
            @(vif.drv_cb);
        end
        @(vif.drv_cb iff vif.drv_cb.out_valid !== 1'b1);
        repeat(t.next_lat) @(vif.drv_cb);
    endtask
 
    //=============================================================
    //                          Main Run
    //=============================================================
    
    task run();
        txn t;
        @(vif.drv_cb);  // align to the clocking event before the first drive
        for(int i = 0; i < pat_num; i++) begin
            gen2drv.get(t);
            drive_input(t);
            wait_output(t, i);
        end
    endtask 

endclass