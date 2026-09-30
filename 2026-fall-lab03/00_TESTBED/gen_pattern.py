#!/usr/bin/env python3
# ============================================================================
# 2026 FALL NYCU IC LAB, LAB03 ZUMA
# Random input.txt generator. Stimulus only: the golden answer is computed in PATTERN.
#
# Usage: python3 gen_pattern.py [--pat 300] [--max_shot 200] [--seed N] [-o input.txt]
#
# Spec constraints kept by construction:
#   - ring_len 4 ~ 128, color 0 ~ 7
#   - initial ring has no same-color segment >= 3 (wrap-around included)
#   - ring size <= 255 before every shot, so it never exceeds 256 after insertion
#   - shot_pos in 0 ~ M-1, and 0 when the ring is empty
# ============================================================================
import argparse
import os
import random

MAX_RING = 256
MAX_LEN = 128
MIN_LEN = 4
COLORS = list(range(8))


# ----------------------------------------------------------------------------
# Ring model (ring[0] is always logical index 0), only used to track the state
# ----------------------------------------------------------------------------
def find_seg(ring, idx):
    m = len(ring)
    left = 0
    while left < m - 1 and ring[(idx - left - 1) % m] == ring[idx]:
        left += 1
    right = 0
    while left + right < m - 1 and ring[(idx + right + 1) % m] == ring[idx]:
        right += 1
    return (idx - left) % m, left + right + 1


def shoot(ring, color, pos, st):
    """Apply one shot in place, return the cascade list [(color, cnt), ...]."""
    res = []
    if not ring:
        ring.append(color)
        st['empty_shot'] += 1
        return res
    ring.insert(pos + 1, color)
    idx = pos + 1
    start, length = find_seg(ring, idx)
    while length >= 3:
        m = len(ring)
        res.append((ring[idx], length))
        if length == m:
            del ring[:]
            st['clear'] += 1
            break
        if start + length <= m:
            if start == 0:
                st['idx0_elim'] += 1
            del ring[start:start + length]
            right = start % len(ring)
        else:
            # wrap: the first survivor after the segment becomes logical index 0
            st['wrap_elim'] += 1
            st['idx0_elim'] += 1
            ring[:] = ring[start + length - m:start]
            right = 0
        if len(ring) < 3:
            break
        left = (right - 1) % len(ring)
        if ring[left] != ring[right]:
            break
        idx = right
        start, length = find_seg(ring, idx)
    return res


# ----------------------------------------------------------------------------
# Initial ring
# ----------------------------------------------------------------------------
def valid_ring(r):
    n = len(r)
    return all(not (r[i] == r[(i + 1) % n] == r[(i + 2) % n]) for i in range(n))


def rand_seq(rng, length, palette, prev=()):
    """Random sequence with no 3 consecutive same colors (also against prev)."""
    r = list(prev)
    for _ in range(length):
        cand = [c for c in palette if not (len(r) >= 2 and r[-1] == r[-2] == c)]
        r.append(rng.choice(cand))
    return r[len(prev):]


def rand_ring(rng, length, palette):
    while True:
        r = rand_seq(rng, length, palette)
        if valid_ring(r):
            return r


def cascade_ring(rng, length, palette):
    """
    Symmetric runs around a 2-bead run of x:  L_d .. L_1 [x x] R_1 .. R_d  + filler.
    L_i / R_i share color c_i and join to 3 or 4 beads, so shooting x into [x x]
    gives d + 1 cascade levels. The ring is rotated so the core may cross index 0.
    Return (ring, trigger_pos, x).
    """
    max_depth = (length - 2) // 3
    for _ in range(1000):
        depth = rng.randint(1, max(1, max_depth))
        cols = [rng.choice(palette)]
        for _ in range(depth):
            cols.append(rng.choice([c for c in palette if c != cols[-1]]))
        x = cols[0]
        sizes = [rng.choice([(1, 2), (2, 1), (2, 2)]) for _ in range(depth)]
        left, right = [], []
        for i in range(depth, 0, -1):
            left += [cols[i]] * sizes[i - 1][0]
        for i in range(1, depth + 1):
            right += [cols[i]] * sizes[i - 1][1]
        core = left + [x, x] + right
        if len(core) > length:
            continue
        ring = core + rand_seq(rng, length - len(core), palette, core[-2:])
        if not valid_ring(ring):
            continue
        rot = rng.randrange(length)
        ring = ring[rot:] + ring[:rot]
        return ring, (len(left) - rot) % length, x
    return rand_ring(rng, length, palette), None, None


# ----------------------------------------------------------------------------
# Shot policy
# ----------------------------------------------------------------------------
def pair_starts(ring):
    m = len(ring)
    if m < 2:
        return []
    return [p for p in range(m) if ring[p] == ring[(p + 1) % m] and (m > 2 or p == 0)]


