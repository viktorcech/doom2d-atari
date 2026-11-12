#!/usr/bin/env python3
"""doom2d - guard against XEX segments landing in reserved RAM.

Some 6502 address ranges hold no loadable code/data at runtime; anything the
XEX loads there is lost or clobbered, giving a silent "black screen" or a
KIL-halt much later. This parses the segmented XEX and fails the build if a
segment overlaps any reserved range, so the boundary is caught at build time
(mads has no such check, and separate `org`s don't trip its overflow guard).

DOOM2D memory map (see source/constants.asm + main.asm):
  $0580-$06FF  INI staging: upload procs at $0580 (each INI runs, then the
               next segment overwrites it - overlap here is BY DESIGN),
               generic_upload $0630, early_init $0690: page 6 may be reused
               by a segment loaded after the last INI (lk_walk $0600).
  $0700-$08FF  ATR boot loader + sector buffer (must stay untouched while
               the XEX streams from disk - the loader IS the streamer).
  $2000-$83FF  main segment (mads' own `ert *>$8400` guards its growth).
  $6000-$8FFF  INI staging for asset uploads (palette/tiles/sprites/sky/...)
               - consumed during load, overlap here is BY DESIGN.
  $9000-$9FFF  MEMAC-A window: CPU writes go to VBXE VRAM, not RAM ->
               nothing loadable may target it.
  $A000-$BFFF  GTIA-9 sky rows ($A000, 5760 B) + display lists ($B800/$BC00)
               (BASIC ROM is disabled by early_init via PORTB).
  $C000-$FFFF  Atari OS ROM - writes from the XEX loader land nowhere.

Usage:  python check_xex.py bin/doom2d.xex
"""
import os
import re
import struct
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))

# (lo, hi, description) - inclusive byte ranges no XEX segment may touch.
RESERVED = [
    (0x0700, 0x08FF, "ATR boot loader + sector buffer"),
    (0x9000, 0x9FFF, "MEMAC-A window (VBXE VRAM, not RAM)"),
    (0xC000, 0xFFFF, "Atari OS ROM"),
]

# Ranges where later-segment-overwrites-earlier is the INTENDED load-time
# staging pattern: overlap between two segments is only an error if the
# overlapping bytes lie outside every staging range.
STAGING = [
    (0x0580, 0x05FF, "INI upload procs"),
    (0x6000, 0x8FFF, "asset upload staging"),
]
# Load-time code (generic_upload $0630, early_init $0690) that only INIs
# run: a segment loaded after the LAST INI may reuse it (en_look's lk_walk).
AFTER_INI = [
    (0x0600, 0x06FF, "INI code, free after the last INI"),
]


def in_staging(lo, hi):
    return any(lo >= slo and hi <= shi for slo, shi, _ in STAGING)


