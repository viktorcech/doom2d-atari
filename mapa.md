# DOOM 2D Atari - Mapovy system

## Analyza referencie (PC Doom 2D)

PC verzia Doom 2D pouziva tile-based mapy s:
- Koridory na roznych vyskach spojene schodmi
- Platformy na ktore sa skace
- Pozadie je textura/skybox (NIE cierne!)
- Kamenno-sede a tehlovo-hnede steny
- Tekutiny (nukage, voda) - poskodzuju hraca
- Dekoracie (lampy, stlpy)
- HUD panel napravo (pripravime, nemusime este robit)

Pre nasu Atari verziu: jednoduchy obdlznikovy dizajn, bez diagonal tiles.

## Sucasny stav

- Mapa hardcoded v `data.asm` ako MADS direktivy (dta, .rept)
- 64x32 tiles = 2048 bytov
- 15 typov tiles (0-14): empty, wall, floor, ceiling, door, sky, darkbg, techwall, metalwall, support, stonewall, 4x floor variants
- Tilesheet: 16 tiles * 256 bytov = 4096 bytov
- Tiles generovane v `tools/prepare_sprites.py` z DOOM WAD textur
- Hrac vyska 28px = potrebuje min 2 tiles (32px) volneho priestoru

## Tile typy

### Aktualne (0-5):

| ID | Znak | Nazov     | Solid | Popis                    |
|----|------|-----------|-------|--------------------------|
| 0  | `.`  | empty     | nie   | prazdny priestor         |
| 1  | `#`  | wall      | ano   | tehlova stena            |
| 2  | `=`  | floor     | ano   | betonova podlaha/platforma|
| 3  | `-`  | ceiling   | ano   | strop                    |
| 4  | `D`  | door      | ano   | dvere (neskor interaktivne)|
| 5  | `~`  | sky       | nie   | obloha (pozadie)         |

### Implementovane (6-14):

| ID | Znak | Nazov      | Solid | Popis                    |
|----|------|------------|-------|--------------------------|
| 6  | `b`  | darkbg     | nie   | tmave pozadie (interior) |
| 7  | `T`  | techwall   | ano   | STARTAN2 textura         |
| 8  | `m`  | metalwall  | ano   | METAL1 textura           |
| 9  | `S`  | support    | ano   | SUPPORT2 textura         |
| 10 | `G`  | stonewall  | ano   | STONE2 textura           |
| 11 | `f`  | techfloor  | one-way | half-height platforma  |
| 12 | `o`  | metalfloor | one-way | half-height platforma  |
| 13 | `p`  | stepfloor  | one-way | half-height platforma  |
| 14 | `g`  | darkfloor  | one-way | half-height platforma  |
| 15 |      | reserved   |       | volny slot               |

## Mapovy format (.map text)

Textovy subor, editovatelny v lubovolnom editore:
```
; Komentar (ignorovany)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#..............................................................#
#....====......................................................#
================================================================
```

- Kazdy riadok = 64 znakov = 1 riadok mapy
- 32 riadkov celkom
- Znaky podla tabulky vyssie
- Riadky zacinajuce `;` su komentare, prazdne sa ignoruju

## Nastroje

### `tools/map2bin.py` - Text -> Binary konvertor
```
python tools/map2bin.py maps/test.map data/test_map.bin
```
Vystup: 2048 bytov, cisty grid tile indexov.

### `tools/bin2map.py` - Binary -> Text (spetny prevod)
```
python tools/bin2map.py data/test_map.bin maps/test.map
```

## Pouzitie v hre (ASM)

V `data.asm` namiesto hardcoded dat:
```asm
map_data
    ins '../data/test_map.bin'    ; 2048 bytov
```

## Zdroje DOOM tile textur

DOOM.WAD obsahuje:
- **Flats** (64x64): FLOOR*, CEIL*, FLAT*, NUKAGE* -> downscale na 16x16
- **Wall patches**: WALL*, BRICK*, STONE* -> crop/downscale na 16x16
- Extrahovanie cez `wad_extract.py`, konverzia v `prepare_sprites.py`
- Tilesheet ma 16 slotov, pouzitych 15 = 1 volny

## Testovacia mapa - dizajn

Potrebuje:
- Spawn area - otvoreny priestor na zaciatok
- Platformy v roznych vyskach (test skoku, JUMPF=7 = cca 21px max vyska)
- Chodba s min. 2 tiles vysky (hrac=28px)
- Schody/stupienky po 1 tile
- Miesto na nepriatelov

## Celkovy plan - ako levely v DOOM 2D Atari funguju

### Struktura levelu
- Kazdy level = 1 mapa (64x32 tiles) + spawn pozicie nepriatelov + spawn pozicia hraca
- Level ma definovane: ciel (exit zona alebo vsetci nepriatelia zabiti)
- Levely su cislovane (Level 1, 2, 3...)
- Medzi levelmi: kratka obrazovka s vysledkami (kills, time)

