#======================================================
#         Design Flow MakeFile (Author: Marco)
#======================================================
.PHONY: vcs_rtl vcs_gate syn clean_vcs clean_syn

#======================================================
#              Set your desired file names
#======================================================
top_design=OISS.v
source_file="file.f"
TIMESCALE="-timescale=1ns/1ps"
syn_tcl="syn90.tcl"
syn_log="syn.log"
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
	+define+RTL \
	+ntb_random_seed=${seed} | tee rtl_sim.log

VCS_GATE = vcs ${TIMESCALE} \
	-full64 \
	-debug_access+all \
	-R \
	+v2k \
	-f ${source_file} \
	-CFLAGS "${DPI_CFLAGS}" \
	${DPI_SOURCE} \
	+neg_tchk \
	+define+GATE \
	+ntb_random_seed=${seed}

#======================================================
#                   Design Compiler
#======================================================
DC_shell = dc_shell -f ${syn_tcl} | tee ${syn_log}

vcs_rtl:
	${VCS_RTL}

vcs_gate:
	${VCS_GATE}

syn:
	${DC_shell}

#======================================================
#                          Clean
#======================================================
clean_vcs:
	rm -rf *.fsdb ./csrc *.log simv* *.sdf.X *.key

clean_syn:
	rm -rf ./Netlist/*.* ./Report/*.* *.log alib* *.svf dwsvf* *.ddc *.pvl *.syn *.mr
