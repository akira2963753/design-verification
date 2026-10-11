# F_ATTN fixed-point model on the GPU (numba-cuda): the same integer datapath as fxp_model.model,
# one thread = one (config, pattern), a block reduces 128 patterns of one config
# all intermediates fit in int64 for the sweep ranges (largest: Q'.K sum < 2^(Fq + Fk + 9))
import math, os, time
import numpy as np
from numba import cuda, int64, float64
from numba.cuda import libdevice
import fxp_model as fm

TPB = 128                                           # patterns per block

#=============================================================
#                      Device Functions
#=============================================================
@cuda.jit(device=True, inline=True)
def shr(x, n):
    if n >= 0:
        if n > 62:
            return x >> 63                          # 0 or -1, as a Python shift by a large n
        return x >> n
    return x << (-n)

@cuda.jit(device=True, inline=True)
def conv_q(b, cint, Nc, Fq):
    e = (b >> 23) & 0xFF
    if e == 0 or e > 126:
        return int64(0)
    m = (b & 0x7FFFFF) | 0x800000
    x = shr(m * cint, 150 + Nc - Fq - 1 - e)
    x = (x + 1) >> 1
    if (b >> 31) & 1:
        return -x
    return x

@cuda.jit(device=True, inline=True)
def conv_f(b, F, emax):
    e = (b >> 23) & 0xFF
    if e == 0 or e > emax:
        return int64(0)
    m = (b & 0x7FFFFF) | 0x800000
    x = shr(m, 149 - F - e)
    x = (x + 1) >> 1
    if (b >> 31) & 1:
        return -x
    return x

@cuda.jit(device=True, inline=True)
def pow2(fr, Ft, T, ti, HB, XQ, EB, ST, A1B, A2B, A1, A2, bias):
    # ATTN_POW2 with its internal precision (see fxp_model.P2KEYS), table row ti
    x = fr & ((int64(1) << (Ft - HB)) - 1)
    fh = fr >> (Ft - HB)
    lin = shr(x * A1, A1B + Ft - EB)
    xq = shr(x, Ft - XQ)
    quad = shr(xq * xq * A2, 2 * XQ + A2B - EB)
    t = T[ti, fh]
    return t + shr((t >> ST) * (lin + quad), EB - ST) + bias

@cuda.jit(device=True, inline=True)
def hval(M, D, shh, hmax):
    a = M
    if a < 0:
        a = -a
    hq = shr(a, -shh) // D
    if hq > hmax:
        hq = hmax
    hq = 2 * hq + 1                                 # |H| + 1/2 LSB
    if M < 0:
        return -hq
    return hq

@cuda.jit(device=True, inline=True)
def to_fp(acc, F):
    neg = acc < 0
    mag = acc
    if neg:
        mag = ~acc
    if mag == 0:
        return 0.0
    pos = 63 - libdevice.clzll(mag)
    if pos >= 23:
        mant = mag >> (pos - 23)
    else:
        mant = mag << (23 - pos)
    v = libdevice.ldexp(float64(mant), pos - 23 - F)
    if neg:
        return -v
    return v

