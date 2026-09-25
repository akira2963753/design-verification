//############################################################################
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//   (C) Copyright Laboratory System Integration and Silicon Implementation
//   All Right Reserved
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//   ICLAB 2026 Fall
//   Lab02 Exercise
//   Author     		: Chuan-Chun Hsu
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//   File Name   : TESTBED.v
//   Module Name : TESTBED
//   Release version : V1.0 (Release Date: 2026-09)
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//############################################################################

`timescale 1ns/10ps
`include "PATTERN.v"
`ifdef RTL
  `include "LDPC.v"
`endif
`ifdef GATE
  `include "LDPC_SYN.v"
`endif
 
module TESTBED;

//Connection wires
wire clk;
wire rst_n;
wire in_mode_valid;
wire in_mode;
wire in_data_valid;
wire signed [5:0] in_data;

wire out_valid;
wire signed [7:0] out_data;
wire out_warn;



initial begin
  `ifdef RTL
    $fsdbDumpfile("LDPC.fsdb");
	  $fsdbDumpvars(0,"+mda");
    $fsdbDumpvars();
  `endif
  `ifdef GATE
    $sdf_annotate("LDPC_SYN.sdf", DUT_LDPC);
    $fsdbDumpfile("LDPC_SYN.fsdb");
	  $fsdbDumpvars(0,"+mda");
    $fsdbDumpvars();
  `endif
end

LDPC DUT_LDPC(
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

PATTERN My_PATTERN(
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
