/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    vif.sv
* Project:      2026 FALL NYCU IC LAB, LAB02
* Module:       verification interface
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

interface vif(input logic clk);
    
    logic rst_n;
    logic in_mode_valid;
    logic in_mode;
    logic in_data_valid;
    logic signed [5:0] in_data;

    logic out_valid;
    logic signed [7:0] out_data;
    logic out_warn;

    //=============================================================
    //                     Driver Interface
    //=============================================================

    clocking drv_cb @(negedge clk);
        default input #1step output #0;
        input out_valid;
        output in_mode_valid, in_mode, in_data_valid, in_data;
    endclocking

    // rst_n is asynchronous and driven by PATTERN drive_reset
    modport drv(clocking drv_cb);

    //=============================================================
    //                     Monitor Interface
    //=============================================================

    clocking mon_cb @(negedge clk);
        default input #1step;
        input in_mode_valid, in_mode, in_data_valid, in_data;
        input out_valid, out_data, out_warn;
    endclocking

    // rst_n is asynchronous and driven by PATTERN drive_reset
    modport mon(clocking mon_cb);


    //=============================================================
    //                   SystemVerilog Assertion
    //=============================================================

    // Async reset is checked in PATTERN at posedge rst_n since clk is forced during reset 

    OUT_VALID_UNKNOWN_CHECK: assert property(
        @(posedge clk) disable iff(!rst_n) !($isunknown(out_valid))
    ) else $fatal(1, "[SVA FAILED] out_valid must be known after reset"); 

    OUT_VALID_CHECK: assert property(
        @(posedge clk) disable iff(!rst_n) !out_valid |-> (!out_warn && out_data == 'd0)
    ) else $fatal(1, "[SVA FAILED] All outputs must be 0 when out_valid is zero");

    OUT_UNKNOWN_CHECK: assert property(
        @(posedge clk) disable iff(!rst_n) out_valid |-> !($isunknown(out_data) || $isunknown(out_warn))
    ) else $fatal(1, "[SVA FAILED] All outputs must be known when out_valid is asserted");  

    IN_OUT_VALID_CHECK: assert property(
        @(posedge clk) disable iff(!rst_n) out_valid |-> (!in_mode_valid && !in_data_valid)
    ) else $fatal(1, "[SVA FAILED] All input valid signal must be 0 when out_valid is asserted");

    OUT_WARN_CHECK: assert property(
        @(posedge clk) disable iff(!rst_n) out_valid |=> (out_valid -> $stable(out_warn))
    ) else $fatal(1, "[SVA FAILED] out_warn must be stable after out_valid is asserted");
    
    MAX_LAT_CHECK: assert property(
        @(posedge clk) disable iff(!rst_n) in_data_valid ##1 !in_data_valid |-> ##[0:99] out_valid
    ) else $fatal(1, "[SVA FAILED] out of maximum latency");

endinterface