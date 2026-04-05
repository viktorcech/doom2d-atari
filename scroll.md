# Scrolling - stav a plan

## Implementovane (2-3.4.2026)

### Krok 1: Kamera
- `cam_tx` (ZP $D6) - tile column lavej hrany kamery (0..44)
- `cam_x_lo/cam_x_hi` (ZP $D7/$D8) - camera X v pixeloch (tile-aligned, pre sprite offset)
- `cam_sub` (ZP $D9) - sub-tile pixel offset (0-15, pre XDL smooth scroll)
- `scroll_redraw` (ZP $DA) - >0 = full redraw pending (countdown pre oba buffery)
- `cam_tx_prev` (ZP $DB) - predchadzajuci cam_tx (detekcia zmeny)
- `camera_update` v player.asm: cam_x = clamp(player_x - 160, 0, 704)
  - cam_tx = cam_x >> 4, cam_sub = cam_x & 15
  - cam_x_lo/hi = cam_tx * 16 (tile-aligned, sprity odcitavaju tuto hodnotu)
  - XDL offset = cam_sub (sub-pixel shift, hardware)
  - Volane v game loope po player_update aj po player_dead

### Krok 2: Tile rendering s camera offsetom
- `render_tiles` a `restore_dirty` pouzivaju `cam_tx + r_col` pre map lookup
- `render_tiles` renderuje 21 stlpcov (0-20) pre padding pri XDL shifte
- Prazdne tiles na stlpci 20 volaju blit_bg (sky wrapping col 20 → 0)
- `scroll_redraw` flag (=2 pre oba buffery) spusti full redraw pri zmene cam_tx
- Full redraw: clear dirty flags + clear_screen + render_tiles + force dirty bbox full
- Poradie v game loope: scroll_redraw ALEBO restore_dirty, potom sprite render

### Krok 3: Sprite camera offset
- Vsetky game sprity odcitavaju cam_x_lo/cam_x_hi od world pozicie
- `lda world_x / sec / sbc cam_x_lo / sta zdx` (cam_x_lo = cam_tx*16, bez cam_sub)
- XDL shift robi sub-pixel posun automaticky
- Upravene: renderer.asm (player, projs), enemies.asm (enemies, eproj),
  pickups.asm (pickups_nodirty), decorations.asm (decor_nodirty, exploding,
  render_decorations), dirty.asm (render_static)
- HUD a menu NIE su offsetnute (screen-relative, vlastny XDL blok)
- render_pickups_nodirty/render_decor_nodirty: dirty bbox check konvertuje
  world tile col na screen-relative (sbc cam_tx) pred porovnanim

### Krok 4: Split XDL (border + game + HUD)
- XDL ma 3 bloky (23 bytov):
  - Block 1: border (20 riadkov, overlay off) - $24,$00, RPTL=19
  - Block 2: game area (192 riadkov) - $62,$08, RPTL=191,
    OVADR lo=cam_sub, mid=$00, hi=buffer, OVSTEP=336, OVATT=$11/$FF
  - Block 3: HUD (8 riadkov) - $62,$88, RPTL=7,
    OVADR $00/$FC/buffer, OVSTEP=336, OVATT=$11/$FF
- HUD nescrolluje (OVADR bez cam_sub)
- XDL runtime offsets: XDL_GAME_LO=6, XDL_GAME_HI=8, XDL_HUD_HI=18
- Buffer swap zapisuje cam_sub + zbuf_hi do oboch blokov

