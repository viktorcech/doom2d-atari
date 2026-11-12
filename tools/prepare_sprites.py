#!/usr/bin/env python3
"""
Monster sprites for the Atari VBXE port, straight from Doom 2D Forever.

Reads the frame sheets (git/DF-Assets-master/GameWAD/MTEXTURES/*.tga) and the
animation data of g_monsters.pas (frame size and count, AnimSpeed, AnimDelta,
the hit rect), scales every frame to half size (the world is drawn at 1:2),
crops it to its pixels and writes:

  data/mon_spr0.bin, ...     the packed frames per VRAM region (8bpp, 0 = transparent)
  source/gen/mon_frames.asm        frame tables (RAM)
  source/gen/mon_anims.asm         animation + weapon tables (RAM)
  source/gen/mon_upload.asm        the INI segments that copy mon_spr.bin to VRAM
  tools/out/mon_sprites.png  preview, 4x

Placement follows TMonster.Draw: a frame is drawn at Obj + AnimDelta (facing
right); facing left it is mirrored around the hit rect, unless the type has
its own _L sheet. Offsets are stored relative to the engine's position
(en_x = hit centre - 8, en_y = feet).

Usage: python tools/prepare_sprites.py
"""

import math
import os
import re

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
GM_PAS = os.path.join(ROOT, 'git', 'Doom2D-Forever-master', 'src', 'game', 'g_monsters.pas')
MTEX = os.path.join(ROOT, 'git', 'DF-Assets-master', 'GameWAD', 'MTEXTURES')
DATA = os.path.join(ROOT, 'data')
GEN = os.path.join(ROOT, 'source', 'gen')
OUT = os.path.join(ROOT, 'tools', 'out')

REGIONS = [(0x034000, 0x044000),    # free VRAM below the sound data
           (0x078000, 0x07F000),    # between the tileset and the XDL
           (0x05E000, 0x061000),    # between the map and the bg canvas
           (0x011000, 0x012000),    # below the animated textures (VRAM_ANIM);
           (0x013000, 0x014000)]    # $012000: sounds2vram.py EXTRA (SECRET)
for _lo, _ in REGIONS:          # generic_upload writes whole 4K banks from their start
    assert _lo % 4096 == 0
CHUNK = 12288                   # one INI load at $6000-$8FFF

# engine en_type order (EN_ZOMBIE .. EN_LOSTSOUL in sprite_defs.asm)
TYPES = ['ZOMBY', 'IMP', 'DEMON', 'CACO', 'SERG', 'BARON', 'SOUL']
ANIMS = ['SLEEP', 'GO', 'DIE', 'MESS', 'ATTACK', 'ATTACK2', 'PAIN']
LOOP = [1, 1, 0, 0, 0, 0, 0]    # ANIMTABLE.loop
ANIM_DIE, ANIM_MESS = 2, 3

DOOMER = os.path.join(ROOT, 'git', 'DF-Assets-master', 'DoomerWAD', 'TEXTURES')
EXT = {'DIE1': '.png', 'DIE2': '.png'}
PLAYER1_COLOR = (64, 175, 48)   # g_player.pas PLAYER1_DEF_COLOR
PL_CX = 5                       # hit centre = zpx + PL_W/2
# per ANIM slot: (resource, frames, waitcount, loop) from MODEL.txt; slots
# STAND, WALK, DIE1, DIE2 (gibs), ATTACK, -, PAIN
PLAYER_ANIMS = [('STAND', 1, 1, 1), ('WALK', 4, 8, 1), ('DIE1', 7, 10, 0),
                ('DIE2', 9, 6, 0), ('ATTACK', 1, 3, 0), (None, 0, 0, 0), ('PAIN', 1, 1, 0)]
WEAPONS = os.path.join(ROOT, 'git', 'DF-Assets-master', 'GameWAD', 'WEAPONS')
# by zpwcur (constants.asm WP_*): (texture, MODEL.txt points key); the fist
# draws nothing
PLAYER_WEAPONS = [None, ('HGUN', 'HGun'), ('SG', 'Sg'), ('MGUN', 'MGun'),
                  ('RKT', 'Rkt'), ('PLZ', 'Plz'), ('BFG', 'BFG'), ('CSAW', 'CSaw')]
