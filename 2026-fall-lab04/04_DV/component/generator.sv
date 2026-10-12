/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    generator.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       generator
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

class generator;

    //=============================================================
    //                          CONSTRUCTOR
    //=============================================================

    uint pat_num;
    mailbox #(txn) gen2drv;

    function new(
        input uint pat_num,
        input mailbox #(txn) gen2drv
    );
        this.pat_num = pat_num;
        this.gen2drv = gen2drv;
    endfunction


    //=============================================================
    //                          MAIN RUN
    //=============================================================

    task run();
        txn t;
        for(int i = 0; i < pat_num; i++) begin
            t = new();
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