"""
DOOM 2D Atari level browser - paths, config, preview sprites.
"""

import sys
import os

# --- Paths ---
# PROJECT_ROOT: where the editable project lives (maps/, data/, build scripts).
#   - dev run:   the repo root (parent of mapedit/)
#   - frozen EXE: the folder the .exe sits in — place doom2d_mapedit.exe in the
#                 project root so it finds bin/doom2d.atr.
# _res_base: read-only bundled resources. In a PyInstaller one-file build these
#   are unpacked to sys._MEIPASS; in dev they live in the project root.
if getattr(sys, 'frozen', False):
    PROJECT_ROOT = os.path.dirname(sys.executable)
    _res_base = sys._MEIPASS
else:
    PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    _res_base = PROJECT_ROOT

# Preview images: prefer bundled copies, fall back to data/preview next to the exe.
PREVIEW_DIR = os.path.join(_res_base, 'data', 'preview')
if not os.path.isdir(PREVIEW_DIR):
    PREVIEW_DIR = os.path.join(PROJECT_ROOT, 'data', 'preview')

# Config sits next to the exe/project root so settings persist across runs.
CONFIG_FILE = os.path.join(PROJECT_ROOT, 'mapedit.cfg')

# --- Level view: game entity types -> preview sprite (data/preview) ---
# enemy type (map2bin etype_map) -> (facing right, facing left)
ENEMY_PREVIEW = [
    ('zombie_idle_L.png', 'zombie_idle.png'),
    ('imp_idle_L.png', 'imp_idle.png'),
    ('pinky_idle_L.png', 'pinky_idle.png'),
    ('caco_idle_L.png', 'caco_idle.png'),
    ('shotgun_idle_L.png', 'shotgun_idle.png'),
    ('baron_idle_L.png', 'baron_idle.png'),
    (None, None),                   # lost soul: no preview
]
# pickup type (source/constants.asm PK_*) -> preview
PICKUP_PREVIEW = {
    0: 'stimpack.png', 1: 'ammo_clip.png', 2: 'medikit.png', 3: 'greenarmor.png',
    4: 'bluearmor.png', 5: 'soulsphere.png', 6: 'keyred.png', 7: 'keyblue.png',
    8: 'keyyellow.png', 9: 'shotgunpk.png', 10: 'shells.png', 11: 'ammo_clip.png',
    12: 'chaingunpk.png', 13: 'rocketpk.png', 14: 'rocketbox.png',
    19: 'health_bonus.png',
}


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
