/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    driver.sv
* Project:      2026 FALL NYCU IC LAB, LAB03
* Module:       driver
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/


class driver;

    //=============================================================
    //                          Variable
    //=============================================================

    virtual vif.drv vif;
    uint pat_num;
    uint time_out;
    mailbox #(txn) gen2drv;
    uint shot_num;      // finished shots, the env waits until the scoreboard checked all of them

    //=============================================================
    //                         Constructor
    //=============================================================

    function new (
        virtual vif.drv vif,
        uint pat_num,
        uint time_out,
        mailbox #(txn) gen2drv
    );
        this.vif = vif;
        this.pat_num = pat_num;
        this.time_out = time_out;
        this.gen2drv = gen2drv;
        this.shot_num = 0;
    endfunction

    //=============================================================
    //                           Task
    //=============================================================

    // rst_n is given once, clk is held low so a synchronous reset fails SPEC-4
    task reset();
        // Written directly, drv_cb would wait for a clock edge that never comes
        vif.clk_en = 1'b0;
        vif.in_valid = 1'b0;
        vif.ring_len = 'd0;
        vif.in_color = 'd0;
        vif.shot_valid = 1'b0;
        vif.shot_color = 'd0;
        vif.shot_pos = 'd0;

        #10 vif.rst_n = 1'b0;
        #100 vif.rst_n = 1'b1;  // RESET_CHECK samples the outputs 100 ns after rst_n falls
        #10 vif.clk_en = 1'b1;
        @(vif.drv_cb);
    endtask

    // Valid low, data are random don't care values
    task idle_load();
        vif.drv_cb.in_valid <= 1'b0;
        vif.drv_cb.ring_len <= $urandom_range(255, 0);
        vif.drv_cb.in_color <= $urandom_range(7, 0);
    endtask

    task idle_shot();
        vif.drv_cb.shot_valid <= 1'b0;
        vif.drv_cb.shot_color <= $urandom_range(7, 0);
        vif.drv_cb.shot_pos <= $urandom_range(255, 0);
    endtask

    // in_valid stays high for ring_len cycles, ring_len is valid in the 1st cycle only
    task drive_load(txn t);
        foreach(t.ring[i]) begin
            vif.drv_cb.in_valid <= 1'b1;
            vif.drv_cb.ring_len <= (i == 0)? t.ring_len : $urandom_range(255, 0);
            vif.drv_cb.in_color <= t.ring[i];
            @(vif.drv_cb);
        end
        idle_load();
    endtask

    // shot_valid is a 1-cycle pulse
    task drive_shot(shot_txn s);
        vif.drv_cb.shot_valid <= 1'b1;
        vif.drv_cb.shot_color <= s.color;
        vif.drv_cb.shot_pos <= s.pos;
        @(vif.drv_cb);
        idle_shot();
    endtask

    // Wait for the whole out_valid burst, the next input comes 1~4 negedges after out_valid falls
    task wait_output(shot_txn s, uint game, uint idx);
        uint cnt = 0;
        while(vif.drv_cb.out_valid !== 1'b1) begin
            if(cnt >= time_out) begin
                $display("=============================================================");
                $display("[DRV] Game [%0d] Shot [%0d] no out_valid after %0d cycles", game, idx, time_out);
                $display("=============================================================");
                $fatal(1);
            end
            cnt++;
            @(vif.drv_cb);
        end
        while(vif.drv_cb.out_valid === 1'b1) begin
            if(cnt >= time_out) begin
                $display("=============================================================");
                $display("[DRV] Game [%0d] Shot [%0d] out_valid not low after %0d cycles", game, idx, time_out);
                $display("=============================================================");
                $fatal(1);
            end
            cnt++;
            @(vif.drv_cb);
        end
        repeat(s.gap - 1) @(vif.drv_cb);    // this negedge is already the 1st one
    endtask

    //=============================================================
    //                          Main Run
    //=============================================================

    task run();
        txn t;
        for(int i = 0; i < pat_num; i++) begin
            gen2drv.get(t);
            drive_load(t);
            repeat(t.in_gap) @(vif.drv_cb);
            foreach(t.shots[j]) begin
                drive_shot(t.shots[j]);
                wait_output(t.shots[j], i, j);
                shot_num++;
            end
        end
    endtask

endclass
