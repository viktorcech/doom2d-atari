;==============================================
; DOOM2D - Constants & equates
; constants.asm
;==============================================

; --- Build flags ---
; AUTOPLAY: 1 = debug build - skip the title menu and hold joystick RIGHT
; (deterministic scroll for emulator regression runs). Ship with 0.
AUTOPLAY        = 0

; --- Atari OS ---
RTCLOK3         = $14
RANDOM          = $D20A          ; POKEY random byte (read)
SDMCTL          = $22F
SDLSTL          = $230           ; OS shadow: display list pointer lo
SDLSTH          = $231           ; OS shadow: display list pointer hi
DLISTL          = $D402          ; ANTIC display list pointer (hardware)
DLISTH          = $D403
HSCROL          = $D404
COLOR2          = $2C6           ; OS shadow: playfield 2 (text background)
COLOR4          = $2C8
CH              = $02FC          ; OS keyboard shadow ($FF = no key)
CIOV            = $E456
PORTA           = $D300
TRIG0           = $D010
PAL             = $D014          ; GTIA: PAL/NTSC detect (bits 1-3)
AUDF1           = $D200
AUDC1           = $D201
AUDF2           = $D202
AUDC2           = $D203
AUDC3           = $D205
AUDC4           = $D207
AUDCTL          = $D208
STIMER          = $D209
IRQEN           = $D20E
IRQST           = $D20E          ; read: IRQ status (0 = pending)
SKCTL           = $D20F
VCOUNT          = $D40B

; --- OS vectors/shadow ---
POKMSK          = $0010
VIMIRQ          = $0216          ; immediate IRQ vector (Timer 1 chain)
VTIMR1          = $0210

; --- Sound ---
SFX_PISTOL      = 0
SFX_ITEMUP      = 1
SFX_ROCKET      = 2
SFX_PODEATH     = 3
SFX_POSIGHT     = 4
SFX_IMPSIGHT    = 5
SFX_IMPDEATH    = 6
SFX_SHOTGUN     = 7
SFX_WPNUP      = 8
SFX_PUNCH      = 9
SFX_BAREXP     = 10
SFX_SLOP       = 11
SFX_BRSSIT     = 12
SFX_BRSDTH     = 13
SFX_SGTSIT     = 14
SFX_SGTDTH     = 15
SFX_CACSIT     = 16
SFX_CACDTH     = 17
SFX_PLASMA     = 18
SFX_BFG        = 19
SFX_BFGXPL     = 20
SFX_PLDEATH    = 21
SFX_DOOROPN    = 22
SFX_DOORCLS    = 23
SFX_OOF        = 24
SFX_POSIGHT2   = 25
SFX_POSIGHT3   = 26
SFX_FIRSHT     = 27
SFX_SWTCHN     = 28
SFX_SWTCHX     = 29
SFX_CLAW       = 30
SFX_SGTATK     = 31
SFX_SKLATK     = 32
SFX_FIRXPL     = 33
SFX_DMPAIN     = 34
SFX_SGCOCK     = 35
SFX_IMPSIT2    = 36
SFX_PODEATH2   = 37
SFX_PODEATH3   = 38
SFX_PSTOP      = 39
SFX_SAWUP      = 40            ; DOOM.WAD DSSAW*: the chainsaw
SFX_SAWIDL     = 41
SFX_SAWFUL     = 42
SFX_SAWHIT     = 43
SFX_PAUK       = 44            ; D2DF DSPAUK (MAP09 TRIGGER_SOUND)
SFX_BULK1      = 45            ; D2DF GameWAD BULK1/2: a splash (VRAM $05D200, snd_x)
SFX_BULK2      = 46
SFX_SECRET     = 47            ; D2DF GameWAD SECRET: a secret found (VRAM $012000, snd_y)
SAW_LOCK       = 16            ; frames the saw sound plays before a retrigger

; --- VBXE registers: page $D6 or $D7 (build_doom2d.py -d:VBXE_PAGE, one
; XEX each; the boot loader picks by $D740) ---
VBXE_REG        = VBXE_PAGE<<8
VBXE_VCTL       = VBXE_REG+$40  ; read: CORE_TYPE ($10 = FX)
VBXE_XDL0       = VBXE_REG+$41  ; read: CORE_REVISION
VBXE_XDL1       = VBXE_REG+$42
VBXE_XDL2       = VBXE_REG+$43
VBXE_CSEL       = VBXE_REG+$44
VBXE_PSEL       = VBXE_REG+$45
VBXE_CR         = VBXE_REG+$46
VBXE_CG         = VBXE_REG+$47
VBXE_CB         = VBXE_REG+$48
VBXE_BL_ADR0    = VBXE_REG+$50
VBXE_BL_ADR1    = VBXE_REG+$51
VBXE_BL_ADR2    = VBXE_REG+$52
VBXE_BLITTER    = VBXE_REG+$53
VBXE_MEMAC_B    = VBXE_REG+$5D
VBXE_MEMAC_CTRL = VBXE_REG+$5E
VBXE_BANK_SEL   = VBXE_REG+$5F

