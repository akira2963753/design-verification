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

    uint pat_num = 500;         // number of patterns, +PAT_NUM=<n>
    uint mbx_size = 20;         // bounded gen2drv depth
    string name = "rand";       // +TEST=<rand | k_max>

    env e;

    //=============================================================
    //                           BLUEPRINT
    //=============================================================

    // Swap the generator blueprint, every pattern is copied from it, env and generator stay the same
    function void set_blueprint();
        k_max_txn k_max_bp;

        case(name)
            "rand": ;   // keep the default txn built in generator.new()
            "k_max": begin
                k_max_bp = new();
                e.gen.blueprint = k_max_bp;
            end
            default: begin
                $display("=============================================================");
                $display("              [TEST] Unknown test name: %s", name);
                $display("=============================================================");
                $fatal(1);
            end
        endcase
    endfunction

    //=============================================================
    //                           MAIN FLOW
    //=============================================================

    initial begin : MAIN_FLOW
        void'($value$plusargs("PAT_NUM=%d", pat_num));
        void'($value$plusargs("TEST=%s", name));
        e = new(tb_if, pat_num, mbx_size);

        // After new() builds the generator, before run() copies the 1st pattern
        set_blueprint();

        $display("=============================================================");
        $display("                F_ATTN Environment Started");
        $display("Test = %s, patterns = %0d, mailbox = %0d", name, pat_num, mbx_size);
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
