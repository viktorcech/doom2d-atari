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
        sta zpvx
        sta zpvy
        sta zpgnd
        sta zpcoy
        sta zpx_hi
        sta zpwcool
        sta zpammo
        sta zpshells
        sta zprockets
        sta zpcells
        sta zparmor
        sta zpkeys
        lda #SPAWN_X
        sta zpx
        lda #SPAWN_Y
        sta zpy
        lda #100
        sta zphp
        ; Start with fist + pistol + 50 bullets (like DOOM)
        lda #$03                ; bit0=fist, bit1=pistol
        sta zpweap
        lda #WP_PISTOL
        sta zpwcur
        lda #50
        sta zpammo
        lda #0
        sta pl_pain_timer
        ; Clear projectiles
        ldx #MAX_PROJ-1
?cp     sta proj_a,x
        dex
        bpl ?cp
        rts
.endp

; ============================================
; INPUT
; ============================================
.proc read_input
        lda zjoy
        sta zjoyp
        lda ztrig
        sta ztrigp
        lda $0278           ; STICK0 (OS shadow, updated by VBI)
        eor #$FF
        and #$0F
        sta zjoy
        lda $0284           ; STRIG0 (OS shadow)
        eor #$01
        sta ztrig
        jsr check_weapon_switch
        rts
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
        ; --- Coyote timer ---
        lda zpgnd
        beq ?coy_dec
        lda #COYOTE
        sta zpcoy
        jmp ?horiz
?coy_dec
        lda zpcoy
        beq ?horiz
        dec zpcoy

?horiz
        ; --- Horizontal acceleration ---
        lda zjoy
        and #J_LEFT
        beq ?not_l

        ; Accelerate left (air = half rate)
        lda zpgnd
        bne ?al_do
        lda zfr
        and #1
        bne ?dir_l          ; skip accel every other frame in air
?al_do  lda zpvx
        cmp #256-PL_MAXSPD  ; already at -3?
        beq ?dir_l
        dec zpvx
?dir_l  lda #1
        sta zpdir
        jmp ?apply_vx

?not_l  lda zjoy
        and #J_RIGHT
        beq ?no_h

        ; Accelerate right (air = half rate)
        lda zpgnd
        bne ?ar_do
        lda zfr
        and #1
        bne ?dir_r
?ar_do  lda zpvx
        cmp #PL_MAXSPD      ; already at +3?
        beq ?dir_r
        inc zpvx
?dir_r  lda #0
        sta zpdir
        jmp ?apply_vx

?no_h   ; No input: decelerate toward 0
        lda zpvx
        beq ?stopped
        bmi ?dec_n
        dec zpvx
        jmp ?apply_vx
?dec_n  inc zpvx
        jmp ?apply_vx
?stopped
        lda zpgnd
        bne ?st2
        jmp ?hd
?st2    lda #0
        sta zpst
        jmp ?hd

?apply_vx
        ; --- Apply horizontal velocity with collision ---
        lda zpvx
        bne ?vx_go
        jmp ?set_st
?vx_go  bmi ?vx_l

        ; Moving right: collision check (16-bit X)
        lda zpx
        clc
        adc zpvx
        sta zt              ; new X low
        lda zpx_hi
        adc #0
        sta zt2             ; new X high
        ; Check tile at (newX + PL_W, y-14)
        lda zt
        clc
        adc #PL_W
        sta gt_px
        lda zt2
        adc #0
        sta gt_px_hi
        lda zpy
        sec
        sbc #14
        sta gt_py
        jsr check_solid
        beq ?vx_rok
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
        adc #PL_W
        sta gt_px
        lda zt2
        adc #0
        sta gt_px_hi
        lda zpy
        sec
        sbc #14
        sta gt_py
        jsr check_solid
        bne ?vx_stop
?vx_rok lda zt
        sta zpx
        lda zt2
        sta zpx_hi
        jmp ?set_st

?vx_l   ; Moving left: collision check
        lda zpx
        clc
        adc zpvx            ; add negative = subtract
        sta zt
        lda zpx_hi
        adc #$FF            ; add -1 if borrow (sign extend)
        sta zt2
        bmi ?vx_l1          ; went negative = past left edge
        ; Check tile at (newX + 3, y-14)
        lda zt
        clc
        adc #3
        sta gt_px
        lda zt2
        adc #0
        sta gt_px_hi
        lda zpy
        sec
        sbc #14
        sta gt_py
        jsr check_solid
        beq ?vx_lok
        ; Blocked: try 1px
