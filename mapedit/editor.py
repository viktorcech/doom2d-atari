"""
DOOM 2D Atari - level browser: the levels straight from the game's ATR
(bin/doom2d.atr), a view of each, and "Play" = Altirra from that level.

The ATR: boot sectors 1-3, the XEX from sector 4, the levels (build_doom2d.py).
The XEX's tables (doom2d.lab): num_levels, lvl_sec_lo/hi (each level's first
sector), start_level (a new game's first level: Play writes bin/doom2d_level.atr
with it set and boots that).
A level (tools/map2bin.py): LVL_HDR sectors of header + entities, the map
(MAP_H rows of MAP_STRIDE cell ids), tile tables, the tiles in use (walls
from id 0, background from id 128), ...
"""

import os
import subprocess
import sys
import tkinter as tk
from tkinter import filedialog, messagebox

from PIL import Image, ImageDraw, ImageTk

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
from mapedit.constants import (PROJECT_ROOT, PREVIEW_DIR, ENEMY_PREVIEW,
                               PICKUP_PREVIEW, load_config, save_config)

ATR = os.path.join(PROJECT_ROOT, 'bin', 'doom2d.atr')
PLAY_ATR = os.path.join(PROJECT_ROOT, 'bin', 'doom2d_level.atr')    # Play: from level N
LAB = os.path.join(PROJECT_ROOT, 'bin', 'doom2d.lab')
PALETTE = os.path.join(PROJECT_ROOT, 'data', 'palette.bin')
SECTOR = 128
MAP_W = MAP_H = 100             # tools/map2bin.py
MAP_STRIDE = 128
LVL_HDR_SECTORS = 8             # source/diskio.asm
TILE_ATTR_SECTORS = 4
EMPTY = (24, 24, 32)            # cell id 0 (the sky shows there in the game)


