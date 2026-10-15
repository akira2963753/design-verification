/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    driver.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
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

    function new(
        virtual vif.drv vif,
        uint pat_num,
        mailbox #(txn) gen2drv
    );
        this.vif = vif;
        this.pat_num = pat_num;
        this.gen2drv = gen2drv;
    endfunction

    //=============================================================
    //                         RESET TASK
    //============================================================= 

    task reset();
        vif.clk_en = 1'b0;
        vif.in_valid = 1'b0;
        vif.Q = 'd0;
        vif.K = 'd0;
        vif.V = 'd0;
        vif.out_weight = 'd0;

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

    task drive_data(logic [31:0] q, k, v, w);
        vif.drv_cb.in_valid <= 1'b1;
        vif.drv_cb.Q <= q;
        vif.drv_cb.K <= k;
        vif.drv_cb.V <= v;
        vif.drv_cb.out_weight <= w;
        @(vif.drv_cb);
    endtask

    //=============================================================
    //                        WAITING TASK
    //=============================================================

    task wait_out();
        uint cnt = 0;
        uint out_cnt = 0;

        vif.drv_cb.in_valid <= 1'b0;
        vif.drv_cb.Q <= 'dx;
        vif.drv_cb.K <= 'dx;
        vif.drv_cb.V <= 'dx;
        vif.drv_cb.out_weight <= 'dx;

        while(vif.drv_cb.out_valid !== 1'b1) begin
            if(cnt == TIMEOUT) begin
                $display("=============================================================");
                $display(" [SPEC-6 FAILED] Time out, Your latency over the 1000 cycles ");
                $display("=============================================================");
                $fatal(1);
            end
            @(vif.drv_cb);
            cnt++;
        end

        // Wait for the 64 outputs, leaves at the 1st negedge after out_valid pulled down
        while(vif.drv_cb.out_valid === 1'b1) begin
            if(out_cnt == 64) begin
                $display("=============================================================");
                $display("  [IO-6 FAILED] out_valid must be high for 64 cycles exactly ");
                $display("=============================================================");
                $fatal(1);
            end
            @(vif.drv_cb);
            out_cnt++;
        end

        if(out_cnt != 64) begin
            $display("=============================================================");
            $display("  [IO-6 FAILED] out_valid must be high for 64 cycles exactly ");
            $display("=============================================================");
            $fatal(1);
        end
    endtask

    //=============================================================
    //                           MAIN FLOW
    //============================================================= 

    task run();
        txn t;
        for(int i = 0; i < pat_num; i++) begin
            gen2drv.get(t);
            for(int j = 0; j < 64; j++) begin
                if(j < 16) drive_data(t.q[j], t.k[j], t.v[j], t.w[j]);
                else drive_data(t.q[j], t.k[j], t.v[j],'dx);
            end
            wait_out();
            repeat($urandom_range(1, 3)) @(vif.drv_cb);
        end
    endtask

endclass