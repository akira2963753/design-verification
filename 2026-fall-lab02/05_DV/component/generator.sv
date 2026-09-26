/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    generator.sv
* Project:      2026 FALL NYCU IC LAB, LAB02
* Module:       generator
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/


class generator;

    //=============================================================
    //                          Variable
    //=============================================================
    uint pat_num;
    mailbox #(txn) gen2drv;

    //=============================================================
    //                          Constructor
    //=============================================================
    function new(
        uint pat_num,
        mailbox #(txn) gen2drv,
        string path = "G_128_64.txt"
    );
        this.pat_num = pat_num;
        this.gen2drv = gen2drv;
        txn::load_G(path);
    endfunction

    //=============================================================
    //                          Main Run
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
            gen2drv.put(t); // put the txn into gen2drv mailbox
        end
    endtask
endclass