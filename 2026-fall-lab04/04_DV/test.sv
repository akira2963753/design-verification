/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    test.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       test
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

`include "env.sv"

program automatic test(vif tb_if);

    //=============================================================
    //                         CONFIGURATION
    //=============================================================

    uint pat_num = 500;         // patterns, +PAT_NUM=<n>
    uint mbx_size = 20;         // bounded gen2drv depth

    env e;

    //=============================================================
    //                           MAIN FLOW
    //=============================================================

    initial begin : MAIN_FLOW
        void'($value$plusargs("PAT_NUM=%d", pat_num));
        e = new(tb_if, pat_num, mbx_size);

        $display("=============================================================");
        $display("                F_ATTN Environment Started");
        $display("Patterns = %0d, mailbox = %0d", pat_num, mbx_size);
        $display("=============================================================");

        e.run();
        e.report();

        $display("=============================================================");
        $display("                F_ATTN Environment Completed");
        $display("                Congratulations! All Pass");
        $display("=============================================================");
        $finish;
    end

endprogram
