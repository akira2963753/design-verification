/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    monitor.sv
* Project:      2026 FALL NYCU IC LAB, LAB05
* Module:       monitor
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

import dv_pkg::*;

class monitor;

    //=============================================================
    //                          CONSTRUCTOR
    //=============================================================

    virtual vif.mon vif;
    mailbox #(mon_txn) mon2scb;     // images and bytes in time order

    function new(
        virtual vif.mon vif,
        mailbox #(mon_txn) mon2scb
    );
        this.vif = vif;
        this.mon2scb = mon2scb;
    endfunction

    //=============================================================
    //                           MAIN FLOW
    //=============================================================

    // Passive: samples every negedge, no knowledge of how many bytes an image has,
    // the scoreboard decides when an image is done
    task run();
        img_txn img;
        byte_txn b;
        int idx = -1;   // index of the next pixel, -1 = no image in progress
        uint lat = 0;   // cycles since in_valid fell, the falling negedge (E1) is cycle 1

        forever begin
            @(vif.mon_cb);
            lat++;

            // SPEC-12: 16384 consecutive pixels
            if(vif.mon_cb.in_valid === 1'b1) begin
                if(idx < 0) begin
                    img = new();
                    idx = 0;
                end
                img.pix[idx] = vif.mon_cb.in_data;
                idx++;

                // The last pixel is sampled at the negedge pulling in_valid down (E1 of spec Fig 14)
                if(idx == PIX_NUM) begin
                    mon2scb.put(img);
                    idx = -1;
                    lat = 1;
                end
            end

            if(vif.mon_cb.out_valid === 1'b1) begin
                b = new();
                b.data = vif.mon_cb.out_data;
                b.lat = lat;
                mon2scb.put(b);
            end
        end
    endtask

endclass
