/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    vif.sv
* Project:      2026 FALL NYCU IC LAB, LAB05
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
    logic [7:0] in_data;
    logic out_valid;
    logic [7:0] out_data;

    logic clk_en = 1'b0;

    //=============================================================
    //                      DRIVER INTERFACE
    //=============================================================

    clocking drv_cb @(negedge clk);
        default input #1step output #0;
        input out_valid;
        output in_valid, in_data;
    endclocking

    modport drv(clocking drv_cb, output rst_n, clk_en, in_valid, in_data);

    //=============================================================
    //                      MONITOR INTERFACE
    //=============================================================

    clocking mon_cb @(negedge clk);
        default input #1step;
        input in_valid, in_data, out_valid, out_data;
    endclocking

    modport mon(clocking mon_cb);

    //=============================================================
    //                   SYSTEMVERILOG ASSERTION
    //=============================================================

    // Set by the falling edge of rst_n, the X -> 1 initialization at time 0 is not a reset
    bit rst_fell = 1'b0;

    always @(negedge rst_n) rst_fell = 1'b1;

    // SPEC-9: clk is held low during reset, so only an asynchronous reset clears the outputs
    CHECK_RESET: assert property(
        @(posedge rst_n) rst_fell |-> (out_valid === 1'b0 && out_data === 8'd0))
        else begin
            $display("=============================================================");
            $display("   [SPEC-9 FAILED] All output signals must be zero when reset");
            $display("=============================================================");
            $fatal(1);
        end

    // SPEC-17
    CHECK_OVERLAP: assert property(
        @(posedge clk) disable iff(!rst_n) (in_valid === 1'b1) |-> (out_valid === 1'b0))
        else begin
            $display("=============================================================");
            $display("   [SPEC-17 FAILED] out_valid cannot overlap with in_valid   ");
            $display("=============================================================");
            $fatal(1);
        end

    // SPEC-19
    CHECK_OUT_ZERO: assert property(
        @(posedge clk) disable iff(!rst_n) (out_valid === 1'b0) |-> (out_data === 8'd0))
        else begin
            $display("=============================================================");
            $display("   [SPEC-19 FAILED] out_data must be 0 when out_valid is low ");
            $display("=============================================================");
            $fatal(1);
        end

    // out_valid is never X after reset, an X would be skipped as a bubble by the monitor
    CHECK_VALID_X: assert property(
        @(posedge clk) disable iff(!rst_n) !$isunknown(out_valid))
        else begin
            $display("=============================================================");
            $display("     [SVA FAILED] out_valid must be known after reset        ");
            $display("=============================================================");
            $fatal(1);
        end

    // SPEC-18
    CHECK_DATA_X: assert property(
        @(posedge clk) disable iff(!rst_n) (out_valid === 1'b1) |-> !$isunknown(out_data))
        else begin
            $display("=============================================================");
            $display("   [SPEC-18 FAILED] out_data must be known when out_valid is high");
            $display("=============================================================");
            $fatal(1);
        end

endinterface
