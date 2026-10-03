/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    test.sv
* Project:      2026 FALL NYCU IC LAB, LAB03
* Module:       test
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

`include "env.sv"

program automatic test(vif tb_if);

    //=============================================================
    //                       Configuration
    //=============================================================

    uint pat_num = 300;         // games, +PAT_NUM=<n>
    uint mbx_size = 20;         // bounded gen2drv depth
    uint time_out = 2000;       // driver hang guard in cycles, above the SPEC-7 limit 1000
    string name = "mix";        // +TEST=<mix | random | match | seam | grow | drain | cascade>
    uint kind_w[txn::N_KIND];   // game kind weights

    env e;

    //=============================================================
    //                          Function
    //=============================================================

    // mix: every kind, otherwise only the named kind
    function void set_kind_w();
        kind_t k;
        kind_w = '{2, 3, 2, 1, 1, 3};  // random, match, seam, grow, drain, cascade
        if(name == "mix") return;
        k = k.first();
        repeat(k.num()) begin
            if(k.name() == {"K_", name.toupper()}) begin
                kind_w = '{default: 0};
                kind_w[k] = 1;
                return;
            end
            k = k.next();
        end
        $display("=============================================================");
        $display("              [TEST] Unknown test name: %s", name);
        $display("=============================================================");
        $fatal(1);
    endfunction

    //=============================================================
    //                           Main Flow
    //=============================================================

    initial begin : MAIN_FLOW
        void'($value$plusargs("PAT_NUM=%d", pat_num));
        void'($value$plusargs("TEST=%s", name));
        set_kind_w();
        e = new(tb_if, pat_num, mbx_size, time_out, kind_w);

        $display("=============================================================");
        $display("                 ZUMA Environment Started");
        $display("Test = %s, games = %0d, mailbox = %0d", name, pat_num, mbx_size);
        $display("=============================================================");

        e.run();
        e.report();

        $display("=============================================================");
        $display("                 ZUMA Environment Completed");
        $display("                 Congratulations! All Pass");
        $display("=============================================================");
        $finish;
    end

endprogram
