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
    // One appended all-same-opcode case for each supported opcode.
    localparam int unsigned DIRECTED_NUM = 8;
    mailbox #(txn) gen2drv;
    int unsigned pattern_num;
    int unsigned testcase = 0;

    function new(
        input mailbox #(txn) gen2drv,
        input int unsigned pattern_num
    );
        this.gen2drv = gen2drv;
        this.pattern_num = pattern_num;
    endfunction

    task run_random();
        txn tr;

        repeat(pattern_num) begin
            tr = new();

            if(!tr.randomize()) 
                $fatal(1, 
                    {"================================================================\n",
                    "               Transaction Randomization Failed ! ! !            \n",
                    "================================================================"});

            tr.print(testcase);
            // Wait for queue space before generating the next transaction.
            gen2drv.put(tr);
            testcase = testcase + 1;
        end
    endtask

    //=============================================================
    //                      Directed Patterns
    //=============================================================

    task run_directed();
        txn tr;
        op_typ target_op;

        for(int unsigned op_index = 0; op_index < DIRECTED_NUM; op_index++) begin
            tr = new();
            // Exercise each opcode with all eight instructions using that opcode.
            target_op = op_typ'(op_index);

            if(!tr.randomize() with {
                foreach(inst[i]) inst[i].op == local::target_op;
            }) $fatal(1,
                {"================================================================\n",
                "        Directed Randomization Failed: opcode = %s\n",
                "================================================================"}, target_op.name());

            $display("DIRECTED PATTERN [%0d]: all %s, graph = %s",
                testcase, target_op.name(), tr.tar_graph.name());
            tr.print(testcase);
            gen2drv.put(tr);
            testcase++;
        end
    endtask

    //=============================================================
    //                           Main Run
    //=============================================================

    task run();
        run_random();
        run_directed();
    endtask

endclass
