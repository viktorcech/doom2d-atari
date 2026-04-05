#!/usr/bin/env python3
"""
VBXE Blitter Simulator for Doom2D debugging.

Simulates the VBXE screen rendering pipeline:
1. Load palette, tilesheet, spritesheet from data/
2. Load map from source (parsed)
3. Simulate render loop: clear -> erase old -> tiles -> sprites
4. Output PNG screenshots

Usage:
    python vbxe_sim.py
    python vbxe_sim.py --frame 10 --zombie-x 180
"""

import os
import struct
import argparse
from PIL import Image

# Paths
DATA_DIR = os.path.join(os.path.dirname(__file__), '..', 'data')

# Constants (match main.asm)
SCR_W = 320
SCR_H = 200
TILE_W = 16
TILE_H = 16
MAP_W = 64
MAP_H = 32
TILES_X = 20
TILES_Y = 12


def load_palette():
    """Load VBXE palette (7-bit RGB)."""
    with open(os.path.join(DATA_DIR, 'palette.bin'), 'rb') as f:
        data = f.read()
    pal = []
    for i in range(256):
        r = min(255, data[i] << 1)
        g = min(255, data[256 + i] << 1)
        b = min(255, data[512 + i] << 1)
        pal.append((r, g, b))
    return pal


def load_tilesheet():
    """Load tilesheet (16 tiles * 256 bytes)."""
    with open(os.path.join(DATA_DIR, 'tilesheet.bin'), 'rb') as f:
        data = f.read()
    tiles = []
    for i in range(16):
        tile = data[i * 256:(i + 1) * 256]
        tiles.append(tile)
    return tiles


def load_spritesheet():
    """Load spritesheet with known layout."""
    with open(os.path.join(DATA_DIR, 'spritesheet.bin'), 'rb') as f:
        data = f.read()
    return data


# Sprite definitions (match sprite_defs.asm)
SPRITE_DEFS = [
    # (name, width, height, offset)
    ('player_idle',  16, 32, 0x0000),
    ('player_walk1', 16, 32, 0x0200),
    ('player_walk2', 16, 32, 0x0400),
    ('player_walk3', 16, 32, 0x0600),
    ('player_shoot', 16, 32, 0x0800),
    ('player_death', 16, 32, 0x0A00),
    ('zombie_idle',  16, 32, 0x0C00),
    ('zombie_walk1', 16, 32, 0x0E00),
    ('zombie_walk2', 16, 32, 0x1000),
    ('zombie_walk3', 16, 32, 0x1200),
    ('zombie_shoot', 16, 32, 0x1400),
    ('zombie_death', 16, 32, 0x1600),
    ('proj1',         8,  8, 0x1800),
    ('proj2',         8,  8, 0x1840),
    ('medikit',      16, 16, 0x1880),
    ('stimpack',     16, 16, 0x1980),
    ('health_bonus', 16, 16, 0x1A80),
    ('ammo_clip',    16, 16, 0x1B80),
]


def build_map():
    """Build map data matching main.asm."""
    m = bytearray(MAP_W * MAP_H)

    # Rows 0-3: sky (tile 5)
    for row in range(4):
        for col in range(MAP_W):
            m[row * MAP_W + col] = 5

    # Rows 4-9: walls on sides (tile 1), empty inside (tile 0)
    for row in range(4, 10):
        m[row * MAP_W + 0] = 1
        for col in range(1, MAP_W - 1):
            m[row * MAP_W + col] = 0
        m[row * MAP_W + MAP_W - 1] = 1

    # Row 10: platforms
    row = 10
    idx = row * MAP_W
    m[idx] = 1
    for i in range(1, 7): m[idx + i] = 0
    for i in range(7, 17): m[idx + i] = 2
    for i in range(17, 21): m[idx + i] = 0
    for i in range(21, 31): m[idx + i] = 2
    for i in range(31, 35): m[idx + i] = 0
    for i in range(35, 45): m[idx + i] = 2
    for i in range(45, 49): m[idx + i] = 0
    for i in range(49, 55): m[idx + i] = 2
    for i in range(55, 60): m[idx + i] = 0
    m[idx + 60] = 2
    m[idx + 61] = 2
    m[idx + 62] = 0  # note: map row 10 has only 62 bytes in asm! bug
    m[idx + 63] = 1

    # Row 11: solid floor (tile 2)
    for col in range(MAP_W):
        m[11 * MAP_W + col] = 2

    # Rows 12-31: underground (tile 1)
    for row in range(12, MAP_H):
        for col in range(MAP_W):
            m[row * MAP_W + col] = 1

    return m


