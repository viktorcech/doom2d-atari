#!/usr/bin/env python3
"""
Convert 16x16 TGA textures to tile .bin files using VBXE palette.
Usage: python tga2tile.py SWITCH1_0.tga switch1_off.bin
"""
import sys
import os
import struct

sys.path.insert(0, os.path.dirname(__file__))
PALETTE_BIN = os.path.join(os.path.dirname(__file__), '..', 'data', 'palette.bin')


def load_palette():
    with open(PALETTE_BIN, 'rb') as f:
        data = f.read()
    palette = []
    for i in range(256):
        r = data[i] << 1
        g = data[256 + i] << 1
        b = data[512 + i] << 1
        palette.append((r, g, b))
    return palette


def find_closest_color(r, g, b, palette, skip_zero=True):
    best_idx = 0
    best_dist = 999999
    start = 1 if skip_zero else 0
    for i in range(start, 256):
        pr, pg, pb = palette[i]
        d = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
        if d < best_dist:
            best_dist = d
            best_idx = i
    return best_idx


def read_tga(path):
    """Read uncompressed TGA, return (width, height, pixels as list of (r,g,b))."""
    with open(path, 'rb') as f:
        data = f.read()
    id_len = data[0]
    img_type = data[2]
    width = struct.unpack('<H', data[12:14])[0]
    height = struct.unpack('<H', data[14:16])[0]
    bpp = data[16]
    descriptor = data[17]
    offset = 18 + id_len

    if img_type != 2:
        raise ValueError(f"Only uncompressed RGB TGA supported, got type {img_type}")

    bytes_pp = bpp // 8
    pixels = []
    for i in range(width * height):
        idx = offset + i * bytes_pp
        b = data[idx]
        g = data[idx + 1]
        r = data[idx + 2]
        pixels.append((r, g, b))

    # TGA is bottom-up by default (unless bit 5 of descriptor is set)
    top_to_bottom = (descriptor & 0x20) != 0
    if not top_to_bottom:
        # Flip vertically
        rows = [pixels[y * width:(y + 1) * width] for y in range(height)]
        rows.reverse()
        pixels = [p for row in rows for p in row]

    return width, height, pixels


def convert_tga_to_tile(tga_path, palette, shrink=None):
    """Convert TGA to 16x16 indexed tile data.
    shrink: if set (e.g. 8), downscale graphic to NxN and center in 16x16
            with index 0 (transparent) border.
    """
    width, height, pixels = read_tga(tga_path)

    if shrink:
        # Downscale to shrink x shrink, center in 16x16
        sw, sh = shrink, shrink
        out = []
        for y in range(sh):
            sy = y * height // sh
            for x in range(sw):
                sx = x * width // sw
                out.append(pixels[sy * width + sx])

        result = bytearray(256)  # 16x16, all index 0 (transparent)
        ox = (16 - sw) // 2
        oy = (16 - sh) // 2
        for y in range(sh):
            for x in range(sw):
                r, g, b = out[y * sw + x]
                idx = find_closest_color(r, g, b, palette)
                result[(oy + y) * 16 + (ox + x)] = idx
        return bytes(result)

    # Downscale if needed
    if width != 16 or height != 16:
        # Simple nearest-neighbor downscale
        out = []
        for y in range(16):
            sy = y * height // 16
            for x in range(16):
                sx = x * width // 16
                out.append(pixels[sy * width + sx])
        pixels = out

    # Map to palette
    result = bytearray(256)
    for i, (r, g, b) in enumerate(pixels):
        # TGA colors are 8-bit, palette is 7-bit (shifted to 8-bit in load_palette)
        result[i] = find_closest_color(r, g, b, palette)
    return bytes(result)


def main():
    if len(sys.argv) < 3:
        print("Usage: python tga2tile.py input.tga output.bin [--shrink N]")
        sys.exit(1)

    tga_path = sys.argv[1]
    out_path = sys.argv[2]
    shrink = None
    if '--shrink' in sys.argv:
        idx = sys.argv.index('--shrink')
        shrink = int(sys.argv[idx + 1])

    palette = load_palette()
    tile = convert_tga_to_tile(tga_path, palette, shrink=shrink)

    with open(out_path, 'wb') as f:
        f.write(tile)
    print(f"OK: {tga_path} -> {out_path} ({len(tile)} bytes, shrink={shrink})")


if __name__ == '__main__':
    main()
