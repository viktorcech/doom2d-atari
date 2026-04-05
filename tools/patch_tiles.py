#!/usr/bin/env python3
"""
Patch missing floor tiles (11-14) into existing tilesheet.bin
using DOOM WAD flats. Does NOT regenerate existing tiles.

Usage: python patch_tiles.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from prepare_sprites import (load_palette, find_closest_color,
                              extract_flat_from_wad, downscale_flat_to_tile,
                              load_doom_palette_from_wad, downscale_walltex_to_tile,
                              extract_wall_texture)
from wad_extract import WADFile

WAD_PATH = os.path.join(os.path.dirname(__file__), '..', 'DOOM.WAD')
TILESHEET = os.path.join(os.path.dirname(__file__), '..', 'data', 'tilesheet.bin')
PREVIEW_DIR = os.path.join(os.path.dirname(__file__), '..', 'data', 'preview')

# Tile 11-14: floor variants (one-way platforms)
# Each tile = 256 bytes (16x16 indexed)
FLOOR_TILES = {
    11: ('techfloor',  ['FLOOR4_8', 'FLOOR4_6', 'FLAT4']),
    12: ('metalfloor', ['FLOOR0_3', 'CEIL4_1', 'FLAT1']),
    13: ('stepfloor',  ['FLOOR5_3', 'FLOOR5_1', 'FLAT8']),
    14: ('darkfloor',  ['FLOOR7_1', 'FLOOR6_1', 'FLAT5_1']),
}

def main():
    palette = load_palette()
    wad = WADFile(WAD_PATH)
    doom_pal = load_doom_palette_from_wad(wad)

    with open(TILESHEET, 'rb') as f:
        data = bytearray(f.read())

    print(f"Tilesheet: {len(data)} bytes ({len(data)//256} tiles)")

    for tile_idx, (name, candidates) in FLOOR_TILES.items():
        offset = tile_idx * 256
        # Check if already has content
        existing = data[offset:offset+256]
        if any(b != 0 for b in existing):
            print(f"  Tile {tile_idx} ({name}): already has data, skipping")
            continue

        extracted = False
        for flat_name in candidates:
            flat_data = extract_flat_from_wad(wad, flat_name)
            if flat_data:
                tile_data = bytearray(downscale_flat_to_tile(flat_data, doom_pal, palette, brightness=1.2))
                # Floor tiles are half-height: top 8px texture, bottom 8px transparent
                for y in range(8, 16):
                    for x in range(16):
                        tile_data[y * 16 + x] = 0
                data[offset:offset+256] = tile_data
                print(f"  Tile {tile_idx} ({name}): extracted from WAD flat {flat_name} (half-height)")
                extracted = True

                # Save preview
                from prepare_sprites import save_preview
                preview_path = os.path.join(PREVIEW_DIR, f'tile_{name}.png')
                save_preview(bytes(tile_data), 16, 16, palette, preview_path)
                break

        if not extracted:
            # Try wall textures
            for tex_name in candidates:
                result = extract_wall_texture(wad, tex_name)
                if result:
                    tw, th, tex_pixels = result
                    tile_data = downscale_walltex_to_tile(tex_pixels, tw, th, doom_pal, palette)
                    data[offset:offset+256] = tile_data
                    print(f"  Tile {tile_idx} ({name}): extracted from WAD wall tex {tex_name}")
                    extracted = True
                    break

        if not extracted:
            print(f"  Tile {tile_idx} ({name}): NOT FOUND in WAD")

    with open(TILESHEET, 'wb') as f:
        f.write(data)
    print(f"\nTilesheet patched: {len(data)} bytes")


if __name__ == '__main__':
    main()
