;==============================================
; DOOM2D - Barrel logic
; barrel.asm
;
; Barrel explosion, chain reactions, damage,
; projectile collision, map solid tile management.
; Uses decoration arrays from decorations.asm.
;==============================================

; ============================================
; UPDATE DECORATIONS (barrel explosion logic)
; ============================================
.proc update_decorations
        ldx #0
?lp     lda dc_act,x
        cmp #2
        bne ?not_exp
        jmp ?exploding
?not_exp
        jmp ?nx
?exploding
        lda dc_timer,x
        cmp #30
        bne ?chk_dmg
        ; Timer=30: explosion visual + sound + chain (no damage yet)
        stx ud_idx
        jsr barrel_clear_solid
        lda #SFX_BAREXP
        jsr play_sfx_unlock
        ; Chain: set nearby live barrels to exploding
        ldx ud_idx
        ldy #0
?clp    cpy ud_idx
        beq ?cnx
        lda dc_act,y
        cmp #1
        bne ?cnx
        lda dc_type,y
        cmp #DC_BARREL
        bne ?cnx
        ; 16-bit X distance
        lda dc_x,x
        sec
        sbc dc_x,y
        sta ud_tmp
        lda dc_xhi,x
        sbc dc_xhi,y
        beq ?cxchk
        cmp #$FF
        bne ?cnx
        lda ud_tmp
        beq ?cnx               ; lo=0 → distance=256, too far
        lda #0
        sec
        sbc ud_tmp
        sta ud_tmp
?cxchk  lda ud_tmp
        cmp #BARREL_RADIUS
        bcs ?cnx
        lda dc_y,x
        sec
        sbc dc_y,y
        bpl ?cya
        eor #$FF
        clc
        adc #1
?cya    cmp #BARREL_RADIUS
        bcs ?cnx
        lda #2
        sta dc_act,y
        lda #32
        sta dc_timer,y
?cnx    iny
        cpy #MAX_DECOR
        bne ?clp
        ldx ud_idx
        jmp ?no_fire
?chk_dmg
        cmp #20
        bne ?no_fire
        ; Timer=20: apply radius damage (~0.2s after explosion)
        stx ud_idx
        txa
        tay
        jsr barrel_explode
        ldx ud_idx
?no_fire
        dec dc_timer,x
        bne ?nx2
        ; Timer=0: barrel disappears
        lda dc_x,x
        sta zdx
        lda dc_xhi,x
        sta zdxh
        lda dc_y,x
        sec
        sbc #16
        sta zdy
        lda #16
        sta md_w
        sta md_h
        stx ud_idx
        jsr mark_dirty_sprite
        ldx ud_idx
        lda #0
        sta dc_act,x
?nx2    jmp ?nx
?nx     inx
        cpx #MAX_DECOR
        beq ?done
        jmp ?lp
?done   rts
ud_idx  dta 0
ud_tmp  dta 0
.endp

; ============================================
; BARREL EXPLODE - apply radius damage
; Input: Y = barrel decoration index
; ============================================
.proc barrel_explode
        sty bx_idx
        ldx bx_idx
        ; --- Radius damage to enemies ---
        ldy #0
?elp    sty bx_eidx
        lda en_act,y
        cmp #1
        beq ?eact
        jmp ?enx
?eact   ldx bx_idx
        lda dc_xhi,x
        cmp enxhi,y
        beq ?exhi_ok
        jmp ?enx
?exhi_ok
        lda dc_x,x
        sec
        sbc en_x,y
        bpl ?exa
        eor #$FF
        clc
        adc #1
?exa    cmp #BARREL_RADIUS
        bcc ?exr_ok
        jmp ?enx
?exr_ok ldx bx_idx
        lda dc_y,x
        sec
        sbc en_y,y
        bpl ?eya
        eor #$FF
        clc
        adc #1
?eya    cmp #BARREL_RADIUS
        bcc ?eyr_ok
        jmp ?enx
