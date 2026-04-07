;==============================================
; DOOM2D - Player projectiles, death, damage
; player_proj.asm
;==============================================

; ============================================
; PROJECTILES
; ============================================
proj_a  .ds MAX_PROJ
proj_x  .ds MAX_PROJ
proj_xh .ds MAX_PROJ            ; X high byte (for positions > 255)
proj_y  .ds MAX_PROJ
proj_vx .ds MAX_PROJ
proj_dmg .ds MAX_PROJ           ; damage per projectile (from weapon)
proj_spr .ds MAX_PROJ           ; sprite index per projectile

.proc spawn_proj
        ldx #0
?f      lda proj_a,x
        beq ?ok
        inx
        cpx #MAX_PROJ
        bne ?f
        rts
?ok     lda #1
        sta proj_a,x
        lda zpx
        sta proj_x,x
        lda zpx_hi
        sta proj_xh,x
        lda zpy
        sec
        sbc #14             ; gun height (chest level)
        sta proj_y,x
        ; Set damage and sprite from saved weapon (auto-switch may have changed zpwcur)
        ldy player_update.fire_wcur
        lda weap_dmg,y
        sta proj_dmg,x
        lda weap_proj_spr,y
        sta proj_spr,x
        lda zpdir
        bne ?pl
        lda #3
        sta proj_vx,x
        rts
?pl     lda #$FD
        sta proj_vx,x
        rts
.endp

.proc proj_update
        ldx #0
?lp     lda proj_a,x
        bne ?upd
        jmp ?nx
?upd    ; Update 16-bit X: proj_xh:proj_x += proj_vx (signed)
        lda proj_x,x
        clc
        adc proj_vx,x
        sta proj_x,x
        ; Sign-extend velocity to high byte
        lda proj_vx,x
        bmi ?neg
        ; Positive velocity: xh += carry
        lda proj_xh,x
        adc #0
        sta proj_xh,x
        jmp ?bounds
?neg    ; Negative velocity: xh += $FF + carry
        lda proj_xh,x
        adc #$FF
        sta proj_xh,x
?bounds ; Kill if off screen
        lda proj_xh,x
        bmi ?kill            ; xh < 0: past left edge
        cmp #2
        bcs ?kill            ; xh >= 2: past 512
        cmp #1
        bne ?chk_wall        ; xh = 0: check wall
        ; xh = 1: kill if past right edge (X > 320 = xh=1,lo=64)
        lda proj_x,x
        cmp #64
        bcs ?kill
?chk_wall
        ; Check hit against barrels FIRST (before tile check,
        ; because barrel uses invisible solid tile 15)
        stx zt
        jsr check_proj_barrels
        bcs ?nx3            ; hit barrel
        ; Check if projectile center hit a solid tile
        ldx zt
        lda proj_x,x
        clc
        adc #4              ; center of 8x8 sprite
        sta gt_px
        lda proj_xh,x
        adc #0
        sta gt_px_hi
        lda proj_y,x
        sta gt_py
        stx zt2
        jsr check_solid
        pha
        ldx zt2
        pla
        bne ?kill
        ; Check hit against all enemies
        ldx zt
        stx zt
        jsr check_proj_enemies
        bcc ?no_ehit
        ; Enemy hit — check if BFG for radius blast
        ldx zt
        lda proj_spr,x
        cmp #SPR_BFG_PROJ1
        bne ?nx3            ; not BFG, done
        jsr bfg_blast
        txa
        pha
        ldx #SFX_BFGXPL
        jsr snd_play
        pla
        tax
        jmp ?nx3
?no_ehit
        ldx zt
        jmp ?nx
?kill   lda proj_spr,x
        cmp #SPR_ROCKET_PROJ
        bne ?chk_bfg
        jsr rocket_splash_player
        txa
        pha
        ldx #SFX_BAREXP
        jsr snd_play
        pla
        tax
        jmp ?no_ksnd
?chk_bfg
        cmp #SPR_BFG_PROJ1
        bne ?no_ksnd
        jsr bfg_blast
        txa
        pha
        ldx #SFX_BFGXPL
        jsr snd_play
        pla
        tax
