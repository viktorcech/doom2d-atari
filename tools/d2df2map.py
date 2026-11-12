#!/usr/bin/env python3
"""
Convert a Doom 2D Forever .map to the Atari DOOM2D .map text format, 1:1:
one 16x16 D2DF cell = one Atari tile, up to 100x100 (MAP_W/MAP_H).

  python d2df2map.py input.map output.map        convert (2 chars per tile)
  python d2df2map.py --png out_dir a.map [...]   1:1 textured previews + stats
  python d2df2map.py --cmp pc.map atari.map out.png   PC vs converted, 1:1

Type numbers and hitboxes are from git/Doom2D-Forever-master
(src/shared/mapdef.inc, g_monsters.pas MONSTERTABLE, g_items.pas ITEMSIZE).
Panel textures map to the Atari tile with the nearest average colour (the
real per-level tileset comes later); entities stand on the cell under the
bottom centre of their hitbox.
"""
import re
import struct
import sys
import os

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
MAP_W = MAP_H = 100                     # source/constants.asm
MAX_ENEMIES, MAX_PICKUPS, MAX_DECOR = 66, 96, 16

# D2DF panel types (mapdef.inc PanelType)
PANEL_WALL = 1
PANEL_BACK = 2
PANEL_FORE = 4
PANEL_WATER = 8
PANEL_ACID1 = 16
PANEL_ACID2 = 32
PANEL_STEP = 64
PANEL_LIFTUP = 128
PANEL_LIFTDOWN = 256
PANEL_OPENDOOR = 512
PANEL_CLOSEDOOR = 1024
PANEL_BLOCKMON = 2048

# D2DF monster -> (our char facing right, hitbox X, Y, W, H). Types we have
# no sprite for get the nearest one we have.
MONSTER_MAP = {
    1: ('K', 7, 8, 50, 52),     # DEMON -> pinky
    2: ('I', 15, 10, 34, 50),   # IMP
    3: ('Z', 15, 8, 34, 52),    # ZOMBY
    4: ('W', 15, 8, 34, 52),    # SERG -> shotgun guy
    5: ('B', 24, 9, 80, 110),   # CYBER -> baron
    6: ('W', 15, 4, 34, 56),    # CGUN -> shotgun guy
    7: ('B', 39, 32, 50, 64),   # BARON
    8: ('B', 39, 32, 50, 64),   # KNIGHT -> baron
    9: ('C', 34, 36, 60, 56),   # CACO
    10: ('>', 16, 14, 32, 36),  # SOUL -> lost soul
    11: ('C', 34, 36, 60, 56),  # PAIN -> caco
    12: ('B', 23, 14, 210, 100),  # SPIDER -> baron
    13: ('C', 14, 17, 100, 42),   # BSP -> caco
    14: ('B', 28, 34, 72, 60),  # MANCUB -> baron
    15: ('I', 30, 28, 68, 72),  # SKEL -> imp
    16: ('I', 30, 28, 68, 72),  # VILE -> imp
    18: ('!', 20, 13, 24, 36),  # BARREL (decoration)
    19: ('B', 30, 26, 68, 76),  # ROBO -> baron
    20: ('Z', 15, 6, 34, 52),   # MAN -> zombie
}
LEFT_CHAR = {'K': 'k', 'I': 'i', 'Z': 'z', 'W': 'w', 'B': 'n', 'C': 'c', '>': '<'}

# D2DF item -> (our char, W, H)
ITEM_MAP = {
    1: ('H', 14, 15), 2: ('M', 28, 19), 3: ('M', 28, 19), 4: ('1', 31, 16),
    5: ('2', 31, 16), 6: ('3', 25, 25), 7: ('3', 25, 25), 10: ('3', 25, 25),
    12: ('7', 63, 12), 13: ('7', 54, 13), 14: ('Q', 54, 16), 15: ('R', 62, 16),
    16: ('u', 54, 16), 17: ('j', 61, 36), 18: ('Q', 54, 16), 19: ('A', 9, 11),
    20: ('A', 28, 16), 21: ('8', 15, 7), 22: ('8', 32, 12), 23: ('v', 12, 27),
    24: ('r', 54, 21), 25: ('e', 15, 12), 26: ('e', 32, 21), 28: ('4', 16, 16),
    29: ('6', 16, 16), 30: ('5', 16, 16), 32: ('9', 43, 16), 33: ('h', 14, 18),
    34: ('a', 16, 15), 11: ('0', 62, 24), 9: ('/', 14, 27), 27: (',', 22, 29),
}
PICKUP_RANK = '456' + '7QRuj90,/' + '123M' + 'Hhaer v8A'   # kept first when over the cap

PLAYER_RECT = (15, 12, 34, 52)          # g_player.pas PLAYER_RECT
ITEM_OPTION_ONLYDM = 1                  # mapdef.inc ItemOption
AREA_PLAYER1 = 1
AREA_PLAYER2 = 2
TRIGGER_EXIT = 1
TRIGGER_TELEPORT = 2


