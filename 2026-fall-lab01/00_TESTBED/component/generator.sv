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
    // Directed 1: all eight instructions share a randomly selected opcode.
    localparam int unsigned DIRECTED_1_NUM = 1000;
    localparam int unsigned DIRECTED_2_REPLAY_NUM = 4;
    localparam int unsigned DIRECTED_2_PER_TYPE = 1000;
    localparam int unsigned DIRECTED_2_NUM = DIRECTED_2_REPLAY_NUM + 3 * DIRECTED_2_PER_TYPE;
    localparam int unsigned DIRECTED_3_NUM = 1000;
    localparam int unsigned DIRECTED_NUM = DIRECTED_1_NUM + DIRECTED_2_NUM + DIRECTED_3_NUM;
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

    task run_directed_1();
        txn tr;
        op_typ target_op;

        repeat(DIRECTED_1_NUM) begin
            tr = new();
            // Randomize the shared opcode independently for each pattern.
            target_op = op_typ'($urandom_range(7, 0));

            if(!tr.randomize() with {
                foreach(inst[i]) inst[i].op == local::target_op;
            }) $fatal(1,
                {"================================================================\n",
                    "        Directed 1 Randomization Failed: opcode = %s\n",
                "================================================================"}, target_op.name());

            $display("DIRECTED 1 PATTERN [%0d]: all %s, graph = %s",
                testcase, target_op.name(), tr.tar_graph.name());
            tr.print(testcase);
            gen2drv.put(tr);
            testcase++;
        end
    endtask

    //=============================================================
    //                  Directed 2: Dual Chain Ties
    //=============================================================

    task run_directed_2();
        txn tr;
        directed_2_txn corner;
        bit [95:0] replay_seq;
        bit [47:0] replay_lat;

        for(int index = 0; index < int'(DIRECTED_2_REPLAY_NUM); index++) begin
            case(index)
                0: begin
                    replay_seq = 96'h124124524324200200400200;
                    // Unused opcode latencies use legal minimum values.
                    replay_lat = 48'h042186795041;
                end
                1: begin
                    replay_seq = 96'h2490530a4b530bc8441c32a5;
                    replay_lat = 48'h044249a15041;
                end
                2: begin
                    replay_seq = 96'h9008471178a83b914308a133;
                    replay_lat = 48'h042206c20141;
                end
                3: begin
                    replay_seq = 96'h124124324324124000c00000;
                    replay_lat = 48'h043186794081;
                end
                default: $fatal(1, "Unknown directed 2 replay index");
            endcase
            tr = new();
            // Solve metadata too, so existing coverage receives a valid txn.
            if(!tr.randomize() with {
                foreach(inst[i]) {
                    inst[i].op == local::replay_seq[i*12 + 9 +: 3];
                    inst[i].rs == local::replay_seq[i*12 + 6 +: 3];
                    inst[i].rt == local::replay_seq[i*12 + 3 +: 3];
                    inst[i].rd == local::replay_seq[i*12 +: 3];
                }
                foreach(lat[i]) lat[i] == local::replay_lat[i*6 +: 6];
            }) $fatal(1, "Directed 2 replay %0d randomization failed", index);
            $display("DIRECTED 2 REPLAY [%0d]: case=%0d", testcase, index);
            tr.print(testcase);
            gen2drv.put(tr);
            testcase++;
        end

        for(int scenario = 0; scenario < 3; scenario++) begin
            for(int index = 0; index < int'(DIRECTED_2_PER_TYPE); index++) begin
                corner = new();
                corner.scenario = scenario;
                if(scenario == 0) begin
                    // Half preserve (1,L,1,1); half sweep all 16 position pairs.
                    if(index >= int'(DIRECTED_2_PER_TYPE) / 2) begin
                        corner.long_pos_a = (index - int'(DIRECTED_2_PER_TYPE) / 2) % 4;
                        corner.long_pos_b = ((index - int'(DIRECTED_2_PER_TYPE) / 2) / 4) % 4;
                    end
                end
                else if(scenario == 1) corner.total_gap = index % 3;
                else begin
                    corner.a_length = 2 + (index % 2);
                    // Keep variants of the known 3+5 profile in this family.
                    corner.replay_short_shape = (index % 4 == 1);
                end
                if(!corner.randomize()) $fatal(1,
                    "Directed 2 scenario=%0d index=%0d randomization failed", scenario, index);
                $display("DIRECTED 2 PATTERN [%0d]: scenario=%0d, A=%p B=%p",
                    testcase, scenario, corner.a_latency, corner.b_latency);
                corner.print(testcase);
                gen2drv.put(corner);
                testcase++;
            end
        end
    endtask

    //=============================================================
    //                 Directed 3: Shared Register
    //=============================================================

    task run_directed_3();
        txn tr;
        bit [2:0] target_reg;

        repeat(DIRECTED_3_NUM) begin
            tr = new();
            target_reg = 3'($urandom_range(7, 0));
            // All instructions share one register; retain legal graph/memory constraints.
            if(!tr.randomize() with {
                foreach(inst[i]) {
                    inst[i].rs == local::target_reg;
                    inst[i].rt == local::target_reg;
                    inst[i].rd == local::target_reg;
                }
            }) $fatal(1, "Directed 3 randomization failed: register = r%0d", target_reg);
            $display("DIRECTED 3 PATTERN [%0d]: rs = rt = rd = r%0d, graph = %s",
                testcase, target_reg, tr.tar_graph.name());
            tr.print(testcase);
            gen2drv.put(tr);
            testcase++;
        end
    endtask

    //=============================================================
    //                           Main Run
    //=============================================================

    task run();
        run_directed_1();
        run_directed_2();
        run_directed_3();
        run_random();
    endtask

endclass
