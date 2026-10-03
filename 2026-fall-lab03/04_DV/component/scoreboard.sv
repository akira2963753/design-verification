/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    scoreboard.sv
* Project:      2026 FALL NYCU IC LAB, LAB03
* Module:       scoreboard
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

class scoreboard;

    //=============================================================
    //                          Variable
    //=============================================================

    mailbox #(mon_txn) mon2scb;
    ref_model rm;
    coverage cov;               // sampled with the golden result of every load / shot

    uint game_num;              // ring loading phases
    uint shot_num;              // checked shots, the env compares it with the driver
    uint game_shot;             // shots of the current game

    // Current game, dumped in TA input.txt format on failure
    bit [2:0] init_ring[$];
    bit [10:0] shot_log[$];     // {shot_pos, shot_color}

    // Statistics
    uint chain_hist[8];         // chain_num 0, 1, 2, 3, 4~7, 8~15, 16~31, 32~
    uint cnt_hist[3];           // elim_cnt 3, 4, others
    uint max_chain;
    uint max_ring;              // ring size right after the insertion
    uint total_lat;
    uint max_lat;
    uint ev_empty;              // shots into an empty ring
    uint ev_full;               // shots into a 255-bead ring, 256 beads after insertion
    uint ev_wrap;
    uint ev_head;
    uint ev_clear;

    //=============================================================
    //                         Constructor
    //=============================================================

    function new(
        mailbox #(mon_txn) mon2scb,
        coverage cov
    );
        this.mon2scb = mon2scb;
        this.cov = cov;
        this.rm = new();
    endfunction

    //=============================================================
    //                          Function
    //=============================================================

    function string ring_str(const ref bit [2:0] r[$]);
        string s = "";
        foreach(r[i]) s = {s, $sformatf("%0d ", r[i])};
        return s;
    endfunction

    // Write the current game up to the failed shot in TA input.txt format for replay
    function void dump_pattern();
        int fd;
        fd = $fopen("fail_input.txt", "w");
        $fdisplay(fd, "1");
        $fdisplay(fd, "%0d %0d", init_ring.size(), shot_log.size());
        $fdisplay(fd, "%s", ring_str(init_ring));
        foreach(shot_log[i]) $fdisplay(fd, "%0d %0d", shot_log[i][2:0], shot_log[i][10:3]);
        $fclose(fd);
    endfunction

    function void report_fail(string reason, mon_txn t, const ref bit [2:0] prev_ring[$]);
        int n;
        string gold, dut;
        $display("=============================================================");
        $display("     [SCB] Game [%0d] Shot [%0d] FAIL: %s", game_num, game_shot, reason);
        $display("=============================================================");
        $display("Ring before the shot (M = %0d): %s", prev_ring.size(), ring_str(prev_ring));
        $display("shot_color = %0d, shot_pos = %0d, latency = %0d", t.shot_color, t.shot_pos, t.lat);
        $display("Golden chain_num = %0d, DUT out_valid cycles = %0d", rm.chain, t.chain_num.size());
        n = (rm.elim_color.size() > t.chain_num.size())? rm.elim_color.size() : t.chain_num.size();
        for(int i = 0; i < n; i++) begin
            gold = (i < rm.elim_color.size())? $sformatf("(%0d, %0d)", rm.elim_color[i], rm.elim_cnt[i]) : "-";
            dut = (i < t.chain_num.size())? $sformatf("(%0d, %0d, %0d)", t.chain_num[i], t.elim_color[i], t.elim_cnt[i]) : "-";
            $display("    Cycle %3d: golden (color, cnt) = %s, DUT (chain_num, color, cnt) = %s", i + 1, gold, dut);
        end
        dump_pattern();
        $display("Game written to fail_input.txt (TA input.txt format)");
        $display("=============================================================");
        $fatal(1);
    endfunction

    // New game: in_valid must last exactly ring_len cycles
    function void load(mon_txn t);
        bit [2:0] init[$];
        if(t.ring.size() != t.ring_len) begin
            $display("=============================================================");
            $display("   [SCB] in_valid lasted %0d cycles, ring_len = %0d", t.ring.size(), t.ring_len);
            $display("=============================================================");
            $fatal(1);
        end
        foreach(t.ring[i]) init.push_back(t.ring[i]);
        rm.load(init);
        cov.sample_load(init);
        init_ring = init;
        shot_log.delete();
        game_shot = 0;
        game_num++;
    endfunction

    // Compare the whole out_valid burst of one shot at once
    function void check(mon_txn t);
        bit [2:0] prev_ring[$];
        uint m, exp_len;

        m = rm.ring.size();
        prev_ring = rm.ring;
        game_shot++;
        shot_log.push_back({t.shot_pos, t.shot_color});
        if(m != 0 && t.shot_pos >= m) report_fail("shot_pos out of range (TB)", t, prev_ring);
        rm.shoot(t.shot_color, t.shot_pos);

        exp_len = (rm.chain == 0)? 1 : rm.chain;
        if(t.chain_num[0] !== rm.chain) report_fail("chain_num mismatch", t, prev_ring);
        if(t.chain_num.size() != exp_len) report_fail("out_valid length mismatch", t, prev_ring);
        foreach(t.chain_num[i]) begin
            if(t.chain_num[i] !== rm.chain) report_fail($sformatf("chain_num changed at cycle %0d", i + 1), t, prev_ring);
            if(t.elim_color[i] !== rm.elim_color[i] || t.elim_cnt[i] !== rm.elim_cnt[i]) report_fail($sformatf("level %0d mismatch", i + 1), t, prev_ring);
        end

        // Statistics
        shot_num++;
        total_lat += t.lat;
        if(t.lat > max_lat) max_lat = t.lat;
        if(rm.chain > max_chain) max_chain = rm.chain;
        if(m + 1 > max_ring) max_ring = m + 1;
        chain_hist[(rm.chain < 4)? rm.chain : (rm.chain < 8)? 4 : (rm.chain < 16)? 5 : (rm.chain < 32)? 6 : 7]++;
        if(rm.chain != 0) foreach(rm.elim_cnt[i]) cnt_hist[(rm.elim_cnt[i] == 3)? 0 : (rm.elim_cnt[i] == 4)? 1 : 2]++;
        ev_empty += (m == 0);
        ev_full += (m == 255);
        ev_wrap += rm.ev_wrap;
        ev_head += rm.ev_head;
        ev_clear += rm.ev_clear;
        cov.sample_shot(m, t.shot_pos, t.shot_color, rm);
    endfunction

    function void report();
        $display("=============================================================");
        $display("                     Scoreboard Summary");
        $display("=============================================================");
        $display("Pass games = %0d, pass shots = %0d", game_num, shot_num);
        $display("Latency: total = %0d, max = %0d, avg = %.2f cycles", total_lat, max_lat, (shot_num == 0)? 0.0 : real'(total_lat) / shot_num);
        $display("chain_num 0 / 1 / 2 / 3 / 4~7 / 8~15 / 16~31 / 32~ = %0d / %0d / %0d / %0d / %0d / %0d / %0d / %0d, max = %0d",
            chain_hist[0], chain_hist[1], chain_hist[2], chain_hist[3], chain_hist[4], chain_hist[5], chain_hist[6], chain_hist[7], max_chain);
        $display("elim_cnt 3 / 4 / others = %0d / %0d / %0d", cnt_hist[0], cnt_hist[1], cnt_hist[2]);
        $display("Shots into empty ring = %0d, into 255 beads = %0d, max ring = %0d", ev_empty, ev_full, max_ring);
        $display("Wrap-around segments = %0d, index 0 eliminated = %0d, ring cleared = %0d", ev_wrap, ev_head, ev_clear);
        $display("=============================================================");
    endfunction

    //=============================================================
    //                          Main Run
    //=============================================================

    task run();
        mon_txn t;
        forever begin
            mon2scb.get(t);
            if(t.kind == MON_LOAD) load(t);
            else check(t);
        end
    endtask

endclass
