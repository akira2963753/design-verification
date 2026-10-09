//v65: v61 (st2+jc, no tail store) with every walker / job register given a known value at each shot (S_C1 / S_PTR loads) and the shot window also used in S_WAIT (the v64 fix against unknown values in the gate-level simulation)
module ZUMA (
    input               clk,
    input               rst_n,
    // ---- ring loading phase ----
    input               in_valid,
    input      [7:0]    ring_len,
    input      [2:0]    in_color,
    // ---- shooting phase ----
    input               shot_valid,
    input      [2:0]    shot_color,
    input      [7:0]    shot_pos,
    // ---- outputs ----
    output              out_valid,
    output     [6:0]    chain_num,
    output     [2:0]    elim_color,
    output     [8:0]    elim_cnt
);

// ============================================================================
// Overview
//   ring_q holds 256 beads of 3 bits, slot i = logical index i (mf_q beads once the pending update is done).
//   Every run of equal colors in the ring is at most 2 beads long (spec
//   guarantee plus the elimination rules), so level 1 always removes 3 beads
//   and every later level removes 3 or 4 beads (2 + 1, 1 + 2 or 2 + 2).
//   S_C1   : one compute cycle reads an 8-bead window (logical k-3 .. k+4)
//            and decides level 1 and level 2 into plain registers (e1_q, e2_q).
//            S_PTR follows; for chain 0 / 1 its outputs are decoded from those
//            registers after the flip-flops, so the burst starts at the same
//            edge as before. Everything else (bead count, ring update
//            operation, "fewer than 3 beads left" test) is done in S_PTR from
//            registered results.
//   S_EV   : longer cascades are counted by a walker that reads 8-bead chunks
//            alternately on the left and right side (one level per cycle).
//   S_REV  : the walker replays levels >= 5 during the output burst. The count keeps the color and
//            size of levels 3 and 4 in st_q, so the burst starts in the cycle after
//            the count ends (level 1, then levels 2, 3, 4 while S_SU1 .. S_SU3 restart the walker from
//            the frontiers after level 4). A chain of 3 / 4 needs no replay: its deletion job starts
//            with the burst.
//   Ring updates run on a job sequencer, one operation per clock edge:
//   insert one bead, or delete two beads, at a position. The operation of a
//   cycle is decided at the edge before it and held in registers, so the
//   update network starts from flip-flops. An eliminated shot bead is never
//   stored. Odd deletions insert a dummy bead first ("dup").
// ============================================================================

localparam S_IDLE = 4'd0;
localparam S_WAIT = 4'd1;   // shot taken, previous ring update still running
localparam S_C1   = 4'd2;   // first compute cycle
localparam S_O2A  = 4'd3;   // chain of 2 decided in S_PTR: output level 2
localparam S_O2B  = 4'd4;   // chain of 2 found by the walker: output level 2
localparam S_LAST = 4'd5;   // last output cycle
localparam S_PTR  = 4'd6;   // after S_C1. e2_q = 0: output of chain 0 / 1 (only cycle); e2_q = 1: frontiers after level 2, chain of 2 when fewer than 3 beads remain
localparam S_SU1  = 4'd7;   // walker start-up
localparam S_SU2  = 4'd8;
localparam S_SU3  = 4'd9;
localparam S_EV   = 4'd10;  // walker: count levels >= 3
localparam S_REV  = 4'd11;  // walker: replay levels >= 5 during the burst

// ---------------------------------------------------------------- registers
reg  [767:0] ring_q;
reg  [8:0]   mf_q;         // beads after the pending ring update; during a shot (until its job) the count before the shot
reg          iv_q;         // a bead was sampled at the previous edge
reg  [3:0]   state;
reg  [7:0]   k_q;
reg  [7:0]   st_q;         // level store: [3:0] level 3, [7:4] level 4 ({4 beads, color})
reg  [2:0]   s_q;
reg          km1_q, km2_q, km3_q, km4_q; // k == M - 1 .. M - 4 (shot decode compares, taken with k_q)
reg          k0_q, k1_q, k2_q; // k == 0 / 1 / 2

reg  [31:0]  w_row;        // window centre C = start + 3: one-hot of C[7:3] (row 32 = row 0)
reg  [9:0]   w_xoh;        // window offset in the row: one-hot of C[2:0], 8 / 9 only for k < 3 (see the shot decode)
reg  [7:0]   w_w0;         // walker window: one-hot of the first position at or beyond M (0 when none)
reg  [23:0]  w_hs;         // M < 8: head slot of every window position, from the table row of k (input half cycle)

// S_C1 results (color compares of the window): loaded at every edge, valid in the cycle after S_C1 (S_PTR)
reg          ha_r, hb_r, hl1_r, hr1_r; // shot color == bead k / k+1 / k-1 / k+2
reg          fa_r, fb_r, fc_r; // level-2 junction colors equal: L1 == R1 (case A), L2 == R0 (B), L0 == R2 (C)
reg          eL12_r, eL23_r, eL01_r, eR12_r, eR01_r, eR23_r; // neighbour equalities (level-2 run lengths)
reg  [2:0]   l0_r, l1_r, l2_r; // window beads k, k-1, k-2 (the level-2 color is picked from them in S_PTR)
reg          stx_r, sty_r, stz_r; // L2 != R3, L3 != R2, L3 != R3 (local stop of a chain of 2, used in S_PTR)
// copies taken in S_PTR for the later states
reg          p2b_q, q2b_q;
reg  [2:0]   col2_q;
reg          c1d_q;        // the previous cycle was S_C1

reg          out_valid_r;  // registered part of the outputs (zero in the cycle after S_C1)
reg  [6:0]   chain_num_r;
reg  [2:0]   elim_color_r;
reg          ec4_r, ec3_r; // registered elim_cnt: 4 or 3 (both 0: 0)

