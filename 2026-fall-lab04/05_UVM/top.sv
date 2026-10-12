/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    top.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       top
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/
`timescale 1ns/1ps

module top;

    import uvm_pkg::*;
    import fattn_pkg::*;    // registers every test / component class to the factory

    //=============================================================
    //                           PARAMETER
    //=============================================================

    localparam realtime CLK_PERIOD = 50.0;     // same as 02_SYN/syn.tcl and TA PATTERN

    //=============================================================
    //                       CLOCK & INTERFACE
    //=============================================================

    logic clk;

    vif tb_if(.clk(clk));

    // clk stays low until driver.reset() sets clk_en, a synchronous reset never sees an edge
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2.0) clk = (tb_if.clk_en)? ~clk : 1'b0;

    //=============================================================
    //                           FSDB DUMP
    //=============================================================

    `ifdef FSDB
        initial begin
            $fsdbDumpfile("F_ATTN.fsdb");
            $fsdbDumpvars(0, top, "+mda");
        end
    `endif

    //=============================================================
    //                    SIM MODE & SDF ANNOTATE
    //=============================================================

    `ifdef GATE
        initial begin
            $display("=============================================================");
            $display("              [INFO] GATE-LEVEL SIMULATION START  ");
            $display("              [INFO] Clock period = %0.1f ns", CLK_PERIOD);
            $display("=============================================================");
            $sdf_annotate("../02_SYN/Netlist/F_ATTN_SYN.sdf", u_dut, , ,"maximum");
        end
    `else
        initial begin
            $display("=============================================================");
            $display("               [INFO] BEHAVIORAL SIMULATION START  ");
            $display("               [INFO] Clock period = %0.1f ns", CLK_PERIOD);
            $display("=============================================================");
        end
    `endif

    //=============================================================
    //                              DUT
    //=============================================================

    F_ATTN u_dut (
        .clk(clk),
        .rst_n(tb_if.rst_n),
        .in_valid(tb_if.in_valid),
        .Q(tb_if.Q),
        .K(tb_if.K),
        .V(tb_if.V),
        .out_weight(tb_if.out_weight),
        .out_valid(tb_if.out_valid),
        .out(tb_if.out)
    );

    //=============================================================
    //                           RUN TEST
    //=============================================================

    // The test class is uvm_test_top, each modport goes only to the component that uses it
    initial begin
        uvm_config_db #(virtual vif.drv)::set(null, "uvm_test_top.env.agt.drv", "vif", tb_if);
        uvm_config_db #(virtual vif.mon)::set(null, "uvm_test_top.env.agt.mon", "vif", tb_if);
        run_test();
    end

endmodule