?eyr_ok ; Enemy in range! Apply damage
        ldy bx_eidx
        lda en_hp,y
        sta bx_oldhp
        sec
        sbc #BARREL_DMG
        bcs ?ehok
        lda #0
?ehok   sta en_hp,y
        beq ?ekill
        jmp ?enx
?ekill
        ; Enemy killed by barrel!
        lda #2
        sta en_act,y
        lda #20
        sta en_dtimer,y
        lda #0
        sta en_gib,y
        sta envelx,y
        ; Gib check: only zombie, imp, shotgun
        lda en_type,y
        cmp #EN_ZOMBIE
        beq ?gchk
        cmp #EN_IMP
        beq ?gchk
        cmp #EN_SHOTGUN
        beq ?gchk
        jmp ?enx_snd
?gchk   ; overkill = BARREL_DMG - old_hp
        lda #BARREL_DMG
        sec
        sbc bx_oldhp
        ; threshold = overkill * 3 + 10
        sta bx_oldhp
        asl
        clc
        adc bx_oldhp           ; *3
        adc #10                ; +10 base
        sta bx_oldhp
        lda zfr
        eor RTCLOK3
        and #$3F
        cmp bx_oldhp
        bcs ?enx_snd
        ; Gib! Set flag + knockback away from barrel
        lda #1
        sta en_gib,y
        lda #$FE
        sta envely,y
        ldx bx_idx
        lda en_x,y
        cmp dc_x,x
        bcs ?bkr
        lda #$FE
        bne ?bkset
?bkr    lda #2
?bkset  sta envelx,y
        ; Gib sound
        sty bx_eidx
        lda #SFX_SLOP
        jsr play_sfx_unlock
        lda #8
        sta snd_lock
        ldy bx_eidx
        jmp ?enx
?enx_snd
        sty bx_eidx
        ldx bx_eidx
        jsr play_enemy_death
        ldy bx_eidx
?enx    ldy bx_eidx
        iny
        cpy #MAX_ENEMIES
        beq ?edone
        jmp ?elp
?edone
        ; --- Radius damage to player ---
        ; --- Player splash damage from barrel explosion ---
        ; Skip if barrel and player on different X hi pages
        ldx bx_idx
        lda dc_xhi,x
        cmp zpx_hi
        bne ?ret
        ; X distance: |barrel_x - player_x|
        lda dc_x,x
        sec
        sbc zpx
        bpl ?pxa
        eor #$FF                ; negate (absolute value)
        clc
        adc #1
?pxa    cmp #BARREL_RADIUS      ; too far horizontally?
        bcs ?ret
        sta bx_dist
        ; Y distance: |barrel_y - player_y|
        lda dc_y,x
        sec
        sbc zpy
        bpl ?pya
        eor #$FF
        clc
        adc #1
?pya    cmp #BARREL_RADIUS      ; too far vertically?
        bcs ?ret
        ; Use max(dx, dy) as distance
        cmp bx_dist
        bcs ?dok
        lda bx_dist
?dok    sta bx_dist
        ; Damage = BARREL_PLR_MAX - dist*3 (farther = less damage)
        asl                     ; dist * 2
        clc
        adc bx_dist             ; dist * 3
        sta bx_dist
        lda #BARREL_PLR_MAX     ; max damage at point blank
        sec
        sbc bx_dist             ; reduce by distance
        bcc ?pmin               ; underflow = minimum damage
        cmp #1
        bcs ?papply
?pmin   lda #1                  ; minimum 1 damage
?papply sta bx_dist
        lda bx_dist
        jsr player_take_damage
        ; --- Horizontal knockback: push player away from barrel ---
        ; Direction based on player position relative to barrel
        ldx bx_idx
        lda zpx
        cmp dc_x,x
        bcs ?kb_r
        ; Player is left of barrel → push left (negative velocity)
        lda #0
        sec
        sbc #BARREL_KB_X
        sta zpvx
        jmp ?ret