#=============================================================
#                          Kernel
#=============================================================
@cuda.jit
def sweep_kernel(Qb, Kb, Vb, Wb, G, cfgs, p2, c_base, cint_tab, T, out_max, out_sum, dump, dump_out):
    # cfgs[c] = the 9 widths, p2[c] = HB, XQ, EB, ST, A1B, A2B, A1, A2, bias, table row
    p = cuda.blockIdx.x * TPB + cuda.threadIdx.x
    ci = c_base + cuda.blockIdx.y
    smax = cuda.shared.array(TPB, float64)
    ssum = cuda.shared.array(TPB, float64)
    pmax = 0.0
    if p < G.shape[0] and ci < cfgs.shape[0]:
        Nc = cfgs[ci, 0]; Fq = cfgs[ci, 1]; Fk = cfgs[ci, 2]; Fv = cfgs[ci, 3]; Fw = cfgs[ci, 4]
        Ft = cfgs[ci, 5]; Pw = cfgs[ci, 6]; Fm = cfgs[ci, 7]; Fh = cfgs[ci, 8]
        cint = cint_tab[Nc]
        HB = p2[ci, 0]; XQ = p2[ci, 1]; EB = p2[ci, 2]; ST = p2[ci, 3]; A1B = p2[ci, 4]; A2B = p2[ci, 5]
        A1 = p2[ci, 6]; A2 = p2[ci, 7]; bias = p2[ci, 8]; ti = p2[ci, 9]
        K = cuda.local.array(64, int64)
        V = cuda.local.array(64, int64)
        W = cuda.local.array(16, int64)
        Hr = cuda.local.array(4, int64)
        for c in range(64):
            K[c] = conv_f(int64(Kb[p, c]), Fk, 134)
            V[c] = conv_f(int64(Vb[p, c]), Fv, 126)
        for c in range(16):
            W[c] = conv_f(int64(Wb[p, c]), Fw, 126)
        st = Fq + Fk - Ft
        tr = int64(1) << (st - 1)
        sp = Pw + Fv - Fm
        pr = int64(1) << (sp - 1)
        shh = Fh - Fm + Pw
        hmax = (int64(1) << (Fh - 1)) - 1
        fmask = (int64(1) << Ft) - 1
        F = Fh + 1 + Fw
        for i in range(16):                         # row = token i, both heads, then its 4 outputs
            for h in range(2):
                qa = conv_q(int64(Qb[p, 4 * i + 2 * h]), cint, Nc, Fq)
                qb = conv_q(int64(Qb[p, 4 * i + 2 * h + 1]), cint, Nc, Fq)
                r = int64(0); D = int64(0); M0 = int64(0); M1 = int64(0)
                for j in range(8):
                    ka = 8 * j + 2 * h
                    kb = ka + 4
                    # S1
                    t0 = (qa * K[ka] + qb * K[ka + 1] + tr) >> st
                    t1 = (qa * K[kb] + qb * K[kb + 1] + tr) >> st
                    # S2
                    f0 = t0 >> Ft
                    f1 = t1 >> Ft
                    r0 = t0 & fmask
                    r1 = t1 & fmask
                    c0 = f0
                    if r0 != 0:
                        c0 += 1
                    c1 = f1
                    if r1 != 0:
                        c1 += 1
                    rn = max(c0, c1)
                    if j > 0 and r > rn:
                        rn = r
                    w0 = pow2(r0, Ft, T, ti, HB, XQ, EB, ST, A1B, A2B, A1, A2, bias) >> min(rn - f0, 31)
                    w1 = pow2(r1, Ft, T, ti, HB, XQ, EB, ST, A1B, A2B, A1, A2, bias) >> min(rn - f1, 31)
                    # S3
                    pv0 = (w0 * V[ka] + w1 * V[kb] + pr) >> sp
                    pv1 = (w0 * V[ka + 1] + w1 * V[kb + 1] + pr) >> sp
                    if j == 0:
                        D = w0 + w1
                        M0 = pv0
                        M1 = pv1
                    else:
                        dl = min(rn - r, 31)
                        D = (D >> dl) + w0 + w1
                        M0 = (M0 >> dl) + pv0
                        M1 = (M1 >> dl) + pv1
                    r = rn
                Hr[2 * h] = hval(M0, D, shh, hmax)
                Hr[2 * h + 1] = hval(M1, D, shh, hmax)
            for o in range(4):
                acc = Hr[0] * W[4 * o] + Hr[1] * W[4 * o + 1] + Hr[2] * W[4 * o + 2] + Hr[3] * W[4 * o + 3]
                v = to_fp(acc, F)
                if dump:
                    dump_out[p, 4 * i + o] = v
                err = abs(v - G[p, 4 * i + o])
                if err > pmax:
                    pmax = err
    smax[cuda.threadIdx.x] = pmax
    ssum[cuda.threadIdx.x] = pmax
    cuda.syncthreads()
    s = TPB // 2
    while s > 0:
        if cuda.threadIdx.x < s:
            if smax[cuda.threadIdx.x + s] > smax[cuda.threadIdx.x]:
                smax[cuda.threadIdx.x] = smax[cuda.threadIdx.x + s]
            ssum[cuda.threadIdx.x] += ssum[cuda.threadIdx.x + s]
        cuda.syncthreads()
        s //= 2
    if cuda.threadIdx.x == 0 and ci < cfgs.shape[0]:
        cuda.atomic.max(out_max, ci, smax[0])
        cuda.atomic.add(out_sum, ci, ssum[0])

