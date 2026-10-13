/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    env.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       environment
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

// Compile these definitions through test.sv -> env.sv only, not again in file.f.
`include "dv_pkg.sv"
// package dv_pkg [fp32_t, uint, mat16x4_t / mat4x4_t, TIMEOUT, ERR_TOL, pack_16x4 / pack_4x4]

`include "vif.sv"
// interface vif [clocking blocks, SVA]

`include "trans.sv"
// class txn [constraint-random Q / K / V / W], class mon_txn [sampled inputs and 64 outputs]

`include "generator.sv"
// input uint pat_num
// input mailbox #(txn) gen2drv [patterns to driver]

`include "driver.sv"
// input virtual vif.drv vif [driver interface]
// input uint pat_num
// input mailbox #(txn) gen2drv [patterns from generator]

`include "monitor.sv"
// input virtual vif.mon vif [monitor interface]
// input mailbox #(mon_txn) mon2scb [whole patterns to scoreboard]

`include "scoreboard.sv"
// input mailbox #(mon_txn) mon2scb [whole patterns from monitor]

import dv_pkg::*;

class env;

    //=============================================================
    //                          CONSTRUCTOR
    //=============================================================

    virtual vif vif;
    uint pat_num;

    mailbox #(txn) gen2drv;        // generator to driver, bounded
    mailbox #(mon_txn) mon2scb;    // monitor to scoreboard, unbounded so the monitor never blocks

    generator gen;
    driver drv;
    monitor mon;
    scoreboard scb;

    function new(
        virtual vif vif,
        uint pat_num,
        uint mbx_size
    );
        this.vif = vif;
        this.pat_num = pat_num;
        gen2drv = new(mbx_size);
        mon2scb = new();
        gen = new(pat_num, gen2drv);
        drv = new(vif, pat_num, gen2drv);
        mon = new(vif, mon2scb);
        scb = new(mon2scb);
    endfunction

    //=============================================================
    //                           MAIN FLOW
    //=============================================================

    // The monitor puts the last pattern at the negedge the driver sees out_valid low,
    // the driver still waits 1 ~ 3 negedges after it, so the scoreboard is done when drv.run() returns
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
        disable fork;   // stop the monitor and scoreboard loops
    endtask

    function void report();
        scb.report();
    endfunction

endclass
