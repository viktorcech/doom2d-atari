# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

DOOM 2D for Atari XE/XL with VBXE graphics accelerator. A 2D side-scrolling action game written in 6502 assembly (MADS assembler). Features scrolling camera, double-buffered rendering, hardware blitter sprites, digital sound via POKEY, and 6 enemy types with AI.

## Build

```bash
bash build_doom2d.sh
```

Output: `bin/doom2d.xex` (~272 KB). Also produces `bin/doom2d.lst` (listing) and `bin/doom2d.lab` (symbol table).

Run in Altirra emulator with VBXE enabled.

## MADS Assembler Pitfall

**Never use underscore before `h` or `v` in label names.** MADS silently parses `en_xh` as `en_x` with hex suffix `h`, causing the `.ds` allocation to be skipped without error. Use concatenated names: `enxhi` not `en_xhi`, `envely` not `en_vely`. Always verify new labels appear in `bin/doom2d.lab` after build.

## 6502 ASM Editing Rules

When modifying assembly code that changes register usage:
- **Trace A/X/Y at every reachable branch target.** Shared labels like `?kill`, `?done`, `?skip` may be reached from multiple code paths with different register expectations.
- Save/restore index registers (X/Y) around subroutine calls if they hold entity indices.
- After `jsr` calls, assume A/X/Y are clobbered unless the subroutine documents otherwise.

## Architecture

### Source Files (`source/`)

Entry point is `main.asm`, which includes all other modules via `icl`:

| File | Role |
|------|------|
| `constants.asm` | VBXE/POKEY/OS registers, game constants, sprite enums |
| `zeropage.asm` | Zero-page variables ($80-$D5): player state, camera, sound, controls |
| `vbxe.asm` | XDL setup, blitter operations (BCB), screen clear, MEMAC |
| `game.asm` | Level init, tile collision (`get_tile_at`), map address calc via MEMAC-A |
| `player.asm` | Input, movement, jump physics, camera follow, death |
| `weapons.asm` | 7 weapons (fist/pistol/shotgun/chaingun/rocket/plasma/BFG), hitscan + projectiles |
| `enemies.asm` | 6 types (zombie/imp/pinky/caco/shotguy/baron), AI with LOS/chase/attack |
| `renderer.asm` | Tile and sprite rendering, double-buffer swap |
| `dirty.asm` | Dirty tile tracking — only re-render changed tiles (~10-20 vs 240/frame) |
| `hud.asm` | HP, ammo, weapon number, keys, armor display |
| `pickups.asm` | 21 item types (health, armor, weapons, ammo, keys) |
| `decorations.asm` | Barrels (explosive, chain reaction), torches, lamps, pillars |
| `door.asm` | 8 door slots, colored key doors, auto-close timer |
| `sound.asm` | 4-bit sample playback via POKEY Timer 1 IRQ (~3995 Hz), VIMIRQ direct hook |
| `uploads.asm` | VRAM chunk upload procedures |
| `init.asm` | Initialization routines |
| `luts.asm` | Lookup tables |
| `data.asm` | Sprite tables, map binary, entity spawns, Y-address LUT |
| `menu.asm` | Title screen, pause menu |

### Memory Layout

- **RAM $2000-$5FB0**: Code + data (~16 KB)
- **RAM $6000-$91F6**: Sound samples (~12.8 KB)
- **$9000-$9FFF**: MEMAC-A window (VBXE VRAM access)
- **VBXE VRAM (512 KB)**: Screen buffers (2x 67 KB), sprites (48 KB), sky parallax (128 KB), tiles, sounds, HUD font, XDL, BCB

### Rendering Pipeline

Double-buffered: render to back buffer, swap on VSYNC. Dirty tile system tracks sprite bounding boxes and only re-blits affected tiles. Screen pitch is 336 bytes (not 320) for VBXE alignment.

### Sound System

Samples stored in VRAM, read via MEMAC-B. VIMIRQ direct hook bypasses OS dispatch (17% vs 32% CPU). Timer 1 active only during playback. Sound crackling usually means `uc_lastpg` in upload stub is wrong — check `sounds2vram.py` output for correct page count.

## Tools (`tools/`)

- `map2bin.py` — Convert `.map` text to binary tile grid + entity spawn ASM
- `sounds2vram.py` — Convert WAVs to 4-bit VRAM chunks + generate `sound_tables.asm`
- `prepare_sprites.py` — Generate `sprite_defs.asm` with VRAM offsets
- `wav2pokey.py` — WAV to 4-bit packed nibbles
- `sky2bin.py` — Sky image to parallax background chunks

## Map Format

Text files in `maps/` (64x32 chars). Tiles: `.` empty, `#` wall, `=` floor, `-` ceiling, `D` door, `~` sky, `b` dark bg, `T`/`m`/`S`/`G` wall variants, `f`/`o`/`p`/`g` one-way platforms. Entities: `@` player spawn, `Z`/`I`/`K`/`C`/`W`/`B` enemies, `H`/`A`/`M` pickups, `X` exit. Edit with `mapedit/` (Python/Tkinter GUI).

Convert map to binary: `python tools/map2bin.py maps/level.map`

## Key Constants

- Visible area: 20x12 tiles (320x192 px), map size: 64x32 tiles
- Max entities: 6 enemies, 12 pickups, 4 projectiles
- Player physics: MAXSPD=2, GRAV=1, JUMPF=8, MAXFALL=3, COYOTE=3
- Tile size: 16x16 px

## Documentation

- `stav.md` — Current project status and feature list (Slovak)
- `sounds.md` — Sound system technical details and SFX list
- `mapa.md` — Map system and tile type reference
- `zadanie2.md` — Roadmap and planned features