#=============================================================
#                           Host
#=============================================================
class Sweeper:
    # holds the patterns / golden and the ATTN_POW2 tables on the GPU
    def __init__(self, Q, K, V, W, G, pw_range, ft_range):
        self.P = G.shape[0]
        self.d = [cuda.to_device(np.ascontiguousarray(x)) for x in (Q, K, V, W, G)]
        self.cint = cuda.to_device(np.array([round(fm.C * (1 << n)) for n in range(40)], dtype=np.int64))
        self.tables = {}; self.d_T = None
        # default pow2 (64-entry table) for every (Ft, Pw) of the width sweep
        self.ft_min, self.pw_min = ft_range[0], pw_range[0]
        self.lut = np.zeros((ft_range[1] - ft_range[0] + 1, pw_range[1] - pw_range[0] + 1, 10), dtype=np.int64)
        for ft in range(ft_range[0], ft_range[1] + 1):
            for pw in range(pw_range[0], pw_range[1] + 1):
                self.lut[ft - self.ft_min, pw - self.pw_min] = self.p2_row(ft, pw, fm.pow2_defaults(pw))
        self.dummy = cuda.to_device(np.zeros((1, 64), dtype=np.float64))

    def table(self, HB, TB, Pw):
        # row of the table for (HB, TB, Pw), built on first use
        key = (HB, TB, Pw)
        if key not in self.tables:
            self.tables[key] = (len(self.tables), fm.pow2_table(HB, TB, Pw))
            self.d_T = None
        return self.tables[key][0]

    def p2_row(self, Ft, Pw, q, consts=None):
        # HB, XQ, EB, ST, A1B, A2B, A1, A2, bias, table row for a pow2 parameter set q
        A1, A2, bias = consts if consts is not None else fm.pow2_params(Ft, Pw, **q)[1:4]
        return [q['HB'], q['XQ'], q['EB'], q['ST'], q['A1B'], q['A2B'], A1, A2, bias, self.table(q['HB'], q['TB'], Pw)]

    def p2_default(self, cfgs):
        return self.lut[cfgs[:, 5].astype(np.int64) - self.ft_min, cfgs[:, 6].astype(np.int64) - self.pw_min]

    def upload(self):
        if self.d_T is None:
            T = np.zeros((len(self.tables), 256), dtype=np.int64)
            for i, t in self.tables.values(): T[i, :len(t)] = t
            self.d_T = cuda.to_device(T)

    def run(self, cfgs, p2=None, batch=1024, dump_n=0):
        # cfgs: (n, 9) widths (fm.KEYS), p2: (n, 10) pow2 rows (default pow2 when None)
        # returns (max error, mean of the per-pattern max) [, outputs when dump_n]
        if p2 is None: p2 = self.p2_default(cfgs)
        self.upload()
        d_cfg = cuda.to_device(np.ascontiguousarray(cfgs, dtype=np.int64))
        d_p2 = cuda.to_device(np.ascontiguousarray(p2, dtype=np.int64))
        n = len(cfgs)
        d_max = cuda.to_device(np.zeros(n, dtype=np.float64)); d_sum = cuda.to_device(np.zeros(n, dtype=np.float64))
        dump_out = cuda.to_device(np.zeros((self.P, 64), dtype=np.float64)) if dump_n else self.dummy
        gx = (self.P + TPB - 1) // TPB
        for c0 in range(0, n, batch):
            nb = min(batch, n - c0)
            sweep_kernel[(gx, nb), TPB](*self.d, d_cfg, d_p2, c0, self.cint, self.d_T,
                                        d_max, d_sum, 1 if dump_n else 0, dump_out)
        cuda.synchronize()
        res = d_max.copy_to_host(), d_sum.copy_to_host() / self.P
        if dump_n: return res + (dump_out.copy_to_host(),)
        return res

def sweep_all(sw, cfgs, ckpt, chunk=65536, batch=1024, log=print, save_every=300):
    # full sweep with checkpoints: finished chunks are saved to ckpt (.npz) every save_every
    # seconds and at the end, a rerun resumes from there
    n = len(cfgs)
    if os.path.exists(ckpt):
        d = np.load(ckpt); mx, mn, done = d['mx'], d['mn'], int(d['done'])
        if len(mx) != n: raise ValueError('checkpoint does not match the config list')
    else:
        mx = np.zeros(n); mn = np.zeros(n); done = 0
    t0 = time.time(); start = done; saved = t0
    while done < n:
        hi = min(done + chunk, n)
        a, b = sw.run(cfgs[done:hi], batch=batch)
        mx[done:hi] = a; mn[done:hi] = b; done = hi
        if done == n or time.time() - saved > save_every:
            np.savez(ckpt, mx=mx, mn=mn, done=done); saved = time.time()
        el = time.time() - t0; rate = (done - start) / el
        log('%d / %d configs  %.0f s  (%.1f configs/s, %.1f min left)' % (done, n, el, rate, (n - done) / rate / 60))
    return mx, mn
