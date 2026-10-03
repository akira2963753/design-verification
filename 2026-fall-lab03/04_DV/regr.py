#!/usr/bin/env python3
# ******************************************************************************
# Copyright (C) 2026 Marco
#
# File Name:    regr.py
# Project:      2026 FALL NYCU IC LAB, LAB03
# Module:       seed / fault regression
# Author:       Marco <harry2963753@gmail.com>
#
# ******************************************************************************
#
# Seed mode : run `make vcs_fast seed=<N>` for consecutive seeds, one after another (all
#             runs share the same simv / csrc, so they cannot run in parallel).
#             -n N --start S runs seeds S ~ S+N-1, so a whole batch replays from (N, S).
# Fault mode: run the TA encrypted design once per injected fault (define=SPEC_x_y).
#             Every fault must be caught (FAIL), then define=CORRECT must pass.
#
# Usage (in 04_DV):
#   python3 regr.py                     # seeds 1 ~ 10
#   python3 regr.py -n 50               # seeds 1 ~ 50
#   python3 regr.py -n 50 --start 51    # seeds 51 ~ 100, a new batch
#   python3 regr.py -s 3 7 2026         # given seeds
#   python3 regr.py --fault             # all TA faults + CORRECT, seed 7
#   python3 regr.py --fault -s 3        # same with seed 3
#   python3 regr.py pat=100 -n 5        # extra make variables (before -s / -n)
#
# A run passes only if make exits 0 AND the log has "All Pass".
# Exit code: 0 all as expected, 1 otherwise.

import argparse
import os
import re
import subprocess
import sys
import time

TARGET = "vcs_fast"
LOG_DIR = "report"
PASS_KEY = "All Pass"
# Fail reason: first line of the highest-priority pattern found in the log
# (TB messages first, then the VCS generic Fatal / Error lines)
FAIL_KEYS = [
    re.compile(r"\[SVA FAILED\]|\[(SCB|DRV|GEN|ENV|TEST)\]"),
    re.compile(r"FAIL|Timeout"),
    re.compile(r"Error-\[|Fatal"),
]
# Same fault list as 01_RTL/07_check_pattern: (SPEC, number of faults)
FAULTS = ["SPEC_{}_{}".format(s, i) for s, n in ((4, 4), (5, 5), (6, 2), (7, 1), (8, 10), (9, 2)) for i in range(1, n + 1)]


def parse_args():
    p = argparse.ArgumentParser(description="VCS seed / fault regression on top of the makefile")
    g = p.add_mutually_exclusive_group()
    g.add_argument("-s", "--seeds", type=int, nargs="+", help="seeds to run")
    g.add_argument("-n", "--num", type=int, default=10, help="number of consecutive seeds (default 10)")
    p.add_argument("--start", type=int, default=1, help="first seed of -n (default 1)")
    p.add_argument("--fault", action="store_true", help="run every TA fault, then CORRECT")
    p.add_argument("make_vars", nargs="*", help="extra make variables, e.g. pat=100")
    args = p.parse_args()
    if args.start < 1:
        p.error("--start must be >= 1")
    return args


def fail_reason(log_path):
    try:
        with open(log_path, errors="replace") as f:
            lines = f.readlines()
    except OSError:
        return "log file not found"
    for key in FAIL_KEYS:
        for line in lines:
            if key.search(line):
                return line.strip()
    return "no \"All Pass\" in log"


def run_one(seed, define, make_vars):
    log_path = "{}/{}_{}_seed_{}.log".format(LOG_DIR, TARGET, define, seed)
    cmd = ["make", TARGET, "seed={}".format(seed), "define={}".format(define)] + make_vars

    # Remove the old log, so a make that never reaches the recipe
    # reports "log file not found" instead of a stale reason
    if os.path.exists(log_path):
        os.remove(log_path)

    t0 = time.time()
    rc = subprocess.call(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    sec = time.time() - t0

    passed = False
    try:
        with open(log_path, errors="replace") as f:
            passed = (rc == 0) and (PASS_KEY in f.read())
    except OSError:
        pass
    reason = "" if passed else fail_reason(log_path)
    return passed, sec, log_path, reason


def seed_mode(args):
    if args.seeds:
        seeds = args.seeds
        batch = "-s " + " ".join(str(s) for s in seeds)
    else:
        seeds = list(range(args.start, args.start + args.num))
        batch = "-n {} --start {}".format(args.num, args.start)
    print("=" * 61)
    print("  Seed regression: make {} x {} seeds".format(TARGET, len(seeds)))
    if not args.seeds and seeds:
        print("  seeds     : {} ~ {}".format(seeds[0], seeds[-1]))
    if args.make_vars:
        print("  make vars : {}".format(" ".join(args.make_vars)))
    print("=" * 61)

    fails = []
    t_all = time.time()
    for i, seed in enumerate(seeds, 1):
        passed, sec, log_path, reason = run_one(seed, "CORRECT", args.make_vars)
        print("[{:>3}/{}] seed {:>10} : {}  ({:.1f} s)".format(i, len(seeds), seed, "PASS" if passed else "FAIL", sec))
        if not passed:
            fails.append((seed, log_path, reason))
            print("                      {}".format(reason))
        sys.stdout.flush()

    print("=" * 61)
    print("  Summary: {} / {} pass, total {:.1f} s".format(len(seeds) - len(fails), len(seeds), time.time() - t_all))
    if fails:
        print("  Failed seeds:")
        for seed, log_path, reason in fails:
            print("    seed {:>10} -> {}".format(seed, log_path))
            print("                    {}".format(reason))
        print("  Rerun one seed with: make {} seed=<seed>".format(TARGET))
    else:
        print("  All seeds pass")
    # make vars go first, -s takes every value after it
    print("  Replay this batch : {}".format(" ".join(["python3 regr.py"] + args.make_vars + [batch])))
    if not args.seeds:
        print("  Next new batch    : --start {}".format(args.start + args.num))
    print("=" * 61)
    return 1 if fails else 0


def fault_mode(args):
    seed = args.seeds[0] if args.seeds else 7
    runs = [(d, False) for d in FAULTS] + [("CORRECT", True)]
    print("=" * 61)
    print("  Fault regression: {} faults + CORRECT, seed {}".format(len(FAULTS), seed))
    if args.make_vars:
        print("  make vars : {}".format(" ".join(args.make_vars)))
    print("=" * 61)

    bad = []
    t_all = time.time()
    for i, (define, expect_pass) in enumerate(runs, 1):
        passed, sec, log_path, reason = run_one(seed, define, args.make_vars)
        if expect_pass:
            ok = passed
            state = "PASS" if passed else "FAIL"
        else:
            ok = not passed
            state = "CAUGHT" if not passed else "MISSED"
        print("[{:>2}/{}] {:<9} : {:<6} ({:.1f} s)".format(i, len(runs), define, state, sec))
        if reason:
            print("                {}".format(reason))
        if not ok:
            bad.append((define, state, log_path))
        sys.stdout.flush()

    print("=" * 61)
    print("  Summary: {} / {} as expected, total {:.1f} s".format(len(runs) - len(bad), len(runs), time.time() - t_all))
    for define, state, log_path in bad:
        print("    {:<9} {} -> {}".format(define, state, log_path))
    if not bad:
        print("  Every fault caught, CORRECT design passes")
    print("=" * 61)
    return 1 if bad else 0


def main():
    args = parse_args()
    return fault_mode(args) if args.fault else seed_mode(args)


if __name__ == "__main__":
    sys.exit(main())
