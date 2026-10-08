#!/usr/bin/env python3
"""Problem 3 (LRU Cache) golden model and testcase generator.

Contains the answer: do not open before solving problem-3.

Writes ../../problem-3/testcase/input.txt and output.txt.
input.txt:
    <case_num>
    <cap> <m> <tag>
    G <key>  or  P <key> <val>      (m lines)
output.txt:
    <case_num>
    <m> <tag>
    <result>                        (m lines)
GET result: value on a hit, -1 on a miss.
PUT result: evicted key, -1 when nothing is evicted.
"""

import os
import random
from collections import OrderedDict

KEY_MAX = 0x7FFFFFFF
SEED = 2026

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "..", "problem-3", "testcase")


def lru_run(cap, ops):
    """Golden: OrderedDict keeps the LRU key first."""
    cache = OrderedDict()
    res = []
    for op in ops:
        if op[0] == "G":
            k = op[1]
            if k in cache:
                cache.move_to_end(k)
                res.append(cache[k])
            else:
                res.append(-1)
        else:
            k, v = op[1], op[2]
            if k in cache:
                cache.move_to_end(k)
                res.append(-1)
            elif len(cache) == cap:
                old, _ = cache.popitem(last=False)
                res.append(old)
            else:
                res.append(-1)
            cache[k] = v
    return res


def lru_run_brute(cap, ops):
    """Cross-check: list ordered from LRU to MRU."""
    order, val, res = [], {}, []
    for op in ops:
        k = op[1]
        if op[0] == "G":
            if k in val:
                order.remove(k)
                order.append(k)
                res.append(val[k])
            else:
                res.append(-1)
        else:
            if k in val:
                order.remove(k)
                res.append(-1)
            elif len(order) == cap:
                old = order.pop(0)
                del val[old]
                res.append(old)
            else:
                res.append(-1)
            order.append(k)
            val[k] = op[2]
    return res


def rand_ops(rng, m, keys, get_ratio, val_max=9999):
    ops = []
    for _ in range(m):
        k = rng.choice(keys)
        if rng.random() < get_ratio:
            ops.append(("G", k))
        else:
            ops.append(("P", k, rng.randint(0, val_max)))
    return ops


def build_cases(rng):
    cases = []
    G = lambda k: ("G", k)
    P = lambda k, v: ("P", k, v)

    # Examples, same as problem-3.md
    cases.append(("example_1", 2, [P(1, 1), P(2, 2), G(1), P(3, 3), G(2), P(4, 4), G(1), G(3), G(4)]))
    cases.append(("example_2", 2, [P(1, 10), P(2, 20), P(1, 11), P(3, 30), G(1), G(2)]))
    cases.append(("example_3", 3, [P(5, 0), G(5), G(6), P(0, 7), G(0)]))

    # Edge cases
    cases.append(("edge_no_ops", 4, []))
    cases.append(("edge_get_empty", 3, [G(0), G(1), G(KEY_MAX)]))
    cases.append(("edge_cap_one", 1, [P(1, 1), G(1), P(2, 2), G(1), G(2), P(2, 5), G(2), P(3, 3), G(2)]))
    cases.append(("edge_update_full", 3, [P(1, 1), P(2, 2), P(3, 3), P(2, 22), P(1, 11), P(3, 33),
                                          G(1), G(2), G(3), P(4, 4), G(2)]))
    cases.append(("edge_zero", 2, [P(0, 0), G(0), P(1, 0), G(1), G(2), P(2, 0), G(0), G(1)]))
    cases.append(("edge_max_key", 2, [P(KEY_MAX, KEY_MAX), P(0, 1), G(KEY_MAX), P(7, 7), G(0), G(KEY_MAX)]))
    cases.append(("edge_repeat_put", 2, [P(9, i) for i in range(6)] + [G(9), P(8, 8), P(7, 7), G(9)]))
    cases.append(("edge_get_refresh", 3, [P(1, 1), P(2, 2), P(3, 3), G(1), G(2), P(4, 4), G(3),
                                          G(1), P(5, 5), G(2), G(4)]))
    cases.append(("edge_miss_no_touch", 2, [P(1, 1), P(2, 2), G(3), G(3), P(4, 4), G(1), G(2)]))
    cases.append(("edge_evict_all", 4, [P(k, k * 10) for k in range(4)] + [G(2), G(0)]
                                       + [P(k, k) for k in range(10, 14)]))

    # Random
    cases.append(("random_small", 3, rand_ops(rng, 50, list(range(7)), 0.5)))
    cases.append(("random_hit_heavy", 50, rand_ops(rng, 2000, list(range(60)), 0.6)))
    cases.append(("random_miss_heavy", 10, rand_ops(rng, 2000, list(range(1000)), 0.5)))
    big_keys = [rng.randint(0, KEY_MAX) for _ in range(150)]
    cases.append(("random_big_keys", 100, rand_ops(rng, 3000, big_keys, 0.5)))
    cases.append(("random_put_only", 64, rand_ops(rng, 3000, list(range(100)), 0.0)))
    cases.append(("random_mixed", 1000, rand_ops(rng, 20000, list(range(1500)), 0.5)))

    # Performance: a queue scanned with find / delete per op is O(cap) and times out
    cases.append(("perf_300k", 50000, rand_ops(rng, 300000, list(range(55000)), 0.5)))
    return cases


def write_input(path, cases):
    with open(path, "w", newline="\n") as f:
        f.write(f"{len(cases)}\n")
        for tag, cap, ops in cases:
            f.write(f"{cap} {len(ops)} {tag}\n")
            for op in ops:
                f.write(" ".join(str(x) for x in op) + "\n")


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
    for tag, cap, ops in cases:
        assert len(tag) <= 18 and " " not in tag and cap >= 1
        assert all(0 <= op[1] <= KEY_MAX for op in ops)
        assert all(0 <= op[2] <= KEY_MAX for op in ops if op[0] == "P")
    answers = [(tag, lru_run(cap, ops)) for tag, cap, ops in cases]

    # Cross-check the golden against the list model on the small cases
    for (tag, cap, ops), (_, res) in zip(cases, answers):
        if len(ops) * cap <= 5000000:
            assert res == lru_run_brute(cap, ops), tag

    os.makedirs(OUT_DIR, exist_ok=True)
    write_input(os.path.join(OUT_DIR, "input.txt"), cases)
    write_output(os.path.join(OUT_DIR, "output.txt"), answers)

    for i, ((tag, cap, ops), (_, res)) in enumerate(zip(cases, answers), 1):
        hits = sum(1 for op, r in zip(ops, res) if op[0] == "G" and r >= 0)
        evicts = sum(1 for op, r in zip(ops, res) if op[0] == "P" and r >= 0)
        print(f"case {i:2d} {tag:<18s} cap = {cap:6d}  M = {len(ops):6d}  hit = {hits:6d}  evict = {evicts:6d}")


if __name__ == "__main__":
    main()
