#!/usr/bin/env python3
"""
Prepare new item/decoration sprites for DOOM2D Atari VBXE.

Takes extracted DOOM WAD PNGs, resizes to 16x16, converts to 8bpp
indexed (palette index 0 = transparent), saves .bin + preview.

Does NOT touch spritesheet or sprite_defs - those must be updated
by hand after verifying the output.

Usage:
    python prepare_items.py
"""

import os
import sys
from PIL import Image

# Reuse palette/color functions from prepare_sprites
sys.path.insert(0, os.path.dirname(__file__))
from prepare_sprites import load_palette, find_closest_color

# Paths
SPRITES_PNG = os.path.join(os.path.dirname(__file__), '..', 'extracted', 'sprites', 'png')
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), '..', 'data')
PREVIEW_DIR = os.path.join(OUTPUT_DIR, 'preview')

# New items to process: (wad_png, target_w, target_h, output_name, max_scale)
# max_scale limits size for items that are too big at native resolution
NEW_ITEMS = [
    ('ARM1A0.png',  16, 16, 'greenarmor', None),
    ('ARM2A0.png',  16, 16, 'bluearmor',  None),
    ('SOULA0.png',  16, 16, 'soulsphere', None),
    ('RKEYA0.png',  16, 16, 'keyred',     0.5),
    ('BKEYA0.png',  16, 16, 'keyblue',    0.5),
    ('YKEYA0.png',  16, 16, 'keyyellow',  0.5),
    ('SHOTA0.png',  16, 16, 'shotgunpk',  None),
    ('SHELA0.png',  16, 16, 'shells',     None),
]

NEW_DECOR = [
    ('BAR1A0.png',  16, 16, 'barrel',  None),
    ('COLUA0.png',  16, 32, 'pillar',  None),
    ('TREDA0.png',  16, 32, 'torch',   None),
    ('CBRAA0.png',  16, 32, 'lamp',    None),
]


def convert_sprite(png_path, target_w, target_h, palette, max_scale=None):
    """Load PNG, resize, convert to 8bpp indexed with DOOM palette.
    Returns raw bytes (target_w * target_h), index 0 = transparent.
    max_scale: limit scaling factor (e.g. 0.7 to make item smaller)
    """
    img = Image.open(png_path).convert('RGBA')
    orig_w, orig_h = img.size

    # Scale to fit target, maintain aspect ratio
    scale = min(target_w / orig_w, target_h / orig_h)
    if max_scale is not None:
        scale = min(scale, max_scale)
    new_w = max(1, int(orig_w * scale))
    new_h = max(1, int(orig_h * scale))

    img_resized = img.resize((new_w, new_h), Image.LANCZOS)

    # Create output buffer (0 = transparent)
    raw = bytearray(target_w * target_h)

    # Center horizontally, align to bottom
    ox = (target_w - new_w) // 2
    oy = target_h - new_h

    pixels = img_resized.load()
    for y in range(new_h):
        for x in range(new_w):
            r, g, b, a = pixels[x, y]
            if a < 128:
                continue
            dx = ox + x
            dy = oy + y
            if 0 <= dx < target_w and 0 <= dy < target_h:
                idx = find_closest_color(r, g, b, palette)
                raw[dy * target_w + dx] = idx

    return bytes(raw)


def save_preview(raw_data, width, height, palette, output_path):
    """Save raw indexed data as PNG preview (4x scaled)."""
    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    for y in range(height):
        for x in range(width):
            idx = raw_data[y * width + x]
            if idx == 0:
                continue
            r, g, b = palette[idx]
            img.putpixel((x, y), (r, g, b, 255))

    img_big = img.resize((width * 4, height * 4), Image.NEAREST)
    img_big.save(output_path)


def main():
    palette = load_palette()
    print(f"Loaded VBXE palette ({len(palette)} colors)")

    os.makedirs(PREVIEW_DIR, exist_ok=True)

    all_items = NEW_ITEMS + NEW_DECOR

    for src_png, tw, th, name, mscale in all_items:
        png_path = os.path.join(SPRITES_PNG, src_png)
        if not os.path.exists(png_path):
            print(f"  SKIP {name}: {src_png} not found")
            continue

        raw = convert_sprite(png_path, tw, th, palette, max_scale=mscale)

        # Save .bin
        bin_path = os.path.join(OUTPUT_DIR, f'{name}.bin')
        with open(bin_path, 'wb') as f:
            f.write(raw)

        # Save preview
        preview_path = os.path.join(PREVIEW_DIR, f'{name}.png')
        save_preview(raw, tw, th, palette, preview_path)

        print(f"  {name}: {src_png} -> {tw}x{th} = {len(raw)} bytes  ({bin_path})")

    print(f"\nDone! {len(all_items)} items processed.")
    print("Next steps:")
    print("  1. Check previews in data/preview/")
    print("  2. Add .bin data to spritesheet chunks")
    print("  3. Update sprite_defs.asm with new indices")


if __name__ == '__main__':
    main()