// After the replay (or for a chain of 2) lo_q / hi_q are the survivors next to the final arc and
// rem_q the beads left: the replay advances lo / hi exactly as often as the count did, and rem_q
// is only counted down in S_EV, so the deletion job reads these registers directly.
reg  [7:0]   lo_q, hi_q;   // walker frontiers (slots of the next beads to test)
reg  [7:0]   lo2_q, hi2_q; // replay start: frontiers after level 2, moved on by the first two levels of the count
reg  [8:0]   rem_q;        // beads not eliminated yet
reg  [6:0]   nlev_q;       // levels found / chain length; counted down by the replay
reg  [23:0]  wl_q, wr_q;   // left chunk (wl[0] = frontier side) / right chunk
reg  [6:0]   dl_q, dr_q;   // frontier offset inside the chunks, one-hot (offset 0 .. 6)
reg  [1:0]   pp_q, qp_q;   // run lengths taken by the walker in the previous cycle
reg          ph_q;         // 0: the window reads a left chunk in this cycle
reg          rw_q;         // replay mode
reg          jgen_q;       // create the deletion job of the final arc at this edge

reg          u_ins_q;      // this cycle: insert ub_q at slot up_q
reg          u_del_q;      // this cycle: delete the two beads at slots up_q, up_q + 1
reg  [8:0]   up_q;
reg  [2:0]   ub_q;
reg  [8:0]   r_y;         // beads still to delete at slot r_pos after this cycle
reg  [8:0]   r_pos;

wire         new_game = in_valid & ~iv_q;

