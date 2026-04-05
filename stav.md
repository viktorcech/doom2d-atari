DOOM 2D - Stav projektu (2.4.2026)
=====================================

AKTUALNY STAV: HRATELNY PROTOTYP
- Hrac sa hybi, skace, striela, zomiera (death animacia + R restart)
- 7 zbrani (vsetky z DOOM 1), 6 typov nepriatelov so zvukmi
- Zombie striela na hraca (hitscan, 3 dmg)
- Armor system (75% absorpcia), HUD zobrazenie
- FPS counter (F key)

ENEMY AI (Doom-style)
----------------------
- LOS detekcia, proximity, sound/damage alert, chase, patrol
- LOS scan optimalizovany: kazdy 2. frame per enemy (staggered)
- Floor check skip 3/4 framov ked enemy stoji na zemi
- Zombie hitscan utok: 3 dmg, random interval 60-155 framov, shoot sprite
- Y distance check (nestriela hore/dole)

DEATH SYSTEM
-------------
- Enemy: 3-frame death animacia + blink, gib system (barrel/rocket kill)
- Player: 3-frame death (PLAYH0→PLAYI0→PLAYK0), DSPLDETH zvuk, blink, R restart
- Game logic freeze pri smrti hraca (enemies/decorations pokracuju)

WEAPON SYSTEM (DOOM 1 - KOMPLETNY)
------------------------------------
  | # | Zbran    | DMG | CD | Ammo     | Typ       |
  |---|----------|-----|----|----------|-----------|
  | 0 | Fist     | 2   | 12 | -        | melee     |
  | 1 | Pistol   | 1   | 15 | bullets  | hitscan   |
  | 2 | Shotgun  | 5   | 30 | shells   | hitscan+pierce |
  | 3 | Chaingun | 1   | 4  | bullets  | hitscan+autofire |
  | 4 | Rocket L.| 10  | 35 | rockets  | projektil+splash |
  | 5 | Plasma   | 2   | 3  | cells    | projektil+autofire |
  | 6 | BFG      | 20  | 60 | cells    | projektil+blast(64px) |

- Hitscan: okamzity zasah, tile scan, barrel damage
- Shotgun: moze trafit 2 enemies v rovnakom stlpci
- Ammo max: bullets 200, shells 50, rockets 50, cells 200

BARREL SYSTEM (barrel.asm)
---------------------------
- Solid dekoracia + tile 15 (invisible solid)
- Explozia: 3 zasahy, DMG radius 32px, chain reaction
- Delayed damage: vizual timer=30, damage timer=20 (~0.2s delay)
- Gib system: overkill-based sanca (threshold = overkill*3+10)
- 16-bit distance check (fix pre cross-page barrels)
- Chain explozia: zero-negation fix (256→0 bug)

DOOR SYSTEM (door.asm)
-----------------------
- SPACE = USE key, auto-close po 150 framoch
- Farebne klucove dvere: red ({), blue (}), yellow (|)
- Zvuky: DSBDOPN (open), DSBDCLS (close), DSSKLDTH (locked/wall)
- Metallic textura z DOOM WAD (DOOR2_1) + 3 farebne varianty
- Restart zatvara dvere (restart_close_doors)

ZVUKOVY SYSTEM
---------------
- 22 zvukov: zbrane, enemies (sight+death), barrel, slop, player death, doors
- Zvuky vo VRAM ($044000+), 3 upload chunky
- Sound queue: death sounds sa zafronta ak weapon sound hra
- Weapon sound hra PRED hitscan (oba zvuky pocutelne)
- snd_irq optimalizovany: VRAM read presunute z hi do lo path (-45 cyklov)
- Lo path bez Y push/pop, inc/dec phase toggle

PICKUP SYSTEM
--------------
- 21 typov: health, medikit, soulsphere, armors, keys, vsetky zbrane+ammo
- Health bonus (+1, max 200), Armor bonus (+1, max 200)
- Single rocket, cells, vsetky weapon pickupy s DOOM ammo hodnotami
- Pickup collision skip pri smrti hraca
- Armor: green=100, blue=200 (set behavior, DOOM style)

ARMOR SYSTEM
-------------
- Absorbuje 75% damage (HP dostane 25%)
- player_take_damage procedura pre vsetky zdroje damage
- HUD zobrazenie (3 cifry za HP, len ked > 0)

SPRITESHEET STAV
-----------------
- 138 spritov (0-137)
- C1-C4: zakladne sprity (banky $11-$1C, 48KB)
- C5: death/gib/explosion sprity (banky $31-$33)
- C6: plasma/BFG/bonus/death sprity (bank $1F)

MAP EDITOR
-----------
- Vsetky pickupy: H,A,M,1-9,Q,R,r,P,E,G,v,h,a
- Vsetky enemies: Z/z,I/i,K/k,C/c,W/w,B/n
- Dekoracie: !,t,l,L,d,e
- Sky selector, Undo/Redo, Rectangle, Flood fill, Eraser

PERFORMANCE OPTIMALIZACIE
--------------------------
- Hitscan: ziadne projektily pre pistol/shotgun/chaingun (~3-5K cyklov/frame)
- snd_irq: VRAM read v lo path, bez Y push (~90K cyklov/s)
- Enemy LOS: kazdy 2. frame (staggered, 2px kompenzacia)
- Enemy floor check: skip 3/4 framov ked na zemi
- Pickup skip pri smrti hraca
- HUD conditional redraw + double-buffer aware
- BCB template pre-filled, dirty bounding box

CODE STRUCTURE
--------------
  main.asm → constants, zeropage, vbxe, game, weapons, player,
             pickups, decorations, barrel, enemies, renderer,
             hud, dirty, sound, data

VRAM LAYOUT (512KB)
-------------------
  $000000  Screen 0 (64KB)
  $010000  Tiles 0-15 (4KB)
  $011000  Sprity C1-C4 (48KB)
  $01D000  HUD font
  $01E000  Mapa (2KB)
  $01F000  Sprity C6 (plasma/BFG/bonus/death)
  $020000  Screen 1 (64KB)
  $031000  Sprity C5 (death/gib)
  $034000  Sky background (64KB)
  $044000  Zvuky (34KB, 3 chunky)
  $07F000  XDL + BCB

TODO
----
- Enemy utoky: imp fireball, pinky melee, caco/baron projektily
- Exit/level system
- Chainsaw (slot 1 s fist)
- Scrolling (mapa > 1 obrazovka)
