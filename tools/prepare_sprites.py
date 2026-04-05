#!/usr/bin/env python3
"""
Prepare DOOM sprites for Atari VBXE Doom2D engine.

Takes extracted DOOM PNG sprites, resizes them to target dimensions,
and exports as:
- Raw 8bpp indexed bitmap (palette index per pixel, 0=transparent)
- Preview PNGs at target size
- Combined spritesheet.bin for VBXE VRAM upload
- Combined tilesheet.bin for VBXE VRAM upload
- MADS include file with sprite/tile metadata

Usage:
    python prepare_sprites.py
"""

import os
import sys
import struct
from PIL import Image
import numpy as np

# Add tools directory to path so we can import wad_extract
sys.path.insert(0, os.path.dirname(__file__))
from wad_extract import WADFile, extract_wall_texture

# Paths
EXTRACT_DIR = os.path.join(os.path.dirname(__file__), '..', 'extracted')
SPRITES_PNG = os.path.join(EXTRACT_DIR, 'sprites', 'png')
PALETTE_BIN = os.path.join(EXTRACT_DIR, 'palette', 'palette.bin')
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), '..', 'data')
WAD_PATH = os.path.join(os.path.dirname(__file__), '..', 'DOOM.WAD')

# ============================================
# Load DOOM palette
# ============================================
def load_palette():
    """Load DOOM palette from extracted palette.bin (7-bit VBXE format)."""
    with open(PALETTE_BIN, 'rb') as f:
        data = f.read()
    # Format: 256 R values, 256 G values, 256 B values (7-bit each)
    palette = []
    for i in range(256):
        r = data[i] << 1           # 7-bit -> 8-bit
        g = data[256 + i] << 1
        b = data[512 + i] << 1
        palette.append((r, g, b))
    return palette


def find_closest_color(r, g, b, palette, skip_zero=True):
    """Find closest palette index for given RGB color."""
    best_idx = 0
    best_dist = 999999
    start = 1 if skip_zero else 0  # skip index 0 (transparent)
    for i in range(start, 256):
        pr, pg, pb = palette[i]
        dist = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
        if dist < best_dist:
            best_dist = dist
            best_idx = i
    return best_idx


# ============================================
# Sprite definitions
# ============================================

# Format: (source_png, target_width, target_height, name)
PLAYER_SPRITES = [
    ('PLAYA3A7.png',  16, 32, 'player_idle'),
    ('PLAYB3B7.png',  16, 32, 'player_walk1'),
    ('PLAYC3C7.png',  16, 32, 'player_walk2'),
    ('PLAYD3D7.png',  16, 32, 'player_walk3'),
    ('PLAYE3E7.png',  16, 32, 'player_shoot'),
    ('PLAYH0.png',    16, 32, 'player_death1'),
]

ZOMBIE_SPRITES = [
    ('POSSA3A7.png',  16, 32, 'zombie_idle'),
    ('POSSB3B7.png',  16, 32, 'zombie_walk1'),
    ('POSSC3C7.png',  16, 32, 'zombie_walk2'),
    ('POSSD3D7.png',  16, 32, 'zombie_walk3'),
    ('POSSE3E7.png',  16, 32, 'zombie_shoot'),
    ('POSSH0.png',    16, 32, 'zombie_death1'),
]

IMP_SPRITES = [
    ('TROOA3A7.png',  16, 32, 'imp_idle'),
    ('TROOB3B7.png',  16, 32, 'imp_walk1'),
    ('TROOC3C7.png',  16, 32, 'imp_walk2'),
    ('TROOD3D7.png',  16, 32, 'imp_walk3'),
    ('TROOE3E7.png',  16, 32, 'imp_shoot'),
    ('TROOI0.png',    16, 32, 'imp_death1'),
]

PINKY_SPRITES = [
    ('SARGA3A7.png',  16, 32, 'pinky_idle'),
    ('SARGB3B7.png',  16, 32, 'pinky_walk1'),
    ('SARGC3C7.png',  16, 32, 'pinky_walk2'),
    ('SARGD3D7.png',  16, 32, 'pinky_walk3'),
    ('SARGE3.png',    16, 32, 'pinky_attack'),
    ('SARGI0.png',    16, 32, 'pinky_death1'),
]

