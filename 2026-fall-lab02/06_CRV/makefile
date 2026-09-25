#======================================================
#         Design Flow MakeFile (Author: Marco)
#======================================================
.PHONY: vcs_rtl vcs_gate vcs_fast
#======================================================
#              Set your desired file names
#======================================================
top_design=LDPC.v
source_file="file.f"
TIMESCALE="-timescale=1ns/1ps"
seed = 11111
UMC018_SIM = ~iclabTA01/umc018/Verilog/umc18_neg.v
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
	+ntb_random_seed=${seed} \
	-cm line+branch+tgl+fsm+cond+assert 2>&1 | tee seed_${seed}.log

VCS_GATE = vcs ${TIMESCALE} \
	-full64 \
	-debug_access+all \
	-R \
	+v2k \
	-f ${source_file} \
	-v ${UMC018_SIM} \
	+neg_tchk \
	+define+GATE \
	+ntb_random_seed=${seed} \
	+no_tchk_msg \
	+no_notifier \
	-cm line+branch+tgl+fsm+cond+assert 2>&1 | tee seed_${seed}.log

VCS_FAST = vcs ${TIMESCALE} \
	-full64 \
	-R \
	+v2k \
	-f ${source_file} \
	+notimingchecks \
	+define+RTL \
	+ntb_random_seed=${seed} 2>&1 | tee seed_${seed}.log

vcs_rtl:
	${VCS_RTL}
vcs_gate:
	${VCS_GATE}
vcs_fast:
	${VCS_FAST}
