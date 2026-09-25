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

    uint pattern_num;
    uint timeout;  // hang guard in cycles, not the spec latency check
    virtual vif.DRV vif;
    mailbox #(trans) gen2drv;

    function new(virtual vif.DRV vif, mailbox #(trans) gen2drv, uint pattern_num, uint timeout = 1000);
        this.vif = vif;
        this.gen2drv = gen2drv;
        this.pattern_num = pattern_num;
        this.timeout = timeout;
    endfunction

    // Idle: all inputs 0 while their valid is low
    task drive_idle();
        vif.drv_cb.in_mode_valid <= 1'b0;
        vif.drv_cb.in_mode <= 1'b0;
        vif.drv_cb.in_data_valid <= 1'b0;
        vif.drv_cb.in_data <= '0;
    endtask

    // in_mode_valid 1 cycle -> in_lat idle cycles -> in_data_valid 128 cycles
    task drive_input(trans txn);
        vif.drv_cb.in_mode_valid <= 1'b1;
        vif.drv_cb.in_mode <= txn.mode;
        @(vif.drv_cb);
        drive_idle();
        repeat(txn.in_lat) @(vif.drv_cb);
        foreach(txn.lch[i]) begin
            vif.drv_cb.in_data_valid <= 1'b1;
            vif.drv_cb.in_data <= txn.lch[i];
            @(vif.drv_cb);
        end
        drive_idle();
    endtask

    // Wait for the whole out_valid period, then next_lat idle cycles
    task wait_output(trans txn, int idx);
        uint cnt = 0;
        while(vif.drv_cb.out_valid !== 1'b1) begin
            if(cnt >= timeout) $fatal(1, "[DRV] pattern %0d: no out_valid after %0d cycles", idx, timeout);
            cnt++;
            @(vif.drv_cb);
        end
        while(vif.drv_cb.out_valid === 1'b1) @(vif.drv_cb);
        repeat(txn.next_lat) @(vif.drv_cb);
    endtask

    task run();
        trans txn;
        drive_idle();  // reset is done by PATTERN drive_reset
        repeat(2) @(vif.drv_cb);
        for(int i = 0; i < pattern_num; i++) begin
            gen2drv.get(txn);
            drive_input(txn);
            wait_output(txn, i);
        end
    endtask

endclass
