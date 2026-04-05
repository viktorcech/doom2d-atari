;==============================================
; DOOM2D - Enemy projectile hits + enemy projectiles
; enemies_proj.asm
;==============================================

; ============================================
; CHECK PROJECTILE HIT ON ALL ENEMIES
; Returns: C=1 if hit (enemy killed/damaged), C=0 if no hit
; Input: proj_x[zt], proj_y[zt] via X index in zt
; ============================================
.proc check_proj_enemies
        lda zt
        sta cp_proj
        lda #0
        sta cp_eidx
?lp     ldx cp_eidx
        lda en_act,x
        cmp #1              ; only alive enemies (skip dead=0 and dying=2)
        beq ?chk
        jmp ?nxe
?chk    ; --- X distance (16-bit) ---
        ldx cp_proj
        lda proj_x,x
        sec
        ldx cp_eidx
        sbc en_x,x
        sta cp_tmp          ; dist low
        ldx cp_proj
        lda proj_xh,x
        ldx cp_eidx
        sbc enxhi,x
        sta cp_tmph          ; dist high (signed)
        ; Absolute value
        bpl ?xpos
        lda cp_tmp
        eor #$FF
        clc
        adc #1
        sta cp_tmp
        lda cp_tmph
        eor #$FF
        adc #0
        sta cp_tmph
?xpos   lda cp_tmph
        beq ?xnear
        jmp ?nxe            ; hi != 0 -> too far
?xnear  lda cp_tmp
        cmp #14             ; within 14px X
        bcc ?ychk
        jmp ?nxe
?ychk   ; --- Y distance ---
        ldx cp_proj
        lda proj_y,x
        sec
        ldx cp_eidx
        sbc en_y,x
        bpl ?ypos
        eor #$FF
        clc
        adc #1
?ypos   cmp #28             ; within 28px Y
        bcc ?hit
        jmp ?nxe
?hit    ; --- HIT! ---
        ; Apply damage
        ldx cp_proj
        lda proj_dmg,x
        ldx cp_eidx
        ; Subtract from HP
        sta cp_tmp          ; damage amount
        lda en_hp,x
        sec
        sbc cp_tmp
        bcc ?kill
        beq ?kill
        sta en_hp,x
        ; Pain sprite
        lda #6
        sta en_pain_tmr,x
        ; Knockback from hit (use proj_vx direction)
        ldx cp_proj
        lda proj_vx,x
        ldx cp_eidx
        bmi ?kb_l
        ; Knockback right (projectile going right)
        lda envelx,x
        clc
        adc #2
        cmp #4
        bcc ?kb_s
        lda #4
        jmp ?kb_s
?kb_l   ; Knockback left (projectile going left)
        lda envelx,x
        sec
        sbc #2
        cmp #$FC
        bcs ?kb_s
        lda #$FC
?kb_s   sta envelx,x
        ; Play pain sound
        lda #SFX_OOF
        jsr play_sfx_unlock
        ; Destroy projectile
        ldx cp_proj
        lda #0
        sta proj_a,x
        sec              ; hit
        rts
?kill   ; Enemy killed!
        ldx cp_eidx
        jsr start_enemy_death
        ; Knockback velocity for gib (rocket + weak enemy only)
        ldx cp_proj
        lda proj_spr,x
        cmp #SPR_ROCKET_PROJ     ; rocket?
        bne ?no_gib
        ; Only zombie, imp, shotgun guy can gib
        ldx cp_eidx
        lda en_type,x
        cmp #EN_ZOMBIE
        beq ?do_gib
        cmp #EN_IMP
        beq ?do_gib
        cmp #EN_SHOTGUN
        beq ?do_gib
        jmp ?no_gib              ; pinky/caco/baron = normal death
?do_gib ldx cp_eidx
        lda #1
        sta en_gib,x
        ldx cp_proj
        lda proj_vx,x       ; A = proj direction (signed)
        bmi ?gib_l           ; check sign BEFORE ldx clobbers N flag
        ldx cp_eidx
        lda #8              ; right knockback
        sta envelx,x
        jmp ?gib_vy
?gib_l  ldx cp_eidx
        lda #$F8            ; left knockback (-8)
        sta envelx,x
?gib_vy lda #$F4            ; upward velocity (-12)
        sta envely,x
        ; Gib sound (splat)
        lda #SFX_SLOP
        jsr play_sfx_unlock
        jmp ?kill_done
?no_gib ldx cp_eidx
        lda #0
        sta envely,x
        ; Death sound
        jsr play_enemy_death
?kill_done
        ; Destroy projectile + splash if rocket
        ldx cp_proj
        lda proj_spr,x
        cmp #SPR_ROCKET_PROJ
        bne ?nosplash
        jsr rocket_splash_player
        ldx cp_proj
?nosplash
        lda #0
        sta proj_a,x
        sec              ; hit
        rts
?nxe    inc cp_eidx
        lda cp_eidx
        cmp #MAX_ENEMIES
        bcs ?miss
        jmp ?lp
?miss   clc              ; no hit
        rts
cp_proj dta 0
cp_eidx dta 0
cp_tmp  dta 0
cp_tmph dta 0
.endp

; Turn counter for stuck detection
en_tcnt      dta 0,0,0,0,0,0    ; MAX_ENEMIES = 6
en_pain_tmr  dta 0,0,0,0,0,0    ; pain sprite timer

; ============================================
; ENEMY PROJECTILES (imp fireball etc.)
; ============================================
MAX_EPROJ = 3

eproj_a   .ds MAX_EPROJ       ; 0=inactive, 1=active
eproj_x   .ds MAX_EPROJ       ; X lo
eproj_xh  .ds MAX_EPROJ       ; X hi
eproj_y   .ds MAX_EPROJ       ; Y
eproj_vx  .ds MAX_EPROJ       ; velocity X (signed)
eproj_dmg .ds MAX_EPROJ       ; damage
eproj_spr .ds MAX_EPROJ       ; sprite index

