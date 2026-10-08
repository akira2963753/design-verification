#======================================================
#           SV Practice Judge, Problem 1
#======================================================
.PHONY: all compile run clean

# bash for $$? and the time limit check
SHELL := /bin/bash

#======================================================
#                    Configuration
#======================================================
# case: 0 runs every case, make case=5 runs only case 5
case 		= 0
time_limit 	= 5
src 		= src/sol.sv src/test.sv

#======================================================
#                         VCS
#======================================================

VCS = vcs -full64 \
	-sverilog \
	-q \
	-timescale=1ns/1ps \
	-o simv \
	-l compile.log \
	${src}

all: run

# On failure, print every Error block of compile.log (up to its blank line)
compile:
	@${VCS} > /dev/null 2>&1 || { awk '/^Error-/{p = 1} p{print} /^$$/{p = 0}' compile.log; echo "Result : Compile Error"; exit 1; }

# Only simv is timed, compile time does not count toward the limit
run: compile
	@t0=$$(date +%s%N); \
	timeout --foreground ${time_limit} ./simv -q +CASE=${case}; \
	rc=$$?; \
	t1=$$(date +%s%N); \
	if [ $$rc -eq 124 ]; then echo ""; echo "Result : Time Limit Exceeded (${time_limit} s)"; fi; \
	echo "Runtime: $$(( (t1 - t0) / 1000000 )) ms"

clean:
	rm -rf csrc simv simv.daidir ucli.key vc_hdrs.h compile.log