### Krok 5: 336-byte buffer pitch
- SCR_PITCH = 336 (21 tiles * 16px, padding pre XDL offset)
- RENDER_COLS = 21 (render_tiles), TILES_X = 20 (dirty tracking)
- y_addr LUT: Y*336, na $A000 (samostatny segment na konci main.asm)
- y_addr_xhi: overflow byte pre Y>=196 (336*196 > 65535)
- calc_dst: 17-bit y_addr support (lda y_addr_xhi,y namiesto lda #0)
- BCB dst_step prefill: 336 (setup_xdl)
- clear_screen: src_step=320 (sky), dst_step=336 (buffer), width=320
- Tiles presunuté z $010000 (bank $10) na $052000 (bank $52)
  - Screen 0 buffer (336*200=67200B) siaha do $010680, kolidoval s tiles
  - blit_tile: source $05:($20+tile):$00 namiesto $01:tile:$00
  - BANK_TILES = $52
- blit_bg: sky source wrapping pre col 20 (col >= TILES_X → sbc TILES_X)

### Title screen: 336 pitch reformat
- Title data uploadnute pri 320B pitch (INI segmenty, raw binary)
- `reformat_title_336` INI segment (org $6000, po upload_title6):
  - Blit buffer 1 (src 320 pitch) → buffer 0 (dst 336 pitch)
  - Blit buffer 0 (src 336 pitch) → buffer 1 (dst 336 pitch)
  - Inline blitter access (nie JSR run_blit, lebo BCB este nie je inicializovany)
- Vysledok: oba buffery maju title data pri 336 pitch
- Nie je potrebny pitch switching (title aj game pouzivaju 336)

### Infrastruktura
- y_addr_lo/hi/xhi LUT na $A000 (600B, pod BASIC ROM, disabled po uploadoch)
- uc_bank/uc_cnt/uc_lastpg presunute do ZP $BB-$BD (uvolnilo 3B pred $6000)
- cam_sub/cam_tx/cam_x inicializovane na 0 v init_game a pred title
- Pred $6000 je ~185B rezervy pre dalsi kod
- menu.asm: backup/restore_menu_area pouziva SCR_PITCH (336) pre step
- hud.asm: clear_hud_area pouziva SCR_PITCH (336) pre step
- Enemy off-screen skip zmeneny: |enxhi - cam_x_hi| >= 2 (vzdialenost od kamery)

### VRAM layout (aktualizovany 3.4.2026)
```
$000000-$010680: Screen 0 (336*200 = 67200B)
$011000-$01CFFF: Sprites c1-c4
$01D000-$01D9FF: HUD font
$01E000-$01E8FF: Map data
$01F000-$01FFFF: Sprites c6
$020000-$030680: Screen 1 (336*200 = 67200B)
$031000-$033FFF: Death sprites (c5)
$034000-$053FFF: Sky background (512*256 = 131072B, rozsirene pre parallax+vscroll)
$054000-$054FFF: Pain sprites (c7, presunuty z $051000)
$055000-$055FFF: Tilesheet (4KB, presunuty z $052000)
$060000-$0601FF: Switch tiles
$061000-$06D48D: Sound data (presunuty z $044000)
$07F000-$07F0FF: XDL (23B)
$07F100-$07F1FF: BCB (21B)
```

### Vertikalny scroll (implementovany 3.4.2026)
- cam_ty (ZP $DE): tile row kamery (0..4 s 8-bit zpy)
- cam_y (ZP $DF): camera Y v pixeloch (tile-aligned = cam_ty*16, 0-64)
- cam_ty_prev (ZP $E0): predchadzajuci cam_ty
- camera_update Y: cam_y = clamp(zpy - 96, 0, 64), len ked hrac stoji na zemi
- render_tiles/restore_dirty: map lookup pouziva cam_ty + r_row
- Vsetky sprite renderery odcitavaju cam_y od world Y
- blit_bg: bg_row tabulky 16 entries (cam_ty max 4 + r_row max 11 = 15)
- clear_screen: sky Y offset = cam_ty * $2000 (pridane do src mid byte)
- scroll_redraw trigger pri zmene cam_ty (rovnako ako cam_tx)

### Parallax sky (implementovany 3.4.2026)
- Sky obraz 512x256 v VRAM ($034000-$053FFF), pitch 512
- Proporcionalny parallax: sky_offset = 192 * cam_x / 704 (rozsah 0-192)
- sky_lut[cam_tx]: 45-entry LUT + cam_sub interpolacia (calc_sky_offset)
- clear_screen: src = $034000 + sky_x_lo + cam_ty*$2000, src_step=512
- blit_bg: src_step=512, sky_x_lo offset v source X
- XDL: 3 bloky (border + game + HUD) - parallax split docasne vypnuty
- Ziadny wrap, ziadny sev, jeden blit

## Zname problemy / TODO

### Parallax sky pozadie

#### Neuspesne pokusy (3.4.2026)
- **Wrap pristup** (sky 320px, sky_x = cam_tx*8, 2-blit wrap): viditelny sev pri wrape,
  sky obraz nie je seamless, stutter pri cam_tx hraniciach (-7px skok)
- **XDL split** (sky blok cam_sub/2 + tile blok cam_sub): horizontalna diskontinuita
  na hranici blokov, tiles v sky bloku scrolluju zlou rychlostou
- **Per-frame rendering** (calc_sky_x kazdy frame): plynuly parallax ale FPS 25-30
  (clear_screen + render_tiles kazdy frame prilis pomale)
- **Zaver**: wrap pristup nefunguje dobre. XDL split nefunguje kvoli zdielandmu bufferu.

#### Novy plan: Doom 2D PC pristup (proporcionalny parallax)
Inspirovane PC verziou Doom 2D (d2-source/game/g_game.pas):
- Sky obraz je **sirsie ako obrazovka** (napr. 480x200 namiesto 320x200)
- **Ziadny wrap/opakovanie** - sky offset sa linearne mapuje na poziciu kamery
- Vzorec: `sky_offset = (SKY_W - 320) * cam_x / (MAP_W*16 - 320)`
- Pre SKY_W=480: `sky_offset = 160 * cam_x / 704` (rozsah 0-160)
- clear_screen blituje 320px okno z 480px sirokeho sky s offsetom sky_offset
- **Jeden blit, ziadny wrap, ziadny sev, ziadny stutter**

#### Implementacny plan
1. **Sky data**: rozsirit z 320x200 na 480x200 (96000B)
   - `sky2bin.py` zmena na 480px sirku
   - Sky PNG pripravit v GIMPe (rozsirit okraje, napr. scale alebo content-aware)
   - Sky upload: 8 chunkov namiesto 6

2. **VRAM reorganizacia** (sky zaberie viac miesta):
   ```
   $034000-$04F75F: Sky 480x200 (96000B) [rozsirene z 64000B]
   $051000-$051FFF: Pain sprites (bez zmeny)
   $052000-$052FFF: Tilesheet (bez zmeny)
   $060000-$0601FF: Switch tiles (bez zmeny)
   $061000-$06D48D: Sound data [PRESUNUTY z $044000]
   ```
   - Sound MEMAC-B bank: zmena z $C4 na $D8
   - `sounds2vram.py` zmena VRAM base z $044000 na $061000
   - Regenerovat `data/sound_tables.asm`

3. **Sky offset vypocet** (45B LUT + interpolacia, ~85B celkom):
   ```
   sky_lut: :45 dta [160 * # * 16 / 704]   ; pre-computed per cam_tx
   calc_sky_offset:
     sky_x = sky_lut[cam_tx] + (sky_lut[cam_tx+1] - sky_lut[cam_tx]) * cam_sub / 16
   ```
   - Vysledok v sky_x_lo (0-160), sky_x_hi = 0 (vzdy < 256)
   - Volane z camera_update

4. **clear_screen zmena**:
   - src = $034000 + sky_x_lo (sky offset)
   - src_step = SKY_W (480 namiesto 320)
   - dst_step = SCR_PITCH (336, bez zmeny)
   - width = 320 (bez zmeny), height = 192
   - **Vzdy jeden blit** (ziadny wrap!)

5. **blit_bg zmena**:
   - src_step = SKY_W (480)
   - src X = sky_x_lo + r_col * 16 (s carry do mid byte)
   - bg_row_mid/hi tabulky prepocitat pre pitch 480 (row*7680)
   - Col 20 wrap: col 20 → col 0 + sky_x_lo (rovnake ako predtym)

6. **Konstanty** (constants.asm):
   - `SKY_W = 480`
   - `MEMB_SND_BANK0 = $D8` (presunuty sound)

### FPS drop pri tile redraw
- Kazdy 16px scrollu (zmena cam_tx): clear_screen + render_tiles (~120+ blitov)
- Riesenie: column-shift (1 velky blit + 1-2 male namiesto 120)
- Vyzaduje dirty restore PRED shiftom (cistenie spritov)

### Dirty system pri scrolli
- Dirty flags su screen-relative (20x12 = 240 tiles)
- Pri zmene cam_tx sa dirty pozicie stanu neplatnymi
- Aktualny workaround: full redraw pri kazdom cam_tx zmene
- Stlpec 20 (padding) nie je dirty-tracked
- Sprite remnants v stlpci 20 sa nevymazavaju

### Garbage pruh vpravo
- Stlpec 20 nie je pokryty clear_screen (len 320px)
- render_tiles vyplna col 20 cez blit_bg (sky wrapping)
- Moze sa stat ze sprite remnants v col 20 ostanu (nie dirty-tracked)

### 16-bit Y (IMPLEMENTOVANE 3.4.2026)
- zpy_hi ($9D) pre hracov, en_yhi, proj_yhi, eproj_yhi, pk_yhi, dc_yhi
- gt_py_hi v get_tile_at pre 16-bit tile collision
- cam_ty 0-20, cam_y_hi:cam_y (max 320) - kamera sleduje celú 32-row mapu
- Vsetky sprite renderery pouzivaju calc_scr_y helper ($A000)
- Kamera updatuje Y pri pade (zpvy>=0) aj na zemi, nie pri skoku
- clear_screen: partial sky + fill black pre cam_ty > 4
- blit_bg: fill black pre cam_ty + r_row >= 16
- BASIC ROM vypnuty v early_init ($0600) pre pristup k $A000 datam
- Spawn data (enemy/pickup/decor _yhi) generovane map2bin.py

### Dalsie TODO
- Door vizualne efekty s camera offset
- Hitscan vizualizacia s camera offset
- Pause menu: backup/restore area uz pouziva SCR_PITCH
- Pickup collision (update_pickups) pracuje s world coords - OK
- Enemy patrol bounds (en_xmin/en_xmax) su 8-bit, moze byt problem pre enxhi>0
- Parallax XDL split: docasne vypnuty, vrati sa po vertical scroll stabilizacii
