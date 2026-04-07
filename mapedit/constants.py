"""
DOOM 2D Atari Map Editor - Constants & tile/entity definitions.
"""

import sys
import os

# --- Map dimensions ---
MAP_W = 32
MAP_H = 32
TILE_SIZE = 32      # pixels per tile in editor
VISIBLE_W = 20      # visible tiles horizontal (game screen)
VISIBLE_H = 12      # visible tiles vertical (game screen)

# --- Paths ---
if getattr(sys, 'frozen', False):
    _base = sys._MEIPASS
else:
    _base = os.path.join(os.path.dirname(__file__), '..')
PREVIEW_DIR = os.path.join(_base, 'data', 'preview')
CONFIG_FILE = os.path.join(os.path.dirname(__file__), '..', 'mapedit.cfg')

# --- Tile definitions ---
TILES_WALLS = [
    ('#', 'wall',       '#808080', 'tile_wall.png'),
    ('-', 'ceiling',    '#505050', 'tile_ceiling.png'),
    ('T', 'techwall',   '#A08050', 'tile_techwall.png'),
    ('S', 'support',    '#909090', 'tile_support.png'),
    ('G', 'stone',      '#606060', 'tile_stonewall.png'),
    ('J', 'dem1_1',     '#805040', 'tile_dem1_1.png'),
    ('P', 'flat22',     '#605040', 'tile_flat22.png'),
    ('V', 'floor1_1',   '#706050', 'tile_floor1_1.png'),
    ('q', 'mflr8_1',    '#504840', 'tile_mflr8_1.png'),
]

TILES_FLOORS = [
    ('f', 'techfloor',  '#607050', 'tile_techfloor.png'),
    ('o', 'metalflr',   '#505050', 'tile_metalfloor.png'),
    ('Y', 'floor5_1',   '#605848', 'tile_floor5_1.png'),
]

TILES_BG = [
    ('.', 'empty',      '#000000', 'tile_empty.png'),
    ('~', 'sky',        '#4060C0', 'tile_sky.png'),
]

TILES_DOORS = [
    ('D', 'door',       '#8B4513', 'tile_door.png'),
    ('{', 'door red',   '#FF2020', 'tile_door_red.png'),
    ('}', 'door blue',  '#2040FF', 'tile_door_blue.png'),
    ('|', 'door yellow','#FFD700', 'tile_door_yellow.png'),
]

TILES_SWITCHES = [
    ('$', 'switch',     '#40C040', 'tile_switch_off.png'),
    ('E', 'exit switch','#FF4040', 'tile_exit_sw_off.png'),
]

TILES = TILES_WALLS + TILES_FLOORS + TILES_BG + TILES_DOORS + TILES_SWITCHES

# --- Entity definitions ---
ENTITY_PLAYER = [
    ('@', 'player',    '#00FF00', 'player_idle.png'),
]

ENTITIES_R = [
    ('Z', 'zombie >',  '#804000', 'zombie_idle_L.png'),
    ('I', 'imp >',     '#C04000', 'imp_idle_L.png'),
    ('K', 'pinky >',   '#FF4080', 'pinky_idle_L.png'),
    ('C', 'caco >',    '#FF0000', 'caco_idle_L.png'),
    ('W', 'shotguy >', '#C08000', 'shotgun_idle_L.png'),
    ('B', 'baron >',   '#800040', 'baron_idle_L.png'),
]

ENTITIES_L = [
    ('z', 'zombie <',  '#804000', 'zombie_idle.png'),
    ('i', 'imp <',     '#C04000', 'imp_idle.png'),
    ('k', 'pinky <',   '#FF4080', 'pinky_idle.png'),
    ('c', 'caco <',    '#FF0000', 'caco_idle.png'),
    ('w', 'shotguy <', '#C08000', 'shotgun_idle.png'),
    ('n', 'baron <',   '#800040', 'baron_idle.png'),
]

