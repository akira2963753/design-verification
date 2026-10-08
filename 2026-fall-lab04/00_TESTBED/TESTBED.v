//############################################################################
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//   (C) Copyright Laboratory System Integration and Silicon Implementation
//   All Right Reserved
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//   ICLAB 2026 Fall
//   Lab04 Exercise		: Flash Attention
//   Author     		: Yu Chen Hung 
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//   File Name   : F_ATTN.v
//   Module Name : F_ATTN
//   Release version : V1.0 
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//############################################################################


`timescale 1ns/10ps



 		  	
module TESTBED;

wire          clk, rst_n, in_valid;
wire  [31:0]  Q;
wire  [31:0]  K;
wire  [31:0]  V;
wire  [31:0]  out_weight;
wire          out_valid;
wire  [31:0]  out;


initial begin
  `ifdef RTL
    $fsdbDumpfile("F_ATTN.fsdb");
	  $fsdbDumpvars(0,"+mda");
    $fsdbDumpvars();
  `endif
  `ifdef GATE
    $sdf_annotate("../02_SYN/Netlist/F_ATTN_SYN.sdf", u_F_ATTN);
    $fsdbDumpfile("F_ATTN_SYN.fsdb");
    $fsdbDumpvars(0,"+mda");
    $fsdbDumpvars();    
  `endif
end

F_ATTN u_F_ATTN(
    .clk(clk),
    .rst_n(rst_n),
    .in_valid(in_valid),
    .Q(Q),
    .K(K),
    .V(V),
    .out_weight(out_weight),
    .out_valid(out_valid),
    .out(out)
    );

PATTERN u_PATTERN(
    .clk(clk),
    .rst_n(rst_n),
    .in_valid(in_valid),
    .Q(Q),
    .K(K),
    .V(V),
    .out_weight(out_weight),
    .out_valid(out_valid),
    .out(out)
    );
 
endmodule