CACODEMON_SPRITES = [
    ('HEADA3A7.png',  16, 32, 'caco_idle'),
    ('HEADB3B7.png',  16, 32, 'caco_walk1'),
    ('HEADC3C7.png',  16, 32, 'caco_walk2'),
    ('HEADD3D7.png',  16, 32, 'caco_walk3'),
    ('HEADE3E7.png',  16, 32, 'caco_shoot'),
    ('HEADF3F7.png',  16, 32, 'caco_death1'),
]

SHOTGUN_SPRITES = [
    ('SPOSA3A7.png',  16, 32, 'shotgun_idle'),
    ('SPOSB3B7.png',  16, 32, 'shotgun_walk1'),
    ('SPOSC3C7.png',  16, 32, 'shotgun_walk2'),
    ('SPOSD3D7.png',  16, 32, 'shotgun_walk3'),
    ('SPOSE3E7.png',  16, 32, 'shotgun_shoot'),
    ('SPOSH0.png',    16, 32, 'shotgun_death1'),
]

BARON_SPRITES = [
    ('BOSSA3A7.png',  16, 32, 'baron_idle'),
    ('BOSSB3B7.png',  16, 32, 'baron_walk1'),
    ('BOSSC3C7.png',  16, 32, 'baron_walk2'),
    ('BOSSD3D7.png',  16, 32, 'baron_walk3'),
    ('BOSSE3.png',    16, 32, 'baron_shoot'),
    ('BOSSI0.png',    16, 32, 'baron_death1'),
]

PROJECTILE_SPRITES = [
    ('BAL1A0.png',     8,  8, 'projectile1'),
    ('BAL1B0.png',     8,  8, 'projectile2'),
]

PICKUP_SPRITES = [
    ('MEDIA0.png',    16, 16, 'medikit'),
    ('STIMA0.png',    16, 16, 'stimpack'),
    ('BON1A0.png',    16, 16, 'health_bonus'),
    ('CLIPA0.png',    16, 16, 'ammo_clip'),
]

ALL_SPRITES = (PLAYER_SPRITES + ZOMBIE_SPRITES + IMP_SPRITES +
               PINKY_SPRITES + CACODEMON_SPRITES +
               SHOTGUN_SPRITES + BARON_SPRITES +
               PROJECTILE_SPRITES + PICKUP_SPRITES)

# Character groups: (name, sprite_list) - order must match enemy type indices
CHARACTER_GROUPS = [
    ('player', PLAYER_SPRITES),
    ('zombie', ZOMBIE_SPRITES),
    ('imp', IMP_SPRITES),
    ('pinky', PINKY_SPRITES),
    ('caco', CACODEMON_SPRITES),
    ('shotgun', SHOTGUN_SPRITES),
    ('baron', BARON_SPRITES),
]

# Enemy groups: (name, hp) - order = EN_ZOMBIE=0, EN_IMP=1, etc.
ENEMY_GROUPS = [
    ('zombie', 3),
    ('imp', 5),
    ('pinky', 8),
    ('caco', 12),
    ('shotgun', 6),
    ('baron', 20),
]


# ============================================
# Tile definitions (generated, not from DOOM)
# ============================================

def extract_flat_from_wad(wad, flat_name):
    """Extract a 64x64 flat from the WAD and return its raw 4096-byte data.

    Flats are stored between F_START and F_END markers as raw 64x64
    indexed pixel data (no header, just 4096 bytes using DOOM palette).
    Returns None if not found.
    """
    data = wad.read_lump(flat_name)
    if data and len(data) == 4096:
        return data
    return None


