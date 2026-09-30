/**************************************************************************/
// Copyright (c) 2026, SI2 Lab
// MODULE: TESTBED
// FILE NAME: TESTBED.v
// VERSRION: 1.0
// DATE: Aug 01, 2026
// AUTHOR: NYCU IEE
// CODE TYPE: RTL or Behavioral Level (Verilog)
// DESCRIPTION: 2026 Fall IC Lab / Exersise Lab03 / ZUMA
// MODIFICATION HISTORY:
// Date                 Description
//
/**************************************************************************/
`timescale 1ns/10ps

`include "PATTERN.v"
`ifdef RTL
    // `include "ZUMA.v"
    `include "ZUMA_encrypted.v"
`endif
`ifdef GATE
    `include "ZUMA_SYN.v"
`endif

module TESTBED;

wire            clk, rst_n;
// Ring loading interface
wire            in_valid;
wire [7:0]      ring_len;
wire [2:0]      in_color;
// Shooting interface
wire            shot_valid;
wire [2:0]      shot_color;
wire [7:0]      shot_pos;
// Result interface
wire            out_valid;
wire [6:0]      chain_num;
wire [2:0]      elim_color;
wire [8:0]      elim_cnt;

initial begin
    `ifdef RTL
        $fsdbDumpfile("ZUMA.fsdb");
        $fsdbDumpvars(0,"+mda");
    `endif
    `ifdef GATE
        $sdf_annotate("ZUMA_SYN.sdf", u_ZUMA);
        // $fsdbDumpfile("ZUMA_SYN.fsdb");
        // $fsdbDumpvars(0,"+mda");
    `endif
end

PATTERN u_PATTERN (
    .clk(clk),
    .rst_n(rst_n),

    .in_valid(in_valid),
    .ring_len(ring_len),
    .in_color(in_color),

    .shot_valid(shot_valid),
    .shot_color(shot_color),
    .shot_pos(shot_pos),

    .out_valid(out_valid),
    .chain_num(chain_num),
    .elim_color(elim_color),
    .elim_cnt(elim_cnt)
);

ZUMA u_ZUMA (
    .clk(clk),
    .rst_n(rst_n),

    .in_valid(in_valid),
    .ring_len(ring_len),
    .in_color(in_color),

    .shot_valid(shot_valid),
    .shot_color(shot_color),
    .shot_pos(shot_pos),

    .out_valid(out_valid),
    .chain_num(chain_num),
    .elim_color(elim_color),
    .elim_cnt(elim_cnt)
);

endmodule
