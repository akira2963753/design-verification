#!/usr/bin/env python3
# ============================================================================
# 2026 FALL NYCU IC LAB, LAB04 F_ATTN
# Random input.txt generator. Stimulus only: the golden answer is computed in PATTERN.
#
# Usage: python3 gen_pattern.py [--pat 300] [--seed N] [-o input.txt]
#
# File format (one line per input cycle, 64 lines per pattern):
#   <pattern num>
#   Q K V W      <- cycle 0 ~ 15, FP32 hex in raster order
#   Q K V        <- cycle 16 ~ 63, out_weight is only valid for 16 cycles
#
# Spec ranges kept by construction (magnitude, sign is random):
#   Q, V, W : 0 ~ 0.5
#   K       : 0.5 ~ 255.0
# ============================================================================
import argparse
import math
import os
import random
import struct

N = 16          # tokens
D = 4           # embedding dim
Q_RANGE = (0.0, 0.5)
K_RANGE = (0.5, 255.0)
V_RANGE = (0.0, 0.5)
W_RANGE = (0.0, 0.5)
SQRT2 = struct.unpack('>f', bytes.fromhex('3FB504F3'))[0]   # TA parameter sqare_root_2


# ----------------------------------------------------------------------------
# FP32 helpers
# ----------------------------------------------------------------------------
def f32(x):
    """Round a python float to the nearest FP32 value."""
    return struct.unpack('>f', struct.pack('>f', x))[0]


def f32_hex(x):
    return struct.pack('>f', x).hex().upper()


def rand_sign(rng, mag):
    return mag if rng.random() < 0.5 else -mag


def uniform_mag(rng, lo, hi):
    return rng.uniform(lo, hi)


def log_mag(rng, lo, hi):
    """Log-uniform magnitude, so small exponents also show up (lo = 0 uses 1e-7)."""
    lo = max(lo, 1e-7)
    return math.exp(rng.uniform(math.log(lo), math.log(hi)))


def edge_mag(rng, lo, hi):
    """Range boundary or a value right next to it."""
    return rng.choice([lo, hi, lo + (hi - lo) * 1e-3, hi - (hi - lo) * 1e-3])


def mat(rng, rows, rng_lo_hi, mag_fn, sign=None):
    lo, hi = rng_lo_hi
    out = []
    for _ in range(rows):
        row = []
        for _ in range(D):
            m = mag_fn(rng, lo, hi)
            v = m if sign == '+' else -m if sign == '-' else rand_sign(rng, m)
            row.append(f32(v))
        out.append(row)
    return out


# ----------------------------------------------------------------------------
# Pattern modes
# ----------------------------------------------------------------------------
def gen_pattern(rng, mode):
    if mode == 'uniform':
        q = mat(rng, N, Q_RANGE, uniform_mag)
        k = mat(rng, N, K_RANGE, uniform_mag)
        v = mat(rng, N, V_RANGE, uniform_mag)
        w = mat(rng, D, W_RANGE, uniform_mag)
    elif mode == 'logmag':
        # spread the exponents: tiny Q / V / W and small K
        q = mat(rng, N, Q_RANGE, log_mag)
        k = mat(rng, N, K_RANGE, log_mag)
        v = mat(rng, N, V_RANGE, log_mag)
        w = mat(rng, D, W_RANGE, log_mag)
    elif mode == 'boundary':
        q = mat(rng, N, Q_RANGE, edge_mag)
        k = mat(rng, N, K_RANGE, edge_mag)
        v = mat(rng, N, V_RANGE, edge_mag)
        w = mat(rng, D, W_RANGE, edge_mag)
    elif mode == 'max_score':
        # |Q| = 0.5, |K| = 255 -> |score| up to 2 * 0.5 * 255 / sqrt2 ~= 180, e^S overflows FP32
        q = mat(rng, N, (0.5, 0.5), uniform_mag, sign='+')
        k = mat(rng, N, (255.0, 255.0), uniform_mag)
        v = mat(rng, N, V_RANGE, uniform_mag)
        w = mat(rng, D, W_RANGE, uniform_mag)
    elif mode in ('max_last', 'max_first'):
        # Q > 0 and K > 0 growing with the token index -> every row max sits in the
        # last K block (running max is updated on every tile) or in the first one
        q = mat(rng, N, Q_RANGE, uniform_mag, sign='+')
        k = []
        for t in range(N):
            base = K_RANGE[0] + (K_RANGE[1] - K_RANGE[0]) * t / (N - 1)
            k.append([f32(min(K_RANGE[1], base + rng.uniform(0.0, 0.4))) for _ in range(D)])
        if mode == 'max_first':
            k.reverse()
        v = mat(rng, N, V_RANGE, uniform_mag)
        w = mat(rng, D, W_RANGE, uniform_mag)
    elif mode == 'equal_score':
        # all K rows the same -> every score in a row is equal, uniform softmax
        q = mat(rng, N, Q_RANGE, uniform_mag)
        row = mat(rng, 1, K_RANGE, uniform_mag)[0]
        k = [list(row) for _ in range(N)]
        v = mat(rng, N, V_RANGE, uniform_mag)
        w = mat(rng, D, W_RANGE, uniform_mag)
    elif mode == 'zero_q':
        # all scores are 0 -> uniform softmax
        q = [[0.0] * D for _ in range(N)]
        k = mat(rng, N, K_RANGE, uniform_mag)
        v = mat(rng, N, V_RANGE, uniform_mag)
        w = mat(rng, D, W_RANGE, uniform_mag)
    elif mode == 'zero_v':
        # every output must be exactly 0
        q = mat(rng, N, Q_RANGE, uniform_mag)
        k = mat(rng, N, K_RANGE, uniform_mag)
        v = [[0.0] * D for _ in range(N)]
        w = mat(rng, D, W_RANGE, uniform_mag)
    elif mode == 'negative':
        q = mat(rng, N, Q_RANGE, uniform_mag, sign='-')
        k = mat(rng, N, K_RANGE, uniform_mag, sign='-')
        v = mat(rng, N, V_RANGE, uniform_mag, sign='-')
        w = mat(rng, D, W_RANGE, uniform_mag, sign='-')
    else:
        raise ValueError(mode)
    return q, k, v, w


