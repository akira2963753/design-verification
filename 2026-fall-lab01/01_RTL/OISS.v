module OISS (
    input  [95:0] Inst_seq_I,
    input  [47:0] Inst_latency_I,
    output [23:0] Inst_order_O,
    output [8:0]  Ex_cycle
);

    wire [11:0] Inst_seq_I_split [0:7];
    wire [5:0] opcode_latency [0:7];
    wire [5:0] inst_lat [0:7];
    wire [2:0] opcode [0:7];
    wire [2:0] rs [0:7];
    wire [2:0] rt [0:7];
    wire [2:0] rd [0:7];
    wire writes_rd [0:7];
    wire reads_rs_rt [0:7];
    wire is_store [0:7];
    wire dep [0:7][0:7];

    genvar i, j, op;
    generate
        for (op = 0; op < 8; op = op + 1) begin : gen_op_lat
            // Each input entry specifies the latency of one opcode.
            assign opcode_latency[op] = Inst_latency_I[op*6 +: 6];
        end

        for (i = 0; i < 8; i = i + 1) begin : gen_decode
            assign Inst_seq_I_split[i] = Inst_seq_I[i*12 +: 12];

            assign opcode[i] = Inst_seq_I_split[i][11:9];
            // Instructions with the same opcode share the same latency.
            assign inst_lat[i] = opcode_latency[opcode[i]];
            assign rs[i] = Inst_seq_I_split[i][8:6];
            assign rt[i] = Inst_seq_I_split[i][5:3];
            assign rd[i] = Inst_seq_I_split[i][2:0];

            assign writes_rd[i] = !opcode[i][2] | (opcode[i] == 3'b100);    //ADD,SUB,MUL,DIV,LOAD
            assign reads_rs_rt[i] = !opcode[i][2] | (opcode[i] == 3'b110);  //ADD,SUB,MUL,DIV,BRANCH
            assign is_store[i] = (opcode[i] == 3'b101);                     //STORE
        end

        for (i = 0; i < 8; i = i + 1) begin : gen_dep_row
            for (j = 0; j < 8; j = j + 1) begin : gen_dep_col
                if (i < j) begin : gen_forward
                    // dep[i][j] means instruction i must finish before j starts.
                    // Register zero is a normal register in this lab.
                    // Share the rd comparison across WAW and STORE hazards.
                    assign dep[i][j] =
                        (writes_rd[i] & reads_rs_rt[j] &            //RAW   i_write , j_read
                         ((rd[i] == rs[j]) | (rd[i] == rt[j]))) |
                        (writes_rd[j] & reads_rs_rt[i] &            //WAR   j_write , i_read
                         ((rd[j] == rs[i]) | (rd[j] == rt[i]))) |
                        ((rd[i] == rd[j]) &                         //WAW, STORE
                         ((writes_rd[i] & writes_rd[j]) |
                          (writes_rd[i] & is_store[j]) |            //RAW
                          (is_store[i] & writes_rd[j])));           //WAR
                end else begin : gen_unused
                    assign dep[i][j] = 1'b0;
                end
            end
        end
    endgenerate

    // Select the earliest instruction with an outgoing dependency as A's head.
    // Propagate membership along forward edges, including redundant edges.
    wire [7:0] has_out;
    wire [7:0] seed_a;
    wire [7:0] member_a;
    wire [7:0] member_b;
    wire b_is_chain;

    genvar g, h;
    generate
        for (g = 0; g < 8; g = g + 1) begin : gen_chain_group
            wire [7:0] outgoing;
            wire [7:0] from_a;

            for (h = 0; h < 8; h = h + 1) begin : gen_group_edge
                assign outgoing[h] = dep[g][h];

                if (h < g) begin : gen_predecessor
                    assign from_a[h] = dep[h][g] & member_a[h];
                end else begin : gen_unused
                    assign from_a[h] = 1'b0;
                end
            end

            assign has_out[g] = |outgoing;

            if (g == 0) begin : gen_first_seed
                assign seed_a[g] = has_out[g];
            end else begin : gen_later_seed
                assign seed_a[g] = has_out[g] & ~(|has_out[g-1:0]);
            end

            assign member_a[g] = seed_a[g] | (|from_a);
        end
    endgenerate

    assign member_b = ~member_a;
    // Under the graph constraints, B is either one chain or independent jobs.
    assign b_is_chain = |(member_b & has_out);

    // Balanced population count; the result must represent all eight members.
    function [3:0] count_members;
        input [7:0] bits;
        reg [1:0] pair_0, pair_1, pair_2, pair_3;
        reg [2:0] half_0, half_1;
        begin
            pair_0 = {1'b0, bits[0]} + {1'b0, bits[1]};
            pair_1 = {1'b0, bits[2]} + {1'b0, bits[3]};
            pair_2 = {1'b0, bits[4]} + {1'b0, bits[5]};
            pair_3 = {1'b0, bits[6]} + {1'b0, bits[7]};
            half_0 = {1'b0, pair_0} + {1'b0, pair_1};
            half_1 = {1'b0, pair_2} + {1'b0, pair_3};
            count_members = {1'b0, half_0} + {1'b0, half_1};
        end
    endfunction

    wire [3:0] length_a;
    wire [3:0] length_b;
    wire [2:0] rank_a [0:7];

    assign length_a = count_members(member_a);
    assign length_b = 4'd8 - length_a;

    // Compare each unordered pair once. Equal latencies favor the lower index.
    wire before_latency [0:7][0:7];
    wire [2:0] rank_b [0:7];
    wire [7:0] select_a [0:7];
    wire [7:0] select_b [0:7];
    wire [2:0] seq_a_index [0:7];
    wire [2:0] seq_b_index [0:7];
    wire [5:0] seq_a_lat [0:7];
    wire [5:0] seq_b_lat [0:7];
    genvar lane, peer, field_bit;
    generate
        for (lane = 0; lane < 8; lane = lane + 1) begin : gen_latency_rank
            wire [7:0] ahead_a;
            wire [7:0] ahead_b;
            wire [3:0] rank_a_count;
            wire [3:0] rank_b_count;

            for (peer = 0; peer < 8; peer = peer + 1) begin : gen_before
                if (lane < peer) begin : gen_compare
                    assign before_latency[lane][peer] =
                        inst_lat[lane] >= inst_lat[peer];
                end else if (lane > peer) begin : gen_reverse
                    assign before_latency[lane][peer] =
                        ~before_latency[peer][lane];
                end else begin : gen_self
                    assign before_latency[lane][peer] = 1'b0;
                end

                assign ahead_a[peer] = member_a[peer] & (peer < lane);
                assign ahead_b[peer] = member_b[peer] &
                    (b_is_chain ? (peer < lane) : before_latency[peer][lane]);
            end

            assign rank_a_count = count_members(ahead_a);
            assign rank_b_count = count_members(ahead_b);
            // Self is excluded, so each rank is at most seven.
            assign rank_a[lane] = rank_a_count[2:0];
            assign rank_b[lane] = rank_b_count[2:0];
        end

        // A slot shares its one-hot selection across index and latency bits.
        // No selected member means both outputs are zero for that slot.
        for (lane = 0; lane < 8; lane = lane + 1) begin : gen_sequence_slot
            localparam [2:0] SLOT_INDEX = lane;
            for (peer = 0; peer < 8; peer = peer + 1) begin : gen_slot_select
                assign select_a[lane][peer] =
                    member_a[peer] & (rank_a[peer] == SLOT_INDEX);
                assign select_b[lane][peer] =
                    member_b[peer] & (rank_b[peer] == SLOT_INDEX);
            end

            for (field_bit = 0; field_bit < 9; field_bit = field_bit + 1) begin : gen_payload
                wire [7:0] masked_a;
                wire [7:0] masked_b;
                for (peer = 0; peer < 8; peer = peer + 1) begin : gen_source
                    localparam [2:0] SOURCE_INDEX = peer;
                    if (field_bit < 3) begin : gen_index_bit
                        assign masked_a[peer] = select_a[lane][peer] & SOURCE_INDEX[field_bit];
                        assign masked_b[peer] = select_b[lane][peer] & SOURCE_INDEX[field_bit];
                    end else begin : gen_latency_bit
                        assign masked_a[peer] = select_a[lane][peer] & inst_lat[peer][field_bit-3];
                        assign masked_b[peer] = select_b[lane][peer] & inst_lat[peer][field_bit-3];
                    end
                end
                if (field_bit < 3) begin : gen_index_output
                    assign seq_a_index[lane][field_bit] = |masked_a;
                    assign seq_b_index[lane][field_bit] = |masked_b;
                end else begin : gen_latency_output
                    assign seq_a_lat[lane][field_bit-3] = |masked_a;
                    assign seq_b_lat[lane][field_bit-3] = |masked_b;
                end
            end
        end
    endgenerate

    function integer ones;
        input integer value;
        integer bit_pos;
        begin
            ones = 0;
            for (bit_pos = 0; bit_pos < 9; bit_pos = bit_pos + 1)
                ones = ones + ((value >> bit_pos) & 1);
        end
    endfunction

    function [8:0] max_time;
        input [8:0] left_time;
        input [8:0] right_time;
        begin
            max_time = (left_time >= right_time) ? left_time : right_time;
        end
    endfunction

    // Three states per prefix. finish_b_max is also B's ready time in chain mode.
    // Only six choices are expanded; a local solver handles the last two.
    wire [8:0] next_issue [1:127];
    wire [8:0] finish_a [1:127];
    wire [8:0] finish_b_max [1:127];
    assign next_issue[1] = 9'd0;
    assign finish_a[1] = 9'd0;
    assign finish_b_max[1] = 9'd0;
    genvar depth, node;
    generate
        for (depth = 1; depth <= 6; depth = depth + 1) begin : gen_depth
            for (node = (1 << depth); node < (1 << (depth+1)); node = node + 1) begin : gen_prefix
                localparam PARENT = node / 2;
                localparam USED_A = ones(PARENT) - 1;
                localparam USED_B = depth - 1 - USED_A;
                wire [8:0] start_time;
                wire [8:0] end_time;
                if ((node % 2) == 1) begin : gen_a
                    // Consecutive valid A jobs have latency >= 1, so finish wins.
                    if ((depth > 1) && ((PARENT % 2) == 1)) begin : gen_same_chain
                        assign start_time = finish_a[PARENT];
                    end else begin : gen_ready_check
                        assign start_time = max_time(next_issue[PARENT], finish_a[PARENT]);
                    end
                    assign end_time = start_time + {3'b0, seq_a_lat[USED_A]};
                    assign finish_a[node] = end_time;
                    assign finish_b_max[node] = finish_b_max[PARENT];
                end else begin : gen_b
                    if ((depth > 1) && ((PARENT % 2) == 0)) begin : gen_same_sequence
                        assign start_time = b_is_chain ? finish_b_max[PARENT] : next_issue[PARENT];
                    end else begin : gen_ready_check
                        assign start_time = b_is_chain ?
                            max_time(next_issue[PARENT], finish_b_max[PARENT]) : next_issue[PARENT];
                    end
                    assign end_time = start_time + {3'b0, seq_b_lat[USED_B]};
                    assign finish_a[node] = finish_a[PARENT];
                    assign finish_b_max[node] = b_is_chain ? end_time :
                        max_time(finish_b_max[PARENT], end_time);
                end
                assign next_issue[node] = start_time + 9'd1;
            end
        end
    endgenerate

    wire [8:0] length_match;
    // Share adjacent-pair costs across all two-instruction tail solvers.
    wire [6:0] pair_a_sum [0:6];
    wire [6:0] pair_b_cost [0:6];
    genvar size;
    generate
        for (size = 0; size <= 8; size = size + 1) begin : gen_length_match
            localparam [3:0] SEQUENCE_LENGTH = size;
            assign length_match[size] = (length_a == SEQUENCE_LENGTH);
        end
        for (size = 0; size < 7; size = size + 1) begin : gen_pair_cost
            wire [6:0] b_sum;
            wire [6:0] b_second_end;
            wire [6:0] b_overlap;
            assign pair_a_sum[size] = {1'b0, seq_a_lat[size]} + {1'b0, seq_a_lat[size+1]};
            assign b_sum = {1'b0, seq_b_lat[size]} + {1'b0, seq_b_lat[size+1]};
            assign b_second_end = 7'd1 + {1'b0, seq_b_lat[size+1]};
            assign b_overlap = ({1'b0, seq_b_lat[size]} >= b_second_end) ?
                {1'b0, seq_b_lat[size]} : b_second_end;
            assign pair_b_cost[size] = b_is_chain ? b_sum : b_overlap;
        end
    endgenerate

    wire [8:0] best_cycle [1:127];
    wire [7:0] best_mask [1:127];
    generate
        for (node = 64; node < 128; node = node + 1) begin : gen_tail
            localparam USED_A = ones(node) - 1;
            localparam USED_B = 6 - USED_A;
            localparam [5:0] PREFIX_MASK = node - 64;
            wire [8:0] start_a;
            wire [8:0] start_b;
            wire [8:0] end_a;
            wire [8:0] end_b;
            wire [8:0] end_b_after_a;
            wire [8:0] end_a_after_b;
            wire [8:0] cycle_aa;
            wire [8:0] cycle_bb;
            wire [8:0] cycle_ab;
            wire [8:0] cycle_ba;
            wire choose_ba;
            wire [8:0] mixed_cycle;
            wire [1:0] mixed_mask;
            wire [1:0] suffix_mask;

            // The sixth choice is constant. Eliminate its same-chain ready max.
            // Invalid prefixes remain excluded by the length checks below.
            if ((node % 2) == 1) begin : gen_after_a
                assign start_a = finish_a[node];
                assign start_b = b_is_chain ?
                    max_time(next_issue[node], finish_b_max[node]) : next_issue[node];
            end else begin : gen_after_b
                assign start_a = max_time(next_issue[node], finish_a[node]);
                assign start_b = b_is_chain ? finish_b_max[node] : next_issue[node];
            end
            assign end_a = start_a + {3'b0, seq_a_lat[USED_A]};
            assign end_b = start_b + {3'b0, seq_b_lat[USED_B]};

            // AA is serial. BB is serial only when B is a dependency chain.
            // These formulas are used only for tails with matching lengths.
            assign cycle_aa = max_time(finish_b_max[node],
                start_a + {2'b0, pair_a_sum[USED_A]});
            assign cycle_bb = max_time(max_time(finish_a[node], finish_b_max[node]),
                start_b + {2'b0, pair_b_cost[USED_B]});

            assign end_b_after_a = max_time(start_a + 9'd1,
                b_is_chain ? finish_b_max[node] : 9'd0) + {3'b0, seq_b_lat[USED_B]};
            assign end_a_after_b = max_time(start_b + 9'd1, finish_a[node]) +
                {3'b0, seq_a_lat[USED_A]};
            assign cycle_ab = max_time(finish_b_max[node], max_time(end_a, end_b_after_a));
            assign cycle_ba = max_time(finish_b_max[node], max_time(end_b, end_a_after_b));
            // BA (01) wins ties over AB (10), preserving ascending-mask ties.
            assign choose_ba = cycle_ba <= cycle_ab;
            assign mixed_cycle = choose_ba ? cycle_ba : cycle_ab;
            assign mixed_mask = choose_ba ? 2'b01 : 2'b10;

            assign best_cycle[node] = length_match[USED_A] ? cycle_bb :
                length_match[USED_A+1] ? mixed_cycle :
                length_match[USED_A+2] ? cycle_aa : 9'd511;
            assign suffix_mask = length_match[USED_A] ? 2'b00 :
                length_match[USED_A+1] ? mixed_mask : 2'b11;
            assign best_mask[node] = {PREFIX_MASK, suffix_mask};
        end

        // Six balanced levels select among the 64 locally solved prefixes.
        for (node = 1; node < 64; node = node + 1) begin : gen_minimum
            wire choose_left;
            assign choose_left = best_cycle[2*node] <= best_cycle[2*node+1];
            assign best_cycle[node] = choose_left ? best_cycle[2*node] : best_cycle[2*node+1];
            assign best_mask[node] = choose_left ? best_mask[2*node] : best_mask[2*node+1];
        end
    endgenerate
    assign Ex_cycle = best_cycle[1];

    // Count only choices before the current issue, using balanced popcounts.
    // Reconstruction uses dynamic selection; evaluation above uses constants.
    wire [3:0] count_a [0:7];
    wire [3:0] count_b [0:7];
    generate
        for (lane = 0; lane < 8; lane = lane + 1) begin : gen_output
            localparam [3:0] ISSUE_POSITION = lane;
            wire [7:0] earlier_choices;
            wire take_a;
            wire [2:0] selected_a;
            wire [2:0] selected_b;
            assign earlier_choices = best_mask[1] >> (8-lane);
            assign count_a[lane] = count_members(earlier_choices);
            assign count_b[lane] = ISSUE_POSITION - count_a[lane];
            assign take_a = best_mask[1][7-lane];
            // All array addresses are three bits, even on the unused branch.
            assign selected_a = seq_a_index[count_a[lane][2:0]];
            assign selected_b = seq_b_index[count_b[lane][2:0]];
            assign Inst_order_O[lane*3 +: 3] = take_a ?
                selected_a : selected_b;
        end
    endgenerate
endmodule
