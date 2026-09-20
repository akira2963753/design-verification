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
    bit is_random;

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
        is_random = 1'b1;
    endfunction

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
