;==============================================
; DOOM2D - Player logic (input, movement, projectiles)
; player.asm
;==============================================

; ============================================
; INIT PLAYER
; ============================================
.proc init_player
        lda #0
        sta zpdir
        sta zpst
        sta zpan
        sta zpwcool
        sta zpshells
        sta zprockets
        sta zpcells
        ; (zparmor/zpkeys: init_game's init_pickups zeroes both right after;
        ;  zpvx/zpvy/zpgnd: player_spawn below)
        sta pl_pain_timer
        sta pl_expl_iframe
        ; Clear projectiles
        ldx #MAX_PROJ-1
?cp     sta proj_a,x
        dex
        bpl ?cp
        lda #100
        sta zphp
        ; Start with fist + pistol + 50 bullets (like DOOM)
        lda #$03                ; bit0=fist, bit1=pistol
        sta zpweap
        lda #WP_PISTOL
        sta zpwcur
        lda #50
        sta zpammo
        ldx #AM_BYTES-1         ; ammo hi bytes 0, the first limits
?cap    lda am_cap0-4,x
        cpx #4
        bcs ?cs
        lda #0
?cs     sta am_hi,x
        dex
        bpl ?cap
        ert *<>player_spawn     ; falls through
        ert AM_BYTES<>12
.endp

; PLAYER SPAWN - put the player at the level start, at rest (also next level)
.proc player_spawn
        lda #<AIR_DEF           ; D2DF: a life starts with AIR_DEF air
        sta pl_air
        lda #>AIR_DEF
        sta pl_air+1
        lda pl_start_x
        sta zpx
        lda pl_start_x+1
        sta zpx_hi
        lda pl_start_y
        sta zpy
        lda pl_start_y_hi
        sta zpy_hi
        lda #0
        sta zpvx
        sta zpvy
        sta zpvx_f
        sta zpvy_f
        sta zpx_f
        sta zpy_f
        sta zpgnd
        sta pl_liq              ; (zero page: not cleared at boot)
        rts                     ; Z=1 (lda #0): main's next-level path branches on it
.endp

; 8.8 fractions of the player's velocity and position (zpvx/zpvy are the
; signed whole parts)
zpvx_f  dta 0
zpvy_f  dta 0
zpx_f   dta 0
zpy_f   dta 0
pl_air  dta <AIR_DEF, >AIR_DEF  ; D2DF FAir (signed, 36 Hz ticks)
pl_acid_t dta ACID_TICKS        ; frames to the next acid hit

; ============================================
; INPUT
; ============================================
.proc read_input
        lda ztrig               ; (zjoyp: nothing read it)
        sta ztrigp
        lda $0278           ; STICK0 (OS shadow, updated by VBI)
        eor #$FF
        and #$0F
        sta zjoy
.if AUTOPLAY=1
        lda #J_RIGHT        ; debug: hold RIGHT (deterministic scroll)
        sta zjoy
.endif
        lda $0284           ; STRIG0 (OS shadow)
        eor #$01
        sta ztrig
        jmp check_weapon_switch ; tail call
.endp

; ============================================
; PLAYER UPDATE (with tile collision)
; ============================================
.proc player_update
        ; --- Pain timer ---
        lda pl_pain_timer
        beq ?no_pain_dec
        dec pl_pain_timer
?no_pain_dec
        ; --- Explosion immunity timer ---
        lda pl_expl_iframe
        beq ?no_expl_dec
        dec pl_expl_iframe
?no_expl_dec
        ; --- Liquid at the waist (D2DF BodyInLiquid); acid hurts every
        ;     ACID_TICKS frames: acid1 5, acid2 10 (g_basic.pas g_GetAcidHit) ---
        jsr pl_liquid           ; A = pl_liq, C = (A >= 2): acid
        bcc ?coy
        dec pl_acid_t
        bne ?coy
        ldx #ACID_TICKS
        stx pl_acid_t
        tax
        lda ?acid-2,x
        jsr player_take_damage
?coy    ; --- Air (D2DF, per 36 Hz tick): the head in a liquid loses 1, below
        ;     -9 a 10 hit and back to 0; out of it at least AIR_DEF ---
        bit ai_now
        bpl ?aird
        lda pl_liq              ; the head is only under if the waist is
        beq ?brth
        lda #PL_H-3             ; D2DF HeadInLiquid: the top of the body
        jsr pl_liquid.at
        beq ?brth
        lda pl_air
        bne ?ad
        dec pl_air+1
