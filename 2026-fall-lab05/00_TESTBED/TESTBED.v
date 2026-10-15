//############################################################################
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//   (C) Copyright Laboratory System Integration and Silicon Implementation
//   All Right Reserved
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//   ICLAB 2026 Fall
//   Lab05 Exercise		: JPEG-Like image compression ENCorder (JPEGLENC)
//   Author     		: Yu-Yang Tang
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



	  		  	
module TESTBED;

wire                clk;
wire                rst_n;
wire                in_valid;
wire        [7:0]   in_data;
wire                out_valid;
wire        [7:0]   out_data;

initial begin
	`ifdef RTL
		$fsdbDumpfile("JPEGLENC.fsdb");
		$fsdbDumpvars(0,"+mda");
		$fsdbDumpvars();
	`endif
	`ifdef GATE
		$sdf_annotate("../02_SYN/Netlist/JPEGLENC_SYN.sdf", u_JPEGLENC);
		//$fsdbDumpfile("JPEGLENC_SYN.fsdb");
		//$fsdbDumpvars();    
	`endif
	`ifdef POST
		$sdf_annotate("CHIP.sdf", u_CHIP);
		//$fsdbDumpfile("CHIP.fsdb");
		//$fsdbDumpvars();    
	`endif
end

`ifdef RTL
	JPEGLENC u_JPEGLENC(
		// input signals
    	.clk(clk),
    	.rst_n(rst_n),
    	.in_valid(in_valid),
    	.in_data(in_data),
        // output signals
    	.out_valid(out_valid),
		.out_data(out_data)
	);
`elsif GATE
	JPEGLENC u_JPEGLENC(
		// input signals
    	.clk(clk),
    	.rst_n(rst_n),
    	.in_valid(in_valid),
    	.in_data(in_data),
        // output signals
    	.out_valid(out_valid),
		.out_data(out_data)
	);
`elsif POST
	CHIP u_CHIP(
		// input signals
    	.clk(clk),
    	.rst_n(rst_n),
    	.in_valid(in_valid),
    	.in_data(in_data),
        // output signals
    	.out_valid(out_valid),
		.out_data(out_data)	);
`endif

PATTERN u_PATTERN(
        // input signals
    	.clk(clk),
    	.rst_n(rst_n),
    	.in_valid(in_valid),
    	.in_data(in_data),
        // output signals
    	.out_valid(out_valid),
		.out_data(out_data)
);
 
endmodule
