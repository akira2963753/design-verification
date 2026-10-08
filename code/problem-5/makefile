#======================================================
#        SV Practice Judge, Problem 5 (Bug Hunt)
#======================================================
.PHONY: all run judge clean

SHELL := /bin/bash

#======================================================
#                    Configuration
#======================================================
# bug: 0 = correct DUT, make bug=3 injects BUG_3
# opt: extra VCS options, e.g. opt="-debug_access+all +define+FSDB"
bug 		= 0
seed 		= 1
time_limit 	= 20
num_bug 	= 13
opt 		=

#======================================================
#                        Judge
#======================================================

all: run

# One run, TB output on screen
run:
	@VCS_OPT="${opt}" bash judge.sh run ${bug} ${seed} ${time_limit}

# Correct DUT + every bug, summary table only
judge:
	@VCS_OPT="${opt}" bash judge.sh all ${num_bug} ${seed} ${time_limit}

clean:
	rm -rf csrc simv simv.daidir ucli.key vc_hdrs.h log *.fsdb novas* verdiLog