?no_ksnd
        lda #0
        sta proj_a,x
?nx     inx
        cpx #MAX_PROJ
        beq ?end
        jmp ?lp
?end    rts
?nx3    ldx zt
        inx
        cpx #MAX_PROJ
        beq ?end2
        jmp ?lp
?end2   rts
.endp

; ============================================
; PLAYER DEAD - death animation + wait for R restart
; ============================================
pl_dead_timer dta 0
pl_pain_timer dta 0

.proc player_dead
        ; Mark dirty at player position (ensure sprite cleanup between frames)
        lda zpx
        sta zdx
        lda zpx_hi
        sta zdxh
        lda zpy
        sec
        sbc #32
        bcs ?dy_ok
        lda #0
?dy_ok  sta zdy
        lda #16
        sta md_w
        lda #32
        sta md_h
        jsr mark_dirty_sprite

        lda pl_dead_timer
        bne ?counting
        ; First frame of death: play sound, init timer
        lda #0
        sta snd_lock
        ldx #SFX_PLDEATH
        jsr snd_play
        lda #1
        sta pl_dead_timer
?counting
        ; Increment death timer (for animation)
        lda pl_dead_timer
        cmp #255
        beq ?wait
        inc pl_dead_timer
?wait
        ; Auto-restart after ~3s (timer=180)
        lda pl_dead_timer
        cmp #180
        bcc ?done
        lda #$FF
        sta $02FC
        lda #0
        sta snd_active
        sta AUDC4
        sta pl_dead_timer
        lda POKMSK
        and #$FE
        sta POKMSK
        sta IRQEN
        jsr load_level
        jsr init_game
        jsr init_render
        lda #$FF
        sta hud_prev_hp
        sta hud_prev_ammo
        sta hud_prev_weap
        sta hud_prev_keys
        sta hud_prev_armor
        lda #2
        sta hud_frames
        lda #2
        sta hud_full_clear
?done   rts
.endp

; ============================================
; BFG BLAST - radius damage to all enemies in range
; Input: X = projectile index
; Radius: 64px, Damage: 20 per enemy
; ============================================
BFG_RADIUS = 64
BFG_BLAST_DMG = 20

.proc bfg_blast
        stx bf_proj
        ; Check once: is proj inside a solid tile? (wall/door hit)
        lda proj_x,x
        sta gt_px
        lda proj_xh,x
        sta gt_px_hi
        lda proj_y,x
        sta gt_py
        jsr check_solid
        sta bf_wall             ; 0 = open air, !0 = in wall
        ldy #0
?lp     sty bf_eidx
        lda en_act,y
        cmp #1
        beq ?alive
        jmp ?nx
?alive  ; Check same hi byte
        ldx bf_proj
        lda proj_xh,x
        cmp enxhi,y
        beq ?xhi_ok
        jmp ?nx
?xhi_ok
        ; X distance
        lda proj_x,x
        sec
        sbc en_x,y
        bpl ?xa
        eor #$FF
        clc
        adc #1
?xa     cmp #BFG_RADIUS
        bcc ?xok
        jmp ?nx
?xok    ; Y distance
        ldx bf_proj
        lda proj_y,x
        sec
        sbc en_y,y
        bpl ?ya
        eor #$FF
        clc
        adc #1
?ya     cmp #BFG_RADIUS
        bcc ?yok
        jmp ?nx
?yok    ; LOS: if proj hit wall, block enemies behind it
        lda bf_wall
        beq ?los_ok             ; proj in open air, blast always hits
        ldx bf_proj
        lda proj_vx,x
        bmi ?chk_left
        ; Proj going right: only hit enemies LEFT of proj (near side)
        lda en_x,y
        cmp proj_x,x
        bcs ?los_blocked        ; enemy X >= proj X = behind wall
        jmp ?los_ok
?chk_left
        ; Proj going left: only hit enemies RIGHT of proj (near side)
        lda proj_x,x
        cmp en_x,y
        bcs ?los_blocked        ; proj X >= enemy X = behind wall