?ad     dec pl_air
        lda pl_air+1
        bpl ?aird               ; >= 0
        lda pl_air
        cmp #<[-9]
        bcs ?aird               ; -9..-1
        lda #0
        sta pl_air
        sta pl_air+1
        lda #10
        jsr player_take_damage
        jmp ?aird
?brth   lda pl_air+1            ; air = max(air, AIR_DEF)
        bmi ?aset
        cmp #>AIR_DEF
        bcc ?aset
        bne ?aird
        lda pl_air
        cmp #<AIR_DEF
        bcs ?aird
?aset   lda #<AIR_DEF
        sta pl_air
        lda #>AIR_DEF
        sta pl_air+1
?aird
?horiz
        ; --- Horizontal velocity (8.8, D2DF TPlayer.Run): a held direction
        ; adds PL_ACC up to PL_VMAX, ground or air; no key brakes by PL_ACC.
        ; Velocities stay small (|v| < 8): no signed overflow in the tests.
        lda zjoy
        and #J_LEFT
        beq ?not_l
        lda zpvx                ; at -PL_VMAX or below already? (knockback can be)
        cmp #<[[-PL_VMAX]>>8]
        bmi ?dir_l
        bne ?al
        lda zpvx_f
        cmp #<[-PL_VMAX]
        bcc ?dir_l
        beq ?dir_l
?al     lda zpvx_f              ; v -= PL_ACC, not below -PL_VMAX
        sec
        sbc #<PL_ACC
        sta zpvx_f
        lda zpvx
        sbc #>PL_ACC
        sta zpvx
        cmp #<[[-PL_VMAX]>>8]
        bmi ?cap_l
        bne ?dir_l
        lda zpvx_f
        cmp #<[-PL_VMAX]
        bcs ?dir_l
?cap_l  lda #<[-PL_VMAX]
        sta zpvx_f
        lda #<[[-PL_VMAX]>>8]
        sta zpvx
?dir_l  lda #1
        sta zpdir
        jmp ?apply_vx

?not_l  lda zjoy
        and #J_RIGHT
        jeq ?no_h
        lda zpvx                ; at PL_VMAX or above already?
        bmi ?ar
        cmp #>PL_VMAX
        bcc ?ar
        bne ?dir_r
        lda zpvx_f
        cmp #<PL_VMAX
        bcs ?dir_r
?ar     lda zpvx_f              ; v += PL_ACC, not above PL_VMAX
        clc
        adc #<PL_ACC
        sta zpvx_f
        lda zpvx
        adc #>PL_ACC
        sta zpvx
        bmi ?dir_r
        cmp #>PL_VMAX
        bcc ?dir_r
        bne ?cap_r
        lda zpvx_f
        cmp #<PL_VMAX
        bcc ?dir_r
?cap_r  lda #<PL_VMAX
        sta zpvx_f
        lda #>PL_VMAX
        sta zpvx
?dir_r  lda #0
        sta zpdir
        jeq ?apply_vx           ; Z=1 from lda #0

?stopped
        lda zpgnd
        jeq ?hd
        lda #0
        sta zpst
?jhd    jmp ?hd

?vx_stop
        lda #0
        sta zpvx
        sta zpvx_f
?set_st ; Clamp player X to map bounds (0 to PL_XMAX); ?mv comes here only out of them
        lda zpx_hi
        bmi ?clamp_l           ; xhi < 0 → past left edge
        cmp #>PL_XMAX
        jcc ?hd                ; in bounds: zpst stays
        bne ?clamp_r
        lda zpx
        cmp #<[PL_XMAX+1]
        jcc ?hd
?clamp_r ; Past right edge
        lda #<PL_XMAX
        sta zpx
        lda #>PL_XMAX
        sta zpx_hi
        lda #0
        beq ?clz                ; (always)
?clamp_l
        lda #0
        sta zpx
        sta zpx_hi
?clz    sta zpvx
        sta zpvx_f
        beq ?jhd               ; (always: A = 0); zpvx = 0: zpst stays

?no_h   ; No input: brake toward 0 by PL_ACC (D2DF z_dec), stopping at 0
        lda zpvx
        ora zpvx_f
        jeq ?stopped
        lda zpvx
        bmi ?brk_n
        lda zpvx_f
        sec
        sbc #<PL_ACC
        sta zpvx_f
        lda zpvx
        sbc #>PL_ACC
        sta zpvx
        bpl ?apply_vx
        bmi ?brk_0              ; crossed 0
