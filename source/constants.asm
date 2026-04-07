;==============================================
; DOOM2D - Constants & equates
; constants.asm
;==============================================

; --- Atari OS ---
RTCLOK3         = $14
SDMCTL          = $22F
COLOR4          = $2C8
CIOV            = $E456
PORTA           = $D300
TRIG0           = $D010
AUDF1           = $D200
AUDC1           = $D201
AUDF2           = $D202
AUDC2           = $D203
AUDC4           = $D207
AUDCTL          = $D208
STIMER          = $D209
IRQEN           = $D20E
SKCTL           = $D20F
VCOUNT          = $D40B

; --- OS vectors/shadow ---
POKMSK          = $0010
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

TILE_SWITCH_OFF = 28
TILE_SWITCH_ON  = 29
TILE_EXIT_SW_OFF = 30
TILE_EXIT_SW_ON  = 31

; --- Switch target system ---
MAX_SWITCHES    = 4
SW_ACT_DOOR     = 0             ; switch opens door (spacebar locked)
SW_ACT_WALL     = 1             ; remove wall (hidden area)
SW_ACT_ELEV     = 2             ; call elevator (future)
SW_ACT_DOOR_LOCK = 3            ; pickup opens door (spacebar locked)
SW_ACT_FLOOR    = 4             ; floor trigger opens door (step on tile)
SW_ACT_EXIT     = 5             ; exit switch — advance to next level

; --- VBXE registers ---
VBXE_VCTL       = $D640
VBXE_XDL0       = $D641
VBXE_XDL1       = $D642
VBXE_XDL2       = $D643
VBXE_CSEL       = $D644
VBXE_PSEL       = $D645
VBXE_CR         = $D646
VBXE_CG         = $D647
VBXE_CB         = $D648
VBXE_BL_ADR0    = $D650
VBXE_BL_ADR1    = $D651
VBXE_BL_ADR2    = $D652
VBXE_BLITTER    = $D653
VBXE_MEMAC_CTRL = $D65E
VBXE_BANK_SEL   = $D65F

; --- VBXE constants ---
VC_XDL_ON       = $01
VC_NO_TRANS     = $04
MC_CPU          = $08
BANK_EN         = $80
BLT_TRANS       = $01

; --- VRAM layout (double buffered) ---
; Screen 0: $000000 (64000 bytes)
; Tiles:    $010000 (bank $10, 4KB)
; Sprites:  $011000 (banks $11-$12, 7KB)
; Screen 1: $020000 (64000 bytes)
; XDL:      $07F000 (bank $7F)
; BCB:      $07F100 (bank $7F)
SCR1_HI         = $02           ; Screen 1 high byte for buffer swap

VRAM_XDL        = $07F000
VRAM_BCB        = $07F100

; Explicit MEMAC-A bank numbers
BANK_TILES      = $10           ; VRAM $010000
BANK_SPR0       = $11           ; VRAM $011000 (first 4KB of sprites)
BANK_SPR1       = $12           ; VRAM $012000 (remaining sprites)
BANK_HUD        = $1D           ; VRAM $01D000 (HUD font, 768 bytes)
BANK_MAP        = $1E           ; VRAM $01E000 (map data, 2048 bytes)
BANK_BG         = $34           ; VRAM $034000 (background sky image, 320x200)

; MEMAC-B ($D65D): 16KB window at $4000-$7FFF for sound data
; Sound VRAM starts at $044000 = MEMAC-B bank 4 (each bank = 16KB)
; Control byte: $C0 = enable+CPU, + bank number
VBXE_MEMAC_B    = $D65D
MEMB            = $4000         ; MEMAC-B window base
MEMB_SND_BANK0  = $C4           ; first sound bank ($C0 enable + bank 4 = VRAM $040000)
BANK_XDL        = $7F           ; VRAM $07F000
BANK_BCB        = $7F           ; VRAM $07F100

; MEMAC-A window (at $9000 to avoid overlap with program data!)
MEMW            = $9000

; --- Screen ---
SCR_W           = 320
SCR_H           = 200

; --- Tiles/map ---
TW              = 16
TH              = 16
MAP_W           = 32
MAP_H           = 32
TILES_X         = 20
TILES_Y         = 12

; --- Game ---
PL_MAXSPD       = 2             ; max horizontal speed (px/frame)
GRAV            = 1
JUMPF           = 8
MAXFALL         = 3
COYOTE          = 3             ; coyote time (frames after leaving edge)
MAX_PROJ        = 4
MAX_ENEMIES     = 6
MAX_PICKUPS     = 12

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
NUM_PK_TYPES    = 21

; --- Decoration ---
MAX_DECOR       = 8
DC_BARREL       = 0
DC_TORCH        = 1
DC_PILLAR       = 2
DC_LAMP         = 3
DC_DEADGUY      = 4
DC_TECHTHING    = 5
NUM_DC_TYPES    = 6

; Barrel
BARREL_HP       = 3             ; hits to explode
BARREL_DMG      = 20            ; explosion damage to enemies (fixed)
BARREL_RADIUS   = 32            ; explosion radius (pixels)
BARREL_PLR_MAX  = 100           ; max barrel damage to player (point blank)
BARREL_PLR_SCALE = 3            ; damage reduction per pixel distance (100-32*3=4 at edge)
BARREL_KB_X     = 6             ; barrel knockback horizontal (stronger than rocket)
BARREL_KB_Y     = 8             ; barrel knockback vertical

; Rocket splash
ROCKET_SPLASH_RADIUS = 32       ; splash radius (pixels)
ROCKET_SPLASH_MAX    = 50       ; max self-damage (point blank)
ROCKET_SPLASH_SCALE  = 2        ; damage reduction per pixel distance
ROCKET_KB_X          = 3        ; horizontal knockback velocity
ROCKET_KB_Y          = 6        ; upward knockback velocity

; --- Player ---
PL_W            = 10            ; player collision width
PL_H            = 28            ; player collision height

; --- Weapons ---
WP_FIST         = 0             ; key 1 (fist/chainsaw share slot)
WP_PISTOL       = 1             ; key 2
WP_SHOTGUN      = 2             ; key 3
WP_CHAINGUN     = 3             ; key 4
WP_ROCKET       = 4             ; key 5
WP_PLASMA       = 5             ; key 6
WP_BFG          = 6             ; key 7
NUM_WEAPONS     = 7
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
