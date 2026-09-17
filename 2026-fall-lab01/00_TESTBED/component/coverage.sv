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

    //=============================================================
    //                       Observed Fields
    //=============================================================

    typedef enum bit [1:0] {LAT_MIN, LAT_MIDDLE, LAT_MAX, LAT_FIXED} latency_typ;
    op_typ opcode, configured_opcode;
    bit [2:0] position;
    latency_typ instruction_latency, configured_latency;
    graph_typ graph;
    bit has_raw, has_war, has_waw;
    int single_length, short_length;
    int unsigned sampled_patterns = 0;
    int unsigned skipped_patterns = 0;
    int unsigned invalid_graphs = 0;

    //=============================================================
    //                    Instruction Coverage
    //=============================================================

    // Sample eight times per pattern, once for each observed instruction.
    covergroup instruction_cg;
        option.per_instance = 1;
        cp_opcode: coverpoint opcode {
            bins op_add = {ADD};
            bins op_sub = {SUB};
            bins op_mul = {MUL};
            bins op_div = {DIV};
            bins op_load = {LOAD};
            bins op_store = {STORE};
            bins op_branch = {BRANCH};
            bins op_jump = {JUMP};
        }
        cp_position: coverpoint position {
            bins index[] = {[0:7]};
        }
        cx_opcode_position: cross cp_opcode, cp_position;
    endgroup

    // Latency of opcodes actually present in the instruction sequence.
    // Only the cross contributes to this group's percentage.
    covergroup instruction_latency_cg;
        option.per_instance = 1;
        cp_opcode: coverpoint opcode {
            option.weight = 0;
            bins each_opcode[] = {[0:7]};
        }
        cp_latency: coverpoint instruction_latency {
            option.weight = 0;
            bins minimum = {LAT_MIN};
            bins middle = {LAT_MIDDLE};
            bins maximum = {LAT_MAX};
            bins fixed_one = {LAT_FIXED};
        }
        cx_opcode_latency: cross cp_opcode, cp_latency {
            ignore_bins jump_variable = binsof(cp_opcode) intersect {JUMP} &&
                binsof(cp_latency) intersect {LAT_MIN, LAT_MIDDLE, LAT_MAX};
            ignore_bins other_fixed = binsof(cp_opcode) intersect {[0:6]} &&
                binsof(cp_latency) intersect {LAT_FIXED};
        }
    endgroup

    //=============================================================
    //                 Configured Latency Coverage
    //=============================================================

    // Sample all eight latency fields, even if an opcode is absent.
    // Keep this separate from instruction latency coverage above.
    covergroup configured_latency_cg;
        option.per_instance = 1;
        cp_opcode: coverpoint configured_opcode {
            option.weight = 0;
            bins each_opcode[] = {[0:7]};
        }
        cp_latency: coverpoint configured_latency {
            option.weight = 0;
            bins minimum = {LAT_MIN};
            bins middle = {LAT_MIDDLE};
            bins maximum = {LAT_MAX};
            bins fixed_one = {LAT_FIXED};
        }
        cx_opcode_latency: cross cp_opcode, cp_latency {
            ignore_bins jump_variable = binsof(cp_opcode) intersect {JUMP} &&
                binsof(cp_latency) intersect {LAT_MIN, LAT_MIDDLE, LAT_MAX};
            ignore_bins other_fixed = binsof(cp_opcode) intersect {[0:6]} &&
                binsof(cp_latency) intersect {LAT_FIXED};
        }
    endgroup

    //=============================================================
    //                       Pattern Coverage
    //=============================================================

    // Sample once per pattern, after computing dependencies from sampled input.
    covergroup pattern_cg;
        option.per_instance = 1;
        cp_raw: coverpoint has_raw {
            bins absent = {0};
            bins present = {1};
        }
        cp_war: coverpoint has_war {
            bins absent = {0};
            bins present = {1};
        }
        cp_waw: coverpoint has_waw {
            bins absent = {0};
            bins present = {1};
        }
        cp_graph: coverpoint graph {
            bins no_chain = {NO_CHAIN};
            bins one_chain = {ONE_CHAIN};
            bins two_chains = {TWO_CHAINS};
            ignore_bins invalid = {INVALID_GRAPH};
        }
        cp_single_length: coverpoint single_length iff(graph == ONE_CHAIN) {
            bins length[] = {[2:8]};
        }
        // Chains are unordered: 2+6 and 6+2 hit the same bin.
        cp_two_lengths: coverpoint short_length iff(graph == TWO_CHAINS) {
            bins two_six = {2};
            bins three_five = {3};
            bins four_four = {4};
        }
    endgroup

    function new();
        instruction_cg = new();
        instruction_latency_cg = new();
        configured_latency_cg = new();
        pattern_cg = new();
    endfunction

    //=============================================================
    //                        Decode Helpers
    //=============================================================

    local function int minimum_latency(input op_typ op);
        case(op)
            ADD, SUB, JUMP: return 1;
            MUL: return 20;
            DIV: return 30;
            LOAD, STORE: return 6;
            BRANCH: return 2;
            default: return 0;
        endcase
    endfunction

    local function int maximum_latency(input op_typ op);
        case(op)
            ADD, SUB: return 5;
            MUL: return 40;
            DIV: return 50;
            LOAD, STORE: return 10;
            BRANCH: return 4;
            JUMP: return 1;
            default: return 0;
        endcase
    endfunction

    local function latency_typ classify_latency(input op_typ op, input int value);
        if(op == JUMP) return LAT_FIXED;
        if(value == minimum_latency(op)) return LAT_MIN;
        if(value == maximum_latency(op)) return LAT_MAX;
        return LAT_MIDDLE;
    endfunction

    local function void analyze_graph(input logic [95:0] inst_seq);
        bit [7:0] reads[8], writes[8];
        bit [7:0][7:0] edges, reachable, reduced;
        int incoming[8], outgoing[8];
        op_typ op;
        int rs, rt, rd, active, chains;
        int lengths[8];
        bit branching;

        edges = '0;
        reduced = '0;
        has_raw = 0;
        has_war = 0;
        has_waw = 0;
        single_length = 0;
        short_length = 0;
        graph = INVALID_GRAPH;
        active = 0;
        chains = 0;
        branching = 0;

        for(int i = 0; i < 8; i++) begin
            reads[i] = '0;
            writes[i] = '0;
            incoming[i] = 0;
            outgoing[i] = 0;
            lengths[i] = 0;
            op = op_typ'(inst_seq[i*12 + 9 +: 3]);
            rs = int'(inst_seq[i*12 + 6 +: 3]);
            rt = int'(inst_seq[i*12 + 3 +: 3]);
            rd = int'(inst_seq[i*12 +: 3]);
            if(op <= DIV || op == BRANCH) reads[i] = (8'b1 << rs) | (8'b1 << rt);
            if(op == STORE) reads[i] = 8'b1 << rd;
            if(op <= LOAD) writes[i] = 8'b1 << rd;
        end

        for(int i = 0; i < 8; i++) begin
            for(int j = i + 1; j < 8; j++) begin
                has_raw |= |(writes[i] & reads[j]);
                has_war |= |(reads[i] & writes[j]);
                has_waw |= |(writes[i] & writes[j]);
                edges[i][j] = |((writes[i] & reads[j]) |
                    (reads[i] & writes[j]) | (writes[i] & writes[j]));
            end
        end

        // Compute transitive closure, then remove redundant direct edges.
        reachable = edges;
        for(int k = 0; k < 8; k++) begin
            for(int i = 0; i < 8; i++) begin
                for(int j = 0; j < 8; j++) begin
                    reachable[i][j] |= reachable[i][k] && reachable[k][j];
                end
            end
        end
        reduced = edges;
        for(int i = 0; i < 8; i++) begin
            for(int j = i + 1; j < 8; j++) begin
                for(int k = i + 1; k < j; k++) begin
                    if(reachable[i][k] && reachable[k][j]) reduced[i][j] = 0;
                end
                if(reduced[i][j]) begin
                    outgoing[i]++;
                    incoming[j]++;
                end
            end
        end

        for(int i = 0; i < 8; i++) begin
            if(incoming[i] > 1 || outgoing[i] > 1) branching = 1;
            if(incoming[i] != 0 || outgoing[i] != 0) active++;
            if(incoming[i] == 0 && outgoing[i] != 0) begin
                lengths[chains] = 1 + $countones(reachable[i]);
                chains++;
            end
        end
        if(branching) return;
        if(active == 0) graph = NO_CHAIN;
        else if(chains == 1) begin
            graph = ONE_CHAIN;
            single_length = lengths[0];
        end
        else if(chains == 2 && active == 8) begin
            graph = TWO_CHAINS;
            short_length = (lengths[0] < lengths[1])? lengths[0] : lengths[1];
        end
    endfunction

    //=============================================================
    //                      Transaction Sampling
    //=============================================================

    function void write(input mon_txn tr);
        int latency[8];

        // Do not let unknown or illegal fields produce misleading coverage.
        // The scoreboard remains responsible for reporting invalid input.
        if(tr == null) begin
            skipped_patterns++;
            return;
        end
        if($isunknown({tr.inst_seq, tr.inst_lat})) begin
            skipped_patterns++;
            return;
        end
        for(int i = 0; i < 8; i++) begin
            latency[i] = int'(tr.inst_lat[i*6 +: 6]);
            if(latency[i] < minimum_latency(op_typ'(i)) || latency[i] > maximum_latency(op_typ'(i))) begin
                skipped_patterns++;
                return;
            end
        end

        for(int i = 0; i < 8; i++) begin
            configured_opcode = op_typ'(i);
            configured_latency = classify_latency(configured_opcode, latency[i]);
            configured_latency_cg.sample();

            opcode = op_typ'(tr.inst_seq[i*12 + 9 +: 3]);
            position = i[2:0];
            instruction_latency = classify_latency(opcode, latency[opcode]);
            instruction_cg.sample();
            instruction_latency_cg.sample();
        end
        analyze_graph(tr.inst_seq);
        if(graph == INVALID_GRAPH) invalid_graphs++;
        pattern_cg.sample();
        sampled_patterns++;
    endfunction

    //=============================================================
    //                           Reporting
    //=============================================================

    function void report();
        $display("================================================================");
        $display("                  Functional Coverage Report");
        $display("Sampled patterns = %0d, skipped = %0d, invalid graphs = %0d",
            sampled_patterns, skipped_patterns, invalid_graphs);
        $display("Opcode                 = %0.2f%%", instruction_cg.cp_opcode.get_inst_coverage());
        $display("Instruction position   = %0.2f%%", instruction_cg.cp_position.get_inst_coverage());
        $display("Opcode x position      = %0.2f%%", instruction_cg.cx_opcode_position.get_inst_coverage());
        $display("Configured latency     = %0.2f%%", configured_latency_cg.get_inst_coverage());
        $display("Instruction latency    = %0.2f%%", instruction_latency_cg.get_inst_coverage());
        $display("RAW absent/present     = %0.2f%%", pattern_cg.cp_raw.get_inst_coverage());
        $display("WAR absent/present     = %0.2f%%", pattern_cg.cp_war.get_inst_coverage());
        $display("WAW absent/present     = %0.2f%%", pattern_cg.cp_waw.get_inst_coverage());
        $display("Graph type             = %0.2f%%", pattern_cg.cp_graph.get_inst_coverage());
        $display("Single-chain length    = %0.2f%%", pattern_cg.cp_single_length.get_inst_coverage());
        $display("Two-chain lengths      = %0.2f%%", pattern_cg.cp_two_lengths.get_inst_coverage());
        $display("================================================================");
    endfunction
endclass
