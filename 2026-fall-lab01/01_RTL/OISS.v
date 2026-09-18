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

            assign writes_rd[i] = !opcode[i][2] | (opcode[i] == 3'b100);
            assign reads_rs_rt[i] = !opcode[i][2] | (opcode[i] == 3'b110);
            assign is_store[i] = (opcode[i] == 3'b101);
        end

        for (i = 0; i < 8; i = i + 1) begin : gen_dep_row
            for (j = 0; j < 8; j = j + 1) begin : gen_dep_col
                if (i < j) begin : gen_forward
                    // dep[i][j] means instruction i must finish before j starts.
                    // Register zero is a normal register in this lab.
                    // Share the rd comparison across WAW and STORE hazards.
                    assign dep[i][j] =
                        (writes_rd[i] & reads_rs_rt[j] &
                         ((rd[i] == rs[j]) | (rd[i] == rt[j]))) |
                        (writes_rd[j] & reads_rs_rt[i] &
                         ((rd[j] == rs[i]) | (rd[j] == rt[i]))) |
                        ((rd[i] == rd[j]) &
                         ((writes_rd[i] & writes_rd[j]) |
                          (writes_rd[i] & is_store[j]) |
                          (is_store[i] & writes_rd[j])));
                end else begin : gen_unused
                    assign dep[i][j] = 1'b0;
                end
            end
        end
    endgenerate

    // Label each chain by its earliest instruction. The specified input
    // graphs are disjoint chains (possibly with redundant forward edges).
    reg [2:0] root [0:7];
    reg [7:0] connected;
    reg [2:0] root_a;
    reg [7:0] member_a;
    reg [3:0] length_a;
    reg b_is_chain;
    integer r, p;
    always @* begin
        connected = 8'b0;
        for (r = 0; r < 8; r = r + 1) begin
            root[r] = r;
            for (p = 0; p < r; p = p + 1) begin
                if (dep[p][r])
                    root[r] = root[p];
            end
            for (p = 0; p < 8; p = p + 1)
                connected[r] = connected[r] | dep[r][p] | dep[p][r];
        end
        root_a = 3'd0;
        for (r = 7; r >= 0; r = r - 1)
            if (connected[r]) root_a = root[r];

        member_a = 8'b0;
        length_a = 4'd0;
        b_is_chain = 1'b0;
        for (r = 0; r < 8; r = r + 1) begin
            member_a[r] = connected[r] && (root[r] == root_a);
            length_a = length_a + {3'b0, member_a[r]};
            b_is_chain = b_is_chain | (connected[r] && !member_a[r]);
        end
    end

    // Pairwise latency comparisons run in parallel with chain grouping.
    // A uses original index order. B uses index order for a second chain,
    // or descending latency (then ascending index) for independent jobs.
    wire before_latency [0:7][0:7];
    reg [3:0] rank_a [0:7];
    reg [3:0] rank_b [0:7];
    reg [2:0] seq_a_index [0:7];
    reg [2:0] seq_b_index [0:7];
    wire [5:0] seq_a_lat [0:7];
    wire [5:0] seq_b_lat [0:7];
    genvar lane, peer;
    generate
        for (lane = 0; lane < 8; lane = lane + 1) begin : gen_latency_rank
            for (peer = 0; peer < 8; peer = peer + 1) begin : gen_before
                assign before_latency[lane][peer] =
                    (inst_lat[lane] > inst_lat[peer]) |
                    ((inst_lat[lane] == inst_lat[peer]) && (lane < peer));
            end
            assign seq_a_lat[lane] = inst_lat[seq_a_index[lane]];
            assign seq_b_lat[lane] = inst_lat[seq_b_index[lane]];
        end
    endgenerate

    integer u, v, slot;
    always @* begin
        for (u = 0; u < 8; u = u + 1) begin
            rank_a[u] = 4'd0;
            rank_b[u] = 4'd0;
            for (v = 0; v < 8; v = v + 1) begin
                rank_a[u] = rank_a[u] + {3'b0, (member_a[v] && (v < u))};
                rank_b[u] = rank_b[u] +
                    {3'b0, (!member_a[v] &&
                     (b_is_chain ? (v < u) : before_latency[v][u]))};
            end
        end
        // Mask-and-OR extraction gives each valid slot exactly one source.
        // Unused slots are zero and cannot cause out-of-range array reads.
        for (slot = 0; slot < 8; slot = slot + 1) begin
            seq_a_index[slot] = 3'd0;
            seq_b_index[slot] = 3'd0;
            for (u = 0; u < 8; u = u + 1) begin
                if (member_a[u] && (rank_a[u] == slot))
                    seq_a_index[slot] = seq_a_index[slot] | u[2:0];
                if (!member_a[u] && (rank_b[u] == slot))
                    seq_b_index[slot] = seq_b_index[slot] | u[2:0];
            end
        end
    end

    function integer ones;
        input integer value;
        integer bit_pos;
        begin
            ones = 0;
            for (bit_pos = 0; bit_pos < 9; bit_pos = bit_pos + 1)
                ones = ones + ((value >> bit_pos) & 1);
        end
    endfunction

    // Enumerate all 256 fixed interleavings, sharing identical prefixes.
    // Heap node 1 is empty, left appends B, right appends A. Nodes 256..511
    // are complete eight-instruction orders. All node indices are constants.
    wire [8:0] next_issue [1:511];
    wire [8:0] finish_a [1:511];
    wire [8:0] finish_b [1:511];
    wire [8:0] max_finish [1:511];
    assign next_issue[1] = 9'd0;
    assign finish_a[1] = 9'd0;
    assign finish_b[1] = 9'd0;
    assign max_finish[1] = 9'd0;
    genvar depth, node;
    generate
        for (depth = 1; depth <= 8; depth = depth + 1) begin : gen_depth
            for (node = (1 << depth); node < (1 << (depth+1)); node = node + 1) begin : gen_prefix
                localparam PARENT = node / 2;
                localparam USED_A = ones(PARENT) - 1;
                localparam USED_B = depth - 1 - USED_A;
                wire [8:0] ready_time;
                wire [8:0] start_time;
                wire [8:0] end_time;
                if ((node % 2) == 1) begin : gen_a
                    assign ready_time = finish_a[PARENT];
                    assign end_time = start_time + {3'b0, seq_a_lat[USED_A]};
                    assign finish_a[node] = end_time;
                    assign finish_b[node] = finish_b[PARENT];
                end else begin : gen_b
                    assign ready_time = b_is_chain ? finish_b[PARENT] : 9'd0;
                    assign end_time = start_time + {3'b0, seq_b_lat[USED_B]};
                    assign finish_a[node] = finish_a[PARENT];
                    assign finish_b[node] = end_time;
                end
                assign start_time = (next_issue[PARENT] >= ready_time) ?
                                    next_issue[PARENT] : ready_time;
                assign next_issue[node] = start_time + 9'd1;
                assign max_finish[node] = (max_finish[PARENT] >= end_time) ?
                                         max_finish[PARENT] : end_time;
            end
        end
    endgenerate

    // Balanced eight-level minimum tree. Equal costs choose the left leaf.
    // A legal schedule is at most 400 cycles; 511 excludes invalid leaves.
    wire [8:0] best_cycle [1:511];
    wire [7:0] best_mask [1:511];
    generate
        for (node = 256; node < 512; node = node + 1) begin : gen_candidate
            localparam [3:0] COUNT_A = ones(node) - 1;
            assign best_cycle[node] = (length_a == COUNT_A) ? max_finish[node] : 9'd511;
            assign best_mask[node] = node - 256;
        end
        for (node = 1; node < 256; node = node + 1) begin : gen_minimum
            wire choose_left;
            assign choose_left = best_cycle[2*node] <= best_cycle[2*node+1];
            assign best_cycle[node] = choose_left ? best_cycle[2*node] : best_cycle[2*node+1];
            assign best_mask[node] = choose_left ? best_mask[2*node] : best_mask[2*node+1];
        end
    endgenerate
    assign Ex_cycle = best_cycle[1];

    // Decode the winning mask only once. Slot zero occupies output [2:0].
    wire [3:0] count_a [0:8];
    wire [3:0] count_b [0:8];
    assign count_a[0] = 4'd0;
    assign count_b[0] = 4'd0;
    generate
        for (lane = 0; lane < 8; lane = lane + 1) begin : gen_output
            wire take_a;
            assign take_a = best_mask[1][7-lane];
            assign count_a[lane+1] = count_a[lane] + {3'b0, take_a};
            assign count_b[lane+1] = count_b[lane] + {3'b0, !take_a};
            assign Inst_order_O[lane*3 +: 3] = take_a ?
                seq_a_index[count_a[lane][2:0]] : seq_b_index[count_b[lane][2:0]];
        end
    endgenerate
endmodule
