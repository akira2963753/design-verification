#!/usr/bin/env python3
"""Renumber Fig / Table captions of a spec.html in document order.

Captions look like  <p class="cap">Fig 3. ...</p>  or  <summary>Table 7. ...</summary>.
A caption may use a placeholder instead of a number (Fig @F_flow. / Table @T_io.).
In-text references ("見 Table @T_io", "(Fig 5)") are rewritten to the new numbers:
  - placeholder references map to their caption
  - numeric references map from the old caption number to the new one
Text inside <script> is left untouched except caption placeholders never appear there.

Usage: python renumber.py docs/spec.html
"""
import re
import sys

path = sys.argv[1]
s = open(path, encoding='utf-8').read()

cap_re = re.compile(r'(class="cap">|<summary>)(Fig|Table) ([0-9]+|@\w+)\.')
script = re.search(r'<script>.*</script>', s, re.S)
body_end = script.start() if script else len(s)
body, tail = s[:body_end], s[body_end:]

# protect captions, turn numeric in-text refs into @oldN placeholders
spans = [(m.start(), m.end()) for m in cap_re.finditer(body)]
in_cap = lambda pos: any(a <= pos < b for a, b in spans)
out, last = [], 0
for m in re.finditer(r'(Fig|Table) ([0-9]+)', body):
    if in_cap(m.start()):
        continue
    out.append(body[last:m.start()] + f'{m.group(1)} @old{m.group(2)}')
    last = m.end()
out.append(body[last:])
body = ''.join(out)

cnt = {'Fig': 0, 'Table': 0}
mapping = {}
def renum(m):
    kind, old = m.group(2), m.group(3)
    cnt[kind] += 1
    key = (kind, '@old' + old) if old.isdigit() else (kind, old)
    if key in mapping:
        sys.exit(f'duplicate caption label: {kind} {old}')
    mapping[key] = cnt[kind]
    return f'{m.group(1)}{kind} {cnt[kind]}.'
body = cap_re.sub(renum, body)

missing = []
def ref(m):
    key = (m.group(1), m.group(2))
    if key in mapping:
        return f'{m.group(1)} {mapping[key]}'
    missing.append(key)
    return f'{m.group(1)} {m.group(2)[4:]}' if m.group(2).startswith('@old') else m.group(0)
body = re.sub(r'(Fig|Table) (@\w+)', ref, body)

open(path, 'w', encoding='utf-8', newline='\n').write(body + tail)
print(f"Fig 1~{cnt['Fig']}, Table 1~{cnt['Table']}")
for k in missing:
    print('WARNING: reference without caption:', *k)
