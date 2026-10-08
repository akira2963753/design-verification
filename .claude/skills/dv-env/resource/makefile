#=============================================================================
#                       Design Flow MakeFile
#=============================================================================
# Single run (compile + run with -R):
#   make vcs_rtl                          # RTL, debug, seed 7
#   make vcs_rtl seed=3 define="A B=1"    # extra +define+ macros, space separated
#   make vcs_rtl_cv seed=3                # with coverage, one test per seed in ${cm_dir}
#   make vcs_gate / vcs_gate_cv / vcs_gate_fast
#
# Regression (compile once, run many seeds, used by regr.py):
#   make regr_comp define="A" cov=1       # compile ${regr_simv} once per define
#   make regr_sim seed=N define="A" cov=1 # run only, seed is a runtime option
#
#   make cov_view                         # open ${cm_dir} in Verdi, all tests merged in view
#   make cov_merge                        # merge all tests into ${merge_dir} (many seeds)
#   make clean
#=============================================================================
.PHONY: vcs_rtl vcs_rtl_cv vcs_rtl_fast vcs_gate vcs_gate_cv vcs_gate_fast regr_comp regr_sim cov_view cov_merge clean
.DEFAULT_GOAL := vcs_rtl

# bash for pipefail: a VCS failure is not hidden by tee
SHELL := /bin/bash

#=============================================================================
#                          Project settings
#=============================================================================
source_file = file.f
simv        = simv
regr_simv   = simv_regr
log_dir     = report
cm_dir      = coverage.vdb
merge_dir   = merged.vdb
seed        = 7
define      =
cov         = 0
TIMESCALE   = -timescale=1ns/1ns
neg_file    = /usr/cad/CBDK_TSMC90GUTM_Arm_f1.0/CIC/Verilog/tsmc090.v

# DPI-C: set DPI_SOURCE to the .cpp path to enable it
DPI_SOURCE =
DPI_CFLAGS = -std=c++17 -O2

#=============================================================================
#							VCS (BASE SETTINGS)
#=============================================================================
DPI_OPTS     = ${if ${DPI_SOURCE},-CFLAGS "${DPI_CFLAGS}" ${DPI_SOURCE},}
EXTRA_DEFINE = ${addprefix +define+,${define}}

# log tag: define="A B" -> _A_B
empty :=
space := ${empty} ${empty}
tag    = ${if ${define},_${subst ${space},_,${define}},}

# coverage: compile-time instrumentation + runtime test name per seed
CM_TYPE = -cm line+branch+tgl+fsm+cond+assert
CM_COMP = ${CM_TYPE} -cm_dir ${cm_dir}
CM_SIM  = ${CM_TYPE} -cm_dir ${cm_dir} -cm_name seed_${seed}${tag}

VCS_COMP = vcs ${TIMESCALE} \
	-full64 \
	-sverilog \
	-f ${source_file} \
	${DPI_OPTS} \
	${EXTRA_DEFINE}

VCS_BASE = ${VCS_COMP} \
	-R \
	-o ${simv} \
	+ntb_random_seed=${seed}

VCS_CM = ${CM_COMP} \
	-cm_name seed_${seed}${tag}

#=============================================================================
#							VCS (RTL SIMULATION)
#=============================================================================
VCS_RTL_FAST = ${VCS_BASE} \
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
#                 Regression (compile once, run many seeds)
#=============================================================================
# define is compile-time: recompile with regr_comp when define changes
REGR_CM_COMP = ${if ${filter 1,${cov}},${CM_COMP},}
REGR_CM_SIM  = ${if ${filter 1,${cov}},${CM_SIM},}

regr_comp:
	${RUN} ${VCS_COMP} -o ${regr_simv} +notimingchecks +define+RTL ${REGR_CM_COMP} \
	2>&1 | tee ${log_dir}/regr_comp${tag}.log

regr_sim:
	${RUN} ./${regr_simv} +ntb_random_seed=${seed} ${REGR_CM_SIM} \
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
	ucli.key vc_hdrs.h *.fsdb *.vpd DVEfiles novas* verdiLog ${log_dir}