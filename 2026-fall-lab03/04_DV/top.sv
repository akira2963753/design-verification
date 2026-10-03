/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    top.sv
* Project:      2026 FALL NYCU IC LAB, LAB03
* Module:       top
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/
`timescale 1ns/1ps

module top;

    //=============================================================
    //                         Parameter
    //=============================================================

    localparam realtime CLK_PERIOD = 15.0;

    //=============================================================
    //                    Clock & Interface
    //=============================================================

    logic clk;

    vif tb_if(.clk(clk));

    // clk stays low until driver.reset() sets clk_en, a synchronous reset never sees an edge
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2.0) clk = (tb_if.clk_en)? ~clk : 1'b0;

    //=============================================================
    //                         FSDB Dump
    //=============================================================

    `ifdef FSDB
        initial begin
            $fsdbDumpfile("ZUMA.fsdb");
            $fsdbDumpvars(0, top, "+mda");
        end
    `endif

    //=============================================================
    //                   Sim Mode & SDF Annotate
    //=============================================================

    `ifdef GATE
        initial begin
            $display("=============================================================");
            $display("              [INFO] GATE-LEVEL SIMULATION START  ");
            $display("              [INFO] Clock period = %0.1f ns", CLK_PERIOD);
            $display("=============================================================");
            $sdf_annotate("../02_SYN/Netlist/ZUMA_SYN.sdf", u_dut, , ,"maximum");
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
    //                         DUT & test
    //=============================================================

    ZUMA u_dut (
        .clk(clk),
        .rst_n(tb_if.rst_n),
        .in_valid(tb_if.in_valid),
        .ring_len(tb_if.ring_len),
        .in_color(tb_if.in_color),
        .shot_valid(tb_if.shot_valid),
        .shot_color(tb_if.shot_color),
        .shot_pos(tb_if.shot_pos),
        .out_valid(tb_if.out_valid),
        .chain_num(tb_if.chain_num),
        .elim_color(tb_if.elim_color),
        .elim_cnt(tb_if.elim_cnt)
    );

    test u_test(.tb_if(tb_if));

endmodule
