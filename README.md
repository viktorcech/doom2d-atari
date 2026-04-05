# Doom 2D VBXE for Atari XE/XL

A 2D side-scrolling action game inspired by Doom, written entirely in 6502 assembly for the Atari XE/XL computer with VBXE graphics accelerator.

## Features

- Double-buffered VBXE rendering at 320x192 (8-bit color)
- Hardware blitter (BCB) for fast sprite compositing
- Scrolling camera with dirty-tile optimization (~10-20 redrawn tiles per frame instead of 240)
- Sky parallax background
- 7 weapons: fist, pistol, shotgun, chaingun, rocket launcher, plasma rifle, BFG
- 6 enemy types with AI: zombie, imp, pinky, cacodemon, shotgun guy, baron
- Hitscan and projectile weapon systems
- 21 pickup types (health, armor, weapons, ammo, keys)
- Explosive barrels with chain reactions
- Doors with colored key locks and auto-close
- Digital sound effects via POKEY Timer 1 IRQ (~3995 Hz sample playback)
- Title screen and pause menu
- Map editor (Python/Tkinter)

## Requirements

- [MADS](https://github.com/tebe6502/Mad-Assembler) assembler (tested with mads 2.1.7)
- [Altirra](https://virtualdub.org/altirra.html) emulator with VBXE enabled
- Python 3.x (for asset tools and map editor)

## Build

```bash
bash build_doom2d.sh
```

Output: `bin/doom2d.xex` (~272 KB)

## Project Structure

```
source/         6502 assembly source files (MADS)
  main.asm        Entry point, includes all modules
  constants.asm   VBXE/POKEY/OS registers, game constants
  zeropage.asm    Zero-page variables ($80-$D5)
  vbxe.asm        XDL setup, blitter, screen clear, MEMAC
  game.asm        Level init, tile collision, map access via MEMAC-A
  player.asm      Input, movement, jump physics, camera follow
  weapons.asm     7 weapon types, hitscan + projectile systems
  enemies.asm     6 enemy types, AI with LOS/chase/attack
  renderer.asm    Tile and sprite rendering, double-buffer swap
  dirty.asm       Dirty tile tracking for optimized rendering
  hud.asm         HP, ammo, weapon, keys, armor display
  pickups.asm     21 item types
  door.asm        8 door slots, key doors, auto-close timer
  sound.asm       4-bit sample playback via POKEY IRQ
  menu.asm        Title screen and pause menu
data/           Binary assets (sprites, tiles, sounds, sky, palette)
converted/      Converted sprite assets
maps/           Level maps (text format, 64x32 tiles)
tools/          Python asset pipeline scripts
mapedit/        Map editor (Python/Tkinter)
```

## Memory Layout

| Range | Usage |
|-------|-------|
| $2000-$5FB0 | Code + data (~16 KB) |
| $6000-$91F6 | Sound samples (~12.8 KB) |
| $9000-$9FFF | MEMAC-A window (VBXE VRAM access) |
| VBXE VRAM (512 KB) | Screen buffers, sprites, sky, tiles, sounds, HUD font |

## License

This project is for educational and hobbyist purposes.
Doom is a trademark of id Software.
