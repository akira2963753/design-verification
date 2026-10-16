#!/usr/bin/env python3
# ******************************************************************************
# Copyright (C) 2026 Marco
#
# File Name:    regr.py
# Project:      2026 FALL NYCU IC LAB, LAB05
# Module:       seed regression
# Author:       Marco <harry2963753@gmail.com>
#
# ******************************************************************************
#
# Run `make vcs_rtl_fast seed=<N>` for consecutive seeds, one after another (all runs
# share the same simv / csrc, so they cannot run in parallel).
# -n N --start S runs seeds S ~ S+N-1, so a whole batch replays from (N, S).
# The scoreboard latency and output bytes of every passing seed are collected, the same
# seeds drive the same stimulus, so RTL versions can be compared directly.
#
# Usage (in 04_DV):
#   python3 regr.py                     # seeds 1 ~ 10
#   python3 regr.py -n 50               # seeds 1 ~ 50
#   python3 regr.py -n 50 --start 51    # seeds 51 ~ 100, a new batch
#   python3 regr.py -s 3 7 2026         # given seeds
#   python3 regr.py -d "A B=1" -n 5     # extra +define+ macros
#
# A run passes only if make exits 0 AND the log has "All Pass".
# Exit code: 0 all pass, 1 otherwise.

import argparse
import os
import re
import subprocess
import sys
import time

TARGET = "vcs_rtl_fast"
LOG_DIR = "report"
PASS_KEY = "All Pass"
# Fail reason: first line of the highest-priority pattern found in the log
# (TB messages first, then the VCS generic Fatal / Error lines)
FAIL_KEYS = [
    re.compile(r"\[SVA FAILED\]|\[(SPEC|IO)-\d+ FAILED\]|\[(SCB|DRV|GEN|ENV|TEST)\]"),
    re.compile(r"FAIL|Timeout"),
    re.compile(r"Error-\[|Fatal"),
]
# Scoreboard summary lines, printed only when the whole run passes
LAT_KEY = re.compile(r"Latency: total = (\d+), max = (\d+)")
PAT_KEY = re.compile(r"Pass patterns = (\d+)")
BYTE_KEY = re.compile(r"Output bytes: total = (\d+), max = (\d+)")


def parse_args():
    p = argparse.ArgumentParser(description="VCS seed regression on top of the makefile")
    g = p.add_mutually_exclusive_group()
    g.add_argument("-s", "--seeds", type=int, nargs="+", help="seeds to run")
    g.add_argument("-n", "--num", type=int, default=10, help="number of consecutive seeds (default 10)")
    p.add_argument("--start", type=int, default=1, help="first seed of -n (default 1)")
    p.add_argument("-d", "--define", default="", help="extra +define+ macros, space separated")
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


def summary(log_path):
    """(total lat, max lat, patterns, total bytes, max bytes) of the scoreboard summary, None if not found."""
    try:
        with open(log_path, errors="replace") as f:
            text = f.read()
    except OSError:
        return None
    lat = LAT_KEY.search(text)
    pat = PAT_KEY.search(text)
    byt = BYTE_KEY.search(text)
    if not lat or not pat or not byt:
        return None
    return int(lat.group(1)), int(lat.group(2)), int(pat.group(1)), int(byt.group(1)), int(byt.group(2))


def run_one(seed, define):
    # Same log name as the makefile: define="A B" -> _A_B
    tag = "_" + "_".join(define.split()) if define.strip() else ""
    log_path = "{}/{}{}_seed_{}.log".format(LOG_DIR, TARGET, tag, seed)
    cmd = ["make", TARGET, "seed={}".format(seed), "define={}".format(define)]

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


def main():
    args = parse_args()
    if args.seeds:
        seeds = args.seeds
        batch = "-s " + " ".join(str(s) for s in seeds)
    else:
        seeds = list(range(args.start, args.start + args.num))
        batch = "-n {} --start {}".format(args.num, args.start)
    if args.define:
        batch = "-d \"{}\" {}".format(args.define, batch)
    print("=" * 61)
    print("  Seed regression: make {} x {} seeds".format(TARGET, len(seeds)))
    if not args.seeds and seeds:
        print("  seeds     : {} ~ {}".format(seeds[0], seeds[-1]))
    if args.define:
        print("  define    : {}".format(args.define))
    print("=" * 61)

    fails = []
    lat_total, lat_max, lat_seed, pat_total = 0, 0, None, 0
    byte_total, byte_max, byte_seed = 0, 0, None
    t_all = time.time()
    for i, seed in enumerate(seeds, 1):
        passed, sec, log_path, reason = run_one(seed, args.define)
        line = "[{:>3}/{}] seed {:>10} : {}  ({:.1f} s)".format(i, len(seeds), seed, "PASS" if passed else "FAIL", sec)
        sm = summary(log_path) if passed else None
        if sm:
            line += "  latency total {}, max {}, bytes total {}, max {}".format(sm[0], sm[1], sm[3], sm[4])
            lat_total += sm[0]
            pat_total += sm[2]
            if lat_seed is None or sm[1] > lat_max:
                lat_max, lat_seed = sm[1], seed
            byte_total += sm[3]
            if byte_seed is None or sm[4] > byte_max:
                byte_max, byte_seed = sm[4], seed
        print(line)
        if not passed:
            fails.append((seed, log_path, reason))
            print("                      {}".format(reason))
        sys.stdout.flush()

    print("=" * 61)
    print("  Summary: {} / {} pass, total {:.1f} s".format(len(seeds) - len(fails), len(seeds), time.time() - t_all))
    # Passing seeds only, a failed run stops before the scoreboard summary
    if pat_total:
        print("  Latency : total {} cycles, max {} (seed {}), avg {:.2f} cycles / pattern".format(
            lat_total, lat_max, lat_seed, lat_total / pat_total))
        print("  Bytes   : total {}, max {} (seed {}), avg {:.2f} bytes / pattern".format(
            byte_total, byte_max, byte_seed, byte_total / pat_total))
    if fails:
        print("  Failed seeds:")
        for seed, log_path, reason in fails:
            print("    seed {:>10} -> {}".format(seed, log_path))
            print("                    {}".format(reason))
        print("  Rerun one seed with: make vcs_rtl seed=<seed> define=FSDB")
    else:
        print("  All seeds pass")
    print("  Replay this batch : python3 regr.py {}".format(batch))
    if not args.seeds:
        print("  Next new batch    : --start {}".format(args.start + args.num))
    print("=" * 61)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
