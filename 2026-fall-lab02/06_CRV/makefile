#======================================================
#         Design Flow MakeFile (Author: Marco)
#======================================================
.PHONY: vcs_rtl vcs_gate vcs_fast
#======================================================
#              Set your desired file names
#======================================================
top_design=OISS.v
source_file="file.f"
TIMESCALE="-timescale=1ns/1ns"
seed = 11111
DPI_SOURCE = ../00_TESTBED/component/oiss.cpp
DPI_CFLAGS = -std=c++17 -O2
#======================================================
#                          VCS
#======================================================
VCS_RTL = vcs ${TIMESCALE} \
	-full64 \
	-debug_access+all \
	-R \
	+v2k \
	-f ${source_file} \
	-CFLAGS "${DPI_CFLAGS}" \
	${DPI_SOURCE} \
	+notimingchecks \
	+define+RTL+PRINT \
	+ntb_random_seed=${seed} 2>&1 \
	-cm line+branch+tgl+fsm+cond+assert | tee seed_${seed}.log

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
	-cm line+branch+tgl+fsm+cond+assert | tee seed_${seed}.log

VCS_FAST = vcs ${TIMESCALE} \
	-full64 \
	-R \
	+v2k \
	-f ${source_file} \
	-CFLAGS "${DPI_CFLAGS}" \
	${DPI_SOURCE} \
	+notimingchecks \
	+define+RTL \
	+ntb_random_seed=${seed} 2>&1 | tee seed_${seed}.log

vcs_rtl:
	${VCS_RTL}
vcs_gate:
	${VCS_GATE}
vcs_fast:
	${VCS_FAST}