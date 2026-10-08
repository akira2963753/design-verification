/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    driver.sv
* Project:      2026 FALL NYCU IC LAB, LAB01
* Module:       OISS Driver
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

class driver;
    virtual vif.driver_mp drv_if;
    mailbox #(txn) gen2drv;
    mailbox #(txn) drv2cov;
    int unsigned pattern_num;

    //=============================================================
    //                         Constructor
    //=============================================================

    function new(
        input virtual vif.driver_mp drv_if,
        input mailbox #(txn) gen2drv,
        input mailbox #(txn) drv2cov,
        input int unsigned pattern_num
    );

        this.drv_if = drv_if;
        this.gen2drv = gen2drv;
        this.drv2cov = drv2cov;
        this.pattern_num = pattern_num;
    endfunction

    //=============================================================
    //                      Transaction Drive
    //=============================================================

    // Called by run() at the driver clocking event; do not wait another edge.
    local task drive_one(input txn tr);
        drv_if.driver_cb.Inst_seq_I <= tr.inst_seq;
        drv_if.driver_cb.Inst_latency_I <= tr.inst_lat;
        drv_if.driver_cb.sample_valid <= 1'b1;
    endtask

    //=============================================================
    //                           Main Run
    //=============================================================

    task run();
        txn tr;
        int unsigned sent_num;

        sent_num = 0;
        while(sent_num < pattern_num) begin
            @(drv_if.driver_cb);
            if(gen2drv.try_get(tr) != 0) begin
                drive_one(tr);
                // Coverage only reads this handle; generator creates a new txn
                // for every pattern.
                drv2cov.put(tr);
                sent_num++;
            end
            else drv_if.driver_cb.sample_valid <= 1'b0;
        end

        // The monitor samples the last valid transaction before this clear.
        @(drv_if.driver_cb);
        drv_if.driver_cb.sample_valid <= 1'b0;
    endtask
endclass