?brk_n  lda zpvx_f
        clc
        adc #<PL_ACC
        sta zpvx_f
        lda zpvx
        adc #>PL_ACC
        sta zpvx
        bmi ?apply_vx
?brk_0  lda #0
        sta zpvx
        sta zpvx_f

?apply_vx
        ; --- Apply horizontal velocity with collision: whole pixels this
        ; frame = (zpvx:zpvx_f) + the position fraction zpx_f ---
        lda zpx_f
        clc
        adc zpvx_f
        sta zpx_f
        lda zpvx
        adc #0                  ; A = signed whole-pixel step
        jeq ?set_st             ; no whole pixel this frame: no move
        jmi ?vx_l

        ; Moving right: collision check (16-bit X); A = the step
        clc
        adc zpx
        sta zt              ; new X low
        lda zpx_hi
        adc #0
        sta zt2             ; new X high
        ; The rect's right side (newX + PL_RR) over its height
        lda zt
        clc
        adc #PL_RR
        sta gt_px
        lda zt2
        adc #0
        sta gt_px_hi
        jsr pl_wall
        beq ?vx_lok
        ; Blocked: try 1px
        lda zpx
        clc
        adc #1
        sta zt
        lda zpx_hi
        adc #0
        sta zt2
        lda zt
        clc
        adc #PL_RR
        sta gt_px
        lda zt2
        adc #0
        sta gt_px_hi
        jsr pl_wall
        beq ?vx_lok
?vxs    jmp ?vx_stop

?vx_l   ; Moving left: collision check of the rect's left side; A = the step
        clc
        adc zpx             ; add negative = subtract
        sta zt
        lda zpx_hi
        adc #$FF            ; add -1 if borrow (sign extend)
        sta zt2
        bmi ?vx_l1          ; went negative = past left edge: retry 1px
        ; The rect's left side (newX - PL_RL) over its height
        lda zt
        sec
        sbc #PL_RL
        sta gt_px
        lda zt2
        sbc #0
        sta gt_px_hi
        jsr pl_wall
        beq ?vx_lok
?vx_l1  ; Blocked: try 1px
        lda zpx
        sec
        sbc #1
        sta zt
        lda zpx_hi
        sbc #0
        sta zt2
        bmi ?vxs            ; past left edge
        lda zt
        sec
        sbc #PL_RL
        sta gt_px
        lda zt2
        sbc #0
        sta gt_px_hi
        jsr pl_wall
        jne ?vx_stop
?vx_lok lda zt
        sta zpx
        lda zt2
        sta zpx_hi          ; N = sign of new X high
        ; Moved: clamp to map bounds, else animate
        bmi ?oob               ; xhi < 0 → past left edge
        cmp #>PL_XMAX
        bcc ?mv_ok
        bne ?oob
        lda zpx
        cmp #<[PL_XMAX+1]
        bcc ?mv_ok
?oob    jmp ?set_st            ; the same test there clamps (out of bounds here)
?mv_ok  lda #1
        sta zpst

?hd
        ; --- Jump (D2DF Jump: only from the ground) ---
        lda zjoy
        and #J_UP
        beq ?noj
        lda zpgnd
        bne ?do_j
        lda pl_liq              ; no ground: in a liquid, swim up
        beq ?noj                ; (D2DF Jump: Vel.Y = -VEL_SW)
        lda #<[-PL_SWV]
        sta zpvy_f
        lda #>[-PL_SWV]
        sta zpvy
        bne ?noj                ; (always: the hi byte of a negative v)
?do_j   ; Check ceiling above head before jumping (2 px over the rect)
        lda zpy
        sec
        sbc #PL_RH+2
        sta gt_py
        lda zpy_hi
        sbc #0
        sta gt_py_hi
        jsr pl_roof
        bne ?noj            ; ceiling directly above → block jump
        lda #<[-PL_JUMPV]   ; v = -PL_JUMPV (D2DF VEL_JUMP; no cut on release)
        sta zpvy_f
        lda #<[[-PL_JUMPV]>>8]
        sta zpvy
        lda #0
        sta zpgnd
        lda #2
        sta zpst
?noj
        ; --- Lifts (g_Obj_Move): up = v - PL_GRAV down to -PL_LIFTV, the
        ; player leaves the ground; down = gravity, at most +PL_LIFTV ---
        jsr lift_player         ; C=1 inside: A = 0 up, 1 down
        bcc ?grav
        lsr
        bcs ?ldn
        lda #0
        sta zpgnd
        lda zpvy_f
        sec
        sbc #PL_GRAV
        tax
        lda zpvy
        sbc #0
        cmp #>[-PL_LIFTV]       ; v < -PL_LIFTV: back to it
        bcc ?lcap
        bne ?lst
        cpx #<[-PL_LIFTV]
        bcs ?lst