; --- VBXE constants ---
VC_XDL_ON       = $01
VC_NO_TRANS     = $04
MC_CPU          = $08
BANK_EN         = $80
BLT_TRANS       = $01

; --- VRAM layout (double buffered) ---
; Screen 0: $000000 (64000 bytes)
; Sprites:  $011000 (banks $11-$1C)
; Screen 1: $020000 (64000 bytes)
; Map:      $05A000 (BANK_MAP), level tiles: $074000 (VRAM_TILESET)
; XDL:      $07F000 (bank $7F)
; BCB:      $07F100 (bank $7F)
SCR1_HI         = $02           ; Screen 1 high byte for buffer swap

VRAM_XDL        = $07F000
VRAM_BCB        = $07F100

; Explicit MEMAC-A bank numbers
BANK_HUD        = $1D           ; VRAM $01D000 (HUD font, 768 bytes)
VRAM_TILESET    = $074000       ; 256 map tiles x 64 B (TW x TH), $074000-$077FFF
BANK_MAP        = $5A          ; VRAM $05A000-$05D1FF: map, MAP_RPB rows per bank

; MEMAC-B (VBXE_MEMAC_B): 16KB window at $4000-$7FFF for sound data
; Sound VRAM starts at $044000 = MEMAC-B bank 4 (each bank = 16KB)
; Control byte: $C0 = enable+CPU, + bank number
MEMB          = $4000         ; MEMAC-B window base
MEMB_SND_BANK0  = $C4           ; first sound bank ($C0 enable + bank 4 = VRAM $040000)
BANK_XDL        = $7F           ; VRAM $07F000
BANK_BCB        = $7F           ; VRAM $07F100

; MEMAC-A window (at $9000 to avoid overlap with program data!)
MEMW            = $9000

; --- Screen ---
SCR_W           = 320
SCR_H           = 200

