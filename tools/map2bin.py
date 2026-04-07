#!/usr/bin/env python3
"""
DOOM 2D Atari - Map text to binary converter

Converts a text-based .map file (64x32 characters) to a 2048-byte
binary file for the Atari game engine.

Also extracts entity spawn positions to a separate .ent file.

Usage:
    python map2bin.py input.map output.bin [output.ent]
    python map2bin.py ../maps/test.map ../data/test_map.bin
"""

import sys
import os

MAP_W = 32
MAP_H = 32

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
    # Enemies facing LEFT (lowercase, 'n' for baron since 'b'=darkbg)
    'z': (0, 'zombie'),
    'i': (0, 'imp'),
    'k': (0, 'pinky'),
    'c': (0, 'caco'),
    'w': (0, 'shotgun'),
    'n': (0, 'baron'),
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
    # Decorations
    '!': (0, 'barrel'),
    't': (0, 'torch'),
    'l': (0, 'pillar'),
    'L': (0, 'lamp'),
    'd': (0, 'deadguy'),
}

# Characters that mean "facing left"
FACING_LEFT = {'z', 'i', 'k', 'c', 'w', 'n'}

def convert_map(input_path, output_bin, output_ent=None):
    """Convert text map to binary."""

    with open(input_path, 'r') as f:
        lines = f.readlines()

    # Filter out comments and empty lines, extract switch links
    map_lines = []
    switch_links = []
    hidden_overrides = []
    for line in lines:
        line = line.rstrip('\n\r')
        if line.startswith(';SWITCH '):
            # Parse: ;SWITCH col,row -> tgt_col,tgt_row action
            try:
                parts = line[8:].split('->')
                src = parts[0].strip().split(',')
                tgt_parts = parts[1].strip().split()
                tgt = tgt_parts[0].split(',')
                action = tgt_parts[1] if len(tgt_parts) > 1 else 'door'
                switch_links.append({
                    'col': int(src[0]), 'row': int(src[1]),
                    'tgt_col': int(tgt[0]), 'tgt_row': int(tgt[1]),
                    'action': action
                })
                print(f"  Switch link: ({src[0]},{src[1]}) -> ({tgt[0]},{tgt[1]}) action={action}")
            except (IndexError, ValueError) as e:
                print(f"  WARNING: Bad ;SWITCH line: {line} ({e})")
            continue
        if line.startswith(';HIDDEN '):
            # Parse: ;HIDDEN col,row tile_char
            # Overrides tile at entity position with wall tile (enemy stays hidden)
            try:
                parts = line[8:].strip().split()
                pos = parts[0].split(',')
                tile_ch = parts[1] if len(parts) > 1 else '#'
                hidden_overrides.append({
                    'col': int(pos[0]), 'row': int(pos[1]),
                    'tile_ch': tile_ch
                })
                print(f"  Hidden enemy: ({pos[0]},{pos[1]}) tile='{tile_ch}'")
            except (IndexError, ValueError) as e:
                print(f"  WARNING: Bad ;HIDDEN line: {line} ({e})")
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

    # Convert
    map_data = bytearray(MAP_W * MAP_H)
    entities = []
    player_spawn = None

    for row in range(MAP_H):
        line = map_lines[row]
        # Pad or trim to MAP_W
        if len(line) < MAP_W:
            line = line + '.' * (MAP_W - len(line))
        elif len(line) > MAP_W:
            line = line[:MAP_W]

        for col in range(MAP_W):
            ch = line[col]

            if ch in ENTITY_MAP:
                tile_id, ent_type = ENTITY_MAP[ch]
                if tile_id == 0:
                    # Auto-detect: use tile from row above, or empty(0) as fallback
                    # Don't copy solid/one-way tiles (they'd create visual duplicates)
                    # Only copy sky(5) and empty(0) as background
                    SAFE_BG_TILES = {0, 5}  # tiles safe to use as entity background
                    if row > 0:
                        above_ch = map_lines[row - 1][col] if col < len(map_lines[row - 1]) else '.'
                        if above_ch in TILE_MAP:
                            above_tile = TILE_MAP[above_ch]
                            if above_tile in SAFE_BG_TILES:
                                tile_id = above_tile
                            # else: leave tile_id=0 (empty) - don't duplicate walls/floors
                        elif above_ch in ENTITY_MAP:
                            tile_id = 0
                        else:
                            tile_id = 0
                    else:
                        tile_id = 0
                map_data[row * MAP_W + col] = tile_id
                facing = 1 if ch in FACING_LEFT else 0  # 0=right, 1=left
                entities.append((col, row, ent_type, facing))
                if ent_type == 'player':
                    player_spawn = (col, row)
                dir_str = "L" if facing else "R"
                print(f"  Entity: {ent_type} at col={col}, row={row} (px: {col*16},{row*16}) dir={dir_str}")
            elif ch in TILE_MAP:
                map_data[row * MAP_W + col] = TILE_MAP[ch]
            else:
                print(f"  WARNING: Unknown char '{ch}' at row={row}, col={col}, using empty")
                map_data[row * MAP_W + col] = 0

    # Apply hidden enemy tile overrides
    for ho in hidden_overrides:
        c, r, tch = ho['col'], ho['row'], ho['tile_ch']
        if tch in TILE_MAP:
            tid = TILE_MAP[tch]
            map_data[r * MAP_W + c] = tid
            print(f"  Hidden override: ({c},{r}) tile '{tch}' -> ID {tid}")
        else:
            print(f"  WARNING: Unknown tile char '{tch}' in ;HIDDEN at ({c},{r})")

    # Write binary map
    with open(output_bin, 'wb') as f:
        f.write(map_data)
    print(f"Map binary: {output_bin} ({len(map_data)} bytes)")

    # Write entity file
    if output_ent and entities:
        with open(output_ent, 'w') as f:
            f.write("; Auto-generated entity data from map\n")
            f.write(f"; Source: {os.path.basename(input_path)}\n")
            f.write(f"; Entities: {len(entities)}\n\n")
            for col, row, ent_type, facing in entities:
                px_x = col * 16
                px_y = row * 16
                ds = "L" if facing else "R"
                f.write(f"{ent_type:10s} col={col:3d} row={row:3d}  px=({px_x},{px_y}) dir={ds}\n")
        print(f"Entities:   {output_ent} ({len(entities)} entities)")

    # Generate MADS include for entity spawns
    if output_ent:
        asm_path = output_ent.replace('.ent', '_ent.asm')
        with open(asm_path, 'w') as f:
            f.write("; Auto-generated entity spawn data\n")
            f.write(f"; Source: {os.path.basename(input_path)}\n\n")

            if player_spawn:
                f.write(f"SPAWN_X = {player_spawn[0] * 16}\n")
                f.write(f"SPAWN_Y = {player_spawn[1] * 16}\n\n")
            else:
                f.write("; WARNING: No player spawn (@) on map, using default\n")
                f.write("SPAWN_X = 32\n")
                f.write("SPAWN_Y = 32\n\n")

            # Enemy spawns
            enemies = [e for e in entities if e[2] in ('zombie', 'imp', 'pinky', 'caco', 'shotgun', 'baron')]
            f.write(f"NUM_ENEMIES = {len(enemies)}\n\n")

            etype_map = {'zombie': 0, 'imp': 1, 'pinky': 2, 'caco': 3, 'shotgun': 4, 'baron': 5}

            MAX_ENEMIES = 6
            f.write("enemy_spawn_x\n")
            for col, row, etype, facing in enemies:
                f.write(f"        dta a({col * 16})  ; {etype}\n")
            for _ in range(MAX_ENEMIES - len(enemies)):
                f.write("        dta a(0)\n")

            f.write("\nenemy_spawn_y\n")
            for col, row, etype, facing in enemies:
                f.write(f"        dta {row * 16}  ; {etype}\n")
            for _ in range(MAX_ENEMIES - len(enemies)):
                f.write("        dta 0\n")

            f.write("\nenemy_spawn_type\n")
            for col, row, etype, facing in enemies:
                f.write(f"        dta {etype_map.get(etype, 0)}  ; {etype}\n")
            for _ in range(MAX_ENEMIES - len(enemies)):
                f.write("        dta 0\n")

            f.write("\nenemy_spawn_dir\n")
            for col, row, etype, facing in enemies:
                ds = "left" if facing else "right"
                f.write(f"        dta {facing}  ; {etype} {ds}\n")
            for _ in range(MAX_ENEMIES - len(enemies)):
                f.write("        dta 0\n")

            # Pickup spawns (all collectible items)
            pickup_types = ('health', 'ammo', 'medikit', 'greenarmor', 'bluearmor',
                           'soulsphere', 'keyred', 'keyblue', 'keyyellow', 'shotgunpk', 'shells',
                           'pistolpk', 'chaingunpk', 'rocketpk', 'rocketbox',
                           'plasmagun', 'cells', 'bfgpk', 'rocket1', 'healthbonus',
                           'armorbonus')
            pickups = [e for e in entities if e[2] in pickup_types]
            f.write(f"\nNUM_PICKUPS = {len(pickups)}\n\n")

            ptype_map = {'health': 0, 'ammo': 1, 'medikit': 2,
                        'greenarmor': 3, 'bluearmor': 4, 'soulsphere': 5,
                        'keyred': 6, 'keyblue': 7, 'keyyellow': 8,
                        'shotgunpk': 9, 'shells': 10,
                        'pistolpk': 11, 'chaingunpk': 12, 'rocketpk': 13, 'rocketbox': 14,
                        'plasmagun': 15, 'cells': 16, 'bfgpk': 17, 'rocket1': 18,
                        'healthbonus': 19, 'armorbonus': 20}

            MAX_PICKUPS = 12
            f.write("pickup_spawn_x\n")
            for col, row, ptype, _ in pickups:
                px = col * 16
                f.write(f"        dta {px & 255}  ; {ptype}\n")
            for _ in range(MAX_PICKUPS - len(pickups)):
                f.write("        dta 0\n")

            f.write("\npickup_spawn_xhi\n")
            for col, row, ptype, _ in pickups:
                px = col * 16
                f.write(f"        dta {px >> 8}  ; {ptype}\n")
            for _ in range(MAX_PICKUPS - len(pickups)):
                f.write("        dta 0\n")

            f.write("\npickup_spawn_y\n")
            for col, row, ptype, _ in pickups:
                f.write(f"        dta {row * 16}  ; {ptype}\n")
            for _ in range(MAX_PICKUPS - len(pickups)):
                f.write("        dta 0\n")

            f.write("\npickup_spawn_type\n")
            for col, row, ptype, _ in pickups:
                f.write(f"        dta {ptype_map.get(ptype, 0)}  ; {ptype}\n")
            for _ in range(MAX_PICKUPS - len(pickups)):
                f.write("        dta 0\n")

            # Decoration spawns
            decor_types = ('barrel', 'torch', 'pillar', 'lamp', 'deadguy')
            decors = [e for e in entities if e[2] in decor_types]
            f.write(f"\nNUM_DECOR = {len(decors)}\n\n")

            dtype_map = {'barrel': 0, 'torch': 1, 'pillar': 2,
                        'lamp': 3, 'deadguy': 4}

            MAX_DECOR = 8
            f.write("decor_spawn_x\n")
            for col, row, dtype, _ in decors:
                px = col * 16
                f.write(f"        dta {px & 255}  ; {dtype}\n")
            for _ in range(MAX_DECOR - len(decors)):
                f.write("        dta 0\n")

            f.write("\ndecor_spawn_xhi\n")
            for col, row, dtype, _ in decors:
                px = col * 16
                f.write(f"        dta {px >> 8}  ; {dtype}\n")
            for _ in range(MAX_DECOR - len(decors)):
                f.write("        dta 0\n")

            f.write("\ndecor_spawn_y\n")
            for col, row, dtype, _ in decors:
                f.write(f"        dta {row * 16}  ; {dtype}\n")
            for _ in range(MAX_DECOR - len(decors)):
                f.write("        dta 0\n")

            f.write("\ndecor_spawn_type\n")
            for col, row, dtype, _ in decors:
                f.write(f"        dta {dtype_map.get(dtype, 0)}  ; {dtype}\n")
            for _ in range(MAX_DECOR - len(decors)):
                f.write("        dta 0\n")

            # Switch target links
            # Auto-detect source type for door action:
            #   '$' (switch) or '.' (floor trigger) → door (0) — spacebar locked
            #   pickup → door_lock (3) — spacebar locked (same, but distinct type)
            act_map = {'door': 0, 'wall': 1, 'elevator': 2}
            for s in switch_links:
                if s['action'] == 'door':
                    src_ch = '.'
                    sr, sc = s['row'], s['col']
                    if sr < len(map_lines) and sc < len(map_lines[sr]):
                        src_ch = map_lines[sr][sc]
                    if src_ch == '.':
                        s['action'] = 'floor'
                        print(f"  Auto: link ({sc},{sr}) floor trigger -> floor")
                    elif src_ch != '$':
                        s['action'] = 'door_lock'
                        print(f"  Auto: link ({sc},{sr}) source='{src_ch}' -> door_lock")
            act_map['door_lock'] = 3
            act_map['floor'] = 4
            act_map['exit'] = 5
            for s in switch_links:
                if s['action'] in ('door', 'floor', 'door_lock'):
                    sr, sc = s['row'], s['col']
                    if sr < len(map_lines) and sc < len(map_lines[sr]):
                        if map_lines[sr][sc] == 'E':
                            s['action'] = 'exit'
                            print(f"  Auto: link ({sc},{sr}) exit switch")
            max_sw = 4
            num_sw = min(len(switch_links), max_sw)
            if len(switch_links) > max_sw:
                print(f"  WARNING: {len(switch_links)} switches, max is {max_sw}, truncating!")

            f.write(f"\n; Switch target links (auto-generated)\n")
            f.write(f"num_switches\n        dta {num_sw}\n")

            f.write("sw_col\n")
            for i in range(max_sw):
                if i < num_sw:
                    s = switch_links[i]
                    f.write(f"        dta {s['col']}  ; switch {i}\n")
                else:
                    f.write(f"        dta 0\n")

            f.write("sw_row\n")
            for i in range(max_sw):
                if i < num_sw:
                    s = switch_links[i]
                    f.write(f"        dta {s['row']}  ; switch {i}\n")
                else:
                    f.write(f"        dta 0\n")

            f.write("sw_tgt_col\n")
            for i in range(max_sw):
                if i < num_sw:
                    s = switch_links[i]
                    f.write(f"        dta {s['tgt_col']}  ; -> {s['action']}\n")
                else:
                    f.write(f"        dta 0\n")

            f.write("sw_tgt_row\n")
            for i in range(max_sw):
                if i < num_sw:
                    s = switch_links[i]
                    f.write(f"        dta {s['tgt_row']}  ; -> {s['action']}\n")
                else:
                    f.write(f"        dta 0\n")

            f.write("sw_action\n")
            for i in range(max_sw):
                if i < num_sw:
                    s = switch_links[i]
                    act = act_map.get(s['action'], 0)
                    f.write(f"        dta {act}  ; {s['action']}\n")
                else:
                    f.write(f"        dta 0\n")

        print(f"ASM spawns: {asm_path}")

    # Generate .lvl binary (for disk loading at runtime)
    if output_ent:
        lvl_path = output_bin.replace('.bin', '.lvl')
        lvl = bytearray(map_data)                     # 1024 bytes: tiles

        # Header (7 bytes)
        spawn_px = player_spawn[0] * 16 if player_spawn else 32
        spawn_py = player_spawn[1] * 16 if player_spawn else 32
        enemies = [e for e in entities if e[2] in ('zombie', 'imp', 'pinky', 'caco', 'shotgun', 'baron')]
        pickups_l = [e for e in entities if e[2] in pickup_types]
        decors_l = [e for e in entities if e[2] in decor_types]
        lvl.append(spawn_px & 0xFF)                    # spawn_x lo
        lvl.append((spawn_px >> 8) & 0xFF)             # spawn_x hi
        lvl.append(spawn_py & 0xFF)                    # spawn_y
        lvl.append(len(enemies) & 0xFF)                # num_enemies
        lvl.append(len(pickups_l) & 0xFF)              # num_pickups
        lvl.append(len(decors_l) & 0xFF)               # num_decor
        num_sw = min(len(switch_links), 4)
        lvl.append(num_sw)                             # num_switches

        # Enemies (5 bytes each: x_lo, x_hi, y, type, dir)
        for col, row, etype, facing in enemies:
            px = col * 16
            lvl.append(px & 0xFF)
            lvl.append((px >> 8) & 0xFF)
            lvl.append(row * 16)
            lvl.append(etype_map.get(etype, 0))
            lvl.append(facing)

        # Pickups (4 bytes each: x_lo, x_hi, y, type)
        for col, row, ptype, _ in pickups_l:
            px = col * 16
            lvl.append(px & 0xFF)
            lvl.append((px >> 8) & 0xFF)
            lvl.append(row * 16)
            lvl.append(ptype_map.get(ptype, 0))

        # Decorations (4 bytes each: x_lo, x_hi, y, type)
        for col, row, dtype, _ in decors_l:
            px = col * 16
            lvl.append(px & 0xFF)
            lvl.append((px >> 8) & 0xFF)
            lvl.append(row * 16)
            lvl.append(dtype_map.get(dtype, 0))

        # Switches (5 bytes each: col, row, tgt_col, tgt_row, action)
        for i in range(num_sw):
            s = switch_links[i]
            act = act_map.get(s['action'], 0)
            lvl.append(s['col'])
            lvl.append(s['row'])
            lvl.append(s['tgt_col'])
            lvl.append(s['tgt_row'])
            lvl.append(act)

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

    if player_spawn:
        print(f"\nPlayer spawn: col={player_spawn[0]}, row={player_spawn[1]}")
        print(f"              pixel: x={player_spawn[0]*16}, y={player_spawn[1]*16}")
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