class VBXEScreen:
    """Simulates 320x200 8bpp VBXE screen buffer."""

    def __init__(self, palette):
        self.palette = palette
        self.buffer = bytearray(SCR_W * SCR_H)  # 8bpp indexed

    def clear(self):
        """Fill screen with color 0 (black)."""
        for i in range(len(self.buffer)):
            self.buffer[i] = 0

    def blit_normal(self, src_data, src_w, dst_x, dst_y, w, h):
        """Normal blit (mode 0): copy all pixels including 0."""
        for row in range(h):
            sy = row
            dy = dst_y + row
            if dy < 0 or dy >= SCR_H:
                continue
            for col in range(w):
                sx = col
                dx = dst_x + col
                if dx < 0 or dx >= SCR_W:
                    continue
                pixel = src_data[sy * src_w + sx]
                self.buffer[dy * SCR_W + dx] = pixel

    def blit_transparent(self, src_data, src_w, dst_x, dst_y, w, h):
        """Transparent blit (mode 1): skip $00 source pixels."""
        for row in range(h):
            sy = row
            dy = dst_y + row
            if dy < 0 or dy >= SCR_H:
                continue
            for col in range(w):
                sx = col
                dx = dst_x + col
                if dx < 0 or dx >= SCR_W:
                    continue
                pixel = src_data[sy * src_w + sx]
                if pixel != 0:  # Skip transparent pixels!
                    self.buffer[dy * SCR_W + dx] = pixel

    def fill_rect(self, dst_x, dst_y, w, h, color=0):
        """Fill rectangle with color (erase sprite area)."""
        for row in range(h):
            dy = dst_y + row
            if dy < 0 or dy >= SCR_H:
                continue
            for col in range(w):
                dx = dst_x + col
                if dx < 0 or dx >= SCR_W:
                    continue
                self.buffer[dy * SCR_W + dx] = color

    def to_image(self):
        """Convert buffer to PIL Image."""
        img = Image.new('RGB', (SCR_W, SCR_H))
        for y in range(SCR_H):
            for x in range(SCR_W):
                idx = self.buffer[y * SCR_W + x]
                img.putpixel((x, y), self.palette[idx])
        return img


def render_tiles(screen, tiles, game_map, scroll_x=0, scroll_y=0):
    """Render visible tiles to screen."""
    tile_ox = scroll_x // TILE_W
    fine_x = scroll_x % TILE_W
    tile_oy = scroll_y // TILE_H
    fine_y = scroll_y % TILE_H

    for row in range(TILES_Y + 1):
        for col in range(TILES_X + 1):
            mx = tile_ox + col
            my = tile_oy + row
            if mx >= MAP_W or my >= MAP_H:
                continue
            tile_idx = game_map[my * MAP_W + mx]
            if tile_idx == 0:
                continue  # skip empty tiles

            dx = col * TILE_W - fine_x
            dy = row * TILE_H - fine_y
            if dx < -TILE_W or dy < -TILE_H:
                continue

            tile_data = tiles[tile_idx] if tile_idx < len(tiles) else tiles[0]
            screen.blit_normal(tile_data, TILE_W, dx, dy, TILE_W, TILE_H)


def get_sprite(spritesheet, sprite_idx):
    """Get sprite data by index."""
    if sprite_idx >= len(SPRITE_DEFS):
        return None, 0, 0
    name, w, h, offset = SPRITE_DEFS[sprite_idx]
    data = spritesheet[offset:offset + w * h]
    return data, w, h