; --- Tiles/map ---
; One map cell = 16 px of the original Doom 2D map, drawn at half scale
; (the 320 px screen shows the original's 640 px view): TW x TH screen px.
TW              = 8
TH              = 8
MAP_W           = 100
MAP_H           = 100           ; full map height (matches editor + map2bin)
PL_XMAX         = MAP_W*TW-16   ; rightmost player X (16-bit, sprite 16 wide)
MAP_STRIDE      = 128          ; VRAM bytes per map row: a row never crosses a page
MAP_RPB         = 32            ; map rows per 4K VRAM bank (32*128 = 4096 B)
MAP_BYTES       = MAP_H*MAP_STRIDE ; VRAM/disk image of the map (12800 B = 100 sectors)
        ert MAP_W>MAP_STRIDE
TILES_X         = SCR_W/TW      ; 40 cells across the screen
TILES_Y         = GAME_H/TH     ; 24 cells down the game area

; --- Scroll camera ---
GAME_H          = 192           ; visible game area height (= HUD_Y)
MAX_CAM_X       = MAP_W*TW-SCR_W

SR_MAX          = 28             ; the world sprites' screen rects of a frame (vbxe.asm)
sr_x0           = $B690          ; x/2
sr_x1           = sr_x0+SR_MAX   ; ceil((x+w)/2)
sr_y0           = sr_x1+SR_MAX   ; y
sr_y1           = sr_y0+SR_MAX   ; y+h
FORE_RAM        = $B700          ; foreground rects of the level (fore.asm)
        ert sr_y1+SR_MAX>FORE_RAM

; --- Game ---
; Player physics = Doom 2D Forever (g_player.pas / g_phys.pas, 36 ticks/s,
; gravity +1 every 2nd tick, VEL_JUMP 10, MAX_RUNVEL 8, run accel 1/tick)
; at half scale and 50 frames/s (x 0.72 per frame), 8.8 fixed point:
PL_GRAV         = $21           ; 0.13 px/frame^2  (0.5/2 x 0.72^2)
PL_JUMPV        = $0399         ; 3.6 px/frame     (10/2 x 0.72) -> 50 px jump
PL_LIFTV        = $01CD         ; 1.8 px/frame     (5/2 x 0.72): lift speed
PL_VMAX         = $02E1         ; 2.88 px/frame    (8/2 x 0.72)
PL_ACC          = $42           ; 0.26 px/frame^2  (1/2 x 0.72^2), also braking
PL_MAXFALL      = TH-1          ; whole px/frame: below a cell, no floor skipped
PL_MAXV         = $0ACD         ; 10.8 px/frame    (30/2 x 0.72): D2DF MAX_YV, the
        ert PL_MAXV>=2*TH*256   ; player's/monsters' fall (2 floor probes)
PL_SWV          = $0170         ; 1.44 px/frame    (4/2 x 0.72): D2DF VEL_SW, the
                                ; swim-up speed and the liquid's speed limit
ACID_TICKS      = 21            ; 15 D2DF ticks (x 50/36): acid hit interval
EN_MAXFALL      = 3             ; enemies (not ported yet)
MAX_PROJ        = 4
MAX_ENEMIES     = 66            ; MAP07 and MAP12 (with the fish) have 66
MAX_PICKUPS     = 96

; --- Pickup types ---
PK_HEALTH       = 0
PK_AMMO         = 1
PK_MEDIKIT      = 2
PK_GREENARMOR   = 3
PK_BLUEARMOR    = 4
PK_SOULSPHERE   = 5
PK_KEYRED       = 6
PK_KEYBLUE      = 7
PK_KEYYELLOW    = 8
PK_SHOTGUN      = 9
PK_SHELLS       = 10
PK_PISTOL       = 11
PK_CHAINGUN     = 12
PK_ROCKETL      = 13
PK_ROCKETBOX    = 14
PK_PLASMAGUN    = 15
PK_CELLS        = 16
PK_BFG          = 17
PK_ROCKET1      = 18
PK_HEALTHBONUS  = 19
PK_ARMORBONUS   = 20
PK_SAW          = 21            ; chainsaw (D2DF ITEM_WEAPON_SAW)
PK_OXYGEN       = 22            ; D2DF ITEM_OXYGEN
PK_BACKPACK     = 23            ; D2DF ITEM_AMMO_BACKPACK
AIR_DEF         = 360           ; D2DF air at spawn / on surfacing (ticks)
AIR_MAX         = 1091          ; D2DF air after an oxygen tank

; --- Decoration ---
MAX_DECOR       = 16

; Barrel
BARREL_HP       = 3             ; hits to explode
BARREL_DMG      = 40            ; damage to enemies at point blank; falls off
                                ; linearly (dmg = BARREL_DMG - dist), like
                                ; DOOM's P_RadiusAttack. 9 dmg at the edge.
BARREL_RADIUS   = 32            ; explosion radius (pixels)
BARREL_PLR_MAX  = 100           ; max barrel damage to player (point blank)
BARREL_PLR_SCALE = 3            ; damage reduction per pixel distance (100-32*3=4 at edge)
BARREL_KB_X     = 6             ; barrel knockback horizontal (stronger than rocket)
BARREL_KB_Y     = 8             ; barrel knockback vertical (the barrel jump)

; Barrel explosion timeline (dc_timer counts DOWN from BARREL_EXP_TIME to 0)
BARREL_EXP_TIME  = 31           ; set by barrel_ignite
BARREL_EXP_CHAIN = 30           ; clear solid tile + sound + ignite neighbours
BARREL_EXP_F2    = 21           ; >= : flash sprite, below: fire sprite
BARREL_EXP_DMG   = 20           ; apply radius damage (~0.2s after the flash)
BARREL_EXP_F3    = 11           ; >= : fire sprite, below: smoke + blink
EXPL_IFRAME      = 10           ; frames of explosion-damage immunity for the player
                                ; (stops a barrel chain stacking full splash hits)

; Rocket splash
ROCKET_SPLASH_RADIUS = 32       ; splash radius (pixels)
ROCKET_SPLASH_MAX    = 50       ; max self-damage (point blank)
ROCKET_SPLASH_SCALE  = 2        ; damage reduction per pixel distance
ROCKET_KB_Y          = 6        ; upward knockback velocity

; --- Player ---
PL_W            = 10            ; player collision width
PL_H            = 28            ; player collision height
PL_RL           = 3             ; D2DF PLAYER_RECT (34x52 at half scale, 17x26):
PL_RR           = 13            ; [zpx-PL_RL, zpx+PL_RR] x [zpy-PL_RH, zpy-1]
PL_RH           = 26

; --- Weapons ---
WP_FIST         = 0             ; key 1 (fist/chainsaw share slot)
WP_PISTOL       = 1             ; key 2
WP_SHOTGUN      = 2             ; key 3
WP_CHAINGUN     = 3             ; key 4
WP_ROCKET       = 4             ; key 5
WP_PLASMA       = 5             ; key 6
WP_BFG          = 6             ; key 7
WP_SAW          = 7             ; key 1 too (D2DF: knuckles and saw share it)
AMMO_NONE       = $FF           ; melee weapons

; --- HUD ---
HUD_FONT_ADDR   = $D000         ; Font offset within bank $1D (low 12 bits)
HUD_CHAR_W      = 8
HUD_CHAR_H      = 8
HUD_Y           = 192           ; Y position (bottom 8px of screen)
HUD_HP_IX       = 8             ; X for heart icon
HUD_HP_DX       = 24            ; X for HP first digit
HUD_AM_IX       = 80            ; X for bullet icon
HUD_AM_DX       = 96            ; X for ammo first digit
HUD_CHR_HEART   = 10
HUD_CHR_BULLET  = 11
HUD_WP_DX       = 160           ; X for weapon number display
HUD_KEY_DX      = 220           ; X for key icons (3x16px, max 220+48=268 < 320)

; --- Game states ---
STATE_TITLE     = 0
STATE_PLAYING   = 1

; --- Joystick (inverted) ---
J_UP            = $01
J_DOWN          = $02
J_LEFT          = $04
J_RIGHT         = $08

; --- Sprite indices (all defined in sprite_defs.asm) ---
