#!/usr/bin/env python3
"""Problem 2 (Sliding Window Maximum) golden model and testcase generator.

Contains the answer: do not open before solving problem-2.

Writes ../../problem-2/testcase/input.txt and output.txt.
input.txt:
    <case_num>
    <n> <w> <tag>
    <x>            (n lines, signed decimal)
output.txt:
    <case_num>
    <m> <tag>
    <idx>          (m lines, m = max(0, n - w + 1))
"""

import os
import random
from collections import deque

S_MIN = -32768
S_MAX = 32767
SEED = 2026

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "..", "problem-2", "testcase")


def window_max(x, w):
    """Golden: monotonic deque of indices, earliest index wins on a tie."""
    dq = deque()
    res = []
    for i, v in enumerate(x):
        while dq and x[dq[-1]] < v:
            dq.pop()
        dq.append(i)
        if dq[0] <= i - w:
            dq.popleft()
        if i >= w - 1:
            res.append(dq[0])
    return res


def window_max_brute(x, w):
    res = []
    for i in range(len(x) - w + 1):
        best = i
        for j in range(i + 1, i + w):
            if x[j] > x[best]:
                best = j
        res.append(best)
    return res


def rand_samples(rng, n, lo=S_MIN, hi=S_MAX):
    return [rng.randint(lo, hi) for _ in range(n)]


def build_cases(rng):
    cases = []

    # Examples, same as problem-2.md
    cases.append(("example_1", [1, 3, -1, -3, 5, 3, 6, 7], 3))
    cases.append(("example_2", [4, 2, 4, 1, 4], 3))
    cases.append(("example_3", [-5, -2, -8, -1], 2))

    # Edge cases
    cases.append(("edge_empty", [], 1))
    cases.append(("edge_w_gt_n", [3, 1, 2], 5))
    cases.append(("edge_w_eq_n", [2, 9, -4, 9, 0, 1], 6))
    cases.append(("edge_w_one", [5, -1, 0, 7, 7, -32768], 1))
    cases.append(("edge_all_equal", [7] * 8, 3))
    cases.append(("edge_increasing", list(range(1, 11)), 4))
    cases.append(("edge_decreasing", list(range(10, 0, -1)), 4))
    cases.append(("edge_min_max", [S_MIN, S_MAX, -1, 0, S_MIN, S_MAX, S_MAX, S_MIN], 2))
    cases.append(("edge_all_negative", [-1, S_MIN, -2, -3, -32767, -2, -1], 3))
    cases.append(("edge_tie_leave", [5, 1, 5, 1, 5, 1, 5, 1], 3))

    # Random
    cases.append(("random_small", rand_samples(rng, 20), 4))
    cases.append(("random_negative", rand_samples(rng, 50, S_MIN, -30000), 5))
    cases.append(("random_tie", rand_samples(rng, 200, -1, 1), 7))
    cases.append(("random_mid", rand_samples(rng, 1000), 37))
    cases.append(("random_big_w", rand_samples(rng, 2000), 1500))
    cases.append(("random_cross_zero", rand_samples(rng, 3000, -50, 50), 64))
    cases.append(("random_mixed", rand_samples(rng, 5000), 100))

    # Performance: O(N*W) times out; the non-increasing case also breaks
    # "rescan only when the max leaves the window"
    cases.append(("perf_random", rand_samples(rng, 200000), 50000))
    cases.append(("perf_non_incr", [S_MAX - i // 3 for i in range(150000)], 50000))
    return cases


def write_input(path, cases):
    with open(path, "w", newline="\n") as f:
        f.write(f"{len(cases)}\n")
        for tag, x, w in cases:
            f.write(f"{len(x)} {w} {tag}\n")
            for v in x:
                f.write(f"{v}\n")


def write_output(path, answers):
    with open(path, "w", newline="\n") as f:
        f.write(f"{len(answers)}\n")
        for tag, res in answers:
            f.write(f"{len(res)} {tag}\n")
            for v in res:
                f.write(f"{v}\n")


def main():
    rng = random.Random(SEED)
    cases = build_cases(rng)
    for tag, x, w in cases:
        assert len(tag) <= 18 and " " not in tag
        assert w >= 1 and all(S_MIN <= v <= S_MAX for v in x)
    answers = [(tag, window_max(x, w)) for tag, x, w in cases]

    # Cross-check the golden against brute force on the small cases
    for (tag, x, w), (_, res) in zip(cases, answers):
        if len(x) * w <= 2000000:
            assert res == window_max_brute(x, w), tag

    os.makedirs(OUT_DIR, exist_ok=True)
    write_input(os.path.join(OUT_DIR, "input.txt"), cases)
    write_output(os.path.join(OUT_DIR, "output.txt"), answers)

    for i, ((tag, x, w), (_, res)) in enumerate(zip(cases, answers), 1):
        print(f"case {i:2d} {tag:<18s} N = {len(x):6d}  W = {w:6d}  M = {len(res):6d}")


if __name__ == "__main__":
    main()
