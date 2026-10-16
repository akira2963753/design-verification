#!/usr/bin/env python3
"""Render every <figure> of a spec.html at 2x and save one PNG per figure.

Uses Edge/Chrome headless (Windows). Each figure is rendered alone so text
overflow, overlaps and clipped labels are easy to spot when reading the PNGs.
SVG <text> whose bounding box leaves the viewBox is outlined in red.

Usage: python figcheck.py docs/spec.html [out_dir]   (default out_dir: C:/tmp/figcheck)
"""
import os
import re
import subprocess
import sys
from pathlib import Path

src = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2] if len(sys.argv) > 2 else 'C:/tmp/figcheck')
out.mkdir(parents=True, exist_ok=True)

BROWSERS = [
    r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    r'C:\Program Files\Google\Chrome\Application\chrome.exe',
]
browser = next((b for b in BROWSERS if os.path.exists(b)), None)
if not browser:
    sys.exit('no Edge/Chrome found')

html = src.read_text(encoding='utf-8')
n_fig = len(re.findall(r'<figure>', html))
inject = '''<style>main > *:not(figure){display:none!important} nav#toc,#tocbtn{display:none!important}
figure{margin:0 0 40px!important}</style>
<script>addEventListener('load',()=>{const k=+location.hash.slice(1);
document.querySelectorAll('figure').forEach((f,i)=>{if(i!==k)f.style.display='none'});
document.querySelectorAll('svg').forEach(svg=>{const vb=svg.viewBox.baseVal;if(!vb||!vb.width)return;
svg.querySelectorAll('text').forEach(t=>{if(t.getAttribute('transform'))return;const b=t.getBBox();
if(b.x<vb.x-.5||b.y<vb.y-.5||b.x+b.width>vb.x+vb.width+.5||b.y+b.height>vb.y+vb.height+.5){
const r=document.createElementNS('http://www.w3.org/2000/svg','rect');
['x','y','width','height'].forEach(a=>r.setAttribute(a,b[a]));r.setAttribute('fill','none');
r.setAttribute('stroke','red');svg.appendChild(r);}})})});</script>'''
tmp = src.with_name('_figcheck.html')
tmp.write_text(html.replace('</head>', inject + '</head>'), encoding='utf-8')
try:
    for i in range(n_fig):
        png = out / f'fig_{i + 1:02d}.png'
        subprocess.run([browser, '--headless=new', '--disable-gpu', '--hide-scrollbars',
                        '--virtual-time-budget=8000', '--force-device-scale-factor=2',
                        '--window-size=1100,1400', f'--screenshot={png}',
                        tmp.as_uri() + f'#{i}'], capture_output=True)
        try:
            from PIL import Image
            import numpy as np
            im = Image.open(png)
            g = np.asarray(im.convert('L'))
            rows = np.where(g.min(axis=1) < 245)[0]
            cols = np.where(g.min(axis=0) < 245)[0]
            if len(rows) and len(cols):
                im.crop((max(cols.min() - 20, 0), max(rows.min() - 20, 0),
                         min(cols.max() + 20, im.width), min(rows.max() + 20, im.height))).save(png)
        except ImportError:
            pass
        print(png)
finally:
    tmp.unlink(missing_ok=True)
