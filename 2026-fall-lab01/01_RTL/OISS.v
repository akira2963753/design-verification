// Experiment A: incremental signed probe comparison margin.
// Baseline SHA256: e0f71cc51c48bd29271f53dcf9e3d118c964dd14cd10474888c5c01ffcd72078
//======================================================================
// OISS - Out-of-Order Instruction Scheduling Solver
//
// Architecture V3 : same engine as V1, only 2 slim probes (smallest area)
//
// The spec guarantees the dependency graph is at most TWO vertex disjoint
// chains (everything else is an isolated instruction), so the whole problem
// collapses to a merge of exactly two ordered streams:
//
//   stream A : the dependency chain that owns the earliest producer
//   stream B : the second chain, or - when it does not exist - every
//              independent instruction sorted by descending latency
//
// Scheduling law used here (equivalent to the spec recurrence):
//   every instruction owns one distinct issue cycle, so a schedule is just an
//   assignment of distinct start cycles obeying start[next] >= finish[prev].
//   Walking the two streams and always issuing whichever head becomes
//   available first is therefore optimal; the ONLY real decision happens when
//   both heads become available in the very same cycle.
//
//   * ENGINE 0 is general (handles all three graph shapes) and breaks a tie
//     with the critical-path rule: longest remaining work first, and on an
//     exact draw the head that ends its own stream sooner.  This is optimal
//     for "no dependency" and for "one chain + independents".
//   * ENGINES 1.. are SLIM: they only ever run the chain-vs-chain case, so
//     they drop the running-maximum tracker, the independent-stream paths and
//     the wide critical-path subtractors.  They replay the same walk with the
//     first PROBE_W ties forced to every possible combination, which covers
//     the chain collision patterns a single priority rule cannot see.
//
// Slim-engine identity that makes them cheap:
//   a chain only ever slips by the ties it loses, so sa = prefix[ptrA] + dA.
//   At a tie sa == sb, hence
//        remaining_A >= remaining_B
//     <=> A_total + dA >= B_total + dB
//     <=> (A_total - B_total) >= (dB - dA)
//   and dA, dB are 3-bit counters.  The wide compare becomes one shared
//   thermometer lookup indexed by a 4-bit difference.
//
// All engines emit a legal order, so taking the minimum over them is safe.
// Purely combinational (no storage element is inferred, no vendor IP used).
//======================================================================
module OISS (
    input  [95:0] Inst_seq_I,
    input  [47:0] Inst_latency_I,
    output [23:0] Inst_order_O,
    output [8:0]  Ex_cycle
);

    localparam PROBE_W = 1;                    // ties explored exhaustively
    localparam PROBES  = (1 << PROBE_W);
    localparam ENGINES = 1 + PROBES;

    //------------------------------------------------------------------
    // 1. Instruction decode
    //------------------------------------------------------------------
    wire [11:0] inst_word    [0:7];
    wire [5:0]  opcode_lat   [0:7];
    wire [5:0]  inst_lat     [0:7];
    wire [2:0]  opcode       [0:7];
    wire [2:0]  rs           [0:7];
    wire [2:0]  rt           [0:7];
    wire [2:0]  rd           [0:7];
    wire        writes_rd    [0:7];
    wire        reads_rs_rt  [0:7];
    wire        is_store     [0:7];
    wire        dep          [0:7][0:7];

    genvar i, j, op;
    generate
        for (op = 0; op < 8; op = op + 1) begin : gen_op_lat
            assign opcode_lat[op] = Inst_latency_I[op*6 +: 6];
        end

        for (i = 0; i < 8; i = i + 1) begin : gen_decode
            assign inst_word[i]   = Inst_seq_I[i*12 +: 12];
            assign opcode[i]      = inst_word[i][11:9];
            assign inst_lat[i]    = opcode_lat[opcode[i]];
            assign rs[i]          = inst_word[i][8:6];
            assign rt[i]          = inst_word[i][5:3];
            assign rd[i]          = inst_word[i][2:0];
            // ADD/SUB/MUL/DIV/LOAD produce rd
            assign writes_rd[i]   = !opcode[i][2] | (opcode[i] == 3'b100);
            // ADD/SUB/MUL/DIV/BRANCH consume rs and rt
            assign reads_rs_rt[i] = !opcode[i][2] | (opcode[i] == 3'b110);
            // STORE consumes rd as its data source
            assign is_store[i]    = (opcode[i] == 3'b101);
        end

        //--------------------------------------------------------------
        // 2. Dependency edges (only forward pairs can exist)
        //--------------------------------------------------------------
        for (i = 0; i < 8; i = i + 1) begin : gen_dep_row
            for (j = 0; j < 8; j = j + 1) begin : gen_dep_col
                if (i < j) begin : gen_forward
                    assign dep[i][j] =
                        (writes_rd[i] & reads_rs_rt[j] &                 // RAW
                         ((rd[i] == rs[j]) | (rd[i] == rt[j]))) |
                        (writes_rd[j] & reads_rs_rt[i] &                 // WAR
                         ((rd[j] == rs[i]) | (rd[j] == rt[i]))) |
                        ((rd[i] == rd[j]) &
                         ((writes_rd[i] & writes_rd[j]) |                // WAW
                          (writes_rd[i] & is_store[j]) |                 // RAW via store data
                          (is_store[i] & writes_rd[j])));                // WAR via store data
                end else begin : gen_unused
                    assign dep[i][j] = 1'b0;
                end
            end
        end
    endgenerate

    //------------------------------------------------------------------
    // 3. Split into stream A (first chain) and stream B (the rest)
    //------------------------------------------------------------------
    wire [7:0] has_out;
    wire [7:0] seed_a;
    wire [7:0] member_a;
    wire [7:0] member_b;
    wire       b_is_chain;

    genvar g, h;
    generate
        for (g = 0; g < 8; g = g + 1) begin : gen_chain_group
            wire [7:0] outgoing;
            wire [7:0] from_a;
            for (h = 0; h < 8; h = h + 1) begin : gen_group_edge
                assign outgoing[h] = dep[g][h];
                if (h < g) begin : gen_predecessor
                    assign from_a[h] = dep[h][g] & member_a[h];
                end else begin : gen_no_pred
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

    assign member_b   = ~member_a;
    assign b_is_chain = |(member_b & has_out);

    function [3:0] popcount8;
        input [7:0] bits;
        reg [1:0] p0, p1, p2, p3;
        reg [2:0] h0, h1;
        begin
            p0 = {1'b0, bits[0]} + {1'b0, bits[1]};
            p1 = {1'b0, bits[2]} + {1'b0, bits[3]};
            p2 = {1'b0, bits[4]} + {1'b0, bits[5]};
            p3 = {1'b0, bits[6]} + {1'b0, bits[7]};
            h0 = {1'b0, p0} + {1'b0, p1};
            h1 = {1'b0, p2} + {1'b0, p3};
            popcount8 = {1'b0, h0} + {1'b0, h1};
        end
    endfunction

    //------------------------------------------------------------------
    // 4. Order each stream
    //    A : chain order == index order (edges only go forward)
    //    B : chain order, or descending latency when B is independent work
    //------------------------------------------------------------------
    wire       ahead_lat     [0:7][0:7];
    wire [2:0] rank_a        [0:7];
    wire [2:0] rank_b        [0:7];
    wire [7:0] pick_a        [0:7];
    wire [7:0] pick_b        [0:7];
    wire [2:0] seq_a_index   [0:7];
    wire [2:0] seq_b_index   [0:7];
    wire [5:0] seq_a_lat     [0:7];
    wire [5:0] seq_b_lat     [0:7];

    genvar lane, peer, fbit;
    generate
        for (lane = 0; lane < 8; lane = lane + 1) begin : gen_rank
            wire [7:0] front_a;
            wire [7:0] front_b;
            wire [3:0] cnt_a;
            wire [3:0] cnt_b;
            for (peer = 0; peer < 8; peer = peer + 1) begin : gen_front
                if (lane < peer) begin : gen_cmp
                    assign ahead_lat[lane][peer] = inst_lat[lane] >= inst_lat[peer];
                end else if (lane > peer) begin : gen_mirror
                    assign ahead_lat[lane][peer] = ~ahead_lat[peer][lane];
                end else begin : gen_self
                    assign ahead_lat[lane][peer] = 1'b0;
                end
                assign front_a[peer] = member_a[peer] & (peer < lane);
                assign front_b[peer] = member_b[peer] &
                    (b_is_chain ? (peer < lane) : ahead_lat[peer][lane]);
            end
            assign cnt_a = popcount8(front_a);
            assign cnt_b = popcount8(front_b);
            assign rank_a[lane] = cnt_a[2:0];
            assign rank_b[lane] = cnt_b[2:0];
        end

        // One-hot gather.  Unused slots fall back to latency 0, which is the
        // "stream exhausted" marker used by every engine (real latency >= 1).
        for (lane = 0; lane < 8; lane = lane + 1) begin : gen_slot
            localparam [2:0] SLOT = lane;
            for (peer = 0; peer < 8; peer = peer + 1) begin : gen_onehot
                assign pick_a[lane][peer] = member_a[peer] & (rank_a[peer] == SLOT);
                assign pick_b[lane][peer] = member_b[peer] & (rank_b[peer] == SLOT);
            end
            for (fbit = 0; fbit < 9; fbit = fbit + 1) begin : gen_field
                wire [7:0] mask_a;
                wire [7:0] mask_b;
                for (peer = 0; peer < 8; peer = peer + 1) begin : gen_src
                    localparam [2:0] SRC = peer;
                    if (fbit < 3) begin : gen_idx_bit
                        assign mask_a[peer] = pick_a[lane][peer] & SRC[fbit];
                        assign mask_b[peer] = pick_b[lane][peer] & SRC[fbit];
                    end else begin : gen_lat_bit
                        assign mask_a[peer] = pick_a[lane][peer] & inst_lat[peer][fbit-3];
                        assign mask_b[peer] = pick_b[lane][peer] & inst_lat[peer][fbit-3];
                    end
                end
                if (fbit < 3) begin : gen_idx_out
                    assign seq_a_index[lane][fbit]   = |mask_a;
                    assign seq_b_index[lane][fbit]   = |mask_b;
                end else begin : gen_lat_out
                    assign seq_a_lat[lane][fbit-3]   = |mask_a;
                    assign seq_b_lat[lane][fbit-3]   = |mask_b;
                end
            end
        end
    endgenerate

    //------------------------------------------------------------------
    // 5. Stream totals and the shared tie-compare thermometer
    //
    //    slim engines need  (a_total - b_total) >= (dB - dA)
    //    with dB - dA in [-7, +7], so one shared thermometer indexed by the
    //    4-bit difference replaces a wide compare inside every engine.
    //------------------------------------------------------------------
    wire [8:0]  a_total;
    wire [8:0]  b_total;
    wire signed [10:0] total_gap;
    wire signed [5:0]  gap_sat;   // total_gap clamped into [-8, +8]

    wire [8:0] pair_a [0:3];
    wire [8:0] pair_b [0:3];
    wire [8:0] quad_a [0:1];
    wire [8:0] quad_b [0:1];

    genvar t;
    generate
        for (t = 0; t < 4; t = t + 1) begin : gen_pair_sum
            assign pair_a[t] = {3'b0, seq_a_lat[2*t]} + {3'b0, seq_a_lat[2*t+1]};
            assign pair_b[t] = {3'b0, seq_b_lat[2*t]} + {3'b0, seq_b_lat[2*t+1]};
        end
        for (t = 0; t < 2; t = t + 1) begin : gen_quad_sum
            assign quad_a[t] = pair_a[2*t] + pair_a[2*t+1];
            assign quad_b[t] = pair_b[2*t] + pair_b[2*t+1];
        end
    endgenerate
    assign a_total   = quad_a[0] + quad_a[1];
    assign b_total   = quad_b[0] + quad_b[1];
    assign total_gap = $signed({2'b0, a_total}) - $signed({2'b0, b_total});

    // dB - dA never leaves [-7, +7], so clamping the gap to [-8, +8] keeps
    // every comparison against it exact while shrinking it to 6 signed bits.
    assign gap_sat = (total_gap >  11'sd8) ?  6'sd8 :
                     (total_gap < -11'sd8) ? -6'sd8 : $signed(total_gap[5:0]);

    //------------------------------------------------------------------
    // 6a. Engine 0 - general, covers every graph shape
    //
    //     remaining work of stream A is tracked as  work_a = a_total + dA,
    //     which is just a conditional increment instead of a subtractor
    //     chain over per-slot suffix sums.
    //------------------------------------------------------------------
    wire [8:0] gen_cycle;
    wire [7:0] gen_sel;

    wire [8:0] g_sa     [0:8];
    wire [8:0] g_sb     [0:8];
    wire [8:0] g_best   [0:8];
    wire [8:0] g_work_a [0:8];
    wire [8:0] g_work_b [0:8];
    wire [5:0] g_la     [0:8][0:7];
    wire [5:0] g_lb     [0:8][0:7];
    wire [7:0] g_took_a;

    assign g_sa[0]     = 9'd0;
    assign g_sb[0]     = 9'd0;
    assign g_best[0]   = 9'd0;
    assign g_work_a[0] = a_total;
    assign g_work_b[0] = b_total;

    genvar k, q;
    generate
        for (q = 0; q < 8; q = q + 1) begin : gen_g_init
            assign g_la[0][q] = seq_a_lat[q];
            assign g_lb[0][q] = seq_b_lat[q];
        end

        for (k = 0; k < 8; k = k + 1) begin : gen_g_step
            localparam LEFT = 8 - k;
            wire       live_a;
            wire       live_b;
            wire       next_a;
            wire       next_b;
            wire       lower;
            wire       same;
            wire [8:0] finish_a;
            wire [8:0] finish_b;
            wire [8:0] bump_a;
            wire [8:0] bump_b;
            wire [8:0] finish;
            wire [8:0] rank_rhs;
            wire       work_gt;
            wire       work_eq;
            wire       draw_a;
            wire       prefer_a;
            wire       take_a;
            wire       slip_a;
            wire       slip_b;

            assign live_a = |g_la[k][0];
            assign live_b = |g_lb[k][0];
            assign next_a = |g_la[k][1];
            assign next_b = |g_lb[k][1];
            assign lower  = g_sa[k] <  g_sb[k];
            assign same   = g_sa[k] == g_sb[k];

            // Candidate results are built beside the comparator, never behind
            // the decision mux, so the adder stays off the decision path.
            assign finish_a = g_sa[k] + {3'b0, g_la[k][0]};
            assign finish_b = g_sb[k] + {3'b0, g_lb[k][0]};
            assign bump_a   = g_sa[k] + 9'd1;
            assign bump_b   = g_sb[k] + 9'd1;

            // At a tie sa == sb, so the head of an independent stream has
            // remaining work sb + latency, which is exactly finish_b.
            assign rank_rhs = b_is_chain ? g_work_b[k] : finish_b;
            assign work_gt  = g_work_a[k] >  rank_rhs;
            assign work_eq  = g_work_a[k] == rank_rhs;
            // Exact draw: let the stream that finishes itself go first.
            assign draw_a   = ~next_a | (next_b & (g_la[k][0] >= g_lb[k][0]));
            assign prefer_a = work_eq ? draw_a : work_gt;

            assign take_a = live_a & (~live_b | lower | (same & prefer_a));
            assign finish = take_a ? finish_a : finish_b;
            assign slip_a = same & ~take_a & live_a;   // A lost this tie
            assign slip_b = same &  take_a & live_b;   // B lost this tie

            assign g_sa[k+1] = take_a ? finish_a : (slip_a ? bump_a : g_sa[k]);
            assign g_sb[k+1] = take_a ? (slip_b ? bump_b : g_sb[k])
                                      : (b_is_chain ? finish_b : bump_b);
            assign g_best[k+1] = (finish > g_best[k]) ? finish : g_best[k];
            assign g_took_a[k] = take_a;

            assign g_work_a[k+1] = slip_a ? (g_work_a[k] + 9'd1) : g_work_a[k];
            assign g_work_b[k+1] = slip_b ? (g_work_b[k] + 9'd1) : g_work_b[k];

            for (q = 0; q < 8; q = q + 1) begin : gen_g_shift
                if (q < LEFT - 1) begin : gen_live_entry
                    assign g_la[k+1][q] = take_a ? g_la[k][q+1] : g_la[k][q];
                    assign g_lb[k+1][q] = take_a ? g_lb[k][q]   : g_lb[k][q+1];
                end else begin : gen_dead_entry
                    assign g_la[k+1][q] = 6'd0;
                    assign g_lb[k+1][q] = 6'd0;
                end
            end
        end
    endgenerate

    assign gen_cycle = g_best[8];
    assign gen_sel   = g_took_a;

    //------------------------------------------------------------------
    // 6b. Slim probe engines - chain versus chain only
    //
    //     Two facts make these engines tiny:
    //
    //     (1) We always issue whichever head is ready first, so right after an
    //         issue that stream leads the other by at most its own latency:
    //         |sa - sb| <= 50 for the whole run.  The probes therefore track
    //         only the signed difference, never the 9-bit absolute cycles.
    //     (2) A chain slips only on ties it loses, so its final finish is
    //         total + slips.  Ex_cycle is computed once at the end from the
    //         two 3-bit slip counters - no running maximum, no wide adders.
    //------------------------------------------------------------------
    localparam DW = 8;            // signed width of the stream lead

    wire [8:0] probe_cycle [0:PROBES-1];
    wire [7:0] probe_sel   [0:PROBES-1];

    genvar e;
    generate
        for (e = 0; e < PROBES; e = e + 1) begin : gen_probe
            wire signed [DW-1:0] lead [0:8];   // sa - sb
            wire signed [5:0] margin [0:8]; // gap_sat + dA - dB
            wire [2:0] da    [0:8];
            wire [2:0] db    [0:8];
            wire [PROBE_W-1:0] plan  [0:8];
            wire [PROBE_W-1:0] fresh [0:8];
            wire [5:0] la    [0:8][0:7];
            wire [5:0] lb    [0:8][0:7];
            wire [7:0] took_a;
            wire [8:0] end_a;
            wire [8:0] end_b;
            localparam [PROBE_W-1:0] PLAN_INIT = e;

            assign lead[0]  = {DW{1'b0}};
            assign margin[0] = gap_sat;
            assign da[0]    = 3'd0;
            assign db[0]    = 3'd0;
            assign plan[0]  = PLAN_INIT;
            assign fresh[0] = {PROBE_W{1'b1}};

            for (q = 0; q < 8; q = q + 1) begin : gen_p_init
                assign la[0][q] = seq_a_lat[q];
                assign lb[0][q] = seq_b_lat[q];
            end

            for (k = 0; k < 8; k = k + 1) begin : gen_p_step
                localparam LEFT = 8 - k;
                wire       live_a;
                wire       live_b;
                wire       next_a;
                wire       next_b;
                wire       lower;
                wire       same;
                wire signed [DW-1:0] lead_a;
                wire signed [DW-1:0] lead_b;
                // The comparison margin is carried between steps.
                wire       work_gt;
                wire       work_eq;
                wire       draw_a;
                wire       rule_a;
                wire       choice;
                wire       prefer_a;
                wire       take_a;
                wire       slip_a;
                wire       slip_b;

                assign live_a = |la[k][0];
                assign live_b = |lb[k][0];
                assign next_a = |la[k][1];
                assign next_b = |lb[k][1];
                assign lower  = lead[k][DW-1];        // sa < sb
                assign same   = (lead[k] == {DW{1'b0}});

                // remaining work compare, with both sides shifted by sa == sb:
                //   a_total + dA  >=  b_total + dB
                //   <=> gap_sat + dA  >=  dB
                assign work_gt = ~margin[k][5] & (|margin[k]);
                assign work_eq = (margin[k] == 6'sd0);
                assign margin[k+1] = slip_a ? (margin[k] + 6'sd1) :
                                     slip_b ? (margin[k] - 6'sd1) : margin[k];
                // Exact draw: let the stream that ends itself go first.
                assign draw_a   = ~next_a | (next_b & (la[k][0] >= lb[k][0]));
                assign rule_a   = work_eq ? draw_a : work_gt;

                // A genuine choice point consumes one planned answer; after
                // the plan runs out the engine falls back to the rule.
                assign choice    = live_a & live_b & same;
                assign prefer_a  = fresh[k][0] ? plan[k][0] : rule_a;
                assign plan[k+1]  = choice ? (plan[k]  >> 1) : plan[k];
                assign fresh[k+1] = choice ? (fresh[k] >> 1) : fresh[k];

                assign take_a = live_a & (~live_b | lower | (same & prefer_a));
                assign slip_a = same & ~take_a & live_a;
                assign slip_b = same &  take_a & live_b;

                // Issuing A pushes A ahead by its latency; the loser of a tie
                // slips one cycle, which is the same -1 / +1 on the lead.
                assign lead_a = lead[k] + $signed({2'b0, la[k][0]});
                assign lead_b = lead[k] - $signed({2'b0, lb[k][0]});
                assign lead[k+1] = take_a ? (lead_a - $signed({{(DW-1){1'b0}}, slip_b}))
                                          : (lead_b + $signed({{(DW-1){1'b0}}, slip_a}));

                assign da[k+1] = da[k] + {2'b0, slip_a};
                assign db[k+1] = db[k] + {2'b0, slip_b};
                assign took_a[k] = take_a;

                for (q = 0; q < 8; q = q + 1) begin : gen_p_shift
                    if (q < LEFT - 1) begin : gen_live_entry
                        assign la[k+1][q] = take_a ? la[k][q+1] : la[k][q];
                        assign lb[k+1][q] = take_a ? lb[k][q]   : lb[k][q+1];
                    end else begin : gen_dead_entry
                        assign la[k+1][q] = 6'd0;
                        assign lb[k+1][q] = 6'd0;
                    end
                end
            end

            assign end_a = a_total + {6'b0, da[8]};
            assign end_b = b_total + {6'b0, db[8]};
            // Only meaningful when both streams really are chains.
            assign probe_cycle[e] = ~b_is_chain      ? 9'h1FF :
                                    (end_a > end_b)  ? end_a  : end_b;
            assign probe_sel[e]   = took_a;
        end
    endgenerate

    //------------------------------------------------------------------
    // 7. Keep the cheapest schedule
    //------------------------------------------------------------------
    wire [8:0] win_cycle [0:PROBES];
    wire [7:0] win_sel   [0:PROBES];

    assign win_cycle[0] = gen_cycle;
    assign win_sel[0]   = gen_sel;

    generate
        for (e = 0; e < PROBES; e = e + 1) begin : gen_reduce
            wire keep_old;
            assign keep_old       = win_cycle[e] <= probe_cycle[e];
            assign win_cycle[e+1] = keep_old ? win_cycle[e] : probe_cycle[e];
            assign win_sel[e+1]   = keep_old ? win_sel[e]   : probe_sel[e];
        end
    endgenerate

    assign Ex_cycle = win_cycle[PROBES];

    //------------------------------------------------------------------
    // 8. Rebuild the issue order from the winning decision mask
    //------------------------------------------------------------------
    generate
        for (k = 0; k < 8; k = k + 1) begin : gen_order
            localparam [3:0] POSITION = k;
            wire [7:0] earlier;
            wire [3:0] used_a;
            wire [3:0] used_b;
            for (q = 0; q < 8; q = q + 1) begin : gen_earlier
                if (q < k) begin : gen_before
                    assign earlier[q] = win_sel[PROBES][q];
                end else begin : gen_after
                    assign earlier[q] = 1'b0;
                end
            end
            assign used_a = popcount8(earlier);
            assign used_b = POSITION - used_a;
            assign Inst_order_O[k*3 +: 3] = win_sel[PROBES][k]
                                          ? seq_a_index[used_a[2:0]]
                                          : seq_b_index[used_b[2:0]];
        end
    endgenerate

endmodule
