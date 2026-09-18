/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    OISS.v
* Project:      NCTU-EE IC Lab Fall 2026 Lab01
* Module:       OISS
* Author:       Marco
*
* Out-of-order instruction scheduling solver (combinational).
******************************************************************************/

module OISS (
    input  [95:0] Inst_seq_I,
    input  [47:0] Inst_latency_I,
    output [23:0] Inst_order_O,
    output [8:0]  Ex_cycle
);

    localparam int NUM_INST = 8;
    localparam int NUM_PERM = 40320;

    logic [11:0] inst_word [0:NUM_INST-1];
    logic [5:0]  inst_lat  [0:NUM_INST-1];
    logic [7:0]  inst_rset [0:NUM_INST-1];
    logic [7:0]  inst_wset [0:NUM_INST-1];
    logic        dep_edge  [0:NUM_INST-1][0:NUM_INST-1];

    logic [23:0] best_order;
    logic [8:0]  best_cycle;

    function automatic logic [5:0] opcode_latency(
        input logic [2:0] opcode,
        input logic [47:0] lat_pack
    );
        case(opcode)
            3'b000: opcode_latency = lat_pack[5:0];
            3'b001: opcode_latency = lat_pack[11:6];
            3'b010: opcode_latency = lat_pack[17:12];
            3'b011: opcode_latency = lat_pack[23:18];
            3'b100: opcode_latency = lat_pack[29:24];
            3'b101: opcode_latency = lat_pack[35:30];
            3'b110: opcode_latency = lat_pack[41:36];
            default: opcode_latency = lat_pack[47:42];
        endcase
    endfunction

    function automatic logic [7:0] inst_read_set(input logic [11:0] word);
        logic [2:0] opcode;
        logic [2:0] rs;
        logic [2:0] rt;
        logic [2:0] rd;
        opcode = word[11:9];
        rs = word[8:6];
        rt = word[5:3];
        rd = word[2:0];
        inst_read_set = 8'b0;
        case(opcode)
            3'b000, 3'b001, 3'b010, 3'b011:
                inst_read_set = (8'b1 << rs) | (8'b1 << rt);
            3'b101:
                inst_read_set = 8'b1 << rd;
            3'b110:
                inst_read_set = (8'b1 << rs) | (8'b1 << rt);
            default:
                inst_read_set = 8'b0;
        endcase
    endfunction

    function automatic logic [7:0] inst_write_set(input logic [11:0] word);
        logic [2:0] opcode;
        logic [2:0] rd;
        opcode = word[11:9];
        rd = word[2:0];
        inst_write_set = 8'b0;
        if(opcode <= 3'b100)
            inst_write_set = 8'b1 << rd;
    endfunction

    function automatic logic [8:0] eval_issue_cycles(
        input logic [2:0] issue_ord [0:NUM_INST-1],
        input logic [5:0] lat       [0:NUM_INST-1],
        input logic       dep       [0:NUM_INST-1][0:NUM_INST-1]
    );
        logic [8:0] start_cyc [0:NUM_INST-1];
        logic [8:0] finish_cyc [0:NUM_INST-1];
        logic [8:0] issue_gap;
        logic [8:0] dep_ready;
        logic [8:0] max_finish;
        logic [2:0] cur_idx;
        logic [2:0] prev_idx;
        int         ii;

        for(ii = 0; ii < NUM_INST; ii = ii + 1) begin
            start_cyc[ii] = 9'd0;
            finish_cyc[ii] = 9'd0;
        end

        cur_idx = issue_ord[0];
        start_cyc[cur_idx] = 9'd0;
        finish_cyc[cur_idx] = lat[cur_idx];

        for(ii = 1; ii < NUM_INST; ii = ii + 1) begin
            cur_idx = issue_ord[ii];
            prev_idx = issue_ord[ii-1];
            issue_gap = start_cyc[prev_idx] + 9'd1;
            dep_ready = 9'd0;
            for(int jj = 0; jj < NUM_INST; jj = jj + 1)
                if(dep[jj][cur_idx])
                    dep_ready = (finish_cyc[jj] > dep_ready)? finish_cyc[jj] : dep_ready;
            start_cyc[cur_idx] = (issue_gap > dep_ready)? issue_gap : dep_ready;
            finish_cyc[cur_idx] = start_cyc[cur_idx] + lat[cur_idx];
        end

        max_finish = 9'd0;
        for(ii = 0; ii < NUM_INST; ii = ii + 1)
            max_finish = (finish_cyc[ii] > max_finish)? finish_cyc[ii] : max_finish;

        eval_issue_cycles = max_finish;
    endfunction

    function automatic logic [23:0] pack_order(input logic [2:0] ord [0:NUM_INST-1]);
        pack_order = {
            ord[7], ord[6], ord[5], ord[4],
            ord[3], ord[2], ord[1], ord[0]
        };
    endfunction

    function automatic logic order_respects_deps(
        input logic [2:0] issue_ord [0:NUM_INST-1],
        input logic       dep       [0:NUM_INST-1][0:NUM_INST-1]
    );
        int pos_table [0:NUM_INST-1];
        int ii;
        int jj;
        order_respects_deps = 1'b1;
        for(ii = 0; ii < NUM_INST; ii = ii + 1)
            pos_table[ii] = 0;
        for(ii = 0; ii < NUM_INST; ii = ii + 1)
            pos_table[issue_ord[ii]] = ii;
        for(ii = 0; ii < NUM_INST; ii = ii + 1)
            for(jj = ii + 1; jj < NUM_INST; jj = jj + 1)
                if(dep[ii][jj] && (pos_table[ii] >= pos_table[jj]))
                    order_respects_deps = 1'b0;
    endfunction

    always_comb begin
        int         perm_idx;
        int         perm_rem;
        int         pick_slot;
        int         fact_div;
        int         rem_pos;
        logic [2:0] rem_list [0:NUM_INST-1];
        logic [2:0] cur_order [0:NUM_INST-1];
        logic [8:0] cur_cycle;
        int         ii;
        int         jj;
        int         kk;

        for(ii = 0; ii < NUM_INST; ii = ii + 1) begin
            inst_word[ii] = Inst_seq_I[ii*12 +: 12];
            inst_lat[ii] = opcode_latency(inst_word[ii][11:9], Inst_latency_I);
            inst_rset[ii] = inst_read_set(inst_word[ii]);
            inst_wset[ii] = inst_write_set(inst_word[ii]);
        end

        for(ii = 0; ii < NUM_INST; ii = ii + 1)
            for(jj = 0; jj < NUM_INST; jj = jj + 1)
                dep_edge[ii][jj] = 1'b0;

        for(ii = 0; ii < NUM_INST; ii = ii + 1)
            for(jj = ii + 1; jj < NUM_INST; jj = jj + 1) begin
                dep_edge[ii][jj] =
                    ((inst_wset[ii] & inst_rset[jj]) != 8'b0) |
                    ((inst_rset[ii] & inst_wset[jj]) != 8'b0) |
                    ((inst_wset[ii] & inst_wset[jj]) != 8'b0);
            end

        best_cycle = 9'd511;
        best_order = 24'b0;

        for(perm_idx = 0; perm_idx < NUM_PERM; perm_idx = perm_idx + 1) begin
            perm_rem = perm_idx;
            for(ii = 0; ii < NUM_INST; ii = ii + 1)
                rem_list[ii] = ii[2:0];

            fact_div = 5040;
            for(kk = 0; kk < NUM_INST; kk = kk + 1) begin
                pick_slot = perm_rem / fact_div;
                cur_order[kk] = rem_list[pick_slot];
                for(rem_pos = pick_slot; rem_pos < NUM_INST - kk - 1; rem_pos = rem_pos + 1)
                    rem_list[rem_pos] = rem_list[rem_pos + 1];
                perm_rem = perm_rem % fact_div;
                case(kk)
                    0: fact_div = 720;
                    1: fact_div = 120;
                    2: fact_div = 24;
                    3: fact_div = 6;
                    4: fact_div = 2;
                    5: fact_div = 1;
                    default: fact_div = 1;
                endcase
            end

            if(order_respects_deps(cur_order, dep_edge)) begin
                cur_cycle = eval_issue_cycles(cur_order, inst_lat, dep_edge);
                if(cur_cycle < best_cycle) begin
                    best_cycle = cur_cycle;
                    best_order = pack_order(cur_order);
                end
            end
        end
    end

    assign Inst_order_O = best_order;
    assign Ex_cycle = best_cycle;

endmodule
