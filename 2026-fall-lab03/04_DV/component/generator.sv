/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    generator.sv
* Project:      2026 FALL NYCU IC LAB, LAB03
* Module:       generator
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/


class generator;

    //=============================================================
    //                          Variable
    //=============================================================

    uint pat_num;
    mailbox #(txn) gen2drv;
    ref_model rm;                   // shadow ring: every shot_pos stays in 0 ~ M-1, M <= 256

    // Statistics
    uint kind_num[txn::N_KIND];     // games per kind
    uint shot_total;

    //=============================================================
    //                          Constructor
    //=============================================================

    function new(
        uint pat_num,
        uint kind_w[txn::N_KIND],
        mailbox #(txn) gen2drv
    );
        this.pat_num = pat_num;
        this.gen2drv = gen2drv;
        this.rm = new();
        txn::kind_w = kind_w;
    endfunction

    //=============================================================
    //                          Function
    //=============================================================

    // {pos, color} candidates of the shadow ring for the shot policies
    function void set_state(shot_txn s, txn t);
        int m, len;
        bit [2:0] c;

        m = rm.ring.size();
        s.kind = t.kind;
        s.ring_size = m;
        s.palette = t.palette;

        // Only the 2 neighbor colors of the insertion point can make a run longer than 1
        for(int p = 0; p < m; p++) begin
            for(int k = 0; k < 2; k++) begin
                c = rm.ring[(p + k) % m];
                if(k == 1 && c == rm.ring[p]) continue;
                len = rm.run_len(p, c);
                if(len >= 3) s.hit.push_back({p[7:0], c});
                else if(len == 2) s.pair.push_back({p[7:0], c});
            end
            foreach(t.palette[j]) begin
                c = t.palette[j];
                if(c != rm.ring[p] && c != rm.ring[(p + 1) % m]) s.safe.push_back({p[7:0], c});
            end
        end
        if(m == 0) foreach(t.palette[j]) s.safe.push_back({8'd0, t.palette[j]});

        // Insert after index M-2, M-1 (across the seam) or 0 with a seam color
        if(m != 0) begin
            for(int p = m - 2; p <= m; p++) begin
                if(p < 0) continue;
                s.seam.push_back({8'(p % m), rm.ring[m-1]});
                s.seam.push_back({8'(p % m), rm.ring[0]});
            end
        end
    endfunction

    // Shots are planned on the shadow ring, so the game is complete before the driver gets it
    function void gen_shots(txn t);
        shot_txn s;
        bit ok;
        int trig[$];

        rm.load(t.ring);
        for(int i = 0; i < t.shot_num; i++) begin
            if(rm.ring.size() >= 256) break;    // one more bead would exceed 256
            s = new();
            set_state(s, t);
            if(t.kind == K_CASCADE && i == 0) begin
                // the 1st shot of a cascade game hits the [x x] pair of the core
                trig = s.hit.find_first_index(x) with (x == {t.trig_pos, t.trig_color});
                ok = (trig.size() != 0) && s.randomize() with {policy == P_HIT; pick == trig[0];};
            end
            else ok = s.randomize();
            if(!ok) begin
                $display("=============================================================");
                $display("   [GEN] Shot randomize failed: kind = %s, shot %0d, M = %0d", t.kind.name(), i, rm.ring.size());
                $display("=============================================================");
                $fatal(1);
            end

            rm.shoot(s.color, s.pos);
            if(t.kind == K_CASCADE && i == 0 && rm.chain < t.depth + 1) begin
                $display("=============================================================");
                $display("   [GEN] Cascade core broken: depth = %0d, chain_num = %0d", t.depth, rm.chain);
                $display("=============================================================");
                $fatal(1);
            end
            t.shots.push_back(s);
        end
        shot_total += t.shots.size();
    endfunction

    function void report();
        $display("Games: random = %0d, match = %0d, seam = %0d, grow = %0d, drain = %0d, cascade = %0d",
            kind_num[K_RANDOM], kind_num[K_MATCH], kind_num[K_SEAM], kind_num[K_GROW], kind_num[K_DRAIN], kind_num[K_CASCADE]);
    endfunction

    //=============================================================
    //                          Main Run
    //=============================================================

    task run();
        txn t;
        for(int i = 0; i < pat_num; i++) begin
            t = new();
            if(!t.randomize()) begin
                $display("=============================================================");
                $display("          [GEN] Randomize failed at game %0d", i);
                $display("=============================================================");
                $fatal(1);
            end
            gen_shots(t);
            kind_num[t.kind]++;
            gen2drv.put(t); // put the txn into gen2drv mailbox
        end
    endtask
endclass
