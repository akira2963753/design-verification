#!/usr/bin/env python3
# ******************************************************************************
# Copyright (C) 2026 Marco
#
# File Name:    regr.py
# Project:      2026 FALL NYCU IC LAB, LAB02
# Module:       seed regression
# Author:       Marco <harry2963753@gmail.com>
#
# ******************************************************************************
#
# Run `make vcs_fast seed=<N>` for many seeds, one after another (all seeds share
# the same simv / csrc, so they cannot run in parallel in one directory).
#
# Usage (in 00_TESTBED):
#   python3 regr.py                  # 10 random seeds
#   python3 regr.py -n 50            # 50 random seeds
#   python3 regr.py -s 1 7 2026      # given seeds
#   python3 regr.py rtl_dut=../01_RTL/LDPC_v16.v -n 5   # extra make variables (before -s / -n)
#
# A seed passes only if make exits 0 AND the log has "All Pass".
# Exit code: 0 all pass, 1 any fail.

import argparse
import random
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
    re.compile(r"\[SVA FAILED\]|\[ERROR\]"),
    re.compile(r"FAIL|Timeout"),
    re.compile(r"Error-\[|Fatal"),
]


def parse_args():
    p = argparse.ArgumentParser(description="VCS seed regression on top of the makefile")
    g = p.add_mutually_exclusive_group()
    g.add_argument("-s", "--seeds", type=int, nargs="+", help="seeds to run")
    g.add_argument("-n", "--num", type=int, default=10, help="number of random seeds (default 10)")
    p.add_argument("make_vars", nargs="*", help="extra make variables, e.g. rtl_dut=...")
    return p.parse_args()


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


def run_seed(seed, make_vars):
    log_path = "{}/{}_seed_{}.log".format(LOG_DIR, TARGET, seed)
    cmd = ["make", TARGET, "seed={}".format(seed)] + make_vars
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


def main():
    args = parse_args()
    seeds = args.seeds if args.seeds else random.sample(range(1, 2 ** 31), args.num)

    print("=" * 61)
    print("  Regression: make {} x {} seeds".format(TARGET, len(seeds)))
    if args.make_vars:
        print("  make vars : {}".format(" ".join(args.make_vars)))
    print("=" * 61)

    results = []
    t_all = time.time()
    for i, seed in enumerate(seeds, 1):
        passed, sec, log_path, reason = run_seed(seed, args.make_vars)
        results.append((seed, passed, log_path, reason))
        print("[{:>3}/{}] seed {:>10} : {}  ({:.1f} s)".format(i, len(seeds), seed, "PASS" if passed else "FAIL", sec))
        if not passed:
            print("                      {}".format(reason))
        sys.stdout.flush()

    fails = [r for r in results if not r[1]]
    print("=" * 61)
    print("  Summary: {} / {} pass, total {:.1f} s".format(len(seeds) - len(fails), len(seeds), time.time() - t_all))
    if fails:
        print("  Failed seeds:")
        for seed, _, log_path, reason in fails:
            print("    seed {:>10} -> {}".format(seed, log_path))
            print("                    {}".format(reason))
        print("  Rerun one seed with: make {} seed=<seed>".format(TARGET))
    else:
        print("  All seeds pass")
    print("=" * 61)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
