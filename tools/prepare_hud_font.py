#!/usr/bin/env python3
"""
Generate HUD font for DOOM 2D Atari VBXE.

Output: data/hud_font.bin (768 bytes)
  - 12 characters, each 8x8 = 64 bytes
  - Index 0-9: digits '0'-'9'
  - Index 10: heart icon (HP)
  - Index 11: bullet icon (ammo)

Each byte = palette index. 0 = transparent, 4 = bright red (heart),
176 = yellow (digits/bullet) from DOOM palette.

Usage: python tools/prepare_hud_font.py
"""

import os
import struct

OUTPUT = os.path.join(os.path.dirname(__file__), '..', 'data', 'hud_font.bin')

# DOOM palette indices for HUD colors
COL_DIGIT = 176    # yellow/gold (DOOM status bar number color)
COL_HEART = 176    # red for heart
COL_BULLET = 176   # yellow for bullet
COL_BG = 0         # transparent

# 8x8 pixel font bitmaps (1 = foreground, 0 = transparent)
# Each entry is 8 rows of 8 bits
FONT_BITMAPS = {
    0: [  # '0'
        0b01111100,
        0b11000110,
        0b11001110,
        0b11011110,
        0b11110110,
        0b11100110,
        0b01111100,
        0b00000000,
    ],
    1: [  # '1'
        0b00011000,
        0b00111000,
        0b01111000,
        0b00011000,
        0b00011000,
        0b00011000,
        0b01111110,
        0b00000000,
    ],
    2: [  # '2'
        0b01111100,
        0b11000110,
        0b00001110,
        0b00111100,
        0b01110000,
        0b11000110,
        0b11111110,
        0b00000000,
    ],
    3: [  # '3'
        0b01111100,
        0b11000110,
        0b00000110,
        0b00111100,
        0b00000110,
        0b11000110,
        0b01111100,
        0b00000000,
    ],
    4: [  # '4'
        0b00001100,
        0b00011100,
        0b00111100,
        0b01101100,
        0b11111110,
        0b00001100,
        0b00001100,
        0b00000000,
    ],
    5: [  # '5'
        0b11111110,
        0b11000000,
        0b11111100,
        0b00000110,
        0b00000110,
        0b11000110,
        0b01111100,
        0b00000000,
    ],
    6: [  # '6'
        0b00111100,
        0b01100000,
        0b11000000,
        0b11111100,
        0b11000110,
        0b11000110,
        0b01111100,
        0b00000000,
    ],
    7: [  # '7'
        0b11111110,
        0b11000110,
        0b00001100,
        0b00011000,
        0b00110000,
        0b00110000,
        0b00110000,
        0b00000000,
    ],
    8: [  # '8'
        0b01111100,
        0b11000110,
        0b11000110,
        0b01111100,
        0b11000110,
        0b11000110,
        0b01111100,
        0b00000000,
    ],
    9: [  # '9'
        0b01111100,
        0b11000110,
        0b11000110,
        0b01111110,
        0b00000110,
        0b00001100,
        0b01111000,
        0b00000000,
    ],
    10: [  # Heart icon
        0b00000000,
        0b01100110,
        0b11111111,
        0b11111111,
        0b11111111,
        0b01111110,
        0b00111100,
        0b00011000,
    ],
    11: [  # Bullet/ammo icon
        0b00000000,
        0b00011100,
        0b00111110,
        0b01111111,
        0b01111111,
        0b00111110,
        0b00011100,
        0b00000000,
    ],
}

# Color for each character index
COLORS = {
    0: COL_DIGIT, 1: COL_DIGIT, 2: COL_DIGIT, 3: COL_DIGIT, 4: COL_DIGIT,
    5: COL_DIGIT, 6: COL_DIGIT, 7: COL_DIGIT, 8: COL_DIGIT, 9: COL_DIGIT,
    10: COL_HEART,
    11: COL_BULLET,
}


def bitmap_to_raw(bitmap_rows, color):
    """Convert 8-row bitmap to 64-byte raw 8bpp data."""
    raw = bytearray(64)
    for row in range(8):
        bits = bitmap_rows[row]
        for col in range(8):
            if bits & (0x80 >> col):
                raw[row * 8 + col] = color
            else:
                raw[row * 8 + col] = COL_BG
    return raw


def main():
    data = bytearray()
    for i in range(12):
        char_data = bitmap_to_raw(FONT_BITMAPS[i], COLORS[i])
        data.extend(char_data)

    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, 'wb') as f:
        f.write(data)

    print(f"HUD font: {len(data)} bytes -> {OUTPUT}")
    print(f"  12 characters (0-9, heart, bullet), each 8x8 = 64 bytes")

    # Print ASCII preview
    for i in range(12):
        name = str(i) if i < 10 else ('heart' if i == 10 else 'bullet')
        print(f"\n  [{i}] {name}:")
        for row in range(8):
            line = ""
            for col in range(8):
                if data[i * 64 + row * 8 + col] != 0:
                    line += "##"
                else:
                    line += "  "
            print(f"    {line}")


if __name__ == '__main__':
    main()
