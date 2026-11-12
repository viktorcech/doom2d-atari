#!/usr/bin/env python3
"""
DOOM 2D Atari - Map text to binary converter

Converts a text-based .map file (2 chars per tile, up to MAP_W x MAP_H;
smaller maps are padded with empty tiles) to the map's VRAM image: rows of
MAP_STRIDE bytes (source/constants.asm), MAP_H*MAP_STRIDE bytes.

Also extracts entity spawn positions to a separate .ent file and writes the
.lvl disk record: LVL_HDR_SECTORS of header + entities, the map's VRAM
image, the tile tables (tile_solid/oneway, 512 B), the level's tileset
(256 x 64 B), the foreground rects and the triggers from the .tiles file
next to the .map (source/diskio.asm load_level).

Usage:
    python map2bin.py input.map output.bin [output.ent]
    python map2bin.py ../maps/test.map ../data/test_map.bin
"""

import sys
import os

MAP_W = 100
MAP_H = 100
MAP_STRIDE = 128                # keep in step with source/constants.asm
MAX_ENEMIES, MAX_PICKUPS, MAX_DECOR = 66, 96, 16   # source/constants.asm
CELL = 8                        # TW/TH: one map cell in world pixels


class At(int):
    """A cell index that also carries the exact pixel (from a '; ENT' line)."""
    def __new__(cls, cell, px):
        obj = int.__new__(cls, cell)
        obj.px = px
        return obj


# Sky name -> .lvl header +8 index (tools/sky2vbxe.py: the texture of each)
SKY_NAMES = [
    'D2DSKY1', 'D2DSKY2', 'D2DSKY3', 'D2DSKY4',
    'DFSKY0', 'DFSKY1', 'DFSKY2', 'DFSKY3', 'DFSKY4',
]

# pickup name -> pk_type (constants.asm PK_*)
PTYPE = {'health': 0, 'ammo': 1, 'medikit': 2,
         'greenarmor': 3, 'bluearmor': 4, 'soulsphere': 5,
         'keyred': 6, 'keyblue': 7, 'keyyellow': 8,
         'shotgunpk': 9, 'shells': 10,
         'pistolpk': 11, 'chaingunpk': 12, 'rocketpk': 13, 'rocketbox': 14,
         'plasmagun': 15, 'cells': 16, 'bfgpk': 17, 'rocket1': 18,
         'healthbonus': 19, 'armorbonus': 20, 'chainsaw': 21,
         'oxygen': 22, 'backpack': 23}


def ent_x(col):
    """Left edge of a 16 px wide entity: the exact one, else centred on col."""
    return col.px if isinstance(col, At) else max(0, col * CELL - 4)


def ent_y(row):
    """Spawn Y (the engine adds 16, the sprite height, to get the feet): the
    exact one, else feet on the top of the cell below row."""
    return row.px if isinstance(row, At) else max(0, row * CELL - 8)
LVL_HDR_BYTES = 8 * 128         # LVL_HDR_SECTORS in source/diskio.asm
FORE_SECTORS = 6                # FORE_SECTORS in source/diskio.asm
FORE_BYTES = 7 * 7 + 1 + 4 * 160        # d2df2map.FORE_BYTES
LIQ_SECTORS = 4                 # LQ_SECTORS in source/liquid.asm
LIQ_BYTES = 7 * 7 + 1 + 5 * 80          # d2df2map.LIQ_BYTES (liquid_rects)
TRIG_RAM_SECTORS = 13           # d2df2map trigger_block: RAM part, then the
ANIM_SECTORS = 2                # d2df2map ANIM_RAM_BYTES / 128 (source/anim.asm)
TRIG_SECTORS = 13 + 24          # panel cells (VRAM part, stored trimmed)


def vram_image(map_data):
    """Linear MAP_W x MAP_H tiles -> MAP_STRIDE-byte rows (VRAM / disk image)."""
    img = bytearray(MAP_H * MAP_STRIDE)
    for r in range(MAP_H):
        img[r * MAP_STRIDE:r * MAP_STRIDE + MAP_W] = map_data[r * MAP_W:(r + 1) * MAP_W]
    return img

