/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    coverage.sv
* Project:      2026 FALL NYCU IC LAB, LAB01
* Module:       OISS Functional Coverage
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

typedef enum bit [3:0] {
    TOPO_NO_CHAIN,
    TOPO_ONE_CHAIN_2,
    TOPO_ONE_CHAIN_3,
    TOPO_ONE_CHAIN_4,
    TOPO_ONE_CHAIN_5,
    TOPO_ONE_CHAIN_6,
    TOPO_ONE_CHAIN_7,
    TOPO_ONE_CHAIN_8,
    TOPO_TWO_CHAIN_2_6,
    TOPO_TWO_CHAIN_3_5,
    TOPO_TWO_CHAIN_4_4,
    TOPO_INVALID
} topology_typ;

class coverage;
    mailbox #(txn) drv2cov;
    int unsigned pattern_num;

    //=============================================================
    //                     Functional Coverage
    //=============================================================

    covergroup cg_crv with function sample(
        int position,
        op_typ opcode,
        int latency,
        topology_typ topology
    );
        option.per_instance = 1;

        cp_position: coverpoint position {
            bins position[] = {[0:7]};
        }

        cp_opcode: coverpoint opcode {
            bins opcode[] = {[ADD:JUMP]};
        }

        cp_latency: coverpoint latency {
            bins latency[] = {[1:50]};
        }

        cp_topology: coverpoint topology {
            bins no_chain = {TOPO_NO_CHAIN};
            bins one_chain[] = {
                TOPO_ONE_CHAIN_2,
                TOPO_ONE_CHAIN_3,
                TOPO_ONE_CHAIN_4,
                TOPO_ONE_CHAIN_5,
                TOPO_ONE_CHAIN_6,
                TOPO_ONE_CHAIN_7,
                TOPO_ONE_CHAIN_8
            };
            bins two_chain[] = {
                TOPO_TWO_CHAIN_2_6,
                TOPO_TWO_CHAIN_3_5,
                TOPO_TWO_CHAIN_4_4
            };
            illegal_bins invalid = {TOPO_INVALID};
        }

        cr_crv: cross cp_position, cp_opcode, cp_latency, cp_topology {
            ignore_bins add_sub_invalid =
                binsof(cp_opcode) intersect {ADD, SUB} &&
                binsof(cp_latency) intersect {[6:50]};

            ignore_bins mul_invalid =
                binsof(cp_opcode) intersect {MUL} &&
                binsof(cp_latency) intersect {[1:19], [41:50]};

            ignore_bins div_invalid =
                binsof(cp_opcode) intersect {DIV} &&
                binsof(cp_latency) intersect {[1:29]};

            ignore_bins load_store_invalid =
                binsof(cp_opcode) intersect {LOAD, STORE} &&
                binsof(cp_latency) intersect {[1:5], [11:50]};

            ignore_bins branch_invalid =
                binsof(cp_opcode) intersect {BRANCH} &&
                binsof(cp_latency) intersect {1, [5:50]};

            ignore_bins jump_invalid =
                binsof(cp_opcode) intersect {JUMP} &&
                binsof(cp_latency) intersect {[2:50]};

            // JUMP has no dependency and cannot belong to a graph containing
            // all eight instructions in one or two dependency chains.
            ignore_bins jump_full_graph =
                binsof(cp_opcode) intersect {JUMP} &&
                binsof(cp_topology) intersect {
                    TOPO_ONE_CHAIN_8,
                    TOPO_TWO_CHAIN_2_6,
                    TOPO_TWO_CHAIN_3_5,
                    TOPO_TWO_CHAIN_4_4
                };
        }
    endgroup

    //=============================================================
    //                         Constructor
    //=============================================================

    function new(input mailbox #(txn) drv2cov, input int unsigned pattern_num);
        this.drv2cov = drv2cov;
        this.pattern_num = pattern_num;
        cg_crv = new();
    endfunction

    //=============================================================
    //                       Input Sampling
    //=============================================================

    local function automatic topology_typ get_topology(input txn tr);
        case(tr.tar_graph)
            NO_CHAIN: return TOPO_NO_CHAIN;
            ONE_CHAIN: begin
                case($countones(tr.chain_mask))
                    2: return TOPO_ONE_CHAIN_2;
                    3: return TOPO_ONE_CHAIN_3;
                    4: return TOPO_ONE_CHAIN_4;
                    5: return TOPO_ONE_CHAIN_5;
                    6: return TOPO_ONE_CHAIN_6;
                    7: return TOPO_ONE_CHAIN_7;
                    8: return TOPO_ONE_CHAIN_8;
                    default: return TOPO_INVALID;
                endcase
            end
            TWO_CHAINS: begin
                case(tr.two_chain_short_len)
                    2: return TOPO_TWO_CHAIN_2_6;
                    3: return TOPO_TWO_CHAIN_3_5;
                    4: return TOPO_TWO_CHAIN_4_4;
                    default: return TOPO_INVALID;
                endcase
            end
            default: return TOPO_INVALID;
        endcase
    endfunction

    local function automatic void sample_input(input txn tr);
        topology_typ topology;

        topology = get_topology(tr);
        foreach(tr.inst[i]) begin
            cg_crv.sample(
                i,
                tr.inst[i].op,
                int'(tr.lat[tr.inst[i].op]),
                topology
            );
        end
    endfunction

    //=============================================================
    //                          Run Task
    //=============================================================

    task run();
        txn tr;

        repeat(pattern_num) begin
            drv2cov.get(tr);
            if(tr.is_random) sample_input(tr);
        end
    endtask
endclass
