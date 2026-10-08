/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    top.sv
* Project:      2026 FALL NYCU IC LAB, LAB01
* Module:       top
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/
`timescale 1ns/1ns

module top;

    //=============================================================
    //                      Connection Wires
    //=============================================================

    wire clk;
    wire [95:0] Inst_seq_I;
    wire [47:0] Inst_latency_I;
    wire [23:0] Inst_order_O;
    wire [8:0] Ex_cycle;

    //=============================================================
    //                         FSDB Dump
    //=============================================================

    `ifdef FSDB
        initial begin
            $fsdbDumpfile("OISS.fsdb");
            $fsdbDumpvars(0, u_dut, "+mda");
        end
    `endif

    //=============================================================
    //                   Sim Mode & SDF Annotate
    //=============================================================

    `ifdef GATE
        initial begin
            $display("=============================================================");
            $display("              [INFO] GATE-LEVEL SIMULATION START  ");
            $display("=============================================================");
            $sdf_annotate("../02_SYN/Netlist/OISS_SYN.sdf", u_dut);
        end
    `else
        initial begin
            $display("=============================================================");
            $display("               [INFO] BEHAVIORAL SIMULATION START  ");
            $display("=============================================================");
        end
    `endif

    //=============================================================
    //                         DUT & env
    //=============================================================

    // clk is only for testbench synchronization, OISS is purely combinational
    OISS u_dut (
        .Inst_seq_I(Inst_seq_I),
        .Inst_latency_I(Inst_latency_I),
        .Inst_order_O(Inst_order_O),
        .Ex_cycle(Ex_cycle)
    );

    env u_env (
        .clk(clk),
        .Inst_seq_I(Inst_seq_I),
        .Inst_latency_I(Inst_latency_I),
        .Inst_order_O(Inst_order_O),
        .Ex_cycle(Ex_cycle)
    );

endmodule
