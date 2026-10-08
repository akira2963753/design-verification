#!/usr/bin/env python3
"""Problem 1 (Merge Intervals) golden model and testcase generator.

Contains the answer: do not open before solving problem-1.

Writes ../../problem-1/testcase/input.txt and output.txt.
File format, every number of a range in 8-digit hex:
    <case_num>
    <n> <tag>
    <lo> <hi>      (n lines)
    ...
"""

import os
import random

MAX = 0xFFFFFFFF
SEED = 2026

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "..", "problem-1", "testcase")


def merge(ranges):
    """Golden: closed ranges, merge when overlapping or adjacent (next.lo <= cur.hi + 1)."""
    res = []
    for lo, hi in sorted(ranges):
        if res and lo <= res[-1][1] + 1:
            res[-1][1] = max(res[-1][1], hi)
        else:
            res.append([lo, hi])
    return [tuple(r) for r in res]


def rand_ranges(rng, n, span_lo, span_hi, max_len):
    out = []
    for _ in range(n):
        lo = rng.randint(span_lo, span_hi)
        hi = min(lo + rng.randint(0, max_len), MAX)
        out.append((lo, hi))
    return out


def build_cases(rng):
    cases = []

    # Examples, same as problem-1.md
    cases.append(("example_1", [(0x01, 0x03), (0x02, 0x06), (0x08, 0x0A), (0x0F, 0x12)]))
    cases.append(("example_2", [(0x1000, 0x1FFF), (0x2000, 0x2FFF)]))
    cases.append(("example_3", [(0x22, 0x30), (0x10, 0x20), (0x12, 0x18)]))

    # Edge cases
    cases.append(("edge_empty", []))
    cases.append(("edge_single", [(0x5, 0x5)]))
    cases.append(("edge_points", [(0x3, 0x3), (0x1, 0x1), (0x7, 0x7), (0x2, 0x2), (0x5, 0x5)]))
    cases.append(("edge_duplicate", [(0x40, 0x4F)] * 5))
    cases.append(("edge_nested", [(0x20, 0x30), (0x50, 0x60), (0x00, 0xFF), (0x10, 0x18), (0xF0, 0xFF)]))
    cases.append(("edge_chain", [(0x40 - 0x8 * i, 0x47 - 0x8 * i) for i in range(8)]))
    cases.append(("edge_gap_one", [(0x21, 0x2F), (0x10, 0x1F), (0x31, 0x31)]))
    cases.append(("edge_zero_addr", [(0x0, 0x5), (0x0, 0x3), (0x0, 0x0), (0x7, 0x9)]))
    cases.append(("edge_max_addr", [(0x10, MAX), (0x20, 0x30), (0xFFFFFFF0, MAX)]))
    cases.append(("edge_high_half", [(0x90000000, 0x9000000F), (0x10, 0x1F), (0x7FFFFFF0, 0x80000010),
                                     (0x80000011, 0x8000001F), (0xC0000000, 0xC0000000)]))
    cases.append(("edge_full_space", [(0x80000000, MAX), (0x0, 0x7FFFFFFF)]))

    # Random
    cases.append(("random_dense", rand_ranges(rng, 12, 0x00, 0xFF, 0x20)))
    cases.append(("random_sparse", rand_ranges(rng, 20, 0, MAX, 0x1000)))
    cases.append(("random_points", rand_ranges(rng, 60, 0, 100, 0)))
    cases.append(("random_mid", rand_ranges(rng, 200, 0, 0xFFFF, 0x400)))
    cases.append(("random_top", rand_ranges(rng, 300, 0xFFFF0000, MAX, 0x200)))
    cases.append(("random_cross", rand_ranges(rng, 500, 0x7FFF0000, 0x8000FFFF, 0x100)))
    cases.append(("random_large", rand_ranges(rng, 2000, 0, MAX, 1 << 24)))
    mixed = (rand_ranges(rng, 2000, 0, MAX, 0x10000)
             + rand_ranges(rng, 2000, 0, 0xFFFFF, 0x100)
             + rand_ranges(rng, 1000, 0xFFF00000, MAX, 0x100))
    rng.shuffle(mixed)
    cases.append(("random_mixed", mixed))

    # Performance: sparse, so most ranges stay separate and O(N^2) or O(N*M) times out
    cases.append(("perf_100k", rand_ranges(rng, 100000, 0, MAX, 0x4000)))
    return cases


def write_file(path, blocks):
    with open(path, "w", newline="\n") as f:
        f.write(f"{len(blocks)}\n")
        for tag, ranges in blocks:
            f.write(f"{len(ranges)} {tag}\n")
            for lo, hi in ranges:
                f.write(f"{lo:08x} {hi:08x}\n")


def main():
    rng = random.Random(SEED)
    cases = build_cases(rng)
    for tag, ranges in cases:
        assert len(tag) <= 18 and " " not in tag
        assert all(0 <= lo <= hi <= MAX for lo, hi in ranges)
    answers = [(tag, merge(ranges)) for tag, ranges in cases]

    os.makedirs(OUT_DIR, exist_ok=True)
    write_file(os.path.join(OUT_DIR, "input.txt"), cases)
    write_file(os.path.join(OUT_DIR, "output.txt"), answers)

    for i, ((tag, ranges), (_, ans)) in enumerate(zip(cases, answers), 1):
        print(f"case {i:2d} {tag:<18s} N = {len(ranges):6d}  M = {len(ans):6d}")


if __name__ == "__main__":
    main()