TEXTURES = os.path.join(ROOT, 'git', 'DF-Assets-master', 'GameWAD', 'TEXTURES')
# projectiles in flight (g_weapons.pas): name, texture, frames, _L copies
SMALL_PROJ = [('ROCKET_PROJ', 'BROCKET', 4, True), ('PLASMA_PROJ', 'BPLASMA', 2, False),
              ('BFG_PROJ', 'BBFG', 2, False), ('IMP_FIRE', 'BIMPFIRE', 2, False),
              ('CACO_FIRE', 'BCACOFIRE', 2, False), ('BARON_FIRE', 'BBARONFIRE', 2, True)]
# by pk_type (constants.asm PK_*): texture, frames, ping-pong, ticks a frame
# (g_items.pas, 0 = still), the item rect W x H (ITEMSIZE)
ITEMS = [('MED1', 1, 0, 0, 14, 15), ('CLIP', 1, 0, 0, 9, 11), ('MED2', 1, 0, 0, 28, 19),
         ('ARMORGREEN', 3, 1, 20, 31, 16), ('ARMORBLUE', 3, 1, 20, 31, 16),
         ('SBLUE', 4, 1, 15, 25, 25), ('KEYR', 1, 0, 0, 16, 16), ('KEYB', 1, 0, 0, 16, 16),
         ('KEYG', 1, 0, 0, 16, 16), ('SHOTGUN1', 1, 0, 0, 63, 12), ('SHELL1', 1, 0, 0, 15, 7),
         ('PISTOL', 1, 0, 0, 43, 16), ('MGUN', 1, 0, 0, 54, 16), ('RLAUNCHER', 1, 0, 0, 62, 16),
         ('ROCKETS', 1, 0, 0, 54, 21), ('PGUN', 1, 0, 0, 54, 16), ('CELL', 1, 0, 0, 15, 12),
         ('BFG', 1, 0, 0, 61, 36), ('ROCKET', 1, 0, 0, 12, 27), ('BOTTLE', 4, 1, 20, 14, 18),
         ('HELMET', 4, 1, 20, 16, 15), ('SAW', 1, 0, 0, 62, 24),
         ('OXYGEN', 1, 0, 0, 14, 27), ('BPACK', 1, 0, 0, 22, 29)]


def load_palette():
    """VBXE palette (data/palette.bin: 256 R, 256 G, 256 B, 7-bit)."""
    with open(os.path.join(DATA, 'palette.bin'), 'rb') as f:
        data = f.read()
    return [(data[i] << 1, data[256 + i] << 1, data[512 + i] << 1) for i in range(256)]


def find_closest_color(r, g, b, palette, skip_zero=True):
    """Closest palette index (index 0 = transparent is skipped)."""
    best, best_d = 0, None
    for i in range(1 if skip_zero else 0, 256):
        pr, pg, pb = palette[i]
        d = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
        if best_d is None or d < best_d:
            best, best_d = i, d
    return best


def parse_monsters():
    src = open(GM_PAS, encoding='latin-1').read()
    rects = {m[0]: tuple(int(v) for v in m[1:]) for m in re.findall(
        r"Name:'(\w+)'; Rect:\(X:(-?\d+); Y:(-?\d+); Width:(\d+); Height:(\d+)\)", src)}
    pt = r"\(X:\s*(-?\d+);\s*Y:\s*(-?\d+)\s*\)"
    anim = {}
    for m in re.finditer(r"LeftAnim: (True|False);[^;]*;[^;]*; AnimSpeed:\(([\d,\s]+)\);\s*//(\w+)\s*"
                         r"AnimDeltaRight:\s*\((.*?)\);\s*AnimDeltaLeft:\s*\((.*?\))\)\)", src, re.S):
        anim[m[3]] = dict(left=m[1] == 'True',
                          speed=[int(v) for v in m[2].split(',')],
                          dr=[(int(x), int(y)) for x, y in re.findall(pt, m[4])],
                          dl=[(int(x), int(y)) for x, y in re.findall(pt, m[5])])
    frames = {m[0]: (int(m[1]), int(m[2]), int(m[3])) for m in re.findall(
        r"'FRAMES_MONSTER_(\w+)', [^,]+, (\d+), (\d+), (\d+)\)", src)}
    return rects, anim, frames


