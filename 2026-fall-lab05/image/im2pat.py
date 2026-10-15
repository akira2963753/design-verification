#!/usr/bin/env python3
"""Convert images to a JPEGLENC input file.

Each image is center-cropped to a square and resized to 128x128.

input.txt format:
  line 1 : pat_num (number of DUT patterns = images x 1 (gray) or x 3 (rgb))
  line 2 : mode    (0 = gray, 1 = rgb)
  then for each image:
    gray : 16384 lines (Y)
    rgb  : 16384 lines Y, 16384 lines Cb, 16384 lines Cr   (JFIF YCbCr)
  Each pixel line is 2-digit hex in raster order (k = 128*y + x).

Default output : pattern/input_gray.txt or pattern/input_rgb.txt
Preview PNGs   : preview/gray/<name>_gray.png, preview/rgb/<name>_{Y,Cb,Cr}.png

Usage:
  python3 im2pat.py                    all images in src/, gray
  python3 im2pat.py --rgb              all images in src/, rgb
  python3 im2pat.py --rgb src/scared.jpg   single image
  python3 im2pat.py -o ../00_TESTBED/input.txt
"""
import argparse
from pathlib import Path
from PIL import Image

SIZE = 128
EXTS = {'.png', '.jpg', '.jpeg', '.bmp', '.webp'}
HERE = Path(__file__).resolve().parent
IMG_DIR = HERE / 'src'
PAT_DIR = HERE / 'pattern'
PRE_DIR = HERE / 'preview'


def load(src: Path) -> Image.Image:
    img = Image.open(src).convert('RGB')
    w, h = img.size
    s = min(w, h)
    img = img.crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s))
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def channels(src: Path, rgb: bool):
    img = load(src)
    if rgb:
        chs = list(zip(('Y', 'Cb', 'Cr'), img.convert('YCbCr').split()))
        pre = PRE_DIR / 'rgb'
    else:
        chs = [('gray', img.convert('L'))]
        pre = PRE_DIR / 'gray'
    pre.mkdir(parents=True, exist_ok=True)
    for name, ch in chs:
        ch.save(pre / f'{src.stem}_{name}.png')
    return [ch for _, ch in chs]


def main():
    ap = argparse.ArgumentParser(description='image -> JPEGLENC input.txt')
    ap.add_argument('--rgb', action='store_true', help='mode 1: Y/Cb/Cr (default mode 0: gray)')
    ap.add_argument('-o', '--out', type=Path, help='output file')
    ap.add_argument('imgs', nargs='*', type=Path, help='images (default: all in src/)')
    args = ap.parse_args()

    srcs = args.imgs or sorted(p for p in IMG_DIR.iterdir() if p.suffix.lower() in EXTS)
    assert srcs, 'no image found'
    mode = 1 if args.rgb else 0
    out = args.out or PAT_DIR / f'input_{"rgb" if args.rgb else "gray"}.txt'

    pat_num = len(srcs) * (3 if args.rgb else 1)
    lines = [str(pat_num), str(mode)]
    for i, src in enumerate(srcs):
        for ch in channels(src, args.rgb):
            pix = ch.tobytes()
            assert len(pix) == SIZE * SIZE
            lines += [f'{p:02X}' for p in pix]
        print(f'image {i}: {src.name}')

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text('\n'.join(lines) + '\n', newline='\n')
    print(f'-> {out} (pat_num = {pat_num}, mode = {mode})')


if __name__ == '__main__':
    main()