?vx_l1  lda zpx
        sec
        sbc #1
        sta zt
        lda zpx_hi
        sbc #0
        sta zt2
        bmi ?vx_stop        ; past left edge
        lda zt
        clc
        adc #3
        sta gt_px
        lda zt2
        adc #0
        sta gt_px_hi
        lda zpy
        sec
        sbc #14
        sta gt_py
        jsr check_solid
        bne ?vx_stop
        bcs ?vx_stop
?vx_lok lda zt
        sta zpx
        lda zt2
        sta zpx_hi
        jmp ?set_st

?vx_stop
        lda #0
        sta zpvx

?set_st ; Clamp player X to map bounds (0 to MAP_W*16-16)
        lda zpx_hi
        bmi ?clamp_l           ; xhi < 0 → past left edge
        cmp #(MAP_W*16/256)
        bcc ?xok
        ; Past right edge
        lda #<(MAP_W*16-16)
        sta zpx
        lda #>(MAP_W*16-16)
        sta zpx_hi
        lda #0
        sta zpvx
        jmp ?xok
?clamp_l
        lda #0
        sta zpx
        sta zpx_hi
        sta zpvx
?xok    ; Update animation state
        lda zpvx
        beq ?hd
        lda #1
        sta zpst

?hd
        ; --- Jump (with coyote time) ---
        lda zjoy
        and #J_UP
        beq ?noj
        lda zpgnd
        bne ?do_j
        lda zpcoy
        beq ?noj            ; no ground, no coyote
?do_j   lda #0
        sec
        sbc #JUMPF
        sta zpvy
        lda #0
        sta zpgnd
        sta zpcoy           ; consume coyote
        lda #2
        sta zpst
        ; sound disabled (will add custom sounds later)
?noj
        ; --- Variable jump height ---
        lda zpvy
        bpl ?noj2
        lda zjoyp
        and #J_UP
        beq ?noj2           ; wasn't holding UP
        lda zjoy
        and #J_UP
        bne ?noj2           ; still holding UP
        ; UP just released during ascent: cut upward velocity
        lda zpvy
        cmp #$FE            ; already -2 or -1?
        bcs ?noj2
        lda #$FE            ; reduce to gentle coast
        sta zpvy
?noj2
        ; --- Gravity ---
        lda zpgnd
        bne ?nog
        lda zpvy
        clc
        adc #GRAV
        bmi ?gok            ; still ascending (negative) = skip cap
        cmp #MAXFALL
        bcc ?gok
        lda #MAXFALL
?gok    sta zpvy
?nog
        ; --- Apply vel Y + vertical collision ---
        lda zpy
        clc
        adc zpvy
        sta zpy

        ; Check if falling (zpvy >= 0): floor collision
        lda zpvy
        bpl ?chk_floor
        ; Ascending: check Y underflow (carry from adc zpvy still valid)
        bcs ?chkup              ; carry set → no wrap, check ceiling
        ; Underflow: zpy wrapped past 0, clamp to top
        lda #1
        sta zpy
        lda #0
        sta zpvy
        jmp ?cd
?chk_floor

        ; Floor check: tile at feet (x+5, y)
        ; Use check_solid_or_platform so player lands on platforms
        lda zpx
        clc
        adc #5
        sta gt_px
        lda zpx_hi
        adc #0
        sta gt_px_hi
        lda zpy
        sta gt_py
        jsr check_solid_or_platform
        beq ?nofloor
        ; Landed! Snap to top of tile
        lda zpy
        and #$F0
        sta zpy
        lda #0
        sta zpvy
        lda #1
        sta zpgnd
        jmp ?cd
?nofloor
        lda zpy
        cmp #240
        bcc ?chkgnd
        lda #240
        sta zpy
        lda #0
        sta zpvy
        lda #1
        sta zpgnd
        jmp ?cd

