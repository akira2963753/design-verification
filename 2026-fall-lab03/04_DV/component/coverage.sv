/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    coverage.sv
* Project:      2026 FALL NYCU IC LAB, LAB03
* Module:       coverage
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

// Functional coverage of the stimulus, sampled by the scoreboard with the golden result
class coverage;

    //=============================================================
    //                        Covergroup
    //=============================================================

    // One sample per ring loading phase
    covergroup cg_load with function sample(int len, int color_num);
        option.per_instance = 1;
        cp_len: coverpoint len {
            bins len4 = {4};
            bins len5_15 = {[5:15]};
            bins len16_63 = {[16:63]};
            bins len64_127 = {[64:127]};
            bins len128 = {128};
        }
        cp_color_num: coverpoint color_num {   // colors used by the initial ring
            bins two = {2};
            bins three_four = {[3:4]};
            bins five_up = {[5:8]};
        }
    endgroup

    // One sample per shot, region: 0 after index 0, 1 in between, 2 after index M-1 (across the seam)
    covergroup cg_shot with function sample(uint m, uint region, bit [2:0] color, int chain, bit wrap, bit head, bit clear);
        option.per_instance = 1;
        cp_size: coverpoint m {
            bins empty = {0};
            bins one = {1};
            bins two = {2};
            bins low = {[3:15]};
            bins mid = {[16:127]};
            bins high = {[128:254]};
            bins full = {255};
        }
        cp_region: coverpoint region iff(m >= 3) {
            bins head = {0};
            bins body = {1};
            bins tail = {2};
        }
        cp_color: coverpoint color;
        cp_chain: coverpoint chain {
            bins none = {0};
            bins one = {1};
            bins two = {2};
            bins few = {[3:4]};
            bins mid = {[5:8]};
            bins deep = {[9:16]};
            bins deeper = {[17:32]};
            bins deepest = {[33:127]};
        }
        cp_hit: coverpoint (chain != 0);
        cp_wrap: coverpoint wrap {bins yes = {1};}
        cp_head: coverpoint head {bins yes = {1};}
        cp_clear: coverpoint clear {bins yes = {1};}
        x_region_hit: cross cp_region, cp_hit;
    endgroup

    // One sample per cascade level
    covergroup cg_level with function sample(int level, bit [2:0] color, bit [8:0] cnt);
        option.per_instance = 1;
        cp_level: coverpoint level {
            bins l1 = {1};
            bins l2 = {2};
            bins l3_8 = {[3:8]};
            bins l9_up = {[9:127]};
        }
        cp_color: coverpoint color;
        cp_cnt: coverpoint cnt {
            bins three = {3};
            bins four = {4};
        }
        // Level 1 always eliminates exactly 3, a stable ring has no run longer than 2
        x_level_cnt: cross cp_level, cp_cnt {
            ignore_bins l1_four = binsof(cp_level.l1) && binsof(cp_cnt.four);
        }
    endgroup

    //=============================================================
    //                         Constructor
    //=============================================================

    function new();
        cg_load = new();
        cg_shot = new();
        cg_level = new();
    endfunction

    //=============================================================
    //                          Function
    //=============================================================

    function void sample_load(const ref bit [2:0] ring[$]);
        bit [7:0] seen = '0;
        foreach(ring[i]) seen[ring[i]] = 1'b1;
        cg_load.sample(ring.size(), $countones(seen));
    endfunction

    // m: ring size before the shot, rm: golden result of this shot
    function void sample_shot(uint m, bit [7:0] pos, bit [2:0] color, ref_model rm);
        uint region;
        region = (pos == 0)? 0 : (pos == m - 1)? 2 : 1;
        cg_shot.sample(m, region, color, rm.chain, rm.ev_wrap, rm.ev_head, rm.ev_clear);
        if(rm.chain != 0) foreach(rm.elim_cnt[i]) cg_level.sample(i + 1, rm.elim_color[i], rm.elim_cnt[i]);
    endfunction

    function void report();
        real load_cov, shot_cov, level_cov;
        load_cov = cg_load.get_inst_coverage();
        shot_cov = cg_shot.get_inst_coverage();
        level_cov = cg_level.get_inst_coverage();
        $display("=============================================================");
        $display("                    Functional Coverage");
        $display("=============================================================");
        $display("Ring load = %.2f %%, shot = %.2f %%, cascade level = %.2f %%", load_cov, shot_cov, level_cov);
        $display("Average = %.2f %%", (load_cov + shot_cov + level_cov) / 3.0);
        $display("=============================================================");
    endfunction

endclass
