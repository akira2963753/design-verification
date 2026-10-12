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
    //              INPUT / OUTPUT SIGNAL DECLARATION
    //=============================================================

    logic rst_n;
    logic in_valid;
    logic [31:0] Q;
    logic [31:0] K;
    logic [31:0] V;
    logic [31:0] out_weight;
    logic out_valid;
    logic [31:0] out;

    logic clk_en = 1'b0;

    //=============================================================
    //                      DRIVER INTERFACE
    //=============================================================

    clocking drv_cb @(negedge clk);
        default input #1step output #0;
        input out_valid;
        output in_valid, Q, K, V, out_weight;
    endclocking

    modport drv(clocking drv_cb, output rst_n, clk_en, in_valid, Q, K, V, out_weight);

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

    // SPEC-5 / IO-7
    CHECK_OUT: assert property(
        @(posedge clk) disable iff(!rst_n) !out_valid |-> out == 'd0)
        else begin
            $display("=============================================================");
            $display("     [SPEC-5 FAILED] out must be 0 when out_valid is low     ");
            $display("=============================================================");
            $fatal(1);
        end

    // IO-8
    CHECK_VALID: assert property(
        @(posedge clk) disable iff(!rst_n) in_valid |-> !out_valid)
        else begin
            $display("=============================================================");
            $display("   [IO-8 FAILED] out_valid cannot overlap with in_valid      ");
            $display("=============================================================");
            $fatal(1);
        end

    // IO-6
    CHECK_OUT_VALID_LEN: assert property(
        @(posedge clk) disable iff(!rst_n) $rose(out_valid) |-> out_valid[*64] ##1 !out_valid)
        else begin
            $display("=============================================================");
            $display("  [IO-6 FAILED] out_valid must be high for 64 cycles exactly ");
            $display("=============================================================");
            $fatal(1);
        end

endinterface