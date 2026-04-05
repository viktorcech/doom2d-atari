## BUILD
```
cd source && ../mads.exe main.asm -o:../bin/doom2d.xex -l:../bin/doom2d.lst -t:../bin/doom2d.lab
```


DOOM 2D pre Atari XE/XL + VBXE - Plan
========================================

DALSI KROKY (priorita)
-----------------------

1. NEPRIATEL AI - UTOKY
   - hitscan vsetkych enemies (okamzity damage, shoot sprite, cooldown 60)
   - Imp fireball (projektil, sprite BAL1A0, cooldown 90)
   - Imp utok pazurmi (zvuk, animacia)
   - Pinky melee rush (zrychleny pohyb k hracovi, hryznutie)
   - Cacodemon + Baron projektily
   - Enemy projektil system (enemy_proj_* polia, MAX_ENEMY_PROJ=4)
   - Kolizia enemy projektil → hrac = damage

2. INTERAKTIVNE PRVKY
   - Dvere: klasicke otvaranie (animacia, DSDOROPN/DSDORCLS zvuky)
   - Dvere na kluc (cerveny/modry/zlty kluc → prislusne dvere)
   - Prepinac/switch: zavola vytah alebo otvori dvere na dialku
   - Vytah (platforma ktora sa pohybuje hore/dole)

3. LEVEL SYSTEM
   - Viac map (level1.map, level2.map...)
   - Exit zona (tile 'X' v mape) - prechod na dalsi level
   - Level loading z mapy (clear + reinit)
   - Progression: tazsie levely

4. SMRT HRACA + GAME OVER
   - HP=0: death animacia (SPR_PL_DEATH), pauza, restart levelu
   - Game over screen
   - Zivoty (3 lives) alebo continue

5. TITLE SCREEN + GAME FLOW
   - Rozdelenie hry na title screen a hlavnu hru (game_state)
   - STATE_TITLE: DOOM logo/TITLEPIC, "PRESS FIRE TO START"
   - STATE_PLAYING: aktualna hra
   - STATE_GAMEOVER: "GAME OVER", restart
   - Title grafika na Screen 0, po FIRE clear + init_render

6. DEATH ANIMACIE - DALSIE ENEMY TYPY
   - Imp: death2, death3 framy (TROO sprites)
   - Shotgun guy: death2, death3 (SPOS sprites)
   - Pinky, Caco, Baron: death framy
   - Vsetko ide do VRAM chunk5+ (ziadna RAM naroky)

7. HORIZONTALNY SCROLL
   - Kamera sleduje hraca, vacsie levely (napr. 40x12 tiles)
   - VBXE overlay address shift pre hardware scroll
   - Dirty tiles kompatibilita so scrollom

8. DALSIE ZVUKY
   [ ] Sight/death zvuky pre pinky, caco, baron
   [ ] Player pain (DSPLPAIN), player death (DSPLDETH)
   [ ] Door open/close (DSDOROPN, DSDORCLS)
   [ ] Plasma, BFG zbrane
   [ ] Hudba (RMT alebo VQ-tracker)
   POZOR: celkom max ~12KB zvukov ($6000-$8FFF, MEMAC limit)

ZNAME OBMEDZENIA A PRAVIDLA
---------------------------
MEMAC:
- MEMAC-A okno na $9000, zvuky NESMU presahovat $8FFF!
- generic_upload MUSI vypnut BANK_SEL po uploade
- Mapa v VRAM bank $1E, pristup cez MEMAC (calc_map_ptr nastavuje BANK_MAP)

RAM:
- Hlavny segment $2000-$42EB, max do $5FFF (7.4KB volnych)
- Zvuky $6000-$8FFF, max ~12KB

SPRITY:
- Stare sprity: VRAM $01xxxx (spr_off_bank=$01), chunky C1-C4
- Nove sprity: VRAM $03xxxx (spr_off_bank=$03), chunk C5+
- VZDY zaloha XEX pred zmenou spritov!

TILES:
- 0-15: tilesheet.bin (VRAM $010000, bank $10)
- 16-24: nove textury (VRAM $032000+, bank $32)
- blit_tile: tile<16 → $01:tile:$00, tile>=16 → $03:(tile+$10):$00
- Floor = one-way platforma (tile_oneway), Wall = solid (tile_solid)

ZVUKY:
- Po pridani/odobrani zvuku v sounds2vram.py VZDY updatovat uc_lastpg v upload_snd4
  (main.asm). Vypocet: celkova velkost chunk4 / 4096 = plne banky, zvysok / 256 zaokruhlit hore.
  Ak sa uc_lastpg neupdatuje, novy zvuk chrci (data sa nenahru do VRAM).
- Ak zvuk chrci po konverzii: vytvorit normalizovanu WAV verziu (normalize + low-pass filter)
  a dat do data/sfx_used/, potom nastavit trimmed_name v sounds2vram.py SOUNDS liste
- Priklad: DSCACSIT chrcal → DSCACSIT_norm.wav (normalize + butter LP 2kHz)

MADS BUGY:
- Nazvy premennych nesmu mat 'en_xh' tvar (parsuje 'h' suffix)
- check_solid_or_platform clobberuje X register

OPTIMALIZACIE (ked bude treba):
- VBI interrupt pre 60Hz timing
- Spatial grid pre viac nepriatelov
- VBXE hardware scroll

VRAM LAYOUT
-----------
$000000  Screen 0 (64KB)
$010000  Tiles 0-15 (4KB, bank $10)
$011000  Sprity stare (48KB, banky $11-$1C)
$01D000  HUD font (bank $1D)
$01E000  Mapa (2KB, bank $1E, pristup cez MEMAC)
$020000  Screen 1 (64KB)
$031000  Death/gib sprity (bank $31)
$032000  Tiles 16-24 (bank $32)
$07F000  XDL + BCB (bank $7F)
VOLNE:   $033000-$07EFFF (~300KB)

RAM: $2000-$42EB kod, $6000-$8F04 zvuky, $9000 MEMAC

ARCHITEKTURA
------------
source/main.asm        - game loop, VBXE init, generic_upload, INI segmenty
source/vbxe.asm        - XDL, blitter (blit_tile s tile>=16 podporou, blit_sprite s spr_off_bank)
source/game.asm        - init, tile kolizie, calc_map_ptr (MEMAC BANK_MAP)
source/weapons.asm     - weapon system, melee, ammo
source/player.asm      - hrac, projektily, rocket wall sound
source/enemies.asm     - AI, death/gib animacie, knockback, 16-bit kolizia
source/pickups.asm     - 15 pickup typov
source/decorations.asm - barrel explosion, torch, pillar, lamp
source/renderer.asm    - rendering (tiles, player, projektily)
source/hud.asm         - HUD (HP, ammo, weapon, keys)
source/dirty.asm       - dirty tile optimalizacia
source/sound.asm       - VIMIRQ IRQ, 12 zvukov
source/data.asm        - sprite_defs, entity spawns, Y-LUT
source/sprite_defs.asm - sprite tabulky + gib/death lookup + tile konstanty

tools/mapedit.py       - GUI editor (farebne skupiny, F5 test, Altirra config)
tools/wav2pokey.py     - WAV → 4-bit POKEY (fade-out, max_ms)
tools/map2bin.py       - mapa → binary + entity tabulky
DoomMapEditor.exe      - skompilovany editor

Pipeline:
  Map:   python tools/map2bin.py maps/test.map data/test_map.bin data/test_map_ent.asm
  Build: cd source && ../mads.exe main.asm -o:../bin/doom2d.xex
  Editor: python tools/mapedit.py (alebo DoomMapEditor.exe)
