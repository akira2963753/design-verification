/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    top.sv
* Project:      2026 FALL NYCU IC LAB, LAB02
* Module:       top
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/
`timescale 1ns/1ps

module top;

    //=============================================================
    //                      Connection Wires
    //=============================================================

    wire clk, rst_n;
    wire in_mode_valid, in_mode, in_data_valid;
    wire signed [5:0] in_data;
    wire out_valid, out_warn;
    wire signed [7:0] out_data;

    //=============================================================
    //                         FSDB Dump
    //=============================================================

    `ifdef FSDB
        initial begin
            $fsdbDumpfile("LDPC.fsdb");
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
            $sdf_annotate("../02_SYN/Netlist/LDPC_SYN.sdf", u_dut, , ,"maximum");
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

    LDPC u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_mode_valid(in_mode_valid),
        .in_mode(in_mode),
        .in_data_valid(in_data_valid),
        .in_data(in_data),
        .out_valid(out_valid),
        .out_data(out_data),
        .out_warn(out_warn)
    );

    env u_env (
        .clk(clk),
        .rst_n(rst_n),
        .in_mode_valid(in_mode_valid),
        .in_mode(in_mode),
        .in_data_valid(in_data_valid),
        .in_data(in_data),
        .out_valid(out_valid),
        .out_data(out_data),
        .out_warn(out_warn)
    );

endmodule
