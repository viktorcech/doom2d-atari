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
- Wall switches that trigger doors and events
- Digital sound effects via POKEY Timer 1 IRQ (~3995 Hz sample playback)
- Title screen and pause menu
- Map editor (Python/Tkinter)

## Requirements

- [MADS](https://github.com/tebe6502/Mad-Assembler) assembler (tested with mads 2.1.7)
- [Altirra](https://virtualdub.org/altirra.html) emulator with VBXE enabled
- Python 3.x (for asset tools and map editor)

## Build

```
python build_doom2d.py
```

Put `mads.exe` in the project root. With no arguments it builds every level in
`maps/` (`d2d_map01`-`d2d_map23`); you can also pass your own `.map` files.

Output: `bin/doom2d.atr`, a bootable disk image (boot loader, the game for VBXE
at `$D600` or `$D700`, the levels and 3 save slots). Mount it as D1: and boot.

## Project Structure

```
build_doom2d.py   Build: maps -> levels, boot loader + game (MADS), ATR
source/           6502 assembly source files (MADS), main.asm includes the modules
  gen/            Generated tables (sprite frames, animations, sound tables)
data/             Binary assets (sprites, sky, title, sounds, palette, HUD font)
maps/             Levels: .map (text) + .tiles (tileset, foreground, triggers)
tools/            Python tools: map2bin (used by the build), d2df2map
                  (Doom 2D Forever map converter), asset preparation
mapedit/          Map editor (Python/Tkinter)
```

## Memory Layout

| Range | Usage |
|-------|-------|
| $2000-$5FB0 | Code + data (~16 KB) |
| $6000-$91F6 | Sound samples (~12.8 KB) |
| $9000-$9FFF | MEMAC-A window (VBXE VRAM access) |
| VBXE VRAM (512 KB) | Screen buffers, sprites, sky, tiles, sounds, HUD font |

## Known Issues / TODO

- Scrolling and parallax background need rework — current implementation has issues with VBXE pitch alignment and vertical fine-scroll (4px steps instead of per-pixel)

## Credits

Inspired by [Doom 2D](https://doom2d.org/) by Prikol Software and the original [Doom](https://en.wikipedia.org/wiki/Doom_(1993_video_game)) by id Software.

Huge thanks to [Altirra](https://virtualdub.org/altirra.html) by Avery Lee — its debugger and hardware reference documentation were invaluable for understanding VBXE, POKEY, and Atari internals.

## License

This project is for educational and hobbyist purposes.
Doom is a trademark of id Software.
