/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    env.sv
* Project:      2026 FALL NYCU IC LAB, LAB03
* Module:       env
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

// Compile these definitions through test.sv -> env.sv only, not again in file.f.
`include "vif.sv"
// interface vif [clocking blocks, SVA for SPEC 4 / 5 / 6 / 7 / 9]

`include "trans.sv"
// class shot_txn [constraint-random shot], class txn [constraint-random game], class mon_txn [sampled load / shot]

`include "ref_model.sv"
// queue-based golden ring, shadow model of the generator and golden model of the scoreboard

`include "coverage.sv"
// covergroups of ring load / shot / cascade level, sampled by scoreboard

`include "generator.sv"
// input uint pat_num, kind_w[] [game kind weights]
// input mailbox #(txn) gen2drv [games with all shots to driver]

`include "driver.sv"
// input virtual vif.drv vif [driver interface]
// input uint pat_num, time_out
// input mailbox #(txn) gen2drv [games from generator]

`include "monitor.sv"
// input virtual vif.mon vif [monitor interface]
// input mailbox #(mon_txn) mon2scb [loads and whole out_valid bursts to scoreboard]

`include "scoreboard.sv"
// input mailbox #(mon_txn) mon2scb [loads and whole out_valid bursts from monitor]
// input coverage cov [sampled with the golden result]

class env;

    //=============================================================
    //                          Variable
    //=============================================================

    virtual vif vif;
    uint pat_num;

    mailbox #(txn) gen2drv;        // generator to driver, bounded
    mailbox #(mon_txn) mon2scb;    // monitor to scoreboard, unbounded so the monitor never blocks

    generator gen;
    driver drv;
    monitor mon;
    scoreboard scb;
    coverage cov;

    //=============================================================
    //                         Constructor
    //=============================================================

    function new(
        virtual vif vif,
        uint pat_num,
        uint mbx_size,
        uint time_out,
        uint kind_w[txn::N_KIND]
    );
        this.vif = vif;
        this.pat_num = pat_num;
        gen2drv = new(mbx_size);
        mon2scb = new();
        gen = new(pat_num, kind_w, gen2drv);
        drv = new(vif, pat_num, time_out, gen2drv);
        mon = new(vif, mon2scb);
        cov = new();
        scb = new(mon2scb, cov);
    endfunction

    //=============================================================
    //                            Task
    //=============================================================

    // The monitor puts the last burst at the negedge the driver sees out_valid low
    task drain();
        uint cnt = 0;
        while(scb.shot_num != drv.shot_num) begin
            if(cnt >= 10) begin
                $display("=============================================================");
                $display("[ENV] Scoreboard checked %0d shots, driver finished %0d", scb.shot_num, drv.shot_num);
                $display("=============================================================");
                $fatal(1);
            end
            cnt++;
            @(vif.mon_cb);
        end
    endtask

    task run();
        drv.reset();
        fork
            mon.run();
            scb.run();
        join_none
        fork
            gen.run();
            drv.run();
        join
        drain();
        disable fork;   // stop the monitor and scoreboard loops
    endtask

    function void report();
        gen.report();
        scb.report();
        cov.report();
    endfunction

endclass
