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
    localparam int unsigned DIRECTED_NUM = 23;
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
        bit [95:0] directed_seq[DIRECTED_NUM];
        bit [47:0] directed_lat[DIRECTED_NUM];

        directed_seq = '{
            96'h000000000000000000000000,
            96'h200200200200200200200200,
            96'h400400400400400400400400,
            96'h600600600600600600600600,
            96'h800800800800800800800800,
            96'hbc0b80b40b00ac0a80a40a00,
            96'hc00c00c00c00c00c00c00c00,
            96'he00e00e00e00e00e00e00e00,
            96'h124124524324200200400200,
            96'h2490530a4b530bc8441c32a5,
            96'h9008471178a83b914308a133,
            96'h124124324324124000c00000,
            96'he00e00800600400200c00000,
            96'he49e49849649449249c49049,
            96'he92e92892692492292c92092,
            96'hedbedb8db6db4db2dbcdb0db,
            96'hf24f24924724524324d24124,
            96'hf6df6d96d76d56d36dd6d16d,
            96'hfb6fb69b67b65b63b6db61b6,
            96'hffffff9ff7ff5ff3ffdff1ff,
            96'h249249249249249449000600,
            96'h249249249249449000000600,
            96'h249249249449000000000600
        };

        directed_lat = '{
            48'h042186794041,
            48'h042186794041,
            48'h042186794041,
            48'h042186794041,
            48'h042186794041,
            48'h042186794041,
            48'h042186794041,
            48'h042186794041,
            48'h042186795041,
            48'h044249a15041,
            48'h042206c20141,
            48'h043186794081,
            48'h042186794041,
            48'h042186794041,
            48'h042186794041,
            48'h042186794041,
            48'h042186794041,
            48'h042186794041,
            48'h042186794041,
            48'h042186794041,
            48'h04218679a041,
            48'h04218679c041,
            48'h04218679e041
        };

        for(int index = 0; index < DIRECTED_NUM; index++) begin
            tr = new();
            tr.inst_seq = directed_seq[index];
            tr.inst_lat = directed_lat[index];

            `ifdef PRINT
                $display(
                    "DIRECTED PATTERN [%0d]: Inst_seq=%024h, Inst_latency=%012h",
                    testcase, tr.inst_seq, tr.inst_lat
                );
            `endif

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