### Priebeh hry
1. Hra nacita level data (mapa + nepriatelia)
2. Hrac sa objavuje na spawn pozicii
3. Hrac prechadza mapou, zabija nepriatelov, zbiera itemy
4. Po splneni ciela (exit/kill all) -> dalsi level
5. Game over pri smrti -> restart levelu

### Level data format

#### Textova mapa (.map)
Entity znaky v mape - konvertor ich nahradi darkbg tile (6):
- `@` = hrac spawn (prave 1 na mapu!)
- Enemies facing RIGHT (uppercase): `Z`=zombie, `I`=imp, `K`=pinky, `C`=caco, `W`=shotgun, `B`=baron
- Enemies facing LEFT (lowercase): `z`=zombie, `i`=imp, `k`=pinky, `c`=caco, `w`=shotgun, `n`=baron
- Pickups: `H`=health, `A`=ammo, `M`=medikit
- `X` = exit zona

#### Binarne level data (.bin)
`map2bin.py` generuje JEDEN subor so vsetkym:

```
Offset    Velkost   Obsah
------    -------   -----
$0000     2048B     Mapa (64x32 tile indexov)
$0800     1B        Player spawn X (pixel, 0-255)
$0801     1B        Player spawn Y (pixel, 0-255)
$0802     1B        Pocet nepriatelov (0-8)
$0803+    6B/enemy  Enemy data:
                      [0] spawn X (pixel)
                      [1] spawn Y (pixel)
                      [2] typ (0=zombie,1=imp,2=pinky,3=caco)
                      [3] HP
                      [4] patrol min X
                      [5] patrol max X
```

Max 8 nepriatelov = 48B. Celkovy level subor: max 2048+3+48 = 2099B.

#### Patrol range - automaticky vypocet
Konvertor skenuje vlavo/vpravo od spawnu nepriatela a hlada steny.
Patrol min = prva stena vlavo (alebo okraj mapy) * 16.
Patrol max = prva stena vpravo * 16.
Capped na 0-255 (limit 1 bajtu, kym nemame scrolling).

#### HP podla typu
Konvertor nastavi default HP podla enemy typu:
- zombie = 3 HP
- imp = 3 HP
- pinky = 4 HP
- caco = 5 HP

### Ako hra nacita level

V ASM: `init_level` procedura nahradi `init_game` + `init_enemies`:

```asm
.proc init_level
    ; level_data ukazuje na aktualny level binary (ins alebo loaded)

    ; 1. Player spawn
    lda level_data+$800     ; spawn X
    sta zpx
    lda level_data+$801     ; spawn Y
    sta zpy

    ; 2. Enemies
    lda level_data+$802     ; pocet
    sta num_active_enemies
    tax
    ; Loop: nacitaj enemy data z level_data+$803
    ; pre kazdeho: nastav en_x, en_y, en_type, en_hp, en_xmin, en_xmax
    ...
    rts
.endp
```

### Build pipeline
```
maps/level01.map  -->  map2bin.py  -->  data/level01.bin (mapa + spawns, 1 subor)
```

V `data.asm`:
```asm
level_data
    ins '../data/level01.bin'    ; cely level v jednom subore
map_data = level_data            ; mapa je na zaciatku
```

### Pamat a loading
- 1 level = max ~2100 bytov (zmesti sa do RAM)
- Na zaciatku: vsetky levely v XEX (included cez ins)
- Neskor: loading z disku/TNFS pre viac levelov
- Pozor: bez scrollingu su pixel pozicie limitovane na 0-255 (1 bajt)
- Po pridani scrollingu: prejst na tile suradnice alebo 16-bit pozicie

### Planovane levely
1. **Test level** - otvoreny, vsetky mechaniky na testovanie
2. **E1M1 inspired** - jednoduchy intro level, malo nepriatelov
3. **Corridor level** - chodby, dvere, viac nepriatelov
4. **Platform level** - vertikalny dizajn, skakanie
5. **Boss level** - velka arena

### Velkost mapy a scrolling

**Obrazovka Atari VBXE:** 320x200 px = 20x12.5 tiles viditelnych naraz.

**Mozne velkosti mapy:**

| Velkost    | Tiles   | Pixely     | Bytov | Popis                         |
|------------|---------|------------|-------|-------------------------------|
| 20x12      | 240     | 320x192    | 240B  | 1 obrazovka, bez scrollingu   |
| 40x12      | 480     | 640x192    | 480B  | 2 obrazovky sirka, horiz.scroll|
| 64x12      | 768     | 1024x192   | 768B  | velka sirka, horiz.scroll     |
| 64x32      | 2048    | 1024x512   | 2048B | plna mapa, plny scroll        |

**Rozhodnutie - fazovy pristup:**

- **Faza 1 (teraz):** Binarny format ostava 64x32 (2048B). Ale pouzivame
  len oblast 20x12 (co je na obrazovke). Zvysok vyplneny stenami.
  Hrac sa hyble v ramci jednej obrazovky. Jednoduche, funguje okamzite.

