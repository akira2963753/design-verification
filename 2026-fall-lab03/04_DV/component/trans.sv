/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    trans.sv
* Project:      2026 FALL NYCU IC LAB, LAB03
* Module:       transaction
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

typedef int unsigned uint;

//=============================================================
// Game kind, decides the ring shape and the shot policy mix
// K_RANDOM:    any length, 2~8 colors, random shots
// K_MATCH:     2~5 colors, shots join same-color neighbors
// K_SEAM:      short ring, shots around logical index M-1 / 0
// K_GROW:      long ring, no elimination, grows to 256 beads
// K_DRAIN:     2~3 colors, short ring, eliminations empty the ring
// K_CASCADE:   symmetric initial ring, the 1st shot starts a deep cascade
//=============================================================

typedef enum bit [2:0] {
    K_RANDOM,
    K_MATCH,
    K_SEAM,
    K_GROW,
    K_DRAIN,
    K_CASCADE
} kind_t;

//=============================================================
// Shot policy, length of the same-color run with the new bead
// P_RANDOM:    any
// P_HIT:       >= 3, level 1 elimination and maybe a cascade
// P_PAIR:      2, builds a pair for a later hit
// P_SAFE:      1, no elimination, the ring grows
// P_SEAM:      any, inserted next to logical index M-1 / 0
//=============================================================

typedef enum bit [2:0] {
    P_RANDOM,
    P_HIT,
    P_PAIR,
    P_SAFE,
    P_SEAM
} policy_t;

typedef enum bit {
    MON_LOAD,   // one ring loading phase
    MON_SHOT    // one shot with its whole out_valid burst
} mon_kind_t;

//=============================================================
//                      Shot Transaction
//=============================================================

class shot_txn;

    //=============================================================
    //                          Variable
    //=============================================================

    rand policy_t policy;
    rand bit [2:0] color;
    rand bit [7:0] pos;
    rand bit [10:0] pick;       // index into the candidate list of the policy
    rand bit [2:0] gap;         // negedges from out_valid low to the next shot_valid / in_valid

    // Shadow ring state, refreshed by the generator before every randomize()
    kind_t kind;
    uint ring_size;             // M before this shot
    bit [2:0] palette[$];
    bit [10:0] hit[$];          // {pos, color} making a run >= 3
    bit [10:0] pair[$];         // {pos, color} making a run of 2
    bit [10:0] safe[$];         // {pos, color} making a run of 1
    bit [10:0] seam[$];         // {pos, color} next to logical index M-1 / 0

    //=============================================================
    //                         Constraints
    //=============================================================

    constraint c_shot {
        color inside {palette};
        (ring_size == 0) -> pos == 0;   // empty ring: shot_pos is 0 and ignored
        (ring_size != 0) -> pos < ring_size;
    }

    constraint c_policy {
        if(ring_size == 255 && hit.size() != 0) {
            policy == P_HIT;    // eliminate inside a full 256-bead ring
        }
        else {
            (kind == K_RANDOM) -> policy dist {P_RANDOM := 1};
            (kind == K_MATCH) -> policy dist {P_HIT := 3, P_PAIR := 2, P_RANDOM := 1};
            (kind == K_SEAM) -> policy dist {P_SEAM := 3, P_HIT := 1, P_RANDOM := 1};
            (kind == K_GROW) -> policy dist {P_SAFE := 9, P_RANDOM := 1};
            (kind == K_DRAIN) -> policy dist {P_HIT := 4, P_PAIR := 2, P_RANDOM := 1};
            (kind == K_CASCADE) -> policy dist {P_HIT := 2, P_SEAM := 1, P_RANDOM := 1};
        }
        (hit.size() == 0) -> policy != P_HIT;
        (pair.size() == 0) -> policy != P_PAIR;
        (safe.size() == 0) -> policy != P_SAFE;
        (seam.size() == 0) -> policy != P_SEAM;
    }

    // An index is much cheaper to solve than {pos, color} inside {list}
    constraint c_pick {
        (policy == P_HIT) -> pick < hit.size();
        (policy == P_PAIR) -> pick < pair.size();
        (policy == P_SAFE) -> pick < safe.size();
        (policy == P_SEAM) -> pick < seam.size();
    }

    constraint c_gap {
        gap dist {1 := 30, [2:3] :/ 40, 4 := 30};
    }

    //=============================================================
    //                        Post Randomize
    //=============================================================

    // P_RANDOM keeps the solved pos / color, the other policies take the picked candidate
    function void post_randomize();
        case(policy)
            P_HIT: {pos, color} = hit[pick];
            P_PAIR: {pos, color} = pair[pick];
            P_SAFE: {pos, color} = safe[pick];
            P_SEAM: {pos, color} = seam[pick];
            default: ;
        endcase
    endfunction