def read_d2df(path):
    with open(path, 'rb') as f:
        data = f.read()

    # Check magic
    if data[:3] != b'MAP':
        print(f"ERROR: Not a D2DF map (magic: {data[:4]})")
        sys.exit(1)

    pos = 4  # skip magic + version byte
    textures = []
    panels = []
    items = []
    areas = []
    monsters = []
    triggers = []
    header = {}

    while pos < len(data):
        if pos + 9 > len(data):
            break
        btype = data[pos]
        bsize = struct.unpack_from('<I', data, pos + 5)[0]
        pos += 9

        if pos + bsize > len(data):
            break

        block = data[pos:pos + bsize]
        pos += bsize

        if btype == 7:  # Header
            header = {
                'name': block[0:32].split(b'\x00')[0].decode('ascii', errors='ignore'),
                'sky': block[384:448].split(bytes(1))[0].decode('ascii', errors='ignore'),
                'width': struct.unpack_from('<H', block, 448)[0],
                'height': struct.unpack_from('<H', block, 450)[0],
            }
        elif btype == 1:  # Textures
            rec_size = 65
            for i in range(bsize // rec_size):
                off = i * rec_size
                path_str = block[off:off+64].split(b'\x00')[0].decode('ascii', errors='ignore')
                textures.append(path_str)
        elif btype == 2:  # Panels
            rec_size = 18
            for i in range(bsize // rec_size):
                off = i * rec_size
                x, y = struct.unpack_from('<ii', block, off)
                w, h = struct.unpack_from('<HH', block, off + 8)
                tex_idx = struct.unpack_from('<H', block, off + 12)[0]
                ptype = struct.unpack_from('<H', block, off + 14)[0]
                panels.append({'x': x, 'y': y, 'w': w, 'h': h, 'tex': tex_idx, 'type': ptype})
        elif btype == 3:  # Items
            rec_size = 10
            for i in range(bsize // rec_size):
                off = i * rec_size
                x, y = struct.unpack_from('<ii', block, off)
                itype = block[off + 8]
                if block[off + 9] & ITEM_OPTION_ONLYDM:
                    continue                # deathmatch only: not in single player
                items.append({'x': x, 'y': y, 'type': itype})
        elif btype == 4:  # Areas
            rec_size = 10
            for i in range(bsize // rec_size):
                off = i * rec_size
                x, y = struct.unpack_from('<ii', block, off)
                atype = block[off + 8]
                direction = block[off + 9]
                areas.append({'x': x, 'y': y, 'type': atype, 'dir': direction})
        elif btype == 5:  # Monsters
            rec_size = 10
            for i in range(bsize // rec_size):
                off = i * rec_size
                x, y = struct.unpack_from('<ii', block, off)
                mtype = block[off + 8]
                mdir = block[off + 9]
                monsters.append({'x': x, 'y': y, 'type': mtype, 'dir': mdir})
        elif btype == 6:  # Triggers
            rec_size = 148
            for i in range(bsize // rec_size):
                off = i * rec_size
                x, y = struct.unpack_from('<ii', block, off)
                tw, th = struct.unpack_from('<HH', block, off + 8)
                ttype = block[off + 17]
                triggers.append({'x': x, 'y': y, 'w': tw, 'h': th, 'type': ttype,
                                 'enabled': block[off + 12],
                                 'tex_panel': struct.unpack_from('<i', block, off + 13)[0],
                                 'act': block[off + 18], 'keys': block[off + 19],
                                 'data': block[off+20:off+148]})

    return header, textures, panels, items, areas, monsters, triggers


def tex_base(tex_path, map_path):
    """D2DF texture path -> its path in the unpacked WAD folder (no extension)."""
    wad, res = tex_path.split(':', 1)
    assets = os.path.dirname(os.path.dirname(os.path.abspath(map_path)))
    wad_dir = (os.path.join(assets, os.path.splitext(wad)[0] + 'WAD') if wad
               else os.path.dirname(os.path.abspath(map_path)))
    return os.path.join(wad_dir, *res.split('\\'))


def anim_info(tex_path, map_path):
    """An animated texture's TEXT/ANIM.txt (g_textures.pas) as a dict
    (framecount, framewidth, frameheight, waitcount, backanimation), else None."""
    if ':' not in tex_path:
        return None
    fn = os.path.join(tex_base(tex_path, map_path), 'TEXT', 'ANIM.txt')
    if not os.path.exists(fn):
        return None
    kv = dict(l.strip().split('=', 1) for l in open(fn, encoding='latin-1') if '=' in l)
    return {k: int(v) if v.strip().isdigit() else v.strip() for k, v in kv.items()}


def load_texture(tex_path, map_path, cache, frame=0):
    """D2DF texture path ('Standart.wad:D2DTEXTURES\\NAME') -> RGBA image or None.
    The WAD is the unpacked folder <Name>WAD in DF-Assets; an animated texture
    is a folder: frame `frame` of its ANIM.txt sheet."""
    if (tex_path, frame) in cache:
        return cache[(tex_path, frame)]
    img = None
    if ':' in tex_path:
        base = tex_base(tex_path, map_path)
        frames = os.path.join(base, 'TEXTURES')
        for cand in [base + '.tga', base + '.png']:
            if os.path.exists(cand):
                img = cand
                break
        if img is None and os.path.isdir(frames):
            tgas = sorted(f for f in os.listdir(frames) if f.lower().endswith(('.tga', '.png')))
            if tgas:
                img = os.path.join(frames, tgas[0])
        if img is not None:
            img = Image.open(img).convert('RGBA')
            a = anim_info(tex_path, map_path)
            if a:
                k = frame % a['framecount']
                img = img.crop((k * a['framewidth'], 0, (k + 1) * a['framewidth'],
                                a['frameheight']))
    cache[(tex_path, frame)] = img
    return img


def sky_name(res):
    """'Standart.wad:D2DSKY\\RSKY1' -> D2DSKY1, '...:STDSKY\\SKY0' -> DFSKY0
    (tools/map2bin.py SKY_NAMES); no sky -> SKY0, the engine default."""
    res = res.upper()
    if 'RSKY' in res:
        return 'D2DSKY' + res.rsplit('RSKY', 1)[1]
    if 'SKY' in res:
        return 'DFSKY' + res.rsplit('SKY', 1)[1]
    return 'DFSKY0'


def convert(map_path, out_path):
    header, textures, panels, items, areas, monsters, triggers = read_d2df(map_path)
    w, h = header.get('width', 1600), header.get('height', 1600)
    print(f"  {header.get('name', '')}: {w}x{h} px -> {MAP_W}x{MAP_H} tiles")
    if w > MAP_W * 16 or h > MAP_H * 16:
        print(f"  WARNING: map larger than {MAP_W * 16}x{MAP_H * 16}, cut")
    # The text grid only tells walls ('#'), platforms ('Y'), doors ('D') and
    # background ('#b') apart for map2bin; the look comes from the .tiles file.
    grid = [['.', ' '] for _ in range(MAP_W * MAP_H)]

    def cells(p):
        for ty in range(max(0, p['y'] // 16), min(MAP_H, (p['y'] + p['h'] + 15) // 16)):
            for tx in range(max(0, p['x'] // 16), min(MAP_W, (p['x'] + p['w'] + 15) // 16)):
                yield ty * MAP_W + tx

    # back + fore -> background (passable) tiles; then platforms; walls/doors win
    for p in panels:
        if p['type'] & (PANEL_BACK | PANEL_FORE):
            for i in cells(p):
                if grid[i][0] == '.':
                    grid[i] = ['#', 'b']
    for p in panels:
        if p['type'] & PANEL_STEP:
            for i in cells(p):
                grid[i] = ['Y', ' ']
    for p in panels:
        if p['type'] & PANEL_WALL:
            for i in cells(p):
                grid[i] = ['#', ' ']
        elif p['type'] & PANEL_CLOSEDOOR:
            for i in cells(p):
                grid[i] = ['D', ' ']

    def solid(i):
        return grid[i][1] != 'b' and grid[i][0] not in '.Y'

    ents = []                           # '; ENT ch x y' lines: exact spawns
    dropped = []

    def place(ch, fx, fy, what, h=0):
        """Monsters, items, barrels: the exact spawn of the original at half
        scale (16 px sprite centred on the foot point, feet on it; several
        may share a spot, as in the original)."""
        # a hitbox bottom inside the floor (the map stores it so) stands
        # on that floor's top, as the game shows it; a monster's rect h
        # tall: a floor in the lower half of it (a big monster stood in for)
        c = fx // 16
        for r in range((fy - 1) // 16, (fy - h // 2) // 16 - 1, -1):
            if h and 0 <= c < MAP_W and 0 <= r < MAP_H and solid(r * MAP_W + c):
                fy = r * 16
                break
        for _ in range(2):
            c, r = fx // 16, (fy - 1) // 16
            if 0 <= c < MAP_W and 0 <= r < MAP_H and solid(r * MAP_W + c):
                fy = r * 16
        ents.append((ch, max(0, fx // 2 - 8), max(0, fy // 2 - 16)))
        return True

    for a in areas:
        if a['type'] == AREA_PLAYER1:       # single-player start (P2 = co-op)
            # g_player.pas Respawn: the area is the top-left of PLAYER_RECT;
            # '; ENT @ x y': x = zpx (rect left + PL_RL), y + 16 = feet (zpy)
            _, _, _, rh = PLAYER_RECT
            ents.append(('@', a['x'] // 2 + 3, (a['y'] + rh) // 2 - 16))
    n_en = n_pk = n_dc = 0
    for m in monsters:
        if m['type'] not in MONSTER_MAP:
            dropped.append(f"monster type {m['type']}")
            continue
        ch, rx, ry, rw, rh = MONSTER_MAP[m['type']]
        if ch == '!':
            if n_dc >= MAX_DECOR:
                dropped.append('barrel (MAX_DECOR)')
                continue
            n_dc += place(ch, m['x'] + rx + rw // 2, m['y'] + ry + rh, 'barrel')
            continue
        if n_en >= MAX_ENEMIES:
            dropped.append(f"{ch} (MAX_ENEMIES)")
            continue
        if m['dir'] == 0:                       # DIR_LEFT
            ch = LEFT_CHAR[ch]
        n_en += place(ch, m['x'] + rx + rw // 2, m['y'] + ry + rh, f"monster {ch}", rh)
    known = [it for it in items if it['type'] in ITEM_MAP]
    dropped += [f"item type {it['type']}" for it in items if it['type'] not in ITEM_MAP]
    known.sort(key=lambda it: PICKUP_RANK.find(ITEM_MAP[it['type']][0]))
    for it in known:
        ch, iw, ih = ITEM_MAP[it['type']]
        if n_pk >= MAX_PICKUPS:
            dropped.append(f"{ch} (MAX_PICKUPS)")
            continue
        n_pk += place(ch, it['x'] + iw // 2, it['y'] + ih, f"item {ch}")

    with open(out_path, 'w') as f:
        f.write(f"; DOOM 2D Atari map\n; Converted 1:1 from {os.path.basename(map_path)}"
                f" ({header.get('name', '')}) by tools/d2df2map.py\n")
        f.write(f";sky={sky_name(header.get('sky', ''))}\n")
        for ch, x, y in ents:
            f.write(f"; ENT {ch} {x} {y}\n")
        for r in range(MAP_H):
            f.write(''.join(grid[r * MAP_W + c][0] + grid[r * MAP_W + c][1]
                            for c in range(MAP_W)).rstrip() + '\n')
    print(f"  enemies {n_en}, pickups {n_pk}, decor {n_dc}")
    if dropped:
        print(f"  dropped {len(dropped)}: " + ', '.join(dropped))
    print(f"  -> {out_path}")
    build_tiles(map_path, os.path.splitext(out_path)[0] + '.tiles')


AT_MAX, AP_MAX = 8, 40                          # animated textures / their panels
ANIM_RAM_BYTES = 256                            # source/anim.asm ANIM_RAM (2 sectors)
ANIM_VRAM_BYTES = 32768                         # VRAM_ANIM ($014000-$01BFFF)
SOLID_IDS = [i for i in range(1, 128) if i != 15]   # 15: the barrels' invisible solid
BG_IDS = list(range(128, 256))                  # bit 7 = passable background


def build_tiles(map_path, tiles_path):
    """The level's own tileset from the original textures: every 16x16 cell
    of the 1:1 render, box-filtered to 8x8 in the VBXE palette. Cells with
    the same look and behaviour share a tile; over the id budget the closest
    pair (RGB) inside one behaviour is merged until it fits. Writes
    tiles_path: ids[MAP_W*MAP_H], tile_solid[256] (of a bg tile 128+: its
    liquid, 1 water, 2 acid1, 3 acid2), tile_oneway[256],
    textures[256*64] (index 0 = transparent), the foreground rects, the
    trigger block."""
    import numpy as np
    _, textures, panels, *_, triggers = read_d2df(map_path)
    # panels a trigger toggles: every door panel, and the switch pictures
    # (texture_panel: X_n -> X_n+1, or X_0 after the last; a lone texture
    # toggles between shown and not shown)
    doors = [j for j, p in enumerate(panels) if p['type'] & (PANEL_OPENDOOR | PANEL_CLOSEDOOR)]
    switches = sorted({t['tex_panel'] for t in triggers if 0 <= t['tex_panel'] < len(panels)})
    texalt = {}
    for j in switches:
        name = textures[panels[j]['tex']]
        m = re.match(r'(.*)_(\d+)$', name)
        alt = None
        if m:
            cache = {}
            for cand in (f'{m[1]}_{int(m[2]) + 1}', f'{m[1]}_0'):
                if load_texture(cand, map_path, cache) is not None:
                    alt = cand
                    break
        texalt[j] = alt

    def kinds(flip):
        # 0 empty, 1 wall, 2 platform, 3 door, 4 bg, 5/6/7 bg in water/acid1/acid2
        kind = [0] * (MAP_W * MAP_H)

        def mark(p, k):
            for i in panel_cells(p):
                kind[i] = k
        for p in panels:
            if p['type'] & (PANEL_BACK | PANEL_FORE):
                mark(p, 4)
        for p in panels:                # g_phys.pas: the panel type makes the liquid
            t = p['type']
            if t & (PANEL_WATER | PANEL_ACID1 | PANEL_ACID2):
                mark(p, 5 if t & PANEL_WATER else 6 if t & PANEL_ACID1 else 7)
        for p in panels:
            if p['type'] & PANEL_STEP:
                mark(p, 2)
        for j, p in enumerate(panels):
            ptype = p['type'] ^ (PANEL_OPENDOOR | PANEL_CLOSEDOOR) if j in flip else p['type']
            if ptype & PANEL_WALL:
                mark(p, 1)
            elif ptype & PANEL_CLOSEDOOR:
                mark(p, 3)
        return kind

    def cell_keys(kind, img):
        small = img.resize((img.width // 2, img.height // 2), Image.BOX)   # 8 px cells
        px = np.array(small, dtype=np.uint8)
        # translucent pixels as the PC shows them: over its dark sky
        a = px[:, :, 3:4].astype(np.float32) / 255
        vis = (px[:, :, 3] >= 128)[:, :, None]
        mix = px[:, :, :3] * a + np.array([24, 24, 32], np.float32) * (1 - a)
        px[:, :, :3] = np.where(vis, mix, px[:, :, :3]).astype(np.uint8)
        keys = [None] * (MAP_W * MAP_H)
        for r in range(MAP_H):
            for c in range(MAP_W):
                i = r * MAP_W + c
                k = kind[i]
                cell = px[r * 8:r * 8 + 8, c * 8:c * 8 + 8]
                if k in (0, 4) and cell[:, :, 3].max() < 128:
                    continue                                # nothing visible: id 0
                if k == 0:
                    k = kind[i] = 4                         # stray pixels: background
                keys[i] = (k, cell.tobytes(), cell)
        return keys

    # the tiles without the liquid filter: the game filters the screen
    # (source/liquid.asm, MODE 7 after the sprites)
    def_keys = cell_keys(kinds(()), render_image(map_path, bg=(0, 0, 0, 0), liquids=False))
    alt_keys = cell_keys(kinds(set(doors)),
                         render_image(map_path, bg=(0, 0, 0, 0), flip=set(doors), texalt=texalt,
                                      liquids=False))
    toggled = {i for j in doors + switches for i in panel_cells(panels[j])}

    # animated textures (ANIM.txt): the look of their cells frame by frame;
    # cells with the same sequence share one tile id, the ids of a texture
    # are consecutive (the engine copies a frame of all of them in one blit)
    zero = np.zeros((8, 8, 4), np.uint8)
    anim, anim_cell = [], {}                    # (name, info, {seq: group}), cell -> (t, g)
    for name in sorted({textures[p['tex']] for p in panels if p['tex'] < len(textures)}):
        a = anim_info(name, map_path)
        if not a:
            continue
        order = list(range(a['framecount']))
        if a.get('backanimation'):
            order += order[-2:0:-1]
        fk = {0: def_keys}
        for k in set(order) - {0}:
            fk[k] = cell_keys(kinds(()), render_image(map_path, bg=(0, 0, 0, 0), aframe={name: k},
                                                      liquids=False))
        seqs = {}
        for p in panels:
            if p['tex'] >= len(textures) or textures[p['tex']] != name:
                continue
            for i in panel_cells(p):
                if i in anim_cell or i in toggled:
                    continue
                seq = tuple(fk[k][i] or (4, zero.tobytes(), zero) for k in order)
                if len({q[:2] for q in seq}) == 1 or min(q[0] for q in seq) < 4:
                    continue                    # never changes / a wall cell: static
                key = tuple(q[:2] for q in seq)
                if key not in seqs:
                    seqs[key] = (len(seqs), seq)
                anim_cell[i] = (len(anim), seqs[key][0])
        if seqs:
            anim.append((name, a, order, seqs))
    n_anim = sum(len(x[3]) for x in anim)

    uniq, cell_key = {}, [None] * (MAP_W * MAP_H)
    for i, k in enumerate(def_keys):
        if k is not None and i not in anim_cell:
            uniq.setdefault(k[:2], [k[2], 0])[1] += 1
            cell_key[i] = k[:2]
    alt_key = {}
    for i in toggled:
        k = alt_keys[i]
        if k is not None:
            uniq.setdefault(k[:2], [k[2], 0])[1] += 1
            alt_key[i] = k[:2]

    # merge the closest look-alikes until each id range fits
    keys = list(uniq)
    rgb = np.array([uniq[k][0][:, :, :3].astype(np.float32).ravel() for k in keys]) \
        if keys else np.zeros((0, 192), np.float32)
    grp = np.array([0 if k[0] >= 4 else 1 for k in keys])
    cnt = np.array([uniq[k][1] for k in keys], dtype=np.float64)
    beh = np.array([k[0] for k in keys])
    alive = np.ones(len(keys), bool)
    rep = list(range(len(keys)))                            # merged-into map
    limit = {0: len(BG_IDS) - n_anim, 1: len(SOLID_IDS)}
    for g in (0, 1):
        idx = np.where((grp == g) & alive)[0]
        if len(idx) <= limit[g]:
            continue
        sub = rgb[idx]
        d = ((sub[:, None, :] - sub[None, :, :]) ** 2).sum(-1)
        d[beh[idx][:, None] != beh[idx][None, :]] = np.inf  # never mix behaviours
        np.fill_diagonal(d, np.inf)
        live = np.ones(len(idx), bool)
        for _ in range(len(idx) - limit[g]):
            a, b = np.unravel_index(np.argmin(d), d.shape)
            if not np.isfinite(d[a, b]):
                break
            keep, drop = (a, b) if cnt[idx[a]] >= cnt[idx[b]] else (b, a)
            rep[idx[drop]] = idx[keep]
            cnt[idx[keep]] += cnt[idx[drop]]
            live[drop] = False
            d[drop, :] = np.inf
            d[:, drop] = np.inf
        alive[idx[~live]] = False
        if live.sum() > limit[g]:
            print(f"  WARNING: {live.sum()} tiles of one kind left > {limit[g]}")

    def root(j):
        while rep[j] != j:
            j = rep[j]
        return j

    # palette (VBXE 7-bit) for the quantizer; entry 0 is transparency only
    pal = open(os.path.join(ROOT, 'data', 'palette.bin'), 'rb').read()
    flat = []
    for i in range(256):
        flat += [pal[i] << 1, pal[256 + i] << 1, pal[512 + i] << 1]
    flat[0:3] = [255, 0, 255]
    palimg = Image.new('P', (1, 1))
    palimg.putpalette(flat)

    solid, oneway = bytearray(256), bytearray(256)
    tex = bytearray(256 * 64)
    solid[15] = 1                                           # barrel: invisible solid
    free = {0: list(BG_IDS), 1: list(SOLID_IDS)}

    def quant(cell):
        q = Image.fromarray(cell[:, :, :3].copy(), 'RGB').quantize(
            palette=palimg, dither=Image.Dither.NONE)
        data = bytearray(q.tobytes())
        for n, a in enumerate(cell[:, :, 3].ravel()):
            if a < 128:
                data[n] = 0
        return data

    # the animated tiles first: consecutive background ids per texture; their
    # frames (frame k of every tile of a texture back to back) for VRAM_ANIM
    ids = bytearray(MAP_W * MAP_H)
    at_rows, an_vram, ap_rows = [], bytearray(), []
    for t, (name, a, order, seqs) in enumerate(anim):
        id0 = free[0][0]
        groups = sorted(seqs.values())
        for g, seq in groups:
            tt = free[0].pop(0)
            assert tt == id0 + g and seq[0][0] >= 4, name
            tex[tt * 64:tt * 64 + 64] = quant(seq[0][2])
            solid[tt] = seq[0][0] - 4 if seq[0][0] >= 5 else 0
        at_rows.append((id0, len(groups), len(order), a['waitcount'], len(an_vram)))
        for f in range(len(order)):
            for g, seq in groups:
                an_vram += quant(seq[f][2])
        for p in panels:
            if p['tex'] < len(textures) and textures[p['tex']] == name:
                cs = [i for i in panel_cells(p) if anim_cell.get(i, (None,))[0] == t]
                if cs:
                    cols, rows = [i % MAP_W for i in cs], [i // MAP_W for i in cs]
                    ap_rows.append((t, min(cols), min(rows), max(cols) + 1, max(rows) + 1))
    for i, (t, g) in anim_cell.items():
        ids[i] = at_rows[t][0] + g
    if len(at_rows) > AT_MAX or len(ap_rows) > AP_MAX or len(an_vram) > ANIM_VRAM_BYTES:
        raise SystemExit(f'animated textures: {len(at_rows)} / {len(ap_rows)} panels / '
                         f'{len(an_vram)} B over')
    an_ram = bytearray((len(at_rows), len(ap_rows)))
    for f in range(4):                          # at_id0, at_n, at_fr, at_wait
        an_ram += bytes(r[f] & 255 for r in at_rows).ljust(AT_MAX, bytes(1))
    an_ram += bytes(r[4] & 255 for r in at_rows).ljust(AT_MAX, bytes(1))
    an_ram += bytes(r[4] >> 8 for r in at_rows).ljust(AT_MAX, bytes(1))
    for f in range(5):
        an_ram += bytes(r[f] for r in ap_rows).ljust(AP_MAX, bytes(1))

    tid = {}
    for j, k in enumerate(keys):
        if root(j) != j:
            continue
        b = beh[j]
        t = free[grp[j]].pop(0)
        cell = uniq[k][0]
        tex[t * 64:t * 64 + 64] = quant(cell)
        solid[t] = 1 if b in (1, 3) else b - 4 if b >= 5 else 0   # bg: the liquid
        oneway[t] = 1 if b == 2 else 0
        tid[j] = t
    index = {k: j for j, k in enumerate(keys)}
    for i, key in enumerate(cell_key):
        if key is not None:
            ids[i] = tid[root(index[key])]
    alt_ids = {i: (tid[root(index[k])] if (k := alt_key.get(i)) else 0) for i in toggled}
    same = [(panels[j]['x'], panels[j]['y'], sum(1 for i in panel_cells(panels[j]) if alt_ids[i] == ids[i]),
             len(list(panel_cells(panels[j])))) for j in doors]
    print('  doors (x, y, cells that do not change, cells):', [s for s in same if s[2]])
    fore = fore_rects(panels, ids) + liquid_rects(panels, textures)
    trig = trigger_block(panels, triggers, doors, switches, ids, alt_ids)
    with open(tiles_path, 'wb') as f:
        f.write(ids + solid + oneway + tex + fore + trig)     # fore: + the liquids
        # tiles used: ids 0..top (walls, with the barrels' 15) and
        # 128..127+nb (background): the assignment takes them in order and
        # map2bin stores only those
        k = len(SOLID_IDS) - len(free[1])
        f.write(bytes((max([15] + SOLID_IDS[:k]), len(BG_IDS) - len(free[0]))))
        f.write(an_ram.ljust(ANIM_RAM_BYTES, bytes(1)) + an_vram)   # map2bin: the rest
    if anim:
        print(f"  animated: {len(at_rows)} textures, {n_anim} tiles, {len(ap_rows)} panels, "
              f"{len(an_vram)} B frames")
    print(f"  tileset: {len(tid)} tiles ({sum(1 for t in tid.values() if t >= 128)} bg), "
          f"from {len(keys)} distinct cells -> {tiles_path}")


def panel_cells(p):
    """Map cell indices a panel (or trigger) rectangle covers."""
    for ty in range(max(0, p['y'] // 16), min(MAP_H, (p['y'] + p['h'] + 15) // 16)):
        for tx in range(max(0, p['x'] // 16), min(MAP_W, (p['x'] + p['w'] + 15) // 16)):
            yield ty * MAP_W + tx


def touching(a, b):
    """g_CollideAround: the rects overlap after a 1 px shift in x or y."""
    def ov(ax, ay, aw, ah):
        return ax < b['x'] + b['w'] and b['x'] < ax + aw and ay < b['y'] + b['h'] and b['y'] < ay + ah
    return (ov(a['x'] - 1, a['y'], a['w'] + 2, a['h']) or ov(a['x'], a['y'] - 1, a['w'], a['h'] + 2))


# Trigger block (source/triggers.asm TRIG_*): a RAM image read straight to
# trig_ram, then the panels' cell lists for VRAM_TPC.
TR_MAX, PL_MAX, DP_MAX, SP_MAX, LF_MAX, BM_MAX = 76, 32, 48, 24, 12, 24
TRIG_RAM_BYTES = 13 * TR_MAX + PL_MAX + 8 * DP_MAX + 3 * SP_MAX + 6 * LF_MAX + 4 + 1 + 4 * BM_MAX
TRIG_RAM_SECTORS = (TRIG_RAM_BYTES + 127) // 128
TRIG_VRAM_BYTES = 3072          # VRAM_TPC (bank-aligned, read bank by bank)
KEYMAP = ((1, 1), (2, 4), (4, 2))       # D2DF red/green/blue -> zpkeys red/yellow/blue
SUPPORTED = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 16, 17, 18, 20}
TRIG_SFX = {'DSPAUK': 44}             # TRIGGER_SOUND name -> SFX_* (constants.asm)


def trigger_block(panels, triggers, doors, switches, ids, alt_ids):
    """g_triggers.pas data for the engine. Rects in map cells (every trigger
    of the original maps sits on the 16 px grid). Per trigger p0..p3:
    doors/traps p0 = door panel; lifts p0 = lift; teleport p0..p3 = foot
    point (half px, 16-bit x, y) of the player put there; PRESS/ON/OFF
    p0/p1 = its target list in tr_pl, p2 = wait, p3 = count."""
    def rect(o):
        c0, r0 = max(0, o['x'] // 16), max(0, o['y'] // 16)
        return c0, r0, min(MAP_W, (o['x'] + o['w'] + 15) // 16), min(MAP_H, (o['y'] + o['h'] + 15) // 16)

    lifts = [j for j, p in enumerate(panels) if p['type'] & (PANEL_LIFTUP | PANEL_LIFTDOWN)]
    tr = [t for t in triggers if t['type'] in SUPPORTED][:TR_MAX]
    if len(doors) > DP_MAX or len(switches) > SP_MAX or len(lifts) > LF_MAX:
        raise SystemExit(f'triggers: {len(doors)} doors / {len(switches)} switches / {len(lifts)} lifts over')

    def groups(idx):
        g = list(range(len(idx)))               # d2d: flood fill of touching panels

        def root(k):
            while g[k] != k:
                k = g[k]
            return k
        for a in range(len(idx)):
            for b in range(a + 1, len(idx)):
                if touching(panels[idx[a]], panels[idx[b]]):
                    g[root(b)] = root(a)
        return [root(k) for k in range(len(idx))]

    vram = bytearray()

    def cell_list(j):
        cells = list(panel_cells(panels[j]))
        if (len(vram) + 4 * len(cells)) // 4096 != len(vram) // 4096:
            vram.extend(bytes(-len(vram) % 4096))   # one MEMAC bank per list
        off = len(vram)
        vram.append(len(cells))
        for i in cells:
            vram.extend((i % MAP_W, i // MAP_W, alt_ids[i], ids[i]))
        return off

    arr = {k: [0] * TR_MAX for k in ('c0', 'r0', 'c1', 'r1', 'type', 'act', 'keys', 'flag',
                                     'tex', 'p0', 'p1', 'p2', 'p3')}
    pl = []
    for n, t in enumerate(tr):
        d = t['data']
        c0, r0, c1, r1 = rect(t)
        keys = sum(o for b, o in KEYMAP if t['keys'] & b)
        flag = 1 if t['enabled'] else 0
        tp = t['type']
        p = [0, 0, 0, 0]
        if tp in (3, 4, 5, 6, 7, 8, 11, 12, 13):
            pid = struct.unpack_from('<i', d, 0)[0]
            lst = doors if tp <= 8 else lifts
            p[0] = lst.index(pid) if pid in lst else 0xFF
            flag |= (2 if d[5] else 0) | (4 if d[4] else 0)
        elif tp == 2:
            tx, ty = struct.unpack_from('<ii', d, 0)
            if not d[8]:                        # top-left of the player rect
                rx, ry, rw, rh = PLAYER_RECT
                tx, ty = tx + rw // 2, ty + rh
            fx, fy = tx // 2, ty // 2
            p = [fx & 255, fx >> 8, fy & 255, fy >> 8]
            flag |= (4 if d[9] else 0) | ((d[10] & 3) << 4)
        elif tp in (9, 15, 16, 17):
            tx, ty, tw, th, wait, count = struct.unpack_from('<iiHHHH', d, 0)
            tg = [k for k, o in enumerate(tr)
                  if (k != n or wait > 0) and o['x'] < tx + tw and tx < o['x'] + o['w']
                  and o['y'] < ty + th and ty < o['y'] + o['h']]
            if wait > 254:                      # TF_LONG: steps of 16 ticks
                assert wait % 16 == 0 and wait // 16 <= 254, wait
                wait //= 16
                flag |= 16
            p = [len(pl), len(tg), wait, min(count, 255)]
            pl += tg
            flag |= 8 if d[20] else 0
        elif tp == 18:                          # SOUND: p0 = SFX_*, p1 = play count
            name = d[:64].split(bytes(1))[0].decode().split(chr(92))[-1]
            p = [TRIG_SFX[name], max(1, d[67]), 0, 0]
        elif tp == 20:                          # SPAWNITEM: the item's pk_x / feet y,
            import map2bin                      # pk_type in flag bits 3-7
            tx, ty = struct.unpack_from('<ii', d, 0)
            ch, iw, ih = ITEM_MAP[d[8]]
            fx, fy = max(0, (tx + iw // 2) // 2 - 8), (ty + ih) // 2
            p = [fx & 255, fx >> 8, fy & 255, fy >> 8]
            flag |= map2bin.PTYPE[map2bin.ENTITY_MAP[ch][1]] << 3
        for k, v in zip(arr, (c0, r0, c1, r1, tp, t['act'], keys, flag,
                              switches.index(t['tex_panel']) if t['tex_panel'] in switches else 0xFF,
                              *p)):
            arr[k][n] = v
    if len(pl) > PL_MAX:
        raise SystemExit(f'triggers: press lists {len(pl)} > {PL_MAX}')
    dg = groups(doors)
    dp = {k: [0] * DP_MAX for k in ('c0', 'r0', 'c1', 'r1', 'grp', 'state', 'vlo', 'vhi')}
    for k, j in enumerate(doors):
        off = cell_list(j)
        closed = 3 if panels[j]['type'] & PANEL_CLOSEDOOR else 0      # bit0 closed, bit1 default
        for f, v in zip(dp, (*rect(panels[j]), dg[k], closed, off & 255, off >> 8)):
            dp[f][k] = v
    sp = {k: [0] * SP_MAX for k in ('state', 'vlo', 'vhi')}
    for k, j in enumerate(switches):
        off = cell_list(j)
        sp['vlo'][k], sp['vhi'][k] = off & 255, off >> 8
    lg = groups(lifts)
    lf = {k: [0] * LF_MAX for k in ('c0', 'r0', 'c1', 'r1', 'type', 'grp')}
    for k, j in enumerate(lifts):
        for f, v in zip(lf, (*rect(panels[j]), 1 if panels[j]['type'] & PANEL_LIFTDOWN else 0, lg[k])):
            lf[f][k] = v
    if len(vram) > TRIG_VRAM_BYTES:
        raise SystemExit(f'triggers: panel cells {len(vram)} B > {TRIG_VRAM_BYTES}')
    out = bytearray()
    for a in arr.values():
        out += bytes(v & 255 for v in a)
    out += bytes(pl).ljust(PL_MAX, b'\0')
    for d in (dp, sp, lf):
        for a in d.values():
            out += bytes(v & 255 for v in a)
    out += bytes((len(tr), len(doors), len(switches), len(lifts)))
    bm = [rect(p) for p in panels if p['type'] & PANEL_BLOCKMON]
    if len(bm) > BM_MAX:
        raise SystemExit(f'triggers: blockmon {len(bm)} > {BM_MAX}')
    out.append(len(bm))                             # bm_n, bm_c0/r0/c1/r1[BM_MAX]
    for f in range(4):
        out += bytes(b[f] for b in bm).ljust(BM_MAX, b'\0')
    assert len(out) == TRIG_RAM_BYTES
    print(f"  triggers: {len(tr)} ({len(triggers) - len(tr)} unsupported), {len(doors)} doors, "
          f"{len(switches)} switches, {len(lifts)} lifts, press {len(pl)}, cells {len(vram)} B")
    return out.ljust(TRIG_RAM_SECTORS * 128, b'\0') + vram.ljust(TRIG_VRAM_BYTES, b'\0')


FORE_BK = 16                    # bucket size in cells (source/fore.asm FB_*)
FORE_NB = (MAP_W + FORE_BK - 1) // FORE_BK
FORE_MAX = 160
FORE_BYTES = FORE_NB * FORE_NB + 1 + 4 * FORE_MAX


def fore_rects(panels, ids):
    """Foreground (PANEL_FORE) cells with a visible tile as rectangles, cut
    to FORE_BK x FORE_BK buckets: fb_first[NB*NB+1] (first rect of each
    bucket, by*NB+bx; the last entry = the count), then fr_c0, fr_r0, fr_w,
    fr_h [FORE_MAX] each. The game draws them over the sprites."""
    cell = bytearray(MAP_W * MAP_H)
    for p in panels:
        if p['type'] & PANEL_FORE:
            for ty in range(max(0, p['y'] // 16), min(MAP_H, (p['y'] + p['h'] + 15) // 16)):
                for tx in range(max(0, p['x'] // 16), min(MAP_W, (p['x'] + p['w'] + 15) // 16)):
                    if ids[ty * MAP_W + tx]:
                        cell[ty * MAP_W + tx] = 1
    rects = []
    for by in range(FORE_NB):
        for bx in range(FORE_NB):
            x0, y0 = bx * FORE_BK, by * FORE_BK
            x1, y1 = min(MAP_W, x0 + FORE_BK), min(MAP_H, y0 + FORE_BK)
            for r in range(y0, y1):                 # greedy: widest run, then down
                for c in range(x0, x1):
                    if not cell[r * MAP_W + c]:
                        continue
                    w = 1
                    while c + w < x1 and cell[r * MAP_W + c + w]:
                        w += 1
                    h = 1
                    while r + h < y1 and all(cell[(r + h) * MAP_W + c + k] for k in range(w)):
                        h += 1
                    for rr in range(r, r + h):
                        for k in range(w):
                            cell[rr * MAP_W + c + k] = 0
                    rects.append((by * FORE_NB + bx, c, r, w, h))
    if len(rects) > FORE_MAX:
        print(f"  WARNING: {len(rects)} foreground rects > {FORE_MAX}, cut")
        rects = rects[:FORE_MAX]
    first = [0] * (FORE_NB * FORE_NB + 1)
    for b in range(FORE_NB * FORE_NB + 1):
        first[b] = sum(1 for r in rects if r[0] < b)
    out = bytearray(first)
    for k in range(1, 5):
        out += bytes(r[k] for r in rects).ljust(FORE_MAX, b'\0')
    print(f"  foreground: {len(rects)} rects")
    return out


LIQ_MAX = 80                    # source/liquid.asm LQ_MAX
LIQ_BYTES = FORE_NB * FORE_NB + 1 + 5 * LIQ_MAX


def liquid_rects(panels, textures):
    """The liquid cells (g_panel.pas PANEL_WATER / ACID1 / ACID2) as
    rectangles of one kind, cut to FORE_BK buckets like fore_rects:
    lq_first[NB*NB+1], then lq_c0, lq_r0, lq_w, lq_h, lq_k [LIQ_MAX]; lq_k =
    0 water, 1 acid1, 2 acid2. The game filters the screen in them after
    the sprites with MODE 7 (source/liquid.asm)."""
    cat = [0] * (MAP_W * MAP_H)         # 1 + filter, 0 none; the filter colour is
    names = ('_water_0', '_water_1', '_water_2')    # the texture's, not the type's
    for flag in (PANEL_ACID1, PANEL_ACID2, PANEL_WATER):
        for p in panels:                # drawn in this order: the last one shows
            name = textures[p['tex']] if p['tex'] < len(textures) else ''
            if p['type'] & flag and name in names:
                for i in panel_cells(p):
                    cat[i] = 1 + names.index(name)
    rects = []
    for by in range(FORE_NB):
        for bx in range(FORE_NB):
            x0, y0 = bx * FORE_BK, by * FORE_BK
            x1, y1 = min(MAP_W, x0 + FORE_BK), min(MAP_H, y0 + FORE_BK)
            for r in range(y0, y1):
                for c in range(x0, x1):
                    v = cat[r * MAP_W + c]
                    if not v:
                        continue
                    w = 1
                    while c + w < x1 and cat[r * MAP_W + c + w] == v:
                        w += 1
                    h = 1
                    while r + h < y1 and all(cat[(r + h) * MAP_W + c + k] == v for k in range(w)):
                        h += 1
                    for rr in range(r, r + h):
                        for k in range(w):
                            cat[rr * MAP_W + c + k] = 0
                    rects.append((by * FORE_NB + bx, c, r, w, h, v - 1))
    if len(rects) > LIQ_MAX:
        raise SystemExit(f'liquids: {len(rects)} rects > {LIQ_MAX}')
    out = bytearray(sum(1 for q in rects if q[0] < b) for b in range(FORE_NB * FORE_NB + 1))
    for k in range(1, 6):
        out += bytes(q[k] for q in rects).ljust(LIQ_MAX, b'\0')
    print(f"  liquids: {len(rects)} rects")
    return out


def atari_image(tiles_path):
    """The converted map as the Atari draws it: 8x8 tiles from the .tiles
    file, 1 px = 1 Atari px (800x800). Index 0 shows as the PC's dark sky."""
    blob = open(tiles_path, 'rb').read()
    n = MAP_W * MAP_H
    ids, tex = blob[:n], blob[n + 512:n + 512 + 256 * 64]
    pal = open(os.path.join(ROOT, 'data', 'palette.bin'), 'rb').read()
    rgb = [(24, 24, 32)] + [(pal[i] << 1, pal[256 + i] << 1, pal[512 + i] << 1)
                            for i in range(1, 256)]
    out = Image.new('RGB', (MAP_W * 8, MAP_H * 8), rgb[0])
    tiles = {}
    for i, t in enumerate(ids):
        if not t:
            continue
        if t not in tiles:
            im = Image.new('RGB', (8, 8))
            im.putdata([rgb[b] for b in tex[t * 64:t * 64 + 64]])
            tiles[t] = im
        out.paste(tiles[t], ((i % MAP_W) * 8, (i // MAP_W) * 8))
    return out


def compare_png(map_path, our_path, png_path):
    """PC map 1:1 with the converted Atari map on top: cells solid only on the
    PC red, solid only on the Atari blue, Atari entities as cyan boxes with
    their map character. Prints the mismatch counts."""
    render_png(map_path, png_path)
    img = Image.open(png_path).convert('RGBA')
    over = Image.new('RGBA', img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(over)
    _, _, panels, *_ = read_d2df(map_path)
    pc = set()
    for p in panels:
        if p['type'] & (PANEL_WALL | PANEL_CLOSEDOOR):
            for ty in range(max(0, p['y'] // 16), min(MAP_H, (p['y'] + p['h'] + 15) // 16)):
                for tx in range(max(0, p['x'] // 16), min(MAP_W, (p['x'] + p['w'] + 15) // 16)):
                    pc.add((tx, ty))
    lines = open(our_path).read().splitlines()
    rows = [l for l in lines if not l.startswith(';')]
    for l in lines:                         # exact spawns: foot point x2
        if l.startswith('; ENT '):
            ch, x, y = l[6:].split()
            fx, fy = (int(x) + 8) * 2, (int(y) + 16) * 2
            draw.rectangle((fx - 8, fy - 16, fx + 7, fy - 1), outline=(0, 255, 255, 255))
            draw.text((fx - 3, fy - 14), ch, fill=(0, 255, 255, 255))
    sys.path.insert(0, os.path.join(ROOT, 'tools'))
    from map2bin import TILE_MAP, ENTITY_MAP
    ours, ents = set(), []
    for r, line in enumerate(rows[:MAP_H]):
        for c in range(min(MAP_W, (len(line) + 1) // 2)):
            ch, mod = line[2 * c], (line[2 * c + 1] if 2 * c + 1 < len(line) else ' ')
            if ch in ENTITY_MAP:
                ents.append((c, r, ch))
            elif ch in TILE_MAP and mod != 'b' and ch not in '.~ YE$':
                ours.add((c, r))
    for (c, r) in pc - ours:
        draw.rectangle((c * 16, r * 16, c * 16 + 15, r * 16 + 15), fill=(255, 0, 0, 150))
    for (c, r) in ours - pc:
        draw.rectangle((c * 16, r * 16, c * 16 + 15, r * 16 + 15), fill=(0, 80, 255, 150))
    for c, r, ch in ents:
        draw.rectangle((c * 16, r * 16, c * 16 + 15, r * 16 + 15), outline=(0, 255, 255, 255))
        draw.text((c * 16 + 4, r * 16 + 2), ch, fill=(0, 255, 255, 255))
    img.alpha_composite(over)
    tiles_path = os.path.splitext(our_path)[0] + '.tiles'
    if os.path.exists(tiles_path):              # PC | Atari (2x), side by side
        pcimg = render_image(map_path).convert('RGB')
        at = atari_image(tiles_path).resize((pcimg.width, pcimg.height), Image.NEAREST)
        both = Image.new('RGB', (pcimg.width * 2 + 16, pcimg.height), (255, 255, 255))
        both.paste(pcimg, (0, 0))
        both.paste(at, (pcimg.width + 16, 0))
        both.save(os.path.splitext(png_path)[0] + '_side.png')
    img.convert('RGB').save(png_path)
    print(f"  compare: {len(pc - ours)} cells solid only on PC (red), "
          f"{len(ours - pc)} only on Atari (blue), {len(ents)} entities -> {png_path}")


def render_image(map_path, bg=(24, 24, 32, 255), flip=(), texalt=None, aframe=None,
                 liquids=True):
    """The D2DF map 1:1 (1 px = 1 px) with its textures, as the PC draws it.
    flip: door panel indices drawn in the other state; texalt: panel index ->
    texture name drawn instead (None = not drawn); aframe: animated texture
    name -> its frame drawn (else 0); liquids: apply the liquid filter."""
    header, textures, panels, *_ = read_d2df(map_path)
    texalt = texalt or {}
    w, h = header.get('width', 1600), header.get('height', 1600)
    out = Image.new('RGBA', (w, h), bg)
    draw = ImageDraw.Draw(out)
    cache = {}
    # g_game.pas renderMapInternal: back, step, walls, closed doors, then the
    # liquids as a FILTER (g_panel.pas: e_DrawFillQuad TBlending.Filter =
    # glBlendFunc(GL_ZERO, GL_SRC_COLOR): what is under them times the colour),
    # acid1, acid2, water, then fore. Lifts and open doors are not drawn.
    liquid = {'_water_0': (0, 0, 255), '_water_1': (0, 230, 0), '_water_2': (230, 0, 0)}
    layers = [PANEL_BACK, PANEL_STEP, PANEL_WALL | PANEL_CLOSEDOOR,
              PANEL_ACID1, PANEL_ACID2, PANEL_WATER, PANEL_FORE]
    for mask in layers:
        for j, p in enumerate(panels):
            ptype = p['type']
            if j in flip:
                ptype ^= PANEL_OPENDOOR | PANEL_CLOSEDOOR
            if not ptype & mask or p['w'] == 0 or p['h'] == 0:
                continue
            name = textures[p['tex']] if p['tex'] < len(textures) else ''
            if j in texalt:
                name = texalt[j]
                if name is None:
                    continue
            box = (p['x'], p['y'], p['x'] + p['w'] - 1, p['y'] + p['h'] - 1)
            if name in liquid:          # the filter: rgb * colour / 255, alpha kept
                if not liquids:
                    continue
                x0, y0 = max(0, p['x']), max(0, p['y'])
                part = out.crop((x0, y0, min(w, p['x'] + p['w']), min(h, p['y'] + p['h'])))
                r, g, b, a = part.split()
                cr, cg, cb = liquid[name]
                part = Image.merge('RGBA', (r.point(lambda v: v * cr // 255),
                                            g.point(lambda v: v * cg // 255),
                                            b.point(lambda v: v * cb // 255), a))
                out.paste(part, (x0, y0))
                continue
            tex = load_texture(name, map_path, cache, (aframe or {}).get(name, 0))
            if tex is None:
                draw.rectangle(box, fill=(128, 128, 128, 255))
                continue
            tile = Image.new('RGBA', (p['w'], p['h']))
            for ty in range(0, p['h'], tex.height):
                for tx in range(0, p['w'], tex.width):
                    tile.paste(tex, (tx, ty))
            out.alpha_composite(tile, (max(0, p['x']), max(0, p['y'])))
    return out


# D2DF item type -> (GameWAD TEXTURES name, frame width; 0 = one image), g_items.pas
ITEM_TEX = {1: ('MED1', 0), 2: ('MED2', 0), 3: ('BMED', 0), 4: ('ARMORGREEN', 32),
            5: ('ARMORBLUE', 32), 6: ('SBLUE', 32), 7: ('SWHITE', 32), 8: ('SUIT', 0),
            9: ('OXYGEN', 0), 10: ('INVUL', 32), 11: ('SAW', 0), 12: ('SHOTGUN1', 0),
            13: ('SHOTGUN2', 0), 14: ('MGUN', 0), 15: ('RLAUNCHER', 0), 16: ('PGUN', 0),
            17: ('BFG', 0), 18: ('SCHAINGUN', 0), 19: ('CLIP', 0), 20: ('AMMO', 0),
            21: ('SHELL1', 0), 22: ('SHELL2', 0), 23: ('ROCKET', 0), 24: ('ROCKETS', 0),
            25: ('CELL', 0), 26: ('CELL2', 0), 27: ('BPACK', 0), 28: ('KEYR', 0),
            29: ('KEYG', 0), 30: ('KEYB', 0), 31: ('KNUCKLES', 0), 32: ('PISTOL', 0),
            33: ('BOTTLE', 16), 34: ('HELMET', 16), 35: ('JETPACK', 32), 36: ('INVIS', 32),
            37: ('FLAMETHROWER', 0), 38: ('FUELCAN', 0)}
# D2DF monster type -> (MTEXTURES name, frame width), g_monsters.pas
MON_TEX = {1: ('DEMON', 64), 2: ('IMP', 64), 3: ('ZOMBY', 64), 4: ('SERG', 64),
           5: ('CYBER', 128), 6: ('CGUN', 64), 7: ('BARON', 128), 8: ('KNIGHT', 128),
           9: ('CACO', 128), 10: ('SOUL', 64), 11: ('PAIN', 128), 12: ('SPIDER', 256),
           13: ('BSP', 128), 14: ('MANCUB', 128), 15: ('SKEL', 128), 16: ('VILE', 128),
           17: ('FISH', 32), 18: ('BARREL', 64), 19: ('ROBO', 128), 20: ('MAN', 64)}


def render_png(map_path, png_path, closed=False):
    """render_image + entity markers (START / EXIT labels) + stats; closed:
    every door panel in its other state (traps shut, doors open)."""
    header, textures, panels, items, areas, monsters, triggers = read_d2df(map_path)
    w, h = header.get('width', 1600), header.get('height', 1600)
    flip = {j for j, p in enumerate(panels) if p['type'] & (PANEL_OPENDOOR | PANEL_CLOSEDOOR)} if closed else ()
    out = render_image(map_path, flip=flip)
    plain = out.convert('RGB')          # the tiles only (stats), before the sprites
    draw = ImageDraw.Draw(out)

    def label(x0, y0, x1, y1, text, col):
        """Thick frame + a text plate above it: start / exit stand out."""
        draw.rectangle((x0 - 4, y0 - 4, x1 + 4, y1 + 4), outline=col, width=4)
        tw = 6 * len(text) + 8
        ty = max(0, y0 - 22)
        draw.rectangle((x0 - 4, ty, x0 - 4 + tw, ty + 14), fill=col)
        draw.text((x0, ty + 2), text, fill=(0, 0, 0, 255))
    tele = 0
    for t in triggers:
        if t['type'] == TRIGGER_EXIT:
            label(t['x'], t['y'], t['x'] + t['w'] - 1, t['y'] + t['h'] - 1,
                  'EXIT', (255, 40, 40, 255))
        elif t['type'] == TRIGGER_TELEPORT:     # g_triggers.pas: area -> TargetPoint
            tele += 1
            col = (40, 220, 255, 255)
            x0, y0 = t['x'], t['y']
            label(x0, y0, x0 + t['w'] - 1, y0 + t['h'] - 1, f'TELE {tele}', col)
            tx, ty = struct.unpack_from('<ii', t['data'], 0)
            rx, ry, rw, rh = PLAYER_RECT
            if t['data'][8]:                    # d2d: the point is the player's feet
                tx, ty = tx - rw // 2, ty - rh
            draw.line((x0 + t['w'] // 2, y0 + t['h'] // 2, tx + rw // 2, ty + rh // 2),
                      fill=col, width=2)
            label(tx, ty, tx + rw - 1, ty + rh - 1, f'CIEL {tele}', col)
    game = os.path.join(ROOT, 'git', 'DF-Assets-master', 'GameWAD')

    def sprite(folder, name, fw, x, y, mirror=False):
        """The first fw-wide frame of a GameWAD texture, top-left at x, y."""
        path = os.path.join(game, folder, name + '.tga')
        if not os.path.exists(path):
            return False
        img = Image.open(path).convert('RGBA')
        img = img.crop((0, 0, min(fw or img.width, img.width), img.height))
        if mirror:
            img = img.transpose(Image.FLIP_LEFT_RIGHT)
        out.alpha_composite(img, (max(0, x), max(0, y)))
        return True
    for it in items:                    # g_items.pas: texture (first frame) at Obj.X/Y
        tex, fw = ITEM_TEX.get(it['type'], (None, 0))
        if not (tex and sprite('TEXTURES', tex, fw, it['x'], it['y'])):
            draw.rectangle((it['x'], it['y'], it['x'] + 11, it['y'] + 11),
                           fill=(255, 220, 0, 255), outline=(0, 0, 0, 255))
    for m in monsters:                  # g_monsters.pas: the first SLEEP frame
        tex, fw = MON_TEX.get(m['type'], (None, 0))
        if not (tex and sprite('MTEXTURES', tex + '_SLEEP', fw, m['x'], m['y'], m['dir'] == 1)):
            draw.rectangle((m['x'], m['y'], m['x'] + 15, m['y'] + 23),
                           fill=(230, 30, 30, 255), outline=(0, 0, 0, 255))
    for a in areas:
        if a['type'] == AREA_PLAYER1:       # single-player start (P2 = co-op)
            # g_player.pas Respawn: the area is the top-left of PLAYER_RECT
            _, _, rw, rh = PLAYER_RECT
            x0, y0 = a['x'], a['y']
            draw.rectangle((x0, y0, x0 + rw - 1, y0 + rh - 1), fill=(30, 230, 30, 255))
            # (the frame inside the rect: its bottom edge stays the feet)
            label(x0 + 4, y0 + 4, x0 + rw - 5, y0 + rh - 5, 'START', (30, 230, 30, 255))
    # unique 16x16 pieces of the textured layers = tiles an Atari tileset needs
    uniq = set()
    rgb = out.convert('RGB')
    for p in panels:
        if p['type'] & (PANEL_BACK | PANEL_WALL | PANEL_FORE | PANEL_STEP |
                        PANEL_OPENDOOR | PANEL_CLOSEDOOR):
            for ty in range(p['y'], p['y'] + p['h'], 16):
                for tx in range(p['x'], p['x'] + p['w'], 16):
                    uniq.add(plain.crop((tx, ty, tx + 16, ty + 16)).tobytes())
    rgb.save(png_path)
    print(f"  {header.get('name', '')}: {w}x{h} -> {png_path}, "
          f"{len(textures)} textures, {len(uniq)} unique 16x16 tiles, "
          f"{len(monsters)} monsters, {len(items)} items, {len(triggers)} triggers")


def stats(maps):
    """Monster / single-player item type counts over all maps."""
    mons, its = {}, {}
    for m in maps:
        _, _, _, items, _, monsters, _ = read_d2df(m)
        for x in monsters:
            mons[x['type']] = mons.get(x['type'], 0) + 1
        for x in items:
            its[x['type']] = its.get(x['type'], 0) + 1
    print('monsters', dict(sorted(mons.items())))
    print('items   ', dict(sorted(its.items())))
    for m in maps:                                  # items hidden by foreground panels
        _, _, panels, items, _, _, _ = read_d2df(m)
        fore = [p for p in panels if p['type'] & PANEL_FORE]
        hid = [(it['type'], it['x'] // 2, it['y'] // 2) for it in items      # Atari px
               if any(p['x'] <= it['x'] + 8 < p['x'] + p['w'] and p['y'] <= it['y'] + 8 < p['y'] + p['h']
                      for p in fore)]
        cells = {(ty, tx) for p in fore
                 for ty in range(p['y'] // 16, (p['y'] + p['h'] + 15) // 16)
                 for tx in range(p['x'] // 16, (p['x'] + p['w'] + 15) // 16)}
        print(f'{os.path.basename(m)}: {len(fore)} fore panels, {len(cells)} cells, items under them {hid}')
    # triggers: (type, activation bits, keys) -> count; with a texture panel
    # (a switch picture) or not
    trig = {}
    for m in maps:
        _, _, panels, *_, triggers = read_d2df(m)
        doors = sum(1 for p in panels if p['type'] & (PANEL_OPENDOOR | PANEL_CLOSEDOOR))
        lifts = sum(1 for p in panels if p['type'] & (PANEL_LIFTUP | PANEL_LIFTDOWN))
        odd = sum(1 for t in triggers if (t['x'] | t['y'] | t['w'] | t['h']) & 15)
        tele = sum(1 for t in triggers if t['type'] == TRIGGER_TELEPORT)
        bmon = [p for p in panels if p['type'] & PANEL_BLOCKMON]
        bodd = sum(1 for p in bmon if (p['x'] | p['y'] | p['w'] | p['h']) & 15)
        print(f'{os.path.basename(m)}: {len(triggers)} triggers ({tele} teleports, {odd} off the 16 px grid), '
              f'{doors} door panels, {lifts} lift panels, {len(bmon)} blockmon ({bodd} off the grid)')
        for t in triggers:
            k = (t['type'], t['act'], t['keys'], t['tex_panel'] >= 0, t['enabled'])
            trig[k] = trig.get(k, 0) + 1
    print('triggers (type, activate, keys, switch texture, enabled): count')
    for k, n in sorted(trig.items()):
        print(f'  {k}: {n}')
    pbits = {}                                      # panel type bits over all maps
    for m in maps:
        for p in read_d2df(m)[2]:
            for b in range(16):
                if p['type'] & (1 << b):
                    pbits[1 << b] = pbits.get(1 << b, 0) + 1
    print('panel type bits', dict(sorted(pbits.items())))


def list_triggers(path):
    """Every trigger of one map: index, type, activation, keys, rect (px)."""
    d = read_d2df(path)
    for n, t in enumerate(d[6]):
        pan = ''
        if t['type'] in (3, 4, 5, 6, 7, 8):                     # its door panel
            p = d[2][struct.unpack_from('<i', t['data'], 0)[0]]
            pan = f" panel {p['x']},{p['y']} {p['w']}x{p['h']} type {p['type']} tex {d[1][p['tex']] if p['tex'] < len(d[1]) else p['tex']} d2d {t['data'][5]}"
            if t['data'][5]:                                    # door panels touching it
                pan += ' touching ' + ' '.join(
                    f"{q['x']},{q['y']} {q['w']}x{q['h']} tex {d[1][q['tex']] if q['tex'] < len(d[1]) else q['tex']}" for q in d[2]
                    if q is not p and q['type'] & (PANEL_OPENDOOR | PANEL_CLOSEDOOR) and touching(p, q))
        print(f"{n:3} type {t['type']:2} act {t['act']:2} keys {t['keys']} rect "
              f"{t['x']},{t['y']} {t['w']}x{t['h']} tex {t['tex_panel']}{pan}")


def main():
    if '--triggers' in sys.argv:
        # python d2df2map.py --triggers pc.map
        list_triggers([x for x in sys.argv[1:] if x != '--triggers'][0])
        return
    if '--stats' in sys.argv:
        # python d2df2map.py --stats maps...
        stats([x for x in sys.argv[1:] if x != '--stats'])
        return
    if '--cmp' in sys.argv:
        # python d2df2map.py --cmp pc.map atari.map out.png
        a = [x for x in sys.argv[1:] if x != '--cmp']
        compare_png(a[0], a[1], a[2])
        return
    if '--png' in sys.argv:
        # --closed: every door panel in its other state, as MAPxx_closed.png
        closed = '--closed' in sys.argv
        args = [a for a in sys.argv[1:] if a not in ('--png', '--closed')]
        out_dir, maps = args[0], args[1:]
        os.makedirs(out_dir, exist_ok=True)
        for m in maps:
            name = os.path.splitext(os.path.basename(m))[0] + ('_closed' if closed else '')
            render_png(m, os.path.join(out_dir, name + '.png'), closed)
        return
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2])


if __name__ == '__main__':
    main()