def simulate_frame(screen, tiles, spritesheet, game_map,
                   player_x, player_y, player_spr,
                   zombie_x, zombie_y, zombie_spr,
                   old_zombie_x=None, old_zombie_y=None,
                   scroll_x=0):
    """Simulate one complete frame render."""

    # 1. Erase old sprite positions
    if old_zombie_x is not None:
        _, zw, zh = get_sprite(spritesheet, zombie_spr)
        erase_dx = old_zombie_x - scroll_x
        erase_dy = old_zombie_y - 32  # feet offset
        screen.fill_rect(erase_dx, erase_dy, zw, zh)

    # 2. Render tiles (covers erased areas)
    render_tiles(screen, tiles, game_map, scroll_x, 0)

    # 3. Draw sprites (transparent mode)
    # Zombie
    spr_data, sw, sh = get_sprite(spritesheet, zombie_spr)
    if spr_data:
        zx = zombie_x - scroll_x
        zy = zombie_y - 32
        screen.blit_transparent(spr_data, sw, zx, zy, sw, sh)

    # Player
    spr_data, sw, sh = get_sprite(spritesheet, player_spr)
    if spr_data:
        px = player_x - scroll_x
        py = player_y - 32
        screen.blit_transparent(spr_data, sw, px, py, sw, sh)


def main():
    parser = argparse.ArgumentParser(description='VBXE Doom2D Simulator')
    parser.add_argument('--frames', type=int, default=5, help='Number of frames to simulate')
    parser.add_argument('--player-x', type=int, default=32)
    parser.add_argument('--player-y', type=int, default=144)
    parser.add_argument('--zombie-x', type=int, default=160)
    parser.add_argument('--zombie-y', type=int, default=144)
    args = parser.parse_args()

    out_dir = os.path.join(os.path.dirname(__file__), '..', 'sim_output')
    os.makedirs(out_dir, exist_ok=True)

    print("Loading assets...")
    palette = load_palette()
    tiles = load_tilesheet()
    spritesheet = load_spritesheet()
    game_map = build_map()

    print(f"Palette: {len(palette)} colors")
    print(f"Tiles: {len(tiles)}")
    print(f"Spritesheet: {len(spritesheet)} bytes")
    print(f"Map: {MAP_W}x{MAP_H}")

    screen = VBXEScreen(palette)
    screen.clear()

    zombie_x = args.zombie_x
    zombie_y = args.zombie_y
    zombie_dir = 0  # 0=right
    old_zx = zombie_x
    old_zy = zombie_y

    player_x = args.player_x
    player_y = args.player_y

    for frame in range(args.frames):
        # Zombie patrol
        old_zx_save = zombie_x
        if zombie_dir == 0:
            zombie_x += 1
            if zombie_x >= 240:
                zombie_dir = 1
        else:
            zombie_x -= 1
            if zombie_x <= 32:
                zombie_dir = 0

        # Zombie animation frame
        zombie_spr = 7 + (frame // 4) % 4  # SPR_ZM_W1..W3

        simulate_frame(
            screen, tiles, spritesheet, game_map,
            player_x, player_y, 0,  # SPR_PL_IDLE
            zombie_x, zombie_y, zombie_spr,
            old_zombie_x=old_zx, old_zombie_y=old_zy,
            scroll_x=0
        )

        old_zx = old_zx_save
        old_zy = zombie_y

        # Save frame
        img = screen.to_image()
        # Scale up 2x
        img_big = img.resize((SCR_W * 2, SCR_H * 2), Image.NEAREST)
        path = os.path.join(out_dir, f'frame_{frame:03d}.png')
        img_big.save(path)
        print(f"  Frame {frame}: zombie at ({zombie_x},{zombie_y}), saved {path}")

    # Also save individual sprite previews
    print("\nSprite previews:")
    for i, (name, w, h, offset) in enumerate(SPRITE_DEFS):
        data = spritesheet[offset:offset + w * h]
        if len(data) < w * h:
            print(f"  {name}: INCOMPLETE DATA ({len(data)}/{w*h} bytes)")
            continue
        img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        nonzero = 0
        for y in range(h):
            for x in range(w):
                idx = data[y * w + x]
                if idx != 0:
                    r, g, b = palette[idx]
                    img.putpixel((x, y), (r, g, b, 255))
                    nonzero += 1
        img_big = img.resize((w * 4, h * 4), Image.NEAREST)
        path = os.path.join(out_dir, f'sprite_{i:02d}_{name}.png')
        img_big.save(path)
        print(f"  [{i:2d}] {name:20s} {w}x{h} ({nonzero} non-zero pixels)")

    print(f"\nOutput in: {out_dir}/")


if __name__ == '__main__':
    main()
