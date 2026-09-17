/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    generator.sv
* Project:      2026 FALL NYCU IC LAB, LAB01
* Module:       OISS Generator
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

class generator;
    mailbox #(txn) gen2drv = new;
    int unsigned pattern_num;
    int unsigned testcase;

    function new(
        input mailbox #(txn) gen2drv,
        input int unsigned pattern_num
    );
        this.gen2drv = gen2drv;
        this.pattern_num = pattern_num;
        testcase = 0;
    endfunction

    task run();
        txn tr;

        repeat(pattern_num) begin
            tr = new();

            case($urandom_range(2, 0))
                0: tr.tar_graph = NO_CHAIN;
                1: tr.tar_graph = ONE_CHAIN;
                2: tr.tar_graph = TWO_CHAINS;
            endcase

            if(!tr.randomize()) 
                $fatal(1, 
                    {"================================================================\n",
                    "               Transaction Randomization Failed ! ! !            \n",
                    "================================================================"});

            tr.print(testcase);
            gen2drv.put(tr);
            testcase = testcase + 1;
        end
    endtask
endclass
