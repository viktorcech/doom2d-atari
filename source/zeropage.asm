;==============================================
; DOOM2D - Zero page variables
; zeropage.asm
;==============================================

zt              = $80       ; temp
zt2             = $81
zsrc            = $82       ; 2b source pointer
zva             = $86       ; 3b VRAM address (24-bit)

zfr             = $90       ; frame counter
zpx             = $91       ; player X pixel
zpy             = $92       ; player Y pixel
zpvx            = $93       ; player vel X (signed)
zpvy            = $94       ; player vel Y (signed)
zpdir           = $95       ; 0=right 1=left
zpst            = $96       ; player state
zpan            = $97       ; anim timer
zphp            = $98       ; health
zpammo          = $99       ; ammo
zpgnd           = $9A       ; on ground
zpx_hi          = $9C       ; player X high byte (for positions > 255)
zpy_hi          = $9D       ; player Y high byte (16-bit Y for tall maps / vertical scroll)

zparmor         = $A0       ; armor points (0-200)
zpkeys          = $A1       ; key flags: bit0=red, bit1=blue, bit2=yellow
zpweap          = $A2       ; bitfield: owned weapons (bit0=fist..bit7=chainsaw)
zpshells        = $A3       ; shells ammo (shotgun)
zprockets       = $A4       ; rockets ammo (rocket launcher)
zpcells         = $A5       ; cells ammo (plasma, BFG)
zpwcur          = $A6       ; current weapon (0-7)
tu_i            = $A7       ; trigger index (triggers.asm: per trigger, every tick)

zjoy            = $A8       ; joystick state
ztrig           = $A9       ; trigger state
                            ; $AA free (zjoyp: nothing read it, 2026-11-11)
ztrigp          = $AB       ; previous trigger

; Current enemy temp vars
zzidx           = $B5       ; current enemy index

; Hot loop counters (proj-enemy collision)
zcp_proj        = $AC       ; projectile index in collision loop
zcp_tmp         = $AE       ; collision temp

zpwcool         = $C3       ; weapon cooldown timer
snd_lock        = $CB       ; the saw's sound: frames to its retrigger (player.asm)


; --- Scroll camera (world->screen offset) ---
cam_x           = $B0       ; camera X lo (0..MAX_CAM_X)
cam_x_hi        = $B1       ; camera X hi
cam_y           = $B2       ; camera Y lo (0..MAX_CAM_Y)
cam_y_hi        = $B3       ; camera Y hi
cam_tcol        = $B4       ; camera left-edge tile column (cam_x>>4)
cam_trow        = $B6       ; camera top-edge tile row (cam_y>>4)


zdx             = $D0       ; draw X lo
zdxh            = $D1       ; draw X hi
zdy             = $D2       ; draw Y (world Y lo)
zdy_hi          = $D3       ; draw Y world hi byte (16-bit world Y for blit_sprite cam offset)
ztptr           = $D4       ; 2b tile map pointer
                            ; $D6-$D9 free (ecam: nothing read it, 2026-11-11)
spl_ptr         = $DA       ; 2b: next free BCB of the sprite list (MEMAC window)
tl_ptr          = $DC       ; 2b: next free BCB of the tile list (MEMAC window)

; Loop bounds read on every pass (2026-10-30 6502-cycles-layout.md "Zero page
; is the register file: hot variables should"); $E0-$E1: the boot loader only
num_en          = $E2       ; enemy count (set by load_level)
num_pk          = $E3       ; pickup count (savegame: num_en+1)
num_dc          = $E4       ; decoration count (savegame: num_en+2)
pk_end          = $E5       ; slots 0..pk_end-1 may be active (loop bound)
; blit_frame's per-call state (the same skill rule, 2026-10-30)
bf_top          = $E6       ; rows cut off at the top
bf_mir          = $E8       ; $FF: the frame mirrored, else 0
sr_n            = $E9       ; world sprites in sr_* ($FF: more than SR_MAX)
ai_now          = $EA       ; bit 7 = this frame is an AI tick
pl_liq          = $EB       ; liquid at the waist: 0, 1 water, 2 acid1, 3 acid2 (every
                            ; frame, 2026-11-02 6502-cycles-layout.md "hot variables should")

; --- Hot per-frame temps (ZP = 1 cycle less per access) ---
bs_w            = $8D       ; blit_sprite clipped width
bs_h            = $8E       ; blit_sprite clipped height
bs_clip         = $C1       ; blit_sprite bottom clip line (GAME_H/SCR_H)
tl_left         = $8F       ; tile list: free slots + 1 (frame.asm tl_add)
r_row           = $B7       ; tile row (renderer/camera/blit_tile)
gt_px           = $BB       ; tile-check pixel X lo
gt_px_hi        = $BC       ; tile-check pixel X hi
gt_py           = $BD       ; tile-check pixel Y lo
gt_py_hi        = $BE       ; tile-check pixel Y hi (16-bit Y, player)
gt_col          = $BF       ; tile-check computed column
gt_row          = $C0       ; tile-check computed row
r_col           = $C2       ; tile column (renderer/camera/blit_tile)
tg_x            = $EC       ; the thinking enemy's target (enemies_ai.asm tg_set):
tg_xh           = $ED       ; its x, y (the player's zpx.. or a monster's en_x..)
tg_y            = $EE
tg_yh           = $EF
tg_ok           = $F0       ; <> 0: the target is alive (D2DF GetPos)
