#!/usr/bin/env python3
"""Wrap JPEGLENC raw entropy bytes into a viewable baseline JPEG.

The design output (one hex byte per line, all channels concatenated) is split
into scans by Huffman-decoding exactly 256 blocks per scan. The structure comes
from the header of the matching input.txt (line 1 = pat_num, line 2 = mode).
pat_num counts DUT patterns (channels), so images = pat_num / 1 or / 3:
  mode 0 (gray) : 1 scan per image  -> grayscale JPEG
  mode 1 (rgb)  : 3 scans per image -> color JPEG (Y, Cb, Cr, one scan each)
One JPEG is written per image: jpg/output_<i>.jpg

The header uses the lab's own tables: DQT = 2^S(u,v), DHT = dc/ac_huffman_lut.txt.
Byte stuffing (FF -> FF 00) is added here because the design outputs raw bytes.

Usage: python3 raw2jpg.py [-i input.txt] [-r output.txt] [-d out_dir] [--show W | --no-show]
  Each image is also decoded (pure Python, no Pillow needed) and printed in the
  terminal with 24-bit color, width 64 by default.
"""
import argparse
import sys
import struct
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE / 'src'
SIZE = 128
BLOCKS = (SIZE // 8) ** 2


# ------------------------------------------------------------------
# Tables
# ------------------------------------------------------------------
def load_tables():
    zz = [tuple(map(int, l.split()[1:3])) for l in (SRC / 'zigzag_table.txt').read_text().splitlines()[1:] if l.strip()]
    shift = {}
    for l in (SRC / 'shift_table.txt').read_text().splitlines()[1:]:
        if l.strip():
            u, v, s = map(int, l.split())
            shift[(u, v)] = s
    dc = {}
    for l in (SRC / 'dc_huffman_lut.txt').read_text().splitlines()[1:]:
        if l.strip():
            f = l.split()
            dc[int(f[0])] = f[3]
    ac = {}
    for l in (SRC / 'ac_huffman_lut.txt').read_text().splitlines()[1:]:
        if l.strip():
            f = l.split()
            ac[int(f[0], 16)] = f[5]
    return zz, shift, dc, ac


def dht_segment(cls_id, table):
    # BITS / HUFFVAL from code lengths, then check canonical codes match the lut
    syms = sorted(table, key=lambda s: (len(table[s]), table[s]))
    bits = [0] * 16
    for s in syms:
        bits[len(table[s]) - 1] += 1
    code, k = 0, 0
    for n in range(1, 17):
        for _ in range(bits[n - 1]):
            assert format(code, f'0{n}b') == table[syms[k]], f'table not canonical at symbol {syms[k]:02X}'
            code += 1
            k += 1
        code <<= 1
    body = bytes([cls_id]) + bytes(bits) + bytes(syms)
    return b'\xff\xc4' + struct.pack('>H', len(body) + 2) + body


# ------------------------------------------------------------------
# Scan decoding (256 blocks -> byte length + 128x128 pixel plane)
# ------------------------------------------------------------------
C = [
    [181, 181, 181, 181, 181, 181, 181, 181],
    [251, 213, 142, 50, -50, -142, -213, -251],
    [237, 98, -98, -237, -237, -98, 98, 237],
    [213, -50, -251, -142, 142, 251, 50, -213],
    [181, -181, -181, 181, 181, -181, -181, 181],
    [142, -251, 50, 213, -213, -50, 251, -142],
    [98, -237, 237, -98, -98, 237, -237, 98],
    [50, -142, 213, -251, 251, -213, 142, -50]
]


class BitReader:
    def __init__(self, data, pos):
        self.data, self.bit = data, pos * 8

    def read(self, n):
        v = 0
        for _ in range(n):
            byte = self.data[self.bit >> 3]
            v = (v << 1) | ((byte >> (7 - (self.bit & 7))) & 1)
            self.bit += 1
        return v

    def amp(self, size):
        v = self.read(size)
        return v - (1 << size) + 1 if size and v < (1 << (size - 1)) else v

    def huff(self, rev):
        code = ''
        while code not in rev:
            code += str(self.read(1))
            assert len(code) <= 16, f'invalid Huffman code at bit {self.bit}'
        return rev[code]


def idct(D):
    # inverse of the lab's integer DCT: P'(x,y) = sum C(u,x) C(v,y) D(u,v) / 2^18
    T = [[sum(C[v][y] * D[v][u] for v in range(8) if D[v][u]) for y in range(8)] for u in range(8)]
    return [[min(255, max(0, round(sum(C[u][x] * T[u][y] for u in range(8)) / (1 << 18)) + 128))
             for x in range(8)] for y in range(8)]


def decode_scan(data, pos, zz, shift, dc, ac):
    rdc = {v: k for k, v in dc.items()}
    rac = {v: k for k, v in ac.items()}
    br = BitReader(data, pos)
    plane = [[0] * SIZE for _ in range(SIZE)]
    pred = 0
    for b in range(BLOCKS):
        Z = [0] * 64
        pred += br.amp(br.huff(rdc))
        Z[0] = pred
        k = 1
        while k < 64:
            sym = br.huff(rac)
            if sym == 0x00:
                break
            if sym == 0xF0:
                k += 16
                continue
            k += sym >> 4
            assert k < 64, f'AC index overflow at bit {br.bit}'
            Z[k] = br.amp(sym & 0xF)
            k += 1
        D = [[0] * 8 for _ in range(8)]  # D[v][u], dequantized
        for i, (u, v) in enumerate(zz):
            D[v][u] = Z[i] << shift[(u, v)]
        blk = idct(D)
        bx, by = b % 16, b // 16
        for y in range(8):
            plane[by * 8 + y][bx * 8:bx * 8 + 8] = blk[y]
    nbit = br.bit - pos * 8
    nbyte = (nbit + 7) // 8
    if nbit % 8:
        pad = data[pos + nbyte - 1] & ((1 << (8 - nbit % 8)) - 1)
        assert pad == (1 << (8 - nbit % 8)) - 1, 'end-of-image padding is not all 1'
    return nbyte, plane


# ------------------------------------------------------------------
# Terminal preview: one upper-half block (U+2580) = 2 pixels (fg = upper, bg = lower)
# ------------------------------------------------------------------
def to_rgb(planes):
    if len(planes) == 1:
        return [[(p, p, p) for p in row] for row in planes[0]]
    clip = lambda v: min(255, max(0, round(v)))
    return [[(clip(Y + 1.402 * (Cr - 128)),
              clip(Y - 0.344136 * (Cb - 128) - 0.714136 * (Cr - 128)),
              clip(Y + 1.772 * (Cb - 128)))
             for Y, Cb, Cr in zip(*rows)] for rows in zip(*planes)]


def show(rgb, w):
    rng = [(i * SIZE // w, (i + 1) * SIZE // w) for i in range(w)]

    def px(x, y):
        cells = [rgb[j][i] for j in range(*rng[y]) for i in range(*rng[x])]
        return [sum(c[k] for c in cells) // len(cells) for k in range(3)]

    for y in range(0, w, 2):
        row = ''
        for x in range(w):
            t, b = px(x, y), px(x, y + 1)
            row += f'\x1b[38;2;{t[0]};{t[1]};{t[2]}m\x1b[48;2;{b[0]};{b[1]};{b[2]}m\u2580'
        sys.stdout.flush()
        sys.stdout.buffer.write((row + '\x1b[0m\n').encode('utf-8'))
        sys.stdout.buffer.flush()


# ------------------------------------------------------------------
# JPEG
# ------------------------------------------------------------------
def build_jpeg(scans, zz, shift, dc, ac):
    ncomp = len(scans)
    out = bytearray(b'\xff\xd8')
    out += b'\xff\xe0' + struct.pack('>H', 16) + b'JFIF\x00' + bytes([1, 1, 0, 0, 1, 0, 1, 0, 0])
    q = bytes(1 << shift[zz[i]] for i in range(64))
    out += b'\xff\xdb' + struct.pack('>H', 67) + b'\x00' + q
    sof = struct.pack('>BHHB', 8, SIZE, SIZE, ncomp) + b''.join(bytes([c + 1, 0x11, 0]) for c in range(ncomp))
    out += b'\xff\xc0' + struct.pack('>H', len(sof) + 2) + sof
    out += dht_segment(0x00, dc) + dht_segment(0x10, ac)
    for c, raw in enumerate(scans):
        out += b'\xff\xda' + struct.pack('>HB', 8, 1) + bytes([c + 1, 0x00, 0, 63, 0])
        out += raw.replace(b'\xff', b'\xff\x00')
    out += b'\xff\xd9'
    return bytes(out)


def main():
    ap = argparse.ArgumentParser(description='JPEGLENC raw bytes -> JPEG')
    ap.add_argument('-i', '--input', type=Path, default=HERE / 'input.txt')
    ap.add_argument('-r', '--raw', type=Path, default=HERE / 'output.txt')
    ap.add_argument('-d', '--dir', type=Path, default=HERE / 'jpg')
    ap.add_argument('--show', type=int, default=64, metavar='W', help='terminal preview width (default 64)')
    ap.add_argument('--no-show', dest='show', action='store_const', const=0, help='disable terminal preview')
    args = ap.parse_args()

    with open(args.input) as f:
        pat_num, mode = int(f.readline()), int(f.readline())
    assert mode in (0, 1), f'mode = {mode}, expect 0 (gray) or 1 (rgb)'
    nch = 3 if mode else 1
    assert pat_num % nch == 0, f'pat_num = {pat_num} is not a multiple of {nch}'
    img_num = pat_num // nch

    zz, shift, dc, ac = load_tables()
    data = bytes(int(t, 16) for t in args.raw.read_text().split())

    scans, planes, pos = [], [], 0
    while pos < len(data):
        n, plane = decode_scan(data, pos, zz, shift, dc, ac)
        scans.append(data[pos:pos + n])
        planes.append(plane)
        print(f'scan {len(scans) - 1}: {n} bytes')
        pos += n
    assert len(scans) == pat_num, f'{len(scans)} scans, expect pat_num = {pat_num} ({args.input.name} header)'

    args.dir.mkdir(parents=True, exist_ok=True)
    for i in range(img_num):
        out = args.dir / f'output_{i}.jpg'
        out.write_bytes(build_jpeg(scans[i * nch:(i + 1) * nch], zz, shift, dc, ac))
        print(f'image {i} ({"rgb" if mode else "gray"}) -> {out.name}')
        if args.show:
            show(to_rgb(planes[i * nch:(i + 1) * nch]), min(SIZE, args.show - args.show % 2))


if __name__ == '__main__':
    main()
