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
    mailbox #(txn) drv2cov;
    int unsigned pattern_num;

    function new(
        input mailbox #(txn) drv2cov,
        input int unsigned pattern_num
    );
        this.drv2cov = drv2cov;
        this.pattern_num = pattern_num;

        // 記得要實例化 covergroup
        cg_inst = new();
        cg_same_op = new();
        cg_one_chain = new();
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
            bins b_index[] = {[0:7]};
        }

        cross index, op;
    endgroup

    // Coverage 2 : 相同 opcode 的 condition 是否都有發生 (low hit)
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

    // Coverage 3 : ONE CHAIN 長度是否涵蓋 2 ~ 8 
    covergroup cg_one_chain with function sample(int unsigned length);
        coverpoint length {
            bins b_len[] = {[2:8]};
        }
    endgroup

    // Coverage 4 : 


    //=============================================================
    //                          Run Task
    //=============================================================

    task run();
        txn tr;
        bit same_flag;
        op_typ same_op;

        repeat(pattern_num) begin
            drv2cov.get(tr);
            for(int i = 0; i < 8; i++) cg_inst.sample(i, tr.inst[i].op);

            same_op = tr.inst[0].op;
            same_flag = 1'b1;
            for(int i = 1; i < 8; i++) same_flag &= (tr.inst[i].op == same_op);
            cg_same_op.sample(same_flag, same_op);

            if(tr.tar_graph == ONE_CHAIN) cg_one_chain.sample($countones(tr.chain_mask));

        end
    endtask

endclass