?kb_r   ; Player is right of barrel → push right (positive velocity)
        lda #BARREL_KB_X
        sta zpvx
?ret    rts
bx_idx  dta 0
bx_eidx dta 0
bx_dist dta 0
bx_oldhp dta 0
.endp

; ============================================
; CHECK PROJECTILE HIT ON BARRELS
; Input: X = projectile index
; Output: C=1 if hit a barrel
; ============================================
.proc check_proj_barrels
        stx cb_proj
        ldy #0
?lp     lda dc_act,y
        cmp #1
        beq ?act
        jmp ?nx
?act
        lda dc_type,y
        cmp #DC_BARREL
        beq ?isbar
        jmp ?nx
?isbar
        ; Bounding box X overlap: proj(8px) vs barrel(16px)
        ; delta = proj_x - dc_x (16-bit)
        ; hit if: hi=0 and lo<16 (proj right of barrel left)
        ;     or: hi=$FF and lo>=248 (proj left edge within 8px of barrel left)
        ldx cb_proj
        lda proj_x,x
        sec
        sbc dc_x,y
        sta cb_tmp
        lda proj_xh,x
        sbc dc_xhi,y
        bne ?xneg
        ; hi=0: proj_x >= dc_x, check if proj_x < dc_x+16
        lda cb_tmp
        cmp #16
        bcs ?nx
        jmp ?xhit
?xneg   cmp #$FF
        bne ?nx                ; too far
        ; hi=$FF: proj_x < dc_x, check if proj_x+8 > dc_x
        lda cb_tmp             ; 256 - |delta|
        cmp #249               ; 256 - 7: proj right edge touches barrel left
        bcc ?nx
?xhit
        lda proj_y,x
        sec
        sbc dc_y,y
        bpl ?ya
        eor #$FF
        clc
        adc #1
?ya     cmp #16
        bcs ?nx
        ; Hit! Damage barrel
        ldx cb_proj
        lda proj_dmg,x
        sta zt2
        lda dc_hp,y
        sec
        sbc zt2
        bcs ?hok
        lda #0
?hok    sta dc_hp,y
        bne ?hit
        lda #2
        sta dc_act,y
        lda #31
        sta dc_timer,y
?hit    ldx cb_proj
        jsr rocket_splash_player
        ldx cb_proj
        lda #0
        sta proj_a,x
        sec
        rts
?nx     iny
        cpy #MAX_DECOR
        beq ?miss
        jmp ?lp
?miss
        clc
        rts
cb_proj dta 0
cb_tmp  dta 0
.endp

; ============================================
; BARREL MAP SOLID: write/clear solid tile
; X = decoration index
; ============================================
; Shared: barrel tile col/row → r_col/r_row + calc_map_ptr
.proc barrel_calc_pos
        lda dc_x,x
        lsr
        lsr
        lsr
        lsr
        sta r_col
        lda dc_xhi,x
        asl
        asl
        asl
        asl
        ora r_col
        sta r_col
        lda decor_spawn_y,x
        lsr
        lsr
        lsr
        lsr
        sta r_row
        jmp calc_map_ptr
.endp

.proc barrel_set_solid
        stx bs_idx
        jsr barrel_calc_pos
        ldy #0
        lda (ztptr),y
        cmp #15
        bne ?orig_ok
        lda #0
?orig_ok
        ldx bs_idx
        sta dc_orig_tile,x
        lda #15
        ldy #0
        sta (ztptr),y
        ldx bs_idx
        rts
bs_idx  dta 0
.endp

.proc barrel_clear_solid
        stx bc_idx
        jsr barrel_calc_pos
        ldy #0
        ldx bc_idx
        lda dc_orig_tile,x
        sta (ztptr),y
        ldx bc_idx
        rts
bc_idx  dta 0
.endp
