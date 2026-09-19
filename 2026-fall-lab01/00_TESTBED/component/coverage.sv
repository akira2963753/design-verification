/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    coverage.sv
* Project:      2026 FALL NYCU IC LAB, LAB01
* Module:       OISS Functional Coverage
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

class coverage;
    // Input stimulus coverage only; DUT output checks belong to scoreboard.
    mailbox #(txn) drv2cov;
    int unsigned pattern_num;
    int unsigned sampled_num;

    //=============================================================
    //                     Functional Coverage
    //=============================================================

    // Coverage 1: Every opcode at every input position.
    covergroup cg_inst with function sample(int index, op_typ op);
        coverpoint op {
            bins op_add = {ADD};
            bins op_sub = {SUB};
            bins op_mul = {MUL};
            bins op_div = {DIV};
            bins op_load = {LOAD};
            bins op_store = {STORE};
            bins op_branch = {BRANCH};
            bins op_jump = {JUMP};
        }
        coverpoint index {
            bins b_index[] = {[0:7]};
        }
        cross index, op;
    endgroup

    // Coverage 2: Sample ONLY when all eight instructions share an opcode.
    covergroup cg_same_op with function sample(op_typ op);
        coverpoint op {
            bins b_op[] = {[ADD:JUMP]};
        }
    endgroup

    // Coverage 3: The three legal graph types and their chain lengths.
    covergroup cg_graph with function sample(graph_typ graph);
        coverpoint graph {
            bins no_chain = {NO_CHAIN};
            bins one_chain = {ONE_CHAIN};
            bins two_chains = {TWO_CHAINS};
        }
    endgroup

    covergroup cg_one_chain with function sample(int length);
        coverpoint length {
            bins b_len[] = {[2:8]};
        }
    endgroup

    // The shorter chain uniquely identifies the unordered length pair.
    covergroup cg_two_chains with function sample(int shorter_length);
        coverpoint shorter_length {
            bins len_2_6 = {2};
            bins len_3_5 = {3};
            bins len_4_4 = {4};
        }
    endgroup

    // Coverage 4: One sample per original pair i < j; bit order is RAW/WAR/WAW.
    covergroup cg_dependency with function sample(bit [2:0] hazards);
        coverpoint hazards {
            bins independent = {3'b000};
            bins raw_only = {3'b100};
            bins war_only = {3'b010};
            bins waw_only = {3'b001};
            bins raw_war = {3'b110};
            bins raw_waw = {3'b101};
            bins war_waw = {3'b011};
            bins raw_war_waw = {3'b111};
        }
    endgroup

    // Coverage 5: Latency of opcodes actually present in the input.
    // Per-opcode points avoid impossible opcode x latency cross bins.
    covergroup cg_latency with function sample(op_typ op, int latency);
        cp_add: coverpoint latency iff(op == ADD) {
            bins minimum = {1};
            bins middle[] = {[2:4]};
            bins maximum = {5};
        }
        cp_sub: coverpoint latency iff(op == SUB) {
            bins minimum = {1};
            bins middle[] = {[2:4]};
            bins maximum = {5};
        }
        cp_mul: coverpoint latency iff(op == MUL) {
            bins minimum = {20};
            bins lower[] = {[21:30]};
            bins bit_boundary[] = {31, 32};
            bins upper[] = {[33:39]};
            bins maximum = {40};
        }
        cp_div: coverpoint latency iff(op == DIV) {
            bins minimum = {30};
            bins bit_boundary[] = {31, 32};
            bins upper[] = {[33:49]};
            bins maximum = {50};
        }
        cp_load: coverpoint latency iff(op == LOAD) {
            bins minimum = {6};
            bins middle[] = {[7:9]};
            bins maximum = {10};
        }
        cp_store: coverpoint latency iff(op == STORE) {
            bins minimum = {6};
            bins middle[] = {[7:9]};
            bins maximum = {10};
        }
        cp_branch: coverpoint latency iff(op == BRANCH) {
            bins minimum = {2};
            bins middle = {3};
            bins maximum = {4};
        }
        cp_jump: coverpoint latency iff(op == JUMP) {
            bins fixed_latency = {1};
        }
    endgroup

    // Coverage 6: Input scenarios exercising special operand meanings.
    // A hit alone does not prove that the DUT decoded the operand correctly.
    covergroup cg_special_rw with function sample(int scenario);
        coverpoint scenario {
            bins store_reads_rd = {0};
            bins store_does_not_write_rd = {1};
            bins branch_does_not_write_rd = {2};
            bins load_does_not_read_address = {3};
            bins jump_does_not_read = {4};
            bins jump_does_not_write = {5};
        }
    endgroup

    // Coverage 7: Duplicate encodings still represent distinct instructions.
    covergroup cg_duplicate with function sample(bit duplicate);
        coverpoint duplicate {
            bins absent = {0};
            bins present = {1};
        }
    endgroup

    covergroup cg_memory with function sample(op_typ op, int address);
        coverpoint op {
            bins load = {LOAD};
            bins store = {STORE};
        }
        coverpoint address {
            bins minimum = {0};
            bins middle = {[1:62]};
            bins maximum = {63};
        }
        cross op, address;
    endgroup

    covergroup cg_memory_pair with function sample(int scenario);
        coverpoint scenario {
            bins load_same_address = {0};
            bins load_different_address = {1};
            bins load_store_different_address = {2};
            bins store_store_different_address = {3};
        }
    endgroup

    //=============================================================
    //                         Constructor
    //=============================================================

    function new(input mailbox #(txn) drv2cov, input int unsigned pattern_num);
        this.drv2cov = drv2cov;
        this.pattern_num = pattern_num;
        sampled_num = 0;
        cg_inst = new();
        cg_same_op = new();
        cg_graph = new();
        cg_one_chain = new();
        cg_two_chains = new();
        cg_dependency = new();
        cg_latency = new();
        cg_special_rw = new();
        cg_duplicate = new();
        cg_memory = new();
        cg_memory_pair = new();
    endfunction

    //=============================================================
    //                       Input Sampling
    //=============================================================

    // Read the solved transaction fields; do not rebuild the dependency graph.
    function automatic void sample_input(input txn tr);
        bit same_flag, duplicate, incoming;
        bit [7:0] fake_reads, fake_write;
        int shorter_length, length;
        same_flag = 1;
        duplicate = 0;
        for(int i = 0; i < 8; i++) begin
            cg_inst.sample(i, tr.inst[i].op);
            cg_latency.sample(tr.inst[i].op, int'(tr.lat[tr.inst[i].op]));
            same_flag &= (tr.inst[i].op == tr.inst[0].op);
            if(tr.inst[i].op inside {LOAD, STORE}) cg_memory.sample(tr.inst[i].op, int'({tr.inst[i].rs, tr.inst[i].rt}));
            for(int j = i + 1; j < 8; j++) begin
                cg_dependency.sample({tr.raw[i][j], tr.war[i][j], tr.waw[i][j]});
                duplicate |= (tr.inst[i] == tr.inst[j]);
                if(tr.inst[i].op == LOAD && tr.inst[j].op == LOAD) begin
                    if({tr.inst[i].rs, tr.inst[i].rt} == {tr.inst[j].rs, tr.inst[j].rt}) cg_memory_pair.sample(0);
                    else cg_memory_pair.sample(1);
                end
                else if(tr.inst[i].op == STORE && tr.inst[j].op == STORE) cg_memory_pair.sample(3);
                else if((tr.inst[i].op inside {LOAD, STORE}) && (tr.inst[j].op inside {LOAD, STORE})) cg_memory_pair.sample(2);
            end

            // Matching ignored fields must not create a new dependency path.
            fake_reads = (8'b1 << tr.inst[i].rs) | (8'b1 << tr.inst[i].rt);
            fake_write = 8'b1 << tr.inst[i].rd;
            for(int j = 0; j < 8; j++) begin
                if(j < i && tr.inst[i].op == STORE && tr.raw[j][i]) cg_special_rw.sample(0);
                if(j > i && !tr.reach[i][j] && (|(fake_write & tr.read_mask[j]))) begin
                    if(tr.inst[i].op == STORE) cg_special_rw.sample(1);
                    if(tr.inst[i].op == BRANCH) cg_special_rw.sample(2);
                    if(tr.inst[i].op == JUMP) cg_special_rw.sample(5);
                end
                if(j < i && !tr.reach[j][i] && (|(tr.write_mask[j] & fake_reads))) begin
                    if(tr.inst[i].op == LOAD) cg_special_rw.sample(3);
                    if(tr.inst[i].op == JUMP) cg_special_rw.sample(4);
                end
            end
        end
        if(same_flag) cg_same_op.sample(tr.inst[0].op);
        cg_duplicate.sample(duplicate);
        cg_graph.sample(tr.tar_graph);
        if(tr.tar_graph == ONE_CHAIN) cg_one_chain.sample($countones(tr.chain_mask));
        if(tr.tar_graph == TWO_CHAINS) begin
            shorter_length = 8;
            for(int i = 0; i < 8; i++) begin
                incoming = 0;
                for(int j = 0; j < 8; j++) incoming |= tr.chain_edge[j][i];
                if(!incoming && tr.chain_mask[i]) begin
                    length = 1 + $countones(tr.reach[i]);
                    if(length < shorter_length) shorter_length = length;
                end
            end
            cg_two_chains.sample(shorter_length);
        end
    endfunction

    //=============================================================
    //                          Run Task
    //=============================================================

    task run();
        txn tr;
        repeat(pattern_num) begin
            drv2cov.get(tr);
            sample_input(tr);
            sampled_num++;
        end
        $display("Input coverage: sampled %0d driven transactions", sampled_num);
    endtask
endclass
