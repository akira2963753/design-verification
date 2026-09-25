/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    vif.sv
* Project:      2026 FALL NYCU IC LAB, LAB02
* Module:       vif
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

interface vif(input logic clk);

    logic rst_n;

    // TB -> DUT
    logic in_mode_valid;
    logic in_mode;
    logic in_data_valid;
    logic signed [5:0] in_data;

    // DUT -> TB
    logic out_valid;
    logic signed [7:0] out_data;
    logic out_warn;

    clocking drv_cb @(negedge clk);
        default input #1step output #0;
        output in_mode_valid, in_mode, in_data_valid, in_data;
        input out_valid;
    endclocking

    clocking mon_cb @(negedge clk);
        default input #1step;
        input in_mode_valid, in_mode, in_data_valid, in_data;
        input out_valid, out_data, out_warn;
    endclocking

    // rst_n is asynchronous and driven by PATTERN drive_reset
    modport DRV(clocking drv_cb);
    modport MON(clocking mon_cb, input rst_n);

endinterface
