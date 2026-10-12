#=============================================================================
#                       UVM Design Flow MakeFile
#=============================================================================
# Run everything from 05_UVM: file.f lists the TB only, the DUT is added per
# target (RTL from 01_RTL, gate netlist from 02_SYN/Netlist).
# The UVM library comes with VCS (-ntb_opts uvm-1.2), nothing to download.
#
# Single run (compile + run with -R):
#   make vcs_rtl                              # RTL, debug, base_test, seed 7
#   make vcs_rtl test=k_max_test seed=3       # pick the test class, +UVM_TESTNAME
#   make vcs_rtl verb=UVM_HIGH                # +UVM_VERBOSITY: UVM_LOW / MEDIUM / HIGH / DEBUG
#   make vcs_rtl plusarg="+PAT_NUM=100"       # extra runtime plusargs
#   make vcs_rtl define="FSDB"                # extra +define+ macros, space separated
#   make vcs_rtl_cv / vcs_gate / vcs_gate_cv / vcs_gate_fast
#
# Regression (compile once, every test / seed is runtime only):
#   make regr_comp define="A" cov=1
#   make regr_sim test=k_max_test seed=N cov=1
#
#   make cov_view / cov_merge / clean
#=============================================================================
.PHONY: vcs_rtl vcs_rtl_cv vcs_rtl_fast vcs_gate vcs_gate_cv vcs_gate_fast regr_comp regr_sim cov_view cov_merge clean
.DEFAULT_GOAL := vcs_rtl

# bash for pipefail: a VCS failure is not hidden by tee
SHELL := /bin/bash

#=============================================================================
#                          Project settings
#=============================================================================
source_file = file.f
rtl_dut     = ../01_RTL/F_ATTN.v
gate_dut    = ../02_SYN/Netlist/F_ATTN_SYN.v
simv        = simv
regr_simv   = simv_regr
log_dir     = report
cm_dir      = coverage.vdb
merge_dir   = merged.vdb
test        = base_test
verb        = UVM_MEDIUM
seed        = 7
define      =
plusarg     =
cov         = 0
TIMESCALE   = -timescale=1ns/1ps
neg_file    = /usr/cad/CBDK_TSMC90GUTM_Arm_f1.0/CIC/Verilog/tsmc090.v

#=============================================================================
#							VCS (BASE SETTINGS)
#=============================================================================
EXTRA_DEFINE = ${addprefix +define+,${define}}

# log tag: test + define="A B" -> _base_test_A_B
empty :=
space := ${empty} ${empty}
tag    = _${test}${if ${define},_${subst ${space},_,${define}},}

# runtime options, the same for -R and ./simv_regr
SIM_OPTS = +ntb_random_seed=${seed} \
	+UVM_TESTNAME=${test} \
	+UVM_VERBOSITY=${verb} \
	${plusarg}

# coverage: compile-time instrumentation + runtime test name per seed
CM_TYPE = -cm line+branch+tgl+fsm+cond+assert
CM_COMP = ${CM_TYPE} -cm_dir ${cm_dir}
CM_SIM  = ${CM_TYPE} -cm_dir ${cm_dir} -cm_name seed_${seed}${tag}

VCS_COMP = vcs ${TIMESCALE} \
	-full64 \
	-sverilog \
	-ntb_opts uvm-1.2 \
	-f ${source_file} \
	${EXTRA_DEFINE}

VCS_BASE = ${VCS_COMP} \
	-R \
	-o ${simv} \
	${SIM_OPTS}

VCS_CM = ${CM_COMP} \
	-cm_name seed_${seed}${tag}

#=============================================================================
#							VCS (RTL SIMULATION)
#=============================================================================
VCS_RTL_FAST = ${VCS_BASE} \
	${rtl_dut} \
	+notimingchecks \
	+define+RTL

VCS_RTL = ${VCS_RTL_FAST} \
	-debug_access+all

VCS_RTL_CV = ${VCS_RTL} \
	${VCS_CM}

#=============================================================================
#							VCS (GATE SIMULATION)
#=============================================================================
VCS_GATE_FAST = ${VCS_BASE} \
	${gate_dut} \
	-v ${neg_file} \
	+neg_tchk \
	+no_tchk_msg \
	+no_notifier \
	+define+GATE

VCS_GATE = ${VCS_GATE_FAST} \
	-debug_access+all

VCS_GATE_CV = ${VCS_GATE} \
	${VCS_CM}

#=============================================================================
#								 PROCESSING
#=============================================================================

RUN = mkdir -p ${log_dir}; set -o pipefail;
LOG = 2>&1 | tee ${log_dir}/$@${tag}_seed_${seed}.log

vcs_rtl:
	${RUN} ${VCS_RTL} ${LOG}

vcs_rtl_cv:
	${RUN} ${VCS_RTL_CV} ${LOG}

vcs_rtl_fast:
	${RUN} ${VCS_RTL_FAST} ${LOG}

vcs_gate:
	${RUN} ${VCS_GATE} ${LOG}

vcs_gate_cv:
	${RUN} ${VCS_GATE_CV} ${LOG}

vcs_gate_fast:
	${RUN} ${VCS_GATE_FAST} ${LOG}

#=============================================================================
#                 Regression (compile once, run many tests / seeds)
#=============================================================================
# define is compile-time: recompile with regr_comp when define changes,
# test / seed / verb / plusarg are runtime only
REGR_CM_COMP = ${if ${filter 1,${cov}},${CM_COMP},}
REGR_CM_SIM  = ${if ${filter 1,${cov}},${CM_SIM},}
comp_tag     = ${if ${define},_${subst ${space},_,${define}},}

regr_comp:
	${RUN} ${VCS_COMP} ${rtl_dut} -o ${regr_simv} +notimingchecks +define+RTL ${REGR_CM_COMP} \
	2>&1 | tee ${log_dir}/regr_comp${comp_tag}.log

regr_sim:
	${RUN} ./${regr_simv} ${SIM_OPTS} ${REGR_CM_SIM} \
	2>&1 | tee ${log_dir}/regr_sim${tag}_seed_${seed}.log

#=============================================================================
#                                 Utility
#=============================================================================
cov_view:
	verdi -cov -covdir ${cm_dir} &

cov_merge:
	urg -dir ${cm_dir} -dbname ${merge_dir} -noreport

clean:
	rm -rf csrc ${simv} ${simv}.daidir ${regr_simv} ${regr_simv}.daidir ${cm_dir} ${merge_dir} \
	ucli.key vc_hdrs.h *.fsdb *.vpd DVEfiles novas* verdiLog ${log_dir} fail_input.txt