class Atr:
    """bin/doom2d.atr: its sectors, the XEX in it, the level records."""

    def __init__(self, path):
        self.path = path
        self.data = bytearray(open(path, 'rb').read())
        self.lab = {}
        for line in open(LAB, encoding='latin-1'):
            f = line.split()
            if len(f) == 3 and len(f[1]) == 4:
                try:
                    self.lab[f[2].upper()] = int(f[1], 16)
                except ValueError:
                    pass
        # two XEX: VBXE at $D6xx from sector 4, at $D7xx from XEX_D7_SEC (the
        # boot loader picks one: both carry start_level, same addresses)
        self.segs = self._xex_segments(4)
        self.segs7 = self._xex_segments(self.lab['XEX_D7_SEC'])
        n = self.byte('NUM_LEVELS')
        lo, hi = self.lab['LVL_SEC_LO'], self.lab['LVL_SEC_HI']
        self.starts = [self.mem(lo + i) | self.mem(hi + i) << 8 for i in range(n)]

    def sectors(self, first, count):
        off = 16 + (first - 1) * SECTOR
        return bytes(self.data[off:off + count * SECTOR])

    def _xex_segments(self, first):
        """(load address, offset in the ATR file, length) of each segment of
        the XEX starting at sector first."""
        off, end = 16 + (first - 1) * SECTOR, len(self.data)
        segs = []
        while off + 4 <= end:
            a, b = self.data[off] | self.data[off + 1] << 8, self.data[off + 2] | self.data[off + 3] << 8
            if a == 0xFFFF:
                off += 2
                continue
            if b < a or a == 0:
                break
            segs.append((a, off + 4, b - a + 1))
            off += 4 + b - a + 1
        return segs

    def file_offset(self, addr, segs=None):
        # the last segment wins: the bank uploads go through $6000 before the
        # main code loads there
        for a, off, n in reversed(segs or self.segs):
            if a <= addr < a + n:
                return off + addr - a
        raise KeyError(f'${addr:04X} is not loaded by the XEX')

    def mem(self, addr):
        return self.data[self.file_offset(addr)]

    def byte(self, label):
        return self.mem(self.lab[label])

    def write_with_start_level(self, path, n, spawn=None):
        """This ATR with start_level = n, written to path (doom2d.atr stays);
        spawn = (x, feet y): level n's player start in its header instead."""
        data = bytearray(self.data)
        for segs in (self.segs, self.segs7):        # both XEX ($D6xx, $D7xx)
            data[self.file_offset(self.lab['START_LEVEL'], segs)] = n
        if spawn:
            x, y = spawn                # map2bin header: +0/+1 x, +2 y lo, +9 y hi
            hdr = 16 + (self.starts[n] - 1) * SECTOR
            data[hdr], data[hdr + 1], data[hdr + 2], data[hdr + 9] = x & 0xFF, x >> 8, y & 0xFF, y >> 8
        with open(path, 'wb') as f:
            f.write(data)

    def level(self, i):
        """-> dict: header fields, entities, cell ids, tile textures."""
        s = self.starts[i]
        hdr = self.sectors(s, LVL_HDR_SECTORS)
        s += LVL_HDR_SECTORS
        vram = self.sectors(s, MAP_H * MAP_STRIDE // SECTOR)
        s += MAP_H * MAP_STRIDE // SECTOR + TILE_ATTR_SECTORS
        ts_walls, ts_bg = hdr[6], hdr[7]
        tex = bytearray(256 * 64)
        w = self.sectors(s, ts_walls)
        tex[:len(w)] = w
        b = self.sectors(s + ts_walls, ts_bg)
        tex[128 * 64:128 * 64 + len(b)] = b
        ids = bytearray()
        for r in range(MAP_H):
            ids += vram[r * MAP_STRIDE:r * MAP_STRIDE + MAP_W]
        lv = {'spawn': (hdr[0] | hdr[1] << 8, hdr[2] | hdr[9] << 8),
              'ids': ids, 'tex': tex, 'enemies': [], 'pickups': [], 'barrels': []}
        p = 12
        for _ in range(hdr[3]):         # x, y, type, dir, sleep
            lv['enemies'].append((hdr[p] | hdr[p + 1] << 8, hdr[p + 2] | hdr[p + 3] << 8,
                                  hdr[p + 4], hdr[p + 5]))
            p += 7
        for _ in range(hdr[4]):         # x, y, type
            lv['pickups'].append((hdr[p] | hdr[p + 1] << 8, hdr[p + 2] | hdr[p + 3] << 8,
                                  hdr[p + 4]))
            p += 5
        for _ in range(hdr[5]):         # x, y
            lv['barrels'].append((hdr[p] | hdr[p + 1] << 8, hdr[p + 2] | hdr[p + 3] << 8))
            p += 4
        return lv


class MapEditor:
    def __init__(self, root):
        self.root = root
        self.root.title("DOOM 2D Atari - Levels")
        self.config = load_config()
        self.atr = None
        self.zoom = 1
        self.photo = None
        self.cache = {}                 # level -> PIL image
        self.sprites = {}
        self.spawn = {}                 # level -> (x, feet y): right-click start for Play
        pal = open(PALETTE, 'rb').read()
        self.rgb = [EMPTY] + [(pal[i] << 1, pal[256 + i] << 1, pal[512 + i] << 1)
                              for i in range(1, 256)]
        self._build_ui()
        self.reload()

    def _build_ui(self):
        menubar = tk.Menu(self.root)
        filemenu = tk.Menu(menubar, tearoff=0)
        filemenu.add_command(label="Reload ATR", command=self.reload, accelerator="F5")
        filemenu.add_command(label="Set Altirra path...", command=self.set_altirra_path)
        filemenu.add_separator()
        filemenu.add_command(label="Exit", command=self.root.destroy)
        menubar.add_cascade(label="File", menu=filemenu)
        self.root.config(menu=menubar)

        bar = tk.Frame(self.root, bg='#2A2A2A')
        bar.pack(side=tk.TOP, fill=tk.X)
        tk.Button(bar, text="▶ Play level", bg='#2A5020', fg='#60FF60',
                  font=('Arial', 9, 'bold'), command=self.play).pack(side=tk.LEFT, padx=4, pady=3)
        tk.Button(bar, text="Zoom 1x/2x", bg='#444', fg='#DDD',
                  command=self.toggle_zoom).pack(side=tk.LEFT, padx=4)
        self.show_ents = tk.BooleanVar(value=True)
        tk.Checkbutton(bar, text="Entities", variable=self.show_ents, bg='#2A2A2A', fg='#DDD',
                       selectcolor='#444', command=self.show).pack(side=tk.LEFT, padx=4)
        tk.Button(bar, text="Clear my spawn", bg='#444', fg='#DDD',
                  command=self.clear_spawn).pack(side=tk.LEFT, padx=4)
        tk.Label(bar, text="right-click on the map = my spawn (feet at the cursor)",
                 bg='#2A2A2A', fg='#FF60FF').pack(side=tk.LEFT, padx=8)

        main = tk.Frame(self.root, bg='#111')
        main.pack(fill=tk.BOTH, expand=True)
        self.listbox = tk.Listbox(main, width=26, bg='#222', fg='#DDD', font=('Consolas', 10),
                                  selectbackground='#2A5020', activestyle='none',
                                  exportselection=False)
        self.listbox.pack(side=tk.LEFT, fill=tk.Y)
        self.listbox.bind('<<ListboxSelect>>', lambda e: self.show())
        self.listbox.bind('<Double-Button-1>', lambda e: self.play())
        self.listbox.bind('<Return>', lambda e: self.play())

        view = tk.Frame(main)
        view.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        hs = tk.Scrollbar(view, orient=tk.HORIZONTAL)
        hs.pack(side=tk.BOTTOM, fill=tk.X)
        vs = tk.Scrollbar(view, orient=tk.VERTICAL)
        vs.pack(side=tk.RIGHT, fill=tk.Y)
        self.canvas = tk.Canvas(view, bg='black', highlightthickness=0,
                                xscrollcommand=hs.set, yscrollcommand=vs.set)
        self.canvas.pack(fill=tk.BOTH, expand=True)
        hs.config(command=self.canvas.xview)
        vs.config(command=self.canvas.yview)
        self.canvas.bind('<Button-3>', self.set_spawn)

        self.status = tk.Label(self.root, anchor=tk.W, bg='#111', fg='#AAA', padx=8,
                               font=('Consolas', 9))
        self.status.pack(side=tk.BOTTOM, fill=tk.X)
        self.root.bind('<F5>', lambda e: self.reload())

    def reload(self):
        """(Re)read bin/doom2d.atr (after a build)."""
        try:
            self.atr = Atr(ATR)
        except (OSError, KeyError) as e:
            messagebox.showerror("ATR", f"Cannot read {ATR}:\n{e}\n\nBuild first: python build_doom2d.py")
            return
        self.cache = {}
        sel = self.selected()
        self.listbox.delete(0, tk.END)
        for i in range(len(self.atr.starts)):
            lv = self.atr.level(i)
            self.listbox.insert(tk.END, f"Level {i + 1:2d}  E{len(lv['enemies']):2d} "
                                        f"P{len(lv['pickups']):2d}")
        i = sel if sel is not None and sel < len(self.atr.starts) else self.atr.byte('START_LEVEL')
        self.listbox.selection_set(i)
        self.listbox.see(i)
        self.listbox.focus_set()
        self.show()

    def selected(self):
        s = self.listbox.curselection()
        return s[0] if s else None

    def sprite(self, name, mirror=False):
        """A data/preview sprite (4x) at game size, bottom-aligned by the caller."""
        if not name:
            return None
        if name not in self.sprites:
            path = os.path.join(PREVIEW_DIR, name)
            img = None
            if os.path.exists(path):
                img = Image.open(path).convert('RGBA')
                img = img.resize((img.width // 4, img.height // 4), Image.NEAREST)
            self.sprites[name] = img
        return self.sprites[name]

    def render(self, i):
        """The level as the game draws it (1 px = 1 Atari px)."""
        if i in self.cache:
            return self.cache[i]
        lv = self.atr.level(i)
        img = Image.new('RGBA', (MAP_W * 8, MAP_H * 8), EMPTY + (255,))
        tiles = {}
        for n, t in enumerate(lv['ids']):
            if not t:
                continue
            if t not in tiles:
                tile = Image.new('RGBA', (8, 8))
                tile.putdata([self.rgb[b] + (255 if b else 0,) for b in lv['tex'][t * 64:t * 64 + 64]])
                tiles[t] = tile
            img.alpha_composite(tiles[t], ((n % MAP_W) * 8, (n // MAP_W) * 8))
        ents = img.copy()
        d = ImageDraw.Draw(ents)

        def put(spr, x, y, col):
            # x = left edge of the 16 px entity, y + 16 = its feet (map2bin)
            if spr is not None:
                ents.alpha_composite(spr, (max(0, x + 8 - spr.width // 2), max(0, y + 16 - spr.height)))
            else:
                d.rectangle((x, y, x + 15, y + 15), outline=col)
        for x, y, t, facing in lv['enemies']:
            r, l = ENEMY_PREVIEW[t] if t < len(ENEMY_PREVIEW) else (None, None)
            put(self.sprite(l if facing else r), x, y, (255, 60, 60))
        for x, y, t in lv['pickups']:
            put(self.sprite(PICKUP_PREVIEW.get(t)), x, y, (255, 220, 0))
        for x, y in lv['barrels']:
            put(self.sprite('barrel.png'), x, y, (60, 220, 60))
        sx, sy = lv['spawn']            # the player's: feet Y (map2bin spawn_py)
        put(self.sprite('player_idle.png'), sx, sy - 16, (60, 255, 60))
        d.rectangle((sx - 2, sy - 18, sx + 17, sy + 1), outline=(60, 255, 60))
        d.text((sx, max(0, sy - 30)), "START", fill=(60, 255, 60))
        self.cache[i] = (img, ents, lv)
        return self.cache[i]

    def show(self, scroll=True):
        i = self.selected()
        if i is None or not self.atr:
            return
        img, ents, lv = self.render(i)
        img = ents if self.show_ents.get() else img
        if self.zoom != 1:
            img = img.resize((img.width * self.zoom, img.height * self.zoom), Image.NEAREST)
        self.photo = ImageTk.PhotoImage(img)
        self.canvas.delete('all')
        self.canvas.create_image(0, 0, image=self.photo, anchor=tk.NW)
        self.canvas.config(scrollregion=(0, 0, img.width, img.height))
        sx, sy = lv['spawn']
        if scroll:
            self.canvas.xview_moveto(max(0, sx * self.zoom - 300) / img.width)
            self.canvas.yview_moveto(max(0, sy * self.zoom - 200) / img.height)
        mine = ""
        if i in self.spawn:             # the player rect: x..x+15, feet at y
            mx, my = self.spawn[i]
            z = self.zoom
            self.canvas.create_rectangle(mx * z, (my - 32) * z, (mx + 16) * z, my * z,
                                         outline='#FF40FF', width=2)
            self.canvas.create_text(mx * z, (my - 34) * z, text="MY SPAWN", fill='#FF40FF',
                                    anchor=tk.SW)
            mine = f", my spawn {mx},{my}"
        self.status.config(text=f"Level {i + 1}: sector {self.atr.starts[i]}, "
                                f"{len(lv['enemies'])} enemies, {len(lv['pickups'])} pickups, "
                                f"{len(lv['barrels'])} barrels, start {sx},{sy}{mine}   "
                                f"|  Enter / double-click = play")

    def set_spawn(self, e):
        """Right-click: the player starts with the feet at the cursor (Play)."""
        i = self.selected()
        if i is None or not self.atr:
            return
        px = int(self.canvas.canvasx(e.x)) // self.zoom
        py = int(self.canvas.canvasy(e.y)) // self.zoom
        if not (0 <= px < MAP_W * 8 and 0 <= py < MAP_H * 8):
            return
        self.spawn[i] = (max(0, px - 8), py)    # x = the 16 px rect's left edge
        self.show(scroll=False)

    def clear_spawn(self):
        i = self.selected()
        if i is not None and self.spawn.pop(i, None):
            self.show(scroll=False)

    def toggle_zoom(self):
        self.zoom = 3 - self.zoom
        self.show()

    def set_altirra_path(self):
        current = self.config.get('altirra', '')
        path = filedialog.askopenfilename(
            title="Select Altirra executable",
            filetypes=[("Executable", "*.exe"), ("All files", "*.*")],
            initialdir=os.path.dirname(current) if current else None)
        if path:
            self.config['altirra'] = path
            save_config(self.config)

    def play(self):
        """bin/doom2d_level.atr = bin/doom2d.atr with start_level = the
        selected level, booted in Altirra.
        New game starts there; LOAD GAME and the next levels work as usual."""
        i = self.selected()
        if i is None or not self.atr:
            return
        altirra = self.config.get('altirra', '')
        if not os.path.exists(altirra):
            self.set_altirra_path()
            altirra = self.config.get('altirra', '')
            if not os.path.exists(altirra):
                return
        spawn = self.spawn.get(i)
        self.atr.write_with_start_level(PLAY_ATR, i, spawn)
        subprocess.Popen([altirra, '/disk', PLAY_ATR])
        self.status.config(text=f"Altirra: new game starts at level {i + 1}"
                                + (f", my spawn {spawn[0]},{spawn[1]}" if spawn else ""))


def main():
    root = tk.Tk()
    root.geometry("1400x800")
    root.configure(bg='#111')
    MapEditor(root)
    root.mainloop()


if __name__ == '__main__':
    main()
