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

    uint pattern_num;
    mailbox #(trans) gen2drv;

    function new(mailbox #(trans) gen2drv, uint pattern_num, string g_path = "G_128_64.txt");
        this.gen2drv = gen2drv;
        this.pattern_num = pattern_num;
        trans::load_G(g_path);
    endfunction

    task run();
        trans txn;
        for(int i = 0; i < pattern_num; i++) begin
            txn = new();  // new object per pattern, the mailbox only passes the handle
            if(!txn.randomize()) $fatal(1, "[GEN] randomize failed at pattern %0d", i);
            gen2drv.put(txn);
        end
    endtask

endclass
