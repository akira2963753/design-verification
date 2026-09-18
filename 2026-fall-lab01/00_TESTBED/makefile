#======================================================

#         Design Flow MakeFile (Author: Marco)

#======================================================

.PHONY: vcs_rtl vcs_gate



#======================================================

#              Set your desired file names

#======================================================

top_design=OISS.v

source_file="file.f"

TIMESCALE="-timescale=1ns/1ps"

seed = 11111

DPI_SOURCE = ../00_TESTBED/component/oiss.cpp

DPI_CFLAGS = -std=c++17



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

	+ntb_random_seed=${seed} \

	-cm line+branch+tgl+fsm+cond+assert | tee rtl_sim.log



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