#!/bin/bash
#======================================================
#        SV Practice Judge, Problem 5 (Bug Hunt)
#======================================================
# Usage: bash judge.sh run <bug> <seed> <time_limit>
#            one run with TB output on screen, bug 0 = correct DUT
#        bash judge.sh all <num_bug> <seed> <time_limit>
#            correct DUT + BUG_1 ~ BUG_<num_bug>, summary table only
# Extra VCS options come from the VCS_OPT environment variable.

DUT=dut/AXI4_MEM.sv
TB=src/file.f
LOG_DIR=log

#======================================================
#                      Function
#======================================================

# $1 = bug number, 0 builds the correct DUT
compile() {
    vcs -full64 -sverilog -q -timescale=1ns/1ps -o simv -l ${LOG_DIR}/compile.log \
        ${DUT} -f ${TB} +define+BUG_$1 ${VCS_OPT} > /dev/null 2>&1 && return 0
    awk '/^Error-/{p = 1} p{print} /^$/{p = 0}' ${LOG_DIR}/compile.log
    echo "Result : Compile Error"
    exit 1
}

# Sets VERDICT (PASS / FAIL) and REASON from sim log $1 and simv exit code $2
classify() {
    local line
    if [ "$2" -eq 124 ]; then
        VERDICT=FAIL
        REASON="time limit exceeded, no \$finish"
        return
    fi
    line=$(grep -m1 -E '^[[:space:]]*FAIL' "$1")
    if [ -n "${line}" ]; then
        VERDICT=FAIL
        REASON=$(echo "${line}" | sed 's/^[[:space:]]*//')
        return
    fi
    if grep -q 'ALL PASS' "$1"; then
        VERDICT=PASS
        REASON="ALL PASS"
        return
    fi
    line=$(grep -m1 -E 'Fatal|Error' "$1")
    VERDICT=FAIL
    REASON="no ALL PASS printed${line:+, ${line}}"
}

# $1 = bug, $2 = seed, $3 = time limit, $4 = 1 hides the TB output
sim() {
    local name log
    name=$([ "$1" -eq 0 ] && echo correct || echo bug_$1)
    log=${LOG_DIR}/${name}.log
    compile $1
    if [ "$4" -eq 1 ]; then
        timeout --foreground $3 ./simv -q +ntb_random_seed=$2 > ${log} 2>&1
        RC=$?
    else
        timeout --foreground $3 ./simv -q +ntb_random_seed=$2 2>&1 | tee ${log}
        RC=${PIPESTATUS[0]}
    fi
    classify ${log} ${RC}
}

#======================================================
#                        Main
#======================================================

mode=$1
mkdir -p ${LOG_DIR}

if [ "${mode}" = run ]; then
    bug=$2
    sim ${bug} $3 $4 0
    echo "============================================================="
    echo "    DUT     : $([ ${bug} -eq 0 ] && echo correct || echo BUG_${bug}), seed ${3}"
    echo "    Verdict : ${VERDICT} (${REASON})"
    echo "============================================================="
    exit 0
fi

if [ "${mode}" != all ]; then
    echo "Usage: bash judge.sh run <bug> <seed> <time_limit> | all <num_bug> <seed> <time_limit>"
    exit 1
fi

num_bug=$2
caught=0
missed=""
echo "============================================================="
echo "      Problem 5: AXI4 Bug Hunt (seed $3, ${num_bug} bugs)"
echo "============================================================="

sim 0 $3 $4 1
correct=${VERDICT}
printf "%-8s %-7s %s\n" "correct" "${VERDICT}" "${REASON:0:70}"

for((b = 1; b <= num_bug; b++)); do
    sim ${b} $3 $4 1
    if [ "${VERDICT}" = FAIL ]; then
        caught=$((caught + 1))
        printf "%-8s %-7s %s\n" "BUG_${b}" "caught" "${REASON:0:70}"
    else
        missed="${missed} ${b}"
        printf "%-8s %-7s %s\n" "BUG_${b}" "missed" "${REASON:0:70}"
    fi
done

echo "============================================================="
if [ "${correct}" != PASS ]; then
    echo "    Result : False Alarm (TB fails on the correct DUT, ${caught}/${num_bug} bugs caught)"
    echo "    Replay : make"
elif [ ${caught} -eq ${num_bug} ]; then
    echo "    Result : Accepted (correct DUT PASS, ${caught}/${num_bug} bugs caught)"
else
    echo "    Result : Wrong Answer (correct DUT PASS, ${caught}/${num_bug} bugs caught)"
    echo "    Replay : make bug=$(echo ${missed} | cut -d' ' -f1)"
fi
echo "============================================================="
echo "Logs     : ${LOG_DIR}/correct.log, ${LOG_DIR}/bug_<n>.log"
