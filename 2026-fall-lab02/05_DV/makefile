#======================================================
#         		Design Verification Flow
#======================================================
.PHONY: vcs_fast vcs_cov vcs_debug vcs_gate clean

# bash for pipefail: a VCS failure is not hidden by tee
SHELL := /bin/bash

#======================================================
#              Set your desired file names
#======================================================
top_design	= LDPC
tb_file 	= file.f
rtl_dut 	= ../01_RTL/${top_design}.v
gate_dut 	= ../02_SYN/Netlist/${top_design}_SYN.v
TIMESCALE 	= -timescale=1ns/1ps
neg_path 	= "/usr/cad/CBDK_TSMC90GUTM_Arm_f1.0/CIC/Verilog/tsmc090.v"
log_dir 	= report
seed 		= 7

#======================================================
#                          VCS
#======================================================

# Shared by every target: TB files from file.f, DUT added per target
VCS_BASE = vcs ${TIMESCALE} \
	-full64 \
	-sverilog \
	-R \
	+v2k \
	-f ${tb_file} \
	+ntb_random_seed=${seed}

# Daily regression: plain RTL, fastest
VCS_FAST = ${VCS_BASE} \
	${rtl_dut} \
	+notimingchecks \
	+define+RTL

# Coverage: RTL + code coverage, result in simv.vdb
VCS_COV = ${VCS_FAST} \
	-cm line+branch+tgl+fsm+cond+assert

# Waveform: RTL + FSDB dump in top.sv (needs the Verdi PLI)
VCS_DEBUG = ${VCS_FAST} \
	-debug_access+all \
	+define+FSDB

VCS_GATE = ${VCS_BASE} \
	${gate_dut} \
	-v ${neg_path} \
	+neg_tchk \
	+define+GATE \
	+no_tchk_msg \
	+no_notifier

# stdout + stderr to the terminal and report/<target>_seed_<seed>.log
RUN = mkdir -p ${log_dir}; set -o pipefail;
LOG = 2>&1 | tee ${log_dir}/$@_seed_${seed}.log

vcs_fast:
	${RUN} ${VCS_FAST} ${LOG}
vcs_cov:
	${RUN} ${VCS_COV} ${LOG}
vcs_debug:
	${RUN} ${VCS_DEBUG} ${LOG}
vcs_gate:
	${RUN} ${VCS_GATE} ${LOG}