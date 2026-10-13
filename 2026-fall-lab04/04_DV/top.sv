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

    //=============================================================
    //                           PARAMETER
    //=============================================================

    localparam realtime CLK_PERIOD = 50.0; 

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
            $display("               [INFO] BEHAVIORAL SIMULATION START            ");
            $display("               [INFO] Clock period = %0.1f ns", CLK_PERIOD);
            $display("=============================================================");
        end
    `endif

    //=============================================================
    //                          DUT & TEST
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

    test u_test(.tb_if(tb_if));

endmodule
