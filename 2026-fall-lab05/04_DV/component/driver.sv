/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    driver.sv
* Project:      2026 FALL NYCU IC LAB, LAB05
* Module:       driver
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

import dv_pkg::*;

class driver;

    //=============================================================
    //                          CONSTRUCTOR
    //=============================================================

    virtual vif.drv vif;
    uint pat_num;
    mailbox #(txn) gen2drv;
    mailbox #(uint) scb2drv;    // the scoreboard puts the latency when all bytes of an image are checked

    function new(
        virtual vif.drv vif,
        uint pat_num,
        mailbox #(txn) gen2drv,
        mailbox #(uint) scb2drv
    );
        this.vif = vif;
        this.pat_num = pat_num;
        this.gen2drv = gen2drv;
        this.scb2drv = scb2drv;
    endfunction

    //=============================================================
    //                         RESET TASK
    //=============================================================

    task reset();
        vif.clk_en = 1'b0;
        vif.in_valid = 1'b0;
        vif.in_data = 'dx;

        vif.rst_n = 1'b1;
        #10 vif.rst_n = 1'b0;
        #100 vif.rst_n = 1'b1;

        // Avoiding recovery / removal violation
        #10 vif.clk_en = 1'b1;
        @(vif.drv_cb);
    endtask

    //=============================================================
    //                         DRIVE TASK
    //=============================================================

    // SPEC-12: 16384 cycles in raster order, no bubble
    task drive_image(txn t);
        for(int i = 0; i < PIX_NUM; i++) begin
            vif.drv_cb.in_valid <= 1'b1;
            vif.drv_cb.in_data <= t.pix[i];
            @(vif.drv_cb);
        end

        // SPEC-13: in_data is unknown after the last pixel
        vif.drv_cb.in_valid <= 1'b0;
        vif.drv_cb.in_data <= 'dx;
    endtask

    //=============================================================
    //                        WAITING TASK
    //=============================================================

    // Called at the negedge pulling in_valid down (E1, cycle 1 of spec Fig 14),
    // returns at the negedge where the next image may start
    task wait_out(bit last);
        uint cnt = 1;   // cycle number of the current negedge
        uint lat;       // cycle number of the last byte

        // SPEC-3: the scoreboard answers at the negedge of the last byte
        while(!scb2drv.try_get(lat)) begin
            if(cnt > TIMEOUT) begin
                $display("=============================================================");
                $display("   [SPEC-3 FAILED] Time out, latency over %0d cycles", TIMEOUT);
                $display("=============================================================");
                $fatal(1);
            end
            @(vif.drv_cb);
            cnt++;
        end
        // the answer may be taken in the same negedge it was put, check the byte itself too
        if(lat > TIMEOUT) begin
            $display("=============================================================");
            $display("   [SPEC-3 FAILED] Time out, latency = %0d > %0d cycles", lat, TIMEOUT);
            $display("=============================================================");
            $fatal(1);
        end

        // SPEC-14: the next in_valid at the 3rd ~ 6th negedge after the last out_valid,
        // the last image waits longer so extra bytes still reach the scoreboard
        lat += (last)? 10 : $urandom_range(3, 6);
        while(cnt < lat) begin
            @(vif.drv_cb);
            cnt++;
        end
    endtask

    //=============================================================
    //                           MAIN FLOW
    //=============================================================

    task run();
        txn t;
        for(int i = 0; i < pat_num; i++) begin
            gen2drv.get(t);
            drive_image(t);
            wait_out(i == pat_num - 1);
        end
    endtask

endclass
