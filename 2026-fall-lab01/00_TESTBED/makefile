#======================================================
#         Design Flow MakeFile (Author: Marco)
#======================================================
.PHONY: vcs_rtl vcs_gate VCS_REGRESSION
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c
#======================================================
#              Set your desired file names
#======================================================
top_design=OISS.v
source_file="file.f"
TIMESCALE="-timescale=1ns/1ps"
seed = 11111
DPI_SOURCE = ../00_TESTBED/component/oiss.cpp
DPI_CFLAGS = -std=c++17 -O2
REGRESSION_SEEDS ?= 100
REGRESSION_PATTERNS ?= 50000
PATTERN_NUM ?= 2000
#======================================================
#                          VCS
#======================================================
VCS_RTL = vcs ${TIMESCALE} \
	-full64 \
	-R \
	+v2k \
	-f ${source_file} \
	-CFLAGS "${DPI_CFLAGS}" \
	${DPI_SOURCE} \
	+notimingchecks \
	+define+RTL \
	-pvalue+TESTBED.My_PATTERN.PATTERN_NUM=${PATTERN_NUM} \
	+ntb_random_seed=${seed} 2>&1 | tee rtl_seed_${seed}.log

VCS_GATE = vcs ${TIMESCALE} \
	-full64 \
	-debug_access+all \
	-R \
	+v2k \
	-f ${source_file} \
	-CFLAGS "${DPI_CFLAGS}" \
	${DPI_SOURCE} \
	+neg_tchk \
	+define+GATE+PRINT \
	+ntb_random_seed=${seed} \
	+no_tchk_msg \
	+no_notifier \
	-cm line+branch+tgl+fsm+cond+assert | tee rtl_sim.log

vcs_rtl:
	${VCS_RTL}
vcs_gate:
	${VCS_GATE}

# Run every seed even if an earlier simulation fails.
vcs_regression:
	@for ((s=${seed}; s<${seed}+${REGRESSION_SEEDS}; s++)); do \
		$(MAKE) --no-print-directory -f ../00_TESTBED/makefile vcs_rtl \
			seed=$$s PATTERN_NUM=${REGRESSION_PATTERNS} || true; \
	done
