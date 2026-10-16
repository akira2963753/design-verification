/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    top.sv
* Project:      2026 FALL NYCU IC LAB, LAB05
* Module:       top
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/
`timescale 1ns/1ps

module top;

    //=============================================================
    //                           PARAMETER
    //=============================================================

    localparam realtime CLK_PERIOD = 20.0;     // same as CYCLE in 02_SYN/syn.tcl

    //=============================================================
    //                       CLOCK & INTERFACE
    //=============================================================

    logic clk;

    vif tb_if(.clk(clk));

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2.0) clk = (tb_if.clk_en)? ~clk : 1'b0;

    //=============================================================
    //                           FSDB DUMP
    //=============================================================

    `ifdef FSDB
        initial begin
            $fsdbDumpfile("JPEGLENC.fsdb");
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
            $sdf_annotate("../02_SYN/Netlist/JPEGLENC_SYN.sdf", u_dut, , ,"maximum");
        end
    `else
        initial begin
            $display("=============================================================");
            $display("               [INFO] BEHAVIORAL SIMULATION START            ");
            $display("               [INFO] Clock period = %0.1f ns", CLK_PERIOD);
            $display("=============================================================");
        end
    `endif

    //=============================================================
    //                          DUT & TEST
    //=============================================================

    JPEGLENC u_dut (
        .clk(clk),
        .rst_n(tb_if.rst_n),
        .in_valid(tb_if.in_valid),
        .in_data(tb_if.in_data),
        .out_valid(tb_if.out_valid),
        .out_data(tb_if.out_data)
    );

    test u_test(.tb_if(tb_if));

endmodule