def downscale_flat_to_tile(flat_data, doom_palette, vbxe_palette, brightness=1.4):
    """Downscale a 64x64 DOOM flat to 16x16 tile using 4x4 block averaging.

    flat_data: 4096 bytes of raw DOOM palette indices (64x64)
    doom_palette: DOOM's original 8-bit RGB palette (from PLAYPAL)
    vbxe_palette: our 7-bit VBXE palette used for find_closest_color
    brightness: multiplier to compensate for 7-bit palette darkening (1.0=no change)

    Returns 256 bytes of VBXE palette indices (16x16).
    """
    tile = bytearray(256)
    for ty in range(16):
        for tx in range(16):
            # Average the 4x4 block of source pixels
            r_sum, g_sum, b_sum = 0, 0, 0
            for dy in range(4):
                for dx in range(4):
                    sx = tx * 4 + dx
                    sy = ty * 4 + dy
                    idx = flat_data[sy * 64 + sx]
                    r, g, b = doom_palette[idx]
                    r_sum += r
                    g_sum += g
                    b_sum += b
            r_avg = min(255, int(r_sum // 16 * brightness))
            g_avg = min(255, int(g_sum // 16 * brightness))
            b_avg = min(255, int(b_sum // 16 * brightness))
            tile[ty * 16 + tx] = find_closest_color(r_avg, g_avg, b_avg, vbxe_palette, skip_zero=False)
    return bytes(tile)


def load_doom_palette_from_wad(wad):
    """Load the original 8-bit DOOM palette (PLAYPAL) from the WAD."""
    data = wad.read_lump('PLAYPAL')
    if not data:
        return None
    palette = []
    for i in range(256):
        r = data[i * 3]
        g = data[i * 3 + 1]
        b = data[i * 3 + 2]
        palette.append((r, g, b))
    return palette


def downscale_walltex_to_tile(tex_pixels, tex_w, tex_h, doom_palette, vbxe_palette, brightness=1.2):
    """Downscale a DOOM wall texture to 16x16 tile using block averaging.

    tex_pixels: raw bytes (tex_w * tex_h) of DOOM palette indices
    Returns 256 bytes of VBXE palette indices (16x16).
    """
    tile = bytearray(256)
    block_w = tex_w // 16
    block_h = tex_h // 16
    if block_w < 1: block_w = 1
    if block_h < 1: block_h = 1
    for ty in range(16):
        for tx in range(16):
            r_sum, g_sum, b_sum, count = 0, 0, 0, 0
            for dy in range(block_h):
                for dx in range(block_w):
                    sx = tx * block_w + dx
                    sy = ty * block_h + dy
                    if sx < tex_w and sy < tex_h:
                        idx = tex_pixels[sy * tex_w + sx]
                        r, g, b = doom_palette[idx]
                        r_sum += r
                        g_sum += g
                        b_sum += b
                        count += 1
            if count > 0:
                r_avg = min(255, int(r_sum // count * brightness))
                g_avg = min(255, int(g_sum // count * brightness))
                b_avg = min(255, int(b_sum // count * brightness))
                tile[ty * 16 + tx] = find_closest_color(r_avg, g_avg, b_avg, vbxe_palette, skip_zero=False)
    return bytes(tile)


def generate_tiles(palette):
    """Generate tiles using real DOOM WAD flats where possible.

    Extracts flats from DOOM.WAD, downscales 64x64 -> 16x16, and maps
    to our VBXE palette. Falls back to generated patterns for door/sky.
    """
    tiles = {}

    # Try to load WAD for real textures
    wad = None
    doom_palette = None
    if os.path.exists(WAD_PATH):
        try:
            wad = WADFile(WAD_PATH)
            doom_palette = load_doom_palette_from_wad(wad)
            print(f"  Loaded DOOM.WAD for flat extraction")
        except Exception as e:
            print(f"  WARNING: Could not load WAD: {e}")

    # Flat assignments: (tile_name, list of candidate flat names)
    flat_assignments = [
        ('wall',    ['FLAT20', 'FLAT18', 'FLAT23']),
        ('floor',   ['CEIL3_2', 'FLOOR0_1', 'FLAT5_4']),
        ('ceiling', ['MFLR8_1', 'CEIL3_5', 'CEIL5_2']),
    ]

    # Tile 0: Empty (all transparent = index 0)
    tiles['empty'] = bytes(256)

    # Extract real flats for wall, floor, ceiling
    for tile_name, candidates in flat_assignments:
        extracted = False
        if wad and doom_palette:
            for flat_name in candidates:
                flat_data = extract_flat_from_wad(wad, flat_name)
                if flat_data:
                    tiles[tile_name] = downscale_flat_to_tile(flat_data, doom_palette, palette)
                    print(f"  Tile '{tile_name}': extracted from WAD flat {flat_name}")
                    extracted = True
                    break
        if not extracted:
            print(f"  Tile '{tile_name}': WAD flat not available, using generated pattern")
            tiles[tile_name] = _generate_fallback_tile(tile_name, palette)


    # Tile 4: Door - generated pattern (no good flat equivalent)
    door_color = find_closest_color(160, 80, 0, palette)
    door_frame = find_closest_color(100, 50, 0, palette)
    door = bytearray(256)
    for y in range(16):
        for x in range(16):
            if x == 0 or x == 15:
                door[y * 16 + x] = door_frame
            elif y == 0 or y == 15:
                door[y * 16 + x] = door_frame
            elif x == 7 or x == 8:
                door[y * 16 + x] = door_frame  # center line
            else:
                door[y * 16 + x] = door_color
    tiles['door'] = bytes(door)
    print(f"  Tile 'door': generated pattern")

    # Tile 5: Sky - generated gradient pattern
    sky_blue = find_closest_color(64, 128, 255, palette)
    sky_light = find_closest_color(100, 160, 255, palette)
    sky = bytearray(256)
    for y in range(16):
        for x in range(16):
            if (x + y * 2) % 13 == 0:
                sky[y * 16 + x] = sky_light
            else:
                sky[y * 16 + x] = sky_blue
    tiles['sky'] = bytes(sky)
    print(f"  Tile 'sky': generated pattern")

    # Tile 6: Dark background (interior) - from DOOM WAD flat
    darkbg_extracted = False
    if wad and doom_palette:
        for flat_name in ['DEM1_1', 'FLOOR7_1', 'FLAT10']:
            flat_data = extract_flat_from_wad(wad, flat_name)
            if flat_data:
                tiles['darkbg'] = downscale_flat_to_tile(flat_data, doom_palette, palette, brightness=0.7)
                print(f"  Tile 'darkbg': extracted from WAD flat {flat_name} (low brightness)")
                darkbg_extracted = True
                break
    if not darkbg_extracted:
        dark_col = find_closest_color(24, 16, 8, palette)
        tiles['darkbg'] = bytes([dark_col] * 256)
        print(f"  Tile 'darkbg': generated solid dark")

    # Tiles 7-10: Wall textures from DOOM WAD (composite patches)
    wall_texture_assignments = [
        ('techwall',  ['STARTAN2', 'STARG3']),      # tile 7: tech/tan wall
        ('metalwall', ['METAL1']),                    # tile 8: corrugated metal
        ('support',   ['SUPPORT2', 'GRAY5']),         # tile 9: metal support/columns
        ('stonewall', ['STONE2', 'BROWN1']),          # tile 10: gray stone
    ]

    for tile_name, candidates in wall_texture_assignments:
        extracted = False
        if wad and doom_palette:
            for tex_name in candidates:
                result = extract_wall_texture(wad, tex_name)
                if result:
                    tw, th, tex_pixels = result
                    tiles[tile_name] = downscale_walltex_to_tile(
                        tex_pixels, tw, th, doom_palette, palette)
                    print(f"  Tile '{tile_name}': extracted from WAD wall texture {tex_name}")
                    extracted = True
                    break
        if not extracted:
            tiles[tile_name] = bytes(256)
            print(f"  Tile '{tile_name}': not found, empty placeholder")

    # Tiles 11-15: reserved (empty)
    for i in range(11, 16):
        tiles[f'reserved_{i}'] = bytes(256)

    return tiles


def _generate_fallback_tile(tile_name, palette):
    """Generate a simple fallback tile pattern if WAD extraction fails."""
    tile = bytearray(256)
    if tile_name == 'wall':
        wall_brown = find_closest_color(128, 64, 0, palette)
        wall_dark = find_closest_color(80, 40, 0, palette)
        wall_line = find_closest_color(96, 48, 0, palette)
        for y in range(16):
            for x in range(16):
                if y == 0 or y == 8:
                    tile[y * 16 + x] = wall_line
                elif x == 0 and y < 8:
                    tile[y * 16 + x] = wall_line
                elif x == 8 and y >= 8:
                    tile[y * 16 + x] = wall_line
                elif (x + y) % 7 == 0:
                    tile[y * 16 + x] = wall_dark
                else:
                    tile[y * 16 + x] = wall_brown
    elif tile_name == 'floor':
        floor_gray = find_closest_color(128, 128, 128, palette)
        floor_dark = find_closest_color(96, 96, 96, palette)
        for y in range(16):
            for x in range(16):
                if (x + y * 3) % 11 == 0:
                    tile[y * 16 + x] = floor_dark
                else:
                    tile[y * 16 + x] = floor_gray
    elif tile_name == 'ceiling':
        ceil_dark = find_closest_color(64, 64, 64, palette)
        ceil_light = find_closest_color(80, 80, 80, palette)
        for y in range(16):
            for x in range(16):
                if (x * 2 + y) % 9 == 0:
                    tile[y * 16 + x] = ceil_light
                else:
                    tile[y * 16 + x] = ceil_dark
    return bytes(tile)


# ============================================
# Sprite conversion
# ============================================

def compute_group_scale(sprite_list, sprites_png_dir):
    """Compute uniform scale for a character group.

    Finds the scale factor that fits the LARGEST sprite in the group
    into the target dimensions, then returns that scale so all sprites
    in the group have consistent size.
    """
    max_w, max_h = 0, 0
    target_w, target_h = 0, 0
    for src_png, tw, th, name in sprite_list:
        target_w, target_h = tw, th
        png_path = os.path.join(sprites_png_dir, src_png)
        if os.path.exists(png_path):
            img = Image.open(png_path)
            max_w = max(max_w, img.size[0])
            max_h = max(max_h, img.size[1])
    if max_w == 0 or max_h == 0:
        return None
    group_scale = min(target_w / max_w, target_h / max_h)
    return group_scale


def convert_sprite(png_path, target_w, target_h, palette, group_scale=None):
    """Load PNG, resize, convert to 8bpp indexed with DOOM palette.

    If group_scale is provided, uses that fixed scale for consistent sizing
    across a character group. Otherwise computes per-sprite scale.

    Returns raw bytes (target_w * target_h), index 0 = transparent.
    """
    img = Image.open(png_path).convert('RGBA')

    # Resize maintaining aspect ratio, center in target
    orig_w, orig_h = img.size
    if group_scale is not None:
        scale = group_scale
    else:
        scale = min(target_w / orig_w, target_h / orig_h)
    new_w = max(1, int(orig_w * scale))
    new_h = max(1, int(orig_h * scale))

    img_resized = img.resize((new_w, new_h), Image.LANCZOS)

    # Create output buffer (0 = transparent)
    raw = bytearray(target_w * target_h)

    # Center in target
    ox = (target_w - new_w) // 2
    oy = target_h - new_h  # align to bottom (feet on ground)

    pixels = img_resized.load()
    for y in range(new_h):
        for x in range(new_w):
            r, g, b, a = pixels[x, y]
            if a < 128:
                continue  # transparent
            dx = ox + x
            dy = oy + y
            if 0 <= dx < target_w and 0 <= dy < target_h:
                idx = find_closest_color(r, g, b, palette)
                raw[dy * target_w + dx] = idx

    return bytes(raw)


def normalize_sprite_group(sprites_raw, width, height):
    """Ensure all sprites in a group have the same first visible row.

    Finds the highest (earliest) first visible row across the group,
    then clears any rows above that in sprites that start earlier.
    This prevents stray top pixels from blinking with animation cycling.
    """
    # Find the latest (highest row number) first visible row
    max_first_row = 0
    for raw in sprites_raw:
        for row in range(height):
            row_data = raw[row * width:(row + 1) * width]
            if any(b != 0 for b in row_data):
                max_first_row = max(max_first_row, row)
                break
    # Clear rows above max_first_row in all sprites
    result = []
    for raw in sprites_raw:
        raw = bytearray(raw)
        for row in range(max_first_row):
            for x in range(width):
                raw[row * width + x] = 0
        result.append(bytes(raw))
    return result


def flip_sprite_horizontal(raw_data, width, height):
    """Flip raw sprite data horizontally (mirror left-right)."""
    flipped = bytearray(width * height)
    for y in range(height):
        for x in range(width):
            flipped[y * width + x] = raw_data[y * width + (width - 1 - x)]
    return bytes(flipped)


def save_preview(raw_data, width, height, palette, output_path):
    """Save raw indexed data as PNG preview."""
    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    for y in range(height):
        for x in range(width):
            idx = raw_data[y * width + x]
            if idx == 0:
                continue  # transparent
            r, g, b = palette[idx]
            img.putpixel((x, y), (r, g, b, 255))

    # Scale up 4x for visibility
    img_big = img.resize((width * 4, height * 4), Image.NEAREST)
    img_big.save(output_path)


# ============================================
# MADS include file generation
# ============================================

def generate_mads_include(sprite_info, tile_names, character_groups, enemy_groups, pickup_sprites):
    """Generate MADS assembler include with ALL sprite/tile constants and tables.

    character_groups: list of (group_name, sprite_list) - e.g. [('player', [...]), ('zombie', [...])]
    enemy_groups: list of (group_name, hp) - e.g. [('zombie', 3), ('imp', 5)]
    pickup_sprites: list of (pickup_name, sprite_name) - e.g. [('medikit', 'medikit')]
    """
    lines = [
        ';==============================================',
        '; Auto-generated sprite/tile definitions',
        '; DO NOT EDIT - generated by prepare_sprites.py',
        ';==============================================',
        '',
    ]

    # Build sprite index + offset map
    offset = 0
    sprite_idx = 0
    sprite_offsets = {}  # name -> (index, offset)
    for name, w, h, raw_size in sprite_info:
        if name.startswith('_'):
            offset += raw_size
            continue
        sprite_offsets[name] = (sprite_idx, offset)
        offset += raw_size
        sprite_idx += 1

    # --- Sprite index constants ---
    lines.append('; Sprite indices')
    for name, w, h, _ in sprite_info:
        if name.startswith('_'):
            continue
        idx, off = sprite_offsets[name]
        lines.append(f'SPR_{name.upper():24s} equ {idx:3d}  ; {w}x{h}, offset ${off:04X}')
    lines.append(f'SPRITESHEET_SIZE         equ ${offset:04X}  ; {offset} bytes total')
    lines.append('')

    # --- Character group base indices (collected, not re-declared) ---
    char_base_indices = {}
    for gname, gsprites in character_groups:
        idle_name = gsprites[0][3]
        if idle_name in sprite_offsets:
            char_base_indices[gname] = sprite_offsets[idle_name][0]

    # Player shorthand aliases
    player_base = char_base_indices.get('player', 0)
    lines.append('; Player sprite aliases')
    lines.append(f'SPR_PL_IDLE              equ {player_base}')
    lines.append(f'SPR_PL_W1                equ {player_base+1}')
    lines.append(f'SPR_PL_W2                equ {player_base+2}')
    lines.append(f'SPR_PL_W3                equ {player_base+3}')
    lines.append(f'SPR_PL_SHOOT             equ {player_base+4}')
    lines.append(f'SPR_PL_DEATH             equ {player_base+5}')
    lines.append('')

    # --- Projectile indices ---
    for name in ['projectile1', 'projectile2']:
        if name in sprite_offsets:
            idx = sprite_offsets[name][0]
            cname = 'SPR_PROJ1' if '1' in name else 'SPR_PROJ2'
            lines.append(f'{cname:33s} equ {idx:3d}')
    lines.append('')

    # --- Pickup base ---
    if pickup_sprites:
        first_pickup = pickup_sprites[0][1]
        if first_pickup in sprite_offsets:
            lines.append(f'SPR_PICKUP_BASE          equ {sprite_offsets[first_pickup][0]:3d}')
    lines.append('')

    # --- Mirror offset ---
    # Find first mirrored sprite
    for name, w, h, _ in sprite_info:
        if name.endswith('_L') and not name.startswith('_'):
            mirror_idx = sprite_offsets[name][0]
            non_mirror = name[:-2]
            if non_mirror in sprite_offsets:
                mirror_offset = mirror_idx - sprite_offsets[non_mirror][0]
                lines.append(f'MIRROR_OFFSET            equ {mirror_offset:3d}')
                break
    lines.append('')

    # --- Enemy type constants ---
    lines.append('; Enemy types')
    for i, (gname, hp) in enumerate(enemy_groups):
        lines.append(f'EN_{gname.upper():28s} equ {i}')
    lines.append('')

    # --- Offset tables (for data.asm) ---
    lines.append('; Sprite VRAM offset tables')
    lines.append('spr_off_lo')
    for name, w, h, _ in sprite_info:
        if name.startswith('_'):
            continue
        idx, off = sprite_offsets[name]
        lines.append(f'        dta <${off:04X}  ; {name}')

    lines.append('')
    lines.append('spr_off_hi')
    for name, w, h, _ in sprite_info:
        if name.startswith('_'):
            continue
        idx, off = sprite_offsets[name]
        lines.append(f'        dta >${off:04X}  ; {name}')

    lines.append('')
    lines.append('; Sprite width/height tables')
    lines.append('spr_w')
    for name, w, h, _ in sprite_info:
        if not name.startswith('_'):
            lines.append(f'        dta {w}  ; {name}')
    lines.append('')
    lines.append('spr_h')
    for name, w, h, _ in sprite_info:
        if not name.startswith('_'):
            lines.append(f'        dta {h}  ; {name}')

    # --- Enemy tables ---
    lines.append('')
    lines.append('; Enemy base sprite + HP tables')
    lines.append('en_base_spr')
    for gname, hp in enemy_groups:
        base = char_base_indices.get(gname, 0)
        lines.append(f'        dta {base}  ; {gname}')
    lines.append('')
    lines.append('en_hp_tab')
    for gname, hp in enemy_groups:
        lines.append(f'        dta {hp}  ; {gname}')

    # --- Pickup sprite table ---
    # Order: PK_HEALTH=0 -> stimpack, PK_AMMO=1 -> ammo_clip, PK_MEDIKIT=2 -> medikit
    lines.append('')
    lines.append('; Pickup type -> sprite index')
    lines.append('pk_spr_tab')
    pk_type_map = {'stimpack': 0, 'ammo_clip': 1, 'medikit': 2,
                   'health_bonus': 0}  # health_bonus also health type
    # Fixed order: health(stimpack), ammo(ammo_clip), medikit
    pk_order = [('stimpack', 'PK_HEALTH'), ('ammo_clip', 'PK_AMMO'), ('medikit', 'PK_MEDIKIT')]
    for pk_sprite, pk_label in pk_order:
        if pk_sprite in sprite_offsets:
            lines.append(f'        dta {sprite_offsets[pk_sprite][0]}  ; {pk_label} -> {pk_sprite}')

    # --- Tile definitions ---
    lines.append('')
    lines.append('; Tile indices')
    for i, name in enumerate(tile_names):
        lines.append(f'TILE_{name.upper():20s} equ {i:3d}  ; offset ${i*256:04X}')
    lines.append(f'TILESHEET_SIZE           equ ${len(tile_names)*256:04X}')

    return '\n'.join(lines)


# ============================================
# Main
# ============================================

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    os.makedirs(os.path.join(OUTPUT_DIR, 'preview'), exist_ok=True)

    print("Loading DOOM palette...")
    palette = load_palette()
    print(f"  Loaded {len(palette)} colors")

    # ---- Compute group scales ----
    print("\nComputing uniform group scales...")
    scale_groups = [PLAYER_SPRITES, ZOMBIE_SPRITES, IMP_SPRITES,
                    PINKY_SPRITES, CACODEMON_SPRITES]
    group_scales = {}
    for group in scale_groups:
        gs = compute_group_scale(group, SPRITES_PNG)
        if gs:
            for _, _, _, name in group:
                group_scales[name] = gs
            print(f"  {group[0][3].split('_')[0]:10s}: group_scale = {gs:.4f}")

    # ---- Convert sprites ----
    print("\nConverting sprites...")
    spritesheet = bytearray()
    sprite_info = []

    for src_png, tw, th, name in ALL_SPRITES:
        png_path = os.path.join(SPRITES_PNG, src_png)
        if not os.path.exists(png_path):
            print(f"  WARNING: {src_png} not found, creating blank")
            raw = bytes(tw * th)
        else:
            gs = group_scales.get(name)
            raw = convert_sprite(png_path, tw, th, palette, group_scale=gs)
            print(f"  {name:20s} ({src_png:15s}) -> {tw}x{th} = {len(raw)} bytes")

        # Save individual raw
        with open(os.path.join(OUTPUT_DIR, f'{name}.bin'), 'wb') as f:
            f.write(raw)

        # Save preview
        save_preview(raw, tw, th, palette,
                    os.path.join(OUTPUT_DIR, 'preview', f'{name}.png'))

        spritesheet.extend(raw)
        sprite_info.append((name, tw, th, len(raw)))

    # Normalize character groups: ensure consistent first visible row
    # across idle, walk1-3, shoot (not death) to prevent visual jumping
    print("\nNormalizing sprite groups...")
    for _, group in CHARACTER_GROUPS:
        # Collect active sprites (idle + walk + shoot = indices 0-4, skip death=5)
        active_raws = []
        active_names = []
        for i, (_, tw, th, name) in enumerate(group):
            if i >= 5:  # skip death frame
                break
            raw_path = os.path.join(OUTPUT_DIR, f'{name}.bin')
            with open(raw_path, 'rb') as f:
                active_raws.append(f.read())
            active_names.append(name)

        if active_raws:
            normalized = normalize_sprite_group(active_raws, tw, th)
            for name, nraw in zip(active_names, normalized):
                with open(os.path.join(OUTPUT_DIR, f'{name}.bin'), 'wb') as f:
                    f.write(nraw)
            # Check what changed
            first_rows = []
            for nraw in normalized:
                for row in range(th):
                    if any(nraw[row*tw+x] != 0 for x in range(tw)):
                        first_rows.append(row)
                        break
                else:
                    first_rows.append(th)
            print(f"  {group[0][3].split('_')[0]:10s}: first rows = {first_rows}")

    # Rebuild spritesheet with normalized data
    spritesheet = bytearray()
    sprite_info = []
    for src_png, tw, th, name in ALL_SPRITES:
        raw_path = os.path.join(OUTPUT_DIR, f'{name}.bin')
        with open(raw_path, 'rb') as f:
            raw = f.read()
        spritesheet.extend(raw)
        sprite_info.append((name, tw, th, len(raw)))

    # Pad spritesheet to 256-byte boundary before mirrored sprites
    # This ensures mirrored sprite VRAM addresses have low byte = $00
    # which avoids a VBXE blitter artifact with $xx80 source addresses
    pad_needed = (256 - (len(spritesheet) % 256)) % 256
    if pad_needed > 0:
        print(f"\nAdding {pad_needed} bytes padding for 256-byte alignment")
        spritesheet.extend(bytes(pad_needed))
        sprite_info.append(('_align_pad', 0, 0, pad_needed))

    # Generate mirrored (horizontally flipped) versions of player and zombie sprites
    print("\nGenerating mirrored sprites...")
    mirror_sprites = (PLAYER_SPRITES + ZOMBIE_SPRITES + IMP_SPRITES +
                       PINKY_SPRITES + CACODEMON_SPRITES)
    for src_png, tw, th, name in mirror_sprites:
        mirror_name = name + '_L'
        # Read the already-converted raw data
        raw_path = os.path.join(OUTPUT_DIR, f'{name}.bin')
        with open(raw_path, 'rb') as f:
            raw = f.read()
        flipped = flip_sprite_horizontal(raw, tw, th)
        print(f"  {mirror_name:20s} (flipped {name}) -> {tw}x{th} = {len(flipped)} bytes")

        # Save individual raw
        with open(os.path.join(OUTPUT_DIR, f'{mirror_name}.bin'), 'wb') as f:
            f.write(flipped)

        # Save preview
        save_preview(flipped, tw, th, palette,
                    os.path.join(OUTPUT_DIR, 'preview', f'{mirror_name}.png'))

        spritesheet.extend(flipped)
        sprite_info.append((mirror_name, tw, th, len(flipped)))

    # Save combined spritesheet
    with open(os.path.join(OUTPUT_DIR, 'spritesheet.bin'), 'wb') as f:
        f.write(spritesheet)
    print(f"\nSpritesheet: {len(spritesheet)} bytes ({len(sprite_info)} sprites)")

    # ---- Generate tiles ----
    print("\nGenerating tiles...")
    tiles = generate_tiles(palette)
    tilesheet = bytearray()
    tile_names = []

    for name, data in tiles.items():
        tilesheet.extend(data)
        tile_names.append(name)
        print(f"  {name:20s} 16x16 = 256 bytes")

        # Save preview
        save_preview(data, 16, 16, palette,
                    os.path.join(OUTPUT_DIR, 'preview', f'tile_{name}.png'))

    with open(os.path.join(OUTPUT_DIR, 'tilesheet.bin'), 'wb') as f:
        f.write(tilesheet)
    print(f"\nTilesheet: {len(tilesheet)} bytes ({len(tile_names)} tiles)")

    # ---- Save palette for direct VBXE use ----
    # Copy palette.bin to data dir
    import shutil
    shutil.copy2(PALETTE_BIN, os.path.join(OUTPUT_DIR, 'palette.bin'))
    print(f"\nPalette copied to data/palette.bin")

    # ---- Generate MADS include ----
    include_code = generate_mads_include(sprite_info, tile_names, CHARACTER_GROUPS, ENEMY_GROUPS, PICKUP_SPRITES)
    include_path = os.path.join(os.path.dirname(__file__), '..', 'source', 'sprite_defs.asm')
    with open(include_path, 'w') as f:
        f.write(include_code)
    print(f"MADS include: src/sprite_defs.asm")

    # ---- Summary ----
    print(f"""
==============================
 DOOM2D Asset Preparation Done
==============================
 Sprites: {len(sprite_info):3d} ({len(spritesheet)} bytes)
 Tiles:   {len(tile_names):3d} ({len(tilesheet)} bytes)
 Palette: 256 colors (768 bytes)
 Total VRAM needed: {len(spritesheet) + len(tilesheet)} bytes

 Files in data/:
   spritesheet.bin  - all sprites sequential
   tilesheet.bin    - all tiles sequential
   palette.bin      - VBXE 7-bit RGB palette
   *.bin            - individual sprite files
   preview/*.png    - 4x scaled previews

 Files in src/:
   sprite_defs.asm  - MADS equates and tables
""")


if __name__ == '__main__':
    main()