def vram_check():
    """--vram: every INI upload (uploads.asm) vs. its files, upload overlaps, and
    every sprite (sprite_defs.asm spr_off_*) / tile (blit_tile formula) against
    the bytes really uploaded. Bytes uploaded past a file's end are whatever the
    $6000 staging RAM held: garbage."""
    src = os.path.join(ROOT, 'source')
    consts = {}
    for line in open(os.path.join(src, 'constants.asm')):
        m = re.match(r'(\w+)\s*=\s*\$([0-9A-Fa-f]+)', line)
        if m:
            consts[m.group(1).upper()] = int(m.group(2), 16)
    text = open(os.path.join(src, 'uploads.asm')).read()
    files, label = {}, None
    for line in text.splitlines():
        m = re.match(r"(\w+)?\s+ins\s+'([^']+)'", line)
        pad = re.match(r'\s+:(\d+)\s+dta\s+0\b', line)
        if m:
            label = m.group(1) or label
            files.setdefault(label, []).append(m.group(2))
        elif pad and label:
            files.setdefault(label, []).append(int(pad.group(1)))   # zero padding
        elif re.match(r'(\w+)\s*$', line):
            label = line.strip()

    def blob_of(parts):
        return b''.join(bytes(p) if isinstance(p, int) else
                        open(os.path.normpath(os.path.join(src, p)), 'rb').read()
                        for p in parts)
    ups = []                                # (lo, hi_excl, backed_hi_excl, name)
    bad = []
    for m in re.finditer(r'\.proc (\w+)(.*?)\.endp', text, re.S):
        body = m.group(2)
        lab = re.search(r'lda #<(\w+)', body)
        bank = re.search(r'lda #BANK_EN\+(\$?\w+)', body)
        if not (lab and bank and 'generic_upload' in body):
            continue
        b = bank.group(1)
        b = int(b[1:], 16) if b.startswith('$') else consts[b.upper()]
        cnt = int(re.search(r'lda #(\d+)[^\n]*\n\s*sta uc_cnt', body).group(1))
        last = int(re.search(r'lda #(\d+)[^\n]*\n\s*sta uc_lastpg', body).group(1))
        size = (cnt - 1) * 4096 + last * 256
        fsize = len(blob_of(files[lab.group(1)]))
        lo = b * 4096
        ups.append((lo, lo + size, lo + min(size, fsize), m.group(1)))
        note = ''
        if size > fsize:
            note = f'  <-- {size - fsize} B past the file end = GARBAGE'
            bad.append(m.group(1))
        elif size < fsize:
            note = f'  <-- {fsize - size} B of the file NOT uploaded'
            bad.append(m.group(1))
        print(f'  ${lo:06X}-${lo + size - 1:06X} {m.group(1):22s} '
              f'upload {size:5d} B, files {fsize:5d} B{note}')
    for i in range(len(ups)):
        for j in range(i + 1, len(ups)):
            a, b2 = ups[i], ups[j]
            if a[0] < b2[1] and b2[0] < a[1]:
                print(f'  OVERLAP {a[3]} / {b2[3]}: '
                      f'${max(a[0], b2[0]):06X}-${min(a[1], b2[1]) - 1:06X}')
                bad.append(a[3])

    real = []                               # file-backed ranges, adjacent ones merged
    for lo, _, bhi, _ in sorted(ups):
        if real and lo <= real[-1][1]:
            real[-1][1] = max(real[-1][1], bhi)
        else:
            real.append([lo, bhi])

    def backed(lo, n):
        return any(r[0] <= lo and lo + n <= r[1] for r in real)

    # sprites: VRAM = bank:(hi+$10):lo (vbxe.asm blit_sprite)
    tabs, cur = {}, None
    for line in open(os.path.join(src, 'sprite_defs.asm')):
        m = re.match(r'(spr_off_lo|spr_off_hi|spr_off_bank|spr_w|spr_h)\s*$', line)
        if m:
            cur = m.group(1)
            tabs[cur] = []
            continue
        m = re.match(r'\s+(?::(\d+)\s+)?dta\s+([<>]?)\$?([0-9A-Fa-f]+)\s*;\s*(\S+)', line)
        if cur and m:
            v = int(m.group(3), 16 if '$' in line.split(';')[0] else 10)
            v = v & 255 if m.group(2) == '<' else v >> 8 if m.group(2) == '>' else v
            tabs[cur] += [(v, m.group(4))] * int(m.group(1) or 1)
        elif cur and line.strip() and not line.strip().startswith(';'):
            cur = None
    nspr = 0
    for k, (lo, name) in enumerate(tabs['spr_off_lo']):
        hi, bk = tabs['spr_off_hi'][k][0], tabs['spr_off_bank'][k][0]
        n = tabs['spr_w'][k][0] * tabs['spr_h'][k][0]
        adr = (bk << 16) + (((hi + 0x10) & 255) << 8) + lo
        nspr += 1
        if not backed(adr, n):
            print(f'  SPRITE {k:3d} {name:24s} ${adr:06X}+{n} not on uploaded file data')
            bad.append(name)
    # tiles (vbxe.asm blit_tile): 0-15 $01:t:00, 16-27 $03:t+$10:00, 28+ $06:t-28:00
    ntiles = 43
    for t in range(ntiles):
        adr = (0x010000 + t * 256 if t < 16 else
               0x030000 + (t + 0x10) * 256 if t < 28 else 0x060000 + (t - 28) * 256)
        if not backed(adr, 256):
            print(f'  TILE {t:2d} ${adr:06X} not on uploaded file data')
            bad.append(f'tile {t}')
    print(f'  VRAM check: {len(ups)} uploads, {nspr} sprites, {ntiles} tiles, '
          f'{len(bad)} problem(s).')
    if '--png' in sys.argv:
        # what the game sees: VRAM image from the upload files, 4x, to tools/out
        from PIL import Image, ImageDraw
        vram = bytearray(0x80000)
        hole = bytearray(0x80000)               # 1 = not file-backed
        for lo, hi, bhi, name in ups:
            hole[lo:hi] = b'\1' * (hi - lo)
        for m in re.finditer(r'\.proc (\w+)(.*?)\.endp', text, re.S):
            lab = re.search(r'lda #<(\w+)', m.group(2))
            u = [x for x in ups if x[3] == m.group(1)]
            if not (lab and u):
                continue
            blob = blob_of(files[lab.group(1)])
            lo, _, bhi, _ = u[0]
            vram[lo:bhi] = blob[:bhi - lo]
            hole[lo:bhi] = bytes(bhi - lo)
        p = open(os.path.join(ROOT, 'data', 'palette.bin'), 'rb').read()
        pal = [(p[i] << 1, p[256 + i] << 1, p[512 + i] << 1) for i in range(256)]

        def cell(adr, w, h):
            im = Image.new('RGB', (w, h), (40, 40, 48))
            for y in range(h):
                for x in range(w):
                    a = adr + y * w + x
                    if hole[a]:
                        im.putpixel((x, y), (255, 0, 255))
                    elif vram[a]:
                        im.putpixel((x, y), pal[vram[a]])
            return im
        items = [(f'T{t}', (0x010000 + t * 256 if t < 16 else 0x030000 + (t + 0x10) * 256
                            if t < 28 else 0x060000 + (t - 28) * 256), 16, 16)
                 for t in range(ntiles)]
        for k, (lo, name) in enumerate(tabs['spr_off_lo']):
            hi, bk = tabs['spr_off_hi'][k][0], tabs['spr_off_bank'][k][0]
            items.append((f'{k} {name}', (bk << 16) + (((hi + 0x10) & 255) << 8) + lo,
                          tabs['spr_w'][k][0], tabs['spr_h'][k][0]))
        cols, cw, ch = 12, 40, 52                # grid cell in native pixels
        sheet = Image.new('RGB', (cols * cw, -(-len(items) // cols) * ch), (16, 16, 20))
        for i, (_, adr, w, h) in enumerate(items):
            sheet.paste(cell(adr, w, h), ((i % cols) * cw + 2, (i // cols) * ch + 2))
        sheet = sheet.resize((sheet.width * 4, sheet.height * 4), Image.NEAREST)
        d = ImageDraw.Draw(sheet)
        for i, (label, *_) in enumerate(items):
            d.text(((i % cols) * cw * 4 + 4, (i // cols) * ch * 4 + ch * 4 - 14),
                   label[:20], fill=(255, 255, 255))
        out = os.path.join(ROOT, 'tools', 'out', 'vram_assets.png')
        os.makedirs(os.path.dirname(out), exist_ok=True)
        sheet.save(out)
        print(f'  -> {out} (magenta = not uploaded from a file)')
    sys.exit(1 if bad else 0)


def unused_check():
    """--unused: global labels (source/*.asm, gen/) that nothing else names,
    with their size in the main segment (bin/doom2d.lab: up to the next label)
    - candidates for deletion (dead code / data); check each before deleting
    (a fall-through into it, an `ert`, a table read with an offset)."""
    src = os.path.join(ROOT, 'source')
    files = [os.path.join(src, f) for f in os.listdir(src) if f.endswith('.asm')]
    files += [os.path.join(src, 'gen', f) for f in os.listdir(os.path.join(src, 'gen'))]
    text = {f: open(f, encoding='latin-1').read() for f in files}
    lab = {}
    for line in open(os.path.join(ROOT, 'bin', 'doom2d.lab'), encoding='latin-1'):
        p = line.split()
        if len(p) == 3 and re.fullmatch(r'[0-9A-F]{4}', p[1]):
            lab[p[2]] = int(p[1], 16)
    addrs = sorted(set(a for n, a in lab.items() if '.' not in n))
    words = {}
    for t in text.values():
        for w in re.findall(r'[A-Za-z_][A-Za-z0-9_]*', re.sub(r';.*', '', t)):
            w = w.upper()
            words[w] = words.get(w, 0) + 1
    out = []
    for name, a in lab.items():
        if '.' in name or not 0x2000 <= a < 0x8400 or words.get(name, 0) > 1:
            continue
        nxt = next((b for b in addrs if b > a), a)
        out.append((nxt - a, name, a))
    for size, name, a in sorted(out, reverse=True):
        print(f'  {size:5d} B  ${a:04X}  {name}')
    print(f'  {sum(s for s, *_ in out)} B in {len(out)} labels named once')
    sys.exit(0)


def main():
    if '--unused' in sys.argv:
        unused_check()
    if '--vram' in sys.argv:
        vram_check()
    data = open(sys.argv[1], 'rb').read()
    i = 0
    if data[0:2] == b'\xff\xff':
        i = 2
    bad = []
    segs = []                               # (start, end) of every data segment
    last_ini = -1                           # segs index the last INI vector follows
    while i + 4 <= len(data):
        start, end = struct.unpack_from('<HH', data, i)
        i += 4
        if start == 0xFFFF:                  # optional segment-header marker
            continue
        seg_len = (end - start + 1) & 0xFFFF
        # INIT ($02E2) and RUN ($02E0) vectors are tiny 2-byte segments that
        # legitimately sit in the OS page-2 vector region -- skip them in the
        # overlap check so they don't false-positive against each other or
        # against a data segment that happens to be page-2 adjacent.
        if start not in (0x02E0, 0x02E2):
            segs.append((start, end))
        elif start == 0x02E2:
            last_ini = len(segs) - 1
        for lo, hi, why in RESERVED:
            if not (end < lo or start > hi):
                bad.append((start, end, lo, hi, why))
        i += seg_len

    # Inter-segment overlap: two XEX segments that target the same RAM byte
    # silently let the later one win at load time; outside the staging
    # ranges that is a latent crash (two symbols sharing storage).
    overlaps = []
    for a in range(len(segs)):
        sa, ea = segs[a]
        for b in range(a + 1, len(segs)):
            sb, eb = segs[b]
            if sa <= eb and sb <= ea:
                lo = max(sa, sb)
                hi = min(ea, eb)
                if in_staging(lo, hi):
                    continue                # staged uploads reuse RAM by design
                if b > last_ini and any(lo >= slo and hi <= shi
                                        for slo, shi, _ in AFTER_INI):
                    continue                # loaded after every INI ran
                overlaps.append((sa, ea, sb, eb, lo, hi))

    if bad or overlaps:
        print('XEX BOUNDARY CHECK FAILED:')
        for s, e, lo, hi, why in bad:
            print(f'  segment ${s:04X}-${e:04X} overlaps reserved '
                  f'${lo:04X}-${hi:04X} ({why}) -> lost/clobbered at runtime.')
        for sa, ea, sb, eb, lo, hi in overlaps:
            print(f'  segment ${sa:04X}-${ea:04X} overlaps segment '
                  f'${sb:04X}-${eb:04X} on ${lo:04X}-${hi:04X} '
                  f'({hi - lo + 1} B) -> later load wins; runtime sharing = latent crash.')
        sys.exit(1)
    ranges = ', '.join(f'${lo:04X}-${hi:04X}' for lo, hi, _ in RESERVED)
    print(f'  XEX boundary OK (nothing in {ranges}; '
          f'no inter-segment overlap outside staging).')
    if '--map' in sys.argv:
        # resident memory map: merged segments (staging excluded) + the gaps
        res = sorted((s, e) for s, e in segs if not in_staging(s, e))
        merged = []
        for s, e in res:
            if merged and s <= merged[-1][1] + 1:
                merged[-1][1] = max(merged[-1][1], e)
            else:
                merged.append([s, e])
        print('  loaded:', ', '.join(f'${s:04X}-${e:04X}' for s, e in merged))
        prev = 0x0900
        for s, e in merged:
            if s > prev and s - prev >= 64:
                print(f'  free  ${prev:04X}-${s - 1:04X} ({s - prev} B, not loaded - '
                      f'check BSS/.ds before use)')
            prev = max(prev, e + 1)


if __name__ == '__main__':
    main()