# Character -> tile index mapping
TILE_MAP = {
    '.': 0,   # empty
    ' ': 0,   # space = empty
    '#': 1,   # wall (brick)
    # '=': 2,   # floor/platform — REMOVED
    '-': 3,   # ceiling
    'D': 4,   # door (no key)
    '{': 25,  # door red key
    '}': 26,  # door blue key
    '|': 27,  # door yellow key
    '~': 5,   # sky
    # 'b': 6,   # darkbg — REMOVED
    'T': 7,   # techwall (STARTAN2)
    # 'm': 8,   # metalwall — REMOVED
    'S': 9,   # support/columns (SUPPORT2)
    'G': 10,  # stonewall/gray (STONE2)
    'f': 11,  # tech floor (half-height)
    'o': 12,  # metal floor (half-height)
    # 'p': 13,  # stepfloor — REMOVED
    # 'g': 14,  # darkfloor — REMOVED
    # 'E': 16,  # ceil3_5 — REMOVED
    # 'F': 17,  # ceil5_1 — REMOVED
    'J': 18,  # DEM1_1 (wall)
    # 'O': 19,  # flat1 — REMOVED
    'P': 20,  # FLAT22 (wall)
    # 'U': 21,  # floor0_6 — REMOVED
    'V': 22,  # FLOOR1_1 (wall)
    'Y': 23,  # FLOOR5_1 (one-way platform)
    'q': 24,  # MFLR8_1 (wall)
    '$': 28,  # switch OFF
    'E': 30,  # exit switch OFF
    'b': 32,  # BOX01 (wall)
    'g': 33,  # BOX02 (wall)
    'p': 34,  # COMP02 (wall)
    'm': 35,  # COMP04 (wall)
    'N': 36,  # COMP05 (wall)
    'O': 37,  # WALL009 (wall)
    'U': 38,  # WALL020 (wall)
    'F': 39,  # WALL024 (wall)
    'x': 40,  # WALL026 (wall)
    'y': 41,  # WALL027 (wall)
    's': 42,  # WALL028 (wall)
    '%': 43,  # solid floor (half-height, blocks from below)
}

# Entity characters -> (underlying tile, entity type)
# Underlying tile = 0 (auto-detect from neighbor above)
# map2bin will look at the tile ABOVE the entity to determine background
ENTITY_MAP = {
    '@': (0, 'player'),
    # Enemies facing RIGHT (uppercase)
    'Z': (0, 'zombie'),
    'I': (0, 'imp'),
    'K': (0, 'pinky'),
    'C': (0, 'caco'),
    'W': (0, 'shotgun'),
    'B': (0, 'baron'),
    '>': (0, 'lostsoul'),
    # Enemies facing LEFT (lowercase, 'n' for baron since 'b'=darkbg)
    'z': (0, 'zombie'),
    'i': (0, 'imp'),
    'k': (0, 'pinky'),
    'c': (0, 'caco'),
    'w': (0, 'shotgun'),
    'n': (0, 'baron'),
    '<': (0, 'lostsoul'),
    # Pickups & exit
    'H': (0, 'health'),
    'A': (0, 'ammo'),
    'M': (0, 'medikit'),
    'X': (0, 'exit'),
    # New pickups
    '1': (0, 'greenarmor'),
    '2': (0, 'bluearmor'),
    '3': (0, 'soulsphere'),
    '4': (0, 'keyred'),
    '5': (0, 'keyblue'),
    '6': (0, 'keyyellow'),
    '7': (0, 'shotgunpk'),
    '8': (0, 'shells'),
    '9': (0, 'pistolpk'),
    'Q': (0, 'chaingunpk'),
    'R': (0, 'rocketpk'),
    'r': (0, 'rocketbox'),
    'u': (0, 'plasmagun'),
    'e': (0, 'cells'),
    'j': (0, 'bfgpk'),
    'v': (0, 'rocket1'),
    'h': (0, 'healthbonus'),
    'a': (0, 'armorbonus'),
    '0': (0, 'chainsaw'),
    '/': (0, 'oxygen'),
    ',': (0, 'backpack'),
    # Decorations
    '!': (0, 'barrel'),
    't': (0, 'torch'),
    'l': (0, 'pillar'),
    'L': (0, 'lamp'),
    'd': (0, 'deadguy'),
    '(': (0, 'evileye'),
    ')': (0, 'skulpillar'),
    '[': (0, 'eleclamp'),
    ']': (0, 'deadtree'),
    '^': (0, 'browntree'),
    '&': (0, 'hangbody'),
    '*': (0, 'hangleg'),
    '+': (0, 'impaled'),
    '=': (0, 'skullpile'),
    ':': (0, 'redtorch'),
}