- **Faza 2 (horizontalny scroll):** Pouzijeme plnych 64 stlpcov.
  Kamera sleduje hraca horizontalne. Vertikalne ostava fixne (12 riadkov
  hratelnej vysky). Mapa je vlastne dlha chodba/level.
  VBXE overlay: zmena VRAM base adresy pre scroll offset.

- **Faza 3 (plny scroll):** Pouzijeme celych 64x32. Kamera sleduje
  hraca v oboch osiach. Komplex, ale da sa.

**Pre fazu 1** - single screen level dizajn:
- Riadky 0-2: obloha (sky) = 3 tiles
- Riadky 3-10: hratelny priestor = 8 tiles = 128px vyska
- Riadok 11: podlaha
- Format suboru je 64x32 ale aktivna oblast je stlpce 0-19, riadky 0-11

**Format suboru sa NEMENI** medzi fazami. Vzdy 2048 bytov (64x32).
Jednoducho sa len zvacsuje aktivna oblast s pridanim scrollingu.

### Obmedzenia Atari
- Max 3 aktivni nepriatelia naraz (RAM/CPU limit)
- 16 tile typov max (tilesheet = 4KB VRAM)
- Pixel pozicie v 1 bajte = max 255 (bez scrollingu staci)
- Po pridani scrollingu: 16-bit pozicie pre hraca + nepriatelov

## Plán: Scrolling + aktivačné zóny (31.3.2026)

### Problém
Keď bude mapa plná 64x32 s viacerými entitami, CPU musí updatovať
všetko každý frame - aj čo hráč nevidí. To spomalí hru.

### Entity limity pre plnú mapu

| Entity       | Teraz | Plná mapa |
|--------------|-------|-----------|
| MAX_ENEMIES  | 6     | 16-20     |
| MAX_PICKUPS  | 12    | 30+       |
| MAX_DECOR    | 8     | 16+       |
| MAX_PROJ     | 4     | 4 (ostáva)|

### Aktivačné zóny (CPU optimalizácia)

Enemy ďaleko od kamery nepotrebuje plný AI každý frame:

| Zóna              | Vzdialenosť     | AI update     | Rendering |
|-------------------|------------------|---------------|-----------|
| Obrazovka         | na screene       | každý frame   | ÁNO       |
| Blízka (+1 screen)| +320px okolo     | každý frame   | NIE       |
| Ďaleká (2+ screen)| +640px           | každý 4. frame| NIE       |
| Mimo              | veľmi ďaleko     | SKIP (spí)    | NIE       |

- Blízki enemies (obrazovka + 1 screen): plný AI každý frame
- Vzdialení: round-robin update (len každý 4. frame)
- Rendering: len viditeľní (cam_x/cam_y check pred blit_sprite)
- Pickupy/dekorácie: lacné, môžu ostať všetky aktívne

### Odhad CPU záťaže

PAL frame budget = ~29 000 cyklov

| Čo                  | Teraz       | Plná mapa (so zónami) |
|----------------------|-------------|----------------------|
| Enemy AI             | 6× ~3000c  | 6-8 aktívnych ~4000c |
| Pickup check         | 12× ~600c  | 30× ~1500c           |
| Projectile           | 4× ~200c   | 4× ~200c             |
| Dekorácie            | 8× ~400c   | 16× ~800c            |
| Scrolling overhead   | 0           | ~1000-2000c           |
| SPOLU                | ~4200c      | ~7500-8500c           |
| Voľné (z 29000c)    | ~24800c     | ~20500-21500c         |

### Scrolling implementácia

1. **cam_x, cam_y** premenné (16-bit) sledujú hráča
2. Tile rendering s offsetom: kresliť len viditeľných 20x12 tiles
3. Pri pohybe kamery: prekresliť len nové stĺpce/riadky (delta scroll)
4. Dirty tile system treba prepracovať pre scrolling

### Poznámky

- CPU optimalizácie (SMC, unrolling, page-align) riešiť AŽ keď
  reálne nestíhame framerate
- VBXE blitter robí rendering, CPU len nastavuje BCB (~50c/sprite)
- LOS scan je najdrahšia AI operácia (~500c worst case per enemy)
  - Aktivačná zóna to rieši (scanujú len blízki)
- Formát .map sa NEMENÍ (64x32), len sa zväčšuje aktívna oblasť

## Postup implementácie

1. Vytvorit `tools/map2bin.py` - konvertor text->binary
2. Vytvorit `maps/test.map` - testovacia mapa v textovom formate
3. Spustit konverziu -> `data/test_map.bin`
4. Upravit `data.asm` - pouzit `ins` namiesto hardcoded dat
5. Build a test v Altirre
6. Iterovat - upravovat .map, konvertovat, testovat
7. (Neskor) Extrahovanie DOOM textur pre lepsie tiles
8. (Neskor) Load map z disku/TNFS za behu
9. (Neskor) HUD panel - pripravit layout, implementovat az po mapach
