#!/usr/bin/env python3
"""
The level sky for the VBXE blitter (source/sky.asm) and the MODE 7 liquid
filter tables (source/liquid.asm, data/liquid_lut.bin). The sky: the original Doom 2D
Forever sky texture, area-averaged to SKY_W x SKY_H and mapped to the game
palette (data/palette.bin, 7-bit R/G/B planes; index 0 is never used, the
sky is opaque).

  python tools/sky2vbxe.py [texture] [out.bin]
    default: git/DF-Assets-master/StandartWAD/D2DSKY/RSKY1.tga -> data/sky_vbxe.bin

The game draws it with ONE BCB zoomed 4 x 2 (80 columns -> 320 px, 96 rows
-> 192 lines); the 4 columns past 80 are the parallax room (source column
offset = cam_x >> 7). g_map.pas draws the whole texture over the view too.
"""

import os
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SKY_W, SKY_H = 84, 96               # keep in step with source/sky.asm


def palette_image():
    """A 'P' image holding the game palette, entry 0 made unreachable."""
    pal = open(os.path.join(ROOT, 'data', 'palette.bin'), 'rb').read()
    flat = []
    for i in range(256):
        flat += [pal[i] << 1, pal[256 + i] << 1, pal[512 + i] << 1]
    flat[0:3] = [255, 0, 255]       # 0 = transparent: no sky pixel maps to it
    img = Image.new('P', (1, 1))
    img.putpalette(flat)
    return img


def liquid_luts():
    """The MODE 7 tables of the liquid filter (source/liquid.asm): for water,
    acid1, acid2, palette index -> the index nearest to its colour times the
    g_panel.pas colour (0,0,255), (0,230,0), (230,0,0) / 255. 0 stays 0."""
    pal = open(os.path.join(ROOT, 'data', 'palette.bin'), 'rb').read()
    rgb = [(pal[i] << 1, pal[256 + i] << 1, pal[512 + i] << 1) for i in range(256)]
    out = bytearray()
    for cr, cg, cb in ((0, 0, 255), (0, 230, 0), (230, 0, 0)):
        for i in range(256):
            if i == 0:
                out.append(0)
                continue
            r, g, b = rgb[i]
            t = (r * cr // 255, g * cg // 255, b * cb // 255)
            out.append(min(range(1, 256), key=lambda j: (rgb[j][0] - t[0]) ** 2 +
                           (rgb[j][1] - t[1]) ** 2 + (rgb[j][2] - t[2]) ** 2))
    # page 3: the level stats' values in red (g_game.pas DrawSingleStat
    # _RGB(255, 0, 0)): every font colour -> red, 0 (the font's empty) -> 0
    red = min(range(1, 256), key=lambda j: (rgb[j][0] - 255) ** 2 + rgb[j][1] ** 2 + rgb[j][2] ** 2)
    out += bytes([0] + [red] * 255)
    return out


def blood_cols():
    """source/blood.asm: the blood colours (g_monsters.pas FBloodRed..Blue:
    150 red, caco blue, baron green; g_gfx.pas g_GFX_Blood crnd = 20 *
    Random(6) - 50 on the set channel), 8 shades a kind (the 6, then the
    middle two again), palette index nearest (never 0: transparent)."""
    pal = open(os.path.join(ROOT, 'data', 'palette.bin'), 'rb').read()
    rgb = [(pal[i] << 1, pal[256 + i] << 1, pal[512 + i] << 1) for i in range(256)]
    def near(t):
        return min(range(1, 256), key=lambda j: sum((rgb[j][c] - t[c]) ** 2 for c in range(3)))
    out = bytearray()
    for ch in (0, 2, 1):                # red, blue (caco), green (baron)
        for k in (0, 1, 2, 3, 4, 5, 2, 3):
            t = [0, 0, 0]
            t[ch] = max(0, min(255, 150 + 20 * k - 50))
            out.append(near(t))
    for k in range(8):                  # sparks (g_GFX_Spark): 255, 100+Random(155), 64
        out.append(near((255, 100 + 155 * k // 7, 64)))
    tex = os.path.join(ROOT, 'git', 'DF-Assets-master', 'GameWAD', 'TEXTURES')
    for name in ('EBULLET', 'ESHELL'):  # the casings: their textures' mean colour
        px = [p for p in Image.open(os.path.join(tex, name + '.tga')).convert('RGBA').getdata()
              if p[3] >= 128]
        out.append(near(tuple(sum(p[c] for p in px) // len(px) for c in range(3))))
    return out


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        ROOT, 'git', 'DF-Assets-master', 'StandartWAD', 'D2DSKY', 'RSKY1.tga')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, 'data', 'sky_vbxe.bin')
    rgb = Image.open(src).convert('RGB').resize((SKY_W, SKY_H), Image.BOX)
    q = rgb.quantize(palette=palette_image(), dither=Image.Dither.NONE)
    data = q.tobytes()
    assert 0 not in data and len(data) == SKY_W * SKY_H
    with open(out, 'wb') as f:
        f.write(data)
    print(f"sky: {src} -> {out} ({SKY_W}x{SKY_H}, {len(data)} B)")
    lut = os.path.join(ROOT, 'data', 'liquid_lut.bin')
    with open(lut, 'wb') as f:
        f.write(liquid_luts())
    print(f"MODE 7 tables: {lut} (3 liquid filters + the red text, 4 x 256 B)")
    bc = os.path.join(ROOT, 'data', 'blood_cols.bin')
    with open(bc, 'wb') as f:
        f.write(blood_cols())
    print(f"blood colours: {bc} (3 x 8 B, 8 sparks, 2 casings)")


if __name__ == '__main__':
    main()
