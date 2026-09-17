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
seed = 12345

#======================================================
#                          VCS
#======================================================
VCS_RTL = vcs ${TIMESCALE} \
	-full64 \
	-debug_access+all \
	-R \
	+v2k \
	-f ${source_file} \
	+notimingchecks \
	+define+RTL \
	+ntb_random_seed=${seed}

VCS_GATE = vcs ${TIMESCALE} \
	-full64 \
	-debug_access+all \
	-R \
	+v2k \
	-f ${source_file} \
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