ENTITIES_PICKUPS = [
    ('H', 'health',      '#00C0FF', 'stimpack.png'),
    ('A', 'ammo',        '#FFFF00', 'ammo_clip.png'),
    ('M', 'medikit',     '#FF0080', 'medikit.png'),
    ('1', 'green armor', '#00C000', 'greenarmor.png'),
    ('2', 'blue armor',  '#0040FF', 'bluearmor.png'),
    ('3', 'soulsphere',  '#4080FF', 'soulsphere.png'),
    ('4', 'key red',     '#FF0000', 'keyred.png'),
    ('5', 'key blue',    '#0000FF', 'keyblue.png'),
    ('6', 'key yellow',  '#FFFF00', 'keyyellow.png'),
    ('7', 'shotgun',     '#C08040', 'shotgunpk.png'),
    ('8', 'shells',      '#C0A000', 'shells.png'),
    ('9', 'pistol',      '#C0C0C0', 'ammo_clip.png'),
    ('Q', 'chaingun',    '#808000', 'chaingunpk.png'),
    ('R', 'rocket l.',   '#806040', 'rocketpk.png'),
    ('r', 'rocket box',  '#605030', 'rocketbox.png'),
    ('u', 'plasma gun',  '#00FF80', 'plasmagun.png'),
    ('e', 'cells',       '#00C0C0', 'cells.png'),
    ('j', 'BFG 9000',    '#40FF40', 'bfgpk.png'),
    ('v', 'rocket',      '#AA6030', 'rocket1.png'),
    ('h', 'health +1',   '#4040FF', 'health_bonus.png'),
    ('a', 'armor +1',    '#40FF40', 'armorbonus.png'),
    ('X', 'exit',        '#FF00FF', None),
]

ENTITIES_DECOR = [
    ('!', 'barrel',    '#408040', 'barrel.png'),
    ('t', 'torch',     '#FF8000', 'torch.png'),
    ('l', 'pillar',    '#A0A0A0', 'pillar.png'),
    ('L', 'lamp',      '#FFE080', 'lamp.png'),
    ('d', 'deadguy',   '#800000', 'player_death3.png'),
]

ENTITIES = ENTITY_PLAYER + ENTITIES_R + ENTITIES_L + ENTITIES_PICKUPS + ENTITIES_DECOR
ALL_ITEMS = TILES + ENTITIES

# --- Lookup tables ---
CHAR_TO_COLOR = {ch: col for ch, name, col, _ in ALL_ITEMS}
CHAR_TO_NAME = {ch: name for ch, name, col, _ in ALL_ITEMS}
CHAR_TO_PREVIEW = {ch: pf for ch, name, col, pf in ALL_ITEMS}

# --- Enemy facing map ---
RIGHT_TO_LEFT = {'Z': 'z', 'I': 'i', 'K': 'k', 'C': 'c', 'W': 'w', 'B': 'n'}

# --- Sky backgrounds ---
SKY_LIST = [
    ('D2DSKY1', 'D2DSKY1.png'),
    ('D2DSKY2', 'D2DSKY2.png'),
    ('D2DSKY3', 'D2DSKY3.png'),
    ('D2DSKY4', 'D2DSKY4.png'),
    ('DFSKY0',  'DFSKY0.png'),
    ('DFSKY1',  'DFSKY1.png'),
    ('DFSKY2',  'DFSKY2.png'),
    ('DFSKY3',  'DFSKY3.png'),
    ('DFSKY4',  'DFSKY4.png'),
]

# --- Unique items (only 1 per map) ---
UNIQUE_CHARS = {
    '4': 'red key', '5': 'blue key', '6': 'yellow key',
    '{': 'red door', '}': 'blue door', '|': 'yellow door',
}

# --- Link sources (tiles that can trigger actions) ---
LINK_SOURCES = (
    {'$', '.'} |
    {ch for ch, _, _, _ in ENTITIES_PICKUPS}
)

LINK_ACTIONS = ['door', 'wall', 'elevator']


def load_config():
    """Load config from mapedit.cfg."""
    cfg = {}
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'r') as f:
            for line in f:
                line = line.strip()
                if '=' in line and not line.startswith('#'):
                    k, v = line.split('=', 1)
                    cfg[k.strip()] = v.strip()
    return cfg


def save_config(cfg):
    """Save config to mapedit.cfg."""
    with open(CONFIG_FILE, 'w') as f:
        f.write("# DOOM 2D Map Editor config\n")
        for k, v in cfg.items():
            f.write(f"{k}={v}\n")
