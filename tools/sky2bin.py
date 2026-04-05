#!/usr/bin/env python3
"""
Convert sky PNG to 320x200 8-bit indexed binary for VBXE.

Uses the game's palette.bin to find nearest colors.
Outputs chunked binary files for VRAM upload (max 12KB per chunk).

Usage:
    python sky2bin.py input.png palette.bin output_prefix
    python sky2bin.py ../original-doom-2d/D2DMP-Files-0.6/data/sky/D2DSKY1.png ../data/palette.bin ../data/sky
"""

import sys
import os
import numpy as np
from PIL import Image


def load_palette(path):
    """Load palette.bin (256 R + 256 G + 256 B = 768 bytes)."""
    with open(path, 'rb') as f:
        data = f.read()
    # Return as numpy array (256, 3)
    r = np.frombuffer(data[0:256], dtype=np.uint8)
    g = np.frombuffer(data[256:512], dtype=np.uint8)
    b = np.frombuffer(data[512:768], dtype=np.uint8)
    return np.stack([r, g, b], axis=1).astype(np.int32)


def convert_sky(input_path, palette_path, output_prefix):
    palette = load_palette(palette_path)  # (256, 3)

    img = Image.open(input_path).convert('RGB')
    img = img.resize((320, 200), Image.LANCZOS)
    pixels = np.array(img, dtype=np.int32)  # (200, 320, 3)

    # Vectorized nearest color: for each pixel find closest palette entry
    # Skip index 0 (transparent)
    pal = palette[1:]  # (255, 3)

    flat = pixels.reshape(-1, 3)  # (64000, 3)

    # Process in batches to avoid memory issues
    BATCH = 4000
    result = np.zeros(flat.shape[0], dtype=np.uint8)
    for i in range(0, flat.shape[0], BATCH):
        batch = flat[i:i + BATCH]  # (batch, 3)
        # Compute squared distances to all palette entries
        diff = batch[:, np.newaxis, :] - pal[np.newaxis, :, :]  # (batch, 255, 3)
        dist = np.sum(diff * diff, axis=2)  # (batch, 255)
        result[i:i + BATCH] = np.argmin(dist, axis=1).astype(np.uint8) + 1  # +1 to skip index 0

    data = result.tobytes()  # 64000 bytes
    unique_colors = len(set(map(tuple, flat.tolist())))
    print(f"Image: 320x200 = {len(data)} bytes, {unique_colors} unique colors")

    # Split into chunks of 12288 bytes (3 VRAM banks each)
    CHUNK_SIZE = 12288
    chunk_num = 1
    offset = 0
    while offset < len(data):
        chunk = data[offset:offset + CHUNK_SIZE]
        chunk_path = f"{output_prefix}_c{chunk_num}.bin"
        with open(chunk_path, 'wb') as f:
            f.write(chunk)
        print(f"  Chunk {chunk_num}: {chunk_path} ({len(chunk)} bytes, "
              f"{(len(chunk) + 255) // 256} pages)")
        chunk_num += 1
        offset += CHUNK_SIZE

    print(f"\nTotal: {len(data)} bytes in {chunk_num - 1} chunks")
    print(f"VRAM: $034000-${0x034000 + len(data) - 1:06X}")


if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("Usage: python sky2bin.py input.png palette.bin output_prefix")
        print("Example: python sky2bin.py D2DSKY1.png ../data/palette.bin ../data/sky")
        sys.exit(1)
    convert_sky(sys.argv[1], sys.argv[2], sys.argv[3])