def pick_shot(rng, ring, palette, policy):
    m = len(ring)
    if m == 0:
        return rng.choice(palette), 0
    if policy == 'match' or policy == 'drain':
        pairs = pair_starts(ring)
        if pairs and (policy == 'drain' or rng.random() < 0.7):
            p = rng.choice(pairs)
            pos = rng.choice([(p - 1) % m, p, (p + 1) % m])   # before, inside, after the pair
            return ring[p], pos
        j = rng.randrange(m)
        return ring[j], rng.choice([j, (j - 1) % m])          # make a pair next to bead j
    if policy == 'wrap':
        pos = rng.choice([m - 1, 0, max(0, m - 2)])
        return rng.choice([ring[0], ring[-1], ring[min(1, m - 1)]]), pos
    if policy == 'grow':
        pos = rng.randrange(m)
        cand = [c for c in palette if c != ring[pos] and c != ring[(pos + 1) % m]]
        return (rng.choice(cand) if cand else rng.choice(palette)), pos
    return rng.choice(palette), rng.randrange(m)                # random


MODES = {
    # mode: (policy weights, palette size range, ring_len range)
    'random':  ({'random': 1},                                    (2, 8), (MIN_LEN, MAX_LEN)),
    'match':   ({'match': 3, 'random': 1},                        (2, 5), (MIN_LEN, MAX_LEN)),
    'wrap':    ({'wrap': 3, 'match': 1},                          (2, 4), (MIN_LEN, 16)),
    'grow':    ({'grow': 1},                                      (3, 8), (100, MAX_LEN)),
    'drain':   ({'drain': 1},                                     (2, 3), (MIN_LEN, 12)),
    'cascade': ({'match': 2, 'wrap': 1, 'random': 1},             (2, 6), (MIN_LEN, MAX_LEN)),
}
MODE_WEIGHT = {'random': 2, 'match': 3, 'wrap': 2, 'grow': 1, 'drain': 1, 'cascade': 3}


def gen_pattern(rng, mode, max_shot, st):
    weights, (pmin, pmax), (lmin, lmax) = MODES[mode]
    palette = rng.sample(COLORS, rng.randint(pmin, pmax))
    length = rng.randint(lmin, lmax)

    shots = []
    if mode == 'cascade':
        init, trig, x = cascade_ring(rng, length, palette)
        if trig is not None:
            shots.append((x, trig))
    else:
        init = rand_ring(rng, length, palette)

    shot_num = rng.randint(130, max(130, max_shot)) if mode == 'grow' else rng.randint(1, max_shot)
    ring = list(init)
    pols, wts = zip(*weights.items())
    applied = 0
    for i in range(shot_num):
        if len(ring) >= MAX_RING:
            break                                                # no room for one more insertion
        if i >= len(shots):
            shots.append(pick_shot(rng, ring, palette, rng.choices(pols, wts)[0]))
        color, pos = shots[i]
        res = shoot(ring, color, pos, st)
        applied += 1
        st['shots'] += 1
        st['max_ring'] = max(st['max_ring'], len(ring))
        st['hit256'] += (len(ring) == MAX_RING)
        st['chain'][len(res)] = st['chain'].get(len(res), 0) + 1
        for _, cnt in res:
            st['cnt'][cnt] = st['cnt'].get(cnt, 0) + 1
    return init, shots[:applied]


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description='Lab03 ZUMA input.txt generator')
    ap.add_argument('--pat', type=int, default=300, help='number of patterns')
    ap.add_argument('--max_shot', type=int, default=200, help='max shots per pattern')
    ap.add_argument('--seed', type=int, default=None, help='random seed')
    ap.add_argument('-o', '--out', default=os.path.join(here, 'input.txt'))
    args = ap.parse_args()

    seed = args.seed if args.seed is not None else random.randrange(1 << 31)
    rng = random.Random(seed)
    st = {'shots': 0, 'empty_shot': 0, 'clear': 0, 'wrap_elim': 0, 'idx0_elim': 0,
          'max_ring': 0, 'hit256': 0, 'chain': {}, 'cnt': {}, 'mode': {}}

    # pattern 1: the PDF example as a sanity check
    pats = [([1, 2, 2, 3, 3, 2, 2, 4, 1], [(3, 3), (1, 2), (4, 0), (4, 0), (2, 0)])]
    ring = list(pats[0][0])
    for c, p in pats[0][1]:
        shoot(ring, c, p, dict(st, chain={}, cnt={}))

    modes, mw = zip(*MODE_WEIGHT.items())
    for _ in range(args.pat - 1):
        mode = rng.choices(modes, mw)[0]
        st['mode'][mode] = st['mode'].get(mode, 0) + 1
        pats.append(gen_pattern(rng, mode, args.max_shot, st))

    with open(args.out, 'w', newline='\n') as f:
        f.write('%d\n' % len(pats))
        for init, shots in pats:
            f.write('%d %d\n' % (len(init), len(shots)))
            f.write(' '.join(map(str, init)) + '\n')
            for c, p in shots:
                f.write('%d %d\n' % (c, p))

    print('seed          : %d' % seed)
    print('output        : %s' % args.out)
    print('patterns      : %d  %s' % (len(pats), dict(sorted(st['mode'].items()))))
    print('shots         : %d  (empty-ring shots %d)' % (st['shots'], st['empty_shot']))
    print('chain_num     : %s' % dict(sorted(st['chain'].items())))
    print('elim_cnt      : %s' % dict(sorted(st['cnt'].items())))
    print('wrap elim     : %d, index-0 eliminated %d, ring cleared %d' % (st['wrap_elim'], st['idx0_elim'], st['clear']))
    print('max ring size : %d  (shots ending at 256: %d)' % (st['max_ring'], st['hit256']))


if __name__ == '__main__':
    main()
