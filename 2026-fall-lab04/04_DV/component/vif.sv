/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    vif.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       verification interface
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

interface vif(input logic clk);

    //=============================================================
    //              INPUT / OUTPUT SIGNAL DECLARTION
    //=============================================================

    logic rst_n;
    logic in_valid;
    logic [31:0] Q;
    logic [31:0] K;
    logic [31:0] V;
    logic [31:0] out_weight;
    logic out_valid;
    logic [31:0] out;

    //=============================================================
    //                      DRIVER INTERFACE
    //=============================================================

    clocking drv_cb @(negedge clk);
        default input #1step output #0;
        input out_valid;
        output in_valid, Q, K, V, out_weight;
    endclocking

    modport drv(clocking drv_cb);

    //=============================================================
    //                      MONITOR INTERFACE
    //=============================================================

    clocking mon_cb @(negedge clk);
        default input #1step;
        input in_valid, Q, K, V, out_weight, out_valid, out;
    endclocking

    modport mon(clocking mon_cb);

    //=============================================================
    //                   SYSTEMVERILOG ASSERTION
    //=============================================================

endinterface