/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    vif.sv
* Project:      2026 FALL NYCU IC LAB, LAB01
* Module:       vif (verification interface)
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

interface vif(input logic clk);

    logic [95:0] Inst_seq_I;
    logic [47:0] Inst_latency_I;
    logic [23:0] Inst_order_O;
    logic [8:0] Ex_cycle;

    // Testbench-only qualifier; this signal is not connected to the DUT.
    logic sample_valid = 1'b0;

    //=============================================================
    //                    Driver Clocking Block
    //=============================================================

    // driver 在 posedge 前一個 cycle send data
    clocking driver_cb @(posedge clk);
        default input #1step output #0;
        output Inst_seq_I;
        output Inst_latency_I;
        output sample_valid;
    endclocking

    //=============================================================
    //                    Monitor Clocking Block
    //=============================================================
    
    // monitor 在 posedge 前一個 cycle sample data
    clocking monitor_cb @(posedge clk);
        default input #1step output #0;
        input Inst_seq_I;
        input Inst_latency_I;
        input Inst_order_O;
        input Ex_cycle;
        input sample_valid;
    endclocking

    //=============================================================
    //                           Modports
    //=============================================================
    modport driver_mp (clocking driver_cb);
    modport monitor_mp (clocking monitor_cb);

endinterface