// ---------------------------------------------------------------- shot decode (before the sampling edge)
// Uses shot_pos and mf_q only; mf_q is final before any shot can arrive.
// Window start S = (k - 3) mod M; window positions at or beyond M come from head slots 0..6.
// The window registers hold the centre C = S + 3: C = k for k >= 3 (no borrow from k - 3) and
// C = M + k for k < 3. shot_pos arrives half a cycle late, so everything that depends on mf_q alone
// is prepared first. The cases k = 0 / 1 / 2 and k + j == M exclude each other (for M >= 8), so they
// are combined as AND-OR terms instead of priority muxes.
wire [8:0]  mfm1 = mf_q - 9'd1;
wire [8:0]  mfm2 = mf_q - 9'd2;
wire [8:0]  mfm3 = mf_q - 9'd3;
wire [8:0]  mfm4 = mf_q - 9'd4;
wire [8:0]  mfp1 = mf_q + 9'd1;
wire [8:0]  mfp2 = mf_q + 9'd2;
wire        mf_small = (mf_q < 9'd8);
wire        nsm      = ~mf_small;
wire        hi0      = (shot_pos[7:3] == 5'd0);             // k < 8
wire        kz0      = hi0 & (shot_pos[2:0] == 3'd0);       // k == 0 / 1 / 2
wire        kz1      = hi0 & (shot_pos[2:0] == 3'd1);
wire        kz2      = hi0 & (shot_pos[2:0] == 3'd2);

// k >= 3: centre k straight from shot_pos (row 0 / offsets 0..2 of k < 3 are left out)
wire [31:0] rowk   = 32'd1 << shot_pos[7:3];
wire [7:0]  xok    = 8'd1 << shot_pos[2:0];
wire [31:0] row_a  = {rowk[31:1], hi0 & (shot_pos[2] | (shot_pos[1] & shot_pos[0]))};
wire [7:0]  xoh_a  = {xok[7:3], xok[2:0] & {3{~hi0}}};

// k < 3: centre M + k. Its non-substituted positions w < 3 - k are slots M - 3 + k + w, so the window is read
// around the static row R = M >> 3 with the offset o = M[2:0] + k (0..9): slot 8R - 3 + o + w = M - 3 + k + w
// (index o + w <= M[2:0] + 2 <= 9 of the 15 read slots). One row candidate from mf_q instead of three.
wire [31:0] rowm   = 32'd1 << mf_q[7:3];
wire [9:0]  xom    = 10'd1 << mf_q[2:0];
wire        kzs    = kz0 | kz1 | kz2;
wire [31:0] sh_row = row_a | ({32{kzs}} & rowm);
wire [9:0]  sh_xoh = {2'b00, xoh_a} | ({10{kz0}} & xom) | ({10{kz1}} & {xom[8:0], 1'b0}) | ({10{kz2}} & {xom[7:0], 2'b00});

// head substitution flags: k + j == M (j = 1..4) marks the first position w = 3 + j that wraps,
// k = 0 / 1 / 2 the first position 3 / 2 / 1. Only these flags are registered; the substitution
// itself is decoded in the read cycle (below).
wire        sq1 = ({1'b0, shot_pos} == mfm1);
wire        sq2 = ({1'b0, shot_pos} == mfm2);
wire        sq3 = ({1'b0, shot_pos} == mfm3);
wire        sq4 = ({1'b0, shot_pos} == mfm4);

// M < 8: whole ring is in head slots 0..6, index (k - 3 + w) mod M, one table row per k
// (one correction is enough for every position the logic uses); the row of k is registered (w_hs)
reg  [191:0] hs_tab;
integer      ht, hw, vv;
always @* begin
    for (ht = 0; ht < 8; ht = ht + 1)
        for (hw = 0; hw < 8; hw = hw + 1) begin
            vv = ht + hw + 5;                                // k - 3 + w + 8
            if (vv < 8) vv = vv - 8 + mf_q[2:0];
            else if (vv - 8 >= mf_q[2:0]) vv = vv - 8 - mf_q[2:0];
            else vv = vv - 8;
            hs_tab[24*ht + 3*hw +: 3] = vv[2:0];
        end
end

// ---------------------------------------------------------------- walker chunk decode
// left chunk: 8 beads ending at lo (start (lo - 7) mod M); right chunk: 8 beads starting at hi.
// The walker only runs when M >= 8, so one wrap correction is enough.
// centre C = S + 3 and wrap point w0 = M - S are computed from lo / hi in parallel (no serial mod):
// left chunk C = lo - 4 (lo >= 7) or lo + M - 4 (lo < 7), right chunk C = hi + 3
wire        l_ge7 = (lo_q >= 8'd7);
wire [8:0]  l_ca  = {1'b0, lo_q} - 9'd4;                   // lo >= 7
// lo < 7: lo + M - 4 is one of M - 4 .. M + 2, all computed for the shot decode already
wire [8:0]  l_cb  = ({9{lo_q[2:0] == 3'd0}} & mfm4) | ({9{lo_q[2:0] == 3'd1}} & mfm3)
                  | ({9{lo_q[2:0] == 3'd2}} & mfm2) | ({9{lo_q[2:0] == 3'd3}} & mfm1)
                  | ({9{lo_q[2:0] == 3'd4}} & mf_q) | ({9{lo_q[2:0] == 3'd5}} & mfp1)
                  | ({9{lo_q[2:0] == 3'd6}} & mfp2);
wire [8:0]  l_wb  = 9'd7 - {1'b0, lo_q};                  // M - (lo + M - 7)
wire [8:0]  ct_l  = l_ge7 ? l_ca : l_cb;
// lo >= 7: the chunk lo - 7 .. lo lies inside 0 .. M-1 (lo < M), so nothing wraps (w0 = 8)
wire [8:0]  w0_l  = l_ge7 ? 9'd8 : l_wb;
wire [8:0]  ct_r  = {1'b0, hi_q} + 9'd3;
wire [8:0]  w0_r  = mf_q - {1'b0, hi_q};
wire        pt_left = (state == S_SU1) | (state == S_SU3) | (((state == S_EV) | (state == S_REV)) & ph_q);
wire [8:0]  pt_c  = pt_left ? ct_l : ct_r;                  // window centre (bit 8 dropped: row 32 = row 0)
wire [8:0]  pt_w0 = pt_left ? w0_l : w0_r;                  // first position at or beyond M
// the wrap point is registered one-hot (only w0 < 8 matters: high bits zero)
wire        pt_w0in = (pt_w0[8:3] == 6'd0);
wire [7:0]  pt_w0oh = {8{pt_w0in}} & (8'd1 << pt_w0[2:0]);

// ---------------------------------------------------------------- window select registers
wire        ld_shot = (state == S_IDLE);
wire        ld_ptr  = (state == S_SU1) | (state == S_SU2) | (state == S_SU3) | (state == S_EV) | (state == S_REV);
always @(posedge clk) begin
    if (ld_shot) begin
        w_row  <= sh_row;
        w_xoh  <= sh_xoh;
        w_hs   <= hs_tab[24*shot_pos[2:0] +: 24];
        w_w0   <= 8'd0;
    end else if (ld_ptr) begin
        w_row  <= 32'd1 << pt_c[7:3];
        w_xoh  <= {2'b00, 8'd1 << pt_c[2:0]};
        w_w0   <= pt_w0oh;
    end
end

// ---------------------------------------------------------------- head substitution, decoded in the read cycle
// The window of S_C1 is the shot window, every other read is a walker chunk. For M >= 8 both substitute a suffix:
// positions w >= w0 take head slot w - w0, with w0 one-hot (shot: k = 2 / 1 / 0 -> 1 / 2 / 3, k = M-1 .. M-4 ->
// 4 .. 7, these exclude each other). For a shot with M < 8 every position takes head slot hs_tab[k][w].
// All inputs are registers (k_q, the flags, mf_q), so the selects are ready before the row read.
wire        rd_shot = (state == S_C1) | (state == S_WAIT);
wire [7:0]  w0oh    = rd_shot ? {km4_q, km3_q, km2_q, km1_q, k0_q, k1_q, k2_q, 1'b0} : w_w0;
wire        rd_sm   = rd_shot & mf_small;
wire [23:0] hid_s   = w_hs;
reg  [7:0]  w_sub;           // position w reads a head slot
reg  [55:0] w_hsel;          // position w reads head slot h: w_hsel[7*w + h]
integer     iw, ih;
always @* begin
    for (iw = 0; iw < 8; iw = iw + 1) begin
        w_sub[iw] = rd_sm;
        for (ih = 0; ih <= iw; ih = ih + 1)
            w_sub[iw] = w_sub[iw] | w0oh[ih];
        for (ih = 0; ih < 7; ih = ih + 1) begin
            w_hsel[7*iw + ih] = rd_sm & (hid_s[3*iw +: 3] == ih);
            if (ih <= iw)
                w_hsel[7*iw + ih] = w_hsel[7*iw + ih] | (~rd_sm & w0oh[iw - ih]);
        end
    end
end

// ---------------------------------------------------------------- window read: centre row and its neighbours
// row r holds slots 8r .. 8r + 7. With the centre C = 8R + o (R = w_row, o = w_xoh) the window is
// slots C - 3 .. C + 4: the last 3 slots of row R - 1, row R and the first 4 slots of row R + 1
// (rows mod 32; C >= 3 always). All are read with w_row directly: cat[j] = slot 8R - 3 + j, j = 0 .. 14.
reg  [44:0] cat;
integer     rb, rr;
always @* begin
    cat = 45'd0;
    for (rr = 0; rr < 32; rr = rr + 1) begin
        for (rb = 0; rb < 3; rb = rb + 1)
            cat[3*rb +: 3] = cat[3*rb +: 3] |
                ({3{w_row[rr]}} & ring_q[3*(8*((rr + 31) % 32) + rb + 5) +: 3]);
        for (rb = 0; rb < 8; rb = rb + 1)
            cat[3*(rb + 3) +: 3] = cat[3*(rb + 3) +: 3] |
                ({3{w_row[rr]}} & ring_q[3*(8*rr + rb) +: 3]);
        for (rb = 0; rb < 4; rb = rb + 1)
            cat[3*(rb + 11) +: 3] = cat[3*(rb + 11) +: 3] |
                ({3{w_row[rr]}} & ring_q[3*(8*((rr + 1) % 32) + rb) +: 3]);
    end
end

// offset select and head substitution in one AND-OR: win[w] = bead at window position w = cat[o + w]
// (offsets 8 / 9 only occur for k < 3, where just positions w <= 1 / w = 0 read the row)
reg  [23:0] win;
integer     ww, wb, wh;
always @* begin
    for (ww = 0; ww < 8; ww = ww + 1) begin
        win[3*ww +: 3] = 3'd0;
        for (wb = 0; wb < 10; wb = wb + 1)
            if (wb + ww <= 14 && (wb < 8 || ww + wb <= 9))
                win[3*ww +: 3] = win[3*ww +: 3] |
                    ({3{w_xoh[wb] & ~w_sub[ww]}} & cat[3*(wb + ww) +: 3]);
        for (wh = 0; wh < 7; wh = wh + 1)
            win[3*ww +: 3] = win[3*ww +: 3] |
                ({3{w_hsel[7*ww + wh]}} & ring_q[3*wh +: 3]);
    end
end

// ---------------------------------------------------------------- first compute cycle: levels 1 and 2
wire [2:0] L3 = win[2:0];      // logical k-3
wire [2:0] L2 = win[5:3];      // k-2
wire [2:0] L1 = win[8:6];      // k-1
wire [2:0] L0 = win[11:9];     // k
wire [2:0] R0 = win[14:12];    // k+1
wire [2:0] R1 = win[17:15];    // k+2
wire [2:0] R2 = win[20:18];    // k+3
wire [2:0] R3 = win[23:21];    // k+4

// M compares for S_PTR: registered at every edge (mf_q does not change at the S_C1 edge), so in S_PTR they
// hold the compares of the bead count of the shot
reg  m_ge2, m_ge5, m_ge9, m_ge10;
wire ha    = (L0 == s_q);
wire hb    = (R0 == s_q);
wire hl1   = (L1 == s_q);
wire hr1   = (R1 == s_q);

wire eL12  = (L1 == L2);
wire eL23  = (L2 == L3);
wire eL01  = (L0 == L1);
wire eR12  = (R1 == R2);
wire eR01  = (R0 == R1);
wire eR23  = (R2 == R3);
// S_C1 registers only these compares (and the beads k-2 .. k); the decision is made from them in S_PTR.
// ---------------------------------------------------------------- S_PTR: levels 1 and 2 from the registered compares
// e1 = cA | cB | cC with cA = ha & hb, cB = ha & ~hb & hl1, cC = ~ha & hb & hr1 (all with M >= 2);
// e2 = m_ge5 & (cA & e2A | cB & e2B | cC & e2C), split in the terms of cases A / B and C
wire       e1_q   = m_ge2 & (ha_r ? (hb_r | hl1_r) : (hb_r & hr1_r));
wire       e2ab_q = m_ge5 & ha_r & (hb_r ? (fa_r & (eL12_r | eR12_r)) : (hl1_r & fb_r & (eL23_r | eR01_r)));
wire       e2c_q  = m_ge5 & ~ha_r & hb_r & hr1_r & fc_r & (eL01_r | eR23_r);
wire       e2_q   = e2ab_q | e2c_q;
// case, level-2 runs and color are only used after level 1 fired (e1_q / e2_q mask them otherwise),
// and then ha / hb alone tell the case: A = ha & hb, B = ha & ~hb, C = ~ha
wire [1:0] cs_q   = ha_r ? (hb_r ? 2'd1 : 2'd2) : 2'd3;
wire       p2b_r  = ha_r ? (hb_r ? eL12_r : eL23_r) : eL01_r;
wire       q2b_r  = ha_r ? (hb_r ? eR12_r : eR01_r) : eR23_r;

// next cycle: bead counts after a chain 0 / 1 shot, and "at least 3 beads remain after level 2"
wire [8:0] m_p1  = mfp1;
wire [8:0] m_m2  = mfm2;
// local stop: level 3 needs equal colors at the two frontiers after level 2. With the case and the level-2 run
// lengths p / q, the frontiers that lie inside the window k-3 .. k+4 are: A: L2 or L3 against R2 or R3,
// B (p = 0): L3 against R1 or R2, C (q = 0): L1 or L2 against R3. Differing colors there end the chain at 2;
// so do 3 or fewer beads left after level 2 (3 contiguous old beads are never one color).
// The walker is needed only without such a proof and with at least 4 beads left.
wire       c2_stop = (cs_q == 2'd1) ? ((~p2b_r & q2b_r & stx_r) | (p2b_r & ~q2b_r & sty_r) | (p2b_r & q2b_r & stz_r))
                   : (cs_q == 2'd2) ? (~p2b_r & q2b_r & sty_r)
                   :                    (p2b_r & ~q2b_r & stx_r);
wire       calc3 = ((p2b_r & q2b_r) ? m_ge10 : m_ge9) & ~c2_stop;

// chain of 1: the pair to delete (old beads) and how it sits in the ring
//   A: pair k, k+1   B: pair k-1, k   C: pair k+1, k+2
//   pair M-1, 0 : drop one tail bead, delete slot 0 (dup)
//   pair M-2, M-1: drop two tail beads
// mf_q keeps the count before the shot until the job is created, so k == mf_q - j is the shot decode compare sq_j
wire kM1 = km1_q;
wire kM2 = km2_q;
wire kM3 = km3_q;
wire k0 = k0_q;
wire [8:0] k_p1 = {1'b0, k_q} + 9'd1;
wire [8:0] k_m1 = {1'b0, k_q} - 9'd1;
wire [8:0] c_pC = kM1 ? 9'd0 : k_p1;
wire       c1_dup = (cs_q == 2'd1) ? kM1 : (cs_q == 2'd2) ? k0  : kM2;
wire       c1_t2  = (cs_q == 2'd1) ? kM2 : (cs_q == 2'd2) ? kM1 : kM3;
wire [8:0] c1_p   = (cs_q == 2'd1) ? {1'b0, k_q} : (cs_q == 2'd2) ? k_m1 : c_pC;
wire [8:0] ins_p  = (mf_q == 9'd0) ? 9'd0 : k_p1;

// ---------------------------------------------------------------- frontiers after level 2
// The frontiers after level 2 are lo2 = (k - offl) mod M and hi2 = (k + offr) mod M (M >= 5 here) with
// offl = A: 2 + p, B: 3 + p, C: 1 + p (1..4) and offr = A: 3 + q, B: 2 + q, C: 4 + q (2..5). All candidates come
// from registers (k_q, mf_q, the k == M - j flags); the decoded case and runs only pick one (one-hot AND-OR).
//   left : k >= j ? k - j : M - (j - k), the latter one of mf_q - 1 .. 4 (k < 4 then)
//   right: k + j wraps exactly when k == M - d with d <= j, giving j - d
wire [7:0] lc1   = (k_q >= 8'd1) ? k_q - 8'd1 : mfm1[7:0];
wire [7:0] lc2   = (k_q >= 8'd2) ? k_q - 8'd2 : (k_q[0] ? mfm1[7:0] : mfm2[7:0]);
wire [7:0] lc3   = (k_q >= 8'd3) ? k_q - 8'd3 : (k_q[1:0] == 2'd2) ? mfm1[7:0] : (k_q[1:0] == 2'd1) ? mfm2[7:0] : mfm3[7:0];
wire [7:0] lc4   = (k_q >= 8'd4) ? k_q - 8'd4 : (k_q[1:0] == 2'd3) ? mfm1[7:0] : (k_q[1:0] == 2'd2) ? mfm2[7:0]
                 : (k_q[1:0] == 2'd1) ? mfm3[7:0] : mfm4[7:0];
wire [8:0] mfm5  = mf_q - 9'd5;
wire [8:0] mfm6  = mf_q - 9'd6;
wire       km5   = ({1'b0, k_q} == mfm5);
wire [7:0] hc2   = km1_q ? 8'd1 : km2_q ? 8'd0 : k_q + 8'd2;
wire [7:0] hc3   = km1_q ? 8'd2 : km2_q ? 8'd1 : km3_q ? 8'd0 : k_q + 8'd3;
wire [7:0] hc4   = km1_q ? 8'd3 : km2_q ? 8'd2 : km3_q ? 8'd1 : km4_q ? 8'd0 : k_q + 8'd4;
wire [7:0] hc5   = km1_q ? 8'd4 : km2_q ? 8'd3 : km3_q ? 8'd2 : km4_q ? 8'd1 : km5 ? 8'd0 : k_q + 8'd5;
// case A = ha & hb, B = ha & ~hb, C = ~ha; p / q as above
wire       cA_r  = ha_r & hb_r;
wire       cB_r  = ha_r & ~hb_r;
wire       cC_r  = ~ha_r;
wire       ol1   = cC_r & ~p2b_r;
wire       ol2   = (cA_r & ~p2b_r) | (cC_r & p2b_r);
wire       ol3   = (cA_r & p2b_r) | (cB_r & ~p2b_r);
wire       ol4   = cB_r & p2b_r;
wire       or2   = cB_r & ~q2b_r;
wire       or3   = (cA_r & ~q2b_r) | (cB_r & q2b_r);
wire       or4   = (cA_r & q2b_r) | (cC_r & ~q2b_r);
wire       or5   = cC_r & q2b_r;
wire [7:0] lo2v  = ({8{ol1}} & lc1) | ({8{ol2}} & lc2) | ({8{ol3}} & lc3) | ({8{ol4}} & lc4);
wire [7:0] hi2v  = ({8{or2}} & hc2) | ({8{or3}} & hc3) | ({8{or4}} & hc4) | ({8{or5}} & hc5);
// beads left after level 2: M - 4 - p - q
wire [8:0] rem2v = (p2b_r & q2b_r) ? mfm6 : (p2b_r ^ q2b_r) ? mfm5 : mfm4;          // used in S_PTR only

// ---------------------------------------------------------------- walker: one level per cycle
reg  [2:0] xa, xb, ya, yb;     // beads at the frontier offset and the next one
integer    od;
always @* begin
    xa = 3'd0; xb = 3'd0; ya = 3'd0; yb = 3'd0;
    for (od = 0; od < 7; od = od + 1) begin
        xa = xa | ({3{dl_q[od]}} & wl_q[3*od +: 3]);
        xb = xb | ({3{dl_q[od]}} & wl_q[3*od + 3 +: 3]);
        ya = ya | ({3{dr_q[od]}} & wr_q[3*od +: 3]);
        yb = yb | ({3{dr_q[od]}} & wr_q[3*od + 3 +: 3]);
    end
end
wire [2:0] pp_oh   = {pp_q == 2'd2, pp_q == 2'd1, pp_q == 2'd0};   // run lengths 0 / 1 / 2, one-hot
wire [2:0] qp_oh   = {qp_q == 2'd2, qp_q == 2'd1, qp_q == 2'd0};
wire       ev_ab   = (xa == xb);
wire       ev_cd   = (ya == yb);
wire       ev_fire = (rem_q >= 9'd3) & (xa == ya) & (ev_ab | ev_cd);
wire [1:0] ev_p    = ev_ab ? 2'd2 : 2'd1;
wire [1:0] ev_q    = ev_cd ? 2'd2 : 2'd1;
wire [2:0] ev_pq   = {1'b0, ev_p} + {1'b0, ev_q};          // beads of this level (3 or 4)
// next frontiers: both candidates computed from the registers, picked by the run lengths
// (lo, hi are slots 0 .. M-1): lo - 1 / lo - 2 only wrap for lo = 0 / 1, to M - 1 / M - 2, and
// hi + 1 / hi + 2 only for hi = M - 1 / M - 2, to 0 / 1 - equality tests against mf_q - 1 / - 2
// (computed for the shot decode anyway) instead of a second adder and a magnitude compare
wire       lo_z    = (lo_q == 8'd0);
wire       lo_o    = (lo_q == 8'd1);
wire [7:0] lo_d1   = lo_z ? mfm1[7:0] : lo_q - 8'd1;
wire [7:0] lo_d2   = lo_z ? mfm2[7:0] : lo_o ? mfm1[7:0] : lo_q - 8'd2;
wire [7:0] lo_nx   = ev_ab ? lo_d2 : lo_d1;
wire       hi_t1   = ({1'b0, hi_q} == mfm1);
wire       hi_t2   = ({1'b0, hi_q} == mfm2);
wire [7:0] hi_u1   = hi_t1 ? 8'd0 : hi_q + 8'd1;
wire [7:0] hi_u2   = hi_t1 ? 8'd1 : hi_t2 ? 8'd0 : hi_q + 8'd2;
wire [7:0] hi_nx   = ev_cd ? hi_u2 : hi_u1;
// left chunk in walker order: lchunk[0] = window position 7 (the frontier)
wire [23:0] lchunk = {win[2:0], win[5:3], win[8:6], win[11:9], win[14:12], win[17:15], win[20:18], win[23:21]};
// level store: the count finds level 3 with nlev_q == 2 and level 4 with nlev_q == 3
wire        st_w3  = (state == S_EV) & ev_fire & (nlev_q == 7'd2);
wire        st_w4  = (state == S_EV) & ev_fire & (nlev_q == 7'd3);
wire        n_le4  = (nlev_q <= 7'd4);

// ---------------------------------------------------------------- ring update job
// generic job from the survivors next to the final arc (lo_q / hi_q / rem_q, see the registers)
wire       jg_empty = (rem_q == 9'd0);
wire       jg_in    = (lo_q < hi_q);
wire [8:0] jg_y_in  = {1'b0, hi_q} - {1'b0, lo_q} - 9'd1;
wire [8:0] jg_y     = jg_empty ? 9'd0 : jg_in ? jg_y_in : {1'b0, hi_q};
wire [8:0] jg_p     = jg_in ? {1'b0, lo_q} + 9'd1 : 9'd0;

// a new job (jgen_q) or the running one: two deletions while two or more beads remain,
// one dummy insert for the last odd one; one -2 / +1 shared by both
wire [8:0] j_y      = jgen_q ? jg_y : r_y;
wire [8:0] j_p      = jgen_q ? jg_p : r_pos;
wire       j_d2     = (j_y >= 9'd2);
wire       j_dup    = (j_y == 9'd1);
wire [8:0] j_ym2    = j_y - 9'd2;
wire [8:0] j_p1     = j_p + 9'd1;

// the job still has work after this edge
wire       j_more   = (r_y != 9'd0);

wire       c1_done  = c1d_q & ~e2_q;                  // the cycle after a chain 0 / 1 shot (state S_PTR)

// r_y (job still running) keeps its reset: it steers the state machine. The operation registers do not
// need one: after reset r_y = 0 and jgen_q = 0 give "no operation" at the first edge, and the ring is
// loaded before any shot (r_pos is cleared while loading, so the idle "no operation" cycles use a known slot).
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)        r_y <= 9'd0;
    else if (c1_done)  r_y <= (e1_q & c1_dup) ? 9'd2 : 9'd0;
    else if (in_valid) r_y <= 9'd0;
    else               r_y <= j_d2 ? j_ym2 : j_dup ? 9'd2 : 9'd0;
end

always @(posedge clk) begin
    if (c1_done) begin
        // chain 0: insert the shot bead; chain 1: delete the pair (chain >= 2: job comes later)
        // (beads dropped from the tail need no operation: mf_q already has the new count)
        u_ins_q <= ~e1_q | c1_dup;
        u_del_q <= e1_q & ~c1_dup & ~c1_t2;
        up_q    <= ~e1_q ? ins_p : c1_dup ? 9'd1 : c1_p;
        r_pos   <= 9'd0;
    end else if (in_valid) begin
        // ring loading: append the bead at the end (slot 0 for the first bead of a game);
        // mf_q counts the beads sampled before this one
        u_ins_q <= 1'b1;
        u_del_q <= 1'b0;
        up_q    <= iv_q ? mf_q : 9'd0;
        r_pos   <= 9'd0;
    end else begin
        u_ins_q <= j_dup;
        u_del_q <= j_d2;
        up_q    <= j_dup ? j_p1 : j_p;
        r_pos   <= j_p;
    end
end

always @(posedge clk) ub_q <= in_valid ? in_color : s_q;

// mf_q is set by the first bead of every game before any shot
always @(posedge clk) begin
    if (new_game) mf_q <= 9'd1;
    else if (in_valid) mf_q <= mf_q + 9'd1;
    else if (c1_done) mf_q <= e1_q ? m_m2 : m_p1;
    else if (jgen_q) mf_q <= rem_q;                  // chain >= 2: beads left, taken with the job of the final arc
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) iv_q <= 1'b0;
    else iv_q <= in_valid;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) c1d_q <= 1'b0;
    else c1d_q <= (state == S_C1);
end

// ---------------------------------------------------------------- ring update network
// per slot {keep, write, i-1, i+2}. The operation is folded into the 16 x 16 predecode, so every slot
// gets two thresholds from one AND-OR each: gi[i] = insert & (i >= up_q), gd[i] = delete & (i >= up_q)
// (u_ins_q and u_del_q are never both set); the selects then need no per-slot gate with the operation.
wire [15:0] gti_h, eqi_h, gtd_h, eqd_h, ge_l;
genvar g;
generate
    for (g = 0; g < 16; g = g + 1) begin : g_pre
        // every update position is at most 255, so up_q[8] is always 0
        assign gti_h[g] = u_ins_q & (up_q[7:4] < g);
        assign eqi_h[g] = u_ins_q & (up_q[7:4] == g);
        assign gtd_h[g] = u_del_q & (up_q[7:4] < g);
        assign eqd_h[g] = u_del_q & (up_q[7:4] == g);
        assign ge_l[g]  = (up_q[3:0] <= g);
    end
endgenerate

wire [255:0] gi, gd;
generate
    for (g = 0; g < 256; g = g + 1) begin : g_ge
        assign gi[g] = gti_h[g/16] | (eqi_h[g/16] & ge_l[g%16]);
        assign gd[g] = gtd_h[g/16] | (eqd_h[g/16] & ge_l[g%16]);
    end
endgenerate

wire [255:0] sel_w, sel_m1, sel_p2, sel_k;
generate
    for (g = 0; g < 256; g = g + 1) begin : g_sel
        if (g == 0) begin : g_first
            assign sel_w[g]  = gi[g];
            assign sel_m1[g] = 1'b0;
        end else begin : g_rest
            assign sel_w[g]  = gi[g] & ~gi[g-1];
            assign sel_m1[g] = gi[g-1];
        end
        assign sel_p2[g] = gd[g];
        assign sel_k[g]  = ~(gi[g] | gd[g]);
    end
endgenerate

// pad[3*(j+1) +: 3] is slot j; slot -1 and slots 256, 257 read as zero
wire [776:0] pad = {6'd0, ring_q, 3'd0};
reg  [767:0] ring_d;
integer      iu;
always @* begin
    for (iu = 0; iu < 256; iu = iu + 1)
        ring_d[3*iu +: 3] = (({3{sel_k[iu]}}  & pad[3*(iu+1) +: 3])
                           | ({3{sel_m1[iu]}} & pad[3*iu +: 3])
                           | ({3{sel_p2[iu]}} & pad[3*(iu+3) +: 3]))
                          | ({3{sel_w[iu]}}  & ub_q);
end

always @(posedge clk) ring_q <= ring_d;

// level store (reset: it is read only after it was written, but must not be unknown in a gate-level simulation)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) st_q <= 8'd0;
    else begin
        if (st_w3) st_q[3:0] <= {ev_ab & ev_cd, xa};
        if (st_w4) st_q[7:4] <= {ev_ab & ev_cd, xa};
    end
end

// ---------------------------------------------------------------- data registers (no reset needed)
always @(posedge clk) begin
    if (state == S_IDLE) begin
        k_q   <= shot_pos;
        s_q   <= shot_color;
        km1_q <= sq1;
        km2_q <= sq2;
        km3_q <= sq3;
        km4_q <= sq4;
        k0_q  <= kz0;
        k1_q  <= kz1;
        k2_q  <= kz2;
    end
    // S_C1 results, no enable: only the values taken in S_C1 are used (in S_PTR)
    ha_r   <= ha;
    hb_r   <= hb;
    hl1_r  <= hl1;
    hr1_r  <= hr1;
    fa_r   <= (L1 == R1);
    fb_r   <= (L2 == R0);
    fc_r   <= (L0 == R2);
    eL12_r <= eL12;
    eL23_r <= eL23;
    eL01_r <= eL01;
    eR12_r <= eR12;
    eR01_r <= eR01;
    eR23_r <= eR23;
    l0_r   <= L0;
    l1_r   <= L1;
    l2_r   <= L2;
    stx_r  <= (L2 != R3);
    m_ge2  <= (mf_q >= 9'd2);
    m_ge5  <= (mf_q >= 9'd5);
    m_ge9  <= (mf_q >= 9'd9);
    m_ge10 <= (mf_q >= 9'd10);
    sty_r  <= (L3 != R2);
    stz_r  <= (L3 != R3);
    if (state == S_PTR) begin
        p2b_q  <= p2b_r;
        q2b_q  <= q2b_r;
        col2_q <= (cs_q == 2'd1) ? l1_r : (cs_q == 2'd2) ? l2_r : l0_r;
    end
    if (state == S_PTR) begin                        // (used only after a chain >= 2; loaded in every S_PTR)
        lo_q   <= lo2v;
        hi_q   <= hi2v;
        lo2_q  <= lo2v;
        hi2_q  <= hi2v;
        rem_q  <= rem2v;
    end
    if ((state == S_SU2) | (state == S_C1)) wl_q <= lchunk;   // (S_C1: only to give them a known value)
    if ((state == S_SU3) | (state == S_C1)) wr_q <= win;
    if ((state == S_REV) | ((state == S_EV) & ev_fire)) begin
        lo_q  <= lo_nx;
        hi_q  <= hi_nx;
    end
    if (st_w3 | st_w4) begin                         // levels 3 / 4 come from the store, not from the replay
        lo2_q <= lo_nx;
        hi2_q <= hi_nx;
    end
    // chunks: loaded in every walker cycle (after an S_EV cycle without a level, S_SU2 / S_SU3 load them again)
    if ((state == S_REV) | (state == S_EV)) begin
        if (~ph_q) wl_q <= lchunk;
        else       wr_q <= win;
    end
    if ((state == S_EV) & ev_fire) rem_q <= rem_q - {6'd0, ev_pq};
    if ((state == S_EV) & ~ev_fire) begin
        lo_q   <= lo2_q;                             // replay starts after level 4 (chain of 2 .. 4: lo2_q == lo_q)
        hi_q   <= hi2_q;
    end
end

// ---------------------------------------------------------------- control and outputs
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state        <= S_IDLE;
        out_valid_r  <= 1'b0;
        chain_num_r  <= 7'd0;
        elim_color_r <= 3'd0;
        {ec4_r, ec3_r} <= 2'b00;
        jgen_q       <= 1'b0;
    end else begin
        jgen_q <= 1'b0;
        case (state)
        S_IDLE: begin
            if (shot_valid) state <= j_more ? S_WAIT : S_C1;
        end
        S_WAIT: begin
            if (!j_more) state <= S_C1;
        end
        S_C1: begin
            // levels 1 and 2 go to e1_q / e2_q only; the output registers stay 0
            state <= S_PTR;
        end
        S_O2A: begin
            elim_color_r <= col2_q;
            {ec4_r, ec3_r} <= {p2b_q & q2b_q, ~(p2b_q & q2b_q)};
            jgen_q       <= 1'b1;
            state        <= S_LAST;
        end
        S_O2B: begin
            elim_color_r <= col2_q;
            {ec4_r, ec3_r} <= {p2b_q & q2b_q, ~(p2b_q & q2b_q)};
            state        <= S_LAST;
        end
        S_LAST: begin
            out_valid_r  <= 1'b0;
            chain_num_r  <= 7'd0;
            elim_color_r <= 3'd0;
            {ec4_r, ec3_r} <= 2'b00;
            state        <= S_IDLE;
        end
        S_PTR: begin
            if (~e2_q) begin                         // chain 0 / 1: its only output cycle (decoded below)
                state  <= S_IDLE;
            end else if (calc3) begin                // the walker looks further
                state  <= S_SU1;
            end else begin                          // chain of 2, fewer than 3 beads left
                out_valid_r  <= 1'b1;
                chain_num_r  <= 7'd2;
                elim_color_r <= s_q;
                {ec4_r, ec3_r} <= 2'b01;
                state        <= S_O2A;
            end
        end
        S_SU1: begin
            if (rw_q) begin                         // burst: level 2
                elim_color_r <= col2_q;
                {ec4_r, ec3_r} <= {p2b_q & q2b_q, ~(p2b_q & q2b_q)};
            end
            state <= S_SU2;
        end
        S_SU2: begin
            if (rw_q) begin                         // level 3 from the store
                elim_color_r <= st_q[2:0];
                {ec4_r, ec3_r} <= {st_q[3], ~st_q[3]};
            end
            state <= (rw_q & (nlev_q == 7'd3)) ? S_LAST : S_SU3;
        end
        S_SU3: begin
            if (rw_q) begin                         // level 4 from the store
                elim_color_r <= st_q[6:4];
                {ec4_r, ec3_r} <= {st_q[7], ~st_q[7]};
            end
            state <= ~rw_q ? S_EV : (nlev_q == 7'd4) ? S_LAST : S_REV;
        end
        S_EV: begin                                  // (a level found: walker step in the walker registers below)
            if (ev_fire) begin
                state        <= S_EV;
            end else if (nlev_q == 7'd2) begin       // chain of 2
                out_valid_r  <= 1'b1;
                chain_num_r  <= 7'd2;
                elim_color_r <= s_q;
                {ec4_r, ec3_r} <= 2'b01;
                jgen_q       <= 1'b1;
                state        <= S_O2B;
            end else begin                           // chain >= 3: the burst starts with level 1
                out_valid_r  <= 1'b1;
                chain_num_r  <= nlev_q;
                elim_color_r <= s_q;
                {ec4_r, ec3_r} <= 2'b01;
                jgen_q       <= n_le4;               // chain of 3 / 4: no replay, the frontiers are final
                state        <= S_SU1;              // S_SU1 .. S_SU3: levels 2 .. 4 while the walker restarts
            end
        end
        S_REV: begin
            // chain_num_r was set from nlev_q at the end of the count; nlev_q now counts the levels still to
            // replay (level 5 with nlev_q = N, the last level with nlev_q = 5)
            elim_color_r <= xa;
            {ec4_r, ec3_r} <= {ev_ab & ev_cd, ~(ev_ab & ev_cd)};
            if (nlev_q == 7'd5) begin
                jgen_q <= 1'b1;
                state  <= S_LAST;
            end
        end
        default: state <= S_IDLE;
        endcase
    end
end

// walker registers: no reset, every shot sets them in S_PTR / S_SU1 .. S_SU3 before the walker reads them
// (S_PTR loads the start values even when the walker does not run; they are not used then).
// In S_EV / S_REV the offsets, run lengths and phase step in every cycle: an S_EV cycle without a level
// ends the count, and S_SU1 .. S_SU3 set them again before the replay (a chain of 2 does not use them),
// so only the level count waits for ev_fire.
always @(posedge clk) begin
    case (state)
    S_C1: begin                                      // start values, only to have known values early
        pp_q <= 2'd0;
        qp_q <= 2'd0;
        dl_q <= 7'd1;
        dr_q <= 7'd1;
        ph_q <= 1'b0;
    end
    S_PTR: begin
        nlev_q <= 7'd2;
        rw_q   <= 1'b0;
    end
    S_SU1: begin
        pp_q <= 2'd0;
        qp_q <= 2'd0;
    end
    S_SU2: dl_q <= 7'd1;
    S_SU3: begin
        dr_q <= 7'd1;
        ph_q <= 1'b0;
    end
    S_EV, S_REV: begin
        pp_q <= ev_p;
        qp_q <= ev_q;
        ph_q <= ~ph_q;
        // one-hot offsets: a new chunk starts at pp + run (pp = run taken last cycle), otherwise shift by the run
        if (~ph_q) begin
            dl_q <= ev_ab ? {2'b00, pp_oh, 2'b00} : {3'b000, pp_oh, 1'b0};
            dr_q <= ev_cd ? {dr_q[4:0], 2'b00} : {dr_q[5:0], 1'b0};
        end else begin
            dr_q <= ev_cd ? {2'b00, qp_oh, 2'b00} : {3'b000, qp_oh, 1'b0};
            dl_q <= ev_ab ? {dl_q[4:0], 2'b00} : {dl_q[5:0], 1'b0};
        end
        if (state == S_REV) nlev_q <= nlev_q - 7'd1;
        else begin
            rw_q <= 1'b1;                            // read only in S_SU2 / S_SU3: the next pass is the replay
            if (ev_fire) nlev_q <= nlev_q + 7'd1;
        end
    end
    default: ;
    endcase
end

// first output of a chain 0 / 1 shot, in the cycle after S_C1 (the registered part is 0 then)
wire c1_one = c1d_q & e1_q & ~e2_q;
assign out_valid  = out_valid_r | (c1d_q & ~e2_q);
assign chain_num  = chain_num_r | {6'd0, c1_one};
assign elim_color = elim_color_r | ({3{c1_one}} & s_q);
assign elim_cnt   = {6'd0, ec4_r, ec3_r | c1_one, ec3_r | c1_one};

endmodule
