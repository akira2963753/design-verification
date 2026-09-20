//======================================================================
// VERSION : v13a          <- bump this on EVERY change
// VARIANT : A  (v12b + shared crossbar decode)
//           128 three-bit comparators become 16 decoders
//           (the v1/v2 in the FILE NAME is the variant, not the version)
//
// REVISION HISTORY
//   v01  2^6 prefix DP tree over interleavings           957,260 @100ns
//   v02  two-stream greedy merge, 9 general engines
//   v03  slim probes via a 15-entry thermometer          304,818 @40ns
//   v04  lead-difference domain (|sa-sb| <= 50)
//   v05  single add/sub for the lead, last step trimmed  261,165 @40ns
//   v06  general engine specialised to the independent
//        stream and switched out when B is a chain       220,395 @40ns
//   v07  general engine: chain finish from the slip
//        counter, t folded into one adder               179,773 @40ns
//   v08  margin speculation (predicates carried forward) 217,980 @30ns
//   v09  4 plan probes + 2 pinned engines (bug fix for
//        the BRANCH-latency-3 two-chain family)
//   v10  4-engine minimum hitting set over the full
//        (plan depth x plan value x draw direction)
//        space - same bug fixed, one fewer engine       219,298 @29ns
//   v11a issue order off the post-reduce path: each
//        engine carries its own slot pointers          218,536 @29ns
//   v12  the reduce no longer merges the two result
//        families.  b_is_chain already makes them
//        mutually exclusive, so it is a 2-level tree
//        over the probes plus one family mux, and the
//        9'h1FF masks are gone entirely.
//        v12b  + pb dropped               213,533 @27ns  5.77M
//   v13  crossbar select written as a shared 3-to-8 decode
//        instead of 128 three-bit comparators
//        v13a  decode only
//
// OISS - Out-of-Order Instruction Scheduling Solver
//
// Architecture V1 : 1 independent-stream engine + 4 chain-merge probes
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
//   * ENGINE 0 only has to be OPTIMAL when B is the independent stream, and it
//     is switched out of the reduce entirely when B is a chain.  There B's head
//     is always ready, so sb == t and hence sa >= sb for the whole run: the
//     "who is ready first" compare disappears and only the tie survives.  The
//     rank compare at a tie is remaining-chain-work against the head latency,
//     carried as a pre-computed 6-bit saturated suffix, so no 9-bit
//     accumulator is left anywhere on that engine's decision path.
//   * ENGINES 1.. are SLIM: they only ever run the chain-vs-chain case.
//     They replay the same walk with the first few ties forced to a chosen
//     answer, which covers the chain collision patterns that no
//     single priority rule can see.  Two identities make them cheap:
//
//       (1) we always issue whichever head is ready first, so a stream never
//           leads by more than one latency: |sa - sb| <= 50 for the whole run.
//           The probes carry only that signed lead, never 9-bit absolute time.
//       (2) a chain slips only on ties it loses, so its finish is
//           total + slips.  Ex_cycle is built once at the end from two 3-bit
//           slip counters - no running maximum inside the loop.
//
//     The tie compare follows from (2): at a tie sa == sb, so
//        remaining_A >= remaining_B   <=>   gap + dA >= dB
//     with gap = a_total - b_total clamped to [-8, +8] (exact, because
//     dB - dA never leaves [-7, +7]).  That quantity is carried as a signed
//     "margin" register that only a slip can move, by one, so the compare
//     degenerates into a sign bit and a zero test.
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

    localparam PLAN_W = 2;     // widest plan carried by any probe
    localparam PROBES = 4;     // see the engine table in 6b
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
    wire [7:0] onehot_a      [0:7];
    wire [7:0] onehot_b      [0:7];
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

            // rank_x[lane] == SLOT swept over all eight SLOTs IS a 3-to-8
            // decode of rank_x[lane].  Doing it once per lane replaces 64
            // three-bit comparators per stream with 8 decoders - DC was
            // inferring a DW_cmp for every (lane, SLOT) pair instead.
            assign onehot_a[lane] = member_a[lane] ? (8'd1 << rank_a[lane]) : 8'd0;
            assign onehot_b[lane] = member_b[lane] ? (8'd1 << rank_b[lane]) : 8'd0;
        end

        // One-hot gather.  Unused slots fall back to latency 0, which is the
        // "stream exhausted" marker used by every engine (real latency >= 1).
        for (lane = 0; lane < 8; lane = lane + 1) begin : gen_slot
            for (peer = 0; peer < 8; peer = peer + 1) begin : gen_onehot
                assign pick_a[lane][peer] = onehot_a[peer][lane];
                assign pick_b[lane][peer] = onehot_b[peer][lane];
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
    // 5. Stream totals and the clamped tie-compare gap
    //
    //    slim engines need  (a_total - b_total) >= (dB - dA)
    //    and dB - dA never leaves [-7, +7], so the gap can be clamped once to
    //    [-8, +8] and every in-loop compare shrinks from 9 bits to 6.
    //------------------------------------------------------------------
    wire [8:0]  a_total;
    wire [8:0]  b_total;
    wire signed [10:0] total_gap;
    wire signed [4:0]  gap_sat;   // total_gap clamped into [-8, +8]

    wire [8:0] suffix_a   [0:8];
    wire [5:0] suffix_sat [0:7];

    wire [8:0] pair_b [0:3];
    wire [8:0] quad_b [0:1];

    genvar t;
    generate
        for (t = 0; t < 4; t = t + 1) begin : gen_pair_sum
            assign pair_b[t] = {3'b0, seq_b_lat[2*t]} + {3'b0, seq_b_lat[2*t+1]};
        end
        for (t = 0; t < 2; t = t + 1) begin : gen_quad_sum
            assign quad_b[t] = pair_b[2*t] + pair_b[2*t+1];
        end
    endgenerate
    assign a_total   = suffix_a[0];
    assign b_total   = quad_b[0] + quad_b[1];

    // Remaining chain work seen from every slot of stream A.  The independent
    // stream engine only ever compares it against a head latency (<= 50), so a
    // 6-bit saturating copy carries all the information it needs and keeps a
    // 9-bit accumulator out of that engine's loop.
    assign suffix_a[8] = 9'd0;
    generate
        for (t = 0; t < 8; t = t + 1) begin : gen_suffix_a
            localparam SUF_SLOT = 7 - t;
            assign suffix_a[SUF_SLOT] = suffix_a[SUF_SLOT+1] +
                                        {3'b0, seq_a_lat[SUF_SLOT]};
        end
        for (t = 0; t < 8; t = t + 1) begin : gen_suffix_sat
            assign suffix_sat[t] = (|suffix_a[t][8:6]) ? 6'd63 : suffix_a[t][5:0];
        end
    endgenerate
    assign total_gap = $signed({2'b0, a_total}) - $signed({2'b0, b_total});

    // dB - dA never leaves [-7, +7], so clamping the gap to [-8, +8] keeps
    // every comparison against it exact; the margin it feeds stays in [-15,15],
    // so 5 signed bits carry the whole in-loop compare.
    assign gap_sat = (total_gap >  11'sd8) ?  5'sd8 :
                     (total_gap < -11'sd8) ? -5'sd8 : $signed(total_gap[4:0]);

    //------------------------------------------------------------------
    // 6a. Engine 0 - the independent-stream engine
    //
    //     The probes below cover chain-versus-chain completely, so this engine
    //     only ever has to be OPTIMAL when B is the independent stream, and it
    //     is switched out of the reduce entirely when B is a chain.  That
    //     specialisation strips the loop down a long way:
    //
    //       * B's head is always ready, so sb == t and therefore sa >= sb for
    //         the whole run - the "who is ready first" compare disappears and
    //         only the tie (lead == 0) survives.
    //       * at a tie sa == t, so the rank compare is remaining-chain-work
    //         against the head latency: a 6-bit compare on a pre-computed
    //         saturated suffix, not a 9-bit accumulator in the loop.
    //
    //     What is left of the 9-bit arithmetic (t, the finishes, the running
    //     maximum) is pure feed-forward and no longer sits on the decision
    //     path, which is what the whole loop is timed by.
    //------------------------------------------------------------------
    wire [8:0] gen_cycle;
    wire [7:0] gen_sel;
    wire [23:0] gen_pa;

    wire [8:0] g_t      [0:8];   // next free issue cycle  (== sb)
    wire [6:0] g_lead   [0:8];   // sa - t, never negative here
    wire [8:0] g_best   [0:8];   // max over independent finishes only
    wire [2:0] g_da     [0:8];   // ties the chain lost
    wire [5:0] g_la     [0:8][0:7];
    wire [5:0] g_lb     [0:8][0:7];
    wire [5:0] g_ra     [0:8][0:7];   // saturated remaining chain work
    wire [7:0] g_took_a;
    wire [2:0] g_pa     [0:8];   // slot pointers, == popcount of took_a so far

    assign g_t[0]    = 9'd0;
    assign g_lead[0] = 7'd0;
    assign g_best[0] = 9'd0;
    assign g_pa[0]   = 3'd0;
    assign g_da[0]   = 3'd0;

    genvar k, q;
    generate
        for (q = 0; q < 8; q = q + 1) begin : gen_g_init
            assign g_la[0][q] = seq_a_lat[q];
            assign g_lb[0][q] = seq_b_lat[q];
            assign g_ra[0][q] = suffix_sat[q];
        end
        for (k = 0; k < 8; k = k + 1) begin : gen_g_step
            localparam LEFT = 8 - k;
            wire       live_a;
            wire       live_b;
            wire       take_a;
            wire [8:0] fin_b;

            assign live_a = |g_la[k][0];
            assign live_b = |g_lb[k][0];

            // A singleton issues at t, so this is its finish.  The CHAIN needs
            // no finish arithmetic at all: it slips only on ties it loses, so
            // its last finish is a_total + dA, built once after the loop.
            assign fin_b = g_t[k] + {3'b0, g_lb[k][0]};

            if (k < 7) begin : gen_full_step
                wire same;
                wire prefer_a;
                wire slip_a;
                assign same     = (g_lead[k] == 7'd0);
                // Whole decision path: a 7-bit zero test and a 6-bit compare.
                assign prefer_a = g_ra[k][0] >= g_lb[k][0];
                assign take_a   = live_a & (~live_b | (same & prefer_a));
                assign slip_a   = same & ~take_a & live_a;
                // A issues at t + lead, B issues at t; either way t lands one
                // past the issued cycle, so one adder covers both.
                assign g_t[k+1] = g_t[k] +
                                  {2'b0, (take_a ? g_lead[k] : 7'd0)} + 9'd1;
                // After A issues, A's next head is ready latency cycles later
                // and t moved one past the issue, so the lead is latency - 1.
                assign g_lead[k+1] = take_a ? (g_la[k][0] - 6'd1)
                                            : (same ? 7'd0 : (g_lead[k] - 7'd1));
                assign g_da[k+1]   = g_da[k] + {2'b0, slip_a};
            end else begin : gen_last_step
                // One instruction is left, so exactly one stream is live: the
                // pick is forced, no tie can fire, and t / lead are never read.
                assign take_a      = live_a;
                assign g_t[k+1]    = g_t[k];
                assign g_lead[k+1] = g_lead[k];
                assign g_da[k+1]   = g_da[k];
            end

            assign g_best[k+1] = (~take_a & (fin_b > g_best[k])) ? fin_b
                                                                 : g_best[k];
            assign g_took_a[k] = take_a;
            assign g_pa[k+1] = g_pa[k] + {2'b0,  take_a};

            for (q = 0; q < 8; q = q + 1) begin : gen_g_shift
                if (q < LEFT - 1) begin : gen_live_entry
                    assign g_la[k+1][q] = take_a ? g_la[k][q+1] : g_la[k][q];
                    assign g_ra[k+1][q] = take_a ? g_ra[k][q+1] : g_ra[k][q];
                    assign g_lb[k+1][q] = take_a ? g_lb[k][q]   : g_lb[k][q+1];
                end else begin : gen_dead_entry
                    assign g_la[k+1][q] = 6'd0;
                    assign g_ra[k+1][q] = 6'd0;
                    assign g_lb[k+1][q] = 6'd0;
                end
            end
        end
    endgenerate

    // The chain's own finish, from the identity "total + ties lost".
    wire [8:0] g_end_a;
    assign g_end_a = a_total + {6'b0, g_da[8]};
    // Switched out whenever B is a chain; the probes own that case.
    assign gen_cycle = (g_best[8] > g_end_a) ? g_best[8] : g_end_a;
    assign gen_sel   = g_took_a;
    assign gen_pa[ 0 +: 3] = g_pa[0];
    assign gen_pa[ 3 +: 3] = g_pa[1];
    assign gen_pa[ 6 +: 3] = g_pa[2];
    assign gen_pa[ 9 +: 3] = g_pa[3];
    assign gen_pa[12 +: 3] = g_pa[4];
    assign gen_pa[15 +: 3] = g_pa[5];
    assign gen_pa[18 +: 3] = g_pa[6];
    assign gen_pa[21 +: 3] = g_pa[7];

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
    //
    //     Every probe forces the first few ties to a fixed answer and then
    //     falls back to the critical-path rule.  Which forced prefixes, and
    //     which way the rule settles an exact draw, is not guesswork: a
    //     minimum-hitting-set search over the whole
    //         (plan depth) x (plan value) x (draw direction)
    //     engine space showed that no 1, 2 or 3 engine set covers the legal
    //     two-chain space, and that the four in the table below do.
    //------------------------------------------------------------------
    localparam DW = 7;            // signed width of the lead; |sa-sb| <= 50

    wire [8:0] probe_cycle [0:PROBES-1];
    wire [7:0] probe_sel   [0:PROBES-1];
    wire [23:0] probe_pa   [0:PROBES-1];

    genvar e;
    generate
        for (e = 0; e < PROBES; e = e + 1) begin : gen_probe
            // Engine table.  A minimum-hitting-set search over every
            // (plan depth) x (plan value) x (exact-draw direction) engine
            // showed no 1, 2 or 3 engine set can cover the legal two-chain
            // space, and that these four do.  Two shallow probes settle the
            // first tie both ways under one draw direction; two deeper probes
            // settle the first two ties both ways under the other.
            //
            //   e | plan depth | forced ties | exact-draw compare
            //   0 |     1      |      B      | la >= lb
            //   1 |     1      |      A      | la >= lb
            //   2 |     2      |     B,B     | la <  lb
            //   3 |     2      |     A,A     | la <  lb
            localparam EPW  = (e < 2) ? 1 : 2;
            localparam EREV = (e >= 2);
            localparam [PLAN_W-1:0] PLAN_INIT = (e == 0) ? 2'b00 :
                                                (e == 1) ? 2'b01 :
                                                (e == 2) ? 2'b00 : 2'b11;
            localparam [PLAN_W-1:0] FRESH_INIT = (EPW == 1) ? 2'b01 : 2'b11;

            wire signed [DW-1:0] lead   [0:8];   // sa - sb
            wire signed [4:0]    margin [0:8];   // gap_sat + dA - dB
            wire                 wgt    [0:8];   // margin >  0, carried forward
            wire                 weq    [0:8];   // margin == 0, carried forward
            wire [2:0] da [0:8];
            wire [2:0] db [0:8];
            wire [PLAN_W-1:0] plan  [0:8];
            wire [PLAN_W-1:0] fresh [0:8];
            wire [5:0] la [0:8][0:7];
            wire [5:0] lb [0:8][0:7];
            wire [7:0] took_a;
            wire [2:0] pa [0:8];
            wire [8:0] end_a;
            wire [8:0] end_b;

            assign lead[0]   = {DW{1'b0}};
            assign margin[0] = gap_sat;
            assign wgt[0]    = (gap_sat >  5'sd0);
            assign weq[0]    = (gap_sat == 5'sd0);
            assign da[0]     = 3'd0;
            assign db[0]     = 3'd0;
            assign pa[0]     = 3'd0;
            assign plan[0]   = PLAN_INIT;
            assign fresh[0]  = FRESH_INIT;

            for (q = 0; q < 8; q = q + 1) begin : gen_p_init
                assign la[0][q] = seq_a_lat[q];
                assign lb[0][q] = seq_b_lat[q];
            end

            for (k = 0; k < 8; k = k + 1) begin : gen_p_step
                localparam LEFT = 8 - k;
                wire live_a;
                wire live_b;
                wire take_a;

                assign live_a = |la[k][0];
                assign live_b = |lb[k][0];

                if (k < 7) begin : gen_full_step
                    wire lower;
                    wire same;
                    wire [DW-1:0] addend;
                    wire signed [DW-1:0] lead_run;
                    wire signed [DW-1:0] tie_a;
                    wire signed [DW-1:0] tie_b;
                    wire prefer_a;
                    wire slip_a;
                    wire slip_b;

                    assign lower = lead[k][DW-1];        // sa < sb
                    assign same  = (lead[k] == {DW{1'b0}});

                    wire work_gt;
                    wire work_eq;
                    wire draw_a;
                    wire rule_a;
                    wire choice;
                    // margin == gap_sat + dA - dB.  A slip is the only
                    // thing that can move it, and only by one, so the THREE
                    // possible next answers are built here and the slip
                    // just selects one next cycle.  That lifts the 5-bit
                    // arithmetic and its compares out of the decision loop.
                    assign work_gt = wgt[k];
                    assign work_eq = weq[k];
                    // Exact draw on remaining work: longer head goes first.
                    assign draw_a  = EREV ? (la[k][0] <  lb[k][0])
                                          : (la[k][0] >= lb[k][0]);
                    assign rule_a  = work_eq ? draw_a : work_gt;
                    // A genuine choice point consumes one planned answer;
                    // after the plan runs out the rule takes over.
                    assign choice     = live_a & live_b & same;
                    assign prefer_a   = fresh[k][0] ? plan[k][0] : rule_a;
                    assign plan[k+1]  = choice ? (plan[k]  >> 1) : plan[k];
                    assign fresh[k+1] = choice ? (fresh[k] >> 1) : fresh[k];
                    // margin+1 >0 <=> margin >= 0 ; margin+1 ==0 <=> margin == -1
                    // margin-1 >0 <=> margin >  1 ; margin-1 ==0 <=> margin ==  1
                    assign wgt[k+1] = slip_a ? (wgt[k] | weq[k]) :
                                      slip_b ? (margin[k] >  5'sd1) : wgt[k];
                    assign weq[k+1] = slip_a ? (margin[k] == -5'sd1) :
                                      slip_b ? (margin[k] ==  5'sd1) : weq[k];
                    assign margin[k+1] = slip_a ? (margin[k] + 5'sd1) :
                                         slip_b ? (margin[k] - 5'sd1) : margin[k];

                    assign take_a = live_a & (~live_b | lower | (same & prefer_a));
                    assign slip_a = same & ~take_a & live_a;
                    assign slip_b = same &  take_a & live_b;

                    // Away from a tie the winner is decided by the sign of the
                    // lead alone, which is known before the decision, so the
                    // operand is selected ahead of a SINGLE add/sub instead of
                    // running one adder per stream.  (When a stream is dead the
                    // lead stops being read, so the wrong branch is safe.)
                    assign addend   = lower ? {2'b0, la[k][0]} : ~{2'b0, lb[k][0]};
                    assign lead_run = lead[k] + $signed(addend) +
                                      {{(DW-1){1'b0}}, ~lower};
                    // A slip can only happen when lead == 0, so the tie results
                    // are plain 6-bit expressions.
                    assign tie_a = $signed({2'b0, la[k][0]}) -
                                   $signed({{(DW-1){1'b0}}, live_b});
                    assign tie_b = $signed({{(DW-1){1'b0}}, live_a}) -
                                   $signed({2'b0, lb[k][0]});
                    assign lead[k+1] = same ? (take_a ? tie_a : tie_b) : lead_run;

                    assign da[k+1] = da[k] + {2'b0, slip_a};
                    assign db[k+1] = db[k] + {2'b0, slip_b};
                end else begin : gen_last_step
                    // One instruction is left, so exactly one stream is live:
                    // the pick is forced and neither slip term can fire (each
                    // needs a live stream AND the other one taken).  Nothing
                    // downstream of here reads lead or margin again.
                    assign take_a      = live_a;
                    assign lead[k+1]   = lead[k];
                    assign da[k+1]     = da[k];
                    assign db[k+1]     = db[k];
                    assign plan[k+1]   = plan[k];
                    assign fresh[k+1]  = fresh[k];
                    assign margin[k+1] = margin[k];
                    assign wgt[k+1]    = wgt[k];
                    assign weq[k+1]    = weq[k];
                end

                assign took_a[k] = take_a;
                assign pa[k+1] = pa[k] + {2'b0,  take_a};

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

            // end_a - end_b == gap + dA - dB, which is exactly what margin
            // tracks, so the sign bit already computed decides the maximum.
            // (Clamping gap to [-8,+8] cannot flip that sign, |dA-dB| <= 7.)
            // no mask: b_is_chain picks the family in the reduce below
            assign probe_cycle[e] = wgt[8] ? end_a : end_b;
            assign probe_sel[e] = took_a;
            assign probe_pa[e][ 0 +: 3] = pa[0];
            assign probe_pa[e][ 3 +: 3] = pa[1];
            assign probe_pa[e][ 6 +: 3] = pa[2];
            assign probe_pa[e][ 9 +: 3] = pa[3];
            assign probe_pa[e][12 +: 3] = pa[4];
            assign probe_pa[e][15 +: 3] = pa[5];
            assign probe_pa[e][18 +: 3] = pa[6];
            assign probe_pa[e][21 +: 3] = pa[7];
        end
    endgenerate

    //------------------------------------------------------------------
    // 7. Keep the cheapest schedule
    //
    //    b_is_chain already makes the two families mutually exclusive: a probe
    //    only ever means anything for chain-versus-chain, the general engine
    //    only for the independent stream.  So instead of one five-deep chain
    //    with a 9'h1FF mask on every input, take the minimum of the four
    //    probes as a TREE and let b_is_chain pick the family.  Every mask
    //    disappears and the reduce is 2 compare levels deep instead of 4.
    //------------------------------------------------------------------
    wire        kab, kcd, kpm;
    wire [8:0]  ab_cycle, cd_cycle, pm_cycle;
    wire [7:0]  ab_sel, cd_sel, pm_sel, win_sel;
    wire [23:0] ab_pa, cd_pa, pm_pa, win_pa;

    assign kab      = probe_cycle[0] <= probe_cycle[1];
    assign kcd      = probe_cycle[2] <= probe_cycle[3];
    assign ab_cycle = kab ? probe_cycle[0] : probe_cycle[1];
    assign cd_cycle = kcd ? probe_cycle[2] : probe_cycle[3];
    assign ab_sel   = kab ? probe_sel[0]   : probe_sel[1];
    assign cd_sel   = kcd ? probe_sel[2]   : probe_sel[3];

    assign kpm      = ab_cycle <= cd_cycle;
    assign pm_cycle = kpm ? ab_cycle : cd_cycle;
    assign pm_sel   = kpm ? ab_sel   : cd_sel;

    assign win_sel  = b_is_chain ? pm_sel   : gen_sel;
    assign ab_pa    = kab ? probe_pa[0] : probe_pa[1];
    assign cd_pa    = kcd ? probe_pa[2] : probe_pa[3];
    assign pm_pa    = kpm ? ab_pa       : cd_pa;
    assign win_pa   = b_is_chain ? pm_pa  : gen_pa;

    assign Ex_cycle = b_is_chain ? pm_cycle : gen_cycle;

    //------------------------------------------------------------------
    // 8. Rebuild the issue order
    //
    //    pa[k] + pb[k] == k by construction, and k is a CONSTANT here, so the
    //    B slot is a constant-minus-3-bits - a handful of gates, not a
    //    subtractor - and half the winner payload never has to be carried
    //    through the tree at all.
    //------------------------------------------------------------------
    generate
        for (k = 0; k < 8; k = k + 1) begin : gen_order
            localparam [2:0] POSITION = k;
            wire [2:0] slot_a;
            wire [2:0] slot_b;
            assign slot_a = win_pa[k*3 +: 3];
            assign slot_b = POSITION - slot_a;
            assign Inst_order_O[k*3 +: 3] = win_sel[k] ? seq_a_index[slot_a]
                                                       : seq_b_index[slot_b];
        end
    endgenerate

endmodule