.proc init_eproj
        ldx #MAX_EPROJ-1
?lp     lda #0
        sta eproj_a,x
        dex
        bpl ?lp
        rts
.endp

; Spawn enemy projectile
; Input: X = enemy index (en_x/enxhi/en_y/en_dir used for position)
.proc spawn_eproj
        stx ep_eidx
        ; Find free slot
        ldx #0
?f      lda eproj_a,x
        beq ?ok
        inx
        cpx #MAX_EPROJ
        bne ?f
        rts                    ; no free slot
?ok     lda #1
        sta eproj_a,x
        ; Position from enemy + offset in fire direction
        ldy ep_eidx
        lda en_dir,y
        bne ?sp_left
        ; Facing right: X + 12
        lda en_x,y
        clc
        adc #12
        sta eproj_x,x
        lda enxhi,y
        adc #0
        sta eproj_xh,x
        jmp ?sp_y
?sp_left
        ; Facing left: X - 4
        lda en_x,y
        sec
        sbc #4
        sta eproj_x,x
        lda enxhi,y
        sbc #0
        sta eproj_xh,x
?sp_y   lda en_y,y
        sec
        sbc #14                ; chest height
        sta eproj_y,x
        ; Velocity: toward player direction
        lda en_dir,y
        bne ?left
        lda #3                 ; right
        sta eproj_vx,x
        jmp ?setdmg
?left   lda #$FD               ; left (-3)
        sta eproj_vx,x
?setdmg ; Set damage and sprite based on enemy type
        ldy ep_eidx
        lda en_type,y
        cmp #EN_CACO
        beq ?caco_fb
        ; Imp fireball: 20 damage, red sprite
        lda #20
        sta eproj_dmg,x
        lda #SPR_IMP_FIRE1
        sta eproj_spr,x
        rts
?caco_fb ; Caco fireball: 15 damage, different sprite
        lda #15
        sta eproj_dmg,x
        lda #SPR_CACO_FIRE1
        sta eproj_spr,x
        rts
ep_eidx dta 0
.endp

; Update enemy projectiles
.proc eproj_update
        ldx #0
?lp     lda eproj_a,x
        bne ?upd
        jmp ?nx
?upd    ; Animate sprite (toggle frame every 4 frames)
        lda eproj_spr,x
        cmp #SPR_CACO_FIRE1
        bcs ?caco_anim
        ; Imp fireball animation
        lda zfr
        and #$04
        beq ?f1
        lda #SPR_IMP_FIRE2
        sta eproj_spr,x
        jmp ?move
?f1     lda #SPR_IMP_FIRE1
        sta eproj_spr,x
        jmp ?move
?caco_anim
        lda zfr
        and #$04
        beq ?cf1
        lda #SPR_CACO_FIRE2
        sta eproj_spr,x
        jmp ?move
?cf1    lda #SPR_CACO_FIRE1
        sta eproj_spr,x
?move   ; Update 16-bit X
        lda eproj_x,x
        clc
        adc eproj_vx,x
        sta eproj_x,x
        lda eproj_vx,x
        bmi ?negv
        lda eproj_xh,x
        adc #0
        sta eproj_xh,x
        jmp ?bounds
?negv   lda eproj_xh,x
        adc #$FF
        sta eproj_xh,x
?bounds ; Kill if off screen
        lda eproj_xh,x
        bmi ?kill
        cmp #2
        bcs ?kill
        ; Check wall collision
        stx ep_idx
        lda eproj_x,x
        clc
        adc #4
        sta gt_px
        lda eproj_xh,x
        adc #0
        sta gt_px_hi
        lda eproj_y,x
        sta gt_py
        jsr check_solid
        bne ?kill2
        ; Check player collision (8x8 vs player 10x28)
        ldx ep_idx
        ; X distance
        lda eproj_x,x
        sec
        sbc zpx
        sta ep_dx
        lda eproj_xh,x
        sbc zpx_hi
        bne ?nx2               ; hi byte diff = too far
        lda ep_dx
        bpl ?xpos
        eor #$FF
        clc
        adc #1
?xpos   cmp #12                ; within 12px X
        bcs ?nx2
        ; Y distance
        lda eproj_y,x
        sec
        sbc zpy
        bpl ?ypos
        eor #$FF
        clc
        adc #1
?ypos   cmp #24                ; within 24px Y
        bcs ?nx2
        ; Hit player!
        lda eproj_dmg,x
        jsr player_take_damage
        lda #0
        sta eproj_a,x
        jmp ?nx
?kill2  ldx ep_idx
?kill   lda #0
        sta eproj_a,x
?nx     inx
        cpx #MAX_EPROJ
        beq ?done
        jmp ?lp
?nx2    ldx ep_idx
        jmp ?nx
?done   rts
ep_idx  dta 0
ep_dx   dta 0
.endp

; Render enemy projectiles
.proc render_eproj
        ldx #0
?lp     lda eproj_a,x
        beq ?nx
        stx ep_ridx
        ; Set draw position
        lda eproj_x,x
        sta zdx
        lda eproj_xh,x
        sta zdxh
        lda eproj_y,x
        sta zdy
        ; Mark dirty
        lda #8
        sta md_w
        sta md_h
        jsr mark_dirty_sprite
        ; Blit sprite
        ldx ep_ridx
        lda eproj_spr,x
        jsr blit_sprite
        ldx ep_ridx
?nx     inx
        cpx #MAX_EPROJ
        beq ?done
        jmp ?lp
?done   rts
ep_ridx dta 0
.endp