def half(img):
    """2:1 downscale: a pixel is opaque when 2+ of its 4 sources are; its
    colour is their average."""
    w, h = img.size[0] // 2, img.size[1] // 2
    src = img.load()
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    dst = out.load()
    for y in range(h):
        for x in range(w):
            op = [src[2 * x + i, 2 * y + j] for j in (0, 1) for i in (0, 1)]
            op = [p for p in op if p[3] >= 128]
            if len(op) >= 2:
                dst[x, y] = tuple(sum(p[k] for p in op) // len(op) for k in range(3)) + (255,)
    return out


def main():
    rects, animtab, frames = parse_monsters()
    pal = load_palette()
    flat = [c for rgb in pal for c in rgb]
    flat[0:3] = [255, 0, 255]                       # 0 = transparency only
    palimg = Image.new('P', (1, 1))
    palimg.putpalette(flat)

    blobs = [bytearray() for _ in REGIONS]
    blob_at = {}                                    # pixels -> VRAM address (dedupe)
    recs = []                                       # (addr, w, h, ox, oxm, oy)
    irecs = []                                      # the items' records
    anims = []                                      # per type*8+anim: (r, l, n, spd, flg)
    preview = []                                    # (type, [RGBA frames])

    def sheet_frames(name, img=None, fw=None, n=None, scale=2):
        if img is None:
            fw, fh, n = frames[name]
            img = Image.open(os.path.join(MTEX, name + '.tga')).convert('RGBA')
        fh = img.height
        out = []
        for i in range(n):
            hf = img.crop((i * fw, 0, (i + 1) * fw, fh))
            if scale == 2:
                hf = half(hf)
            box = hf.getchannel('A').getbbox()
            if box is None:
                out.append((hf, 0, 0, 1, 1, b'\0'))
                continue
            cx, cy, x1, y1 = box
            c = hf.crop(box)
            q = c.convert('RGB').quantize(palette=palimg, dither=Image.Dither.NONE)
            px = bytearray(q.tobytes())
            a = c.getchannel('A').tobytes()
            for k in range(len(px)):
                if a[k] < 128:
                    px[k] = 0
                elif px[k] == 0:
                    px[k] = find_closest_color(*c.getpixel((k % c.width, k // c.width))[:3], pal)
            out.append((c, cx, cy, x1 - cx, y1 - cy, bytes(px)))
        return fw, out

    def alloc(w, h, px):
        """VRAM address of these pixels (shared when identical)."""
        key = (w, h, px)
        if key not in blob_at:
            for (lo, hi), blob in zip(REGIONS, blobs):
                if lo + len(blob) + len(px) <= hi:
                    blob_at[key] = lo + len(blob)
                    blob.extend(px)
                    break
            else:
                raise SystemExit('sprites: VRAM regions full')
        return blob_at[key]

    def add(fw, fr, left_full, dy, centre, foot, mirror_left=None, cx0=8):
        """One frame record; mirror_left = left_full of the mirrored draw;
        cx0 = the hit centre's x from the engine's position."""
        img, cx, cy, w, h, px = fr
        key = (w, h, px)
        alloc(w, h, px)
        ox = math.floor(cx0 + (left_full - centre) / 2) + cx
        oxm = 0
        if mirror_left is not None:
            oxm = math.floor(cx0 + (mirror_left - centre) / 2) + (fw // 2 - cx - w)
        oy = math.floor((dy - foot) / 2) + cy
        return blob_at[key], w, h, ox, oxm, oy

    def put(seq):
        """The records of one animation, consecutive; an identical run that
        is already there is shared (MESS = DIE). Returns its first index."""
        for i in range(len(recs) - len(seq) + 1):
            if recs[i:i + len(seq)] == seq:
                return i
        recs.extend(seq)
        return len(recs) - len(seq)

    def monster(t):
            rx, ry, rw, rh = rects[t]
            at = animtab[t]
            centre, foot = rx + rw / 2, ry + rh
            shown = []
            for a, an in enumerate(ANIMS):
                spd = at['speed'][a]
                sheet = f'{t}_{an}'
                if spd and sheet not in frames and a == ANIM_MESS and f'{t}_DIE' in frames:
                    sheet, spd = f'{t}_DIE', at['speed'][ANIM_DIE]   # MESS falls back to DIE
                if not spd or sheet not in frames:
                    anims.append((0, 0, 0, 0, 0))
                    continue
                (dxr, dyr), (dxl, dyl) = at['dr'][a], at['dl'][a]
                fw, fr = sheet_frames(sheet)
                own_left = at['left'] and sheet + '_L' in frames
                if not own_left and dyl != dyr:
                    raise SystemExit(f'{sheet}: mirrored left frames need dy L = R')
                mirror = None if own_left else 2 * rx + rw - fw - dxl
                r0 = put([add(fw, f, dxr, dyr, centre, foot, mirror) for f in fr])
                l0 = r0
                if own_left:
                    fwl, frl = sheet_frames(sheet + '_L')
                    l0 = put([add(fwl, f, dxl, dyl, centre, foot) for f in frl])
                    if len(frl) != len(fr):
                        raise SystemExit(f'{sheet}_L: frame count differs')
                anims.append((r0, l0, len(fr), spd, LOOP[a] | (0 if own_left else 0x80)))
                shown += [f[0] for f in fr]
            anims.append((0, 0, 0, 0, 0))               # pad: index = type*8 + anim
            preview.append((t, shown))

    for t in TYPES:
        monster(t)

    # the barrel (a decoration here, a monster in D2DF): SLEEP and DIE as
    # TMonster.Draw places them, never mirrored
    rx, ry, rw, rh = rects['BARREL']
    at = animtab['BARREL']
    barrel = {}
    for a in (0, ANIM_DIE):
        fw, fr = sheet_frames('BARREL_' + ANIMS[a])
        dx, dy = at['dr'][a]
        barrel[ANIMS[a]] = put([add(fw, f, dx, dy, rx + rw / 2, ry + rh) for f in fr])
        preview.append(('BARREL', [f[0] for f in fr]))

    # the teleport flash (g_game.pas FRAMES_TELEPORT: TEXTURES\TELEPORT, 10 x
    # 64x64): TeleportTo draws it centred on PLAYER_RECT, its top-left 32 px
    # left of the centre and 32 above the middle (26 above the feet)
    img = Image.open(os.path.join(TEXTURES, 'TELEPORT.tga')).convert('RGBA')
    fw, fr = sheet_frames('TELEPORT', img, 64, 10)
    tele = put([add(fw, f, -32, -32 - 26, 0, 0) for f in fr])
    preview.append(('TELEPORT', [f[0] for f in fr]))

    # the player (type 7): the Doomer model, its mask tinted with player 1's
    # colour (TPlayerModel.Draw); frames face right, left = mirrored, drawn at
    # Obj.X/Y with PLAYER_RECT (15,12,34,52) inside
    shown = []
    for a, (res, n, spd, loop) in enumerate(PLAYER_ANIMS):
        if res is None:
            anims.append((0, 0, 0, 0, 0))
            continue
        base = Image.open(os.path.join(DOOMER, res + EXT.get(res, '.tga'))).convert('RGBA')
        mask = Image.open(os.path.join(DOOMER, res + 'MASK' + EXT.get(res, '.tga'))).convert('RGBA')
        r, g, b, al = mask.split()
        r = r.point(lambda v: v * PLAYER1_COLOR[0] // 255)
        g = g.point(lambda v: v * PLAYER1_COLOR[1] // 255)
        b = b.point(lambda v: v * PLAYER1_COLOR[2] // 255)
        img = Image.alpha_composite(base, Image.merge('RGBA', (r, g, b, al)))
        fw, fr = sheet_frames(res, img, img.width // n, n)
        r0 = put([add(fw, f, 0, 0, 32, 64, 0, PL_CX) for f in fr])
        anims.append((r0, r0, n, spd, loop | 0x80))
        shown += [f[0] for f in fr]
    anims.append((0, 0, 0, 0, 0))
    preview.append(('PLAYER', shown))
    monster('FISH')                                 # type 8 (D2DF MONSTER_FISH)

    # weapons in the player's hands (features=guns2: 64x64 textures drawn at
    # Obj + the MODEL.txt point, facing left mirrored at Obj - point); STAND
    # and WALK show the plain texture, ATTACK the _FIRE one
    model = open(os.path.join(DOOMER, '..', 'TEXT', 'MODEL.txt'), encoding='latin-1').read()
    wa = [0xFF] * ((len(PLAYER_WEAPONS) - 1) * 8)  # no row for the fist (None, first)
    assert PLAYER_WEAPONS[0] is None
    shown = []
    for w, wp in enumerate(PLAYER_WEAPONS):
        if wp is None:
            continue
        tex, key = wp
        for a, sect, fire in ((0, 'StandAnim', ''), (1, 'WalkAnim', ''), (4, 'AttackAnim', '_FIRE')):
            body = model.split(f'[{sect}]')[1].split('[')[0]
            pts = re.search(rf'^{key}_points=(.*)$', body, re.M)[1].split(',')
            img = Image.open(os.path.join(WEAPONS, tex + fire + '.tga')).convert('RGBA')
            fw, fr = sheet_frames(tex, img, 64, 1)
            pts = [tuple(int(v) for v in p.split(':')) for p in pts]
            wa[(w - 1) * 8 + a] = put([add(fw, fr[0], px, py, 32, 64, -px, PL_CX) for px, py in pts])
            shown.append(fr[0][0])
    preview.append(('WEAPONS', shown))

    # items (pk_type order): the texture's top-left at the original's Obj.X/Y,
    # i.e. from the engine's pk_x (= foot centre - 8) / pk_y (= feet) by the
    # item rect; animated ones as their whole (ping-pong) sequence
    ip = []
    shown = []
    for tex, n, back, spd, iw, ih in ITEMS:
        fn = os.path.join(TEXTURES, tex + '.tga')
        if not os.path.exists(fn):
            fn = fn[:-4] + '.png'                   # OXYGEN.png
        img = Image.open(fn).convert('RGBA')
        fw, fr = sheet_frames(tex, img, img.width // n, n)
        seq = []
        for f in fr:
            _, cx, cy, w, h, _ = f
            r = list(add(fw, f, 0, 0, 0, 0))
            r[3] = 8 - (iw // 2) // 2 + cx          # x from pk_x
            r[4] = 0
            r[5] = -(ih // 2) + cy                  # y from pk_y
            seq.append(tuple(r))
        irecs.extend(seq)                           # items: own records (it_*)
        ip.append((len(irecs) - len(seq), 2 * n - 2 if back else n, spd, n))   # ping-pong: folded
        shown += [f[0] for f in fr[:n]]
    preview.append(('ITEMS', shown))

    # small sprites for blit_sprite (no animation table): HUD icons and the
    # flying projectiles (g_weapons.pas), ox/oy centre a projectile on its
    # 8x8 hit point; _L = mirrored copy (flying left)
    small = []                                      # (name, addr, w, h, ox, oy)
    alias = []                                      # (projectile, its first sprite)

    def small_add(name, fr, mirror=False, centre=True):
        _, _, _, w, h, px = fr
        if mirror:
            px = b''.join(px[r * w:(r + 1) * w][::-1] for r in range(h))
        ox, oy = (4 - w // 2, 4 - h // 2) if centre else (0, 0)
        small.append((name, alloc(w, h, px), w, h, ox, oy))

    def tex_frames(tex, n, scale=2):
        img = Image.open(os.path.join(TEXTURES, tex + '.tga')).convert('RGBA')
        return sheet_frames(tex, img, img.width // n, n, scale)[1]

    for name, tex in (('KEYRED', 'KEYR'), ('KEYBLUE', 'KEYB'), ('KEYYELLOW', 'KEYG')):
        small_add(name, tex_frames(tex, 1)[0], centre=False)
    for name, tex in (('PISTOLPK', 'PISTOL'), ('SHOTGUNPK', 'SHOTGUN1'), ('CHAINGUNPK', 'MGUN'),
                      ('ROCKETPK', 'RLAUNCHER'), ('PLASMAGUNPK', 'PGUN'), ('BFGPK', 'BFG'),
                      ('SAWPK', 'SAW')):
        small_add(name, tex_frames(tex, 1)[0], centre=False)
    for name, tex, n, mirror in SMALL_PROJ:
        if len(small) & 1:                          # FIRE1 even: FIRE2 = FIRE1 | 1
            small.append(('PAD',) + small[-1][1:])
        alias.append((name, len(small)))
        fr = tex_frames(tex, n)
        for i, f in enumerate(fr):
            small_add(f'{name}{i + 1}' if n > 1 else name, f)
        if mirror:
            for i, f in enumerate(fr):
                small_add(f'{name}{i + 1}_L' if n > 1 else name + '_L', f, mirror=True)
    if len(small) > 255:
        raise SystemExit('small sprites > 255')

    if len(recs) > 255:                             # + IT_SLOT (an item's copy)
        raise SystemExit(f'{len(recs)} frames > 255')
    for r, blob in enumerate(blobs):
        blob.extend(bytes(-len(blob) % 256))        # whole pages: the upload copies pages
        path = os.path.join(DATA, f'mon_spr{r}.bin')
        if blob:
            with open(path, 'wb') as f:
                f.write(blob)
        elif os.path.exists(path):
            os.remove(path)                         # an unused region: no file

    def tab(name, vals, comment):
        s = f'{name:<8} ; {comment}\n'
        for i in range(0, len(vals), 16):
            s += '        dta ' + ','.join(str(v & 0xFF) for v in vals[i:i + 16]) + '\n'
        return s

    with open(os.path.join(GEN, 'mon_frames.asm'), 'w') as f:
        f.write('; generated by tools/prepare_sprites.py - do not edit\n')
        f.write(f'MON_FRAMES = {len(recs)}\n')
        f.write(f'IT_SLOT = {len(recs)}   ; the drawn item: its record copied from it_*\n')
        recs.append((0, 0, 0, 0, 0, 0))
        f.write(f'BARREL_SLEEP0 = {barrel["SLEEP"]}   ; 3 frames, a loop\n')
        f.write(f'BARREL_DIE0 = {barrel["DIE"]}   ; 4 frames\n')
        f.write(f'TELE0 = {tele}   ; the teleport flash, 10 frames\n\n')
        f.write(tab('mf_lo', [r[0] for r in recs], 'frame VRAM address lo'))
        f.write(tab('mf_mi', [r[0] >> 8 for r in recs], 'mid'))
        f.write(tab('mf_bk', [r[0] >> 16 for r in recs], 'bank byte'))
        f.write(tab('mf_w', [r[1] for r in recs], 'width'))
        f.write(tab('mf_h', [r[2] for r in recs], 'height'))
        f.write(tab('mf_ox', [r[3] for r in recs], 'x from en_x, facing right (signed)'))
        f.write(tab('mf_oxm', [r[4] for r in recs], 'x from en_x, drawn mirrored (signed)'))
        f.write(tab('mf_oy', [r[5] for r in recs], 'y from en_y = feet (signed)'))
    with open(os.path.join(GEN, 'mon_anims.asm'), 'w') as f:
        f.write('; generated by tools/prepare_sprites.py - do not edit\n')
        f.write('; animations, index = en_type*8 + ANIM_* (the player: type 7)\n')
        f.write(tab('ma_r', [a[0] for a in anims], 'first frame facing right'))
        f.write(tab('ma_l', [a[1] for a in anims], 'first frame facing left'))
        f.write(tab('ma_n', [a[2] for a in anims], 'frame count (0 = none)'))
        f.write(tab('ma_spd', [a[3] for a in anims], 'ticks per frame: AI ticks (18 Hz) monsters, 36 Hz player'))
        f.write(tab('wa_fr', wa, 'weapon in hand: (zpwcur-1)*8 + PA_* -> first frame ($FF none)'))
    with open(os.path.join(GEN, 'item_anims.asm'), 'w') as f:
        f.write('; generated by tools/prepare_sprites.py - do not edit\n')
        f.write(tab('it_lo', [r[0] for r in irecs], 'item frame: VRAM address lo'))
        f.write(tab('it_mi', [r[0] >> 8 for r in irecs], 'mid'))
        f.write(tab('it_bk', [r[0] >> 16 for r in irecs], 'bank byte'))
        f.write(tab('it_w', [r[1] for r in irecs], 'width'))
        f.write(tab('it_h', [r[2] for r in irecs], 'height'))
        f.write(tab('it_ox', [r[3] for r in irecs], 'x from pk_x (signed)'))
        f.write(tab('it_oy', [r[5] for r in irecs], 'y from pk_y = feet (signed)'))
        f.write(tab('ip_r', [i[0] for i in ip], 'item by pk_type: first it_* frame'))
        f.write(tab('ip_n', [i[1] for i in ip], 'frames in its sequence'))
        f.write(tab('ip_h', [i[3] for i in ip], 'frames stored; a phase >= ip_h plays ip_n - phase'))
        f.write(tab('ip_spd', [i[2] for i in ip], 'ticks (36 Hz) a frame: 0 still, 15, 20'))
    with open(os.path.join(GEN, 'mon_anims.asm'), 'a') as f:
        f.write(tab('ma_flg', [a[4] for a in anims], 'bit 0 loop, bit 7 left = mirrored right'))

    with open(os.path.join(GEN, 'spr_small.asm'), 'w') as f:
        f.write('; generated by tools/prepare_sprites.py - do not edit\n')
        f.write('; small sprites for blit_sprite (HUD icons, projectiles)\n')
        for i, s in enumerate(small):
            if s[0] != 'PAD':
                f.write(f'SPR_{s[0]:<16} = {i}   ; {s[2]}x{s[3]}\n')
        for name, i in alias:
            if not any(s[0] == name for s in small):
                f.write(f'SPR_{name:<16} = {i}   ; first frame\n')
        f.write('SPR_PROJ1            = 255   ; hitscan shot: a marker, never drawn\n\n')
        f.write(tab('spr_off_lo', [s[1] for s in small], 'VRAM address lo'))
        f.write(tab('spr_off_hi', [s[1] >> 8 for s in small], 'mid'))
        f.write(tab('spr_off_bank', [s[1] >> 16 for s in small], 'bank byte'))
        f.write(tab('spr_w', [s[2] for s in small], 'width'))
        f.write(tab('spr_h', [s[3] for s in small], 'height'))
        f.write(tab('spr_ox', [s[4] for s in small], 'projectile: x from its hit point (signed)'))
        f.write(tab('spr_oy', [s[5] for s in small], 'y (signed)'))

    with open(os.path.join(GEN, 'mon_upload.asm'), 'w') as f:
        f.write('; generated by tools/prepare_sprites.py - do not edit\n')
        chunks = [(r, off, min(CHUNK, len(blob) - off), lo + off)
                  for r, ((lo, _), blob) in enumerate(zip(REGIONS, blobs))
                  for off in range(0, len(blob), CHUNK)]
        for k, (r, off, ln, adr) in enumerate(chunks):
            banks = (ln + 4095) // 4096
            f.write(f"""
        org $6000
mon_c{k} ins '../data/mon_spr{r}.bin',{off},{ln}
        org $0580
.proc upload_mon{k}
        lda #<mon_c{k}
        sta zsrc
        lda #>mon_c{k}
        sta zsrc+1
        lda #BANK_EN+${adr >> 12:02X}
        sta uc_bank
        lda #{banks}
        sta uc_cnt
        lda #{(ln - (banks - 1) * 4096) // 256}
        sta uc_lastpg
        jmp generic_upload
.endp
        ini upload_mon{k}
""")

    os.makedirs(OUT, exist_ok=True)
    cw = max(sum(i.width + 2 for i in fr) for _, fr in preview)
    ch = sum(max(i.height for i in fr) + 2 for _, fr in preview)
    pv = Image.new('RGBA', (cw, ch), (40, 40, 48, 255))
    y = 0
    for _, fr in preview:
        x = 0
        for i in fr:
            pv.alpha_composite(i, (x, y))
            x += i.width + 2
        y += max(i.height for i in fr) + 2
    pv.resize((cw * 4, ch * 4), Image.NEAREST).save(os.path.join(OUT, 'mon_sprites.png'))
    print(f'{len(recs)} frames,', ', '.join(f'{len(b)} B at ${lo:06X}' for (lo, _), b in zip(REGIONS, blobs)))


if __name__ == '__main__':
    main()
