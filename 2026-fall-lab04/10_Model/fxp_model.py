# F_ATTN fixed-point model (CPU): parametric, bit-exact with 01_RTL/F_ATTN.v at BASE
# (the reference for the GPU sweep kernel in fxp_gpu.py)
import struct, math, os, sys, pickle, subprocess
import numpy as np

SQ2 = struct.unpack('>f', bytes.fromhex('3FB504F3'))[0]
C = math.log2(math.e) / SQ2
KEYS = ['Nc', 'Fq', 'Fk', 'Fv', 'Fw', 'Ft', 'Pw', 'Fm', 'Fh']
# widths of 01_RTL (r08); hhalf / tround / pvround / pow2 are design options, not swept
BASE = dict(Nc=19, Fq=25, Fk=16, Fv=22, Fw=22, Ft=20, Pw=23, Fm=24, Fh=22,
            pow2='hw', hhalf=1, pvround=1, tround=1)

#=============================================================
#                      Bit-exact Model
#=============================================================
def fpb(h):
    b = int(h, 16) if isinstance(h, str) else int(h)
    s = b >> 31; e = (b >> 23) & 0xFF
    return s, e, (0 if e == 0 else (b & 0x7FFFFF) | 0x800000)

def shr(x, n): return (x >> n) if n >= 0 else (x << -n)

# ATTN_POW2 internal precision (fraction bits unless noted), defaults = the RTL derivation from Pw:
#   HB  table index bits (2^HB entries)        TB  table entry fraction bits (<= Pw)
#   A1B a1 = round(a1 * 2^A1B)                 XQ  fraction bits kept in xq (x squared)
#   A2B a2 = round(a2 * 2^A2B), 0 = no x^2     EB  fraction bits of e = 2^x - 1
#   ST  low bits of T dropped in T * e
P2KEYS = ['HB', 'TB', 'A1B', 'XQ', 'A2B', 'EB', 'ST']

def pow2_defaults(Pw):
    return dict(HB=6, TB=Pw, A1B=Pw - 5, XQ=Pw - 9, A2B=Pw - 16, EB=Pw + 1, ST=Pw - 16)

_fit = {}
def pow2_fit(HB):
    # a1 / a2 of 2^x - 1 ~ a1 x + a2 x^2, least squares on [0, 2^-HB)
    if HB not in _fit:
        xs = np.linspace(0, 2.0 ** -HB, 4001)
        _fit[HB] = np.linalg.lstsq(np.vstack([xs, xs ** 2]).T, 2.0 ** xs - 1, rcond=None)[0]
    return _fit[HB]

