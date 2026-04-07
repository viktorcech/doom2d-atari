"""
DOOM 2D Atari Map Editor - Main editor class.
"""

import sys
import os
import copy
import tkinter as tk
from tkinter import filedialog, messagebox

try:
    from PIL import Image, ImageTk
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    print("WARNING: Pillow not installed. Using colored rectangles.")

from mapedit.constants import *

class MapEditor:
    def __init__(self, root, filename=None):
        self.root = root
        self.root.title("DOOM 2D Atari - Map Editor")
        self.root.protocol("WM_DELETE_WINDOW", self.quit_app)
        self.filename = filename
        self.current_tile = '#'
        self.modified = False
        self.show_grid = True
        self.show_visible = True
        self.fullscreen = False
        self.config = load_config()

        # Map data
        self.map_data = [['.' for _ in range(MAP_W)] for _ in range(MAP_H)]
        self.sky_name = 'D2DSKY1'   # default sky
        self.dragging = False       # drag & drop state
        self.drag_char = None
        self.drag_from = None       # (row, col)
        self.drag_ghost = None      # canvas item id

        # Tool mode: 'paint', 'rect', 'fill', 'eraser', 'link'
        self.tool = 'paint'
        self.rect_start = None      # (row, col) for rectangle tool
        self.rect_preview = None    # canvas item id

        # Switch links: list of (sw_col, sw_row, tgt_col, tgt_row, action)
        self.switch_links = []
        self.link_src = None        # (row, col) of switch being linked

        # Undo/Redo
        self.undo_stack = []
        self.redo_stack = []
        self.max_undo = 50

        # Load preview images
        self.tile_images = {}
        self.palette_images = {}
        self._load_previews()
        self._sky_tile_img = None
        self._load_sky_tile()

        self._build_ui()

        if filename and os.path.exists(filename):
            self.load_map(filename)

    def _load_previews(self):
        """Load and resize preview images for all tiles and entities."""
        if not HAS_PIL:
            return

        ts = TILE_SIZE
        darkbg_path = os.path.join(PREVIEW_DIR, 'tile_darkbg.png')
        darkbg_img = None
        if os.path.exists(darkbg_path):
            darkbg_img = Image.open(darkbg_path).resize((ts, ts), Image.NEAREST)

        for ch, name, color, preview_file in ALL_ITEMS:
            if not preview_file:
                continue
            path = os.path.join(PREVIEW_DIR, preview_file)
            if not os.path.exists(path):
                continue

            try:
                img = Image.open(path).convert('RGBA')
                orig_w, orig_h = img.size

                if orig_h > orig_w:
                    # Sprite (taller than wide, e.g. 64x128) - entity
                    # Scale to fit tile width, keep aspect ratio
                    scale = ts / orig_w
                    new_h = int(orig_h * scale)
                    sprite = img.resize((ts, new_h), Image.NEAREST)

                    # Composite: darkbg tile + bottom part of sprite
                    composite = Image.new('RGBA', (ts, ts), (0, 0, 0, 255))
                    if darkbg_img:
                        bg = darkbg_img.convert('RGBA')
                        composite = Image.alpha_composite(
                            Image.new('RGBA', (ts, ts), (0, 0, 0, 255)), bg)
                    # Crop sprite to show bottom tile-sized portion
                    crop_top = max(0, new_h - ts)
                    sprite_crop = sprite.crop((0, crop_top, ts, new_h))
                    temp = Image.new('RGBA', (ts, ts), (0, 0, 0, 0))
                    temp.paste(sprite_crop, (0, ts - sprite_crop.height))
                    composite = Image.alpha_composite(composite, temp)
                    self.tile_images[ch] = ImageTk.PhotoImage(composite)
                else:
                    # Tile (square, 64x64) - composite on darkbg like in game
                    resized = img.resize((ts, ts), Image.NEAREST)
                    if darkbg_img and resized.getchannel('A').getextrema()[0] < 255:
                        composite = darkbg_img.convert('RGBA').copy()
                        composite = Image.alpha_composite(composite, resized)
                        self.tile_images[ch] = ImageTk.PhotoImage(composite)
                    else:
                        self.tile_images[ch] = ImageTk.PhotoImage(resized)

                # Also create palette icon (smaller)
                pal_size = 24
                if orig_h > orig_w:
                    scale = pal_size / orig_w
                    pal_h = int(orig_h * scale)
                    pal_img = img.resize((pal_size, pal_h), Image.NEAREST)
                    # Crop bottom portion
                    crop_top = max(0, pal_h - pal_size)
                    pal_crop = pal_img.crop((0, crop_top, pal_size, pal_h))
                    pal_composite = Image.new('RGBA', (pal_size, pal_size), (0, 0, 0, 255))
                    temp_pal = Image.new('RGBA', (pal_size, pal_size), (0, 0, 0, 0))
                    temp_pal.paste(pal_crop, (0, pal_size - pal_crop.height))
                    pal_composite = Image.alpha_composite(pal_composite, temp_pal)
                    self.palette_images[ch] = ImageTk.PhotoImage(pal_composite)
                else:
                    self.palette_images[ch] = ImageTk.PhotoImage(
                        img.resize((pal_size, pal_size), Image.NEAREST))
            except Exception as e:
                print(f"  Warning: failed to load {preview_file}: {e}")

    def _build_ui(self):
        # Menu bar
        menubar = tk.Menu(self.root)
        filemenu = tk.Menu(menubar, tearoff=0)
        filemenu.add_command(label="New", command=self.new_map)
        filemenu.add_command(label="Open...", command=self.open_map)
        filemenu.add_command(label="Save", command=self.save_map)
        filemenu.add_command(label="Save As...", command=self.save_map_as)
        filemenu.add_separator()
        filemenu.add_command(label="Export .bin", command=self.export_bin)
        filemenu.add_command(label="Test in Altirra", command=self.test_in_altirra)
        filemenu.add_separator()
        filemenu.add_command(label="Set Altirra path...", command=self.set_altirra_path)
        filemenu.add_separator()
        filemenu.add_command(label="Exit", command=self.quit_app)
        menubar.add_cascade(label="File", menu=filemenu)

        editmenu = tk.Menu(menubar, tearoff=0)
        editmenu.add_command(label="Undo", command=self.undo, accelerator="Ctrl+Z")
        editmenu.add_command(label="Redo", command=self.redo, accelerator="Ctrl+Y")
        editmenu.add_separator()
        editmenu.add_command(label="Paint tool", command=lambda: self.set_tool('paint'))
        editmenu.add_command(label="Rectangle tool", command=lambda: self.set_tool('rect'))
        editmenu.add_command(label="Fill tool", command=lambda: self.set_tool('fill'))
        editmenu.add_command(label="Eraser tool", command=lambda: self.set_tool('eraser'))
        editmenu.add_command(label="Move tool", command=lambda: self.set_tool('move'))
        editmenu.add_command(label="Link tool (switch)", command=lambda: self.set_tool('link'))
        menubar.add_cascade(label="Edit", menu=editmenu)

        viewmenu = tk.Menu(menubar, tearoff=0)
        viewmenu.add_command(label="Toggle Grid", command=self.toggle_grid)
        viewmenu.add_command(label="Toggle Visible Area", command=self.toggle_visible)
        viewmenu.add_command(label="Toggle Fullscreen", command=self.toggle_fullscreen)
        viewmenu.add_separator()
        viewmenu.add_command(label="Screenshot...", command=self.take_screenshot)
        menubar.add_cascade(label="View", menu=viewmenu)

        self.root.config(menu=menubar)

        # Keyboard shortcuts (minimal - Ctrl combos only)
        self.root.bind('<Control-n>', lambda e: self.new_map())
        self.root.bind('<Control-o>', lambda e: self.open_map())
        self.root.bind('<Control-s>', lambda e: self.save_map())
        self.root.bind('<Control-z>', lambda e: self.undo())
        self.root.bind('<Control-y>', lambda e: self.redo())

        # Toolbar
        toolbar = tk.Frame(self.root, bg='#2A2A2A', bd=1, relief=tk.RAISED)
        toolbar.pack(side=tk.TOP, fill=tk.X)

        tool_defs = [
            ('Paint', 'paint', '#60FF60'),
            ('Rect', 'rect', '#FF6060'),
            ('Fill', 'fill', '#6060FF'),
            ('Eraser', 'eraser', '#FFD700'),
            ('Move', 'move', '#00CCCC'),
        ]
        self.tool_buttons = {}
        for label, tool, color in tool_defs:
            btn = tk.Button(toolbar, text=label,
                            bg='#444', fg=color, activebackground='#555',
                            activeforeground=color, font=('Arial', 8, 'bold'),
                            relief=tk.RAISED, bd=1, padx=6, pady=2,
                            command=lambda t=tool: self.set_tool(t))
            btn.pack(side=tk.LEFT, padx=2, pady=2)
            self.tool_buttons[tool] = btn

        # Separator
        tk.Frame(toolbar, width=2, bg='#666').pack(side=tk.LEFT, fill=tk.Y, padx=4, pady=2)

        # Link switch button
        link_tb_btn = tk.Button(toolbar, text="Link Switch \u2192 Target",
                                bg='#402060', fg='#FF00FF', activebackground='#603090',
                                activeforeground='#FF80FF', font=('Arial', 8, 'bold'),
                                relief=tk.RAISED, bd=1, padx=6, pady=2,
                                command=lambda: self.set_tool('link'))
        link_tb_btn.pack(side=tk.LEFT, padx=2, pady=2)
        self.tool_buttons['link'] = link_tb_btn

        # Separator
        tk.Frame(toolbar, width=2, bg='#666').pack(side=tk.LEFT, fill=tk.Y, padx=4, pady=2)

        # Screenshot button
        tk.Button(toolbar, text="\U0001f4f7 Screenshot",
                  bg='#444', fg='#AAAAAA', activebackground='#555',
                  font=('Arial', 8, 'bold'), relief=tk.RAISED, bd=1, padx=6, pady=2,
                  command=self.take_screenshot).pack(side=tk.LEFT, padx=2, pady=2)

        # Test in Altirra button
        tk.Button(toolbar, text="\u25B6 Test Game",
                  bg='#2A5020', fg='#60FF60', activebackground='#3A6030',
                  activeforeground='#80FF80', font=('Arial', 8, 'bold'),
                  relief=tk.RAISED, bd=1, padx=6, pady=2,
                  command=self.test_in_altirra).pack(side=tk.LEFT, padx=2, pady=2)

        # Main layout
        main = tk.Frame(self.root)
        main.pack(fill=tk.BOTH, expand=True)

        # Left: tile palette with scroll
        pal_outer = tk.Frame(main, width=210, bg='#222')
        pal_outer.pack(side=tk.LEFT, fill=tk.Y)
        pal_outer.pack_propagate(False)

        pal_canvas = tk.Canvas(pal_outer, bg='#222', highlightthickness=0)
        pal_scroll = tk.Scrollbar(pal_outer, orient=tk.VERTICAL, command=pal_canvas.yview)
        pal_canvas.configure(yscrollcommand=pal_scroll.set)
        pal_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        pal_canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        palette_frame = tk.Frame(pal_canvas, bg='#222')
        pal_canvas.create_window((0, 0), window=palette_frame, anchor=tk.NW)
        palette_frame.bind('<Configure>',
            lambda e: pal_canvas.configure(scrollregion=pal_canvas.bbox('all')))

        # Current tile indicator (at top for easy access)
        sel_frame = tk.Frame(palette_frame, bg='#333', bd=1, relief=tk.SUNKEN)
        sel_frame.pack(pady=(4, 6), padx=4, fill=tk.X)
        self.current_label = tk.Label(sel_frame, text="# wall", fg='white',
                                       bg='#808080', width=14, height=1,
                                       relief=tk.RAISED, font=('Arial', 9, 'bold'))
        self.current_label.pack(side=tk.LEFT, padx=2, pady=2)
        self.current_preview = tk.Label(sel_frame, bg='#333')
        self.current_preview.pack(side=tk.LEFT, padx=2, pady=2)
        self._update_current_preview()

        # --- Tiles ---
        self._add_palette_group(palette_frame, "Walls", '#FF6060', TILES_WALLS, cols=4)
        self._add_palette_group(palette_frame, "Floors", '#60FF60', TILES_FLOORS, cols=4)
        self._add_palette_group(palette_frame, "BG", '#6060FF', TILES_BG, cols=3)
        self._add_palette_group(palette_frame, "Doors & Switches", '#CD853F',
                                TILES_DOORS + TILES_SWITCHES, cols=4)

        # --- Entities ---
        self._add_palette_group(palette_frame, "Player", '#00FF00',
                                ENTITY_PLAYER, cols=1)
        # Interleave R/L pairs so they appear side by side: zombie> zombie< imp> imp< ...
        enemy_pairs = []
        for r, l in zip(ENTITIES_R, ENTITIES_L):
            enemy_pairs.append(r)
            enemy_pairs.append(l)
        self._add_palette_group(palette_frame, "Enemies (\u25B6 right  \u25C0 left)", '#FFD700',
                                enemy_pairs, cols=4)
        self._add_palette_group(palette_frame, "Pickups", '#FFD700', ENTITIES_PICKUPS, cols=5)
        self._add_palette_group(palette_frame, "Decorations", '#FFD700', ENTITIES_DECOR, cols=4)

        # Sky background selector
        self._add_sky_selector(palette_frame)

        # Right: canvas with scrollbars
        canvas_frame = tk.Frame(main)
        canvas_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        self.hscroll = tk.Scrollbar(canvas_frame, orient=tk.HORIZONTAL)
        self.hscroll.pack(side=tk.BOTTOM, fill=tk.X)
        self.vscroll = tk.Scrollbar(canvas_frame, orient=tk.VERTICAL)
        self.vscroll.pack(side=tk.RIGHT, fill=tk.Y)

        canvas_w = MAP_W * TILE_SIZE
        canvas_h = MAP_H * TILE_SIZE

        self.canvas = tk.Canvas(canvas_frame, bg='black',
                                scrollregion=(0, 0, canvas_w, canvas_h),
                                xscrollcommand=self.hscroll.set,
                                yscrollcommand=self.vscroll.set)
        self.canvas.pack(fill=tk.BOTH, expand=True)

        self.hscroll.config(command=self.canvas.xview)
        self.vscroll.config(command=self.canvas.yview)

        # Mouse events
        self.canvas.bind('<Button-1>', self.on_click)
        self.canvas.bind('<B1-Motion>', self.on_drag)
        self.canvas.bind('<ButtonRelease-1>', self.on_release)
        self.canvas.bind('<Button-3>', self.on_right_click)

        # Status bar
        self.status = tk.Label(self.root,
                               text="Ready  |  Ctrl+Z=Undo  Ctrl+S=Save",
                               anchor=tk.W, bg='#111', fg='#AAA', padx=8, pady=3,
                               font=('Consolas', 9))
        self.status.pack(side=tk.BOTTOM, fill=tk.X)

        # Tool indicator
        self.tool_label = tk.Label(self.root, text="PAINT", anchor=tk.E,
                                    bg='#111', fg='#60FF60', padx=8, pady=3,
                                    font=('Consolas', 10, 'bold'))
        self.tool_label.place(relx=1.0, rely=1.0, anchor=tk.SE, x=-10, y=-3)

        # Draw initial map
        self.draw_map()

    def _add_sky_selector(self, parent):
        """Add sky background dropdown selector."""
        tk.Label(parent, text="Sky Background", fg='#4080FF', bg='#222',
                 font=('Arial', 10, 'bold')).pack(pady=(8, 2), anchor=tk.W, padx=4)
        frame = tk.Frame(parent, bg='#222')
        frame.pack(padx=4, fill=tk.X)
        self.sky_var = tk.StringVar(value=self.sky_name)
        sky_names = [name for name, _ in SKY_LIST]
        self.sky_menu = tk.OptionMenu(frame, self.sky_var, *sky_names,
                                       command=self._on_sky_change)
        self.sky_menu.config(bg='#333', fg='white', font=('Arial', 9),
                            highlightthickness=0)
        self.sky_menu.pack(fill=tk.X)
        # Sky preview
        self.sky_preview = tk.Label(frame, bg='#222')
        self.sky_preview.pack(pady=2)
        self._update_sky_preview()

    def _on_sky_change(self, value):
        self.sky_name = value
        self.modified = True
        self._update_sky_preview()
        self._load_sky_tile()
        self.draw_map()
        self.status.config(text=f"Sky: {value}")

    def _update_sky_preview(self):
        if not HAS_PIL:
            return
        for name, filename in SKY_LIST:
            if name == self.sky_name:
                path = os.path.join(PREVIEW_DIR, filename)
                if os.path.exists(path):
                    img = Image.open(path).convert('RGB')
                    img = img.resize((160, 100), Image.LANCZOS)
                    self._sky_preview_img = ImageTk.PhotoImage(img)
                    self.sky_preview.config(image=self._sky_preview_img)
                break

    def _load_sky_tile(self):
        """Load sky image, cut into tile-sized pieces for map background."""
        self._sky_tiles = {}
        if not HAS_PIL:
            return
        for name, filename in SKY_LIST:
            if name == self.sky_name:
                path = os.path.join(PREVIEW_DIR, filename)
                if os.path.exists(path):
                    img = Image.open(path).convert('RGB')
                    ts = TILE_SIZE
                    # Scale to visible area (TILES_X * ts wide, TILES_Y * ts tall)
                    vw = VISIBLE_W * ts
                    vh = VISIBLE_H * ts
                    sky = img.resize((vw, vh), Image.LANCZOS)
                    # Cut into tiles
                    for row in range(VISIBLE_H):
                        for col in range(VISIBLE_W):
                            crop = sky.crop((col*ts, row*ts, (col+1)*ts, (row+1)*ts))
                            self._sky_tiles[(col, row)] = ImageTk.PhotoImage(crop)
                break

    def _add_palette_group(self, parent, title, color, items, cols=3):
        """Add a labeled group of tile buttons in a grid layout."""
        tk.Label(parent, text=title, fg=color, bg='#222',
                 font=('Arial', 10, 'bold')).pack(pady=(8, 2), anchor=tk.W, padx=4)
        grid = tk.Frame(parent, bg='#222')
        grid.pack(padx=2, fill=tk.X)
        for i, (ch, name, clr, pf) in enumerate(items):
            r, c = divmod(i, cols)
            if ch in self.tile_images:
                btn = tk.Button(grid, image=self.tile_images[ch],
                                bg='#333', relief=tk.RAISED,
                                command=lambda c=ch: self.select_tile(c))
            elif ch in self.palette_images:
                btn = tk.Button(grid, image=self.palette_images[ch],
                                bg='#333', relief=tk.RAISED,
                                command=lambda c=ch: self.select_tile(c))
            else:
                btn = tk.Button(grid, text=f"{ch}", bg=clr,
                                fg='white' if self._is_dark(clr) else 'black',
                                width=3, height=1, relief=tk.RAISED,
                                font=('Arial', 9),
                                command=lambda c=ch: self.select_tile(c))
            btn.grid(row=r, column=c, padx=1, pady=1, sticky='nsew')
            # Tooltip on hover
            btn.bind('<Enter>', lambda e, n=name: self.status.config(text=n))

    def _add_palette_button(self, parent, ch, name, color):
        frame = tk.Frame(parent, bg='#222')
        frame.pack(padx=3, pady=1, fill=tk.X)

        if ch in self.palette_images:
            btn = tk.Button(frame, image=self.palette_images[ch], text=f" {name}",
                            compound=tk.LEFT, bg='#333', fg='white',
                            anchor=tk.W, relief=tk.RAISED, width=110,
                            font=('Arial', 9),
                            command=lambda c=ch: self.select_tile(c))
        else:
            btn = tk.Button(frame, text=f"{ch} {name}", bg=color,
                            fg='white' if self._is_dark(color) else 'black',
                            width=14, anchor=tk.W, relief=tk.RAISED,
                            font=('Arial', 9),
                            command=lambda c=ch: self.select_tile(c))
        btn.pack(fill=tk.X)

    def _is_dark(self, hex_color):
        r = int(hex_color[1:3], 16)
        g = int(hex_color[3:5], 16)
        b = int(hex_color[5:7], 16)
        return (r + g + b) / 3 < 128

    def select_tile(self, ch):
        self.current_tile = ch
        name = CHAR_TO_NAME.get(ch, '?')
        color = CHAR_TO_COLOR.get(ch, '#000')
        self.current_label.config(text=f"{ch} {name}", bg=color,
                                  fg='white' if self._is_dark(color) else 'black')
        self._update_current_preview()

    def _update_current_preview(self):
        ch = self.current_tile
        if ch in self.tile_images:
            self.current_preview.config(image=self.tile_images[ch])
        else:
            self.current_preview.config(image='')

    def draw_map(self):
        self.canvas.delete('all')
        ts = TILE_SIZE

        # Draw all tiles
        for row in range(MAP_H):
            for col in range(MAP_W):
                ch = self.map_data[row][col]
                x1, y1 = col * ts, row * ts

                if ch in ('.', '~') and (col, row) in self._sky_tiles:
                    self.canvas.create_image(x1, y1,
                        image=self._sky_tiles[(col, row)], anchor=tk.NW)
                elif ch in ('.', '~') and self._sky_tiles:
                    # Outside visible area but still sky — use nearest tile
                    sc = min(col, VISIBLE_W - 1)
                    sr = min(row, VISIBLE_H - 1)
                    if (sc, sr) in self._sky_tiles:
                        self.canvas.create_image(x1, y1,
                            image=self._sky_tiles[(sc, sr)], anchor=tk.NW)
                elif ch in self.tile_images:
                    self.canvas.create_image(x1, y1, image=self.tile_images[ch],
                                             anchor=tk.NW)
                else:
                    color = CHAR_TO_COLOR.get(ch, '#000')
                    self.canvas.create_rectangle(x1, y1, x1 + ts, y1 + ts,
                        fill=color, outline='')

                # Grid lines
                if self.show_grid:
                    self.canvas.create_rectangle(x1, y1, x1 + ts, y1 + ts,
                        fill='', outline='#333333')

                # Entity label overlay
                if ch in CHAR_TO_NAME and ch not in {c for c,_,_,_ in TILES}:
                    self.canvas.create_text(x1 + ts - 3, y1 + 3,
                        text=ch, fill='#FFD700', anchor=tk.NE,
                        font=('Arial', 8, 'bold'))

        # Switch link lines + floor trigger markers
        link_colors = {'door': '#FF8000', 'wall': '#FF00FF', 'elevator': '#00FFFF'}
        for sc, sr, tc, tr, action in self.switch_links:
            color = link_colors.get(action, '#FFFFFF')
            sx = sc * ts + ts // 2
            sy = sr * ts + ts // 2
            tx = tc * ts + ts // 2
            ty = tr * ts + ts // 2
            self.canvas.create_line(sx, sy, tx, ty, fill=color, width=2,
                                    arrow=tk.LAST, dash=(6, 3))
            self.canvas.create_text(tx, ty - 10, text=action,
                                    fill=color, font=('Arial', 8, 'bold'))
            # Floor trigger marker (empty tile as link source)
            if self.map_data[sr][sc] == '.':
                x1, y1 = sc * ts, sr * ts
                self.canvas.create_rectangle(x1 + 4, y1 + 4, x1 + ts - 4, y1 + ts - 4,
                    outline='#FF8000', width=2, dash=(3, 3))
                self.canvas.create_text(x1 + ts // 2, y1 + ts // 2,
                    text='T', fill='#FF8000', font=('Arial', 9, 'bold'))

        # Highlight link source if in link mode
        if self.tool == 'link' and self.link_src:
            sr, sc = self.link_src
            x1, y1 = sc * ts, sr * ts
            self.canvas.create_rectangle(x1, y1, x1 + ts, y1 + ts,
                outline='#FF00FF', width=3)

        # Visible area overlay
        if self.show_visible:
            vx2 = VISIBLE_W * ts
            vy2 = VISIBLE_H * ts
            self.canvas.create_rectangle(0, 0, vx2, vy2,
                outline='#FFFF00', width=2, dash=(6, 4))
            self.canvas.create_text(vx2 - 5, 5, text="visible area",
                fill='#FFFF00', anchor=tk.NE, font=('Arial', 9))

    def _canvas_to_tile(self, event):
        cx = self.canvas.canvasx(event.x)
        cy = self.canvas.canvasy(event.y)
        col = int(cx // TILE_SIZE)
        row = int(cy // TILE_SIZE)
        if 0 <= col < MAP_W and 0 <= row < MAP_H:
            return row, col
        return None, None

    def _is_entity(self, ch):
        """Check if character is an entity (not a tile)."""
        return ch in {c for c, _, _, _ in ENTITIES}

    def on_click(self, event):
        row, col = self._canvas_to_tile(event)
        if row is None:
            return
        ctrl = event.state & 0x4  # Ctrl key
        ch = self.map_data[row][col]
        # Ctrl+click on entity = drag & drop (any tool)
        if ctrl and self._is_entity(ch):
            self._save_undo()
            self.dragging = True
            self.drag_char = ch
            self.drag_from = (row, col)
            self.map_data[row][col] = '.'
            self.draw_map()
            self.status.config(
                text=f"Dragging {CHAR_TO_NAME.get(ch, '?')} from col={col}, row={row}")
            return
        shift = event.state & 0x1  # Shift key
        # Tool dispatch
        if self.tool == 'move':
            ch = self.map_data[row][col]
            if ch != '.':
                self._save_undo()
                self.dragging = True
                self.drag_char = ch
                self.drag_from = (row, col)
                self.map_data[row][col] = '.'
                self.draw_map()
                self.status.config(
                    text=f"Moving {CHAR_TO_NAME.get(ch, ch)} from col={col}, row={row}")
            return
        if self.tool == 'link':
            self._link_click(row, col)
        elif self.tool == 'fill':
            self.flood_fill(row, col)
        elif self.tool == 'rect':
            self.rect_start = (row, col)
        elif self.tool == 'eraser':
            self._save_undo()
            self._erase_saved = True
            self._cleanup_links(row, col)
            self.map_data[row][col] = '.'
            self.modified = True
            self.draw_map()
        else:  # paint
            if hasattr(self, '_paint_undo_saved'):
                del self._paint_undo_saved
            self.paint_tile(row, col, shift)

    def on_drag(self, event):
        if self.dragging:
            # Update ghost position
            cx = self.canvas.canvasx(event.x)
            cy = self.canvas.canvasy(event.y)
            ts = TILE_SIZE
            if self.drag_ghost:
                self.canvas.delete(self.drag_ghost)
                self.drag_ghost = None
            col = int(cx // ts)
            row = int(cy // ts)
            if 0 <= col < MAP_W and 0 <= row < MAP_H:
                x1, y1 = col * ts, row * ts
                ch = self.drag_char
                if ch in self.tile_images:
                    self.drag_ghost = self.canvas.create_image(
                        x1, y1, image=self.tile_images[ch], anchor=tk.NW)
                else:
                    color = CHAR_TO_COLOR.get(ch, '#FFF')
                    self.drag_ghost = self.canvas.create_rectangle(
                        x1 + 2, y1 + 2, x1 + ts - 2, y1 + ts - 2,
                        fill=color, outline='#FFFF00', width=2)
            return
        row, col = self._canvas_to_tile(event)
        if row is None:
            return
        if self.tool == 'rect' and self.rect_start:
            # Draw rectangle preview
            if self.rect_preview:
                self.canvas.delete(self.rect_preview)
            ts = TILE_SIZE
            r1, c1 = self.rect_start
            r2, c2 = row, col
            x1 = min(c1, c2) * ts
            y1 = min(r1, r2) * ts
            x2 = (max(c1, c2) + 1) * ts
            y2 = (max(r1, r2) + 1) * ts
            self.rect_preview = self.canvas.create_rectangle(
                x1, y1, x2, y2, outline='#FFFF00', width=2, dash=(4, 4))
        elif self.tool == 'eraser':
            if self.map_data[row][col] != '.':
                self._cleanup_links(row, col)
                self.map_data[row][col] = '.'
                self.modified = True
                self.draw_map()
        elif self.tool == 'paint':
            shift = event.state & 0x1
            self.paint_tile(row, col, shift)

    def on_release(self, event):
        # Drag & drop release
        if self.dragging:
            row, col = self._canvas_to_tile(event)
            if self.drag_ghost:
                self.canvas.delete(self.drag_ghost)
                self.drag_ghost = None
            if row is not None:
                self.map_data[row][col] = self.drag_char
                self.modified = True
                # Update switch links if source or target moved
                fr, fc = self.drag_from
                self._move_links(fc, fr, col, row)
                self.status.config(
                    text=f"Moved {CHAR_TO_NAME.get(self.drag_char, '?')} "
                         f"to col={col}, row={row}")
            else:
                r, c = self.drag_from
                self.map_data[r][c] = self.drag_char
                self.status.config(text="Move cancelled")
            self.dragging = False
            self.drag_char = None
            self.drag_from = None
            self.draw_map()
            return
        # Rectangle tool release
        if self.tool == 'rect' and self.rect_start:
            row, col = self._canvas_to_tile(event)
            if self.rect_preview:
                self.canvas.delete(self.rect_preview)
                self.rect_preview = None
            if row is not None:
                self._save_undo()
                r1, c1 = self.rect_start
                r2, c2 = row, col
                for rr in range(min(r1, r2), max(r1, r2) + 1):
                    for cc in range(min(c1, c2), max(c1, c2) + 1):
                        self._cleanup_links(rr, cc)
                        self.map_data[rr][cc] = self.current_tile
                self.modified = True
                w = abs(c2 - c1) + 1
                h = abs(r2 - r1) + 1
                self.status.config(
                    text=f"Rectangle {w}x{h} of {CHAR_TO_NAME.get(self.current_tile, '?')}")
                self.draw_map()
            self.rect_start = None
        # Reset paint undo flag
        if hasattr(self, '_paint_undo_saved'):
            del self._paint_undo_saved

    def on_right_click(self, event):
        """Pick tile under cursor, or unlink switch in link mode."""
        row, col = self._canvas_to_tile(event)
        if row is None:
            return
        if self.tool == 'link':
            self._link_unlink(row, col)
            return
        ch = self.map_data[row][col]
        self.select_tile(ch)

    def paint_tile(self, row, col, shift=False, save_undo=True):
        tile = self.current_tile
        # Shift+click on enemy = left-facing variant
        if shift and tile in RIGHT_TO_LEFT:
            tile = RIGHT_TO_LEFT[tile]
        # Limit: only 1 colored door and 1 key of each color per level
        if tile in UNIQUE_CHARS:
            for r in range(MAP_H):
                for c in range(MAP_W):
                    if self.map_data[r][c] == tile and (r != row or c != col):
                        messagebox.showwarning("Limit",
                            f"Only 1 {UNIQUE_CHARS[tile]} per level!\n"
                            f"Already placed at col={c}, row={r}")
                        return
        # Limit: only 1 player spawn
        if tile == '@':
            for r in range(MAP_H):
                for c in range(MAP_W):
                    if self.map_data[r][c] == '@' and (r != row or c != col):
                        self.map_data[r][c] = '.'  # remove old spawn
        if self.map_data[row][col] != tile:
            if save_undo and not hasattr(self, '_paint_undo_saved'):
                self._save_undo()
                self._paint_undo_saved = True
            self._cleanup_links(row, col)
            self.map_data[row][col] = tile
            self.modified = True
            self.draw_map()
            self.status.config(
                text=f"Painted {CHAR_TO_NAME.get(self.current_tile, '?')} "
                     f"at col={col}, row={row}")

    def new_map(self):
        if self.modified:
            if not messagebox.askyesno("New", "Discard changes?"):
                return
        self.map_data = [['.' for _ in range(MAP_W)] for _ in range(MAP_H)]
        self.switch_links = []
        self.filename = None
        self.modified = False
        self.draw_map()
        self.root.title("DOOM 2D Atari - Map Editor [new]")

    def open_map(self):
        if self.modified:
            if not messagebox.askyesno("Open", "Discard unsaved changes?"):
                return
        path = filedialog.askopenfilename(
            filetypes=[("Map files", "*.map"), ("All files", "*.*")],
            initialdir=os.path.join(os.path.dirname(__file__), '..', 'maps'))
        if path:
            self.load_map(path)

    def load_map(self, path):
        try:
            with open(path, 'r') as f:
                lines = f.readlines()

            map_lines = []
            self.switch_links = []
            for line in lines:
                line = line.rstrip('\n\r')
                if line.startswith(';sky='):
                    self.sky_name = line[5:].strip()
                    if hasattr(self, 'sky_var'):
                        self.sky_var.set(self.sky_name)
                        self._update_sky_preview()
                        self._load_sky_tile()
                    continue
                if line.startswith(';SWITCH '):
                    try:
                        parts = line[8:].split('->')
                        src = parts[0].strip().split(',')
                        tgt_parts = parts[1].strip().split()
                        tgt = tgt_parts[0].split(',')
                        action = tgt_parts[1] if len(tgt_parts) > 1 else 'door'
                        self.switch_links.append((
                            int(src[0]), int(src[1]),
                            int(tgt[0]), int(tgt[1]), action))
                    except (IndexError, ValueError):
                        pass
                    continue
                if line.startswith(';') or len(line.strip()) == 0:
                    continue
                map_lines.append(line)

            for row in range(MAP_H):
                for col in range(MAP_W):
                    if row < len(map_lines) and col < len(map_lines[row]):
                        self.map_data[row][col] = map_lines[row][col]
                    else:
                        self.map_data[row][col] = '.'

            self.filename = path
            self.modified = False
            self.draw_map()
            self.root.title(f"DOOM 2D Atari - Map Editor [{os.path.basename(path)}]")
            self.status.config(text=f"Loaded: {path}")
        except Exception as e:
            messagebox.showerror("Error", f"Failed to load: {e}")

    def save_map(self):
        if not self.filename:
            self.save_map_as()
            return
        self._write_map(self.filename)

    def save_map_as(self):
        path = filedialog.asksaveasfilename(
            defaultextension=".map",
            filetypes=[("Map files", "*.map"), ("All files", "*.*")],
            initialdir=os.path.join(os.path.dirname(__file__), '..', 'maps'))
        if path:
            self.filename = path
            self._write_map(path)

    def _write_map(self, path):
        try:
            with open(path, 'w') as f:
                f.write("; DOOM 2D Atari map\n")
                f.write("; Saved by mapedit.py\n")
                f.write(f";sky={self.sky_name}\n")
                for sc, sr, tc, tr, action in self.switch_links:
                    f.write(f";SWITCH {sc},{sr} -> {tc},{tr} {action}\n")
                for row in range(MAP_H):
                    f.write(''.join(self.map_data[row]) + '\n')
            self.modified = False
            self.root.title(f"DOOM 2D Atari - Map Editor [{os.path.basename(path)}]")
            self.status.config(text=f"Saved: {path}")
        except Exception as e:
            messagebox.showerror("Error", f"Failed to save: {e}")

    def _validate_map(self):
        """Check map for errors and warnings.
        Returns (errors, warnings) — errors block export/test."""
        errors = []
        warnings = []
        enemy_chars = {c for c, _, _, _ in ENTITIES_R + ENTITIES_L}
        pickup_chars = {c for c, _, _, _ in ENTITIES_PICKUPS} - {'X'}
        decor_chars = {c for c, _, _, _ in ENTITIES_DECOR}

        enemies = 0
        pickups = 0
        decors = 0
        players = 0
        door_red = 0
        door_blue = 0
        door_yellow = 0

        for row in range(MAP_H):
            for col in range(MAP_W):
                ch = self.map_data[row][col]
                if ch == '@':
                    players += 1
                elif ch in enemy_chars:
                    enemies += 1
                elif ch in pickup_chars:
                    pickups += 1
                elif ch in decor_chars:
                    decors += 1
                elif ch == '{':
                    door_red += 1
                elif ch == '}':
                    door_blue += 1
                elif ch == '|':
                    door_yellow += 1

        # Errors (block export/test)
        if players == 0:
            errors.append("No player spawn (@) on map!")
        if players > 1:
            errors.append(f"Multiple player spawns: {players} (max 1)")
        if door_red > 1:
            errors.append(f"Multiple red doors: {door_red} (max 1)")
        if door_blue > 1:
            errors.append(f"Multiple blue doors: {door_blue} (max 1)")
        if door_yellow > 1:
            errors.append(f"Multiple yellow doors: {door_yellow} (max 1)")

        # Warnings (allow proceed)
        if enemies > 6:
            warnings.append(f"Too many enemies: {enemies}/6")
        if pickups > 12:
            warnings.append(f"Too many pickups: {pickups}/12")
        if decors > 8:
            warnings.append(f"Too many decorations: {decors}/8")
        return errors, warnings

    def export_bin(self):
        errors, warnings = self._validate_map()
        if errors:
            messagebox.showerror("Cannot export",
                "Fix these errors first:\n\n" + "\n".join(errors))
            return
        if warnings:
            msg = "Warnings:\n\n" + "\n".join(warnings)
            msg += "\n\nProceed with export anyway?"
            if not messagebox.askyesno("Validation", msg):
                return
        if not self.filename:
            self.save_map_as()
            if not self.filename:
                return
        self._write_map(self.filename)
        bin_path = self.filename.replace('.map', '.bin')
        ent_path = self.filename.replace('.map', '.ent')
        import subprocess
        base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
        tools_dir = os.path.join(base_dir, 'tools')
        map2bin = os.path.join(tools_dir, 'map2bin.py')
        python_exe = self.config.get('python', sys.executable)
        r = subprocess.run([python_exe, map2bin, self.filename, bin_path, ent_path],
                           capture_output=True, text=True)
        result = r.stdout + r.stderr
        self.status.config(text=f"Exported: {bin_path}")
        if r.returncode != 0:
            messagebox.showerror("Export", f"Export failed:\n{result}")
        else:
            messagebox.showinfo("Export", f"Exported to:\n{bin_path}\n\n{result}")

    def set_altirra_path(self):
        """Set path to Altirra emulator executable."""
        current = self.config.get('altirra', '')
        path = filedialog.askopenfilename(
            title="Select Altirra executable",
            filetypes=[("Executable", "*.exe"), ("All files", "*.*")],
            initialdir=os.path.dirname(current) if current else None)
        if path:
            self.config['altirra'] = path
            save_config(self.config)
            self.status.config(text=f"Altirra path set: {path}")

    def test_in_altirra(self):
        """Test: Validate, save map, build ATR via build script, launch Altirra"""
        errors, warnings = self._validate_map()
        if errors:
            messagebox.showerror("Cannot test",
                "Fix these errors first:\n\n" + "\n".join(errors))
            return
        if warnings:
            msg = "Warnings:\n\n" + "\n".join(warnings)
            msg += "\n\nProceed with test anyway?"
            if not messagebox.askyesno("Validation", msg):
                return

        # If map not saved yet, prompt Save As
        if not self.filename:
            self.save_map_as()
            if not self.filename:
                return

        altirra = self.config.get('altirra', '')
        if not altirra or not os.path.exists(altirra):
            messagebox.showwarning("Test",
                "Altirra path not set.\nUse File → Set Altirra path...")
            self.set_altirra_path()
            altirra = self.config.get('altirra', '')
            if not altirra or not os.path.exists(altirra):
                return

        import subprocess

        base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
        bin_dir = os.path.join(base_dir, 'bin')

        # 1. Save map
        self._write_map(self.filename)
        self.status.config(text="Test: saving map...")
        self.root.update()

        # 2. Run full build script (converts maps, builds XEX, creates ATR)
        self.status.config(text="Test: building ATR...")
        self.root.update()
        build_script = os.path.join(base_dir, 'build_doom2d.sh')
        # Find Git Bash (Windows: WSL bash != Git Bash)
        git_bash = r'C:\Program Files\Git\usr\bin\bash.exe'
        bash_cmd = git_bash if os.path.exists(git_bash) else 'bash'
        r = subprocess.run([bash_cmd, build_script],
                           capture_output=True, text=True, cwd=base_dir)
        if r.returncode != 0:
            out = (r.stdout or '') + '\n' + (r.stderr or '')
            if len(out) > 2000:
                out = '...\n' + out[-2000:]
            messagebox.showerror("Test",
                f"Build failed (exit code {r.returncode}):\n\n{out}")
            return

        # 3. Launch Altirra with ATR
        atr = os.path.join(bin_dir, 'doom2d.atr')
        if not os.path.exists(atr):
            messagebox.showerror("Test", f"ATR not found: {atr}")
            return
        self.status.config(text="Test: launching Altirra...")
        self.root.update()
        subprocess.Popen([altirra, '/disk', atr])
        self.status.config(text=f"Test: launched Altirra with {os.path.basename(atr)}")

    def toggle_grid(self):
        self.show_grid = not self.show_grid
        self.draw_map()

    def toggle_visible(self):
        self.show_visible = not self.show_visible
        self.draw_map()

    def toggle_fullscreen(self):
        self.fullscreen = not self.fullscreen
        self.root.attributes('-fullscreen', self.fullscreen)

    def _exit_fullscreen(self):
        if self.fullscreen:
            self.fullscreen = False
            self.root.attributes('-fullscreen', False)

    def take_screenshot(self):
        """Save screenshot of visible area (20x12 tiles) as PNG."""
        if not HAS_PIL:
            messagebox.showwarning("Screenshot", "Pillow required for screenshots")
            return
        ts = TILE_SIZE
        w = VISIBLE_W * ts
        h = VISIBLE_H * ts
        img = Image.new('RGB', (w, h), (0, 0, 0))
        self._render_screenshot(img, ts, VISIBLE_W, VISIBLE_H)
        # Save
        base_dir = os.path.join(os.path.dirname(__file__), '..')
        shot_path = filedialog.asksaveasfilename(
            defaultextension=".png",
            filetypes=[("PNG files", "*.png")],
            initialdir=base_dir,
            initialfile="screenshot.png")
        if shot_path:
            img.save(shot_path)
            self.status.config(text=f"Screenshot saved: {shot_path}")

    def _render_screenshot(self, img, ts, max_cols=MAP_W, max_rows=MAP_H):
        """Render map tiles into a PIL image."""
        darkbg_path = os.path.join(PREVIEW_DIR, 'tile_darkbg.png')
        darkbg = None
        if os.path.exists(darkbg_path):
            darkbg = Image.open(darkbg_path).resize((ts, ts), Image.NEAREST).convert('RGBA')

        for row in range(min(max_rows, MAP_H)):
            for col in range(min(max_cols, MAP_W)):
                ch = self.map_data[row][col]
                x1, y1 = col * ts, row * ts
                pf = CHAR_TO_PREVIEW.get(ch)
                if pf:
                    path = os.path.join(PREVIEW_DIR, pf)
                    if os.path.exists(path):
                        src = Image.open(path).convert('RGBA')
                        orig_w, orig_h = src.size
                        if orig_h > orig_w:
                            # Sprite: scale and show bottom portion on darkbg
                            scale = ts / orig_w
                            new_h = int(orig_h * scale)
                            sprite = src.resize((ts, new_h), Image.NEAREST)
                            composite = Image.new('RGBA', (ts, ts), (0, 0, 0, 255))
                            if darkbg:
                                composite = Image.alpha_composite(
                                    Image.new('RGBA', (ts, ts), (0, 0, 0, 255)), darkbg)
                            crop_top = max(0, new_h - ts)
                            sprite_crop = sprite.crop((0, crop_top, ts, new_h))
                            temp = Image.new('RGBA', (ts, ts), (0, 0, 0, 0))
                            temp.paste(sprite_crop, (0, ts - sprite_crop.height))
                            composite = Image.alpha_composite(composite, temp)
                            img.paste(composite.convert('RGB'), (x1, y1))
                        else:
                            # Tile: just resize
                            resized = src.resize((ts, ts), Image.NEAREST)
                            img.paste(resized.convert('RGB'), (x1, y1))
                        continue
                # Fallback: colored rectangle
                color = CHAR_TO_COLOR.get(ch, '#000000')
                r = int(color[1:3], 16)
                g = int(color[3:5], 16)
                b = int(color[5:7], 16)
                for dy in range(ts):
                    for dx in range(ts):
                        img.putpixel((x1+dx, y1+dy), (r, g, b))

    # ============================================
    # UNDO / REDO
    # ============================================
    def _save_undo(self):
        """Save current map state for undo."""
        state = [row[:] for row in self.map_data]
        self.undo_stack.append(state)
        if len(self.undo_stack) > self.max_undo:
            self.undo_stack.pop(0)
        self.redo_stack.clear()

    def undo(self):
        if not self.undo_stack:
            self.status.config(text="Nothing to undo")
            return
        self.redo_stack.append([row[:] for row in self.map_data])
        self.map_data = self.undo_stack.pop()
        self.modified = True
        self.draw_map()
        self.status.config(text=f"Undo ({len(self.undo_stack)} left)")

    def redo(self):
        if not self.redo_stack:
            self.status.config(text="Nothing to redo")
            return
        self.undo_stack.append([row[:] for row in self.map_data])
        self.map_data = self.redo_stack.pop()
        self.modified = True
        self.draw_map()
        self.status.config(text=f"Redo ({len(self.redo_stack)} left)")

    # ============================================
    # SWITCH LINK TOOL
    # ============================================
    # LINK_SOURCES and LINK_ACTIONS are in constants.py

    def _link_click(self, row, col):
        """Link mode click: first click = select switch, second = select target."""
        ch = self.map_data[row][col]
        if self.link_src is None:
            # First click: must be a switch
            if ch not in LINK_SOURCES:
                self.status.config(text="LINK: Click on a switch ($) or pickup first!")
                return
            # Check limit
            existing = [l for l in self.switch_links if l[0] == col and l[1] == row]
            if existing:
                self.status.config(
                    text=f"LINK: Switch at col={col},row={row} already linked. "
                         f"Right-click to unlink first.")
                return
            if len(self.switch_links) >= 4:
                self.status.config(text="LINK: Max 4 switch links! Unlink one first.")
                return
            self.link_src = (row, col)
            self.status.config(
                text=f"LINK: Switch at col={col},row={row} selected. "
                     f"Now click the TARGET tile (door/wall).")
            self.draw_map()
        else:
            # Second click: target tile
            sr, sc = self.link_src
            if row == sr and col == sc:
                self.status.config(text="LINK: Can't link switch to itself!")
                return
            # Ask for action type
            action = self._ask_link_action()
            if action is None:
                self.link_src = None
                self.set_tool('paint')
                self.draw_map()
                self.status.config(text="LINK: Cancelled.")
                return
            self.switch_links.append((sc, sr, col, row, action))
            self.modified = True
            self.link_src = None
            self.set_tool('paint')
            self.draw_map()
            self.status.config(
                text=f"LINK: ({sc},{sr}) -> ({col},{row}) action={action}  "
                     f"[{len(self.switch_links)}/4 links]")

    def _ask_link_action(self):
        """Pop up a dialog to choose switch action type."""
        win = tk.Toplevel(self.root)
        win.title("Switch Action")
        win.geometry("250x150")
        win.resizable(False, False)
        win.transient(self.root)
        win.grab_set()

        result = [None]

        tk.Label(win, text="Choose action:", font=('Arial', 11, 'bold')).pack(pady=8)
        for action in LINK_ACTIONS:
            labels = {'door': 'Open Door', 'wall': 'Remove Wall (secret)',
                      'elevator': 'Call Elevator'}
            tk.Button(win, text=labels.get(action, action), width=25,
                      command=lambda a=action: (result.__setitem__(0, a), win.destroy())
                      ).pack(pady=2)

        win.wait_window()
        return result[0]

    def _move_links(self, old_col, old_row, new_col, new_row):
        """Update switch links when a tile moves from old to new position."""
        updated = False
        new_links = []
        for sc, sr, tc, tr, action in self.switch_links:
            if sc == old_col and sr == old_row:
                sc, sr = new_col, new_row
                updated = True
            if tc == old_col and tr == old_row:
                tc, tr = new_col, new_row
                updated = True
            new_links.append((sc, sr, tc, tr, action))
        if updated:
            self.switch_links = new_links
            self.modified = True

    def _cleanup_links(self, row, col):
        """Remove any switch links involving tile at (col, row) as source or target."""
        before = len(self.switch_links)
        self.switch_links = [l for l in self.switch_links
                             if not (l[0] == col and l[1] == row)
                             and not (l[2] == col and l[3] == row)]
        if len(self.switch_links) < before:
            self.modified = True

    def _link_unlink(self, row, col):
        """Remove link from switch at (col, row)."""
        before = len(self.switch_links)
        self.switch_links = [l for l in self.switch_links
                             if not (l[0] == col and l[1] == row)]
        if len(self.switch_links) < before:
            self.modified = True
            self.set_tool('paint')
            self.draw_map()
            self.status.config(
                text=f"LINK: Unlinked switch at col={col},row={row}  "
                     f"[{len(self.switch_links)}/4 links]")
        else:
            self.status.config(text=f"LINK: No link found at col={col},row={row}")

    # ============================================
    # TOOL SWITCHING
    # ============================================
    def set_tool(self, tool):
        self.tool = tool
        self.link_src = None  # reset link state
        colors = {'paint': '#60FF60', 'rect': '#FF6060',
                  'fill': '#6060FF', 'eraser': '#FFD700', 'move': '#00CCCC',
                  'link': '#FF00FF'}
        self.tool_label.config(text=tool.upper(), fg=colors.get(tool, '#AAA'))
        # Highlight active toolbar button
        if hasattr(self, 'tool_buttons'):
            for t, btn in self.tool_buttons.items():
                if t == tool:
                    btn.config(relief=tk.SUNKEN, bg='#666')
                else:
                    btn.config(relief=tk.RAISED, bg='#444' if t != 'link' else '#402060')
        hint = f"Tool: {tool.upper()}"
        if tool == 'move':
            hint = "MOVE: Click & drag any tile/entity to move it."
        elif tool == 'link':
            hint = "LINK: Click switch, then click target (door/wall). Right-click switch to unlink."
        self.status.config(text=f"Tool: {tool.upper()}  |  {hint}")

    # ============================================
    # FLOOD FILL
    # ============================================
    def flood_fill(self, row, col):
        """Fill connected area of same tile with current tile."""
        target = self.map_data[row][col]
        fill = self.current_tile
        if target == fill:
            return
        self._save_undo()
        stack = [(row, col)]
        visited = set()
        while stack:
            r, c = stack.pop()
            if (r, c) in visited:
                continue
            if r < 0 or r >= MAP_H or c < 0 or c >= MAP_W:
                continue
            if self.map_data[r][c] != target:
                continue
            visited.add((r, c))
            self.map_data[r][c] = fill
            stack.extend([(r-1, c), (r+1, c), (r, c-1), (r, c+1)])
        self.modified = True
        self.draw_map()
        self.status.config(text=f"Filled {len(visited)} tiles with {CHAR_TO_NAME.get(fill, '?')}")

    def quit_app(self):
        if self.modified:
            if not messagebox.askyesno("Quit", "Discard unsaved changes?"):
                return
        self.root.destroy()