endclass

//=============================================================
//                  Initial Ring (solved alone)
//=============================================================

// Palette, length and core are state here, so the solve stays small
class ring_seq;

    rand bit [2:0] bead[];

    bit [2:0] palette[$];
    int len;
    bit [2:0] core[$];          // fixed prefix, empty without a cascade core

    // No same-color run of 3 or more, wrap-around included
    constraint c_ring {
        bead.size() == len;
        foreach(bead[i]) {
            bead[i] inside {palette};
            if(i < core.size()) bead[i] == core[i];
            if(i >= 2) !(bead[i] == bead[i-1] && bead[i] == bead[i-2]);
            if(i == len - 1) !(bead[i-1] == bead[i] && bead[i] == bead[0]);
            if(i == len - 1) !(bead[i] == bead[0] && bead[0] == bead[1]);
        }
    }

endclass

//=============================================================
//                  Cascade Core (solved alone)
//=============================================================

// L_d .. L_1 [x x] R_1 .. R_d: level 1 eliminates [x x] + shot, level i+1 eliminates L_i + R_i
class core_seq;

    rand bit [2:0] lvl_color[]; // [0]: x, [i]: L_i / R_i
    rand bit [1:0] lsz[];       // [i-1]: |L_i|
    rand bit [1:0] rsz[];       // [i-1]: |R_i|

    bit [2:0] palette[$];
    int depth;
    int room;                   // ring_len - 1, >= 1 filler bead keeps L_d and R_d apart
    int extra;                  // levels that may take a 4th bead, room - (3 * depth + 2)

    // A guard on extra instead of lsz.sum() + rsz.sum() <= room, the sum is very slow when room is tight
    constraint c_core {
        lvl_color.size() == depth + 1;
        lsz.size() == depth;
        rsz.size() == depth;
        foreach(lvl_color[i]) {
            lvl_color[i] inside {palette};
            if(i >= 1) lvl_color[i] != lvl_color[i-1];
        }
        foreach(lsz[i]) {
            lsz[i] inside {[1:2]};
            rsz[i] inside {[1:2]};
            lsz[i] + rsz[i] >= 3;   // 3 or 4 beads per level
            if(i >= extra) lsz[i] + rsz[i] == 3;
        }
    }

    function void pre_randomize();
        extra = room - (3 * depth + 2);
    endfunction

    // Beads from L_d to R_d, lsum = |L_d| + .. + |L_1| = index of the 1st x
    function void get_core(output bit [2:0] core[$], output int lsum);
        core.delete();
        for(int i = depth; i >= 1; i--) repeat(lsz[i-1]) core.push_back(lvl_color[i]);
        lsum = core.size();
        repeat(2) core.push_back(lvl_color[0]);
        for(int i = 1; i <= depth; i++) repeat(rsz[i-1]) core.push_back(lvl_color[i]);
    endfunction

endclass

//=============================================================
//                      Game Transaction
//=============================================================