?chkup  ; Rising: ceiling check at (x+5, y-PL_H)
        lda zpx
        clc
        adc #5
        sta gt_px
        lda zpx_hi
        adc #0
        sta gt_px_hi
        lda zpy
        sec
        sbc #PL_H
        bcs ?ceil_ok
        lda #0              ; underflow: clamp to tile row 0
?ceil_ok sta gt_py
        jsr check_solid
        beq ?cd
        ; Hit ceiling: snap below ceiling tile
        lda gt_py
        and #$F0
        clc
        adc #16
        adc #PL_H
        sta zpy
        lda #0
        sta zpvy
        jmp ?cd

?chkgnd lda zpgnd
        beq ?cd
        lda zpx
        clc
        adc #5
        sta gt_px
        lda zpx_hi
        adc #0
        sta gt_px_hi
        lda zpy
        sta gt_py
        jsr check_solid_or_platform
        bne ?cd
        lda #0
        sta zpgnd
?cd
        ; --- Shoot (with cooldown, weapon-dependent) ---
        lda zpwcool
        beq ?can_fire
        dec zpwcool
        jmp ?nos
?can_fire
        lda ztrig
        bne ?chk_fire
        jmp ?nos
?chk_fire
        ; --- Auto-fire detection ---
        ; Chaingun and Plasma fire continuously while trigger held.
        ; Other weapons require trigger release between shots (edge detect).
        ldx zpwcur
        cpx #WP_CHAINGUN
        beq ?autofire           ; chaingun: hold trigger = keep firing
        cpx #WP_PLASMA
        beq ?autofire           ; plasma: hold trigger = keep firing
        lda ztrigp              ; other weapons: check trigger was released
        beq ?autofire
        jmp ?nos                ; still held from last frame = don't fire
?autofire
        ; --- Ammo check ---
        jsr get_cur_ammo
        beq ?nos                ; no ammo left = can't fire
        ; --- Dispatch by weapon type ---
        ldx zpwcur
        lda weap_range,x
        bne ?melee              ; melee range > 0 = fist/chainsaw
        cpx #WP_ROCKET
        bcs ?projectile         ; rocket/plasma/BFG = spawn projectile
        ; --- Hitscan weapon (pistol, shotgun, chaingun) ---
        ; Save weapon before deduct (auto_switch may change zpwcur)
        lda zpwcur
        sta fire_wcur
        jsr deduct_ammo         ; subtract ammo (may auto-switch if empty)
        ; Play weapon sound BEFORE hit (so enemy death sound can queue)
        ldx fire_wcur           ; use saved weapon
        lda weap_sfx,x
        cmp #$FF
        beq ?no_hsfx            ; no sound defined = skip
        tax
        jsr snd_play
        ; Set sound lock duration based on weapon fire rate.
        ldx fire_wcur
        lda weap_cooldown,x     ; cooldown = frames between shots
        cmp #8
        bcc ?short_lock         ; cooldown < 8 → use cooldown as lock
        lda #8                  ; cooldown >= 8 → cap lock at 8 frames
?short_lock
        sta snd_lock
?no_hsfx
        jsr hitscan_fire
        jsr alert_enemies_sound
        ldx fire_wcur           ; use saved weapon for cooldown
        lda weap_cooldown,x
        sta zpwcool
        jmp ?nos
?projectile
        ; Projectile weapon (rocket, plasma, BFG)
        ; Save current weapon before deduct (auto_switch may change zpwcur)
        lda zpwcur
        sta fire_wcur
        jsr deduct_ammo
        jsr spawn_proj
        jsr alert_enemies_sound
        ldx fire_wcur          ; use saved weapon, not auto-switched
        lda weap_sfx,x
        cmp #$FF
        beq ?no_sfx
        tax
        jsr snd_play
?no_sfx ldx fire_wcur
        lda weap_cooldown,x
        sta zpwcool
        jmp ?nos
?melee  ; Melee attack
        jsr melee_attack
        ldx zpwcur
        lda weap_sfx,x
        cmp #$FF
        beq ?no_msfx
        tax
        jsr snd_play
?no_msfx ldx zpwcur
        lda weap_cooldown,x
        sta zpwcool
?nos
        inc zpan
        rts
fire_wcur dta 0                 ; saved weapon index during fire (before auto-switch)
.endp