DIRECTED = ['max_score', 'max_last', 'max_first', 'equal_score', 'zero_q', 'zero_v', 'negative', 'boundary']
MODE_WEIGHT = {'uniform': 5, 'logmag': 2, 'boundary': 2, 'max_score': 1,
               'max_last': 1, 'max_first': 1, 'equal_score': 1, 'negative': 1}


# ----------------------------------------------------------------------------
# Statistics only (the golden answer lives in PATTERN)
# ----------------------------------------------------------------------------
def max_abs_score(q, k):
    m = 0.0
    for h in range(2):
        for i in range(N):
            for j in range(N):
                s = (q[i][2*h] * k[j][2*h] + q[i][2*h+1] * k[j][2*h+1]) / SQRT2
                m = max(m, abs(s))
    return m


def check_range(q, k, v, w):
    for mtx, (lo, hi) in ((q, Q_RANGE), (k, K_RANGE), (v, V_RANGE), (w, W_RANGE)):
        for row in mtx:
            for x in row:
                assert lo <= abs(x) <= hi, (x, lo, hi)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description='Lab04 F_ATTN input.txt generator')
    ap.add_argument('--pat', type=int, default=300, help='number of patterns')
    ap.add_argument('--seed', type=int, default=None, help='random seed')
    ap.add_argument('-o', '--out', default=os.path.join(here, 'input.txt'))
    args = ap.parse_args()

    seed = args.seed if args.seed is not None else random.randrange(1 << 31)
    rng = random.Random(seed)

    # directed corner patterns first, then a weighted random mix
    modes = DIRECTED[:args.pat]
    names, wts = zip(*MODE_WEIGHT.items())
    while len(modes) < args.pat:
        modes.append(rng.choices(names, wts)[0])

    pats = []
    st = {'mode': {}, 'max_score': 0.0, 'over_88': 0}
    for mode in modes:
        q, k, v, w = gen_pattern(rng, mode)
        check_range(q, k, v, w)
        pats.append((q, k, v, w))
        st['mode'][mode] = st['mode'].get(mode, 0) + 1
        ms = max_abs_score(q, k)
        st['max_score'] = max(st['max_score'], ms)
        st['over_88'] += (ms > 88.7)

    with open(args.out, 'w', newline='\n') as f:
        f.write('%d\n' % len(pats))
        for q, k, v, w in pats:
            for c in range(N * D):
                t, d = c // D, c % D
                row = [f32_hex(q[t][d]), f32_hex(k[t][d]), f32_hex(v[t][d])]
                if c < D * D:
                    row.append(f32_hex(w[t][d]))
                f.write(' '.join(row) + '\n')

    print('seed          : %d' % seed)
    print('output        : %s' % args.out)
    print('patterns      : %d  %s' % (len(pats), dict(sorted(st['mode'].items()))))
    print('max |score|   : %.2f  (patterns with |score| > 88.7, e^S overflows FP32: %d)' % (st['max_score'], st['over_88']))


if __name__ == '__main__':
    main()