?lcap   ldx #<[-PL_LIFTV]
        lda #>[-PL_LIFTV]
?lst    stx zpvy_f
        sta zpvy
        jmp ?nog
?ldn    lda zpvy                ; v > PL_LIFTV: stays, else + gravity
        bmi ?ladd
        cmp #>PL_LIFTV
        bcc ?ladd
        bne ?nog
        lda zpvy_f
        cmp #<PL_LIFTV+1
        bcs ?nog
?ladd   lda #0
        sta zpgnd
        lda zpvy_f
        clc
        adc #PL_GRAV
        sta zpvy_f
        lda zpvy
        adc #0
        sta zpvy
        jmp ?nog
?grav   ; --- Gravity (8.8): v += PL_GRAV in the air, at most PL_MAXV ---
        lda zpgnd
        bne ?nog
        lda zpvy_f
        clc
        adc #PL_GRAV
        sta zpvy_f
        lda zpvy
        adc #0
        bmi ?gok            ; still rising: no cap
        cmp #>PL_MAXV
        bcc ?gok
        bne ?gcap
        ldy zpvy_f          ; whole = 10: the fraction decides (A kept)
        cpy #<PL_MAXV
        bcc ?gok
?gcap   lda #<PL_MAXV       ; cap: D2DF MAX_YV
        sta zpvy_f
        lda #>PL_MAXV
?gok    sta zpvy
?nog    lda pl_liq              ; in a liquid: speeds past PL_SWV lose half
        beq ?dry                ; the excess (D2DF g_Obj_Move)
        ldx #0
        jsr pl_damp             ; vx
        inx
        jsr pl_damp             ; vy
?dry
        ; --- Apply vel Y + vertical collision (16-bit Y): whole pixels this
        ; frame = (zpvy:zpvy_f) + the position fraction zpy_f ---
        lda zpy_f
        clc
        adc zpvy_f
        sta zpy_f
        lda zpvy
        adc #0
        tax                     ; X = this frame's whole-pixel step dy
        clc
        adc zpy
        sta zpy
        tay                     ; Y = new zpy lo (no call before its uses below)
        txa                     ; C kept for the high byte
        bpl ?vy_pos             ; falling (dy >= 0) -> floor; rising -> ceiling
        lda zpy_hi
        adc #$FF                ; negative velocity -> sign-extend hi with -1
        sta zpy_hi              ; N = new hi (from adc)
        bmi ?vy_wrap            ; wrapped past top

        ; Rising: ceiling check along the rect's top (y-PL_RH)
        tya                     ; = zpy
        sec
        sbc #PL_RH
        sta gt_py
        lda zpy_hi
        sbc #0
        sta gt_py_hi
        jsr pl_roof
        jeq ?cd
        ; Hit ceiling: snap feet below the ceiling tile (tile_top + TH + PL_RH)
        lda gt_py
        and #$100-TH
        clc
        adc #TH+PL_RH
        sta zpy
        lda gt_py_hi
        adc #0
        sta zpy_hi
        lda #0
?zvy    sta zpvy
        sta zpvy_f
        jeq ?cd                 ; Z=1 from lda #0 (all three ways in)

?vy_wrap
        lda #1                  ; wrapped past top -> clamp to Y=1
        sta zpy
        lda #0
        sta zpy_hi
        beq ?zvy                ; (always)
?f8     lda gt_py               ; the cell 8 px above the new feet
        sec
        sbc #TH
        sta gt_py
        bcs ?f8a
        dec gt_py_hi
?f8a    jsr pl_xl
        jsr check_solid_or_platform16
        bne ?l8
        jsr pl_xr
        jsr check_solid_or_platform16
        bne ?l8
        lda zpy                 ; none: the feet's own cell
        sta gt_py
        lda zpy_hi
        sta gt_py_hi
        jmp ?f0
?l8     lda gt_py               ; land on that cell's top
        sta zpy
        lda gt_py_hi
        sta zpy_hi
        jmp ?land
?nofloor
        ; No floor: in the air. Below the map get_tile_at16 reads solid, so the
        ; feet land on Y = MAP_H*TH (the probes above see that) - the last row's
        ; triggers (an EXIT at the map bottom) cover the player there
        lda #0
        sta zpgnd
        jeq ?cd                 ; Z=1 from lda #0

