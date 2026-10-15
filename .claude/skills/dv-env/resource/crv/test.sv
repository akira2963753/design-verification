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
    string name = "rand";       // +TEST=<rand | file>
    string in_file = "../00_TESTBED/input.txt";    // +IN_FILE=<path>, file test only
    int fd;

    env e;

    //=============================================================
    //                           BLUEPRINT
    //=============================================================

    // Swap the generator blueprint, every pattern is copied from it, env and generator stay the same
    function void set_blueprint();
        file_txn file_bp;

        case(name)
            "rand": ;   // keep the default txn built in generator.new()
            "file": begin
                file_bp = new();
                e.gen.blueprint = file_bp;
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

        // Before new env: the 1st line of the file is the pattern number
        if(name == "file") begin
            void'($value$plusargs("IN_FILE=%s", in_file));
            fd = $fopen(in_file, "r");
            if(fd == 0) begin
                $display("=============================================================");
                $display("              [TEST] Cannot open %s", in_file);
                $display("=============================================================");
                $fatal(1);
            end
            if($fscanf(fd, "%d", pat_num) != 1) begin
                $display("=============================================================");
                $display("              [TEST] No pattern number in %s", in_file);
                $display("=============================================================");
                $fatal(1);
            end
            file_txn::fd = fd;      // static, post_randomize() starts from the 1st pattern
        end

        e = new(tb_if, pat_num, mbx_size);

        // After new() builds the generator, before run() copies the 1st pattern
        set_blueprint();

        $display("=============================================================");
        $display("                F_ATTN Environment Started");
        $display("Test = %s, patterns = %0d, mailbox = %0d", name, pat_num, mbx_size);
        $display("=============================================================");

        e.run();

        // e.run() returns after the generator read the last pattern
        if(name == "file") $fclose(fd);

        e.report();

        $display("=============================================================");
        $display("                F_ATTN Environment Completed");
        $display("                Congratulations! All Pass");
        $display("=============================================================");
        $finish;
    end

endprogram