# Characters that mean "facing left"
FACING_LEFT = {'z', 'i', 'k', 'c', 'w', 'n', '<'}

def convert_map(input_path, output_bin, output_ent=None):
    """Convert text map to binary."""

    with open(input_path, 'r') as f:
        lines = f.readlines()


    # Filter out comments and empty lines
    map_lines = []
    exact_ents = []                     # '; ENT' lines: (char, x, y)
    sky_name = 'D2DSKY1'  # default
    for line in lines:
        line = line.rstrip('\n\r')
        if line.startswith(';sky='):
            sky_name = line[5:].strip()
            print(f"  Sky: {sky_name}")
            continue
        if line.startswith('; ENT '):
            # '; ENT ch x y': an entity at an exact spawn position (d2df2map:
            # the original's, several may share a spot)
            ch, x, y = line[6:].split()
            exact_ents.append((ch, int(x), int(y)))
            continue
        if line.startswith(';') or len(line.strip()) == 0:
            continue
        map_lines.append(line)

    if len(map_lines) < MAP_H:
        print(f"WARNING: Only {len(map_lines)} rows, padding to {MAP_H}")
        while len(map_lines) < MAP_H:
            map_lines.append('.' * MAP_W)

    if len(map_lines) > MAP_H:
        print(f"WARNING: {len(map_lines)} rows, trimming to {MAP_H}")
        map_lines = map_lines[:MAP_H]

    # Auto-detect 2-char format (what mapedit writes): any line of 64+ chars.
    # The old 1-char maps are 32 wide; MAP_W no longer tells them apart.
    two_char = any(len(l) >= 64 for l in map_lines if l.strip())
    if two_char:
        print("  Format: 2-char per tile")

    # Convert
    map_data = bytearray(MAP_W * MAP_H)
    entities = []
    player_exact = None
    for ch, x, y in exact_ents:
        if ch == '@':                   # the player: x = zpx, y + 16 = feet
            player_exact = (x, y + 16)
            continue
        etype = ENTITY_MAP[ch][1]
        entities.append((At(x // CELL, x), At((y + 16) // CELL - 1, y), etype,
                         1 if ch in FACING_LEFT else 0, 0))
    player_spawn = None

    for row in range(MAP_H):
        line = map_lines[row]

        if two_char:
            # Parse 2-char tiles: each tile = 2 chars
            tiles_row = []
            padded = line.ljust(MAP_W * 2)
            for c in range(MAP_W):
                tiles_row.append(padded[c*2:c*2+2])
        else:
            # 1-char format (backward compat)
            padded = line.ljust(MAP_W, '.')[:MAP_W]
            tiles_row = [padded[c] + ' ' for c in range(MAP_W)]

        for col in range(MAP_W):
            pair = tiles_row[col]
            ch = pair[0]
            mod = pair[1] if len(pair) > 1 else ' '
            is_bg = (mod == 'b')

            if ch in ENTITY_MAP:
                tile_id, ent_type = ENTITY_MAP[ch]
                # Check if entity sits on a BG tile (mod = wall char)
                if mod != ' ' and mod != 'b' and mod in TILE_MAP:
                    tile_id = TILE_MAP[mod] | 0x80  # BG variant
                elif tile_id == 0:
                    # Auto-detect: use tile from row above, or empty(0) as fallback
                    SAFE_BG_TILES = {0, 5}
                    if row > 0:
                        above_line = map_lines[row - 1]
                        if two_char:
                            above_padded = above_line.ljust(MAP_W * 2)
                            above_ch2 = above_padded[col*2]
                        else:
                            above_ch2 = above_line[col] if col < len(above_line) else '.'
                        if above_ch2 in TILE_MAP:
                            above_tile = TILE_MAP[above_ch2]
                            if above_tile in SAFE_BG_TILES:
                                tile_id = above_tile
                        elif above_ch2 in ENTITY_MAP:
                            tile_id = 0
                    else:
                        tile_id = 0
                map_data[row * MAP_W + col] = tile_id
                facing = 1 if ch in FACING_LEFT else 0  # 0=right, 1=left
                entities.append((col, row, ent_type, facing, 0))  # 5th = sleep
                if ent_type == 'player':
                    player_spawn = (col, row)
                dir_str = "L" if facing else "R"
                print(f"  Entity: {ent_type} at col={col}, row={row} (px: {col*16},{row*16}) dir={dir_str}")
            elif ch in TILE_MAP:
                tile_id = TILE_MAP[ch]
                if is_bg:
                    tile_id |= 0x80  # bit 7 = BG variant (passable)
                map_data[row * MAP_W + col] = tile_id
            else:
                print(f"  WARNING: Unknown char '{ch}' at row={row}, col={col}, using empty")
                map_data[row * MAP_W + col] = 0

    # the player's start: zpx, feet zpy ('; ENT @' = the original's, exact;
    # an '@' in the grid: feet on its cell bottom)
    if player_exact:
        spawn = player_exact
    elif player_spawn:
        spawn = (ent_x(player_spawn[0]), (player_spawn[1] + 1) * CELL)
    else:
        spawn = None

    # --- Entity Y limit ------------------------------------------------------
    # All entity types now carry a 16-bit world Y (enemies, pickups, decor) and
    # the player spawn is 16-bit too, so entities can live in any row 0-31.
    # Anything NOT in Y16_TYPES (unknown future type) is still treated as 8-bit
    # and dropped below row 15, with a warning, so the build can't silently
    # place it at a wrapped Y.  Keep this set in sync with the engine.
    ENT_MAX_ROW = 15
    Y16_TYPES = {
        # enemies
        'zombie', 'imp', 'pinky', 'caco', 'shotgun', 'baron', 'lostsoul',
        # pickups
        'health', 'ammo', 'medikit', 'greenarmor', 'bluearmor', 'soulsphere',
        'keyred', 'keyblue', 'keyyellow', 'shotgunpk', 'shells', 'pistolpk',
        'chaingunpk', 'rocketpk', 'rocketbox', 'plasmagun', 'cells', 'bfgpk',
        'rocket1', 'healthbonus', 'armorbonus', 'chainsaw', 'oxygen', 'backpack',
        # decor
        'barrel', 'torch', 'pillar', 'lamp', 'deadguy', 'techthing', 'evileye',
        'skulpillar', 'eleclamp', 'deadtree', 'browntree', 'hangbody', 'hangleg',
        'impaled', 'skullpile', 'redtorch',
    }
    dropped = [e for e in entities
               if e[2] != 'player' and e[2] not in Y16_TYPES and e[1] > ENT_MAX_ROW]
    if dropped:
        print(f"\nWARNING: dropping {len(dropped)} decor entity(ies) below row"
              f" {ENT_MAX_ROW} (decor Y is still 8-bit -- keep decor in rows"
              f" 0-{ENT_MAX_ROW}):")
        for col, row, etype, *_ in dropped:
            print(f"    - {etype} at col={col}, row={row}")
    entities = [e for e in entities
                if e[2] == 'player' or e[2] in Y16_TYPES or e[1] <= ENT_MAX_ROW]

    # The level's tileset (d2df2map.py): cell ids, tile behaviour tables and
    # the 8x8 textures from the original. The cell ids replace the text grid.
    tiles_path = os.path.splitext(input_path)[0] + '.tiles'
    if not os.path.exists(tiles_path):
        print(f"ERROR: {tiles_path} missing (make it with tools/d2df2map.py)")
        sys.exit(1)
    blob = open(tiles_path, 'rb').read()
    n = MAP_W * MAP_H
    map_data = bytearray(blob[:n])
    tile_attrs = blob[n:n + 512]            # tile_solid, tile_oneway
    tileset = blob[n + 512:n + 512 + 256 * 64]  # 256 x 64 B
    tail = n + 512 + 256 * 64
    fore = blob[tail:tail + FORE_BYTES]     # foreground rects (d2df2map.fore_rects)
    tail += FORE_BYTES
    liq = blob[tail:tail + LIQ_BYTES]       # liquid rects (d2df2map.liquid_rects)
    tail += LIQ_BYTES
    trig = blob[tail:tail + TRIG_SECTORS * 128]     # trigger_block
    top_solid, n_bg = blob[tail + TRIG_SECTORS * 128:][:2]
    # animated textures (d2df2map): the RAM tables (ANIM_SECTORS), the frames
    anim = blob[tail + TRIG_SECTORS * 128 + 2:]
    an_ram, an_vram = anim[:ANIM_SECTORS * 128], anim[ANIM_SECTORS * 128:]
    an_vram = an_vram.ljust(-(-len(an_vram) // 128) * 128, bytes(1))
    # only the tiles in use: ids 0..top_solid and 128..127+n_bg, whole sectors
    ts_solid = tileset[:(top_solid + 1) * 64].ljust(-(-(top_solid + 1) * 64 // 128) * 128, b'\0')
    ts_bg = tileset[128 * 64:(128 + n_bg) * 64].ljust(-(-n_bg * 64 // 128) * 128, b'\0')
    # the panel cell lists (VRAM part) only as far as they go
    trig_ram = trig[:TRIG_RAM_SECTORS * 128]
    cells = trig[TRIG_RAM_SECTORS * 128:].rstrip(b'\0')
    trig_vram = cells.ljust(max(1, -(-len(cells) // 128)) * 128, b'\0')
    assert len(tile_attrs) == 512 and len(tileset) == 256 * 64
    assert len(fore) == FORE_BYTES <= FORE_SECTORS * 128
    assert len(liq) == LIQ_BYTES <= LIQ_SECTORS * 128
    assert len(trig) == TRIG_SECTORS * 128

    # (output_bin / output_ent only name the .lvl made below)
    etype_map = {'zombie': 0, 'imp': 1, 'pinky': 2, 'caco': 3, 'shotgun': 4, 'baron': 5, 'lostsoul': 6}
    pickup_types = ('health', 'ammo', 'medikit', 'greenarmor', 'bluearmor',
                    'soulsphere', 'keyred', 'keyblue', 'keyyellow', 'shotgunpk', 'shells',
                    'pistolpk', 'chaingunpk', 'rocketpk', 'rocketbox',
                    'plasmagun', 'cells', 'bfgpk', 'rocket1', 'healthbonus',
                    'armorbonus', 'chainsaw', 'oxygen', 'backpack')
    ptype_map = PTYPE
    decor_types = ('barrel',)           # the original's maps have barrels only

    # Generate .lvl binary (for disk loading at runtime)
    if output_ent:
        lvl_path = output_bin.replace('.bin', '.lvl')
        lvl = bytearray()

        # Header (11 bytes)
        spawn_px, spawn_py = spawn or (32, 32)
        enemies = [e for e in entities if e[2] in ('zombie', 'imp', 'pinky', 'caco', 'shotgun', 'baron', 'lostsoul')]
        pickups_l = [e for e in entities if e[2] in pickup_types]
        decors_l = [e for e in entities if e[2] in decor_types]
        for what, lst, cap in (('enemies', enemies, MAX_ENEMIES),
                               ('pickups', pickups_l, MAX_PICKUPS),
                               ('decorations', decors_l, MAX_DECOR)):
            if len(lst) > cap:          # the engine's arrays would overflow
                print(f"ERROR: {len(lst)} {what} > {cap} (source/constants.asm)")
                sys.exit(1)
        if sky_name not in SKY_NAMES:
            print(f"ERROR: unknown sky {sky_name}")
            sys.exit(1)
        sky_index = SKY_NAMES.index(sky_name)
        print(f"  Sky index: {sky_index} ({sky_name})")
        lvl.append(spawn_px & 0xFF)                    # +0 spawn_x lo
        lvl.append((spawn_px >> 8) & 0xFF)             # +1 spawn_x hi
        lvl.append(spawn_py & 0xFF)                    # +2 spawn_y
        lvl.append(len(enemies) & 0xFF)                # +3 num_enemies
        lvl.append(len(pickups_l) & 0xFF)              # +4 num_pickups
        lvl.append(len(decors_l) & 0xFF)               # +5 num_decor
        lvl.append(len(ts_solid) // 128)               # +6 tileset sectors: walls
        lvl.append(len(ts_bg) // 128)                  # +7 tileset sectors: background
        lvl.append(sky_index)                          # +8 sky_index
        lvl.append((spawn_py >> 8) & 0xFF)             # +9 spawn_y_hi (16-bit spawn)
        lvl.append(len(trig_vram) // 128)              # +10 trigger panel cell sectors
        lvl.append(len(an_vram) // 128)                # +11 animated texture frame sectors

        # Enemies (7 bytes each: x_lo, x_hi, y_lo, y_hi, type, dir, sleep)
        for col, row, etype, facing, sleep in enemies:
            px = ent_x(col)
            py = ent_y(row)
            lvl.append(px & 0xFF)
            lvl.append((px >> 8) & 0xFF)
            lvl.append(py & 0xFF)
            lvl.append((py >> 8) & 0xFF)
            lvl.append(etype_map.get(etype, 0))
            lvl.append(facing)
            lvl.append(sleep)

        # Pickups (5 bytes each: x_lo, x_hi, y_lo, y_hi, type)
        for col, row, ptype, *_ in pickups_l:
            px = ent_x(col)
            py = ent_y(row)
            lvl.append(px & 0xFF)
            lvl.append((px >> 8) & 0xFF)
            lvl.append(py & 0xFF)
            lvl.append((py >> 8) & 0xFF)
            lvl.append(ptype_map.get(ptype, 0))

        # Barrels (4 bytes each: x_lo, x_hi, y_lo, y_hi)
        for col, row, dtype, *_ in decors_l:
            px = ent_x(col)
            py = ent_y(row)
            lvl.append(px & 0xFF)
            lvl.append((px >> 8) & 0xFF)
            lvl.append(py & 0xFF)
            lvl.append((py >> 8) & 0xFF)

        if len(lvl) > LVL_HDR_BYTES:
            print(f"ERROR: header + entities = {len(lvl)} B > {LVL_HDR_BYTES} B "
                  f"(LVL_HDR_SECTORS)")
            sys.exit(1)
        # + map VRAM image + tile tables (4 sectors) + the tiles in use (+6,
        # +7) + foreground rects (FORE_SECTORS) + liquid rects (LIQ_SECTORS)
        # + triggers: RAM part, panel cells (+10)
        lvl = (lvl.ljust(LVL_HDR_BYTES, b'\0') + vram_image(map_data) + tile_attrs
               + ts_solid + ts_bg + fore.ljust(FORE_SECTORS * 128, b'\0')
               + liq.ljust(LIQ_SECTORS * 128, b'\0')
               + trig_ram + trig_vram + (an_ram + an_vram if an_vram else b''))
        with open(lvl_path, 'wb') as f:
            f.write(lvl)
        print(f"LVL binary: {lvl_path} ({len(lvl)} bytes)")

    # Stats
    tile_counts = {}
    for b in map_data:
        tile_counts[b] = tile_counts.get(b, 0) + 1

    print(f"\nTile stats:")
    tile_names = {0:'empty', 1:'wall', 2:'floor', 3:'ceiling', 4:'door', 5:'sky'}
    for tid, count in sorted(tile_counts.items()):
        name = tile_names.get(tid, f'tile_{tid}')
        print(f"  {tid} ({name:8s}): {count:5d} tiles")

    if spawn:
        print(f"\nPlayer spawn: x={spawn[0]}, feet y={spawn[1]}")
    else:
        print("\nWARNING: No player spawn (@) found!")

    return True


def main():
    if len(sys.argv) < 3:
        print("Usage: python map2bin.py input.map output.bin [output.ent]")
        print("       python map2bin.py ../maps/test.map ../data/test_map.bin ../data/test_map.ent")
        sys.exit(1)

    input_path = sys.argv[1]
    output_bin = sys.argv[2]
    output_ent = sys.argv[3] if len(sys.argv) > 3 else None

    if not os.path.exists(input_path):
        print(f"ERROR: Input file not found: {input_path}")
        sys.exit(1)

    convert_map(input_path, output_bin, output_ent)
    print("\nDone!")


if __name__ == '__main__':
    main()