?vy_pos lda zpy_hi
        adc #0
        sta zpy_hi
        ; Floor check at the feet, both sides of the rect. A step of 8+ px
        ; may pass a whole cell: the cell 8 px higher first (rare)
        sta gt_py_hi
        sty gt_py               ; Y = zpy
        lda zpvy
        cmp #TH
        bcs ?f8
?f0     jsr pl_xl
        jsr check_solid_or_platform16
        bne ?land
        jsr pl_xr
        jsr check_solid_or_platform16
        jeq ?nofloor
?land
        ; Landed! Snap to top of tile (clear the low bits; hi unchanged)
        lda zpy
        and #$100-TH
        sta zpy
        lda #0
        sta zpvy
        sta zpvy_f
        sta zpy_f
        lda #1
        sta zpgnd
?cd
        ; --- Shoot (with cooldown, weapon-dependent) ---
        lda zpwcool
        beq ?can_fire
        dec zpwcool
        inc zpan                ; ?nos inlined (same 3 bytes as the jmp)
        rts
?can_fire
        lda ztrig
        bne ?chk_fire
        inc zpan                ; ?nos inlined
        rts
?chk_fire
        ; --- Auto-fire detection ---
        ; Chaingun and Plasma fire continuously while trigger held.
        ; Other weapons require trigger release between shots (edge detect).
        ldx zpwcur
        cpx #WP_CHAINGUN
        beq ?autofire           ; chaingun: hold trigger = keep firing
        cpx #WP_PLASMA
        beq ?autofire           ; plasma: hold trigger = keep firing
        cpx #WP_SAW
        beq ?autofire           ; saw: hold trigger = keep sawing
        lda ztrigp              ; other weapons: check trigger was released
        beq ?autofire
        inc zpan                ; ?nos inlined: still held from last frame = don't fire
        rts
?autofire
        ; --- Ammo check ---
        jsr get_cur_ammo        ; returns X = zpwcur
        beq ?nos                ; no ammo left = can't fire
        ; --- Dispatch by weapon type ---
        lda weap_range,x
        bne ?melee              ; melee range > 0 = fist/chainsaw
        cpx #WP_ROCKET
        bcs ?projectile         ; rocket/plasma/BFG = spawn projectile
        ; --- Hitscan weapon (pistol, shotgun, chaingun) ---
        ; Save weapon before deduct (auto_switch may change zpwcur)
        stx fire_wcur           ; X = zpwcur
        jsr deduct_ammo         ; returns X = zpwcur at entry = fire_wcur
        ; The weapon's sound on a voice of its own (sound.asm: SND_NV voices).
        ; Every weapon has a sound (ert in weapons.asm): no $FF test.
        lda weap_sfx,x
        tax
        jsr snd_play
        jsr hitscan_fire
        jsr bl_shell            ; the casing (blood.asm)
        ldx fire_wcur           ; use saved weapon for cooldown
        bne ?cool               ; (always: hitscan weapons are 1..3)
?projectile
        ; Projectile weapon (rocket, plasma, BFG)
        ; Save current weapon before deduct (auto_switch may change zpwcur)
        stx fire_wcur           ; X = zpwcur
        jsr deduct_ammo
        jsr spawn_proj
        ldx fire_wcur          ; use saved weapon, not auto-switched
        lda weap_sfx,x
        tax
        jsr snd_play
        ldx fire_wcur
        bne ?cool               ; (always: projectile weapons are 4..6)
?melee  ; Melee attack
        jsr melee_attack
        ldx zpwcur
        cpx #WP_SAW             ; the saw: its sound plays SAW_LOCK frames
        bne ?mfx                ; before a retrigger (D2DF loops it while held)
        lda snd_lock
        bne ?mcd
        ldx #SFX_SAWFUL
        jsr snd_play
        lda #SAW_LOCK
        sta snd_lock
        bne ?mcd                ; (always)
?mfx    lda weap_sfx,x
        tax
        jsr snd_play
?mcd    ldx zpwcur
?cool   lda weap_cooldown,x
        sta zpwcool
?nos
        inc zpan
        rts
fire_wcur dta 0                 ; saved weapon index during fire (before auto-switch)
?acid   dta 5, 10               ; acid1, acid2 damage
        ert >[-PL_SWV]=0
.endp

