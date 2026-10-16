/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    env.sv
* Project:      2026 FALL NYCU IC LAB, LAB05
* Module:       environment
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

// Compile these definitions through test.sv -> env.sv only, not again in file.f.
`include "dv_pkg.sv"
// package dv_pkg [uint, img_e, PIX_NUM, TIMEOUT, C / S / zigzag tables, round_s, Huffman tables, bit packing]

`include "vif.sv"
// interface vif [clocking blocks, SVA]

`include "trans.sv"
// class txn [image type + pixels], kind_txn [fixed image type], file_txn [input.txt]
// class mon_txn [base], img_txn [sampled image], byte_txn [one output byte + latency]

`include "generator.sv"
// input uint pat_num
// input mailbox #(txn) gen2drv [patterns to driver]

`include "driver.sv"
// input virtual vif.drv vif [driver interface]
// input uint pat_num
// input mailbox #(txn) gen2drv [patterns from generator]
// input mailbox #(uint) scb2drv [an image is fully checked, its latency]

`include "monitor.sv"
// input virtual vif.mon vif [monitor interface]
// input mailbox #(mon_txn) mon2scb [images and bytes to scoreboard, in time order]

`include "scoreboard.sv"
// input mailbox #(mon_txn) mon2scb [images and bytes from monitor]
// input mailbox #(uint) scb2drv [an image is fully checked, its latency]

import dv_pkg::*;

class env;

    //=============================================================
    //                          CONSTRUCTOR
    //=============================================================

    virtual vif vif;
    uint pat_num;

    mailbox #(txn) gen2drv;        // generator to driver, bounded
    mailbox #(mon_txn) mon2scb;    // monitor to scoreboard, unbounded so the monitor never blocks
    mailbox #(uint) scb2drv;       // scoreboard to driver, one message per image

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
        scb2drv = new();
        gen = new(pat_num, gen2drv);
        drv = new(vif, pat_num, gen2drv, scb2drv);
        mon = new(vif, mon2scb);
        scb = new(mon2scb, scb2drv);
    endfunction

    //=============================================================
    //                           MAIN FLOW
    //=============================================================

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
        // the driver returns 10 cycles after the last byte, every image is already checked
        disable fork;   // stop the monitor and scoreboard loops
    endtask

    function void report();
        scb.report();
    endfunction

endclass
