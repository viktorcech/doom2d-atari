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
zpcoy           = $9B       ; coyote timer
zpx_hi          = $9C       ; player X high byte (for positions > 255)

zparmor         = $A0       ; armor points (0-200)
zpkeys          = $A1       ; key flags: bit0=red, bit1=blue, bit2=yellow
zpweap          = $A2       ; bitfield: owned weapons (bit0=fist..bit7=chainsaw)
zpshells        = $A3       ; shells ammo (shotgun)
zprockets       = $A4       ; rockets ammo (rocket launcher)
zpcells         = $A5       ; cells ammo (plasma, BFG)
zpwcur          = $A6       ; current weapon (0-7)

zjoy            = $A8       ; joystick state
ztrig           = $A9       ; trigger state
zjoyp           = $AA       ; previous joystick
ztrigp          = $AB       ; previous trigger

; Current enemy temp vars
zzidx           = $B5       ; current enemy index

; Hot loop counters (proj-enemy collision)
zcp_proj        = $AC       ; projectile index in collision loop
zcp_eidx        = $AD       ; enemy index in collision loop
zcp_tmp         = $AE       ; collision temp
zcp_tmph        = $AF       ; collision temp hi

zpwcool         = $C3       ; weapon cooldown timer
snd_ptr         = $C4       ; 2b: current sample address (sound IRQ)
snd_end         = $C6       ; 2b: end of sample address
snd_phase       = $C8       ; 0=hi nibble, 1=lo nibble

snd_active      = $C9       ; 0=silent, 1=playing
snd_cur_byte    = $CA       ; current packed byte (for lo nibble)
snd_lock        = $CB       ; >0 = priority sound playing, don't override
snd_bank        = $CC       ; current MEMAC-B bank
snd_save_y      = $CD       ; Y register save for sound IRQ

game_state      = $B8       ; 0=title, 1=playing
dirty_ptr       = $B9       ; 2b pointer to current dirty array

zdx             = $D0       ; draw X lo
zdxh            = $D1       ; draw X hi
zdy             = $D2       ; draw Y
ztptr           = $D4       ; 2b tile map pointer