_exact = {}
def pow2_exact(Ft, Pw):
    # sample points f and exact 2^f * 2^Pw used to center the truncation error
    if (Ft, Pw) not in _exact:
        f = list(range(0, 1 << Ft, max(1, (1 << Ft) // 10800)))
        _exact[(Ft, Pw)] = (np.array(f, dtype=np.int64), np.array([2.0 ** (x / (1 << Ft)) * (1 << Pw) for x in f]))
    return _exact[(Ft, Pw)]

def shr_np(x, n): return (x >> n) if n >= 0 else (x << -n)

def pow2_table(HB, TB, Pw):
    # 2^(i / 2^HB) rounded to TB fraction bits, aligned to Pw fraction bits
    return [round(2.0 ** (i / (1 << HB)) * (1 << TB)) << (Pw - TB) for i in range(1 << HB)]

def pow2_job(a):
    # (Ft, Pw, q) -> (A1, A2, bias), for a process pool
    Ft, Pw, q = a
    return tuple(pow2_params(Ft, Pw, **q)[1:4])

def pow2_params(Ft, Pw, **kw):
    # table (aligned to Pw fraction bits), a1, a2, bias and the full parameter set
    q = pow2_defaults(Pw); q.update(kw)
    HB, TB, A1B, XQ, A2B, EB, ST = (q[k] for k in P2KEYS)
    T = pow2_table(HB, TB, Pw)
    a1, a2 = pow2_fit(HB)
    A1 = round(a1 * 2 ** A1B)
    A2 = round(a2 * 2 ** A2B) if A2B > 0 else 0
    fs, ex = pow2_exact(Ft, Pw)
    x = fs & ((1 << (Ft - HB)) - 1); t = np.array(T, dtype=np.int64)[fs >> (Ft - HB)]
    xq = shr_np(x, Ft - XQ)
    e = shr_np(x * A1, A1B + Ft - EB) + shr_np(xq * xq * A2, 2 * XQ + A2B - EB)
    d = (t + shr_np((t >> ST) * e, EB - ST)).astype(np.float64) - ex
    bias = int(round(-(d.max() + d.min()) / 2))
    return T, A1, A2, bias, q

def pow2_consts(Ft, Pw):
    # default ATTN_POW2 (64-entry table): table, a1, a2, bias
    return pow2_params(Ft, Pw)[:4]

def pow2_raw(T, A1, A2, Ft, Pw, q):
    HB, TB, A1B, XQ, A2B, EB, ST = (q[k] for k in P2KEYS)
    xm = (1 << (Ft - HB)) - 1
    def nb(fr):
        x = fr & xm; fh = fr >> (Ft - HB)
        lin = shr(x * A1, A1B + Ft - EB)
        xq = shr(x, Ft - XQ)
        quad = shr(xq * xq * A2, 2 * XQ + A2B - EB)
        return T[fh] + shr((T[fh] >> ST) * (lin + quad), EB - ST)
    return nb

def make_pow2(p):
    Ft, Pw = p['Ft'], p['Pw']
    if p['pow2'] == 'ideal':
        return lambda fr: int(math.floor(2.0 ** (fr / (1 << Ft)) * (1 << Pw) + 0.5))
    T, A1, A2, bias, q = pow2_params(Ft, Pw, **{k: p[k] for k in P2KEYS if k in p})
    nb = pow2_raw(T, A1, A2, Ft, Pw, q)
    return lambda fr: nb(fr) + bias

def to_fp32(acc, F):
    # one's complement |acc| (|acc| - 1 when negative) and a truncated mantissa, as in the RTL
    s = 1 if acc < 0 else 0
    mag = (~acc) if s else acc
    if mag == 0: return 0.0
    pos = mag.bit_length() - 1
    mant = (mag >> (pos - 23)) if pos >= 23 else (mag << (23 - pos))
    return (-1.0 if s else 1.0) * mant * 2.0 ** (pos - 23 - F)

def model(pat, p, pow2):
    # pat = (q, k, v, w): fp32 words (hex strings or ints), 64 / 64 / 64 / 16
    q, k, v, w = pat
    Nc, Fq, Fk, Fv, Fw, Ft, Pw, Fm, Fh = (p[x] for x in KEYS)
    cint = round(C * (1 << Nc))
    def cq(h):                                          # Q' = Q * c, round half up
        s, e, m = fpb(h)
        if m == 0 or e > 126: return 0
        x = shr(m * cint, 150 + Nc - Fq - 1 - e); x = (x + 1) >> 1
        return -x if s else x
    def cf(h, F, emax):                                 # K / V / W, round half up
        s, e, m = fpb(h)
        if m == 0 or e > emax: return 0
        x = shr(m, 149 - F - e); x = (x + 1) >> 1
        return -x if s else x
    Q = [cq(x) for x in q]; K = [cf(x, Fk, 134) for x in k]; V = [cf(x, Fv, 126) for x in v]; W = [cf(x, Fw, 126) for x in w]
    st = Fq + Fk - Ft; tr = (1 << (st - 1)) if p['tround'] else 0
    sp = Pw + Fv - Fm; pr = (1 << (sp - 1)) if p['pvround'] else 0
    sh_h = Fh - Fm + Pw; hmax = (1 << (Fh - 1)) - 1
    fmask = (1 << Ft) - 1
    H = [[0] * 4 for _ in range(16)]
    for h in range(2):
        for i in range(16):
            qa, qb = Q[4 * i + 2 * h], Q[4 * i + 2 * h + 1]
            for j in range(8):                          # key tiles in the RTL order
                ka = 4 * (2 * j) + 2 * h; kb = 4 * (2 * j + 1) + 2 * h
                # S1: t = Q' . K
                t0 = (qa * K[ka] + qb * K[ka + 1] + tr) >> st
                t1 = (qa * K[kb] + qb * K[kb + 1] + tr) >> st
                # S2: integer running max r, weight = 2^frac(t) >> (r - floor t)
                f0, f1 = t0 >> Ft, t1 >> Ft; r0, r1 = t0 & fmask, t1 & fmask
                c0 = f0 + (1 if r0 else 0); c1 = f1 + (1 if r1 else 0)
                rn = max(c0, c1) if j == 0 else max(r, c0, c1)
                w0 = pow2(r0) >> min(rn - f0, 31); w1 = pow2(r1) >> min(rn - f1, 31)
                # S3: D / M accumulation with the shift correction
                pv0 = (w0 * V[ka] + w1 * V[kb] + pr) >> sp
                pv1 = (w0 * V[ka + 1] + w1 * V[kb + 1] + pr) >> sp
                if j == 0:
                    D = w0 + w1; M0 = pv0; M1 = pv1
                else:
                    dl = min(rn - r, 31)
                    D = (D >> dl) + w0 + w1; M0 = (M0 >> dl) + pv0; M1 = (M1 >> dl) + pv1
                r = rn
            # divider: |H| = floor(|M| / D), saturated; + 1/2 LSB in the linear layer
            for d, M in ((0, M0), (1, M1)):
                hq = min(shr(abs(M), -sh_h) // D, hmax)
                if p['hhalf']: hq = 2 * hq + 1
                H[i][2 * h + d] = -hq if M < 0 else hq
    # linear layer + fp32
    F = Fh + (1 if p['hhalf'] else 0) + Fw
    return [to_fp32(sum(H[t_][c] * W[4 * o + c] for c in range(4)), F) for t_ in range(16) for o in range(4)]

#=============================================================
#                    Golden and Patterns
#=============================================================
def golden(pat):
    # standard (non-tiled) attention in double precision, as ref_model in PATTERN
    q, k, v, w = pat
    f = lambda h: struct.unpack('>f', struct.pack('>I', int(h, 16) if isinstance(h, str) else int(h)))[0]
    Q = [[f(q[4 * i + d]) for d in range(4)] for i in range(16)]; K = [[f(k[4 * i + d]) for d in range(4)] for i in range(16)]
    V = [[f(v[4 * i + d]) for d in range(4)] for i in range(16)]; W = [[f(w[4 * i + d]) for d in range(4)] for i in range(4)]
    head = [[0] * 4 for _ in range(16)]
    for h in range(2):
        for i in range(16):
            s = [(Q[i][2 * h] * K[j][2 * h] + Q[i][2 * h + 1] * K[j][2 * h + 1]) / SQ2 for j in range(16)]
            m = max(s); e = [math.exp(x - m) for x in s]; sm = sum(e)
            for d in range(2): head[i][2 * h + d] = sum(e[j] * V[j][2 * h + d] for j in range(16)) / sm
    return [sum(head[t][c] * W[o][c] for c in range(4)) for t in range(16) for o in range(4)]

def load(path):
    # input.txt format: pattern count, then per cycle "Q K V [W]" (W only in the first 16 cycles)
    t = open(path).read().split(); n = int(t[0]); it = iter(t[1:]); P = []
    for _ in range(n):
        q, k, v, w = [], [], [], []
        for c in range(64):
            q.append(next(it)); k.append(next(it)); v.append(next(it))
            if c < 16: w.append(next(it))
        P.append((q, k, v, w))
    return P

def make_patterns(pat_dir, gen, seeds):
    os.makedirs(pat_dir, exist_ok=True)
    files = []
    for s in seeds:
        fn = os.path.join(pat_dir, 'seed_%d.txt' % s)
        if not os.path.exists(fn):
            subprocess.run([sys.executable, gen, '--pat', '1000', '--seed', str(s), '-o', fn], check=True, stdout=subprocess.DEVNULL)
        files.append(fn)
    return files

def _golden_chunk(pats): return [golden(x) for x in pats]

def load_data(files, cache, pool=None):
    # patterns as uint32 arrays (Q, K, V: P x 64, W: P x 16) + golden (P x 64), cached in an .npz
    if os.path.exists(cache):
        d = np.load(cache)
        return d['Q'], d['K'], d['V'], d['W'], d['G']
    P = []
    for fn in files: P += load(fn)
    if pool is None: G = [golden(x) for x in P]
    else: G = [g for part in pool.map(_golden_chunk, [P[i:i + 250] for i in range(0, len(P), 250)]) for g in part]
    to = lambda idx, n: np.array([[int(x, 16) for x in pat[idx]] for pat in P], dtype=np.uint32).reshape(len(P), n)
    Q, K, V, W = to(0, 64), to(1, 64), to(2, 64), to(3, 16)
    G = np.array(G, dtype=np.float64)
    np.savez(cache, Q=Q, K=K, V=V, W=W, G=G)
    return Q, K, V, W, G

def as_pat(Q, K, V, W, i): return ([int(x) for x in Q[i]], [int(x) for x in K[i]], [int(x) for x in V[i]], [int(x) for x in W[i]])

def _err_chunk(args):
    # per-pattern max |out - golden| for one config over patterns lo ~ hi (CPU reference)
    p, Q, K, V, W, G = args
    pw = make_pow2(p)
    return [max(abs(a - b) for a, b in zip(model(as_pat(Q, K, V, W, i), p, pw), G[i])) for i in range(len(G))]

def cpu_errors(pool, p, Q, K, V, W, G, chunk=200):
    n = len(G)
    jobs = [(p, Q[i:i + chunk], K[i:i + chunk], V[i:i + chunk], W[i:i + chunk], G[i:i + chunk]) for i in range(0, n, chunk)]
    return np.array([e for part in pool.map(_err_chunk, jobs) for e in part])