class txn;

    //=============================================================
    //                         Parameter
    //=============================================================

    localparam int N_KIND = 6;
    localparam int MIN_LEN = 4;
    localparam int MAX_LEN = 128;
    localparam int MAX_SHOT = 200;

    //=============================================================
    //                          Variable
    //=============================================================

    rand kind_t kind;
    rand bit [3:0] color_num;
    rand bit [2:0] palette[];   // colors of this game
    rand bit [7:0] ring_len;
    rand bit [7:0] shot_num;    // planned shots, the generator stops at 256 beads
    rand bit [2:0] in_gap;      // negedges from in_valid low to the 1st shot_valid
    rand bit [5:0] depth;       // cascade core levels, 0 without a core
    rand bit [7:0] rot;         // rotation, the core may cross logical index 0

    static uint kind_w[N_KIND]; // kind weights from the test

    bit [2:0] ring[];           // initial ring, logical index 0 ~ ring_len-1
    bit [2:0] trig_color;       // 1st shot of a cascade game
    bit [7:0] trig_pos;
    shot_txn shots[$];          // filled by the generator with the shadow ring

    //=============================================================
    //                         Constraints
    //=============================================================

    constraint c_kind {
        kind dist {
            K_RANDOM := kind_w[K_RANDOM],
            K_MATCH := kind_w[K_MATCH],
            K_SEAM := kind_w[K_SEAM],
            K_GROW := kind_w[K_GROW],
            K_DRAIN := kind_w[K_DRAIN],
            K_CASCADE := kind_w[K_CASCADE]
        };
        foreach(kind_w[i]) (kind_w[i] == 0) -> (kind != kind_t'(i));
    }

    constraint c_palette {
        (kind == K_RANDOM) -> color_num inside {[2:8]};
        (kind == K_MATCH) -> color_num inside {[2:5]};
        (kind == K_SEAM) -> color_num inside {[2:4]};
        (kind == K_GROW) -> color_num inside {[3:8]};
        (kind == K_DRAIN) -> color_num inside {[2:3]};
        (kind == K_CASCADE) -> color_num inside {[2:6]};
        palette.size() == color_num;
        unique {palette};
    }

    constraint c_len {
        ring_len inside {[MIN_LEN:MAX_LEN]};
        (kind == K_RANDOM) -> ring_len dist {MIN_LEN := 10, [MIN_LEN+1:MAX_LEN-1] :/ 80, MAX_LEN := 10};
        (kind == K_SEAM) -> ring_len <= 16;
        (kind == K_GROW) -> ring_len >= 100;
        (kind == K_DRAIN) -> ring_len <= 12;
    }

    constraint c_shot {
        (kind == K_GROW) -> shot_num inside {[130:255]};   // enough shots to reach 256 beads
        (kind != K_GROW) -> shot_num inside {[1:MAX_SHOT]};
        in_gap inside {[1:4]};
    }

    constraint c_core {
        (kind != K_CASCADE) -> depth == 0;
        (kind == K_CASCADE) -> {
            depth inside {[1:41]};
            3 * depth + 3 <= ring_len;
            depth dist {[1:3] :/ 30, [4:15] :/ 40, [16:41] :/ 30};
        }
        rot < ring_len;
        solve ring_len before rot;  // else a long ring has more rot solutions and is picked more often
    }

    //=============================================================
    //                        Post Randomize
    //=============================================================

    // Core and ring are solved after the game knobs, which are state there
    function void post_randomize();
        core_seq cs = new();
        ring_seq rs = new();
        int lsum = 0;

        rs.palette = palette;
        rs.len = ring_len;
        if(depth != 0) begin
            cs.palette = palette;
            cs.depth = depth;
            cs.room = ring_len - 1;
            if(!cs.randomize()) begin
                $display("=============================================================");
                $display("          [GEN] Cascade core randomize failed");
                $display("=============================================================");
                $fatal(1);
            end
            cs.get_core(rs.core, lsum);
            trig_color = cs.lvl_color[0];
        end

        if(!rs.randomize()) begin
            $display("=============================================================");
            $display("          [GEN] Initial ring randomize failed");
            $display("=============================================================");
            $fatal(1);
        end

        // new index i holds old index i + rot
        ring = new[ring_len];
        foreach(ring[i]) ring[i] = rs.bead[(i + rot) % ring_len];

        // insert x between the 2 beads of [x x]
        trig_pos = (lsum + ring_len - rot) % ring_len;
    endfunction

endclass

//=============================================================
//                    Monitor Transaction
//=============================================================

class mon_txn;
    mon_kind_t kind;
    logic [7:0] ring_len;       // MON_LOAD: sampled in the 1st in_valid cycle
    logic [2:0] ring[$];        // MON_LOAD: one bead per in_valid cycle
    logic [2:0] shot_color;     // MON_SHOT
    logic [7:0] shot_pos;
    logic [6:0] chain_num[$];   // MON_SHOT: one entry per out_valid cycle
    logic [2:0] elim_color[$];
    logic [8:0] elim_cnt[$];
    uint lat;                   // posedge taking shot_valid to the posedge out_valid falls
endclass
