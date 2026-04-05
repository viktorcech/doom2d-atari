;==============================================
; DOOM2D - Hitscan fire system
; weapons_hitscan.asm
;
; Instant-hit for pistol/shotgun/chaingun.
; Scans tile columns, checks enemies and barrels.
;==============================================

; ============================================
; HITSCAN FIRE - instant hit for pistol/shotgun/chaingun
; Scans tile columns from player in firing direction,
; stops at first wall or enemy hit.
; ============================================
.proc hitscan_fire
        ; Pre-compute weapon damage
        ldx zpwcur
        lda weap_dmg,x
        sta hs_dmg

        ; Map row pointer for gun height
        lda zpy
        sec
        sbc #14
        sta hs_gy
        lsr
        lsr
        lsr
        lsr
        tay                     ; Y = tile row
        ; ztptr = map_data + row*64 (LUT)
        lda map_row_lo,y
        sta ztptr
        lda map_row_hi,y
        sta ztptr+1
        lda #BANK_EN+BANK_MAP
        sta VBXE_BANK_SEL

        ; Player tile column = (zpx_hi:zpx+5) / 16
        lda zpx
        clc
        adc #5
        sta zt
        lda zpx_hi
        adc #0
        asl
        asl
        asl
        asl
        sta hs_col
        lda zt
        lsr
        lsr
        lsr
        lsr
        ora hs_col
        sta hs_col

        ; Scan direction
        lda zpdir
        bne ?left

        ; --- Scan RIGHT ---
        lda hs_col
?rlp    clc
        adc #1
        cmp #MAP_W
        bcs ?miss
        sta hs_cur
        tay
        lda (ztptr),y
        tax
        lda tile_solid,x
        beq ?r_open
        cpx #15                 ; barrel invisible solid?
        bne ?miss               ; real wall
        jsr hs_chk_barrel
        jmp ?miss               ; barrel or wall, stop either way
?r_open jsr hs_chk_col
        bcs ?hit
        lda hs_cur
        jmp ?rlp

        ; --- Scan LEFT ---
?left   lda hs_col
?llp    sec
        sbc #1
        bcc ?miss               ; past column 0
        sta hs_cur
        tay
        lda (ztptr),y
        tax
        lda tile_solid,x
        beq ?l_open
        cpx #15
        bne ?miss               ; real wall
        jsr hs_chk_barrel
        jmp ?miss
?l_open jsr hs_chk_col
        bcs ?hit
        lda hs_cur
        jmp ?llp

?hit    ; X = enemy index (from hs_chk_col)
        jsr hs_damage_enemy
        ; Shotgun pierce: check for second enemy in same column
        lda zpwcur
        cmp #WP_SHOTGUN
        bne ?miss
        ; Continue from next enemy index
        inx
        jsr hs_chk_col_from
        bcc ?miss
        jsr hs_damage_enemy
?miss   rts

hs_gy   dta 0
hs_col  dta 0
hs_cur  dta 0
hs_dmg  dta 0
.endp

; ============================================
; HS_CHK_COL - check if any enemy is in tile column hs_cur
; Returns: C=1 hit (X=enemy index), C=0 no hit
; ============================================
.proc hs_chk_col
        ldx #0
        jmp hs_chk_col_from
.endp

; ============================================
; HS_DAMAGE_ENEMY - apply hitscan damage to enemy X
; ============================================
.proc hs_damage_enemy
        lda en_hp,x
        sec
        sbc hitscan_fire.hs_dmg
        bcs ?hok
        lda #0
?hok    sta en_hp,x
        lda #8
        sta en_pain_tmr,x
        lda en_hp,x
        bne ?done
        ; Killed!
        jsr start_enemy_death
        jsr play_enemy_death
?done   rts
.endp

; ============================================
; HS_CHK_COL_FROM - like hs_chk_col but starts from X
; Returns: C=1 hit (X=enemy), C=0 no hit
; ============================================
.proc hs_chk_col_from
?lp     cpx #MAX_ENEMIES
        bcs ?miss
        lda en_act,x
        cmp #1
        bne ?nx
        ; Enemy tile column
        lda en_x,x
        clc
        adc #8
        sta zt
        lda enxhi,x
        adc #0
        asl
        asl
        asl
        asl
        sta zt2
        lda zt
        lsr
        lsr
        lsr
        lsr
        ora zt2
        cmp hitscan_fire.hs_cur
        bne ?nx
        ; Same column! Check Y
        lda en_y,x
        sec
        sbc zpy
        bpl ?yp
        eor #$FF
        clc
        adc #1
?yp     cmp #18
        bcs ?nx
        sec
        rts
?nx     inx
        jmp ?lp
?miss   clc
        rts
.endp

; ============================================
; HS_CHK_BARREL - damage barrel at tile column hs_cur
; ============================================
.proc hs_chk_barrel
        ldx #0
?lp     lda dc_act,x
        cmp #1
        bne ?nx
        lda dc_type,x
        cmp #DC_BARREL
        bne ?nx
        ; Barrel tile column = dc_xhi:dc_x / 16
        lda dc_xhi,x
        asl
        asl
        asl
        asl
        sta zt
        lda dc_x,x
        lsr
        lsr
        lsr
        lsr
        ora zt
        cmp hitscan_fire.hs_cur
        bne ?nx
        ; Same column! Damage barrel
        lda dc_hp,x
        sec
        sbc hitscan_fire.hs_dmg
        bcs ?hok
        lda #0
?hok    sta dc_hp,x
        bne ?done
        ; Barrel killed → start explosion
        lda #2
        sta dc_act,x
        lda #31
        sta dc_timer,x
?done   rts
?nx     inx
        cpx #MAX_DECOR
        bne ?lp
        rts
.endp
