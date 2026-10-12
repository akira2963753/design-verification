/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    generator.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       generator
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

import dv_pkg::*;

class generator;

    //=============================================================
    //                          CONSTRUCTOR
    //=============================================================

    uint pat_num;
    mailbox #(txn) gen2drv;
    txn blueprint;

    function new(
        uint pat_num,
        mailbox #(txn) gen2drv
    );
        this.pat_num = pat_num;
        this.gen2drv = gen2drv;
        this.blueprint = new();
    endfunction


    //=============================================================
    //                          MAIN RUN
    //=============================================================

    task run();
        txn t;
        for(int i = 0; i < pat_num; i++) begin
            // A new object every pattern, the mailbox keeps handles, not values
            t = blueprint.copy();
            if(!t.randomize()) begin
                $display("=============================================================");
                $display("          [GEN] Randomize failed at pattern %0d", i);
                $display("=============================================================");
                $fatal(1);
            end
            gen2drv.put(t);
        end
    endtask



endclass