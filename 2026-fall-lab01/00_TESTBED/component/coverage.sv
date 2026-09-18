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
    mailbox #(mon_txn) mon2cov;
    int unsigned pattern_num;

    inst_typ inst[8];

    function new(
        input mailbox #(mon_txn) mon2cov,
        input int unsigned pattern_num
    );
        this.mon2cov = mon2cov;
        this.pattern_num = pattern_num;

        // 記得要實例化 covergroup
        cg_inst = new();
        cg_same_op = new();
    endfunction

    //=============================================================
    //                      Functional Coverage
    //=============================================================

    // Coverage 1 : 每個 instruction index 都有執行過每個 opcode
    covergroup cg_inst with function sample(int unsigned index, op_typ op);
        
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
            bins indices[] = {[0:7]};
        }

        cross index, op;
    endgroup

    // Coverage 2 : 相同 opcode 的 condition
    covergroup cg_same_op with function sample(bit same_flag, op_typ same_op);
        coverpoint same_flag {
            bins same = {1};
        }

        coverpoint same_op{
            bins same_op_add = {ADD};
            bins same_sub = {SUB};
            bins same_mul = {MUL};
            bins same_div = {DIV};
            bins same_load = {LOAD};
            bins same_store = {STORE};
            bins same_branch = {BRANCH};
            bins same_jump = {JUMP};
        }

        cross same_flag, same_op;
    endgroup

    // Coverage 3 ...



    //=============================================================
    //                          Run Task
    //=============================================================

    task run();
        mon_txn tr;
        bit same_flag;
        op_typ same_op;

        repeat(pattern_num) begin
            mon2cov.get(tr);
            // Unpack each 12-bit instruction into its packed struct using type cast
            for(int i = 0; i < 8; i++) inst[i] = inst_typ'(tr.inst_seq[i*12 +: 12]);
            for(int i = 0; i < 8; i++) cg_inst.sample(i, inst[i].op);

            same_op = inst[0].op;
            same_flag = 1'b1;
            for(int i = 1; i < 8; i++) same_flag &= (inst[i].op == same_op);
            cg_same_op.sample(same_flag, same_op);

        end
    endtask

endclass