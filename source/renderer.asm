;==============================================
; DOOM2D - Rendering (tiles, sprites)
; renderer.asm
;==============================================

; ============================================
; RENDER TILES
; ============================================
.proc render_tiles
        lda #0
        sta r_row
?rrow   lda #0
        sta r_col
?rcol
        ; [inlined calc_map_ptr - bank set once per row]
        lda #BANK_EN+BANK_MAP
        sta VBXE_BANK_SEL
        ldy r_row
        lda map_row_lo,y
        clc
        adc r_col
        sta ztptr
        lda map_row_hi,y
        adc #0
        sta ztptr+1

        ldy #0
        lda (ztptr),y
        beq ?skip              ; tile 0 = empty, sky from clear_screen
        cmp #15
        beq ?skip              ; tile 15 = invisible solid (barrel), sky already drawn
        sta r_tile
        jsr blit_tile
?skip   inc r_col
        lda r_col
        cmp #TILES_X
        bcc ?rcol
        inc r_row
        lda r_row
        cmp #TILES_Y
        bcc ?rrow
        rts
.endp

r_row   dta 0
r_col   dta 0
r_tile  dta 0

; ============================================
; RENDER PLAYER
; ============================================
.proc render_player
        lda zpx
        sta zdx
        lda zpx_hi
        sta zdxh
        bpl ?xok
        jmp ?done
?xok
        lda zpy
        sec
        sbc #32
        bcs ?y_ok
        lda #0
?y_ok   sta zdy
        ; Dead? Show death animation (3 frames + blink)
        lda zphp
        bne ?not_dead
        lda pl_dead_timer
        cmp #80
        bcs ?d_blink           ; 80+: blink
        cmp #40
        bcs ?d_fr3             ; 40-79: death3
        cmp #15
        bcs ?d_fr2             ; 15-39: death2
        lda #SPR_PL_DEATH      ; 0-14: death1
        jmp ?draw_death
?d_fr2  lda #SPR_PL_DEATH2
        jmp ?draw_death
?d_fr3  lda #SPR_PL_DEATH3
        jmp ?draw_death
?d_blink lsr
        bcc ?d_show
        jmp ?done              ; blink: odd = hidden
?d_show
        lda #SPR_PL_DEATH3
?draw_death
        ; Death sprites: no mirror, direct blit
        pha
        lda #16
        sta md_w
        lda #32
        sta md_h
        jsr mark_dirty_sprite
        pla
        jsr blit_sprite
        jmp ?done
?not_dead
        ; Check pain (hit reaction)
        lda pl_pain_timer
        beq ?no_pain
        ; Pain sprite from chunk 7 (VRAM $05xxxx)
        lda zpdir
        bne ?pain_l
        lda #SPR_PL_PAIN_L    ; dir=0 (right) -> _L variant
        jmp ?draw_pain
?pain_l lda #SPR_PL_PAIN      ; dir=1 (left) -> base variant
?draw_pain
        pha
        lda #16
        sta md_w
        lda #32
        sta md_h
        jsr mark_dirty_sprite
        pla
        jsr blit_sprite
        jmp ?done
?no_pain
        ; Check if shooting (show shoot sprite while cooldown active)
        ; Skip shoot sprite for melee weapons
        lda zpwcool
        beq ?no_shoot
        ldx zpwcur
        lda weap_range,x
        bne ?no_shoot           ; melee = no shoot sprite
        lda #SPR_PL_SHOOT
        jmp ?draw
?no_shoot
        lda zpst
        cmp #1
        beq ?walk
        cmp #2
        beq ?jump
        lda #SPR_PL_IDLE
        jmp ?draw
?walk   lda zpan
        lsr
        lsr
        and #$03
        cmp #3
        bne ?wok
        lda #1              ; cycle: 0,1,2,1 (walk1,walk2,walk3,walk2)
?wok    clc
        adc #SPR_PL_W1
        jmp ?draw
?jump   lda #SPR_PL_W2
?draw   ; Mark dirty tiles before drawing
        pha                     ; save sprite index
        lda #16
        sta md_w
        lda #32
        sta md_h
        jsr mark_dirty_sprite
        pla                     ; restore sprite index
        ; Base sprites face LEFT, _L sprites face RIGHT
        ; dir=0 (right) -> +MIRROR_OFFSET, dir=1 (left) -> base
        ldy zpdir
        bne ?noflip
        clc
        adc #MIRROR_OFFSET
?noflip jsr blit_sprite
?done   rts
.endp

; ============================================
; RENDER PROJECTILES
; ============================================
.proc render_projs
        ldx #0
?lp     lda proj_a,x
        beq ?nx
        ; Only render rocket and plasma projectiles (hitscan = invisible)
        lda proj_spr,x
        cmp #SPR_ROCKET_PROJ
        beq ?draw
        cmp #SPR_PLASMA_PROJ1
        beq ?draw_plasma
        cmp #SPR_BFG_PROJ1
        beq ?draw_bfg
        jmp ?nx
?draw_plasma
        ; Animate plasma: alternate proj1/proj2 every 4 frames
        lda zfr
        and #$04
        beq ?pp1
        lda #SPR_PLASMA_PROJ2
        jmp ?draw_spr
?pp1    lda #SPR_PLASMA_PROJ1
        jmp ?draw_spr
?draw_bfg
        lda zfr
        and #$04
        beq ?bp1
        lda #SPR_BFG_PROJ2
        jmp ?draw_bfg2
?bp1    lda #SPR_BFG_PROJ1
?draw_bfg2
        stx rj_idx
        pha
        lda proj_x,x
        sta zdx
        lda proj_xh,x
        sta zdxh
        lda proj_y,x
        sta zdy
        lda #16
        sta md_w
        sta md_h
        jsr mark_dirty_sprite
        pla
        jsr blit_sprite
        ldx rj_idx
        jmp ?nx
?draw   lda #SPR_ROCKET_PROJ
?draw_spr
        stx rj_idx
        pha
        lda proj_x,x
        sta zdx
        lda proj_xh,x
        sta zdxh
        lda proj_y,x
        sta zdy
        lda #8
        sta md_w
        sta md_h
        jsr mark_dirty_sprite
        pla
        jsr blit_sprite
        ldx rj_idx
?nx     inx
        cpx #MAX_PROJ
        beq ?done
        jmp ?lp
?done   rts
rj_idx  dta 0
.endp