; PL_LIQUID - pl_liq = the liquid at the waist (x+5, y-14): a background
; tile's tile_solid is its liquid (d2df2map.py). Returns A = pl_liq and
; C = (A >= 2): acid. PL_LIQUID.AT: A = rows above the feet; returns A =
; the liquid there (Z=1: none), pl_liq untouched. Entering a liquid: a
; splash (pl_splash, blood.asm; it keeps no register).
.proc pl_liquid
        lda #14
        jsr at
        bne ?in                 ; Z from at: out of a liquid falls through
?st     sta pl_liq
        cmp #2
        rts
?in     ldx pl_liq
        bne ?st                 ; in it already
        pha                     ; just entered, X = 0 (2026-11-02 6502-cycles-layout.md
        jsr pl_splash           ; "rare case out of line"; 6502-idioms.md "no RAM
        pla                     ; cell for a value that only waits")
        bne ?st                 ; (always: A = the liquid, 1..3)
at      sta ?o+1
        lda zpx
        clc
        adc #5
        sta gt_px
        lda zpx_hi
        adc #0
        sta gt_px_hi
        lda zpy
        sec
?o      sbc #0                  ; (patched: rows above the feet)
        sta gt_py
        lda zpy_hi
        sbc #0
        sta gt_py_hi
        jsr get_tile_at16       ; N = background (out of the map: 1, N=0)
        bpl ?no
        tay
        lda tile_solid,y        ; 0..3, Z: no liquid
        rts
?no     lda #0
        rts
.endp

; PL_WALL - a side of the rect (D2DF PLAYER_RECT at half scale, 17 x 26 px:
; [zpx-PL_RL, zpx+PL_RR] x [zpy-PL_RH, zpy-1]) on the column gt_px: probes
; at most a cell (8 px) apart from the feet to the head. Z=0: blocked.
.proc pl_wall
        ldx #4
?lp     lda zpy
        sec
        sbc ?dy,x
        sta gt_py
        lda zpy_hi
        sbc #0
        sta gt_py_hi
        jsr check_solid16       ; keeps X
        bne done
        dex
        bpl ?lp
        inx                     ; Z=1 (X = $FF + 1)
done    rts                     ; (pl_roof's Z=0 exit too)
?dy     dta 1, 8, 15, 22, PL_RH
.endp

; PL_ROOF - the rect's top row gt_py at both sides: Z=0 solid
.proc pl_roof
        jsr pl_xl
        jsr check_solid16
        bne pl_wall.done
        jsr pl_xr
        jmp check_solid16
.endp

; PL_XL / PL_XR - gt_px = the rect's left / right side
.proc pl_xl
        lda zpx
        sec
        sbc #PL_RL
        sta gt_px
        lda zpx_hi
        sbc #0
        sta gt_px_hi
        rts
.endp
.proc pl_xr
        lda zpx
        clc
        adc #PL_RR
        sta gt_px
        lda zpx_hi
        adc #0
        sta gt_px_hi
        rts
.endp

; PL_DAMP - D2DF g_Obj_Move in a liquid: a speed past PL_SWV loses half of
; the excess. X = 0 vx, 1 vy (zpvx,x whole / zpvx_f,x fraction, signed 8.8).
.proc pl_damp
        lda zpvx,x
        bmi ?neg
        lda zpvx_f,x            ; excess = v - PL_SWV
        sec
        sbc #<PL_SWV
        tay
        lda zpvx,x
        sbc #>PL_SWV
        bcc ?r                  ; v < PL_SWV
        lsr                     ; v = PL_SWV + excess/2 (C = the dropped
        pha                     ; bit 0 of the excess: rounds up; pha/pla keep C)
        tya
        ror
        adc #<PL_SWV
        sta zpvx_f,x
        pla
        adc #>PL_SWV
        sta zpvx,x
?r      rts
?neg    lda #<[-PL_SWV]         ; excess = -PL_SWV - v
        sec
        sbc zpvx_f,x
        tay
        lda #>[-PL_SWV]
        sbc zpvx,x
        bcc ?r                  ; v > -PL_SWV
        lsr                     ; v = -PL_SWV - excess/2: K - e = K + ~e + 1,
        pha                     ; the same bytes and borrow as sec / sbc e
        tya
        ror
        eor #$FF
        sec
        adc #<[-PL_SWV]
        sta zpvx_f,x
        pla
        eor #$FF
        adc #>[-PL_SWV]
        sta zpvx,x
        rts
        ert zpvy<>zpvx+1
        ert zpvy_f<>zpvx_f+1
.endp
