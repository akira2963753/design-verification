/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    trans.sv
* Project:      2026 FALL NYCU IC LAB, LAB01
* Module:       transcation
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/


//=============================================================
//                      Common Definitions
//=============================================================

typedef enum bit [2:0] {
    ADD, SUB, MUL, DIV,
    LOAD, STORE, BRANCH, JUMP
} op_typ;

typedef enum bit [1:0] {
    NO_CHAIN,
    ONE_CHAIN,
    TWO_CHAINS,
    INVALID_GRAPH
} graph_typ;

typedef struct packed {
    op_typ op;
    bit [2:0] rs;
    bit [2:0] rt;
    bit [2:0] rd;
} inst_typ;

//=============================================================
//                     Transaction Definition
//=============================================================
class txn;
    rand inst_typ inst[8];
    rand bit [5:0] lat[8];
    rand bit [7:0] read_mask[8];
    rand bit [7:0] write_mask[8];
    rand graph_typ tar_graph;
    rand bit [2:0] two_chain_short_len;

    rand bit raw[8][8];
    rand bit war[8][8];
    rand bit waw[8][8];

    rand bit [7:0][7:0] dep_edge;
    rand bit [7:0][7:0] dep_edge_inv;
    rand bit [7:0][7:0] reach;
    rand bit [7:0][7:0] reach_inv;
    rand bit [7:0][7:0] chain_edge;
    rand bit [7:0][7:0] chain_edge_inv;
    rand bit [7:0] chain_mask;

    bit [95:0] inst_seq;
    bit [47:0] inst_lat;

    //=============================================================
    //                         Constraints
    //=============================================================

    // Encode the SPEC ReadSet and WriteSet table.
    constraint rw_set_c {
        foreach(inst[i]) {
            if(inst[i].op inside {ADD, SUB, MUL, DIV}) {
                read_mask[i] == ((8'd1 << inst[i].rs) | (8'd1 << inst[i].rt));
                write_mask[i] == (8'd1 << inst[i].rd);
            }
            else if(inst[i].op == LOAD) {
                read_mask[i] == '0;
                write_mask[i] == (8'd1 << inst[i].rd);
            }
            else if(inst[i].op == STORE) {
                read_mask[i] == (8'd1 << inst[i].rd);
                write_mask[i] == '0;
            }
            else if(inst[i].op == BRANCH) {
                read_mask[i] == ((8'd1 << inst[i].rs) | (8'd1 << inst[i].rt));
                write_mask[i] == '0;
            }
            else {
                read_mask[i] == '0;
                write_mask[i] == '0;
            }
        }
    }

    constraint dep_c {
        foreach(raw[i, j]) {
            if(i < j) {
                raw[i][j] == |(write_mask[i] & read_mask[j]);
                war[i][j] == |(read_mask[i] & write_mask[j]);
                waw[i][j] == |(write_mask[i] & write_mask[j]);
            }
            else {
                raw[i][j] == 1'b0;
                war[i][j] == 1'b0;
                waw[i][j] == 1'b0;
            }
        }
    }

    constraint edge_c {
        foreach(dep_edge[i, j]) {
            if(i < j) {
                // Preserve every RAW, WAR, and WAW edge from Ii to Ij.
                dep_edge[i][j] == (raw[i][j] || war[i][j] || waw[i][j]);
                // Transpose the dependency matrix.
                dep_edge_inv[j][i] == dep_edge[i][j];
            }
            else {
                dep_edge[i][j] == 1'b0;
                dep_edge_inv[j][i] == 1'b0;
            }
        }
    }

    // All paths advance in original instruction index, making this recurrence
    // acyclic. A path starts with a direct edge and continues to its target.
    constraint reach_c {
        foreach(reach[i, j]) {
            if(i < j) reach[i][j] == (dep_edge[i][j] || (|(dep_edge[i] & reach_inv[j])));
            else reach[i][j] == 1'b0;
            reach_inv[j][i] == reach[i][j];
        }
    }

    // Remove a direct edge only when an intermediate vertex provides a path.
    constraint chain_edge_c {
        foreach(chain_edge[i, j]) {
            chain_edge[i][j] == (dep_edge[i][j] && !(|(reach[i] & reach_inv[j])));
            chain_edge_inv[j][i] == chain_edge[i][j];
        }
        foreach(chain_mask[i]) chain_mask[i] == ((|chain_edge[i]) || (|chain_edge_inv[i]));
    }

    constraint graph_c {
        tar_graph inside {NO_CHAIN, ONE_CHAIN, TWO_CHAINS};

        foreach(chain_edge[i]) $countones(chain_edge[i]) <= 1;
        foreach(chain_edge_inv[i]) $countones(chain_edge_inv[i]) <= 1;

        if(tar_graph == NO_CHAIN) dep_edge == '0;
        else if(tar_graph == ONE_CHAIN) {
            $countones(chain_mask) inside {[2:8]};
            $countones(chain_edge) == ($countones(chain_mask) - 1);
        }
        else if(tar_graph == TWO_CHAINS) {
            $countones(chain_edge) == 6;
            chain_mask == '1;
        }
    }

    // Choose an unordered length pair without fixing chain membership or layout.
    constraint two_chain_length_c {
        if(tar_graph == TWO_CHAINS) {
            two_chain_short_len dist {2 := 1, 3 := 1, 4 := 1};
            foreach(chain_edge_inv[i]) {
                // A chain head reaches every other instruction in its chain.
                if(chain_edge_inv[i] == '0) {
                    (1 + $countones(reach[i])) inside {
                        int'(two_chain_short_len), (8 - int'(two_chain_short_len))
                    };
                }
            }
        }
        else two_chain_short_len == 0;
    }

    // Choose graph type, then length pair, then the instruction realization.
    constraint solve_order_c {
        solve tar_graph before two_chain_short_len;
        solve two_chain_short_len before inst;
        solve tar_graph before inst;
    }
    
    constraint lat_c {
        // Endpoints each receive 25%; the middle range shares 50% equally.
        lat[ADD] dist {1 := 1, [2:4] :/ 2, 5 := 1};
        lat[SUB] dist {1 := 1, [2:4] :/ 2, 5 := 1};
        lat[MUL] dist {20 := 1, [21:39] :/ 2, 40 := 1};
        lat[DIV] dist {30 := 1, [31:49] :/ 2, 50 := 1};
        lat[LOAD] dist {6 := 1, [7:9] :/ 2, 10 := 1};
        lat[STORE] dist {6 := 1, [7:9] :/ 2, 10 := 1};
        lat[BRANCH] dist {2 := 1, 3 := 2, 4 := 1};
        lat[JUMP] == 1;
    }

    constraint mem_addr_c {
        foreach(inst[i]) {
            foreach(inst[j]) {
                if((i < j) && ({inst[i].op, inst[j].op} inside {
                    {STORE, LOAD}, {LOAD, STORE}, {STORE, STORE}})) {
                    {inst[i].rs, inst[i].rt} != {inst[j].rs, inst[j].rt};
                }
            }
        }
    }

    //=============================================================
    //                        Input Packing
    //=============================================================

    function void print(int unsigned testcase);
        `ifdef PRINT
            $display("================================================================");
            $display("                 TEST PATTERN [%0d] - [%0s]", testcase, tar_graph);
            if(tar_graph == TWO_CHAINS) $display("Chain lengths = %0d + %0d", two_chain_short_len, 8 - int'(two_chain_short_len));
            $display("================================================================");
            foreach(inst[i]) begin
                $display("Inst[%0d]: Op = %0s | Rs = %0d | Rt = %0d | Rd = %0d",
                        i, inst[i].op.name(), inst[i].rs, inst[i].rt, inst[i].rd);
            end
            $display("================================================================");
        `endif
    endfunction

    function void pack_input();
        foreach(inst[i]) begin
            inst_seq[i*12 +: 12] = inst[i];
            inst_lat[i*6 +: 6] = lat[i];
        end
    endfunction

    function void post_randomize();
        pack_input();
    endfunction

endclass

//=============================================================
//                     Directed 2 Transaction
//=============================================================

class directed_2_txn extends txn;
    // Configured before randomize: 0 = symmetric/position sweep,
    // 1 = near-balanced, 2 = unequal lengths with short latencies.
    int scenario;
    int a_length = 4;
    int long_pos_a = 1;
    int long_pos_b = 1;
    int total_gap;
    bit replay_short_shape;

    rand bit [7:0] member_a;
    rand int a_latency[8];
    rand int b_latency[8];
    rand op_typ long_op;

    constraint structure_c {
        tar_graph == TWO_CHAINS;
        int'(two_chain_short_len) == a_length;
        $countones(member_a) == a_length;
        foreach(dep_edge[i, j]) {
            if(i < j) dep_edge[i][j] == (member_a[i] == member_a[j]);
        }
        foreach(a_latency[i]) {
            if(i >= a_length) a_latency[i] == 0;
            else a_latency[i] inside {[1:50]};
            if(i >= (8 - a_length)) b_latency[i] == 0;
            else b_latency[i] inside {[1:50]};
        }
        // Keep countones in a condition: older VCS cannot use it as an index.
        foreach(inst[i]) {
            foreach(a_latency[j]) {
                if(member_a[i] && ($countones(member_a & ((8'b1 << i) - 8'b1)) == j)) {
                    int'(lat[inst[i].op]) == a_latency[j];
                }
                if(!member_a[i] && ($countones((~member_a) & ((8'b1 << i) - 8'b1)) == j)) {
                    int'(lat[inst[i].op]) == b_latency[j];
                }
            }
        }
    }

    constraint profile_c {
        if(scenario == 0) {
            long_op inside {MUL, DIV, LOAD};
            foreach(a_latency[i]) {
                if(i < 4) {
                    if(i == long_pos_a) a_latency[i] == int'(lat[long_op]);
                    else a_latency[i] == 1;
                    if(i == long_pos_b) b_latency[i] == int'(lat[long_op]);
                    else b_latency[i] == 1;
                }
            }
        }
        else {
            long_op == ADD;
            if(scenario == 1) {
                (a_latency.sum() == b_latency.sum() + total_gap) ||
                (b_latency.sum() == a_latency.sum() + total_gap);
                // This scenario has two length-4 chains; inactive entries are zero.
                (a_latency[0] != b_latency[0]) ||
                (a_latency[1] != b_latency[1]) ||
                (a_latency[2] != b_latency[2]) ||
                (a_latency[3] != b_latency[3]);
            }
            else {
                foreach(a_latency[i]) {
                    if(i < a_length) a_latency[i] inside {[1:3]};
                    if(i < (8 - a_length)) b_latency[i] inside {[1:3]};
                }
                if(replay_short_shape) {
                    a_latency[0] == 1; a_latency[1] == 3; a_latency[2] == 1;
                    b_latency[0] == 1; b_latency[1] == 2; b_latency[2] == 2;
                    b_latency[3] == 1; b_latency[4] == 1;
                }
            }
        }
    }
endclass

//=============================================================
//                     Monitor Transaction
//=============================================================

class mon_txn;
    int unsigned testcase;
    logic [95:0] inst_seq;
    logic [47:0] inst_lat;
    logic [23:0] inst_order;
    logic [8:0] ex_cycle;
endclass