?los_ok ldy bf_eidx
        ; Hit! Apply BFG damage
        lda en_hp,y
        sec
        sbc #BFG_BLAST_DMG
        bcs ?hok
        lda #0
?hok    sta en_hp,y
        bne ?nx
        ; Killed
        lda #2
        sta en_act,y
        lda #20
        sta en_dtimer,y
        lda #0
        sta en_gib,y
        sta envelx,y
        sty bf_eidx
        tya
        tax
        jsr play_enemy_death
        ldy bf_eidx
        jmp ?nx
?los_blocked
        ldy bf_eidx
?nx     ldy bf_eidx
        iny
        cpy #MAX_ENEMIES
        beq ?done
        jmp ?lp
?done
        ldx bf_proj
        rts
bf_proj dta 0
bf_eidx dta 0
bf_wall dta 0
.endp

; ============================================
; ROCKET SPLASH DAMAGE + KNOCKBACK TO PLAYER
; Input: X = projectile index
; ============================================
.proc rocket_splash_player
        stx rs_proj
        lda proj_spr,x
        cmp #SPR_ROCKET_PROJ
        bne ?ret
        lda proj_xh,x
        cmp zpx_hi
        bne ?ret
        lda proj_x,x
        sec
        sbc zpx
        bpl ?xa
        eor #$FF
        clc
        adc #1
?xa     cmp #ROCKET_SPLASH_RADIUS
        bcs ?ret
        sta rs_dist
        ldx rs_proj
        lda proj_y,x
        sec
        sbc zpy
        bpl ?ya
        eor #$FF
        clc
        adc #1
?ya     cmp #ROCKET_SPLASH_RADIUS
        bcs ?ret
        cmp rs_dist
        bcs ?dok
        lda rs_dist
?dok    asl
        sta rs_dist
        lda #ROCKET_SPLASH_MAX
        sec
        sbc rs_dist
        bcc ?pmin
        cmp #1
        bcs ?apply
?pmin   lda #1
?apply  sta rs_dist
        lda rs_dist
        jsr player_take_damage
        ; --- Horizontal knockback: push player away from explosion ---
        ldx rs_proj
        lda zpx
        cmp proj_x,x
        bcs ?kb_r
        ; Player left of explosion → push left
        lda #0
        sec
        sbc #BARREL_KB_X        ; use barrel KB strength (stronger)
        sta zpvx
        jmp ?ret
?kb_r   ; Player right → push right
        lda #BARREL_KB_X
        sta zpvx
?ret    rts
rs_proj dta 0
rs_dist dta 0
.endp

; ============================================
; PLAYER TAKE DAMAGE (with armor absorption)
; Input: A = damage amount
; Armor absorbs 75% damage, HP takes 25%
; ============================================
.proc player_take_damage
        sta ptd_dmg
        lda zparmor
        beq ?no_armor
        ; armor_hit = damage * 3/4
        lda ptd_dmg
        lsr
        lsr                     ; damage/4 (HP portion)
        beq ?min_hp
        jmp ?calc
?min_hp lda #1                  ; minimum 1 HP damage
?calc   sta ptd_hp
        lda ptd_dmg
        sec
        sbc ptd_hp              ; armor_hit = damage - damage/4
        sta ptd_arm
        ; Reduce armor
        lda zparmor
        sec
        sbc ptd_arm
        bcs ?ar_ok
        lda #0
?ar_ok  sta zparmor
        ; Apply HP portion
        lda zphp
        sec
        sbc ptd_hp
        bcs ?hp_ok
        lda #0
        jmp ?hp_ok
?no_armor
        ; No armor: full damage to HP
        lda zphp
        sec
        sbc ptd_dmg
        bcs ?hp_ok
        lda #0
?hp_ok  sta zphp
        lda #12                ; pain sprite for 12 frames (~0.2s)
        sta pl_pain_timer
        rts
ptd_dmg dta 0
ptd_arm dta 0
ptd_hp  dta 0
.endp
